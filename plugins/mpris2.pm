# Copyright (C) 2011 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin MPRIS2
name	MPRIS v2
title	MPRIS v2 support
desc	Allows controlling gmusicbrowser via DBus using the MPRIS v2.0 standard
req	perl(Net::DBus, libnet-dbus-perl perl-Net-DBus)
=cut

package GMB::Plugin::MPRIS2;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_MPRIS2_',
};
use Net::DBus::Annotation 'dbus_call_async';

my $bus=$GMB::DBus::bus;
die "Requires DBus support to be active\n" unless $bus; #only requires this to use the hack in gmusicbrowser_dbus.pm so that Net::DBus::GLib is not required, else could do just : use Net::DBus::GLib; $bus=Net::DBus::GLib->session;

my @Objects;

sub Start
{	my $service= $bus->export_service('org.mpris.MediaPlayer2.gmusicbrowser');
	push @Objects, GMB::DBus::MPRIS2->new($service);
}
sub Stop
{	::UnWatch_all($_) for @Objects;
	$_->disconnect for @Objects;
	@Objects=();
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(0,2);
	my $blacklist= Gtk2::CheckButton->new(_"Show in sound menu");
	soundmenu_button_update($blacklist);
	$blacklist->signal_connect(toggled => \&soundmenu_toggle_cb);
	$vbox->pack_start($blacklist,0,0,0);
	return $vbox;
}

sub soundmenu_button_update
{	my $check=shift;
	eval
	 {	my $service = $bus->get_service('com.canonical.indicators.sound');
		my $object = $service->get_object('/com/canonical/indicators/sound/service');
		my $asyncreply=$object->IsBlacklisted(dbus_call_async,'gmusicbrowser');	#called async, because it seems to trigger the calling of gmb DBus methods before replying
		$check->{busy}=1;
		$asyncreply->set_notify(sub {  soundmenu_button_set($check, eval {$_[0]->get_result;}) });
	 };
	soundmenu_button_set($check,undef) unless $check->{busy};
}
sub soundmenu_button_set
{	my ($check,$on)=@_;
	$check->set_active(1) if !$on;
	if (!defined $on)
	{	$check->set_sensitive(0);
		$check->set_tooltip_text(_"No sound menu found");
	}
	delete $check->{busy};
}
sub soundmenu_toggle_cb
{	my $check=shift;
	return if $check->{busy};
	my $on=$check->get_active;
	eval
	 {	my $service = $bus->get_service('com.canonical.indicators.sound');
		my $object = $service->get_object('/com/canonical/indicators/sound/service');
		$object->BlacklistMediaPlayer('gmusicbrowser',!$on);
	 };
	soundmenu_button_update($check);
}

package GMB::DBus::MPRIS2;

use base 'Net::DBus::Object';
use Net::DBus::Exporter 'org.mpris.MediaPlayer2';
use Net::DBus ':typing';

our %PropChanged;
# events watched by properties of org.mpris.MediaPlayer2.Player that send PropertiesChanged signal
# the functions associated with these properties must bless the return value with dbus_string() and friends
my %PropertiesWatch=
(	PlaybackStatus	=> 'Playing',
	LoopStatus	=> 'Lock Repeat',
	Shuffle		=> 'Sort',
	Metadata	=> 'CurSong',
	Volume		=> 'Vol',
	CanGoNext	=> 'Playlist Sort Queue Repeat',
	CanGoPrevious	=> 'CurSongID',
	CanPlay		=> 'CurSongID',
	#CanSeek	=> 'CurSongID', # always true currently => no need to watch event
);

sub new
{	my ($class,$service) = @_;
	my $self = $class->SUPER::new($service, '/org/mpris/MediaPlayer2');
	bless $self, $class;
	::Watch($self, Seek => \&Seeked);

	#watchers for properties of org.mpris.MediaPlayer2.Player that send PropertiesChanged signal
	my %events;
	for my $prop (sort keys %PropertiesWatch)
	{	push @{ $events{$_} }, $prop for split / /, $PropertiesWatch{$prop};
	}
	for my $event (keys %events)
	{	my $props= $events{$event};
		::Watch($self, $event =>
			sub {	my $self=shift;
				$PropChanged{$_}=1 for @$props;
				::IdleDo('2_MPRIS2_propchanged', 500, \&PropertiesChanged, $self);
			});
	}
	return $self;
}

dbus_signal(PropertiesChanged => ['string',['dict','string',['variant']],['array','string']], 'org.freedesktop.DBus.Properties');
sub PropertiesChanged
{	my $self=shift;
	my %changed;
	for my $name (keys %PropChanged)
	{	no strict "refs";
		$changed{$name}= $name->();
	}
	%PropChanged=();
	$self->emit_signal( PropertiesChanged => 'org.mpris.MediaPlayer2.Player', \%changed,[] );
}

dbus_method('Raise', [], [],{no_return=>1});
sub Raise
{	::ShowHide(1);
}
dbus_method('Quit', [], [],{no_return=>1});
sub Quit
{	::Quit();
}

dbus_property('CanQuit', 'bool', 'read');
sub CanQuit {dbus_boolean(1)}
dbus_property('CanRaise', 'bool', 'read');
sub CanRaise {dbus_boolean(1)}
dbus_property('HasTrackList', 'bool', 'read');
sub HasTrackList {dbus_boolean(0)}
dbus_property('Identity', 'string', 'read');
sub Identity { 'gmusicbrowser' }
dbus_property('DesktopEntry', 'string', 'read');
sub DesktopEntry { 'gmusicbrowser' }
dbus_property('SupportedUriSchemes', ['array','string'], 'read');
sub SupportedUriSchemes { return ['file']; }
dbus_property('SupportedMimeTypes', ['array','string'], 'read');
sub SupportedMimeTypes { return [qw(audio/mpeg application/ogg audio/x-flac audio/x-musepack audio/x-m4a)]; } #FIXME

dbus_method('Next',	[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Next	{ ::NextSong(); }

dbus_method('Previous',	[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Previous	{ ::PrevSong(); }

dbus_method('Pause',	[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Pause	{ ::Pause(); }

dbus_method('PlayPause',[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub PlayPause	{ ::PlayPause(); }

dbus_method('Stop',	[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Stop	{ ::Stop(); }

dbus_method('Play',	[], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Play	{ ::Play(); }

dbus_method('Seek', ['int64'], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub Seek
{	my $offset= $_[1]/1_000_000; #convert from microseconds
	my $sec= $::PlayTime || 0;
	return unless defined $::SongID;
	if ($offset>0)
	{	$sec+=$offset;
		my $length= Songs::Get($::SongID,'length');
		if ($sec>$length) { ::NextSong(); }
		else { ::SkipTo($sec) }
	}
	elsif ($offset<0)
	{	$sec+=$offset;
		if ($sec<0) { ::PrevSong(); }
		else { ::SkipTo($sec) }
	}
}

dbus_method('SetPosition', [['struct','objectpath','int64']], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub SetPosition
{	my ($ID,$position)= @{ $_[1] };
	return unless defined $::SongID && $ID==$::SongID;
	$position/=1_000_000;
	my $length= Songs::Get($::SongID,'length');
	return if $length<0 || $position>$length;
	::SkipTo($position);
}

dbus_method('OpenUri', ['string'], [], 'org.mpris.MediaPlayer2.Player', {no_return=>1});
sub OpenUri
{	my $uri=$_[1];
	my $IDs= ::Uris_to_IDs($uri);
	my $ID= $IDs->[0];
	::Select(song => $ID, play=>1) if defined $ID;
}

dbus_signal(Seeked => ['int64'], 'org.mpris.MediaPlayer2.Player');
sub Seeked
{	$_[0]->emit_signal( Seeked => $_[1]*1_000_000 );
}

dbus_property('PlaybackStatus', 'string', 'read', 'org.mpris.MediaPlayer2.Player');
sub PlaybackStatus
{	my $status=	$::TogPlay ? 'Playing' : defined $::TogPlay ? 'Paused' : 'Stopped';
	return dbus_string($status);
}
dbus_property('LoopStatus', 'string', 'readwrite', 'org.mpris.MediaPlayer2.Player');
sub LoopStatus
{	if (defined $_[1])
	{	my $m=$_[1];
		my $notrack;
		if ($m eq 'None')	{ ::SetRepeat(0); $notrack=1; }
		elsif ($m eq 'Track')	{ ::SetRepeat(1); ::ToggleLock('fullfilename',1); }
		elsif ($m eq 'Playlist'){ ::SetRepeat(1); $notrack=1; }
		if ($notrack && $::TogLock && $::TogLock eq 'fullfilename') { ::ToggleLock('fullfilename') }
	}
	else
	{	my $r=	!$::Options{Repeat} ?				'None' :
			($::TogLock && $::TogLock eq 'fullfilename') ?	'Track' : 'Playlist';
		return dbus_string($r);
	}
}

dbus_property('Rate', 'double', 'readwrite', 'org.mpris.MediaPlayer2.Player');
sub Rate {dbus_double(1)}
dbus_property('MinimumRate', 'double', 'read', 'org.mpris.MediaPlayer2.Player');
sub MinimumRate {dbus_double(1)}
dbus_property('MaximumRate', 'double', 'read', 'org.mpris.MediaPlayer2.Player');
sub MaximumRate {dbus_double(1)}

dbus_property('Shuffle', 'bool', 'readwrite', 'org.mpris.MediaPlayer2.Player');
sub Shuffle
{	my $on= ($::RandomMode || $::Options{Sort}=~m/shuffle/) ? 1 : 0;
	return dbus_boolean($on) if !defined $_[1];
	::ToggleSort() if $_[1] xor $on;
}

dbus_property('Metadata', ['dict','string',['variant']], 'read', 'org.mpris.MediaPlayer2.Player');
sub Metadata
{	GetMetadata_from($::SongID);
}

dbus_property('Volume', 'double', 'readwrite', 'org.mpris.MediaPlayer2.Player');
sub Volume
{	if (defined $_[1]) { my $v=$_[1]; $v=0 if $v<0; ::ChangeVol($v); }
	else { return dbus_double($::Volume/100); }
}

dbus_property('Position', 'int64', 'read', 'org.mpris.MediaPlayer2.Player');
sub Position
{	return dbus_int64( ($::PlayTime||0) *1_000_000 );
}

dbus_property('CanGoNext', 'bool', 'read', 'org.mpris.MediaPlayer2.Player');
sub CanGoNext
{	return dbus_boolean(1) if !defined $::Position && @$::ListPlay;
	return dbus_boolean(1) if @$::Queue;
	return dbus_boolean(0) unless @$::ListPlay>1;
	return dbus_boolean(0) if !$::Options{Repeat} && $::Position==$#$::ListPlay;
	return dbus_boolean(1);
}
dbus_property('CanGoPrevious', 'bool', 'read', 'org.mpris.MediaPlayer2.Player');
sub CanGoPrevious
{	return dbus_boolean( @$::Recent > ($::RecentPos||0) );
}
dbus_property('CanPlay', 'bool', 'read', 'org.mpris.MediaPlayer2.Player');
sub CanPlay
{	return dbus_boolean( defined $::SongID );
}
dbus_property('CanSeek', 'bool', 'read', 'org.mpris.MediaPlayer2.Player');
sub CanSeek
{	return dbus_boolean( defined $::SongID ); #will need to check if stream when supported
}
dbus_property('CanControl', 'bool', 'read', 'org.mpris.MediaPlayer2.Player');
sub CanControl {dbus_boolean(1)}

# 'org.mpris.MediaPlayer2.Player','Metadata'
sub GetMetadata_from
{	my $ID=shift;

	# Net::DBus support for properties is incomplete, the following use undocumented functions to force it to use the correct data types for the returned values
	my $type=
	 [ &Net::DBus::Binding::Message::TYPE_DICT_ENTRY,
		[ &Net::DBus::Binding::Message::TYPE_STRING,
			[ &Net::DBus::Binding::Message::TYPE_VARIANT,
				[],
	 ]]];
	#my ($type)= Net::DBus::Binding::Introspector->_convert(['dict','string',['variant']]); #works too, not sure which one is best

	return Net::DBus::Binding::Value->new($type,{}) unless defined $ID;

	my %h;
	$h{$_}=Songs::Get($ID,$_) for qw/title album artist comment length track disc year album_artist uri album_picture rating bitrate samprate genre playcount/;
	my %r= #return values
	(	'mpris:length'		=> dbus_int64($h{'length'}*1_000_000),
		'mpris:trackid'		=> dbus_string($ID), #FIXME should contain a string that uniquely identifies the track within the scope of the playlist
		'xesam:album'		=> dbus_string($h{album}),
		'xesam:albumArtist'	=> dbus_array([ $h{album_artist} ]),
		'xesam:artist'		=> dbus_array([ $h{artist} ]),
		'xesam:comment'		=> ( $h{comment} ne '' ? dbus_array([$h{comment}]) : undef ),
		'xesam:contentCreated'	=> ($h{year} ? dbus_string($h{year}) : undef), #   ."-01-01T00:00Z" ?
		'xesam:discNumber'	=> ($h{disc} ? dbus_int32($h{disc}) : undef),
		'xesam:genre',		=> dbus_array([split /\x00/, $h{genre}]),
		'xesam:lastUsed',	=> ($h{lastplay} ? dbus_string( ::strftime("%FT%RZ",gmtime($h{lastplay})) ) : undef),
		'xesam:title',		=> dbus_string( $h{title} ),
		'xesam:trackNumber'	=> ( $h{track} ? dbus_int32($h{track}) : undef),
		'xesam:url'		=> dbus_string( $h{uri} ),
		'xesam:useCount'	=> dbus_int32($h{playcount}),
		# FIXME check if field exists
		#'xesam:audioBPM'	=>
		#'xesam:composer'	=> dbus_array([ $h{composer} ]),
		#'xesam:lyricist',	=> dbus_array([ $h{lyricist} ]),
	);
	my $rating=$h{rating};
	if (defined $rating && length $rating) { $r{'xesam:userRating'}=dbus_double($rating/100); }
	if (my $pic= $h{album_picture}) #FIXME use ~album.picture.uri when available
	{	$r{'mpris:artUrl'}= dbus_string( 'file://'.::url_escape($pic) ) if $pic=~m/\.(?:jpe?g|png|gif)$/i; # ignore embedded pictures
	}

	delete $r{$_} for grep !defined $r{$_}, keys %r;

	return Net::DBus::Binding::Value->new($type,\%r);
}

1;

