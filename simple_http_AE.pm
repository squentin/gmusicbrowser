# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Simple_http;
use strict;
use warnings;
use AnyEvent::HTTP;
my $UseCache= *GMB::Cache::add{CODE};

sub get_with_cb
{	my $self=bless {};
	my %params=@_;
	$self->{params}=\%params;
	my ($callback,$url,$post)=@params{qw/cb url post/};
	delete $params{cache} unless $UseCache;
	if (my $cached= $params{cache} && GMB::Cache::get($url))
		{ warn "cached result\n" if $::debug; $callback->( ${$cached->{data}}, $cached->{type} ); return undef; }

	warn "simple_http_AE : fetching $url\n" if $::debug;

	my $proxy= $::Options{Simplehttp_Proxy} ?	$::Options{Simplehttp_ProxyHost}.':'.($::Options{Simplehttp_ProxyPort}||3128)
							: $ENV{http_proxy};
	AnyEvent::HTTP::set_proxy($proxy);

	my %headers;
	$headers{'Content-Type'}= 'application/x-www-form-urlencoded; charset=utf-8' if $post;
	$headers{$_}=$params{$_} for grep exists $params{$_}, qw/User-Agent Content-Type Referer Accept/;
	my $method= $post ? 'POST' : 'GET';
	my @args;
	push @args, body => $post if $post;
	if ($params{progress}) # enable progress info via progress()
	{	push @args,	on_header=> sub { $self->{content_length}=$_[0]{"content-length"}; $self->{content}=''; 1; },
				on_body  => sub { $self->{content}.= $_[0]; 1; };
	}
	$self->{request}= http_request( $method, $url, @args, headers=>\%headers, sub { $self->finished(@_) } );
	return $self;
}

sub finished
{	my ($self,$response,$headers)=@_;
	$response= $self->{content} if exists $self->{content};
	my $url=	$self->{params}{url};
	my $callback=	$self->{params}{cb};
	delete $_[0]{request};
	#warn "$_=>$headers->{$_}\n" for sort keys %$headers;
	if ($headers->{Reason} eq 'OK') # and $headers->{Status} == 200 ?
	{	my $type= $headers->{'content-type'};
		if ($self->{params}{cache} && defined $response)
		{	GMB::Cache::add($url,{data=>\$response,type=>$type,size=>length($response)});
		}
		$callback->($response,$type,$self->{params}{url});
	}
	else
	{	warn "Error fetching $url : $headers->{Status} $headers->{Reason}\n";
		$callback->();
	}
}

sub progress
{	my $self=shift;
	my $length= $self->{content_length};	warn $length;
	return $length,0 unless exists $self->{content};
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
{	delete $_[0]{request};
}

1;
