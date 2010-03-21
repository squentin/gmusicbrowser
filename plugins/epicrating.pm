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
title   EpicRating plugin - massage ratings and other "enjoyment" metrics when stuff happens
desc    Automatic rating updates on certain events, and statistical normalization of ratings.
=cut

package GMB::Plugin::EPICRATING;
use strict;
use warnings;

use constant {
    CLIENTID => 'gmb', VERSION => '1.1',
    OPT => 'PLUGIN_EPICRATING_',#used to identify the plugin's options
};

::SetDefaultOptions(OPT, RatingOnSkip => -5, GracePeriod => 15, RatingOnSkipBeforeGrace => -1, RatingOnPlayed => 5);

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

        my $GracePeriod = $::Options{OPT.'GracePeriod'};
        my $RatingOnSkip = $::Options{OPT.'RatingOnSkip'};
        my $RatingOnSkipBeforeGrace = $::Options{OPT.'RatingOnSkipBeforeGrace'};
        my $RatingOnPlayed = $::Options{OPT.'RatingOnPlayed'};

        warn "GracePeriod is $GracePeriod";

        if(!defined $::PlayTime) {
            warn "EpicRating's Played callback is missing PlayTime?!";
            return;
        }
        my $PlayedPartial=$::PlayTime-$::StartedAt < $::Options{PlayedPercent} * ::Songs::Get($ID,'length');
        if ($PlayedPartial)
        {
                my $song_rating = Songs::Get($ID, 'rating');
                if(!$song_rating) {
                    ::Songs::Set($ID, rating=>50);
                } else {
                    if(($GracePeriod != 0) && ($::PlayTime < $GracePeriod)) {
                        AddRatingPointsToSong($ID, $RatingOnSkipBeforeGrace);
                    } else {
                        AddRatingPointsToSong($ID, $RatingOnSkip);
                    }
                }
        }
        else {
                my $song_rating = ::Songs::Get($ID, 'rating');
                if(!$song_rating) {
                    ::Songs::Set($ID, rating=>50);
                }
                AddRatingPointsToSong($ID, $RatingOnPlayed);
        }
}

sub Start {
    ::Watch($self, Played => \&Played);
}

sub Stop {
    ::UnWatch($self, $_) for qw/Played/;
}

sub GracePeriodChanged {
}

sub RatingOnSkipChanged {
}

sub RatingOnSkipBeforeGraceChanged {
}

sub RatingOnPlayedChanged {
}

sub prefbox {
    # TODO validate good values?E!??!
    my $big_vbox= Gtk2::VBox->new(::FALSE, 2);
    my $sg1=Gtk2::SizeGroup->new('horizontal');
    my $sg2=Gtk2::SizeGroup->new('horizontal');

    # rating change on skip
    # rating change on full play
    # if less than 15% in there somehow

    my $grace_period_entry = ::NewPrefEntry(OPT."GracePeriod", _"Grace period before applying a different differential (if zero, grace period does not apply)", cb=>\&GracePeriodChanged, sizeg1 => $sg1,sizeg2=>$sg2);
    my $rating_on_skip_entry = ::NewPrefEntry(OPT.'RatingOnSkip', _"Add to rating on skip:", cb =>\&RatingOnSkipChanged, sizeg1 => $sg1,sizeg2=>$sg2);
    my $rating_on_skip_before_grace_entry = ::NewPrefEntry(OPT.'RatingOnSkipBeforeGrace', _"Add to rating on skip (before grace period):", cb=>\&RatingOnSkipBeforeGraceChanged, sizeg1 => $sg1,sizeg2=>$sg2);


    my $rating_on_played_entry = ::NewPrefEntry(OPT.'RatingOnPlayed', _"Add to rating on played completely:", cb =>\&RatingOnPlayedChanged, sizeg1 => $sg1,sizeg2=>$sg2);

    $big_vbox->pack_start($_, ::FALSE, ::FALSE, 0) for $grace_period_entry, $rating_on_skip_entry, $rating_on_skip_before_grace_entry, $rating_on_played_entry;

    $big_vbox->show_all();
    return $big_vbox;
}
