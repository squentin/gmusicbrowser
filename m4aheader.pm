# Copyright (C) 2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

#based on :
#http://atomicparsley.sourceforge.net/mpeg-4files.html
#http://wiki.multimedia.cx/index.php?title=QuickTime_container
#http://www.geocities.com/xhelmboyx/quicktime/formats/mp4-layout.txt
#
#blame Apple for the absence of official specs for metadata :(

#usage :
#my $tag=Tag::M4A->new(shift);
#if ($tag)
#{	$tag->add(name => 'value');
#	$tag->insert('org.gmusicbrowser----mytag' => 'mytagvalue');
#	$tag->remove_all('disk');
#	$tag->write_file;
#}
#
# uses @Tag::MP3::Genres for numeric genres

package Tag::M4A;
use strict;
use warnings;
use Encode qw(decode encode);

my %IsParent;
INIT
{ $IsParent{$_}=0 for qw/moov trak udta mdia minf stbl ilst moof traf/; # unused parent atoms : tref imap edts mdra rmra imag vnrp dinf
  $IsParent{meta}=4;	#4 bytes version/flags = byte hex version + 24-bit hex flags  (current = 0)
}

sub new
{	my ($class,$file)=@_;
	my $self=bless {}, $class;

	# check that the file exists and is readable
	unless ( -e $file && -r $file )
	{	warn "File '$file' does not exist or cannot be read.\n";
	    return undef;
	}
	$self->{filename} = $file;
	$self->_open or return undef;

	$self->ParseAtomTree;
	$self->_close;

	unless ($self->{info} && $self->{ilst})
	{	warn "error, can't read file or not a valid m4a file\n";
		return undef;
	}
	return $self;
}

sub _open
{	my $self=shift;;
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
		return undef unless $self->{errorsub} && &{ $self->{errorsub} }($err) eq 'yes';
	}
	binmode $fh;
	unless ($tmp)
	{ $self->{fileHandle} = $fh;
	}
	return $fh;
}
sub _close
{	my $self=shift;
	close delete($self->{fileHandle});
}

sub edit
{	my ($self,$key,$nb,@val)=@_;
	$nb||=0;
	my $aref=$self->{ilst}{$key};
	return undef unless $aref &&  @$aref >=$nb;
	my $old=$aref->[$nb];
	if (@val>1 && $key ne $val[1].'----'.$val[2])	#for editing a '----' tag
	{	$self->remove($key,$nb);
		$key= $key=~m/^(Unknown tag with flag=\d+ and key=)/ ? $1 : '';
		$key.=$val[1].'----'.$val[2];
		$self->add($key,@val);
	}
	else { $aref->[$nb]=$val[0]; }
	return $old;
}
sub add
{	my ($self,$key,@val)=@_;
	if (@val>1)	#for adding a '----' tag
	{	$key= $key=~m/^(Unknown tag with flag=\d+ and key=)/ ? $1 : '';
		$key.=$val[1].'----'.$val[2];
	}
	push @{ $self->{ilst}{$key} },$val[0];
	push @{$self->{ilst_order}}, $key;
	return 1;
}
sub insert	#same as add but put it first (of its kind)
{	my ($self,$key,@val)=@_;
	if (@val>1)	#for adding a '----' tag
	{	$key= $key=~m/^(Unknown tag with flag=\d+ and key=)/ ? $1 : '';
		$key.=$val[1].'----'.$val[2];
	}
	unshift @{ $self->{ilst}{$key} },$val[0];
	push @{$self->{ilst_order}}, $key;
	return 1;
}

sub remove_all
{	my ($self,$key)=@_;
	return undef unless defined $key;
	$_=undef for @{ $self->{ilst}{$key} };
	return 1;
}
sub remove
{	my ($self,$key,$nb)=@_;
	return undef unless defined $key and $nb=~m/^\d*$/;
	$nb||=0;
	my $val=$self->{ilst}{$key}[$nb];
	unless (defined $val) {warn "tag to delete not found\n"; return undef; }
	$self->{ilst}{$key}[$nb]=undef;
	#return 1;
	return $val;
}

sub get_fieldtypes
{	my ($self,$key,$nb)=@_;
	my $type= $key=~m/^Unknown tag with flag=\d+ and key=/ ?	'u'  :
		  $key eq 'covr' ?		'p':
		  $key=~m/^cpil$|^pgap$|^pcst$/?'f':
		  				't';
	if ($key=~m/^(?:Unknown tag with flag=\d+ and key=)?(.*)----(.*)$/)
	{	return $type.'tt',_"Other",[$self->{ilst}{$key}[$nb],$1,$2],'----';
	}
	return $type;
}

sub ParseAtomTree
{	my $self=shift;
	my $fh=$self->{fileHandle};
	my $buffer;
	my (@toplevels,$stco,@left,@parents,@poffset,@psize);
	my (%info,@ilst,$ilst_data,$otherkey);
	while (read($fh,$buffer,8)==8)
	{	while (@left && $left[-1]<=0)
		{	pop @parents;
			pop @left;
			pop @poffset;
			pop @psize;
		}
		my ($length,$name)=unpack 'NA4',$buffer;
		my $datalength=$length-8;
		my $offset=tell($fh)-8;
		if ($length==1)	# $length==1 means 64-bit length follow
		{	read($fh,$buffer,8);
			my ($length1,$length2)=unpack 'NN',$buffer;
			if ($length1>0) { warn "atom '$name' has a size >4GB, unsupported => can't read file\n"; return }
			$length=$length2;
			$datalength=$length-16;
		}
		#FIXME if length==0 : open-ended, extends to the end of the file
		elsif ($datalength<0) { warn "error atom '$name' has an invalid size of $datalength bytes";return }
#warn join('.',@parents,$name)."\n";#warn "left:@left\n";
		push @toplevels, $name,$offset,$length,$stco=[] unless @parents;
		$left[-1]-=$length if @left;
		my $isparent= $IsParent{$name};
		$isparent=0 if @parents && $parents[-1] eq 'ilst';  #0 but defined : children of ilst are parents
		if (defined $isparent)
		{	push @left,$datalength;
			push @parents,$name;
			push @poffset,$offset;
			push @psize,$length;
			if ($name eq 'ilst')
			{	push @{$self->{ilstparents}},[@poffset],[@psize];
				push @ilst, $ilst_data=[];
			}
			if (my $offset=$isparent) #for atom 'meta'
			{	seek $fh,$offset,1;
				$left[-1]-=$offset;
			}
			$otherkey=undef;
		}
		elsif (@parents>1 && $parents[-2] eq 'ilst') #in moov.udta.meta.ilst.XXXX
		{	my $key=$parents[-1];
			read($fh,my($data),$datalength);
			if ($key eq '----') #freeform tag
			{	unless ($otherkey) { push @$ilst_data, $key,$otherkey={}; }
				$otherkey->{$name}=$data;
			}
			elsif ($name eq 'data')
			{	push @$ilst_data,$key,$data;
			}
		}
		elsif ($name eq 'mvhd')
		{	read($fh,$buffer,$datalength);
			my ($version,$timescale,$duration)=unpack 'Cx3x4x4NN',$buffer;
			if ($version==1)
			{	($timescale,$duration,my $duration2)=unpack 'x4x8x8NNN',$buffer;
				$info{seconds}= ($duration* 2**32 + $duration2)/$timescale;
			}
			else { $info{seconds}= $duration/$timescale; }
		}
		elsif ($name eq 'stsd')
		{	read($fh,$buffer,$datalength);
			my ($type,$channels,$bitspersample,$samplerate)=unpack 'x4x4x4A4x16nnx2N',$buffer;
			if ($type eq 'mp4a' && !$info{traktype}) #ignore if not mp4a, and only read the first one if more than one (can it happen ?)
			{	$info{channels}=$channels;
				$info{rate}=$samplerate;
				$info{bitspersample}=$bitspersample;
				#warn "channel=$channels bitspersample=$bitspersample samplerate=$samplerate\n";
				$info{bitrate}=unpack 'N',$1 if $buffer=~m/^.{48}esds.{4}\x03(?:\x80\x80\x80)?.{4}\x04(?:\x80\x80\x80)?.{10}(.{4})/s;
				$info{traktype}=$type;
			}
		}
		elsif ($name eq 'cmov')
		{	warn "Compressed moov atom found, unsupported"; return;
		}
		else
		{	if    ($name eq 'mdat')	{ $info{audiodatasize}+=$datalength; }
			elsif ($name=~m/^stco|^co64|^tfhd/) { push @$stco,$name,$offset-$poffset[0]; $self->{nofullrewrite}=1 unless $name eq 'stco'; }
			unless (seek $fh,$datalength,1) { warn $!; return undef }
		}
	}
	if (!$info{audiodatasize}) { warn "Error reading m4a file : no mdat atom found\n"; return }
	$self->{toplevels}=\@toplevels;
	$info{bitrate_calculated}= 8*$info{audiodatasize}/$info{seconds};
	$info{bitrate}||=$info{bitrate_calculated};
	$self->{info}=\%info;

	#warn "$_ => $info{$_}\n" for sort keys %info;

	@ilst=@{$ilst[0]}; #ignore an eventual 2nd ilst
	while (@ilst)
	{	my ($key,$data)=splice @ilst,0,2;
		if ($key eq '----')
		{	$key= substr($data->{mean},4).'----'.substr($data->{name},4);
			$data=$data->{data};
		}
		my $val= substr $data,8;
		my $flag=unpack 'x3C',$data;
		if ($flag==1)				{ $val=decode('utf-8',$val); }
		elsif ($key eq 'trkn' || $key eq 'disk'){ $val=join '/',unpack 'x2nn',$val; }
		elsif ($key eq 'gnre')			{ $val=unpack 'xC',$val; $val=$Tag::MP3::Genres[$val]; $key="\xa9gen"; }
		elsif ($key eq 'covr')			{  } #nothing to do, $val contains the binary data of the picture
		elsif ($key eq 'tmpo')			{ $val=unpack 'n',$val; }
		elsif ($key=~m/^cpil$|^pgap$|^pcst$/)	{ $val=unpack 'C',$val; }
		else					{ $key='Unknown tag with flag='.$flag.' and key='.$key; }
		push @{$self->{ilst}{$key}}, $val;
		push @{$self->{ilst_order}}, $key;
	}
}

sub Make_ilst
{	my $self=shift;
	my $ilst="\x00\x00\x00\x00ilst";
	for my $key (@{ $self->{ilst_order} })
	{	my $val=shift @{$self->{ilst}{$key}};
		next unless defined $val;
		my $data;
		if ($key eq 'covr')
		{	for my $val (grep defined, $val,@{$self->{ilst}{covr}})		#there can be multiple covers
			{	my $flags=13;		#default to jpg
				if ($val=~m/^\x89PNG\x0D\x0A\x1A\x0A/) {$flags=14}	#for png
				#elsif ($val!=~m/^\xff\xd8\xff\xe0..JFIF\x00/s) {warn "picture in unknown format, should be jpg or png"}
				$data.= pack('NA4x3Cx4a*', 16+length $val, 'data',$flags).$val;
			}
			$self->{ilst}{covr}=[];
		}
		else
		{	my $flags=1;
			if ($key=~m/^Unknown tag with flag=(\d+) and key=(.*)$/)	{$key=$2; $flags=$1;}
			if ($key=~m/^(.*)----(.*)$/)
			{	$key='----';
				$data=pack 'NA4x4a*NA4x4a*', (12+length $1), 'mean', $1, (12+length $2), 'name',$2;
			}
			if ($key eq 'trkn' || $key eq 'disk')
			{	next unless $val=~m#(\d+)(?:/(\d+))?#;
				$flags=0;
				$val=pack 'x2nn',$1,($2||0);
				$val.="\x00\x00" if $key eq 'trkn';
			}
			elsif ($key eq 'tmpo')			{ $val=pack 'n',$val; $flags=21; }
			elsif ($key=~m/^cpil$|^pgap$|^pcst$/)	{ $val=pack 'C',$val; $flags=21; }
			elsif ($key eq "\xA9gen" && grep $val eq $_, @Tag::MP3::Genres)
			{	$key='gnre'; $flags=0;
				$val=::first {$val eq $Tag::MP3::Genres[$_]} 0..$#Tag::MP3::Genres;
				$val=pack 'xC',$val;
			}
			elsif ($flags==1)			{ $val=encode('utf-8',$val); }

			$data.= pack 'NA4x3Cx4a*', (16+length $val), 'data', $flags, $val;
		}
		$ilst.= pack 'NA4a*', (8+length $data),$key,$data;
	}
	substr $ilst,0,4,pack('N', length $ilst );	#set size of the new ilst
	return $ilst;
}

sub write_file
{	my $self=shift;
	my $fh=$self->_open;
	unless ($self->{ilstparents}) { warn "ilst not found"; return }
	my ($poffset,$psize)=@{$self->{ilstparents}};
	my $oldsize=pop @$psize;
	my $ilst_offset= pop @$poffset;
	my $moov_offset=$poffset->[0];
	$ilst_offset-=$moov_offset;
	seek $fh,$moov_offset,0;
	read $fh,my($moov),$psize->[0];
	my $free_after_moov=0;
	if (8==read $fh,my($buffer),8)
	{	my ($length,$name)=unpack 'NA4',$buffer;
		if ($length==1 && 8==read($fh,$buffer,8))	# $length==1 means 64-bit length follow
		{	my ($length1,$length2)=unpack 'NN',$buffer;
			if ($length1==0 && $length2>=16) { $length=$length2; }
		}
		$free_after_moov=$length if $name eq 'free' && $length>=8;
	}
	$self->_close;
	my $oldilst= substr $moov,$ilst_offset,$oldsize;
	my $newilst= $self->Make_ilst;
	#look if ilst's parent has a 'free' child right after ilst
	if ($poffset->[-1]-$moov_offset+$psize->[-1] > $ilst_offset+$oldsize)
	{	my ($length,$name)=unpack 'NA4', substr $moov,$ilst_offset+$oldsize,8;
		if ($length==1)	# $length==1 means 64-bit length follow
		{	my ($length1,$length2)=unpack 'NN', substr $moov,$ilst_offset+$oldsize+8,8;
			if ($length1==0 && $length2>=16) { $length=$length2; }
		}
		$oldsize+=$length if $name eq 'free' && $length>=8;
	}
	my $free=$oldsize - length $newilst;  #warn "  free1=$free\n";
	if ($free>=2**32) { warn "file too big, size>4GB are not supported\n"; return 0; }
	elsif ($free==0 || ($free>=8 && ($free<2048 || $self->{nofullrewrite})))
	{	warn "in place editing1.\n";
		$newilst.= pack('NA4',$free,'free') . "\x00"x ($free-8) if $free;
		$fh=$self->_openw or return 0;
		seek $fh,$ilst_offset+$moov_offset,0;
		print $fh $newilst or warn $!;
		#warn "endwrite1=".tell($fh);			#DEBUG
		$self->_close;
	}
	else	# too much or not enough padding -> set padding to 1024 and resize
	{	$newilst.= pack('NA4',1024,'free') . "\x00"x (1024-8);
		my $delta1=1024-$free;
		#replace old ilst by new ilst in $moov
		substr $moov,$ilst_offset,$oldsize, $newilst;
		for my $i (0..$#$poffset)	#resize ilst's parents
		{	substr $moov,$poffset->[$i]-$moov_offset,4, pack('N', $psize->[$i]+=$delta1 );
		}
		my $free= $free_after_moov - $delta1; #warn "  free2=$free\n";
		if ($free==0 || ($free>=8 && ($free<20480 || $self->{nofullrewrite})))
		{	warn "in place editing2.\n";
			$moov.= pack('NA4',$free,'free') . "\x00"x ($free-8) if $free;
			$fh=$self->_openw or return 0;
			seek $fh,$poffset->[0],0;
			print $fh $moov or warn $!;
			#warn "endwrite2=".tell($fh);			#DEBUG
			$self->_close;
		}
		elsif ($self->{nofullrewrite})
		{	warn "file contains a co64 or tfhd atom, adding metadata bigger than the free space is not suppôrted.\n";
			return 0;
		}
		else
		{	my $delta2=4096-$free;		#warn "delta2=$delta2\n";
			$moov.= pack('NA4',4096,'free') . "\x00"x (4096-8);
			my $INfh=$self->_open or return 0;
			my $OUTfh=$self->_openw(1) or return 0;	#open .TEMP file
			my $werr;

			my $toplevels=$self->{toplevels};
			while (@$toplevels)
			{	my ($name,$o,$s,$stco)=splice @$toplevels,0,4;
				if ($o==$moov_offset)	#$name eq 'moov'
				{	for (my $i=1; $i<=$#$stco; $i+=2) { $stco->[$i]+=$delta1 if $stco->[$i]>$ilst_offset; } #fix offset for stco after ilst
					_UpdateStco($stco,\$moov,$moov_offset,$delta2);
					print $OUTfh $moov  or warn $! and $werr++;
					splice @$toplevels,0,4 if @$toplevels && $toplevels->[0] eq 'free';
				}
				elsif ($name eq 'mdat')
				{	seek $INfh,$o,0;
					while ($s>0)
					{	my $size=($s>1048576)? 1048576 : $s;
						read $INfh,my($buffer),$size;
						print $OUTfh $buffer  or warn $! and $werr++;
						$s-=$size;
					}
				}
				else
				{	seek $INfh,$o,0;
					read $INfh,my($buffer),$s;
					_UpdateStco($stco,\$buffer,$moov_offset,$delta2);
					print $OUTfh $buffer  or warn $! and $werr++;
				}
				last if $werr;
			}
			$self->_close;
			close $OUTfh;
			if ($werr) {warn "write errors... aborting.\n"; unlink $self->{filename}.'.TEMP'; return 0; }
			warn "replacing old file with new file.\n";
			unlink $self->{filename} && rename $self->{filename}.'.TEMP',$self->{filename};
		}
	}
	$self=undef;	#to prevent re-use of the object
	return 1;
}

sub _UpdateStco
{	my ($stco,$chunckdataref,$change_position,$delta)=@_;
	while (@$stco)
	{	my ($atom,$offset)=splice @$stco,0,2;
		if ($atom eq 'stco')
		{	my $nb=unpack 'N',substr $$chunckdataref,$offset+12; #number of 4-bytes offset
			my @offsets=unpack 'N*',substr $$chunckdataref,$offset+16,$nb*4;
			$_ = $_ > $change_position ? $_+$delta : $_ for @offsets;
			substr $$chunckdataref,$offset+16, 4*@offsets, pack 'N*',@offsets;
		}
		#updating co64 and tfhd is not supported, will abort before reaching this point because of $self->{nofullrewrite}
		#elsif ($atom eq 'co64')
		#{
		#}
		##elsif ($atom eq 'tfhd')
		#{
		#}
	}
}

1;
