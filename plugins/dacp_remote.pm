# Copyright (C) 2010      Andrew Clunis <andrew@orospakr.ca>
#               2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin DACPREMOTE
name    DACP Remote
title   DACP Remote - DACP remote control support
author  Andrew Clunis <andrew@orospakr.ca>
desc    Use DACP-enabled devices to control Gmusicbrowser.
=cut

package GMB::Plugin::DACPREMOTE;
use strict;
use warnings;

use POE;
use POE::Component::Server::HTTP;
# use POE::Kernel {loop => "Glib"};
use HTTP::Status qw/RC_OK/;


use constant {
    OPT => 'PLUGIN_DACPREMOTE_'
};

my $self=bless {}, __PACKAGE__;


sub web_handler {
  my ($request, $response) = @_;

  # Slurp in the program's source.
  my $ID = $::PlayingID;

  my $playing_song = "Playing song: " . $ID;

  # Build the response.
  $response->code(RC_OK);
  $response->push_header("Content-Type", "text/plain");
  $response->content($playing_song);

  # Signal that the request was handled okay.
  return RC_OK;
}

sub Start {
    POE::Component::Server::HTTP->new(
	Port           => 32080,
	ContentHandler => {"/" => \&web_handler},
	Headers => {Server => 'Gmusicbrowser test DACP',},
    );
    $poe_kernel->run()
}

sub Stop {
}

sub prefbox {
}
