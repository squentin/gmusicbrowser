# Copyright (C) 2008-2011 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Simple_http;
use strict;
use warnings;
use POSIX ':sys_wait_h';	#for WNOHANG in waitpid
use IO::Handle;

my $UseCache= *GMB::Cache::add{CODE};
my $orig_proxy=$ENV{http_proxy};
my $gzip_ok;
BEGIN
{	eval { require IO::Uncompress::Gunzip; $gzip_ok=1; };
}

sub get_with_cb
{	my $self=bless {};
	my %params=@_;
	$self->{params}=\%params;
	my ($callback,$url,$post)=@params{qw/cb url post/};
	delete $params{cache} unless $UseCache;
	if (my $cached= $params{cache} && GMB::Cache::get($url))
	{	warn "cached result\n" if $::debug;
		Glib::Timeout->add(10,sub { $callback->( ${$cached->{data}}, type=>$cached->{type}, filename=>$cached->{filename}, ); 0});
		return $self;
	}

	warn "simple_http_wget : fetching $url\n" if $::debug;

	my $proxy= $::Options{Simplehttp_Proxy} ?	$::Options{Simplehttp_ProxyHost}.':'.($::Options{Simplehttp_ProxyPort}||3128)
							: $orig_proxy;
	$ENV{http_proxy}=$proxy;

	my $useragent= $params{user_agent} || 'Mozilla/5.0';
	my $accept= $params{'accept'} || '';
	my $gzip= $gzip_ok ? '--header=Accept-Encoding: gzip' : '';
	my @cmd_and_args= (qw/wget --timeout=40 -S -O -/, $gzip, "--header=Accept: $accept", "--user-agent=$useragent");
	push @cmd_and_args, "--referer=$params{referer}" if $params{referer};
	push @cmd_and_args, '--post-data='.$post if $post;	#FIXME not sure if I should escape something
	push @cmd_and_args, '--',$url;
	pipe my($content_fh),my$wfh;
	pipe my($error_fh),my$ewfh;
	my $pid=fork;
	if (!defined $pid) { warn "simple_http_wget : fork failed : $!\n"; Glib::Timeout->add(10,sub {$callback->(); 0}); return $self }
	elsif ($pid==0) #child
	{	close $content_fh; close $error_fh;
		open my($olderr), ">&", \*STDERR;
		open \*STDOUT,'>&='.fileno $wfh;
		open \*STDERR,'>&='.fileno $ewfh;
		exec @cmd_and_args  or print $olderr "launch failed (@cmd_and_args)  : $!\n";
		POSIX::_exit(1);
	}
	close $wfh; close $ewfh;
	$content_fh->blocking(0); #set non-blocking IO
	$error_fh->blocking(0);

	$self->{content_fh}=$content_fh;
	$self->{error_fh}=$error_fh;
	$self->{pid}=$pid;
	$self->{content}=$self->{ebuffer}='';
	$self->{watch}= Glib::IO->add_watch(fileno($content_fh),[qw/hup err in/],\&receiving_cb,$self);
	$self->{ewatch}= Glib::IO->add_watch(fileno($error_fh), [qw/hup err in/],\&receiving_e_cb,$self);

	return $self;
}

sub receiving_e_cb
{	my $self=$_[2];
	return 1 if read $self->{error_fh},$self->{ebuffer},1024,length($self->{ebuffer});
	close $self->{error_fh};
	return $self->{ewatch}=0;
}
sub receiving_cb
{	my $self=$_[2];
	return 1 if read $self->{content_fh},$self->{content},1024,length($self->{content});
	close $self->{content_fh};
	$self->{pid}=$self->{sock}=$self->{watch}=undef;
	my $url=	$self->{params}{url};
	my $callback=	$self->{params}{cb};
	my $type; my $result='';
	$url=$1		while $self->{ebuffer}=~m#^Location: (\w+://[^ ]+)#mg;
	$type=$1	while $self->{ebuffer}=~m#^  Content-Type: (.*)$#mg;	##
	$result=$1	while $self->{ebuffer}=~m#^  (HTTP/1\.\d+.*)$#mg;	##
	#warn $self->{ebuffer};

	my $filename;
	while ($self->{ebuffer}=~m#^  Content-Disposition:\s*\w+\s*;\s*filename(\*)?=(.*)$#mgi)
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
	my ($enc)= $self->{ebuffer}=~m#^  Content-Encoding:\s*(.*)#mg;
	if ($enc)
	{	if ($enc eq 'gzip' && $gzip_ok)
		{	my $gzipped= $self->{content};
			IO::Uncompress::Gunzip::gunzip( \$gzipped, \$self->{content} )
				or do {warn "simple_http_wget : gunzip failed: $IO::Uncompress::Gunzip::GunzipError\n"; $result='gunzip error';};
		}
		else
		{	warn "simple_http_wget : can't decode '$enc' encoding\n";
			$result='encoded';
		}
	}

	if ($result=~m#^HTTP/1\.\d+ 200 OK#)
	{	my $response=\$self->{content};
		if ($self->{params}{cache} && defined $$response)
		{	GMB::Cache::add($url,{data=>$response,type=>$type,size=>length($$response),filename=>$filename});
		}
		$callback->($$response,type=>$type,url=>$self->{params}{url},filename=>$filename);
	}
	else
	{	warn "Error fetching $url : $result\n";
		$callback->(undef,error=>$result);
	}
	return $self->{watch}=0;
}

sub progress
{	my $self=shift;
	my $length;
	$length=$1 while $self->{ebuffer}=~m/Content-Length:\s*(\d+)/ig;
	my $size= length $self->{content};
	my $progress;
	if ($length && $size)
	{	$progress= $size/$length;
		$progress=undef if $progress>1;
	}
	# $progress is undef or between 0 and 1
	return $progress,$size;
}

sub abort
{	my $self=$_[0];
	Glib::Source->remove($self->{watch}) if $self->{watch};
	Glib::Source->remove($self->{ewatch}) if $self->{ewatch};
	kill INT=>$self->{pid} if $self->{pid};
	close $self->{content_fh} if defined $self->{content_fh};
	close $self->{error_fh} if defined $self->{error_fh};
	$self->{pid}=$self->{content_fh}=$self->{error_fh}=$self->{watch}=$self->{ewatch}=undef;
}

1;
