# Copyright (C) 2011 Øystein Tråsdahl
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin ALBUMINFO
name	Albuminfo
title	Albuminfo plugin
version	0.2
author  Øystein Tråsdahl (based on the Artistinfo plugin)
desc	Retrieves album-relevant information (review etc.) from allmusic.com.
=cut

# TODO:
# - Create local links in the review that can be used for contextmenus and filtering.
# - Consider searching google instead, or add google search if amg fails.

package GMB::Plugin::ALBUMINFO;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use base 'Gtk3::Box';
use constant
{	OPT	=> 'PLUGIN_ALBUMINFO_',
	AMG_SEARCH_URL => 'http://www.allmusic.com/search/album/',
	AMG_ALBUM_URL => 'http://www.allmusic.com/album/',
};

my @showfields =
(	{short => 'rec_date',	long => _"Recording date",	active => 1,	multi => 0,	defaultshow => 1},
	{short => 'rls_date',	long => _"Release date",	active => 1,	multi => 0,	defaultshow => 1},
	{short => 'time',	long => _"Running time",	active => 0,	multi => 0,	defaultshow => 0},
	{short => 'rating',	long => _"Rating",		active => 1,	multi => 0,	defaultshow => 1},
	{short => 'genre',	long => _"Genres",		active => 1,	multi => 1,	defaultshow => 0},
	{short => 'mood',	long => _"Moods",		active => 1,	multi => 1,	defaultshow => 0},
	{short => 'style',	long => _"Styles",		active => 1,	multi => 1,	defaultshow => 0},
	{short => 'theme',	long => _"Themes",		active => 1,	multi => 1,	defaultshow => 0},
);

::SetDefaultOptions(OPT, PathFile  	=> "~/.config/gmusicbrowser/review/%a - %l.txt",
			 ShowCover	=> 1,
			 CoverSize	=> 100,
			 StyleAsGenre	=> 0,
			 mass_download	=> 'missing',
);
::SetDefaultOptions(OPT, 'Show'.$_->{short} => $_->{defaultshow}) for (@showfields);
delete $::Options{OPT.'Column'.$_} for 0..3; #remove old column options

my $albuminfowidget =
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-albuminfo',
	tabtitle	=> _"Albuminfo",
	schange		=> sub { $_[0]->song_changed },
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};

my %Columns=
(	album	=> { name=> _"Album",				storecol=>0, width=>130, },
	artist	=> { name=> _"Artist",				storecol=>1, width=>130, },
	genre	=> { name=> _"Genre",				storecol=>2, width=>110, },
	year	=> { name=> _"Year",				storecol=>3, width=>50, },
);

my @towrite;              # Needed to avoid progress bar overflow in save_fields when called from mass_download
my $save_fields_lock = 0; # Needed to avoid progress bar overflow in save_fields when called from mass_download

sub Start {
	Layout::RegisterWidget(PluginAlbuminfo => $albuminfowidget);
}

sub Stop {
	Layout::RegisterWidget(PluginAlbuminfo => undef);
}

sub prefbox {
	my $frame_cover  = Gtk3::Frame->new(' '._("Album cover").' ');
	my $spin_picsize = ::NewPrefSpinButton(OPT.'CoverSize',50,500, step=>5, page=>10, text=>_"Cover Size : ", cb=>sub { ::HasChanged('plugin_albuminfo_option_pic'); } );
	my $chk_picshow  = ::NewPrefCheckButton(OPT.'ShowCover'=>_"Show", widget => $spin_picsize, cb=>sub { ::HasChanged('plugin_albuminfo_option_pic'); });
	# my $btn_amg      = ::NewIconButton('plugin-artistinfo-allmusic',undef, sub {::main::openurl("http://www.allmusic.com/"); },'none',_"Open allmusic.com in your web browser");
	# my $hbox_picsize = ::Hpack($spin_picsize, '-', $btn_amg);
	$frame_cover->add($chk_picshow);

	my $frame_review = Gtk3::Frame->new(_" Review ");
	my $entry_path   = ::NewPrefEntry(OPT.'PathFile' => _"Save album info in:", width=>40);
	my $lbl_preview  = Label::Preview->new(event=>'CurSong Option', noescape=>1, wrap=>1, preview=>sub
	{	return '' unless defined $::SongID;
		my $t = ::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
		$t = ::filename_to_utf8displayname($t) if $t;
		$t = $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
		return '<small>'.$t.'</small>';
	});
	my $chk_autosave = ::NewPrefCheckButton(OPT.'AutoSave'=>_"Auto-save positive finds", cb=>sub { ::HasChanged('plugin_albuminfo_option_save'); });
	$frame_review->add(::Vpack($entry_path,$lbl_preview,$chk_autosave));

	my $frame_fields = Gtk3::Frame->new(_" Fields ");
	my $chk_join = ::NewPrefCheckButton(OPT.'StyleAsGenre' => _"Include Styles in Genres", tip=>_"Allmusic uses both Genres and Styles to describe albums. If you use only Genres, you may want to include Styles in allmusic's list of Genres.");
	my @chk_fields;
	for my $field (qw(genre mood style theme)) {
		push(@chk_fields, ::NewPrefCheckButton(OPT.$field=>_(ucfirst($field)."s"), tip=>_"Note: inactive fields must be enabled by the user in the 'Fields' tab in Settings"));
		$chk_fields[-1]->set_sensitive(0) unless Songs::FieldEnabled($field);
	}
	my ($radio_add,$radio_rpl) = ::NewPrefRadio(OPT.'ReplaceFields',[_"Add to existing values",1, _"Replace existing values",0]);
	my $chk_saveflds = ::NewPrefCheckButton(OPT.'SaveFields'=>_"Auto-save fields with data from allmusic", widget=>::Vpack(\@chk_fields, $radio_add, $radio_rpl),
		tip=>_"Save selected fields for all tracks on the same album whenever album data is loaded from allmusic or from file.");
	$frame_fields->add(::Vpack($chk_join, $chk_saveflds));

	my $frame_layout = Gtk3::Frame->new(_" Context pane layout ");
	my @chk_show = ();
	for my $f (@showfields) {
		push(@chk_show, ::NewPrefCheckButton(OPT.'Show'.$f->{short} => $f->{long})) if $f->{active};
	}
	$frame_layout->add(::Hpack(@chk_show));

	my $btn_download = Gtk3::Button->new(_"Download");
	$btn_download->set_tooltip_text(_"Fields will be saved according to the settings above. Albuminfo files will be re-read if there are fields to be saved and you choose 'albums missing reviews' in the combo box.");
	my $cmb_download = ::NewPrefCombo(OPT.'mass_download',  {all=>_"entire collection", missing=>_"albums missing reviews"}, text=>_"album information now for");
	$btn_download->signal_connect(clicked => \&mass_download);
	return ::Vpack($frame_cover, $frame_review, $frame_fields, $frame_layout, [$btn_download,$cmb_download]);
}

sub mass_download {
	my $self = bless {}; # the context widget was meant to be used as self in methods of this plugin, but when downloading all there is no gtk widget to use. Using a blessed hash instead should work as well as long as no gtk2 function is used on it
	$self->{aIDs} = Songs::Get_all_gids('album');
	$self->{end} = scalar(@{$self->{aIDs}});
	$self->{progress} = 0;
	$self->{abort} = 0;
	::Progress('albuminfo', end=>$self->{end}, aborthint=>_"Stop fetching albuminfo", title=>_"Fetching albuminfo",
		abortcb=>sub {$self->cancel}, bartext=>'$current / $end', );
	::IdleDo('9_download_one'.$self, undef, \&download_one, $self);
}

sub download_one {
	my ($self) = @_;
	::Progress('albuminfo', current=>$self->{progress}, );
	return if $self->{progress} >= $self->{end} || $self->{abort};
	my $aID = $self->{aIDs}->[$self->{progress}++];
	warn "Albuminfo: mass download in progress... $self->{progress}/$self->{end}\n" if $::debug;
	my $IDs = Songs::MakeFilterFromGID('album',$aID)->filter();
	my $ID  = $IDs->[0]; # Need a track (any track) from the album: pick the first in the list.
	my $album = Songs::Get($ID, 'album');
	unless ($album) {::IdleDo('9_download_one'.$self, undef, \&download_one, $self); return}
	my $file = ::pathfilefromformat($ID, $::Options{OPT.'PathFile'}, undef, 1);
	if ($::Options{OPT.'mass_download'} ne 'all' && $file && -r $file) {
		if ($::Options{OPT.'SaveFields'}) {
			::IdleDo('9_load_albuminfo'.$self,undef,\&load_file,$self,$ID,$file,1,\&download_one);
		} else {
			::IdleDo('9_download_one'.$self, undef, \&download_one, $self);
		}
	} else {
		my $url = AMG_SEARCH_URL.::url_escapeall($album);
		warn "Albuminfo: fetching search results from $url\n" if $::debug;
		$self->{waiting} = Simple_http::get_with_cb(url=>$url, cache=>1, cb=>sub {$self->load_search_results($ID,1,\&download_one,@_)});
	}
}



#####################################################################
#
# Section: albuminfowidget (the Context pane tab).
#
#####################################################################
sub new {
	my ($class,$options) = @_;
	my $self= bless Gtk3::VBox->new(0,0), $class;
	$self->{$_} = $options->{$_} for qw/group/;
	$self->{fontsize}= 12;		#FIXME 2TO3 find a way to get default size
	$self->{alt_color}= 'grey';	#FIXME 2TO3 find a way to get a good color

	# Heading: cover and album info.
	my $cover= Gtk3::HBox->new(0,0);
	my $group=$options->{group};
	my $cover_create= sub
	{	my $box=shift;
		$box->remove($_) for $box->get_children;
		return unless $::Options{OPT.'ShowCover'};
		my $child = Layout::NewWidget("Cover", {group=>$group, forceratio=>1, maxsize=>$::Options{OPT.'CoverSize'},
			xalign=>0, tip=>_"Click to show larger image", click1=>\&cover_popup,
			click3=>sub {::PopupAAContextMenu({self=>$_[0], field=>'album', ID=>$::SongID, gid=>Songs::Get_gid($::SongID,'album'), mode=>'P'});} });
		$child->show_all;
		$box->add($child);
	};
	::Watch($cover, plugin_albuminfo_option_pic=> $cover_create);
	$cover_create->($cover);

	my $statbox= Gtk3::VBox->new(0,0);
	for my $name (qw/Ltitle Lstats/) {
		my $l= Gtk3::Label->new('');
		$self->{$name} = $l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1); $l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{ratingpic}= Gtk3::Image->new;
	$statbox->pack_start($self->{ratingpic},0,0,2);

	# "Refresh", "save" and "search" buttons
	my $refreshbutton = ::NewIconButton('view-refresh-symbolic', undef, sub { song_changed($_[0],'force'); }, "none", _"Refresh");
	my $savebutton	  = ::NewIconButton('document-save-symbolic', undef, sub
		{my $self= $_[0]->GET_ancestor; save_review(::GetSelID($self),$self->{fields})}, "none", _"Save review");
	$savebutton->show_all;
	$savebutton->set_no_show_all(1);
	my $update_savebutton_visible= sub { $_[0]->set_visible( !$::Options{OPT.'AutoSave'} ); };
	::Watch( $savebutton, plugin_albuminfo_option_save=> $update_savebutton_visible);
	$update_savebutton_visible->($savebutton);

	my $searchbutton= Gtk3::ToggleButton->new;
	$searchbutton->set_relief('none');
	$searchbutton->add(Gtk3::Image->new_from_stock('edit-find-symbolic','menu'));
	$searchbutton->signal_connect(clicked => sub {my $self= $_[0]->GET_ancestor;
		if ($_[0]->get_active()) {$self->manual_search()} else {$self->song_changed()}});
	my $buttonbox= Gtk3::HBox->new;
	$buttonbox->pack_end($searchbutton,0,0,0);
	$buttonbox->pack_end($savebutton,0,0,0);
	$buttonbox->pack_end($refreshbutton,0,0,0);
	$statbox->pack_end($buttonbox,0,0,0);
	my $stateventbox= Gtk3::EventBox->new; # To catch mouse events
	$stateventbox->add($statbox);
	$stateventbox->{group}= $options->{group};
	$stateventbox->signal_connect(button_press_event => sub {my ($stateventbox, $event) = @_; return 0 unless $event->button == 3; my $ID = ::GetSelID($stateventbox);
		 ::PopupAAContextMenu({ self=>$stateventbox, mode=>'P', field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album') }) if defined $ID; return 1; } );
	my $coverstatbox= Gtk3::HBox->new(0,0);
	$coverstatbox->pack_start($cover,0,0,0);
	$coverstatbox->pack_end($stateventbox,1,1,5);

	# For the review: a TextView in a ScrolledWindow in a HBox
	my $textview= Gtk3::TextView->new;
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
	$textview->signal_connect(query_tooltip		  => \&update_cursor_cb);
	my $sw= Gtk3::ScrolledWindow->new;
	$sw->add($textview);
	$sw->set_shadow_type('none');
	$sw->set_policy('automatic','automatic');
	my $infoview= Gtk3::HBox->new;
	$infoview->set_spacing(0);
	$infoview->pack_start($sw,1,1,0);
	$infoview->show_all();

	# Manual search layout
	my $searchview= Gtk3::VBox->new;
	$self->{search}= my $search  = Gtk3::Entry->new;
	$search->set_tooltip_text(_"Enter album name");
	my $Bsearch = ::NewIconButton('edit-find-symbolic', _"Search");
	my $Bok     = Gtk3::Button->new_from_stock('dialog-ok');
	my $Bcancel = Gtk3::Button->new_from_stock('dialog-cancel');
	$Bok    ->set_size_request(80, -1);
	$Bcancel->set_size_request(80, -1);
	# Year is a 'Glib::String' to avoid printing "0" when year is missing. Caveat: will give wrong sort order for albums released before year 1000 or after year 9999 :)
	my $store= Gtk3::ListStore->new(('Glib::String')x5,'Glib::UInt'); # Album, Artist, Label, Year, URL, Sort order.
	my $treeview= Gtk3::TreeView->new($store);
	my %coladded;
	for my $col ( split(/\s+/,$::Options{OPT.'Columns'}||''), qw/album artist genre year/ )
	{	my $coldef= $Columns{$col};
		next unless $coldef;
		next if $coladded{$col}++; #only add a column once
		my $colopt= $::Options{OPT.'Column_'.$col} || {};
		my $column= Gtk3::TreeViewColumn->new_with_attributes($coldef->{name}, Gtk3::CellRendererText->new, text=>$coldef->{storecol});
		$column->{key}=$col;
		$column->set_sort_column_id($coldef->{storecol}); $column->set_expand(1); $column->set_resizable(1); $column->set_reorderable(1);
		$column->set_sizing('fixed');
		$column->set_fixed_width( $colopt->{width}||$coldef->{width}||100 );
		$column->set_visible(!$colopt->{hide});
		$treeview->append_column($column);
		# Recreate the header label to be able to catch mouse clicks in column header:
		my $label= Gtk3::Label->new($coldef->{name}); $column->set_widget($label); $label->show;
		my $button= $label->get_ancestor('Gtk3::Button'); # The header label is attached to a button by Gtk
		$button->signal_connect(button_press_event => \&treeview_click_cb, $col) if $button;
	}
	$treeview->set_rules_hint(1);
	$treeview->signal_connect(row_activated => \&entry_selected_cb);
	my $scrwin= Gtk3::ScrolledWindow->new;
	$scrwin->set_policy('automatic', 'automatic');
	$scrwin->add($treeview);
	$searchview->add( ::Vpack(['_', $search, $Bsearch],
				  '_',  $scrwin,
				  '-',  ['-', $Bcancel, $Bok]) );
	$search ->signal_connect(activate => \&new_search ); # Pressing Enter in the search entry.
	$Bsearch->signal_connect(clicked  => \&new_search );
	$Bok    ->signal_connect(clicked  => \&entry_selected_cb );
	$Bcancel->signal_connect(clicked  => \&song_changed );
	$scrwin ->signal_connect(key_press_event => sub {
		my ($scrwin,$event)=@_;
		my $key= Gtk3::Gdk::keyval_name( $event->keyval );
		if ($key eq 'Return') { entry_selected_cb($scrwin) }
		elsif ($key eq 'Escape') { song_changed($scrwin) }
		});
	$searchview->show_all(); # Must call it once now before $searchview->set_no_show_all(1) disables it.
	$searchview->set_no_show_all(1); # GMB sometimes calls $plugin->show_all(). We then want only infoview to show.
	$searchview->hide();

	# Pack it all into self (a VBox)
	$self->pack_start($coverstatbox,0,0,0);
	$self->pack_start($infoview,1,1,0);
	$self->pack_start($searchview,1,1,0);
	$searchview->signal_connect(show => sub {$searchbutton->set_active(1)});
	$searchview->signal_connect(hide => sub {$searchbutton->set_active(0)});
	$self->signal_connect(destroy => sub {$_[0]->cancel()});

	# Save elements that will be needed in other methods.
	$self->{buffer} = $textview->get_buffer();
	$self->{treeview} = $treeview;
	$self->{infoview} = $infoview;
	$self->{searchview} = $searchview;
	$self->{SaveOptions}= \&SaveOptions; #called when widget is removed or when saving options
	return $self;
}


sub SaveOptions {
	my $self = shift;
	my @cols= $self->{treeview}->get_columns;
	$::Options{OPT.'Columns'}= join ' ', map $_->{key}, @cols;
	for my $col (@cols) {
		my $colopt= $::Options{OPT.'Column_'.$col->{key}}= {};
		$colopt->{width}= $col->get_width;
		$colopt->{hide}=1 if !$col->get_visible;
	}
}

# Called when headers in the results table in manual search are clicked
sub treeview_click_cb {
	my ($button, $event, $colid) = @_;
	my $treeview = $button->get_parent;
	if ($event->button == 1) {
		my ($sortid,$order) = $treeview->get_model->get_sort_column_id();
		my $storecol= $Columns{$colid}{storecol};
		if ($sortid == $storecol && $order eq 'descending') {
			$treeview->get_model->set_sort_column_id(5,'ascending'); # After third click on column header: return to AMG sort order (default).
			return ::TRUE;
		}
	} elsif ($event->button == 3) {
		my $menu=::BuildChoiceMenu( { map { ($_=>$Columns{$_}{name}) } keys %Columns }, #hash of colkey => name
					reverse=>1,
					args => {treeview=>$treeview},
					check=> sub { [map $_->{key}, grep $_->get_visible, $_[0]{treeview}->get_columns]; }, #list of visible columns
					code => sub {
						my ($args,$key)=@_;
						my @cols= $args->{treeview}->get_columns;
						my ($col)= grep $_->{key} eq $key, @cols;
						$col->set_visible( !$col->get_visible ) if $col;
						$cols[0]->set_visible(1) unless grep $_->get_visible, @cols; #make sure one column is visible
					},
			);
		$menu->show_all;
		$menu->popup(undef,undef,undef,undef,$event->button,$event->time);
		return ::TRUE;
	}
	return ::FALSE; # Let Gtk handle it
}

sub update_cursor_cb {
	my $textview = $_[0];
	my (undef,$wx,$wy,undef) = $textview->get_window('text')->get_pointer();
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter = $textview->get_iter_at_location($x,$y);
	my $cursor = 'xterm';
	for my $tag ($iter->get_tags()) {
		$cursor = 'hand2' if $tag->{tip};
		$textview->set_tooltip_text($tag->{tip} || '');
	}
	return if ($textview->{cursor} || '') eq $cursor;
	$textview->{cursor} = $cursor;
	$textview->get_window('text')->set_cursor(Gtk3::Gdk::Cursor->new($cursor));
}

# Mouse button pressed in textview. If link: open url in browser.
sub button_release_cb {
	my ($textview,$event) = @_;
	my $self = $textview->GET_ancestor;
	return ::FALSE unless $event->button == 1;
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $iter = $textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags) {
		if ($tag->{url}) {
			::main::openurl($tag->{url});
			last;
		} elsif ($tag->{field}) {
			my $field= $tag->{field} eq 'year' ? 'year' : '+'.$tag->{field}; # prepend + for multi-value fields : Genre, Mood, Style, Theme
			my $aID = Songs::Get_gid(::GetSelID($self),'album');
			Songs::Set(Songs::MakeFilterFromGID('album', $aID)->filter(), [$field => $tag->{val}]);
		}
	}
	return ::FALSE;
}

sub cover_popup {
	my ($self,$event)= @_;
	my $picsize = 400;
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	if (my $img = AAPicture::newimg(album=>$aID,$picsize)) {
		$img->override_background_color('normal', Gtk3::Gdk::RGBA::parse('black'));
		$img->show;
		my $popover= Gtk3::Popover->new($self);
		$popover->add($img);
		$popover->popup;
	}
	return 1;
}

# Print warnings in the text buffer
sub print_warning {
	my ($self,$text) = @_;
	my $buffer = $self->{buffer};
	$buffer->set_text("");
	my $iter = $buffer->get_start_iter();
	my $fontsize = $self->{fontsize};
	my $tag_noresults = $buffer->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground=>$self->{alt_color});
	$buffer->insert_with_tags($iter,"\n$text",$tag_noresults);
	$buffer->set_modified(0);
}

# Print review (and additional data) in the text buffer
sub print_review {
	my ($self) = @_;
	unless ($self->{fields}{url}) {$self->print_warning(_"No review found"); return}
	my $buffer = $self->{buffer};
	my $fields = $self->{fields};
	$buffer->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_h2 = $buffer->create_tag(undef, font=>$fontsize+1, weight=>::PANGO_WEIGHT_BOLD);
	my $tag_b  = $buffer->create_tag(undef, weight=>::PANGO_WEIGHT_BOLD);
	my $tag_i  = $buffer->create_tag(undef, style=>'italic');
	my $iter = $buffer->get_start_iter();

	for my $f (@showfields) {
		if ($fields->{$f->{short}} && $::Options{OPT.'Show'.$f->{short}} && $f->{active}) {
			$buffer->insert_with_tags($iter, "$f->{long}:  ",$tag_b);
			if ($f->{multi}) { # genres, moods, styles and themes.
				my @old = Songs::Get_list(::GetSelID($self), $f->{short});
				my @amg = @{$fields->{$f->{short}}};
				my $i = 0;
				for my $val (@amg) {
					if (grep {lc($_) eq lc($val)} @old) {
						$buffer->insert($iter, $val);
					} else { # val doesn't exist in local db => create link to save it.
						my $tag  = $buffer->create_tag(undef, foreground=>"#4ba3d2", underline=>'single');
						$tag->{field} = $f->{short}; $tag->{val} = $val;
						$tag->{tip} = ::__x( _"Add {value} to {field} for all tracks on this album.", value=>$val, field=> lc($f->{long}));
						$buffer->insert_with_tags($iter, $val, $tag);
					}
					$buffer->insert($iter,", ") if ++$i < scalar(@amg);
				}
			} elsif ($f->{short} eq 'rls_date') {
				$fields->{rls_date} =~ m|(\d{4})|;
				if (defined $1 && $1 != Songs::Get(::GetSelID($self), 'year')) { # AMG year differs from local year => create link to correct.
					my $tag  = $buffer->create_tag(undef, foreground=>"#4ba3d2", underline=>'single');
					$tag->{field} = 'year'; $tag->{val} = $1;
					$tag->{tip} = ::__x( _"Set {year} as year for all tracks on this album.", year=>$1 );
					$buffer->insert_with_tags($iter, $fields->{rls_date}, $tag);
				} else {
					$buffer->insert($iter,"$fields->{rls_date}");
				}
			} elsif ($f->{short} eq 'rating') {
				$buffer->insert_pixbuf($iter, Songs::Stars($fields->{rating}, 'rating'));
			} else {
				$buffer->insert($iter,"$fields->{$f->{short}}");
			}
			$buffer->insert($iter, "\n");
		}
	}

	if ($fields->{review}) {
		$buffer->insert_with_tags($iter, "\n"._("Review")."\n", $tag_h2);
		$buffer->insert_with_tags($iter, ::__x(_"by {author}", author=>$fields->{author})."\n", $tag_i);
		$buffer->insert($iter,$fields->{review});
	} else {
		$buffer->insert_with_tags($iter,"\n"._("No review written.")."\n",$tag_h2);
	}
	$buffer->insert($iter, "\n\n");
	my $tag_a  = $buffer->create_tag(undef, foreground=>"#4ba3d2", underline=>'single');
	$tag_a->{url} = $fields->{url}; $tag_a->{tip} = $fields->{url};
	$buffer->insert_with_tags($iter,_"Lookup at allmusic.com",$tag_a);
	$buffer->set_modified(0);
}



#####################################################################
#
# Section: "Manual search" window.
#
#####################################################################
sub manual_search {
	my $self = shift;
	$self->{infoview}->hide();
	$self->{searchview}->show();
	my $gid = Songs::Get_gid(::GetSelID($self), 'album');
	$self->{search}->set_text(Songs::Gid_to_Get('album', $gid));
	$self->new_search();
}

sub new_search {
	my $self = $_[0]->GET_ancestor; # $_[0] can be a button or gtk-entry. Ancestor is an albuminfo object.
	my $album = $self->{search}->get_text();
	$album =~ s|^\s+||; $album =~ s|\s+$||; # remove leading and trailing spaces
	return if $album eq '';
	my $url = AMG_SEARCH_URL.::url_escapeall($album);
	$self->cancel();
	$self->{treeview}->get_model->clear;
	warn "Albuminfo: fetching search results from $url.\n" if $::debug;
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->print_results(@_)},url=>$url, cache=>1);
}

sub print_results {
	my ($self,$html,%prop) = @_;
	delete $self->{waiting};
	my $result = parse_amg_search_results($html, $prop{type}); # result is a ref to an array of hash refs
	my $store= $self->{treeview}->get_model;
	$store->set_sort_column_id(5, 'ascending');
	for (@$result) {
		$store->set($store->append, 0,$_->{album}, 1,$_->{artist}, 2,$_->{genres}, 3,$_->{year}, 4,$_->{url}, 5,$_->{order});
	}
}

sub entry_selected_cb {
	my $self = $_[0]->GET_ancestor; # $_[0] may be the TreeView or the 'OK' button. Ancestor is an albuminfo object.
	my ($path, $column) = $self->{treeview}->get_cursor();
	unless (defined $path) {$self->{searchview}->hide(); $self->{infoview}->show(); return} # The user may click OK before selecting an album
	my $store = $self->{treeview}->get_model;
	my $url = $store->get($store->get_iter($path),4);
	warn "Albuminfo: fetching review from $url\n" if $::debug;
	$self->cancel();
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->{searchview}->hide(); $self->{infoview}->show();
		$self->load_review(::GetSelID($self),0,undef,$url,@_)}, url=>$url, cache=>1);
}



#####################################################################
#
# Section: loading and parsing review. Saving review and fields.
#
#####################################################################
sub song_changed {
	my ($widget,$force) = @_;
	my $self = $widget->GET_ancestor;
	return unless $self->get_mapped || $::Options{OPT.'SaveFields'};
	$self->{infoview}->show();
	$self->{searchview}->hide();
	my $ID = ::GetSelID($self);
	return unless defined $ID;
	my $aID = Songs::Get_gid($ID,'album');
	return unless $aID;
	if (!$self->{aID} || $aID != $self->{aID} || $force) { # Check if album has changed or a forced update is required.
		$self->{aID} = $aID;
		$self->{album} = Songs::Gid_to_Get("album",$aID);
		$self->album_changed($ID, $aID, $force);
	} else { # happens for example when song properties are edited, so we need to repaint the widget.
	        ::IdleDo('9_refresh_albuminfo'.$self, undef, sub { $self->update_titlebox($aID); length($self->{album}) ? $self->print_review() : $self->print_warning(_"Unknown album") });
	}
}

sub album_changed {
	my ($self,$ID,$aID,$force) = @_;
	$self->cancel();
	$self->update_titlebox($aID);
	my $album = ::url_escapeall(Songs::Gid_to_Get("album",$aID));
	unless (length($album)) {$self->print_warning(_"Unknown album"); return}
	my $url = AMG_SEARCH_URL.$album;
	$self->print_warning(_"Loading...");
	unless ($force) { # Try loading from file.
		my $file = ::pathfilefromformat( ::GetSelID($self), $::Options{OPT.'PathFile'}, undef, 1 );
		if ($file && -r $file) {
			::IdleDo('9_load_albuminfo'.$self,undef,\&load_file,$self,$ID,$file,0,undef);
			return;
		}
	}
	warn "Albuminfo: fetching search results from $url\n" if $::debug;
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_search_results($ID,0,undef,@_)}, url=>$url, cache=>1);
}

sub update_titlebox {
	my ($self,$aID) = @_;
	my $rating = AA::Get("rating:average",'album',$aID);
	$self->{rating} = int($rating+0.5);
	$self->{ratingrange} = AA::Get("rating:range", 'album',$aID);
	$self->{playcount}   = AA::Get("playcount:sum",'album',$aID);
	my $tip = join("\n",	_("Average rating:")	.' '.$self->{rating},
				_("Rating range:")	.' '.$self->{ratingrange},
				_("Total playcount:")	.' '.$self->{playcount});
	$self->{ratingpic}->set_from_pixbuf(Songs::Stars($self->{rating},'rating'));
	$self->{Ltitle}->set_markup( AA::ReplaceFields($aID,"<big><b>%a</b></big>","album",1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($aID,'%b « %y\n%s, %l',"album",1) );
	for my $name (qw/Ltitle Lstats/) { $self->{$name}->set_tooltip_text($tip); }
}

sub load_search_results {
	my ($self,$ID,$md,$cb,$html,%prop) = @_; # $md = 1 if mass_download, 0 otherwise. $cb = callback function if mass_download, undef otherwise.
	delete $self->{waiting};
	my $result = parse_amg_search_results($html, $prop{type}); # $result[$i] = {url, album, artist, genres, year}
	my ($artist,$year) = ::Songs::Get($ID, qw/artist year/);
	my $url;
	for my $entry (@$result) {
		# Pick the first entry with the right artist and year, or if not: just the right artist.
		if (::superlc($entry->{artist}) eq ::superlc($artist)) {
			if (!$url || ($entry->{year} && $entry->{year} == $year)) {
				warn "Albuminfo: hit in search results: $entry->{album} by $entry->{artist} from $entry->{year} ($entry->{url})\n" if $::debug;
				$url = $entry->{url};
			}
			last if $year && $entry->{year} && $entry->{year} == $year;
		}
	}
	if ($url) {
		warn "Albuminfo: fetching review from $url\n" if $::debug;
		$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_review($ID,$md,$cb,$url,@_)}, url=>$url, cache=>1);
	} else {
		$self->{fields} = {};
		warn "Albuminfo: album not found in search results\n" if $::debug;
		$self->print_warning(_"No review found") unless $md;
		::IdleDo('9_download_one'.$self, undef, $cb, $self) if $cb;
	}	
}

sub load_review {
	my ($self,$ID,$md,$cb,$url,$html,%prop) = @_;
	delete $self->{waiting};
	$self->{fields} = parse_amg_album_page($url,$html,$prop{type});
	$self->print_review() unless $md;
	save_review($ID, $self->{fields}) if $::Options{OPT.'AutoSave'} || $md;
	if ($::Options{OPT.'SaveFields'}) {push(@towrite, [$ID, %{$self->{fields}}]); save_fields()}
	::IdleDo('9_download_one'.$self, undef, $cb, $self) if $cb;
}

sub parse_amg_search_results {
	my ($html,$type) = @_;
	$html = decode($html, $type);
	$html =~ s/\n/ /g;
	# Parsing the html yields (url, album, artist, year, genres) for each album

	my $i = 0; # Used to sort the hits in manual search
	my @result;
	for my $info (split /<div class="info"/,$html) {
		my ($url,$album)= $info=~m#<div class="title".*<a href="(http://www\.allmusic\.com/album/[^"]+)"[^>]*>([^<]+)#i;
		next unless defined $url;
		my %hash=( order=>$i++, album=>$album, url=>$url);
		for my $field (qw/artist year genres/) {
			my ($value)= $info=~m#<div class="$field"[^>]*>\s*(.*?)\s*</div>#i;
			next unless defined $value;
			$value=~s#<[^>]*>\s*##g;
			$hash{$field}=$value;
		}
		push @result, \%hash; # create an array of hash refs
	}
	return \@result;
}

sub parse_amg_album_page {
	my ($url,$html,$type) = @_;
	$html =~ s|\n||g;
	my %result;
	$result{url} = $url;
	$result{author} = $1 if $html =~ m|class="review-author headline">[^<]*by <span itemprop="author">(.*?)</span>|i;
	if ($html =~ m|<div class="text" itemprop="reviewBody">(.*?)</div>|i){
		$result{review} = $1;
		for ($result{review}) {
			s/^(?:<p>|\s+)*//i;	# remove leading spaces/newlines
			s|<br\s.*?/>|\n|gi;	# Replace newline tags by newlines.
			s|</?p>|\n|gi;		# Replace paragraph tags by newlines.
			s|\n\n+|\n|gi;		# Never more than one empty line.
			s|<.*?>(.*?)</.*?>|$1|g; # Remove the rest of the html tags.
		}
	}
	$result{rls_date}	= $1 if $html =~ m|class="release-date">\s*<h\d>Release Date</h\d>\s*<span>([^<]+)</span>|i;
	$result{rec_date}	= $1 if $html =~ m|class="recording-date">\s*<h\d>Recording Date</h\d>\s*<span>([^<]+)</span>|i;
	$result{time}		= $1 if $html =~ m|class="duration">\s*<h\d>Duration</h\d>\s*<span>([^<]+)</span>|i;
	$result{amgid}		= $1 if $html =~ m|AMG Pop ID.*?R\s*(\d+)\s*</span>|i;
	$result{rating}		= 10*$1 if $html =~ m|<div class="allmusic-rating rating-allmusic-7" itemprop="ratingValue">\s*(\d+)\s*</div>|i;
	my ($genrehtml)		= $html =~ m|class="genres?">\s*<h\d>Genres?</h\d>\s*<div>(.*?)</div>|i;
	(@{$result{genre}})	= $genrehtml =~ m|<a href="[^"]+">([^<]+)</a>|ig if $genrehtml;
	my ($stylehtml)		= $html =~ m|class="styles">\s*<h\d>Styles</h\d>\s*<div>(.*?)</div>|i;
	(@{$result{style}})	= $stylehtml =~ m|<a href="[^"]+">([^<]+)</a>|ig if $stylehtml;
	my ($moodshtml)		= $html =~ m|class="moods">\s*<h\d>Album Moods</h\d>\s*<div>(.*?)</div>|i;
	(@{$result{mood}})	= $moodshtml =~ m|<a href="[^"]+">([^<]+)</a>|ig if $moodshtml;
	my ($themeshtml)	= $html =~ m|class="themes">\s*<h\d>Themes</h\d>\s*<div>(.*?)</div>|i;
	(@{$result{theme}})	= $themeshtml =~ m|<a href="[^"]+">([^<]+)</a>|ig if $themeshtml;

	#convert values from html
	for my $value (values %result){
		if (ref $value) { @$value= map decode($_,$type), @$value; }
		else { $value=decode($value,$type); }
	}
	#DEBUG : print values
	#for (sort keys %result){
	#	next if $_ eq 'review';
	#	my $v=$result{$_};
	#	if (ref $v) {warn "$_ : ".join(" -- ",@$v)."\n"}
	#	else {warn "$_ : $v\n"}
	#}

	if ($::Options{OPT.'StyleAsGenre'} && $result{style}) {@{$result{genre}} = ::uniq(@{$result{style}}, @{$result{genre}})}
	return \%result;
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
	my ($self,$ID,$file,$md,$cb) = @_;
	$self->{fields} = {};
	if ( open(my$fh, '<', $file) ) {
		warn "Albuminfo: loading review from file $file\n" if $::debug;
		local $/ = undef; #slurp mode
		my $text = <$fh>;
		if (my $utf8 = Encode::decode_utf8($text)) {$text = $utf8}
		my (@tmp) = $text =~ m|<(.*?)>(.*)</\1>|gs;
		while (my ($key,$val) = splice(@tmp, 0, 2)) {
			if ($key && $val) {
				if ($key =~ m/genre|mood|style|theme/) {
					@{$self->{fields}{$key}} = split(', ', $val);
				} else {
					$self->{fields}{$key} = $val;
				}
			}
		}
		close $fh;
		if ($::Options{OPT.'StyleAsGenre'} && $self->{fields}->{style}) {@{$self->{fields}->{genre}} = ::uniq(@{$self->{fields}->{style}}, @{$self->{fields}->{genre}})}
		$self->print_review() unless $md;
		if ($::Options{OPT.'SaveFields'}) {push(@towrite, [$ID, %{$self->{fields}}]); save_fields()} # We may not have saved when first downloaded.
	} else {
		warn "Albuminfo: failed retrieving info from $file\n" if $::debug;
		$self->print_warning(_"No review found") unless $md;
	}
	::IdleDo('9_download_one'.$self, undef, $cb, $self) if $cb;
}

# Save review to file. The format of the file is: <field>values</field>
sub save_review {
	my ($ID,$fields) = @_;
	my $text = "";
	for my $key (sort {lc $a cmp lc $b} keys %{$fields}) { # Sort fields alphabetically
		if ($key =~ m/genre|mood|style|theme/) {
			$text = $text . "<$key>".join(", ", @{$fields->{$key}})."</$key>\n";
		} else {
			$text = $text . "<$key>".$fields->{$key}."</$key>\n";
		}
	}
	my $format = $::Options{OPT.'PathFile'};
	my ($path,$file) = ::pathfilefromformat( $ID, $format, undef, 1 );
	unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$::MainWindow); return}
	return unless ::CreateDir($path,$::MainWindow,_"Error saving review") eq 'ok';
	if ( open(my$fh, '>:utf8', $path.$file) ) {
		print $fh $text;
		close $fh;
		warn "Albuminfo: Saved review in ".$path.$file."\n" if $::debug;
	} else {
		::ErrorMessage(::__x(_"Error saving review in '{file}' :\n{error}", file => $file, error => $!), $::MainWindow);
	}
}

# Save selected fields (moods, styles etc.) for all tracks in album
sub save_fields {
	return if $save_fields_lock;
	return unless scalar(@towrite);
	my ($ID,%fields) = @{shift(@towrite)};
	my $album = Songs::Gid_to_Get("album", Songs::Get_gid($ID,'album'));
	warn "Albuminfo: Saving tracks on $album (".scalar(@towrite)." album".(scalar(@towrite)!=1 ? "s" : "")." in queue).\n" if $::debug;
	my $IDs = Songs::MakeFilterFromGID('album', Songs::Get_gid($ID,'album'))->filter(); # Songs on this album
	my @updated_fields;
	for my $key (qw/genre mood style theme/) {
		if ($::Options{OPT.$key} && $fields{$key}) {
			if ( $::Options{OPT.'ReplaceFields'} ) {
				push(@updated_fields, $key, $fields{$key});
			} else {
				push(@updated_fields, '+'.$key, $fields{$key});
			}
		}
	}
	if (@updated_fields) {
		$save_fields_lock = 1;
		Songs::Set($IDs, \@updated_fields, callback_finish=>sub {$save_fields_lock = 0; save_fields();});
	} else {
		save_fields(); # There may still be albums in @towrite
	}
}

# Cancel pending tasks, and abort possible http_wget in progress.
sub cancel {
	my $self = shift;
	delete $::ToDo{'9_load_albuminfo'.$self};
	delete $::ToDo{'9_refresh_albuminfo'.$self};
	$self->{waiting}->abort() if $self->{waiting};
	::Progress('albuminfo', abort=>1);
	$self->{abort}=1;
}

1

