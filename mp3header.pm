# Copyright (C) 2005-2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

#Library to read/write mp3 tags (id3v1 id3v2 APE lyrics3), read mp3 header, find mp3 length by reading VBR header or counting mp3 frames
# http://www.id3.org/develop.html
# http://www.dv.co.yu/mpgscript/mpeghdr.htm
# http://www.multiweb.cz/twoinches/MP3inside.htm
# http://www.thecodeproject.com/audio/MPEGAudioInfo.asp

#http://www.kevesoft.com/crossref.htm
#http://www.matroska.org/technical/specs/tagging/othertagsystems/comparetable.html
#http://hobba.hobba.nl/audio/tag_frame_reference.html

use strict;
use warnings;

package Tag::MP3;

my (@bitrates,@freq,@versions,@encodings,$regex_t);
our @Genres;

my $MODIFIEDFILE;

INIT
{ @bitrates=
  ([	# version 1
	[0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],	#layer I
	[0, 32, 48, 56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 384],	#layer II
	[0, 32, 40, 48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320],	#layer III
   ],
   [	#version 2
	[0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],	#layer I
	[0,  8, 16, 24, 32, 40, 48,  56,  64,  80,  96, 112, 128, 144, 160],	#layer II
	#[0, 8, 16, 24, 32, 40, 48,  56,  64,  80,  96, 112, 128, 144, 160],	#layer III
   ],
  );
  $bitrates[1][2]=$bitrates[1][1]; #v2 layer 2 & 3 have the same bitrates

  @freq=( [11025,12000,8000],	# MPEG version 2.5 (from mp3info)
	  undef,		# invalid version
	  [22050,24000,16000],	# MPEG version 2
	  [44100,48000,32000],	# MPEG version 1
   	 );
  @versions=(2.5,undef,2,1);
  my $re8=qr/^(.*?)(?:\x00|$)/s;
  my $re16=qr/^((?:..)*?)(?:\x00\x00|$)/s;
  $regex_t=$re8;
  @encodings=
  (	['iso-8859-1',	"\x00",		$re8	],
	['utf16',	"\x00\x00",	$re16	], #with BOM
	['utf16be',	"\x00\x00",	$re16	],
	['utf8',	"\x00",		$re8	],
  );

  #@index_apic=('other','32x32 PNG file icon','other file icon','front cover','back cover','leaflet page','media','lead artist','artist','conductor','band','composer','lyricist','recording location','during recording','during performance','movie/video screen capture','a bright coloured fish','illustration','band/artist logotype','Publisher/Studio logotype');

  @Genres=('Blues','Classic Rock','Country','Dance','Disco','Funk','Grunge',
   'Hip-Hop','Jazz','Metal','New Age','Oldies','Other','Pop','R&B',
   'Rap','Reggae','Rock','Techno','Industrial','Alternative','Ska',
   'Death Metal','Pranks','Soundtrack','Euro-Techno','Ambient',
   'Trip-Hop','Vocal','Jazz+Funk','Fusion','Trance','Classical',
   'Instrumental','Acid','House','Game','Sound Clip','Gospel','Noise',
   'Alt. Rock','Bass','Soul','Punk','Space','Meditative',
   'Instrumental Pop','Instrumental Rock','Ethnic','Gothic',
   'Darkwave','Techno-Industrial','Electronic','Pop-Folk','Eurodance',
   'Dream','Southern Rock','Comedy','Cult','Gangsta Rap','Top 40',
   'Christian Rap','Pop/Funk','Jungle','Native American','Cabaret',
   'New Wave','Psychedelic','Rave','Showtunes','Trailer','Lo-Fi',
   'Tribal','Acid Punk','Acid Jazz','Polka','Retro','Musical',
   'Rock & Roll','Hard Rock','Folk','Folk/Rock','National Folk',
   'Swing','Fast-Fusion','Bebob','Latin','Revival','Celtic',
   'Bluegrass','Avantgarde','Gothic Rock','Progressive Rock',
   'Psychedelic Rock','Symphonic Rock','Slow Rock','Big Band',
   'Chorus','Easy Listening','Acoustic','Humour','Speech','Chanson',
   'Opera','Chamber Music','Sonata','Symphony','Booty Bass','Primus',
   'Porn Groove','Satire','Slow Jam','Club','Tango','Samba',
   'Folklore','Ballad','Power Ballad','Rhythmic Soul','Freestyle',
   'Duet','Punk Rock','Drum Solo','A Cappella','Euro-House',
   'Dance Hall','Goa','Drum & Bass','Club-House','Hardcore','Terror',
   'Indie','BritPop','Negerpunk','Polsk Punk','Beat',
   'Christian Gangsta Rap','Heavy Metal','Black Metal','Crossover',
   'Contemporary Christian','Christian Rock','Merengue','Salsa',
   'Thrash Metal','Anime','JPop','Synthpop',
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
    $self->_removeblank;
    $self->{info}=$self->_FindFirstFrame;
    return undef unless $self->{info};
    if ( $findlength && !$self->{info}{frames} && ( $findlength>1 || !$self->{info}{seconds}) )
    #if (1)
    	{ warn "No VBR header found, must count all the frames to determine length.\n" if $::debug;
	  my $tries;
	  until (_CountFrames($self))
	  {	warn "** searching another first frame\n" if $::debug;
		$self->{info}=undef;
		last if ++$tries>20;
		last unless $self->{info}=$self->_FindFirstFrame($self->{firstframe}+1);
	  }
	  unless ($self->{info}) { warn "Can't determine number of frames, probably not a valid mp3 file.\n"; }
	}
    $self->_close;
    return $self;
}

sub _FindTags
{	my $self=shift;
	$self->{tags_before}=[];
	$self->{tags_after}=[];
	$self->{startaudio}=0;
	my $fh=$self->{fileHandle};

		#Find ID3 tag(s) at the start of the file
	{ my $tag;
	  seek $fh,$self->{startaudio},0;
	  read $fh,my($header),8;
	  if	($header=~m/^ID3/)	{ $tag=Tag::ID3v2->new_from_file($self); }
	  elsif ($header=~m/^APETAGEX/)	{ $tag=  Tag::APE->new_from_file($self); }
	  last unless $tag;
	  $tag->{offset}=$self->{startaudio};
	  $self->{startaudio}+=$tag->{size};
	  push @{ $self->{tags_before} },$tag;
	  redo if 1;	#look for another tag ?
	}

	#Check end of file for tags
	seek $fh,0,2;
	$self->{endaudio}=tell $fh;
	seek $fh,-128,2;
	read $fh,my($id3v1),128;
	my $apefooter= substr($id3v1,-32,8) eq 'APETAGEX' && substr($id3v1,-8) eq ("\x00"x8);
	if (!$apefooter && substr($id3v1,0,3) eq 'TAG')	#ID3v1 tag
	{	$self->{ID3v1}= Tag::ID3v1->new_from_string($id3v1);
		$self->{endaudio}-=128;
	}

	# search for tag signatures at the end, repeat until none is found
	{	seek $fh,$self->{endaudio}-32,0;
		my $read=read $fh,my($footer),32;
		last unless $read==32;	#for bogus files <32 bytes
		my $tag;
		if    ($footer=~m/^APETAGEX/)			{ $tag=      Tag::APE->new_from_file($self,1); }
		elsif ('3DI'	   eq substr $footer,32-10,3)	{ $tag=    Tag::ID3v2->new_from_file($self,1); }
		elsif ('LYRICS200' eq substr $footer,32-9,9)	{ $tag=Tag::Lyrics3v2->new_from_file($self);   }
		elsif ('LYRICSEND' eq substr $footer,32-9,9)	{ $tag=Tag::Lyrics3v1->new_from_file($self);   }
		if ($tag)
		{  $self->{endaudio}-=$tag->{size};
		   $tag->{offset}=$self->{endaudio};
		   push @{ $self->{tags_after} },$tag;
		   redo;
		}
	}
	return;
}

sub SyncID3v1	#auto sync with id3v2
{	my $self=shift;
	my $id3v1= $self->{ID3v1} || $self->new_ID3v1;
	my $genre=$id3v1->[6];
	my @genres;
	$id3v1->[6]=\@genres;
	if (defined $genre)
	{	if (ref $genre) { push @genres,@$genre	}
		else		{ push @genres,$genre	}
	}
	if ($self->{ID3v2})
	{	my $ref=$self->{ID3v2}{frames};
		my $r;
		if ($ref->{TIT2} and ($r)=(grep defined, @{$ref->{TIT2}})) { $id3v1->[0] = $r->[0]; }
		if ($ref->{TPE1} and ($r)=(grep defined, @{$ref->{TPE1}})) { $id3v1->[1] = $r->[0]; }
		if ($ref->{TALB} and ($r)=(grep defined, @{$ref->{TALB}})) { $id3v1->[2] = $r->[0]; }
		if ($ref->{COMM} and ($r)=(grep defined, @{$ref->{COMM}})) { $id3v1->[4] = $r->[2]; }
		if ($ref->{TYER}) { for (grep defined, @{$ref->{TYER}}) { if ($_->[0]=~m/(\d{4})/)  {$id3v1->[3]=$1;last} }}
		if ($ref->{TRCK}) { for (grep defined, @{$ref->{TRCK}}) { if ($_->[0]=~m/^(\d\d?)/) {$id3v1->[5]=$1;last} }}
		if ($ref->{TCON}) { unshift @genres,@$_ for grep defined,@{$ref->{TCON}} }
		#unshift @genres, @{ $ref->{TCON}[0] } if $ref->{TCON};
	}
}

sub new_ID3v1	 { Tag::ID3v1	 ->new($_[0]); }
sub new_Lyrics3v2{ Tag::Lyrics3v2->new($_[0]);	}
sub new_APE	 { Tag::APE	 ->new($_[0]);	}
sub new_ID3v2	 { Tag::ID3v2	 ->new($_[0]);	}
sub add
{	my $self=shift;
	my $id3v2=$self->{ID3v2} || $self->new_ID3v2;
	$id3v2->add(@_);
}
sub insert
{	my $self=shift;
	my $id3v2=$self->{ID3v2} || $self->new_ID3v2;
	$id3v2->insert(@_);
}
sub edit
{	my $self=shift;
	my $id3v2=$self->{ID3v2} || return 0;
	$id3v2->edit(@_);
}
sub remove
{	my $self=shift;
	my $id3v2=$self->{ID3v2} || return 0;
	$id3v2->remove(@_);
}
sub remove_all
{	my $self=shift;
	my $id3v2=$self->{ID3v2} || return 0;
	$id3v2->remove_all(@_);
}

sub write_file
{	my $self=shift;
	my @towritebefore=();
	my @towriteafter=();
	my $id3v2tag;
	my $copybegin=$self->{startaudio};
	my $copyend=$self->{endaudio};
	{	my $blank=$self->{blank}; #blank before audio
		my $fh;
		my $hole=0;
		for my $tag (reverse @{ $self->{tags_before} })
		{	#warn "$tag : ".(join ' ',keys %$tag)."\n";
			if    ($tag->{deleted})	{ $hole=1; }
			elsif ($tag->{edited})
			{	$hole=1;
				unshift @towritebefore, $tag->make;
				$id3v2tag=$towritebefore[0] if ref $tag eq 'Tag::ID3v2';
			}
			elsif ($hole)
			{	#read tag, put it in @towritebefore
				$fh||=$self->_open or return undef;
				seek $fh,$tag->{offset},0;
				my $buffer;
				read $fh,$buffer,$tag->{size};
				unshift @towritebefore, \$buffer;
			}
			else	{ if ($blank) {$copybegin-=$blank; $blank=0;}
				  $copybegin-=$tag->{size};
				}
		}
		$hole=0;
		for my $tag (reverse @{ $self->{tags_after} })
		{	if    ($tag->{deleted})	{ $hole=1; }
			elsif ($tag->{edited})
			{	$hole=1;
				push @towriteafter, $tag->make;
			}
			elsif ($hole)
			{	#read tag, put it in @towriteafter
				$fh||=$self->_open or return undef;
				seek $fh,$tag->{offset},0;
				my $buffer;
				read $fh,$buffer,$tag->{size};
				push @towriteafter,\$buffer;
			}
			else	{ $copyend+=$tag->{size}; }
		}
		$self->_close if $fh;
	}
	push @towriteafter, $self->{ID3v1}->make if $self->{ID3v1};
	warn "startaudio=".$self->{startaudio}." copybegin=$copybegin length(towritebefore)=".join(' ',map(length $$_,@towritebefore))."\n" if $::debug;
	warn "endaudio=".$self->{endaudio}." copyend=$copyend length(towriteafter)=".join(' ',map(length $$_,@towriteafter))."\n" if $::debug;
	my $in_place;
	if ($id3v2tag)
	{	my $padding=$copybegin;
		$padding-=length($$_) for @towritebefore;
		if	($padding<0 || $padding>2048)	{ $padding=256 }
		else					{ $in_place=1  }
		Tag::ID3v2::_SetPadding($id3v2tag,$padding);
	}
	if ($in_place)
	{	# in place editing
		warn "in place editing.\n"; #DEBUG
		my $fh=$self->_openw or return undef;
		return undef unless defined $fh;
		print $fh $$_  or warn $!  for @towritebefore;
		seek $fh,$copyend,0;
		print $fh $$_  or warn $!  for @towriteafter;
		truncate $fh,tell($fh);
		$self->_close;
		return 1;
	}
	my $INfh=$self->_open or return undef;
	# create new file
	my $OUTfh=$self->_openw(1) or return undef;	#open .TEMP file
	my $werr;
	print $OUTfh $$_  or warn $! and $werr++  for @towritebefore;
	  # copy audio data + unmodified tags next to audio data
	seek $INfh,$copybegin,0;
	#read $INfh,my($buffer),$copyend-$copybegin;
	#print $OUTfh $buffer  or warn $! and $werr++;
	my $tocopy=$copyend-$copybegin;
	while ($tocopy>0)
	{	my $size=($tocopy>1048576)? 1048576 : $tocopy;
		read $INfh,my($buffer),$size;
		print $OUTfh $buffer  or warn $! and $werr++;
		$tocopy-=$size;
	}
	$self->_close;
	print $OUTfh $$_  or warn $! and $werr++  for @towriteafter;
	close $OUTfh;
	if ($werr) {warn "write errors... aborting.\n"; unlink $self->{filename}.'.TEMP'; return 0; }
	warn "replacing old file with new file.\n";
	unlink $self->{filename} && rename $self->{filename}.'.TEMP',$self->{filename};
	$MODIFIEDFILE=1;
	%$self=(); #destroy the object to make sure it is not reused as many of its data are now invalid
	return 1;
}

sub _open
{	my $self=$_[0];
	my $file=$self->{filename};
	open my$fh,'<',$file or warn "can't open $file : $!\n" and return undef;
	binmode $fh;
	$self->{fileHandle} = $fh;
	return $fh;
}
sub _openw
{	my ($self,$tmp)=@_;
	my $file=$self->{filename};
	my $m='+<';
	if ($tmp) {$file.='.TEMP';$m='>';}
	my $fh;
	until (open $fh,$m,$file)
	{	my $err="Error opening '$file' for writing :\n$!";
		warn $err."\n";
		return undef unless $self->{errorsub} && $self->{errorsub}($err) eq 'yes';
	}
	binmode $fh;
	$self->{fileHandle} = $fh unless $tmp;
	return $fh;
}

sub _close
{	my $self=shift;
	close delete($self->{fileHandle});
}

sub _removeblank	#remove blank before audio
{	my $self=$_[0];
	my $fh=$self->{fileHandle};
	seek $fh,$self->{startaudio},0;
	my ($buf,$read); my $blank=0;
	while (($read=read $fh,$buf,100) && $buf=~m/^\00+/)
	{	$blank+=$+[0];
		last unless $read==$+[0];
	}
	$self->{blank}=$blank;
	return unless $blank;
	warn "blank before audio : $blank bytes\n" if $::debug;
	$self->{startaudio}+=$blank;
}

sub _FindFirstFrame
{	my ($self,$offset)=@_;
	my $fh=$self->{fileHandle};
	$offset||=$self->{startaudio};
	seek $fh,$offset,0;
	my $pos=0;
	my %info;
	read $fh,my$buf,100;
SEARCH1ST: while ($pos<60000)			#only look in the first 60000 bytes (after tag)
	{	while ($buf=~m/\xff(...)/sg)
		#while ($buf=~m/\xff([\xe0-\xff][\x00-\xef].)/sg)
		{	my ($byte2,$byte3,$byte4)=unpack 'CCC',$1;
			#print "AAABBCCD EEEEFFGH IIJJKLMM\n";	#DEBUG
			#@_=unpack 'B8B8B8B8',$1; print "@_\n";	#DEBUG
			#next if $byte2<0xf0;	#not a synchro signal (0b11110000)
		#	next if $byte2<0xe0;	#not a synchro signal (0b11100000)
		#	next unless $byte3<0xf0;	#invalid bitrate # ($byte3 & 0b11110000)==0b11110000
			my $mpgversion=($byte2>>3)& 0b11;
			next if $mpgversion==1; #invalid MPEG version
			my $layer=($byte2>>1)& 0b11;
			next if $layer==0;	#invalid layer
			my $freq=($byte3>>2) & 0b11;
			next if $freq==3;	#invalid frequence #warn "unknown sampling rate\n"
			my $bitrateindex=$byte3>>4;
			next if $bitrateindex==15; #invalid bitrate index
			$pos+=$-[0];
			$self->{firstframe}=$pos+$offset;
			warn "skipped $pos, first frame at $self->{firstframe}\n" if $pos && $::debug;
			$self->{byte2}=$byte2;
			$info{version2}=($mpgversion & 0b1)? 0 : 1;
			$info{versionid}=$versions[$mpgversion];
			$info{rate}=$freq[ $mpgversion ][ $freq ];
			$info{layer}=4-$layer;
			$info{crc}=($byte2 & 0b1)? 0 : 1;
			$info{bitrate}=1000*$bitrates[ $info{version2} ][ $info{layer}-1 ][$bitrateindex];
			#if ($info{bitrate}==0) { warn "free bitrate not supported\n"; }
			$info{channels}=($byte4>>6==3)? 1 : 2;
			$info{sampleperframe}=	$info{layer}==1?  384 :
						$info{version2}?  576 :
								 1152 ;
			#compute size of first frame
			  my $pad=($info{layer}==1)? 4 : 1;
			  my $firstframe_size=int($info{bitrate}*$info{sampleperframe}/8/$info{rate});
			  $firstframe_size+=$pad if $byte3 & 0b10;
			#warn "firstframe_size : $firstframe_size\n";
			$self->{audiodatasize}=$self->{endaudio} - $self->{firstframe};
			#check for VBRI header #http://www.thecodeproject.com/audio/MPEGAudioInfo.asp
			{ seek $fh,$self->{firstframe}+36,0;
			  read $fh,$_,18;
			  my ($id,$vers,$delay,$quality,undef,$frames)=unpack 'a4nnnNN',$_;
			  #should I $frames-- to remove this info frame ?
			  last unless $id eq 'VBRI';
			  warn "VBRI header found : version=$vers delay=$delay quality=$quality nbframes=$frames\n" if $::debug;
			  $info{vbr}=1;
			  $self->{audiodatasize}-=$firstframe_size;
			  _calclength(\%info,$frames,$self->{audiodatasize});
			  last SEARCH1ST
			}
			#check if frame is the Xing/LAME header
			{ #offset depends on mpegversion and channels :
			  # 13 for mono v2/2.5 , 36 for stereo v1 , 21 for other
			  $_=(13,21,36)[ (!$info{version2}) + ($info{channels}!=3) ];
			  seek $fh,$self->{firstframe}+$_,0;
			  read $fh,$_,12;
			  my ($id,$flags,$frames)=unpack 'a4NN',$_;
			  last unless ($id eq 'Xing' || $id eq 'Info');
			  warn "Xing header found : $id flags=$flags nbframes=$frames\n" if $::debug;
			  last unless $flags & 1; # unless number of frames is stored
			  $info{vbr}=($id eq 'Xing');
			  $self->{audiodatasize}-=$firstframe_size;
			  _calclength(\%info,$frames,$self->{audiodatasize});
			  last SEARCH1ST;
			}
			#estimating number of frames assuming: found correct first frame and fixed bitrate
			if ($info{bitrate})
			{ $info{estimated}=1;
			  $info{seconds}=$self->{audiodatasize}*8/$info{bitrate};
			  warn "length estimation : $info{seconds} s\n" if $::debug;
			}
			last SEARCH1ST;
		}
		#read next chunk but keep last 3 bytes
		$pos+=length($buf)-3;
		$buf=substr $buf,-3;
		last unless read $fh,$buf,100,3;
	}
	return \%info if defined $self->{firstframe};
	warn "no MP3 frame found\n";
	return undef;
}

sub _CountFrames		#find and count each frames
{	my $time=times; #DEBUG
	$MODIFIEDFILE=undef;
	my $self=shift;
	my $info=$self->{info};
	return 0 if $info->{bitrate}==0;		#if unknown bitrate
	return undef unless $info->{rate};
	my $fh=$self->{fileHandle};
	seek $fh,$self->{firstframe},0;
	my $frames=0;
	my $skipcount;
	my $byte1_2="\xff".chr $self->{byte2};

	# size of padding when present
	my $pad=($info->{layer}==1)? 4 : 1;
	# construct @size array, which will contain the size of the frame in function of the EEEE bits
	my $m=1000*$info->{sampleperframe}/8/$info->{rate};
	my @size=map int($_*$m)-4, @{ $bitrates[ $info->{version2} ][ $info->{layer}-1 ] };
	# -4 to substract 4 bytes header
	$size[0]=$size[15]=0; #for free (0) or reserved (15) bitrate -> skip frame header and look for next
my $count=1000;
	#search for each frame
	while (read $fh,$_,4)
	{	if (substr($_,0,2) eq $byte1_2)
		{	#print "AAAAAAAA AAABBCCD EEEEFFGH IIJJKLMM\n";	#DEBUG
			#@_=unpack "B8B8B8B8",$_; print "@_\n";		#DEBUG
			#my $pos=tell $fh;				#DEBUG
			#print "$pos frame=$frames size=$s bytes\n";	#DEBUG
			#my $s=$cache{substr($_,2,1)}||=((vec $_,17,1)?	$size[ (vec $_,2,8)>>4 ]+$pad:$size[ (vec $_,2,8)>>4 ])};	# a bit faster, needs a my %cache
			$_=vec $_,2,8;
			#seek to the end of the frame :
			seek $fh,(($_ & 0b10)?	$size[ $_>>4 ]+$pad:
						$size[ $_>>4 ]		),1;
			$frames++;
			unless ($count--) { $count=1000; Gtk2->main_iteration while Gtk2->events_pending; }
		}
		else #skip
		{	#@_=unpack "B8B8",$byte1_2; warn "@_ ".tell($fh)."\n";	#DEBUG
			#warn "AAAAAAAA AAABBCCD EEEEFFGH IIJJKLMM\n";		#DEBUG
			#@_=unpack "B8B8B8B8",$_; warn "@_	doesn't match bytes1_2	frame=$frames\n";		#DEBUG
			 # assume first frame invalid if can't find 3 first frames without skipping
			return undef if $frames<4;
			my $skipped=0;
			my $read; my $pos;
			while ($read=read $fh,$_,252,4)
			{	if (m/\Q$byte1_2\E/) { $pos=$-[0]; last; };
				$skipped+=$read;
				$_=substr $_,-4;
			}
			warn "too much skipping\n" and return undef if $skipcount++>50 && $::debug;
			last unless $read  &&  tell($fh) < $self->{endaudio};
			$skipped+=$pos;
			warn "skipped $skipped bytes (offset=".tell($fh).")\n" if $::debug;
			seek $fh,$pos-256,1;
		}
	}
	_calclength($info,$frames,$self->{audiodatasize});
	$info->{estimated}=1 if $MODIFIEDFILE;	#if a file has been rewrote while reading, mark the info as suspicious
	$time=times-$time; warn "full scan : $time s\n" if $::debug; #DEBUG
	return 1;
}

sub _calclength
{	my ($info,$frames,$bytes)=@_;
	$info->{estimated}=undef;
	$info->{frames}=$frames;
	my $s=$info->{seconds}=$frames*$info->{sampleperframe}/$info->{rate};
	$info->{mmss}=sprintf '%d:%02d',$s/60,$s%60;
	$info->{bitrate}= ($s==0)? 0 : $bytes*8/$s;
	warn "total_frames=$info->{frames}, audio_size=$bytes, length=$info->{mmss},  bitrate=$info->{bitrate}\n" if $::debug;
}

package Tag::ID3v1;
use Encode qw(decode encode);

sub new
{	my $file=$_[1];
	return $file->{ID3v1}= bless [];
}

sub new_from_string
{	my $string=$_[1];
	my ($title,$artist,$album,$year,$comment,$vers1_1,$track,$genre)
	   =unpack 'x3 Z30 Z30 Z30 Z4 Z28 C C C',$string;
	if ($vers1_1!=0)	#-> id3v1.0
	{	$comment=unpack 'x97 Z30',$string;
		$track='';
	}
	s/ *$// for $title,$artist,$album,$comment;
	$_=decode($::Options{TAG_id3v1_encoding}||'iso-8859-1',$_) for $title,$artist,$album,$comment;
	$genre=($genre<@Tag::MP3::Genres)? $Tag::MP3::Genres[$genre] : '';
	return bless [$title,$artist,$album,$year,$comment,$track,$genre];
}

sub make
{	my $self=shift;
	my ($title,$artist,$album,$year,$comment,$track,$genre)= @$self;
	if (defined $genre)
	{	if (ref $genre) { ($genre)=grep defined, map _findgenre($_),@$genre; }
		elsif ($genre=~m/^\D+$/) { $genre=_findgenre($genre); }
	}
	$genre=255 unless defined $genre && $genre ne '';
	my $buffer='TAG';
	my @length=(30,30,30,4,30);
	$length[4]=28 if $track;
	for my $v ($title,$artist,$album,$year,$comment)
	{	$v='' unless defined $v;
		my $l=shift @length;
		$v=encode( $::Options{TAG_id3v1_encoding}||'iso-8859-1', $v);
		if (bytes::length($v)<$l){ $buffer.=pack "Z$l",$v }
		else			 { $buffer.=pack "A$l",$v } #FIXME remove partial multi-byte chars
	}
	$buffer.="\x00".bytes::chr($track) if $track;
	$buffer.=bytes::chr $genre;
	return \$buffer;
}

sub _findgenre
{	my $str=shift;
	my $list=\@Tag::MP3::Genres;
	$str=lc$str;
	my $i;
	for (0..$#$list)
	{	if ($str eq lc$list->[$_]) {$i=$_; last}
	}
	return $i;
}

sub get_values
{	return $_[0][$_[1]];
}

package Tag::Lyrics3v1;
use Encode qw(decode encode);

sub new_from_file	 #http://www.id3.org/lyrics3.html	#untested
{	my ($class,$file)=@_;
	my $fh=$file->{fileHandle};
	seek $fh,-5109,1;
	read $fh,my($buffer),5100;
	return undef unless $buffer=~m/LYRICSBEGIN(.+)/;
	warn "found lyrics3 v1 tag (".length($1)." bytes of lyrics)\n" if $::debug;
	my %tag;
	$tag{size}=length $1;
	$tag{lyrics}=decode('iso-8859-1',$1);
	$tag{makesub}=\&_MakeLyrics3Tag;
	return $file->{lyrics3}=bless(\%tag,$class);
}
sub removetag {	$_[0]{deleted}=1; }
sub make
{	my $tag=shift;
	my $tagstring='LYRICSBEGIN'.substr(encode('iso-8859-1',$tag->{lyrics}),0,4096).'LYRICSEND';
	return \$tagstring;
}

package Tag::Lyrics3v2;
use Encode qw(decode encode);

sub new
{	my ($class,$file)=@_;
	my $self={ fields => {}, fields_order => [], edited => 1 };
	unshift @{ $file->{tags_after} },$self;
	$file->{lyrics3v2}=$self;
	return bless($self,$class);
}

sub new_from_file		#http://www.id3.org/lyrics3200.html
{	my ($class,$file)=@_;
	my $fh=$file->{fileHandle};
	seek $fh,$file->{endaudio}-15,0;
	read $fh,my($header),15;
	my $size=substr $header,0,6;
	return undef unless $size=~m/^[0-9]+$/;
	seek $fh,-$size-15,1;
	read $fh,my($rawtag),$size;
	return undef unless $rawtag=~s/^LYRICSBEGIN//;
	my %tag;
	$tag{size}=$size+15;
	warn "found lyrics3 v2.00 tag (".$tag{size}." bytes)\n" if $::debug;
	while ($rawtag=~s/^([A-Z]{3})([0-9]{5})//)
		{	if ($1 eq 'IND') { $tag{IND}=substr($rawtag,0,$2,''); next; }
			$tag{fields}{$1}=decode('iso-8859-1',substr($rawtag,0,$2,''));
			push @{ $tag{fields_order} },$1;
			warn "Lyrics3 $1 : $tag{fields}{$1}\n" if $::debug;
		}
	return $file->{lyrics3v2}=bless(\%tag,$class);
}
sub removetag {	$_[0]{deleted}=1; }
sub add
{	my ($self,$field,$val)=@_;
	return 0 if $self->{fields}{$field};
	push @{ $self->{fields_order} },$field;
	$self->{fields}{$field}=$val;
	$self->{edited}=1;
	return 1;
}
sub edit
{	my ($self,$field,$nb,$val)=@_;
	return 0 unless $self->{fields}{$field};
	$self->{fields}{$field}=$val;
	$self->{edited}=1;
	return 1;
}
sub remove
{	my ($self,$field)=@_;
	delete $self->{fields}{$field};
	$self->{edited}=1;
	return 1;
}

sub get_keys
{	keys %{ $_[0]{fields} };
}
sub get_values
{	return $_[0]{fields}{$_[1]};
}

sub make
{	my $tag=shift;
	my $tagstring='LYRICSBEGIN';
	$tagstring.='IND'.sprintf( '%05d',length($tag->{IND}) ).$tag->{IND} if $tag->{IND};
	for my $field (@{ $tag->{fields_order} })
	{	next unless defined $tag->{fields}{$field};
		my $v=substr encode('iso-8859-1',delete $tag->{fields}{$field}),0,99999;
		$tagstring.=$field.sprintf('%05d',length $v).$v;
	}
	if ($tagstring ne 'LYRICSBEGIN') #not empty
	{	$tagstring=$tagstring.sprintf('%06d',length $tagstring).'LYRICS200';
	}
	return \$tagstring;
}

package Tag::APE;
# http://wiki.hydrogenaudio.org/index.php?title=APEv2_specification
use Encode qw(decode encode);

sub new
{	my ($class,$file)=@_;
	my $self={ realkey =>{}, item => {}, edited => 1 };
	unshift @{ $file->{tags_after} },$self;
	$file->{APE}=$self;
	return bless($self,$class);
}
sub new_from_file
{	my ($class,$file,$isfooter)=@_;
	my $fh=$file->{fileHandle};
	if ($isfooter)	{ seek $fh,$file->{endaudio}-32,0; }
	else		{ seek $fh,$file->{startaudio} ,0; }
	read $fh,my($headorfoot),32;
	my ($v,$size,$Icount,$flags)=unpack 'x8VVVV',$headorfoot;
	my $rawtag;
	$size+=32 if $flags & 0x80000000; #if contains a header
	return undef unless $size; #for some bogus header with a size=0
	if ($flags & 0x20000000)	#if $headorfoot is a header
	{	read $fh, $rawtag, $size-32;
		return undef unless ($flags & 0x40000000) || $rawtag=~m/APETAGEX.{24}$/s; #check footer
	}
	else				# $headorfoot is a footer -> must seek backward
	{	seek $fh,-$size,1;
		read $fh, $rawtag, $size;
		return undef if ($flags & 0x80000000) && $rawtag!~m/^APETAGEX.{24}/sg; #check header
	}
	my %self=( version=> $v/1000, size=> $size, realkey =>{}, item => {}, );
	warn "found APE tag version ".($v/1000)." ($size bytes) ($Icount items)\n" if $::debug;
	for (1..$Icount)
	{	last unless $rawtag=~m/\G(........[\x20-\x7E]+)\x00/sg;
		my ($len,$type,$key)=unpack 'VVa*',$1;
		$key= $self{realkey}{lc$key}||=$key;
		my $val=substr $rawtag,pos($rawtag),$len;
		pos($rawtag)+=$len;
		warn "APE : $key ($len bytes)\n" if $::debug;
		$type&= 0b111;
		if ($type & 0b10) #binary
		{	push @{$self{item}{$key}}, [$val,$type];
		}
		else #utf8 string or link
		{	my @v=split /\x00/,$val;
			push @{$self{item}{$key}}, map {[decode('utf8',$_),$type]} @v;
		}
	}
	return $file->{APE}=bless(\%self,$class);
}
sub removetag {	$_[0]{deleted}=1; }
sub insert
{	my ($self,$key,$val,$type)=@_;
	$key= $self->{realkey}{lc$key}||=$key;
	unshift @{$self->{item}{$key}}, [ $val, $type||0];
	$self->{edited}=1;
	return 1;
}
sub add
{	my ($self,$key,$val,$type)=@_;
	$key= $self->{realkey}{lc$key}||=$key;
	push @{$self->{item}{$key}}, [ $val, $type||0];
	$self->{edited}=1;
	return 1;
}
sub edit
{	my ($self,$key,$nb,$val,$type)=@_;
	$key= $self->{realkey}{lc$key};
	return unless defined $key && $self->{item}{$key}[$nb];
	$self->{item}{$key}[$nb][0]=$val;
	$self->{item}{$key}[$nb][1]=$type if defined $type;
	$self->{edited}=1;
	return 1;
}
sub remove
{	my ($self,$key,$nb)=@_;
	$key= $self->{realkey}{lc$key};
	return unless defined $key && $self->{item}{$key}[$nb];
	$self->{item}{$key}[$nb]=undef;
	$self->{edited}=1;
	return 1;
}
sub remove_all
{	my ($self,$key)=@_;
	$key= delete $self->{realkey}{lc$key};
	if (defined $key)
	{	delete $self->{item}{$key};
		$self->{edited}=1;
	}
	return 1;
}

sub get_keys
{	keys %{ $_[0]{realkey} };
}
sub get_values
{	my ($self,$key)=@_;
	$key= $self->{realkey}{lc$key} || $key;
	my $v= $self->{item}{$key};
	return $v ? (map $_->[0],grep defined, @$v) : ();
}
sub is_binary
{	my ($self,$key,$nb)=@_;
	$key= $self->{realkey}{lc$key} || $key;
	return unless defined $key && defined $nb;
	my $ref= $self->{item}{$key}[$nb];
	return $ref ? $ref->[1]&0b10 : undef;
}

sub make
{	my $tag=shift;
	my $tagstring='';
	my $nb=0;
	for my $key (values %{ $tag->{realkey} })
	{	my $values_types= $tag->{item}{$key};
		next unless $values_types;
		my @towrite;
		for my $vt (@$values_types)
		{	my ($value,$type)= @$vt;
			next unless defined $value;
			$type||=0;
			unless ($type & 0b10) 	#if not binary
			{	$value=encode('utf8',$value);
				my ($prev)= grep $_->[1]==$type, @towrite;	#previous one with same type
				if ($prev) { $prev->[2].= "\x00".$value; next }	#append value to previous
			}
			push @towrite,[$key,$type,$value];
		}
		for my $w (@towrite)
		{	my ($key,$type,$value)=@$w;
			$tagstring.=pack('VV',length($value),$type).$key."\x00".$value;
			$nb++;
		}
	}
	if ($nb)
	{	my $length= 32 + length $tagstring;
		my $header= 'APETAGEX'.pack('VVVVx8', 2000, $length, $nb, 0xa0000000);
		my $footer= 'APETAGEX'.pack('VVVVx8', 2000, $length, $nb, 0x80000000);
		$tagstring= $header.$tagstring.$footer;
	}
	return \$tagstring;
}

package Tag::ID3v2;
use Encode qw(decode encode);

my %FRAMES; my %FRAME_OLD; my %Special;
my $Zlib;

INIT
{
eval { require Compress::Zlib; };
$Zlib=1 unless $@;

  %FRAMES=(
generic_text => 'eT',
generic_url => 'eT',
unknown => 'u',
#text => 'eT',
TXXX =>	'eTM',
WXXX =>	'eTt',
UFID =>	'tb',
MCDI =>	'b',
USLT =>	'elTM',
COMM =>	'elTM',
APIC =>	'etCTb',
GEOB =>	'etTTb',
PCNT =>	'c',
POPM =>	'tCc',
USER =>	'elT',
OWNE =>	'ettT',
PRIV =>	'tb',
WCOM =>	't',
WCOP =>	't',
WOAF =>	't',
WOAR =>	't',
WOAS =>	't',
WORS =>	't',
WPAY =>	't',
WPUB =>	't',
TALB =>	'eT',
TBPM =>	'eT',
TCOM =>	'eT',
TCON =>	'eT*',	#remplacer (\d+) et (RX) (CR)
TCOP =>	'eT',
TDLY =>	'eT', #[0-9]+
TENC =>	'eT',
TEXT =>	'eT',
TFLT =>	'eT',	#special
TIT1 =>	'eT',
TIT2 =>	'eT',
TIT3 =>	'eT',
TKEY =>	'eT',
TLAN =>	'eT*',	#remplacer ([A-Z]{3}) par ISO-639-2
TLEN =>	'eT',
TMED =>	'eT',	#special
TOAL =>	'eT',
TOFN =>	'eT',
TOLY =>	'eT',
TOPE =>	'eT',
TOWN =>	'eT',
TPE1 =>	'eT',
TPE2 =>	'eT',
TPE3 =>	'eT',
TPE4 =>	'eT',
TPOS =>	'eT',	#numeric(/numeric)
TPUB =>	'eT',
TRCK =>	'eT',	#numeric(/numeric)
TRSN =>	'eT',
TRSO =>	'eT',
TSRC =>	'eT',	#(12char) ignore
TSSE =>	'eT',
ETCO =>	'u',
MLLT =>	'u',
SYTC =>	'u',
SYLT =>	'u',
RVRB =>	'u',
RBUF =>	'u',
AENC =>	'u',
LINK =>	'u',
POSS =>	'u',
COMR =>	'u',
ENCR =>	'u',
GRID =>	'u',

# deprecated in v4
TSIZ =>	'eT',
TDAT =>	'eT',
TIME =>	'eT', #HHMM
TRDA =>	'eT', #DDMM
TYER =>	'eT', #YYYY
TORY =>	'eT',
IPLS =>	'eT',
RVAD =>	'u',
EQUA =>	'u',

#only v4
TDRC =>	'eT',
TDOR =>	'eT',
TSST =>	'eT',
TMOO =>	'eT',
TPRO =>	'eT',
TDEN =>	'eT',
TDRL =>	'eT',
TDTG =>	'eT',
TSOA =>	'eT',
TSOP =>	'eT',
TSOT =>	'eT',
TMCL =>	'eT', #(par paires)
TIPL =>	'eT', #(par paires)
RVA2 =>	'u',
EQU2 =>	'u',
SIGN =>	'u',
SEEK =>	'u',
ASPI =>	'u',

#iTunes frames
TCMP => 'eT',	#compilation flag
TSO2 => 'eT',	#Album Artist Sort
TSOC => 'eT',	#Composer Sort

#unconverted id3v2
#XCRM => 'ttb',#CRM
);

  # http://www.unixgods.org/~tilo/ID3/docs/ID3_comparison.html
  %FRAME_OLD=
  (	TT1 => 'TIT1', TT2 => 'TIT2', TT3 => 'TIT3',
	TP1 => 'TPE1', TP2 => 'TPE2', TP3 => 'TPE3', TP4 => 'TPE4',
	TCM => 'TCOM', TXT => 'TEXT', TLA => 'TLAN', TCO => 'TCON',
	TAL => 'TALB', TRK => 'TRCK', TPA => 'TPOS', TRC => 'TSRC',
	TDA => 'TDAT', TYE => 'TYER', TIM => 'TIME', TRD => 'TRDA',
	TOR => 'TORY', TBP => 'TBPM', TMT => 'TMED', TFT => 'TFLT',
	TCR => 'TCOP', TPB => 'TPUB', TEN => 'TENC', TSS => 'TSSE',
	TLE => 'TLEN', TSI => 'TSIZ', TDY => 'TDLY', TKE => 'TKEY',
	TOT => 'TOAL', TOF => 'TOFN', TOA => 'TOPE', TOL => 'TOLY',
	TXX => 'TXXX', WAF => 'WOAF', WAR => 'WOAR', WAS => 'WOAS',
	WCM => 'WCOM', WCP => 'WCOP', WPB => 'WPUB', IPL => 'IPLS',
	ULT => 'USLT', COM => 'COMM', UFI => 'UFID', MCI => 'MCID',
	ETC => 'ETCO', MLL => 'MLLT', STC => 'SYTC', SLT => 'SYLT',
	RVA => 'RVAD', EQU => 'EQUA', REV => 'RVRB', PIC => 'APIC',
	GEO => 'GEOB', CNT => 'PCNT', POP => 'POPM', BUF => 'RBUF',
	CRA => 'AENC', LNK => 'LINK',
  );

  %Special=
  (	TCON => \&_genreid,
  );
}

sub new
{	my ($class,$file)=@_;
	my $self={ frames => {}, framesorder => [], edited => 1 };
	unshift @{ $file->{tags_before} },$self;
	$self->{version}=$::Options{'TAG_write_id3v2.4'}? 4 : 3;
	$file->{ID3v2}=$self;
	return bless($self,$class);
}

sub new_from_file
{	my ($class,$file,$isfooter)=@_;warn "new : @_\n" if $::debug;
	my $fh=$file->{fileHandle};
	my %tag;
	#$tag{offset}=shift;
	#seek $fh,$tag{offset},0;
	#read $fh,$_,10;
	if ($isfooter)	{ seek $fh,$file->{endaudio}-10,0;   }
	else		{ seek $fh,$file->{startaudio} ,0; }
	read $fh,my($headorfoot),10;
	my ($id,$v1,$v2,$flags,$size)=unpack 'a3 CCC a4',$headorfoot;
	#FIXME check sane values
	# $49 44 33 yy yy xx zz zz zz zz
	# Where yy is less than $FF, xx is the 'flags' byte and zz is less than  $80
	if ($v1>4) {warn "Unsupported version ID3v2.$v1.$v2 -> skipped\n"; return undef;}
	$tag{version}= $v1 . ($v2 ? ".$v2" : '');
	$tag{size}=10+($size=_decodesyncsafe($size));
	my $footorhead;
	if	($id eq '3DI')
	{	seek $fh,-$size-20,1;	#id3v2.4 footer -> seek to begining of tag
		read $fh,$footorhead,10;	#read header
	}
	elsif	($id ne 'ID3')
	{	return undef;
	}
	my $rawtag;
	read $fh,$rawtag,$size;
	if ($flags & 0b00010000)	#footer present
	{	substr($headorfoot,0,3)=reverse $id;
		read $fh,$footorhead,10 unless $footorhead;	#read footer
		return undef unless $footorhead eq $headorfoot;
		$tag{footer}=1;
		$tag{size}+=10;
	}
	warn "ID3v2.$v1.$v2 : ".$tag{size}." bytes\n" if $::debug;

	if ($flags & 0b10000000)	#unsynchronisation
	{	warn "unsynchronisation\n" if $::debug;
		$rawtag=~s/\xff\x00/\xff/g if $v1<4;
		$tag{unsync}=1;
	}
	if ($flags & 0b01000000)	#Extended header	#currently unused & untested
	{	return undef if $v1==2;	#means compressed tag -> ignore
		warn "extended header\n" if $::debug;
		my $extsize=substr $rawtag,0,4,'';
		$extsize=($v1==4)? _decodesyncsafe($extsize)-4
				 : unpack 'N',$extsize;
		my $extheader=substr $rawtag,0,$extsize,'';
		if ($v1==3)
		{	my ($f,$padsize,$crc)=unpack 'C2VV',$extheader; #CHECKME V or N
			$tag{crc}=$crc if $f & 0x8000;
			warn "padding $padsize\n" if $::debug;
			#FIXME use remove padding
			#substr $rawtag,-$padsize,$padsize,''; #CHECKME find a file who has $padding
		}
		elsif ($v1==4)
		{	my ($pos,$f)=unpack 'CC',$extheader;
			$pos++;
			if ($f & 0b01000000)	 #update (ignored)	#FIXME considered a new tag for now
			{	$tag{update}=1;
				$pos++; warn "v2.4 update\n" if $::debug;
			}
			if ($f & 0b00100000)	#crc (ignored)
			{	$tag{crc}=_decodesyncsafe(substr $extheader,++$pos,5);
				$pos+=5; warn "v2.4 crc\n" if $::debug;
			}
			if ($f & 0b00010000)	#restrictions (ignored)
			{	$tag{restrictions}=vec $extheader,++$pos,8;
				$pos++; warn "v2.4 restrictions\n" if $::debug;
			}
		}
	}
	# done reading tag header
	my $broken24=0;
	my $pos=0;
	my $maxpos=length($rawtag)-( ($v1==2)? 6 : 10 );
	# for each frame :
	while ( $pos < $maxpos )
	{	my ($frame,$fsize,$f1,$f2);
		my $convertsub;
		warn "........padding\n" if $::debug && (substr($rawtag,$pos,1) eq "\x00"); #DEBUG
		last if substr($rawtag,$pos,1) eq "\x00";	#reached padding
		if ($v1==2)	#v2.2
		{	($frame,$fsize,my @size)=unpack 'a3CCC',substr $rawtag,$pos,6;
			$pos+=6;
			$fsize=($fsize<<8)+$_ for @size;
			$convertsub=\&_ConvertPIC if $frame eq 'PIC';
			$frame=$FRAME_OLD{$frame} || 'X'.$frame;
		}
		else	#v2.3 and v2.4
		{	($frame,$fsize,$f1,$f2)=unpack 'a4a4CC',substr $rawtag,$pos,10;
			#warn " $frame,$fsize,$f1,$f2\n";
			$pos+=10;
			$fsize=($v1==4 && !($broken24&1))	? _decodesyncsafe($fsize)
								: unpack 'N',$fsize;
		}
		my $error;
		unless ($frame=~m/^[A-Z0-9]+$/)		# check if valid frameID
		{	if ($frame=~m/^[A-Za-z0-9 ]+$/)
			{	warn "Invalid frameID '$frame' (lowercase and/or space)\n";
			}
			else
			{	$error="Invalid frameID found";
			}
		}
		if (!$error && length($rawtag) < $fsize+$pos)	#end of tag
		{	$error="End of tag reached prematurely while reading frame $frame";
		}
		if ($error)
		{	my $erroraction="skipping rest of tag";
			if ($v1!=4) { warn "$error -> $erroraction\n";last }
			if ($broken24<3)
			{	$broken24++;
				warn "$error, trying broken id3v2.4 mode$broken24\n";
				$pos=0;
				$tag{brokenframes}=delete $tag{frames};
				$tag{brokenframesorder}=delete $tag{framesorder};
				if ($tag{unsync}) {$rawtag=~s/\xff\x00/\xff/g if $broken24==2;}
				else {$broken24=3}
				next;
			}
			else
			{	warn "$error -> $erroraction\n";
				if ( @{$tag{brokenframesorder}} >= @{$tag{framesorder}} ) #keep the best
				{	$tag{frames}=delete $tag{brokenframes};
					$tag{framesorder}=delete $tag{brokenframesorder};
				}
				last;
			}
		}
		#Read frame
		warn "$frame ($fsize bytes)\n" if $::debug;
		my $rawf=substr $rawtag,$pos,$fsize;
		#warn unpack('H*',$rawf)."\n"; #DEBUG
		$pos+=$fsize;
		if ($v1==3)	#frame flags v2.3
		{ if ($f2 & 0b10000000)
		  {	warn "Frame $frame is compressed\n" if $::debug;
			my $unc_size=unpack 'N',$rawf;
			unless ($Zlib) {warn "Compressed frame $frame can't be read because Compress::Zlib is not found.\n";next;}
			$rawf = Compress::Zlib::uncompress( substr($rawf,4) );
			unless (defined $rawf) {warn "frame decompression failed\n"; next};
			warn "$frame: Wrong size of uncompressed data\n" if $unc_size =! length($rawf);
		  }
		  if ($f2 & 0b1000000)	#Encryption
		  {	#my $e=substr $rawf,0,1,'';
			warn "Frame $frame is encrypted, unsupported -> skipped\n";
			next;
		  }
		  if ($f2 & 0b100000)  #Grouping identity
		  {	warn "frame $frame has Grouping identity\n" if $::debug;
			my $g=substr $rawf,0,1,'';	#FIXME unused
		  }
		}
		elsif ($v1==4)	#frame flags v2.4
		{ if ($f2 & 0b1)	#Data length indicator
		  {	my $size=unpack 'N',$rawf; #not used
			warn "v2.4 Data length indicator : frame Data length=$size\n" if $::debug;
			$rawf=substr $rawf,4;
		  }
		  if (($f2 & 0b10) || $tag{unsync} && !($broken24&1))	#Unsynchronisation
		  {	$rawf=~s/\xff\x00/\xff/g;
			warn "v2.4 frame unsync\n" if $::debug;
		  }
		  if ($f2 & 0b1000)
		  {	warn "Frame $frame is compressed\n" if $::debug;
			unless ($Zlib) {warn "Compressed frame $frame can't be read because Compress::Zlib is not found.\n";next;}
			my $unc_rawf=Compress::Zlib::uncompress($rawf);
			$unc_rawf=Compress::Zlib::uncompress( substr($rawf,4) ) unless defined $unc_rawf; #try to decompress frames which include undeclared Data length indicator (like in v2.3)
			unless (defined $unc_rawf) {warn "frame decompression failed\n"; next};
			$rawf=$unc_rawf;
			warn 'decompressed frame size = '.length($rawf)." bytes\n" if $::debug;
		  }
		  if ($f2 & 0b100)	#Encryption
		  {	warn "Frame $frame is encrypted, unsupported -> skipped\n";
			next;
		  }
		  if ($f2 & 0b1000000)	  #Grouping identity
		  {	warn "frame $frame has Grouping identity\n" if $::debug;
		  }
		}
		$convertsub->(\$rawf) if $convertsub;
		my @data;
		my $type= exists $FRAMES{$frame} ?	$frame	 :
			  $frame=~m/^T[A-Z]+$/	 ?	'generic_text':
			  $frame=~m/^W[A-Z]+$/	 ?	'generic_url' :
							'unknown';
		my $fields=$FRAMES{$type};
		my ($encoding,$regex_T);
		my $joker=$fields=~s/\*$//;
		for my $t (split //, $fields)
		{	if ($t eq 'e')		#encoding for T and M
			{	my $e=ord substr $rawf,0,1,'';
				if ($e>$#encodings) { warn "unknown encoding ($e)\n"; $e=0; }
				($encoding,undef,$regex_T)=@{ $encodings[$e] };
			}
			elsif ($t eq 't')	#text
			{	$rawf=~s/$regex_t//;
				push @data,decode('iso-8859-1',$1);
			}
			elsif ($t eq 'T')	#text
			{	$joker=0 unless $rawf=~s/$regex_T//;
				my $text=eval {decode($encoding,$1)};
				if ($@) {warn $@;$text=''} #happens if no BOM in utf16
				#$text=~s/\n/ /g;	#is it needed ?
				$text=~s/\s+$//;
				push @data,$text;
			}
			elsif ($t eq 'M')	#multi-line text
			{	$rawf=~s/$regex_T//;
				my $text=eval {decode($encoding,$1)};
				if ($@) {warn $@;$text=''}
				$text=~s/\s+$//;
				push @data,$text;
			}
			elsif ($t eq 'l')	#language code
			{	push @data,substr $rawf,0,3,'';
			}
			elsif ($t eq 'C')	#char value
			{	push @data, ord(substr $rawf,0,1,'');
			}
			elsif ($t eq 'c')	#counter	#must be last field
			{	my ($c,@bytes)=unpack 'C*',$rawf;
				$c=($c<<8)+$_ for @bytes;
				push @data,$c;
			}
			else	#elsif ($t eq 'b' || $t eq 'u')	#binary	or unknown	#must be last field
			{ push @data,$rawf; }
			#warn "-- $frame -- $t ".($debug_pos-length($rawf))." bytes\n";	#DEBUG
			redo if ($joker &&  $t ne 'e' && length($rawf)>0);
		}
		$Special{$frame}(\@data,$v1) if $Special{$frame};
		if ($joker)
		{	for (@data)
			{	push @{ $tag{frames}{$frame} },$_;
				push @{ $tag{framesorder} },$frame;
			}
		}
		else
		{	push @{ $tag{frames}{$frame} },  @data>1 ? \@data : $data[0];
			push @{ $tag{framesorder} },$frame;
		}
	}
	if ($file->{ID3v2}) { push @{ $file->{ID3v2s} },\%tag;  warn "found another ID3v2 tag\n"; }
	else		    { $file->{ID3v2}=\%tag; }	#the first found is the main tag
	return bless(\%tag,$class);
}
sub removetag {	$_[0]{deleted}=1; }
sub add
{	my ($self,$fname,$data)=@_;
	($fname,$data)=_prepare_data($fname,$data);
	unless ($fname)	{ warn "Invalid frame\n"; return; }
	push @{ $self->{frames}{$fname} },$data;
	push @{ $self->{framesorder} },$fname;
	$self->{edited}=1;
	return 1;
}
sub insert	#same as add but put it first (of its kind)
{	my ($self,$fname,$data)=@_;
	($fname,$data)=_prepare_data($fname,$data);
	unless ($fname)	{ warn "Invalid frame\n"; return; }
	return unless $fname;
	unshift @{ $self->{frames}{$fname} },$data;
	push @{ $self->{framesorder} }, $fname;
	$self->{edited}=1;
	return 1;
}
sub edit
{	my ($self,$fname,$nb,$data)=@_;
	($fname,$data)=_prepare_data($fname,$data);
	return unless $fname;
	unless (defined $self->{frames}{$fname}[$nb])	{ warn "Frame doesn't exist\n"; return; }
	$self->{frames}{$fname}[$nb]=$data;
	$self->{edited}=1;
	return 1;
}
sub remove
{	my ($self,$fname,$nb)=@_;
	unless (defined $self->{frames}{$fname}[$nb])	{ warn "Frame doesn't exist\n"; return; }
	$self->{frames}{$fname}[$nb]=undef;
	$self->{edited}=1;
	return 1;
}
sub remove_all
{	my ($self,$fname)=@_;
	($fname,my @extra)=split /;/,$fname,-1; #-1 to keep empty trailing fields #COMM;;%v; => key="COMM" and @extra=("","%v","")
	my $ref=$self->{frames}{$fname};
	return unless $ref;
	my @toremove;
	if (@extra)
	{	for my $i (0..$#$ref)
		{	next unless $ref->[$i];
			my $keep;
			for my $j (0..$#extra)
			{	my $extra= $extra[$j];
				next if $extra eq '%v' || $extra eq '';
				$keep=1 if $extra ne $ref->[$i][$j];
			}
			push @toremove,$i unless $keep;
		}
	}
	else { @toremove= 0..$#$ref; }
	$ref->[$_]=undef for @toremove;
	$self->{edited}=1 if @toremove;
	return 1;
}

sub get_keys
{	keys %{ $_[0]{frames} };
}
sub get_values
{	my ($self,$key)=@_;
	($key,my @extra)= split /;/,$key,-1;  #-1 to keep empty trailing fields
	my $v= $self->{frames}{$key};
	return unless $v;
	my @values= grep defined, @$v;
	return unless @values;
	if (@extra && ref $v->[0]) #for multi fields (COMM for example)
	{	@values= map
		 {	my $v_ok; my $notok;
			for my $j (0..$#extra)
			{	my $p=$extra[$j];
				my $vj=$_->[$j];
				if ($p eq '%v') { $v_ok=$vj; }
				elsif ($p ne '' && $p ne $vj) {$notok=1;last}
			}
			$notok ? () : ($v_ok);
		 } @values;
	}
	return @values;
}

sub make
{	my $tag=shift;
	my $v1=$::Options{'TAG_write_id3v2.4'}? 4 : 3;
	if ($::Options{'TAG_keep_id3v2_ver'} && $tag->{version}=~m/^([34])\./) { $v1=$1; }
	my $check=$::Options{'TAG_use_latin1_if_possible'}? 1 : 0;
	my $def_encoding=($v1==4)? 3 : 1;	#use utf8 for v2.4, utf16 for v2.3
	my $tagstring='';
	my %framecount;
	my $unsync24all;
	for my $frameid ( @{ $tag->{framesorder} } )
	{	my $data=$tag->{frames}{$frameid}[ $framecount{$frameid}++ ];
		next unless defined $data;
		my $framestring;
		my $type= exists $FRAMES{$frameid}		?	$frameid :
			  $frameid=~m/^T[A-Z]+$/		?	'generic_text'	 :
			  $frameid=~m/^W[A-Z]+$/		?	'generic_url'	 :
									'unknown';
		my @fields=split //,$FRAMES{$type};
		if ($fields[-1] eq '*')
		{	pop @fields;
			if ($v1==4)	#put all values in the same frame
			{	next if $framecount{$frameid}>1;
				$data= [grep defined, @{$tag->{frames}{$frameid}}];
				push @fields,($fields[-1]) x $#$data;
			}
		}
		my ($encoding,$term);
		$data=[$data] unless ref $data;
		my $datai=0;
		for my $t (@fields)
		{	if ($t eq 'e')		#encoding for T and M
			{	#check if strings to be encoded use 8th bit
				use bytes;
				if ($check && !(grep $fields[$_]=~m/[TM]/ && $data->[$_-1]=~m/[\x80-\xff]/, 1..$#fields))
				{	#use iso-8859-1 encoding if 8th bit not used
					$framestring.="\x00";
					($encoding,$term)=@{$encodings[0]};
				}
				else	#use def_encoding
				{	$framestring.=chr $def_encoding;
					($encoding,$term)=@{ $encodings[$def_encoding] };
				}
				next;
			}
			my $val=$data->[$datai++];
			if ($t eq 't')		#text
			{	$val=~s#\n+# #g;
				$framestring.=encode('iso-8859-1',$val)."\x00";
			}
			elsif ($t eq 'T')	#text
			{	$val=~s#\n+# #g;
				$framestring.=encode($encoding,$val).$term;
			}
			elsif ($t eq 'M')	#multi-line text
			{	$framestring.=encode($encoding,$val).$term;
			}
			elsif ($t eq 'l')	#language code
			{	$framestring.=pack 'a3', encode('iso-8859-1',$val);
			}
			elsif ($t eq 'C')	#char value
			{	$val||=0;
				$val=255 if $val>255;
				$framestring.=chr $val;
			}
			elsif ($t eq 'c')	#counter
			{	my $string;
				while ($val>256) { $string.=chr($val&0xff); $val>>=8; }
				$string.=chr($val).("\x00"x(3-length $string)); #must be at least 4 bytes
				$framestring.=reverse $string;
			}
			else	#elsif ($t eq 'b' || $t eq 'u')	#binary or unknown
			{ $framestring.=$val; }
			#FIXME call special case sub
			#warn "-- $frameid -- $t framepos=".length($framestring)."\n";	#DEBUG
		}
		my $ffflag=0;
		unless ($::Options{TAG_no_desync} || $v1<4)
		{	my $size=length $framestring;
			if ($tagstring=~s/\xFF(?=[\x00\xE0-\xFF])/\xFF\x00/g)
			{	$ffflag|=0b11;
				$size=_encodesyncsafe(4,$size);
				$framestring=$size.$framestring;
				$unsync24all=1 unless defined $unsync24all;
			}
			else {$unsync24all=0}
		}
		my $fsize=length $framestring;
		$fsize=($v1==4)? _encodesyncsafe(4,$fsize) : pack('N',$fsize);
		$tagstring.=$frameid.$fsize."\x00".chr($ffflag).$framestring;
		#warn "-- $frameid 10+".length($framestring)." bytes added tagpos=".length($tagstring)."\n";	#DEBUG
	}
	my $flag=0;
	#warn "==tag ".length($tagstring)." bytes before unsync\n";	#DEBUG
	unless ($::Options{TAG_no_desync} || $v1>3)
	{ $flag|=0b10000000 if $tagstring=~s/\xFF(?=[\x00\xE0-\xFF])/\xFF\x00/g; }
	$flag|=0b10000000 if $unsync24all;
	$tagstring.="\x00" if substr($tagstring,-1,1) eq "\xff";	#1-byte padding to avoid false sync
	#warn "==tag ".length($tagstring)." bytes after unsync (flag=$flag)\n";	#DEBUG
	$tagstring="ID3".chr($v1)."\x00".chr($flag)._encodesyncsafe(4, length($tagstring) ).$tagstring;
	return \$tagstring;
}
sub _SetPadding
{	my ($stringref,$padding)=@_;
	substr($$stringref,6,4)= _encodesyncsafe(4, length($$stringref)+$padding-10 );
	$$stringref.=("\x00"x$padding);
}

sub get_fieldtypes
{	my $frameid=shift;
	my $type= exists $FRAMES{$frameid}		?	$frameid :
		  $frameid=~m/^T[A-Z]+$/		?	'generic_text'	 :
		  $frameid=~m/^W[A-Z]+$/		?	'generic_url'	 :
								'unknown';
	$type= $FRAMES{$type};
	$type=~s/^e//;
	$type=~s/\*$//;
	return $type;
}

sub _encodesyncsafe
{	my ($bytes,$int)=@_;
	my @result;
	while ($bytes--)
	{	unshift @result,chr($int & 0x7f);
		$int>>=7;
	}
	die "integer too big : $_[1]\n" if $int>0; #FIXME when >256MB
	return join('',@result);
}
sub _decodesyncsafe
{	my ($int,@bytes)=unpack 'C*',$_[0];
	$int=($int<<7)+$_ for @bytes;
	return $int;
}

sub _prepare_data
{	my ($fname,$data)=@_;
	($fname,my @extra)=split /;/,$fname,-1;
	if ($fname!~m/^[A-Z0-9]{4}$/) { warn "Invalid id3v2 frameID '$fname', ignoring\n"; return }
	if (@extra && !ref $data)
	{	$data= [ map {$_ eq '%v' ? $data : $_} @extra ];
	}
	my $type=get_fieldtypes($fname);
	my $n= ref $data ? scalar @$data : 1;
	if (length($type) != $n)
	{	warn "Not the right number of subtags for this frame ($fname $n)\n";
		return;
	}
	return $fname, $data;
}

sub _ConvertPIC
{	my $raw=$_[0];
	my $type=uc substr($$raw,1,3);
	if    ($type eq 'PNG')	{ $type='image/png';  }
	elsif ($type eq 'JPG')	{ $type='image/jpeg'; }
	else			{ $type=~s/[ \x00]//g;}
	substr($$raw,1,3)=$type."\x00";
}

sub _genreid	#to convert TCON from id3v2.3 (and from id3v2.2) to id3v2.4
{  my ($ref,$version)=@_;
   if ($version!=4)		# -> convert to list
   {	local $_=$ref->[0];
   	@$ref=();
   	while (s#^\(([\d]+|RX|CR)\)##)
   	{	push @$ref,$1;
   	}
   	s#^\(\(#\(#;
   	push @$ref,$_ if $_ ne '';
   }
   for (@$ref)
   {	$_=$Genres[$_] if m#^(\d+)$# && $_<@Genres;
	s/^\(RX\)$/Remix/;
	s/^\(CR\)$/Cover/;
   }
}



1;
__END__

AAAAAAAA AAABBCCD EEEEFFGH IIJJKLMM
A frame sync =1
B MPEG Audio version ID
C Layer description
D Protection bit

E Bitrate index
F Sampling rate frequency index
G Padding bit
H Private bit

I Channel Mode
J Mode extension (Only if Joint stereo)
K Copyright
L Original
M Emphasis

