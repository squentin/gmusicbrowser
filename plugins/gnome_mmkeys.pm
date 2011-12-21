# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin GMMKEYS
name	Gnome mmkeys
title	Gnome multimedia keys plugin
desc	Makes gmusicbrowser react to the Next/Previous/Play/Stop multimedia keys in gnome.
req	perl(Net::DBus, libnet-dbus-perl perl-Net-DBus)
=cut

package GMB::Plugin::GMMKEYS;
use strict;
use warnings;

use Net::DBus;

my $bus= Net::DBus->find;
my $service = $bus->get_service('org.gnome.SettingsDaemon');
my $object = $service->get_object('/org/gnome/SettingsDaemon/MediaKeys');
eval { $object->connect_to_signal(MediaPlayerKeyPressed => \&callback) };
if ($@) {	my $error=$@;
		# try with old path (for gnome version until ~2.20  <2.22)
		$object=$service->get_object('/org/gnome/SettingsDaemon');
		eval { $object->connect_to_signal(MediaPlayerKeyPressed => \&callback); };
		die $error if $@; #die with the original error
	}

my %cmd=
(	Previous	=> 'PrevSong',
	Next		=> 'NextSong',
	Play		=> 'PlayPause',
	Stop		=> 'Stop',
);

sub Start
{	$object->GrabMediaPlayerKeys('gmusicbrowser',0);
}
sub Stop
{	$object->ReleaseMediaPlayerKeys('gmusicbrowser');
}
sub prefbox
{
}

sub callback
{	my ($app,$key)=@_;
	return unless $app eq 'gmusicbrowser';
	if (my $cmd=$cmd{$key}) { ::run_command(undef,$cmd); }
	else { warn "gnome_mmkeys : unknown key : $key\n" }
}

1
