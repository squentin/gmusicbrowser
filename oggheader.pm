# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

#http://xiph.org/vorbis/doc/framing.html
#http://xiph.org/vorbis/doc/v-comment.html

package Tag::OGG;

use strict;
use warnings;
use Encode qw(decode encode);
use MIME::Base64;

use constant
{ PACKET_INFO	 => 1,
  PACKET_COMMENT => 3,
  PACKET_SETUP	 => 5,
};

my @crc_lookup;
my $digestcrc;
INIT
{ eval
  {	require Digest::CRC;
	$digestcrc=Digest::CRC->new(width=>32, init=>0, xorout=>0, poly=>0x04C11DB7, refin=>0, refout=>0);
	warn "oggheader.pm : using Digest::CRC\n" if $::debug;
  };
  if ($@)
  { warn "oggheader.pm : Digest::CRC not found, using slow pure-perl replacement.\n" if $::debug;
    @crc_lookup=
 (0x00000000,0x04c11db7,0x09823b6e,0x0d4326d9,
  0x130476dc,0x17c56b6b,0x1a864db2,0x1e475005,
  0x2608edb8,0x22c9f00f,0x2f8ad6d6,0x2b4bcb61,
  0x350c9b64,0x31cd86d3,0x3c8ea00a,0x384fbdbd,
  0x4c11db70,0x48d0c6c7,0x4593e01e,0x4152fda9,
  0x5f15adac,0x5bd4b01b,0x569796c2,0x52568b75,
  0x6a1936c8,0x6ed82b7f,0x639b0da6,0x675a1011,
  0x791d4014,0x7ddc5da3,0x709f7b7a,0x745e66cd,
  0x9823b6e0,0x9ce2ab57,0x91a18d8e,0x95609039,
  0x8b27c03c,0x8fe6dd8b,0x82a5fb52,0x8664e6e5,
  0xbe2b5b58,0xbaea46ef,0xb7a96036,0xb3687d81,
  0xad2f2d84,0xa9ee3033,0xa4ad16ea,0xa06c0b5d,
  0xd4326d90,0xd0f37027,0xddb056fe,0xd9714b49,
  0xc7361b4c,0xc3f706fb,0xceb42022,0xca753d95,
  0xf23a8028,0xf6fb9d9f,0xfbb8bb46,0xff79a6f1,
  0xe13ef6f4,0xe5ffeb43,0xe8bccd9a,0xec7dd02d,
  0x34867077,0x30476dc0,0x3d044b19,0x39c556ae,
  0x278206ab,0x23431b1c,0x2e003dc5,0x2ac12072,
  0x128e9dcf,0x164f8078,0x1b0ca6a1,0x1fcdbb16,
  0x018aeb13,0x054bf6a4,0x0808d07d,0x0cc9cdca,
  0x7897ab07,0x7c56b6b0,0x71159069,0x75d48dde,
  0x6b93dddb,0x6f52c06c,0x6211e6b5,0x66d0fb02,
  0x5e9f46bf,0x5a5e5b08,0x571d7dd1,0x53dc6066,
  0x4d9b3063,0x495a2dd4,0x44190b0d,0x40d816ba,
  0xaca5c697,0xa864db20,0xa527fdf9,0xa1e6e04e,
  0xbfa1b04b,0xbb60adfc,0xb6238b25,0xb2e29692,
  0x8aad2b2f,0x8e6c3698,0x832f1041,0x87ee0df6,
  0x99a95df3,0x9d684044,0x902b669d,0x94ea7b2a,
  0xe0b41de7,0xe4750050,0xe9362689,0xedf73b3e,
  0xf3b06b3b,0xf771768c,0xfa325055,0xfef34de2,
  0xc6bcf05f,0xc27dede8,0xcf3ecb31,0xcbffd686,
  0xd5b88683,0xd1799b34,0xdc3abded,0xd8fba05a,
  0x690ce0ee,0x6dcdfd59,0x608edb80,0x644fc637,
  0x7a089632,0x7ec98b85,0x738aad5c,0x774bb0eb,
  0x4f040d56,0x4bc510e1,0x46863638,0x42472b8f,
  0x5c007b8a,0x58c1663d,0x558240e4,0x51435d53,
  0x251d3b9e,0x21dc2629,0x2c9f00f0,0x285e1d47,
  0x36194d42,0x32d850f5,0x3f9b762c,0x3b5a6b9b,
  0x0315d626,0x07d4cb91,0x0a97ed48,0x0e56f0ff,
  0x1011a0fa,0x14d0bd4d,0x19939b94,0x1d528623,
  0xf12f560e,0xf5ee4bb9,0xf8ad6d60,0xfc6c70d7,
  0xe22b20d2,0xe6ea3d65,0xeba91bbc,0xef68060b,
  0xd727bbb6,0xd3e6a601,0xdea580d8,0xda649d6f,
  0xc423cd6a,0xc0e2d0dd,0xcda1f604,0xc960ebb3,
  0xbd3e8d7e,0xb9ff90c9,0xb4bcb610,0xb07daba7,
  0xae3afba2,0xaafbe615,0xa7b8c0cc,0xa379dd7b,
  0x9b3660c6,0x9ff77d71,0x92b45ba8,0x9675461f,
  0x8832161a,0x8cf30bad,0x81b02d74,0x857130c3,
  0x5d8a9099,0x594b8d2e,0x5408abf7,0x50c9b640,
  0x4e8ee645,0x4a4ffbf2,0x470cdd2b,0x43cdc09c,
  0x7b827d21,0x7f436096,0x7200464f,0x76c15bf8,
  0x68860bfd,0x6c47164a,0x61043093,0x65c52d24,
  0x119b4be9,0x155a565e,0x18197087,0x1cd86d30,
  0x029f3d35,0x065e2082,0x0b1d065b,0x0fdc1bec,
  0x3793a651,0x3352bbe6,0x3e119d3f,0x3ad08088,
  0x2497d08d,0x2056cd3a,0x2d15ebe3,0x29d4f654,
  0xc5a92679,0xc1683bce,0xcc2b1d17,0xc8ea00a0,
  0xd6ad50a5,0xd26c4d12,0xdf2f6bcb,0xdbee767c,
  0xe3a1cbc1,0xe760d676,0xea23f0af,0xeee2ed18,
  0xf0a5bd1d,0xf464a0aa,0xf9278673,0xfde69bc4,
  0x89b8fd09,0x8d79e0be,0x803ac667,0x84fbdbd0,
  0x9abc8bd5,0x9e7d9662,0x933eb0bb,0x97ffad0c,
  0xafb010b1,0xab710d06,0xa6322bdf,0xa2f33668,
  0xbcb4666d,0xb8757bda,0xb5365d03,0xb1f740b4
 );}
}

#hash fields :
# filename
# fileHandle
# serial	serial number (binary 4 bytes)
# seg_table	segmentation table of last read page
# granule	granule of last read page
# info		-> hash containing : version channels rate bitrate_upper bitrate_nominal bitrate_lower seconds
# comments	-> hash of arrays (lowercase keys)
# CommentsOrder -> list of keys (mixed-case keys)
# commentpack_size
# vorbis_string
# stream_vers
# end


sub new
{   my ($class,$file)=@_;
    my $self=bless {}, $class;

    # check that the file exists
    unless (-e $file)
    {	warn "File '$file' does not exist.\n";
	return undef;
    }
    $self->{filename} = $file;
    $self->_open or return undef;

    {
    	$self->{info}=_ReadInfo($self);
    	last unless $self->{info};

	$self->{comments}=_ReadComments($self);
    	last unless $self->{comments};

	$self->{end}=_skip_to_last_page($self);
    	_read_packet($self,0) unless $self->{end};
	warn "file truncated or corrupted.\n" unless $self->{end};

	#calulate length
	last unless $self->{info}{rate};# && $self->{end};
	my @granule=unpack 'C*',$self->{granule};
	my $l=0;
	$l=$l*256+$_ for reverse @granule;
	$self->{info}{seconds}=my$s=$l/$self->{info}{rate};
    }

    $self->_close;
    unless ($self->{info} && $self->{comments})
    {	warn "error, can't read file or not a valid ogg file\n";
	return undef;
    }
    return $self;
}

sub _open
{	my $self=shift;
	my $file=$self->{filename};
	open my$fh,'<',$file or warn "can't open $file : $!\n" and return undef;
	binmode $fh;
	$self->{fileHandle} = $fh;
	$self->{seg_table} = [];
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
	unless ($tmp)
	{ $self->{fileHandle} = $fh;
	  $self->{seg_table} = [];
	}
	return $fh;
}

sub _close
{	my $self=shift;
	$self->{seg_table} = undef;
	close delete($self->{fileHandle});
}

sub write_file
{	my $self=shift;
	my $newcom_packref=_PackComments($self);
	#warn "old size $self->{commentpack_size}, need : ".length($$newcom_packref)."\n";
	if ( $self->{commentpack_size} >= length $$newcom_packref)
	{	warn "in place editing.\n";
		my $left=length $$newcom_packref;
		my $offset2=0;
		my $fh=$self->_openw or return;
		_read_packet($self,PACKET_INFO);	#skip first page
		while ($left)
		{ my $pos=tell $fh;
		  my ($pageref,$offset,$size)=_ReadPage($self);
		  seek $fh,$pos,0;
		  if ($left<$size) {$size=$left; $left=0;}
		  else		   {$left-=$size}
		  substr $$pageref,$offset,$size,substr($$newcom_packref,$offset2,$size);
		  $offset2+=$size;
		  _recompute_page_crc($pageref);
		  print $fh $$pageref or warn $!;
		}
		$self->_close;
		return;
	}
	my $INfh=$self->_open or return;
	my $OUTfh=$self->_openw(1) or return;	#open .TEMP file

	my $version=chr $self->{stream_vers};
	my $serial=$self->{serial};
	my $pageref=_ReadPage($self);		#read the first page
	die unless $pageref;	#FIXME check serial, OggS ...
	print $OUTfh $$pageref or warn $!;		#write the first page unmodified
	my $pagenb=1;

	#skip the comment packet in the original file
	die unless _read_packet($self,PACKET_COMMENT);

	#concatenate newly generated comment packet and setup packet from the original file in $data, and compute the segments in @segments
	my $data;
	my @segments;
	for my $packref ( $newcom_packref , _read_packet($self,PACKET_SETUP) )
	{	$data.=$$packref;
		my $size=length $$packref;
		push @segments, (255)x int($size/255), $size%255;
	}

	#separate $data in pages and write them
	my $data_offset=0;
	my $continued=0;
	{	my $size=0;
		my $segments;
		my $nbseg=0;
		my $seg;
		while ($size<4096)		# make page of max 4095+255 bytes
		{	last unless @segments;
			$seg=shift @segments;
			$size+=$seg;
			$segments.=chr $seg;
			$nbseg++;
		}
		#warn unpack('C*',$segments),"\n";
		#warn "$size ",length($data)-$data_offset,"\n";
		warn "writing page $pagenb\n" if $::debug;
		my $page=pack('a4aa x8 a4 V x4 C','OggS',$version,$continued,$serial,$pagenb++,$nbseg).$segments.substr($data,$data_offset,$size);
		_recompute_page_crc(\$page);
		print $OUTfh $page or warn $!;
		$data_offset+=$size;
		$continued=($seg==255)? "\x01" : "\x00";
		redo if @segments;
	}


	# copy AUDIO data

	my $pos=tell $INfh; read $INfh,$data,27; seek $INfh,$pos,0;
	#warn "first audio data on page ".unpack('x18V',$data)."\n";
	# fast raw copy by 1M chunks if page numbers haven't changed
	if ( substr($data,0,4) eq 'OggS' && unpack('x18V',$data) eq $pagenb)
		{ my $buffer;
		  print $OUTfh $buffer  or warn $! while read $INfh,$buffer,1048576;
		}

	# __SLOW__ copy if page number must be changed -> and crc recomputed
	else
	{	warn "must recompute crc for the whole file, this may take a while (install Digest::CRC to make it fast) ...\n" unless $digestcrc;
		while (my $pageref=_ReadPage($self))	# read each page
		{	substr $$pageref,18,4,pack('V',$pagenb++); #replace page number
			_recompute_page_crc($pageref);	#recompute crc
			print $OUTfh $$pageref or warn $!;	#write page
		}
	}

	$self->_close;
	close $OUTfh;
	warn "replacing old file with new file.\n";
	unlink $self->{filename} && rename $self->{filename}.'.TEMP',$self->{filename};
	%$self=(); #destroy the object to make sure it is not reused as many of its data are now invalid
	return 1;
}

sub _ReadPage
{	my $self=shift;
	my $fh=$self->{fileHandle};
	my $page;
	my $r=read $fh,$page,27;			#read page header
	return undef unless $r==27 && substr($page,0,4) eq 'OggS';
	my $segments=vec $page,26,8;
	$r=read $fh,$page,$segments,27;		#read segment table
	return undef unless $r==$segments;
	my $size;
	#$size+=ord substr($page,$_,1) for (27..$segments+26);
	$size+=vec($page,$_,8) for (27..$segments+26);
	$r=read $fh,$page,$size,27+$segments;	#read page data
	return undef unless $r==$size;
	return wantarray ? (\$page,27+$segments,$size) : \$page;
}

sub _ReadInfo
{	my $self=shift;
	#$self->{startaudio}=0;
	# 1) [vorbis_version] = read 32 bits as unsigned integer
	# 2) [audio_channels] = read 8 bit integer as unsigned
	# 3) [audio_sample_rate] = read 32 bits as unsigned integer
	# 4) [bitrate_maximum] = read 32 bits as signed integer
	# 5) [bitrate_nominal] = read 32 bits as signed integer
	# 6) [bitrate_minimum] = read 32 bits as signed integer
	# 7) [blocksize_0] = 2 exponent (read 4 bits as unsigned integer)
	# 8) [blocksize_1] = 2 exponent (read 4 bits as unsigned integer)
	# 9) [framing_flag] = read one bit
	if ( my $packref=_read_packet($self,PACKET_INFO) )
	{	my %info;
		@info{qw/version channels rate bitrate_upper bitrate_nominal bitrate_lower/}= unpack 'x7 VCV V3 C',$$packref;
		return \%info;
	}
	else
	{	warn "Can't read info\n";
		return undef;
	}
}

sub _ReadComments
{	my $self=$_[0];
	if ( my $packref= _read_packet($self,PACKET_COMMENT) )
	{	$self->{commentpack_size}=length $$packref;
		my ($vstring,@comlist)=eval { unpack 'x7 V/a V/(V/a)',$$packref; };
		if ($@) { warn "Comments corrupted\n"; return undef; }
		# Comments vendor strings I have found
		# 'Xiph.Org libVorbis I 20030909' : 1.0.1
		# 'Xiph.Org libVorbis I 20020717' : 1.0 release of libvorbis
		# 'Xiphophorus libVorbis I 200xxxxx' : 1.0_beta1 to 1.0_rc3
		# 'AO; aoTuV b3 [20041120] (based on Xiph.Org's libVorbis)'
		$self->{vorbis_string}=$vstring;
		if ($::debug && $vstring!~m/^Xiph.* libVorbis I (\d{8})/)
		 { warn "unknown comments vendor string : $vstring\n"; }
		my %comments;
		my @order;
		$self->{CommentsOrder}=\@order;
		for my $kv (@comlist)
		{	unless ($kv=~m/^([^=]+)=(.*)$/s) { warn "comment invalid - skipped\n"; next; }
			my $key=$1;
			my $val=decode('utf-8', $2);
			#warn "$key = $val\n";
			push @{ $comments{lc$key} },$val;
			push @order, $key;
		}
		if (my $covers=$comments{coverart})	#upgrade old embedded pictures format to metadata_block_picture
		{	@order= grep !m/^coverart/i, @order;
			for my $i (0..$#$covers)
			{	my $data= $comments{"coverart"}[$i];
				next unless $data;
				my @val= ( map( $comments{"coverart$_"}[$i], qw/mime type description/ ), decode_base64($data) );
				push @{$comments{metadata_block_picture}}, \@val;
				push @order, 'METADATA_BLOCK_PICTURE';
			}
			delete $comments{"coverart$_"} for qw/mime type description/,'';
		}
		return \%comments;
	}
	else
	{	warn "Can't find comments\n";
		return undef;
	}
}
sub _PackComments
{	my $self=$_[0];
	my @comments;
	my %count;
	for my $key ( @{$self->{CommentsOrder}} )
	{	my $nb=$count{lc$key}++ || 0;
		my $val=$self->{comments}{lc$key}[$nb];
		next unless defined $val;
		$key=encode('ascii',$key);
		$key=~tr/\x20-\x7D/?/c; $key=~tr/=/?/; #replace characters that are not allowed by '?'
		if (uc$key eq 'METADATA_BLOCK_PICTURE' && ref $val)
		{	$val= Tag::Flac::_PackPicture($val);
			$val= encode_base64($$val);
		}
		push @comments,$key.'='.encode('utf8',$val);
	}
	my $packet=pack 'Ca6 V/a* V (V/a*)*',PACKET_COMMENT,'vorbis',$self->{vorbis_string},scalar @comments, @comments;
	$packet.="\x01"; #framing_flag
	return \$packet;
}

sub edit
{	my ($self,$key,$nb,$val)=@_;
	$nb||=0;
	my $aref=$self->{comments}{lc$key};
	return unless $aref &&  @$aref >=$nb;
	$aref->[$nb]= $val;
	return 1;
}
sub add
{	my ($self,$key,$val)=@_;
	push @{ $self->{comments}{lc$key} }, $val;
	push @{$self->{CommentsOrder}}, $key;
	return 1;
}
sub insert	#same as add but put it first (of its kind)
{	my ($self,$key,$val)=@_;
	unshift @{ $self->{comments}{lc$key} }, $val;
	push @{$self->{CommentsOrder}}, $key;
	return 1;
}

sub remove_all
{	my ($self,$key)=@_;
	return undef unless defined $key;
	$key=lc$key;
	$_=undef for @{ $self->{comments}{$key} };
	return 1;
}

sub get_keys
{	keys %{ $_[0]{comments} };
}
sub get_values
{	my ($self,$key)=($_[0],lc$_[1]);
	my $v= $self->{comments}{$key};
	return () unless $v;
	if ($key eq 'metadata_block_picture')
	{	for my $val (@$v)
		{	next if ref $val or !defined $val;
			my $dec=decode_base64($val);
			$val= $dec ? Tag::Flac::_ReadPicture(\$dec) : undef;
		}
	}
	return grep defined, @$v;
}

sub remove
{	my ($self,$key,$nb)=@_;
	return undef unless defined $key and $nb=~m/^\d*$/;
	$nb||=0;
	$key=lc$key;
	my $val=$self->{comments}{$key}[$nb];
	unless (defined $val) {warn "comment to delete not found\n"; return undef; }
	$self->{comments}{$key}[$nb]=undef;
	return 1;
}

sub _read_packet
{	my $self=shift;
	my $wantedtype=shift; #wanted type, 0 to read all packets until eof
	my $fh=$self->{fileHandle};
	my $packet;
	do
	{ my $lpacket=0;
	  my $seg_table=$self->{seg_table};
	  my $lastseg;
	  until ($lastseg)
	  {	my $size;
		unless ( @$seg_table ) { _read_page_header($self) || return undef }
		while (defined( my $byte=shift @$seg_table ))
		{	$size+=$byte;
			unless ($byte==255) { $lastseg=1; last; }
		}
		next unless $size;
		my $read=read $fh,$packet,$size,$lpacket;
		return undef unless $size==$read;
		$lpacket+=$read;
	  }

	} until ($wantedtype || $self->{end});
	my ($type,$vorbis)=unpack 'Ca6',$packet;
	warn "read packet : $type $vorbis length=".length($packet)."\n" if $::debug;
	if ( $type==$wantedtype && $vorbis eq 'vorbis')	{ return \$packet; }
	else { return undef; }
}

sub _read_page_header
{	my $self=shift;
	my $fh=$self->{fileHandle};
	my $buf;
	my $r=read $fh,$buf,27;
	return 0 unless $r==27;
	#http://www.xiph.org/ogg/vorbis/doc/framing.html
	# 'OggS' 4 bytes	capture_pattern			0
	# 0x00	 1 byte		stream_structure_version	1
	#	 1 byte		header_type_flag		2
	#	 8 bytes	absolute granule position	3
	#	 4 bytes	stream serial number		4
	#	 4 bytes	page sequence no		5
	#	 4 bytes	page checksum			6
	#	 1 byte		page_segments			7
	#
	#warn "OggS : ".join(' ',unpack('a4CC a8 VVVC',$buf))."\n";
	my ($captpat,$ver,$flags,$granule,$sn,$nbseg)=unpack 'a4CC a8 a4 x8 C',$buf;
	return undef unless $captpat eq 'OggS' and $ver eq 0;
	if ($self->{serial} && $self->{serial} ne $sn) {warn "corrupted page : serial number doesn't match\n";return undef}
	$self->{end}=$flags & 4;
	$self->{serial}=$sn;
	$self->{stream_vers}=$ver;
	$self->{granule}=$granule;
	return undef unless read($fh,$buf,$nbseg)==$nbseg;
	@{ $self->{seg_table} }=unpack 'C*',$buf;
	#warn " seg_table: ".join(' ',@{ $self->{seg_table} })."\n";
	return 1;
}

sub _recompute_page_crc
{ my $pageref=$_[0];

  #warn 'old crc : ',unpack('V',substr($$pageref,22,4)),"\n";
  substr $$pageref,22,4,"\x00\x00\x00\x00";
  my $crc=0;
  if ($digestcrc) { $digestcrc->add($$pageref); $crc=$digestcrc->digest; }
  else			# pure-perl : SLOW
  {	 #$crc=($crc<<8)^vec($crc_lookup, ($crc>>24)^vec($$pageref,$_,8) ,32); # a bit slower
	 #$crc=($crc<<8)^$crc_lookup[ ($crc>>24)^vec($$pageref,$_,8) ] #doesn't work if perl use 64bits
	 $crc=(($crc<<8)&0xffffffff)^$crc_lookup[ ($crc>>24)^vec($$pageref,$_,8) ]
  	for (0 .. length($$pageref)-1);
  }
  #warn "new crc : $crc\n";
  substr $$pageref,22,4,pack('V',$crc);
}

sub _skip_to_last_page
{	my $self=shift;
	my $fh=$self->{fileHandle};
	my $pos=tell $fh;
	seek $fh,-10000,2;
	read $fh,my$buf,10000;
	my $sn=$self->{serial};
	my $granule;
	while ($buf=~m/OggS\x00(.)(.{8})(.{4})/gs)
	{	#@_=unpack "a4CC a8 VVVC",$1;
		next unless $sn eq $3;	#check serial number
		$granule=$2 unless $2 eq "\xff\xff\xff\xff\xff\xff\xff\xff"; #granule==-1 => no packets finish on this page
		next unless vec $1,2,1;	#last page of logical bitstream
		last unless defined $granule;
		# found last page -> save granule
		$self->{granule}=$granule;
		return 1;
	}
	#didn't find last page
	seek $fh,$pos,0;
	return 0;
}

1;
