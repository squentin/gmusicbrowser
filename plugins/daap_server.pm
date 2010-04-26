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
use base qw( Class::Accessor::Fast );
use POE;


#going to cheat for now to make a convenient mock
__PACKAGE__->mk_accessors(qw(
      file

      dmap_itemid dmap_itemname dmap_itemkind dmap_persistentid
      daap_songalbum daap_songartist daap_songbitrate
      daap_songbeatsperminute daap_songcomment daap_songcompilation
      daap_songcomposer daap_songdateadded daap_songdatemodified
      daap_songdisccount daap_songdiscnumber daap_songdisabled
      daap_songeqpreset daap_songformat daap_songgenre
      daap_songdescription daap_songrelativevolume daap_songsamplerate
      daap_songsize daap_songstarttime daap_songstoptime daap_songtime
      daap_songtrackcount daap_songtracknumber daap_songuserrating
      daap_songyear daap_songdatakind daap_songdataurl
      com_apple_itunes_norm_volume

      daap_songgrouping daap_songcodectype daap_songcodecsubtype
      com_apple_itunes_itms_songid com_apple_itunes_itms_artistid
      com_apple_itunes_itms_playlistid com_apple_itunes_itms_composerid
      com_apple_itunes_itms_genreid
      dmap_containeritemid
     ));





package GMB::Plugin::DAAPSERVER::DaapServer;
use strict;
use warnings;

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
    warn "Finding tracks?!  You get NONE!";
    my $dummy = GMB::Plugin::DAAPSERVER::TrackBinding->new();
    
    # $dummy->dmap_itemid("whooot");
    # $dummy->dmap_containeritemid("0");
    # $dummy->dmap_itemkind(2);
    # $dummy->dmap_persistentid("fnaaaaart");
    # $dummy->daap_songbeatsperminute(60);
    # # $dummy->daap_songbitrate(96000); # yikes, I need this?
    # $dummy->daap_songalbum("internet explorer");
    # $dummy->dmap_itemname("windows welcome music");
    # $dummy->daap_songartist("microsoft");
    # $dummy->daap_


    $dummy->dmap_itemid( 34564 ); # the inode should be good enough
    $dummy->dmap_containeritemid( 5139 ); # huh

    $dummy->dmap_itemkind( 2 ); # music
    $dummy->dmap_persistentid( "fneeeerrrr"); # blah, this should be some 64 bit thing
    $dummy->daap_songbeatsperminute( 0 );

    # All mp3 files have 'info'. If it doesn't, give up, we can't read it.
    $dummy->daap_songbitrate( 222 );
    $dummy->daap_songsamplerate( 44100 );
    $dummy->daap_songtime( 34 * 1000 );

    # read the tag if we can, fall back to very simple data otherwise.
    $dummy->dmap_itemname( "windows welcome music" );
    $dummy->daap_songalbum( "internet explorer" );
    $dummy->daap_songartist( "microsoft" );
    $dummy->daap_songcomment( "great bass if you've got the system for it" );
    $dummy->daap_songyear( 1997 );

    $dummy->daap_songtrackcount( 0 );
    $dummy->daap_songtracknumber( 1 );
    $dummy->daap_songcompilation( 0);
    $dummy->daap_songdisccount(  0);
    $dummy->daap_songdiscnumber(  0);

    # $dummy->daap_songcomposer( );
    $dummy->daap_songdateadded( 0 );
    $dummy->daap_songdatemodified( 0 );
    $dummy->daap_songdisabled( 0 );
    $dummy->daap_songeqpreset( '' );
    $dummy->daap_songformat( "mp3" );
    $dummy->daap_songgenre( 'techno' );
    $dummy->daap_songgrouping( '' );
    # $dummy->daap_songdescription( );
    # $dummy->daap_songrelativevolume( );
    $dummy->daap_songsize( 1483000 );
    $dummy->daap_songstarttime( 0 );
    $dummy->daap_songstoptime( 0 );

    $dummy->daap_songuserrating( 45 );
    $dummy->daap_songdatakind( 0 );
    # $dummy->daap_songdataurl( );
    $dummy->com_apple_itunes_norm_volume( 17502 );

    # $dummy->daap_songcodectype( 1836082535 ); # mp3?
    # $self->daap_songcodecsubtype( 3 ); # or is this mp3?


    
    $self->tracks->{"whooot"} = $dummy;
    
}

package GMB::Plugin::DAAPSERVER;
use strict;
use warnings;

# actually get *feedback* instead of silence if a session crashes.
# sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }


use POE::Kernel { loop => "Glib" };
use POE::Component::Server::HTTP;
use Data::Dumper;

use CGI;
use HTTP::Status qw/RC_OK/;
use Net::DAAP::DMAP qw(:all);

use constant {
    OPT => 'PLUGIN_DAAPSERVER_'
};

my $self=bless {}, __PACKAGE__;

# sub login_response {
#     my $dmap =   [
# 	[
# 	 'dmap.loginresponse',
# 	 [
# 	  [
# 	       'dmap.status',
# 	   200
# 	  ],
# 	  [
# 	   'dmap.sessionid',
# 	   2393
# 	  ]
# 	 ]
# 	]
# 	];
    
#     return dmap_pack($dmap);
# }

# # sub databases_response {
# #     $dmap = [
# # 	[ 'dmap.serverdatabases',
# # 	  [
# # 	   ['dmap.status', 200],
# # 	   ['dmap.updatetype',200]
	   
# # 	];
# # }

# sub cgi_from_request {
#     my ($request) = @_;
    
#     # I'm not really sure why POE/HTTP isn't
#     # doing this for me...
#     # this implementation is rather naiive.
#     my $q;
#     if ($request->method() eq 'POST') {
# 	$q = new CGI($request->content);
#     }
#     else {
# 	$request->uri() =~ /\?(.+$)/;
# 	if (defined($1)) {
# 	    $q = new CGI($1);
# 	}
# 	else {
# 	    $q = new CGI;
# 	}
#     }
#     return $q;
# }



# sub databases_handler {
#     my ($request, $response) = @_;

#     my $dmap = [];
       
#     $response->code(RC_OK);
#     $response->push_header("Content-Type", "application/x-dmap-tagged");
#     $response->content(databases_response());
# }

# sub login_handler {
#     my ($request, $response) = @_;
#     warn "Login request received: " . $request;

#     my $cgi = cgi_from_request($request);

#     warn "got cgi";
#     my $pairing_guid = $cgi->param("pairing-guid");
#     warn "... got pairing-guid: " . $pairing_guid;

#     # Build the response.
#     $response->code(RC_OK);
#     $response->push_header("Content-Type", "application/x-dmap-tagged");
#     $response->content(login_response());

#     # Signal that the request was handled okay.
#     return RC_OK;
# }

# sub root_handler {
    

#     my $path = $request->uri->path;
#     my $query = $request->uri->query;

#     warn "HTTP request to root or unknown: " . $request->method . " " . $request->uri->path_query;

#     # we might as well
#     if($request->method eq "POST") {
# 	warn "Attempt to decode DMAP: " . Dumper(dmap_unpack($request->content));
#     }

#     my $ID = $::PlayingID;



#     my $playing_song;
#     if(defined $ID) {
# 	$playing_song = "Playing song: " . ::Songs::Get($ID, 'artist') . " - " . ::Songs::Get($ID, 'title');
#     } else {
# 	$playing_song = "None! :(";
#     }
    
#     # Build the response.
#     $response->code(RC_OK);
#     $response->push_header("Content-Type", "application/x-dmap-tagged");
#     $response->content($playing_song);

#     # Signal that the request was handled okay.
#     return RC_OK;
# }

#our $daap_servar;

sub Start {
    # POE::Component::Server::HTTP->new(
    # 	Port           => 3689,
    # 	ContentHandler => {"/" => \&root_handler,
    # 	                   "/login" => \&login_handler,
    # 			   "/databases" => \&databases_handler
    # 	},
    # 	Headers => {Server => 'Gmusicbrowser DAAP',},
    # );

    $self->{daap_servar} = GMB::Plugin::DAAPSERVER::DaapServer->new(path => "/home/orospakr/Music/Benn Jordan - Pale Blue Dot - V0/", port => 3689, debug => 1);
#   $self->{daap_servar} = Net::DAAP::Server->new(path => "/home/orospakr/Music/Benn Jordan - Pale Blue Dot - V0/", port => 23689, debug => 1);

    # if GMB is started with this plugin enabled, this Start routine
    # appears to get hit too early.  This seems to defer it enough.
    Glib::Timeout->add(0, sub { $poe_kernel->run(); ::FALSE; });
}

sub Stop {
}

sub prefbox {
}


