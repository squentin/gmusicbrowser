# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
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

use constant { EOL => "\015\012" };
my (@Cachedurl,%Cache,$CacheSize,%ipcache); #FIXME purge %ipcache from time to time

sub get_with_cb
{	my $self=bless {};
	my $error;
	if (ref $_[0]) {$self=shift; $error='Too many redirection' if 5 < $self->{redirect}++; }
	my %params=@_;
	$self->{params}=\%params;
	my ($callback,$url,$post)=@params{qw/cb url post/};
	if ($params{cache} && defined $Cache{$url})
		{ warn "cached result\n" if $::debug; $callback->( @{$Cache{$url}} ); return undef; }

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
		$callback->();
		return undef;
	}
	$self->{watch}=Glib::IO->add_watch(fileno($socket),['out','hup'],\&connecting_cb,$self);

	return $self;
}

sub connecting_cb
{	my $failed= ($_[1] >= 'hup'); #connection failed
	my $self=$_[2];#warn "@_";
	my $socket=$self->{sock};
	my $port=$self->{port};
	my $host=$self->{host};

	if ($failed)
	{	warn "Cannot connect to server $host:$port\n";
		close $socket;
		$self->{params}{cb}();
		return 0;
	}

#binmode $socket,':encoding(iso-8859-1)';
	my $post=$self->{params}{post};
	my $method=defined $post ? 'POST' : 'GET';
	print $socket "$method $self->{file} HTTP/1.0".EOL;
	print $socket "Host: $host:$port".EOL;
	#print $socket "User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.6) Gecko/20070725 Firefox/2.0.0.6".EOL;
	#print $socket "Accept: */*".EOL;
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

sub receiving_cb
{	my $self=$_[2];
	return 1 if read $self->{sock},$self->{buffer},1024,length($self->{buffer});
	close $self->{sock};
	$self->{sock}=$self->{watch}=undef;
	#warn "watch done\n";
	my $url=$self->{params}{url};
	my $callback=$self->{params}{cb};
	my $EOL=EOL;
	my ($headers,$response)=split /$EOL$EOL/o,$self->{buffer},2;
	$headers='empty answer' unless defined $headers;
	(my$result,$headers)=split /$EOL/o,$headers,2;
	if ($::debug)
	{	warn "0|$_\n" for $result,split /$EOL/o,$headers;
	}
	$headers.=EOL;
	my %headers=($headers=~m/([^:]*): (.*?)$EOL/og);
	if ($result=~m#^HTTP/1\.\d+ 200 OK#)
	{	#warn "ok $url\n$callback\n";
		if ($self->{params}{cache} && defined $response && length($response)<$::Options{Simplehttp_CacheSize})
		{	$CacheSize+= length $response;
			$Cache{$url}=[$response,$headers{'Content-Type'}];
			push @Cachedurl,$url;
			while ($CacheSize>$::Options{Simplehttp_CacheSize})
			{	my $old=pop @Cachedurl;
				$CacheSize-= length $Cache{$old}[0];
				delete $Cache{$old};
			}
		}
		$callback->($response,$headers{'Content-Type'},$self->{params}{url});
	}
	elsif ($result=~m#^HTTP/1\.\d+ 30[12]# && $headers{Location}) #redirection
	{	my $url=$headers{Location};
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
		$callback->();
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
