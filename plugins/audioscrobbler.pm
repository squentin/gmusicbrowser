# Copyright (C) 2005-2010 Quentin Sculo <squentin@free.fr>
#
# Modified to optionally scrobble to libre.fm by Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin AUDIOSCROBBLER
name	last.fm/libre.fm
title	last.fm/libre.fm plugin
desc	Submit played songs to last.fm/libre.fm
=cut


package GMB::Plugin::AUDIOSCROBBLER;
use strict;
use warnings;
use constant
{	CLIENTID => 'gmb', VERSION => '0.1',
	OPT => 'PLUGIN_AUDIOSCROBBLER_', #used to identify the plugin's options
	#SAVEFILE => 'audioscrobbler.queue', #file used to save unsent data
};
use Digest::MD5 'md5_hex';
require $::HTTP_module;

::SetDefaultOptions(OPT, Site => "last.fm", Savefile => "last.fm.queue");

our $ignore_current_song;

my $self=bless {},__PACKAGE__;
my @ToSubmit; my $NowPlaying; my $unsent_saved=0;
my $interval=5; my ($timeout,$waiting);
my ($HandshakeOK,$submiturl,$nowplayingurl,$sessionid);
my ($Serrors,$Stop);
my $Log=Gtk2::ListStore->new('Glib::String');
Load();

sub Start
{	::Watch($self,PlayingSong=> \&SongChanged);
	::Watch($self,Played => \&Played);
	::Watch($self,Save   => \&Save);
	$self->{on}=1;
	Sleep();
	SongChanged() if $::TogPlay;
	$Serrors=$Stop=undef;
}
sub Stop
{	$waiting->abort if $waiting;
	$waiting=undef;
	::UnWatch($self,$_) for qw/PlayingSong Played Save/;
	$self->{on}=undef;
	$interval=5;
	#@ToSubmit=();
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entry1=::NewPrefEntry(OPT.'USER',_"username :", cb => \&userpass_changed, sizeg1 => $sg1,sizeg2=>$sg2);
	my $entry2=::NewPrefEntry(OPT.'PASS',_"password :", cb => \&userpass_changed, sizeg1 => $sg1,sizeg2=>$sg2, hide => 1);
	my @sites = ("last.fm","libre.fm");
	my $label1=Gtk2::Label->new(_"Site :");
	my $label3=Gtk2::Label->new(_"(applied after restart)");
	my $site=::NewPrefCombo(OPT.'Site', \@sites, cb => sub {$::Options{OPT.'Savefile'} = $::Options{OPT.'Site'}.".queue"; } );
	my $hbox=Gtk2::HBox->new();
	$hbox->pack_start($_,0,0,0) for $label1,$site,$label3;
	my $label2=Gtk2::Button->new(_"(see http://www.".$::Options{OPT.'Site'}.")");
	$label2->set_relief('none');
	$label2->signal_connect(clicked => sub
		{	my $url='http://www'.$::Options{OPT.'Site'}.'.fm';
			my $user=$::Options{OPT.'USER'};
			$url.="/user/$user/" if defined $user && $user ne '';
			::openurl($url);
		});
	my $ignore=Gtk2::CheckButton->new(_"Don't submit current song");
	$ignore->signal_connect(toggled=>sub { return if $_[0]->{busy}; $ignore_current_song= $_[0]->get_active ? $::SongID : undef; ::HasChanged('Lastfm_ignore_current'); });
	::Watch($ignore,Lastfm_ignore_current => sub { $_[0]->{busy}=1; $_[0]->set_active(defined $ignore_current_song); delete $_[0]->{busy}; } );
	$vbox->pack_start($_,::FALSE,::FALSE,0) for $label2,$hbox,$entry1,$entry2,$ignore;
	$vbox->add( ::LogView($Log) );
	return $vbox;
}
sub userpass_changed
{	$HandshakeOK=$Serrors=undef;
	$Stop=undef if $Stop && $Stop eq 'BadAuth';
}

sub SongChanged
{	if (defined $ignore_current_song)
	{	return if defined $::SongID && $::SongID == $ignore_current_song;
		$ignore_current_song=undef; ::HasChanged('Lastfm_ignore_current');
	}
	$NowPlaying=undef;
	my ($title,$artist,$album,$track,$length)= Songs::Get($::SongID,qw/title artist album track length/);
	return if $title eq '' || $artist eq '';
	$NowPlaying= [ $artist, $title, $album, $length, $track, '' ];
	Sleep();
}

sub Played
{	my (undef,$ID,undef,$start_time,$seconds,$coverage)=@_;
	return if $ignore_current_song;
	return unless $seconds>10;
	my $length= Songs::Get($ID,'length');
	if ($length>=30 && ($seconds >= 240 || $coverage >= .5) )
	{	my ($title,$artist,$album,$track)= Songs::Get($ID,qw/title artist album track/);
		return if $title eq '' || $artist eq '';
		::IdleDo("9_".__PACKAGE__,10000,\&Save) if @ToSubmit>$unsent_saved;
		push @ToSubmit,[ $artist,$title,$album,'',$length,$start_time,$track,'P' ];
		Sleep();
	}
}

sub Handshake
{	$HandshakeOK=0;
	my $user=$::Options{OPT.'USER'};
	return 0 unless defined $user && $user ne '';
	my $pass=$::Options{OPT.'PASS'};
	my $time=time;
	my $auth=md5_hex(md5_hex($pass).$time);
	my $site;
	if ($::Options{OPT.'Site'} eq "last.fm") { $site = 'post.audioscrobbler.com'; }
	else { $site = 'turtle.libre.fm'; }
	Send(\&response_cb,'http://'.$site.'/?hs=true&p=1.2&c='.CLIENTID.'&v='.VERSION."&u=$user&t=$time&a=$auth");
}

sub response_cb
{	my ($response,@lines)=@_;
	my $error;
	if	(!defined $response)		{$error=_"connection failed";}
	elsif	($response eq 'OK')		{  }
	elsif	($response=~m/^FAILED (.*)$/)	{$error=$1}
	elsif	($response eq 'BADAUTH')	{$error=_("User authentification error"); $Stop='BadAuth';}
	elsif	($response eq 'BANNED')		{$error=_("Client banned, contact gmusicbrowser's developer");	$Stop='Banned';}
	elsif	($response eq 'BADTIME')	{$error=_("System clock is not close enough to the current time"); $Stop='BadTime';}
	else					{$error=_"unknown error";}

	if (defined $error)
	{	unless ($Stop)
		{	$interval*=2;
			$interval=30*60 if $interval>30*60;
			$interval=60 if $interval<60;
			$error.= ::__x( ' (' . _("retry in {seconds} s") . ')', seconds => $interval);
		}
		Log(_("Handshake failed : ").$error);
	}
	else
	{	($sessionid,$nowplayingurl,$submiturl)=@lines;
		$interval=5;
		$HandshakeOK=1;
		$Serrors=0;
		Log(_"Handshake OK");
	}
}

sub Submit
{	my $post="s=$sessionid";
	my $i=0;
	my $url;
	if (@ToSubmit)
	{	while (my $aref=$ToSubmit[$i])
		{	my @data= map { defined $_ ? ::url_escapeall($_) : "" } @$aref;
			$post.=sprintf "&a[$i]=%s&t[$i]=%s&b[$i]=%s&m[$i]=%s&l[$i]=%s&i[$i]=%s&n[$i]=%s&o[$i]=%s&r[$i]=", @data;
			$i++;
			last if $i==50; #don't submit more than 50 songs at a time
		}
		$url=$submiturl;
		return unless $i;
	}
	elsif ($NowPlaying)
	{	my @data= map { defined $_ ? ::url_escapeall($_) : "" } @$NowPlaying;
		$post.= sprintf "&a=%s&t=%s&b=%s&l=%s&n=%s&m=%s", @data;
		$url=$nowplayingurl;
	}
	else {return}
	my $response_cb=sub
	{	my ($response,@lines)=@_;
		my $error;
		if	(!defined $response) {$error=_"connection failed"; $Serrors++}
		elsif	($response eq 'OK')
		{	$Serrors=0;
			if ($i)
			{	Log( _("Submit OK") . ' ('.
				      ($i>1 ?	  ::__("%d song","%d songs",$i)
						: ::__x( _"{song} by {artist}", song=> $ToSubmit[0][1], artist => $ToSubmit[0][0]) ) . ')' );
				splice @ToSubmit,0,$i;
				::IdleDo("9_".__PACKAGE__,10000,\&Save) if $unsent_saved;
			}
			elsif ($NowPlaying)
			{	Log( _("Submit Now-Playing OK") . ' ('.
				    ::__x( _"{song} by {artist}", song=> $NowPlaying->[1], artist => $NowPlaying->[0])  . ')' );
				$NowPlaying=undef;
			}
		}
		elsif	($response eq 'BADSESSION')
		{	$error=_"Bad session";
			$HandshakeOK=0;
		}
		elsif	($response=~m/^FAILED (.*)$/)
		{	$error=$1;
			$Serrors++;
		}
		else	{$error=_"unknown error"; $Serrors++}

		$HandshakeOK=0 if $Serrors && $Serrors>2;

		if (defined $error)
		{	Log(_("Submit failed : ").$error);
		}
	};

	warn "submitting: $post\n" if $::debug;
	Send($response_cb,$url,$post);
}

sub Sleep
{	#warn "Sleep\n";
	return unless $self->{on};
	return if $Stop || $waiting || $timeout;
	$timeout=Glib::Timeout->add(1000*$interval,\&Awake) if @ToSubmit || $NowPlaying;
	#warn "Sleeping $interval seconds\n" if $timeout;
}
sub Awake
{	#warn "Awoke\n";
	$timeout=undef;
	return 0 unless $self->{on};
	if ($HandshakeOK)	{ Submit(); }
	else			{ Handshake(); }
	Sleep();
	return 0;
}
sub Send
{	my ($response_cb,$url,$post)=@_;
	my $cb=sub
	{	my @response=(defined $_[0])? split "\012",$_[0] : ();
		$waiting=undef;
		&$response_cb(@response);
		Sleep();
	};
	$waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => $post);
}

sub Log
{	my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,50)) { $Log->remove($iter); }
}

sub Load 	#read unsent data
{	return unless -r $::HomeDir.$::Options{OPT.'Savefile'};
	return unless open my$fh,'<:utf8',$::HomeDir.$::Options{OPT.'Savefile'};
	while (my $line=<$fh>)
	{	chomp $line;
		my @data=split "\x1D",$line;
		push @ToSubmit,\@data if @data==8;
	}
	close $fh;
	Log(::__("Loaded %d unsent song from previous session","Loaded %d unsent songs from previous session", scalar @ToSubmit));
}
sub Save	#save unsent data to a file
{	$unsent_saved=@ToSubmit;
	unless (@ToSubmit)
	{ unlink $::HomeDir.$::Options{OPT.'Savefile'}; return }
	my $fh;
	unless (open $fh,'>:utf8',$::HomeDir.$::Options{OPT.'Savefile'})
	 { warn "Error creating '$::HomeDir".$::Options{OPT.'Savefile'}."' : $!\nUnsent last.fm data will be lost.\n"; return; }
	print $fh join("\x1D",@$_)."\n" for @ToSubmit;
	close $fh;
}

1;
