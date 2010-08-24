# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin MPRIS
name	MPRIS v1
title	MPRIS v1 support
desc	Allows controlling gmusicbrowser via DBus using the MPRIS v1.0 standard
req	perl(Net::DBus, libnet-dbus-perl perl-Net-DBus)
version 1.0
=cut

package GMB::Plugin::MPRIS;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_MPRIS_',
};

my $bus=$GMB::DBus::bus;
die "Requires DBus support to be active\n" unless $bus; #only requires this to use the hack in gmusicbrowser_dbus.pm so that Net::DBus::GLib is not required, else could do just : use Net::DBus::GLib; $bus=Net::DBus::GLib->session;

my @Objects;

sub Start
{	my $service= $bus->export_service('org.mpris.gmusicbrowser');
	push @Objects, GMB::DBus::MPRIS->new($service);
	#push @Objects, GMB::DBus::MPRIS::TrackList->new($Objects[0]);
	#push @Objects, GMB::DBus::MPRIS::Player->new($Objects[0]);
	push @Objects, GMB::DBus::MPRIS::TrackList->new($service);
	push @Objects, GMB::DBus::MPRIS::Player->new($service);
	#warn $_->get_object_path for @Objects;
}
sub Stop
{	::UnWatch_all($_) for @Objects;
	$_->disconnect for @Objects;
	@Objects=();
}

sub prefbox {}

package GMB::DBus::MPRIS;

use base 'Net::DBus::Object';
use Net::DBus::Exporter 'org.freedesktop.MediaPlayer';

sub new
{	my ($class,$service) = @_;
	my $self = $class->SUPER::new($service, '/');
	bless $self, $class;
	return $self;
}

dbus_method('Identity', [], ['string']);
sub Identity
{	return 'gmusicbrowser '.::VERSIONSTRING;
}
dbus_method('Quit', [], [],{no_return=>1});
sub Quit
{	::Quit();
}
dbus_method('MprisVersion', [], [['struct','uint16','uint16']]);
sub MprisVersion
{	return [1,0];
}

package GMB::DBus::MPRIS::TrackList;

use base 'Net::DBus::Object';
use Net::DBus::Exporter 'org.freedesktop.MediaPlayer';
use Net::DBus ':typing'; #for dbus_uint32, dbus_double

sub new
{	my ($class,$service) = @_;
	my $self = $class->SUPER::new($service, '/TrackList');
	bless $self, $class;
	::Watch($self,Playlist	=> \&TrackListChange);
	::Watch($self,Sort	=> \&TrackListChange);
	return $self;
}

sub GetMetadata_from
{	my $ID=shift;
	return {} unless defined $ID;
	my %h;
	$h{$_}=Songs::Get($ID,$_) for qw/title album artist comment length track disc year album_artist uri album_picture rating bitrate samprate/;
	my $r=delete $h{rating};
	if (defined $r && length $r) { ::setlocale(::LC_NUMERIC, 'C'); $h{rating}=dbus_double($r/20); ::setlocale(::LC_NUMERIC, ''); }
	if (my $pic= delete $h{album_picture}) #FIXME use ~album.picture.uri when available
	{	$h{arturl}= 'file://'.::url_escape($pic); # ignore picture embedded in mp3/flac files ?
	}
	$h{mtime}= 		$h{'length'}*1000;
	$h{'time'}=		delete $h{'length'};
	$h{location}=		delete $h{uri};
	$h{tracknumber}=	delete $h{track};
	$h{'audio-samplerate'}=	delete $h{samprate};
	$h{'audio-bitrate'}=	delete $h{bitrate};
	$h{$_}=dbus_uint32($h{$_}) for qw/time mtime year audio-bitrate audio-samplerate disc/;
	return \%h;
}

dbus_method('GetMetadata', ['int32'], [['dict', 'string', ["variant"]]]);
sub GetMetadata
{	my ($self,$pos)=@_;
	my $ID= $::ListPlay->[$pos];
	GetMetadata_from($ID);
}
dbus_method('GetCurrentTrack', [], ['int32']);
sub GetCurrentTrack
{	my $p=$::Position;
	$p=::FindPositionSong($::SongID,$::ListPlay) unless defined $p; #random mode or song not in playlist
	$p=0 unless defined $p;		# fallback to 0, not really a good idea, but don't know what else to return if current song is not in playlist
	return $p;
}
dbus_method('GetLength', [], ['int32']);
sub GetLength
{	return scalar @$::ListPlay;
}
dbus_method('AddTrack', ['string','bool'], ['int32']);
sub AddTrack
{	my ($self,$uri,$playnow)=@_;
	$uri=~s/ /%20/g;	#Uris_to_IDs split spaces FIXME Uris_to_IDs shouldn't do that
	my ($ID)= @{::Uris_to_IDs($uri)};
	return 1 unless defined $ID;
	$::ListPlay->Push([$ID]);
	::Select(song => $ID, play=>1) if $playnow;
	return 0; #success
}
dbus_method('DelTrack', ['int32'], [],{no_return=>1});
sub DelTrack
{	my ($self,$pos)=@_;
	$::ListPlay->Remove([$pos]);
}
dbus_method('SetLoop', ['bool'], [],{no_return=>1});
sub SetLoop
{	my ($self,$on)=@_;
	::SetRepeat($on);
}
dbus_method('SetRandom', ['bool'], [],{no_return=>1});
sub SetRandom
{	my ($self,$on)=@_;
	my $israndom= ($::RandomMode || $::Options{Sort}=~m/shuffle/);
	::ToggleSort() if $israndom xor $on;
}

dbus_signal(TrackListChange => ['int32']);
sub TrackListChange
{	$_[0]->emit_signal( TrackListChange => scalar @$::ListPlay );
}

package GMB::DBus::MPRIS::Player;

use base 'Net::DBus::Object';
use Net::DBus::Exporter 'org.freedesktop.MediaPlayer';

sub new
{	my ($class,$service) = @_;
	my $self = $class->SUPER::new($service, '/Player');
	bless $self, $class;
	::Watch($self, PlayingSong => \&TrackChange);
	::Watch($self, $_ => \&StatusChange)	for qw/Sort Playing Lock Repeat/;
	::Watch($self, $_ => \&CapsChange)	for qw/Sort Repeat Playlist CurSongID/;
	return $self;
}

dbus_method('Next', [], [],{no_return=>1});
sub Next
{	::NextSong();
}
dbus_method('Prev', [], [],{no_return=>1});
sub Prev
{	::PrevSong();
}
dbus_method('Pause', [], [],{no_return=>1});
sub Pause
{	::Pause();
}
dbus_method('Stop', [], [],{no_return=>1});
sub Stop
{	::Stop();
}
dbus_method('Play', [], [],{no_return=>1});
sub Play
{	::Play();
}
dbus_method('Repeat', ['bool'], [],{no_return=>1});
sub Repeat
{	my ($self,$on)=@_;
	::ToggleLock('fullfilename',$on);
}
dbus_method('GetStatus', [], [['struct','int32','int32','int32','int32']]);
sub GetStatus
{	my $playstop=	$::TogPlay ? 0 : defined $::TogPlay ? 1 : 2;		#0 = Playing, 1 = Paused, 2 = Stopped
	my $israndom=	($::RandomMode || $::Options{Sort}=~m/shuffle/) ? 1 : 0;
	my $repeat=	($::TogLock && $::TogLock eq 'fullfilename') ? 1 : 0;
	my $loop=	$::Options{Repeat} ? 1 : 0;
	return [$playstop, $israndom, $repeat, $loop];
}
dbus_method('GetMetadata', [], [['dict', 'string', ["variant"]]]);
sub GetMetadata
{	GMB::DBus::MPRIS::TrackList::GetMetadata_from($::SongID);
}
dbus_method('GetCaps', [], ['int32']);
sub GetCaps
{	my $go_next= @$::ListPlay>1 && ( $::RandomMode || $::Options{Repeat} || $::Position<$#$::ListPlay);
	my $go_prev= @$::Recent && ($::RecentPos||0) < $#$::Recent;
	my $pause=  defined $::SongID;
	my $play=   defined $::SongID;
	my $seek=1;
	my $provide_metadata=1;
	#my $has_tracklist= $::RandomMode ? 0 : 1;
	my $has_tracklist=1;
	my $caps=my $i=0;
	for my $cap ($go_next, $go_prev, $pause, $play, $seek, $provide_metadata, $has_tracklist)
	{	$caps+= 1<<$i if $cap;
		$i++;
	}
	return $caps;
}

dbus_method('VolumeSet', ['int32'], []);
sub VolumeSet
{	::UpdateVol($_[1]);
}
dbus_method('VolumeGet', [], ['int32']);
sub VolumeGet
{	return ::GetVol();
}

dbus_method('PositionSet', ['int32'], []);
sub PositionSet
{	::SkipTo($_[1]/1000)
}
dbus_method('PositionGet', [], ['int32']);
sub PositionGet
{	return ($::PlayTime || 0)*1000;
}

dbus_signal(TrackChange => [['dict', 'string', ["variant"]]]);
sub TrackChange
{	$_[0]->emit_signal( TrackChange => GetMetadata() );
}
dbus_signal(StatusChange => [['struct','int32','int32','int32','int32']]);
sub StatusChange
{	$_[0]->emit_signal( StatusChange => GetStatus() );
}
dbus_signal(CapsChange => ['int32']);
sub CapsChange
{	$_[0]->emit_signal( CapsChange => GetCaps() );
}

1
