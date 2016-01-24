# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin Commands
name	Commands
title	Commands plugin
desc	Execution of custom commands on selected files
=cut

package GMB::Plugin::Commands;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_Commands_',
};

my $ON;
my %menuentry=
(tocmd_1 =>
 {	label => sub { ($::Options{OPT.'tocmd_label_1'} || _"Unnamed custom command") },
	code => \&RunCommand_1,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd_1'}; defined $c && $c ne '';},
	notempty => 'IDs',
 },
tocmd_2 =>
 {	label => sub { ($::Options{OPT.'tocmd_label_2'} || _"Unnamed custom command") },
	code => \&RunCommand_2,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd_2'}; defined $c && $c ne '';},
	notempty => 'IDs',
 },
tocmd_3 =>
 {	label => sub { ($::Options{OPT.'tocmd_label_3'} || _"Unnamed custom command") },
	code => \&RunCommand_3,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd_3'}; defined $c && $c ne '';},
	notempty => 'IDs',
 },
 tocmd_4 =>
 {	label => sub { ($::Options{OPT.'tocmd_label_4'} || _"Unnamed custom command") },
	code => \&RunCommand_4,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd_4'}; defined $c && $c ne '';},
	notempty => 'IDs',
 },
 tocmd_5 =>
 {	label => sub { ($::Options{OPT.'tocmd_label_5'} || _"Unnamed custom command") },
	code => \&RunCommand_5,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd_5'}; defined $c && $c ne '';},
	notempty => 'IDs',
 }
);

sub Start
{	$ON=1;
	updatemenu();
}
sub Stop
{	$ON=0;
	updatemenu();
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');

	# CMD1
	my $entry1=::NewPrefEntry(OPT.'tocmd_label_1',_"Menu entry name", sizeg1=> $sg1,tip => _("Name under which the command will appear in the menu"));
	my $entry2=::NewPrefEntry(OPT.'tocmd_cmd_1',_"System command :", sizeg1=> $sg1,
		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
			_("In this case one command by file will be run\n\n").
			_('Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
	my $check1=::NewPrefCheckButton(OPT.'tocmd_1',_"Command 1", cb=>\&updatemenu, widget=> ::Vpack($entry1,$entry2) );
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check1;

	# CMD2
	my $entry3=::NewPrefEntry(OPT.'tocmd_label_2',_"Menu entry name", sizeg1=> $sg1,tip => _("Name under which the command will appear in the menu"));
	my $entry4=::NewPrefEntry(OPT.'tocmd_cmd_2',_"System command :", sizeg1=> $sg1,
		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
			_("In this case one command by file will be run\n\n").
			_('Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
	my $check2=::NewPrefCheckButton(OPT.'tocmd_2',_"Command 2", cb=>\&updatemenu, widget=> ::Vpack($entry3,$entry4));
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check2;

	# CMD3
	my $entry5=::NewPrefEntry(OPT.'tocmd_label_3',_"Menu entry name", sizeg1=> $sg1,tip => _("Name under which the command will appear in the menu"));
	my $entry6=::NewPrefEntry(OPT.'tocmd_cmd_3',_"System command :", sizeg1=> $sg1,
		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
			_("In this case one command by file will be run\n\n").
			_('Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
	my $check3=::NewPrefCheckButton(OPT.'tocmd_3',_"Command 3", cb=>\&updatemenu, widget=> ::Vpack($entry5,$entry6) );
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check3;

	# CMD4
	my $entry6=::NewPrefEntry(OPT.'tocmd_label_4',_"Menu entry name", sizeg1=> $sg1,tip => _("Name under which the command will appear in the menu"));
	my $entry7=::NewPrefEntry(OPT.'tocmd_cmd_4',_"System command :", sizeg1=> $sg1,
		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
			_("In this case one command by file will be run\n\n").
			_('Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
	my $check4=::NewPrefCheckButton(OPT.'tocmd_4',_"Command 4", cb=>\&updatemenu, widget=> ::Vpack($entry6,$entry7));
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check4;

#	# CMD5
#	my $entry8=::NewPrefEntry(OPT.'tocmd_label_5',_"Menu entry name", sizeg1=> $sg1,tip => _("Name under which the command will appear in the menu"));
#	my $entry9=::NewPrefEntry(OPT.'tocmd_cmd_5',_"System command :", sizeg1=> $sg1,
#		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
#			_("In this case one command by file will be run\n\n").
#			_('Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
#	my $check5=::NewPrefCheckButton(OPT.'tocmd_5',_"Command 5", cb=>\&updatemenu, widget=> ::Vpack($entry8,$entry9) );
#	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check5;

	return $vbox;
}

sub updatemenu
{	my $removeall=!$ON;
	for my $eid (keys %menuentry)
	{	my $menu=\@::SongCMenu;
		my $entry=$menuentry{$eid};
		if (!$removeall && $::Options{OPT.$eid})
		{	push @$menu,$entry unless (grep $_==$entry, @$menu);
		}
		else
		{	@$menu =grep $_!=$entry, @$menu;
		}
	}
}

sub RunCommand_1
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $cmd= $::Options{OPT.'tocmd_cmd_1'};
	::run_system_cmd($cmd,$IDs,0);
}

sub RunCommand_2
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $cmd= $::Options{OPT.'tocmd_cmd_2'};
	::run_system_cmd($cmd,$IDs,0);
}
sub RunCommand_3
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $cmd= $::Options{OPT.'tocmd_cmd_3'};
	::run_system_cmd($cmd,$IDs,0);
}

sub RunCommand_4
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $cmd= $::Options{OPT.'tocmd_cmd_4'};
	::run_system_cmd($cmd,$IDs,0);
}
#sub RunCommand_5
#{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
#	my $cmd= $::Options{OPT.'tocmd_cmd_5'};
#	::run_system_cmd($cmd,$IDs,0);
#}

1
