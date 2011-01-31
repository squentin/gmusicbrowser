# Copyright (c) 2009-2010 Sergiy Borodych and Andreas Böttger <andreas.boettger@gmx.de>
#
# The plugin is based on the Program lastfm2gmb by Sergiy Borodych
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin LASTFM2GMB
name	ImportLastFM
title	LastFM import plugin
version	0.1
author  Sergiy Borodych
author  Andreas Böttger <andreas.boettger@gmx.de>
desc	Import playcount, lastplay and rating from last.fm.
=cut

package GMB::Plugin::LASTFM2GMB;
use strict;
use warnings;
use utf8;
use base 'Gtk2::Box';
use Encode;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;
use Net::DBus;
use Storable;
use XML::Simple;
use constant
{	OPT	=> 'PLUGIN_LASTFM2GMB_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
	SITEURL => 0,
};



use constant VERSION => 0.03;

binmode(STDOUT, ":utf8");

#my $usage = "lastfm2gmb v".VERSION." (c)2009-2010 Sergiy Borodych
#Usage: $0 [-c] [-q|-d debug_level] [-k api_key] [-m mode] -u username
#Options:
# -c | --cache           : enable cache results (only for 'playcount & lastplay' mode)
# -d | --debug           : debug level 0..2
# -k | --key             : lastfm api key
# -m | --mode            : import mode: 'a' - all, 'p' - playcount & lastplay, 'l' - loved
# -q | --quiet           : set debug = 0 and no any output
# -r | --rating_loved    : rating for loved tracks (1..100), default 100
# -t | --tmp_dir         : tmp dir for cache store, etc
# -u | --user            : lastfm username, required
#Example:
# lastfm2gmb.pl -c -m p -t /var/tmp/lastfm2gmb -u username
#";

#our %opt;
#Getopt::Long::Configure("bundling");
#GetOptions(
#    'api_uri'           => \$opt{api_uri},  # lastFM API request URL
#    'cache|c'           => \$opt{cache},    # enable cache results (only for user.getWeeklyTrackChart method)
#    'debug|d=i'         => \$opt{debug},    # debug level 0..2
#    'help|h'            => \$opt{help},     # help message ?
#    'key|k=s'           => \$opt{key},      # lastfm api key
#    'mode|m=s'          => \$opt{mode},     # import mode: a - all, p - playcount & lastplay, l - loved
#    'quiet|q'           => \$opt{quiet},    # set debug = 0 and no any output
#    'rating_loved|r=i'  => \$opt{rating_loved}, # rating for loved tracks (1..100), default 100
#    'tmp_dir|t=s'       => \$opt{tmp_dir},  # tmp dir for cache store, etc
#    'user|u=s'          => \$opt{user},     # lastfm username
#)
#    or die "$usage\n";

#print $usage and exit if $opt{help};

## check options
#$opt{api_uri} ||= 'http://ws.audioscrobbler.com/2.0/';
#$opt{debug} ||= 0;
#$opt{key} ||= '4d4019927a5f30dc7d515ede3b3e7f79';       # 'lastfm2gmb' user api key
#$opt{key} or die "Need api key!\n$usage\n";
#$opt{mode} ||= 'a';
#$opt{mode} = 'pl' if $opt{mode} eq 'a';
#$opt{rating_loved} ||= 100;
#$opt{tmp_dir} ||=  File::Spec->catdir( File::Spec->tmpdir(), 'lastfm2gmb' );
#$opt{user} or die "Need username!\n\n$usage\n";



::SetDefaultOptions(OPT, api_uri => "http://ws.audioscrobbler.com/2.0/", key => "4d4019927a5f30dc7d515ede3b3e7f79", mode => "a", rating_loved => "100", tmp_dir => File::Spec->catdir( File::Spec->tmpdir(), 'lastfm2gmb' ), user => "", quiet => "false", debug => "0");

our $ua = LWP::UserAgent->new( timeout=>15 );
our $xs = XML::Simple->new(ForceArray=>['track']);

my $Log=Gtk2::ListStore->new('Glib::String');

sub Start {
}

sub Stop {
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);

	my $titlebox=Gtk2::HBox->new(0,0);
    my $api_uri=::NewPrefEntry(OPT.'api_uri' => _"API URI:", width=>50, tip => _"lastFM API request URL");
    my $key=::NewPrefEntry(OPT.'key' => _"User API Key:", width=>50, tip => _"lastfm api key");
	my $mode=::NewPrefEntry(OPT.'mode' => _"Import mode:", width=>3, tip => _"import mode: a - all, p - playcount & lastplay, l - loved");
	my $rating_loved=::NewPrefEntry(OPT.'rating_loved' => _"Loved tracks rating:", width=>3, tip => _"rating for loved tracks (1..100)");
    my $tmp_dir=::NewPrefEntry(OPT.'tmp_dir' => _"Temp dir:", width=>50, tip => _"tmp dir for cache store, etc");
    my $user=::NewPrefEntry(OPT.'user' => _"LastFM user:", width=>50, tip => _"lastfm username");
	my $description=Gtk2::Label->new;
	$description->set_markup(_"PRE ALPHA!!! Nothing works!!!\nThe plugin is based on the Program <b>lastfm2gmb</b> by Sergiy Borodych and is hosted on <a href='https://github.com/bor/lastfm2gmb'>lastfm2gmb - GitHub</a>.");
	$description->set_line_wrap(1);
	$titlebox->pack_start($description,1,1,0);
	my $optionbox=Gtk2::VBox->new(0,2);
	$optionbox->pack_start($_,0,0,1) for $api_uri,$key,$mode,$rating_loved,$tmp_dir,$user;

    my $button=Gtk2::Button->new(_"Make it now");
    $button->signal_connect(clicked => \&make_it_now);

	$vbox->pack_start($_,::FALSE,::FALSE,5) for $titlebox,$optionbox,$button;
    $vbox->add( ::LogView($Log) );
	return $vbox;
}

sub make_it_now {
    Log(_"Let's start");
    if ( $::Options{OPT.'cache'} and ! -d $::Options{OPT.'tmp_dir'} ) {
        mkdir($::Options{OPT.'tmp_dir'}) or Log(_("Can't create tmp dir").$::Options{OPT.'tmp_dir'});
        # die "Can't create tmp dir $::Options{OPT.'tmp_dir'}: $!";
    }
    $::Options{OPT.'mode'} = 'pl' if $::Options{OPT.'mode'} eq 'a';
    Log(_("Unknown mode: ").$::Options{OPT.'mode'}) unless $::Options{OPT.'mode'}=~/[pl]/;
    Log(_("Last.FM user necessary.").$::Options{OPT.'user'}) unless $::Options{OPT.'user'}=~/.+/;
    # die "Unknown mode!" unless $::Options{OPT.'mode'}=~/[pl]/;

    my $bus = Net::DBus->session;
    my $service = $bus->get_service("org.gmusicbrowser");
    my $gmb_obj = $service->get_object("/org/gmusicbrowser","org.gmusicbrowser");

    $| = 1;
    my %stats = ( imported_playcount => 0, imported_lastplay => 0, imported_loved => 0, lastfm_plays => 0, skiped => 0 );
    my $gmb_library = {};
    my $lastfm_library = {};

    # get current gmb library
    Log(_"Looking up gmb library");
    Log("Pre Alpha, I do nothing.");
=dop
    foreach my $id ( @{$gmb_obj->GetLibrary} ) {
        my $artist = $gmb_obj->Get([$id,'artist']) or next;
        my $title = $gmb_obj->Get([$id,'title']) or next;
        utf8::decode($artist);
        utf8::decode($title);
        $artist = lc($artist);
        $title = lc($title);
        # TODO: if multiple song's with same names when skip it now
        if ( $gmb_library->{$artist}{$title} ) {
            Log("[$id] $artist - $title : found dup - skiped");
            $gmb_library->{$artist}{$title} = { skip => 1 };
            $stats{skiped}++;
        }
        else {
            Log("[$id] $artist - $title : ");
            $gmb_library->{$artist}{$title}{id} = $id;
            if ( $::Options{OPT.'mode'}=~m/p/o ) {
                $gmb_library->{$artist}{$title}{playcount} = $gmb_obj->Get([$id,'playcount']) || 0;
                $gmb_library->{$artist}{$title}{lastplay} = $gmb_obj->Get([$id,'lastplay']) || 0;
                print "playcount: $gmb_library->{$artist}{$title}{playcount} lastplay: $gmb_library->{$artist}{$title}{lastplay} "
                    if $::Options{OPT.'debug'} >= 2;
            }
            if ( $::Options{OPT.'mode'}=~m/l/o ) {
                $gmb_library->{$artist}{$title}{rating} = $gmb_obj->Get([$id,'rating']) || 0;
                print "rating: $gmb_library->{$artist}{$title}{rating}" if $::Options{OPT.'debug'} >= 2;
            }
            print "\n" if $::Options{OPT.'debug'} >= 2;
        }
        $stats{gmb_tracks}++;
        print '.' unless $::Options{OPT.'quiet'} or $stats{gmb_tracks} % 100;
        last if $stats{gmb_tracks} > 100 and $::Options{OPT.'debug'} >= 3;
    }

=dop
    Log(" $stats{gmb_tracks} tracks ($stats{skiped} skipped as dup)";

    our $ua = LWP::UserAgent->new( timeout=>15 );
    our $xs = XML::Simple->new(ForceArray=>['track']);

    # playcount & lastplay
    if ( $::Options{OPT.'mode'}=~m/p/ ) {
        # get weekly chart list
        my $charts_data = lastfm_request({method=>'user.getWeeklyChartList'}) or Log(_"Can't get data from lastfm");
        # add current (last) week
        my $last_week_from = $charts_data->{weeklychartlist}{chart}[$#{$charts_data->{weeklychartlist}{chart}}]{to};
        push @{$charts_data->{weeklychartlist}{chart}}, { from=>$last_week_from, to=>time() }
            if $last_week_from < time();
        print "LastFM request 'WeeklyChartList' found ".scalar(@{$charts_data->{weeklychartlist}{chart}})." pages\n"
            unless $::Options{OPT.'quiet'};
        # clean 'last week' pages workaround
        unlink(glob(File::Spec->catfile($::Options{OPT.'tmp_dir'},"WeeklyTrackChart-$::Options{OPT.'user'}-$last_week_from-*")));
        # get weekly track chart
        print "LastFM request 'WeeklyTrackChart' pages " unless $::Options{OPT.'quiet'};
        foreach my $date ( @{$charts_data->{weeklychartlist}{chart}} ) {
            print "$date->{from}-$date->{to}.." if $::Options{OPT.'debug'};
            print '.' unless $::Options{OPT.'quiet'};
            my $data = lastfm_get_weeklytrackchart({from=>$date->{from},to=>$date->{to}});
            foreach my $title ( keys %{$data->{weeklytrackchart}{track}} ) {
                my $artist = lc($data->{weeklytrackchart}{track}{$title}{artist}{name}||$data->{weeklytrackchart}{track}{$title}{artist}{content});
                my $playcount = $data->{weeklytrackchart}{track}{$title}{playcount};
                $title = lc($title);
                print "$artist - $title - $playcount\n" if $::Options{OPT.'debug'} >= 2;
                if ( $gmb_library->{$artist}{$title} and $gmb_library->{$artist}{$title}{id} ) {
                    $lastfm_library->{$artist}{$title}{playcount} += $playcount;
                    $lastfm_library->{$artist}{$title}{lastplay} = $date->{from}
                        if ( !$lastfm_library->{$artist}{$title}{lastplay}
                                or $lastfm_library->{$artist}{$title}{lastplay} < $date->{from} );
                }
                $stats{lastfm_plays} += $playcount;
            }
            last if $::Options{OPT.'debug'} >= 3;
        }
        print " total $stats{lastfm_plays} plays\n" unless $::Options{OPT.'quiet'};
    }

    # loved tracks (rating)
    if ( $::Options{OPT.'mode'}=~m/l/ ) {
        # first request for get totalPages
        my $data = lastfm_request({method=>'user.getLovedTracks'}) or Log(_"Can't get data from lastfm");
        Log(_("Something wrong: status = ").$data->{status}) unless $data->{status} eq 'ok';
        #die "Something wrong: status = $data->{status}" unless $data->{status} eq 'ok';
        my $pages = $data->{lovedtracks}{totalPages};
        print "LastFM request 'getLovedTracks' found $pages pages ($data->{lovedtracks}{total} tracks)\n" unless $::Options{OPT.'quiet'};
        print "LastFM request 'getLovedTracks' pages " unless $::Options{OPT.'quiet'};
        for ( my $p = 1; $p <= $pages; $p++ ) {
            print "$p.." if $::Options{OPT.'debug'};
            print '.' unless $::Options{OPT.'quiet'};
            $data = lastfm_request({method=>'user.getLovedTracks',page=>$p}) or Log(_"Can't get data from lastfm");
            foreach my $title ( keys %{$data->{lovedtracks}{track}} ) {
                my $artist = lc($data->{lovedtracks}{track}{$title}{artist}{name}||$data->{lovedtracks}{track}{$title}{artist}{content});
                $title = lc($title);
                print "$artist - $title is a loved\n" if $::Options{OPT.'debug'} >= 2;
                if ( $gmb_library->{$artist}{$title} and $gmb_library->{$artist}{$title}{id} ) {
                    $lastfm_library->{$artist}{$title}{rating} = $::Options{OPT.'rating_loved'};
                }
            }
        }
        print "\n" unless $::Options{OPT.'quiet'};
    }

    # import info to gmb
    print "Import to gmb " unless $::Options{OPT.'quiet'};
    foreach my $artist ( sort keys %{$lastfm_library} ) {
        print '.' unless $::Options{OPT.'quiet'};
        print "$artist\n" if $::Options{OPT.'debug'} >= 2;
        foreach my $title ( keys %{$lastfm_library->{$artist}} ) {
            my $e;
            print " $title - $lastfm_library->{$artist}{$title}{playcount} <=> $gmb_library->{$artist}{$title}{playcount}\n" if $::Options{OPT.'debug'} >= 2;
            # playcount
            if ( $lastfm_library->{$artist}{$title}{playcount}
                    and $lastfm_library->{$artist}{$title}{playcount} > $gmb_library->{$artist}{$title}{playcount} ) {
                print "  $artist - $title : playcount : $gmb_library->{$artist}{$title}{playcount} -> $lastfm_library->{$artist}{$title}{playcount}\n" if $::Options{OPT.'debug'};
                $gmb_obj->Set([ $gmb_library->{$artist}{$title}{id}, 'playcount', $lastfm_library->{$artist}{$title}{playcount}])
                    or $e++ and warn " error setting 'playcount' for track ID $gmb_library->{$artist}{$title}{id}\n";
                $e ? $stats{errors}++ : $stats{imported_playcount}++;
            }
            # lastplay
            if ( $lastfm_library->{$artist}{$title}{lastplay}
                    and $lastfm_library->{$artist}{$title}{lastplay} > $gmb_library->{$artist}{$title}{lastplay} ) {
                print "  $artist - $title : lastplay : $gmb_library->{$artist}{$title}{lastplay} -> $lastfm_library->{$artist}{$title}{lastplay}\n" if $::Options{OPT.'debug'};
                $gmb_obj->Set([ $gmb_library->{$artist}{$title}{id}, 'lastplay', $lastfm_library->{$artist}{$title}{lastplay} ])
                    or $e++ and warn " error setting 'lastplay' for track ID $gmb_library->{$artist}{$title}{id}\n";
                $e ? $stats{errors}++ : $stats{imported_lastplay}++;
            }
            # loved
            if ( $lastfm_library->{$artist}{$title}{rating}
                    and $lastfm_library->{$artist}{$title}{rating} > $gmb_library->{$artist}{$title}{rating} ) {
                $gmb_obj->Set([ $gmb_library->{$artist}{$title}{id}, 'rating', $lastfm_library->{$artist}{$title}{rating}])
                                or $e++ and warn " error setting 'rating' for track ID $gmb_library->{$artist}{$title}{id}\n";
                $e ? $stats{errors}++ : $stats{imported_loved}++;
            }
        }
    }

    print "\nImported : playcount - $stats{imported_playcount}, lastplay - $stats{imported_lastplay}, loved - $stats{imported_loved}. " . ($stats{errors} ? $stats{errors} : 'No') . " errors detected.\n"
        unless $::Options{OPT.'quiet'};
=cut
}


# lastfm request
sub lastfm_request {
    my ($params) = @_;
    my $url = "$::Options{OPT.'api_uri'}?api_key=$::Options{OPT.'key'}&user=$::Options{OPT.'user'}";
    if ( $params ) {
        $url .= '&'.join('&',map("$_=$params->{$_}",keys %{$params}));
    }
    my $response = $ua->get($url);
    if ( $response->is_success ) {
        return $xs->XMLin($response->decoded_content);
    }
    else {
        warn "Error: Can't get url '$url' - " . $response->status_line."\n";
        return;
    }
}


# get weekly track chart list
sub lastfm_get_weeklytrackchart {
    my ($params) = @_;
    my $filename = File::Spec->catfile($::Options{OPT.'tmp_dir'}, "WeeklyTrackChart-$::Options{OPT.'user'}-$params->{from}-$params->{to}.data");
    my $data;
    if ( $::Options{OPT.'cache'} and -e $filename ) {
        $data = retrieve($filename);
    }
    else {
        $data = lastfm_request({method=>'user.getWeeklyTrackChart',%{$params}}) or Log(_"Can't get data from lastfm");
        # TODO : strip some data, for left only need info like: artist, name, playcount
        store $data, $filename if $::Options{OPT.'cache'};
    }
    return $data;
}

sub Log {
    my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,50)) { $Log->remove($iter); }
}

