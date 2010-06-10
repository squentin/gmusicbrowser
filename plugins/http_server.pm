# Copyright (C) 2010      Andrew Clunis <andrew@orospakr.ca>
#               2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# This requires POE with Glib support.  However, GLib support is missing
# in the Ubuntu (Debian?) packages.
# As such, it needs to be loaded from CPAN (plus dependencies)

# cpan -i POE POE::Loop::Glib POE::Component::Server::HTTP CGI::Application::Dispatch

=gmbplugin HTTPSERVER
name    HTTP Server
title   HTTP Server - Provides a RESTful HTTP service (and Javascript player) on port 8080
author  Andrew Clunis <andrew@orospakr.ca>
desc    Access the gmusicbrowser library RESTfully, and use a simple javascript UI to interact with it.
=cut

package GMB::Plugin::HTTPSERVER;
use strict;
use warnings;

use POE;
use POE::Kernel { loop => "Glib" };
use POE::Component::Server::HTTP;

use CGI;
use HTTP::Status qw/RC_OK/;

# actually get *feedback* instead of silence if a session crashes.
sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }


# my $cgi = cgi_from_request($request);
# my $field = $cgi->param("field");

sub cgi_from_request {
    my ($request) = @_;
    
    # I'm not really sure why POE/HTTP isn't
    # doing this for me...
    # this implementation is rather naiive.
    my $q;
    if ($request->method() eq 'POST') {
	$q = new CGI($request->content);
    }
    else {
	$request->uri() =~ /\?(.+$)/;
	if (defined($1)) {
	    $q = new CGI($1);
	}
	else {
	    $q = new CGI;
	}
    }
    return $q;
}

sub player_handler {
    my ($request, $response) = @_;
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    my $cgi = cgi_from_request($request);
}

sub skip_handler {
    my ($request, $response) = @_;
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    warn "Got Skip request!";
    my $cgi = cgi_from_request($request);

    ::NextSong();
    warn "Successfully skipped song!";

    $response->code(RC_OK);
    return RC_OK;
}

sub root_handler {
    my ($request, $response) = @_;
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    warn "HTTP request to root or unknown: " . $request->method . " " . $request->uri->path_query;

    my $ID = $::PlayingID;

    my $playing_song;
    if(defined $ID) {
	$playing_song = "Playing song: " . ::Songs::Get($ID, 'artist') . " - " . ::Songs::Get($ID, 'title');
    } else {
	$playing_song = "None! :(";
    }
    
    $playing_song .= "<br /><br /><a href=\"/skip\">Skip!</a>";
    # Build the response.
    $response->code(RC_OK);
#    $response->push_header("Content-Type", "application/x-dmap-tagged");
    $response->content($playing_song);

    # Signal that the request was handled okay.
    return RC_OK;
}

sub Start {
    my $http = POE::Component::Server::HTTP->new(
    	Port           => 8080,
    	ContentHandler => {"/" => \&root_handler,
			   "/player" => \&player_handler,
			   "/skip" => \&skip_handler
    	},
    	Headers => {Server => 'Gmusicbrowser HTTP',},
    );
    
}

sub Stop {
}

sub prefbox {
}

1;
