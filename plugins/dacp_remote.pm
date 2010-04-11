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

# cpan -i POE POE::Loop::Glib POE::Component::Server::HTTP

# if other HTTP services might be useful to add, it might
# be worth turning this plugin into a generic web interface plugin
# that happens to include DACP functionality...

=gmbplugin DACPREMOTE
name    DACP Remote
title   DACP Remote - DACP remote control support
author  Andrew Clunis <andrew@orospakr.ca>
desc    Use DACP-enabled devices to control Gmusicbrowser.
=cut

package GMB::Plugin::DACPREMOTE;
use strict;
use warnings;

use POE::Kernel { loop => "Glib" };
use POE::Component::Server::HTTP;
use HTTP::Status qw/RC_OK/;

use constant {
    OPT => 'PLUGIN_DACPREMOTE_'
};

my $self=bless {}, __PACKAGE__;


sub web_handler {
  my ($request, $response) = @_;

  my $ID = $::PlayingID;

  my $playing_song;
  if(defined $ID) {
      $playing_song = "Playing song: " . ::Songs::Get($ID, 'artist') . " - " . ::Songs::Get($ID, 'title');
  } else {
      $playing_song = "None! :(";
  }

  # Build the response.
  $response->code(RC_OK);
  $response->push_header("Content-Type", "text/plain");
  $response->content($playing_song);

  # Signal that the request was handled okay.
  return RC_OK;
}

sub Start {
    POE::Component::Server::HTTP->new(
	Port           => 8080,
	ContentHandler => {"/" => \&web_handler},
	Headers => {Server => 'Gmusicbrowser DACP',},
    );

    # if GMB is started with this plugin enabled, this Start routine
    # appears to get hit too early.  This seems to defer it enough.
    Glib::Timeout->add(0, sub { $poe_kernel->run(); ::FALSE; });
}

sub Stop {
}

sub prefbox {
}
