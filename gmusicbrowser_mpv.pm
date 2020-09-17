# Copyright (C) 2005-2015 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Play_mpv;
use strict;
use warnings;
use IO::Socket::UNIX;
use JSON::PP;
use Time::HiRes 'sleep';

use POSIX ':sys_wait_h';	#for WNOHANG in waitpid

#$SIG{CHLD} = 'IGNORE';  # to make sure there are no zombies #cause crash after displaying a file dialog and then runnning an external command with mandriva's gtk2
#$SIG{CHLD} = sub { while (waitpid(-1, WNOHANG)>0) {} };

my (@cmd_and_args,$ChildPID,$WatchTag,$WatchTag2,@pidToKill,$Kill9);
my $sockfh;
my (%supported,$mpv);
my $preparednext;
my ($Called_from_eof,$gmb_file,$mpv_file,$Last_messages);
my $initseek;
my $watcher;
my $version;
my @cmd_queue;

my $SOCK = $::HomeDir."gmb_mpv_sock";

$::PlayPacks{Play_mpv}=1; #register the package

sub init
{	undef %supported;
	$mpv= $::Options{mpv_cmd};
	if ($mpv && !-x $mpv && !(::first { -x $_ } map $_.::SLASH.$mpv,  split /:/, $ENV{PATH}))
	{	$mpv=undef;
	}
	$mpv ||= ::first { -x $_ } map $_.::SLASH.'mpv',  split /:/, $ENV{PATH};
	
	warn "mpv: found mpv version $version\n" if $version && $::debug;
	if (!check_version(0, 7))
	{	$mpv=undef;
		warn "mpv version earlier than 0.7 are not supported -> mpv backend disabled\n"
	}
	return unless $mpv;
	return bless {RG=>1,EQ=>1},__PACKAGE__;
}

sub get_version
{	return $version if $version;
	return unless $mpv;
	my $output= qx/$mpv -V/;
    my ($v) = ($output =~ /mpv\s*(\S+)\s.*/);
	return $v;
}

sub check_version
{	my ($major,$minor)=@_;
	my $version=get_version();
	my $ok;
	return unless $version;
	if ($version=~m/^(\d+)\.(\d+)(\S+)?$/i) { $ok= $1>$major || $2>=$minor; }
	elsif ($version=~m/^git-[[:xdigit:]]+$/i) { $ok=1; } #assume git version is ok
	else { warn "mpv: error looking up mpv version\n"; }
	return $ok;
}

sub supported_formats
{	return () unless $mpv;
	unless (keys %supported)
	{for (qx($mpv --ad=help))
	 {	if	(m/\Wmp3\W/i)	{$supported{mp3}=undef}
		elsif	(m/\Wvorbis\W/i){$supported{oga}=undef}
		elsif	(m/\Wopus\W/i)	{$supported{opus}=undef}
		elsif	(m/mpc\d/)	{$supported{mpc}=undef}
		elsif	(m/flac\s/)	{$supported{flac}=undef}
		elsif	(m/wavpack\s/)	{$supported{wv}=undef}
		elsif	(m/ape\s/)	{$supported{ape}=undef}
		elsif	(m/\Waac\W/i)	{$supported{m4a}=undef}
	 }
	}
	return keys %supported;
}

sub cmd_push
{	return unless $sockfh;
	my @args=@_;
	my $callback;
	# If the first argument is a subroutine, use it as callback
	if (ref($args[0]) eq 'CODE') { $callback = shift @args; }
	push @cmd_queue, $callback;
	my $cmd = JSON::PP->new->encode({command => \@args});
	print $sockfh "$cmd\n";
	warn "MPVCMD: $cmd\n" if $::debug;
}

sub cmd_shift
{	my $data=shift;
	my $callback = shift @cmd_queue;
	if ($callback) { $callback->($data); }
}

sub launch_mpv
{	$preparednext=undef;
	@cmd_and_args=($mpv, '--input-unix-socket='.$SOCK, qw/--idle --no-video --no-input-terminal --really-quiet --gapless-audio=weak --softvol-max=100 --mute=no --no-sub-auto/);
	push @cmd_and_args,"--volume=".convertvolume($::Volume);
	if ($::Options{use_replaygain})
	{	if(check_version(0,28))
		{
			push @cmd_and_args,"--replaygain=".get_RG_mode();
			push @cmd_and_args,"--replaygain-preamp=".get_RG_preamp();
			push @cmd_and_args,"--replaygain-clip=".$::Options{rg_limiter} ? 'yes' : 'no';
			push @cmd_and_args,"--replaygain-fallback=".($::Options{rg_fallback} || 0);
		} else { push @cmd_and_args,"--af-add=".get_RG_string(); }
	}
	push @cmd_and_args,"--af-add=".get_EQ_string($::Options{equalizer}) if $::Options{use_equalizer};
	push @cmd_and_args,split / /,$::Options{mpvoptions} if $::Options{mpvoptions};
	warn "@cmd_and_args\n" if $::debug;
	$ChildPID=fork;
	if (!defined $ChildPID) { warn "gmusicbrowser_mpv : fork failed : $!\n"; ::ErrorPlay("Fork failed : $!"); return }
	elsif ($ChildPID==0) #child
	{	exec @cmd_and_args  or print STDERR "launch failed (@cmd_and_args)  : $!\n";
		POSIX::_exit(1);
	}
	#wait for mpv to establish socket as server
	for (0 .. 200)
	{	$sockfh = IO::Socket::UNIX->new(Peer => $SOCK, Type => SOCK_STREAM);
		last if $sockfh || (waitpid($ChildPID, WNOHANG) != 0);
		warn "gmusicbrowser_mpv: could not connect to socket; retrying\n" if $::debug;
		sleep 0.01;
	}
	unless ($sockfh)
	{	handle_error("failed to connect to socket (probably failed to launch mpv): $!");
		return;
	}
	$sockfh->autoflush(1);
	$sockfh->blocking(0);
	$WatchTag = Glib::IO->add_watch(fileno($sockfh),'hup',\&_eos_cb);
	$WatchTag2= Glib::IO->add_watch(fileno($sockfh),'in',\&_remotemsg);
	$watcher = {};
	::Watch($watcher,'NextSongs', \&append_next);
	cmd_push('observe_property', 1, 'playback-time');
	cmd_push('request_log_messages', 'error');
	return 1;
}

sub Play
{	my (undef,$file,$sec)=@_;
	launch_mpv() unless $ChildPID && $sockfh;
	return unless $ChildPID;
	$Last_messages="";
	$gmb_file=$file;
	warn "playing $file (pid=$ChildPID)\n" if $::Verbose;
	# gapless - check for non-user-initiated EOF
	return if ($Called_from_eof && $preparednext && $preparednext eq $gmb_file);
	$mpv_file = "";
	$initseek = $sec;
	cmd_push('loadfile', $file);
	cmd_push('playlist_clear');
}

sub append_next
{	$preparednext=undef;
	cmd_push('playlist_clear');
	if ($::NextFileToPlay && $::NextFileToPlay ne $gmb_file)
	{	cmd_push('loadfile', $::NextFileToPlay, 'append');
		$preparednext= $::NextFileToPlay;
	}
}

sub _remotemsg
{	my $eof;
	while (my $line=<$sockfh>)
	{	my $msg= JSON::PP->new->decode($line); # use JSON::PP->new->decode instead of decode_json (equivalent to JSON::PP->new->utf8->decode) because decode_json converts to utf8, which gives error with invalid utf8 filenames (only happens for mpv >0.9.0)
		warn "mpv raw-output: $line" if $::debug;
		if (my $error=$msg->{error})
		{	warn "mpv error: $error" unless $error eq 'success';
			cmd_shift($msg->{data});
		}
		elsif (my $event=$msg->{event})
		{	if ($event eq 'property-change' && $msg->{name} eq 'path') { $mpv_file= $msg->{data}||""; } # doesn't happen when previous file is same as new file
			elsif ($event eq 'file-loaded')
			{	SkipTo(undef,$initseek) if $initseek;
				$initseek=undef;
				cmd_push(sub { $mpv_file=shift; }, ('get_property', 'path'));
				last if $eof; #only do eof now to catch log-message that are only sent after end-file and start-file
			}
			elsif ($mpv_file ne $gmb_file) {} #ignore all other events unless file is current
			elsif ($event eq 'property-change' && $msg->{name} eq 'playback-time' && defined $msg->{data})
			 { ::UpdateTime($msg->{data}); }
			elsif ($event eq 'end-file')	{ $eof=1; } # ignore EOF signal on user-initiated track change as $mpv_file and $gmb_file aren't equal in those cases
			elsif ($event eq 'log-message')
			{	my $error= $msg->{text};
				chomp $error;
				my $time= $::PlayTime||0;
				$Last_messages.= sprintf " %02d:%02d  [%s] %s\n",
					int($time/60), $time%60, $msg->{prefix}, $error;
			}
		}
	}
	handle_eof() if $eof;
	return 1;
}

sub handle_eof
{	if ($::PlayTime < Songs::Get($::SongID,'length')-5) { handle_error(_"Playback ended unexpectedly.") }
	else { $Called_from_eof=1; ::end_of_file(); $Called_from_eof=0; }
}

sub handle_error
{	my $error=shift;
	Stop();
	my $details=_("File").":\n$gmb_file\n\n";
	$details.= _("Last messages:")."\n$Last_messages\n" if $Last_messages;
	$details.= _("Command used:")."\n@cmd_and_args";
	::ErrorPlay($error,$details);
}

sub _eos_cb
{	my $error;
	if ($ChildPID && $ChildPID==waitpid($ChildPID, WNOHANG))
	{	$error=_"Check your audio settings" if $?;
	}
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
	handle_error ($error or "mpv process closed unexpectedly.");
	return 1;
}

sub Pause
{	cmd_push('set', 'pause', 'yes');
}
sub Resume
{	cmd_push('set', 'pause', 'no');
}

sub SkipTo
{	::setlocale(::LC_NUMERIC, 'C');
	my $sec="$_[1]";
	::setlocale(::LC_NUMERIC, '');
	cmd_push('seek', $sec, 'absolute');
}


sub Stop
{	if ($WatchTag)
	{	Glib::Source->remove($WatchTag);
		Glib::Source->remove($WatchTag2);
		$WatchTag=$WatchTag2=undef;
	}
	if ($ChildPID)
	{	cmd_push('quit');
		Glib::Timeout->add( 100,\&_Kill_timeout ) unless @pidToKill;
		$Kill9=0;	#_Kill_timeout will first try INT, then KILL
		push @pidToKill,$ChildPID;
		undef $ChildPID;
	}
	if ($sockfh)
	{	shutdown($sockfh,2);
		close($sockfh);
		unlink $SOCK;
		undef $sockfh;
	}
	if ($watcher)
	{	::UnWatch($watcher,'NextSongs');
		undef $watcher;
	}
	if (@cmd_queue)
	{
		undef @cmd_queue
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

sub AdvancedOptions
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $opt=::NewPrefEntry('mpvoptions',_"mpv options :", sizeg1=>$sg1);
	$vbox->pack_start($_,::FALSE,::FALSE,2), for $opt;
	return $vbox;
}

# Volume functions
sub GetVolume	{$::Volume}
sub GetMute	{$::Mute}
sub SetVolume
{	shift;
	my $set=shift;
	if	($set eq 'mute')	{ $::Mute=$::Volume; $::Volume=0; }
	elsif	($set eq 'unmute')	{ $::Volume=$::Mute; $::Mute=0;   }
	elsif	($set=~m/^\+(\d+)$/)	{ $::Volume+=$1; }
	elsif	($set=~m/^-(\d+)$/)	{ $::Volume-=$1; }
	elsif	($set=~m/(\d+)/)	{ $::Volume =$1; }
	$::Volume=0   if $::Volume<0;
	$::Volume=100 if $::Volume>100;
	my $vol= convertvolume($::Volume);
	cmd_push('set', 'volume', $vol);
	::HasChanged('Vol');
	$::Options{Volume}=$::Volume;
	$::Options{Volume_mute}=$::Mute;
}

sub convertvolume
{	my $vol=$_[0];
	#$vol= 100*($vol/100)**3;	#convert a linear volume to cubic volume scale #doesn't seem to be needed in mpv
	# will be sent to mpv as string, make sure it use a dot as decimal separator
	::setlocale(::LC_NUMERIC, 'C');
	$vol="$vol";
	::setlocale(::LC_NUMERIC, '');
	return $vol;
}

sub get_EQ_string
{	my $val=shift;
	if (check_version(0, 28))
	{	my @freqs = (29, 59, 119, 237, 474, 947, 1900, 3800, 7500, 15000);
		my @gains = split /:/, $val;
		my $fireq_string = "gain_entry=";
		my @entries;
		for my $i (0 .. $#freqs)
		{	push @entries, "entry(".$freqs[$i].",".$gains[$i].")";
		}
		return "\@EQ:lavfi=[firequalizer=gain_entry='".(join ';', @entries)."']";
	}
	else { return '@EQ:equalizer='.$val; }
}

sub set_equalizer
{	my (undef,$val)=@_;
	cmd_push('af', 'add', get_EQ_string($val));
}

sub EQ_Get_Range
{	return (-12,12,'dB');
}
sub EQ_Get_Hz
{	my $i=$_[1];
	# mplayer and GST equalizers use the same bands, but they are indicated differently
	# mplayer docs list band center frequences, GST reports band start freqs. Using GST values here for consistency
	my @bands=(qw/29Hz 59Hz 119Hz 237Hz 474Hz 947Hz 1.9kHz 3.8kHz 7.5kHz 15.0kHz/);
	return $bands[$i];
}

sub get_RG_preamp
{	my $preamp = $::Options{rg_preamp};
	#FIXME: enforce limits in interface
	$preamp = -15 if $::Options{rg_preamp}<-15;
	$preamp = 15 if $::Options{rg_preamp}>15;
	return $preamp;
}

sub get_RG_mode
{	return $::Options{rg_albummode} ? 'album' : 'track';
}

sub get_RG_string
{	my $enable = $::Options{use_replaygain} ? 'yes' : 'no';
	my $mode = $::Options{rg_albummode} ? 'replaygain-album' : 'replaygain-track';
	my $clip = $::Options{rg_limiter} ? 'yes' : 'no';
	my $preamp = get_RG_preamp();
	my $RGstring = "\@RG:volume=0:$mode=$enable:replaygain-clip=$clip:replaygain-preamp=$preamp";
	return $RGstring;
}

sub RG_set_options
{	if (check_version(0, 28))
	{
		if (!$::Options{use_replaygain}) { cmd_push('set', 'replaygain', 'no'); return; }
		cmd_push('set', 'replaygain', get_RG_mode());
		cmd_push('set', 'replaygain-preamp', get_RG_preamp());
		cmd_push('set', 'replaygain-clip', $::Options{rg_limiter} ? 'yes' : 'no');
		cmd_push('set', 'replaygain-fallback', $::Options{rg_fallback} || 0);
	} else
	{
		my $RGstring = get_RG_string();
		cmd_push('af', 'add', $RGstring);
	}
}

1;
