# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Play_123;
use strict;
use warnings;
use IO::Handle;

use POSIX ':sys_wait_h';	#for WNOHANG in waitpid
#use IPC::Open3;		#for open3 to read STDERR from ogg123 / mpg321 in Play function

#$SIG{CHLD} = 'IGNORE';  # to make sure there are no zombies #cause crash after displaying a file dialog and then runnning an external command with mandriva's gtk2
#$SIG{CHLD} = sub { while (waitpid(-1, WNOHANG)>0) {} };

my (@cmd_and_args,$file,$ChildPID,$WatchTag,$WatchTag2,$OUTPUTfh,@pidToKill);
my ($CMDfh,$RemoteMode);
my %cmds;
my $alsa09;
my %cmdname=(mp3 => 'mpg321', ogg => 'ogg123', flac => 'flac123');

our @ISA=('Play_amixer'); #use amixer for volume

sub init
{	Play_amixer::init();

	for my $ext (keys %cmdname)
	{	my $cmd=$cmdname{$ext};
		for my $path (split /:/, $ENV{PATH})
		{	if (-x $path.::SLASH.$cmd)
			 {$cmds{$ext}=$path.::SLASH.$cmd;last;}
		}
		unless ($cmds{$ext}) { warn "$cmd not found. $ext files won't be played through the 123 output.\n"; }
	}

	return unless keys %cmds;
	return bless {},__PACKAGE__;
}

sub Close {}

sub supported_formats
{	return keys %cmds;
}

sub Play
{	(undef,$file,my$sec)=@_;
	&Stop if $ChildPID;
	@cmd_and_args=();
	my $device_option;
	$RemoteMode=0;
	my $device=$::Options{Device};
	my ($type)= $file=~m/\.([^.]*)$/;
	$type=lc$type;
	if	($type eq 'mp3' && $cmds{mp3})
	{	@cmd_and_args=($cmds{mp3},'-b','2048','-v'); $device_option='-o';
		if ($sec)
		{	my $samperframe=1152;
			$samperframe=  $1==1 ? 384 : $2==2 ? 576 : 1152  if $::Songs[$::PlayingID][::SONG_FORMAT]=~m/mp3 l(\d)v(\d)/;
			my $framepersec= ($::Songs[$::PlayingID][::SONG_SAMPRATE]||44100)/$samperframe;
			$sec=sprintf '%.0f',$sec*$framepersec;
		}
	}
	elsif	($type eq 'ogg' && $cmds{ogg})
	{	@cmd_and_args=($cmds{ogg},'-b','2048'); $device_option='-d';
		$device=~s/^alsa/alsa09/ if (defined $alsa09 ? $alsa09 : $alsa09=qx($cmds{ogg})=~m/alsa09/); #check if ogg123 calls alsa "alsa09" or "alsa"
	}
	elsif	($type eq 'flac' && $cmds{flac})
	{	@cmd_and_args=($cmds{flac},'-R'); $device_option='-d';
		$RemoteMode=1;
	}
	unless (@cmd_and_args) { my $hint=''; $hint="\n\n".::__x(_"{command} is needed to play this file.",command => $cmdname{$type}) if $cmdname{$type}; ::ErrorPlay( ::__x(_"Don't know how to play {file}", file => $file).$hint ); return undef; }
	push @cmd_and_args,$device_option,$device unless $device eq 'default';
	push @cmd_and_args,split / /,$::Options{'123options_'.$type} if $::Options{'123options_'.$type};
	unless ($RemoteMode)
	{	push @cmd_and_args,'-k',$sec if $sec;
		push @cmd_and_args, '--',$file;
	}
	#################################################
	#$ChildPID=open3(my $fh, $OUTPUTfh, $OUTPUTfh, @cmd_and_args, $file);
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
	if ($RemoteMode)
	{	$CMDfh->autoflush(1);
		print $CMDfh "LOAD $file\n";
		SkipTo(undef,$sec) if $sec;
	}
	$OUTPUTfh->blocking(0); #set non-blocking IO
	warn "playing $file (pid=$ChildPID)\n";
	$WatchTag= Glib::IO->add_watch(fileno($OUTPUTfh),'hup',\&_eos_cb);
	$WatchTag2=	$RemoteMode ?
		Glib::IO->add_watch(fileno($OUTPUTfh),'in',\&_remotemsg) :
		Glib::Timeout->add(500,\&_UpdateTime)			 ;
}

sub _eos_cb
{	#close $OUTPUTfh;
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	Glib::Source->remove($WatchTag);
	Glib::Source->remove($WatchTag2);
	$WatchTag=$WatchTag2=$ChildPID=undef;
	_UpdateTime('check_error') unless $::PlayTime;
	::end_of_file;
	return 1;
}

sub _remotemsg
{	my $buf;
	my @line=(<$OUTPUTfh>);
	my $line=pop @line; #only read the last line
	chomp $line;
	if ($line=~m/^\@P 0$/) {print $CMDfh "QUIT\n"}	#finished or stopped
	elsif ($line=~m/^\@F \d+ \d+ (\d+)\.\d\d \d+\.\d\d$/)
	{	::UpdateTime( $1 );
	}
	elsif ($line=~m/^\@E(.*)$/) {print $CMDfh "QUIT\n";error($1)} #Error
	#else {warn $line."\n"}
	return 1;
}

sub Pause
{	if ($RemoteMode) { print $CMDfh "PAUSE\n" }
	elsif ($ChildPID) {kill STOP=>$ChildPID};
}
sub Resume
{	if ($RemoteMode) { print $CMDfh "PAUSE\n" }
	elsif ($ChildPID) {kill CONT=>$ChildPID;}
}

sub SkipTo
{	my $sec=$_[1];
	if ($RemoteMode)
	{	::setlocale(::LC_NUMERIC, 'C'); #flac123 ignores decimals anyway
		print $CMDfh "JUMP $sec\n";
		::setlocale(::LC_NUMERIC, '');
	}
	else { Play(undef,$file,$sec); }
}


sub Stop
{	if ($WatchTag)
	{	Glib::Source->remove($WatchTag);
		Glib::Source->remove($WatchTag2);
		$WatchTag=$WatchTag2=undef;
	}
	if ($ChildPID)
	{	print $CMDfh "QUIT\n" if $RemoteMode;
		warn "killing $ChildPID\n" if $::debug;
		#close $OUTPUTfh;
		#kill 15,$ChildPID;
		kill 2,$ChildPID;
		Glib::Timeout->add( 200,\&_Kill_timeout ) unless @pidToKill;
		push @pidToKill,$ChildPID;
		undef $ChildPID;
	}
}
sub _Kill_timeout	#make sure old children are dead
{	@pidToKill=grep kill(0,$_), @pidToKill;
	if (@pidToKill)
	{ warn "killing -9 @pidToKill\n" if $::debug;
	  kill 9,@pidToKill;
	  undef @pidToKill;
	}
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	return 0;
}

sub _UpdateTime
{	unless ($ChildPID || $_[0] eq 'check_error')
	{	::ResetTime();
		return 0;
	}
	#seek $OUTPUTfh,-80,2;
	my $buf;
	#$_=$buf while (my $l=sysread($OUTPUTfh,$buf,100) && $l==100);
	#$_.=$buf;
	sysread($OUTPUTfh,$buf,10000);
	my $line=substr $buf,-100;
	if ($line=~m/\D: +(\d\d):(\d\d).\d\d/)
	{	::UpdateTime( $1*60+$2 );
	}
	elsif ($buf=~m/(Can't find a suitable libao driver)/)	{error($1);}
	elsif ($buf=~m/(Error: Cannot open device \w+)/)	{error($1);}
	elsif ($buf=~m/(No such device \w+)/)			{error($1);}
	return 1;
}

sub error
{	::ErrorPlay(join(' ',@cmd_and_args)." :\n".$_[0]);
}

sub AdvancedOptions
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	for my $type (sort keys %cmdname)
	{	my $hbox=::NewPrefEntry('123options_'.$type, ::__x(_"{cmd} options :",cmd=>$cmdname{$type}),undef,$sg1,$sg2);
		$hbox->set_sensitive(0) unless $cmds{$type};
		$vbox->pack_start($hbox,::FALSE,::FALSE,2);
	}
	my $hbox=Play_amixer->make_option_widget;

	$vbox->pack_start($hbox,::FALSE,::FALSE,2);
	return $vbox;
}

package Play_amixer;
my ($mixer,$Mute,$Volume,$VolumeError);

sub init
{	return if $Volume;
	$Volume=-2;$Mute=0;
	for my $path (split /:/, $ENV{PATH})
	{	if (-x $path.::SLASH.'amixer') {$mixer=$path.::SLASH.'amixer';last;}
	}

#	if ($mixer)
#	{	SetVolume();
		#Glib::Timeout->add(5000,\&SetVolume);
#	}
	unless ($mixer) {warn "amixer not found, won't be able to get/set volume through the 123 or mplayer output.\n"}

}

sub GetVolume
{	if ($Volume==-2)
	{	$Volume=-1;
		{	last unless $mixer;
			my @list=get_amixer_SMC_list();;
			my %h; $h{$_}=1 for @list;
			my $c=\$::Options{amixerSMC};
			if ($$c) { SetVolume(); last if $Volume>=0 || $h{$$c}; $$c=''; }
			if	($h{PCM})	{$$c='PCM'}
			elsif	($h{Master})	{$$c='Master'}
			else	{ warn "Don't know what mixer to choose among : @list\n"; }
		}
		SetVolume();

	}
	return $Volume;
}
sub GetVolumeError
{	!$mixer ? _"Can't change the volume. Needs amixer (packaged in alsa-utils) to change volume when using this audio backend." :
	!$::Options{amixerSMC} ? _"You must choose a mixer control in the advanced options" :
	_"Error running amixer";

}
sub GetMute	{$Mute}
sub SetVolume
{	shift;
	my $inc=$_[0];
	return unless $mixer;
	my $cmd=$mixer;
	if ($inc)	{ if ($inc=~m/^([+-])?(\d+)$/) { $inc=$2.'%'.($1||''); }
			  $cmd.=" set '$::Options{amixerSMC}' $inc";
			}
	else		{ $cmd.=" get '$::Options{amixerSMC}'";	}
	warn "volume command : $cmd\n" if $::debug;
	my $oldvol=$Volume;
	my $oldm=$Mute;
	open VOL,'-|',$cmd;
	while (<VOL>)
	{	if (m/ \d+ \[(\d+)%\](?:.*?\[(on|off)\])?/)
		{	$Volume=$1;
			$Mute=($2 && $2 ne 'on')? 1 : 0;
			last;
		}
	}
	close VOL;
	return 1 unless ($oldvol!=$Volume || $oldm!=$Mute);
	::HasChanged('Vol');
	1;
}

sub make_option_widget
{	my $hbox=::NewPrefCombo(amixerSMC => [get_amixer_SMC_list()],_"amixer control :",sub {SetVolume()});
	$hbox->set_sensitive(0) unless $mixer;
	return $hbox;
}

sub get_amixer_SMC_list
{	return () unless $mixer;
	my (@list,$SMC);
	open VOL,'-|',$mixer;
	while (<VOL>)
	{	if (m/^Simple mixer control '([^']+)'/)
		{	$SMC=$1;
		}
		elsif ($SMC && m/ \d+ \[(\d+)%\](?: \[(\w+)\])?/)
		{	push @list,$SMC; $SMC=undef;
		}
	}
	close VOL;
	return @list;
}

1;
