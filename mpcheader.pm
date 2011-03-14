# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation
package Tag::MPC;
use strict;
use warnings;
our @ISA=('Tag::MP3');
my (@profiles,@freq);

INIT
{ @profiles=
  (	'na',		'Unstable/Experimental','na',			'na',
	'na',		'below Telephone',	'below Telephone',	'Telephone',
	'Thumb',	'Radio',		'Standard',		'Xtreme',
	'Insane',	'BrainDead',		'above BrainDead',	'above BrainDead'
  );
  @freq=(44100,48000,37800,32000);
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
	$info{channels}=2;
	my $fh=$self->{fileHandle};
	my $offset=$self->{startaudio};
	seek $fh,$offset,0;
	read $fh,my$buf,11;
	if ($buf=~m/^MP\+/)	#SV7, SV7.1 or SV8
	{	my ($v,$nbframes,$pf)=unpack 'x3CVxxC',$buf;
		$info{version}=($v & 0x0f).'.'.($v>>4);
		if (($v & 0x0f)>8) { warn "Version of mpc not supported\n";return; }
		$info{frames}=$nbframes;
		$info{profile}=$profiles[$pf >> 4];
		$info{rate}=$freq[$pf & 0b11];
	}
	else #SV 4 5 or 6
	{	my ($dword,$nbframes)=unpack 'VV',$buf;
		$info{version}=my $v=($dword >> 11) & 0x3ff;
		return if $v<4 && $v>6;
		$nbframes>>=16 if $v==4;
		$info{frames}=$nbframes;
		$info{rate}=44100;
	}
	$info{seconds}=$info{frames}*1152/$info{rate};
	$info{bitrate}=( $self->{endaudio}-$self->{startaudio} )*8/$info{seconds};
#	warn "$_=$info{$_}\n" for keys %info;
	$self->{info}=\%info;
}

1;
