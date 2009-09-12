# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Play_mplayer;
use strict;
use warnings;
use IO::Handle;

use POSIX ':sys_wait_h';	#for WNOHANG in waitpid

#$SIG{CHLD} = 'IGNORE';  # to make sure there are no zombies #cause crash after displaying a file dialog and then runnning an external command with mandriva's gtk2
#$SIG{CHLD} = sub { while (waitpid(-1, WNOHANG)>0) {} };

my (@cmd_and_args,$file,$ChildPID,$WatchTag,$WatchTag2,$OUTPUTfh,@pidToKill,$Kill9);
my $CMDfh;
my (%supported,$mplayer);
my ($Mute,$Volume);

$::PlayPacks{Play_mplayer}=1; #register the package

sub init
{	$Volume=100;
	$Mute=0;

	$mplayer=undef;
	for my $path (split /:/, $ENV{PATH})
	{	if (-x $path.::SLASH.'mplayer')
		 {$mplayer=$path.::SLASH.'mplayer';last;}
	}

	return unless $mplayer;
	return bless {},__PACKAGE__;
}

sub Close {}

sub supported_formats
{	return () unless $mplayer;
	unless (keys %supported)
	{for (qx($mplayer -msglevel all=4 -ac help))
	 {	if	(m/^(?:mad|ffmp3)\W.*working/){$supported{mp3}=undef}
		elsif	(m/^vorbis.*working/)	{$supported{oga}=undef}
		elsif	(m/^musepack.*working/)	{$supported{mpc}=undef}
		elsif	(m/^ffflac.*working/)	{$supported{flac}=undef}
		elsif	(m/^ffwavpack.*working/){$supported{wv}=undef}
		elsif	(m/^ffape.*working/)	{$supported{ape}=undef}
		elsif	(m/^ffaad.*working/)	{$supported{m4a}=undef}
	 }
	}
	return keys %supported;
}

sub Play
{	(undef,$file,my$sec)=@_;
	&Stop if $ChildPID;
	#if ($ChildPID) { print $CMDfh "loadfile $file\n"; print $CMDfh "seek $sec 2\n" if $sec; return}
	@cmd_and_args=($mplayer,qw/-nocache -slave -vo null -softvol/);
	#push @cmd_and_args, '-volume',$Volume; # -volume option is too recent (31-10-2008)
	warn "@cmd_and_args\n" if $::debug;
	#push @cmd_and_args,$device_option,$device unless $device eq 'default';
	push @cmd_and_args,split / /,$::Options{mplayeroptions} if $::Options{mplayeroptions};
	push @cmd_and_args,'-ss',$sec if $sec;
	push @cmd_and_args,'-ac','ffwavpack' if $file=~m/\.wvc?$/;
	push @cmd_and_args,'-ac','ffape' if $file=~m/\.ape$/;
	push @cmd_and_args, '--',$file;

	pipe $OUTPUTfh,my$wfh;
	pipe my($rfh),$CMDfh;
	$ChildPID=fork;
	if ($ChildPID==0) #child
	{	close $OUTPUTfh; close $CMDfh;
		open \*STDIN, '<&='.fileno $rfh;
		open \*STDOUT,'>&='.fileno $wfh;
		open \*STDERR,'>&='.fileno $wfh;
		exec @cmd_and_args;
		die "launch failed : @cmd_and_args\n"; #FIXME never happens
	}
	elsif (!defined $ChildPID) { warn "fork failed\n" } #FIXME never happens
	close $wfh; close $rfh;
	$CMDfh->autoflush(1);
	print $CMDfh "volume $Volume 1\n"; #set the initial volume here instead of using the too recent -volume option
	#print $CMDfh "LOAD $file\n";
	#SkipTo(undef,$sec) if $sec;

	$OUTPUTfh->blocking(0); #set non-blocking IO
	warn "playing $file (pid=$ChildPID)\n";
	$WatchTag= Glib::IO->add_watch(fileno($OUTPUTfh),'hup',\&_eos_cb);
	$WatchTag2=Glib::IO->add_watch(fileno($OUTPUTfh),'in',\&_remotemsg);
		#Glib::Timeout->add(500,\&_UpdateTime);
}

sub _eos_cb
{	#close $OUTPUTfh;
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	Glib::Source->remove($WatchTag);
	Glib::Source->remove($WatchTag2);
	$WatchTag=$WatchTag2=$ChildPID=undef;
	::end_of_file;
	return 1;
}

sub _remotemsg
{	my $buf;
	my @line=(<$OUTPUTfh>);
	my $line=pop @line; #only read the last line
	chomp $line;
	if ($line=~m/^A:\s*(\d+).\d /)
	{	::UpdateTime( $1 );
	}
	elsif ($::debug) {warn "mplayer:$_\n" for @line,$line}
	return 1;
}

sub Pause
{	print $CMDfh "pause\n";
}
sub Resume
{	print $CMDfh "pause\n";
}

sub SkipTo
{	my $sec=$_[1];
	::setlocale(::LC_NUMERIC, 'C');
	print $CMDfh "seek $sec 2\n";
	::setlocale(::LC_NUMERIC, '');
}


sub Stop
{	if ($WatchTag)
	{	Glib::Source->remove($WatchTag);
		Glib::Source->remove($WatchTag2);
		$WatchTag=$WatchTag2=undef;
	}
	if ($ChildPID)
	{	print $CMDfh "quit\n";
		#close $OUTPUTfh;
		Glib::Timeout->add( 100,\&_Kill_timeout ) unless @pidToKill;
		$Kill9=0;	#_Kill_timeout will first try INT, then KILL
		push @pidToKill,$ChildPID;
		undef $ChildPID;
	}
}
sub _Kill_timeout	#make sure old children are dead
{	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	@pidToKill=grep kill(0,$_), @pidToKill; #checks to see which ones are still there
	if (@pidToKill)
	{	warn "Sending ".($Kill9 ? 'KILL' : 'INT')." signal to @pidToKill\n" if $::debug;
		if ($Kill9)	{kill KILL=>@pidToKill;}
		else		{kill INT=>@pidToKill;}
		$Kill9=1;	#use KILL if they are still there next time
	}
	return @pidToKill;	#removes the timeout if no more @pidToKill
}

sub error
{	::ErrorPlay(join(' ',@cmd_and_args)." :\n".$_[0]);
}

sub AdvancedOptions
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $hbox0=::NewPrefEntry('mplayeroptions',_"mplayer options :");
	$vbox->pack_start($hbox0,::FALSE,::FALSE,2);
	return $vbox;
}

# Volume functions
sub GetVolume	{$Volume}
sub GetMute	{$Mute}
sub SetVolume
{	shift;
	my $set=shift;
	if	($set eq 'mute')	{ $Mute=$Volume; $Volume=0;	}
	elsif	($set eq 'unmute')	{ $Volume=$Mute; $Mute=0;	}
	elsif	($set=~m/^\+(\d+)$/)	{ $Volume+=$1; }
	elsif	($set=~m/^-(\d+)$/)	{ $Volume-=$1; }
	elsif	($set=~m/(\d+)/)	{ $Volume =$1; }
	$Volume=0   if $Volume<0;
	$Volume=100 if $Volume>100;
	print $CMDfh "volume $Volume 1\n" if $ChildPID;
	::HasChanged('Vol');
}

#sub sendcmd {print $CMDfh "$_[0]\n";} #DEBUG #Play_mplayer::sendcmd('volume 0')
1;
