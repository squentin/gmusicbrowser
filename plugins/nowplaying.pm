# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# the plugin file must have the following block before the first non-comment line,
# it must be of the format :
# =gmbplugin PID
# name	short name
# title	long name, the short name is used if empty
# desc	description, may be multiple lines
# =cut
=gmbplugin NOWPLAYING
name	Now playing
title	NowPlaying plugin
desc	Run a command when playing a song
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

sub Start
{	$handle={};	#the handle to the Watch function must be a hash ref, if it is a Gtk2::Widget, UnWatch will be called when the widget is destroyed
	::Watch($handle, PlayingSong	=> \&Changed);
	::Watch($handle, Playing	=> \&PlayStop);
}
sub Stop
{	::UnWatch($handle,'PlayingSong');
	::UnWatch($handle,'Playing');
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $entry=::NewPrefEntry(OPT.'CMD',_"Command when playing song changed :",	expand=>1,sizeg1=>$sg1);
	my $entry2=::NewPrefEntry(OPT.'StoppedCMD',_"Command when stopped :",		expand=>1,sizeg1=>$sg1);
	my $preview= Label::Preview->new(preview => \&command_preview, event => 'CurSong Option', noescape=>1);
	my $check=::NewPrefCheckButton(OPT.'SENDSTDINPUT',_"Send Title/Artist/Album in standard input");
	my $replacetable=::MakeReplaceTable('talydnfc');
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $replacetable,$entry,$preview,$entry2,$check;
	return $vbox;
}

sub command_preview
{	my $ID=$::SongID;
	my $cmd= $::Options{OPT.'CMD'};
	return '' unless defined $ID && defined $cmd;
	my @cmd= ::split_with_quotes($cmd);
	return '' unless @cmd;
	$_= ::PangoEsc( ::ReplaceFields($ID,$_) ) for @cmd;
	splice @cmd,$_,0, ::MarkupFormat("\n<i>%s</i>", ::__x(_"argument {n} :",n=>$_))   for reverse 1..$#cmd;
	unshift @cmd, ::MarkupFormat('<i>%s</i>', _"command :");
	my $t= join(' ',@cmd);
	return '<small>'.$t.'</small>';
}

sub PlayStop
{	return if defined $::TogPlay;	#TogPlay is undef when Stopped, 0 when Paused, 1 when Playing
	my $cmd=$::Options{OPT.'StoppedCMD'};
	return unless $cmd;
	::forksystem(::split_with_quotes($cmd));
}

sub Changed
{	my $ID=$::SongID;
	my $cmd= $::Options{OPT.'CMD'};
	return unless defined $cmd;
	my @cmd= ::split_with_quotes($cmd);
	return unless @cmd;
	$_=::ReplaceFields($ID,$_) for @cmd;
	if ($::Options{OPT.'SENDSTDINPUT'})
	{	my $string=::ReplaceFields($ID,"Title=%t\nArtist=%a\nAlbum=%l\nLength=%m\nYear=%y\nTrack=%n\n");
		open my$out,'|-:utf8',@cmd;
		print $out $string;
		close $out;
	}
	else
	{	::forksystem(@cmd);
	}
}

1 #the file must return true
