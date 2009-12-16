# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation


=gmbplugin WebContext
name	Web context
title	Web context plugin
desc	Provides context views using MozEmbed or WebKit
=cut

my ($OKMoz,$OKWebKit,$CrashMoz);
BEGIN
{	{	last unless (grep -f $_.'/Gtk2/MozEmbed.pm',@INC);
		# test if mozembed is working
		system(q(GNOME_DISABLE_CRASH_DIALOG=1 perl -e 'use Gtk2 "-init"; use Gtk2::MozEmbed;$w=Gtk2::Window->new;my $e=Gtk2::MozEmbed->new; $w->add($e);$w->show_all;')); #this segfault when mozembed doesn't find its libs
		#if (($? & 127) ==11) {die "Error : mozembed libraries not found. You need to add the mozilla path in /etc/ld.so.conf and run ldconfig (as root) or add the mozilla libraries path to the LD_LIBRARY_PATH environment variable.\n"}
		if (($? & 127) ==11) { $CrashMoz=1; last; }
		$OKMoz=1;
	}
	$OKWebKit=1 if grep -f $_.'/Gtk2/WebKit.pm',@INC;
}

use strict;
use warnings;

package GMB::Plugin::WebContext::MozEmbed;
#use Gtk2::MozEmbed;

our $Embed;
sub init
{	Gtk2::MozEmbed->set_profile_path ($::HomeDir,'mozilla_profile');
	if ($Gtk2::MozEmbed::VERSION>=0.06) {Gtk2::MozEmbed->push_startup}
	else {$Embed||=Gtk2::MozEmbed->new;} #needed to keep a Gtk2::MozEmbed to prevent xpcom from shutting down with the last gtkmozembed
}

sub new_embed
{	my $embed=Gtk2::MozEmbed->new;
	$embed->signal_connect(link_message => \&link_message_cb);
	$embed->signal_connect(net_stop => \&net_startstop_cb,0);
	$embed->signal_connect(net_start => \&net_startstop_cb,1);
	return $embed;
}

sub link_message_cb
{	my $embed=$_[0];
	my $self=::find_ancestor($embed,__PACKAGE__);
	$self->link_message( $embed->get_link_message );
}

sub net_startstop_cb
{	my ($embed,$loading)=@_;
	my $self=::find_ancestor($embed,__PACKAGE__);
	$self->{BStop}->set_sensitive( $loading );
	$self->{BBack}->set_sensitive( $embed->can_go_back );
	$self->{BNext}->set_sensitive( $embed->can_go_forward );
	my $cursor= $loading ? Gtk2::Gdk::Cursor->new('watch') : undef;
	$embed->window->set_cursor($cursor) if $embed->window;
	my $uri=$embed->get_location;
	$self->{Entry}->set_text($uri) if $loading;
	$uri= $uri=~m#^https?://# ? 1 : 0 ;
	$self->{BOpen}->set_sensitive($uri);
}

sub loaded
{	my ($self,$data,$type)=@_;
	my $embed=$self->{embed};
	$embed->render_data($data,$self->{url},$type)
#	$embed->open_stream ($self->{url}, $type);
#	$embed->append_data ($data);
#	$embed->close_stream;
}

sub go_back	{ $_[0]{embed}->go_back }
sub go_forward	{ $_[0]{embed}->go_forward }
sub stop_load	{ $_[0]{embed}->stop_load }
sub get_location{ $_[0]{embed}->get_location }
sub Open	{ $_[0]{embed}->load_url($_[1]); }

sub set_stripped_wiki	#FIXME use print version of the wikipedia page instead ?
{	my $stripped=$_[0];
	my $content='';
	if ($stripped)
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

package GMB::Plugin::WebContext::WebKit;
#use Gtk2::WebKit;

sub new_embed
{	my $embed=Gtk2::WebKit::WebView->new;
	$embed->signal_connect(hovering_over_link => \&link_message_cb);
	$embed->signal_connect(load_finished => \&net_startstop_cb,0);
	$embed->signal_connect(load_committed => \&net_startstop_cb,1);
	my $sw= Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($embed);
	return $embed,$sw;
}

sub link_message_cb
{	my ($embed,undef,$msg)=@_;
	my $self=::find_ancestor($embed,__PACKAGE__);
	$self->link_message($msg);
}

sub net_startstop_cb
{	my ($embed,$frame,$loading)=@_;
	my $self=::find_ancestor($embed,__PACKAGE__);
	$self->{BStop}->set_sensitive( $loading );
	$self->{BBack}->set_sensitive( $embed->can_go_back );
	$self->{BNext}->set_sensitive( $embed->can_go_forward );
	my $cursor= $loading ? Gtk2::Gdk::Cursor->new('watch') : undef;
	$embed->window->set_cursor($cursor) if $embed->window;
	my $uri=$frame->get_uri;
	$self->{Entry}->set_text($uri) if $loading;
	$uri= $uri=~m#^https?://# ? 1 : 0 ;
	$self->{BOpen}->set_sensitive($uri);
}

sub loaded
{	my ($self,$data,$type)=@_;
	my $embed=$self->{embed};
	$embed->load_html_string($data,$self->{url}); #FIXME doesn't check type
}


sub go_back	{ $_[0]{embed}->go_back }
sub go_forward	{ $_[0]{embed}->go_forward }
sub stop_load	{ $_[0]{embed}->stop_loading }
sub get_location{ $_[0]{embed}->get_focused_frame->get_uri }
sub Open	{ $_[0]{embed}->open($_[1]); }

sub set_stripped_wiki {}	#FIXME use print version of the wikipedia page instead ?
# $::Options{OPT.'StrippedWiki'}

package GMB::Plugin::WebContext;
require 'simple_http.pm';
our @ISA;
BEGIN {push @ISA,'GMB::Context';}
use base 'Gtk2::VBox';
use constant
{	OPT => 'PLUGIN_WebContext_',
};


our %Widgets=
(	PluginWebLyrics =>
	{	class		=> 'GMB::Plugin::WebContext::Lyrics',
		tabicon		=> 'gmb-lyrics',		# no icon by that name by default
		tabtitle	=> _"Lyrics",
		schange		=> \&Update,
		group		=> 'Play',
		autoadd_type	=> 'context page lyrics html',
		saveoptions	=> 'follow urientry statusbar',
	},
	PluginWikipedia =>
	{	class		=> 'GMB::Plugin::WebContext::Wikipedia',
		tabicon		=> 'plugin-wikipedia',
		tabtitle	=> _"Wikipedia",
		schange		=> \&Update,
		group		=> 'Play',
		autoadd_type	=> 'context page wikipedia html',
		saveoptions	=> 'follow urientry statusbar',
	},
	PluginLastfm =>
	{	class		=> 'GMB::Plugin::WebContext::Lastfm',
		tabtitle	=> "Last.fm",
		schange		=> \&Update,
		group		=> 'Play',
		autoadd_type	=> 'context page lastfm html',
		saveoptions	=> 'follow urientry statusbar',
	},
);

our @default_options= (follow=>1, urientry=>1, statusbar=>0, );
our @contextmenu=
(	{	label=> _"Show/hide URI entry",
		check => sub { $_[0]{self}{urientry} },
		code => sub { my $w=$_[0]{self}{Entry}; if ($_[0]{self}{urientry}^=1) { $w->set_no_show_all(0); $w->show_all; } else { $w->hide; }  },
	},
	{	label=> _"Show/hide status bar",
		check => sub { $_[0]{self}{statusbar} },
		code => sub { my $w=$_[0]{self}{Status}; if ($_[0]{self}{statusbar}^=1) { $w->set_no_show_all(0); $w->show_all; } else { $w->hide; }  },
	},
);

my $active;
::SetDefaultOptions(OPT, StrippedWiki => 1);
UpdateBackend();

sub UpdateBackend
{	my $backend= $::Options{OPT.'Backend'} || '';
	$backend='' if		!$OKMoz && $backend eq 'MozEmbed'
			||	!$OKWebKit && $backend eq 'WebKit';
	unless ($backend)
	{	if ($OKWebKit) {$backend='WebKit'}
		elsif ($OKMoz) {$backend='MozEmbed'}
	}
	$::Options{OPT.'Backend'}=$backend;

	my $was_active=$active;
	Stop() if $active;
	if ($OKMoz && $backend eq 'MozEmbed')
	{	require Gtk2::MozEmbed; Gtk2::MozEmbed->import;
		GMB::Plugin::WebContext::MozEmbed::init();
		@ISA= grep $_ ne 'GMB::Plugin::WebContext::WebKit', @ISA;
		push @ISA, 'GMB::Plugin::WebContext::MozEmbed';
	}
	elsif ($OKWebKit)
	{	require Gtk2::WebKit; Gtk2::WebKit->import;
		@ISA= grep $_ ne 'GMB::Plugin::WebContext::MozEmbed', @ISA;
		push @ISA, 'GMB::Plugin::WebContext::WebKit';
	}
	Start() if $was_active;
}

sub Start
{	$active=1;
	Layout::RegisterWidget($_ => $Widgets{$_}) for keys %Widgets;
	&set_stripped_wiki;
}
sub Stop
{	$active=0;
	Layout::RegisterWidget($_ => undef) for keys %Widgets;
}

sub new
{	my ($class,$opt)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	%$opt=( @default_options, %$opt );
	$self->{$_}=$opt->{$_} for qw/follow group urientry statusbar/;

	my $toolbar=Gtk2::Toolbar->new;
	my $status=$self->{Status}=Gtk2::Statusbar->new;
	$status->{id}=$status->get_context_id('link');
	($self->{embed},my $container)= $self->new_embed;
	$container||=$self->{embed};
	my $entry=$self->{Entry}=Gtk2::Entry->new;
	my $back= $self->{BBack}=Gtk2::ToolButton->new_from_stock('gtk-go-back');
	my $next= $self->{BNext}=Gtk2::ToolButton->new_from_stock('gtk-go-forward');
	my $stop= $self->{BStop}=Gtk2::ToolButton->new_from_stock('gtk-stop');
	my $open= $self->{BOpen}=Gtk2::ToolButton->new_from_stock('gtk-open');
	$open->set_tooltip($::Tooltips,_"Open this page in the web browser",'');
	#$open->set_use_drag_window(1);
	#::set_drag($open,source=>[::DRAG_FILE,sub {$embed->get_location;}]);
	$self->{$_}->set_sensitive(0) for qw/BBack BNext BStop BOpen/;

	my $entryitem=Gtk2::ToolItem->new;
	$entryitem->add($entry);
	$entryitem->set_expand(1);

	# create follow toggle button, function from GMB::Context
	my $follow=$self->new_follow_toolitem;

	$toolbar->insert($_,-1)  for $back,$next,$stop,$follow,$open,$entryitem,$self->addtoolbar;
	$self->pack_start($toolbar,::FALSE,::FALSE,1);
	$self->add( $container );
	$self->pack_end($status,::FALSE,::FALSE,1);
	$entry->set_no_show_all(!$self->{urientry});
	$status->set_no_show_all(!$self->{statusbar});
	$self->signal_connect(map => \&Update);
	$entry->signal_connect(activate => sub { ::find_ancestor($_[0],__PACKAGE__)->load_url($_[0]->get_text); });
	$back->signal_connect(clicked => sub { ::find_ancestor($_[0],__PACKAGE__)->go_back });
	$next->signal_connect(clicked => sub { ::find_ancestor($_[0],__PACKAGE__)->go_forward });
	$stop->signal_connect(clicked => sub { ::find_ancestor($_[0],__PACKAGE__)->stop_load });
	$open->signal_connect(clicked => sub { my $url=::find_ancestor($_[0],__PACKAGE__)->get_location; ::openurl($url) if $url=~m#^https?://# });
	$toolbar->signal_connect('popup-context-menu' => \&popup_toolbar_menu );
	return $self;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	#my $combo=::NewPrefCombo(OPT.'Site',[sort keys %sites],'site : ',sub {$ID=undef;&Changed;});
	my $check=::NewPrefCheckButton(OPT.'StrippedWiki',_"Strip wikipedia pages",\&set_stripped_wiki,_"Remove header, footer and left column from wikipedia pages");
	my $Bopen=Gtk2::Button->new(_"open context window");
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	my ($radio_wk,$radio_moz)=
	 ::NewPrefRadio( OPT.'Backend',
		sub { $check->set_sensitive($::Options{OPT.'Backend'} eq 'MozEmbed'); UpdateBackend(); },
		_"Use WebKit",		'WebKit',
		_"Use MozEmbed",	'MozEmbed');
	my $label_wk= $OKWebKit ? '' : _"Not found";
	my $label_moz= $OKMoz ? '' : $CrashMoz ? _"Found but not working" : _"Not found";
	$::Tooltips->set_tip($radio_wk,$label_wk) if $label_wk;
	$::Tooltips->set_tip($radio_moz,$label_moz) if $label_moz;
	$radio_wk->set_sensitive($OKWebKit);
	$radio_moz->set_sensitive($OKMoz);
	$check->set_sensitive($::Options{OPT.'Backend'} eq 'MozEmbed');
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $radio_wk,$radio_moz,Gtk2::VSeparator->new,$check,$Bopen;
	$vbox->set_sensitive( $OKMoz || $OKWebKit );
	return $vbox;
}

sub load_url
{	my ($self,$url,$post)=@_;
	$url='http://'.$url unless $url=~m#^\w+://#;# || $url=~m#^about:#;
	$self->{url}=$url;
	$self->{post}=$post;
	if ($post)
	{ Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url,post => $post); }
	else {$self->Open($url);}
}

sub link_message
{	my ($self,$msg)=@_;
	$msg='' unless defined $msg;
	my $statusbar=$self->{Status};
	$statusbar->pop( $statusbar->{id} );
	$statusbar->push( $statusbar->{id}, $msg );
}

sub set_stripped_wiki { GMB::Plugin::WebContext::MozEmbed::set_stripped_wiki( $::Options{OPT.'StrippedWiki'} ); } #FIXME

sub popup_toolbar_menu
{	my ($toolbar,$x,$y,$button)=@_;
	my $args= { self=> ::find_ancestor($toolbar,__PACKAGE__), };
	my $menu=::PopupContextMenu(\@contextmenu,$args);
	$menu->show_all;
	$menu->popup(undef,undef,sub {$x,$y},undef,$button,0);
}

sub Update
{	$_[0]->SongChanged( ::GetSelID($_[0]) )  if $_[0]->mapped;
}

#################################################################################


package GMB::Plugin::WebContext::Lyrics;
our @ISA=('GMB::Plugin::WebContext');

use constant
{	OPT => GMB::Plugin::WebContext::OPT,  #FIXME
};

my %sites=
(	lyrc => ['lyrc','http://lyrc.com.ar/en/tema1en.php?artist=%a&songname=%s'],
	#leoslyrics => ['leolyrics','http://api.leoslyrics.com/api_search.php?artist=%a&songtitle=%s'],
	google  => ['google','http://www.google.com/search?q="%a"+"%s"'],
	lyriki  => ['lyriki','http://lyriki.com/index.php?title=%a:%s'],
	lyricwiki => [lyricwiki => 'http://lyrics.wikia.com/%a:%s'],
	lyricsplugin => [lyricsplugin => 'http://www.lyricsplugin.com/winamp03/plugin/?title=%s&artist=%a'],
	lyricscom => [ 'lyrics.com' => 'http://www.lyrics.com/search.php?keyword=%s+%a&what=all' ],
);

$::Options{OPT.'LyricSite'}=undef if !exists $sites{$::Options{OPT.'LyricSite'}};
::SetDefaultOptions(OPT, LyricSite => 'google');

sub addtoolbar
{	#my $self=$_[0];
	my %h= map {$_=>$sites{$_}[0]} keys %sites;
	my $cb=sub
	 {	my $self=::find_ancestor($_[0],__PACKAGE__);
		$self->SongChanged($self->{ID},1);
	 };
	my $combo=::NewPrefCombo( OPT.'LyricSite', \%h, cb => $cb, toolitem => _"Lyrics source");
	return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && $ID==$self->{ID} && !$force;
	$self->{ID}=$ID;
	my ($title,$artist)= map ::url_escapeall($_), Songs::Get($ID,qw/title artist/);
	return if $title eq '';
	my (undef,$url,$post)=@{$sites{$::Options{OPT.'LyricSite'}}};
	for ($url,$post) { next unless defined $_; s/%a/$artist/; s/%s/$title/; }
	::IdleDo('8_mozlyrics'.$self,1000,sub {$self->load_url($url,$post)});
}

package GMB::Plugin::WebContext::Wikipedia;
our @ISA=('GMB::Plugin::WebContext');

use constant
{	OPT => GMB::Plugin::WebContext::OPT,  #FIXME
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
	my $combo=::NewPrefCombo( OPT.'WikiLocale', \%locales, cb => $cb, toolitem => _"Wikipedia Locale");
	return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	$self->{ID}=$ID;
	my $artist=Songs::Get($ID,'first_artist'); #FIXME add a way to choose artist ?
	return if $artist eq '';
	return if defined $self->{Artist} && $artist eq $self->{Artist} && !$force;
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
			else { $self->{url}.='_(band)'; &$cb }
		},url => $url.'_(band)');
}

sub wikifilter	#not used for now
{	my ($self,$data,$type)=@_;
	return unless $data;	#FIXME
	#$data='<style type="text/css">.firstHeading {display: none}</style>'.$data;
	$self->loaded($data,$type);
}

package GMB::Plugin::WebContext::Lastfm;
our @ISA=('GMB::Plugin::WebContext');

sub addtoolbar
{	#my $self=$_[0];
	return ();
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	$self->{ID}=$ID;
	my $artist=Songs::Get($ID,'artist');
	return if !defined $artist || $artist eq '';
	return if defined $self->{Artist} && $artist eq $self->{Artist} && !$force;
	$self->{Artist}=$artist;
	$artist=~s/ /+/g;
	$artist=::url_escapeall($artist);
	my $url='http://www.last.fm/music/'.$artist;
	::IdleDo('8_mozlastfm'.$self,1000,sub {$self->load_url($url)});
}


1

