
# Copyright (C) 2014 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin AppIndicator
name	App indicator
title	App Indicator plugin
desc	Displays a panel indicator in some desktops
req	perl(Gtk2::AppIndicator, libgtk2-appindicator-perl perl-Gtk2-AppIndicator)
=cut

package GMB::Plugin::AppIndicator;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_AppIndicator_',
};

use Gtk2::AppIndicator;

::SetDefaultOptions(OPT, MiddleClick=>'playpause');

my %mactions= # action when middle-clicking on icon, must correspond to an id in the tray menu (@::TrayMenu)
(	playpause=> _"Play/Pause",
	showhide=> _"Show/Hide",
	next	=> _"Next",
);
my ($indicator,$iconpath);

sub Start
{	$indicator||=Gtk2::AppIndicator->new(::PROGRAM_NAME,'gmusicbrowser','application-status');
	# events that requires updating the traymenu :
	::Watch($indicator, $_=> \&QueueUpdate) for qw/Lock Playing Windows/;
	#::Watch($indicator, $_=> \&UpdateIcon) for qw/Playing Icons/; #FIXME needs initialization #deactivated because it can't work for now
	QueueUpdate();
}
sub Stop
{	::UnWatch_all($indicator);
	$indicator->get_menu->destroy;
	$indicator->set_passive; #can't find how to destroy it, so hide it and reuse it if plugin reactivated
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $middleclick= ::NewPrefCombo(OPT.'MiddleClick', \%mactions, text => _"Middle-click action :", cb=>\&Update);
	my $warning= Gtk2::Label->new_with_format("<i>%s</i>",_"(The middle-click action doesn't work correctly in some desktops)");
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $middleclick,$warning;
	return $vbox;
}

sub QueueUpdate
{	::IdleDo('2_AppIndicator',500,\&Update);
}
sub Update
{	delete $::ToDo{'2_AppIndicator'};
	return unless $indicator;
	my $menu= ::BuildMenu(\@::TrayMenu);
	$menu->show_all;
	$indicator->set_active;
	$indicator->set_menu($menu);
	my ($menuentry)= grep $_->{id} && $_->{id} eq $::Options{OPT.'MiddleClick'}, $menu->get_children;
	$indicator->set_secondary_activate_target($menuentry) if $menuentry;
}

#doesn't work, needs gmb to switch the standard icon system first
sub UpdateIcon
{	my $state= !defined $::TogPlay ? 'default' : $::TogPlay ? 'play' : 'pause';
	$state='default' unless $::TrayIcon{$state};
	my $path= ::dirname($::TrayIcon{$state});
	my $name= ::barename($::TrayIcon{$state});
	$indicator->set_icon_theme_path($iconpath=$path) if $iconpath && $iconpath ne $path;
	$indicator->set_icon_name_active($name);
}

#patch for typo in Gtk2::AppIndicator
package Gtk2::AppIndicator;
sub set_secondary_activate_target {
        my $self=shift;
        my $widget=shift;
        $self->{secondary}=$widget;
        appindicator_set_secondary_activate_target($self->{ind},$widget);
}


1;
