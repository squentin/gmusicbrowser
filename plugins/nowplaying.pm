# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
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
	{	my $string=::ReplaceFields($ID,"Title=%t\nArtist=%a\nAlbum=%l\nLength=%m\nYear=%y\n");
		open my$out,'|-',@cmd;
		print $out $string;
		close $out;
	}
	else
	{	::forksystem(@cmd);
	}
}

1 #the file must return true
