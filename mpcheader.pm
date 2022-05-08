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
	if ($buf=~m/^MPCK/) #SV8
	{	seek $fh,$offset+4,0;
		$self->readV8packets;
		my $info= $self->{info};
		$info->{bitrate_calculated}=( $self->{endaudio}-$self->{startaudio} )*8/$info->{seconds} if $info && $info->{seconds};
		return;
	}
	elsif ($buf=~m/^MP\+/)	#SV7, SV7.1 or SV8? (I've found doc describing SV8 format like that (MP+ instead of MPCK), but not sure such files exist)
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
	$info{bitrate_calculated}=( $self->{endaudio}-$self->{startaudio} )*8/$info{seconds};
#	warn "$_=$info{$_}\n" for keys %info;
	$self->{info}=\%info;
}

sub readV8packets
{	my $self=shift;
	my $fh=$self->{fileHandle};
	my %info;

	eval { # in eval block to avoid error in case of invalid BER value in unpack
	  while (my $read=read($fh,my$buf,12))
	  {	last if $read<3;
		my ($id,$size,$notheader)=unpack 'A2wa*',$buf; #size is BER compressed integer
		$notheader=length $notheader; #number of bytes read that are not from the header
		if ($id!~m/^[A-Z][A-Z]$/) { warn "mpcV8: invalid packet id ".unpack("H*",$id)."\n"; return }
		warn "mpcV8 packet=$id size=$size\n" if $::debug;

		if ($id eq 'AP') { return } # currently stop when the first audio packet is found
		#FIXME very unlikely to happen, especially with audio files, but $size could be too big to be kept as an integer, max possible value is 2**70-1
		# not sure if a too big value would cause problem with seek/read
		# ok for now as it should only affect audio packets, and we stop at the first one

		return if $id eq 'SE'; #stream end packet
		$size-= $read-$notheader; # $size is now size of packet without header
		seek $fh,-$notheader,1; #position at end of packet header
		if ($id eq 'SH' || $id eq 'RG')
		{	my $read=read $fh,$buf,$size;
			if ($read!=$size) { warn "mpcv8: packet $id too short\n"; return }
			if ($id eq 'SH') # stream header packet
			{	my ($crc,$version,$samples,$silence,$freq_bands,$chan_MS_frames)= unpack 'NCwwCC',$buf; # count and silence are BER compressed integer
				# $crc is ignored for now
				warn "mpcV8: unknown bitstream version $version\n" if $version!=8;
				my $freq= $freq_bands>>5;
				$info{rate}= $freq<4 ? $freq[$freq] : 0; #freq can be 0 to 7, but only defined up to 3
				$info{channels}= 1+($chan_MS_frames>>4);
				$info{max_bands}= $chan_MS_frames & 0b11111;
				$info{mid_side_stereo}= $chan_MS_frames & 0b1000 ? 1 : 0;
				$info{frames_per_audio_packet}= 4**($chan_MS_frames & 0b111);
				$info{samples}=$samples;
				$info{silence_samples}=$silence;
				$info{version}=$version;
				$info{seconds}= $info{rate} ? ($samples-$silence)/$info{rate} : 0;
				$self->{info}=\%info;
			}
			elsif ($id eq 'RG') # replaygain packet
			{	my ($version,$tgain,$tpeak,$again,$apeak)= unpack 'Cs>4',$buf; # "s>": signed big-endian 16bit
				$info{replaygain_version}=$version;
				$info{track_gain}= (10 ** ($tgain/256/20) / 65535) if $tgain;#formula taken from mutagen
				$info{album_gain}= (10 ** ($again/256/20) / 65535) if $again;
				$info{track_peak}= 64.82-$tpeak/256 if $tpeak;#formula taken from mutagen
				$info{album_peak}= 64.82-$apeak/256 if $apeak;
				#ignored for now
			}
		}
		else { seek $fh,$size,1 } #skip
	  }
	};
}

1;
