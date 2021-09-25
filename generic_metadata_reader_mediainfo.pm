# Copyright (C) 2020 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Tag::Generic::Mediainfo;

use strict;
use warnings;

our $OK;

INIT
{	if (*::findcmd{CODE}) # if loaded from gmb
	{	if (::findcmd('mediainfo')) { $OK=1; }
		else { warn "Can't find mediainfo: won't be able to use it to add partially supported files\n" if $::Verbose; }
	}
}


our %InfoFields=
(	seconds	=>	'General/Duration',
	channels=>	'Audio/Channels',
	rate	=>	'Audio/SamplingRate',
	bitrate	=>	'Audio/BitRate',
	audio_depth  =>	'Audio/BitDepth',
	audio_format =>	'Audio/Format',
	video_format =>	'Video/Format',
	container_format=>'General/Format',
	framerate    =>	'Video/FrameRate',
	video_bitrate=>	'Video/BitRate',
	video_height =>	'Video/Height',
	video_width  =>	'Video/Width',
	video_ratio  =>	'Video/DisplayAspectRatio',
	video_depth  =>	'Video/BitDepth',
	video_count  =>	'General/VideoCount',
	audio_count  =>	'General/AudioCount',
	audio_lang   =>	'Audio/Language',
	subtitle_lang=>	'Text/Language',
	toc =>		'Menu/toc',
);

our %GenericTag= # keys use vorbis comment name standard for simplicity
(	title	=>	'General/Title',
	album	=>	'General/Album',
	artist	=>	'General/Performer',
	date	=>	'General/Recorded_Date',
	genre	=>	'General/Genre',
	album_artist=>	'General/Album_Performer',
	tracknumber =>	'General/Track_Position',
	discnumber  =>	'General/Part_Position',
);

if (!caller && @ARGV) # if called from command line, useful for testing
{	# in a string eval so that gmb doesn't require HTML::Entities
	eval 'use HTML::Entities;';
	*::decode_html= \&HTML::Entities::decode_entities;
	my $self= Tag::Generic::Mediainfo->new($ARGV[0]);
	my $info= $self->{info};
	binmode STDOUT,':utf8';
	print "info:\n";
	print "  $_: $info->{$_}\n" for sort grep defined $info->{$_}, keys %$info;
	print "tag:\n";
	print "  $_: ".($self->get_values($_)//'')."\n" for sort keys %GenericTag;
}


sub new
{	my ($class,$file)=@_;
	my $self=bless {}, $class;

	# check that the file exists
	unless (-e $file)
	{	warn "File '$file' does not exist.\n";
		return undef;
	}
	$self->{filename} = $file;

	my @cmd_and_args= (qw/mediainfo --Output=XML/,$file);
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
	my ($track,%found,%xml,$extra);
	binmode $content_fh,':utf8';
	while (<$content_fh>)
	{	if (m#^<track type="(\w+)">#i) { $track=$1; $extra= $found{$track}; $found{$track}=1; next }
		if (m#^</track>#i) {$track=undef}
		next unless $track;
		if (m#^<(\w+)>([^<]+)</\1>#)
		{	my ($key,$val)= ($1,::decode_html($2));
			if ($key eq 'Language') { push @{$xml{"$track/$key"}}, $val; } #keep a list of those
			elsif (!$extra) { $xml{"$track/$key"}=$val; } #keep metadata from first track
		}
	}
	close $content_fh;
	if ($xml{'General/Duration'}) # ignore file if we don't have a duration
	{	if (my $menu=$xml{Menu})
		{	my @toc;
			for my $entry (sort keys %$menu)
			{	next unless $entry=~m/^_(\d\d)_(\d\d)_(\d\d)_(\d\d\d)$/;
				push @toc, ((($1*60)+$2*60)+$3*1000)+$4, delete $menu->{$entry};
			}
			$xml{Menu}{toc}=\@toc;
		}
		for my $key (keys %InfoFields)
		{	$self->{info}{$key}= $xml{$InfoFields{$key}};
		}
		$self->{xml}= \%xml;
	}
	else
	{	warn "Skipping file '$file': not recognized or can't find its duration (using mediainfo)\n";
		return undef;
	}
	return $self;
}

sub get_values
{	my ($self,$field)=@_;
	my $name= $GenericTag{$field};
	$name ? $_[0]{xml}{$name} : undef;
}

1;
