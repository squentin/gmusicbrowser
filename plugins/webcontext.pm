# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation


=for gmbplugin WebContext
name	Web context
title	Web context plugin
desc	Provides context views using WebKit
desc	wikipedia, lyrics, and custom webpages
req	gir(WebKit2-4.0, gir1.2-webkit2-4.0 webkit2gtk3)
=cut

use strict;
use warnings;
use utf8;

Glib::Object::Introspection->setup(basename => 'WebKit2', version => '4.0', package => 'WebKit2');
push @GMB::Plugin::WebContext::ISA, 'GMB::Plugin::WebContext::WebKit';

WebKit2::WebContext->get_default->get_cookie_manager->set_persistent_storage($::HomeDir.'cookies','sqlite'); #or 'text' ? #add option to disable saving cookies ?


package GMB::Plugin::WebContext::WebKit;

sub new_embed
{	my $embed= WebKit2::WebView->new;
	$embed->signal_connect(mouse_target_changed => \&mouse_target_changed_cb);
	$embed->signal_connect(load_changed => \&net_startstop_cb);
	$embed->signal_connect(button_press_event=> \&button_press_event_cb);
	$embed->signal_connect('notify::title'=> sub
	 {	my $embed=shift;
		my $self= $embed->GET_ancestor('GMB::Plugin::WebContext');
		$self->set_title($embed->get('title')) if $self;
	 });
	my $sw= Gtk3::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($embed);
	return $embed,$sw;
}

sub button_press_event_cb
{	my ($embed,$event)=@_;
	{	last unless $event->get_button==2; # for middle-click
		my $uri= $embed->{mouse_uri};
		last unless $uri;		# need link under mouse
		my $nb= $_[0]->GET_ancestor('Layout::NoteBook');
		last unless $nb; # only works if inside a NB/TabbedLists/Context widget
		$nb->newtab('PluginWebPage',1,{url=>$uri}) if $nb; #open the link in a new tab
		return 1;
	}
	return 0;
}

sub mouse_target_changed_cb
{	my ($embed,$hittest,$modif)=@_;
	my $uri= $hittest->context_is_link ? $hittest->get_link_uri : '';
	$embed->{mouse_uri}=$uri;
	my $self= $embed->GET_ancestor;
	$self->link_message($uri);
}

sub net_startstop_cb
{	my ($embed,$event)=@_;
	my $loading= $event ne 'finished';
	my $self= $embed->GET_ancestor;
	$self->{BStop}->set_sensitive( $loading );
	$self->{BBack}->set_sensitive( $embed->can_go_back );
	$self->{BNext}->set_sensitive( $embed->can_go_forward );
	my $cursor= $loading ? Gtk3::Gdk::Cursor->new('watch') : undef;
	$embed->get_window->set_cursor($cursor) if $embed->get_window;
	my $uri=$embed->get_uri;
	$self->{Entry}->set_text($uri) if $loading;
	$self->set_title($uri) if $loading;
	$uri= $uri=~m#^https?://# ? 1 : 0 ;
	$self->{BOpen}->set_sensitive($uri);
}

sub set_title {} #ignored unless overridden by the class

sub loaded
{	my ($self,$data,%prop)=@_;
	my $embed=$self->{embed};
	$embed->load_html($data,$self->{url}); #FIXME doesn't check type ($prop{type})
}


sub go_back	{ $_[0]{embed}->go_back }
sub go_forward	{ $_[0]{embed}->go_forward }
sub stop_load	{ $_[0]{embed}->stop_loading }
sub get_location{ $_[0]{embed}->get_uri }
#sub get_location{ $_[0]{embed}->get_focused_frame->get_uri }
sub Open	{ $_[0]{embed}->load_uri($_[1]); }


package GMB::Plugin::WebContext;
our @ISA;
BEGIN {push @ISA,'GMB::Context';}
use base 'Gtk3::VBox';
use constant
{	OPT => 'PLUGIN_WebContext_',
};

our %Predefined =
(	google  => { tabtitle => 'google',	baseurl => 'http://www.google.com/search?q="%a"+"%t"', },
	amgartist=>{ tabtitle => 'amg artist',	baseurl => 'http://www.allmusic.com/search/artist/%a', },
	amgalbum=> { tabtitle => 'amg album',	baseurl => 'http://www.allmusic.com/search/album/%l', },
	lastfm	=> { tabtitle => 'last.fm',	baseurl => 'http://www.last.fm/music/%a', },
	discogs	=> { tabtitle => 'discogs',	baseurl => 'http://www.discogs.com/artist/%a', },
	youtube	=> { tabtitle => 'youtube',	baseurl => 'http://www.youtube.com/results?search_query="%a"', },
	pollstar=> { tabtitle => 'pollstar',	baseurl => 'https://www.pollstar.com/global-search?q=%a', },
	songfacts=>{ tabtitle => 'songfacts',	baseurl => 'http://www.songfacts.com/search_fact.php?title=%t', },
    rateyourmusic=>{ tabtitle => 'rateyourmusic',baseurl=> 'http://rateyourmusic.com/search?searchterm=%a&searchtype=a', },
);

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
	PluginWebCustom =>
	{	class		=> 'GMB::Plugin::WebContext::Custom',
		tabtitle	=> _"Untitled",
		schange		=> \&Update,
		group		=> 'Play',
		saveoptions	=> 'follow urientry statusbar',
	},
	PluginWebPage =>
	{	class		=> 'GMB::Plugin::WebContext::Page',
		tabtitle	=> _"Untitled",
		saveoptions	=> 'url title urientry statusbar',
		options		=> 'url title',  #load/save the title because page is only loaded when mapped, so we can ask it its title until tab is selected
	},
);

our @default_options= (follow=>1, urientry=>1, statusbar=>0, );
our @contextmenu=
(	{	label=> _"Show/hide URI entry",
		toggleoption=> 'self/urientry',
		code => sub { my $w=$_[0]{self}{Entry}; if ($_[0]{self}{urientry}) { $w->set_no_show_all(0); $w->show_all; } else { $w->hide; }  },
	},
	{	label=> _"Show/hide status bar",
		toggleoption=> 'self/statusbar',
		code => sub { my $w=$_[0]{self}{Status}; if ($_[0]{self}{statusbar}) { $w->set_no_show_all(0); $w->show_all; } else { $w->hide; }  },
	},
);

my $active;
#::SetDefaultOptions(OPT, StrippedWiki => 1, Custom => { map {$_=>{ %{$Predefined{$_}} } } qw/lastfm amgartist youtube/ }); #FIXME 2TO3
UpdateCustom($_) for sort keys %{ $::Options{OPT.'Custom'} };


sub Start
{	$active=1;
	Layout::RegisterWidget($_ => $Widgets{$_}) for keys %Widgets;
}
sub Stop
{	$active=0;
	Layout::RegisterWidget($_ => undef) for keys %Widgets;
}

sub UpdateCustom
{	my ($id,$hash)=@_;
	if (!defined $id) # new custom page
	{	return unless $hash;
		$id= $hash->{tabtitle}||'' unless defined $id;
		$id=~tr/a-zA-Z0-9//cd;
		$id='custom' if $id eq '';
		::IncSuffix($id) while $Widgets{'PluginWebCustom_'.$id.'_'}; #find a new name
	}
	elsif ($active) { Layout::RegisterWidget('PluginWebCustom_'.$id.'_' => undef); }
	if ($hash)	# edit existing custom page
	{	$::Options{OPT.'Custom'}{$id}{$_}= $hash->{$_} for keys %$hash;
	}
	$hash=$::Options{OPT.'Custom'}{$id};
	return unless $hash;
	my %widget= ( %{ $Widgets{PluginWebCustom} }, autoadd_type => 'context page custom html', %$hash );	#base the widget on the PluginWebCustom widget
	$widget{tabtitle}||= _"Untitled";

	my $name='PluginWebCustom_'.$id.'_';	#'_' is appended because gmb widget names cannot end with numbers
	$Widgets{$name}= \%widget;
	if ($active) { Layout::RegisterWidget($name => $Widgets{$name}); }
	return $id;
}
sub RemoveCustom
{	my $id=shift;
	delete $::Options{OPT.'Custom'}{$id};
	my $name='PluginWebCustom_'.$id.'_';
	delete $Widgets{$name};
	Layout::RegisterWidget($name => undef);
}

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::VBox->new(0,0), $class;
	%$opt=( @default_options, %$opt );
	$self->{$_}=$opt->{$_} for qw/follow group urientry statusbar baseurl/;

	my $toolbar= Gtk3::Toolbar->new;
	$toolbar->set_style( $opt->{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $opt->{ToolbarSize}||'small-toolbar' );
	my $status= $self->{Status}= Gtk3::Statusbar->new;
	$status->{id}=$status->get_context_id('link');
	($self->{embed},my $container)= $self->new_embed;
	$container||=$self->{embed};
	$self->{DefaultFocus}=$self->{embed};
	$self->{embed}->signal_connect(button_press_event=> \&button_press_cb);
	my $entry=$self->{Entry}= Gtk3::Entry->new;
	my $back= $self->{BBack}= Gtk3::ToolButton->new_from_stock('gtk-go-back');
	my $next= $self->{BNext}= Gtk3::ToolButton->new_from_stock('gtk-go-forward');
	my $stop= $self->{BStop}= Gtk3::ToolButton->new_from_stock('gtk-stop');
	my $open= $self->{BOpen}= Gtk3::ToolButton->new_from_stock('gtk-open');
	$open->set_tooltip_text(_"Open this page in the web browser");
	#$open->set_use_drag_window(1);
	#::set_drag($open,source=>[::DRAG_FILE,sub {$embed->get_location;}]);
	$self->{$_}->set_sensitive(0) for qw/BBack BNext BStop BOpen/;

	my $entryitem= Gtk3::ToolItem->new;
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
	$entry->signal_connect(activate => sub { $_[0]->GET_ancestor->load_url($_[0]->get_text); });
	$back->signal_connect(clicked => sub { $_[0]->GET_ancestor->go_back });
	$next->signal_connect(clicked => sub { $_[0]->GET_ancestor->go_forward });
	$stop->signal_connect(clicked => sub { $_[0]->GET_ancestor->stop_load });
	$open->signal_connect(clicked => sub { my $url= $_[0]->GET_ancestor->get_location; ::openurl($url) if $url=~m#^https?://# });
	$toolbar->signal_connect('popup-context-menu' => \&popup_toolbar_menu );
	return $self;
}

sub button_press_cb
{	my ($embed,$event)=@_;
	my $button= $event->button;
	my $self= $embed->GET_ancestor;
	if    ($button==8) { $self->go_back; }
	elsif ($button==9) { $self->go_forward; }
	else { return 0; }
	return 1;
}

sub addtoolbar #default method, overridden by packages that add extra items to the toolbar
{	return ();
}

sub prefbox
{	my $vbox= Gtk3::VBox->new(::FALSE, 2);
	#my $combo=::NewPrefCombo(OPT.'Site',[sort keys %sites],'site : ',sub {$ID=undef;&Changed;});
	my $Bopen= Gtk3::Button->new(_"open context window");
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $Bopen;
	$vbox->pack_start( GMB::Plugin::WebContext::Custom::Edition->new, ::TRUE,::TRUE,8 );
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

sub popup_toolbar_menu
{	my ($toolbar,$x,$y,$button)=@_;
	my $args= { self=> $toolbar->GET_ancestor, };
	my $menu=::BuildMenu(\@contextmenu,$args);
	$menu->show_all;
	$menu->popup(undef,undef,sub {$x,$y},undef,$button,0);
}

sub Update
{	$_[0]->SongChanged( ::GetSelID($_[0]) )  if $_[0]->get_mapped;
}
#################################################################################

package GMB::Plugin::WebContext::Page;
our @ISA=('GMB::Plugin::WebContext');

#only called once, when mapped
sub SongChanged { $_[0]->load_url($_[0]{url}) if $_[0]{url}; }

sub DynamicTitle	#called by Layout::NoteBook when tab is created
{	my ($self,$default)=@_;
	my $title=$self->{title};
	$title=$default unless length $title;
	my $label= Gtk3::Label->new($title);
	$label->set_ellipsize('end');
	$label->set(hexpand=>1);
	$label->set_max_width_chars(20);
	$self->{titlelabel}=$label;
	return $label;
}
sub set_title
{	my ($self,$title)=@_;
	($title)= $self->{url}=~m#^https?://(?:www\.)?([\w.]+)# unless length $title;
	$self->{title}=$title;
	$self->{titlelabel}->set_text($title);
}

package GMB::Plugin::WebContext::Lyrics;
our @ISA=('GMB::Plugin::WebContext');

use constant
{	OPT => GMB::Plugin::WebContext::OPT,  #FIXME
};

my %sites=
(	google  => ['google','http://www.google.com/search?q="%a"+"%s"'],
	lyriki  => ['lyriki','http://lyriki.com/index.php?title=%a:%s'],
	lyricwiki => [lyricwiki => 'http://lyrics.wikia.com/%a:%s'],
	#lyricsplugin => [lyricsplugin => 'http://www.lyricsplugin.com/winamp03/plugin/?title=%s&artist=%a'],
	lyricscom => [ 'lyrics.com' => 'http://www.lyrics.com/serp.php?st=%s&stype=1' ],
);

$::Options{OPT.'LyricSite'}=undef if $::Options{OPT.'LyricSite'} && !$sites{$::Options{OPT.'LyricSite'}};
::SetDefaultOptions(OPT, LyricSite => 'google');

sub addtoolbar
{	#my $self=$_[0];
	my %h= map {$_=>$sites{$_}[0]} keys %sites;
	my $cb=sub
	 {	my $self= $_[0]->GET_ancestor;
		$self->SongChanged($self->{ID},1);
	 };
	my $combo=::NewPrefCombo( OPT.'LyricSite', \%h, cb => $cb, toolitem => _"Lyrics source");
	return $combo;
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && !$force && ($ID==$self->{ID} || !$self->{follow});
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
	 {	my $self= $_[0]->GET_ancestor;
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
	return if defined $self->{Artist} && !$force && ($artist eq $self->{Artist} || !$self->{follow});
	$self->{Artist}=$artist;
	$artist=::url_escapeall($artist);
	my $url='http://'.$::Options{OPT.'WikiLocale'}.'.m.wikipedia.org/wiki/'.$artist;
	#my $url='http://'.$::Options{OPT.'WikiLocale'}.'.wikipedia.org/w/index.php?title='.$artist.'&action=render';
	::IdleDo('8_mozpedia'.$self,1000,sub {$self->load_url($url)});
	#::IdleDo('8_mozpedia'.$self,1000,sub {$self->wikiload});
}

sub wikiload	#not used for now
{	my $self=$_[0];
	my $url=::url_escapeall($self->{Artist});
	$url='http://'.$::Options{OPT.'WikiLocale'}.'.m.wikipedia.org/wiki/'.$url;
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
{	my ($self,$data,%prop)=@_;
	return unless $data;	#FIXME
	#$data='<style type="text/css">.firstHeading {display: none}</style>'.$data;
	$self->loaded($data,%prop);
}

package GMB::Plugin::WebContext::Custom;
our @ISA=('GMB::Plugin::WebContext');

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	$self->{ID}=$ID;
	my $url= $self->{baseurl};
	unless ($url) { warn "no baseurl defined for custom webcontext $self->{name}\n"; return }
	$url= ::ReplaceFields($ID,$url, \&::url_escapeall);
	return if $self->{url} && !$force && ($url eq  $self->{url} || !$self->{follow});
	warn "loading $url\n";
	::IdleDo('8_mozcustom'.$self,1000,sub {$self->load_url($url)});
}


package GMB::Plugin::WebContext::Custom::Edition;
use base 'Gtk3::Box';

my $CustomPages= $::Options{GMB::Plugin::WebContext::OPT.'Custom'};

sub new
{	my $class=shift;
	my $self= bless Gtk3::VBox->new, $class;
	my $store= Gtk3::ListStore->new('Glib::String','Glib::String');
	my $treeview= Gtk3::TreeView->new($store);
	my $renderer= Gtk3::CellRendererText->new;
	$renderer->set(editable => 1);
	$renderer->signal_connect_swapped(edited => \&rename_cb,$store);
	$treeview->append_column( Gtk3::TreeViewColumn->new_with_attributes( '', $renderer, text => 1 ));
	$treeview->set_headers_visible(::FALSE);
	$treeview->get_selection->signal_connect(changed => \&selchanged_cb);
	my $sw= Gtk3::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($treeview);
	my $hbox= Gtk3::HBox->new;
	my $editbox= Gtk3::VBox->new;
	$self->{editbox}=$editbox;
	$self->{store}=$store;
	$self->{treeview}=$treeview;
	$hbox->pack_start($sw,::FALSE,::FALSE,2);
	$hbox->add($editbox);
	my $label= Gtk3::Label->new;
	$label->set_markup_with_format('<b>%s</b>',_"Custom context pages :");
	$label->set_alignment(0,.5);
	$self->pack_start($label,::FALSE,::FALSE,2);
	$self->add($hbox);

	#buttons
	my $new=   ::NewIconButton('gtk-new',	_"New");
	my $save=  ::NewIconButton('gtk-save',	_"Save");
	my $remove=::NewIconButton('gtk-remove',_"Remove");
	my $preset=::NewIconButton('gtk-add',	_"Pre-set");
	$preset->get_child->add(Gtk3::Arrow->new('down','none'));
	$new	->signal_connect( clicked=> sub { my $self= $_[0]->GET_ancestor; $self->fill_editbox; });
	$save	->signal_connect( clicked=> \&save_cb);
	$remove	->signal_connect( clicked=> \&remove_cb);
	$preset ->signal_connect(button_press_event=>\&preset_menu_cb);
	my $bbox=Gtk3::HButtonBox->new;
	$bbox->set_layout('start');
	$bbox->add($_) for $remove, $new, $preset, $save;
	$self->pack_end($bbox,::FALSE,::FALSE,0);
	$self->{button_save}=$save;
	$self->{button_remove}=$remove;

	my $sg= Gtk3::SizeGroup->new('horizontal');
	$sg->add_widget($_) for $sw, $remove, $new, $preset, $save;

	fill_list($self->{store});
	$self->fill_editbox;
	return $self;
}
sub fill_list
{	my $store=shift;
	$store->clear;
	for my $id ( ::sorted_keys($CustomPages,'tabtitle') )
	{	$store->set($store->append, 0,$id, 1,$CustomPages->{$id}{tabtitle});
	}
}
sub fill_editbox		#if $id => fill entries with existing properties, if $hash => fill entries with content of hash, if neither => empty entries
{	my ($self,$id,$hash)=@_;
	my $editbox= $self->{editbox};
	$editbox->remove($_) for $editbox->get_children;
	$self->{button_save}  ->set_sensitive(defined $hash);
	$self->{button_remove}->set_sensitive(defined $id);
	$editbox->{entry_title}= my $entry_title=Gtk3::Entry->new;
	$editbox->{entry_url}=   my $entry_url=  Gtk3::Entry->new;
	$editbox->{id}=$id;
	my $preview=Label::Preview->new
	(	entry	=> $entry_url,	format => ::MarkupFormat('<small>%s</small>', _"example : %s"),
		event	=> 'CurSong',
		preview	=> sub { my $url=shift; defined $::SongID && $url ? ::ReplaceFields($::SongID,$url, \&::url_escapeall) : undef  },
		wrap=>1,
	);
	$preview->set_selectable(1);
	$hash= $CustomPages->{$id} if defined $id;
	if ($hash)
	{	$hash ||= $CustomPages->{$id};
		$entry_title->set_text($hash->{tabtitle});
		$entry_url  ->set_text($hash->{baseurl});
	}
	my $sg= Gtk3::SizeGroup->new('horizontal');
	my $label_title= Gtk3::Label->new(_"Title");
	my $label_url=   Gtk3::Label->new(_"url");
	$sg->add_widget($_) for $label_title, $label_url;
	my $box= ::Vpack( [$label_title,'_',$entry_title], [$label_url,'_',$entry_url], $preview );


	$_->signal_connect(changed=> \&entry_changed_cb) for $entry_title, $entry_url;
	$entry_title->signal_connect(changed=> \&update_selection);
	$editbox->pack_start($box,::FALSE,::FALSE,2);
	$editbox->show_all;
}

sub entry_changed_cb
{	my $self= $_[0]->GET_ancestor;
	my $editbox= $self->{editbox};
	$self->{button_save}->set_sensitive( $editbox->{entry_title}->get_text ne '' && $editbox->{entry_url}->get_text ne '' );
}

sub update_selection
{	my $self= $_[0]->GET_ancestor;
	my $editbox= $self->{editbox};
	my $title= $editbox->{entry_title}->get_text;
	my $newid;
	for my $id (keys %$CustomPages)
	{	next unless $CustomPages->{$id}{tabtitle} eq $title;
		$newid=$id;
		last;
	}
	$editbox->{id}=$newid;
	my $treesel=$self->{treeview}->get_selection;
	$self->{button_remove}->set_sensitive(defined $newid);
	$editbox->{busy}=1;
	$treesel->unselect_all;
	if (defined $newid)	#select current id
	{	my $store=$self->{store};
		my $iter=$store->get_iter_first;
		while ($iter)
		{	if ( $store->get($iter,0) eq $newid )
			{	$treesel->select_iter($iter);
				last;
			}
			$iter=$store->iter_next($iter);
		}
	}
	$editbox->{busy}=0;
}

sub selchanged_cb
{	my $treesel=shift;
	my $treeview=$treesel->get_tree_view;
	my $self= $treeview->GET_ancestor;
	return if $self->{editbox}{busy};
	my $iter=$treesel->get_selected;
	my $id;
	$id=$treeview->get_model->get($iter,0) if $iter;
	$self->fill_editbox($id);
}

sub rename_cb
{	my ($store, $path_string, $newvalue) = @_;
	my $iter=$store->get_iter_from_string($path_string);
	my $id=$store->get($iter,0);
	return if $newvalue eq '';
	return if $CustomPages->{$id}{tabtitle} eq $newvalue;
	GMB::Plugin::WebContext::UpdateCustom($id=> {tabtitle=>$newvalue});
	fill_list($store);
}
sub remove_cb
{	my $self= $_[0]->GET_ancestor;
	my $editbox= $self->{editbox};
	my $id=$editbox->{id};
	return unless defined $id;
	GMB::Plugin::WebContext::RemoveCustom($id);
	fill_list($self->{store});
}
sub save_cb
{	my $button=shift;
	$button->set_sensitive(0);
	my $self= $button->GET_ancestor;
	my $editbox= $self->{editbox};
	my $hash= { tabtitle=> $editbox->{entry_title}->get_text, baseurl=> $editbox->{entry_url}->get_text, };
	my $id=$editbox->{id};
	GMB::Plugin::WebContext::UpdateCustom($id => $hash); # if $id is undef, create a new page, else edit existing one
	$editbox->{busy}=1;
	fill_list($self->{store});
	$editbox->{busy}=0;
	$self->update_selection;
}
sub preset_menu_cb
{	my ($button,$event)=@_;
	my $self= $button->GET_ancestor;
	my $menu= Gtk3::Menu->new;
	my $predef= \%GMB::Plugin::WebContext::Predefined;
	my $menu_cb= sub { my $preid=$_[1]; $self->fill_editbox(undef,$predef->{$preid}); $self->update_selection; };
	for my $preid ( ::sorted_keys($predef,'tabtitle') )
	{	my $item= Gtk3::MenuItem->new( $predef->{$preid}{tabtitle} );
		$item->signal_connect(activate => $menu_cb,$preid);
		$menu->append($item);
	}
	::PopupMenu($menu);
}


1

