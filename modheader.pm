# Copyright (C) 2020 Quentin Sculo <squentin@free.fr>
# Copyright (C) 2021 Daniel Hursh <dan@hursh.org>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Tag::Modfile;

use strict;
use warnings;

our $OK;

BEGIN { $OK= eval {
	require 'ModFileMetadata.pm';
	require 'generic_metadata_reader_gstreamer.pm'; # Use gstreamer code to read lengths
	};
}



# if called from command line, useful for testing
if (!caller && @ARGV) {
    # in a string eval so that it has no effect when called from gmb
    eval 'use FindBin; use lib $FindBin::RealBin; use ModFileMetadata;';
    my $self= Tag::Modfile->new($ARGV[0]);
    my $info= $self->{info};
    my $tags= $self->{tag};
    binmode STDOUT,':utf8';
    print "info:\n";
    print "  $_: $info->{$_}\n" for sort grep defined $info->{$_}, keys %$info;
    print "tag:\n";
    print "  $_: $tags->{$_}\n" for sort grep defined $tags->{$_}, keys %$tags;
}

sub new {
    my ($class,$file)=@_;
    my $self=bless {}, $class;

    # check that the file exists
    unless (-e $file){
	warn "Skipping file '$file': File does not exist.\n";
        return undef;
    }

    # read the file
    my $mod_info = ModFileMetadata->new($file);
    unless(defined $mod_info){
        warn "Skipping file '$file': not recognized.\n";
        return undef;
    }
    unless($mod_info->isValidModFile){
        warn "Skipping file '$file': not valid.\n";
        return undef;
    }

    # If we got anything, read gst metadata too
    if(defined $self && $Tag::Generic::GStreamer::OK){
        # query gst
        my $gst_tags = Tag::Generic::GStreamer->new($file);
        $self->{gst_tags} = $gst_tags if defined $gst_tags;
    }

    # Store info
    #$self->{filename}               = $file; Not needed?
    #$self->{info}{container_format} = 'MOD';
    $self->{info}{audio_format} = $mod_info->typeVerbose if defined $mod_info->typeVerbose;
    $self->{tag}{title}    = $mod_info->title     if defined $mod_info->title;
    $self->{tag}{artist}   = $mod_info->artist    if defined $mod_info->artist;
    $self->{tag}{comment}  = $mod_info->message   if defined $mod_info->message;
    $self->{info}{seconds} = $self->{gst_tags}{info}{seconds}
        if exists($self->{gst_tags})
        && exists($self->{gst_tags}{info})
        && exists($self->{gst_tags}{info}{seconds});
    delete($self->{gst_tags});
    # Save the object?  $self->{mod_info} = \$mod_info;
    # Need to address samples, instruments and perhaps typeVerbose
    return $self;
}

sub get_values {
    my ($self,$field)=@_;
    return exists($self->{tag}{$field})? $self->{tag}{$field} : undef
}

1;
