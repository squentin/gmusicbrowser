# Copyright (C) 2005-2020 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;

package Layout;

use constant
{
 TRUE  => 1,
 FALSE => 0,

 SIZE_BUTTONS => 'large-toolbar',
 SIZE_FLAGS => 'menu',
};

our @MenuQueue=
(	{label => _"Queue album",	code => sub { ::EnqueueSame('album',$_[0]{ID}); }, istrue=>'ID', },
	{label => _"Queue artist",	code => sub { ::EnqueueSame('artist',$_[0]{ID});}, istrue=>'ID', },  # or use field 'artists' or 'first_artist' ?
	{ include => sub
		{	my $menu=$_[1];
			my @modes= map { $_=>$::QActions{$_}{long} } ::List_QueueActions(0);
			::BuildChoiceMenu( \@modes, menu=>$menu, ordered_hash=>1, 'reverse'=>1,
				check=> sub {$::QueueAction}, code=> sub { ::EnqueueAction($_[1]); }, );
		},
	},
	{label => _"Clear queue",	code => \&::ClearQueue,		test => sub{@$::Queue}},
	{label => _"Shuffle queue",	code => sub {$::Queue->Shuffle},	test => sub{@$::Queue}},
	{label => _"Auto fill up to",	code => sub { $::Options{MaxAutoFill}=$_[1]; ::HasChanged('QueueAction','maxautofill'); },
	 				submenu => sub { my $m= ::max(1,$::Options{MaxAutoFill}-5); return [$m..$m+10]; },
					check => sub {$::Options{MaxAutoFill};},
	},
	{label => _"Edit...",		code => \&::EditQueue, test => sub { !$_[0]{mode} || $_[0]{mode} ne 'Q' }, },
	{ separator=>1},
	{ include => sub
		{	my $menu=$_[1];
			my @modes= map { $_=>$::QActions{$_}{long_next} } grep $_ ne '', ::List_QueueActions(1);
			::BuildChoiceMenu( \@modes, menu=>$menu, ordered_hash=>1, 'reverse'=>1, radio_as_checks=>1,
				check=> sub {$::NextAction},
				code=> sub { my $m=$_[1]; $m='' if $m eq $::NextAction; ::SetNextAction($m); }, );
		},
	},

);

our @MainMenu=
(	{label => _"Add files or folders",code => sub {::ChooseAddPath(0,1)},	stockicon => 'gtk-add' },
	{label => _"Settings",		code => 'OpenPref',	stockicon => 'gtk-preferences' },
	{label => _"Open Browser",	code => \&::OpenBrowser,stockicon => 'gmb-playlist' },
	{label => _"Open Context window",code => \&::ContextWindow, stockicon => 'gtk-info'},
	{label => _"Switch to fullscreen mode",code => \&::ToggleFullscreenLayout, stockicon => 'gtk-fullscreen'},
	{label => _"About",		code => \&::AboutDialog,stockicon => 'gtk-about' },
	{label => _"Quit",		code => \&::Quit,	stockicon => 'gtk-quit' },
);

our %Widgets=
(	Prev =>
	{	class	=> 'Layout::Button',
		#size	=> SIZE_BUTTONS,
		stock	=> 'gtk-media-previous',
		tip	=> _"Recently played songs",
		text	=> _"Previous",
		group	=> 'Recent',
		activate=> \&::PrevSong,
		options => 'nbsongs',
		nbsongs	=> 10,
		click3	=> sub { ::ChooseSongs([::GetPrevSongs($_[0]{nbsongs})]); },
	},
	Stop =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-media-stop',
		tip	=> _"Stop",
		activate=> \&::Stop,
		click2	=> 'EnqueueAction(stop)',
		click3	=> 'SetNextAction(stop)',
	},
	Play =>
	{	class	=> 'Layout::Button',
		state	=> sub {$::TogPlay? 'pause' : 'play'},
		stock	=> {pause => 'gtk-media-pause', play => 'gtk-media-play' },
		tip	=> sub {$::TogPlay? _"Pause" : _"Play"},
		activate=> \&::PlayPause,
		click3	=> 'Stop',
		event	=> 'Playing',
	},
	Next =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-media-next',
		tip	=> _"Next Song",
		text	=> _"Next",
		group	=> 'Next',
		activate=> \&::NextSong,
		options => 'nbsongs',
		nbsongs	=> 10,
		click3	=> sub { ::ChooseSongs([::GetNextSongs($_[0]{nbsongs})]); },
	},
	OpenBrowser =>
	{	class	=> 'Layout::Button',
		oldopt1 => 'toggle',
		options => 'toggle',
		stock	=> 'gmb-playlist',
		tip	=> _"Open Browser window",
		activate=> sub { ::OpenSpecialWindow('Browser',$_[0]{toggle}); },
		click3	=> sub { ::OpenSpecialWindow('Browser'); },
	},
	OpenContext =>
	{	class	=> 'Layout::Button',
		oldopt1 => 'toggle',
		options => 'toggle',
		stock	=> 'gtk-info',
		tip	=> _"Open Context window",
		activate=> sub { ::OpenSpecialWindow('Context',$_[0]{toggle}); },
		click3	=> sub { ::OpenSpecialWindow('Context'); },
	},
	OpenQueue	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gmb-queue-window',
		tip	=> _"Open Queue window",
		options => 'toggle',
		activate=> sub { ::OpenSpecialWindow('Queue',$_[0]{toggle}); },
	},
	Pref =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-preferences',
		tip	=> _"Edit Settings",
		text	=> _"Settings",
		activate=> 'OpenPref',
		click3	=> sub {Layout::Window->new($::Options{Layout});}, #mostly for debugging purpose
		click2	=> \&::AboutDialog,
	},
	Quit =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-quit',
		tip	=> _"Quit",
		activate=> \&::Quit,
		click2	=> 'EnqueueAction(quit)',
		click3	=> 'SetNextAction(quit)',
	},
	Lock	=>
	{	class	=> 'Layout::Button',
		button	=> 0,
		size	=> SIZE_FLAGS,
		options	=> 'field',
		field	=> 'fullfilename',	#default field to make sure it's defined
		state	=> sub { ($::TogLock && $::TogLock eq $_[0]{field})? 'on' : 'off' },
		stock	=> { on => 'gmb-lock', off => '. gmb-locklight' },
		tip	=> sub { ::__x(_"Lock on {field}", field=> Songs::FieldName($_[0]{field})) },
		click1	=> sub {::ToggleLock($_[0]{field});},
		event	=> 'Lock',
	},
	LockSong =>
	{	parent	=> 'Lock',
		field	=> 'fullfilename',
		tip	=> _"Lock on song",
	},
	LockArtist =>
	{	parent	=> 'Lock',
		field	=> 'first_artist',
		tip	=> _"Lock on Artist",
		click2	=> 'EnqueueArtist',
	},
	LockAlbum =>
	{	parent	=> 'Lock',
		field	=> 'album',
		tip	=> _"Lock on Album",
		click2	=> 'EnqueueAlbum',
	},
	Sort =>
	{	class	=> 'Layout::Button',
		button	=> 0,
		size	=> SIZE_FLAGS,
		state	=> sub { my $s=$::Options{'Sort'};($s=~m/^random:/)? 'random' : ($s eq 'shuffle')? 'shuffle' : 'sorted'; },
		stock	=> { random => 'gmb-random', shuffle => 'gmb-shuffle', sorted => 'gtk-sort-ascending' },
		tip	=> sub { _("Play order") ." :\n". ::ExplainSort($::Options{Sort}); },
		text	=> sub { ::ExplainSort($::Options{Sort},1); },
		click1	=> 'MenuPlayOrder',
		click3	=> 'ToggleRandom',
		event	=> 'Sort SavedWRandoms SavedSorts',
	},
	Filter =>
	{	class	=> 'Layout::Button',
		button	=> 0,
		size	=> SIZE_FLAGS,
		state	=> sub { defined $::ListMode ? 'list'
			: $::SelectedFilter->is_empty ? 'library' : 'filter'; },
		stock	=> { list => 'gmb-list', library => 'gmb-library', filter => 'gmb-filter' },
		tip	=> sub
			{ defined $::ListMode	? _"static list"
						: _("Playlist filter :\n").$::SelectedFilter->explain;
			},
		text	=> sub { $::ListMode ? _"static list" : $::SelectedFilter->name; },
		click1	=> 'MenuPlayFilter',
		click3	=> 'ClearPlayFilter',
		event	=> 'Filter SavedFilters',
	},
	Queue =>
	{	class	=> 'Layout::Button',
		button	=> 0,
		size	=> SIZE_FLAGS,
		state	=> sub  { $::NextAction? $::NextAction :
				  @$::Queue?	 'queue' :
				  $::QueueAction? $::QueueAction :
						 'noqueue'
				},
		stock	=> sub  {$_[0] eq 'queue'  ?	'gmb-queue' :
				 $_[0] eq 'noqueue'?	'. gmb-queue' :
							$::QActions{$_[0]}{icon} ;
				},
		tip	=> sub { if ($::NextAction) { return $::QActions{$::NextAction}{long_next} }
				 ::CalcListLength($::Queue,'queue')
				.($::QueueAction? "\n". ::__x( _"then {action}", action => $::QActions{$::QueueAction}{short} ) : '');
				},
		text	=> _"Queue",
		click1	=> 'MenuQueue',
		click3	=> sub { ::EnqueueAction(''); ::SetNextAction(''); ::ClearQueue(); }, #FIXME replace with 3 gmb commands once new command system is done
		event	=> 'Queue QueueAction',
		dragdest=> [::DRAG_ID,sub {shift;shift;::Enqueue(@_);}],
	},
	VolumeIcon =>
	{	class	=> 'Layout::Button',
		button	=> 0,
		state	=> sub { ::GetMute() ? 'm' : ::GetVol() },
		stock	=> sub { 'gmb-vol'.( $_[0] eq 'm' ? 'm' : int(($_[0]-1)/100*$::NBVolIcons) );  },
		tip	=> sub { _("Volume : ").::GetVol().'%' },
		click1 => sub { ::PopupLayout('Volume',$_[0]); },
		click3	=> sub { ::ChangeVol('mute') },
		event	=> 'Vol',
	},
	Button =>
	{	class	=> 'Layout::Button',
	},
	EventBox =>
	{	class	=> 'Layout::Button',
		button	=> 0,
	},
	Text =>
	{	class	=> 'Layout::Label',
		oldopt1 => sub { 'text',$_[0] },
		group	=> 'Play',
	},
	Pos =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		initsize=> ::__n("%d song in queue","%d songs in queue",99999), #longest string that will be displayed
		click1	=> sub { ::ChooseSongs([::GetNeighbourSongs(5)]) unless $::RandomMode || @$::Queue; },
		update	=> sub  { my $t=(@$::ListPlay==0)	?	'':
					 @$::Queue		?	::__n("%d song in queue","%d songs in queue", scalar @$::Queue):
					!defined $::Position	?	::__n("%d song","%d songs",scalar @$::ListPlay):
									($::Position+1).'/'.@$::ListPlay;
				  $_[0]->set_markup_with_format( '<small>%s</small>', $t );
				},
		event	=> 'Pos Queue Filter',
	},
	Title =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		minsize	=> 20,
		markup	=> '<b><big>%S</big></b>%V',
		markup_empty => '<b><big>&lt;'._("Playlist Empty").'&gt;</big></b>',
		click1	=> \&PopupSongsFromAlbum,
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupContextMenu(\@::SongCMenu,{mode=> 'P', self=> $_[0], IDs => [$ID]}) if defined $ID;},
		dragsrc => [::DRAG_ID,\&DragCurrentSong],
		dragdest=> [::DRAG_ID,sub {::Select(song => $_[2]);}],
		cursor	=> 'hand2',
	},
	Title_by =>
	{	class	=> 'Layout::Label',
		parent	=> 'Title',
		markup	=> ::__x(_"{song} by {artist}",song => "<b><big>%S</big></b>%V", artist => "<b>%a</b>"),
	},
	Artist =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		minsize	=> 20,
		markup	=> '<b>%a</b>',
		click1	=> sub { ::PopupAA('artists'); },
		click3	=> sub { my $ID=::GetSelID($_[0]); ::ArtistContextMenu( Songs::Get_gid($ID,'artists'),{self =>$_[0], ID=>$ID, mode => 'P'}) if defined $ID; },
		dragsrc => [::DRAG_ARTIST,\&DragCurrentArtist],
		cursor	=> 'hand2',
	},
	Album =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		minsize	=> 20,
		markup	=> '<b>%l</b>',
		click1	=> sub { my $ID=::GetSelID($_[0]); ::PopupAA( 'album', from=> Songs::Get_gid($ID,'artists')) if defined $ID; },
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupAAContextMenu({self =>$_[0], field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album'), mode => 'P'}) if defined $ID; },
		dragsrc => [::DRAG_ALBUM,\&DragCurrentAlbum],
		cursor	=> 'hand2',
	},
	Year =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		markup	=> ' %y',
		markup_empty=> '',
	},
	Comment =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		markup	=> '%C',
	},
	Length =>
	{	class	=> 'Layout::Label',
		group	=> 'Play',
		initsize=>	::__x( _" of {length}", 'length' => "XX:XX"),
		markup	=>	::__x( _" of {length}", 'length' => "%m" ),
		markup_empty=>	::__x( _" of {length}", 'length' => "0:00" ),
#		font	=> 'Monospace',
	},
	PlayingTime =>
	{	class	=> 'Layout::Label::Time',
		group	=> 'Play',
		markup	=> '%s',
		xalign	=> 1,
		options	=> 'remaining markup_stopped',
		saveoptions => 'remaining',
		markup_stopped=> '--:--',
		initsize=> '-XX:XX',
#		font	=> 'Monospace',
		event	=> 'Time',
		click1	=> sub { $_[0]{remaining}=!$_[0]{remaining}; $_[0]->update_time; },
		update	=> sub { $_[0]->update_time unless $_[0]{busy}; },
	},
	Time =>
	{	parent	=> 'PlayingTime',
		xalign	=> .5,
		markup	=> '%s'		. ::__x( _" of {length}", 'length' => "%m" ),
		markup_empty=> '%s'	. ::__x( _" of {length}", 'length' => "0:00" ),
		initsize=> '-XX:XX'	. ::__x( _" of {length}", 'length' => "XX:XX"),
	},
	TimeBar =>
	{	class	=> 'Layout::Bar',
		group	=> 'Play',
		event	=> 'Time',
		update	=> sub { $_[0]->set_val($::PlayTime); },
		fields	=> 'length',
		schange	=> sub { $_[0]->set_max( defined $_[1] ? Songs::Get($_[1],'length') : 0); },
		set	=> sub { ::SkipTo($_[1]) },
		scroll	=> sub { $_[1] ? ::Forward(undef,10) : ::Rewind (undef,10) },
		set_preview => \&Layout::Bar::update_preview_Time,
		cursor	=> 'hand2',
		text_empty=> '',
	},
	TimeSlider =>
	{	class	=> 'Layout::Bar::Scale',
		parent	=> 'TimeBar',
		cursor	=> undef,
	},
	VolumeBar =>
	{	class	=> 'Layout::Bar',
		orientation => 'left-to-right',
		event	=> 'Vol',
		update	=> sub { $_[0]->set_val( ::GetVol() ); },
		set	=> sub { ::UpdateVol($_[1]) },
		scroll	=> sub { ::ChangeVol($_[1] ? 'up' : 'down') },
		max	=> 100,
		cursor	=> 'hand2',
	},
	VolumeSlider =>
	{	class	=> 'Layout::Bar::Scale',
		orientation => 'bottom-to-top',
		parent	=> 'VolumeBar',
		cursor	=> undef,
	},
	Volume =>
	{	class	=> 'Layout::Label',
		initsize=> '000',
		event	=> 'Vol',
		update	=> sub { $_[0]->set_label(sprintf("%d",::GetVol())); },
	},
	Stars =>
	{	New	=> \&Stars::new_layout_widget,
		group	=> 'Play',
		field	=> 'rating',
		event	=> 'Icons',
		schange	=> \&Stars::update_layout_widget,
		update	=> sub { $_[0]->update_layout_widget( ::GetSelID($_[0]) ); },
		cursor	=> 'hand2',
	},
	Cover =>
	{	class	=> 'Layout::AAPicture',
		group	=> 'Play',
		aa	=> 'album',
		oldopt1 => 'maxsize',
		schange	=> sub { my $key=(defined $_[1])? Songs::Get_gid($_[1],'album') : undef ; $_[0]->set($key); },
		click1	=> \&PopupSongsFromAlbum,
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupAAContextMenu({self =>$_[0], field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album'), mode => 'P'}) if defined $ID; },
		event	=> 'Picture_album',
		update	=> \&Layout::AAPicture::Changed,
		noinit	=> 1,
		dragsrc => [::DRAG_ALBUM,\&DragCurrentAlbum],
		fields	=> 'album',
	},
	ArtistPic =>
	{	class	=> 'Layout::AAPicture',
		group	=> 'Play',
		aa	=> 'artist',
		oldopt1 => 'maxsize',
		schange	=> sub { my $key=(defined $_[1])? Songs::Get_gid($_[1],'artists') : undef ;$_[0]->set($key); },
		click1	=> sub { ::PopupAA('artist'); },
		event	=> 'Picture_artist',
		update	=> \&Layout::AAPicture::Changed,
		noinit	=> 1,
		dragsrc => [::DRAG_ARTIST,\&DragCurrentArtist],
		fields	=> 'artist',
	},
	LabelsIcons =>
	{	New	=> sub { Gtk2::Table->new(1,1); },
		group	=> 'Play',
		field	=> 'label',
		options	=> 'field',
		schange	=> \&UpdateLabelsIcon,
		update	=> \&UpdateLabelsIcon,
		event	=> 'Icons',
		tip	=> '%L',
	},
	Filler =>
	{	New	=> sub { Gtk2::HBox->new; },
	},
	QueueList =>
	{	New	=> sub { $_[0]{type}='Q'; SongList::Common->new($_[0]); },
		tabtitle=> _"Queue",
		tabicon	=> 'gmb-queue',
		issonglist=>1,
	},
	PlayList =>
	{	New	=> sub { $_[0]{type}='A'; SongList::Common->new($_[0]); },
		tabtitle=> _"Playlist",
		tabicon	=> 'gtk-media-play',
		issonglist=>1,
	},
	SongList =>
	{	New	=> sub { SongList->new($_[0]); },
		oldopt1 => 'mode',
		issonglist=>1,
	},
	SongTree =>
	{	New	=> sub { SongTree->new($_[0]); },
		issonglist=>1,
	},
	EditList =>
	{	New 	=> sub { $_[0]{type}='L'; SongList::Common->new($_[0]); },
		tabtitle=> \&SongList::Common::MakeTitleLabel,
		tabrename=>\&SongList::Common::RenameTitleLabel,
		tabicon	=> 'gmb-list',
		issonglist=>1,
	},
	TabbedLists =>
	{	class	=> 'Layout::NoteBook',
		EndInit => \&Layout::NoteBook::EndInit,
		default_child => 'PlayList',
		#these options will be passed to songlist/songtree children :
		options_for_list => 'songlist songtree sort songxpad songypad no_typeahead cols grouping',
	},
	Context =>
	{	class	=> 'Layout::NoteBook',
		EndInit => \&Layout::NoteBook::EndInit,
		group	=> 'Play',
		typesubmenu=> 'C',
		match	=> 'context page',
		#these options will be passed to context children :
		options_for_context => 'group',
	},
	SongInfo=>
	{	class	=> 'Layout::SongInfo',
		group	=> 'Play',
		expander=> 1,
		hide_empty => 1,
		tabicon	=> 'gtk-info',
		tabtitle=> _"Song informations",
	},
	PictureBrowser=>
	{	class	=> 'Layout::PictureBrowser',
		group	=> 'Play',
		field	=> 'album',
		options	=> 'field',
		xalign	=> .5,
		yalign	=> .5,
		follow	=> 1,
		scroll_zoom  => 1,
		show_list    => 0,
		show_folders => 1,
		show_toolbar => 0,
		pdf_mode => 1,
		embedded_mode=>0,
		hpos => 140,
		vpos => 80,
		reset_zoom_on=>'folder', #can be group, folder, file or never
		nowrap	=> 0,
		schange	=> \&Layout::PictureBrowser::queue_song_changed,
		autoadd_type	=> 'context page pictures',
		tabicon		=> 'gmb-picture',
		tabtitle	=> _"Album pictures",
	},
	AABox	=>
	{	class	=> 'GMB::AABox',
		oldopt1	=> sub { 'aa='.( $_[0] ? 'artist' : 'album' ) },
	},
	ArtistBox	=>
	{	class	=> 'GMB::AABox',
		aa	=> 'artists',
	},
	AlbumBox	=>
	{	class	=> 'GMB::AABox',
		aa	=> 'album',
	},
	FilterPane	=>
	{	class	=> 'FilterPane',
		oldopt1	=> sub
			{	my ($nb,$hide,@pages)=split ',',$_[0];
				return (nb => ++$nb,hide => $hide,pages=>join('|',@pages));
			},
	},
	Total	=>
	{	class	=> 'LabelTotal',
		oldopt1 => 'mode',
		saveoptions=> 'mode',
	},
	FilterBox =>
	{	New => \&Browser::makeFilterBox,
		dragdest => [::DRAG_FILTER,sub { ::SetFilter($_[0],$_[2]);}],
	},
	FilterLock=>	{ New		=> \&Browser::makeLockToggle,
			  relief	=> 'none',
			},
	HistItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Recent Filters",
			  updatemenu	=> \&Browser::fill_history_menu,
			},
	PlayItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Playing",
			  updatemenu	=> sub { my $sl=::GetSonglist($_[0]); unless ($sl) {warn "Error : no associated songlist with $_[0]{name}\n"; return} ::BuildMenu(\@Browser::MenuPlaying, { self => $_[0], songlist => $sl }, $_[0]->get_submenu); },
			},
	LSortItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Sort",
			  updatemenu	=> \&Browser::make_sort_menu,
			},
	PSortItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Play order",
			  updatemenu	=> sub { SortMenu($_[0]->get_submenu); },
			},
	PFilterItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Playlist filter",
			  updatemenu	=> sub { FilterMenu($_[0]->get_submenu); },
			},
	QueueItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Queue",
			  updatemenu	=> sub{ ::BuildMenu(\@MenuQueue,{ID=>$::SongID}, $_[0]->get_submenu); },
			},
	LayoutItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Layout",
			  updatemenu	=> sub{ ::BuildChoiceMenu( Layout::get_layout_list(qr/G.*\+/),
					 	 	tree=>1,
							check=> sub {$::Options{Layout}},
							code => sub { $::Options{Layout}=$_[1]; ::IdleDo('2_ChangeLayout',500, \&::CreateMainWindow ); },
							menu => $_[0]->get_submenu,	# re-use menu
						);
					},
			},
	MainMenuItem =>	{ New		=> \&Layout::MenuItem::new,
			  text		=> _"Main",
			  updatemenu	=> sub{ ::BuildMenu(\@MainMenu,undef, $_[0]->get_submenu); },
			},
	MenuItem =>	{ New		=> \&Layout::MenuItem::new,
			},
	SeparatorMenuItem=>
			{ New		=> sub { Gtk2::SeparatorMenuItem->new },
			},
	Refresh =>
	{	class	=> 'Layout::Button',
		size	=> 'menu',
		stock	=> 'gtk-refresh',
		tip	=> _"Refresh list",
		activate=> sub { ::RefreshFilters($_[0]); },
	},
	PlayFilter =>
	{	class	=> 'Layout::Button',
		size	=> 'menu',
		stock	=> 'gtk-media-play',
		tip	=> _"Play filter",
		activate=> sub { ::Select( filter => ::GetFilter($_[0]), song=> 'trykeep', play =>1 ); },
		click2	=> sub { ::EnqueueFilter( ::GetFilter($_[0]) ); },
	},
	QueueFilter =>
	{	class	=> 'Layout::Button',
		size	=> 'menu',
		stock	=> 'gmb-queue',
		tip	=> _"Enqueue filter",
		activate=> sub { ::EnqueueFilter( ::GetFilter($_[0]) ); },
	},
	ResetFilter =>
	{	class	=> 'Layout::Button',
		size	=> 'menu',
		stock	=> 'gtk-clear',
		tip	=> _"Reset filter",
		activate=> sub { ::SetFilter($_[0],undef); },
	},
	ToggleButton =>
	{	class	=> 'Layout::TogButton',
		size	=> 'menu',
	},
	HSeparator =>
	{	New	=> sub {Gtk2::HSeparator->new},
	},
	VSeparator =>
	{	New	=> sub {Gtk2::VSeparator->new},
	},
	Choose =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-add',
		tip	=> _"Choose Artist/Album/Song",
		activate=> sub { Layout::Window->new('Search'); },
	},
	ChooseRandAlbum =>
	{	class	=> 'Layout::Button',
		stock	=> 'gmb-random-album',
		tip	=> _"Choose Random Album",
		options => 'action',
		activate=> sub { my $al=AA::GetAAList('album'); my $r=int rand(@$al); my $key=$al->[$r]; my $list=AA::GetIDs('album',$key); if (my $ac=$_[0]{action}) { ::DoActionForList($ac,$list); } else { my $ID=::FindFirstInListPlay($list); ::Select( song => $ID)}; },
		click3	=> sub { my @list; my $al=AA::GetAAList('album'); my $nb=5; while ($nb--) { my $r=int rand(@$al); push @list, splice(@$al,$r,1); last unless @$al; } ::PopupAA('album', list=>\@list, format=> ::__x( _"{album}\n<small>by</small> {artist}", album => "%a", artist => "%b"));  },
	},
	AASearch =>
	{	class	=> 'AASearch',
	},
	ArtistSearch =>
	{	class	=> 'AASearch',
		aa	=> 'artists',
	},
	AlbumSearch =>
	{	class	=> 'AASearch',
		aa	=> 'album',
	},
	SongSearch =>
	{	class	=> 'SongSearch',
	},
	SimpleSearch =>
	{	class	=> 'SimpleSearch',
		dragdest=> [::DRAG_FILTER,sub { ::SetFilter($_[0],$_[2]);}],
	},
	Visuals		=>
	{	New	=> sub {my $darea=Gtk2::DrawingArea->new; return $darea unless $::Play_package->{visuals}; $::Play_package->add_visuals($darea); my $eb=Gtk2::EventBox->new; $eb->add($darea); return $eb},
		click1	=> sub {$::Play_package->set_visual('+') if $::Play_package->{visuals};}, #select next visual
		click2	=> \&ToggleFullscreen, #FIXME use a fullscreen layout instead,
		click3	=> \&VisualsMenu,
		minheight=>50,
		minwidth=>200,
	},
	Connections	=>	#FIXME could be better
	{	class	=> 'Layout::Label',
		update	=> sub { unless ($::Play_package->can('get_connections')) { $_[0]->hide; $_[0]->set_no_show_all(1); return }; $_[0]->show; $_[0]->child->show_all; my @c= $::Play_package->get_connections; my $t= @c? _("Connections from :")."\n".join("\n",@c) : _("No connections"); $_[0]->child->set_text($t); },
		event	=> 'connections',
	},
	ShuffleList	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gmb-shuffle',
		size	=> SIZE_FLAGS,
		tip	=> _"Shuffle list",
		activate=> sub { my $songarray= ::GetSongArray($_[0]) || return; $songarray->Shuffle; },
		event	=> 'SongArray',
		update	=> \&SensitiveIfMoreOneSong,
		PostInit=> \&SensitiveIfMoreOneSong,
	},
	EmptyList	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-clear',
		size	=> SIZE_FLAGS,
		tip	=> _"Empty list",
		activate=> sub { my $songarray= ::GetSongArray($_[0]) || return; $songarray->Replace(); },
		event	=> 'SongArray',
		update	=> \&SensitiveIfMoreZeroSong,
		PostInit=> \&SensitiveIfMoreZeroSong,
	},
	EditListButtons	=>
	{	class	=> 'EditListButtons',
	},
	QueueActions	=>
	{	class	=> 'QueueActions',
	},
	Fullscreen	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-fullscreen',
		tip	=> _"Toggle fullscreen mode",
		text	=> _"Fullscreen",
		activate=> \&::ToggleFullscreenLayout,
		click3	=> \&ToggleFullscreen,
		autoadd_type	=> 'button main',
		autoadd_option	=> 'AddFullscreenButton',
	},
	Repeat	=>
	{	New => sub { my $w=Gtk2::CheckButton->new(_"Repeat"); $w->signal_connect(clicked => sub { ::SetRepeat($_[0]->get_active); }); return $w; },
		event	=> 'Repeat Sort',
		update	=> sub { if ($_[0]->get_active xor $::Options{Repeat}) { $_[0]->set_active($::Options{Repeat});} $_[0]->set_sensitive(!$::RandomMode); },
	},
	AddLabelEntry =>
	{	New => \&AddLabelEntry,
		group	=> 'Play',
	},
	LabelToggleButtons =>
	{	class	=> 'Layout::LabelToggleButtons',
		group	=> 'Play',
		field	=> 'label',
	},
	PlayOrderCombo =>
	{	New	=> \&PlayOrderComboNew,
		event	=> 'Sort SavedWRandoms SavedSorts',
		update	=> \&PlayOrderComboUpdate,
		minwidth=> 100,
	},
	Progress =>
	{	class => 'Layout::Progress',
		compact=>1,
	},
	VProgress =>
	{	class => 'Layout::Progress',
		vertical=>1,
	},
	Equalizer =>
	{	New	=> \&Layout::Equalizer::new,
		event	=> 'Equalizer',
		update	=> \&Layout::Equalizer::update,
		preamp	=> 1,
		labels	=> 'x-small',
	},
	EqualizerPresets =>
	{	class	=> 'Layout::EqualizerPresets',
		event	=> 'Equalizer',
		update	=> \&Layout::EqualizerPresets::update,
		onoff	=> 1,
	},
	EqualizerPresetsSimple =>
	{	parent => 'EqualizerPresets',
		open   =>1,
		notoggle=>1,
	}
#	RadioList =>
#	{	class => 'GMB::RadioList',
#	},
);

# aliases for previous widget names
{ my %aliases=
  (	Playlist	=> 'OpenBrowser',
	BContext	=> 'OpenContext',
	Date		=> 'Year',
	Label		=> 'Text',
	Vol		=> 'VolumeIcon',
	LabelVol	=> 'Volume',
	FLock		=> 'FilterLock',
	TogButton	=> 'ToggleButton',
	ProgressV	=> 'VProgress',
	FBox		=> 'FilterBox',
	Scale		=> 'TimeSlider',
	VolSlider	=> 'VolumeSlider',
	VolBar		=> 'VolumeBar',
	FPane		=> 'FilterPane',
	LabelTime	=> 'PlayingTime',
	#Pos		=> 'PlaylistPosition', 'Position', ?
	#SimpleSearch	=> 'Search', ?
  );
	while ( my($alias,$real)= each %aliases )
	{	$Widgets{$alias}||=$Widgets{$real};
	}
}

our %Layouts;

sub get_layout_list
{	my $type=$_[0];
	my @list=keys %Layouts;
	@list=grep defined $Layouts{$_}{Type} && $Layouts{$_}{Type}=~m/$type/, @list if $type;
	#return { map { $_ => _ ($Layouts{$_}{Name} || $_) } @list };  #use name instead of id if it exists, and translate
	my %cat;
	my @tree;
	for my $id (@list)
	{	my $name2=$id;
		my $cat= $Layouts{$id}{Category};
		my $name= $Layouts{$id}{Name} || _( $name2 );
		my $array= $cat ?  ($cat{$cat}||=[]) : \@tree;
		push @$array, $id, $name;
	}
	push @tree, $cat{$_},$_ for keys %cat;
	return \@tree;
}

sub get_layout_name
{	my $layout=shift;
	my $def= $Layouts{$layout};
	return sprintf(_"Unknown layout '%s'",$layout) unless $def;
	my $name= $def->{Name} || _( $layout );
	return $name;
}

sub InitLayouts
{	undef %Layouts;
	my @files= ::FileList( qr/\.layout$|(?:$::QSLASH)layouts$/o,	$::DATADIR.::SLASH.'layouts',
									$::HomeDir.'layouts',
									$::CmdLine{searchpath} );
	ReadLayoutFile($_) for @files;
	die "No layouts file found.\n" unless keys %Layouts;

	if ($::CmdLine{layoutlist})
	{	print "Available layouts : ((type) id\t: name)\n";
		my ($max)= sort {$b<=>$a} map length, keys %Layouts;
		for my $id (sort keys %Layouts)
		{	my $name= get_layout_name($id);
			my $type= $Layouts{$id}{Type} || '';
			$type="($type)" if $type;
			printf "%-4s %-${max}s : %s\n",$type,$id,$name;
		}
		exit;
	}
	::QHasChanged('Layouts');
}

sub ReadLayoutFile
{	my $file=shift;
	return unless -f $file;
	warn "Reading layouts in $file\n" if $::debug;
	open my$fh,"<:utf8",$file  or do { warn $!; return };
	my $first;
	my $linecount=0; my ($linefirst,$linenext);
	while (1)
	{	my ($next,$longline);
		my @lines=($first);
		while (local $_=<$fh>)
		{	$linecount++;
			s#^\s+##;
			next if m/^#/;
			s#\s*[\n\r]+$##;
			if (s#\\$##) {$longline.=$_;next}
			next if $_ eq '';
			if ($longline) {$_=$longline.$_;undef $longline;}
			if (m#^[{[]#) { $next=$_; $linenext=$linecount; last}
			push @lines,$_;
		}
		if ($first)
		{	if ($first=~m#^\[#) {ParseLayout(\@lines,$file,$linefirst)}
			else		{ParseSongTreeSkin(\@lines)}
		}
		$first=$next; $linefirst=$linenext;
		last unless $first;
	}
	close $fh;
}

sub ParseLayout
{	my ($lines,$file,$line)=@_;
	my $first=shift @$lines;
	my $name;
	if ($first=~m/^\[([^]=]+)\](?:\s*based on (.+))?$/)
	{	if (defined $2 && !exists $Layouts{$2})
		{	warn "Ignoring layout '$1' because it is based on unknown layout '$2'\n";
			return;
		}
		$name=$1;
		if (defined $2) { %{$Layouts{$name}}=%{$Layouts{$2}}; delete $Layouts{$name}{Name}; }
		else { delete $Layouts{$name}; }
	}
	else {return}
	my $currentkey;
	for (@$lines)
	{	s#_\"([^"]+)"#my $tr=_( $1 ); $tr=~y/"/'/; qq/"$tr"/#ge;	#translation, escaping the " so it is not picked up as a translatable string. Replace any " in translations because they would cause trouble
		unless (m/^(\w+)\s*=\s*(.*)$/) { $Layouts{$name}{$currentkey} .= ' '.$1 if m/\s*(.*)$/; next } #continuation of previous line if doesn't begin with "word="
		$currentkey=$1;
		if ($2 eq '') {delete $Layouts{$name}{$currentkey};next}
		$Layouts{$name}{$currentkey}= $2;
	}
	for my $key (qw/Name Category Title/)
	{	$Layouts{$name}{$key}=~s/^"(.*)"$/$1/ if $Layouts{$name}{$key};	#remove quotes from layout name and category
	}
	my $path=$file; $path=~s#([^/]+)$##; $file=$1;
	$Layouts{$name}{PATH}=$path;
	$Layouts{$name}{FILE}=$file;
	$Layouts{$name}{LINE}=$line;
}

sub ParseSongTreeSkin
{	my $lines=$_[0];
	my $first=shift @$lines;
	my $ref;
	my $name;
	if ($first=~m#{(Column|Group) (.*)}#)
	{	$ref= $1 eq 'Column' ? \%SongTree::STC : \%SongTree::GroupSkin;
		$name=$2;
		$ref=$ref->{$name}={};
	}
	else {return}
	for (@$lines)
	{	my ($key,$e,$string)= m#^(\w+)\s*([=:])\s*(.*)$#;
		next unless defined $key;
		if ($e eq '=')
		{	if ($key eq 'elems' || $key eq 'options') { warn "Can't use reserved keyword $key in SongTreee column $name\n"; next }
			$string= _( $1 ) if $string=~m/_\"([^"]+)"/;	#translation, escaping the " so it is not picked up as a translatable string
			$ref->{$key}=$string;
		}
		elsif ($string=~m#^Option(\w*)\((.+)\)$#)
		{	my $type=$1;
			my $opt=::ParseOptions($2);
			$opt->{type}=$type;
			$ref->{options}{$key}=$opt;
		}
		else { push @{$ref->{elems}}, $key.'='.$string; }
	}
}

sub GetDefaultLayoutOptions
{	my $layout=$_[0];
	my %default;
	my $options= $Layout::Layouts{$layout}{Default} || '';
	if ($options=~m/^\w+\(/) #new format (v1.1.2)
	{	for my $nameopt (::ExtractNameAndOptions($options))
		{	$default{$1}=$2 if $nameopt=~m/^(\w+)\((.+)\)$/;
		}
	}
	else	# old format (version <1.1.2)
	{	#warn "Old options format not supported for layout $layout => ignored\n";
		#$opt2={};
		my @optlist=split /\s+/,$options;
		unshift @optlist,'Window' if @optlist%2;	#very old format (v<0.9573)
		%default= @optlist;
	}
	$_=::ParseOptions($_) for values %default;
	$default{DEFAULT_OPTIONS}=1;
	$default{Window}{DEFAULT_OPTIONS}=1;
	return \%default;
}

sub SaveWidgetOptions		#Save options for this layout by collecting options of its widgets
{	my @widgets=@_;
	my %states;
	for my $widget (@widgets)
	{	my $key=$widget->{name};
		unless ($key) { warn "Error: no name for widget $widget\n"; next }
		my $opt;
		if (my $sub=$widget->{SaveOptions})
		{	my @opt=$sub->($widget);
			$opt= @opt>1 ? {@opt} : $opt[0];
		}
		if (my $keys=$widget->{options_to_save})
		{	$opt->{$_}=$widget->{$_} for grep defined $widget->{$_}, split / /,$keys;
		}
		next unless $opt;
		if (!ref $opt) { warn "invalid options returned from $key\n";next }
		$opt=+{@$opt} if ref $opt eq 'ARRAY';
		next unless keys %$opt;
		$states{$key}=$opt;
	}
	if ($::debug)
	{	warn "Saving widget options :' :\n";
		for my $key (sort keys %states)
		{	warn "  $key:\n";
			warn "    $_ = $states{$key}{$_}\n" for sort keys %{$states{$key}};
		}
	}
	return \%states;
}

sub InitLayout
{	my ($self,$layout,$opt2)=@_;
	$self->{layout}=$layout;
	$self->set_name($layout);

	my $boxes=$Layouts{$layout};
	$self->{KeyBindings}=::make_keybindingshash($boxes->{KeyBindings}) if $boxes->{KeyBindings};
	$self->{widgets}={};
	$self->{global_options}{default_group}=$self->{group};
	for (qw/PATH SkinPath SkinFile DefaultFont DefaultFontColor/)
	{	my $val= $self->{options}{$_} || $boxes->{$_};
		$self->{global_options}{$_}=$val if defined $val;
	}

	my $mainwidget= $self->CreateWidgets($boxes,$opt2);
	$mainwidget ||= do { my $l=Gtk2::Label->new("Error : empty layout"); my $hbox=Gtk2::HBox->new; $hbox->add($l); $hbox; };
	$self->add($mainwidget);

	if (my $name=$boxes->{DefaultFocus})
	{	$self->SetFocusOn($name);
	}
}

sub CreateWidgets
{	my ($self,$boxes,$opt2)=@_;
	if ($self->{layoutdepth} && $self->{layoutdepth}>10) { warn "Too many imbricated layouts\n"; return }
	$self->{layoutdepth}++;
	my $widgets=$self->{widgets};

	# create boxes
	my @boxlist;
	my $defaultgroup= $self->{global_options}{default_group};
	for my $key (keys %$boxes)
	{	my $fullname=$key;
		my $type=substr $key,0,2;
		$type=$Layout::Boxes::Boxes{$type};
		next unless $type;
		my $line=$boxes->{$key};
		my $opt1={};
		if ($line=~m#^\(#)
		{	$opt1=::ExtractNameAndOptions($line);
			$line=~s#^\s+##;
			$opt1=~s#^\(##; $opt1=~s/\)$//;
			$opt1= ::ParseOptions($opt1);
		}
		my $opt2=$opt2->{$key} || {};
		%$opt1= (group=>'',%$opt1,%$opt2);
		my $group=$opt1->{group};
		$opt1->{group}= $defaultgroup.(length $group ? "-$group" : '') unless $group=~m/^[A-Z]/;
		my $box=$widgets->{$key}= $type->{New}( $opt1 );
		$box->{$_}=$opt1->{$_} for grep exists $opt1->{$_}, qw/group tabicon tabtitle maxwidth maxheight expand_weight/;
		ApplyCommonOptions($box,$opt1);

		$box->{name}=$fullname;
		$box->set_border_width($opt1->{border}) if $opt1 && exists $opt1->{border} && $box->isa('Gtk2::Container');
		$box->set_name($key);
		push @boxlist,$key,$line;
	}
	#pack boxes
	while (@boxlist)
	{	my $key=shift @boxlist;
		my $line=shift @boxlist;
		my $type=substr $key,0,2;
		$type=$Layout::Boxes::Boxes{$type};
		my $box=$widgets->{$key};
		my @names= ::ExtractNameAndOptions($line,$type->{Prefix});
		for my $name (@names)
		{	my $packoptions;
			($name,$packoptions)=@$name if ref $name;
			my $opt1;
			$opt1=$1 if $name=~s/\((.*)\)$//; #remove (...) and put it in $opt1
			my $widget= $widgets->{$name};
			my $placeholder;
			if (!$widget)	#create widget if doesn't exist yet (only boxes have already been created)
			{	$widget= NewWidget($name,$opt1,$opt2->{$name},$self->{global_options});
				if ($widget) { $self->{widgets}{$name}=$widget; }
				else
				{	$placeholder={name => $name, opt2=>$opt2->{$name}, };
				}
			};
			if ($widget)
			{	if ($widget->parent) {warn "layout error: $name already has a parent -> can't put it in $key\n"; next;}
				$type->{Pack}( $box,$widget,$packoptions );
			}
			elsif ($placeholder)
			{	$placeholder->{opt1}=$opt1;
				$placeholder->{defaultgroup}=$defaultgroup;
				$placeholder=Layout::PlaceHolder->new( $type,$box,$placeholder,$packoptions);
				$self->{PlaceHolders}{$name}=$placeholder if $placeholder;
			}
		}
		$type->{EndInit}($box) if $type->{EndInit};
	}

	for my $key (grep m/^[HV]Size/, keys %$boxes)
	{	my $mode= ($key=~m/^V/)? 'vertical' : 'horizontal';
		my @names=split /\s+/,$boxes->{$key};
		if ( $names[0]=~m/^\d+$/ )
		{	my $s=shift @names;
			my @req=($mode eq 'vertical')? (-1,$s) : ($s,-1);
			$_->set_size_request(@req) for grep defined, map $widgets->{$_}, @names;
			next if @names==1;
		}
		my $sizegroup=Gtk2::SizeGroup->new($mode);
		for my $n (@names)
		{	if (my $w=$widgets->{$n}) { $sizegroup->add_widget($w); }
			else { warn "Can't add unknown widget '$n' to sizegroup\n" }
		}
	}
	if (my $l=$boxes->{VolumeScroll})
	{	$widgets->{$_}->signal_connect(scroll_event => \&::ChangeVol)
			for grep $widgets->{$_}, split /\s+/,$l;
	}
	$self->signal_connect(key_press_event => \&KeyPressed,0);
	$self->signal_connect_after(key_press_event => \&KeyPressed,1);

	for my $widget (values %$widgets) { my $postinit= delete $widget->{PostInit}; $postinit->($widget) if $postinit; }

	$self->{layoutdepth}--;
	my @noparentboxes=grep m/^(?:[HV][BP]|[AMETNFSW]B|FR)/ && !$widgets->{$_}->parent, keys %$boxes;
	if	(@noparentboxes==0) {warn "layout empty ('$self->{layout}')\n"; return;}
	elsif	(@noparentboxes!=1) {warn "layout error: (@noparentboxes) have no parent -> can't find toplevel box\n"}
	return $widgets->{ $noparentboxes[0] };
}

sub Parse_opt1
{	my ($opt,$oldopt)=@_;
	my %opt;
	if (defined $opt)
	{	if ($oldopt && $opt!~m/=/)
		{	if (ref $oldopt) { %opt= $oldopt->($opt); }
			else { @opt{split / /,$oldopt}=split ',',$opt; }
		}
		else
		{	#%opt= $opt=~m/(\w+)=([^,]*)(?:,|$)/g;
			return Hash_to_HoH( ::ParseOptions($opt) );
		}
	}
	return \%opt;
}

sub Hash_to_HoH		# turn { 'key1/key2' => value } into { key1 => { key2 => value } }
{	my $hash=shift;
	for my $key (grep m#/#, keys %$hash)
	{	my $val=delete $hash->{$key};
		my @keys=split '/',$key;
		$key= pop @keys;
		my $h=$hash;
		for (@keys)
		{	$h= $h->{$_}||={};
			last if !ref $h;
		}
		$h->{$key}=$val;
	}
	return $hash;	# the hash ref hasn't changed, but can be handy to return it anyway
}

sub NewWidget
{	my ($name,$opt1,$opt2,$global_opt)=@_;
	my $namefull=$name;
	$name=~s/\d+$//;
	my $ref;
	$global_opt ||={};
	if ($name=~m/^@(.+)$/)
	{	$ref= {	class => 'Layout::Embedded', };
		$global_opt={ %$global_opt, layout=>$1 };
	}
	else { $ref=$Widgets{$name} }
	unless ($ref) { return undef; }
	while (my $p=$ref->{parent})	#inherit from parent
	{	my $pref=$Widgets{$p};
		$ref= { %$pref, %$ref };
		delete $ref->{parent} if $ref->{parent} eq $p;
	}
	$opt1=Parse_opt1($opt1,$ref->{oldopt1}) unless ref $opt1;
	$opt2||={};
	my %options= (group=>'', %$ref, %$opt1, %$opt2, name=>$namefull, %$global_opt);
	$options{font} ||= $global_opt->{DefaultFont} if $global_opt->{DefaultFont};
	my $group= $options{group};		#FIXME make undef group means parent's group ?
	my $defaultgroup= $options{default_group} || 'default_group';
	$options{group}= $defaultgroup.($group=~m/^\w/ ? '-' : '').$group unless $group=~m/^[A-Z]/;	#group local to window unless it begins with uppercase
	my $widget= $ref->{class}
		? $ref->{class}->new(\%options,$ref)
		: $ref->{New}(\%options);
	return unless $widget;
	$widget->{$_}= $options{$_} for 'group',split / /, ($ref->{options} || '');
	$widget->{$_}=$options{$_} for grep exists $options{$_}, qw/tabtitle tabicon tabrename maxwidth maxheight expand_weight/;
	$widget->{options_to_save}=$ref->{saveoptions} if $ref->{saveoptions};

	$widget->{name}=$namefull;
	$widget->set_name($name);

	ApplyCommonOptions($widget,\%options);

	$widget->{actions}{$_}=$options{$_}  for grep m/^click\d*/, keys %options;
	$widget->signal_connect(button_press_event => \&Button_press_cb) if $widget->{actions};

	if (my $cursor=$options{cursor})
	{	$widget->signal_connect(realize => sub {
				my ($widget,$cursor)=@_;
				my $gdkwin= $widget->window;
				if ($widget->isa('Gtk2::EventBox') && !$widget->get_visible_window)
				{	# for eventbox using an input-only gdkwindow, $widget->window is actually the parent's gdkwin,
					# the only way to get to the input-only gdkwin is looking at all the children of its parent :(
					for my $child ($gdkwin->get_children)
					{	my $w= Glib::Object->new_from_pointer($child->get_user_data);
						if ($w && $w==$widget) { $gdkwin=$child; last }
					}
				}
				$gdkwin->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
			},$cursor);
	}

	my $tip= $options{tip};
	if ( defined $tip)
	{  if (!ref $tip)
	   {	my @fields=::UsedFields($tip);
		if (@fields)
		{	$widget->{song_tip}=$tip;
			::WatchSelID($widget,\&UpdateSongTip,\@fields);
			UpdateSongTip($widget,::GetSelID($widget));
		}
		else
		{	$tip=~s#\\n#\n#g;
			$widget->set_tooltip_text($tip);
		}
	   }
	   else { $widget->{state_tip}=$tip; }
	}
	if (my $schange=$ref->{schange})
	{	my $fields= $options{fields} || $options{field};
		$fields= $fields ? [ split / /,$fields ] : undef;
		::WatchSelID($widget,$schange, $fields);
		$schange->($widget,::GetSelID($widget));
	}
	if ($ref->{event})
	{	my $sub=$ref->{update} || \&UpdateObject;
		::Watch($widget,$_,$sub ) for split / /,$ref->{event};
		$sub->($widget) unless $ref->{noinit};
	}
	::set_drag($widget,source => $ref->{dragsrc}, dest => $ref->{dragdest});
	my $init= delete $widget->{EndInit} || $ref->{EndInit};
	$init->($widget) if $init;
	$widget->{PostInit}||= $ref->{PostInit};
	return $widget;
}
sub ApplyCommonOptions # apply some options common to both boxes and other widgets
{	my ($widget,$opt)=@_;
	if ($opt->{minwidth} or $opt->{minheight})
	{	my ($minwidth,$minheight)=$widget->get_size_request;
		$minwidth=  $opt->{minwidth}  || $minwidth;
		$minheight= $opt->{minheight} || $minheight;
		$widget->set_size_request($minwidth,$minheight);
	}
	if ($opt->{hover_layout})	# only works with widgets/boxes that have their own gdkwindow (put it into a WB box otherwise)
	{	$widget->{$_}=$opt->{$_} for qw/hover_layout hover_delay hover_layout_pos/;
		Layout::Window::Popup::set_hover($widget);
	}
}

sub RegisterWidget
{	my ($name,$hash)=@_;
	my $action;
	if ($hash)
	{	if ($Widgets{$name} && $Widgets{$name}!=$hash) { warn "Widget $name already registered\n"; return }
		$Widgets{$name}=$hash;
		::HasChanged(Widgets=>'new',$name);
	}
	else
	{	::HasChanged(Widgets=>'remove',$name);
		delete $Widgets{$name};
	}
}
sub WidgetChangedAutoAdd
{	my $name=shift;
	::HasChanged(Widgets=>'option',$name) if $Widgets{$name};
}

sub UpdateObject
{	my $widget=$_[0];
	if ( my $tip=$widget->{state_tip} )
	{	$tip= $tip->($widget) if ref $tip;
		$widget->set_tooltip_text($tip);
	}
	if ($widget->{skin}) {$widget->queue_draw}
	elsif ($widget->{stock}) { $widget->UpdateStock }
}

sub Button_press_cb
{	my ($self,$event)=@_;
	my $actions=$self->{actions};
	my $key='click'.$event->button;
	my $sub=$actions->{$key};
	return 0 if !$sub && $self->{clicked_cmd};
	$sub||= $actions->{click} || $actions->{click1};
	return 0 unless $sub;
	if (ref $sub)	{&$sub}
	else		{ ::run_command($self,$sub) }
	1;
}
sub UpdateSongTip
{	my ($widget,$ID)=@_;
	if ($widget->{song_tip})
	{	my $tip= defined $ID ? ::ReplaceFields($ID,$widget->{song_tip}) : '';
		$widget->set_tooltip_text($tip);
	}
}


#sub SetSort
#{	my($self,$sort)=@_;
#	$self->{songlist}->Sort($sort);
#}

sub ShowHide
{	my ($self,$names,$resize,$show)=@_;
	$show= !grep $_ && $_->visible, map $self->{widgets}{$_}, split /\|/,$names unless defined $show;
	if ($show)	{ Show($self,$names,$resize); }
	else		{ Hide($self,$names,$resize); }
}

sub Hide
{	my ($self,$names,$resize)=@_;
	my @resize=split //,$resize||'';
	my $r;
	my ($ww,$wh)=$self->get_size;
	for my $name ( split /\|/,$names )
	{	my $widget=$self->{widgets}{$name};
		$r=shift @resize if @resize;
		next unless $widget;# && $widget->visible;
		my $alloc=$widget->allocation;
		my $w=$alloc->width;
		my $h=$alloc->height;
		$self->{hidden}{$name}=$w.'x'.$h;
		if ($r)
		{	if	($r eq 'v')	{$wh-=$h}
			elsif	($r eq 'h')	{$ww-=$w}
		}
		$widget->hide;
	}
	$self->resize($ww,$wh) if $resize && $resize ne '_';
	::HasChanged('HiddenWidgets');
}
sub Show
{	my ($self,$names,$resize)=@_;
	my @resize=split //,$resize||'';
	my $r;
	my ($ww,$wh)=$self->get_size;
	for my $name ( split /\|/,$names )
	{	my $widget=$self->{widgets}{$name};
		next unless $widget && !$widget->visible;
		$widget->show;
		my $oldsize=delete $self->{hidden}{$name};
		next unless $oldsize && $oldsize=~m/x/;
		my ($w,$h)=split 'x',$oldsize;
		$r=shift @resize if @resize;
		if ($r)
		{	if	($r eq 'v')	{$wh+=$h}
			elsif	($r eq 'h')	{$ww+=$w}
		}
	}
	$self->resize($ww,$wh) if $resize && $resize ne '_';
	::HasChanged('HiddenWidgets');
}

sub GetShowHideState
{	my ($self,$names)=@_;
	my $hidden;
	for my $name ( split /\|/,$names )
	{	my $widget=$self->{widgets}{$name};
		next unless $widget;
		$hidden++ unless $widget->visible;
	}
	return !$hidden;
}

sub ToggleFullscreen
{	return unless $_[0];
	my $win= ::get_layout_widget($_[0])->get_toplevel;
	if ($win->{fullscreen})
	{	if ($::FullscreenWindow && $win==$::FullscreenWindow) { $win->close_window }
		else {$win->unfullscreen}
	}
	else {$win->fullscreen}
}

sub KeyPressed
{	my ($self,$event,$after)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	my $focused=$self->get_toplevel->get_focus;
	return 0 if !$after && $focused && ($focused->isa('Gtk2::Entry') || $focused->isa('Gtk2::SpinButton'));
	my $mod;
	$mod.='c' if $event->state >= 'control-mask';
	$mod.='a' if $event->state >= 'mod1-mask';
	$mod.='w' if $event->state >= 'mod4-mask';
	$mod.='s' if $event->state >= 'shift-mask';
	$key= ($after? '':'+') . ($mod? "$mod-":'') . lc($key);
	my ($cmd,$arg);
	if ( exists $::CustomBoundKeys{$key} )
	{	$cmd= $::CustomBoundKeys{$key};
	}
	elsif ($self->{KeyBindings} && exists $self->{KeyBindings}{$key} )
	{	$cmd= $self->{KeyBindings}{$key};
	}
	elsif ( exists $::GlobalBoundKeys{$key} )
	{	$cmd= $::GlobalBoundKeys{$key};
	}
	elsif ($after && $self->{fullscreen} && $key eq 'Escape') { $cmd='ToggleFullscreen' }
	return 0 unless $cmd;
	if ($self->isa('Gtk2::Window'))	#try to find the focused widget (gmb widget, not gtk one), so that the cmd can act on it
	{	my $widget=$self->get_focus;
		while ($widget) {last if exists $widget->{group}; $widget=$widget->parent}
		$self=$widget if $widget;
	}
	::run_command($self,$cmd);
	return 1;
}

sub EnqueueSelected
{	my $self=shift;
	return unless $self;
	if (my $songlist=::GetSonglist($self))
	{	$songlist->EnqueueSelected;
	}
}
sub GoToCurrentSong
{	my $self=shift;
	return unless $self;
	if (my $songlist=::GetSonglist($self))
	{	$songlist->FollowSong;
	}
}

sub SetFocusOn
{	my ($self,$name)=@_;
	while ($name=~s#^([^/]+)/##)	# if name contains slashes, divide it into parent and child, where parent can be an Embedded layout or a TabbedLists/Context/NB
	{	$self=$self->{widgets}{$1};
		return unless $self;
	}
	my $widget=$self->{widgets}{$name};
	if ($widget)
	{	$widget=$widget->{DefaultFocus} while $widget->{DefaultFocus};
		TurnPagesToWidget($widget);
		$widget->grab_focus;
	}
}
sub TurnPagesToWidget #change the current page of all parent notebook so that widget is on it
{	my $parent=$_[0];
	while (1)
	{	my $child=$parent;
		$parent=$child->parent;
		last unless $parent;
		if ($parent->isa('Gtk2::Notebook'))
		 { $parent->set_current_page($parent->page_num($child)); }
	}
}

sub SensitiveIfMoreOneSong	{ my $songarray= ::GetSongArray($_[0]); $_[0]->set_sensitive($songarray && @$songarray>1); }
sub SensitiveIfMoreZeroSong	{ my $songarray= ::GetSongArray($_[0]); $_[0]->set_sensitive($songarray && @$songarray>0); }

#################################################################################

sub PlayOrderComboNew
{	my $opt=$_[0];
	my $store=Gtk2::ListStore->new(('Glib::String')x3);
	my $combo=Gtk2::ComboBox->new($store);
	my $cell=Gtk2::CellRendererPixbuf->new;
	$cell->set_fixed_size( Gtk2::IconSize->lookup('menu') );
	$combo->pack_start($cell,0);
	$combo->add_attribute($cell,stock_id => 2);
	$cell=Gtk2::CellRendererText->new;
	$combo->pack_start($cell,1);
	$combo->add_attribute($cell, text => 0);
	$combo->signal_connect( changed => sub
	 {	my $combo=$_[0];
		return if $combo->{busy};
		my $store=$combo->get_model;
		my $sort=$store->get($combo->get_active_iter,1);
		if ($sort=~m/^EDIT (.)$/)
		{ PlayOrderComboUpdate($combo); #so that the combo doesn't stay on Edit...
			if ($1 eq 'O')
			{	::EditSortOrder(undef,$::Options{Sort},undef, \&::Select_sort);
			}
			elsif ($1 eq 'R')
			{	::EditWeightedRandom(undef,$::Options{Sort},undef, \&::Select_sort);
			}
		}
		else { ::Select('sort' => $sort); }
	 });
	return $combo;
}

sub PlayOrderComboUpdate
{	my $combo=$_[0];
	$combo->{busy}=1;
	my $store=$combo->get_model;
	$store->clear;
	my $check=$::Options{Sort};
	my $found; my $iter;
	for my $name (sort keys %{$::Options{SavedWRandoms}})
	{	my $sort=$::Options{SavedWRandoms}{$name};
		$store->set(($iter=$store->append), 0,$name, 1,$sort, 2,'gmb-random');
		$found=$iter if $sort eq $check;
	}
	if (!$found && $check=~m/^random:/)
	{	$store->set($iter=$store->append, 0, _"unnamed random mode", 1,$check,2,'gmb-random');
		$found=$iter;
	}
	$store->set($store->append, 0, _"Edit random modes ...", 1,'EDIT R');
	$store->set($iter=$store->append, 0, _"Shuffle", 1,'shuffle',2,'gmb-shuffle');
	$found=$iter if 'shuffle' eq $check;
	if (defined $::ListMode)
	{	$store->set($iter=$store->append, 0, _"List order", 1,'',2,'gmb-list');
		$found=$iter if '' eq $check;
	}
	for my $name (sort keys %{$::Options{SavedSorts}})
	{	my $sort=$::Options{SavedSorts}{$name};
		$store->set($iter=$store->append, 0, $name, 1,$sort,2,'gtk-sort-ascending');
		$found=$iter if $sort eq $check;
	}
	if (!$found)
	{	$store->set($iter=$store->append, 0, ::ExplainSort($check), 1,$check,2,'gtk-sort-ascending');
		$found=$iter;
	}
	$store->set($store->append, 0, _"Edit ordered modes ...",1,'EDIT O');
	$combo->set_active_iter($found);
	$combo->{busy}=undef;
}

sub SortMenu
{	my $nopopup= $_[0];
	my $menu = $_[0] || Gtk2::Menu->new;

	my $return=0;
	$return=1 unless @_;
	my $check=$::Options{Sort};
	my $found;
	my $callback=sub { ::Select('sort' => $_[1]); };
	my $append=sub
	 {	my ($menu,$name,$sort,$true,$cb)=@_;
		$cb||=$callback;
		$true=($sort eq $check) unless defined $true;
		my $item = Gtk2::CheckMenuItem->new_with_label($name);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if $true;
		$item->signal_connect (activate => $cb, $sort );
		$menu->append($item);
	 };

	my $submenu= Gtk2::Menu->new;
	my $sitem = Gtk2::MenuItem->new(_"Weighted Random");
	for my $name (sort keys %{$::Options{SavedWRandoms}})
	{	$append->($submenu,$name, $::Options{SavedWRandoms}{$name} );
	}
	my $editcheck=(!$found && $check=~m/^random:/);
	$append->($submenu,_"Custom...", undef, $editcheck, sub
		{	::EditWeightedRandom(undef,$::Options{Sort},undef, \&::Select_sort);
		});
	$sitem->set_submenu($submenu);
	$menu->prepend($sitem);

	$append->($menu,_"Shuffle",'shuffle') unless $check eq 'shuffle';

	if ($check=~m/shuffle/)
	{ my $item=Gtk2::MenuItem->new(_"Re-shuffle");
	  $item->signal_connect(activate => $callback, $check );
	  $menu->append($item);
	}

	{ my $item=Gtk2::CheckMenuItem->new(_"Repeat");
	  $item->set_active($::Options{Repeat});
	  $item->set_sensitive(0) if $::RandomMode;
	  $item->signal_connect(activate => sub { ::SetRepeat($_[0]->get_active); } );
	  $menu->append($item);
	}

	$menu->append(Gtk2::SeparatorMenuItem->new); #separator between random and non-random modes

	$append->($menu,_"List order", '' ) if defined $::ListMode;
	for my $name (sort keys %{$::Options{SavedSorts}})
	{	$append->($menu,$name, $::Options{SavedSorts}{$name} );
	}
	$append->($menu,_"Custom...",undef,!$found,sub
		{	::EditSortOrder(undef,$::Options{Sort},undef, \&::Select_sort );
		});
	return $menu if $nopopup;
	::PopupMenu($menu);
}

sub FilterMenu
{	my $nopopup= $_[0];
	my $menu = $_[0] || Gtk2::Menu->new;

	my ($check,$found);
	$check=$::SelectedFilter->{string} if $::SelectedFilter;
	my $item_callback=sub { ::Select(filter => $_[1]); };

	my $item0= Gtk2::CheckMenuItem->new(_"All songs");
	$item0->set_active($found=1) if !$check && !defined $::ListMode;
	$item0->set_draw_as_radio(1);
	$item0->signal_connect ( activate =>  $item_callback ,'' );
	$menu->append($item0);

	for my $list (sort keys %{$::Options{SavedFilters}})
	{	my $filt=$::Options{SavedFilters}{$list}->{string};
		my $item = Gtk2::CheckMenuItem->new_with_label($list);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if defined $check && $filt eq $check;
		$item->signal_connect ( activate =>  $item_callback ,$filt );
		$menu->append($item);
	}
	my $item=Gtk2::CheckMenuItem->new(_"Custom...");
	$item->set_active(1) if defined $check && !$found;
	$item->set_draw_as_radio(1);
	$item->signal_connect ( activate => sub
		{ ::EditFilter(undef,$::SelectedFilter,undef, sub {::Select(filter => $_[0])});
		});
	$menu->append($item);
	if (my @SavedLists=::GetListOfSavedLists())
	{	my $submenu=Gtk2::Menu->new;
		my $list_cb=sub { ::Select( staticlist => $_[1] ) };
		for my $list (@SavedLists)
		{	my $item = Gtk2::CheckMenuItem->new_with_label($list);
			$item->set_draw_as_radio(1);
			$item->set_active(1) if defined $::ListMode && $list eq $::ListMode;
			$item->signal_connect( activate =>  $list_cb, $list );
			$submenu->append($item);
		}
		my $sitem=Gtk2::MenuItem->new(_"Saved Lists");
		#my $sitem=Gtk2::CheckMenuItem->new('Saved Lists');
		#$item->set_draw_as_radio(1);
		$sitem->set_submenu($submenu);
		$menu->prepend($sitem);
	}
	return $menu if $nopopup;
	::PopupMenu($menu);
}

sub VisualsMenu
{	my $menu=Gtk2::Menu->new;
	my $cb=sub { $::Play_package->set_visual($_[1]) if $::Play_package->{visuals}; };
	return unless $::Play_package->{visuals};
	my @l= $::Play_package->list_visuals;
	my $current= $::Options{gst_visual}||$l[0];
	for my $v (@l)
	{	my $item=Gtk2::CheckMenuItem->new_with_label($v);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $current eq $v;
		$item->signal_connect (activate => $cb,$v);
		$menu->append($item);
	}
	::PopupMenu($menu);
}

sub UpdateLabelsIcon
{	my $table=$_[0];
	$table->remove($_) for $table->get_children;
	return unless defined $::SongID;
	my $row=0; my $col=0;
	my $count=0;
	for my $stock ( Songs::Get_icon_list($table->{field},$::SongID) )
	{	my $img=Gtk2::Image->new_from_stock($stock,'menu');
		$count++;
		$table->attach($img,$col,$col+1,$row,$row+1,'shrink','shrink',1,1);
		if (++$row>=1) {$row=0; $col++}
	}
	$table->show_all;
}

sub AddLabelEntry	#create entry to add a label to the current song
{	my $entry=Gtk2::Entry->new;
	$entry->set_tooltip_text(_"Adds labels to the current song");
	$entry->signal_connect(activate => sub
	 {	my $entry=shift;
		my $label= $entry->get_text;
		my $ID= ::GetSelID($entry);
		return unless defined $ID & defined $label;
		$entry->set_text('');
		Songs::Set($ID,"+label",$label);
	 });
	GMB::ListStore::Field::setcompletion($entry,'label');
	return $entry;
}

sub DragCurrentSong
{	::DRAG_ID,$::SongID;
}
sub DragCurrentArtist
{	::DRAG_ARTIST,@{Songs::Get_gid($::SongID,'artists')};
}
sub DragCurrentAlbum
{	::DRAG_ALBUM,Songs::Get_gid($::SongID,'album');
}

sub PopupSongsFromAlbum
{	my $ID=::GetSelID($_[0]);
	return unless defined $ID;
	my $aid=Songs::Get_gid($ID,'album');
	::ChooseSongsFromA($aid,nocover=>0);
}

####################################

package Layout::Window;
our @ISA;
BEGIN {push @ISA,'Layout';}
use base 'Gtk2::Window';

sub new
{	my ($class,$layout,%options)=@_;
	my @original_args=@_;
	my $fallback=delete $options{fallback} || 'Lists, Library & Context';
	my $opt0={};
	if (my $opt= $layout=~m/^[^(]+\(.*=/)
	{	($layout,$opt0)= $layout=~m/^([^(]+)\((.*)\)$/; #separate layout id and options
		$opt0= ::ParseOptions($opt0);
	}
	unless (exists $Layout::Layouts{$layout})
	{	if ($fallback eq 'NONE') { warn "Layout '$layout' not found\n"; return undef; }
		warn "Layout '$layout' not found, using '$fallback' instead\n";
		$layout=$fallback; #FIXME if not a player window
		$Layout::Layouts{$layout} ||= { VBmain=>'Label(text="Error : fallback layout not found")' };	#create an error layout if fallback not found
	}
	my $opt2=$::Options{Layouts}{$layout};
	$opt2||= Layout::GetDefaultLayoutOptions($layout);
	for my $child_key (grep m#./.#, keys %options)
	{	my ($child,$key)=split "/",$child_key,2;
		$opt2->{$child}{$key}= delete $options{$child_key};
	}
	my $opt1=::ParseOptions( $Layout::Layouts{$layout}{Window}||'' );
	%options= ( borderwidth=>0, %$opt1, %{$opt2->{Window}||{}}, %options, %$opt0 );
	#warn "window options (layout=$layout) :\n";warn " $_ => $options{$_}\n" for sort keys %options;

	my $uniqueid= $options{uniqueid} || 'layout='.$layout;
		# ifexist=toggle  => if a window with same uniqueid exist it will be closed
		# ifexist=present => if a window with same uniqueid exist it presented
	if (my $mode=$options{ifexist})
	{	my ($window)=grep $_->isa('Layout::Window') && $_->{uniqueid} eq $uniqueid, Gtk2::Window->list_toplevels;
		if ($window)
		{	if    ($mode eq 'toggle'  && !$window->{quitonclose})	{ $window->close_window; return }
			elsif ($mode eq 'replace' && !$window->{quitonclose})	{ $window->close_window; return Layout::Window::new(@original_args,ifexists=>0); } # destroying previous window make it save its settings, then restart new() from the start with new $opt2 but the same original arguments, add ifexists=>0 to make sure it doesn't loop
			elsif ($mode eq 'present')			 	{ $window->force_present; return }
		}
	}

	my $wintype= delete $options{wintype} || 'toplevel';
	my $self=bless Gtk2::Window->new($wintype), $class;
	$self->{uniqueid}= $uniqueid;
	$self->set_role($layout);
	$self->set_type_hint(delete $options{typehint}) if $options{typehint};
	$self->{options}=\%options;
	$self->{name}='Window';
	$self->{SaveOptions}=\&SaveWindowOptions;
	$self->{group}= 'Global('.::refaddr($self).')';
	::Watch($self,Save=>\&SaveOptions);
	$self->set_title(::PROGRAM_NAME);

	if ($options{dragtomove})
	{	$self->add_events(['button-press-mask']);
		$self->signal_connect_after(button_press_event => sub { my $event=$_[1]; $_[0]->begin_move_drag($event->button, $event->x_root, $event->y_root, $event->time); 1;  });
	}

	#$self->signal_connect (show => \&show_cb);
	$self->signal_connect (window_state_event => sub
	 {	my $self=$_[0];
		my $wstate=$_[1]->new_window_state();
		warn "window $self is $wstate\n" if $::debug;
		$self->{sticky}=($wstate >= 'sticky'); #save sticky state
		$self->{fullscreen}=($wstate >= 'fullscreen');
		$self->{ontop}=($wstate >= 'above');
		$self->{below}=($wstate >= 'below');
		$self->{withdrawn}=($wstate >= 'withdrawn');
		$self->{iconified}=($wstate >= 'iconified');
		0;
	 });
	$self->signal_connect(focus_in_event=> sub { $_[0]{last_focused}=time;0; });
	$self->signal_connect(delete_event => \&close_window);
#	::set_drag($self, dest => [::DRAG_FILE,sub
#		{	my ($self,$type,@values)=@_;
#			warn "@values";
#		}],
#		motion => sub
#		{	my ($self,$context,$x,$y,$time)=@_;
#			my $target=$self->drag_dest_find_target($context, $self->drag_dest_get_target_list);
#			$context->{get_data}=1;
#			$self->drag_get_data($context, $target, $time);
#			::TRUE;
#		}
#		);
	$self->InitLayout($layout,$opt2);
	$self->SetWindowOptions(\%options);
	if (my $skin=$Layout::Layouts{$layout}{Skin}) { $self->set_background_skin($skin) }
	$self->init;
	::HasChanged('HiddenWidgets');
	$self->set_opacity($self->{opacity}) if exists $self->{opacity} && $self->{opacity}!=1;
	::QHasChanged('Windows');
	return $self;
}

sub init
{	my $self=$_[0];
	if ($self->{options}{transparent})
	{	if ($::CairoOK)
		{	make_transparent($self);
		}
		else { warn "no Cairo perl module => can't make the window transparent\n" }
	}
	$self->child->show_all;		#needed to get the true size of the window
	$self->realize;
	$self->Resize if $self->{size};
	{	my @hidden;
		# widgets that were saved as hidden
		@hidden=keys %{ $self->{hidden} } if $self->{hidden};
		my $widgets=$self->{widgets};
		# look for widgets asking for other widgets to be hidden at init
		for my $w (values %$widgets)
		{	my $names= delete $w->{need_hide};
			next unless $names;
			push @hidden, split /\|/, $names;
		}
		# hide them
		$_->hide for grep defined, map $widgets->{$_}, @hidden;
	}
	#$self->set_position();#doesn't work before show, at least with sawfish
	my ($x,$y)= $self->Position;
	$self->move($x,$y) if defined $x;
	$self->show;
	$self->move($x,$y) if defined $x;
	$self->parse_geometry( delete $::CmdLine{geometry} ) if $::CmdLine{geometry};
	$self->set_workspace( delete $::CmdLine{workspace} ) if exists $::CmdLine{workspace};
	if ($self->{options}{insensitive})
	{	my $mask=Gtk2::Gdk::Bitmap->create_from_data(undef,'',1,1);
		$self->input_shape_combine_mask($mask,0,0);
	}
}

sub layout_name
{	my $self=shift;
	my $id=$self->{layout};
	return Layout::get_layout_name($id);
}
sub close_window
{	my $self=shift;
	$self->SaveOptions;
	unless ($self->{quitonclose}) { $_->destroy for values %{$self->{widgets}}; $self->destroy; return }
	if ($::Options{CloseToTray}) { ::ShowHide(0); return 1}
	else { &::Quit }
}

sub SaveOptions
{	my $self=shift;
	my $opt=Layout::SaveWidgetOptions($self,values %{ $self->{widgets} }, values %{ $self->{PlaceHolders} });
	$::Options{Layouts}{$self->{layout}} = $opt;
}
sub SaveWindowOptions
{	my $self=$_[0];
	my %wstate;
	$wstate{size}=join 'x',$self->get_size;
	#unless ($self->{options}{DoNotSaveState})
	{	$wstate{sticky}=1 if $self->{sticky};
		$wstate{fullscreen}=1 if $self->{fullscreen};
		$wstate{ontop}=1 if $self->{ontop};
		$wstate{below}=1 if $self->{below};
		$wstate{nodecoration}=1 unless $self->get_decorated;
		$wstate{skippager}=1 if $self->get_skip_pager_hint;
		if ($self->{saved_position})
		{	$wstate{pos}=$self->{saved_position};
			$wstate{skiptaskbar}=1 if $self->{skip_taskbar_hint};
		}
		else
		{	$wstate{pos}=join 'x',$self->get_position;
			$wstate{skiptaskbar}=1 if $self->get_skip_taskbar_hint;
		}
	}
	my $hidden=$self->{hidden};
	if ($hidden && keys %$hidden)
	{	$wstate{hidden}= join '|', map { my $dim=$hidden->{$_}; $_.($dim ? ":$dim" : '') } sort keys %$hidden;
	}
	return \%wstate;
}
sub SetWindowOptions
{	my ($self,$opt)=@_;
	my $layouthash= $Layout::Layouts{ $self->{layout} };
	if	($opt->{fullscreen})	{ $self->fullscreen; }
	else
	{	$self->{size}=$opt->{size};
		#window position in format numberxnumber  number can be a % of screen size
		$self->{pos}=$opt->{pos};
	}
	$self->stick if $opt->{sticky};
	$self->set_keep_above(1) if $opt->{ontop};
	$self->set_keep_below(1) if $opt->{below};
	$self->set_decorated(0)  if $opt->{nodecoration};
	$self->set_skip_pager_hint(1) if $opt->{skippager};
	$self->set_skip_taskbar_hint(1) if $opt->{skiptaskbar};
	$self->{opacity}=$opt->{opacity} if defined $opt->{opacity};
	$self->{hidden}={ $opt->{hidden}=~m/(\w+)(?::?(\d+x\d+))?/g } if $opt->{hidden};

	$self->{size}= $self->{fixedsize}= $opt->{fixedsize} if $opt->{fixedsize};
	$self->set_border_width($self->{options}{borderwidth});
	$self->set_gravity($opt->{gravity}) if $opt->{gravity};
	my $title= $layouthash->{Title} || $opt->{title} || _"%S by %a";
	$title=~s/^"(.*)"$/$1/;
	if (my @l=::UsedFields($title))
	{	$self->{TitleString}=$title;
		my %fields; $fields{$_}=undef for @l;
		::Watch($self,'CurSong',\&UpdateWindowTitle,\%fields);
		$self->UpdateWindowTitle();
	}
	else { $self->set_title($title) }
}
sub UpdateWindowTitle
{	my $self=shift;
	my $ID=$::SongID;
	if (my $title=$self->{TitleString})
	{	$title= defined $ID	? ::ReplaceFields($ID,$title)
					: '<'._("Playlist Empty").'>';
		$self->set_title($title);
	}
}

sub Resize
{	my $self=shift;
	my ($w,$h)= split 'x',delete $self->{size};
	return unless defined $h;
	my $screen=$self->get_screen;
	my $monitor=$screen->get_monitor_at_window($self->window);
	my (undef,undef,$monitorwidth,$monitorheight)=$screen->get_monitor_geometry($monitor)->values;
	$w= $1*$monitorwidth/100 if $w=~m/(\d+)%/;
	$h= $1*$monitorheight/100 if $h=~m/(\d+)%/;
	if ($self->{options}{DEFAULT_OPTIONS}) { $monitorwidth-=40; $monitorheight-=80; } # if using default layout size, reserve some space for potential panels and decorations #FIXME use gdk_screen_get_monitor_workarea once ported to gtk3
	$w=$monitorwidth if $w>$monitorwidth;
	$h=$monitorheight if $h>$monitorheight;
	if ($self->{fixedsize})
	{	$w=-1 if $w<1;	# -1 => do not override default minimum size
		$h=-1 if $h<1;
		$self->set_size_request($w,$h);
		$self->set_resizable(0);
	}
	else
	{	$w=1 if $w<1;	# 1 => resize to minimum size
		$h=1 if $h<1;
		$self->resize($w,$h);
	}
}

sub Position
{	my $self=shift;
	my $pos=delete $self->{pos};
	return unless $pos;		#format : 100x100    50%x100%   -100x-100   500-100% x 500-50%  1@50%x100%
	my ($monitor,$x,$xalign,$y,$yalign)= $pos=~m/(?:(\d+)@)?\s*([+-]?\d+%?)(?:([+-]\d+)%)?\s*x\s*([+-]?\d+%?)(?:([+-]\d+)%)?/;
	my ($w,$h)=$self->get_size; # size of window to position
	my $screen=$self->get_screen;
	my $absolute_coords;
	if (defined $monitor) { $monitor=undef if $monitor>=$screen->get_n_monitors; }
	if (!defined($monitor) && $x!~m/[-%]/ && $y!~m/[-%]/)
	{	$monitor=$screen->get_monitor_at_point($x,$y);
		$absolute_coords=1;
	}
	if (!defined $monitor)
	{	$monitor=$screen->get_monitor_at_window($self->window);
	}
	my ($xmin,$ymin,$monitorwidth,$monitorheight)=$screen->get_monitor_geometry($monitor)->values;
	$xalign= $x=~m/%/ ? 50 : 0   unless defined $xalign;
	$yalign= $y=~m/%/ ? 50 : 0   unless defined $yalign;
	$x= $monitorwidth*$1/100 if $x=~m/(-?\d+)%/;
	$y= $monitorheight*$1/100 if $y=~m/(-?\d+)%/;
	$x= $monitorwidth-$x if $x<0;
	$y= $monitorheight-$y if $y<0;
	$x-= $xalign*$w/100;
	$y-= $yalign*$h/100;
	if ($absolute_coords)
	{	$x-=$xmin if $x>$xmin;
		$y-=$ymin if $y>$ymin;
	}
	$x=0 if $x<0; $x=$monitorwidth -$w if $x+$w>$monitorwidth;
	$y=0 if $y<0; $y=$monitorheight-$h if $y+$h>$monitorheight;
	$x+=$xmin;
	$y+=$ymin;
	return $x,$y;
}

sub set_workspace	#only works with Gnome2::Wnck
{	my ($self,$workspace)=@_;
	eval {require Gnome2::Wnck};
	if ($@) { warn "Setting workspace : error loading Gnome2::Wnck : $@\n"; return }
	my $screen= Gnome2::Wnck::Screen->get_default;
	$screen->force_update;
	$workspace= $screen->get_workspace($workspace);
	return unless $workspace;
	my $xid= $self->window->get_xid;
	my $w=Gnome2::Wnck::Window->get($xid);
	return unless $w;
	$w->move_to_workspace($workspace);
}

sub make_transparent
{	my @children=($_[0]);
	my $colormap=$children[0]->get_screen->get_rgba_colormap;
	return unless $colormap;
	while (my $widget=shift @children)
	{	push @children, $widget->get_children if $widget->isa('Gtk2::Container');
		unless ($widget->no_window)
		{	$widget->set_colormap($colormap);
			$widget->set_app_paintable(1);
			$widget->signal_connect(expose_event => \&transparent_expose_cb);
		}
		if ($widget->isa('Gtk2::container'))
		{	$widget->signal_connect(add => sub { make_transparent($_[1]); } );
		}
	}
}
sub transparent_expose_cb #use Cairo
{	my ($w,$event)=@_;
	my $cr=Gtk2::Gdk::Cairo::Context->create($event->window);
	$cr->set_operator('source');
	$cr->set_source_rgba(0, 0, 0, 0);
	$cr->rectangle($event->area);
	$cr->fill;
	if (my $pixbuf=$w->{skinpb}) { $cr->set_source_pixbuf($pixbuf,0,0); $cr->paint; }
	return 0; #send expose to children
}


sub set_background_skin
{	my ($self,$skin)=@_;
	my ($file,$crop,$resize)=split /:/,$skin;
	$self->{pixbuf}=Skin::_load_skinfile($file,$crop,$self->{global_options});
	return unless $self->{pixbuf};
	$self->{resizeparam}=$resize;
	$self->{skinsize}='0x0';
	$self->signal_connect(size_allocate => \&resize_skin_cb);
	return if $self->{options}{transparent};
	# following not needed when using transparency

	$self->signal_connect(style_set => sub {warn "style set : @_" if $::debug;$_[0]->set_style($_[2]);} ,$self->get_style); #FIXME find the cause of these signals, seems related to stock icons
	my $rc_style= Gtk2::RcStyle->new;
	#$rc_style->bg_pixmap_name($_,'<parent>') for qw/normal selected prelight insensitive active/;
	$rc_style->bg_pixmap_name('normal','<parent>');
	my @children=($self->child);
	while (my $widget=shift @children)
	{	push @children, $widget->get_children if $widget->isa('Gtk2::Container');
		$widget->modify_style($rc_style) unless $widget->no_window;
	}
	$self->set_app_paintable(1);
}
sub resize_skin_cb	#FIXME needs to add a delay to better deal with a burst of resize events
{	my ($self,$alloc)=@_;
	my ($w,$h)=($alloc->width,$alloc->height);
	return unless $self->realized;
	return if $w.'x'.$h eq $self->{skinsize};
	my $pb=Skin::_resize($self->{pixbuf},$self->{resizeparam},$w,$h);
	return unless $pb;
	if ($self->{options}{transparent})
	{	$self->{skinpb}=$pb;	#will be used by transparent_expose_cb()
		if (my $shape= $self->{options}{shape})
		{	my $mask=Gtk2::Gdk::Pixmap->new(undef,$w,$h,1);
			$pb->render_threshold_alpha($mask,0,0,0,0,-1,-1, $shape);
			$self->input_shape_combine_mask($mask,0,0);
		}
	}
	else
	{	#my ($pixmap,$mask)=$pb->render_pixmap_and_mask(1); #leaks X memory for Gtk2 <1.146 or <1.153
		# create shape mask
		my $mask=Gtk2::Gdk::Pixmap->new(undef,$w,$h,1);
		$pb->render_threshold_alpha($mask,0,0,0,0,-1,-1,1);
		$self->shape_combine_mask($mask,0,0);
		# create pixmap background
		my $pixmap=Gtk2::Gdk::Pixmap->new($self->window,$w,$h,-1);
		$pb->render_to_drawable($pixmap, Gtk2::Gdk::GC->new($self->window), 0,0,0,0,-1,-1,'none',0,0);
		$self->window->set_back_pixmap($pixmap,0);
	}
	$self->{skinsize}=$w.'x'.$h;
	$self->queue_draw;
}

package Layout::Window::Popup;
our @ISA;
BEGIN {push @ISA,'Layout','Layout::Window';}

sub new
{	my ($class,$layout,$widget)=@_;
	$layout||=$::Options{LayoutT};
	my $self=Layout::Window::new($class,$layout, wintype=>'popup', 'pos'=>undef, size=>undef, fallback=>'full with buttons', popped_from=>$widget);

	if ($widget)	#warning : widget can be a Gtk2::StatusIcon
	{	::weaken( $widget->{PoppedUpWindow}=$self );
		$self->set_screen($widget->get_screen);
		#$self->set_transient_for($widget->get_toplevel);
		#$self->move( ::windowpos($self,$widget) );
		$self->signal_connect(enter_notify_event => \&CancelDestroy);
	}
	else	{ $self->set_position('mouse'); }
	$self->show;

	return $self;
}
sub init
{	my $self=$_[0];
	#add a frame
	my $child=$self->child;
	$self->remove($self->child);
	my $frame=Gtk2::Frame->new;
	$self->add($frame);
	$frame->add($child);
	my $shadow= $self->{options}{transparent} ? 'none' : 'out';
	$frame->set_shadow_type($shadow);
	$child->set_border_width($self->get_border_width);
	$self->set_border_width(0);
		##$self->set_type_hint('tooltip'); #TEST
		##$self->set_type_hint('notification'); #TEST
		#$self->set_focus_on_map(0);
		#$self->set_accept_focus(0); #?
	$self->signal_connect(leave_notify_event => sub	{ $_[0]->CheckCursor if $_[1]->detail ne 'inferior'; 0; });
	$self->SUPER::init;
}

sub CheckCursor		# StartDestroy if popup is not ancestor of widget under cursor and cursor isn't grabbed (menu)
{	my $self=shift;
	$self->{check_timeout} ||= Glib::Timeout->add(800, \&CheckCursor, $self);

	return 1 if $self->get_display->pointer_is_grabbed;	# to prevent destroying while a menu is open

	if (my $sicon=$self->{popped_from})
	{	return 1 if $sicon->isa('Gtk2::StatusIcon') && OnStatusIcon($sicon);	#check if pointer above statusicon
	}

	my ($gdkwin)=Gtk2::Gdk::Window->at_pointer;
	my $widget= $gdkwin ? Glib::Object->new_from_pointer($gdkwin->get_user_data) : undef;
	while ($widget)
	{	last if $widget->isa('Gtk2::StatusIcon');
		$widget= ::find_ancestor($widget,'Layout::Window::Popup');
		last unless $widget;
		return 1 if $widget==$self;	# don't destroy if cursor is over child of self
		$widget= $widget->{popped_from};# parent popup
	}

	$self->StartDestroy;
	return 1
}

sub OnStatusIcon	#return true if pointer is above sicon
{	my $sicon=shift;
	my ($screen,$area)= $sicon->get_geometry;
	my ($x,$y,$w,$h)= $area->values;
	my ($pscreen,$px,$py)= $screen->get_display->get_pointer;
	return $pscreen==$screen && $px>=$x && $px<=$x+$w && $py>=$y && $py<=$y+$h;
}

sub Position
{	my $self=shift;
	if ( my $widget= delete $self->{options}{popped_from})
	{	::weaken( $self->{popped_from}=$widget );
		if (my $pos=$widget->{hover_layout_pos})
		{	my ($x0,$y0)= split /\s*x\s*/,$pos;
			my ($width,$height)=$self->get_size;
			my ($x,$y)=  $widget->window->get_origin;
			my ($ww,$wh)=$widget->window->get_size;
			if ($widget->no_window)
			{	(my$wx,my$wy,$ww,$wh)=$widget->allocation->values;
				$x+=$wx;$y+=$wy;
			}
			$x=$y=0 if $x0=~s/abs:\s*//;
			my $screen=$widget->get_screen;
			$x+=_compute_pos($x0,$width, $ww,$screen->get_width);
			$y+=_compute_pos($y0,$height,$wh,$screen->get_height);
			return $x,$y;
		}
		return ::windowpos($self,$widget);
	}
	$self->SUPER::Position;
}

sub _compute_pos
{	my ($def,$wp,$ww,$ws)=@_;
	my %h;
	$def="+$def" unless $def=~m/^[-+]/;
	::setlocale(::LC_NUMERIC, 'C'); # so that decimal separator is the dot
	# can parse strings such as : +3s/2-w-p/2+20
	for my $v ($def=~m/([-+][^-+]+)/g)
	{	if ($v=~m#([-+]\d*\.?\d*)([pws])(?:/([0-9]+))?#)
		{	$h{$2}= ($1 eq '+' ? 1 : $1 eq '-' ? -1 : $1) / ($3||1);
		}
		elsif ($v=~m/^[-+]\d+$/) { $h{n}=$v }
	}
	::setlocale(::LC_NUMERIC, '');
	# smart alignment if alignment not specified and only widget or screen relative
	if (!defined $h{p} && (defined $h{w} xor defined $h{s}) && !$h{n})
	{	my $ws= $h{w} || $h{s} || 0;
		$h{p}= $ws==0 ? 0 : $ws==1 ? -1 : -.5;
	}
	$h{$_}||=0 for qw/n p w s/;
	my $x= $h{n} + $h{p}*$wp + $h{w}*$ww + $h{s}*$ws;
	return $x;
}

sub HoverPopup
{	my $widget=shift;
	delete $widget->{hover_timeout};
	return 0 if $widget->isa('Gtk2::StatusIcon') && !OnStatusIcon($widget);	# for statusicon, don't popup if no longer above icon
	return 0 if $widget->{block_popup};
	Popup($widget);
	0;
}
sub Popup
{	my ($widget,$addtimeout)=@_;
	my $self= $widget->{PoppedUpWindow};
	$addtimeout=0 if $self && !$self->{destroy_timeout}; #don't add timeout if there wasn't already one
	$self ||= Layout::Window::Popup->new($widget->{hover_layout},$widget);
	return 0 unless $self;
	$self->CancelDestroy;
	$self->{destroy_timeout}=Glib::Timeout->add( $addtimeout,\&DestroyNow,$self) if $addtimeout;
	$self->{check_timeout} ||= Glib::Timeout->add(400, \&CheckCursor, $self) if $widget->isa('Gtk2::StatusIcon') && !$addtimeout;
	0;
}

sub set_hover
{	my $widget=$_[0];
	if ($widget->isa('Gtk2::StatusIcon'))
	{	$widget->set_has_tooltip(1);
		$widget->signal_connect(query_tooltip => sub { return if $_[0]{hover_timeout}; &PreparePopup });
	}
	else
	{	$widget->signal_connect(enter_notify_event => \&PreparePopup);
		$widget->signal_connect(leave_notify_event => \&CancelPopup );
	}
}

sub PreparePopup
{	my $widget=shift;	#widget can be a statusicon
	return 0 if $widget->{block_popup};
	if (!$widget->{PoppedUpWindow})
	{	my $delay=$widget->{hover_delay}||1000;
		if (my $t=delete $widget->{hover_timeout})	{ Glib::Source->remove($t); }
		$widget->{hover_timeout}= Glib::Timeout->add($delay,\&HoverPopup, $widget);
	}
	else {Popup($widget)}
	0;
}

sub CancelPopup
{	my $widget=shift;
	if (my $t=delete $widget->{hover_timeout})	{ Glib::Source->remove($t); }
	if (my $self=$widget->{PoppedUpWindow})
	{	$self->StartDestroy;
		$self->{check_timeout} ||= Glib::Timeout->add(1000, \&CheckCursor, $self);
	}
}
sub CancelDestroy
{	my $self=shift;
	if (my $t=delete $self->{destroy_timeout}) { Glib::Source->remove($t); }
	if (my $t=delete $self->{check_timeout}) { Glib::Source->remove($t); }
}
sub StartDestroy
{	my $self=shift;
	$self->{destroy_timeout} ||= Glib::Timeout->add(300,\&DestroyNow,$self);
	0;
}
sub DestroyNow
{	my $self=shift;
	$self->CancelDestroy;
	$self->close_window;
	0;
}

package Layout::Embedded;
use base 'Gtk2::Container';
our @ISA;
push @ISA,'Layout';

sub new
{	my ($class,$opt)=@_;
	my $layout=$opt->{layout};
	my $def= $Layout::Layouts{$layout};
	return undef unless $def;
	my $self=bless Gtk2::VBox->new(0,0), $class;
	$self->{SaveOptions}=\&SaveEmbeddedOptions;
	$self->{group}=$opt->{group};
	my %children_opt;
	for my $child_key (grep m#./.#, keys %$opt)
	{	my ($child,$key)=split "/",$child_key,2;
		$children_opt{$child}{$key}= $opt->{$child_key};
	}
	%children_opt=( %children_opt, %{$opt->{children_opt}} ) if $opt->{children_opt};
	$self->InitLayout($layout,\%children_opt);
	$self->{tabicon}=  $self->{tabicon}  || $def->{Icon};
	$self->{tabtitle}= $self->{tabtitle} || $def->{Title} || $def->{Name} || $layout;
	$self->show_all;
	return $self;
}

sub SaveEmbeddedOptions
{	my $self=shift;
	my $opt=Layout::SaveWidgetOptions(values %{ $self->{widgets} }, values %{ $self->{PlaceHolders} });
	return children_opt => $opt;
}

package Layout::Boxes;

our %Boxes=
(	HB	=>
	{	New	=> sub { SHBox->new; },
		#New	=> sub { Gtk2::HBox->new(::FALSE,0); },
		Prefix	=> qr/([-_.0-9]*)/,
		Pack	=> \&SBoxPack,
	},
	VB	=>
	{	New	=> sub { SVBox->new; },
		#New	=> sub { Gtk2::VBox->new(::FALSE,0); },
		Prefix	=> qr/([-_.0-9]*)/,
		Pack	=> \&SBoxPack,
	},
	HP	=>
	{	New	=> sub { PanedNew('Gtk2::HPaned',$_[0]); },
		Prefix	=> qr/([_+]*)/,
		Pack	=> \&PanedPack,
	},
	VP	=>
	{	New	=> sub { PanedNew('Gtk2::VPaned',$_[0]); },
		Prefix	=> qr/([_+]*)/,
		Pack	=> \&PanedPack,
	},
	TB	=>	#tabbed	#deprecated
	{	New	=> \&NewTB,
		Prefix	=> qr/((?:"[^"]*[^\\]")|[^ ]*)\s+/,
		Pack	=> \&PackTB,
	},
	NB	=>	#tabbed 2
	{	New	=> sub { Layout::NoteBook->new(@_); },
		Pack	=> \&Layout::NoteBook::Pack,
		EndInit	=> \&Layout::NoteBook::EndInit,
	},
	MB	=>
	{	New	=> sub { Gtk2::MenuBar->new },
		Pack	=> sub { $_[0]->append($_[1]); },
	},
	SM	=>	#submenu
	{	New	=> sub { my $item=Gtk2::MenuItem->new($_[0]{label}); my $menu=Gtk2::Menu->new; $item->set_submenu($menu); return $item; },
		Pack	=> sub { $_[0]->get_submenu->append($_[1]); },
	},
	BM	=>	#button menu
	{	New	=> sub { Layout::ButtonMenu->new(@_); },
		Pack	=> sub { $_[0]->append($_[1]); },
	},
	EB	=>
	{	New	=> sub { my $self=Gtk2::Expander->new($_[0]{label}); $self->set_expanded($_[0]{expand}); $self->{SaveOptions}=sub { expand=>$_[0]->get_expanded; }; return $self; },
		Pack	=> \&SimpleAdd,
	},
	FB	=>
	{	New	=> sub { SFixed->new; },
		Prefix	=> qr/^(-?\.?\d+,-?\.?\d+(?:,\.?\d+,\.?\d+)?),?\s+/, # "5,4 " or "-5,.4,5,.2 "
		Pack	=> \&Fixed_pack,
	},
	FR	=>
	{	New	=> sub { my $f=Gtk2::Frame->new($_[0]{label}); $f->set_shadow_type($_[0]{shadow}) if $_[0]{shadow};return $f; },
		Pack	=> \&SimpleAdd,
	},
	SB	=>
	{	New	=> sub { my $sw=Gtk2::ScrolledWindow->new; },
		Pack	=> sub { $_[0]->add_with_viewport($_[1]); },
	},
	AB	=>
	{	New	=> sub { my %opt=(xalign=>.5, yalign=>.5, xscale=>1, yscale=>1, %{$_[0]}); Gtk2::Alignment->new(@opt{qw/xalign yalign xscale yscale/});},
		Pack	=> \&SimpleAdd,
	},
	WB	=>
	{	New	=> sub { Gtk2::EventBox->new; },
		Pack	=> \&SimpleAdd,
	},
);

sub SimpleAdd
{	 $_[0]->add($_[1]);
}

sub NewTB
{	my ($opt)=@_;
	my $nb=Gtk2::Notebook->new;
	$nb->set_scrollable(::TRUE);
	$nb->popup_enable;
	#$nb->signal_connect( button_press_event => sub {return !::IsEventInNotebookTabs(@_);});
	if (my $p=$opt->{tabpos})	{ $nb->set_tab_pos($p); }
	if (my $p=$opt->{page})		{ $nb->{SetPage}=$p; }
	$nb->{SaveOptions}=sub { page => $_[0]->get_current_page };
	return $nb;
}
sub PackTB
{	my ($nb,$wg,$title)=@_;
	$title=~s/^"// && $title=~s/"$//;
	$nb->append_page($wg, Gtk2::Label->new($title) );
	$nb->set_tab_reorderable($wg,::TRUE);
	my $n=$nb->{SetPage}||0;
	if ($n==($nb->get_n_pages-1)) {$wg->show; $nb->set_current_page($n); $nb->{DefaultFocus}=$wg; }
}

sub SBoxPack
{	my ($box,$wg,$opt)=@_;
	my $pad= $opt=~m/([0-9]+)/ ? $1 : 0;
	my $exp= $opt=~m/_/;
	my $end= $opt=~m/-/;
	my $fill=$opt!~m/\./;
	if ($end)	{ $box->pack_end(   $wg,$exp,$fill,$pad ); }
	else		{ $box->pack_start( $wg,$exp,$fill,$pad ); }
	if ($Gtk2::VERSION<1.163 || $Gtk2::VERSION==1.170) { $wg->{SBOX_packoptions}=[$exp,$fill,$pad, ($end ? 'end' : 'start')]; } #to work around memory leak (gnome bug #498334)
}

sub PanedPack
{	my ($paned,$wg,$opt)=@_;
	my $expand= $opt=~m/_/;
	my $shrink= $opt!~m/\+/;
	if	(!$paned->child1)	{$paned->pack1($wg,$expand,$shrink);}
	elsif	(!$paned->child2)	{$paned->pack2($wg,$expand,$shrink);}
	else {warn "layout error : trying to pack more than 2 widgets in a paned container\n"}
}

sub PanedNew
{	my ($class,$opt)=@_;
	my $self=$class->new;
	::setlocale(::LC_NUMERIC, 'C');
	($self->{size1},$self->{size2})= map $_+0, split /-|_/, $opt->{size} if defined $opt->{size};	# +0 to make the conversion to numeric while LC_NUMERIC is set to C
	::setlocale(::LC_NUMERIC, '');
	if (defined $self->{size1})
	{	$self->set_position($self->{size1});
		$self->set('position-set',1); # in case $self->{size1}==0 'position-set' is not set to true if child1's size is 0 (which is the case here as child1 doesn't exist yet)
	}
	$self->{SaveOptions}=sub { ::setlocale(::LC_NUMERIC, 'C'); my $s=$_[0]{size1}; $s.='-'. $_[0]{size2} if $_[0]{size2}; ::setlocale(::LC_NUMERIC, ''); return size => $s };
	$self->signal_connect(size_allocate => \&Paned_size_cb ); #needed to correctly save/restore the handle position
	return $self;
}

sub Paned_size_cb
{	my $self=shift;
	my $max=$self->get('max-position');
	return unless $max;
	my $size1=$self->{size1};
	my $size2=$self->{size2};
	if (defined $size1 && defined $size2 && abs($max-$size1-$size2)>5 || $self->{need_resize})
	{	my $not_enough;
		if    ($self->child1_resize && !$self->child2_resize)		{ $size1= ::max($max-$size2,0); $not_enough= $size2>$max; }
		elsif ($self->child2_resize && !$self->child1_resize)		{ $size1= $max if $not_enough= $size1>$max; }
		else								{ $size1= $max*$size1/($size1+$size2); }
		if ($not_enough)	#don't change the saved value if couldn't restore the size properly
		{	$self->{need_resize}=1;	#  => will retry in a later size_allocate event unless the position is set manually
		}
		else
		{	$self->set_position( $size1 );
			$self->{size1}= $size1;
			$self->{size2}= $max-$size1;
			delete $self->{need_resize};
		}
	}
	else { my $size1=$self->get_position; $self->{size1}=$size1; $self->{size2}=$max-$size1; delete $self->{need_resize}; }
}

sub Fixed_pack
{	my ($self,$wg,$opt)=@_;
	if (my ($x,$y,$w,$h)= $opt=~m/^(-?\.?\d+),(-?\.?\d+)(?:,(\.?\d+),(\.?\d+))?/)
	{	if ($1=~m/[-.]/ || $2=~m/[-.]/) { $wg->{SFixed_dynamic_pos}=[$x,$y]; $self->put($wg,0,0);}
		else {$self->put($wg,$x,$y); }
		if ($w||$h)
		{	if ($w=~m/\./ || $h=~m/\./) { $wg->{SFixed_dynamic_size}=[$w,$h]; }
			else
			{	my ($w2,$h2)=$wg->get_size_request;
				$wg->set_size_request($w||$w2,$h||$h2);
			}
		}
	}
	else { warn "Invalid position '$opt' for widget $wg\n" }
}

package SFixed;
use Glib::Object::Subclass
	Gtk2::Fixed::,
	signals =>
	{	size_allocate => \&size_allocate,
	};
sub size_allocate
{	my ($self,$alloc)=@_;
	my ($ox,$oy,$w,$h)=$alloc->values;
	my $border=$self->get_border_width;
	$ox+=$border; $w-=$border*2;
	$oy+=$border; $h-=$border*2;
	for my $child ($self->get_children)
	{	my ($x,$y)=$self->child_get_property($child,qw/x y/);
		if (my $ref=$child->{SFixed_dynamic_pos})
		{	my ($x2,$y2)=@$ref;
			$x=~m/\./ and $x*=$w;
			$x2=~m/\./ and $x2=int($x2*$w);
			$y2=~m/\./ and $y2=int($y2*$h);
			$x2=~m/^-/ and $x2+=$w;
			$y2=~m/^-/ and $y2+=$h;
			if ($x2!=$x || $y2!=$y) { $self->move($child,$x=$x2,$y=$y2); }
		}
		my ($ww,$wh);
		if (my $ref=$child->{SFixed_dynamic_size})
		{	($ww,$wh)=@$ref;
			$ww=~m/\./ and $ww*=$w;
			$wh=~m/\./ and $wh*=$h;
		}
		$ww||=$child->size_request->width;
		$wh||=$child->size_request->height;
		$child->size_allocate(Gtk2::Gdk::Rectangle->new($ox+$x, $oy+$y, $ww,$wh));
	}
}

package Layout::NoteBook;
use base 'Gtk2::Notebook';

our @contextmenu=
(	{ label => _"New list",		code => sub { $_[0]{self}->newtab('EditList',1,{songarray=>''}); },	type=> 'L', stockicon => 'gtk-add', },
	{ label => _"Open Queue",	code => sub { $_[0]{self}->newtab('QueueList',1); },			type=> 'L', stockicon => 'gmb-queue',
		test => sub { !grep $_->{name} eq 'QueueList', $_[0]{self}->get_children } },
	{ label => _"Open Playlist",	code => sub { $_[0]{self}->newtab('PlayList',1); },			type=> 'L', stockicon => 'gtk-media-play',
		test => sub { !grep $_->{name} eq 'PlayList', $_[0]{self}->get_children } },
	{ label => _"Open existing list", code => sub { $_[0]{self}->newtab('EditList',1, {songarray=>$_[1]}); },	type=> 'L',
		submenu => sub { my %h; $h{ $_->{array}->GetName }=1 for grep $_->{name}=~m/^EditList\d*$/, $_[0]{self}->get_children; return [grep !$h{$_}, ::GetListOfSavedLists()]; } },
	{ label => _"Open page layout", code => sub { $_[0]{self}->newtab('@'.$_[1],1); },		type=> 'P',
		submenu => sub { Layout::get_layout_list('P') }, submenu_tree=>1, },
	{ label => _"Open context page",								type=> 'C',
		submenu => sub { $_[0]{self}->make_widget_list('context page'); },	submenu_reverse=>1,
		code	=> sub { $_[0]{self}->newtab($_[1],1); },
	},
	{ label => _"Delete list", code => sub { $_[0]{page}->DeleteList; },	type=> 'L',  istrue=>'page',	test => sub { $_[0]{page}{name}=~m/^EditList\d*$/; } },
	{ label => _"Rename",	code => \&pagerename_cb,				istrue => 'rename',},
	{ label => _"Close",	code => sub { $_[0]{self}->close_tab($_[0]{page},1); },	istrue => 'close',	stockicon=> 'gtk-close',},
);

our @DefaultOptions=
(	closebuttons	=> 1,
	tablist		=> 1,
	newbutton	=> 'end',
);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::Notebook->new, $class;
	%$opt=( @DefaultOptions, %$opt );
	$self->set_scrollable(1);
	$self->set_tab_hborder(0);
	$self->set_tab_vborder(0);
	if (my $tabpos=$opt->{tabpos})
	{	($tabpos,$self->{angle})= $tabpos=~m/^(left|right|top|bottom)?(90|180|270)?/;
		$self->set_tab_pos($tabpos) if $tabpos;
	}
	$self->set_show_tabs(0) if $opt->{hidetabs};
	$opt->{typesubmenu}='LPC' unless exists $opt->{typesubmenu};
	$self->{$_}=$opt->{$_} for qw/group default_child match pages page typesubmenu closebuttons tablist/;
	for my $class (qw/list context layout/)	# option begining with list_ / context_ / layout_ will be passed to children of this class
	{	my @opt1;
		if (my $optkeys=$opt->{'options_for_'.$class})	#no need for a prefix for these options
		{	push @opt1, $_=> $opt->{$_} for grep exists $opt->{$_}, split / /,$optkeys;
		}
		push @opt1, $_=> $opt->{$class.'_'.$_} for map m/^${class}_(.+)/, keys %$opt;
		$self->{children_opt1}{$class}={ @opt1 };
	}
	$self->signal_connect(switch_page => \&SwitchedPage);
	$self->signal_connect(button_press_event => \&button_press_event_cb);
	::Watch($self, SavedLists=> \&SavedLists_changed);
	::Watch($self, Widgets => \&Widgets_changed_cb);
	$self->{groupcount}=0;
	$self->{SaveOptions}=\&SaveOptions;
	$self->{widgets}={};
	$self->{widgets_opt}= $opt->{page_opt} ||={};
	if (my $bl=$opt->{blacklist})
	{	$self->{blacklist}{$_}=undef for split / +/, $bl;
	}
	$opt->{newbutton}=0 unless *Gtk2::Notebook::set_action_widget{CODE}; # Gtk2::Notebook::set_action_widget requires gtk+ >= 2.20 and perl-Gtk2 >= 1.23
	if ($opt->{typesubmenu} && $opt->{newbutton} && $opt->{newbutton} ne 'none') # add a button next to the tabs to show new-tab menu
	{	my $button= ::NewIconButton('gtk-add');
		$button->signal_connect(button_press_event => \&newbutton_cb);
		$button->signal_connect(clicked => \&newbutton_cb);
		$button->show_all;
		my $pos= $opt->{newbutton} eq 'start' ? 'start' : 'end';
		$self->set_action_widget($button,$pos);
	}
	return $self;
}
sub SaveOptions
{	my $self=shift;
	my $i= $self->get_current_page;
	my @children= $self->get_children;
	my @dyn_widgets=values %{ $self->{widgets} };
	my @pages;
	for my $child (@children)
	{	my $name=$child->{name};
		$name='+'.$name if grep $_==$child, @dyn_widgets;
		push @pages,$name;
	}
	my @opt=
	(	page	=> $pages[$i],
		pages	=> join(' ',@pages),
		page_opt=> Layout::SaveWidgetOptions( @dyn_widgets ),
	);
	if (my $bl=$self->{blacklist})
	{	push @opt, blacklist=>join (' ',sort keys %$bl) if keys %$bl;
	}
	return @opt;
}

sub EndInit
{	my $self=shift;
	my %pagewidget;
	$pagewidget{ $_->{name} }=$_ for $self->get_children;
	if (my $pages=delete $self->{pages})
	{	my @pagelist=split / +/,$pages;
		$pagewidget{"+$_"}=$self->newtab($_) for map m/^\+(.+)$/, @pagelist;	#recreate dynamic pages (page name begin with +)
		my $i=0;
		$self->reorder_child($_,$i++) for grep $_, map $pagewidget{$_}, @pagelist;	#reorder pages to the saved order
	}
	if (my $name=delete $self->{page})	#restore selected tab
	{	if (my $page= $pagewidget{$name})
		{	$page->show;	 #needed to set as current page
			$self->set_current_page( $self->page_num($page) );
		}
	}
	$self->Widgets_changed_cb('init') if $self->{match};
	$self->insert_default_page unless $self->get_children;
}

sub newtab
{	my ($self,$name,$setpage,$opt2)=@_;
	$self->SaveOptions if $setpage;	#used to save default options of SongTree/SongList before creating a new one
	my $wtype= $name; $wtype=~s/\d+$//;
	$wtype= $Layout::Widgets{$wtype} || {};
	my $wclass= $wtype->{issonglist} ? 'list' : $name=~m/^@/ ? 'layout' : 'context';
	my $group=$self->{group};
	$group= 'Global('.::refaddr($self).'-'.$self->{groupcount}++.')' if $wclass eq 'list'; # give songlist/songtree their own group
	if ($opt2)	#new widget => use a new name not already used
	{	my $n=0;
		$n++ while $self->{widgets}{$name.$n} || $self->{widgets_opt}{$name.$n};
		$name.=$n;
	}
	else { $opt2= $self->{widgets_opt}{$name}; }
	return if $self->{widgets}{$name};

	my $opt1= $self->{children_opt1}{$wclass} || {};
	my $widget= Layout::NewWidget($name,$opt1,$opt2, {default_group=>$group});
	return unless $widget;
	$self->{widgets}{$name}=$widget;
	$widget->{tabcanclose}=1;
	delete $self->{blacklist}{$name};
	$self->Pack($widget);
	$widget->show_all;
	$self->set_current_page( $self->get_n_pages-1 ) if $setpage; #set current page to the new page
	return $widget;
}

sub Pack
{	my ($self,$wg)=@_;
	if (delete $self->{chooser_mode}) { $self->remove($_) for $self->get_children; }
	my $angle= $self->{angle} || 0;
	my $label= $wg->{tabtitle};
	if (!defined $label)			{ $label= $wg->{name} } #FIXME ? what to do if no tabtitle given
	elsif (ref $label eq 'CODE')		{ $label= $label->($wg); }
	elsif ($wg->can('DynamicTitle'))	{ $label= $wg->DynamicTitle($label); }
	$label=Gtk2::Label->new($label) unless ref $label;
	$label->set_angle($angle) if $angle;
	::weaken( $wg->{tab_page_label}=$label ) if $wg->{tabrename};

	# set base gravity to auto so that rotated tabs handle vertical scripts (asian languages) better
	$label->get_pango_context->set_base_gravity('auto');
	$label->signal_connect(hierarchy_changed=> sub { $_[0]->get_pango_context->set_base_gravity('auto'); }); # for some reason (gtk bug ?) the setting is reverted when the tab is dragged, so this re-set it

	my $icon= $wg->{tabicon};
	$icon=Gtk2::Image->new_from_stock($icon,'menu') if defined $icon;
	my $close;
	if ($wg->{tabcanclose} && $self->{closebuttons})
	{	$close=Gtk2::Button->new;
		$close->set_relief('none');
		$close->can_focus(0);
		::weaken( $close->{page}=$wg );
		$close->signal_connect(clicked => sub {my $page=$_[0]{page}; my $self=$page->parent; $self->close_tab($page,1);});
		$close->add(Gtk2::Image->new_from_file(::PIXPATH.'smallclosetab.png'));
		$close->set_size_request(Gtk2::IconSize->lookup('menu'));
		$close->set_border_width(0);
	}
	my $tab= $angle%180 ? Gtk2::VBox->new(0,0) : Gtk2::HBox->new(0,0);
	my @icons= $angle%180 ? ($close,0,$icon,4) : ($icon,4,$close,0);
	my ($i,$pad)=splice @icons,0,2;
	$tab->pack_start($i,0,0,$pad) if $i;
	$tab->pack_start($label,1,1,2);
	($i,$pad)=splice @icons,0,2;
	$tab->pack_start($i,0,0,$pad) if $i;
	$self->append_page($wg,$tab);
	$self->set_tab_reorderable($wg,1);
	$tab->show_all;
}

sub insert_default_page
{	my $self=shift;
	return if $self->get_children;
	$self->newtab( $self->{default_child} ) if $self->{default_child};
	::IdleDo('5_create_chooser_page',500, \&create_chooser_page, $self) if !$self->get_children && $self->{match};
}

sub close_tab
{	my ($self,$page,$manual)=@_;
	my $name=$page->{name};
	delete $self->{widgets}{$name};
	if ($manual && $self->{match} && $Layout::Widgets{$name} && $Layout::Widgets{$name}{autoadd_type}) { $self->{blacklist}{$name}=undef }
	my $opt=$self->{widgets_opt};
	my $pageopt= Layout::SaveWidgetOptions($page);
	%$opt= ( %$opt, %$pageopt );
	$self->remove($page);
	delete $self->{DefaultFocus} if $self->{DefaultFocus} && $self->{DefaultFocus}==$page;
	$self->insert_default_page unless $self->get_children;
}

sub SavedLists_changed	#remove EditList tab if corresponding list has been deleted
{	my ($self,$name,$action)=@_;
	return unless $action && $action eq 'remove';
	my @remove=grep $_->{name}=~m/^EditList\d*$/ && !defined $_->{array}->GetName, $self->get_children;
	$self->close_tab($_) for @remove;
}

sub newbutton_cb
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	::PopupContextMenu(\@contextmenu, { self=>$self, type=>$self->{typesubmenu}, usemenupos=>1 } );
	1;
}
sub button_press_event_cb
{	my ($self,$event)=@_;
	return 0 if $event->button != 3;
	return 0 unless ::IsEventInNotebookTabs($self,$event); #to make right-click on tab arrows work
	my $pagenb=$self->get_current_page;
	my $page=$self->get_nth_page($pagenb);
	#my $listname= $page? $page->{tabbed_listname} : undef;
	my @menu;
	my @opt=
	(	self=> $self, page=> $page,	type => $self->{typesubmenu},
		'close'=> $page->{tabcanclose}, 'rename' => $page->{tabrename},
	);
	push @menu, @contextmenu;
	if ($self->{tablist} && !$self->{chooser_mode})
	{	push @menu, { separator=>1 };
		for my $page ($self->get_children)	#append page list to menu
		{	my $label= $page->{tab_page_label} ? $page->{tab_page_label}->get_text : $page->{tabtitle};
			my $icon= $page->{tabicon};
			my $i= $self->page_num($page);
			my $cb= sub { $_[0]{self}->set_current_page($i); };
			push @menu, {label=>$label, stockicon=>$icon, code=> $cb, };
		}
	}

	::PopupContextMenu(\@menu, { @opt } );
	return 1;
}

sub pagerename_cb
{	my $page=$_[0]{page};
	my $tab=$_[0]{self}->get_tab_label($page);
	my $renamesub=$_[0]{'rename'};
	my $label=$page->{tab_page_label};
	my $entry=Gtk2::Entry->new;
	$entry->set_has_frame(0);
	$entry->set_inner_border(undef) if *Gtk2::Entry::set_inner_border{CODE}; #Gtk2->CHECK_VERSION(2,10,0);
	$entry->set_text( $label->get_text );
	$entry->set_size_request( 20+$label->allocation->width ,-1);
	$_->hide for grep !$_->isa('Gtk2::Image'), $tab->get_children;
	$tab->pack_start($entry,::FALSE,::FALSE,2);
	$entry->grab_focus;
	$entry->show_all;
	$entry->signal_connect(key_press_event => sub #abort if escape
		{	my ($entry,$event)=@_;
			return 0 unless Gtk2::Gdk->keyval_name( $event->keyval ) eq 'Escape';
			$entry->set_text('');
			$entry->set_sensitive(0);  #trigger the focus-out event
			1;
		});
	$entry->signal_connect(activate => sub {$_[0]->set_sensitive(0)}); #trigger the focus-out event
	$entry->signal_connect(populate_popup => sub { ::weaken($_[0]{popupmenu}=$_[1]); });
	$entry->signal_connect(focus_out_event => sub
	 {	my $entry=$_[0];
		my $popupmenu= delete $entry->{popupmenu};
		return 0 if $entry->get_display->pointer_is_grabbed && $popupmenu && $popupmenu->mapped; # prevent error when context menu of the entry pops-up
		my $new=$entry->get_text;
		$tab->remove($entry);
		$_->show for $tab->get_children;
		if ($new ne '')				#user has entered new name -> do the renaming
		{	$renamesub->($label,$new);
		}
		0;
	 });
}

sub create_chooser_page
{	my $self=shift;
	return if $self->get_children && !$self->{chooser_mode};
	$self->remove($_) for $self->get_children;	#remove a previous version of this page
	my $list= $self->make_widget_list;
	return unless keys %$list;
	$self->{chooser_mode}=1;
	my $cb=sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->newtab($_[1]); };
	my $bbox=Gtk2::VButtonBox->new;
	$bbox->set_layout('start');
	for my $name (sort { $list->{$a} cmp $list->{$b} } keys %$list)
	{	my $button=Gtk2::Button->new($list->{$name});
		$button->signal_connect(clicked=> $cb,$name);
		$bbox->add($button);
	}
	$bbox->show_all;
	$bbox->{name}='';
	$self->append_page($bbox,_"Choose page to open");
}

sub make_widget_list
{	my ($self,$match,@names)=@_;
	$match ||= $self->{match};
	return unless $match;
	my @match=	$match=~m/(?<!-)\b(\w+)\b/g;	#words not preceded by -
	my @matchnot=	$match=~m/-(\w+)\b/g;		#words preceded by -
	my $wdef=\%Layout::Widgets;
	@names= @names?  grep $wdef->{$_}, @names : keys %$wdef;
	@names=grep $wdef->{$_}{autoadd_type}, @names;
	my %ok;
	for my $name (@names)
	{	next if grep $name eq $_->{name}, $self->get_children;	#or use $self->{widgets}{$name} ?
		my $autoadd=$wdef->{$name}{autoadd_type};
		my %h; $h{$_}=1 for split / +/,$autoadd;
		next if grep !$h{$_}, @match;
		next if grep  $h{$_}, @matchnot;
		$ok{$name}=$wdef->{$name}{tabtitle};
	}
	return \%ok;
}
sub Widgets_changed_cb		#new or removed widgets => check if a widget should be added or removed
{	my ($self,$changetype,@widgets)=@_;
	if ($changetype eq 'remove')
	{	for my $name (@widgets)
		{	$self->close_tab($_) for grep $name eq $_->{name}, $self->get_children;
		}
		return
	}
	my $match=$self->{match};
	return unless $match;
	@widgets=keys %Layout::Widgets unless @widgets;
	@widgets=sort grep $Layout::Widgets{$_}{autoadd_type}, @widgets;
	for my $name (@widgets)
	{	my $ref=$Layout::Widgets{$name};
		my $add;
		if (my $autoadd= $ref->{autoadd_type})
		{	#every words in $match must be in $autoadd, except for words starting with - that must not
			my %h; $h{$_}=1 for split / +/,$autoadd;
			next if grep !$h{$_}, $match=~m/(?<!-)\b(\w+)\b/g;
			next if grep  $h{$_}, $match=~m/-(\w+)\b/g;
			$add=1;
		}
		if (my $opt=$ref->{autoadd_option}) { $add=$::Options{$opt} }
		my @already= grep $name eq $_->{name}, $self->get_children;
		if ($add)
		{	next if exists $self->{blacklist}{$name};
			$self->newtab($name,0,undef,1) unless @already;
		}
		else
		{	$self->close_tab($_) for @already;
		}
	}
	::IdleDo('5_create_chooser_page',500, \&create_chooser_page, $self) if !$self->get_children || $self->{chooser_mode};
}

sub SwitchedPage
{	my ($self,undef,$pagenb)=@_;
	delete $self->{DefaultFocus};
	if (defined(my $group=delete $self->{active_group}))
	{	::UnWatch($self,'SelectedID_'.$group);
		::UnWatch($self,'Selection_'.$group);
		#::UnWatchFilter($self,$group);
	}
	my $page=$self->get_nth_page($pagenb);
	::weaken( $self->{DefaultFocus}=$page );
	my $metagroup= $self->{group};
	return if !$page->{group} || $page->{group} eq $metagroup;
	my $group= $self->{active_group}= $page->{group};
	my $ID= ::GetSelID($group);
	::HasChangedSelID($metagroup,$ID) if defined $ID;
	if (my $songlist=$SongList::Common::Register{$group})
	{	$songlist->RegisterGroup($self->{group});
		::HasChanged('Selection_'.$self->{group});
		::Watch($self,'Selection_'.$group,  sub { ::HasChanged('Selection_'.$_[0]->{group}); });
		::HasChanged('SongArray',$songlist->{array},'proxychange');
	}
	# FIXME can't use WatchSelID, should special-case special groups : Play Recent\d *Next\d* ...
	::Watch($self,'SelectedID_'.$group, sub { my ($self,$ID)=@_; ::HasChangedSelID($self->{group},$ID) if defined $ID; });
	#::WatchFilter($self,$group, sub {  });
}

package Layout::PlaceHolder;

our %PlaceHolders=
(	#ContextPages =>
	#{	event_Widgets => \&Widgets_changed_cb,
	#	match => 'context page',
	#	init => sub { $_[0]->Widgets_changed_cb('init'); },
	#},
	ExtraButtons =>
	{	event_Widgets => \&Widgets_changed_cb,
		match => 'button main',
		init => sub { $_[0]->Widgets_changed_cb('init'); },
	},
);


sub new
{	my ($class,$boxfunc,$box,$ph,$packoptions)=@_;
	my $name= $ph->{name};
	$name=~s/\d+$//;
	my $type= $PlaceHolders{$name};
	unless ($type)
	{	return Layout::PlaceHolder::Single->new($boxfunc,$box,$ph,$packoptions);
	}
	bless $ph,$class;
	::weaken( $ph->{boxwidget}=$box );
	$ph->{widgets}={};

	$ph->{$_}||=$type->{$_} for qw/match/;
	$ph->{SaveOptions}=\&SaveOptions;
	$ph->{widgets_opt}=delete $ph->{opt2}{widgets_opt};
	for my $event (grep m/^event_/, keys %$type)
	{	my $cb= $type->{$event};
		$event=~s/^event_//;
		::Watch($ph, $event, $cb);
	}

	$ph->{packsub}=		$boxfunc->{Pack};
	$ph->{packoptions}=	$packoptions;

	if (my $init=$type->{init}) { $init->($ph) }	#used to create children at creation time for some placeholders
	return $ph;
}
sub DESTROY
{	::UnWatch_all($_[0]);
}

sub SaveOptions
{	my $self=shift;
	my $opt= Layout::SaveWidgetOptions(values %{$self->{widgets}});
	return unless keys %$opt;
	return widgets_opt => $opt;

}

sub AddWidget
{	my ($ph,$name)=@_;
	return if $ph->{widgets}{$name};
	my $widget= Layout::NewWidget($name,$ph->{opt1},$ph->{widgets_opt}{$name}, { default_group => $ph->{group} });
	return unless $widget;
	$ph->{widgets}{$name}= $widget;
	$ph->{packsub}->($ph->{boxwidget},$widget, $ph->{packoptions});
	$widget->show_all;
	return $widget;
}
sub RemoveWidget
{	my ($ph,$name)=@_;
	$name=$name->{name} if ref $name;
	my $widget= delete $ph->{widgets}{$name};
	return unless $widget;
	my $opt=$ph->{widgets_opt}||={};
	%$opt= ( %$opt, %{ Layout::SaveWidgetOptions($widget) } );
	$ph->{boxwidget}->remove($widget);
}

sub Widgets_changed_cb		#new or removed widgets => check if a widget should be added or removed
{	my ($ph,$changetype,@widgets)=@_;
	@widgets=keys %Layout::Widgets unless @widgets;
	@widgets=sort grep $Layout::Widgets{$_}{autoadd_type}, @widgets;
	my $match=$ph->{match};
	for my $name (@widgets)
	{	my $ref=$Layout::Widgets{$name};
		my $add= $changetype ne 'remove' ? 1 : 0;
		if (my $autoadd= $ref->{autoadd_type})
		{	#every words in $match must be in $autoadd, except for words starting with - that must not
			my %h; $h{$_}=1 for split / +/,$autoadd;
			next if grep !$h{$_}, $match=~m/(?<!-)\b(\w+)\b/g;
			next if grep  $h{$_}, $match=~m/-(\w+)\b/g;
		}
		if (my $opt=$ref->{autoadd_option}) { $add=$::Options{$opt} }
		if ($add)
		{	my $widget= $ph->AddWidget($name);
		}
		else
		{	$ph->RemoveWidget($name);
		}
	}
}

sub Options_changed
{	my ($ph,$option)=@_;
	return unless exists $ph->{watchoptions}{$option};
	$ph->Widgets_changed_cb('optchanged');
}

package Layout::PlaceHolder::Single;
sub new
{	my ($class,$boxfunc,$box,$ph,$packoptions)=@_;
	bless $ph,$class;
	::weaken( $ph->{boxwidget}=$box );
	::Watch($ph, Widgets => \&Widgets_changed_cb);
	$ph->{packsub}=		$boxfunc->{Pack};
	$ph->{packoptions}=	$packoptions;
	return $ph;
}
sub DESTROY
{	::UnWatch_all(shift);
}

sub Widgets_changed_cb
{	my ($ph,$changetype,@widgets)=@_;
	my $name=$ph->{name};
	$name=~s/\d+$//;
	return unless grep $name eq $_, @widgets;
	if ($changetype eq 'new' && !$ph->{widget})
	{	my $widget= Layout::NewWidget($ph->{name},$ph->{opt1},$ph->{opt2}, { default_group => $ph->{group} });
		return unless $widget;
		$ph->{widget}= $widget;
		$ph->{SaveOptions}=\&SaveOptions;
		$ph->{packsub}->($ph->{boxwidget},$widget, $ph->{packoptions});
		$widget->show_all;
	}
	elsif ($changetype eq 'remove' && $ph->{widget})
	{	my $widget= delete $ph->{widget};
		$ph->{opt2}= Layout::SaveWidgetOptions($widget);
		$ph->{boxwidget}->remove($widget);
		delete $ph->{SaveOptions};
	}
}

sub SaveOptions
{	my $ph=shift;
	Layout::SaveWidgetOptions($ph->{widget});
}

package Layout::Button;
use base 'Gtk2::Bin';

our @default_options= (button=>1, relief=>'none', size=> Layout::SIZE_BUTTONS, ellipsize=> 'none', );

sub new
{	my ($class,$opt,$ref)=@_;
	%$opt=( @default_options, %$opt );
	my $isbutton= $opt->{button};
	my $self;
	my $activate= $opt->{activate};
	if ($isbutton)
	{	$self=Gtk2::Button->new;
		$self->set_relief($opt->{relief});
		$self->{clicked_cmd}= $activate;
		$self->signal_connect(clicked => \&clicked_cb);
	}
	else
	{	$self=Gtk2::EventBox->new;
		$self->set_visible_window(0);
		$opt->{click} ||= $activate;
	}
	bless $self, $class;
	my $text= $opt->{text} || $opt->{label};
	my $stock= $opt->{stock};
	if (!ref $stock && $ref->{'state'})
	{	my $default= $ref->{stock};
		my %hash;
		%hash = %$default if ref $default eq 'HASH'; #make a copy of the default setting if it is a hash
		# extract icon(s) for each state using format : "state1: icon1 facultative_icon2 state2: icon3"
		$hash{$1}=$2 while $stock=~s/(\w+) *: *([^:]+?) *$//;
		$stock=\%hash;
		#if default setting is a function, use a function that look in the hash, and fallback to the default function (this is the case for Queue and VolumeIcon widgets)
		$stock= sub { $hash{$_[0]} || &$default } if ref $default eq 'CODE';
	}
	$self->{state}=$ref->{state} if $ref->{state};
	if ($opt->{skin})
	{	my $skin=Skin->new($opt->{skin},$self,$opt);
		$self->signal_connect(expose_event => \&Skin::draw,$skin);
		$self->{skin}=1; # will force a repaint on stock state change
		$self->set_app_paintable(1); #needed ?
		if (0 && !$isbutton && $opt->{shape}) #mess up button-press cb TESTME
		{	$self->{shape}=1;
		}
	}
	elsif ($stock)
	{	$self->{stock}=$stock;
		$self->{size}= $opt->{size};
		my $img= $self->{img}= Gtk2::Image->new;
		$img->set_size_request(Gtk2::IconSize->lookup($self->{size})); #so that it always request the same size, even when no icon
		if ($opt->{with_text})
		{	my $hbox=Gtk2::HBox->new(0,2);
			my $label= $self->{label}= Gtk2::Label->new;
			my $ellip= $opt->{ellipsize};
			$ellip='end' if $ellip eq '1';
			$label->set_ellipsize($ellip);
			$self->{string}= $text || $opt->{tip};
			$self->{markup}= $opt->{markup} || ($opt->{size} eq 'menu' ? "<small>%s</small>" : "%s");
			$hbox->pack_start($img,0,0,0);
			$hbox->pack_start($label,1,1,0);
			$self->add($hbox);
		}
		else { $self->add($img); }
		$self->{EndInit}=\&UpdateStock;
	}
	elsif (defined $text) { $self->add( Gtk2::Label->new($text) ); }
	return $self;
}

sub clicked_cb
{	my $self=$_[0];
	my $sub=$self->{clicked_cmd};
	return 0 unless $sub;
	if (ref $sub)	{&$sub}
	else		{ ::run_command($self,$sub) }
	1;
}

sub UpdateStock
{	my ($self,undef,$index)=@_;
	my $stock=$self->{stock};
	if (my $state=$self->{state})
	{	$state=&$state;
		$stock = (ref $stock eq 'CODE')? $stock->($state) : $stock->{$state};
	}
	if ($stock=~m/ /)
	{	$stock= (split /\s+/,$stock)[ $index || 0 ];
		$stock='' if $stock eq '.'; #needed ? the result is the same : no icon
		unless (exists $self->{hasenterleavecb})
		{	$self->{hasenterleavecb}=undef;
			$self->signal_connect(enter_notify_event => \&UpdateStock,1);
			$self->signal_connect(leave_notify_event => \&UpdateStock);
		}
	}
	$self->{img}->set_from_stock($stock,$self->{size});
	if (my $l=$self->{label})
	{	my $string=$self->{string};
		$string= $string->() if ref $string eq 'CODE';
		$l->set_markup_with_format($self->{markup},$string);
	}
	0;
}

package Layout::Label;
use base 'Gtk2::EventBox';

use constant	INCR => 1;	#scroll increment in pixels
our @default_options= ( xalign=>0, yalign=>.5, );

sub new
{	my ($class,$opt)=@_;
	%$opt=( @default_options, %$opt );
	my $self = bless Gtk2::EventBox->new, $class;
	my $label=Gtk2::Label->new;
	$label->set_alignment($opt->{xalign},$opt->{yalign});
	$self->set_visible_window(0);

	for (qw/markup markup_empty autoscroll interval/)
	{	$self->{$_}=$opt->{$_} if exists $opt->{$_};
	}

	my $font= $opt->{font} && Gtk2::Pango::FontDescription->from_string($opt->{font});
	$label->modify_font($font) if $font;
	if (my $color= $opt->{color} || $opt->{DefaultFontColor})
	{	$label->modify_fg('normal', Gtk2::Gdk::Color->parse($color) );
	}
	$self->add($label);
#$self->signal_connect(enter_notify_event => sub {$_[0]->set_markup('<u>'.$_[0]->child->get_label.'</u>')});
#$self->signal_connect(leave_notify_event => sub {my $m=$_[0]->child->get_label; $m=~s#^<u>##;$m=~s#</u>$##; $_[0]->set_markup($m)});
	$self->{expand_max}= $opt->{maxwidth} || -1 if $opt->{expand_max};
	my $minsize= $opt->{minsize};
	if (my $el=$opt->{ellipsize})
	{	$label->set_ellipsize($el);
		$minsize=undef;
	}
	if ($minsize && $minsize=~m/^\d+p?$/)
	{	unless ($minsize=~s/p$//)
		{	my $lay=$label->create_pango_layout( 'X' x $minsize );
			$lay->set_font_description($font) if $font;
			($minsize)=$lay->get_pixel_size;
		}
		$self->set_size_request($minsize,-1);
		$label->signal_connect(expose_event => \&expose_cb);
		if ($self->{autoscroll})
		{	$self->{interval} ||=50;	# default to a scroll every 50ms
			$self->signal_connect(size_allocate => \&restart_scrollcheck);
		}
		else	# scroll when mouse is over it
		{	$self->{interval} ||=20;	# default to a scroll every 20ms
			$self->signal_connect(enter_notify_event => \&enter_leave_cb, INCR());
			$self->signal_connect(leave_notify_event => \&enter_leave_cb,-INCR());
		}
	}
	elsif (defined $opt->{initsize})
	{	#$label->set_size_request($label->create_pango_layout( $opt->{initsize} )->get_pixel_size);
		my $lay=$label->create_pango_layout( $opt->{initsize} );
		$lay->set_font_description($font) if $font;
		$label->set_size_request($lay->get_pixel_size);
		$self->{resize}=1;
	}
	if (exists $opt->{markup})
	{	my $m=$opt->{markup};
		if (my @fields=::UsedFields($m))
		{	$self->{EndInit}=\&init;	# needs $self->{group} set before this can be done
		}
		else { $self->set_markup($m) }
	}
	elsif (exists $opt->{text})
	{	$label->set_text($opt->{text});
	}

	return $self;
}

sub init
{	my $self=shift;
	::WatchSelID($self,\&update_text);
	update_text($self,::GetSelID($self));
}

sub update_text
{	my ($self,$ID)=@_;
	if ($self->{markup})
	{	my $markup=	defined $ID			? ::ReplaceFieldsAndEsc( $ID,$self->{markup} ) :
				defined $self->{markup_empty}	? $self->{markup_empty} :
				'';
		$self->set_markup($markup);
	}
}

sub set_label
{	my $label=$_[0]->child; $label->set_label($_[1]); $label->{dx}=0;
	$_[0]->checksize;
}
sub set_markup
{	my $label=$_[0]->child; $label->set_markup($_[1]); $label->{dx}=0;
	$_[0]->checksize;
}
sub set_markup_with_format
{	my $self=shift;
	$self->set_markup(::MarkupFormat(@_));
}
sub checksize	#extend the requested size so that the string fit in initsize mode (in case the initsize string is not wide enough)
{	my $self=$_[0];
	if ($self->{resize})
	{	my $label=$self->child;
		my ($w,$h)=$label->get_layout->get_pixel_size;
		my ($w0,$h0)=$label->get_size_request;
		$w=0 if $w0>$w;
		$h=0 if $h0>$h;
		$label->set_size_request($w||$w0,$h||$h0) if $w || $h;
	}
	elsif (my $emax=$self->{expand_max})
	{	# make it expand up to min(maxwidth,string_width)
		my $label=$self->child;
		$label->get_layout->set_width($emax * Gtk2::Pango->scale) if $label->get_ellipsize ne 'none';
		my ($w)= $label->get_layout->get_pixel_size;
		$w=$emax if $emax>0 && $emax < $w;
		$self->{maxwidth}= $w ||1;
	}
	$self->restart_scrollcheck if $self->{autoscroll};
}

sub restart_scrollcheck	#only used for autoscroll
{	my $self=shift;
	$self->{scroll_inc}||=INCR();
	$self->{scrolltimeout} ||= Glib::Timeout->add($self->{interval}, \&Scroll,$self);
}

sub enter_leave_cb
{	my ($self,$event,$inc)=@_;
	#$self->set_state($inc>0 ? 'selected' : 'normal');
	$self->{scrolltimeout}  ||= Glib::Timeout->add($self->{interval}, \&Scroll,$self);
	$self->{scroll_inc}=$inc;
	0;
}
sub expose_cb #only for scrollable labels
{	my ($label,$event)=@_;
	my $layout=$label->get_layout;
	my ($lw,$lh)=$layout->get_pixel_size;
	return 1 unless $lw; #empty string -> nothing to draw
	my ($xoffset,$yoffset,$aw,$ah)=$label->allocation->values;
	my ($xalign,$yalign)=$label->get_alignment;
	my ($xpad,$ypad)=$label->get_padding;
	$xoffset+=$xpad; $aw-=2*$xpad; $aw=0 if $aw<0;
	$yoffset+=$ypad; $ah-=2*$ypad; $ah=0 if $ah<0;
	$xoffset+=($aw-$lw)*$xalign if $aw>$lw;
	$yoffset+=($ah-$lh)*$yalign if $ah>$lh;
	$label->get_style->paint_layout($label->window, $label->state, ::FALSE, $event->area, $label, 'label', $xoffset-$label->{dx}, $yoffset, $layout);
	1;
}

sub Scroll
{	my $self=$_[0];
	my $label=$self->child;
	return 0 unless $label;
	my $aw=$label->allocation->width;
	my $max= ($label->get_layout->get_pixel_size)[0] - $aw;
	my $dx=$label->{dx};
	$dx+= $self->{scroll_inc};
	$dx=$max if $max<$dx;
	$dx=0 if $dx<0 || $max<0;
	$label->{dx}=$dx;
	$label->parent->queue_draw;
	my $reached_max= ($max<0) || ($dx==0 && $self->{scroll_inc}<0) || ($dx==$max && $self->{scroll_inc}>0);
	if ($self->{autoscroll})
	{	$self->{scroll_inc}=-$self->{scroll_inc} if $reached_max;	# reverse scrolling
		$self->{scrolltimeout}=$self->{scroll_inc}=0 if $max<0;		# no need for scrolling => stop checks
	}
	else
	{	$self->{scrolltimeout}=0 if $reached_max;
	}
	return $self->{scrolltimeout};
}

package Layout::Label::Time;
use base 'Layout::Label';

sub set_markup
{	my ($self,$markup)=@_;
	$self->{time_markup}=$markup;
	$self->update_time;
}
sub update_time
{	my ($self,$time)=@_;
	my $markup=$self->{time_markup};
	$time= $::PlayTime if !defined $time;
	if (defined $time)
	{	my $length= Songs::Get($::SongID,'length');
		my $format= $length<600? '%01d:%02d' : '%02d:%02d';
		if ($self->{remaining})
		{	$format= '-'.$format;
			$time= $length-$time;
		}
		$time= sprintf $format, $time/60, $time%60;
	}
	else
	{	$time= $self->{markup_stopped};
		return unless defined $time; # update_time() can be called before $self->{markup_stopped} is set, ignore
	}
	if ($markup)
	{	$markup=~s/%s/$time/;
	}
	else { $markup=$time }
	$self->SUPER::set_markup($markup);
}

package Layout::Bar;
use base 'Gtk2::ProgressBar';

sub new
{	my ($class,$opt,$ref)=@_;
	my $self=bless Gtk2::ProgressBar->new, $class;
	if ($opt->{text})
	{	$self->{text}=$opt->{text};
		$self->{text_empty}=$opt->{text_empty};
		$self->set_ellipsize( $opt->{ellipsize}||'end' );
		my $font= $opt->{font};
		$self->modify_font(Gtk2::Pango::FontDescription->from_string($font)) if $font;
	}
	my $orientation= $opt->{vertical} ? 'bottom-to-top' : $opt->{horizontal} ? 'left-to-right' : $opt->{orientation} || 'left-to-right';
	$self->set_orientation($orientation);
	if ($opt->{skin} && $opt->{handle_skin})
	{	$self= Layout::Bar::skin->new($opt) || $self;  # warning : replace $self
	}
	$self->add_events([qw/pointer-motion-mask button-press-mask button-release-mask scroll-mask/]);
	$self->signal_connect(button_press_event	=> \&button_press_cb);
	$self->signal_connect(button_release_event	=> \&button_release_cb);
	$self->signal_connect(scroll_event		=> \&scroll_cb);
	$self->{left} ||=0;
	$self->{right}||=0;
	$self->{max}= $ref->{max} || 1;
	$self->{scroll}=$ref->{scroll};
	$self->{set}=$ref->{set};
	$self->{set_preview}=$ref->{set_preview};
	$self->{vertical}= $orientation eq 'bottom-to-top';
	return $self;
}
sub set_val
{	$_[0]{now}=$_[1];
	$_[0]->update;
}
sub set_max
{	$_[0]{max}=$_[1];
	$_[0]->update;
}
sub update
{	my $self=$_[0];
	return if $self->{pressed};
	my $f= ($self->{now}||0) / ($self->{max}||1);
	$f=0 if $f<0; $f=1 if $f>1;
	$self->set_fraction($f);
	if (my $text=$self->{text})
	{	$text= $self->{text_empty} if !defined $::SongID && defined $self->{text_empty};
		my $now=$self->{now}||0;
		my $max=$self->{max}||0;
		my $format= $max<600 ? '%01d:%02d' : '%02d:%02d';
		my $left=$max-$now;
		$_=sprintf($format,int($_/60),$_%60) for $now,$max,$left;
		my %special=
		(	'$percent'	=> sprintf('%d',$f*100),
			'$current'	=> $now,
			'$left'		=> $left,
			'$total'	=> $max,
		);
		$text=::ReplaceFields( $::SongID,$text,0,\%special );
		$self->set_text($text);
	}
}
sub button_press_cb
{	my ($self,$event)=@_;
	$self->{pressed}||=$self->signal_connect(motion_notify_event => \&button_press_cb);
	my ($x,$w)= $self->{vertical} ?	($event->y, $self->allocation->height):
					($event->x, $self->allocation->width) ;
	$w=1 if $w<1;
	$w-= $self->{left} +$self->{right};
	$x-= $self->{left};
	my $f=$x/$w;
	$f=0 if $f<0; $f=1 if $f>1;
	$f=1-$f if $self->{vertical};
	$self->set_fraction($f);

	my $s= $f*$self->{max};
	$self->{newpos}=$s;
	my $sub= $self->{set_preview} || $self->{set};
	$sub->($self,$s);
	1;
}
sub button_release_cb
{	my ($self,$event)=@_;
	return 0 unless $self->{pressed};
	$self->signal_handler_disconnect(delete $self->{pressed});
	if ($self->{set_preview})
	{	$self->{set_preview}->($self, undef);
		$self->{set}->( $self, $self->{newpos} );
	}
	#$self->update;
	1;
}

sub update_preview_Time
{	my ($self,$value)=@_;

	my $h=::get_layout_widget($self)->{widgets};
	my @labels= grep $_->isa('Layout::Label::Time'), values %$h; #get list of Layout::Label::Time widgets in the layouts

	my $preview= defined $value ? 1 : 0;
	for my $label (@labels)
	{	$label->{busy}=$preview;
		$label->update_time($value) if $preview;
	}
}

sub scroll_cb
{	my ($self,$event)=@_;
	my $d= $event->direction;
	if	($d eq 'down'	|| $d eq 'right')	{ $d=1 }
	elsif	($d eq 'up'	|| $d eq 'left' )	{ $d=0 }
	else	{ return 0 }
	$d= !$d if $self->{vertical};
	$self->{scroll}->($self,$d);
	return 1;
}

package Layout::Bar::skin;
our @ISA=('Layout::Bar');
use base 'Gtk2::EventBox';

sub new
{	my ($class,$opt)=@_;
	my $self=bless Gtk2::EventBox->new,$class;
	my $hskin=$self->{handle_skin}=Skin->new($opt->{handle_skin},undef,$opt);
	my $bskin=$self->{back_skin}=  Skin->new($opt->{skin},undef,$opt);
	unless ($hskin && $bskin)
	{	warn "Error loading background skin='$opt->{skin}'\n" unless $bskin;
		warn "Error loading handle handle_skin='$opt->{skin}'\n" unless $hskin;
		return;
	}
	my $resize=$bskin->{resize};
	my ($left)= $resize=~m/l[es](\d+)/;
	my ($right)=$resize=~m/r[es](\d+)/;
	my ($top)=  $resize=~m/t[es](\d+)/;
	my ($bottom)=$resize=~m/b[es](\d+)/;
	$self->{left}=  $left ||= 0;
	$self->{right}= $right||= 0;
	$self->{top}=   $top  ||= 0;
	$self->{bottom}=$bottom||=0;
	$self->set_size_request($left+$right+$hskin->{minwidth},$top+$bottom+$hskin->{minheight});
	$self->signal_connect(expose_event=> \&expose_cb);
	return $self;
}

sub set_fraction
{	$_[0]{fraction}=$_[1];
	$_[0]->queue_draw;
}

sub expose_cb
{	my ($self,$event)=@_;
	Skin::draw($self,$event,$self->{back_skin});
	my ($w,$h)=($self->allocation->values)[2,3];
	if ($self->{vertical})
	{	my $minh=$self->{handle_skin}{minheight};
		$h-= $self->{top}+$self->{bottom};
		my $y= $self->{top} + $h *(1-$self->{fraction});
		$y-= $minh/2;
		Skin::draw($self,$event,$self->{handle_skin},$self->{left},int($y),$w-$self->{left}-$self->{right},$minh);
	}
	else
	{	my $minw=$self->{handle_skin}{minwidth};
		$w-= $self->{right}+$self->{left};
		my $x= $self->{left} + $w *$self->{fraction};
		$x-= $minw/2;
		Skin::draw($self,$event,$self->{handle_skin},int($x),$self->{top},$minw,$h-$self->{top}-$self->{bottom});
	}
	1;
}

package Layout::Bar::Scale;
use base 'Gtk2::Scale';

sub new
{	my ($class,$opt,$ref)=@_;
	my $scale= $opt->{orientation} || 'left-to-right';
	$scale= 'left-to-right' if $opt->{horizontal};
	$scale= 'bottom-to-top' if $opt->{vertical};
	$scale= $scale eq 'left-to-right' ? 'Gtk2::HScale' : 'Gtk2::VScale';
	my $max= $ref->{max} || 1;
	my $self = bless $scale->new_with_range(0,$max,$max/10), $class;
	$self->set_inverted(1) if $scale eq 'Gtk2::VScale';
	$self->{vertical}= $scale eq 'Gtk2::VScale';
	$self->{max}= $max;
	$self->{step_mode}=$opt->{step_mode};
	$self->set_draw_value(0);
	$self->signal_connect(button_press_event => \&button_press_cb);
	$self->signal_connect(button_release_event => \&button_release_cb);
	$self->signal_connect(scroll_event	=> \&Layout::Bar::scroll_cb);
	$self->{$_}=$ref->{$_} for qw/scroll set set_preview/;
	return $self;
}
sub set_val
{	$_[0]->set_value($_[1] || 0) unless $_[0]{pressed};
}
sub set_max
{	$_[0]->{max}=$_[1];
	$_[0]->get_adjustment->upper($_[1]);
}

sub button_press_cb
{	my ($self,$event)=@_;
	if (!$self->{step_mode})	# short-circuit normal Gtk2::Scale click behaviour
	{	$self->{pressed}= $self->signal_connect(motion_notify_event  => \&update_value_direct_mode);
		$self->update_value_direct_mode($event);
		return 1;		# return 1 so that Gtk2::Scale won't get the mouse click
	}
	$self->{pressed}= $self->signal_connect(value_changed  => \&value_changed_cb);
	return 0;
}

sub button_release_cb
{	my $self=$_[0];
	return 0 unless $self->{pressed};
	$self->signal_handler_disconnect( delete $self->{pressed} );
	if ($self->{set_preview})
	{	$self->{set_preview}->($self, undef);
		$self->{set}->( $self, $self->{newpos} );
	}
	0;
}

sub value_changed_cb
{	my $self=$_[0];
	my $s=$self->get_value;
	$self->{newpos}=$s;
	my $sub= $self->{set_preview} || $self->{set};
	$sub->($self,$s);
	1;
}

sub update_value_direct_mode
{	my ($self,$event)=@_;
	my ($x,$w)= $self->{vertical} ?	($event->y, $self->allocation->height):
					($event->x, $self->allocation->width) ;
	$w=1 if $w<1;
	my $f=$x/$w;
	$f=0 if $f<0; $f=1 if $f>1;
	$f=1-$f if $self->{vertical};
	$self->set_value( $f * $self->{max});
	$self->value_changed_cb;
	1;
}

package Layout::AAPicture;
use base 'Gtk2::EventBox';

our @default_options= (maxsize=>500, xalign=>.5, yalign=>.5, r_height=>25, r_alpha1=>80, r_alpha2=>0, r_scale=>90);

sub new
{	my ($class,$opt)=@_;
	%$opt=( @default_options, %$opt );
	my $self = bless Gtk2::EventBox->new, $class;
	$self->set_visible_window(0);
	$self->{aa}=$opt->{aa};
	my $minsize=$opt->{minsize};
	$self->{$_}=$opt->{$_} for qw/maxsize xalign yalign multiple/;

	$self->{usable_w}=$self->{usable_h}=1;
	my $ratio=1;
	if ( (my $refl=$opt->{reflection}) && $::CairoOK)
	{	$self->{$_}= $opt->{$_}/100 for qw/r_alpha1 r_alpha2 r_scale/;
		$self->{reflection}= $refl==1 ? $opt->{r_height}/100 : $refl/100;
		my $height= $self->{reflection} +1;
		$ratio/= $height;
		$self->{usable_h}/=$height;
	}
	if (my $o=$opt->{overlay})
	{{	my ($x,$y,$xy_or_wh,$w,$h,$file)= $o=~m/^(\d+)x(\d+)([-:])(\d+)x(\d+):(.+)/;
		unless (defined $file) { warn "Invalid picture-overlay string : '$o' (format: XxY:WIDTHxHEIGHT:FILE)\n"; last }
		$file= ::SearchPicture( $file, $opt->{PATH} );
		last unless $file;
		my $pb= GMB::Picture::pixbuf($file);
		last unless $pb;
		if ($xy_or_wh eq '-') { $w-=$x; $h-=$y; }
		my $w0=$pb->get_width;
		my $h0=$pb->get_height;
		warn "Bad picture-overlay values : rectangle bigger than the overlay picture\n" if $w0<$w+$x || $h0<$h+$y;
		my $ws= $w0/$w;
		my $hs= $h0/$h;
		$ratio*= $ws/$hs;
		$self->{usable_w}/= $ws;
		$self->{usable_h}/= $hs;
		$self->{overlay}=[$pb, $x/$w, $y/$h, $ws,$hs];
	}}
	if ($opt->{forceratio}) { $self->{forceratio}=$ratio; } #not sure it's still needed with the natural_size mode
	else
	{	$self->{expand_to_ratio}=$ratio;
		$self->{expand_weight}=10;
	}
	if (my $file=$opt->{'default'})
	{	$self->{'default'}= ::SearchPicture( $file, $opt->{PATH} );
	}
	$self->signal_connect(size_allocate => \&size_allocate_cb);
	$self->signal_connect(expose_event => \&expose_cb);
	$self->signal_connect(destroy => sub {delete $::ToDo{'8_LoadImg'.$_[0]}});
	$self->set_size_request($minsize,$minsize) if $minsize;
	$self->{key}=[];
	$self->{natural_size}=1 unless $minsize;
	$self->{ratio}=$ratio;
	return $self;
}

sub Changed
{	my ($self,$key)=@_;
	return unless grep $_ eq $key, @{$self->{key}};
	$self->set(delete $self->{key});
}

sub set
{	my ($self,$key)=@_;
	$key=[] unless defined $key;
	$key=[$key] unless ref $key;
	return if $self->{key} && join("\x1D", @$key) eq join("\x1D", @{$self->{key}});
	$self->{key}=$key;
	my $col=$self->{aa};
	my @files;
	for my $k (@$key)
	{	my $f=AAPicture::GetPicture($col,$k);
		push @files, $f if $f;
	}
	$self->{pixbuf}=undef;
	if ( !@files && (my $file=$self->{'default'}) ) { @files=($file); }	#default picture
	if (@files)
	{	 if (@files>1 && !$self->{multiple}) {$#files=0} # use only the first file if not in multiple mode
		$self->show;
		$self->queue_draw;
		::IdleDo('8_LoadImg'.$self,500,\&LoadImg,$self,@files);
	}
	else
	{	$self->hide unless $self->{natural_size};
	}
	$self->signal_connect('map'=>sub #undo the temporary settings set in size_allocate_cb for the natural_size mode #FIXME should be simpler
	{	my $self=$_[0];
		delete $self->{size} unless $self->{pixbuf} || $::ToDo{'8_LoadImg'.$self};
		$self->set_size_request(-1,-1) unless $self->{forceratio};
		$self->queue_resize;
	}) if $self->{natural_size};
}

sub LoadImg
{	my ($self,@files)=@_;
	my ($w,$h)=split /x/, $self->{size}||'0x0';
	$w*= $self->{usable_w};
	$h*= $self->{usable_h};
	my $size= ::min($w,$h);
	return if $size<8;	# no need to draw such a small picture
	$size=int $size/@files;
	my @pix= grep $_, map GMB::Picture::pixbuf($_,$size), @files;
	my $pix=shift @pix;
	if (@pix) { $pix=collage($self->{multiple},$pix,@pix); }
	$pix= $self->add_overlay($pix) if $pix && $self->{overlay};
	$self->{pixbuf}= $pix;
	$self->queue_draw;
	$self->hide unless $pix;
}

sub size_allocate_cb
{	my ($self,$alloc)=@_;
	my $ratio=$self->{ratio};
	my $w=$alloc->width;
	my $h=$alloc->height;
	if (my $max=$self->{maxsize})
	{	$w=$max if $w>$max;
		$h=$max if $h>$max;
	}
	my $func= $self->{forceratio} ? \&::max : \&::min;
	$w= $func->($w, int $h*$ratio);
	$h= $func->($h, int $w/$ratio);
	my $size=$w.'x'.$h;

	if (delete $self->{natural_size})#set temporary settings for natural_size mode #FIXME should be simpler
	{	$self->set_size_request($w,$h) if !defined $self->{size} || $size ne $self->{size};
		$self->{size}=$size;
		return;
	}

	if (!defined $self->{size})
	{	unless ($self->{pixbuf} || $::ToDo{'8_LoadImg'.$self}) {$self->hide;return};
	}
	elsif ($self->{size} eq $size) {return}
	$self->set_size_request($w,$h) if $self->{forceratio};
	$self->{size}=$size;
	$self->set( delete $self->{key} ); #force reloading
}

sub expose_cb
{	my ($self,$event)=@_;
	my ($x,$y,$ww,$wh)=$self->allocation->values;
	my $pixbuf= $self->{pixbuf};
	return 1 unless $pixbuf;
	my $w=$pixbuf->get_width;
	my $h=$pixbuf->get_height;
	$x+= int ($ww-$w)*$self->{xalign};
	$y+= int ($wh-$h)*$self->{yalign};
	if (!$self->{reflection})
	{	my $gc=Gtk2::Gdk::GC->new($self->window);
		$gc->set_clip_rectangle($event->area);
		$self->window->draw_pixbuf($gc,$pixbuf,0,0,$x,$y,-1,-1,'none',0,0);
	}
	else
	{	my $cr= Gtk2::Gdk::Cairo::Context->create($self->window);
		$cr->rectangle($event->area);
		$cr->clip;
		$cr->translate($x,$y);
		$self->draw_with_reflection($cr,$pixbuf);
	}
	1;
}

sub draw_with_reflection
{	my ($self,$cr,$pixbuf)=@_;
	my $w=$pixbuf->get_width;
	my $h=$pixbuf->get_height;
	my $scale= $self->{r_scale};
	my $rh=$h * $self->{reflection};

	#draw picture
	$cr->set_source_pixbuf($pixbuf,0,0);
	$cr->paint;

	#clip for reflection
	$cr->rectangle(0,$h,$w,$h+$rh);
	$cr->clip;

	#create alpha gradient
	my $pattern= Cairo::LinearGradient->create(0,$h, 0,$h-$rh*(1/$scale));
	$pattern->add_color_stop_rgba(0, 0,0,0, $self->{r_alpha1} );
	$pattern->add_color_stop_rgba(1, 0,0,0, $self->{r_alpha2} );

	#draw reflection
	my $angle=::PI;
	$cr->translate(0,$h);
	$cr->rotate($angle);
	$cr->scale(1,-$scale);
	$cr->rotate(-$angle);
	$cr->translate(0,-$h);
	$cr->set_source_pixbuf($pixbuf,0,0);
	$cr->mask($pattern);
}

sub collage
{	my ($mode,@pixbufs)=@_;
	$mode= $mode eq 'h' ? 1 : 0;
	my ($x,$y,$w,$h)=(0,0,0,0);

	#find resulting width and height
	for my $pb (@pixbufs)
	{	my $pw=$pb->get_width;
		my $ph=$pb->get_height;
		if ($mode)	{ $w+=$pw; $h=$ph if $ph>$h; }
		else		{ $h+=$ph; $w=$pw if $pw>$w; }
	}

	my $pixbuf= Gtk2::Gdk::Pixbuf->new( $pixbufs[0]->get_colorspace, 1,8, $w,$h);
	$pixbuf->fill(0);	 #fill with transparent black

	for my $pb (@pixbufs)
	{	my $pw=$pb->get_width;
		my $ph=$pb->get_height;
		# center pixbuf
		if ($mode)	{ $y=int( ($h-$ph)/2 ); }
		else		{ $x=int( ($w-$pw)/2 ); }
		$pb->copy_area(0,0, $pw,$ph, $pixbuf, $x,$y);
		if ($mode) { $x+=$pw } else { $y+=$ph }
	}
	return $pixbuf;
}

sub add_overlay
{	my ($self,$pixbuf)=@_;
	my $w=$pixbuf->get_width;
	my $h=$pixbuf->get_height;
	my ($overlay,$xs,$ys,$ws,$hs)= @{$self->{overlay}};
	my $wo= $w*$ws;
	my $ho= $h*$hs;
	my $x= $w*$xs;
	my $y= $h*$ys;
	my $result= Gtk2::Gdk::Pixbuf->new( $pixbuf->get_colorspace, 1,8, $wo,$ho);
	$result->fill(0);	 #fill with transparent black
	$pixbuf->copy_area(0,0, $w,$h, $result, $x,$y);
	$overlay->composite($result, 0,0, $wo,$ho, 0,0, $wo/$overlay->get_width,$ho/$overlay->get_height, 'bilinear',255);
	return $result;
}

package Layout::TogButton;
use base 'Gtk2::ToggleButton';

sub new
{	my ($class,$opt)=@_;
	my $self = bless Gtk2::ToggleButton->new, $class;
	my ($icon,$label);
	my $text= $opt->{label} || $opt->{text};
	$self->set_relief($opt->{relief}) if $opt->{relief};
	$label=Gtk2::Label->new($text) if defined $text;
	$icon=Gtk2::Image->new_from_stock($opt->{icon},$opt->{size}) if $opt->{icon};
	my $child= ($label && $icon) ?	::Hpack($icon,$label) :
					$icon || $label;
	$self->add($child) if $child;
	#$self->{gravity}=$opt->{gravity};
	$self->{$_}=$opt->{$_} for qw/widget resize togglegroup/;
	$self->signal_connect( toggled => \&toggled_cb );
	::Watch($self,'HiddenWidgets',\&UpdateToggleState);
	if ($opt->{skin})
	{	my $skin=Skin->new($opt->{skin},$self,$opt);
		$self->signal_connect(expose_event => \&Skin::draw,$skin);
		$self->set_app_paintable(1); #needed ?
		if (0 && $opt->{shape}) #mess up button-press cb TESTME
		{	$self->{shape}=1;
		}
	}

	return $self;
}

sub UpdateToggleState	#also used by Layout::MenuItem
{	my $self=$_[0];
	return unless $self->{widget};
	my $layw=::get_layout_widget($self);
	return unless $layw;
	my $state=$layw->GetShowHideState($self->{widget});
	$self->{busy}=1;
	$self->set_active($state);
	delete $self->{busy};
}

sub toggled_cb		#also used by Layout::MenuItem
{	my $self=$_[0];
	return if $self->{busy} || !$self->{widget};
	my $layw=::get_layout_widget($self);
	return unless $layw;
	my $show= $self->get_active;
	if (my $tg=$self->{togglegroup})
	{	unless ($show) { $show=1; UpdateToggleState($self); } # togglegroup mode, click on a pressed button just press it again, doesn't un-pressed it
		my @togbuttons= grep $_->{togglegroup} && $_!=$self && $_->{togglegroup} eq $tg,	#get list of widgets of the same togglegroup
				values %{$layw->{widgets}};
		my $hidewidgets=join '|',grep $_, map $_->{widget}, @togbuttons;
		$layw->Hide($hidewidgets,$self->{resize}) if $hidewidgets;
	}
	if (my $w=$self->{widget})	{ $layw->ShowHide($w,$self->{resize},$show) }
}

package Layout::MenuItem;

sub new
{	my $opt=shift;
	if ($opt->{button} && $opt->{updatemenu}) { return Layout::ButtonMenu->new($opt); }
	my $self;
	my $label= $opt->{label} || $opt->{text};
	if ($opt->{togglewidget})	{ $self=Gtk2::CheckMenuItem->new($label); }
	elsif ($opt->{icon})		{ $self=Gtk2::ImageMenuItem->new($label);
					  $self->set_image( Gtk2::Image->new_from_stock($opt->{icon}, 'menu'));
				  	}
	else				{ $self=Gtk2::MenuItem->new($label); }
	if ($opt->{updatemenu})
	{	$self->{updatemenu}=$opt->{updatemenu};
		my $submenu=Gtk2::Menu->new;
		$self->set_submenu($submenu);
		$self->signal_connect( activate=>\&UpdateSubMenu );
		::IdleDo( '9_UpdateSubMenu_'.$self, undef, \&UpdateSubMenu,$self);	# (delayed) initial filling of the menu, not needed but makes the menu work better with gnome2-globalmenu
	}
	if ($opt->{togglewidget})
	{	$self->{widget}=$opt->{togglewidget};
		$self->{resize}=$opt->{resize};
		if (my $tg=$opt->{togglegroup})
		{	$self->{togglegroup}=$tg;
			$self->set_draw_as_radio(1);
		}
		$self->signal_connect( toggled => \&Layout::TogButton::toggled_cb );
		::Watch($self,'HiddenWidgets',\&Layout::TogButton::UpdateToggleState);
	}
	if ($opt->{command})
	{	$self->signal_connect(activate => \&::run_command,$opt->{command});
	}

	return $self;
}

sub get_player_window
{	my $menu=$_[0]->parent;
	while (ref $menu eq 'Gtk2::Menu')
	{	$menu=$menu->get_attach_widget->parent;
	}
	return ::get_layout_widget($menu);
}

sub UpdateSubMenu
{	my $self=shift;
	my $menu=$self->get_submenu;
	return unless $menu;
	$menu->remove($_) for $menu->get_children;
	$self->{updatemenu}($self);
	$menu->show_all;
}

package Layout::ButtonMenu;
use base 'Gtk2::ToggleButton';

sub new
{	my ($class,$opt0)=@_;
	my %opt= ( relief=>'none', size=> 'menu', text=>'', %$opt0 );
	my $self= bless Gtk2::ToggleButton->new, $class;
	my $child;
	my $label= $opt{label} || $opt{text};
	$child=Gtk2::Label->new($label) if length $label;
	if ($opt{icon})
	{	my $img= Gtk2::Image->new_from_stock($opt{icon},$opt{size});
		if ($child)
		{	my $hbox= Gtk2::HBox->new(0,4);
			$hbox->pack_start($img,0,0,2);
			$hbox->pack_start($child,0,0,2);
			$child=$hbox;
		}
		$child||=$img;
	}
	$self->add($child) if $child;
	$self->set_relief($opt{relief});
	$self->{menu}=Gtk2::Menu->new;
	$self->{menu}->attach_to_widget($self,undef);
	$self->{updatemenu}=$opt{updatemenu};
	$self->signal_connect(button_press_event => sub
		{	my ($self,$event) = @_;
			my $menu= $self->{menu};
			if ($self->{updatemenu})
			{	$menu->remove($_) for $menu->get_children;
				$self->{updatemenu}($self);
			}
			$self->set_active(1);
			::PopupMenu($menu,event=>$event);
		});
	$self->{menu}->signal_connect(deactivate => sub { my $self = shift; $self->get_attach_widget->set_active(0); } );
	return $self;
}
sub append { $_[0]{menu}->append($_[1]) }
sub get_submenu { $_[0]{menu} }

package Layout::LabelToggleButtons;
use base 'Gtk2::ScrolledWindow';
sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');
	$self->set_policy('automatic','automatic');
	$self->{table}=Gtk2::Table->new(1,1,::TRUE);
	$self->add_with_viewport($self->{table});
	my $field= $opt->{field};
	if (Songs::FieldType($field) ne 'flags')
	{	warn "LabelToggleButtons : invalid field $field\n";
		$field= 'label';
	}
	$self->{field}= $field;
	$self->{$_}= $opt->{$_} for qw/hide_unset group/;
	my $songchange= $self->{hide_unset} ? sub { my $self=shift; $self->{width}=0; $self->update_columns; $self->update_song } : \&update_song;
	::WatchSelID($self, $songchange, [$field]);
	::Watch($self,"newgids_$field",\&update_labels);
	$self->signal_connect( size_allocate => sub { ::IdleDo( "resize_$self",1000, \&update_columns,$_[0] ); });
	return $self;
}
sub update_labels
{	my $self=shift;
	my %checks; $self->{checks}=\%checks;
	for my $label ( @{Songs::ListAll($self->{field})} )
	{	my $check= $checks{$label}= Gtk2::CheckButton->new_with_label($label);
		$check->signal_connect(toggled => \&toggled_cb,$label);
	}
	$self->{width}=0;
	$self->update_columns;
	$self->update_song;
}
sub update_columns
{	my $self=shift;
	goto &update_labels unless $self->{checks}; #initialization
	my $width=$self->child->allocation->width;
	return unless $width;
	return if $self->{width} && $width == $self->{width};
	$self->{width}=$width;
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
	$table->resize(1,1);
	my @list;
	if ($self->{hide_unset})
	{	my $ID= ::GetSelID($self);
		@list= Songs::Get_list($ID,$self->{field}) if defined $ID;
	}
	else { @list= @{Songs::ListAll($self->{field})} }
	my @shown= grep defined, map $self->{checks}{$_}, @list;
	my $maxwidth=::max( 10,map 4+$_->size_request->width, @shown );
	my $maxcol= int( $width / $maxwidth)||1;
	my $col=my $row=0;
	for my $widget (@shown)
	{	$table->attach($widget,$col,$col+1,$row,$row+1,['fill','expand'],'shrink',1,1);
		if (++$col==$maxcol) {$col=0; $row++;}
	}
	$table->show_all;
}

sub update_song
{	my $self=shift;
	$self->{busy}=1;
	my $ID= ::GetSelID($self);
	$self->{table}->set_sensitive(defined $ID);
	my $checks=$self->{checks};
	for my $label (keys %$checks)
	{	my $check=$checks->{$label};
		my $on= defined $ID ? Songs::IsSet($ID,$self->{field}, $label) : 0;
		$check->set_active($on);
	}
	$self->{busy}=0;
}
sub toggled_cb
{	my ($check,$label)=@_;
	return unless $check->parent;
	my $self=::find_ancestor($check,__PACKAGE__);
	return if $self->{busy};
	my $field= ($check->get_active ? '+' : '-').$self->{field};
	my $ID= ::GetSelID($self);
	Songs::Set($ID,$field,[$label]);
}

package Layout::SongInfo;
use base 'Gtk2::ScrolledWindow';
our @default_options= ( markup_cat=>"<u>%s</u>", markup_field=>"<small>%s :</small>", markup_value=>"<small><b>%s</b></small>" );
sub new
{	my ($class,$opt)=@_;
	%$opt=( @default_options, %$opt );
	my $self= bless Gtk2::ScrolledWindow->new, $class;
	$self->set_policy('automatic','automatic');
	$self->{table}=Gtk2::Table->new(1,1,::FALSE);
	$self->add_with_viewport($self->{table});

	$self->{$_}=$opt->{$_} for qw/group ID markup_cat markup_field markup_value font expander collapsed hide_empty/;
	if ($opt->{ID}) # for use in SongProperties window
	{	::Watch($self, SongsChanged=> \&update); #could check which ID changed
	}
	else	#use group option to find ID
	{	::WatchSelID($self, \&update);
	}
	$self->{SaveOptions}= \&SaveOptions;
	::Watch($self,fields_reset=>\&init);
	$self->init;
	return $self;
}
sub init
{	my $self=shift;
	my %collapsed;
	if ($self->{expander})
	{	$self->SaveOptions if $self->{cats}; # updates $self->{collapsed}
		$collapsed{$_}=1 for split / +/, $self->{collapsed}||'';
	}
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
	my $labels1=$self->{labels1}={};
	my $labels2=$self->{labels2}={};
	my $cats=$self->{cats}={};
	my @labels;
	$table->{row}=0;
	my $treelist=Songs::InfoFields;
	while (@$treelist)
	{	my ($cat,$catname,$fields)= splice @$treelist,0,3;
		#category
		my $catlabel=Gtk2::Label->new_with_format($self->{markup_cat}, $catname);
		push @labels, $catlabel;
		my $table2=$table;
		if ($self->{expander})
		{	$table2=Gtk2::Table->new(1,1,::FALSE);
			$table2->{row}=0;
			my $expander= Gtk2::Expander->new;
			$expander->set_label_widget($catlabel);
			$expander->add($table2);
			$expander->set_expanded( !$collapsed{$cat} );
			$catlabel=$expander;
		}
		$cats->{$cat}=$catlabel;
		my $row=$table->{row}++;
		$table->attach($catlabel,0,1,$row,$row+1,'fill','shrink',1,1);
		#fields
		for my $field (@$fields)
		{	my $lab1=$labels1->{$field}=Gtk2::Label->new_with_format($self->{markup_field}, Songs::FieldName($field));
			my $lab2=$labels2->{$field}=Gtk2::Label->new;
			push @labels, $labels1, $labels2;
			$lab1->set_padding(5,0);
			$lab1->set_alignment(1,0);
			$lab2->set_alignment(0,0);
			$lab2->set_line_wrap(1);
			$lab2->set_selectable(1);
			my $row=$table2->{row}++;
			$table2->attach($lab1,0,1,$row,$row+1,'fill','fill',1,1);
			$table2->attach($lab2,1,2,$row,$row+1,'fill','fill',1,1);
		}
		$row=$table->{row}++;
		$table->attach(Gtk2::HBox->new,0,3,$row,$row+1,[],[],0,5) if @$treelist; #space between categories
	}
	if (my $font=$self->{font})
	{	$font= Gtk2::Pango::FontDescription->from_string($font);
		$_->modify_font($font) for @labels;
	}
	if ($self->{expander})
	{	my $sg= Gtk2::SizeGroup->new('horizontal');
		$sg->add_widget($_) for values %$labels1;
	}
	$table->set_no_show_all(0);
	$table->show_all;
	$table->set_no_show_all(1);
	$self->update;
}
sub update
{	my $self=shift;
	my $ID= $self->{ID} || ::GetSelID($self);
	my $labels1= $self->{labels1};
	my $labels2= $self->{labels2};
	my $func= defined $ID ? \&Songs::Display : sub {''};
	my $treelist=Songs::InfoFields;
	while (@$treelist)
	{	my ($cat,$catname,$fields)= splice @$treelist,0,3;
		my $found;
		for my $field (@$fields)
		{	my $lab2= $labels2->{$field};
			next unless $lab2;
			my $val= $func->($ID,$field);
			$lab2->set_markup_with_format($self->{markup_value}, $val);
			if ($self->{hide_empty})
			{	$_->set_visible($val ne '') for $labels1->{$field},$lab2;
				$found ||= $val ne '';
			}
		}
		$self->{cats}{$cat}->set_visible($found) if $self->{hide_empty};
	}
	$self->queue_resize; # for unclear reasons (bug in gtk2 ?), labels that were hidden when the widget is was last shown, and then are shown while the widget is hidden, have a row height of 0 (and thus hidden) when the widget is shown, forcing a queue resize fixes it
}
sub SaveOptions
{	my $self=shift;
	my %opt;
	if (my $cats=$self->{cats})
	{	$opt{collapsed}= $self->{collapsed}= join ' ', sort grep !$cats->{$_}->get_expanded, keys %$cats;
	}
	return %opt;
}

package Layout::PictureBrowser;
use base 'Gtk2::Box';

our @toolbar=
(	{ stockicon=> 'gmb-view-list',	label=>_"Show file list",  toggleoption=>'self/show_list',  cb=> sub { $_[0]{self}->update_showhide; }, },
	{ stockicon=> 'gtk-zoom-in',	label=>_"Zoom in",	cb=> sub { $_[0]{view}->change_zoom('+'); },	},
	{ stockicon=> 'gtk-zoom-out',	label=>_"Zoom out",	cb=> sub { $_[0]{view}->change_zoom('-'); },	},
	{ stockicon=> 'gtk-zoom-100',	label=>_"Zoom 1:1",	cb=> sub { $_[0]{view}->change_zoom(1); },	},
	{ stockicon=> 'gtk-zoom-fit',	label=>_"Zoom to fit",	cb=> sub { $_[0]{view}->set_zoom_fit; },	},
	{ stockicon=> 'gtk-fullscreen',	label=>_"Fullscreen",	cb=> sub { $_[0]{view}->set_fullscreen(1); },	},
#	{ stockicon=> 'gtk-go-back',	label=>_"Previous picture",		cb=> sub { $_[0]{self}->change_file(-1); },	},
#	{ stockicon=> 'gtk-go-forward',	label=>_"Next picture",			cb=> sub { $_[0]{self}->change_file(1); },	},
#	{ stockicon=> 'gtk-',		label=>_"Rotate clockwise",		cb=> sub { $_[0]{view}->rotate(1); },	},
#	{ stockicon=> 'gtk-',		label=>_"Rotate counterclockwise",	cb=> sub { $_[0]{view}->rotate(-1); },	},
	{ stockicon=> 'gtk-jump-to',	label=> sub { $_[0]{self}{group} eq 'Play' ? _"Follow playing song" : _"Follow selected song"; },
	  toggleoption=>'self/follow',	cb=> sub { $_[0]{self}->queue_song_changed; },
	},
);

our @optionsubmenu=
(	{ label=> sub { $_[0]{self}{group} eq 'Play' ? _"Follow playing song" : _"Follow selected song"; },
	  code => sub { $_[0]{self}->queue_song_changed; ::UpdateToolbar($_[0]{toolbar}); }, toggleoption=>'self/follow', mode=>'V',
	},

	{ label=>_"Scroll to zoom",	mode=>'VP',	toggleoption=> 'view/scroll_zoom', },

	{ label=>_"Reset view position when file changes",	mode=>'V', 	toggleoption=> 'self/reset_offset_on_file_change', },

	{ label=>_"Reset zoom",		mode=>'V',	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{reset_zoom_on}},
	  submenu=> [ _"when file changes"=>'file', _"when folder changes"=>'folder', _"never"=>'never'],
	  code => sub { $_[0]{self}{reset_zoom_on}=$_[1] },
	},

	{ separator=>1, mode=>'V', },

	{ label=>_"Show folder list",	mode=>'VL',	toggleoption=>'self/show_folders',	test=> sub { $_[0]{self}{show_list}, },	  code => sub { $_[0]{self}->update_showhide; },
	},
	{ label=>_"Show file list",	mode=>'VL',	toggleoption=>'self/show_list',		code=> sub { $_[0]{self}->update_showhide; },
	},
	{ label=>_"Show toolbar",	mode=>'VL',	toggleoption=>'self/show_toolbar',	code=> sub { $_[0]{self}->update_showhide; },
	},
	{ label=>_"Show pdf pages",	mode=>'VL',	toggleoption=>'self/pdf_mode',		code=> sub { $_[0]{self}->update; },
	},
	{ label=>_"Show embedded pictures",mode=>'VL',	toggleoption=>'self/embedded_mode',	code=> sub { $_[0]{self}->update; },
	},
	{ label=>_"Show all files",mode=>'VL',		toggleoption=>'self/all_mode',		code=> sub { $_[0]{self}->update; },
	},
);
# mode L is for List, V for View, P for Pixbuf (Layout::PictureBrowser::View without a Layout::PictureBrowser, not used yet)
our @ContextMenu=
(	{ label => _"Zoom in",		code => sub { $_[0]{view}->change_zoom('+'); },	defined=>'pixbuf',	stockicon=> 'gtk-zoom-in',  mode=>'PV', },
	{ label => _"Zoom out",		code => sub { $_[0]{view}->change_zoom('-'); },	defined=>'pixbuf',	stockicon=> 'gtk-zoom-out', mode=>'PV', },
	{ label => _"Zoom 1:1",		code => sub { $_[0]{view}->change_zoom(1); }, 	defined=>'pixbuf',	stockicon=> 'gtk-zoom-100', mode=>'PV', },
	{ label => _"Zoom to fit",	code => sub { $_[0]{view}->set_zoom_fit; },	defined=>'pixbuf',	stockicon=> 'gtk-zoom-fit', mode=>'PV', },
	{ separator=>1, mode=>'V', },

	{ label=> _"View in new window",	istrue=> 'file',	code => sub { $_[0]{self}->view_in_new_window($_[0]{file}); }, mode=>'VL', },
	{ label=> _"Rename file", code => sub { my $tv=$_[0]{self}{filetv}; $tv->set_cursor($_[0]{treepaths}[0],$tv->get_column(0),::TRUE); },
	  onlyone => 'treepaths', isfalse=>'ispage', istrue=>'writeable', mode=>'L',
	},
	{ label=> _"Delete file",	code => sub { $_[0]{self}->delete_selected },	istrue=>'writeable', isfalse=>'ispage', mode=>'VL', stockicon=>'gtk-delete', },

	{ label => _"Options", submenu=> \@optionsubmenu, mode=>'VL', },

	{ label=> sub { my $name=Songs::Gid_to_Display($_[0]{field},$_[0]{gid}); ::__x(_"Set as picture for '{name}'", name=>::Ellipsize($name,30)) },
	  code => sub { Songs::Picture($_[0]{gid},$_[0]{field},'set',$_[0]{file}); },
	  test=> sub { $_[0]{file} ne (Songs::Picture($_[0]{gid},$_[0]{field},'get')||''); },	istrue=>'file gid', mode=>'V',
	  # test => sub { Songs::FilterListProp($_[0]{field},'picture') },
	},

	{ label => _"Paste link",
	  test => sub { return unless $_[0]{self}->can('drop_uris'); $_[0]{clip}= $_[0]{self}->get_clipboard(Gtk2::Gdk::Atom->new('PRIMARY',1))->wait_for_text; $_[0]{clip} && $_[0]{clip}=~m#^\s*\w+://#; },
	  code=> sub { $_[0]{self}->drop_uris(uris=>[grep m#^\s*\w+://#, split /[\n\r]+/, $_[0]{clip}]); },
	},

	{ label=> sub { $_[0]{view}{fullwin} ? _"Exit full screen" : _"Full screen" }, code=>sub { $_[0]{view}->set_fullscreen }, mode=>'VP',
	  stockicon=> sub { $_[0]{view}{fullwin} ? 'gtk-leave-fullscreen' : 'gtk-fullscreen' },
	},

);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::VBox->new, $class;
	$self->{$_}= $opt->{$_} for qw/group follow show_list show_folders show_toolbar reset_zoom_on nowrap pdf_mode embedded_mode all_mode/;

	my $hbox= Gtk2::HBox->new;
	my $hpaned=			Layout::Boxes::PanedNew('Gtk2::HPaned',{size=>$opt->{hpos}});
	my $vpaned= $self->{vpaned}=	Layout::Boxes::PanedNew('Gtk2::VPaned',{size=>$opt->{vpos}});
	my $view=	$self->{view}=  Layout::PictureBrowser::View->new(%$opt,mode=>'V');
	my $toolbar=	$self->{toolbar}= ::BuildToolbar(\@toolbar, getcontext=>\&toolbarcontext, self=>$self);
	$self->{dirstore} = Gtk2::ListStore->new(qw/Glib::String Glib::String Glib::String/);
	$self->{filestore}= Gtk2::TreeStore->new(qw/Glib::String Glib::String Glib::Boolean Glib::Uint Glib::Uint/);
	my $treeview1= $self->{foldertv}= Gtk2::TreeView->new($self->{dirstore});
	my $treeview2= $self->{filetv}=	  Gtk2::TreeView->new($self->{filestore});
	my $renderer=Gtk2::CellRendererText->new;
	$renderer->signal_connect(edited => \&filename_edited_cb,$treeview2);
	$treeview1->insert_column_with_attributes(-1, 'Dir icon', Gtk2::CellRendererPixbuf->new, stock_id => 2) unless $opt->{no_folder_icons};
	$treeview1->insert_column_with_attributes(-1, 'Dir name', Gtk2::CellRendererText->new, text => 0);
	$treeview2->insert_column_with_attributes(-1, 'File name',$renderer, text => 0, editable=> 2);

	#size and date column
	my $renderer_s= Gtk2::CellRendererText->new;
	my $renderer_d= Gtk2::CellRendererText->new;
	my $column_s=Gtk2::TreeViewColumn->new_with_attributes('size',$renderer_s);
	my $column_d=Gtk2::TreeViewColumn->new_with_attributes('date',$renderer_d);
	$renderer_s->set(xalign=>1);
	$column_s->set_cell_data_func($renderer_s, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $depth=$store->iter_depth($iter);
			my ($file,$size)= $store->get($iter,1,3);
			$size= ($depth || !$file) ? '' : ::format_number($size);
			$cell->set(text=>$size);
		});
	$treeview2->append_column($column_s);
	$renderer_d->set(xalign=>1);
	$column_d->set_cell_data_func($renderer_d, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $depth=$store->iter_depth($iter);
			my $date= $store->get($iter,4);
			$date= ($depth || !$date) ? '' : Songs::DateString($date);
			$cell->set(text=>$date);
		});
	$treeview2->append_column($column_d);
	$_->set_sizing('autosize') for $treeview2->get_columns;

	# draw "Embedded pictures"... text over the correct row (avoid stretching the first column for nothing and emphasize that this is not a regular row) and draw progress line if needed
	$treeview2->signal_connect_after(expose_event=> sub
	 {	my ($tv,$event)=@_;
		my $path= $tv->{embfiles_path};
		return unless $path;
		my $rect= $tv->get_cell_area($path,undef);
		my $vwidth= ($tv->get_bin_window->get_geometry)[2];
		$rect->width($vwidth-4);
		if ($rect->intersect($event->area))
		{	my $layout=Gtk2::Pango::Layout->new( $tv->create_pango_context );
			my $state= $tv->get_state;
			if ($self->{embfiles_idle}) #draw progress line
			{	my $width= ($vwidth * ($tv->{scan_progress}||0))||1;
				my $gc= $tv->get_style->text_aa_gc($state);
				$tv->get_bin_window->draw_rectangle($gc,::TRUE, 0,$rect->y,$width,2);
			}
			$layout->set_markup($tv->{embfiles_text});
			$tv->get_style->paint_layout($tv->get_bin_window,$state, 1, $rect, $tv, undef, 4+$rect->x, $rect->y, $layout);
		}
	 });

	$treeview1->set_headers_visible(0);
	$treeview2->set_headers_visible(0);
	$treeview2->get_selection->signal_connect(changed => \&treeview_selection_changed_cb);
	$treeview2->get_selection->set_select_function(sub {my ($selection,$store,$treepath)=@_; return $store->get($store->get_iter($treepath),1) ne ''; }); #disable selection of rows without a filename

	$vpaned->pack1(::new_scrolledwindow($treeview1), ::FALSE, ::FALSE);
	$vpaned->pack2(::new_scrolledwindow($treeview2), ::TRUE, ::TRUE);
	$hpaned->pack1($vpaned, ::FALSE, ::FALSE);
	$hpaned->add2($view);
	$hbox->add($hpaned);
	$self->pack_start($toolbar,0,0,2);
	$self->add($hbox);
	$self->{SaveOptions}= \&SaveOptions;

	$_->set_enable_search(0) for $treeview1,$treeview2;
	$self->signal_connect(key_press_event=> \&key_press_cb);
	$treeview1->signal_connect(row_activated=> \&folder_activated_cb);
	$treeview1->signal_connect(button_press_event=> \&folder_button_press_cb);
	$treeview2->signal_connect(button_press_event=> \&file_button_press_cb);
	$self->signal_connect(map => sub {$_[0]->queue_song_changed});
	::set_drag($view, dest => [::DRAG_ID,::DRAG_FILE,sub
	 {	my ($view,$type,@values)=@_;
		my $self= ::find_ancestor($view,__PACKAGE__);
		if ($type==::DRAG_FILE)
		{	$self->drop_uris(uris=>\@values, is_move=>$view->{dragdest_suggested_action});
		}
		elsif ($type==::DRAG_ID)
		{	$self->queue_song_changed($values[0],'force');
		}
	 }],
	 # motion cb needed to show the help message over the picture when dragging something over it
	 motion=> sub {	my ($view,$context,$x,$y,$time)=@_;
			my $datatype;
			for my $atom ($context->targets)
			{	my $type= $::DRAGTYPES{$atom->name}||-1;
				if    ($type==::DRAG_ID)  { $datatype='songid'; last }
				elsif ($type==::DRAG_FILE){ $datatype= 'uri'; last }
			}
			$view->{dnd_message}= $datatype eq 'uri' ?
				_"Drop files in this folder" :
				_"View pictures from this album's folder"; #FIXME make second message depend $self->{field};
			1;
		      }
	 );
	$view->signal_connect(drag_leave => sub { delete $_[0]{dnd_message}; });
	::set_drag($treeview2, source=> [::DRAG_FILE,sub
	 {	my $self= ::find_ancestor($_[0],__PACKAGE__);
		my $file=$self->{current_file};
		$file=~s/:\w+$//;
		return $file ? (::DRAG_FILE,'file://'.::url_escape($file)) : ()
	 }]);
	$self->signal_connect(destroy => sub {$_[0]->destroy_cb});

	$_->show_all, $_->set_no_show_all(1) for $vpaned,$toolbar;
	$self->update_showhide;
	$vpaned->signal_connect(show=> sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->refresh_treeviews; $self->update_selection; }); #updating of the file/folder list is disabled whe hidden, so needs to update it when shown

	if    (my $file=$opt->{set_file}) { $self->set_file($file); }
	elsif (my $pb=$opt->{set_pixbuf}) { $self->{view}->set_pixbuf($pb); $self->{ignore_song}=1; }
	return $self;
}
sub destroy_cb
{	my $self=shift;
	$self->{drop_job}->Abort if $self->{drop_job};
	Glib::Source->remove( $self->{embfiles_idle} ) if $self->{embfiles_idle};
}

sub SaveOptions
{	my $self=shift;
	my %opt;
	my $vpaned= $self->{vpaned};
	$opt{hpos}= ($vpaned->parent->{SaveOptions}($vpaned->parent))[1];	# The SaveOptions function of Layout::Boxes::PanedNew returns (size=>$value),
	$opt{vpos}= ($vpaned->{SaveOptions}($vpaned))[1];			# we only want the value
	$opt{$_}=$self->{view}{$_} for qw/scroll_zoom/;
	$opt{$_}=$self->{$_} for qw/follow show_list show_folders show_toolbar reset_zoom_on pdf_mode embedded_mode all_mode/;
	return %opt;
}

sub toolbarcontext
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	return self=>$self, view=>$self->{view};
}

sub update_showhide
{	my $self=shift;
	my $vpaned= $self->{vpaned};
	$vpaned->set_visible( $self->{show_list} );
	$vpaned->child1->set_visible( $self->{show_folders} );
	my $toolbar= $self->{toolbar};
	$toolbar->set_visible( $self->{show_toolbar} );
	::UpdateToolbar($toolbar);
}

sub view_in_new_window
{	my ($self,$file)=@_;
	$file||= $self->{current_file};
	return unless $file;
	Layout::Window->new('PictureBrowser', pos=>undef, 'PictureBrowser/follow'=>0,'PictureBrowser/set_file'=>$file,'PictureBrowser/embedded_mode'=>$self->{embedded_mode});
}

sub delete_selected
{	my $self=shift;
	return if $::CmdLine{ro};
	my @files= ($self->{current_file});
	@files= grep !m/:\w+$/, @files;
	return unless @files;
	@files= ::uniq(@files);
	my $text= @files==1 ?	::filename_to_utf8displayname(::basename($files[0])) :
				__n("%d file","%d files",scalar @files);
	my $dialog = Gtk2::MessageDialog->new
		( $self->get_toplevel,
		  'modal',
		  'warning','cancel','%s',
		  ::__x(_("About to delete {files}\nAre you sure ?"), files => $text)
		);
	$dialog->add_button("gtk-delete", 2);
	$dialog->show_all;
	if ('2' eq $dialog->run)
	{	my $skip_all;
		my $done=0;
		for my $file (@files)
		{	unless (unlink $file)
			{	my $res= $skip_all;
				my $errormsg= _"Deletion failed";
				$errormsg.= ' ('.($done+1).'/'.@files.')' if @files>1;
				$res ||= ::Retry_Dialog($!,$errormsg, details=>::__x(_("Failed to delete '{file}'"), file => ::filename_to_utf8displayname($file)), window=>$dialog, many=>(@files-$done)>1);
				$skip_all=$res if $res eq 'skip_all';
				redo if $res eq 'retry';
				last if $res eq 'abort';
			}
			GMB::Cache::drop_file($file); #drop file from picture cache
			$done++;
		}
		# update selection
		my $file= $self->{current_file} || '';
		my $list= $self->{filelist};
		my $i= ::first { $list->[$_] eq $file } 0..$#$list;
		if (defined $i)
		{	for my $j (reverse(0..$i), $i+1 .. $#$list)
			{	if (-e $list->[$j]) { $self->{current_file}=$list->[$j]; last }
			}
		}
		$self->update;
	}
	$dialog->destroy;
}
sub filename_edited_cb
{	my ($cell,$path_string,$newutf8,$tv)= @_;
	return if $::CmdLine{ro};
	my $store=$tv->get_model;
	my $iter=$store->get_iter_from_string($path_string);
	my $file= ::decode_url($store->get($iter,1));
	my $suffix= $file=~s/(:\w+)$// ? $1 : '';
	(my $path,$file)= ::splitpath($file);
	my $new= GMB::Picture::RenameFile($path, $file, $newutf8, $tv->get_toplevel) if $newutf8=~m/\S/ && $file ne $newutf8;
	return unless $new;
	my $self= ::find_ancestor($tv,__PACKAGE__);
	$self->{current_file}= ::catfile($path,$new.$suffix);
	$self->update;
}
sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	if (::WordIn($key,'Delete KP_Delete'))	{ $self->delete_selected }
	elsif (lc$key eq 'l')	{ $self->{show_list}^=1; $self->update_showhide; $self->{view}->grab_focus unless $self->{show_list}; }
	elsif (lc$key eq 'n')	{ $self->view_in_new_window }
	elsif ($key eq 'F5')	{ $self->refresh_treeviews }
	else { return $self->{view}->key_press_cb($event); } #propagate event to the view widget
	#else {return 0}
	return 1;
}
sub folder_activated_cb
{	my ($tv,$treepath,$tvcol)=@_;
	my $self= ::find_ancestor($tv,__PACKAGE__);
	my $store= $tv->get_model;
	my $iter= $store->get_iter($treepath);
	return unless $iter;
	my $folder= ::decode_url($store->get($iter,1));
	$self->set_path($folder);
}
sub folder_button_press_cb
{	my ($tv,$event)=@_;
	return 1 if $event->type ne 'button-press'; # ignore double or triple clicks
	my ($path,$column)=$tv->get_path_at_pos($event->get_coords);
	return 0 unless $path;
	$tv->row_activated($path,$column);
	return 1;
}
sub file_button_press_cb
{	my ($tv,$event)=@_;
	my $self= ::find_ancestor($tv,__PACKAGE__);
	#$self->grab_focus;
	my $button=$event->button;
	if ($button == 3)
	{	my @rows=$tv->get_selection->get_selected_rows;
		::PopupContextMenu( \@ContextMenu, {mode=>'L', treepaths=>\@rows, $self->context_menu_args} );
	}
	else {return 0}
	1;
}
sub treeview_selection_changed_cb
{	my ($selection)=@_;
	my ($store,$iter) = $selection->get_selected;
	return unless $iter;
	my $file= ::decode_url($store->get($iter,1));
	my $self= ::find_ancestor($selection->get_tree_view,__PACKAGE__);
	return if $self->{busy};
	$self->set_file($file);
}

sub drop_uris
{	my ($self,%args)=@_;
	return unless $self->{current_path};
	$self->{drop_job} ||= GMB::DropURI->new(toplevel=>$self->get_toplevel, cb=>sub{$self->file_dropped($_[0])}, cb_end=>sub{$self->drop_end});
	$self->{drop_job}->Add_URI(uris=>$args{uris}, is_move=>$args{is_move}, destpath=>$self->{current_path});
	$self->{select_drop}=1;
}

sub file_dropped
{	my ($self,$file)=@_;
	return if ::dirname($file) ne ($self->{current_path}||'');
	#update list and picture
	if ($self->{select_drop}) #if selection hasn't changed since drop, select the new file
	{	if ($file!~m/$::Image_ext_re/ && $file!~m/\.pdf$/i) {$file=undef} #do not select the file if not a picture/pdf
		$self->{current_file}= $file if $file;
	}
	$self->update;
}
sub drop_end
{	my $self=shift;
	delete $self->{drop_job};
	delete $self->{select_drop};
}

sub queue_song_changed
{	my ($self,$ID,$force)=@_;
	return if $self->{current_path} && !$self->{follow} && !$force;
	return if $self->{ignore_song};
	return unless $self->mapped;
	::IdleDo('8_ChangePicture'.$self,500,\&SongChanged,$self,$ID);
}
sub queue_change_picture
{	my ($self,$direction)=@_;
	::IdleDo('8_ChangePicture'.$self,500,\&change_file,$self,$direction);
}

sub SongChanged
{	my ($self,$ID)=@_;
	$ID= ::GetSelID($self) unless defined $ID;
	$self->{ID}=$ID;
	unless (defined $ID)
	{	$self->{gid}=undef;
		$self->set_list([]);
		return;
	}
	$self->{mode}= 'song';
	my $oldgid= $self->{gid} ||0;
	$self->{gid}= Songs::Get_gid($ID,$self->{field});
	$self->{view}->reset_zoom if $self->{reset_zoom_on} eq 'group' && $oldgid==$self->{gid};
	$self->update;
}
sub set_list
{	my ($self,$list)=@_;
	$self->{mode}='list';
	$self->{filelist}=$list;
	$self->update;
}
sub set_path
{	my ($self,$path)=@_;
	$self->{mode}='path';
	$path= ::cleanpath($path) if $path;
	$self->{current_path}= $path;
	$self->update;
}

sub update
{	my $self=shift;
	my (@files,@paths,$default_path,@emb_files);
	my $emb_ok= $self->{embedded_mode};

	if ($self->{mode} eq 'song')
	{	my $field= $self->{field};
		my $gid= $self->{gid};
		@emb_files= Songs::Map('fullfilename',AA::GetIDs($field,$gid)) if $emb_ok;
		my $path= AA::GuessBestCommonFolder($field,$gid);
		@paths=($default_path=$path) if $path;
	}
	elsif ($self->{mode} eq 'path')
	{	my $path= $self->{current_path};
		@paths=($default_path=$path)
	}
	elsif ($self->{mode} eq 'list') { @files= grep {my $f=$_; $f=~s/:\w+$//; -f $f} @{$self->{filelist}}; }

	my $pdfok= $GMB::Picture::pdf_ok && $self->{pdf_mode};
	for my $path (@paths)
	{	opendir my($dh),$path  or do { warn $!; last; };
		for my $file (map $path.::SLASH.$_, ::sort_number_aware(grep !m#^\.#, readdir $dh))
		{	next if -d $file;
			if    ($file=~m/$::Image_ext_re/) { push @files, $file }
			elsif ($file=~m/\.pdf$/i && $pdfok) { push @files, $file, map "$file:$_", 1..GMB::Picture::pdf_pages($file)-1; }
			else
			{	if ($emb_ok && $self->{mode} eq 'path') { push @emb_files,$file }
				if ($self->{all_mode})			{ push @files,$file }
			}
		}
		closedir $dh;
	}

	my $file=$self->{current_file};
	$self->{filelist}=\@files;

	delete $self->{embfiles};
	delete $self->{filetv}{embfiles_path};
	if ($emb_ok)
	{	my $file= $file;
		$file=~s/:\w+$// if $file;
		my $now= $file && (grep $file eq $_, @emb_files); # do not scan embedded files in an idle if selected files is one of them
		$self->scan_embedded_pictures($now,@emb_files);
	}

	unless ($file && (grep $file eq $_, @files))
	{	$file= $self->{current_file}= $files[0];
	}
	my $oldpath= $self->{current_path}||'';
	my $path= $default_path||'';
	if ($file) { my $fpath= ::dirname($file); $path=$fpath if grep $fpath eq $_, @paths; } # make sure the path is in @paths
	$self->{current_path}= $path;
	$self->{view}->reset_zoom if $self->{reset_zoom_on} eq 'folder' && $oldpath ne $self->{current_path};
	$self->refresh_treeviews;
	$self->update_file;
}

sub refresh_treeviews
{	my $self=shift;
	return unless $self->{show_list};
	my $oldpath= $self->{loaded_path};
	my $path= $self->{current_path}; # || $oldpath;
	my $dirstore= $self->{dirstore};
	my $filestore=$self->{filestore};
	my $filetv= $self->{filetv};
	my $foldertv= $self->{foldertv};
	$dirstore->clear;
	$filestore->clear;
	unless ($path && $oldpath && $oldpath eq $path) #folder has changed, reset scrollbars
	{	$foldertv->get_vadjustment->set_value(0);
		$filetv->get_vadjustment->set_value(0);
		$self->{loaded_path}= $path;
	}
	return unless $path;
	my $parent= ::parentdir($path);
	$path= ::pathslash($path); # add a slash at the end
	$dirstore->set( $dirstore->append,  0,'..', 1,Songs::filename_escape($parent), 2,'gtk-go-up') if $parent;
	my $pdfok= $GMB::Picture::pdf_ok && $self->{pdf_mode};

	my $show_expanders;
	my $folder_center_treepath;
	opendir my($dh),$path  or do { warn $!; return; };
	for my $file (::sort_number_aware( grep !m#^\.#, readdir $dh))
	{	if (-d $path.$file)
		{	my $iter= $dirstore->append;
			$dirstore->set( $iter, 0,::filename_to_utf8displayname($file), 1,Songs::filename_escape($path.$file),  2,'gtk-directory');
			if ($oldpath && $oldpath eq $path.$file)	#select and center on previous folder if there
			{	$folder_center_treepath= $dirstore->get_path($iter);
				$foldertv->set_cursor($folder_center_treepath);
			}
			next;
		}

		my @pages; my $suffix='';
		if ($file=~m/\.pdf$/i && $pdfok) { @pages= (1..GMB::Picture::pdf_pages($path.$file)-1); $show_expanders=1; }
		elsif ($file!~m/$::Image_ext_re/ && !$self->{all_mode}) { next }

		my $efile= Songs::filename_escape($path.$file);
		my $iter= $filestore->append(undef);
		my ($size,$time)=(stat $path.$file)[7,9];
		$filestore->set($iter, 0,::filename_to_utf8displayname($file), 1,$efile, 2,!$::CmdLine{ro}, 3,$size, 4,$time);
		for my $n (@pages)
		{	$filestore->set($filestore->append($iter), 0, ::__x(_"page {number}",number=>$n+1), 1,"$efile:$n");
		}
	}
	closedir $dh;

	if ($self->{embfiles})
	{	my $text= $self->{mode} eq 'path' ? _"Embedded pictures in this folder" :
			  $self->{mode} eq 'song' && $self->{field} eq 'album' ? _"Embedded pictures for this album" :
			  _"Embedded pictures";
		$filestore->set($filestore->append(undef), 0, '', 1,''); #empty separator row
		my $iter= $filestore->append(undef);
		$filestore->set($iter, 0, '', 1,''); # empty row where the text will be written
		$self->{filetv}{embfiles_path}= $filestore->get_path($iter);
		$self->{filetv}{embfiles_text}= ::MarkupFormat("<u>%s</u>", $text);
		$self->{filetv}{scan_progress}=0;

		$self->scan_embedded_pictures_update_tv unless $self->{embfiles}{updatetv}; # if scan of embedded files was made immediately
	}

	$filetv->set_show_expanders($show_expanders);
	$filetv->expand_all;
	$foldertv->scroll_to_cell($folder_center_treepath,undef,::TRUE,.5,0) if $folder_center_treepath; #needs to be done once the list is filled
}

sub scan_embedded_pictures
{	my $self=shift;
	my $now=shift;
	my @files= ::sort_number_aware( ::uniq(grep m/$::EmbImage_ext_re$/,@_) );
	return unless @files;
	$self->{embfiles}= { filecount=> scalar @files, toscan=>\@files, pix=> [], updatetv=>!$now};
	if ($now) { $now= $self->scan_embedded_pictures_idle_cb while $now; }
	else { $self->{embfiles_idle} ||= Glib::Idle->add(\&scan_embedded_pictures_idle_cb, $self); }
}

sub scan_embedded_pictures_idle_cb
{	my $self=shift;
	return $self->{embfiles_idle}=0 unless $self->{embfiles};
	my $todo= $self->{embfiles}{toscan};
	my $pix= $self->{embfiles}{pix};
	my $file= shift @$todo;
	my @p= FileTag::PixFromMusicFile($file,undef,1);
	for my $p (0..$#p)
	{	next unless $p[$p];
		my $i= ::first { $p[$p] eq $pix->[$_][1] } 0..$#$pix; #check if already seen that picture
		unless (defined $i) { $i=@$pix; push @$pix, [ $file.':'.$p, $p[$p]]; } #new picture
		push @{$pix->[$i][2]}, "$file:$p";
	}
	#update progress line in filetv
	my $tv=$self->{filetv};
	my $max= $self->{embfiles}{filecount};
	$tv->{scan_progress}= ($max-@$todo)/$max;
	if ($self->{show_list} && (my $path=$tv->{embfiles_path}))
	{	# refresh row where the progress line is drawn
		my $rect= $tv->get_cell_area($path,undef);
		$rect->width( ($tv->get_bin_window->get_geometry)[2] );
		$tv->queue_draw_area($rect->values);
	}
	return 1 if @$todo;

	$self->{embfiles_idle}=0;
	# scanning done => update list
	return 0 unless @$pix; # nothing to do if no embedded picture found
	for my $pixi (@$pix)
	{	push @{$self->{filelist}},$pixi->[0];
		$pixi->[1]= length $pixi->[1]; # replace picture data by its size
		$self->{embfiles}{file2ref}{$pixi->[0]}=$pixi;
	}
	$self->scan_embedded_pictures_update_tv if $self->{embfiles}{updatetv} && $self->{show_list};
	$self->set_file($self->{filelist}[0]) unless $self->{current_file};
	return 0;
}

sub scan_embedded_pictures_update_tv
{	my $self=shift;
	my $pix= $self->{embfiles}{pix};
	return unless @$pix;
	my $count= $self->{embfiles}{filecount};
	my $filestore= $self->{filestore};
	$filestore->set($filestore->append(undef),
		0,' '.sprintf(_"in %d/%d files",scalar(@{$_->[2]}),$count),
		1,Songs::filename_escape($_->[0]), 3,$_->[1])	 for @$pix;
}

sub update_file
{	my $self=shift;
	my $old= $self->{loaded_file}||'';
	my $file= $self->{current_file};
	delete $::ToDo{'8_ChangePicture'.$self};
	if (!$file || $file ne $old) #file changed
	{	$self->{view}->reset_zoom if $self->{reset_zoom_on} eq 'file';
		$self->{view}->reset_offset if $self->{reset_offset_on_file_change};
		delete $self->{select_drop};
	}
	my $pixbuf= $file && GMB::Picture::pixbuf($file,undef,undef,'anim_ok');	#disable cache ?
	my %info;
	if ($file)
	{	my $realfile=$file;
		$info{page}=$1 if $realfile=~s/:(\w+)$//;
		$info{filename}= ::filename_to_utf8displayname($realfile);
		$info{size}= (stat $realfile)[7];

		# check if file is actually an embedded picture, then use the actual picture size rather than the file size
		if (my $pixi= $self->{embfiles} && $self->{embfiles}{file2ref}{$file})
		{	$info{size}= $pixi->[1];
		}
	}
	$self->{view}->set_pixbuf($pixbuf,%info);
	$self->{loaded_file}= $file;
	if ($file && ::dirname($file) ne ($self->{loaded_path}||''))	{ $self->refresh_treeviews;}
	$self->update_selection;
}

sub update_selection
{	my $self=shift;
	return unless $self->{show_list};
	my $treeview= $self->{filetv};
	my $treesel= $treeview->get_selection;
	$treesel->unselect_all;
	my $file=$self->{current_file};
	return unless $file;
	my $page= $file=~s/(\.pdf):(\d+)$/$1/i ? $2 : undef;
	$file= Songs::filename_escape($file);
	$self->{busy}=1;
	my $store= $self->{filestore};
	my $iter= $store->get_iter_first;
	while ($iter)
	{	if ($store->get($iter,1) eq $file)
		{	if ($page) { $iter=$store->iter_nth_child($iter,$page-1); }
			$treesel->select_iter($iter);
			$treeview->scroll_to_cell($store->get_path($iter),undef,::FALSE,0,0); #scroll to row if needed
			last;
		}
		$iter= $store->iter_next($iter);
	}
	delete $self->{busy};
}

sub change_file
{	my ($self,$direction)=@_;
	my $file= $self->{current_file};
	my $list= $self->{filelist};
	my $i;
	if ($file) { $i= ::first { $list->[$_] eq $file } 0..$#$list; }
	if (defined $i)
	{	if ($self->{nowrap}) { $i= ::Clamp($i+$direction,0,$#$list); }
		else { $i= ($i+$direction) % @$list; } # wrap-around
	}
	else {$i=0}
	$self->set_file($list->[$i]);
}

sub set_file
{	my ($self,$file)=@_;
	$self->{current_file}=$file;
	return unless $file;
	if ($file && !(grep $file eq $_, @{$self->{filelist}}))	{ $self->set_path(::dirname($file)); }
	else							{ $self->update_file; }
}

sub context_menu_args
{	my $self=shift;
	my $file= $self->{current_file};
	my $pixi= $file && $self->{embfiles} && $self->{embfiles}{file2ref}{$file};
	my $embfiles= $pixi && $pixi->[2]; #list of file:n that have the selected picture in tag
	my $ispage= $file && $file=~m/:\w+$/;
	return self=>$self, field=>$self->{field}, ID=>$self->{ID}, gid=>$self->{gid},
		file=>$file, ispage=>$ispage, writeable=> ($file && !$::CmdLine{ro}),
		embfiles=>$embfiles,
		toolbar=>$self->{toolbar}, view=>$self->{view};
}

package Layout::PictureBrowser::View;
use base 'Gtk2::Widget';

sub new
{	my ($class,%opt)=@_;
	#my $self= bless Gtk2::EventBox->new, $class;
	my $self= bless Gtk2::DrawingArea->new, $class;
	$self->add_events([qw/pointer-motion-mask scroll-mask key-press-mask button-press-mask button-release-mask/]);
	$self->can_focus(::TRUE);
	$self->signal_connect(expose_event => \&expose_cb);
	$self->signal_connect(size_allocate=> \&resize);
	$self->signal_connect(scroll_event => \&scroll_cb);
	$self->signal_connect(key_press_event=> \&key_press_cb);
	$self->signal_connect(button_press_event =>  \&button_press_cb);
	$self->signal_connect(button_release_event=> \&button_release_cb);
	$self->signal_connect(motion_notify_event => \&motion_notify_cb);
	$self->signal_connect(destroy => sub {delete $_[0]{pbanim}});
	$self->{$_}=$opt{$_} for qw/xalign yalign scroll_zoom show_info oneshot/;
	$self->{mode}= $opt{mode}||'P';
	$self->{offsetx}= $self->{offsety} =0;
	$self->{fit}=1; #default to zoom-to-fit
	if (my $c=$opt{bgcolor}) { $self->modify_bg('normal',Gtk2::Gdk::Color->parse($c)); }
	return $self;
}

sub set_pixbuf
{	my ($self,$pixbuf,%info)=@_;
	$self->{rotate}=0;
	$self->{pixbuf}=$pixbuf;
	delete $self->{pbanim};
	Glib::Source->remove(delete $self->{anim_timeout}) if $self->{anim_timeout};
	if ($pixbuf && $pixbuf->isa('Gtk2::Gdk::PixbufAnimation'))
	{	$self->{pbanim}=$pixbuf;
		$self->animate;
	}
	if ($pixbuf)
	{	my $dim= sprintf "%d x %d",$pixbuf->get_width,$pixbuf->get_height;
		my $file= $info{filename} ? ::filename_to_utf8displayname(::basename($info{filename})) : '';
		$file.= " (".sprintf(_"page %d",$info{page}).")" if $info{page};
		my $size= ::format_number($info{size}).' '._"bytes";
		$self->{info}= ::PangoEsc(sprintf "%s  %s\n%s", $dim, $size, $file);
	}
	$self->resize;
}
sub animate
{	my $self=shift;
	my $anim= $self->{pbanim};
	return 0 unless $anim;
	$self->invalidate_gdkwin;
	my $iter= $anim->{iter} ||= $anim->get_iter;
	$iter->advance;
	$self->{pixbuf}=$iter->get_pixbuf;
	my $ms= $iter->get_delay_time;
	$self->{anim_timeout}= Glib::Timeout->add($ms,\&animate,$self) if $ms>0;
	0;
}
sub reset_zoom
{	my $self=shift;
	$self->{pixbuf}=undef; #force refresh
	$self->{fit}=1;
}
sub reset_offset
{	my $self=shift;
	$self->{offsetx}=$self->{offsety}=0;
}

sub expose_cb
{	my ($self,$event)=@_;
	my $pixbuf= $self->{pixbuf};
	return 1 unless $pixbuf;
	my $scale= $self->{scale};
	unless ($scale) {$self->resize; return 1}
	my $pw= $pixbuf->get_width;
	my $ph= $pixbuf->get_height;
	my $x= $self->{x1} - $self->{offsetx};
	my $y= $self->{y1} - $self->{offsety};
	my $cr= Gtk2::Gdk::Cairo::Context->create($self->gdkwindow);
	$cr->rectangle($event->area);
	$cr->clip;
	$cr->save;
	$cr->translate($x,$y);
	$cr->scale($scale,$scale);
	if (my $angle=$self->{rotate})
	{	if ($angle %180){ $cr->translate(.5*$ph,.5*$pw); }
		else		{ $cr->translate(.5*$pw,.5*$ph); }
		$cr->rotate(::PI*$angle/180);
		$cr->translate(-.5*$pw,-.5*$ph);
	}
	if ($pixbuf->get_has_alpha) # if drawing a transparent image, fill with white first
	{	$cr->set_source_rgb(1,1,1);
		$cr->rectangle(0,0,$pw,$ph);
		$cr->fill;
	}
	$cr->set_source_pixbuf($pixbuf,0,0);
	$cr->paint;
	if (my $msg=$self->{dnd_message}) # display a message when dragging a file/link/song above the picture
	{	$cr->restore;
		$self->draw_overlay_text($cr,::PangoEsc($msg),.5,.5);
	}
	elsif ($self->{show_info} && defined $self->{info})
	{	$cr->restore;
		$self->draw_overlay_text($cr,$self->{info},.5,1);
	}
	1;
}

sub draw_overlay_text
{	my ($self,$cr,$text,$x,$y)=@_;
	my $layout=Gtk2::Pango::Layout->new( $self->create_pango_context );
	$layout->set_markup($text);
	my ($tw,$th)= map $_/Gtk2::Pango->scale, $layout->get_size;
	my ($w,$h)=$self->gdkwindow->get_size;
	my $pad=8;
	$x*= $w-$tw-$pad;
	$y*= $h-$th-$pad;
	$cr->set_source_rgba(0,0,0,.5);
	$cr->rectangle($x-$pad, $y-$pad, $tw+2*$pad, $th+2*$pad);
	$cr->fill;
	$cr->set_source_rgb(1,1,1);
	$cr->move_to($x,$y);
	Pango::Cairo::show_layout($cr,$layout);
}

sub resize
{	my $self=shift;
	my $gdkwin= $self->gdkwindow;
	return unless $gdkwin;
	my ($w,$h)=$gdkwin->get_size;
	my ($x,$y)= $self->no_window ? $gdkwin->get_position : (0,0);
	$self->invalidate_gdkwin;
	my $pixbuf= $self->{pixbuf};
	return unless $pixbuf;

	my $pw= $pixbuf->get_width;
	my $ph= $pixbuf->get_height;
	if ($self->{rotate}%180) { ($pw,$ph)=($ph,$pw) }
	my $fit_scale= ::min($w/$pw, $h/$ph);
	my $scale= $self->{scale}||=1;
	if ($self->{fit}) { $scale=$fit_scale }
	elsif ($self->{fit_scale})			# multiply by new image ratio and divide by old image ratio
	{	$scale*= $fit_scale/$self->{fit_scale};	# to keep the final size constant when changing image
	}
	$self->{fit_scale}= $fit_scale;
	$self->{scale}= $scale;
	$pw*=$scale;
	$ph*=$scale;
	my ($max_x,$max_y);
	if ($w>$pw)	{ $max_x= 0;		$self->{x1}= $x+($w-$pw)*$self->{xalign};	$self->{x2}= $pw; }
	else		{ $max_x= $pw-$w;	$self->{x1}= $x;				$self->{x2}= $w;  }
	if ($h>$ph)	{ $max_y= 0;		$self->{y1}= $y+($h-$ph)*$self->{yalign};	$self->{y2}= $ph; }
	else		{ $max_y= $ph-$h;	$self->{y1}= $y;				$self->{y2}= $h;  }
	$self->{max_x}=$max_x;
	$self->{max_y}=$max_y;
	$self->{offsetx}=$max_x if $self->{offsetx}>$max_x;
	$self->{offsety}=$max_y if $self->{offsety}>$max_y;
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	#my $state=$event->get_state;
	#my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	#my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	#my $shift=$state * ['shift-mask'];
	if    (::WordIn($key,'plus KP_Add Home'))	{ $self->change_zoom('+'); }
	elsif (::WordIn($key,'minus KP_Subtract End'))	{ $self->change_zoom('-'); }
	elsif (::WordIn($key,'equal 1 KP_1'))		{ $self->change_zoom(1); }
	elsif (::WordIn($key,'Return KP_Enter'))	{ $self->set_zoom_fit; }
	elsif ($key eq 'Left')				{ $self->rotate(-1); }
	elsif ($key eq 'Right')				{ $self->rotate(1); }
	elsif (lc$key eq 'i')				{ $self->toggle_info; }
	elsif ($self->{oneshot})			{ $self->get_toplevel->close_window; } # shortcuts before this point must only change zoom/orientation
	elsif (lc$key eq 'f')				{ $self->set_fullscreen }
	elsif ($key eq 'Escape' && $self->{fullwin})	{ $self->set_fullscreen(0) }
	elsif (::WordIn($key,'Down space Page_Up'))	{ $self->change_picture(1); }
	elsif (::WordIn($key,'Up BackSpace Page_Down'))	{ $self->change_picture(-1); }
	else {return 0}
	return 1;
}
sub button_press_cb
{	my ($self,$event)=@_;
	$self->grab_focus;
	my $button=$event->button;
	if ($button == 3)
	{	if ($self->{oneshot}) { $self->get_toplevel->close_window; return 1 }
		my @args= ( view=>$self, mode=> $self->{mode}, );
		my $parent=$self; while ($parent=$parent->get_parent) { last if $parent->{view} && $parent->{view}==$self; }
		push @args,$parent->context_menu_args if $parent && $parent->can('context_menu_args');
		::PopupContextMenu( \@Layout::PictureBrowser::ContextMenu, {@args} );
	}
	elsif ($button==9) { $self->change_picture(1); }
	elsif ($button==8) { $self->change_picture(-1);}
	elsif ($button!=1 && $event->type eq '2button-press') { $self->set_fullscreen }
	elsif (!$self->{pressed})
	{	($self->{last_x},$self->{last_y})=$event->coords;
		$self->{pressed}=$button;
	}
	1;
}
sub button_release_cb
{	my ($self,$event)=@_;
	my $button=$event->button;
	if (($self->{pressed}||0)==$button)
	{	if ($button==1)
		{	if    ($self->{dragged}) { $event->window->set_cursor(undef) }
			elsif ($self->{oneshot}) { $self->get_toplevel->close_window; return }
			elsif (!$self->{scrolled}) { $self->change_picture(1); }
		}
		else
		{	$self->set_zoom_fit unless $self->{zoomed} || $self->{prevnext};
			if ($self->{zoomed}) { $event->window->set_cursor(undef) }
		}
		$self->{$_}= undef for qw/last_x last_y dragged pressed zoomed prevnext scrolled/;
	}
	else {return 0}
	1;
}
sub motion_notify_cb
{	my ($self,$event)=@_;
	my $button= $self->{pressed};
	return unless $button;
	my ($ex,$ey)=$event->coords;
	if ($button==1 && ($self->{max_x} || $self->{max_y}))
	{	$event->window->set_cursor(Gtk2::Gdk::Cursor->new('fleur')) unless $self->{dragged};
		$self->{dragged}=1;
		# move picture
		my $x= $self->{offsetx} + $self->{last_x} - $ex;
		my $y= $self->{offsety} + $self->{last_y} - $ey;
		$self->{offsetx}= ::Clamp($x,0,$self->{max_x});
		$self->{offsety}= ::Clamp($y,0,$self->{max_y});
		($self->{last_x},$self->{last_y})= ($ex,$ey);
		$self->invalidate_gdkwin; # could be optimized, copy parts, not sure it's worth it
	}
	elsif ($button!=1 && !$self->{prevnext}) # zoom or prev/next with other button # only prev/next once by button press
	{	my $zoom= int(($self->{last_y}-$ey)/20); # vertical movement >=20
		my $next= int(($self->{last_x}-$ex)/30); # horizontal movement >=30
		if ($zoom)
		{	$zoom="+$zoom" if $zoom>0;
			$self->change_zoom($zoom,$ex,$ey);
			$self->{last_y}=$ey;
			$event->window->set_cursor(Gtk2::Gdk::Cursor->new('double_arrow')) unless $self->{zoomed};
			$self->{zoomed}=1;
		}
		elsif ($next && !$self->{zoomed} && !$self->{oneshot})
		{	$self->change_picture($next>0 ? -1 : 1);
			$self->{last_x}=$ex;
			$self->{prevnext}=1;
		}
	}
	else {return 0}
	1;
}

sub scroll_cb
{	my ($self,$event)=@_;
	my $d= $event->direction;
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	#my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	my $shift=$state * ['shift-mask'];
	my $updown;
	if    ($d eq 'down')	{ $d=-1;$updown=1 }
	elsif ($d eq 'up')	{ $d=1; $updown=1 }
	elsif ($d eq 'right')	{ $d=1 }
	elsif ($d eq 'left')	{ $d=-1}
	else			{return 0}
	my $button1= ($self->{pressed}||0)==1;
	$self->{scrolled}=1 if $button1;
	if ($updown && !$ctrl && ($shift || (!$self->{scroll_zoom} xor $button1))) #ctrl:zoom, shift:prev/next, else depend on scroll_zoom option (button1 inverts it)
	{	$updown=0; $d*=-1;
	}
	if ($updown)	{ $self->change_zoom( ($d>0? '+':'-'), $event->x,$event->y); }
	else		{ $self->change_picture($d); }
}

sub change_picture
{	my ($self,$direction)=@_;
	if ($self->{oneshot}) { $self->get_toplevel->close_window; return }
	my $browser= ::find_ancestor($self,'Layout::PictureBrowser');
	$browser->queue_change_picture($direction) if $browser;
}
sub change_zoom
{	my ($self,$zoom,$x,$y)=@_;
	return unless $self->{pixbuf};
	if (defined $x) # translate event coordinates to image coordinates
	{	$x= $x - $self->{x1}; $x= $self->{x2} if $x>$self->{x2};
		$y= $y - $self->{y1}; $y= $self->{y2} if $y>$self->{y2};
	}
	else # no zoom coordinates => zoom on center
	{	$x= $self->{x2}/2;
		$y= $self->{y2}/2;
	}
	my $nx= $x+$self->{offsetx};
	my $ny= $y+$self->{offsety};
	my $s=$self->{scale};
	$_/=$s for $nx,$ny;
	if ($zoom=~m/^\d*?\.?\d+$/) {$s=$zoom}
	else
	{	my $change= $zoom=~m/^-(\d*)/ ? -.5 : .5;
		$change*=$1 if $1;
		if ($s==1) { if ($s+$change<1) {$s=1/($s-$change)} else {$s+=$change} }
		elsif ($s<1) { $s=1/$s; $s-=$change; $s=1/$s; $s=1 if $s>1; }
		else { $s+=$change; $s=1 if $s<1; }
	}
	$self->{scale}=$s;
	$self->{fit}=0;
	$self->resize;

	$self->{offsetx}= ::Clamp($s*$nx-$x,0,$self->{max_x});
	$self->{offsety}= ::Clamp($s*$ny-$y,0,$self->{max_y});
}
sub toggle_info
{	my $self=shift;
	$self->{show_info}^=1;
	$self->invalidate_gdkwin;
}
sub set_zoom_fit
{	my $self=shift;
	$self->{fit}=1;
	$self->resize;
}
sub rotate
{	my ($self,$rotate)=@_;
	my $r=$self->{rotate}||0;
	$r+= 90*$rotate;
	$self->{rotate}= $r % 360;
	$self->resize;
}
sub gdkwindow
{	$_[0]{fullwin} || $_[0]->window;
}
sub invalidate_gdkwin
{	my $gdkwin= $_[0]->gdkwindow;
	$gdkwin->invalidate_rect(Gtk2::Gdk::Rectangle->new(0,0,$gdkwin->get_size),0) if $gdkwin;
}
sub set_fullscreen
{	my ($self,$fullscreen)=@_;
	$fullscreen= !$self->{fullwin} if !defined $fullscreen;
	return unless $self->{fullwin} xor $fullscreen;
	if ($fullscreen)
	{	my $screen=$self->get_screen;
		my $monitor=$screen->get_monitor_at_window($self->window);
		my (undef,undef,$monitorwidth,$monitorheight)= $screen->get_monitor_geometry($monitor)->values;
		my %attr=
		(	window_type	=> 'toplevel',
			x		=> 0,
			y		=> 0,
			width		=> $monitorwidth,
			height		=> $monitorheight,
			event_mask	=> [qw/exposure-mask pointer-motion-mask button-press-mask button-release-mask key-press-mask/],
		);
		my $gdkwin= $self->{fullwin}= Gtk2::Gdk::Window->new(undef,\%attr);
		$gdkwin->set_user_data($self->window->get_user_data);
		$gdkwin->fullscreen;
		$gdkwin->show;
		$gdkwin->set_transient_for($self->window);
		$self->grab_focus; #make sure we have the focus
	}
	else
	{	my $gdkwin= delete $self->{fullwin};
		$gdkwin->set_user_data(0); #needed ?
		$gdkwin->destroy;
	}
	$self->{pressed}=undef; #reset mouse state, in particular when using double middle button to fullscreen, the mouse could stay in middle-button-pressed mode
	$self->resize;
}

package GMB::Context;

sub new_follow_toolitem
{	my $self=shift;
	my $follow=Gtk2::ToggleToolButton->new_from_stock('gtk-jump-to');
	$follow->set_active($self->{follow});
	my $follow_text= $self->{group} eq 'Play' ? _"Follow playing song" : _"Follow selected song";
	$follow->set_label($follow_text);
	$follow->set_tooltip_text($follow_text);
	$follow->signal_connect(clicked => \&ToggleFollow);
	::set_drag($follow, dest => [::DRAG_ID,sub
		{	my ($follow,$type,@IDs)=@_;
			my $self=::find_ancestor($_[0],'GMB::Context');
			$self->SongChanged($IDs[0],1);
		}]);
	return $follow;
}
sub ToggleFollow
{	my $self=::find_ancestor($_[0],'GMB::Context');
	$self->{follow}^=1;
	$self->SongChanged( ::GetSelID($self) ) if $self->{follow};
}

package Stars;
use base 'Gtk2::EventBox';

sub new_layout_widget
{	my $opt=shift;
	my $field= $opt->{field};
	if (Songs::FieldType($field) ne 'rating') { warn "Stars: invalid field '$field'\n"; $field='rating'; }
	return Stars->new($field,0, \&set_rating_now_cb, %$opt);
}
sub update_layout_widget
{	my ($self,$ID)=@_;
	my $r= defined $ID ? Songs::Get($ID,$self->{field}) : 0;
	$self->set($r);
}
sub set_rating_now_cb
{	my $ID=::GetSelID($_[0]);
	return unless defined $ID;
	Songs::Set($ID, $_[0]{field} => $_[1])
}


sub new
{	my ($class,$field,$nb,$sub, %opt) = @_;
	if (Songs::FieldType($field) ne 'rating') { warn "Stars: invalid field '$field'\n"; $field='rating'; }
	my $self = bless Gtk2::EventBox->new, $class;
	$self->set_visible_window(0);
	$self->{field}=$field;
	$self->{callback}=$sub;
	%opt=(xalign=>.5, yalign=>.5,%opt);
	my $image=$self->{image}=Gtk2::Image->new;
	$image->set_alignment($opt{xalign},$opt{yalign});
	$self->add($image);
	$self->set($nb);
	$self->signal_connect(button_press_event => \&click);
	return $self;
}

sub callback
{	my ($self,$value)=@_;
	if (my $sub=$self->{callback}) {$sub->($self,$value);}
	else {$self->set($value)}
}
sub set
{	my ($self,$nb)=@_;
	$self->{nb}=$nb;
	$nb=$::Options{DefaultRating} if !defined $nb || $nb eq '' || $nb==255;
	$self->set_tooltip_text(_("Song rating")." : $nb %");
	my $pixbuf= Songs::Stars($nb,$self->{field});
	$self->{width}= $pixbuf->get_width;
	$self->{image}->set_from_pixbuf($pixbuf);
}
sub get { shift->{nb}; }

sub click
{	my ($self,$event)=@_;
	if ($event->button == 3) { $self->popup($event); return 1 }
	my ($xalign)=$self->child->get_alignment;
	my $walloc= $self->allocation->width;
	my $width= $self->{width};
	my ($x)=$event->coords;
	$x-= $xalign*($walloc-$width);
	$x/=$width;
	$x=0 if $x<0;
	$x=1 if $x>1;
	my $pb= $Songs::Def{$self->{field}}{pixbuf} || $Songs::Def{'rating'}{pixbuf};
	my $nbstars=$#$pb;
	my $nb=1+int($x*$nbstars);
	$nb*=100/$nbstars;
	$self->callback($nb);
	return 1;
}

sub popup
{	my ($self,$event)=@_;
	my $menu=Gtk2::Menu->new;
	my $set=$self->{nb}; $set='' unless defined $set;
	my $sub=sub { $self->callback($_[1]); };
	for my $nb (0,10,20,30,40,50,60,70,80,90,100,'')
	{	my $item=Gtk2::CheckMenuItem->new( ($nb eq '' ? _"default" : $nb) );
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $set eq $nb;
		$item->signal_connect(activate => $sub, $nb);
		$menu->append($item);
	}
	::PopupMenu($menu,event=>$event);
}

# not really part of Stars::
sub createmenu
{	my ($field,$IDs)=@_;
	if (Songs::FieldType($field) ne 'rating') { warn "Stars::createmenu : invalid field '$field'\n"; $field='rating'; }
	my $pixbufs= $Songs::Def{$field}{pixbuf} || $Songs::Def{rating}{pixbuf};
	my $nbstars= $#$pixbufs;
	my %set;
	$set{$_}++ for Songs::Map($field,$IDs);
	my $set= (keys %set ==1) ? each %set : 'undef';
	my $cb=sub { Songs::Set($IDs,$field => $_[1]); };
	my $menu=Gtk2::Menu->new;
	for my $nb ('',0..$nbstars)
	{	my $item=Gtk2::CheckMenuItem->new;
		my ($child,$rating)= $nb eq ''	? (Gtk2::Label->new(_"default"),'')
						: (Gtk2::Image->new_from_pixbuf($pixbufs->[$nb]),$nb*100/$nbstars);
		$item->add($child);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $set eq $rating;
		$item->signal_connect(activate => $cb, $rating);
		$menu->append($item);
	}
	return $menu;
}


package Layout::Progress;
sub new
{	my ($class,$opt,$ref)=@_;
	my $self= $opt->{vertical} ? Gtk2::VBox->new : Gtk2::HBox->new;
	::Watch($self,Progress=>\&update);
	update($self,$_,$::Progress{$_}) for keys %::Progress;
	$self->{lastclose}=$opt->{lastclose};
	$self->{compact}= $opt->{compact};
	return $self;
}
sub new_pid
{	my ($self,$prop)=@_;
	my $hbox=Gtk2::HBox->new(0,2);
	my $vbox=Gtk2::VBox->new;
	my $label;
	my $bar=Gtk2::ProgressBar->new;
	$bar->set(ellipsize=>'end');
	unless ($self->{compact})
	{	$label=Gtk2::Label->new;
		$label->set_alignment(0,.5);
		$vbox->pack_start($label,0,0,2);
	}
	$hbox->pack_start($bar,1,1,2);
	$vbox->pack_start($hbox,0,0,2);
	$self->pack_start($vbox,1,1,2);
	if (my $sub=$prop->{abortcb})
	{	my $hint= $prop->{aborthint} || _"Abort";
		my $abort= ::NewIconButton('gtk-stop',undef,$sub,'none',$hint);
		$hbox->pack_end($abort,0,0,0);
	}
	$vbox->show_all;
	return [$vbox,$bar,$label];
}
sub update
{	my ($self,$pid,$prop)=@_;
	unless ($prop)	#task finished => remove widgets
	{	my $widgets= delete $self->{pids}{$pid};
		$self->remove( $widgets->[0] ) if $widgets;
		if ($self->{lastclose} && !($self->get_children)) { $self->get_toplevel->close_window; }
		return;
	}
	return if $prop->{widget};
	my $widgets= $self->{pids}{$pid} ||= new_pid($self,$prop);
	my (undef,$bar,$label)=@$widgets;
	my $title=$prop->{title};
	my $details=$prop->{details};
	$details='' unless defined $details;
	my $bartext=$prop->{bartext};
	if ($bartext)
	{	my $c= $prop->{current}+1;
		$bartext=~s/\$current\b/$c/g;
		$bartext=~s/\$end\b/$prop->{end}/g;
	}
	$bartext .= ' '.$prop->{bartext_append} if $prop->{bartext_append};
	if ($self->{compact})
	{	$bartext=$title.' ... '.(defined $bartext ? $bartext : '');
		$bar->set_tooltip_text($details) if $details;
	}
	else
	{	my $format= '<b>%s</b>';
		$format.= "\n%s" if $details;
		$label->set_markup_with_format( $format, $title, $details );
	}
	$bar->set_fraction( $prop->{fraction} );
	$bar->set_text( $bartext )	if defined $bartext;
}

package Layout::EqualizerPresets;
use base 'Gtk2::Box';
use constant SEPARATOR => '  '; # must not be a possible name of a preset, use "  " because EqualizerPresets won't let you create names that contain only spaces

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::HBox->new, $class;
	my $editmode= $self->{editmode}= $opt->{editmode} ? 1 : 0;
	$self->{open}= $opt->{open} ? 1 : -1;
	$self->{onoff}= $opt->{onoff}||0;
	$self->{turnoff}= $self->{onoff}>1 ? 1 : -1;

	my $mainbox= $self->{mainbox}= Gtk2::HBox->new;

	my $combo= $self->{combo}=  Gtk2::ComboBox->new_text;
	$combo->signal_connect(changed=> \&combo_changed_cb);
	$combo->set_row_separator_func(sub { my $text=$_[0]->get_value($_[1]); defined $text && $text eq SEPARATOR});

	my $turnon= $self->{turnon}= Gtk2::Button->new(_"Turn equalizer on");
	$turnon->signal_connect(clicked=> \&button_cb, 'turn_on');

	unless ($opt->{notoggle})
	{	my $toggle= $self->{toggle}= Gtk2::ToggleButton->new;
		$toggle->add(Gtk2::Image->new_from_stock('gtk-edit','menu'));
		$toggle->set_tooltip_text(_"Toggle edit mode");
		$toggle->set_active(1) if $editmode;
		$toggle->signal_connect(toggled=>\&button_cb,'toggle_mode');
		$mainbox->pack_start($toggle,0,0,0);
	}

	$mainbox->pack_start($combo,0,0,0);

	if (!$opt->{notoggle} || $editmode)
	{	my $editbox= $self->{editbox}= Gtk2::HBox->new;
		my $entry  = $self->{entry}=   Gtk2::Entry->new;
		my $sbutton= $self->{sbutton}= ::NewIconButton('gtk-save',  _"Save");
		my $rbutton= $self->{rbutton}= ::NewIconButton('gtk-delete');
		my $completion= Gtk2::EntryCompletion->new;
		$completion->set_model($combo->get_model);
		$completion->set_text_column(0);
		$entry->set_completion($completion);
		$entry->signal_connect(changed=> \&button_cb, 'entry');
		$sbutton->signal_connect(clicked=> \&button_cb, 'save');
		$rbutton->signal_connect(clicked=> \&button_cb, 'delete');
		$sbutton->set_tooltip_text(_"Save preset");
		$rbutton->set_tooltip_text(_"Delete preset");
		$entry->set_tooltip_text(_"Save as...");
		$editbox->pack_start($_,0,0,0) for $entry,$sbutton,$rbutton;
		$mainbox->pack_start($editbox,0,0,0);
		$editbox->show_all;
		$editbox->set_no_show_all(1);
		$editbox->set_visible($editmode);
	}

	for my $w ($turnon,$mainbox)
	{	$self->pack_start($w,0,0,0);
		$w->show_all;
		$w->set_no_show_all(1);
	}
	return $self;
}

sub combo_changed_cb
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	return if $self->{busy};
	my $current= $self->{combo}->get_active_text;
	my $index= $self->{combo}->get_active;
	my $event=Gtk2->get_current_event;
	if ($index>$self->{lastpreset}) # if an action is selected
	{	my $action= $event->isa('Gtk2::Gdk::Event::Button');
		if ($event->isa('Gtk2::Gdk::Event::Key'))
		{	my $key= Gtk2::Gdk->keyval_name( $event->keyval );
			$action=1 if grep $key eq $_, qw/space Return KP_Enter/;
		}
		#only execute actions if clicked with the mouse, or choose in the popup with the keyboard, not by scrolling
		if (!$action)
		{	$self->update('preset'); #reset the combobox to the current preset
		}
		elsif ($self->{open}   == $index) { ::OpenSpecialWindow('Equalizer'); $self->update; }
		elsif ($self->{turnoff}== $index) { ::SetEqualizer(active=>0); }
		return
	}
	::SetEqualizer(preset=>$current) if $current ne '';
}
sub button_cb
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	my $action= $_[1];

	if ($action eq 'save')
	{	::SetEqualizer(preset_save=> $self->{entry}->get_text );
	}
	elsif ($action eq 'delete')
	{	::SetEqualizer(preset_delete=> $self->{combo}->get_active_text );
	}
	elsif ($action eq 'toggle_mode')
	{	$self->{editmode}= $self->{toggle}->get_active ? 1 : 0;
		$self->{editbox}->set_visible($self->{editmode});
	}
	elsif ($action eq 'entry')
	{	$self->update_buttons;
	}
	elsif ($action eq 'turn_on')
	{	::SetEqualizer(active=>1);
	}
}

sub update
{	my ($self,$event)=@_;
	my $ok= $::Play_package->{EQ} && $::Options{use_equalizer};
	if (!$::Play_package->{EQ})
	{	$self->{mainbox}->hide;
		$self->{turnon}->hide;
	}
	elsif ($self->{onoff}>0)
	{	$self->{mainbox}->set_visible($ok);
		$self->{turnon}->set_visible(!$ok);
	}
	else
	{	$self->{mainbox}->set_sensitive($ok);
		$self->{mainbox}->show;
		$self->{turnon}->hide;
	}
	my $full= !$event || $event eq 'package' || $event eq 'presetlist'; #first time or package changed or preset_list changed
	return unless $full || $event eq 'preset';
	my $set= $::Options{equalizer_preset};
	$set='' unless defined $set;

	my $changed= $set eq ''; # not a saved preset
	$full=1 if $changed xor $self->{changed};
	$full=1 if !$changed && !exists $self->{presets}{$set};
	$self->{changed}= $changed;

	my $combo= $self->{combo};
	$self->{busy}=1;
	if ($full) # (re)fill the list
	{	$combo->get_model->clear;
		delete $self->{presets};
		my $i=0;
		if ($set eq '')
		{	$combo->append_text('');
			$combo->set_active($i);
			$i++;
		}
		for my $name (::GetPresets())
		{	$combo->append_text($name);
			$self->{presets}{$name}=$i;
			$combo->set_active($i) if $name eq $set;
			$i++;
		}
		# add actions
		$self->{lastpreset}= $i-1;
		if ($self->{open}>0 || $self->{turnoff}>0)
		{	$combo->append_text(SEPARATOR);
			$i++;
			if ($self->{open}>0)
			{	$combo->append_text(_"Open equalizer...");
				$self->{open}=$i++;
			}
			if ($self->{turnoff}>0)
			{	$combo->append_text(_"Turn equalizer off");
				$self->{turnoff}=$i++;
			}
		}
	}
	elsif ($set ne '') { $combo->set_active( $self->{presets}{$set} ); }
	$self->{entry}->set_text($set) if $set ne '' && $self->{entry};
	$self->{busy}=0;
	$self->update_buttons;
}
sub update_buttons
{	my $self=shift;
	if ($self->{entry})
	{	my $new= $self->{entry}->get_text;
		my $ok= $new=~m/\S/ && ($self->{changed} || !exists $self->{presets}{$new});
		$self->{sbutton}->set_sensitive($ok);
		my $current= $self->{combo}->get_active_text;
		$self->{rbutton}->set_sensitive(defined $current && exists $self->{presets}{$current});
	}
}

package Layout::Equalizer;
sub new
{	my $opt=$_[0];
	my $self=Gtk2::HBox->new(1,0); #homogenous
	$self->{labels}= $opt->{labels};
	$self->{labels}=undef if $self->{labels} eq 'none';
	if ($opt->{preamp})
	{	my $adj=Gtk2::Adjustment->new(1, 0, 2, .05, .1,0);
		my $scale=Gtk2::VScale->new($adj);
		$scale->set_draw_value(0);
		$scale->set_inverted(1);
		$scale->add_mark(1,'left',undef);
		$self->{adj_preamp}=$adj;
		$adj->signal_connect(value_changed =>
			sub { ::SetEqualizer(preamp=>$_[0]->get_value) unless $_[0]{busy}; });
		if ($self->{labels})
		{	my $vbox=Gtk2::VBox->new;
			my $label0=Gtk2::Label->new;
			$vbox->pack_start($label0,0,0,0);
			$self->{Valuelabel_preamp}=$label0;
			$vbox->add($scale);
			my $label1=Gtk2::Label->new;
			$label1->set_markup_with_format(qq(<span size="%s">%s</span>), $self->{labels},_"pre-amp");
			$vbox->pack_start($label1,0,0,0);
			$scale=$vbox;
		}
		$self->{preamp_widget}=$scale;
		$self->pack_start($scale,1,1,2);
		$self->pack_start(Gtk2::HBox->new(0,0),1,1,2); #empty space
	}
	for my $i (0..9)
	{	my $adj=Gtk2::Adjustment->new(0, -1, 1, .05, .1,0);
		my $scale=Gtk2::VScale->new($adj);
		$scale->set_draw_value(0);
		$scale->set_inverted(1);
		$scale->add_mark(0,'left',undef);
		$self->{'adj'.$i}=$adj;
		$adj->signal_connect(value_changed =>
		sub { ::SetEqualizer($_[1],$_[0]->get_value) unless $_[0]{busy}; },$i);
		if ($self->{labels})
		{	my $vbox=Gtk2::VBox->new;
			my $label0=Gtk2::Label->new;
			$vbox->pack_start($label0,0,0,0);
			$self->{'Valuelabel'.$i}=$label0;
			$vbox->add($scale);
			my $label1=Gtk2::Label->new;
			$vbox->pack_start($label1,0,0,0);
			$self->{'Hzlabel'.$i}=$label1;
			$scale=$vbox;
		}
		$self->pack_start($scale,1,1,2);
	}
	return $self;
}

sub update
{	my ($self,$event)=@_;
	my $doall= !$event || $event eq 'package';
	if ($doall || $event eq 'active')
	{	my $ok= $::Play_package->{EQ} && $::Options{use_equalizer};
		$self->set_sensitive($ok);
		$self->{preamp_widget}->set_sensitive( $ok && $::Play_package->{EQpre} ) if $self->{preamp_widget};
	}
	if ($doall && $self->{labels})
	{	my ($min,$max,$unit)= $::Play_package->{EQ} ? $::Play_package->EQ_Get_Range : (-12,12,'');
		my $inc=abs($max-$min)/10;
		$unit=' '.$unit if $unit;
		$self->{unit}= $unit;
		for my $i (0..9)
		{	if ($self->{labels})
			{	my $val='-';
				$val= $::Play_package->EQ_Get_Hz($i)||'?' if $::Play_package->{EQ};
				$self->{'Hzlabel'.$i}->set_markup_with_format(qq(<span size="%s">%s</span>), $self->{labels},$val);
			}
			my $adj=$self->{'adj'.$i};
			$adj->{busy}=1;
			$adj->lower($min);
			$adj->upper($max);
			$adj->step_increment($inc/10);
			$adj->page_increment($inc);
			delete $adj->{busy};
		}
		$self->queue_draw;
	}
	if ($doall || $event eq 'values')
	{	my @val= split /:/, $::Options{equalizer};
		for my $i (0..9)
		{	my $val=$val[$i];
			my $adj=$self->{'adj'.$i};
			$adj->{busy}=1;
			$adj->set_value($val);
			delete $adj->{busy};
			next unless $self->{labels};
			$self->{'Valuelabel'.$i}->set_markup_with_format(qq(<span size="%s">%.1f%s</span>), $self->{labels},$val,$self->{unit});
		}
	}
	if (($doall || $event eq 'preamp') && (my $adj= $self->{adj_preamp}))
	{	my $val= $::Options{equalizer_preamp};
		$adj->{busy}=1;
		$adj->set_value($val);
		delete $adj->{busy};
		$self->{Valuelabel_preamp}->set_markup_with_format(qq(<span size="%s">%d%%</span>), $self->{labels},($val**3)*100) if $self->{Valuelabel_preamp};
	}
}

# SVBox and SHBox are Gtk2::VBox and Gtk2::HBox with a smarter size_allocate function : the normal boxes divide the extra space equally among children with the expand mode. With these boxes the extra space can be allocated to children up to a ratio of their other dimension (expand_to_ratio), or according to a weight (expand_weight)
package SVBox;
use Glib::Object::Subclass
	Gtk2::VBox::,
	signals =>
	{	size_allocate => \&SHBox::size_allocate,
	};
package SHBox;
use Glib::Object::Subclass
	Gtk2::HBox::,
	signals =>
	{	size_allocate => \&size_allocate,
	};

sub size_allocate
{	my ($self,$alloc)=@_;
	my $vertical= $self->isa('Gtk2::VBox');
	my $max_key= $vertical ? 'maxheight' : 'maxwidth';
	my ($x,$y,$bwidth,$bheight)=$alloc->values;
	my $olda=$self->allocation;
	 $olda->x($x); $olda->y($y);
	 $olda->width($bwidth); $olda->height($bheight);
	($y,$x,$bheight,$bwidth)=($x,$y,$bwidth,$bheight) if $vertical;
	my $border=$self->get_border_width;
	$x+=$border;  $bwidth-=$border*2;
	$y+=$border; $bheight-=$border*2;
	my $total_xreq=0; my $weightsum=my $ecount=0;
	my $spacing=$self->get_spacing;
	my @children;
	for my $child ($self->get_children)
	{	next unless $child->visible;
		my $xreq=$vertical ? $child->size_request->height : $child->size_request->width;
		my ($expand,$fill,$pad,$type)=	($Gtk2::VERSION<1.163 || $Gtk2::VERSION==1.170) ?	 #work around memory leak in query_child_packing (gnome bug #498334)
			@{$child->{SBOX_packoptions}} : $self->query_child_packing($child);
		$total_xreq+=$pad*2+$xreq;
		my $eweight= $child->{expand_weight} || 1;
		my $max;
		my @attrib;
		if (my $r=$child->{expand_to_ratio})	{$max=$r*$bheight}
		else					{$max=$child->{$max_key}}
		if	($max)
		{	$max-=$xreq;
			if ($max>0)	{ $expand=$eweight; }
			else		{ $expand=$max=0; }
		}
		if	($expand)	{ $ecount++; $weightsum+=$eweight; $expand=$eweight; }
		my $end= $type eq 'end';
		@attrib= ($child,$expand,$fill,$pad,$end,$xreq,$max);
		if ($end)	{unshift @children,\@attrib} #to keep the same order as a HBox
		else		{push @children,\@attrib}
	}
	my $total_spacing=0;
	if (@children>1)
	{	$total_spacing= $#children*$spacing;
		if ($bwidth<$total_spacing) { $total_spacing=$bwidth; $spacing=$total_spacing/$#children }
		$total_xreq+= $total_spacing;
	}
	my $xend=$x+$bwidth;
	my $homogeneous;
	if ($self->get_homogeneous && @children)
	{	$homogeneous=($bwidth-$total_spacing)/@children;
	}
	elsif ($total_xreq<$bwidth && $ecount)	# if enough room for all, and some have expand attribute
	{	my $w=$bwidth-$total_xreq;
		my $i=0;
		while ($ecount && $w>$ecount)
		{	my $part= $w/$weightsum;
			# [1] is expand, [6] is max, [7] is extra space given
			for my $child (grep $_->[1], @children)	#children that want to expand
			{	my $max=    $child->[6];
				my $expand= $child->[1];
				my $wpart= int($part*$expand);
				if ($max && $wpart>=$max)	# enough to fill its max
				{	$child->[7]+= $max;	# give it its max
					$w-= $max;
					$child->[1]=0;		# no longer want to expand
					$weightsum-=$expand;
					$ecount--;
				}
				elsif ($wpart>0)		# give it its part
				{	$child->[7]+= $wpart;
					$child->[6]-= $wpart if $max;
					$w-= $wpart;
				}
			}
		}
		if ($w>0 && $ecount)		# less than one pixel by widget left
		{	for my $child (sort {$b->[1] <=> $a->[1] } grep $_->[1], @children)	# start with highest weight
			{	$child->[7]++;		# give 1 pixel to each widget
				last unless --$w;	# until no more pixels
			}
			# note that weightsum, ecount, max and expand are not updated here as they are no longer used
		}
	}
	elsif ($total_xreq>$bwidth && @children)	#not enough room for requested width
	{	my $w=$bwidth-$total_spacing;
		# [5] is request [3] is padding
		my @tofit= sort { $a->[5]+$a->[3]*2 <=> $b->[5]+$b->[3]*2 } @children; # sort from smallest to largest
		while (my $child= shift @tofit)
		{	my $give= int($w/(1+@tofit));	# space available for each child left
			$give=0 if $give<0;
			my $padding=$child->[3]*2;
			my $needed= $child->[5]+$padding;
			if ($give >= $needed)			# need less than available
			{	$give= $needed;			# give it its request
			}
			elsif ($give >= $padding)	# space available more than padding
			{	$child->[5]= $give - $padding; # reduce request to fit
			}
			else	# not even enough space for padding
			{	$child->[5]=0;			# set request to 0
				$child->[3]= $give/2;		# give as much padding as available
			}
			$w-= $give;				# remove given space
		}
	}
	for my $ref (@children)
	{	my ($child,undef,$fill,$pad,$end,$ww,undef,$extra)=@$ref;
		my $wwf= $ww;
		$wwf+=$extra if $extra;	# space given by expand
		if (defined $homogeneous)
		{	$wwf=$homogeneous-$pad*2;
			$wwf=0   if $wwf<0;
			$ww=$wwf if $ww>$wwf;
		}
		$ww=$wwf if $fill;
		my $wx;
		my $totalw=$pad*2+$wwf+$spacing;
		$pad+=($wwf-$ww)/2;
		if ($end)	{ $wx=$xend-$pad-$ww;   $xend-=$totalw; }
		else		{ $wx=$x+$pad;		   $x+=$totalw; }
		my $wa= $vertical ?
			Gtk2::Gdk::Rectangle->new($y, $wx, $bheight, $ww):
			Gtk2::Gdk::Rectangle->new($wx, $y, $ww, $bheight);
		$child->size_allocate($wa);
	}
}

package Skin;

sub new
{	my ($class,$string,$widget,$options)=@_;
	my $self=bless {},$class;
	($self->{file},$self->{crop},$self->{resize},my$states1,my$states2)=split /:/,$string;
	my %states;
	my @states2= $states2 ? (map $_.'_', split '_',$states2) :
				('');
	$states1||='normal';
	my $n=0;
	for my $s (@states2)
	{	$states{$s.$_}=$n++ for split '_',$states1;
	}
	$self->{states}=\%states;
	$self->{skin_options}{$_}=$options->{$_} for qw/PATH SkinPath SkinFile/;
	my $pb=$self->makepixbuf($states2[0].'normal');
	return undef unless $pb;
	$self->{minwidth}=my $w=$pb->get_width;
	$self->{minheight}=my $h=$pb->get_height;
	$widget->set_size_request($w,$h) if $widget;
	return $self;
}

sub draw
{	my ($widget,$event,$self,$x,$y,$w,$h)=@_;
	return 0 unless $self;
	unless ($h)
	{	($x,$y,$w,$h)=$widget->allocation->values;
		$x=$y=0 unless $widget->no_window; #x and y are relative to the parent window, so are only useful if the widget use the parent window
	}
	my $state1=$widget->state;
	my $state2=$widget->{state};
	my $state='normal';
	if (my $states=$self->{states})
	{	my @l= ($state1,'normal');
		if ($state2)
		{	$state2=&$state2;
			unshift @l, $state2.'_'.$state1, $state2.'_normal';
		}
		for (@l)
		{	if (exists $states->{$_}) { $state=$_; last }
		}
	}
	my $pb=$self->{pb}{$state};
	if ($pb && $self->{resize})
	{	$pb=undef if $pb->get_width != $w || $pb->get_height != $h;
	}
	$pb ||= $self->makepixbuf($state,$w,$h);
	return 0 unless $pb;
	my $pbw=$pb->get_width;
	my $pbh=$pb->get_height;
	$x+=int ($w-$pbw)/2;
	$y+=int ($h-$pbh)/2;
	my $style=$widget->get_style;
	my $gc=Gtk2::Gdk::GC->new($widget->window);
	$gc->set_clip_rectangle($event->area);
	$widget->window->draw_pixbuf($gc,$pb,0,0,$x,$y,$pbw,$pbh,'none',0,0);
	$style->paint_focus($widget->window, $state1, $event->area, $widget, undef, $x,$y,$pbw,$pbh) if $widget->has_focus;
	if ($widget->{shape}) #not sure it's a good idea
	{	#my (undef,$mask)=$pb->render_pixmap_and_mask(1); #leaks X memory for Gtk2 <1.146 or <1.153
		my $mask=Gtk2::Gdk::Pixmap->new(undef,$pbw,$pbh,1);
		$pb->render_threshold_alpha($mask,0,0,0,0,-1,-1,1);
		$widget->parent->shape_combine_mask($mask,$x,$y);
	}
	1;
}

sub _load_skinfile
{	my ($file,$crop,$options)=@_;
	my $pb;
	if (ref $file)
	{	$pb=$file if ref $file eq 'Gtk2::Gdk::Pixbuf';
	}
	else
	{	$options||={};
		$file ||= $options->{SkinFile};
		if ($file)
		{	my $path= $options->{SkinPath};
			$file= $path.::SLASH.$file if defined $path;
			$file= ::SearchPicture($file, $options->{PATH});
			$pb= GMB::Picture::pixbuf($file) if $file;
		}
	}
	return unless $pb;
	if ($crop)
	{	my @dim=split '_',$crop;
		if (@dim==4) { $pb=$pb->new_subpixbuf(@dim) }
	}
	return $pb;
}

sub makepixbuf
{	my ($self,$state,$w,$h)=@_;
	my $pb=_load_skinfile($self->{file},$self->{crop},$self->{skin_options});
	return undef unless $pb;
	if (my $states=$self->{states})
	{	my $w= $pb->get_width / keys %$states;
		my $x= $states->{$state}*$w;
		$pb=$pb->new_subpixbuf($x,0,$w,$pb->get_height);
	}
	my $resize=$self->{resize};
	if ($resize && $h)
	{	$pb=_resize($pb,$resize,$w,$h);
	}
	return $self->{pb}{$state}=$pb;
}

sub _resize
{	my ($src,$opt,$width,$height)=@_;
	my $w= $src->get_width;
	my $h= $src->get_height;
	if ($opt eq 'ratio')
	{	my $r=$w/$h;
		my $w2=int(($height||0)*$r);
		my $h2=int(($width ||0)/$r);
		if ($height && $h2>$height)	{$width =$w2}
		else				{$height=$h2}
		return undef unless $height && $width;
		return $src->scale_simple($width,$height,'hyper'); #or bilinear ?
	}
	my ($s_c)=		$opt=~m/^([es])/;
	my ($s_t,$top)=		$opt=~m/t([es])(\d+)/;
	my ($s_b,$bottom)=	$opt=~m/b([es])(\d+)/;
	my ($s_l,$left)=	$opt=~m/l([es])(\d+)/;
	my ($s_r,$right)=	$opt=~m/r([es])(\d+)/;
	if    ($opt=~m/v([es])/) { $s_c=$1; $width =$w;} #$s_t=$1; $top =$h; ?
	elsif ($opt=~m/h([es])/) { $s_c=$1; $height=$h;} #$s_l=$1; $left=$w; ?
	my $wi=$w -($left||=0) -($right||=0); my $dwi=$width -$left -$right;
	my $hi=$h -($top||=0) -($bottom||=0); my $dhi=$height -$top -$bottom;

	my $dest=Gtk2::Gdk::Pixbuf->new($src->get_colorspace, $src->get_has_alpha, $src->get_bits_per_sample, $width, $height);

	#4 corners
	$src->copy_area(0,0, $left,$top, $dest, 0,0) if $left && $top;
	$src->copy_area($w-$right,0, $right,$top, $dest, $width-$right,0) if $right && $top;
	$src->copy_area(0,$h-$bottom, $left,$bottom, $dest, 0,$height-$bottom) if $left && $bottom;
	$src->copy_area($w-$right,$h-$bottom, $right,$bottom, $dest, $width-$right,$height-$bottom) if $right && $bottom;

	my @parts;
	# borders : top, bottom, left, right
	push @parts, [$left,0, $wi,$top, $left,0, $dwi,$top, $s_t] if $top;
	push @parts, [$left,$h-$bottom, $wi,$bottom, $left,$height-$bottom, $dwi,$bottom, $s_b] if $bottom;
	push @parts, [0,$top, $left,$hi, 0,$top, $left,$dhi, $s_l] if $left;
	push @parts, [$w-$right,$top, $right,$hi, $width-$right,$top, $right,$dhi, $s_r] if $right;
	#center
	push @parts, [$left,$top, $wi,$hi, $left,$top, $dwi,$dhi, $s_c] if $hi && $wi;

	for my $ref (@parts)
	{	my ($x,$y,$w,$h,$x2,$y2,$w2,$h2,$s)=@$ref;
		my $subp=$src->new_subpixbuf($x,$y,$w,$h);
		if ($s eq 's')	#stretch
		{	$subp=$subp->scale_simple($w2, $h2, 'hyper');
			$subp->copy_area(0,0, $w2,$h2, $dest, $x2,$y2 );
		}
		else		#repeat to cover the area
		{	my $w1=$w;
			for my $x3 (map $w*$_, 0..int($w2/$w)+1)
			{	$w1=$w2-$x3 if $x3+$w1>$w2;
				next unless $w1;
				my $h1=$h;
				for my $y3 (map $h*$_, 0..int($h2/$h)+1)
				{	$h1=$h2-$y3 if $y3+$h1>$h2;
					next unless $h1;
					$subp->copy_area(0,0, $w1,$h1, $dest, $x2+$x3,$y2+$y3 );
				}
			}
		}
	}
	return $dest;
}

1;
