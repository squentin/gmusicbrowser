# Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Simple_http;
use strict;
use warnings;
use Socket;# 1.3; ?
use Fcntl;
use IO::Handle;

use constant { EOL => "\015\012" };
my %ipcache; #FIXME purge %ipcache from time to time
my $UseCache= *GMB::Cache::add{CODE};

my $gzip_ok;
BEGIN
{	eval { require IO::Uncompress::Gunzip; $gzip_ok=1; };
}

sub get_with_cb
{	my $self=bless {};
	my $error;
	if (ref $_[0]) {$self=shift; $error='Too many redirections' if 5 < $self->{redirect}++; }
	my %params=@_;
	$self->{params}=\%params;
	delete $params{cache} unless $UseCache;
	my ($callback,$url,$post)=@params{qw/cb url post/};
	if (my $cached= $params{cache} && GMB::Cache::get($url))
	{	warn "cached result\n" if $::debug;
		Glib::Timeout->add(10,sub { $callback->( ${$cached->{data}}, type=>$cached->{type}, filename=>$cached->{filename}, ); 0});
		return $self;
	}
	warn "simple_http : fetching $url\n" if $::debug;

	my ($host,$port,$file);
	my $socket;
	{	last if $error;

		if ( $url=~s#^([a-z]+)://## && $1 ne 'http' )
		 { $error="Protocol $1 not supported"; last; }
		($host,$port,$file)= $url=~m#^([^/:]+)(?::(\d+))?(.*)$#;
		if (defined $host)
		{	$port=80 unless defined $port;
			$file='/' if $file eq '';
		}
		else	{ $error='Bad url : http://'.$url; last; }

		my $proxyhost=$::Options{Simplehttp_ProxyHost};
		if ($::Options{Simplehttp_Proxy} && defined $proxyhost && $proxyhost ne '')
		{	$file="http://$host:".$port.$file;
			$host=$proxyhost;
			$port=$::Options{Simplehttp_ProxyPort};
			$port=80 unless defined $port && $port=~m/^\d+$/;
		}
		my $addr;
		if ($host=~m#^\d+\.\d+\.\d+.\d+$#) {$addr=inet_aton($host);}
		else { $addr=$ipcache{$host}||=inet_aton($host)}#FIXME not asynchronous, use a fork ?
		unless ($addr)
		 { $error="Can't resolve host $host"; last; }
		socket($socket, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
		my $paddr=pack_sockaddr_in(0, INADDR_ANY);
		unless ( bind $socket,$paddr )
		 { $error=$!; last; }
		$self->{file}=$file;
		$self->{port}=$port;
		$self->{host}=$host;
		my $sin=sockaddr_in($port,$addr);
		fcntl $socket,F_SETFL,O_NONBLOCK; #unless $^O eq "MSWin32"
		connect $socket,$sin;
	}
	$self->{sock}=$socket;
	if (defined $error)
	{	$error="Cannot connect to server $host:$port : $error" if $host;
		warn "$error\n";
		Glib::Timeout->add(10,sub { $callback->(undef,error=>$error); 0 });
		return $self;
	}
	$self->{buffer}='';
	$self->{watch}=Glib::IO->add_watch(fileno($socket),['out','hup'],\&connecting_cb,$self);

	return $self;
}

sub connecting_cb
{	my $failed= ($_[1] >= 'hup'); #connection failed
	my $self=$_[2];
	my $socket=$self->{sock};
	my $port=$self->{port};
	my $host=$self->{host};
	my $params= $self->{params};

	if ($failed)
	{	warn "Cannot connect to server $host:$port\n";
		close $socket;
		$params->{cb}(undef,error=>"Connection failed");
		return 0;
	}

#binmode $socket,':encoding(iso-8859-1)';
	my $post=$params->{post};
	my $method=defined $post ? 'POST' : 'GET';
	my $useragent= $params->{user_agent} || 'Mozilla/5.0';
	my $accept= $params->{'accept'} || '';
	print $socket "$method $self->{file} HTTP/1.0".EOL;
	print $socket "Host: $host:$port".EOL;
	print $socket "User-Agent: $useragent".EOL;
	print $socket "Referer: $params->{referer}".EOL if $params->{referer};
	print $socket "Accept: $accept".EOL;
	print $socket "Accept-Encoding: gzip".EOL if $gzip_ok;
	#print $socket "Connection: Keep-Alive".EOL;
	if (defined $post)
	{ print $socket 'Content-Type: application/x-www-form-urlencoded; charset=utf-8'.EOL;
	  print $socket "Content-Length: ".length($post).EOL.EOL;
	  print $socket $post.EOL;
	}
	print $socket EOL;

	$socket->autoflush(1);
	$self->{buffer}='';
	$self->{watch}=Glib::IO->add_watch(fileno($socket),['in','hup'],\&receiving_cb,$self);

	return 0;
}

sub progress
{	my $self=shift;
	my ($length)= $self->{buffer}=~m/\015\012Content-Length:\s*(\d+)\015\012/i;
	my $pos= index $self->{buffer}, EOL.EOL;
	my $progress;
	my $size=0;
	if ($pos>=0)
	{	$size=length($self->{buffer})-2-$pos;
		if ($length)
		{	$progress= $size/$length;
			$progress=undef if $progress>1;
		}
	}
	# $progress is undef or between 0 and 1
	return $progress,$size;
}

sub receiving_cb
{	my $self=$_[2];
	return 1 if read $self->{sock},$self->{buffer},1024,length($self->{buffer});
	close $self->{sock};
	$self->{sock}=$self->{watch}=undef;
	#warn "watch done\n";
	my $url=$self->{params}{url};
	my $callback=$self->{params}{cb};
	my $EOL=EOL;
	my ($headers,$response)=split /$EOL$EOL/o,delete $self->{buffer},2;
	$headers='empty answer' unless defined $headers;
	(my$result,$headers)=split /$EOL/o,$headers,2;
	if ($::debug)
	{	warn "0|$_\n" for $result,split /$EOL/o,$headers;
	}
	$headers.=EOL;
	my %headers;
	$headers{lc $1}=$2 while $headers=~m/([^:]*): (.*?)$EOL/og;

	my $filename;
	if ($headers{'content-disposition'} && $headers{'content-disposition'}=~m#^\s*\w+\s*;\s*filename(\*)?=(.*)$#mgi)
	{	$filename=$2; my $rfc5987=$1;
		#decode filename, not perfectly, but good enough (http://greenbytes.de/tech/tc2231/ is a good reference)
		$filename=~s#\\(.)#"\x00".ord($1)."\x00"#ge;
		my $enc='iso-8859-1';
		if ($rfc5987 && $filename=~s#^([A-Za-z0-9_-]+)'\w*'##) {$enc=$1; $filename=::decode_url($filename)} #RFC5987
		else
		{	if ($filename=~s/^"(.*)"$/$1/) { $filename=~s#\x00(\d+)\x00#chr($1)#ge; $filename=~s#\\(.)#"\x00".ord($1)."\x00"#ge; }
			elsif ($filename=~m#[^A-Za-z0-9_.\x00-]#) {$filename=''}
		}
		$filename=~s#\x00(\d+)\x00#chr($1)#ge;
		$filename= eval {Encode::decode($enc,$filename)};
	}
	if (my $enc=$headers{'content-encoding'})
	{	if ($enc eq 'gzip' && $gzip_ok)
		{	my $gzipped= $response;
			IO::Uncompress::Gunzip::gunzip( \$gzipped, \$response )
				or do {warn "simple_http : gunzip failed: $IO::Uncompress::Gunzip::GunzipError\n"; $result='gunzip error';};
		}
		else
		{	warn "simple_http_wget : can't decode '$enc' encoding\n";
			$result='gzipped';
		}
	}
	if ($result=~m#^HTTP/1\.\d+ 200 OK#)
	{	#warn "ok $url\n$callback\n";
		my $type=$headers{'content-type'};
		if ($self->{params}{cache} && defined $response)
		{	GMB::Cache::add($url,{data=>\$response,type=>$type,size=>length($response),filename=>$filename});
		}
		$callback->($response, type=>$type, url=>$self->{params}{url}, filename=>$filename);
	}
	elsif ($result=~m#^HTTP/1\.\d+ 30[123]# && $headers{location}) #redirection
	{	my $url=$headers{location};
		unless ($url=~m#^http://#)
		{	my $base=$self->{params}{url};
			if ($url=~m#^/#){$base=~s#^(?:http://)?([^/]+).*$#$1#;}
			else		{$base=~s#[^/]*$##;}
			$url=$base.$url;
		}
		$self->{params}{url}=$url;
		$self->get_with_cb( %{$self->{params}} );
	}
	else
	{	warn "Error fetching $url : $result\n";
		$callback->(undef,error=>$result);
	}
	return 0;
}

sub abort
{	my $self=$_[0];
	Glib::Source->remove($self->{watch}) if defined $self->{watch};
	close $self->{sock} if defined $self->{sock};
	$self->{sock}=$self->{watch}=undef;
}

1;
