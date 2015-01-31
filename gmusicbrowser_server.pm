# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation
package Play_Server;
use strict;
use warnings;

my ($ChildPID,$WatchTag,$fh,@pidToKill);
my $cmd=$::DATADIR.::SLASH.'iceserver.pl';
$::PlayPacks{Play_Server}=1; #register the package

sub init
{	if (-e $cmd) {return bless {},__PACKAGE__}
	else {return}
}

sub supported_formats
{ qw/flac mp3 mpc oga wv ape m4a/;
}

sub Close {}

sub Play
{	shift;
	close $fh if $fh;
	my $file=shift;
	$ChildPID=open $fh,'-|',$cmd,'-p',$::Options{Icecast_port},$file;
	$WatchTag= Glib::IO->add_watch(fileno($fh),'G_IO_HUP',\&_eos_cb);
}

sub _eos_cb
{	Glib::Source->remove($WatchTag) or warn "couldn't remove watcher";
	undef $WatchTag;
	undef $ChildPID;
	::end_of_file_faketime();
	return 1;
}

sub Stop
{	if ($WatchTag)
	{	Glib::Source->remove($WatchTag) or warn "couldn't remove watcher";
		undef $WatchTag;
	}
	if ($ChildPID)
	{	warn "killing $ChildPID\n" if $::debug;
		#kill TERM=>$ChildPID;
		kill INT=>$ChildPID;
		Glib::Timeout->add( 200,\&_Kill_timeout ) unless @pidToKill;
		push @pidToKill,$ChildPID;
		undef $ChildPID;
	}
}
sub _Kill_timeout	#make sure old children are dead
{	@pidToKill=grep kill(0,$_), @pidToKill;
	if (@pidToKill)
	{ warn "killing -9 @pidToKill\n" if $::debug;
	  kill KILL => @pidToKill;
	  undef @pidToKill;
	}
	#while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	return 0;
}

sub Pause	{kill STOP=>$ChildPID if $ChildPID}
sub Resume	{kill CONT=>$ChildPID if $ChildPID}
sub SkipTo	{}

sub SetVolume	{}
sub GetVolume	{-1}
sub GetVolumeError { _"Can't change the volume in non-gstreamer iceserver mode" }
sub GetMute	{0}

1;
