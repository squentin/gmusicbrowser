# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
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
		sub {	::Watch($self,CurSong => \&SongFieldsChanged);
			::Watch($self,CurSongID =>\&SongChanged);
			::Watch($self,PlayingSong =>\&PlayingSongChanged);
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
{	my $self=$_[0];
	return {} unless defined $::SongID;
	my %h;
	$h{$_}=Songs::Get($::SongID,$_) for qw/title album artist length track disc album_artist file path uri album_picture/;
	#warn "$h{title}\n";
	return \%h;
}
dbus_method('CurrentSongFields', [['array', 'string']], [['array', 'string']]);
sub CurrentSongFields
{	my ($self,$fields)=@_;
	return [] unless defined $::SongID;
	my @ret= Songs::Get($::SongID,@$fields);
	return \@ret;
}

dbus_method('GetPosition', [], ['double']);
sub GetPosition
{	my $self=$_[0];
	return $::PlayTime || 0;
}

dbus_method('Playing', [], ['bool']);
sub Playing
{	return $::TogPlay ? 1 : 0;
}

dbus_method('Set', [['struct', 'string', 'string', 'string']], ['bool']);
sub Set
{	my ($self,$array)=@_;
	Songs::SetTagValue(@$array); #return false on error, true if ok
}
dbus_method('Get', [['struct', 'string', 'string']], ['string']);
sub Get
{	my ($self,$array)=@_;
	Songs::GetTagValue(@$array);
}
dbus_method('GetLibrary', [], [['array', 'uint32']]);
sub GetLibrary
{	\@::Library;
}

dbus_method('GetAlbumCover', ['uint32'], ['string']);
sub GetAlbumCover
{	my ($self,$ID)=@_;
	my $file=Songs::Get($ID,'album_picture');
	return $file;
}

#slow, not a good idea
dbus_method('GetAlbumCoverData', ['uint32'], [['array', 'byte']]);
sub GetAlbumCoverData
{	my ($self,$ID)=@_;
	my $file=GetAlbumCover($self,$ID);
	return undef unless $file && -r $file;
	my $data;
	if ($file=~m/\.(?:mp3|flac)$/i)
	{	$data=ReadTag::PixFromMusicFile($file);
	}
	else
	{	open my$fh,'<',$file; binmode $fh;
		read $fh,$data, (stat $file)[7];
		close $fh;
	}
	return [map ord,split //, $data];
}

dbus_method(CopyFields => [['array', 'string']], ['bool']);
#copy fields from one song to another
#1st arg : filename of ID of source, 2nd arg filename or ID of dest, both must be in the library,
#following args are list of fields, example : added, lastplay, playcount, lastskip, skipcount, rating, label
sub CopyFields
{	my ($self,$array)=@_;
	#my ($file1,$file2,@fields)=@$array;
	Songs::CopyFields(@$array);	#returns true on error
}

dbus_signal(SongFieldsChanged => ['uint32']);
sub SongFieldsChanged
{	$_[0]->emit_signal(SongFieldsChanged => $::SongID);
}
dbus_signal(SongChanged => ['uint32']);
sub SongChanged
{	$_[0]->emit_signal(SongChanged => $::SongID);
}
dbus_signal(PlayingSongChanged => ['uint32']);
sub PlayingSongChanged
{	$_[0]->emit_signal(PlayingSongChanged => $::SongID);
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
