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
# that happens to include DACP functionality...

=gmbplugin DACPREMOTE
name    DACP Remote
title   DACP Remote - DACP remote control support
author  Andrew Clunis <andrew@orospakr.ca>
desc    Use DACP-enabled devices to control Gmusicbrowser.
=cut

# package GMB::Plugin::DACPREMOTE::Track;
# use strict;
# use warnings;
# # use Perl6::Slurp;
# use File::Basename qw(basename);

# sub new {
#     $self = bless {}, shift;
# }


package GMB::Plugin::DACPREMOTE::DacpServer;
use strict;
use warnings;

use POE;
# use Net::DAAP::Server::Track;
use Net::DMAP::Server;
use File::Find::Rule;
use base qw( Net::DMAP::Server );

sub protocol { 'dcap' }

sub find_tracks {
    warn "Finding tracks?!  You get NONE!"
}

# sub new {
# }


package GMB::Plugin::DACPREMOTE;
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
    OPT => 'PLUGIN_DACPREMOTE_'
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

#our $dacp_servar;

sub Start {
    # POE::Component::Server::HTTP->new(
    # 	Port           => 3689,
    # 	ContentHandler => {"/" => \&root_handler,
    # 	                   "/login" => \&login_handler,
    # 			   "/databases" => \&databases_handler
    # 	},
    # 	Headers => {Server => 'Gmusicbrowser DACP',},
    # );

    my $dacp_servar = GMB::Plugin::DACPREMOTE::DacpServer->new(path => "/home/orospakr/Music/Benn Jordan - Pale Blue Dot - V0/", port => 3689, debug => 1);

    # if GMB is started with this plugin enabled, this Start routine
    # appears to get hit too early.  This seems to defer it enough.
    Glib::Timeout->add(0, sub { $poe_kernel->run(); ::FALSE; });
}

sub Stop {
}

sub prefbox {
}


