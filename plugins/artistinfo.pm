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
desc	Display Information about the playing Artist (short-biography or upcoming events) fetched from last.fm
=cut

package GMB::Plugin::ARTISTINFO;
use strict;
use warnings;
require 'simple_http.pm';
our @ISA;
BEGIN {push @ISA,'GMB::Context';}
use base 'Gtk2::VBox';
use base 'Gtk2::HBox';
use base 'Gtk2::EventBox';
use base 'Gtk2::ToggleButton';
use constant
{	OPT	=> 'PLUGIN_ARTISTINFO_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

my %sites =
(
	lastfm => [ 'lastfm artist-info', 'http://www.last.fm/music/%a',sub { $_[0]=~m/<div id="wikiAbstract">(\s*)(.*)<div class="wikiOptions">/s; return 1 }],
	events => [ 'last-fm events', 'http://ws.audioscrobbler.com/1.0/artist/%a/events.rss',sub { $_[0]=~m/<title>(.*?)<\/title>/gi; return 1 }]
);

if (my $site=$::Options{OPT.'ArtistSite'}) { delete $::Options{OPT.'ArtistSite'} unless exists $sites{$site} } #reset selected site if no longer defined
::SetDefaultOptions(OPT, FontSize => 10, PathFile => "~/Music/%a/%l/bio", ArtistSite => 'lastfm');

my $artistinfowidget=
{	class		=> __PACKAGE__,
	tabicon		=> 'gmb-artistinfo',		# no icon by that name by default (yet)
	tabtitle	=> _"Artistinfo",
	saveoptions	=> 'FontSize follow',
	schange		=> \&SongChanged,
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};

my $prev_artist = "";

sub Start
{	Layout::RegisterWidget(PluginArtistinfo => $artistinfowidget);

}
sub Stop
{	Layout::RegisterWidget(PluginArtistinfo => undef);
}

sub new
{	my ($class,$options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	$options->{follow}=1 if not exists $options->{follow};
	$self->{$_}=$options->{$_} for qw/HideToolbar follow group/;
	
	my $textview=Gtk2::TextView->new;
	$self->signal_connect(map => sub { $_[0]->SongChanged( ::GetSelID($_[0]) ); });
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_left_margin(5);
	my $label;
	
	my $togglebox = Gtk2::HBox->new(1,0);
	my $toggleB = Gtk2::RadioButton->new(undef,'biography');
	$toggleB->set_mode(0);
	if ($::Options{OPT.'ArtistSite'} eq "lastfm") { $toggleB->set_active(1); }
	else {$toggleB->set_active(0); }
	$togglebox->pack_start($toggleB,0,0,0);
	
	my @group = $toggleB->get_group;
	$toggleB=Gtk2::RadioButton->new_with_label(@group,'events');
	$toggleB->signal_connect('toggled' => \&toggled_cb);
	$toggleB->signal_connect('toggled' => \&SongChanged);
	
	
	$toggleB->set_mode(0);
	$togglebox->pack_start($toggleB,0,0,0);
	#my $source=::NewPrefCombo( OPT.'ArtistSite', {map {$_=>$sites{$_}[0]} keys %sites} ,cb => \&SongChanged, toolitem=> _"Artist-info from last.fm");
	#$togglebox->pack_start($source,0,0,0);
	
	if (my $color= $options->{color} || $options->{DefaultFontColor})
	{	$textview->modify_text('normal', Gtk2::Gdk::Color->parse($color) );
	}
	$self->{buffer}=$textview->get_buffer;
	$self->{textview}=$textview;
	
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type( $options->{shadow} || 'none');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);

	my $linkbox = Gtk2::VBox->new;
	for my $aref
	(	['gtk-refresh',	\&SongChanged, "Refresh"],
		['webcontext-lastfm', sub { Lookup_cb("http://www.last.fm/music/") }, "Show Artist page on last.fm"],
		['webcontext-wikipedia',sub { Lookup_cb("http://en.wikipedia.org/wiki/") }, "Show Artist page on wikipedia"],
		['webcontext-youtube',sub { Lookup_cb("http://www.youtube.com/results?search_type=&aq=1&search_query=") }, "Search Artist on youtube"],
	)
	{	my ($stock,$cb,$tip)=@$aref;
		my $item=::NewIconButton($stock,"",$cb,"none",$tip);
		$item->set_tooltip_text($tip) if $tip;
		$linkbox->pack_start($item,0,0,0);
	}
		
	my $linkbox_parent = Gtk2::Alignment->new(0.5,1,0,0);
	$linkbox_parent->add($linkbox);
	
	my $infobox = Gtk2::HBox->new;
	
	$self->pack_start($togglebox,0,0,0);
	$self->add($infobox);
	
	$infobox->pack_start($sw,1,1,0);
	$infobox->pack_start($linkbox_parent,0,0,0);

	$self->signal_connect(destroy => \&destroy_event_cb);
	
#	$self->{buffer}->signal_connect(modified_changed => sub {$_[1]->set_sensitive($_[0]->get_modified);}, $self->{saveb});
#	$self->{backb}->set_sensitive(0);
#	SetFont($textview);

	return $self;
}

sub toggled_cb
{	my $toggleB = shift;
	if ($toggleB->get_active) { $::Options{OPT.'ArtistSite'} = "events";}
	else { $::Options{OPT.'ArtistSite'} = "lastfm";}
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
	delete $::ToDo{'8_lyrics'.$self};
	$self->{waiting}->abort if $self->{waiting};
	$self->{waiting}=$self->{pixtoload}=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
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

=dop
sub SetFont
{	my ($textview,$size)=@_;
	my $self=::find_ancestor($textview,__PACKAGE__);
	$::Options{OPT.'FontSize'}=$self->{FontSize}=$size if $size;
	$textview->modify_font(Gtk2::Pango::FontDescription->from_string( $self->{FontSize} ));
}

=cut

sub SongChanged
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID = ::GetSelID($self);
	$self -> ArtistChanged( Songs::Get_gid($ID,'artist') );
}

sub ArtistChanged
{	my ($self,$aID)=@_;
	return unless $self->mapped;
	return unless defined $aID;
#	if (!$force)
#	{	my $file=::pathfilefromformat( $self->{ID}, $::Options{OPT.'PathFile'}, undef,1 );
#		if ($file && -r $file)
#		{	::IdleDo('8_artistinfo'.$self,1000,\&load_file,$self,$file);
#			return
#		}
#	}
	
	my $artist = ::url_escapeall( Songs::Gid_to_Get("artist",$aID) );
	$artist =~ s/%20/%2B/gi; # replace spaces by "+" for last.fm
	my (undef,$url,$post,$check)=@{$sites{$::Options{OPT.'ArtistSite'}}};
	for ($url,$post) { next unless defined $_; s/%a/$artist/; }
	if ($artist ne $self->{artist_esc} or $url ne $self->{url}) {
		$self->{artist_esc} = $artist;
		$self->{url} = $url;
		::IdleDo('8_artistinfo'.$self,1000,\&load_url,$self,$url,$post,$check);
		}
	else { $self->{artist_esc} = $artist; $self->{url} = $url; }
}

sub load_url
{	my ($self,$url,$post,$check)=@_;
	$self->{buffer}->set_text(_"Loading...");
	$self->{buffer}->set_modified(0);
	$self->cancel;
	warn "info : loading $url\n";# if $::debug;
	$self->{url}=$url;
	$self->{post}=$post;
	$self->{check}=$check; # function to check if artist-info found
	$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url,post => $post);
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
#	if ($type && $type!~m#^text/html#)
#	{	if	($type=~m#^text/#)	{$buffer->set_text($data);}
#		return;
#	}
	if ($data=~m/xml version/) { $encoding='utf-8'; }
	$encoding=$1 if $data=~m#<meta *http-equiv="Content-Type" *content="text/html; charset=([\w-]+)"#;
	$encoding='cp1252' if $encoding && $encoding eq 'iso-8859-1'; #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding||='cp1252'; #default encoding
	$data=Encode::decode($encoding,$data) if $encoding;
	
	if ($encoding eq 'utf-8') { $data = ::decode_html($data); }
	my $iter=$buffer->get_start_iter;
	my %prop;
	$prop{weight}=Gtk2::Pango::PANGO_WEIGHT_BOLD;
	my $tag=$buffer->create_tag(undef,%prop);
	my $infoheader;
	
	if ($url =~ m/music/gi) { # either it's artist-info or events-info
		
		if ($data =~ m/<p\ class="origin">(.*?)<\/p>/s)
		{	$infoheader = $1;
			for ($infoheader)
			{	s/^\s+|\s+$|\n|<(.*?)>//gi;
				s/ +/ /g;
			}
			$infoheader = $infoheader . "\n";
		}
		else { $infoheader = ""; }

		$data =~ m/<div id="wikiAbstract">(\s*)(.*)<div class="wikiOptions">/s;
		#$data =~ $regexp;
		$data = $2;
		for ($data)
		{	s/<br \/>|<\/p>/\n/gi; # never more than one empty line
			s/\n\n/\n/gi; # never more than one empty line
			s/&#8216;|&#8217;/\'/gi;
			s/&#8220;|&#8221;/\"/gi;
			s/&Oslash;//gi;
			s/&oslash;/\ø/gi;
			s/&amp;/\&/gi;
			s/<(.*?)>//gi;
		}
	}
	elsif ($url =~ m/event/gi) {
		my @line = $data =~ m/<title>(.*?)<\/title>/gi;
		$data = '';
		foreach (@line) {
			if ($_ ne "Last.fm Events") { $data = $data . " * " . $_ . "\n"; }
		}
		$infoheader = "Upcoming Events\n";
	}
	
	$buffer->insert_with_tags($iter,$infoheader,$tag);
	$buffer->insert($iter,$data);
	#$self->Save_text if $::Options{OPT.'AutoSave'} && $oklyrics && $oklyrics>0;
}

=dob
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
        $buffer->set_text($text);

	#make the title and artist bigger and bold
	my ($title,$artist)= Songs::Get($self->{ID},qw/title artist/);
	$title='' if $title!~m/\w\w/;
	for ($title,$artist)
	{	if (m/\w\w/) {s#\W+#\\W*#g}
		else {$_=''}
	}
	$artist='(?:by\W+)?'.$artist if $artist;
	if ($text && $text=~m#^\W*($title\W*\n?(?:$artist)?)\W*\n#si)
	{ my $tag=$buffer->create_tag(undef,scale => 1.5,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	  $buffer->appl$prev_artist = ""y_tag($tag,$buffer->get_iter_at_offset($-[0]),$buffer->get_iter_at_offset($+[0]));
	}

	$buffer->set_modified(0);
}

sub Save_text
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $win=$self->get_toplevel;
	my $buffer=$self->{buffer};
	my $text= $buffer->get_text($buffer->get_bounds, ::FALSE);
	my $format=$::Options{OPT.'PathFile'};
	my ($path,$file)=::pathfilefromformat( $self->{ID}, $format, undef,1 );
	unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$win); return}
	my $res=::CreateDir($path,$win);
	return unless $res eq 'ok';
	if (open my$fh,'>:utf8',$path.::SLASH.$file)
	{	print $fh $text;
		close $fh;
		$buffer->set_modified(0);
		warn "Saved lyrics in ".$path.::SLASH.$file."\n" if $::debug;
	}
	else {::ErrorMessage(::__x(_("Error saving artist-info in '{file}' :\n{error}"), file => $file, error => $!),$win);}
}
=cut
1
