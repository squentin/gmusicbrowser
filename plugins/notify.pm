# Copyright (C) 2009-2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin NOTIFY
name	Notify
title	Notify plugin
desc	Notify you of the playing song with the system's notification popups
req	perl(Gtk2::Notify, libgtk2-notify-perl perl-Gtk2-Notify)
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
my ($Daemon_name,$can_actions,$can_body);

sub Start
{	$notify=Gtk2::Notify->new('empty','empty');
	#$notify->set_urgency('low');
	#$notify->set_category('music'); #is there a standard category for that ?
	my ($name, $vendor, $version, $spec_version)= Gtk2::Notify->get_server_info;
	$Daemon_name= "$name $version ($vendor)";
	my @caps = Gtk2::Notify->get_server_caps;
	$can_body=	grep $_ eq 'body',	@caps;
	$can_actions=	grep $_ eq 'actions',	@caps;
	set_actions();
	::Watch($notify,'PlayingSong',\&Changed);
}
sub Stop
{	$notify=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $replacetext=::MakeReplaceText('talydngLf');
	my $summary=::NewPrefEntry(OPT.'title',_"Summary :", sizeg1=> $sg1, sizeg2=>$sg2, tip => $replacetext);
	my $body=   ::NewPrefEntry(OPT.'text', _"Body :",    sizeg1=> $sg1, sizeg2=>$sg2, width=>40, tip => $replacetext."\n\n"._("You can use some markup, eg :\n<b>bold</b> <i>italic</i> <u>underline</u>\nNote that the markup may be ignored by the notification daemon"),);
	my $size=   ::NewPrefSpinButton(OPT.'picsize', 0,1000, step=>10, page=>40, text1=>_"Picture size :", sizeg1=>$sg1, tip=> _"Note that some notification daemons resize the displayed picture");
	my $timeout=::NewPrefSpinButton(OPT.'timeout', 0,9999, step=>2,  page=>5,  text1=>_"Timeout :",      sizeg1=>$sg1, text2=>_"seconds", digits=>1);
	my $actions=::NewPrefCheckButton(OPT.'actions',_"Display stop/next actions", cb=>\&set_actions);
	$actions->set_sensitive($can_actions);
	$actions->set_tooltip_text(_("Actions are not supported by current notification daemon").' : '.$Daemon_name) unless $can_actions;
	$body->set_sensitive($can_body);
	$body->set_tooltip_text(_("Body text is not supported by current notification daemon").' : '.$Daemon_name) unless $can_body;
	my $whenhidden=::NewPrefCheckButton(OPT.'onlywhenhidden',_"Don't notify if the main window is visible");
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $summary,$body,$size,$timeout,$actions,$whenhidden;
	return $vbox;
}

sub Changed
{	return if $::Options{OPT.'onlywhenhidden'} && ::IsWindowVisible($::MainWindow);
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
{	return unless $can_actions;
	$notify->clear_actions;
	if ($::Options{OPT.'actions'})
	{	$notify->add_action('media-stop',_"Stop",\&::Stop);
		$notify->add_action('media-next',_"Next",\&::NextSong);
	}
}

1
