# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin MozEmbed
MozEmbed
Mozilla plugin
provide context views using MozEmbed
=cut

BEGIN
{	# test if mozembed is working
	system(q(perl -e 'use Gtk2 "-init"; use Gtk2::MozEmbed;$w=Gtk2::Window->new;my $e=Gtk2::MozEmbed->new; $w->add($e);$w->show_all;')); #this segfault when mozembed doesn't find its libs
	if (($? & 127) ==11) {die "Error : mozembed libraries not found. You need to add the mozilla path in /etc/ld.so.conf and run ldconfig (as root) or add the mozilla libraries path to the LD_LIBRARY_PATH environment variable.\n"}
}

package GMB::Plugin::MozEmbed;
use strict;
use warnings;
require 'simple_http.pm';
use Gtk2::MozEmbed;
use base 'Gtk2::VBox';
use constant
{	OPT => 'PLUGIN_MozEmbed_',
};

our $Embed;
Gtk2::MozEmbed->set_profile_path ($::HomeDir,'mozilla_profile');
if ($Gtk2::MozEmbed::VERSION>=0.06) {Gtk2::MozEmbed->push_startup}
else {$Embed=Gtk2::MozEmbed->new;} #needed to keep a Gtk2::MozEmbed to prevent xpcom from shutting down with the last gtkmozembed

my $active;
::SetDefaultOptions(OPT, StrippedWiki => 1);

sub Start
{	$active=1;
	update_Context_hash();
	&set_stripped_wiki;
}
sub Stop
{	$active=0;
	update_Context_hash(1);
}

sub update_Context_hash
{	for my $ref
		(	['DisableLyrics','MozLyrics','GMB::Plugin::MozEmbed::Lyrics'],
			['DisableWiki','MozWikipedia','GMB::Plugin::MozEmbed::Wikipedia'],
			['DisableLastfm','MozLastfm','GMB::Plugin::MozEmbed::Lastfm'],
		)
	{	my ($option,$key,$package)=@$ref;
		my $on= !$::Options{OPT.$option} && $active;
		if (exists $GMB::Context::Contexts{$key})
		{	if (!$on)
			{	GMB::Context::RemovePackage($key);
			}
		}
		elsif ($on)
		{	GMB::Context::AddPackage($package,$key);
		}
	}
}

sub set_stripped_wiki	#FIXME use print version instead ?
{	my $content='';
	if ($::Options{OPT.'StrippedWiki'})
	{ $content="/*@-moz-document domain(wikipedia.org) { */
.portlet {display: none !important;}
#f-list {display: none !important;}
#footer {display: none !important;}
#content {margin: 0 0 0 0 !important; padding: 0 0 0 0 !important}
/* } */	";
	}
	open my $fh,'>',join(::SLASH,$::HomeDir,'mozilla_profile','chrome','userContent.css') or return;
	print $fh $content;
	close $fh;
}

sub new
{	my ($class)=@_;
	my $self = bless Gtk2::VBox->new, $class;
	my $hbox = Gtk2::HBox->new;
	my $status=$self->{status}=Gtk2::Statusbar->new;
	$status->{id}=$status->get_context_id('link');
	my $embed=$self->{embed}=Gtk2::MozEmbed->new;
	my $back= $self->{BBack}=Gtk2::ToolButton->new_from_stock('gtk-go-back');
	my $next= $self->{BNext}=Gtk2::ToolButton->new_from_stock('gtk-go-forward');
	my $stop= $self->{BStop}=Gtk2::ToolButton->new_from_stock('gtk-stop');
	my $open= $self->{BOpen}=Gtk2::ToolButton->new_from_stock('gtk-jump-to');
	$open->set_tooltip($::Tooltips,_"Open this page in the web browser",'');
	#$open->set_use_drag_window(1);
	#::set_drag($open,source=>[::DRAG_FILE,sub {$embed->get_location;}]);
	$self->{$_}->set_sensitive(0) for qw/BBack BNext BStop BOpen/;
	$hbox->pack_start($_,::FALSE,::FALSE,4) for grep defined, $back,$next,$stop,$open,$self->addtoolbar;
	$self->pack_start($hbox,::FALSE,::FALSE,1);
	$self->add($embed);
	$self->pack_end($status,::FALSE,::FALSE,1) if $::Options{OPT.'StatusBar'};
	$self->show_all;
	$back->signal_connect(clicked => sub { $embed->go_back });
	$next->signal_connect(clicked => sub { $embed->go_forward });
	$stop->signal_connect(clicked => sub { $embed->stop_load });
	$open->signal_connect(clicked => sub { my $url=$embed->get_location; ::openurl($url) if $url=~m#^https?://# });
	$embed->signal_connect(link_message => \&link_message_cb);
	$embed->signal_connect(net_stop => \&net_startstop_cb,0);
	$embed->signal_connect(net_start => \&net_startstop_cb,1);
	return $self;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	#my $combo=::NewPrefCombo(OPT.'Site',[sort keys %sites],'site : ',sub {$ID=undef;&Changed;});
	my $check=::NewPrefCheckButton(OPT.'StrippedWiki',_"Strip wikipedia pages",\&set_stripped_wiki,_"Remove header, footer and left column from wikipedia pages");
	my $Bopen=Gtk2::Button->new(_"open context window");
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	my $check1=::NewPrefCheckButton(OPT.'DisableWiki',_"Disable wikipedia context tab",\&update_Context_hash);
	my $check2=::NewPrefCheckButton(OPT.'DisableLyrics',_"Disable Lyrics context tab",\&update_Context_hash);
	my $check3=::NewPrefCheckButton(OPT.'DisableLastfm',_"Disable Last.fm context tab",\&update_Context_hash);
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $check1,$check2,$check3,$check,$Bopen;
	return $vbox;
}

sub load_url
{	my ($self,$url,$post)=@_;
	$self->{url}=$url;
	$self->{post}=$post;
	if ($post)
	{ Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url,post => $post); }
	else {$self->{embed}->load_url($url);}
}

sub loaded
{	my ($self,$data,$type)=@_;
	my $embed=$self->{embed};
	$embed->render_data($data,$self->{url},$type)
#	$embed->open_stream ($self->{url}, $type);
#	$embed->append_data ($data);
#	$embed->close_stream;
}

sub link_message_cb
{	my $embed=$_[0];
	my $self=::find_ancestor($embed,__PACKAGE__);
	my $statusbar=$self->{status};
	$statusbar->pop( $statusbar->{id} );
	$statusbar->push( $statusbar->{id}, $embed->get_link_message );
}

sub net_startstop_cb
{	my ($embed,$loading)=@_;
	my $self=::find_ancestor($embed,__PACKAGE__);
	$self->{BStop}->set_sensitive( $loading );
	$self->{BBack}->set_sensitive( $embed->can_go_back );
	$self->{BNext}->set_sensitive( $embed->can_go_forward );
	my $loc=$embed->get_location;
	$loc= $loc=~m#^https?://# ? 1 : 0 ;
	$self->{BOpen}->set_sensitive($loc);
}

package GMB::Plugin::MozEmbed::Lyrics;
our @ISA=('GMB::Plugin::MozEmbed');

use constant
{	title => _"Lyrics",
	OPT => GMB::Plugin::MozEmbed::OPT,  #FIXME
};

my %sites=
(	#lyrc => ['lyrc','http://lyrc.com.ar/en/tema1en.php','artist=%a&songname=%s'],
	lyrc => ['lyrc','http://lyrc.com.ar/en/tema1en.php?artist=%a&songname=%s'],
	#leoslyrics => ['leolyrics','http://api.leoslyrics.com/api_search.php?artist=%a&songtitle=%s'],
	google  => ['google','http://www.google.com/search?q="%a"+"%s"'],
	googlemusic  => ['google music','http://www.google.com/musicsearch?q="%a"+"%s"'],
	lyriki  => ['lyriki','http://lyriki.com/index.php?title=%a:%s'],
	lyricwiki => ['lyricwiki','http://lyricwiki.org/%a:%s'],
);

::SetDefaultOptions(OPT, LyricSite => 'google');

sub addtoolbar
{	#my $self=$_[0];
	my %h= map {$_=>$sites{$_}[0]} keys %sites;
	my $cb=sub
	 {	my $self=::find_ancestor($_[0],__PACKAGE__);
		$self->SongChanged($self->{ID},1);
	 };
	my $combo=::NewPrefCombo( OPT.'LyricSite', \%h, undef, $cb);
	return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && $ID==$self->{ID} && !$force;
	$self->{ID}=$ID;
	my $ref=$::Songs[$ID];
	my $title=$ref->[::SONG_TITLE];
	return if !defined $title || $title eq '';
	my $artist=$ref->[::SONG_ARTIST];
	$artist=::url_escapeall($artist);
	$title= ::url_escapeall($title);
	my (undef,$url,$post)=@{$sites{$::Options{OPT.'LyricSite'}}};
	for ($url,$post) { next unless defined $_; s/%a/$artist/; s/%s/$title/; }
	::IdleDo('8_mozlyrics'.$self,1000,sub {$self->load_url($url,$post)});
}

package GMB::Plugin::MozEmbed::Wikipedia;
our @ISA=('GMB::Plugin::MozEmbed');

use constant
{	title => _"Wikipedia",
	OPT => GMB::Plugin::MozEmbed::OPT,  #FIXME
};

my %locales=
(	en => 'English',
	fr => 'Français',
	de => 'Deutsch',
	pl => 'Polski',
	nl => 'Nederlands',
	sv => 'Svenska',
	it => 'Italiano',
	pt => 'Português',
	es => 'Español',
#	ja => "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\x0a",
);
#::_utf8_on( $locales{ja} );

::SetDefaultOptions(OPT, WikiLocale => 'en');

sub addtoolbar
{	#my $self=$_[0];
	my $cb=sub
	 {	my $self=::find_ancestor($_[0],__PACKAGE__);
		$self->SongChanged($self->{ID},1);
	 };
	my $combo=::NewPrefCombo( OPT.'WikiLocale', \%locales, undef, $cb);
	return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	$self->{ID}=$ID;
	my $artist=$::Songs[$ID][::SONG_ARTIST];
	return if !defined $artist || $artist eq '' || $artist eq '<Unknown>';
	return if defined $self->{Artist} && $artist eq $self->{Artist} && !$force;
	($artist)=split /$::re_artist/o,$artist; #FIXME add a way to choose artist ?
	$self->{Artist}=$artist;
	$artist=::url_escapeall($artist);
	my $url='http://'.$::Options{OPT.'WikiLocale'}.'.wikipedia.org/wiki/'.$artist;
	#my $url='http://'.$::Options{OPT.'WikiLocale'}.'.wikipedia.org/w/index.php?title='.$artist.'&action=render';
	::IdleDo('8_mozpedia'.$self,1000,sub {$self->load_url($url)});
	#::IdleDo('8_mozpedia'.$self,1000,sub {$self->wikiload});
}

sub wikiload	#not used for now
{	my $self=$_[0];
	my $url=::url_escapeall($self->{Artist});
	$url='http://'.$::Options{OPT.'WikiLocale'}.'.wikipedia.org/wiki/'.$url;
	#$url='http://google.com/search?q='.$url;
	$self->{url}=$url;
	Simple_http::get_with_cb(cb => sub
		{	my $cb=sub { $self->wikifilter(@_) };
			if (!$_[0] || $_[0]=~m/No page with that title exists/)
			{	Simple_http::get_with_cb(cb => $cb, url => $url);
			}
			else { $self->{url}.='_(band)'; goto $cb }
		},url => $url.'_(band)');
}

sub wikifilter	#not used for now
{	my ($self,$data,$type)=@_;
	return unless $data;	#FIXME
	#$data='<style type="text/css">.firstHeading {display: none}</style>'.$data;
	$self->loaded($data,$type);
}

package GMB::Plugin::MozEmbed::Lastfm;
our @ISA=('GMB::Plugin::MozEmbed');

use constant
{	title => "Last.fm",
#	OPT => GMB::Plugin::MozEmbed::OPT,  #FIXME
};

sub addtoolbar
{	#my $self=$_[0];
	#my $combo=Gtk2::ComboBox->new_text;
	#return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	$self->{ID}=$ID;
	my $artist=$::Songs[$ID][::SONG_ARTIST];
	return if !defined $artist || $artist eq '' || $artist eq '<Unknown>';
	return if defined $self->{Artist} && $artist eq $self->{Artist} && !$force;
	$self->{Artist}=$artist;
	$artist=~s/ /+/g;
	$artist=::url_escapeall($artist);
	my $url='http://www.last.fm/music/'.$artist;
	::IdleDo('8_mozlastfm'.$self,1000,sub {$self->load_url($url)});
}


1

# FIXME use google music : http://www.google.com/musicsearch?q="%a"
