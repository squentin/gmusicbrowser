# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# https://tools.ietf.org/html/rfc7845.html
# https://wiki.xiph.org/OggOpus
# http://xiph.org/vorbis/doc/framing.html

# NOTE To the person who wrote oggheader.pm, no offense, but I think you should invest in a space key. It's a helpful thing, you'll find.

package Tag::Opus;

require 'oggheader.pm';

use strict;
use warnings;
use Encode qw(decode encode);
use MIME::Base64;

use constant
{ 
    PACKET_INFO     => 'OpusHead',
    PACKET_COMMENT  => 'OpusTags',
};

# Tag manipulation members are duplicates of Tag::OGG
*edit       = \&Tag::OGG::edit;
*add        = \&Tag::OGG::add;
*insert     = \&Tag::OGG::insert;
*remove_all = \&Tag::OGG::remove_all;
*get_keys   = \&Tag::OGG::get_keys;
*get_values = \&Tag::OGG::get_values;
*remove     = \&Tag::OGG::remove;

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
# opus_string
# stream_vers
# end

sub new
{   
    my ($class,$file) = @_;
    my $self=bless {}, $class;

    # check that the file exists
    unless (-e $file)
    {	
        warn "File '$file' does not exist.\n";
	    return undef;
    }

    $self->{filename} = $file;
    $self->_open or return undef;

    {
    	$self->{info} = _ReadInfo($self);
    	last unless $self->{info};

	    $self->{comments} = _ReadComments($self);
    	last unless $self->{comments};

	    $self->{end} = Tag::OGG::_skip_to_last_page($self);

    	_read_packet($self, 0) unless $self->{end};

	    warn "file truncated or corrupted.\n" unless $self->{end};


        # from info_opus.c (opusinfo tool) in the reference implementation
        # time = (inf->lastgranulepos - inf->firstgranule - inf->oh.preskip) / 48000.;                                                                                                                                                          
        #calulate length
        last unless $self->{info}{rate};# && $self->{end};
        my @granule = unpack 'C*', $self->{granule};
        my $samples = 0;
        $samples = $samples * 256 + $_ for reverse @granule;
        my $seconds = ($samples - $self->{info}{preskip}) / 48000; # XXX subtracting preskip isn't evidently all that important
        $self->{info}{seconds} = $seconds;
    }

    $self->_close;
    unless ($self->{info} && $self->{comments})
    {	
        warn "error, can't read file or not a valid opus file\n";
	    return undef;
    }
    return $self;
}

# Initial open call for read (->_openw for write)
sub _open
{	
    my $self = shift;
	my $file = $self->{filename};
	open my $fh, '<', $file or warn "can't open $file : $!\n" and return undef;
	binmode $fh;
	$self->{fileHandle} = $fh;
	$self->{seg_table} = [];
	return $fh;
}

sub _openw
{	
    my ($self,$tmp) = @_;
	my $file = $self->{filename};

	my $m = '+<';
	if ($tmp) {
        $file.='.TEMP';
        $m='>';
    }

	my $fh;

	until (open $fh,$m,$file)
	{	
        my $err = "Error opening '$file' for writing :\n$!";
		warn $err."\n";
		return undef unless $self->{errorsub} && $self->{errorsub}($!, 'openwrite', $file) eq 'retry';
	}

	binmode $fh;
	unless ($tmp)
	{ 
        $self->{fileHandle} = $fh;
	    $self->{seg_table} = [];
	}
	return $fh;
}

sub _close
{	
    my $self = shift;
	$self->{seg_table} = undef;
	close delete($self->{fileHandle});
}

sub write_file
{	
    my $self            = shift;
	my $newcom_packref  = _PackComments($self);

	warn "old size $self->{commentpack_size}, need : ".length($$newcom_packref)."\n";
    
	if ( $self->{commentpack_size} >= length $$newcom_packref)
	{	
        warn "in place editing.\n";
		my $left = length $$newcom_packref;
		my $offset2 = 0;
		my $fh=$self->_openw or return;

		_read_packet($self, PACKET_INFO);	#skip first page

		while ($left)
		{ 
            my $pos = tell $fh;
		    
            my ($pageref, $offset, $size) = Tag::OGG::_ReadPage($self);

		    seek $fh, $pos, 0;

		    if ($left < $size) 
            {
                $size = $left; 
                $left = 0;
            }
		    else		   
            {
                $left -= $size
            }

		    substr $$pageref, $offset, $size, substr($$newcom_packref, $offset2, $size);
		    $offset2 += $size;
		    Tag::OGG::_recompute_page_crc($pageref);
		    print $fh $$pageref or warn $!;
		}
		$self->_close;
		return;
	}
	my $INfh=$self->_open or return;
	my $OUTfh=$self->_openw(1) or return;	#open .TEMP file

	my $version=chr $self->{stream_vers};
	my $serial=$self->{serial};
	my $pageref=Tag::OGG::_ReadPage($self);		#read the first page
	die unless $pageref;	#FIXME check serial, OggS ...
	print $OUTfh $$pageref or warn $!;		#write the first page unmodified
	my $pagenb=1;

	#skip the comment packet in the original file
	die unless _read_packet($self, PACKET_COMMENT);

	#concatenate newly generated comment packet and setup packet from the original file in $data, and compute the segments in @segments
	my $data;
	my @segments;

	#separate $data in pages and write them
	my $data_offset=0;
	my $continued=0;
	{	
        my $size=0;
		my $segments;
		my $nbseg=0;
		my $seg;
		
        while ($size < 4096)		# make page of max 4095+255 bytes
		{	
            last unless @segments;
			$seg=shift @segments;
			$size+=$seg;
			$segments.=chr $seg;
			$nbseg++;
		}

		warn "writing page $pagenb\n" if $::debug;
		my $page=pack('a4aa x8 a4 V x4 C','OggS',$version,$continued,$serial,$pagenb++,$nbseg).$segments.substr($data,$data_offset,$size);
		Tag::OGG::_recompute_page_crc(\$page);
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
	{	
		while (my $pageref=Tag::OGG::_ReadPage($self))	# read each page
		{	
            substr $$pageref,18,4,pack('V',$pagenb++); #replace page number
			Tag::OGG::_recompute_page_crc($pageref);	#recompute crc
			print $OUTfh $$pageref or warn $!;	#write page
		}
	}

	$self->_close;
	close $OUTfh;
	warn "replacing old file with new file.\n";
	unlink $self->{filename} && rename $self->{filename}.'.TEMP', $self->{filename}; # does this even happen?
	%$self=(); #destroy the object to make sure it is not reused as many of its data are now invalid
	return 1;
}

# Read OpusHead
sub _ReadInfo
{
    my $self = shift;
	if ( my $packref = _read_packet($self, PACKET_INFO) )
	{	
        my %info;
        @info{qw/capture version channels preskip rate gain/} = unpack 'a8 C C v I s', $$packref;
        print "OpusHead: v$info{version} $info{channels}ch +$info{preskip} $info{rate}Hz $info{gain}dB\n" if $::debug;
		return \%info;
	}
	else
	{	warn "Can't read info\n";
		return undef;
	}
}

# Read OpusTags
sub _ReadComments
{	
    my $self=$_[0];
	if ( my $packref= _read_packet($self,PACKET_COMMENT) )
	{	
        $self->{commentpack_size}=length $$packref;

		my ($capture_string, $vendor_string, @comlist) = eval 
        { 
            unpack 'a8 V/a V/(V/a)', $$packref; 
        };

		if ($@) 
        { 
            warn "Comments corrupted\n"; 
            return undef; 
        }

		$self->{opus_string} = $vendor_string;

		if ($::debug && $vendor_string!~m/^libopus/)
		{ 
            warn "unknown comments vendor string : $vendor_string\n"; 
        }
        else
        {
            print "read vendor string: $vendor_string\n" if $::debug;
        }

		my %comments;
		my @order;
		$self->{CommentsOrder} = \@order;

		for my $kv (@comlist)
		{	
            unless ($kv=~m/^([^=]+)=(.*)$/s) 
            { 
                warn "comment invalid - skipped\n"; 
                next; 
            }
			my $key = $1;
			my $val = decode('utf-8', $2);
			push @{ $comments{lc $key} }, $val;
			push @order, $key;
		}

		if (my $covers = $comments{coverart})	#upgrade old embedded pictures format to metadata_block_picture
		{	
            @order = grep !m/^coverart/i, @order;
			for my $i (0..$#$covers)
			{	
                my $data = $comments{"coverart"}[$i];
				next unless $data;
				my @val = (
                    map($comments{"coverart$_"}[$i], qw/mime type description/), 
                    decode_base64($data) 
                );
				push @{$comments{metadata_block_picture}}, \@val;
				push @order, 'METADATA_BLOCK_PICTURE';
			}
			delete $comments{"coverart$_"} for qw/mime type description/, '';
		}

		return \%comments;
	}
	else
	{	warn "Can't find comments\n";
		return undef;
	}
}

# Differs from vorbis implementation 
sub _PackComments
{	
    my $self = $_[0];
	my @comments;
	my %count;

	for my $key ( @{$self->{CommentsOrder}} )
	{	
        my $nb = $count{lc$key}++ || 0;
		my $val = $self->{comments}{lc$key}[$nb];
		next unless defined $val;

		$key = encode('ascii',$key);
		$key =~ tr/\x20-\x7D/?/c; 
        $key =~ tr/=/?/; #replace characters that are not allowed by '?'

		if (uc $key eq 'METADATA_BLOCK_PICTURE' && ref $val)
		{	
            $val= Tag::Flac::_PackPicture($val);
			$val= encode_base64($$val);
		}
		push @comments, $key . '=' . encode('utf8', $val);
	}

	my $packet = pack 'a8 V/a* V (V/a*)*', PACKET_COMMENT, $self->{opus_string}, scalar @comments, @comments;
	return \$packet;
}

# TODO delegate to Tag::OGG?


sub _read_packet
{	
    my $self       = shift;
	my $wantedtype = shift; #wanted type, 0 to read all packets until eof

	my $fh = $self->{fileHandle};
	my $packet;

	do
	{ 
        my $offset = 0;
	    my $seg_table = $self->{seg_table}; # Page segment table

        {
            my $final_segment_reached;

            until ($final_segment_reached)
            {	
                my $size;
                
                unless ( @$seg_table ) 
                { 
                    Tag::OGG::_read_page_header($self) || return undef;
                }

                # Sum the segment table to compute packet size?
                while (defined( my $byte = shift @$seg_table ))
                {	
                    $size += $byte;

                    unless ($byte == 255) 
                    { 
                        $final_segment_reached = 1; 
                        last; 
                    }
                }
                next unless $size;

                my $read = read $fh, $packet, $size, $offset;

                return undef unless $size == $read;

                $offset += $read;
            }
        }

	} 
    until ($wantedtype || $self->{end});

	my $typemagic = unpack 'a8', $packet;

	warn "loaded packet: type='$typemagic' length=".length($packet)."\n" if $::debug;

	if ($wantedtype eq $typemagic)	
    { 
        return \$packet; 
    }
	else 
    { 
        return undef; 
    }
}

1;
