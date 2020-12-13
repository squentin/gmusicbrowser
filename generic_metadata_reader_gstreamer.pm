# Copyright (C) 2020 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Tag::Generic::GStreamer;

use strict;
use warnings;

our $OK;

our %GenericTag= # keys use vorbis comment name standard for simplicity
(	title	=> 'title',
	album	=> 'album',
	artist	=> 'artist',
	date	=> 'datetime',
	genre	=> 'genre',
	version	=> 'version',
	composer=> 'composer',
	comment	=> 'comment',
	description => 'description',
	album_artist=> 'album-artist',
	tracknumber => 'track-number',
	discnumber  => 'album-disc-number',
	conductor   => 'conductor',
);

# used to try to clean up some of the format names a bit, some simplifications may be bad
our %Formats=reverse
(	#containers
	ASF =>		'Advanced Streaming Format (ASF)',
	AVI =>		'Audio Video Interleave (AVI)',
	CDXA =>		'RIFF/CDXA (VCD)',
	Flash=>		'Flash',
	WebM =>		'WebM',
	Matroska =>	'Matroska',
	Ogg =>		'Ogg',
	Quicktime =>	'Quicktime',
	Realmedia =>	'Realmedia',
	'MPEG-1 PS' =>	'MPEG-1 System Stream',
	'MPEG-2 PS' =>	'MPEG-2 System Stream',
	'MPEG-2 TS' =>	'MPEG-2 Transport Stream',
	#audio
	'AC-3'=>	'AC-3 (ATSC A/52)',
	'AC-3'=>	'DVD AC-3 (ATSC A/52)',
	'AC-3'=>	'E-AC-3 (ATSC A/52B)',
	ADCPM =>	'DVI ADPCM',
	ADCPM =>	'Quicktime ADPCM',
	ADCPM =>	'Microsoft ADPCM',
	ADCPM =>	'A-Law',
	AMR =>		'Adaptive Multi Rate (AMR)',
	MP1 =>		'MPEG-1 Layer 1 (MP1)',
	MP2 =>		'MPEG-1 Layer 2 (MP2)',
	MP3 =>		'MPEG-1 Layer 3 (MP3)',
	PCM =>		'Raw 16-bit PCM audio',
	PCM =>		'Raw 8-bit PCM audio',
	WAV =>		'WAV',
	DTS =>		'DTS',
	AAC =>		'MPEG-4 AAC',
	AAC =>		'MPEG-2 AAC',
	Vorbis =>	'Vorbis',
	Opus =>		'Opus',
	FLAC =>		'Free Lossless Audio Codec (FLAC)',
	ALAC =>		'Apple Lossless Audio (ALAC)',
	QDM2 =>		'QDesign Music (QDM) 2',
	Cook =>		'RealAudio G2 (Cook)',
	Voxware =>	'Voxware',
	GSM =>		'MS GSM',
	MOD =>		'Module Music Format (MOD)',
	MIDI=>		'audio/midi',
	WMA1 =>		'Windows Media Audio 7',
	WMA2 =>		'Windows Media Audio 8',
	WMA3 =>		'Windows Media Audio 9',
	'WMA Voice' =>	'Windows Media Speech',
	#video
	'Sorenson 1' =>	'Sorensen Video 1',
	'Sorenson 3' =>	'Sorensen Video 3',
	'Sorenson Spark' => 'Sorenson Spark Video',
	'RealVideo 4' =>'RealVideo 4.0',
	'MPEG-1' =>	'MPEG-1 Video',
	'MPEG-2' =>	'MPEG-2 Video',
	'MPEG-4' =>	'MPEG-4 Video',
	'MS MPEG-4 4.1' => 'Microsoft MPEG-4 4.1',
	'MS MPEG-4 4.2' => 'Microsoft MPEG-4 4.2',
	'MS MPEG-4 4.3' => 'Microsoft MPEG-4 4.3',
	'MS-CRAM'=>	'Microsoft Video 1',
	'H.265' =>	'H.265',
	'H.264' =>	'H.264',
	'H.264' =>	'ITU H.264',
	'H.26n' =>	'ITU H.26n',
	'DivX 3' =>	'DivX MPEG-4 Version 3',
	'DivX 4' =>	'DivX MPEG-4 Version 4',
	'DivX 5' =>	'DivX MPEG-4 Version 5',
	'DivX 3' =>	'DivX 3',
	'DivX 4' =>	'DivX 4',
	'DivX 5' =>	'DivX 5',
	Cinepak	=>	'Cinepak Video',
	VP6 =>		'On2 VP6/Flash',
	VP8 =>		'VP8',
	VP9 =>		'VP9',
	WMV1 => 	'Windows Media Video 7',
	WMV1 => 	'Windows Media Video 7 Screen',
	WMV2 =>		'Windows Media Video 8 Screen',
	WMV3 =>		'Windows Media Video 9 Screen',
	JPEG =>		'JPEG',
	'Indeo 3' =>	'Intel Indeo 3',
	'Indeo 4' =>	'Intel Indeo 4',
	'Indeo 5' =>	'Intel Indeo 5',
	I263 =>		'Intel H.263',
);

if (caller)
{	# loaded from gmb
	$OK= system('env','perl',__FILE__) ? 0 : 1; # launch it without argument to test init()
	warn "Error trying to initialize gstreamer generic metadata reader: won't be able to use it to add partially supported files\n" unless $OK;
}
else	# independent process: scan file passed as arg
{	die unless init();
	my $uri= shift;  # when called by gmb it should already be a valid uri
	exit 0 unless defined $uri;
	unless ($uri=~m#^\w+://#) # convert non-uri to uri so that it can also be called from command line
	{	$uri=$ENV{PWD}.'/'.$uri unless $uri=~m#^/#;
		$uri=~s#([^/\$_.+!*'(),A-Za-z0-9-])#sprintf('%%%02X',ord($1))#seg;
		$uri="file://$uri";
	}
	my $self= bless {};
	$self->discover($uri);
	$self->print_yaml_result;
	close STDERR; # to get rid of warnings on exit
}


sub init
{	use Glib::Object::Introspection;
	Glib::Object::Introspection->setup(basename => 'Gst', version => '1.0', package => 'GStreamer1');
	GStreamer1::init_check([ $0, @ARGV ]) or die "Can't initialize gstreamer-1.x\n";
	Glib::Object::Introspection->setup(basename => 'GstPbutils', version => '1.0', package => 'GStreamer1::Pbutils');
	#Glib::Object::Introspection->setup(basename => 'GstTag', version => '1.0', package => 'GStreamer1::Tag'); # could be useful for something in the future
	#Glib::Object::Introspection->setup(basename => 'GLib', version => '2.0', package => 'GLib'); # maybe needed to use the GDate type but can't get it to work, maybe it conflicts with some glib parts of Glib::Object::Introspection ?
	return 1;
}

sub new
{	my ($class,$file)=@_;
	my $self=bless {}, $class;

	$self->{filename} = $file;
	my $uri=$file;
	unless ($uri=~m#^\w+://#)
	{	unless (-e $file)
		{	warn "File '$file' does not exist.\n";
			return undef;
		}
		$uri= "file://".::url_escape($uri);
	}

	if (1) { $self->launch_and_parse($uri); }# do it in another process (safer)
	else { $self->discover($uri); }		 # do it in same process (cause warnings and segfault on exit, and could maybe crash gmb)

	return undef unless $self->{info};
	return $self;
}

sub launch_and_parse
{	my ($self,$uri)=@_;
	my @cmd_and_args= ('env','perl',__FILE__,$uri);
	pipe my($content_fh),my$wfh;
	my $pid=fork;
	if (!defined $pid) { warn "fork failed : $!\n"; }
	elsif ($pid==0) #child
	{	close $content_fh; #close $error_fh;
		open \*STDOUT,'>&='.fileno $wfh;
		close STDERR;
		exec @cmd_and_args  or warn "launch failed (@cmd_and_args)  : $!\n";
		POSIX::_exit(1);
	}
	close $wfh;
	my @output;
	binmode $content_fh,':utf8';
	while (<$content_fh>)
	{	push @output, $_;
	}
	close $content_fh;
	::ReadRefFromLines(\@output,$self);
}

sub discover
{	my ($self,$uri)=@_;
	my $discoverer= GStreamer1::Pbutils::Discoverer->new(GStreamer1::SECOND() * 5) or die;
	$discoverer->signal_connect(discovered => \&on_discovered_cb,$self);
	my $info=$discoverer->discover_uri($uri);
	on_discovered_cb($discoverer,$info,undef,$self);
}

# print out results in YAML format. To simplify, each value of info and tag can only be a string or an array of strings
sub print_yaml_result
{	my $self=shift;
	binmode STDOUT,':utf8';
	for my $info_tag (qw/info tag/)
	{	my $hash= $self->{$info_tag};
		next unless $hash;
		print "$info_tag:\n";
		for my $key (sort keys %$hash)
		{	my $lines= "  $key:";
			my $val= $hash->{$key};
			next unless defined $val;
			if (ref $val)
			{	next unless ref $val eq 'ARRAY'; #only supports arrays
				next unless @$val;
				$lines.= "\n";
				$lines.= "    - ".yaml_escape($_)."\n" for @$val;
			}
			else
			{	$lines.= " ".yaml_escape($val)."\n"
			}
			print $lines;
		}
	}
}
sub yaml_escape
{	my $val=shift;
	if (!defined $val) {$val='~'}
	elsif ($val eq '') {$val="''"}
	elsif ($val=~m/[\x00-\x1f\n:#]/ || $val=~m#^'#)
	{	$val=~s/([\x00-\x1f\n"\\])/sprintf "\\x%02x",ord $1/ge;
		$val=qq/"$val"/;
	}
	elsif ($val=~m/^\W/ || $val=~m/\s$/ || $val=~m/^true$|^false$|^null$/i)
	{	$val=~s/'/''/g;
		$val="'$val'";
	}
	return $val;
}

sub on_discovered_cb
{	my ($discoverer,$info,$error,$self)=@_;
	my $result= $info->get_result;
	#warn $result." ". $info->get_uri."\n";
	if ($result ne 'ok')
	{	#if ($result eq 'uri_invalid') {}
		#elsif ($result eq 'error') {}
		#elsif ($result eq 'timeout') {}
		#elsif ($result eq 'busy') {}
		#elsif ($result eq 'missing_plugins') {}
		warn "Error '$result' discovering $info->get_uri\n";
		return;
	}
	#warn $info->get_uri;
	#$info->get_seekable
	#$info->get_live
	$self->{info}= {};
	$self->{info}{seconds}= $info->get_duration / GStreamer1::SECOND();
	if (my $tags=$info->get_tags)
	{	my %used= reverse %GenericTag;
		$tags->foreach(
		sub {	my ($tags,$key)= @_;
			return 1 unless exists $used{$key}; #skip fields that are not in values of %GenericTag, as those won't be used anyway and some non-string types could cause crashes like "date"
			my $val;
			if ($key eq 'date') {  }	# GDate type, can't get to it, cause crashes, datetime seems more popular anyway
			elsif ($key eq 'datetime')	# GstDateTime type
			{	eval { $val= $tags->get_date_time($key)->to_iso8601_string; };
			}
			else { eval { $val= $tags->copy_value($key); }; }
			$self->{tag}{$key}=$val if defined $val;
			1;
		});
	}
	$self->{info}{seekable}= $info->get_seekable;
	if (my $gstinfo= $info->get_stream_info)
	{	$self->scan_topology($gstinfo);
		for my $cat (qw/container_format video_format audio_format/)
		{	my $format= $self->{info}{$cat};
			next unless $format;
			# clean-up format string
			$format=~s/ \([-a-z0-9 ]+ Profile\)$//i;
			$self->{info}{$cat}= $Formats{$format} || $format;
		}
	}
}

sub scan_topology
{	my ($self,$gstinfo)=@_;
	my $info= $self->{info};
	my $caps= $gstinfo->get_caps;
	my $type= $gstinfo->get_stream_type_nick;
	my $desc= $caps->is_fixed ? GStreamer1::Pbutils::pb_utils_get_codec_description($caps) : $caps->to_string;
	$info->{$type."_format"} ||= $desc; # only store the desc for the first of a type of stream
	if (my $toc= !$info->{toc} && $gstinfo->get_toc)
	{	my @entries_todo= @{ $toc->get_entries };
		while (my $entry= shift @entries_todo)
		{	my ($start,$stop)= $entry->get_start_stop_times;
			#warn " toc ".$entry->get_entry_type." $start-$stop\n";		#DEBUG
			#my $tags= $entry->get_tags;					#DEBUG
			#$tags->foreach(sub {my $gvalue=$_[0]->copy_value($_[1]);warn "  ".$_[1]." = ".$gvalue."\n"; 1; }) if $tags;#DEBUG
			my $subentries= $entry->get_sub_entries;
			push @entries_todo, @$subentries if $subentries;
			if ($entry->get_entry_type eq 'chapter')
			{	my $tags= $entry->get_tags;
				my $title= $tags->get_string('title');
				push @{ $info->{toc} }, $stop,$title; #seems $start is always 1 ? so just use $stop
			}
		}
	}
	if ($gstinfo->isa('GStreamer1::Pbutils::DiscovererAudioInfo'))
	{	unless ($info->{audio_count}) #only take info from first audio stream
		{	$info->{channels}=	$gstinfo->get_channels;
			$info->{bitrate}=	$gstinfo->get_bitrate;
			$info->{rate}=		$gstinfo->get_sample_rate;
			$info->{audio_depth}=	$gstinfo->get_depth;
		}
		my $lang= $gstinfo->get_language;
		push @{ $info->{audio_lang} }, $lang if $lang;
		$info->{audio_count}++;
	}
	elsif ($gstinfo->isa('GStreamer1::Pbutils::DiscovererVideoInfo') && !$gstinfo->is_image)
	{	unless ($info->{video_count}) #only take info from first video stream
		{	$info->{video_bitrate}=	$gstinfo->get_bitrate;
			$info->{video_depth}=	$gstinfo->get_depth;
			$info->{video_height}=$gstinfo->get_height;
			$info->{video_width}= $gstinfo->get_width;
			$info->{framerate}= $gstinfo->get_framerate_num / $gstinfo->get_framerate_denom;
			$info->{video_par}= $gstinfo->get_par_num / $gstinfo->get_par_denom; #pixel aspect ratio
			$info->{video_ratio}= $info->{video_par} * $info->{video_width} / $info->{video_height};
			$info->{interlaced}= $gstinfo->is_interlaced ? 1 : 0;
		}
		$info->{video_count}++;
	}
	elsif ($gstinfo->isa('GStreamer1::Pbutils::DiscovererSubtitleInfo'))
	{	$info->{subtitle_count}++;
		my $lang= $gstinfo->get_language;
		push @{ $info->{subtitle_lang} }, $lang if $lang;
	}

	my $next= $gstinfo->get_next;
	if ($next)
	{	$self->scan_topology($next);
	}
	elsif ($gstinfo->isa('GStreamer1::Pbutils::DiscovererContainerInfo'))
	{	for my $stream (@{$gstinfo->get_streams})
		{	$self->scan_topology($stream);
		}
	}
}

sub get_values
{	my ($self,$field)=@_;
	my $name= $GenericTag{$field};
	$name ? $self->{tag}{$name} : undef;
}

1;
