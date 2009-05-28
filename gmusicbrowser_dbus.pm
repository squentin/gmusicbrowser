# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

package GMB::DBus::Object;

use base 'Net::DBus::Object';
use Net::DBus::Exporter 'org.gmusicbrowser';

sub new
{	my ($class,$service) = @_;
	my $self = $class->SUPER::new($service, '/org/gmusicbrowser');
	bless $self, $class;

	Glib::Idle->add(
		sub {	::Watch($self,SongID => \&SongChanged);
			::Watch($self,Playing =>\&SongChanged);
			#::Watch($self,Save => \&GMB::DBus::Quit);
			0;
		});

	return $self;
}

dbus_method('RunCommand', ['string'], []);
sub RunCommand
{   my ($self,$cmd) = @_;
    warn "Received DBus command : '$cmd'\n";
    ::run_command(undef,$cmd);
}

dbus_method('CurrentSong', [], [['dict', 'string', 'string']]);
sub CurrentSong
{	#my $self=$_[0];
	return {} unless defined $::SongID;
	my %h=	(	title	=> ::SONG_TITLE,
			album	=> ::SONG_ALBUM,
			artist	=> ::SONG_ARTIST,
			'length'=> ::SONG_LENGTH,
			track	=> ::SONG_TRACK,
			disc	=> ::SONG_DISC,
		);
	$_=$::Songs[$::SongID][$_] for values %h;
	#warn "$h{title}\n";
	return \%h;
}

dbus_method('GetPosition', [], ['double']);
sub GetPosition
{	return $::PlayTime || 0;
}

dbus_method('Playing', [], ['bool']);
sub Playing
{	return $::TogPlay ? 1 : 0;
}

dbus_method('Set', [['struct', 'string', 'string', 'string']], ['bool']);
sub Set
{	my ($self,$array)=@_;
	::SetTagValue(@$array); #return false on error, true if ok
}
dbus_method('Get', [['struct', 'string', 'string']], ['string']);
sub Get
{	my ($self,$array)=@_;
	::GetTagValue(@$array);
}
dbus_method('GetLibrary', [], [['array', 'uint32']]);
sub GetLibrary
{	\@::Library;
}

dbus_method('GetAlbumCover', ['string'], ['string']);
sub GetAlbumCover
{	my ($self,$album)=@_;
	my $ref=$::Album{$album};
	return undef unless $ref && $ref->[::AAPIXLIST];
	return $ref->[::AAPIXLIST];
}
dbus_method('GetAlbumCoverData', ['string'], [['array', 'byte']]);
sub GetAlbumCoverData
{	my ($self,$album)=@_;
	my $ref=$::Album{$album};
	return undef unless $ref && $ref->[::AAPIXLIST];
	my $file=$ref->[::AAPIXLIST];
	return undef unless -r $file;
	my $data;
	if ($file=~m/\.(?:mp3|flac)$/i)
	{	my $data=ReadTag::PixFromMusicFile($file);
	}
	else
	{	open my$fh,'<',$file; binmode $fh;
		read $fh,$data, (stat $file)[7];
		close $fh;
	}
	return [map ord,split //, $data];
}

dbus_method(CopyFields => [['struct', 'string', 'string']], ['bool']);
#copy stats fields from one song to another
#1st arg : filename of ID of source, 2nd arg filename or ID of dest, both must be in the library
sub CopyFields
{	my ($self,$array)=@_;
	::CopyFields(@$array);
}

dbus_signal('SongChanged', ['uint32']);
my $lasttime;
sub SongChanged
{	my $self=$_[0];
	return unless defined $::SongID && $::TogPlay;
	return if $lasttime && $::StartTime==$lasttime; #if song hasn't really changed
	$lasttime=$::StartTime;
	$self->emit_signal(SongChanged => $::SongID);
}

package GMB::DBus;

use Net::DBus;
use Net::DBus::Service;

my $not_glib_dbus;
my $bus;
eval { require Net::DBus::GLib; $bus=Net::DBus::GLib->session; };
unless ($bus)
{	#warn "Net::DBus::GLib not found (not very important)\n";
	$not_glib_dbus=1;
	$bus= Net::DBus->session;
}

Glib::Idle->add(\&init); #initialize once the main gmb init is finished

sub init
{	#my $bus = Net::DBus->session;
	my $service= $bus->export_service('org.gmusicbrowser');
	my $object = GMB::DBus::Object->new($service);
	DBus_mainloop_hack() if $not_glib_dbus;
	0; #called in an idle, return 0 to run only once
}

sub DBus_mainloop_hack
{	# use Net::DBus internals to connect it to the Glib mainloop, though unlikely, it may break with future version of Net::DBus
	use Net::DBus::Reactor;
	my $reactor=Net::DBus::Reactor->main;

	for my $ref (['in','read'],['out','write'], ['err','exception'])
	{	my ($type1,$type2)=@$ref;
		for my $fd (keys %{$reactor->{fds}{$type2}})
		{	#warn "$fd $type2";
			Glib::IO->add_watch($fd,$type1,
			sub{	$reactor->{fds}{$type2}{$fd}{callback}->invoke;
				$_->invoke for $reactor->_dispatch_hook;
				1;
			   }) if $reactor->{fds}{$type2}{$fd}{enabled};
			#Glib::IO->add_watch($fd,$type1,sub { Net::DBus::Reactor->main->step;Net::DBus::Reactor->main->step;1; }) if $reactor->{fds}{$type2}{$fd}{enabled};
		}
	}

	# run the dbus mainloop once so that events already pending are processed
	# needed if events already waiting when gmb is starting
		my $timeout=$reactor->add_timeout(1, Net::DBus::Callback->new( method => sub {} ));
		Net::DBus::Reactor->main->step;
		$reactor->remove_timeout($timeout);
}

1;
