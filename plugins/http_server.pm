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

use constant {
    OPT => 'PLUGIN_HTTPSERVER_'
};

use JSON;

use POE;
use POE::Kernel { loop => "Glib" };
use POE::Component::Server::HTTP;

use CGI;
use HTTP::Status qw/RC_OK/;

use File::Slurp;

# actually get *feedback* instead of silence if a session crashes.
sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }

::SetDefaultOptions(OPT, PortNumber => 8080);

# my $cgi = cgi_from_request($request);
# my $field = $cgi->param("field");

my $resource_path;
my $resources = {};

sub song2json {
    my ($song_id) = @_;
    return {"id" => $song_id, "artist" => ::Songs::Get($song_id, "artist"), "title" => ::Songs::Get($song_id, "title")};
}

# playing: 1 for playing, 0 for paused, null for stopped.
# volume: value between 0 and 100.
# current: current playing song in JSON representation, see song2json()
sub state2json {
    return {"current" => song2json($::SongID), "playing" => $::TogPlay, "volume" => ::GetVol()};
}

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

sub skip_handler {
    my ($request, $response) = @_;
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    warn "Got Skip request!";
    my $cgi = cgi_from_request($request);

    ::NextSong();
    warn "Successfully skipped song!";

    $response->code(200);
    $response->content_type('application/json');
    $response->content(encode_json(state2json()));
    return RC_OK;
}

sub volume_handler {
    my ($request, $response) = @_;
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    my $cgi = cgi_from_request($request);
    foreach($cgi->param()) {
    	if($_ eq "volume") {
    	    ::UpdateVol($cgi->param($_) * 100);
    	}
    }
    $response->code(200);

    return RC_OK;
}

sub player_handler {
    my ($request, $response) = @_;
    $response->protocol( "HTTP/1.1" );
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    $response->code(200);
    $response->content_type('application/json');
    $response->content(encode_json(state2json()));
    return RC_OK;
}

sub playpause_handler {
    my ($request, $response) = @_;
    $response->protocol( "HTTP/1.1" );
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    warn "Got Skip request!";
    my $cgi = cgi_from_request($request);

    ::PlayPause();

    $response->code(200);
    $response->content_type('application/json');
    $response->content(encode_json(state2json()));
    return RC_OK;
}

sub code_handler {
    my ($request, $response) = @_;
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;

    my @split_request = split(/\//, $path);

    my $local_filename = $resource_path.::SLASH.'http_server'.::SLASH.$split_request[2];

    warn "DETECTED FILENAME: " . $local_filename;

    if( -e $local_filename ) {
	my $contents = read_file($local_filename);
	$response->content($contents);
	$response->code(200);
	$response->header('Content-Type' => "text/javascript");
    } else {
	warn "FILE DID NOT EXIST";
	$response->code(404);
    }

    return RC_OK;
}

sub root_handler {
    my ($request, $response) = @_;
    $request->header(Connection => 'close');
    my $path = $request->uri->path;
    my $query = $request->uri->query;


    warn "HTTP request to root or unknown: " . $request->method . " " . $request->uri->path_query;

    # my $playing_song;
    # if(defined $ID) {
    # 	$playing_song = "Playing song: " . ::Songs::Get($ID, 'artist') . " - " . ::Songs::Get($ID, 'title');
    # } else {
    # 	$playing_song = "None! :(";
    # }
    
    my $webapp = <<END;
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset=utf-8 />
    <title>Gmusicbrowser</title>
    <script src="/code/prototype.js" type="text/javascript"></script>
    <script src="/code/scriptaculous.js" type="text/javascript"></script>
    <style type="text/css">
      #seek_slider {
        background-color: red;
        height: 20px;
        width: 500px;
      }
      #seek_position {
        background-color: blue;
        height: 20px;
        width: 20px;
      }
    </style>
  </head>
  <body>
    <div id=current_song>
      <span id=current_song_artist></span> - 
      <span id=current_song_title></span>
    </div>
    <br>

    <div id=seek_slider>
      <div id=seek_position></div>
    </div>
<br>
    
    <div>
      <button id=playpausebutton>Play</button>
      <button id=skipbutton>Skip</button>
    </div>
    
    <script type="text/javascript" src="/code/player.js"></script>
  </body>
</html>
END

    # Build the response.
    $response->code(RC_OK);
    $response->header('Content-Type' => "text/html");

    $response->content($webapp);

    # Signal that the request was handled okay.
    return RC_OK;
}

my $http_poe_server;

sub StartServer {
    $http_poe_server = POE::Component::Server::HTTP->new(
    	Port           => $::Options{OPT.'PortNumber'},
    	ContentHandler => {"/" => \&root_handler,
			   "/player" => \&player_handler,
			   "/noscript" => \&root_noscript_handler,
			   "/skip" => \&skip_handler,
			   "/playpause" => \&playpause_handler,
			   "/volume" => \&volume_handler,
			   "/code/" => \&code_handler
    	},
    	Headers => {Server => 'Gmusicbrowser HTTP',},
    );
}

sub StopServer {
    POE::Kernel->call($http_poe_server->{httpd}, "shutdown");
    POE::Kernel->call($http_poe_server->{tcp}, "shutdown");
}

sub Start {
    my ($self) = @_;


    $resource_path = $::DATADIR.::SLASH.'plugins'.::SLASH;
    # $resources->{prototypejs} = read_file($resource_path.::SLASH.'http_server'.::SLASH.'prototype.js');
    # $resources->{playerjs} = read_file($resource_path.::SLASH.'http_server'.::SLASH.'player.js');
    StartServer();
}

sub Stop {
    my ($self) = @_;
    StopServer();
}

sub RestartServer {
    StopServer();
    StartServer();
}

sub prefbox {
    my $vbox = new Gtk2::VBox->new();
    my $port_setting = ::NewPrefEntry(OPT."PortNumber", _"Port Number", cb => \&RestartServer);
    $vbox->add($port_setting);
    return $vbox;
}

1;
