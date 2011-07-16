# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin ALBUMINFO
name	Albuminfo
title	Albuminfo plugin
version	0.1
author  Øystein Tråsdahl (based on the Artistinfo plugin)
desc	Retrieves album-relevant information (review etc.) from allmusic.com.
=cut

# TODO:
# - Create fields (moods, styles, themes) automatically. Or allow the user to specify the name of those fields in the preferences.
#   Note: fields are case sensitive.
# - Create local links in the review that can be used for contextmenus and filtering. (Will need something like Songs::Search_albumid().)
# - Consider searching google instead, or add google search if amg fails.
# - Option to save AMG "Style"-tag as Genre (is it useful?).

package GMB::Plugin::ALBUMINFO;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use constant
{	OPT	=> 'PLUGIN_ALBUMINFO_',
};

::SetDefaultOptions
(	OPT,
	PathFile	=> "~/.config/gmusicbrowser/review/%a - %l.txt",
	CoverSize	=> 100,
);

my $albuminfowidget =
{	class			=> __PACKAGE__,
	tabicon			=> 'plugin-albuminfo',
	tabtitle		=> _"Albuminfo",
	schange			=> \&song_changed,
	group			=> 'Play',
	autoadd_type	=> 'context page text',
};



sub Start {
	Layout::RegisterWidget(PluginAlbuminfo => $albuminfowidget);
}

sub Stop {
	Layout::RegisterWidget(PluginAlbuminfo => undef);
}

sub prefbox {
	my $vbox = Gtk2::VBox->new(0,2);
	my $entry = ::NewPrefEntry(OPT.'PathFile' => _"Save album info in:", width=>40);
	my $preview = Label::Preview->new(event=>'CurSong Option', noescape=>1, wrap=>1, preview=>
									  sub { return '' unless defined $::SongID;
											my $t = ::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
											$t = ::filename_to_utf8displayname($t) if $t;
											$t = $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
											return '<small>'.$t.'</small>';
									  });
	my $autosave = ::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds"); #, tip=>_"Only works when the review tab is displayed");
	my $genres = ::NewPrefCheckButton(OPT.'genre' => _"Genres");
	my $moods  = ::NewPrefCheckButton(OPT.'mood'  => _"Moods");
	my $styles = ::NewPrefCheckButton(OPT.'Style' => _"Styles");
	my $themes = ::NewPrefCheckButton(OPT.'Theme' => _"Themes");
	my ($radio1a,$radio1b) = ::NewPrefRadio(OPT.'ReplaceFields',undef,_"Add to existing values",0,_"Replace existing values",1);
	my $savefields = ::NewPrefCheckButton(OPT.'SaveFields' => _"Auto-save fields", tip=>_"Note: missing fields must be created by the user in the 'Fields' tab in Settings", 
										  widget=>::Vpack(::Hpack($genres, $moods, $styles, $themes), ::Vpack($radio1a, $radio1b)));
	my $picsize = ::NewPrefSpinButton(OPT.'CoverSize',50,500, step=>5, page=>10, text1=>_"Cover Size : ", text2=>_"(applied after restart)");
	my $allmusic = ::NewIconButton('plugin-artistinfo-allmusic',undef,sub { ::main::openurl("http://www.allmusic.com/"); },'none',_"Open allmusic.com website in your browser");
	my $titlebox = Gtk2::HBox->new(0,0);
	$titlebox->pack_start($picsize,1,1,0);
	$titlebox->pack_start($allmusic,0,0,5);
	my $frame_review = Gtk2::Frame->new(_"review");
	$frame_review->add(::Vpack($entry,$preview,$autosave,$savefields));
	$vbox->pack_start($_,::FALSE,::FALSE,5) for $titlebox,$frame_review;
	return $vbox;
}



#####################################################################
#
# Section: albuminfowidget (the Context pane tab).
#
#####################################################################
sub new {
	my ($class,$options) = @_;
	my $self = bless(Gtk2::VBox->new(0,0), $class);
	$self->{$_} = $options->{$_} for qw/group/;
	my $fontsize = $self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size() / Gtk2::Pango->scale;

	# Heading: cover and album info.
	my $statbox = Gtk2::VBox->new(0,0);
	my $cover = Layout::NewWidget("Cover", {group=>$options->{group}, forceratio=>1, maxsize=>$::Options{OPT.'CoverSize'}, xalign=>0, tip=>_"Click to show fullsize image", click1=>\&cover_popup,
											click3=>sub {::PopupAAContextMenu({self=>$_[0], field=>'album', ID=>$::SongID, gid=>Songs::Get_gid($::SongID,'album'), mode=>'P'});} });
	for my $name (qw/Ltitle Lstats/) {
		my $l = Gtk2::Label->new('');
		$self->{$name} = $l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1); $l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{ratingpic} = Gtk2::Image->new();
	$statbox->pack_start($self->{ratingpic},0,0,2);

	# "Refresh", "save" and "search" buttons
	my $refreshbutton = ::NewIconButton('gtk-refresh', undef, sub { song_changed($self,undef,undef,1); }, "none", _"Refresh");
	my $savebutton	  = ::NewIconButton('gtk-save', undef, \&save_review, "none", _"Save review");
	my $searchbutton  = ::NewIconButton('gtk-find', undef, sub {$self->manual_search()}, "none", _"Manual search");
	my $buttonbox = Gtk2::HBox->new();
	$buttonbox->pack_end($searchbutton,0,0,0);
	$buttonbox->pack_end($savebutton,0,0,0); # unless $::Options{OPT.'AutoSave'};
	$buttonbox->pack_end($refreshbutton,0,0,0);
	$statbox->pack_end($buttonbox,0,0,0);
	my $stateventbox = Gtk2::EventBox->new(); # To catch mouse events
	$stateventbox->add($statbox);
	$stateventbox->signal_connect(button_press_event => sub {my ($stateventbox, $event) = @_; return 0 unless $event->button == 3; my $ID = ::GetSelID($self);
															 ::PopupAAContextMenu({ self=>$stateventbox, mode=>'P', field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album') }) if defined $ID; return 1; } );

	# For the review: a TextView in a ScrolledWindow in a HBox
	my $textview = Gtk2::TextView->new();
	$self->signal_connect(map => \&song_changed);
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_pixels_above_lines(2);
	$textview->set_editable(0);
	$textview->set_left_margin(5);
	$textview->set_has_tooltip(1);
	$textview->signal_connect(button_release_event	  => \&button_release_cb);
	$textview->signal_connect(motion_notify_event	  => \&update_cursor_cb);
	$textview->signal_connect(visibility_notify_event => \&update_cursor_cb);
	$textview->signal_connect(query_tooltip			  => \&update_cursor_cb);
	$self->{textview} = $textview;
	$self->{buffer} = $textview->get_buffer();
	my $sw = Gtk2::ScrolledWindow->new();
	$sw->add($textview);
	$sw->set_shadow_type('none');
	$sw->set_policy('automatic','automatic');
	my $textbox = Gtk2::HBox->new;
	$textbox->set_spacing(0);
	$textbox->pack_start($sw,1,1,0);
	$textview->show();

	# Pack it all into self (a VBox)
	my $infobox = Gtk2::HBox->new(0,0);
	$infobox->pack_start($cover,0,0,0);
	$infobox->pack_end($stateventbox,1,1,5);
	$self->pack_start($infobox,0,0,0);
	$self->pack_start($textbox,1,1,0);
	$self->signal_connect(destroy => sub {$_[0]->cancel()});
	return $self;
}

sub update_cursor_cb {
	my $textview = $_[0];
	my (undef,$wx,$wy,undef) = $textview->window->get_pointer;
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter = $textview->get_iter_at_location($x,$y);
	my $cursor = 'xterm';
	for my $tag ($iter->get_tags) {
		next unless $tag->{url};
		$cursor = 'hand2';
		$textview->set_tooltip_text($tag->{url});
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor} = $cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

# Mouse button pressed in textview. If link: open url in browser.
sub button_release_cb {
	my ($textview,$event) = @_;
	my $self = ::find_ancestor($textview,__PACKAGE__);
	return ::FALSE unless $event->button == 1;
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $url = $self->url_at_coords($x,$y,$textview);
	::main::openurl($url) if $url;
	return ::FALSE;
}

sub url_at_coords {
	my ($self,$x,$y,$textview) = @_;
	my $iter = $textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags) {
		next unless $tag->{url};
		if ($tag->{url} =~ m/^#(\d+)?/) { $self->scrollto($1) if defined $1; last }
		my $url= $tag->{url};
		return $url;
	}
}

sub cover_popup {
	my ($self, $event) = @_;
	my $menu = Gtk2::Menu->new();
	$menu->modify_bg('GTK_STATE_NORMAL',Gtk2::Gdk::Color->parse('black')); # black bg for the cover-popup
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	if (my $img = Gtk2::Image->new_from_file(AAPicture::GetPicture('album',$aID))) {
		my $apic = Gtk2::MenuItem->new();
		$apic->modify_bg('GTK_STATE_SELECTED',Gtk2::Gdk::Color->parse('black'));
		$apic->add($img);
		$apic->show_all();
		$menu->append($apic);
		$menu->popup (undef, undef, undef, undef, $event->button, $event->time);
		return 1;
	} else {
		return 0;
	}
}

# Print warnings in the text buffer
sub print_warning {
	my ($self,$text) = @_;
	$self->{buffer}->set_text("");
	my $iter = $self->{buffer}->get_start_iter();
	my $fontsize = $self->{fontsize};
	my $tag_noresults = $self->{buffer}->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	$self->{buffer}->insert_with_tags($iter,"\n$text",$tag_noresults);
	$self->{buffer}->set_modified(0);
}

# Print review (and additional data) in the text buffer
sub print_review {
	my ($self) = @_;
	my $buffer = $self->{buffer};
	$self->{buffer}->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_h1 = $buffer->create_tag(undef, justification=>'left', font=>$fontsize+2, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_h2 = $buffer->create_tag(undef, justification=>'left', font=>$fontsize+1, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_b  = $buffer->create_tag(undef, justification=>'left', weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_i  = $buffer->create_tag(undef, justification=>'left', style=>'italic');
	my $tag_a  = $buffer->create_tag(undef, justification=>'left', foreground=>"#4ba3d2", underline=>'single');
	my $iter = $buffer->get_start_iter();
	if ($self->{fields}{label})	   {$buffer->insert_with_tags($iter,_"Label:\t\t\t",$tag_b); $buffer->insert($iter,"$self->{fields}{label}\n")}
	if ($self->{fields}{rec_date}) {$buffer->insert_with_tags($iter,_"Recording date:\t",$tag_b); $buffer->insert($iter,"$self->{fields}{rec_date}\n")}
	if ($self->{fields}{rls_date}) {$buffer->insert_with_tags($iter,_"Release date:\t\t",$tag_b); $buffer->insert($iter,"$self->{fields}{rls_date}\n")}
	if ($self->{fields}{rating})   {$buffer->insert_with_tags($iter,_"AMG Rating:\t\t",$tag_b);
									$buffer->insert_pixbuf($iter, Songs::Stars($self->{fields}{rating}, 'rating')); $buffer->insert($iter,"\n");}
	if ($self->{fields}->{review}) {
		$buffer->insert_with_tags($iter, _"\nReview\n", $tag_h2);
		$buffer->insert_with_tags($iter, _"by ".$self->{fields}->{author}."\n", $tag_i);
		$buffer->insert($iter,$self->{fields}->{review});
	} else {
		$buffer->insert_with_tags($iter,_"\nNo review written.\n",$tag_h2);
	}
	$tag_a->{url} = $self->{fields}->{url};
	$buffer->insert_with_tags($iter,_"\n\nLookup at allmusic.com",$tag_a);
	$buffer->set_modified(0);
}



#####################################################################
#
# Section: "Manual search" window.
#
#####################################################################
sub manual_search {
	my $context = shift; # The context pane object is needed when we get to load_review
	my $gid = Songs::Get_gid(::GetSelID($context), 'album');
	my $album = Songs::Gid_to_Get("album",$gid);
	my $self = bless(Gtk2::Dialog->new(_"Searching AMG for ".$album,undef,'destroy-with-parent', 'gtk-ok'=>'ok','gtk-cancel'=>'cancel'));
	$self->set_default_size(600, 600);
	$self->set_position('center-always');
	$self->set_border_width(4);

	# Contents: textentry, searchbutton, stopbutton and scrollwindow (for radiobuttons).
	$self->{search} = my $search  = Gtk2::Entry->new;
	$self->{Bsearch}= my $Bsearch = ::NewIconButton('gtk-find', _"Search");
	$self->{Bstop}	= my $Bstop	  = ::NewIconButton('gtk-cancel', _"Stop");
	$self->{vbox}	= my $vbox = Gtk2::VBox->new(0,0);
	$search->set_tooltip_text(_"Enter album name");
	$search->set_text(Songs::Gid_to_Get('album', $gid));
	my $scrwin = Gtk2::ScrolledWindow->new();
	$scrwin->set_policy('automatic', 'automatic');
	$scrwin->add_with_viewport($vbox);
	$self->get_content_area()->add( ::Vpack(['_', $search, $Bsearch, $Bstop], '_', $scrwin) );

	# Handle the relevant events (signals).
	$search ->signal_connect(activate => \&new_search ); # Pressing Enter in the search entry.
	$Bsearch->signal_connect(clicked  => \&new_search );
	$Bstop	->signal_connect(clicked  => sub {if ($self->{waiting}) {$self->{vbox}->remove($_) for $self->{vbox}->get_children();
											  $self->{vbox}->pack_start(Gtk2::Label->new('Search stopped.'),0,0,20);
											  $self->{vbox}->show_all(); $self->cancel(); delete $self->{waiting};}});
	$scrwin->signal_connect(key_press_event => sub {$self->response('ok') if $_[1]->keyval == $Gtk2::Gdk::Keysyms{Return};}); # Pressing Enter in results list
	$self->signal_connect(response => sub {$self->destroy();
										   $self->entry_selected_cb($context) if ($_[1] eq 'ok');} );
	$self->signal_connect(destroy => \&cancel);
	$self->show_all();
	$self->new_search();
}

sub new_search {
	my $self = ::find_ancestor($_[0], __PACKAGE__); # $_[0] can be a button or gtk-entry. Ancestor is an albuminfo object.
	my $album = $self->{search}->get_text();
	$album =~ s|^\s+||; $album =~ s|\s+$||; # remove leading and trailing spaces
	return if $album eq '';
	$self->set_title(_"Searching AMG for ".$album);
	$self->{vbox}->remove($_) for $self->{vbox}->get_children();
	$self->{vbox}->pack_start(Gtk2::Label->new('Searching...'),0,0,20);
	$self->{vbox}->show_all();
	my $url = "http://allmusic.com/search/album/".::url_escapeall($album);
	$self->cancel();
	warn "Albuminfo: fetching AMG search from url $url.\n" if $::debug;
	::IdleDo('8_albuminfo'.$self,1000, 
			 sub {$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->print_results(@_)},url=>$url, cache=>1);});
}

sub print_results {
	my ($self,$html,$type,$url) = @_;
	delete $self->{waiting};
	$self->{vbox}->remove($_) for $self->{vbox}->get_children();
	my $result = parse_amg_search_results($html, $type); # result is a ref to an array of hash refs
	my @radios;
	if ( $#{$result} + 1 ) {
		push(@radios, Gtk2::RadioButton->new(undef, "$_->{artist} - $_->{album} ($_->{year}) on $_->{label}")) foreach @$result;
		my $group = $radios[0]->get_group();
		$radios[$_]->set_group($group) for (1 .. $#radios);
		$self->{vbox}->pack_start($_,0,0,0) foreach @radios;
	} else {
		$self->{vbox}->pack_start(Gtk2::Label->new(_"No results found."),0,0,20);
	}
	$self->{result} = $result;
	$self->{radios} = \@radios;
	$self->show_all();
}

sub entry_selected_cb {
	my ($self, $context) = @_;
	return unless ( $#{$self->{result}} + 1 );
	my $selected;
	foreach (0 .. $#{$self->{radios}}) {
		if (${$self->{radios}}[$_]->get_active()) {$selected = ${$self->{result}}[$_]; last;}
	}
	warn "Albuminfo: fetching review from url $selected->{url}\n" if $::debug;
	$context->{url} = $selected->{url}.'/review';
	$self->cancel();
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$context->load_review(@_)}, url=>$context->{url}, cache=>1);
}




#####################################################################
#
# Section: loading and parsing review. Saving review and fields.
#
#####################################################################
sub song_changed {
	my ($widget,$tmp,$group,$force) = @_; # $tmp = ::GetSelID($self), but not always. So we don't use it. $group is also not used.
	my $self = ::find_ancestor($widget, __PACKAGE__);
	return unless $self->mapped() || $::Options{OPT.'SaveFields'};
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	return unless $aID;
	if (!$self->{aID} || $aID != $self->{aID} || $force) { # Check if album has changed or a forced update is required.
		$self->{aID} = $aID;
		$self->album_changed($ID, $aID, $force);
	}
}

sub album_changed {
	my ($self,$ID,$aID,$force) = @_;
	$self->update_titlebox($aID);
	$self->cancel();
	my $album = lc(::url_escapeall(Songs::Gid_to_Get("album",$aID)));
	my $url = "http://allmusic.com/search/album/$album";
	$self->print_warning(_"Loading...");
	unless ($force) { # Try loading from file.
		my $file = ::pathfilefromformat( ::GetSelID($self), $::Options{OPT.'PathFile'}, undef, 1 );
		if ($file && -r $file) {
			::IdleDo('8_albuminfo'.$self,1000,\&load_file,$self,$file);
			return;
		}
	}
	warn "Albuminfo: fetching search results from url $url\n" if $::debug;
	::IdleDo('8_albuminfo'.$self,1000, 
			 sub {$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_search_results($ID,@_)}, url=>$url, cache=>1);});
}

sub update_titlebox {
	my ($self,$aID) = @_;
	my $rating = AA::Get("rating:average",'album',$aID);
	$self->{rating} = int($rating+0.5);
	$self->{ratingrange} = AA::Get("rating:range",'album',$aID);
	$self->{playcount}	 = AA::Get("playcount:sum",'album',$aID);
	my $tip = join("\n",_"Average rating:"	.' '.$self->{rating},
						_"Rating range:"	.' '.$self->{ratingrange},
						_"Total playcount:"	.' '.$self->{playcount});
	$self->{ratingpic}->set_from_pixbuf(Songs::Stars($self->{rating},'rating'));
	$self->{Ltitle}->set_markup( AA::ReplaceFields($aID,"<big><b>%a</b></big>","album",1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($aID,'<small>by %b\n%y\n%s, %l</small>',"album",1) );
	for my $name (qw/Ltitle Lstats/) { $self->{$name}->set_tooltip_text($tip); }
}

sub load_search_results {
	my ($self,$ID,$html,$type) = @_;
	delete $self->{waiting};
	my $result = parse_amg_search_results($html, $type);
	my ($artist,$year) = ::Songs::Get($ID, qw/artist year/);
	my $url;
	foreach my $entry (@$result) {
		# Pick the first entry with the right artist and year, or if not: just the right artist.
		if (lc($entry->{artist}) eq lc($artist)) {
			if (!$url || $entry->{year} == $year) {
				warn "Albuminfo: AMG hit: $entry->{album} by $entry->{artist} from year=$entry->{year} ($entry->{url})\n" if $::debug;
				$url = $entry->{url}."/review";
			}
			last if $entry->{year} == $year;
		}
	}
	if ($url) {
		$self->{url} = $url;
		warn "Albuminfo: fetching review from url $url\n" if $::debug;
		::IdleDo('8_albuminfo'.$self,1000, 
				 sub {$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_review(@_)}, url=>$url, cache=>1);});
	} else {
		$self->print_warning(_"No review found");
	}	
}

sub load_review {
	my ($self,$html,$type) = @_;
	delete $self->{waiting};
	$self->{fields} = parse_amg_album_page($html);
	$self->{fields}{url} = $self->{url}; # So that url gets stored if AutoSave is chosen.
	$self->print_review();
	$self->save_review() if $::Options{OPT.'AutoSave'};
	$self->save_fields() if $::Options{OPT.'SaveFields'};
}

sub parse_amg_search_results {
	my ($html,$type) = @_;
	$html = decode($html, $type);
	$html =~ s/\n/ /g;
	# Parsing the html yields @res = (url1, album1, artist1, label1, year1, url2, album2, ...)
	my @res = $html =~ m|<a href="(http://allmusic\.com/album.*?)">(.*?)</a></td>\s.*?<td>(.*?)</td>\s.*?<td>(.*?)</td>\s.*?<td>(.*?)</td>|g;
	my @fields = qw/url album artist label year/;
	my @result;
	push(@result, {%_}) while (@_{@fields} = splice(@res, 0, 5)); # create an array of hash refs
	return \@result;
}

sub parse_amg_album_page {
	my ($html,$type) = @_;
	$html = decode($html, $type);
	$html =~ s|\n| |g;
	my $result = {};
	$result->{author} = $1 if $html =~ m|<p class="author">by (.*?)</p>|;
	$result->{review} = $1 if $html =~ m|<p class="text">(.*?)</p>|;
	if ($result->{review}) {
		$result->{review} =~ s|<br\s.*?/>|\n|gi;	  # Replace newline tags by newlines.
		$result->{review} =~ s|<p\s.*?/>|\n\n|gi;	  # Replace paragraph tags by newlines.
		$result->{review} =~ s|\n{3,}|\n\n|gi;		  # Never more than one empty line.
		$result->{review} =~ s|<.*?>(.*?)</.*?>|$1|g; # Remove the rest of the html tags.
	}
	$result->{rls_date} = $1 if $html =~ m|<h3>Release Date</h3>\s*?<p>(.*?)</p>|;
	$result->{rec_date} = $1 if $html =~ m|<h3>Recording Date</h3>\s*?<p>(.*?)</p>|;
	$result->{label}	= $1 if $html =~ m|<h3>Label</h3>\s*?<p>(.*?)</p>|;
	$result->{type}		= $1 if $html =~ m|<h3>Type</h3>\s*?<p>(.*?)</p>|;
	$result->{time}		= $1 if $html =~ m|<h3>Time</h3>\s*?<p>(.*?)</p>|;
	$result->{amgid}	= $1 if $html =~ m|<p class="amgid">(.*?)</p>|; $result->{amgid} =~ s/R\s*/r/;
	$result->{rating}	= 10*($1+1) if $html =~ m|star_rating\((\d+?)\)|;
	my ($genrehtml)		= $html =~ m|<h3>Genre</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{genre}}) = $genrehtml =~ m|<li><a.*?>\s.*?(.*?)</a></li>|g if $genrehtml;
	my ($stylehtml)		= $html =~ m|<h3>Style</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{Style}}) = $stylehtml =~ m|<li><a.*?>(.*?)</a></li>|g if $stylehtml;
	my ($moodshtml)		= $html =~ m|<h3>Moods</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{mood}})  = $moodshtml =~ m|<li><a.*?>(.*?)</a></li>|g if $moodshtml;
	my ($themeshtml)	= $html =~ m|<h3>Themes</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{Theme}}) = $themeshtml =~ m|<li><a.*?>(.*?)</a></li>|g if $themeshtml;
	return $result;
}

# Get right encoding of html and decode it
sub decode {
	my ($html,$type) = @_;
	my $encoding;
	$encoding = lc($1)	 if ($type && $type =~ m|^text/.*; ?charset=([\w-]+)|);
	$encoding = 'utf-8'	 if ($html =~ m|xml version|);
	$encoding = lc($1)	 if ($html =~ m|<meta.*?charset=[ "]*?([\w-]+)[ "]|);
	$encoding = 'cp1252' if ($encoding && $encoding eq 'iso-8859-1'); #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding ||= 'cp1252'; #default encoding
	$html = Encode::decode($encoding,$html) if $encoding;
	$html = ::decode_html($html) if ($encoding eq 'utf-8');
	return $html;
}	

# Load review from file
sub load_file {
	my ($self,$file) = @_;
	warn "Albuminfo: loading review from file $file\n" if $::debug;
	my $buffer = $self->{buffer};
	$buffer->delete($buffer->get_bounds);
	$self->{fields} = {};
	if ( open(my$fh, '<', $file) ) {
		while (my $line = <$fh>) {
			if (my $utf8 = Encode::decode_utf8($line)) {$line = $utf8}
			my ($key,$val) = $line =~ m|<(.*?)>(.*?)<.*|;
			if ($key && $val) {
				if ($key =~ m/genre|mood|Style|Theme/) {
					@{$self->{fields}{$key}} = split(', ', $val);
				} else {
					$self->{fields}{$key} = $val;
				}
			}
		}
		close $fh;
	}
	$self->print_review();
	$self->save_fields() if $::Options{OPT.'SaveFields'}; # We may not have saved when first downloaded.
}


# Save review to file.
# The format of the file is: <field>values</field>
sub save_review {
	my $self = ::find_ancestor($_[0],__PACKAGE__);
	my $text = "";
	for my $key (sort keys %{$self->{fields}}) {
		if ($key =~ m/genre|mood|Style|Theme/) {
			$text = $text . "<$key>".join(", ", @{$self->{fields}{$key}})."</$key>\n";
		} else {
			$text = $text . "<$key>".$self->{fields}{$key}."</$key>\n";
		}
	}
	my $format = $::Options{OPT.'PathFile'};
	my ($path,$file) = ::pathfilefromformat( ::GetSelID($self), $format, undef, 1 );
	my $win = $self->get_toplevel;
	unless ($path && $file) {::ErrorMessage(_"Error: invalid filename pattern"." : $format",$win); return}
	my $res = ::CreateDir($path,$win);
	return unless $res eq 'ok';
	if ( open(my$fh, '>:utf8', $path.$file) ) {
		print $fh $text;
		close $fh;
		$self->{buffer}->set_modified(0);
		warn "Albuminfo: Saved review in ".$path.$file."\n" if $::debug;
	} else {
		::ErrorMessage(::__x(_"Error saving review in '{file}' :\n{error}", file => $file, error => $!),$win);
	}
}

# Save selected fields (moods, styles etc.) for all tracks in album
sub save_fields {
	my ($self) = @_;
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	my $IDs = Songs::MakeFilterFromGID('album', $aID)->filter(); # Songs on this album
	for $ID (@{$IDs}) {
		my @updated_fields;
		for my $key (keys %{$self->{fields}}) {
			if ($key =~ m/mood|Style|Theme/ && $::Options{OPT.$key}) {
				my @newvals;
				if ( $::Options{OPT.'ReplaceFields'} ) {
					@newvals = @{$self->{fields}->{$key}};
				} else {
					@newvals = keys %{{ map { $_ => 1 } (::Songs::Get_list($ID, $key), @{$self->{fields}->{$key}}) }}; # merge and remove duplicates
				}
				push(@updated_fields, $key, \@newvals) if @newvals;
			}		
		}
		Songs::Set($ID, \@updated_fields) if @updated_fields;
	}
}

# Cancel pending tasks, and abort possible http_wget in progress.
sub cancel {
	my $self = shift;
	delete $::ToDo{'8_albuminfo'.$self};
	$self->{waiting}->abort() if $self->{waiting};
}

1

