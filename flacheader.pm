# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

#http://flac.sourceforge.net/format.html
package Tag::Flac;
use strict;
use warnings;
our @ISA=('Tag::OGG');

use constant
{ STREAMINFO	=> 0,
  PADDING	=> 1,
  APPLICATION	=> 2,
  SEEKTABLE	=> 3,
  VORBIS_COMMENT=> 4,
  CUESHEET	=> 5,
  PICTURE	=> 6,
};

sub new
{   my ($class,$file)=@_;
    my $self=bless {}, $class;
    local $_;
    # check that the file exists and is readable
    unless ( -e $file && -r $file )
    {	warn "File '$file' does not exist or cannot be read.\n";
	return undef;
    }
    $self->{filename} = $file;
    $self->{startaudio}=0; #start of flac stream (in case an id3v2 tag is at the beginning of the file)
    my $fh=$self->_open  or return undef;

    my $buffer;
    {	last unless read($fh,$buffer,4)==4;
	if ($buffer=~m/^ID3/)
	{	my $tag=Tag::ID3v2->new_from_file($self);
		$self->{startaudio}+=$tag->{size};
		redo;
	}
    }
    unless ($buffer && $buffer eq 'fLaC')
	{ warn "flac: Not a flac header\n"; $self->_close; return undef; }

    my $last;
    while ( !$last && read($fh,$buffer,4)==4 )
    {	$buffer=unpack 'N',$buffer;
	my $size=$buffer & 0xffffff;
	my $pos=tell $fh;
	my $type=($buffer >> 24) & 0x7f;
	$last=$buffer >>31;
	unless (read($fh,$buffer,$size)==$size)
	 { warn "flac: Premature end of file\n"; $self->_close; return undef; }
	if	($type==STREAMINFO)	{$self->{info}=_ReadInfo(\$buffer);}
	elsif	($type==VORBIS_COMMENT) {$self->{comments}=_UnpackComments($self,\$buffer); $self->{comment_offset}=$pos-4}
	elsif	($type==PICTURE)	{my $pic=_ReadPicture(\$buffer); push @{$self->{pictures}},$pic if $pic;}
    }
    my $audiosize=(stat $fh)[7]-tell($fh);
    $self->_close;
    unless ($self->{info})
    {	warn "error, can't read file or not a valid flac file\n";
	return undef;
    }
    $self->{info}{bitrate}= $self->{info}{seconds} ? $audiosize*8/$self->{info}{seconds} : 0;
    unless ($self->{comments})
    {	$self->{vorbis_string}='gmusicbrowser'; #FIXME
	$self->{CommentsOrder}=[];
	$self->{comments}={};
    }
    return $self;

}

sub write_file	# experimental
{	my $self=shift;
	local $_;
	my ($INfh,$OUTfh);
	my $newcom_packref=_PackComments($self);
	my $fh=$self->_open  or return undef;
	my $buffer; my $last; my $towrite='fLaC'; my $padding=0;
	seek $fh,$self->{startaudio} ,0; #skip extra tags
	return undef unless (read($fh,$buffer,4)==4 && $buffer eq 'fLaC');
	while ( !$last && read($fh,$buffer,4)==4 )
	{	$buffer=unpack 'N',$buffer;
		my $size=$buffer & 0xffffff;
		my $type=($buffer >> 24) & 0x7f;
		$last=$buffer >>31;
		if ($type!=VORBIS_COMMENT && $type!=PADDING)
		{	$buffer&=0x7fffffff;	#set Last-metadata-block flag to 0
			$towrite.=pack 'N',$buffer;
			unless (read($fh,$towrite,$size,length($towrite))==$size)
			 { warn "flac: Premature end of file\n"; return undef; }
		}
		else {$padding+=$size+4; seek $fh,$size,1; }
	}
	$padding-=4+length $$newcom_packref;
	my $header=VORBIS_COMMENT;
	my $inplace=($padding==0 || ($padding>3 && $padding<8192) );
	#if ($inplace && $padding<4)
	# { $$newcom_packref.="\x00" x(4-$padding); $padding=''; $header+=0x80; }
	if ($padding==0) {$header+=0x80;$padding='';}
	else
	{	$padding=$inplace? $padding-4 : 256;
		$padding=pack "Nx$padding",((0x80+PADDING)<<24)+$padding;
	}
	$header=pack 'N',($header<<24)+length $$newcom_packref;
	if ($inplace)
	{	$self->_close;
		$fh=$self->_openw or return undef;
		seek $fh,$self->{startaudio} ,0;
		print $fh $towrite.$header.$$newcom_packref.$padding or warn $!;
		$self->_close;
		return 1;
	}
	else
	{	my $tmpfh=$self->_openw(1) or return undef;
		if ($self->{startaudio})
		{	seek $fh,0,0;
			read($fh,$buffer,$self->{startaudio});
			print $tmpfh $buffer or warn $!;
		}
		print $tmpfh $towrite.$header.$$newcom_packref.$padding or warn $!;
		while (read($fh,$buffer,1048576))
		 { print $tmpfh $buffer or warn $!; }
		$self->_close;
		close $tmpfh;
		warn "replacing old file with new file.\n";
		unlink $self->{filename} && rename $self->{filename}.'.TEMP',$self->{filename};
		return 1;
	}
}

sub _close
{	my $self=shift;
	close delete($self->{fileHandle});
}

sub _ReadInfo
{	my $packref=$_[0];
	my @v=unpack 'nn CnCn nCCN',$$packref;
	#A16 B16 C8 C16 D8 D16 E16 EEEEFFFG GGGGHHHH H32 I128
	#A <16> The minimum block size (in samples) used in the stream
	#B <16> The maximum block size (in samples) used in the stream. (Minimum blocksize == maximum blocksize) implies a fixed-blocksize stream.
	#C <24> The minimum frame size (in bytes) used in the stream. May be 0 to imply the value is not known.
	#D <24> The maximum frame size (in bytes) used in the stream. May be 0 to imply the value is not known.
	#E <20> Sample rate in Hz. Though 20 bits are available, the maximum sample rate is limited by the structure of frame headers to 1048570Hz. Also, a value of 0 is invalid.
	#F <3>  (number of channels)-1. FLAC supports from 1 to 8 channels
	#G <5> (bits per sample)-1. FLAC supports from 4 to 32 bits per sample. Currently the reference encoder and decoders only support up to 24 bits per sample
	#H  <36> Total samples in stream. 'Samples' means inter-channel sample, i.e. one second of 44.1Khz audio will have 44100 samples regardless of the number of channels. A value of zero here means the number of total samples is unknown.
	#I  <128>  MD5 signature of the unencoded audio data
	my %info;
	$info{min_block_size}=$v[0];
	$info{max_block_size}=$v[1];
	$info{min_frame_size}=($v[2]<<16)+$v[3];
	$info{max_frame_size}=($v[4]<<16)+$v[5];
	$info{rate}=($v[6]<<4)+($v[7]>>4);
	$info{channels}=1+( ($v[7] & 0b1110)>>1 );
	$info{bit_per_sample}=1+( ($v[7] & 0b1)<<5 )+( $v[8] >>4 );
	$info{seconds}=( $v[9]+($v[8] & 0b1111)*2**32 )/$info{rate};
	return \%info;
}

sub _ReadPicture
{	my $packref=$_[0];
	eval
	{	my ($type,$mime,$desc,undef,undef,undef,undef,$data)
			=unpack 'V V/a V/a VVV V/a',$$packref;
		return [$mime,$type,$desc,$data];
	};
	warn "invalid picture block - skipped\n";
	return undef;
}

sub _UnpackComments
{	my ($self,$packref)=@_;
	my ($vstring,@c);
	eval { ($vstring,@c)=unpack 'V/a V/(V/a)',$$packref; };
	if ($@) { warn "Comments corrupted\n"; return undef; }
	$self->{vorbis_string}=$vstring;
	my %comments;
	for (@c)
	{	unless (s/^([^=]+)=//) { warn "comment invalid - skipped\n"; next; }
		my $key=lc$1;
		my $val=Encode::decode('utf-8', $_);
		#print "$key = $val\n";
		push @{ $comments{$key} },$val;
		my $nb=@{ $comments{$key} }-1;
		push @{$self->{CommentsOrder}}, $key;
	}
	return \%comments;
}
sub _PackComments
{	my $self=$_[0];
	my @comments;
	my %count;
	for my $key ( @{$self->{CommentsOrder}} )
	{	my $nb=$count{$key}++ || 0;
		my $val=$self->{comments}{$key}[$nb];
		next unless defined $val;
		push @comments,$key.'='.$val;
	}
	my $packet=pack 'V/a* V (V/a*)*',$self->{vorbis_string},scalar @comments,@comments;
	#$packet.="\x01"; #framing_flag #gstreamer doesn't like it and not needed anyway
	return \$packet;
}

1;
