# Copyright (C) 2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Tag::APEfile;
use strict;
use warnings;
our @ISA=('Tag::MP3');
my %compression;

INIT
{%compression=
 (	1000 => 'Fast',
	2000 => 'Normal',
	3000 => 'High',
	4000 => 'Extra High',
	5000 => 'Insane',
 );
}

sub new
{   my ($class,$file,$findlength)=@_;
    my $self=bless {}, $class;
    local $_;
    # check that the file exists and is readable
    unless ( -e $file && -r $file )
    {	warn "File '$file' does not exist or cannot be read.\n";
	return undef;
    }
    $self->{filename} = $file;
    $self->_open or return undef;

    $self->_FindTags;
    $self->_ReadHeader;
    return undef unless $self->{info};
    $self->_close;
    return $self;
}

sub _ReadHeader
{	my $self=$_[0];
	my %info;
	my $fh=$self->{fileHandle};
	my $offset=$self->{startaudio};
	seek $fh,$offset,0;
	my $buf;
	return unless read($fh,$buf,12)==12;
	return unless $buf=~m/^MAC /;
	my ($v,$desc_size)=unpack 'x4Vv',$buf;
	$info{version}=$v/1000;
	seek $fh,$desc_size-12,1;
	return unless read($fh,$buf,24)==24;
	my ($compression,$blocksperframe,$finalsblocks,$nbframes,$bitpersample,$channels,$freq)=unpack 'vx2VVVvvV',$buf;
	$info{compression}=$compression{$compression} || $compression;
	$info{channels}=$channels;
	$info{frames}=$nbframes;
	$info{rate}=$freq;
	if ($nbframes==0) {$info{seconds}=$info{bitrate}=0}
	else
	{ $info{seconds}=( ($nbframes-1)*$blocksperframe+$finalsblocks )/$freq;
	  #$info{seconds}=( ($nbframes-1)*$blocksperframe+$finalsblocks )*1000/$freq;
	  $info{bitrate}=( $self->{endaudio}-$self->{startaudio} )*8/1000/$info{seconds};
	}
	#warn "$_=$info{$_}\n" for keys %info;
	$self->{info}=\%info;
}

1;

