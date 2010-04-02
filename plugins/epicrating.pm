# Copyright (C) 2010      Andrew Clunis <andrew@orospakr.ca>
#                         Daniel Rubin <dan@fracturedproject.net>
#               2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin EPICRATING
name    EpicRating
title   EpicRating plugin - automatically update ratings
author  Andrew Clunis <andrew@orospakr.ca>
author  Daniel Rubin <dan@fracturedproject.net>
desc    Automatic rating updates on configurable listening behaviour events.
=cut

package GMB::Plugin::EPICRATING;
use strict;
use warnings;

use constant {
    OPT => 'PLUGIN_EPICRATING_',#used to identify the plugin's options
    ALWAYS_AVAILABLE => ["PlayingID"],
    EVENTS => {played => ["PlayTime", "PlayedPercent"]},
    ACTIONS => ["REMOVE_FROM_RATING", "ADD_TO_RATING", "RATING_SET_TO_DEFAULT"]
};

::SetDefaultOptions(OPT, RatingOnSkip => -5, GracePeriod => 15, RatingOnSkipBeforeGrace => -1, RatingOnPlayed => 5, SetDefaultRatingOnSkipped => 1, SetDefaultRatingOnPlayed => 1, MyHash => { a => "a", b => "actually b"}, Rules => [[ {signal => 'Finished', field => "rating", value => 5}, {signal => 'Skipped', field => 'rating', value => -5 }, { signal => "SkippedBefore15", field => "rating", value => -1}]]);

my $self=bless {},__PACKAGE__;

sub AddRatingPointsToSong {
    my $ID=$_[0];
    my $PointsToRemove = $_[1];
    my $ExistingRating = ::Songs::Get($ID, 'rating');
    if(($ExistingRating + $PointsToRemove) > 100)
    {
        warn "Yikes, can't rate this song above one hundred.";
        ::Songs::Set($ID, rating=>100);
    } elsif(($ExistingRating + $PointsToRemove) < 0) {
        warn "Negaive addend in EpicRating pushed song rating to below 0.  Pinning.";
        ::Songs::Set($ID, rating => 0);
    } else {
        warn "EpicRating changing song rating by " . $PointsToRemove;
        ::Songs::Set($ID, rating=>($ExistingRating + $PointsToRemove));
    }
}

sub Played {
        my $ID=$::PlayingID;
        my $DefaultRating = $::Options{"DefaultRating"};
        my $GracePeriod = $::Options{OPT.'GracePeriod'};
        my $RatingOnSkip = $::Options{OPT.'RatingOnSkip'};
        my $RatingOnSkipBeforeGrace = $::Options{OPT.'RatingOnSkipBeforeGrace'};
        my $RatingOnPlayed = $::Options{OPT.'RatingOnPlayed'};

        if(!defined $::PlayTime) {
            warn "EpicRating's Played callback is missing PlayTime?!";
            return;
        }
        my $PlayedPartial=$::PlayTime-$::StartedAt < $::Options{PlayedPercent} * ::Songs::Get($ID,'length');
        if ($PlayedPartial)
        {
                my $song_rating = Songs::Get($ID, 'rating');
                if(($song_rating eq "") && $::Options{OPT."SetDefaultRatingOnSkipped"}) {
                    ::Songs::Set($ID, rating=>$DefaultRating);
                } elsif(!$song_rating) {
                    # user didn't have the setting on
                    return;
                } else {
                    if(($GracePeriod != 0) && ($::PlayTime < $GracePeriod)) {
                        AddRatingPointsToSong($ID, $RatingOnSkipBeforeGrace);
                    } else {
                        AddRatingPointsToSong($ID, $RatingOnSkip);
                    }
                }
        } else {
                my $song_rating = ::Songs::Get($ID, 'rating');
                if(($song_rating eq "") && $::Options{OPT."SetDefaultRatingOnPlayed"}) {
                    ::Songs::Set($ID, rating=>$DefaultRating);
                } elsif(!$song_rating) {
                    # user didn't have the setting on
                    return;
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

# rule editor.
# - event
# - value .... could somehow be another one of these rules?
# - operator

my $editor_signals = ['Played', 'Skipped', 'Finished', 'SkippedBefore15'];
my $editor_fields = ['rating'];

# perl, sigh.
# sub indexOfStr($arr, $matey) {
#     for(my $idx = 0; idx < $#{$arr}; idx ++) {
#         return $idx if $arr eq $matey;
# }

sub RuleEditor {
    my ($rule) = @_;

    my $frame = Gtk2::Frame->new();
    my $editor_hbox = Gtk2::HBox->new();

    my $signal_combo = Gtk2::ComboBox->new_text();
    my $signal_idx = 0;
    foreach my $signal (@{$editor_signals}) {
        $signal_combo->append_text($signal);
        if($signal eq ${$rule}{signal}) {
            $signal_combo->set_active($signal_idx);
        }
        $signal_idx++;
    }
    $signal_combo->signal_connect('changed', sub {
        ${$rule}{signal} = $signal_combo->get_active_text();
    });

    my $field_combo = Gtk2::ComboBox->new_text();
    my $field_idx = 0;
    foreach my $field (@{$editor_fields}) {
        $field_combo->append_text($field);
        if($field eq ${$rule}{field}) {
            $field_combo->set_active($field_idx);
        }
        $field_idx++;
    }
    $field_combo->signal_connect('changed', sub {
        ${$rule}{field} = $field_combo->get_active_text();
    });

    my $value_entry = Gtk2::Entry->new();
    $value_entry->set_text(${$rule}{value});
    $value_entry->signal_connect('changed', sub {
        ${$rule}{value} = $value_entry->get_text();
    });


    $editor_hbox->add(Gtk2::Label->new("Signal: "));
    $editor_hbox->add($signal_combo);
    $editor_hbox->add(Gtk2::Label->new("Field: "));
    $editor_hbox->add($field_combo);
    $editor_hbox->add(Gtk2::Label->new("Differential: "));
    $editor_hbox->add($value_entry);
    $editor_hbox->show_all();
    $frame->add($editor_hbox);

    return $frame;
}

sub RulesListAddRow {
    my $rule = $_[0]; # hash reference

     my $rule_editor = RuleEditor($rule);
    $self->{rules_table}->attach($rule_editor, 0, 1, $self->{current_row}, $self->{current_row}+1, "shrink", "shrink", 0, 0);
    $self->{current_row} += 1;
}

sub prefbox {
    # TODO validate good values?E!??!
    my $big_vbox = Gtk2::VBox->new(::FALSE, 2);
    my $rules_scroller = Gtk2::ScrolledWindow->new();
    $rules_scroller->set_policy('never', 'automatic');
    $self->{rules_table} = Gtk2::Table->new(1, 4, ::FALSE);
    $rules_scroller->add_with_viewport($self->{rules_table});
    $self->{current_row} = 0;

    # force some debug fixtures in
    # $::Options{OPT.'Rules'} = [ {signal => 'Finished', field => "rating", value => 5}, {signal => 'Skipped', field => 'rating', value => -5 }, { signal => "SkippedBefore15", field => "rating", value => -1}];

    my $rules = $::Options{OPT.'Rules'};

    foreach my $rule (@{$rules}) {
        RulesListAddRow($rule);
    }

    $big_vbox->add($rules_scroller);

    $big_vbox->show_all();
    return $big_vbox;
}
