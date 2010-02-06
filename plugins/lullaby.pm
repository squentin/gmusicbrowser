# Copyright (C) 2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin LULLABY
name	Lullaby
title	Lullaby plugin
desc	Allow for scheduling fade-out and stop
=cut

#TODO :
#- configure what to do at the end
#- visual feedback
#- way to abort

package GMB::Plugin::LULLABY;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_LULLABY_',
};

::SetDefaultOptions(OPT, timespan => 30);
my @dayname= (_"Sunday", _"Monday", _"Tuesday", _"Wednesday", _"Thursday", _"Friday", _"Saturday");
my $handle; my $alarm;
my $StartingVolume;

sub Start
{	$::Command{FadeOut}=[\&start_fadeout,_"Fade-out then stop",_"Timespan of the fade-out in seconds"];
	update_alarm();
}
sub Stop
{	Glib::Source->remove($handle) if $handle;	$handle=undef;
	Glib::Source->remove($alarm) if $alarm;		$alarm=undef;
	delete $::Command{FadeOut};
}


sub prefbox
{	my $vbox=Gtk2::VBox->new;
	my $spin=::NewPrefSpinButton(OPT.'timespan', 1,60*60*24, step=>1, text1=>_"Fade-out in", text2=>_"seconds");
	my $button=Gtk2::Button->new(_"Fade-out");
	$button->signal_connect(clicked => \&start_fadeout);
	my $sg=Gtk2::SizeGroup->new('horizontal');
	my @hours;
	for my $wd (0..6)
	{	my $min= ::NewPrefSpinButton(OPT."day${wd}m", 0,59, cb=>\&update_alarm, step=>1, page=>5, wrap=>1);
		my $hour=::NewPrefSpinButton(OPT."day${wd}h", 0,23, cb=>\&update_alarm, step=>1, page=>4, wrap=>1);
		my $timeentry=::Hpack($hour,Gtk2::Label->new(':'),$min);
		my $check=::NewPrefCheckButton(OPT."day$wd",$dayname[$wd], cb=>\&update_alarm, widget=>$timeentry, horizontal=>1, sizegroup=>$sg);
		push @hours,$check;
	}
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $spin,@hours,$button;
	return $vbox;
}

sub update_alarm
{	Glib::Source->remove($alarm) if $alarm; $alarm=undef;
	my $now=time;
	my (undef,undef,undef,$mday0,$mon,$year,$wday0,$yday,$isdst)= localtime($now);
	my $next=0;
	for my $wd (0..6)
	{	next unless $::Options{OPT."day$wd"};
		my $mday=$mday0+($wd-$wday0+7)%7;
		my $m=$::Options{OPT."day${wd}m"};
		my $h=$::Options{OPT."day${wd}h"};
		my $time=::mktime(0,$m,$h,$mday,$mon,$year);
		#warn "$wd $time<$now\n";
		$time=::mktime(0,$m,$h,$mday+7,$mon,$year) if $time<=$now;
		if ($next) {$next=$time if $time<$next}
		else {$next=$time}
		#warn "$wd $time next=$next\n";
	}
	return unless $next;#warn ($next-$now);
	$alarm=Glib::Timeout->add(($next-$now)*1000,\&alarm);
}
sub alarm { start_fadeout(); update_alarm(); }

sub start_fadeout
{	return if $handle;
	my $timespan=$::Options{OPT.'timespan'};
	$timespan=$_[1] if $_[1] and $_[1]=~m/^\d+$/;
	$StartingVolume= ::GetVol();
	$handle=Glib::Timeout->add($timespan*1000/100,\&fade,$StartingVolume/100);
}
sub fade
{	my $dec=$_[0];
	my $new= ::GetVol() - $dec;
	$new=0 if $new<0;
	::UpdateVol($new);
	if ($new==0)
	{	warn "fade-out finished\n" if $::debug;
		$handle=undef;
		::Stop();
		::UpdateVol($StartingVolume);
		#::TurnOff();

	}
	return $handle; #false when finished
}

1
