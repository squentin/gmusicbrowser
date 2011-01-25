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



::SetDefaultOptions(OPT, api_uri => "http://ws.audioscrobbler.com/2.0/", key => "4d4019927a5f30dc7d515ede3b3e7f79", mode => "a", rating_loved => "100", tmp_dir => File::Spec->catdir( File::Spec->tmpdir(), 'lastfm2gmb' ), user => "");

my $lastfm2gmbwidget=
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-lastfm2gmb',		# no icon by that name by default (yet)
	tabtitle	=> _"Artistinfo",
};

our $ua = LWP::UserAgent->new( timeout=>15 );
our $xs = XML::Simple->new(ForceArray=>['track']);

sub Start {
	Layout::RegisterWidget(PluginLastfm2gmb => $lastfm2gmbwidget);
	#push @::cMenuAA,\%menuitem;
}
sub Stop {
	Layout::RegisterWidget(PluginLastfm2gmb => undef);
	#@::cMenuAA=  grep $_!=\%menuitem, @::SongCMenu;
}


sub new {
    my ($class,$options)=@_;
    my $self = bless Gtk2::VBox->new(0,0), $class;



    return $self;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(0,2);
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
	$vbox->pack_start($_,::FALSE,::FALSE,5) for $titlebox,$optionbox;
	return $vbox;
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
        $data = lastfm_request({method=>'user.getWeeklyTrackChart',%{$params}}) or die 'Cant get data from lastfm';
        # TODO : strip some data, for left only need info like: artist, name, playcount
        store $data, $filename if $::Options{OPT.'cache'};
    }
    return $data;
}

