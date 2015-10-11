# Copyright (C) 2010-2011 Quentin Sculo <squentin@free.fr> and Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin ARTISTINFO
name	Artistinfo
title	Artistinfo plugin
version	0.5
author  Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
author  Pasi Lallinaho <pasi@shimmerproject.org>
desc	This plugin retrieves artist-relevant information (biography, upcoming events, similar artists) from last.fm.
url	http://gmusicbrowser.org/dokuwiki/doku.php?id=plugins:artistinfo
=cut

package GMB::Plugin::ARTISTINFO;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use base 'Gtk2::Box';
use constant
{	OPT	=> 'PLUGIN_ARTISTINFO_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
	SITEURL => 0,
};

my %sites =
(
	biography => ['http://ws.audioscrobbler.com/2.0/?method=artist.getinfo&artist=%a&api_key=7aa688c2466dc17263847da16f297835&autocorrect=1',_"Biography",_"Show artist's biography"],
	events => ['http://ws.audioscrobbler.com/2.0/?method=artist.getevents&artist=%a&api_key=7aa688c2466dc17263847da16f297835&autocorrect=1',_"Events",_"Show artist's upcoming events"],
	similar => ['http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=%a&api_key=7aa688c2466dc17263847da16f297835&autocorrect=1&limit=%l',_"Similar",_"Show similar artists"]);

my @External=
(	['lastfm',	"http://www.last.fm/music/%a",								_"Show Artist page on last.fm"],
	['wikipedia',	"http://en.wikipedia.org/wiki/%a",							_"Show Artist page on wikipedia"],
	['youtube',	"http://www.youtube.com/results?search_type=&aq=1&search_query=%a",			_"Search for Artist on youtube"],
	['amazon',	"http://www.amazon.com/s/ref=nb_sb_noss?url=search-alias=aps&field-keywords=%a",	_"Search amazon.com for Artist"],
	['google',	"http://www.google.com/search?q=%a",							_"Search google for Artist" ],
	['allmusic',	"http://www.allmusic.com/search/artist/%a",						_"Search allmusic for Artist" ],
	['pitchfork',	"http://pitchfork.com/search/?search_type=standard&query=%a",				_"Search pitchfork for Artist" ],
	['discogs',	"http://www.discogs.com/artist/%a",							_"Search discogs for Artist" ],
);

my %menuitem=
(	label => _"Search on the web",					#label of the menu item
	submenu => sub { CreateSearchMenu( Songs::Gid_to_Get('artist',$_[0]{gid}) );  },			#when menu item selected
	test => sub {$_[0]{mainfield} eq 'artist'},	#the menu item is displayed if returns true
);
my $nowplayingaID;
my $queuewaiting;
my %queuemode=
(	order=>10, icon=>'gtk-refresh',	short=> _"similar-artists",		long=> _"Auto-fill queue with similar artists (from last.fm)",	changed=>\&QAutofillSimilarArtists,	keep=>1,save=>1,autofill=>1,
);

=dop
my @similarity=
(	['super',	'0.9',	'#ff0101'],
	['very high',	'0.7',	'#e9c102'],
	['high',	'0.5',	'#05bd4c'],
	['medium',	'0.3',	'#453e45'],
	['lower',	'0.1',	'#9a9a9a'],
);

=cut
# lastfm api key 7aa688c2466dc17263847da16f297835
# "secret" string: 18cdd008e76705eb5f942892d49a71e2

::SetDefaultOptions(OPT,PathFile	=> "~/.config/gmusicbrowser/bio/%a",
			ArtistPicSize	=> 70,
			ArtistPicShow	=> 1,
			SimilarLimit	=> 15,
			SimilarRating	=> 20,
			SimilarLocal	=> 0,
			SimilarExcludeSeed => 0,
			Eventformat	=> '%title at %name<br>%startDate<br>%city (%country)<br><br>',
			Eventformat_history => ['%title<br>%startDate<br><br>','%title on %startDate<br><br>'],
);

my $artistinfowidget=
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-artistinfo',		# no icon by that name by default (yet)
	tabtitle	=> _"Artistinfo",
	saveoptions	=> 'site',
	schange		=> sub { $_[0]->SongChanged; },
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};

sub Start {
	Layout::RegisterWidget(PluginArtistinfo => $artistinfowidget);
	push @::cMenuAA,\%menuitem;
	$::QActions{'autofill-similar-artists'} = \%queuemode; ::Update_QueueActionList();
}
sub Stop {
	Layout::RegisterWidget(PluginArtistinfo => undef);
	@::cMenuAA=  grep $_!=\%menuitem, @::SongCMenu;
	delete $::QActions{'autofill-similar-artists'}; ::Update_QueueActionList();
	$queuewaiting->abort if $queuewaiting; $queuewaiting=undef;
}

sub new
{	my ($class,$options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	$self->{$_}=$options->{$_} for qw/site/;
	delete $self->{site} if $self->{site} && !$sites{$self->{site}}[SITEURL]; #reset selected site if no longer defined
	$self->{site} ||= 'biography';	# biography is the default site
	my $fontsize=$self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size / Gtk2::Pango->scale;
	$self->{artist_esc} = "";
	my $statbox=Gtk2::VBox->new(0,0);
	my $artistpic=Gtk2::HBox->new(0,0);
	for my $name (qw/Ltitle Lstats/)
	{	my $l=Gtk2::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1);$l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{artistrating} = Gtk2::Image->new;
	$statbox->pack_start($self->{artistrating},0,0,0);
	my $stateventbox = Gtk2::EventBox->new;
	$stateventbox->add($statbox);
	$stateventbox->{group}= $options->{group};
	$stateventbox->signal_connect(button_press_event => sub {my ($stateventbox, $event) = @_; return 0 unless $event->button == 3; my $ID=::GetSelID($stateventbox); ::ArtistContextMenu( Songs::Get_gid($ID,'artists'),{ ID=>$ID, self=> $stateventbox, mode => 'S'}) if defined $ID; return 1; } ); # FIXME: do a proper cm

	my $artistbox = Gtk2::HBox->new(0,0);
	$artistbox->pack_start($artistpic,0,1,0);
	$artistbox->pack_start($stateventbox,1,1,0);

	my $group= $options->{group};
	my $artistpic_create= sub
	{	my $box=shift;
		$box->remove($_) for $box->get_children;
		return unless $::Options{OPT.'ArtistPicShow'};
		my $child = Layout::NewWidget("ArtistPic",{forceratio=>1,minsize=>$::Options{OPT.'ArtistPicSize'},click1=>\&apiczoom,xalign=>0,group=>$group,tip=>_"Click to show fullsize image"});
		$child->show_all;
		$box->add($child);
	};
	::Watch($artistpic, plugin_artistinfo_option_pic=> $artistpic_create);
	$artistpic_create->($artistpic);

	my $textview=Gtk2::TextView->new;
	$self->signal_connect(map => \&SongChanged);
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_pixels_above_lines(2);
	$textview->set_editable(0);
	$textview->set_left_margin(5);
	$textview->set_has_tooltip(1);
	$textview->signal_connect(button_release_event	=> \&button_release_cb);
	$textview->signal_connect(motion_notify_event 	=> \&update_cursor_cb);
	$textview->signal_connect(visibility_notify_event=>\&update_cursor_cb);
	$textview->signal_connect(query_tooltip => \&update_cursor_cb);

	my $store=Gtk2::ListStore->new('Glib::String','Glib::Double','Glib::String','Glib::UInt','Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	my $tc_artist=Gtk2::TreeViewColumn->new_with_attributes( _"Artist",Gtk2::CellRendererText->new,markup=>0);
	$tc_artist->set_sort_column_id(0);
	$tc_artist->set_expand(1);
	$tc_artist->set_resizable(1);
	$treeview->append_column($tc_artist);
	$treeview->set_has_tooltip(1);
	$treeview->set_tooltip_text(_"Middle-click on local artists to set a filter on them, right-click non-local artists to search for them on the web.");
	my $renderer=Gtk2::CellRendererText->new;
	my $tc_similar=Gtk2::TreeViewColumn->new_with_attributes( "%",$renderer,text => 1);
	$tc_similar->set_cell_data_func($renderer, sub { my ($column, $cell, $model, $iter, $func_data) = @_; my $rating = $model->get($iter, 1); $cell->set( text => sprintf '%.1f', $rating ); }, undef); # limit similarity rating to one decimal
	$tc_similar->set_sort_column_id(1);
	$tc_similar->set_alignment(1.0);
	$tc_similar->set_min_width(10);
	$treeview->append_column($tc_similar);
	$treeview->set_rules_hint(1);
	$treeview->signal_connect(button_press_event => \&tv_contextmenu);
	$treeview->{store}=$store;

	my $toolbar=Gtk2::Toolbar->new;
	$toolbar->set_style( $options->{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $options->{ToolbarSize}||'small-toolbar' );
	#$toolbar->set_show_arrow(1);
	my $radiogroup; my $menugroup;
	foreach my $key (sort keys %sites)
	{	my $item = $sites{$key}[1];
		$item = Gtk2::RadioButton->new($radiogroup,$item);
		$item->{key} = $key;
		$item -> set_mode(0); # display as togglebutton
		$item -> set_relief("none");
		$item -> set_tooltip_text($sites{$key}[2]);
		$item->set_active( $key eq $self->{site} );
		$item->signal_connect(toggled => sub { my $self=::find_ancestor($_[0],__PACKAGE__); toggled_cb($self,$item,$textview); } );
		$radiogroup = $item -> get_group;
		my $toolitem=Gtk2::ToolItem->new;
		$toolitem->add( $item );
		$toolitem->set_expand(1);
		$toolbar->insert($toolitem,-1);

# trying to make the radiobuttons overflowable, but no shared groups for radiobuttons and radiomenuitems (group doesn't seem to work for radiomenuitem at all)
#		my $menuitem=Gtk2::RadioMenuItem->new($menugroup,$sites{$key}[1]);
#		$menuitem->set_active( $key eq $self->{site} );
		#$menuitem->set_group($menugroup);
#		$menuitem->set_draw_as_radio(1);
#		$menuitem->{key} = $key;
#		if ($menuitem->get_active) { warn $menuitem->{key}; }
#		$menuitem->signal_connect('toggled' => sub { &toggled_cb($self,$menuitem,$textview); } );
#		$toolitem->set_proxy_menu_item($key,$menuitem);
	}
	for my $button
	(	[refresh => 'gtk-refresh', sub { my $self=::find_ancestor($_[0],__PACKAGE__); SongChanged($self,'force'); },_"Refresh", _"Refresh"],
		[save => 'gtk-save',	\&Save_text,	_"Save",	_"Save artist biography",$::Options{OPT.'AutoSave'}],
	)
	{	my ($key,$stock,$cb,$label,$tip)=@$button;
		my $item=Gtk2::ToolButton->new_from_stock($stock);
		$item->signal_connect(clicked => $cb);
		$item->set_tooltip_text($tip) if $tip;
		my $menuitem = Gtk2::ImageMenuItem->new ($label);
		$menuitem->set_image( Gtk2::Image->new_from_stock($stock,'menu') );
		$item->set_proxy_menu_item($key,$menuitem);
		$toolbar->insert($item,-1);
		if ($key eq 'save')
		{	$item->show_all;
			$item->set_no_show_all(1);
			my $update= sub { $_[0]->set_visible(!$::Options{OPT.'AutoSave'}); };
			::Watch($item, plugin_artistinfo_option_save=> $update);
			$update->($item);
		}
	}
	my $artistinfobox = Gtk2::VBox->new(0,0);
	$artistinfobox->pack_start($artistbox,1,1,0);
	$artistinfobox->pack_start($toolbar,0,0,0);
	#$statbox->pack_start($toolbar,0,0,0);
	$self->{buffer}=$textview->get_buffer;
	$self->{store}=$store;

	my $infobox = Gtk2::HBox->new;
	$infobox->set_spacing(0);
	my $sw1=Gtk2::ScrolledWindow->new;
	my $sw2=Gtk2::ScrolledWindow->new;
	$sw1->add($textview);
	$sw2->add($treeview);
	for ($sw1,$sw2) {
		$_->set_shadow_type('none');
		$_->set_policy('automatic','automatic');
		$infobox->pack_start($_,1,1,0);
	}
	if ($self->{site} ne "similar") { $treeview->show; $sw2->set_no_show_all(1); } # only show the correct widget at startup
	else { $textview->show; $sw1->set_no_show_all(1); }
	$self->{sw1} = $sw1;
	$self->{sw2} = $sw2;

	$self->pack_start($artistinfobox,0,0,0);
	$self->pack_start($infobox,1,1,0);

	$self->signal_connect(destroy => \&destroy_event_cb);
	return $self;
}

sub toggled_cb
{	my ($self, $togglebutton,$textview) = @_;
	if ($togglebutton -> get_active) {
		$self->{site} = $togglebutton->{key};
		$self->SongChanged;
		$textview->set_tooltip_text($self->{site}) if $self->{site} ne "events";
	}
}

sub destroy_event_cb
{	my $self=shift;
	$self->cancel;
}

sub cancel
{	my $self=shift;
	delete $::ToDo{'8_artistinfo'.$self};
	$self->{waiting}->abort if $self->{waiting};
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(0,2);
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Load/Save Artist Info in :", width=>50);
	my $preview= Label::Preview->new(preview => \&filename_preview, event => 'CurSong Option', noescape=>1,wrap=>1);
	my $autosave = ::NewPrefCheckButton(OPT.'AutoSave'=>_"Auto-save positive finds", tip=>_"only works when the artist-info tab is displayed",
		cb=>sub { ::HasChanged('plugin_artistinfo_option_save'); });
	my $picsize=::NewPrefSpinButton(OPT.'ArtistPicSize',50,500, step=>5, page=>10, text =>_("Artist picture size : %d"), cb=>sub { ::HasChanged('plugin_artistinfo_option_pic'); });
	my $picshow=::NewPrefCheckButton(OPT.'ArtistPicShow' => _"Show artist picture", widget => ::Vpack($picsize), cb=>sub { ::HasChanged('plugin_artistinfo_option_pic'); } );
	my $eventformat=::NewPrefEntry(OPT.'Eventformat' => _"Enter custom event string :", expand=>1, tip => _"Use tags from last.fm's XML event pages with a leading % (e.g. %headliner), furthermore linebreaks '<br>' and any text you'd like to have in between. E.g. '%title taking place at %startDate<br>in %city, %country<br><br>'", history=>OPT.'Eventformat_history');
	my $eventformat_reset=Gtk2::Button->new(_"reset format");
	$eventformat_reset->{format_combo}=$eventformat;
	$eventformat_reset->signal_connect(clicked => sub {
		my $self = shift;
		my $prefentry = $self->{format_combo};
		my ($combo) = grep $_->isa("Gtk2::ComboBoxEntry"), $prefentry->get_children;
		$combo->child->set_text('%title at %name<br>%startDate<br>%city (%country)<br><br>');
		$::Options{OPT.'Eventformat'} = '%title at %name<br>%startDate<br>%city (%country)<br><br>';
	});
	my $similar_limit=::NewPrefSpinButton(OPT.'SimilarLimit',0,500, step=>1, page=>10, text1=>_"Limit similar artists to the first : ", tip=>_"0 means 'show all'");
	my $similar_rating=::NewPrefSpinButton(OPT.'SimilarRating',0,100, step=>1, text1=>_"Limit similar artists to a rate of similarity : ", tip=>_"last.fm's similarity categories:\n>90 super\n>70 very high\n>50 high\n>30 medium\n>10 lower");
	my $similar_local=::NewPrefCheckButton(OPT.'SimilarLocal' => _"Only show similar artists from local library", tip=>_"applied on reload");
	my $similar_exclude_seed=::NewPrefCheckButton(OPT.'SimilarExcludeSeed' => _"Exclude 'seed'-artist from queue", tip=>_"The artists similar to the 'seed'-artist will be used to populate the queue, but you can decide to exclude the 'seed'-artist him/herself.");
	my $lastfm=::NewIconButton('plugin-artistinfo-lastfm',undef,sub { ::main::openurl("http://www.last.fm/music/"); },'none',_"Open last.fm website in your browser");
	my $titlebox=Gtk2::HBox->new(0,0);
	$titlebox->pack_start($picshow,1,1,0);
	$titlebox->pack_start($lastfm,0,0,5);
	my $frame_bio=Gtk2::Frame->new(_"Biography");
	$frame_bio->add(::Vpack($entry,$preview,$autosave));
	my $frame_events=Gtk2::Frame->new(_"Events");
	$frame_events->add(::Hpack('_',$eventformat,$eventformat_reset));
	my $frame_similar=Gtk2::Frame->new(_"Similar Artists");
	$frame_similar->add(::Vpack($similar_limit,$similar_rating,$similar_local,$similar_exclude_seed));
	$vbox->pack_start($_,::FALSE,::FALSE,5) for $titlebox,$frame_bio,$frame_events,$frame_similar;
	return $vbox;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
	$t= ::filename_to_utf8displayname($t) if $t;
	$t= $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
	return '<small>'.$t.'</small>';
}

sub set_buffer
{	my ($self,$text) = @_;
	$self->{buffer}->set_text("");
	my $iter=$self->{buffer}->get_start_iter;
	my $fontsize=$self->{fontsize};
	my $tag_noresults=$self->{buffer}->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	$self->{buffer}->insert_with_tags($iter,"\n$text",$tag_noresults);
	$self->{buffer}->set_modified(0);
}

sub tv_contextmenu {
	my ($treeview, $event) = @_;
	return 0 unless $treeview;
	my ($path, $column) = $treeview->get_cursor;
	return unless defined $path;
	my $store=$treeview->{store};
	my $iter=$store->get_iter($path);
	my $artist=$store->get( $store->get_iter($path),4);
	my $url=$store->get( $store->get_iter($path),2);
	my $aID=$store->get( $store->get_iter($path),3);
	if ($event->button == 2) { if ($url eq "local") {
		my $filter = Songs::MakeFilterFromGID('artists',$aID);
		::SetFilter($treeview,$filter,1);
	}
	return 1;
	}
	elsif ($event->button == 3) {
	if ($url eq "local") {
		::PopupAAContextMenu({gid=>$aID,self=>$treeview,field=>'artists',mode=>'S'});
		return 0;
	}
	else {
		my $menu = CreateSearchMenu($artist,$url);
		my $title=Gtk2::MenuItem->new(_"Search for artist on:");
		$menu->prepend($title);
		$menu->show_all;
		$menu->popup (undef, undef, undef, undef, $event->button, $event->time);
	}
	return 1;
	}

}

sub CreateSearchMenu {
	my($artist,$lastfm_url)=@_;
	$artist=::url_escapeall($artist);
	my $menu=Gtk2::Menu->new;
	for my $item (@External) {
			my ($key,$url,$text)=@$item;
			if ($key eq "lastfm" && $lastfm_url) { $url='http://'.$lastfm_url; }
			else { $url=~s/%a/$artist/; }
			my $menuitem = Gtk2::ImageMenuItem->new ($key);
			$menuitem->set_image( Gtk2::Image->new_from_stock('plugin-artistinfo-'.$key,'menu') );
			$menuitem->signal_connect(activate => sub { ::main::openurl($url) if $url; return 0; });
			$menu->append($menuitem);
		}
	return $menu;
}

sub apiczoom {
	my ($self, $event) = @_;
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'artist');
	my $picsize=250;
	my $img= AAPicture::newimg(artist=>$aID,$picsize);
	return 0 unless $img;

	my $menu=Gtk2::Menu->new;
	$menu->modify_bg('normal',Gtk2::Gdk::Color->parse('black')); # black bg for the artistpic-popup
	my $apic = Gtk2::MenuItem->new;
	$apic->modify_bg('selected',Gtk2::Gdk::Color->parse('black'));
	$apic->add($img);

	my $artist = Songs::Gid_to_Get("artist",$aID);
	my $item=Gtk2::MenuItem->new;
	my $label=Gtk2::Label->new;	# use a label instead of a normal menu-item for formatted text
	$item->modify_bg('selected',Gtk2::Gdk::Color->parse('black'));
	$label->modify_fg($_,Gtk2::Gdk::Color->parse('white')) for qw/normal prelight/;
	$label->set_line_wrap(1);
	$label->set_justify('center');
	$label->set_ellipsize('end');
	$label->set_markup( "<big><b>$artist</b></big>" );
	$item->add($label);

	$menu->append($apic);
	$menu->append($item);
	$menu->show_all;
	$menu->popup (undef, undef, undef, undef, $event->button, $event->time);
	return 1;
}

sub update_cursor_cb
{	my $textview=$_[0];
	my (undef,$wx,$wy,undef)=$textview->window->get_pointer;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter=$textview->get_iter_at_location($x,$y);
	my $cursor='xterm';
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		$cursor='hand2';
		$textview->set_tooltip_text($tag->{url});
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor}=$cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

sub button_release_cb
{	my ($textview,$event) = @_;
	my $self=::find_ancestor($textview,__PACKAGE__);
	return ::FALSE unless $event->button == 1;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $url=$self->url_at_coords($x,$y,$textview);
	::main::openurl($url) if $url;
	return ::FALSE;
}

sub url_at_coords
{	my ($self,$x,$y,$textview)=@_;
	my $iter=$textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		if ($tag->{url}=~m/^#(\d+)?/) { $self->scrollto($1) if defined $1; last }
		my $url= $tag->{url};
		return $url;
	}
}

sub SongChanged
{	my ($widget,$force) = @_;
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $ID = ::GetSelID($self);
	return unless defined $ID;
	$self -> ArtistChanged( Songs::Get_gid($ID,'artist'),Songs::Get_gid($ID,'album'),$force);
}

sub ArtistChanged
{	my ($self,$aID,$albumID,$force)=@_;
	return unless $self->mapped;
	return unless defined $aID;
	my $rating = AA::Get("rating:average",'artist',$aID);
	$self->{artistratingvalue}= int($rating+0.5);
	$self->{artistratingrange}=AA::Get("rating:range",'artist',$aID);
	$self->{artistplaycount}=AA::Get("playcount:sum",'artist',$aID);
	$self->{albumplaycount}=AA::Get("playcount:sum",'album',$albumID);
	my $tip = join "\n",	_("Average rating:")	.' '.$self->{artistratingvalue},
				_("Rating range:")	.' '.$self->{artistratingrange},
				_("Artist playcount:")	.' '.$self->{artistplaycount},
				_("Album playcount:")	.' '.$self->{albumplaycount};

	$self->{artistrating}->set_from_pixbuf(Songs::Stars($self->{artistratingvalue},'rating'));
	$self->{Ltitle}->set_markup( AA::ReplaceFields($aID,"<big><b>%a</b></big>","artist",1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($aID,'%X « %s'."\n<small>%y</small>","artist",1) );
	for my $name (qw/Ltitle Lstats artistrating/) { $self->{$name}->set_tooltip_text($tip); }

	my $url = GetUrl($sites{$self->{site}}[SITEURL],$aID);
	return unless $url;
	if (!$self->{url} or ($url ne $self->{url}) or $force) {
		$self->cancel;
		$self->{url} = $url;
		if ($self->{site} eq "biography") { # check for local biography file before loading the page
			unless ($force) {
			my $file=::pathfilefromformat( ::GetSelID($self), $::Options{OPT.'PathFile'}, undef,1 );
			if ($file && -r $file)
				{	::IdleDo('8_artistinfo'.$self,1000,\&load_file,$self,$file);
					$self->{sw2}->hide; $self->{sw1}->show;
					return;
				}
			}
		}
		::IdleDo('8_artistinfo'.$self,1000,\&load_url,$self,$url);
	}
}

sub GetUrl
{	my ($url,$aID) = @_;
	my $artist = ::url_escapeall( Songs::Gid_to_Get("artist",$aID) );
	return unless length $artist;
	$url=~s/%a/$artist/;
	my $limit = "";
	if ($::Options{OPT.'SimilarLimit'} != "0") { $limit = $::Options{OPT.'SimilarLimit'}; }
	$url=~s/%l/$limit/;
	return $url;
}

sub load_url
{	my ($self,$url)=@_;
	$self->set_buffer(_"Loading...");
	$self->cancel;
	warn "info : loading $url\n" if $::debug;
	$self->{url}=$url;
	$self->{sw2}->hide; $self->{sw1}->show;
	$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url, cache => 1);
}

sub loaded
{	my ($self,$data,%prop)=@_;
	delete $self->{waiting};
	my $buffer=$self->{buffer};
	my $type=$prop{type};
	unless ($data) { $data=_("Loading failed.").qq( <a href="$self->{url}">)._("retry").'</a>'; $type="text/html"; }
	$self->{url}=$prop{url} if $prop{url}; #for redirections
	$buffer->delete($buffer->get_bounds);
	my $encoding;
	if ($type && $type=~m#^text/.*; ?charset=([\w-]+)#) {$encoding=$1}
	if ($data=~m/xml version/) { $encoding='utf-8'; }
	$encoding=$1 if $data=~m#<meta *http-equiv="Content-Type" *content="text/html; charset=([\w-]+)"#;
	$encoding='cp1252' if $encoding && $encoding eq 'iso-8859-1'; #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding||='cp1252'; #default encoding
	$data=Encode::decode($encoding,$data) if $encoding;
	if ($encoding eq 'utf-8') { $data = ::decode_html($data); }
	my $iter=$buffer->get_start_iter;

	my $fontsize = $self->{fontsize};
	my $tag_warning = $buffer->create_tag(undef,foreground=>"#bf6161",justification=>'center',underline=>'single');
	my $tag_extra = $buffer->create_tag(undef,foreground_gdk=>$self->style->text_aa("normal"),justification=>'left');
	my $tag_noresults=$buffer->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	my $tag_header = $buffer->create_tag(undef,justification=>'left',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $infoheader;

	if ($self->{site} eq "biography") {
		$infoheader = _"Artist Biography";
		(my($lfm_artist,$url,$listeners,$playcount),$data)=
			$data =~ m|^.*?<name>([^<]*)</name>.*?<url>([^<]*)</url>.*?<listeners>([^<]*)</listeners>.*?<playcount>([^<]*)</playcount>.*?<content>(.*?)\n[^\n]*</content>|s; # last part of the regexp removes the license-notice (=last line)

		if (!defined $data) {
			$infoheader = "\n". _"No results found";
			$tag_header = $tag_noresults;
			$buffer->insert_with_tags($iter,$infoheader."\n",$tag_header);
		} # fallback text if artist-info not found
		else {
			for ($data) {
				s/<br \/>|<\/p>/\n/gi;
				s/\n\n*/\n/g; # never more than one empty line
				s/<([^<]*)>//g; # strip tags
			}
			my $href = $buffer->create_tag(undef,justification=>'left',foreground=>"#4ba3d2",underline=>'single');
			$href->{url}=$url.'/+wiki/edit';
			my $aID = Songs::Get_gid($::SongID,'artist');
			my $local_artist = Songs::Gid_to_Get("artist",$aID);
			my $warning;
			$warning= "Redirected to: ".$lfm_artist."\n" if $lfm_artist ne $local_artist;
			$buffer->insert_with_tags($iter,$warning,$tag_warning) if $warning;
			$buffer->insert_with_tags($iter,$infoheader."\n",$tag_header);
			$buffer->insert($iter,$data);
			$buffer->insert_with_tags($iter,"\n\n"._"Edit in the last.fm wiki",$href);
			$buffer->insert_with_tags($iter,"\n\n"._"Listeners: ".$listeners."  |   "._"Playcount: ".$playcount,$tag_extra); # only shown on fresh load, not saved to local info
			$self->{infoheader}=$infoheader;
			$self->{biography}=$data;
			$self->{lfm_url}=$url;
			$self->Save_text if $::Options{OPT.'AutoSave'};
		}
	}

	elsif ($self->{site} eq "events") {

		if ($data =~ m#total=\"(.*?)\">#g) {
			if ( $1 == 0) { $self->set_buffer(_"No results found"); return; }
			else { $infoheader = ::__("%d Upcoming Event","%d Upcoming Events",$1)."\n\n"; }
			$buffer->insert_with_tags($iter,$infoheader,$tag_header) if $infoheader;
		}
		for my $event (split /<\/event>/, $data) {
			my %event;
			$event{$1} = ::decode_html($2) while $event=~ m#<(\w+)>([^<]*)</\1>#g; # FIXME: add workaround for description (which includes <tags>)
			next unless $event{id}; # otherwise the last </events> is also treated like an event
			$event{startDate} = substr($event{startDate},0,-9); # cut the useless time (hh:mm:ss) from the date
			my $format = $::Options{OPT.'Eventformat'};
			$format =~ s/%(\w+)/$event{$1}/g;
			$format =~ s#<br>#\n#g;
			my $offset1 = $iter->get_offset;
			my $href = $buffer->create_tag(undef,justification=>'left');
			$href->{url}=$event{url};
			my ($first,$rest) = split /\n/,$format,2;
			$buffer->insert($iter,$first);
			my $offset2 = $iter->get_offset;
			$buffer->apply_tag($href,$buffer->get_iter_at_offset($offset1),$buffer->get_iter_at_offset($offset2));
			$buffer->insert_with_tags($iter,"\n".$rest,$tag_extra) if $rest;
		}

	}
	elsif ($self->{site} eq "similar") {
		$self->{store}->clear;
		$self->{sw1}->hide; $self->{sw2}->show;
		for my $s_artist (split /<\/artist>/, $data) {
			my %s_artist;
			$s_artist{$1} = ::decode_html($2) while $s_artist=~ m#<(\w+)>([^<]*)</\1>#g;
			next unless $s_artist{name}; # otherwise the last </artist> is also treated like an artist
			if ($s_artist{match} >= $::Options{OPT.'SimilarRating'} / 100) {
				my $aID=Songs::Search_artistid($s_artist{name});
				my $stats='';
				my $color=$self->style->text_aa("normal")->to_string;
				my $fgcolor = substr($color,0,3).substr($color,5,2).substr($color,9,2);
				if ($aID) {
					$stats=AA::ReplaceFields($aID,' <span foreground="'.$fgcolor.'">(%X « %s)</span>',"artist",1);
					$s_artist{url} = "local";
					$self->{store}->set($self->{store}->append,0,::PangoEsc($s_artist{name}).$stats,1,$s_artist{match} * 100,2,$s_artist{url},3,$aID,4,$s_artist{name});
				}
				elsif ($::Options{OPT.'SimilarLocal'} == 0) {
					$self->{store}->set($self->{store}->append,0,::PangoEsc($s_artist{name}).$stats,1,$s_artist{match} * 100,2,$s_artist{url},3,$aID,4,$s_artist{name});
				}
			}

		}
	}
}

sub load_file
{	my ($self,$file)=@_;
	my $buffer=$self->{buffer};
	$buffer->delete($buffer->get_bounds);
	my $text=_("Loading failed.");
	if (open my$fh,'<',$file)
	{	local $/=undef; #slurp mode
		$text=<$fh>;
		close $fh;
		if (my $utf8=Encode::decode_utf8($text)) {$text=$utf8}
	}
	my $fontsize=$self->{fontsize};
	my $href = $buffer->create_tag(undef,justification=>'left',foreground=>"#4ba3d2",underline=>'single');
	my $tag_header = $buffer->create_tag(undef,justification=>'left',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my ($infoheader,$url);
	if ($text =~ m/<title>(.*?)<\/title>(.*?)<url>(.*?)<\/url>/s) {
		$infoheader = $1; $url = $3; $text = $2;
	}
	else { $text =~ s/<title>(.*?)<\/title>\n?//i; $infoheader = $1 . "\n"; }
	my $iter=$buffer->get_start_iter;
	$buffer->insert_with_tags($iter,$infoheader,$tag_header);
	$buffer->insert($iter,$text);
	if ($url) {
		$href->{url}=$url;
		$buffer->insert_with_tags($iter,_"Edit in the last.fm wiki",$href);
	}
	$buffer->set_modified(0);
}

sub Save_text
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $win=$self->get_toplevel;
	my $buffer=$self->{buffer};
	my $text = "<title>".$self->{infoheader}."</title>\n".$self->{biography}."\n\n<url>".$self->{lfm_url}."</url>";
	my $format=$::Options{OPT.'PathFile'};
	my ($path,$file)=::pathfilefromformat( ::GetSelID($self), $format, undef,1 );
	unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$win); return}
	my $res=::CreateDir($path,$win,_"Error saving artistbio");
	return unless $res eq 'ok';
	if (open my$fh,'>:utf8',$path.$file)
	{	print $fh $text;
		close $fh;
		$buffer->set_modified(0);
		warn "Saved artistbio in ".$path.$file."\n" if $::debug;
	}
	else {::ErrorMessage(::__x(_("Error saving artistbio in '{file}' :\n{error}"), file => $file, error => $!),$win);}
}

sub QAutofillSimilarArtists
{	$queuewaiting->abort if $queuewaiting; $queuewaiting=undef;
	return unless $::QueueAction eq 'autofill-similar-artists';
	return if $::Options{MaxAutoFill}<=@$::Queue;
	return unless $::SongID;

	$nowplayingaID = Songs::Get_gid($::SongID,'artist');
	return unless Songs::Gid_to_Get("artist",$nowplayingaID);

	my $url = GetUrl($sites{similar}[0],$nowplayingaID);
	return unless $url;
	$queuewaiting=Simple_http::get_with_cb(url => $url, cb => \&PopulateQueue );
}

sub PopulateQueue
{	$queuewaiting=undef;
	if ( $nowplayingaID != Songs::Get_gid($::SongID,'artist')) { QAutofillSimilarArtists; return; }
	my $data = $_[0];

	return unless $::QueueAction eq 'autofill-similar-artists'; # re-check queueaction and
	my $nb=$::Options{MaxAutoFill}-@$::Queue;
	return unless $nb>0;
	my @artist_gids;
	for my $s_artist (split /<\/artist>/, $data) {
		my %s_artist;
		$s_artist{$1} = ::decode_html($2) while $s_artist=~ m#<(\w+)>([^<]*)</\1>#g;
		next unless $s_artist{name};
		if ($s_artist{match} >= $::Options{OPT.'SimilarRating'} / 100) {
			my $aID=Songs::Search_artistid($s_artist{name});
			push (@artist_gids, $aID) if $aID;
		}
	}
	push (@artist_gids, Songs::Get_gid($::SongID,'artist')) unless $::Options{OPT.'SimilarExcludeSeed'}; # add currently playing artist as well

	my $filter= Filter->newadd(0, map Songs::MakeFilterFromGID("artist",$_), @artist_gids );
	my $random= Random->new('random:',$filter->filter($::ListPlay));
	my @IDs=$random->Draw($nb,[@$::Queue,$::SongID]); # add queue and current song to blacklist (won't draw)
	return unless @IDs;
	$::Queue->Push(\@IDs);
}

1
