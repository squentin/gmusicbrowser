# Copyright (C) 2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Tag::WVfile;
use strict;
use warnings;
our @ISA=('Tag::MP3');
my @sample_rates;

INIT
{ @sample_rates = (6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000);
}

sub new
{   my ($class,$file,$findlength)=@_;
    my $self=bless {}, $class;
    local $_;
    # check that the file exists
    unless (-e $file)
    {	warn "File '$file' does not exist.\n";
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
	return unless read($fh,$buf,32)==32;
	return unless $buf=~m/^wvpk/;
	my ($block_size,$ver,$total_samples,$block_index,$block_samples,$flags)=unpack 'x4Vvx2VVVV',$buf;
	$total_samples=0 if $total_samples==0xffff; #unknown length
	$ver=sprintf '4.%x',$ver; $ver=~s/(\d)$/.$1/;
	$info{version}=$ver;
	$info{channels}= ($flags>>2) & 1  ? 1 : 2;
	$info{frames}=$total_samples;
	$info{rate}= $sample_rates[ ($flags>>23) & 0b1111 ];
	#my $bytes_per_sample= ($flags & 0b11)+1;
	if ($total_samples==0) {$info{seconds}=$info{bitrate}=0}
	else
	{ $info{seconds}=( $total_samples/$info{rate} );
	  $info{bitrate}=( $self->{endaudio}-$self->{startaudio} )*8/$info{seconds};
	}
	#warn "$_=$info{$_}\n" for keys %info;
	$self->{info}=\%info;
}

1;

