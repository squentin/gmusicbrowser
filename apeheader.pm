# Copyright (C) 2007,2010 Quentin Sculo <squentin@free.fr>
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
	my $fh=$self->{fileHandle};
	my $offset=$self->{startaudio};
	seek $fh,$offset,0;
	my $buf;
	return unless read($fh,$buf,32)==32;
	my ($sig,$v,$desc_size)=unpack 'a4vx2v',$buf;
	return unless $sig eq 'MAC ';
	my ($compression,$blocksperframe,$finalsblocks,$nbframes,$channels,$freq);
	if ($v<3980)	#old header
	{	($compression,$channels,$freq,$nbframes,$finalsblocks)=unpack 'x6vx2vVx8VV',$buf;
		$blocksperframe= $v>=3950 ? 73728*4 :
				($v>=3900 || ($v>=3800 && $compression==4000)) ? 73728 : 9216;
	}
	else
	{	seek $fh,$desc_size-32,1;
		return unless read($fh,$buf,24)==24;
		($compression,$blocksperframe,$finalsblocks,$nbframes,$channels,$freq)=unpack 'vx2VVVx2vV',$buf;
	}
	my $bitrate= my $seconds=0;
	my $blocks = ($nbframes-1)*$blocksperframe+$finalsblocks;
	if ($blocks & $freq)
	{	$seconds= $blocks/$freq;
		$bitrate= ( $self->{endaudio}-$self->{startaudio} ) *8/$seconds;
	}
	my %info=
	(	version		=> $v/1000,
		channels	=> $channels,
		frames		=> $nbframes,
		rate		=> $freq,
		seconds		=> $seconds,
		bitrate_calculated=> $bitrate,
		compression	=> $compression{$compression} || $compression,
	);
	#warn "$_=$info{$_}\n" for keys %info;
	$self->{info}=\%info;
}

1;

