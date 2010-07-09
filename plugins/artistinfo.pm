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
desc	Display Artistinfo
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
use constant
{	OPT	=> 'PLUGIN_ARTISTINFO_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

::SetDefaultOptions(OPT, FontSize => 10, PathFile => "~/.lyrics/%a/%t.lyric");


my $artistinfowidget=
{	class		=> __PACKAGE__,
	#tabicon		=> 'gmb-lyrics',		# no icon by that name by default
	tabtitle	=> _"Artistinfo",
	saveoptions	=> 'FontSize follow',
	schange		=> \&SongChanged,
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};

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
	#my $color = Gtk2::Gdk::Color->parse('black'); # hardcoding the color
	
#	my $parent = bless Gtk2::Notebook->new, $class;
#	my $bgcolor = $parent->get_style() ->bg('normal'); # retrieving the color
#	$bgcolor =~ m/\((.*)\)/gi;
#	$bgcolor = $1;
#	my $bgcolor_ = Gtk2::Gdk::Color->new;
#	$bgcolor_ > set_pixel($bgcolor->pixel);
#	$textview->modify_base('normal',$bgcolor_);
	
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
	(	['gtk-refresh',	\&Refresh_cb, "Refresh"],
		['webcontext-lastfm',\&Lookup_lastfm, "Show Artist page on last.fm"],
		['webcontext-wikipedia',\&Lookup_lastfm, "Show Artist page on wikipedia"],
	)
	{	my ($stock,$cb,$tip)=@$aref;
		my $item=::NewIconButton($stock,"",$cb,"none",$tip);
		$item->signal_connect(clicked => $cb);
		$item->set_tooltip_text($tip) if $tip;
		$linkbox->pack_start($item,0,0,0);
	}
	
#	'http://www.last.fm/music/'
#	'http://en.wikipedia.org/wiki/'

	
	my $linkbox_parent = Gtk2::Alignment->new(0.5,1,0,0);
	$linkbox_parent->add($linkbox);
	
	my $infobox = Gtk2::HBox->new;
	
	$self->add($infobox);
	$infobox->pack_start($sw,1,1,0);
	$infobox->pack_start($linkbox_parent,0,0,0);

	$self->signal_connect(destroy => \&destroy_event_cb);
	
#	$self->{buffer}->signal_connect(modified_changed => sub {$_[1]->set_sensitive($_[0]->get_modified);}, $self->{saveb});
#	$self->{backb}->set_sensitive(0);
#	SetFont($textview);

	return $self;
}

sub Lookup_lastfm
{	#my ($ID)=@_;
	#my $source = $_[0];
	#print $_[0] . " : " . $_[1];
	my $ID=$::SongID;
	my $q=::ReplaceFields($ID,"%a");
	#my ($artist)= map ::url_escapeall($_), Songs::Get($ID,qw/artist/);
	#if ($source = m/last.fm/) { $q =~ s/ /+/g; } # replace spaces with "+" for last.fm
	my $url='http://www.last.fm/music/'.$q;
	#warn $url;
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
#	my $Bopen=Gtk2::Button->new(_"open context window");
#	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $entry,$preview,$autosave;
	return $vbox;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
	$t= $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
	return '<small>'.$t.'</small>';
}

#sub SetFont
#{	my ($textview,$size)=@_;
#	my $self=::find_ancestor($textview,__PACKAGE__);
#	$::Options{OPT.'FontSize'}=$self->{FontSize}=$size if $size;
#	$textview->modify_font(Gtk2::Pango::FontDescription->from_string( $self->{FontSize} ));
#}

sub SetSource
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	$self->SongChanged($self->{ID},1);
}

sub Refresh_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID=delete $self->{ID};
	$self->SongChanged($ID,1);
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless $self->mapped;
	return unless defined $ID;
	return if defined $self->{ID} && !$force && ( $ID==$self->{ID} || !$self->{follow} );
	$self->{ID}=$ID;
	$self->{time}=undef;

	if (!$force)
	{	my $file=::pathfilefromformat( $self->{ID}, $::Options{OPT.'PathFile'}, undef,1 );
		if ($file && -r $file)
		{	::IdleDo('8_lyrics'.$self,1000,\&load_file,$self,$file);
			return
		}
	}

	my ($artist)= map ::url_escapeall($_), Songs::Get($ID,qw/artist/);
	my $site=[undef,'http://www.last.fm/music/%a',sub { $_[0]=~m/<div id="wikiAbstract">(\s*)(.*)<div class="wikiOptions">/s; return 1 }];
	my ($url,$post,$check)=@{$site};
	for ($url,$post) { next unless defined $_; s/%a/$artist/; }
	#$self->load_url($urlGtk2::Gdk::Color->parse($bgcolor),$post);
	::IdleDo('8_lyrics'.$self,1000,\&load_url,$self,$url,$post,$check);
}

sub load_url
{	my ($self,$post,$url,$check)=@_;
	$self->{buffer}->set_text(_"Loading...");
	$self->{buffer}->set_modified(0);
	$self->cancel;
	warn "info : loading $url\n";# if $::debug;
	$self->{url}=$url;
	$self->{post}=$post;
	$self->{check}=$check; # function to check if lyrics found
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
	if ($type && $type!~m#^text/html#)
	{	if	($type=~m#^text/#)	{$buffer->set_text($data);}
		#elsif	($type=~m#^image/#)
		#{	my $loader= GMB::Picture::LoadPixData($data);
		#	if (my $p=$loader->get_pixbuf) {$buffer->insert_pixbuf(0,$p);}
		#}
		return;
	}
	$encoding=$1 if $data=~m#<meta *http-equiv="Content-Type" *content="text/html; charset=([\w-]+)"#;
	$encoding='cp1252' if $encoding && $encoding eq 'iso-8859-1'; #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding||='cp1252'; #default encoding
	$data=Encode::decode($encoding,$data) if $encoding;
	
	my $artistheader;
	if ($data =~ m/<p\ class="origin">(.*?)<\/p>/s)
	{	$artistheader = $1;
		for ($artistheader)
		{	s/^\s+|\s+$|\n|<(.*?)>//gi;
			s/ +/ /g;
		}
		$artistheader = $artistheader . "\n";
	}
	else { $artistheader = ""; }
	
	$data =~ m/<div id="wikiAbstract">(\s*)(.*)<div class="wikiOptions">/s;
	$data = $2;
	for ($data)
	{	s/<br \/>|<\/p>/\n/gi; # never more than one empty line
		s/\n\n/\n/gi; # never more than one empty line
		s/&#8216;|&#8217;/\'/gi;
		s/&#8220;|&#8221;/\"/gi;
		s/&amp;/\&/gi;
		s/<(.*?)>//gi;
	}
	#my $artistheader = "HEADER\n";
	#$artistheader->modify_font(Gtk2::Pango::FontDescription->from_string("Sans Bold 18"));
	#$data = qq/$artistheader/ . "\n" . $data;
	#$data = substr($data,0,1000);

#	my $artistbio = "";
#	for(my $i = 1; $i < 125; $i++)
#		{	my $word = (split(' ', $data));
#			$artistbio = $artistbio.' '.$word;
#		}
	#for ($data)
#			foreach my $word (split(' ', $data))
#			{	$artistbio = $artistbio.' '.$word;
#				#warn $i . " : ".$word;
#			}
		
#	warn $artistbio;

	
	my $iter=$buffer->get_start_iter;
	my %prop;
	$prop{weight}=Gtk2::Pango::PANGO_WEIGHT_BOLD;
	my $tag=$buffer->create_tag(undef,%prop);
	$buffer->insert_with_tags($iter,$artistheader,$tag);
	$buffer->insert($iter,$data);
	#$self->Save_text if $::Options{OPT.'AutoSave'} && $oklyrics && $oklyrics>0;
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
	  $buffer->apply_tag($tag,$buffer->get_iter_at_offset($-[0]),$buffer->get_iter_at_offset($+[0]));
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

1
