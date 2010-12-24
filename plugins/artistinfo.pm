# Copyright (C) 20010 Quentin Sculo <squentin@free.fr> and Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin ARTISTINFO
name	Artistinfo
title	Artistinfo plugin
version	0.3
author  Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
author  Pasi Lallinaho <pasi@shimmerproject.org>
desc	This plugin retrieves artist-relevant information (biography, upcoming events) from last.fm.
=cut

package GMB::Plugin::ARTISTINFO;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use base 'Gtk2::Box';
use constant
{	OPT	=> 'PLUGIN_ARTISTINFO_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

my %sites =
(
	biography => 'http://ws.audioscrobbler.com/2.0/?method=artist.getinfo&artist=%a&api_key=7aa688c2466dc17263847da16f297835&autocorrect=1',
	events => 'http://ws.audioscrobbler.com/2.0/?method=artist.getevents&artist=%a&api_key=7aa688c2466dc17263847da16f297835&autocorrect=1',
	web => 'weblinks',
);
my @External=
(	['lastfm',	"http://www.last.fm/music/%a",								_"Show Artist page on last.fm"],
	['wikipedia',	"http://en.wikipedia.org/wiki/%a",							_"Show Artist page on wikipedia"],
	['youtube',	"http://www.youtube.com/results?search_type=&aq=1&search_query=%a",			_"Search for Artist on youtube"],
	['amazon',	"http://www.amazon.com/s/ref=nb_sb_noss?url=search-alias=aps&field-keywords=%a",	_"Search amazon.com for Artist"],
	['google',	"http://www.google.at/search?q=%a",							_"Search google for Artist" ],
	['allmusic',	"http://www.allmusic.com/cg/amg.dll?p=amg&opt1=1&sql=%a",				_"Search allmusic for Artist" ],
	['pitchfork',	"http://pitchfork.com/search/?search_type=standard&query=%a",				_"Search pitchfork for Artist" ],
	['discogs',	"http://www.discogs.com/artist/%a",							_"Search discogs for Artist" ],
);

# lastfm api key 7aa688c2466dc17263847da16f297835
# "secret" string: 18cdd008e76705eb5f942892d49a71e2

::SetDefaultOptions(OPT, PathFile => "~/.config/gmusicbrowser/bio/%a", ArtistPicSize => "100", Eventformat => "%title at %name<br>%startDate<br>%city (%country)<br><br>");

my $artistinfowidget=
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-artistinfo',		# no icon by that name by default (yet)
	tabtitle	=> _"Artistinfo",
	saveoptions	=> 'site',
	schange		=> \&SongChanged,
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};

sub Start
{	Layout::RegisterWidget(PluginArtistinfo => $artistinfowidget); }
sub Stop
{	Layout::RegisterWidget(PluginArtistinfo => undef); }

sub new
{	my ($class,$options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;

	$self->{$_}=$options->{$_} for qw/site/;
	delete $self->{site} if $self->{site} && !$sites{$self->{site}}; #reset selected site if no longer defined
	$self->{site} ||= 'biography';	# biography is the default site
	my $fontsize=$self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size / Gtk2::Pango->scale;
	$self->{artist_esc} = "";

	my $statbox=Gtk2::VBox->new(0,0);
# TODO use own widget to display artistpic and add left-click image-zoom
	my $artistpic = Layout::NewWidget("ArtistPic",{forceratio=>1,maxsize=>$::Options{OPT.'ArtistPicSize'},click1=>undef,xalign=>0});
	for my $name (qw/Ltitle Lstats/)
	{	my $l=Gtk2::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1);$l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{artistrating} = Gtk2::Image->new;
	$statbox->pack_start($self->{artistrating},0,0,2);
	my $stateventbox = Gtk2::EventBox->new;
	$stateventbox->add($statbox);
	$stateventbox->{group}= $options->{group};
	$stateventbox->signal_connect(button_press_event => sub {my ($stateventbox, $event) = @_; return 0 unless $event->button == 3; my $ID=::GetSelID($stateventbox); ::ArtistContextMenu( Songs::Get_gid($ID,'artists'),{ ID=>$ID, self=> $stateventbox, mode => 'B'}) if defined $ID; return 1; } ); # add right-click artist-contextmenu

	my $artistbox = Gtk2::HBox->new(0,0);
	$artistbox->pack_start($artistpic,1,1,0);
	$artistbox->pack_start($stateventbox,1,1,0);

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

	my $togglebox = Gtk2::HBox->new();
	my $group;
	for my $togglebutton
	(	['biography',_"biography",_"Show artist's biography"],
		['events',_"events",_"Show artist's upcoming events"],
		['web',_"web",_"Search the web for artist"]
	)
	{	my ($key,$item,$tip) = @$togglebutton;
		$item = Gtk2::RadioButton->new($group,$item);
		$item->{key} = $key;
		$item -> set_mode(0); # display as togglebutton
		$item -> set_relief("none");
		$item -> set_tooltip_text($tip);
		$item->set_active( $key eq $self->{site} );
		$item->signal_connect('toggled' => sub { &toggled_cb($self,$item,$textview); } );
		$group = $item -> get_group;
		$togglebox->pack_start($item,1,0,0);
	}

	my $refresh =	::NewIconButton('gtk-refresh',undef, \&Refresh_cb ,"none",_"Refresh");
	my $savebutton =::NewIconButton('gtk-save',   undef, \&Save_text,  "none",_"Save artist biography");

	$togglebox->pack_start($refresh,0,0,0);
	if (!$::Options{OPT.'AutoSave'}) { $togglebox->pack_start($savebutton,0,0,0); }
	$statbox->pack_start($togglebox,0,0,0);
	$self->{buffer}=$textview->get_buffer;
	$self->{textview}=$textview;

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type( $options->{shadow} || 'none');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);

	my $infobox = Gtk2::HBox->new;
	$infobox->set_spacing(0);
	$infobox->pack_start($sw,1,1,0);

	$self->pack_start($artistbox,0,0,0);
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
	my $titlebox=Gtk2::HBox->new(0,0);
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Load/Save Artist Info in :", width=>30);
	my $preview= Label::Preview->new(preview => \&filename_preview, event => 'CurSong Option', noescape=>1,wrap=>1);
	my $autosave=::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds", tip=>_"only works when the artist-info tab is displayed");
	my $picsize=::NewPrefSpinButton(OPT.'ArtistPicSize',50,500, step=>5, page=>10, text1=>_"Artist Picture Size : ", text2=>_"(applied after restart)");
	my $eventformat=::NewPrefEntry(OPT.'Eventformat' => _"Enter custom event string :", width=>50, tip => _"Use tags from last.fm's XML event pages with a leading % (e.g. %headliner), furthermore linebreaks '<br>' and any text you'd like to have in between. E.g. '%title taking place at %startDate<br>in %city, %country<br><br>'");
	my $lastfmimage=Gtk2::Image->new_from_stock("plugin-artistinfo-lastfm",'dnd');
	my $lastfm=Gtk2::Button->new;
	$lastfm->set_image($lastfmimage);
	$lastfm->set_tooltip_text(_"Open last.fm website in your browser");
	$lastfm->signal_connect(clicked => sub { ::main::openurl("http://www.last.fm/music/"); } );
	$lastfm->set_relief("none");
	my $description=Gtk2::Label->new;
	$description->set_markup(_"For information on how to use this plugin, please navigate to the <a href='http://gmusicbrowser.org/dokuwiki/doku.php?id=plugins:artistinfo'>plugin's wiki page</a> in the <a href='http://gmusicbrowser.org/dokuwiki/'>gmusicbrowser-wiki</a>.");
	$description->set_line_wrap(1);
	$titlebox->pack_start($description,1,1,0);
	$titlebox->pack_start($lastfm,0,0,5);
	my $optionbox=Gtk2::VBox->new(0,2);
	$optionbox->pack_start($_,0,0,1) for $entry,$preview,$autosave,$picsize,$eventformat;
	$vbox->pack_start($_,::FALSE,::FALSE,5) for $titlebox,$optionbox;
	return $vbox;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
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
	my $url=$self->url_at_coords($x,$y);
	::main::openurl($url) if $url;
	return ::FALSE;
}

sub url_at_coords
{	my ($self,$x,$y)=@_;
	my $iter=$self->{textview}->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		if ($tag->{url}=~m/^#(\d+)?/) { $self->scrollto($1) if defined $1; last }
		my $url= $tag->{url};
		return $url;
	}
}

sub ExternalLinks
{	my $self = shift;
	my $buffer = $self -> {buffer};
	$buffer->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_header = $buffer->create_tag(undef,justification=>'left',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $centered = $buffer->create_tag(undef,justification=>'center');
	my $iter=$buffer->get_start_iter;
	$buffer->insert_with_tags($iter,_("Search the web for artist")." :\n\n",$tag_header);
	my $i = 1;
	my $artist = $self->{artist_esc};
	for my $linkbutton (@External)
	{	if ($i==5) {$buffer->insert($iter,"\n"); }
		$i++;
		my ($stock,$url,$tip)=@$linkbutton;
		my $item=Gtk2::Button->new;
		my $image=Gtk2::Image->new_from_stock("plugin-artistinfo-".$stock,'dnd');
		$item->set_image($image);
		$item->set_tooltip_text($tip);
		$item->set_relief("none");
		$url=~s/%a/$artist/;
		$item->signal_connect(clicked => sub { ::main::openurl($_[1]); }, $url);
		$buffer->insert_with_tags($iter,"  ",$centered);
		my $anchor = $buffer->create_child_anchor($iter);
		$self->{textview}->add_child_at_anchor($item,$anchor);
		$buffer->insert_with_tags($iter,"  ",$centered);
		$item->show_all;
	}

	$buffer->set_modified(0);
}

sub Refresh_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID = ::GetSelID($self);
	$self -> ArtistChanged( Songs::Get_gid($ID,'artist'),1);
}

sub SongChanged
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID = ::GetSelID($self);
	$self -> ArtistChanged( Songs::Get_gid($ID,'artist'));
}

sub ArtistChanged
{	my ($self,$aID,$force)=@_;
	return unless $self->mapped;
	return unless defined $aID;
	if ($self->{site} ne "biography") { $force = 1; }
	$self->cancel;
	my $rating = AA::Get("rating:average",'artist',$aID);
	$self->{artistratingvalue}= int($rating+0.5);
	$self->{artistratingrange}=AA::Get("rating:range",'artist',$aID);
	$self->{artistplaycount}=AA::Get("playcount:sum",'artist',$aID);
	my $tip = "Average rating: ".$self->{artistratingvalue} ."\nRating range: ".$self->{artistratingrange}."\nTotal playcount: ".$self->{artistplaycount};

	$self->{artistrating}->set_from_pixbuf(Songs::Stars($self->{artistratingvalue},'rating'));
	$self->{Ltitle}->set_markup( AA::ReplaceFields($aID,"<big><b>%a</b></big>","artist",1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($aID,'%X « %s'."\n<small>%y</small>","artist",1) );
	for my $name (qw/Ltitle Lstats artistrating/) { $self->{$name}->set_tooltip_text($tip); }

	if (!$force) # if not forced to reload (events, reload-button), check for local file first
	{	my $file=::pathfilefromformat( ::GetSelID($self), $::Options{OPT.'PathFile'}, undef,1 );
		if ($file && -r $file)
		{	::IdleDo('8_artistinfo'.$self,1000,\&load_file,$self,$file);
			return
		}
	}

	my $artist = ::url_escapeall( Songs::Gid_to_Get("artist",$aID) );

	my $url= $sites{$self->{site}};
	$url=~s/%a/$artist/;
	if ($artist ne $self->{artist_esc} or $url ne $self->{url} or $force) {
		$self->{artist_esc} = $artist;
		$self->{url} = $url;
		::IdleDo('8_artistinfo'.$self,1000,\&load_url,$self,$url);
		}
}

sub load_url
{	my ($self,$url)=@_;
	$self->set_buffer(_"Loading...");
	$self->cancel;
	warn "info : loading $url\n" if $::debug;
	$self->{url}=$url;
	if ($self->{site} ne "web") { $self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url); }
	else {	$self->ExternalLinks; }
}

sub loaded
{	my ($self,$data,$type,$url)=@_;
	delete $self->{waiting};
	my $buffer=$self->{buffer};
	unless ($data) { $data=_("Loading failed.").qq( <a href="$self->{url}">)._("retry").'</a>'; $type="text/html"; }
	$self->{url}=$url if $url; #for redirections
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
	my $tag_noresults=$buffer->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	my $tag_header = $buffer->create_tag(undef,justification=>'left',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my ($artistinfo_ok,$infoheader);

	if ($self->{site} eq "biography") {
		$infoheader = "Artist Biography";
		$data =~ m/<content><\!\[CDATA\[(.*)/gi;
		$data = $1;
		for ($data) {
			s/<br \/>|<\/p>/\n/gi; # never more than one empty line
			s/\n\n/\n/gi; # never more than one empty line (again)
			s/<(.*?)>//gi; # strip tags
		}
		if ($data eq "") { $infoheader = "\nNo results found"; $artistinfo_ok = "0"; $tag_header = $tag_noresults; } # fallback text if artist-info not found
		else { $artistinfo_ok = "1"; }
		$buffer->insert_with_tags($iter,$infoheader."\n",$tag_header);
		$buffer->insert($iter,$data);
		$self->{infoheader}=$infoheader;
		$self->{biography} = $data;
	}

	elsif ($self->{site} eq "events") {

		my $tag = $buffer->create_tag(undef,foreground_gdk=>$self->style->text_aa("normal"),justification=>'left');
		my @events;
		if ($data =~ m#total=\"(.*?)\">#g) {
			if ( $1 == 1) { $infoheader = $1 ." Upcoming Event\n\n"; }
			elsif ( $1 == 0) { $self->set_buffer("No results found"); return; }
			else { $infoheader = $1 ." Upcoming Events\n\n"; }
			$buffer->insert_with_tags($iter,$infoheader,$tag_header) if $infoheader;
		}
		for my $event (split /<\/event>/, $data) {
			my %event;
			$event{$1} = ::decode_html($2) while $event=~ m#<(\w+)>([^<]*)</\1>#g;
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
			$buffer->insert_with_tags($iter,"\n".$rest,$tag) if $rest;
		}

	}

	$self->Save_text if $::Options{OPT.'AutoSave'} && $artistinfo_ok && $artistinfo_ok==1;
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
	my $tag_header = $buffer->create_tag(undef,justification=>'left',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	$text =~ s/<title>(.*?)<\/title>\n?//i;
	my $infoheader = $1 . "\n";
	my $iter=$buffer->get_start_iter;
	$buffer->insert_with_tags($iter,$infoheader,$tag_header);
        $buffer->insert($iter,$text);
	$buffer->set_modified(0);
}

sub Save_text
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $win=$self->get_toplevel;
	my $buffer=$self->{buffer};
	my $text = "<title>".$self->{infoheader}."</title>\n".$self->{biography};
	my $format=$::Options{OPT.'PathFile'};
	my ($path,$file)=::pathfilefromformat( ::GetSelID($self), $format, undef,1 );
	unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$win); return}
	my $res=::CreateDir($path,$win);
	return unless $res eq 'ok';
	if (open my$fh,'>:utf8',$path.$file)
	{	print $fh $text;
		close $fh;
		$buffer->set_modified(0);
		warn "Saved artistbio in ".$path.$file."\n"; #if $::debug;
	}
	else {::ErrorMessage(::__x(_("Error saving artistbio in '{file}' :\n{error}"), file => $file, error => $!),$win);}
}

1
