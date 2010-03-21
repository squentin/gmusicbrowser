# Copyright (C) 2010 Andrew Clunis <andrew@orospakr.ca>
#                    Daniel Rubin <dan@fracturedproject.net>
#                    2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin EPICRATING
name    EpicRating
title   Rating mangler plugin
desc    Automatic rating updates on certain events, and statistical normalization of ratings.
=cut


package GMB::Plugin::EPICRATING;
use strict;
use warnings;

use constant {
    CLIENTID => 'gmb', VERSION => '1.1',
    OPT => 'PLUGIN_EPICRATING_',#used to identify the plugin's options
};

my $self=bless {},__PACKAGE__;

sub AddRatingPointsToSong {
    my $ID=$_[0];
    my $PointsToRemove = $_[1];
    my $ExistingRating = ::Songs::Get($ID, 'rating');
    if(($ExistingRating + $PointsToRemove) > 100)
    {
        warn "Yikes, can't rate this song above one hundred.";
        ::Songs::Set($ID, rating=>100);
    } else {
        warn "Rating up song by " . $PointsToRemove;
        ::Songs::Set($ID, rating=>($ExistingRating + $PointsToRemove));
    }
}

sub Played {
        my $ID=$::PlayingID;

        return unless defined $::PlayTime;
        my $PlayedPartial=$::PlayTime-$::StartedAt < $::Options{PlayedPercent} * ::Songs::Get($ID,'length');
        if ($PlayedPartial) #FIXME maybe only count as a skip if played less than ~20% ?
        {
                my $song_rating = Songs::Get($ID, 'rating');
                if(!$song_rating) {
                    ::Songs::Set($ID, rating=>50);
                } else {
                    if($song_rating < 15) {
                        AddRatingPointsToSong($ID, -1);
                    } else {
                        AddRatingPointsToSong($ID, -5);
                    }
                }
        }
        else {
                my $song_rating = ::Songs::Get($ID, 'rating');
                if(!$song_rating) {
                    ::Songs::Set($ID, rating=>50);
                }
                AddRatingPointsToSong($ID, 5);
        }
}

sub Start {
    ::Watch($self, Played => \&Played);
}

sub Stop {
    ::UnWatch($self, $_) for qw/Played/;
}

sub prefbox {
    my $vbox=Gtk2::VBox->new(::FALSE, 2);
    return $vbox;
}
