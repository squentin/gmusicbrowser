# Copyright (C) 2010      Andrew Clunis <andrew@orospakr.ca>
#               2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# DACP is Apple's Zeroconfesque remote control protocol, which like DAAP
# has become a defacto-standard of sorts.  There's a very nice Free Software
# DACP remote app for Android, for instance.

# This requires POE with Glib support.  However, GLib support is missing
# in the Ubuntu (Debian?) packages.
# As such, it needs to be loaded from CPAN (plus dependencies)

# cpan -i POE POE::Loop::Glib POE::Component::Server::HTTP Net::DAAP::DMAP Net::Rendezvous::Publish::Backend::Avahi
# apt-get install libnet-rendezvous-publish-perl

# if other HTTP services might be useful to add, it might
# be worth turning this plugin into a generic web interface plugin
# that happens to include DAAP functionality...

=gmbplugin DAAPSERVER
name    DAAP Server
title   DAAP Server - Applish DA*P protocol access to gmusicbrowser library and facilities
author  Andrew Clunis <andrew@orospakr.ca>
desc    DAAP access to your gmusicbrowser library from DAAP clients (iTunes).  Use DACP-enabled devices to control Gmusicbrowser (soon).
=cut

# package GMB::Plugin::DAAPSERVER::Track;
# use strict;
# use warnings;
# # use Perl6::Slurp;
# use File::Basename qw(basename);

# sub new {
#     $self = bless {}, shift;
# }

package GMB::Plugin::DAAPSERVER::TrackBinding;
use strict;
use warnings;
use Net::DAAP::Server::Track;
use base qw( Net::DAAP::Server::Track );
use POE;


#going to cheat for now to make a convenient mock
# __PACKAGE__->mk_accessors(qw(
#       file

#       dmap_itemid dmap_itemname dmap_itemkind dmap_persistentid
#       daap_songalbum daap_songartist daap_songbitrate
#       daap_songbeatsperminute daap_songcomment daap_songcompilation
#       daap_songcomposer daap_songdateadded daap_songdatemodified
#       daap_songdisccount daap_songdiscnumber daap_songdisabled
#       daap_songeqpreset daap_songformat daap_songgenre
#       daap_songdescription daap_songrelativevolume daap_songsamplerate
#       daap_songsize daap_songstarttime daap_songstoptime daap_songtime
#       daap_songtrackcount daap_songtracknumber daap_songuserrating
#       daap_songyear daap_songdatakind daap_songdataurl
#       com_apple_itunes_norm_volume

#       daap_songgrouping daap_songcodectype daap_songcodecsubtype
#       com_apple_itunes_itms_songid com_apple_itunes_itms_artistid
#       com_apple_itunes_itms_playlistid com_apple_itunes_itms_composerid
#       com_apple_itunes_itms_genreid
#       dmap_containeritemid
#      ));

sub new {
    my $class = shift;
    my $file = shift;

    my $self = $class->SUPER::new({file => $file});
}

package GMB::Plugin::DAAPSERVER::DaapServer;
use strict;
use warnings;

use File::Spec;

use POE;
# use Net::DAAP::Server::Track;
use Net::DMAP::Server;
use Net::DAAP::Server;
use File::Find::Rule;
use base qw( Net::DAAP::Server );

# not any more, and now we'll need a separate server for it, unless
# only the interfaces of ::Server require improvement (pass multiple protocol names,
# at least if it's only used for publishing on mdns anyway).
# sub protocol { 'dcap' }

sub find_tracks {
    my $self = shift;
    warn "Finding tracks?!  HERE IT GOES";


    my $all_songs = Filter->new("")->filter;

    for my $song_id (@{$all_songs}) {

	my ($length, $title, $artist, $album, $rating, $genre, $track) = ::Songs::Get($song_id, 'length', 'title', 'artist', 'album', 'rating', 'genre', 'track');

	my ($path, $filename) = ::Songs::Get($song_id, qw/path file/);

	# warn "Song pathname is: " . File::Spec->catfile($path,$filename);
	
	my $dummy = GMB::Plugin::DAAPSERVER::TrackBinding->new(File::Spec->catfile($path, $filename));
	
	$dummy->dmap_itemid( $song_id ); # the inode should be good enough
	$dummy->dmap_containeritemid( 5139 ); # huh

	$dummy->dmap_itemkind( 2 ); # music
	$dummy->dmap_persistentid( "GMB" . $song_id); # blah, this should be some 64 bit thing I guess?
	$dummy->daap_songbeatsperminute( 0 );

	$dummy->daap_songbitrate( 222 );
	$dummy->daap_songsamplerate( 44100 );
	$dummy->daap_songtime($length );

	$dummy->daap_songtime($length * 1000);

	$dummy->dmap_itemname( $title );
	$dummy->daap_songalbum( $album );
	$dummy->daap_songartist( $artist);
	$dummy->daap_songcomment( );
	$dummy->daap_songyear( 1997 );

	$dummy->daap_songtrackcount( 0 );
	$dummy->daap_songtracknumber( $track );
	$dummy->daap_songcompilation( 0);
	$dummy->daap_songdisccount(  0);
	$dummy->daap_songdiscnumber(  0);

	# $dummy->daap_songcomposer( );
	$dummy->daap_songdateadded( 0 );
	$dummy->daap_songdatemodified( 0 );
	$dummy->daap_songdisabled( 0 );
	$dummy->daap_songeqpreset( '' );
	$dummy->daap_songformat( "mp3" );
	$dummy->daap_songgenre( $genre );
	$dummy->daap_songgrouping( '' );
	# $dummy->daap_songdescription( );
	# $dummy->daap_songrelativevolume( );
	$dummy->daap_songsize( 1483000 );
	$dummy->daap_songstarttime( 0 );
	$dummy->daap_songstoptime( 0 );

	$dummy->daap_songuserrating( $rating );
	$dummy->daap_songdatakind( 0 );
	# $dummy->daap_songdataurl( );
	$dummy->com_apple_itunes_norm_volume( 17502 );

	# $dummy->daap_songcodectype( 1836082535 ); # mp3?
	# $self->daap_songcodecsubtype( 3 ); # or is this mp3?

	$self->tracks->{$song_id} = $dummy;

    }
}

1;

package GMB::Plugin::DAAPSERVER;
use strict;
use warnings;

# actually get *feedback* instead of silence if a session crashes.
# sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }

use POE::Kernel { loop => "Glib" };
use POE::Component::Server::HTTP;
use Data::Dumper;
use Sys::Hostname;

use CGI;
use HTTP::Status qw/RC_OK/;
use Net::DAAP::DMAP qw(:all);

use constant {
    OPT => 'PLUGIN_DAAPSERVER_'
};

my $self=bless {}, __PACKAGE__;

sub Start {

    $self->{daap_servar} = GMB::Plugin::DAAPSERVER::DaapServer->new(port => 3689, debug => 1, name => getlogin() . _"'s gmusicbrowser@" . hostname());
}

sub Stop {
}

sub prefbox {
}

;1
