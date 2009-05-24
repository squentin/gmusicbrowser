# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# the plugin file must have the following block before the first non-comment line,
# it must be of the format :
# =gmbplugin PID
# short name
# long name, the short name is used if empty
# description, may be multiple lines
# =cut
=gmbplugin NOWPLAYING
Now playing
NowPlaying plugin
run a command when playing a song
=cut

# the plugin package must be named GMB::Plugin::PID (replace PID), and must have these sub :
# Start	: called when the plugin is activated
# Stop	: called when the plugin is de-activated
# prefbox : returns a Gtk2::Widget used to describe the plugin and set its options

package GMB::Plugin::NOWPLAYING;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_NOWPLAYING_',
};
my $handle;
my $lasttime;

sub Start
{	$handle={};	#the handle to the Watch function must be a hash ref, if it is a Gtk2::Widget, UnWatch will be called when the widget is destroyed
	::Watch($handle,'SongID',\&Changed);
	::Watch($handle,'Playing',\&Changed);
}
sub Stop
{	::UnWatch($handle,'SongID');
	::UnWatch($handle,'Playing');
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $entry=::NewPrefEntry(OPT.'CMD',_"command :");
	my $check=::NewPrefCheckButton(OPT.'SENDSTDINPUT',_"Send Title/Artist/Album in standard input");
	my $replacetable=::MakeReplaceTable('talydnfc');
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $replacetable,$entry,$check;
	return $vbox;
}

sub Changed
{	return unless defined $::SongID && $::TogPlay;
	return if $lasttime && $::StartTime==$lasttime; #if song hasn't really changed
	$lasttime=$::StartTime;
	my $ID=$::SongID;
	return unless defined $::Options{OPT.'CMD'};
	my @cmd=split / /, $::Options{OPT.'CMD'};
	return unless @cmd;
	$_=::ReplaceFields($ID,$_) for @cmd;
	if ($::Options{OPT.'SENDSTDINPUT'})
	{	my $ref=$::Songs[$ID];
		my $string=	'Title='.	$ref->[::SONG_TITLE]."\n"
				.'Artist='.	$ref->[::SONG_ARTIST]."\n"
				.'Album='.	$ref->[::SONG_ALBUM]."\n"
				.'Length='.	$ref->[::SONG_LENGTH]."\n"
				.'Year='.	$ref->[::SONG_DATE]."\n"
		;
		open my$out,'|-',@cmd;
		print $out $string;
		close $out;
	}
	else
	{	::forksystem(@cmd);
	}
}

1 #the file must return true

# song properties :
# SONG_UFILE	SONG_UPATH	SONG_MODIF
# SONG_LENGTH	SONG_SIZE	SONG_BITRATE
# SONG_FORMAT	SONG_CHANNELS	SONG_SAMPRATE
# SONG_TITLE	SONG_ARTIST	SONG_ALBUM
# SONG_DISC	SONG_TRACK	SONG_DATE
# SONG_VERSION	SONG_GENRE	SONG_COMMENT
# SONG_AUTHOR
# SONG_ADDED	SONG_LASTPLAY	SONG_NBPLAY
# SONG_RATING	SONG_LABELS
# SONG_FILE	SONG_PATH
#
# SONG_GENRE & SONG_LABELS are "\x00" separated lists
#
# filename of album cover is in $::Album{ $::Songs[$::SongID][::SONG_ALBUM] }[::AAPIXLIST]
#  (may be an mp3 file, '0' means "no cover and don't auto-set cover")
# if you change the album cover, you should call : ::HasChanged('AAPicture',$album); where $album is the album name
