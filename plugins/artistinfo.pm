# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin ARTISTINFO
name	Artistinfo
title	Artistinfo plugin
author  Simon Steinbeiß <simon.steinbeiss@shimmerproject.org>
author  Pasi Lallinaho <pasi@shimmerproject.org>
desc	Display Information about the playing Artist (short-biography or upcoming events) fetched from last.fm
=cut

package GMB::Plugin::ARTISTINFO;
use strict;
use warnings;
use utf8;
require 'simple_http.pm';
our @ISA;
BEGIN {push @ISA,'GMB::Context';}
use base 'Gtk2::VBox';
use base 'Gtk2::HBox';
use base 'Gtk2::EventBox';
use constant
{	OPT	=> 'PLUGIN_ARTISTINFO_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

my %sites =
(
	biography => [ 'http://www.last.fm/music/%a'],
	events => [ 'http://www.last.fm/music/%a/+events'],
	web => ['weblinks'],
);


::SetDefaultOptions(OPT, PathFile => "~/.config/gmusicbrowser/bio/%a");

my $artistinfowidget=
{	class		=> __PACKAGE__,
	#tabicon		=> 'gmb-artistinfo',		# no icon by that name by default (yet)
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
	if ($self->{site}) { delete $self->{site} unless exists $sites{$self->{site}} } #reset selected site if no longer defined
	else { $self->{site} = 'biography'; } # biography is the default site
	my $fontsize=$self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size / Gtk2::Pango->scale;
	$self->{artist_esc} = "";
	
	my $statbox=Gtk2::VBox->new(0,0);
	
	my $artistpic = Layout::NewWidget("ArtistPic",{forceratio=>0,click1=>undef,xalign=>0});
	
	for my $name (qw/Ltitle Lstats/)
	{	my $l=Gtk2::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1);$l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{artistrating} = Gtk2::Image->new;
	$statbox->pack_start($self->{artistrating},0,0,2);

	my $artistbox = Gtk2::HBox->new(0,0);
	$artistbox->pack_start($artistpic,1,1,0);
	$artistbox->pack_start($statbox,1,1,0);
	
	my $textview=Gtk2::TextView->new;
	$self->signal_connect(map => sub { $_[0]->SongChanged( ::GetSelID($_[0]) ); });
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_pixels_above_lines(2);
	$textview->set_editable(0);
	$textview->set_left_margin(5);
	
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
		$item->signal_connect('toggled' => sub { &toggled_cb($self,$item); } );
		$group = $item -> get_group;
		$togglebox->pack_start($item,1,0,0);
	}
	
	my $refresh = ::NewIconButton('reload',"", \&Refresh_cb ,"none","Refresh");
	$refresh->set_tooltip_text("Refresh");
	my $savebutton = ::NewIconButton('gtk-save',"",\&Save_text,"none","Save");
	$savebutton->set_tooltip_text("Save artist biography");
	
	$togglebox->pack_start($refresh,0,0,0);
	if ($::Options{OPT.'AutoSave'} != 1) { $togglebox->pack_start($savebutton,0,0,0); }
	$statbox->pack_start($togglebox,0,0,0);
	$self->{buffer}=$textview->get_buffer;
	$self->{textview}=$textview;
	
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type( $options->{shadow} || 'none');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);
	
	my $infobox = Gtk2::HBox->new;
	$infobox->set_spacing("0");
	$infobox->pack_start($sw,1,1,0);
	
	$self->pack_start($artistbox,0,0,0);
	$self->pack_start($infobox,1,1,0);
	
	$self->signal_connect(destroy => \&destroy_event_cb);
	return $self;
}

sub toggled_cb
{	my ($self, $togglebutton) = @_;
	if ($togglebutton -> get_active) {
		$self->{site} = $togglebutton->{key};
		SongChanged($togglebutton);
	}
}

sub Lookup_cb
{	my $source = shift;
	my $ID=$::SongID;
	my $q=::ReplaceFields($ID,"%a");
	if ($source =~ m/last/gi) { $q =~ s/ /+/g; } # replace spaces with "+" for last.fm
	elsif ($source =~ m/wiki/gi) { $q =~ s/ /_/g; } # replace spaces with "_" for wikipedia
	my $url=$source.$q;
	::main::openurl($url);
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
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Load/Save Artist Info in :", width=>30);
	my $preview= Label::Preview->new(preview => \&filename_preview, event => 'CurSong Option', noescape=>1,wrap=>1);
	my $autosave=::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds", tip=>_"only works when the artist-info tab is displayed");
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $entry,$preview,$autosave;
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
	my $tag_noresults=$self->{buffer}->create_tag(undef,justification=>'GTK_JUSTIFY_CENTER',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	$self->{buffer}->insert_with_tags($iter,"\n$text",$tag_noresults);
	$self->{buffer}->set_modified(0);
}

sub ExternalLinks
{	my $self = shift;
	my $buffer = $self -> {buffer};
	$buffer->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_header = $buffer->create_tag(undef,justification=>'GTK_JUSTIFY_LEFT',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $centered = $buffer->create_tag(undef,justification=>'GTK_JUSTIFY_CENTER');
	my $iter=$buffer->get_start_iter;
	$buffer->insert_with_tags($iter,"Search for artist on the web:\n\n",$tag_header);
	my $i = 1;
	for my $linkbutton
	(	['artistinfo-lastfm', sub { Lookup_cb("http://www.last.fm/music/") }, "Show Artist page on last.fm"],
		['artistinfo-wikipedia',sub { Lookup_cb("http://en.wikipedia.org/wiki/") }, "Show Artist page on wikipedia"],
		['artistinfo-youtube',sub { Lookup_cb("http://www.youtube.com/results?search_type=&aq=1&search_query=") }, "Search for Artist on youtube"],
		['artistinfo-amazon',sub { Lookup_cb("http://www.amazon.com/s/ref=nb_sb_noss?url=search-alias%3Daps&field-keywords=") }, "Search amazon.com for Artist"],
		['artistinfo-google',sub { Lookup_cb("http://www.google.at/search?q=") }, "Search google for Artist" ],
		['artistinfo-allmusic',sub { Lookup_cb("http://www.allmusic.com/cg/amg.dll?p=amg&opt1=1&sql=") }, "Search allmusic for Artist" ],
		['artistinfo-pitchfork', sub { Lookup_cb("http://pitchfork.com/search/?search_type=standard&query=") }, "Search pitchfork for Artist" ],
		['artistinfo-discogs', sub { Lookup_cb("http://www.discogs.com/artist/") }, "Search discogs for Artist" ],
	)
	{	if ($i==5) {$buffer->insert($iter,"\n"); }
		$i++;
		my ($stock,$cb,$tip)=@$linkbutton;
		my $item=Gtk2::Button->new;
		my $image=Gtk2::Image->new_from_stock($stock,'dnd');
		$item->set_image($image);
		$item->set_tooltip_text($tip);
		$item->set_relief("none");
		$item->signal_connect(clicked => $cb);
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

sub getRSSurl
{	my ($self,$url) = @_;
	&set_buffer($self,"Loading...");
	warn "info : loading $url\n";
	$self->{waiting} = Simple_http::get_with_cb(cb => sub {$self->parseRSS(@_)},url => $url);
}

sub parseRSS
{	my ($self,$data) = @_;
	delete $self->{waiting};
	my $url;
	if ($data =~ m/There are no upcoming events for this artist./gi | $data =~ m/There are no events to list here./gi) {
		&set_buffer($self,"No upcoming events for this artist.");
		return;
	}
	elsif ($data =~ m/http:\/\/ws.audioscrobbler.com(.*?).rss/gi) {
		$url = "http://ws.audioscrobbler.com".$1.".rss";
	}
	warn "info : loading $url\n";
	$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url);
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
	
	$self->{artistrating}->set_from_pixbuf(Stars::get_pixbuf($self->{artistratingvalue},1));
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
	for ($artist) {
		s#%#%25#gi; # weird last.fm escaping, "/" -> %2f (url_escapeall) "%" -> %25 -> %252f
		s/%20/%2B/gi; # replace spaces by "+" for last.fm
		s/\?/%3F/gi;
	}
	my ($url)=@{$sites{$self->{site}}};
	for ($url) { next unless defined $_; s/%a/$artist/; }
	if ($artist ne $self->{artist_esc} or $url ne $self->{url} or $force) {
		$self->{artist_esc} = $artist;
		$self->{url} = $url;
		if ($self->{site} eq "events") { ::IdleDo('8_artistinfo'.$self,1000,\&getRSSurl,$self,$url); }
		else {	::IdleDo('8_artistinfo'.$self,1000,\&load_url,$self,$url); }
		}
}

sub load_url
{	my ($self,$url)=@_;
	&set_buffer($self,"Loading...");
	$self->cancel;
	warn "info : loading $url\n";# if $::debug;
	$self->{url}=$url;
	if ($self->{site} ne "web") { $self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url); }
	else {	&ExternalLinks($self); }
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
	my $tag_noresults=$buffer->create_tag(undef,justification=>'GTK_JUSTIFY_CENTER',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	my $tag_header = $buffer->create_tag(undef,justification=>'GTK_JUSTIFY_LEFT',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my ($artistinfo_ok,$infoheader);
	
	if ($self->{site} eq "biography") {	
		if ($data =~ m/<p\ class="origin">(.*?)<\/p>/s)
		{	$infoheader = $1;
			for ($infoheader)
			{	s/^\s+|\s+$|\n|<(.*?)>//gi;
				s/ +/ /g;
			}			
		}
		else { $infoheader = "Artist Biography"; }

		$data =~ m/<div id="wikiAbstract">(\s*)(.*)<div class="wikiOptions">/s;
		$data = $2;
		for ($data)
		{	s/<br \/>|<\/p>/\n/gi; # never more than one empty line
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
		my @line = split /\n/s, $data;
		my $tag_title = $buffer->create_tag(undef,justification=>'GTK_JUSTIFY_LEFT'); 
		my $tag_date = $buffer->create_tag(undef,foreground_gdk=>$self->style->text_aa("normal"),justification=>'GTK_JUSTIFY_LEFT');
		while (defined($_=shift @line)) {
			if ($_ =~ m/<title>(.*?)<\/title>/i) {
				if ($_ =~ m/<title>Last.fm Events/gi) {
					$infoheader = "Upcoming Events\n\n";
					$buffer->insert_with_tags($iter,$infoheader,$tag_header);
				}
				else {
					s/<(.*?)>//gi;
					$_ =~ s/^\s+//; # remove leading whitespace
					$_ =~ s/\s+$//; # remove trailing whitespace
					$_ =~ m/ on (.*)/g;
					$_ =~ s/ on (.*)//gi;

					$buffer->insert_with_tags($iter,$_ . "\n",$tag_title);
					$buffer->insert_with_tags($iter,$1 . "\n",$tag_date);	
				}
			}
			elsif ($_ =~ m/<description><\!\[CDATA\[Location/gi ) {
				$_ =~ s/  <description><!\[CDATA\[Location: //;					
				$buffer->insert_with_tags($iter,$_ . "\n\n",$tag_date);
			}
		}
		my $text= $buffer->get_text($buffer->get_bounds, ::FALSE);
		if ($text eq "Upcoming Events\n\n") {	&set_buffer($self,"No results found");	}
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
	my $tag_header = $buffer->create_tag(undef,justification=>'GTK_JUSTIFY_LEFT',font=>$fontsize+1,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	$text =~ m/<title>(.*?)<\/title>/gi;
	my $infoheader = $1 . "\n";
	$text =~ s/<title>(.*?)<\/title>\n//;
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
