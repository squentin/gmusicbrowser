# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
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
my $alsa09;
our %Commands=
(	mpg321	=> {type => 'mp3', devices => 'oss alsa esd arts sun',	cmdline => \&mpg321_cmdline, },
	ogg123	=> {type => 'oga flac', devices => 'pulse alsa arts esd oss', cmdline => \&ogg123_cmdline,
			priority=> 1, #makes it higher priority than flac123
		   }, #FIXME could check if flac codec is available
	mpg123	=>
		{ type => 'mp3', devices =>  sub { return grep $_ ne 'dummy', map m/^(\w+)\s+output*/g, qx/mpg123 --list-modules/; },
		  remote => { PAUSE => 'P', RESUME => 'P', QUIT => 'Q',
			      LOAD => sub { "L $_[0]" },
			      JUMP => sub { "J $_[0]s" },
			      watcher => \&_remotemsg,
		      	    },
		  cmdline => \&mpg123_cmdline,
		  priority=> 1, #makes it higher priority than mpg321
		},
	flac123	=>
		{ type => 'flac', devices => 'oss esd arts ',
		  remote => { PAUSE => 'P', RESUME => 'P', QUIT => 'Q',
			      LOAD => sub { "L $_[0]" }, JUMP => sub { "J $_[0]" }, watcher => \&_remotemsg,
		      	    },
		  cmdline => \&flac123_cmdline,
		},
);
our %Supported;

our @ISA=('Play_amixer'); #use amixer for volume
$::PlayPacks{Play_123}=1; #register the package

sub init
{	Play_amixer::init();

	my @notfound; my $foundone;
	for my $cmd (sort {($Commands{$b}{priority}||0) <=> ($Commands{$a}{priority}||0)} keys %Commands)
	{	my ($found)= grep -x, map $_.::SLASH.$cmd, split /:/, $ENV{PATH};
		for my $ext (split / /,$Commands{$cmd}{type}) { push @{$Supported{$ext}},$cmd if $found; }
		$Commands{$cmd}{found}=1 if $found;
		if ($found)	{$foundone++}
		else		{push @notfound,$cmd;}
	}
	for my $ext (keys %Supported)
	{	my $cmds=$Supported{$ext};
		my $priority=$::Options{'123priority_'.$ext};
		if ($priority && (grep $priority eq $_, @$cmds)) { $Supported{$ext}=$priority; }
		else { $Supported{$ext}=$cmds->[0]; }
	}
	$Supported{$_}=$Supported{$::Alias_ext{$_}} for grep $Supported{$::Alias_ext{$_}}, keys %::Alias_ext;
	my @missing= grep !$Supported{$_}, qw/mp3 oga flac/;
	if (@missing)
	{	warn "These commands were not found : ".join(', ',@notfound)."\n";
		warn " => these file types won't be played by the 123 output : ".join(', ',@missing)."\n"; #FIXME include aliases
	}

	return unless $foundone;
	return bless {},__PACKAGE__;
}

sub Close {}

sub supported_formats
{	return grep $Supported{$_}, keys %Supported;
}

sub mp3_sec_to_frame	#mpg321 needs a frame number
{	my $sec=$_[0];
	my ($filetype,$samprate)=Songs::Get($::PlayingID,'filetype','samprate');
	my $samperframe=1152;
	$samperframe=  $1==1 ? 384 : $2==2 ? 576 : 1152  if $filetype=~m/mp3 l(\d)v(\d)/;
	my $framepersec= ($samprate||44100)/$samperframe;
	return sprintf '%.0f',$sec*$framepersec;
}
sub mpg321_cmdline
{	my ($file,$sec,$out,@opt)=@_;
	unshift @opt,'-o',$out if $out;
	push @opt,'-k',mp3_sec_to_frame($sec) if $sec;
	return 'mpg321',@opt,'-v','--',$file;
}
sub ogg123_cmdline
{	my ($file,$sec,$out,@opt)=@_;
	if ($out)
	{	$out=~s/^alsa/alsa09/ if (defined $alsa09 ? $alsa09 : $alsa09=qx(ogg123)=~m/alsa09/); #check if ogg123 calls alsa "alsa09" or "alsa"
		unshift @opt,'-d',$out;
	}
	push @opt,'-k',$sec if $sec;
	return 'ogg123',@opt,'--',$file;
}
sub flac123_cmdline
{	my ($file,$sec,$out,@opt)=@_;
	unshift @opt,'-d',$out if $out;
	return 'flac123',@opt,'-R';
}
sub mpg123_cmdline
{	my ($file,$sec,$out,@opt)=@_;
	unshift @opt,'-o',$out if $out;
	return 'mpg123',@opt,'-R';
}

sub Play
{	(undef,$file,my$sec)=@_;
	&Stop if $ChildPID;
	@cmd_and_args=();
	my $device_option;
	my $device=$::Options{Device};
	my ($type)= $file=~m/\.([^.]*)$/;
	$type=lc$type;
	my $cmd=$Supported{$type};
	$RemoteMode=$Commands{$cmd}{remote};
	if ($cmd)
	{	my @extra= split / /, $::Options{'123options_'.$cmd}||'';
		my $out= $::Options{'123device_'.$cmd};
		$out=undef if $out && $out eq 'default';
		@cmd_and_args= $Commands{$cmd}{cmdline}($file,$sec,$out,@extra);
	}
	else
	{	my $hint='';
		#FIXME FIXME
		#$hint= "\n\n".::__x(_"{command} is needed to play this file.",command => $cmdname{$type}) if $cmdname{$type};#FIXME FIXME
		::ErrorPlay( ::__x(_"Don't know how to play {file}", file => $file).$hint );
		return undef;
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
		print $CMDfh $RemoteMode->{LOAD}($file)."\n";
		SkipTo(undef,$sec) if $sec;
	}
	$OUTPUTfh->blocking(0); #set non-blocking IO
	warn "playing $file (pid=$ChildPID)\n";
	$WatchTag= Glib::IO->add_watch(fileno($OUTPUTfh),'hup',\&_eos_cb);
	$WatchTag2=	$RemoteMode ?
		Glib::IO->add_watch(fileno($OUTPUTfh),'in',$RemoteMode->{watcher}) :
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

sub _remotemsg	#used by flac123 and mpg123
{	my $buf;
	my @line=(<$OUTPUTfh>);
	my $line=pop @line; #only read the last line
	chomp $line;
	if ($line=~m/^\@P 0$/) {print $CMDfh $RemoteMode->{QUIT}."\n"}	#finished or stopped
	elsif ($line=~m/^\@F \d+ \d+ (\d+)\.\d\d \d+\.\d\d$/)
	{	::UpdateTime( $1 );
	}
	elsif ($line=~m/^\@E(.*)$/) {print $CMDfh $RemoteMode->{QUIT}."\n";error($1)} #Error
	#else {warn $line."\n"}
	return 1;
}

sub Pause
{	if ($RemoteMode) { print $CMDfh $RemoteMode->{PAUSE}."\n" }
	elsif ($ChildPID) {kill STOP=>$ChildPID};
}
sub Resume
{	if ($RemoteMode) { print $CMDfh $RemoteMode->{RESUME}."\n" }
	elsif ($ChildPID) {kill CONT=>$ChildPID;}
}

sub SkipTo
{	my $sec=$_[1];
	if ($RemoteMode)
	{	::setlocale(::LC_NUMERIC, 'C'); #flac123 ignores decimals anyway
		print $CMDfh $RemoteMode->{JUMP}($sec)."\n";
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
	{	print $CMDfh $RemoteMode->{QUIT}."\n" if $RemoteMode;
		warn "killing $ChildPID\n" if $::debug;
		#close $OUTPUTfh;
		#kill TERM,$ChildPID;
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
	  kill KILL=>@pidToKill;
	  undef @pidToKill;
	}
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	return 0;
}

sub _UpdateTime	#used by ogg123 and mpg321
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
	elsif ( $buf=~m/(Can't find a suitable libao driver)/	||
		$buf=~m/(Error: Cannot open device \w+)/	||
		$buf=~m/(No such device \w+)/)			{error($1);}
	return 1;
}

sub error
{	::ErrorPlay(join(' ',@cmd_and_args)." :\n".$_[0]);
}

sub AdvancedOptions
{	my $vbox=Gtk2::VBox->new;
	my $table=Gtk2::Table->new(1,1,::FALSE);
	my %ext; my %extgroup;
	$ext{$_}=undef for map split(/ /,$Commands{$_}{type}), keys %Commands;
	my @ext=sort keys %ext;
	for my $e (@ext) { $ext{$e}= join '/', $e, sort grep $::Alias_ext{$_} eq $e,keys %::Alias_ext; }
	my $i=my $j=0;
	$table->attach_defaults(Gtk2::Label->new($_), $i++,$i,$j,$j+1) for (_"Command", _"Output", _"Options",map " $ext{$_} ", @ext);
	for my $cmd (sort keys %Commands)
	{	$i=0; $j++;
		my $devs= $Commands{$cmd}{devices};
		my @widgets;
		my @devlist= ref $devs ? $devs->() : split / /,$devs;
		push @widgets,
			Gtk2::Label->new($cmd),
			::NewPrefCombo('123device_'.$cmd => ['default',@devlist]),
			::NewPrefEntry('123options_'.$cmd);
		my %cando; $cando{$_}=undef for split / /,$Commands{$cmd}{type};
		$table->attach_defaults($_, $i++,$i,$j,$j+1) for @widgets;
		for my $ext (@ext)
		{	if (exists $cando{$ext})
			{	my $w=Gtk2::RadioButton->new($extgroup{$ext});
				$::Tooltips->set_tip($w, ::__x(_"Use {command} to play {ext} files",command=>$cmd, ext=>$ext{$ext}) );
				$extgroup{$ext}||=$w;
				$table->attach_defaults($w, $i,$i+1,$j,$j+1);
				push @widgets,$w;
				$w->set_active(1) if $cmd eq ($Supported{$ext} || '');
				$w->signal_connect(toggled => sub { return unless $_[0]->get_active; $Supported{$ext}=$::Options{'123priority_'.$ext}=$cmd; $Supported{$_}=$Supported{$ext} for grep $::Alias_ext{$_} eq $ext, keys %::Alias_ext; });
			}
			$i++;
		}
		unless ($Commands{$cmd}{found}) {$_->set_sensitive(0) for @widgets;}
	}
	$vbox->pack_start($table,::FALSE,::FALSE,2);
	my $hbox=Play_amixer->make_option_widget;

	$vbox->pack_start($hbox,::FALSE,::FALSE,2);
	return $vbox;
}

package Play_amixer;
my ($mixer,$Mute,$Volume);

sub init
{	return if $Volume;
	$Mute=0;
	for my $path (split /:/, $ENV{PATH})
	{	if (-x $path.::SLASH.'amixer') {$mixer=$path.::SLASH.'amixer';last;}
	}

#	if ($mixer)
#	{	SetVolume();
		#Glib::Timeout->add(5000,\&SetVolume);
#	}
	unless ($mixer) {warn "amixer not found, won't be able to get/set volume through the 123 or mplayer output.\n"}

}

sub init_volume
{	$Volume=-1;
	return unless $mixer;
	my @list=get_amixer_SMC_list();;
	my %h; $h{$_}=1 for @list;
	my $c=\$::Options{amixerSMC};
	if ($$c) { SetVolume(); return if $Volume>=0 || $h{$$c}; $$c=''; }
	if	($h{PCM})	{$$c='PCM'}
	elsif	($h{Master})	{$$c='Master'}
	else	{ warn "Don't know what mixer to choose among : @list\n"; }
	SetVolume();
}

sub GetVolume
{	init_volume() unless defined $Volume;
	return $Volume;
}
sub GetVolumeError { _"Can't change the volume. Needs amixer (packaged in alsa-utils) to change volume when using this audio backend." }
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
{	my $hbox=::NewPrefCombo(amixerSMC => [get_amixer_SMC_list()], text =>_"amixer control :", cb =>sub {SetVolume()});
	$hbox->set_sensitive(0) unless $mixer;
	return $hbox;
}

sub get_amixer_SMC_list
{	return () unless $mixer;
	init_volume() unless defined $Volume;
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
