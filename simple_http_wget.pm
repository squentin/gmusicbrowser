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

sub get_with_cb
{	my $self=bless {};
	my %params=@_;
	$self->{params}=\%params;
	my ($callback,$url,$post)=@params{qw/cb url post/};
	delete $params{cache} unless $UseCache;
	if (my $cached= $params{cache} && GMB::Cache::get($url))
		{ warn "cached result\n" if $::debug; $callback->( ${$cached->{data}}, $cached->{type} ); return undef; }

	warn "simple_http_wget : fetching $url\n" if $::debug;

	my $proxy= $::Options{Simplehttp_Proxy} ?	$::Options{Simplehttp_ProxyHost}.':'.($::Options{Simplehttp_ProxyPort}||3128)
							: $orig_proxy;
	$ENV{http_proxy}=$proxy;

	my @cmd_and_args=qw/wget --timeout=40 --header=Accept: --user-agent= -S -O -/;
	push @cmd_and_args, '--post-data='.$post if $post;	#FIXME not sure if I should escape something
	push @cmd_and_args, '--',$url;
	pipe my($content_fh),my$wfh;
	pipe my($error_fh),my$ewfh;
	my $pid=fork;
	if ($pid==0) #child
	{	close $content_fh; close $error_fh;
		open \*STDOUT,'>&='.fileno $wfh;
		open \*STDERR,'>&='.fileno $ewfh;
		exec @cmd_and_args;
	}
	elsif (!defined $pid) { warn "fork failed\n" }
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
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	return $self->{ewatch}=0;
}
sub receiving_cb
{	my $self=$_[2];
	return 1 if read $self->{content_fh},$self->{content},1024,length($self->{content});
	close $self->{content_fh};
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	$self->{pid}=$self->{sock}=$self->{watch}=undef;
	my $url=	$self->{params}{url};
	my $callback=	$self->{params}{cb};
	my $type; my $result='';
	$url=$1		while $self->{ebuffer}=~m#^Location: (\w+://[^ ]+)#mg;
	$type=$1	while $self->{ebuffer}=~m#^  Content-Type: (.*)$#mg;	##
	$result=$1	while $self->{ebuffer}=~m#^  (HTTP/1\.\d+.*)$#mg;	##
	if ($result=~m#^HTTP/1\.\d+ 200 OK#)
	{	my $response=\$self->{content};
		if ($self->{params}{cache} && defined $$response)
		{	GMB::Cache::add($url,{data=>$response,type=>$type,size=>length($$response)});
		}
		$callback->($$response,$type,$self->{params}{url});
	}
	else
	{	warn "Error fetching $url : $result\n";
		$callback->();
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
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	$self->{pid}=$self->{content_fh}=$self->{error_fh}=$self->{watch}=$self->{ewatch}=undef;
}

1;
