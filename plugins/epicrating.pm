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

# dependencies: Text::CSV, libtext-csv-perl

package GMB::Plugin::EPICRATING;
use strict;
use warnings;

use constant {
    OPT => 'PLUGIN_EPICRATING_',#used to identify the plugin's options
    ALWAYS_AVAILABLE => ["PlayingID"],
    EVENTS => {played => ["PlayTime", "PlayedPercent"]},
    ACTIONS => ["REMOVE_FROM_RATING", "ADD_TO_RATING", "RATING_SET_TO_DEFAULT"]
};

::SetDefaultOptions(OPT, SetDefaultRatingOnSkipped => 1, SetDefaultRatingOnFinished => 1, Rules => [ {signal => 'Finished', field => "rating", value => 5}, {signal => 'Skipped', field => 'rating', value => -5 }, { signal => "Skipped", before => 15, field => "rating", value => -1}]);

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
	warn "Negative addend in EpicRating pushed song rating to below 0.  Pinning.";
	::Songs::Set($ID, rating => 0);
    } else {
	warn "EpicRating changing song rating by " . $PointsToRemove;
	::Songs::Set($ID, rating=>($ExistingRating + $PointsToRemove));
    }
}

sub GetRulesBySignal {
    my ($rule_name) = @_;
    my $rules = $::Options{OPT.'Rules'};
    my $matched_rules = [];

    foreach my $rule (@{$rules}) {
	if(${$rule}{signal} eq $rule_name) {
	    push @{$matched_rules}, $rule;
	}
    }
    return $matched_rules;
}

# apply the action this rule specifies.
sub ApplyRule {
    my ($rule, $song_id) = @_;
    AddRatingPointsToSong($song_id, ${$rule}{value});
}

# lasso all rules with a given signal and apply them all.  not appropriate for signals conditions/options.
sub ApplyRulesByName {
    my ($rule_name, $song_id) = @_;
    my $rules = $::Options{OPT.'Rules'};

    my $matched_rules = GetRulesBySignal($rule_name);

    foreach my $matched_rule (@{$matched_rules}) {
	my $value = ::Songs::Get($song_id, ${$matched_rule}{field});
	if((defined $value) && ($value ne "")) {
	    ApplyRule($matched_rule, $song_id);
	}
    }
}

# Finished playing song (actually PlayedPercent or more, neat eh?)
sub Finished {
    my $rules = $::Options{OPT.'Rules'};
    my $DefaultRating = $::Options{"DefaultRating"};


    my $ID=$::PlayingID;

    my $song_rating = Songs::Get($ID, 'rating');
    if(!($song_rating && $::Options{OPT."SetDefaultRatingOnFinished"})) {
	::Songs::Set($ID, rating=>$DefaultRating);
    }

    ApplyRulesByName('Finished', $ID);
}

sub Skipped {
    warn 'EpicRating has noticed that a song has been skipped!';
    my $DefaultRating = $::Options{"DefaultRating"};
    my $rules = $::Options{OPT.'Rules'};
    my $ID=$::PlayingID;

    # we apply the default if the checkbox is enabled regardless
    # of rules.
    my $song_rating = Songs::Get($ID, 'rating');
    if(!($song_rating && $::Options{OPT."SetDefaultRatingOnSkipped"})) {
	::Songs::Set($ID, rating=>$DefaultRating);
    }


    my $all_skip_rules = GetRulesBySignal('Skipped');

    foreach my $skip_rule (@{$all_skip_rules}) {
	my $before = ${$skip_rule}{'before'};
	my $after = ${$skip_rule}{'after'};

	# takes a list of expressions
	# if an expression is true, OR an operand is nil, AND it with the others.
	# return true
	# meh, maybe not useful

	my $after_exists = defined($after)  && $after ne "";
	my $before_exists = defined($before) && $before ne "";

	if(!$before_exists && !$after_exists) {
	    # neither
	    # warn "Evalauted skip rule... neither after or before constraints.";
	    ApplyRule($skip_rule, $ID);
	    return;
	} elsif($before_exists && $after_exists) {
	    # both
	    # warn "Evaluated skip rule... there's a range.";
	    if(($::PlayTime >= $after) && ($::PlayTime <= $before)) {
		ApplyRule($skip_rule, $ID);
		return;
	    }
	} elsif($before_exists) {
	    # only before
	    # warn "Evaluated skip rule... only before constraint.";
	    if($::PlayTime <= $before) {
		ApplyRule($skip_rule, $ID);
		return;
	    }

	} elsif($after_exists) {
	    # only after
	    # warn "Evaluated skip rule... only after constraint.";
	    if($::PlayTime => $after) {
		ApplyRule($skip_rule, $ID);
		return;
	    }
	} else {
	    warn "wow, um, I missed a case?";
	}
    }
}

sub Start {
    # ::Watch($self, Played => \&Played);
    ::Watch($self, Finished => \&Finished);
    ::Watch($self, Skipped => \&Skipped);
}

sub Stop {
    ::UnWatch($self, $_) for qw/Finished Skipped/;
}

# rule editor.
# - event
# - value
# - operator

my $editor_signals = ['Finished', 'Skipped'];
my $editor_fields = ['rating'];

# checkbox for "set default rating when file played/skipped, required for rating update on files without a rating"

# weird behaviour with Gtk2::Table->attach() not working for Add, even though the scenario ends up being no different than at creation time?! D:

# add setting to gmusicbrowser core UI for PlayedPercent.  not sure why it isn't there already. :P

# perl, sigh.
# sub indexOfStr {
#     my ($arr,  $matey) = @_;
#     for(my $idx = 0; $idx <= $#{$arr}; $idx ++) {
#         return $idx if $arr eq $matey;
#     }
# }

sub indexOfRef {
   my ($arr, $matey) = @_;
    for(my $idx = 0; $idx <= $#{$arr}; $idx ++) {
	return $idx if $arr == $matey;
    }
}

# sub deleteStrFromArr {
#     my ($arr, $strval) = @_;
#     splice($arr, indexOfStr($strval), 1);
# }

sub deleteRefFromArr {
    my ($arr, $ref) = @_;
    splice(@$arr, indexOfRef($arr, $ref), 1);
}

# sub RuleEditor {
#     my ($rule) = @_;

    

#     return $frame;
# }

sub RulesListAddRow {
    my $rule = $_[0]; # hash reference
    my $rule_editor = GMB::Plugin::EPICRATING::Editor->new($rule);
    $self->{rules_table}->add_with_properties($rule_editor, "expand", ::FALSE);

    $rule_editor->show_all();
    $self->{current_row} += 1;
}

sub NewRule {
    my $new_rule = { signal => "", field => "", value => 0};
    my $options_rules_array = $::Options{OPT.'Rules'};

    push(@$options_rules_array, $new_rule);
    return $new_rule;
}

sub PopulateRulesList {
    my $rules = $::Options{OPT.'Rules'};
     $self->{current_row} = 0;

     foreach my $rule (@{$rules}) {
	RulesListAddRow($rule);
     }
}

sub prefbox {
    # TODO validate good values?E!??!
    my $big_vbox = Gtk2::VBox->new(::FALSE, 2);
    my $rules_scroller = Gtk2::ScrolledWindow->new();
    $rules_scroller->set_policy('never', 'automatic');
#    $self->{rules_table} = Gtk2::Table->new(1, 4, ::FALSE);
    $self->{rules_table} = Gtk2::VBox->new();
    $rules_scroller->add_with_viewport($self->{rules_table});

    PopulateRulesList();
    # force some debug fixtures in
    # $::Options{OPT.'Rules'} = [ {signal => 'Finished', field => "rating", value => 5}, {signal => 'Skipped', field => 'rating', value => -5 }, { signal => "SkippedBefore15", field => "rating", value => -1}];

    my $add_rule_button = Gtk2::Button->new_from_stock('gtk-add');
    $add_rule_button->signal_connect('clicked', sub {

	my $rule = NewRule();
	# manually add the new rule, no point in repopulating everything
	RulesListAddRow($rule);
    });

    my $default_rating_box = Gtk2::VBox->new();
    my $set_default_rating_label = Gtk2::Label->new(_"Apply your default rating to files when they are first played (required for rating update on files with default rating):");
    my $set_default_rating_skip_check = ::NewPrefCheckButton(OPT."SetDefaultRatingOnSkipped", _"... on skipped songs");
    my $set_default_rating_finished_check = ::NewPrefCheckButton(OPT."SetDefaultRatingOnFinished", _"... on played songs");
    $default_rating_box->add($set_default_rating_label);
    $default_rating_box->add($set_default_rating_skip_check);
    $default_rating_box->add($set_default_rating_finished_check);

    my $rating_freq_dump_button = Gtk2::Button->new("CSV dump of rating populations to stdout");



    use Text::CSV;
    $rating_freq_dump_button->signal_connect(clicked => sub {
	my $file_chooser = Gtk2::FileChooserDialog->new(
	    _"Save gmusicbrowser song stats CSV dump as...",
	    undef, 'save', 'gtk-save' => 'ok', 'gtk-cancel' => 'cancel');
	my $response = $file_chooser->run();

	
	if($response eq 'ok') {
	    my $csv_filename = $file_chooser->get_filename();
	    open CSVF, ">", $csv_filename or warn "Couldn't open CSV output!";

	    use Data::Dumper;
	    my $csv = Text::CSV->new ({binary => 1 });
	    
	    my $all_songs = Filter->new("")->filter;
	    for my $song_id (@{$all_songs}) {
		my $rating = ::Songs::Get($song_id, 'rating');
		my $title = ::Songs::Get($song_id, 'title');
		my $playcount = ::Songs::Get($song_id, 'playcount');
		my $skipcount = ::Songs::Get($song_id, 'skipcount');
		$csv->combine(@{[$song_id, $title, $rating, $playcount, $skipcount]});
		print CSVF $csv->string . "\n";
	    }
	    close CSVF;
	}
	$file_chooser->destroy();
    });

    $big_vbox->add($rules_scroller);
    $big_vbox->add_with_properties($add_rule_button, "expand", ::FALSE);
    $big_vbox->add_with_properties($default_rating_box, "expand", ::FALSE);
    $big_vbox->add_with_properties($rating_freq_dump_button, "expand", ::FALSE);

    $big_vbox->show_all();
    return $big_vbox;
}

package GMB::Plugin::EPICRATING::Editor;
use Gtk2;
use base 'Gtk2::Frame';

sub ExtraFieldsEditor {
    my ($self) = @_;
    my $hbox = Gtk2::HBox->new();
    
    if($self->{rule}{signal} eq "Skipped") {
	my $b_label = Gtk2::Label->new(_"Before: ");
	my $b_entry = Gtk2::Entry->new();
	$b_entry->set_text($self->{rule}{before}) if defined($self->{rule}{before});
	$b_entry->signal_connect('changed', sub {
	    $self->{rule}{before} = $b_entry->get_text();
	});

	my $a_label = Gtk2::Label->new(_"After: ");
	my $a_entry = Gtk2::Entry->new();
	$a_entry->set_text($self->{rule}{after}) if defined($self->{rule}{after});
	$a_entry->signal_connect('changed', sub {
	    $self->{rule}{after} = $a_entry->get_text();
	});

	$hbox->add_with_properties($b_label, "expand", ::FALSE);
	$hbox->add_with_properties($b_entry, "expand", ::FALSE);
	$hbox->add_with_properties($a_label, "expand", ::FALSE);
	$hbox->add_with_properties($a_entry, "expand", ::FALSE);
	$hbox->show_all();
    }
    return $hbox;
}

sub rebuild_extra_fields {
    my $self = shift;
    $self->{editor_hbox}->remove($self->{extra_hbox}) unless(!defined($self->{extra_hbox}));
    $self->{extra_hbox} = $self->ExtraFieldsEditor();
    $self->{editor_hbox}->add_with_properties($self->{extra_hbox}, "expand", ::FALSE);
}

sub new {
    my ($class, $rule) = @_;
    my $self = bless Gtk2::Frame->new;
    $self->{rule} = $rule;

    $self->{editor_hbox} = Gtk2::HBox->new();

    $self->{extra_hbox} = undef;

    my $extra_fields = [];

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
	# shit, gotta repopulate the entire special-fields area
	# even better just to repopulate the whole thing?
	$self->rebuild_extra_fields();
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

    $self->{editor_hbox}->add_with_properties(Gtk2::Label->new(_"Signal: "), "expand", ::FALSE);
    $self->{editor_hbox}->add_with_properties($signal_combo, "expand", ::FALSE);

    $self->{editor_hbox}->add_with_properties(Gtk2::Label->new(_"Field: "), "expand", ::FALSE);
    $self->{editor_hbox}->add_with_properties($field_combo, "expand", ::FALSE);
    $self->{editor_hbox}->add_with_properties(Gtk2::Label->new(_"Differential: "), "expand", ::FALSE);
    $self->{editor_hbox}->add_with_properties($value_entry, "expand", ::FALSE);

    $self->rebuild_extra_fields();

    my $remove_button = Gtk2::Button->new_from_stock('gtk-delete');
    $remove_button->signal_connect('clicked', sub {
    	GMB::Plugin::EPICRATING::deleteRefFromArr($::Options{ GMB::Plugin::EPICRATING::OPT.'Rules'}, $rule);
	$self->destroy();
    });

    $self->{editor_hbox}->pack_end($remove_button, ::FALSE, ::FALSE, 1);
    $self->{editor_hbox}->show_all();
    $self->add($self->{editor_hbox});

    return $self;
}
