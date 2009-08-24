# Copyright (C) 2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin NOTIFY
Notify
Notify plugin
Notify you of the playing song with libnotify
=cut

package GMB::Plugin::NOTIFY;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_NOTIFY_',
};

use Gtk2::Notify -init, ::PROGRAM_NAME;

::SetDefaultOptions(OPT, title => "%t", text => _"<i>by</i> %a\\n<i>from</i> %l", picsize => 50, timeout=>5);

my $notify;
my $lasttime;

sub Start
{	$notify=Gtk2::Notify->new('');
	#$notify->set_urgency('low');
	#$notify->set_category('music'); #is there a standard category for that ?
	set_actions();
	::Watch($notify,'SongID',\&Changed);
	::Watch($notify,'Playing',\&Changed);
}
sub Stop
{	$notify->destroy;
	$notify=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $replacetext=::MakeReplaceText('talydnf');
	my $entry1=::NewPrefEntry(OPT.'title',_"Title :", tip => $replacetext, sg1=> $sg1, sg2=>$sg2);
	my $entry2=::NewPrefEntry(OPT.'text',_"Text :", tip => $replacetext."\n\n"._("You can use some markup, eg : <b>bold</b>"), sg1=> $sg1, sg2=>$sg2);
	my $size=::NewPrefSpinButton(OPT.'picsize',undef,10,0,0,1000,10,40,_"Picture size :",undef,$sg1);
	my $timeout=::NewPrefSpinButton(OPT.'timeout',undef,10,1,0,9999,2,5,_"Timeout :",_"seconds",$sg1);
	my $actions=::NewPrefCheckButton(OPT.'actions',_"Display stop/next actions",\&set_actions);
	my $whenhidden=::NewPrefCheckButton(OPT.'onlywhenhidden',_"Don't notify if the main window is visible");
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $entry1,$entry2,$size,$timeout,$actions,$whenhidden;
	return $vbox;
}

sub Changed
{	return unless defined $::SongID && $::TogPlay;
	return if $lasttime && $::StartTime==$lasttime; #if song hasn't really changed
	$lasttime=$::StartTime;
	return if $::Options{OPT.'onlywhenhidden'} && ::IsWindowVisible($::MainWindow);
	my $ID=$::SongID;
	my $title=$::Options{OPT.'title'};
	my $text= $::Options{OPT.'text'};
	my $size= $::Options{OPT.'picsize'};
	my $timeout=$::Options{OPT.'timeout'}*1000;
	return unless $title || $text || $size;
	$notify->update( ::ReplaceFields($ID,$title), ::ReplaceFieldsAndEsc($ID,$text));
	my $pixbuf;
	if ($size)
	{	my $album_gid= Songs::Get_gid($ID,'album');
		$pixbuf=AAPicture::pixbuf('album', $album_gid, $size, 1);
	}
	$pixbuf ||= Gtk2::Gdk::Pixbuf->new_from_xpm_data('1 1 1 1','a c none','a'); #1x1 transparent pixbuf to remove previous pixbuf
	$notify->set_icon_from_pixbuf($pixbuf);
	$notify->set_timeout($timeout);
	$notify->show;
	set_actions();
}

sub set_actions
{	$notify->clear_actions;
	if ($::Options{OPT.'actions'})
	{	$notify->add_action('media-stop',_"Stop",\&::Stop);
		$notify->add_action('media-next',_"Next",\&::NextSong);
	}
}

1
