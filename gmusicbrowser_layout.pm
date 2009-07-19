# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;

package Layout;
use Gtk2;

use constant
{
 TRUE  => 1,
 FALSE => 0,

 SIZE_BUTTONS => 'large-toolbar',
 SIZE_FLAGS => 'menu',
};

my @MenuQueue=
(	{label => _"Queue album",	code => sub { ::EnqueueSame('album',$_[0]{ID}); } },
	{label => _"Queue artist",	code => sub { ::EnqueueSame('artist',$_[0]{ID});} },  # or use field 'artists' or 'first_artist' ?
	{label => _"Normal mode",	code => sub {&::EnqueueAction('')},		radio => sub {!$::QueueAction} },
	{label => _"Auto fill queue",	code => sub {&::EnqueueAction('autofill')},	radio => sub {$::QueueAction eq 'autofill'} },
	{label => _"Wait when queue empty",	code => sub {&::EnqueueAction('wait')}, radio => sub {$::QueueAction eq 'wait'} },
	{label => _"Stop when queue empty",	code => sub {&::EnqueueAction('stop')}, radio => sub {$::QueueAction eq 'stop'} },
	{label => _"Quit when queue empty",	code => sub {&::EnqueueAction('quit')}, radio => sub {$::QueueAction eq 'quit'} },
	{label => _"Turn off computer when queue empty",	code => sub {&::EnqueueAction('turnoff')}, radio => sub {$::QueueAction eq 'turnoff'}, test => sub { $::Options{Shutdown_cmd}; } },
	{label => _"Clear queue",	code => \&::ClearQueue,		test => sub{@$::Queue}},
	{label => _"Shuffle queue",	code => \&::ShuffleQueue,	test => sub{@$::Queue}},
	{label => _"Edit...",		code => \&::EditQueue},
);

my @MainMenu=
(	{label => _"Settings",		code => \&::PrefDialog,	stockicon => 'gtk-preferences' },
	{label => _"Open Browser",	code => \&::Playlist,	stockicon => 'gmb-playlist' },
	{label => _"Open Context window",code => \&::ContextWindow, stockicon => 'gtk-info'},
	{label => _"Switch to fullscreen mode",code => \&::ToggleFullscreenLayout, stockicon => 'gtk-fullscreen'},
	{label => _"About",		code => \&::AboutDialog,stockicon => 'gtk-about' },
	{label => _"Quit",		code => \&::Quit,	stockicon => 'gtk-quit' },
);

my %objects=
(	Prev =>
	{	class	=> 'Layout::Button',
		#size	=> SIZE_BUTTONS,
		stock	=> 'gtk-media-previous',
		tip	=> _"Recently played songs",
		activate=> \&::PrevSong,
		click3	=> sub { ::ChooseSongs(undef,::GetPrevSongs(5)); },
	},
	Stop =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-media-stop',
		tip	=> _"Stop",
		activate=> \&::Stop,
		click3	=> sub {&::EnqueueAction('stop')},
	},
	Play =>
	{	class	=> 'Layout::Button',
		state	=> sub {$::TogPlay? 'Paused' : 'Play'},
		stock	=> {Paused => 'gtk-media-pause', Play => 'gtk-media-play' },
		tip	=> sub {$::TogPlay? _"Pause" : _"Play"},
		activate=> \&::PlayPause,
		#click3	=> undef,
		event	=> 'Playing',
	},
	Next =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-media-next',
		tip	=> _"Next Song",
		activate=> \&::NextSong,
		click3	=> sub { ::ChooseSongs(undef,::GetNextSongs(5)); },
	},
	Playlist =>
	{	class	=> 'Layout::Button',
		oldopt1 => 'toggle',
		stock	=> 'gmb-playlist',
		tip	=> _"Open Browser window",
		activate=> sub {::Playlist($_[0]{opt1})},
		click3	=> sub {Layout::Window->new($::Options{LayoutB});},
	},
	BContext =>
	{	class	=> 'Layout::Button',
		oldopt1 => 'toggle',
		stock	=> 'gtk-info',
		tip	=> _"Open Context window",
		activate=> sub {::ContextWindow($_[0]{opt1})},
		click3	=> sub {Layout::Window->new('Context');},
	},
	Pref =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-preferences',
		tip	=> _"Edit Settings",
		activate=> \&::PrefDialog,
		click3	=> sub {Layout::Window->new($::Options{Layout});},
		click2	=> \&::AboutDialog,
	},
	Quit =>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-quit',
		tip	=> _"Quit",
		activate=> \&::Quit,
		click3	=> sub {&::EnqueueAction('quit')},
	},
	LockArtist =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		size	=> SIZE_FLAGS,
		state	=> sub { ($::TogLock && $::TogLock eq 'first_artist')? 'on' : 'off' },
		stock	=> { on => 'gmb-lock', off => ['','gmb-locklight'] },
		tip	=> _"Lock on Artist",
		click1	=> sub {::ToggleLock('first_artist');},
		event	=> 'Lock',
	},
	LockAlbum =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		size	=> SIZE_FLAGS,
		state	=> sub { ($::TogLock && $::TogLock eq 'album')? 'on' : 'off' },
		stock	=> { on => 'gmb-lock', off => ['','gmb-locklight'] },
		tip	=> _"Lock on Album",
		click1	=> sub {::ToggleLock('album');},
		event	=> 'Lock',
	},
	Sort =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		size	=> SIZE_FLAGS,
		state	=> sub { my $s=$::Options{'Sort'};($s=~m/^random:/)? 'random' : ($s eq 'shuffle')? 'shuffle' : 'sorted'; },
		stock	=> { random => 'gmb-random', shuffle => 'gmb-shuffle', sorted => 'gtk-sort-ascending' },
		tip	=> sub { _("Play order :\n").::ExplainSort($::Options{Sort}); },
		click1	=> \&::ToggleSort,
		click3	=> \&SortMenu,
		event	=> 'Sort SavedWRandoms SavedSorts',
	},
	Filter =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		size	=> SIZE_FLAGS,
		state	=> sub { defined $::ListMode ? 'list'
			: $::SelectedFilter->is_empty ? 'library' : 'filter'; },
		stock	=> { list => 'gmb-list', library => 'gmb-library', filter => 'gmb-filter' },
		tip	=> sub
			{ defined $::ListMode	? ref $::ListMode	? _"unnamed static list"
									: $::ListMode.' list'
						: _("Playlist filter :\n").$::SelectedFilter->explain;
			},
		click1	=> \&RemoveFilter,
		click3	=> \&FilterMenu,
		event	=> 'Filter SavedFilters',
	},
	Queue =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		size	=> SIZE_FLAGS,
		state	=> sub  { @$::Queue?	 'queue' :
				  $::QueueAction? $::QueueAction :
						 'noqueue'
				},
		stock	=> sub  {$_[0] eq 'queue'  ?	'gmb-queue' :
				 $_[0] eq 'noqueue'?	['','gmb-queue'] :
							$::QActions{$_[0]}[1] ;
				},
		tip	=> sub { ::CalcListLength($::Queue,'queue')
				.($::QueueAction? "\n". ::__x( _"then {action}", action => $::QActions{$::QueueAction}[2] ) : '');
				},
		click1	=> \&::ClearQueue,
		click3	=> sub {::PopupContextMenu(\@MenuQueue,{ID=>$::SongID});},
		event	=> 'Queue QueueAction',
		dragdest=> [::DRAG_ID,sub {shift;shift;::Enqueue(@_);}],
	},
	Vol =>
	{	class	=> 'Layout::Button',
		nobutton=> undef,
		state	=> sub { ::GetMute() ? 'm' : ::GetVol() },
		stock	=> sub { 'gmb-vol'.( $_[0] eq 'm' ? 'm' : int(($_[0]-1)/100*$::NBVolIcons) );  },
		tip	=> sub { _("Volume : ").::GetVol().'%' },
		click1 => sub { ::PopupLayout('Volume'); },
		click3	=> sub { ::ChangeVol('mute') },
		event	=> 'Vol',
	},
	Button =>
	{	class	=> 'Layout::Button',
	},
	Label =>
	{	class	=> 'Layout::Label',
		oldopt1 => sub { 'text',$_[0] },
		default_group => 'Play',
	},
	Pos =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		initsize=> ::__("%d song in queue","%d songs in queue",99999), #longest string that will be displayed
		click1	=> sub { ::ChooseSongs(undef,::GetNeighbourSongs(5)) unless $::RandomMode || @$::Queue; },
		update	=> sub  { my $t=(@$::ListPlay==0)	?	'':
					 @$::Queue		?	::__("%d song in queue","%d songs in queue", scalar @$::Queue):
					!defined $::Position	?	::__("%d song","%d songs",scalar @$::ListPlay):
									($::Position+1).'/'.@$::ListPlay;
				  $_[0]->set_markup( '<small>'.$t.'</small>' );
				},
		event	=> 'Pos Queue',
	},
	Title =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		minsize	=> 20,
		markup	=> '<b><big>%S</big></b>%V',
		markup_empty => '<b><big>&lt;'._("Playlist Empty").'&gt;</big></b>',
		click1	=> \&PopupSongsFromAlbum,
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupContextMenu(\@::SongCMenu,{mode=> 'P', self=> $_[0], IDs => [$ID]}) if defined $ID;},
		dragsrc => [::DRAG_ID,\&DragCurrentSong],
		dragdest=> [::DRAG_ID,sub {::Select(song => $_[2]);}],
	},
		cursor	=> 'hand2',
	Title_by =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		minsize	=> 20,
		markup	=> ::__x(_"{song} by {artist}",song => "<b><big>%S</big></b>%V", artist => "<b>%a</b>"),
		markup_empty => '<b><big>&lt;'._("Playlist Empty").'&gt;</big></b>',
		click1	=> \&PopupSongsFromAlbum,
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupContextMenu(\@::SongCMenu,{mode=> 'P', self=> $_[0], IDs => [$ID]}) if defined $ID;},
		dragsrc => [::DRAG_ID,\&DragCurrentSong],
		cursor	=> 'hand2',
	},
	Artist =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		minsize	=> 20,
		markup	=> '<b>%a</b>',
		click1	=> sub { ::PopupAA('artists'); },
		click3	=> sub { my $ID=::GetSelID($_[0]); ::ArtistContextMenu( Songs::Get_gid($ID,'artists'),{self =>$_[0], ID=>$ID, mode => 'P'}) if defined $ID; },
		dragsrc => [::DRAG_ARTIST,\&DragCurrentArtist],
		cursor	=> 'hand2',
	},
	Album =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		minsize	=> 20,
		markup	=> '<b>%l</b>',
		click1	=> sub { my $ID=::GetSelID($_[0]); ::PopupAA( 'album', from=> Songs::Get_gid($ID,'artists')) if defined $ID; },
		click3	=> sub { my $ID=::GetSelID($_[0]); ::PopupAAContextMenu({self =>$_[0], field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album'), mode => 'P'}) if defined $ID; },
		dragsrc => [::DRAG_ALBUM,\&DragCurrentAlbum],
		cursor	=> 'hand2',
	},
	Date =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		markup	=> ' %y',
		markup_empty=> '',
	},
	Comment =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		markup	=> '%C',
	},
	Length =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		initsize=>	::__x( _" of {length}", 'length' => "XX:XX"),
		markup	=>	::__x( _" of {length}", 'length' => "%m" ),
		markup_empty=>	::__x( _" of {length}", 'length' => "0:00" ),
#		font	=> 'Monospace',
	},
	LabelTime =>
	{	class	=> 'Layout::Label',
		default_group => 'Play',
		xalign	=> 1,
		options => 'remaining',
		initsize=> '-XX:XX',
#		font	=> 'Monospace',
		event	=> 'Time',
		click1 => sub { $_[0]{remaining}=!$_[0]{remaining}; $_[0]{'ref'}{update}->(); },
		update	=> sub { $_[0]->set_label( ::TimeString($_[0]{remaining}) ) unless $_[0]{busy}; },
	},
	Scale =>
	{	class	=> 'Layout::Bar::Scale',
		default_group => 'Play',
		event	=> 'Time',
		update	=> sub { $_[0]->set_val($::PlayTime); },
		fields	=> 'length',
		schange	=> sub { $_[0]->set_max( defined $_[1] ? Songs::Get($_[1],'length') : 0); },
		set	=> sub { ::SkipTo($_[1]) },
		scroll	=> sub { $_[1] ? ::Forward(undef,10) : ::Rewind (undef,10) },
		set_preview => \&Layout::Bar::update_preview_Time,
	},
	TimeBar =>
	{	class	=> 'Layout::Bar',
		default_group => 'Play',
		event	=> 'Time',
		update	=> sub { $_[0]->set_val($::PlayTime); },
		fields	=> 'length',
		schange	=> sub { $_[0]->set_max( defined $_[1] ? Songs::Get($_[1],'length') : 0); },
		set	=> sub { ::SkipTo($_[1]) },
		scroll	=> sub { $_[1] ? ::Forward(undef,10) : ::Rewind (undef,10) },
		set_preview => \&Layout::Bar::update_preview_Time,
	},
	VolBar =>
	{	class	=> 'Layout::Bar',
		orientation => 'left-to-right',
		event	=> 'Vol',
		update	=> sub { $_[0]->set_val( ::GetVol() ); },
		set	=> sub { ::UpdateVol($_[1]) },
		scroll	=> sub { ::ChangeVol($_[1] ? 'up' : 'down') },
		max	=> 100,
	},
	VolSlider =>
	{	class	=> 'Layout::Bar::Scale',
		orientation => 'bottom-to-top',
		event	=> 'Vol',
		update	=> sub { $_[0]->set_val( ::GetVol() ); },
		set	=> sub { ::UpdateVol($_[1]) },
		scroll	=> sub { ::ChangeVol($_[1] ? 'up' : 'down') },
		max	=> 100,
	},
	LabelVol =>
	{	class	=> 'Layout::Label',
		initsize=> '000',
		event	=> 'Vol',
		update	=> sub { $_[0]->set_label(sprintf("%d",::GetVol())); },
	},
	Stars =>
	{	New	=> sub	{ Stars->new(0,sub {	my $ID=::GetSelID($_[0]);
							return unless defined $ID;
							Songs::Set($ID, rating => $_[1])
						  });
				},
		default_group => 'Play',
		fields	=> 'rating',
		schange	=> sub	{ my $r=(defined $_[1])? Songs::Get($_[1],'rating') : 0; $_[0]->set($r); },
	},
	Cover =>
	{	class	=> 'Layout::AAPicture',
		default_group => 'Play',
		aa	=> 'album',
		oldopt1 => 'maxsize',
		schange	=> sub { my $key=(defined $_[1])? Songs::Get_gid($_[1],'album') : undef ; $_[0]->set($key); },
		click1	=> \&PopupSongsFromAlbum,
		event	=> 'Picture_album',
		update	=> \&Layout::AAPicture::Changed,
		#size	=> 60,
		noinit	=> 1,
		dragsrc => [::DRAG_ALBUM,\&DragCurrentAlbum],
		fields	=> 'album',
	},
	ArtistPic =>
	{	class	=> 'Layout::AAPicture',
		default_group => 'Play',
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
		default_group => 'Play',
		fields	=> 'label',
		schange	=> \&UpdateLabelsIcon,
		update	=> \&UpdateLabelsIcon,
		event	=> 'Icons',
		tip	=> '%L',
	},
	Filler =>
	{	New	=> sub { Gtk2::HBox->new; },
	},
	SongList =>
	{	New	=> sub { $_[0]{type}||='B';SongList->new($_[0],$_[1]); },
		oldopt1 => 'mode',			 #for version <0.9475
		oldopt2 => 'sort cols colwidth',
	},
	SongTree =>
	{	New	=> sub { $_[0]{type}||='B';SongTree->new($_[0],$_[1]); },
	},
	AABox	=>
	{	class	=> 'GMB::AABox',
		oldopt1	=> sub { 'aa='.( $_[0] ? 'artist' : 'album' ) } #for version <0.9479
	},
	FPane	=>
	{	class	=> 'FilterPane',
		oldopt1	=> sub
			{	my ($nb,$hide,@pages)=split ',',$_[0];
				return (nb => ++$nb,hide => $hide,pages=>join('|',@pages));
			},
	},
	Total	=>
	{	class	=> 'LabelTotal',
		oldopt1 => 'mode',
	},
	FBox	=>
	{	New => \&Browser::makeFilterBox,
		dragdest => [::DRAG_FILTER,sub { ::SetFilter($_[0],$_[2]);}],
	},
	FLock	=>	{ New => \&Browser::makeLockToggle,},
	HistItem =>	{ New => sub { Gtk2::MenuItem->new(_"Recent Filters"); },
			  setmenu => \&Browser::make_history_menu,
			},
	PlayItem =>	{ New => sub { Gtk2::MenuItem->new(_"Playing"); },
			  setmenu => \&Browser::make_playing_menu,
			},
	LSortItem =>	{ New => sub { Gtk2::MenuItem->new(_"Sort"); },
			  setmenu => \&Browser::make_sort_menu,
			},
	PSortItem =>	{ New => sub { Gtk2::MenuItem->new(_"Play order"); },
			  setmenu => sub {SortMenu();},
			},
	PFilterItem =>	{ New => sub { Gtk2::MenuItem->new(_"Playlist filter"); },
			  setmenu => sub {FilterMenu();},
			},
	QueueItem =>	{ New => sub { Gtk2::MenuItem->new(_"Queue"); },
			  setmenu => sub{ my $m=::PopupContextMenu(\@MenuQueue,{ID=>$::SongID}); },
			},
	MainMenuItem =>	{ New => sub { Gtk2::MenuItem->new(_"Main"); },
			  setmenu => sub{ my $m=::PopupContextMenu(\@MainMenu); },
			},
	MenuItem =>	{ New => \&Layout::MenuItem::new,
			},
	SeparatorMenuItem=>
			{ New => sub { Gtk2::SeparatorMenuItem->new },
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
	QueueList =>
	{	New	=> sub { $_[0]{type}='Q'; return SongList->new($_[0],$_[1],$::Queue); }
	},
	Context =>
	{	class	=> 'GMB::Context',
		default_group => 'Play',
	},
	TogButton =>
	{	class	=> 'Layout::TogButton',
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
		stock	=> 'gmb-random', #FIXME
		tip	=> _"Choose Random Album",
		activate=> sub { my $al=AA::GetAAList('album'); my $r=int rand(@$al); my $key=$al->[$r]; my $list=AA::GetIDs('album',$key); if (my $ac=$_[0]{opt1}{action}) { ::DoActionForList($ac,$list); } else { my $ID=::FindFirstInListPlay($list); ::Select( song => $ID)}; },
		click3	=> sub { my @list; my $al=AA::GetAAList('album'); my $nb=5; while ($nb--) { my $r=int rand(@$al); push @list, splice(@$al,$r,1); last unless @$al; } ::PopupAA('album', list=>\@list, format=> ::__x( _"{album}\n<small>by</small> {artist}", album => "%a", artist => "%b"));  },
	},
	AASearch =>
	{	class	=> 'AASearch',
	},
	SongSearch =>
	{	class	=> 'SongSearch',
	},
	SimpleSearch =>
	{	class	=> 'SimpleSearch',
		dragdest=> [::DRAG_FILTER,sub { ::SetFilter($_[0],$_[2]);}],
	},
	TabbedLists =>
	{	class	=> 'TabbedLists',
	},
	Visuals		=>
	{	New	=> sub {my $darea=Gtk2::DrawingArea->new; $darea->set_size_request(200,50); return $darea unless $::Packs{Play_GST} && $::Packs{Play_GST}{visuals}; Play_GST::add_visuals($darea); my $eb=Gtk2::EventBox->new; $eb->add($darea); return $eb},
		click1	=> sub {Play_GST::set_visual('+');}, #select next visual
		click2	=> \&ToggleFullscreen, #FIXME use a fullscreen layout instead,
		click3	=> \&VisualsMenu,
	},
	Connections	=>	#FIXME could be better
	{	class	=> 'Layout::Label',
		update	=> sub { my $h=\%Play_GST_server::sockets; my $t=join "\n",map $h->{$_}[2], grep $h->{$_}[1],keys %$h; $t= $t? _("Connections from :")."\n".$t : _("No connections"); $_[0]->child->set_text($t); if ($::Play_package eq 'Play_GST_server') {$_[0]->show; $_[0]->child->show_all} else {$_[0]->hide; $_[0]->set_no_show_all(1)}; },
		event	=> 'connections',
	},
	EditListButtons	=>
	{	class	=> 'EditListButtons',
	},
	QueueActions	=>
	{	class	=> 'QueueActions',
	},
	OpenQueue	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gmb-queue',
		tip	=> _"Open Queue window",
		activate=> sub {::EditQueue($_[0]{opt1})},
	},
	Fullscreen	=>
	{	class	=> 'Layout::Button',
		stock	=> 'gtk-fullscreen',
		tip	=> _"Toggle fullscreen mode",
		activate=> \&::ToggleFullscreenLayout,
		#activate=> \&ToggleFullscreen,
	},
	Repeat	=>
	{	New => sub { Gtk2::CheckButton->new(_"Repeat"); },
		activate=> sub { ::SetRepeat($_[0]->get_active); },
		event	=> 'Repeat Sort',
		update	=> sub { if ($_[0]->get_active xor $::Options{Repeat}) { $_[0]->set_active($::Options{Repeat});} $_[0]->set_sensitive(!$::RandomMode); },
	},
	AddLabelEntry =>
	{	New => \&AddLabelEntry,
	},
	LabelToggleButtons =>
	{	class => 'Layout::LabelToggleButtons',
		default_group => 'Play',
		schange	=> \&Layout::LabelToggleButtons::update_song,
	},
	PlayOrderCombo =>
	{	New => \&PlayOrderComboNew,
		event => 'Sort SavedWRandoms SavedSorts',
		update	=> \&PlayOrderComboUpdate,
	},
	Progress =>
	{	class => 'Layout::Progress',
		compact=>1,
	},
	ProgressV =>
	{	class => 'Layout::Progress',
		vertical=>1,
	},
	Equalizer =>
	{	New => \&Layout::Equalizer::new,
		event => 'Equalizer',
		update => \&Layout::Equalizer::update,
	},
#	RadioList =>
#	{	class => 'GMB::RadioList',
#	},
);

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
		my $cat= $Layouts{$id}{Category} || ($name2=~s#(.+)/## && $1);
		my $name= $Layouts{$id}{Name} || $name2;
		my $array= $cat ?  ($cat{$cat}||=[]) : \@tree;
		push @$array, $id, _( $name );
	}
	push @tree, $cat{$_},_( $_ ) for keys %cat;
	return \@tree;
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
		{	my $name= $Layouts{$id}{Name} || $id;
			my $type= $Layouts{$id}{Type} || '';
			$type="($type)" if $type;
			printf "%-4s %-${max}s : %s\n",$type,$id,$name;
		}
		exit;
	}
}

sub ReadLayoutFile
{	my $file=shift;
	#no warnings;#warn $file;
	return unless -f $file && -r $file;
	open my$fh,"<:utf8",$file;
	my $first;
	while (1)
	{	my ($next,$longline);
		my @lines=($first);
		while (local $_=<$fh>)
	 	{	s#^\s+##;
			next if m/^#/;
			s#\s*[\n\r]+$##;
			if (s#\\$##) {$longline.=$_;next}
			next if $_ eq '';
			if ($longline) {$_=$longline.$_;undef $longline;}
			if (m#^[{[]#) {$next=$_;last}
			push @lines,$_;
		}
		if ($first)
		{	if ($first=~m#^\[#) {ParseLayout(\@lines)}
			else		{ParseSongTreeSkin(\@lines)}
		}
		$first=$next;
		last unless $first;
	}
	close $fh;
}

sub ParseLayout
{	my $lines=$_[0];	#print join "\n",@$lines,"\n\n\n";
	my $first=shift @$lines;
	my $name;
	if ($first=~m/^\[([^]=]+)\](?:\s*based on (.+))?$/)
	{	if (defined $2 && !exists $Layouts{$2})
		{	warn "Ignoring layout '$1' because it is based on unknown layout '$2'\n";
			return;
		}
		$name=$1;
		if (defined $2) { %{$Layouts{$name}}=%{$Layouts{$2}}; }
		else { $Layouts{$name}=undef; }
	}
	else {return}
	for (@$lines)
	{	s#_\"([^"]+)"#'"'._($1).'"'#ge;	#translation, escaping the " so it is not picked up as a translatable string
		next unless m/^(\w+)\s*=\s*(.*)$/;
		if ($2 eq '') {delete $Layouts{$name}{$1};next}
		$Layouts{$name}{$1}= $2;
	}
}

sub ParseSongTreeSkin
{	my $lines=$_[0];
	my $first=shift @$lines;
	my $ref;
	if ($first=~m#{(Column|Group) (.*)}#)
	{	$ref= $1 eq 'Column' ? \%SongTree::STC : \%SongTree::GroupSkin;
		$ref=$ref->{$2}={};
	}
	else {return}
	for (@$lines)
	{	my ($key,$e,$string)= m#^(\w+)\s*([=:])\s*(.*)$#;
		next unless defined $key;
		if ($e eq '=') {$ref->{$key}=$string unless $key eq 'elems' || $key eq 'options'}
		elsif ($string=~m#^Option(\w*)\((.+)\)$#)
		{	my $type=$1;
			my $opt=::ParseOptions($2);
			$opt->{type}=$type;
			$ref->{options}{$key}=$opt;
		}
		else { push @{$ref->{elems}}, $key.'='.$string; }
	}
}

sub SaveOptions		#Save options for this layout by collecting options of its widgets
{	my ($self,@states)=@_;
	#warn "saving ".$self->{layout}." layout options\n";

	for my $key (keys %{ $self->{widgets} })
	{	my $w=$self->{widgets}{$key};
		my $opt=$w->{SaveOptions};
		if ($opt)
		{	$opt=$opt->($w) if ref $opt;
		}
		elsif ( my $optkeys=$w->{'ref'}{options} )
		{	$opt= { map { $_=>$w->{$_} } grep defined $w->{$_}, split / /,$optkeys };
		}
		if (ref $opt)	#array or hash => to string
		{	$opt=+{@$opt} if ref $opt eq 'ARRAY';
			$opt=join ',',map $_.'='.$opt->{$_}, sort keys %$opt;
		}
		push @states,$key,$opt if defined $opt && $opt=~m#\S#;
	}
	warn "Options of $self->{layout} = @states\n" if $::debug;
	return $::Options{'Layout_'.$self->{layout}}=join ' ',@states;
}

sub Pack
{	my ($self,$layout,$opt2)=@_;
	$self->{layout}=$layout;
	$self->set_name($layout);

	my $boxes=$Layouts{$layout};
	$self->{KeyBindings}=::make_keybindingshash($boxes->{KeyBindings}) if $boxes->{KeyBindings};
	my $widgets=$self->{widgets}={};

	for (qw/SkinPath SkinFile DefaultFont Window/)
	{	$self->{layout_options}{$_}=$boxes->{$_} if exists $boxes->{$_};
	}
	my $border_width=2; #default border width
	if (my $wopt=$self->{layout_options}{Window})
	{	$border_width=$1 if $wopt=~m/\bborderwidth=(\d+)\b/;
		$self->set_skip_pager_hint(1) && $self->set_skip_taskbar_hint(1) if $wopt=~m/\bskip=1\b/;
	}
	$self->set_border_width($border_width);


	# create boxes
	my @boxlist;
	for my $key (keys %$boxes)
	{	my $type=substr $key,0,2;
		$type=$Layout::Boxes::Boxes{$type};
		next unless $type;
		my $line=$boxes->{$key};
		my $opt1;
		if ($line=~m#^\(#)
		{	$opt1=::ExtractNameAndOptions($line);
			$line=~s#^\s+##;
			$opt1=~s#^\(##; $opt1=~s/\)$//;
			$opt1= ::ParseOptions($opt1);
		}
		my $box=$widgets->{$key}= $type->{New}( $opt1,$opt2->{$key} );
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
		my @names= $type->{Parse}?	$type->{Parse}( $box, $line )
					 :	::ExtractNameAndOptions($line,$type->{Prefix});
		for my $name (@names)
		{	my @packoptions;
			($name,@packoptions)=@$name if ref $name;
			my $opt1;
			$opt1=$1 if $name=~s/\((.*)\)$//; #remove (...) and put it in $extra
			my $wg=$widgets->{$name} ||= $self->NewObject($name,$opt1,$opt2->{$name});
			unless ($wg) { delete $widgets->{$name}; next; }
			if ($wg->parent) {warn "layout error: $name already has a parent -> can't put it in $key\n"; next;}

			#$self->{'songlist'.$wg->{group}}=$wg if $wg->isa('SongList') || $wg->isa('SongTree');
			$type->{Pack}( $box,$wg,@packoptions );
		}
	}

	for my $key (grep m/^[HV]Size/, keys %$boxes)
	{	my $mode= ($key=~m/^V/)? 'vertical' : 'horizontal';
		my @names=split /\s+/,$boxes->{$key};
		if ( $names[0]=~m/^\d+$/ )
		{	my $s=shift @names;
			my @req=($mode eq 'vertical')? (-1,$s) : ($s,-1);
			$widgets->{$_}->set_size_request(@req) for @names;
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
	$self->signal_connect_after(key_press_event => \&KeyPressed);

	my @noparentboxes=grep m/^(?:[HVM][BP]|[ETFS]B|FR|AB)/ && !$widgets->{$_}->parent, keys %$boxes;
	if	(@noparentboxes==0) {warn "layout empty\n" if $::debug; return;}
	elsif	(@noparentboxes!=1) {warn "layout error: (@noparentboxes) have no parent -> can't find toplevel box\n"}
	$self->add( $widgets->{ $noparentboxes[0] } );

	if (my $name=$boxes->{DefaultFocus})
	{	$self->SetFocusOn($name);
	}

	if (my $line=$boxes->{ExtraWidgets})
	{	my @l=split /\s+/,$line;
		while (@l>1)
		{	my $type=shift @l;
			my $key=shift @l;
			my $opt;
			$opt=::ParseOptions($1) if $key=~s#\((.*)\)$##;
			my $packsub=$Layout::Boxes::Boxes{substr $key,0,2}{Pack};
			my $box=$widgets->{$key};
			next unless $box;
			ExtraWidgets::SetupContainer($box,$type,$packsub,$opt);
		}
	}

}

sub Parse_opt1_2
{	my ($opt,$oldopt)=@_;
	my %opt;
	if (defined $opt)
	{	if ($oldopt && $opt!~m/=/)
		{	if (ref $oldopt) { %opt= $oldopt->($opt); }
			else { @opt{split / /,$oldopt}=split ',',$opt; }
		}
		else
		{	#%opt= $opt=~m/(\w+)=([^,]*)(?:,|$)/g;
			return ::ParseOptions($opt);
		}
	}
	return \%opt;
}

sub NewObject
{	my ($self,$name,$opt1,$opt2)=@_;
	my $namefull=$name;
	$name=~s/\d+$//;
	my $import;
	#$import=$1 if $name=~s/^(\w+):://;
	my $ref=$objects{$name};
	unless ($ref) { warn "layout error : unknown object '$name'\n"; return undef; }
	#warn $name;
	$opt1=Parse_opt1_2($opt1,$ref->{oldopt1});
	$opt2=Parse_opt1_2($opt2,$ref->{oldopt2});
	my $group= $opt1->{group} || $ref->{default_group} || '';
	$group= $self->{group}."_$group" unless $group=~m/^[A-Z]/;	#group local to window unless it begins with uppercase
	$opt1->{group}=$group;
	my $widget= $ref->{class}
		? $ref->{class}->new($opt1,$opt2,$ref, $self->{layout_options})
		: $ref->{New}($opt1,$opt2);
	if ($ref->{options})
	{	for my $key (split / /,$ref->{options})
		{	$widget->{$key}= (exists $opt2->{$key}) ?
					$opt2->{$key} : $opt1->{$key};
		}
	}
	$widget->{group}=$group;
	$widget->{'ref'}=$ref;
	$widget->{name}=$namefull;
	$widget->set_name($name);

	$widget->{actions}{$_}=$ref->{$_}  for grep m/^click/, keys %$ref;
	$widget->{actions}{$_}=$opt1->{$_} for grep m/^click/, keys %$opt1;
	$widget->signal_connect(button_press_event => \&Button_press_cb) if $widget->{actions};
	if ($widget->isa('Gtk2::Button') and my $activate= ($opt1->{activate} || $ref->{activate}))
	{	$widget->{actions}{activate}=$activate;
		$widget->signal_connect(clicked => \&Button_activate_cb);
	}
	if (my $cursor= ($opt1->{cursor}||$ref->{cursor}))
	{	$widget->signal_connect(realize => sub { $_[0]->window->set_cursor(Gtk2::Gdk::Cursor->new($_[1])); },$cursor);
	}

	my %towatch;
	my $tip= $ref->{tip};
	$tip= $opt1->{tip} if exists $opt1->{tip} && (!$tip || !ref $tip);
	if ( defined $tip && !ref $tip)
	{	my @fields=::UsedFields($tip);
		$towatch{$_}=undef for @fields;
		if (@fields) { $widget->{tip}=$tip; }
		else
		{	$tip=~s#\\n#\n#g;
			$::Tooltips->set_tip( $widget, $tip );
		}
	}
	if ($opt1->{hover_layout}) { $widget->{$_}=$opt1->{$_} for qw/hover_layout hover_delay/; Layout::Window::Popup::set_hover($widget); }
	if (my $f=$ref->{fields})
	{	$towatch{$_}=undef for split / /,$f;
	}
	if ($widget->{markup})
	{	$towatch{$_}=undef for ::UsedFields($widget->{markup});
	}
	if ($ref->{schange} || (keys %towatch))
	{	::WatchSelID($widget,\&UpdateSongID,\%towatch);
		UpdateSongID($widget,::GetSelID($widget));
	}
	if ($ref->{event})
	{	my $sub=$ref->{update} || \&UpdateObject;
		::Watch($widget,$_,$sub ) for split / /,$ref->{event};
		$sub->($widget) unless $ref->{noinit};
	}
	::set_drag($widget,source => $ref->{dragsrc}, dest => $ref->{dragdest});
	return $widget;
}

sub UpdateObject
{	my $widget=$_[0];
	my $ref=$widget->{'ref'};
	if ( my $tip=$ref->{tip} )
	{	$tip=&$tip if ref $tip;
		$::Tooltips->set_tip($widget,$tip);
	}
	if ($widget->{skin}) {$widget->queue_draw}
	elsif ($widget->{stock}) { $widget->UpdateStock }
}

sub Button_press_cb
{	(my $self,$::LEvent)=@_;
	my $actions=$self->{actions};
	my $key='click'.$::LEvent->button;
	my $sub=$actions->{$key};
	return 0 if !$sub && $actions->{activate};
	$sub||=$actions->{click1};
	return 0 unless $sub;
	if (ref $sub)	{&$sub}
	else		{ ::run_command($self,$sub) }
	1;
}
sub Button_activate_cb
{	my $self=$_[0];
	my $sub=$self->{actions}{activate};
	return 0 unless $sub;
	if (ref $sub)	{&$sub}
	else		{ ::run_command($self,$sub) }
	1;
}

sub UpdateSongID
{	my ($widget,$ID)=@_;
	for my $w ($widget)
	{	$w->{ref}{schange}($w,$ID) if $w->{ref} && $w->{ref}{schange};
		if ($w->{markup})
		{	if (defined $ID) { $w->set_markup(::ReplaceFieldsAndEsc( $ID,$w->{markup} )); }
			elsif ($w->{markup_empty}) { $w->set_markup($w->{markup_empty}); }
			else { $w->set_markup(''); }
		}
		if ($w->{tip})
		{	my $tip= defined $ID ? ::ReplaceFields($ID,$w->{tip}) : '';
			$::Tooltips->set_tip($w,$tip);
		}
	}
}

#sub SetSort
#{	my($self,$sort)=@_;
#	$self->{songlist}->Sort($sort);
#}

sub ShowHide
{	my ($self,$names,$resize)=@_;
	if (grep $_ && $_->visible, map $self->{widgets}{$_}, split /\|/,$names)
	{ &Hide	} else { &Show } #keep @_
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
	my $win=$_[0]->get_toplevel;
	if ($win->{fullscreen}) {$win->unfullscreen}
	else {$win->fullscreen} }

sub KeyPressed
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	my $mod;
	$mod.='c' if $event->state >= 'control-mask';
	$mod.='a' if $event->state >= 'mod1-mask';
	$mod.='w' if $event->state >= 'mod4-mask';
	$mod.='s' if $event->state >= 'shift-mask';
	$key=$mod.'-'.$key if $mod;
	my ($cmd,$arg);
	if ( exists $::CustomBoundKeys{$key} )
	{	$cmd= $::CustomBoundKeys{$key};
	}
	elsif ($self->{KeyBindings} && exists $self->{KeyBindings}{$key} )
	{	$cmd= $self->{KeyBindings}{$key};
	}
	if ( exists $::GlobalBoundKeys{$key} )
	{	$cmd= $::GlobalBoundKeys{$key};
	}
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

#################################################################################

sub RemoveFilter
{	::Select(filter => '') if defined $::ListMode || !$::SelectedFilter->is_empty;
}

sub PlayOrderComboNew
{	my $opt1=$_[0];
	my $store=Gtk2::ListStore->new(('Glib::String')x3);
	my $combo=Gtk2::ComboBox->new($store);
	$combo->set_size_request($opt1->{reqwidth}||100,-1);
	my $cell=Gtk2::CellRendererPixbuf->new;
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
	{	$store->set($iter=$store->append, 0, _"list order", 1,'',2,'gmb-list');
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
{	my $return=0;
	$return=1 unless @_;
	my $check=$::Options{Sort};
	my $found;
	my $callback=sub { ::Select('sort' => $_[1]); };
	my $append=sub
	 {	my ($menu,$name,$sort,$true,$cb)=@_;
		$cb||=$callback;
		$true=($sort eq $check) unless defined $true;
		my $item = Gtk2::CheckMenuItem->new($name);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if $true;
		$item->signal_connect (activate => $cb, $sort );
		$menu->append($item);
	 };
	my $menu = Gtk2::Menu->new;

	my $submenu= Gtk2::Menu->new;
	my $sitem = Gtk2::MenuItem->new(_"Weighted Random");
	for my $name (sort keys %{$::Options{SavedWRandoms}})
	{	$append->($submenu,$name, $::Options{SavedWRandoms}{$name} );
	}
	my $editcheck=(!$found && $check=~m/^random:/);
	$append->($submenu,_"Edit ...", undef, $editcheck, sub
		{	::EditWeightedRandom(undef,$::Options{Sort},undef, \&::Select_sort);
		});
	$sitem->set_submenu($submenu);
	$menu->prepend($sitem);

	$append->($menu,_"Shuffle",'shuffle',undef,\&::Shuffle);

	{ my $item=Gtk2::CheckMenuItem->new(_"Repeat");
	  $item->set_active($::Options{Repeat});
	  $item->set_sensitive(0) if $::RandomMode;
	  $item->signal_connect(activate => sub { ::SetRepeat($_[0]->get_active); } );
	  $menu->append($item);
	}

	$menu->append(Gtk2::SeparatorMenuItem->new); #separator between random and non-random modes

	$append->($menu,_"list order", '' ) if defined $::ListMode;
	for my $name (sort keys %{$::Options{SavedSorts}})
	{	$append->($menu,$name, $::Options{SavedSorts}{$name} );
	}
	$append->($menu,_"Edit...",undef,!$found,sub
		{	::EditSortOrder(undef,$::Options{Sort},undef, \&::Select_sort );
		});
	$menu->show_all;
	return $menu if $return;
	$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button,$::LEvent->time);
}

sub FilterMenu
{	my $return=0;
	$return=1 unless @_;
	my $check;
	$check=$::SelectedFilter->{string} if $::SelectedFilter;
	my $menu = Gtk2::Menu->new;
	my $item_callback=sub { ::Select(filter => $_[1]); };
	for my $list (sort keys %{$::Options{SavedFilters}})
	{	next if $list eq 'Playlist';
		my $filt=$::Options{SavedFilters}{$list}->{string};
		my $text=$list; $text=~s/^_//;
		my $item = Gtk2::CheckMenuItem->new($text);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if defined $check && $filt eq $check;
		$item->signal_connect ( activate =>  $item_callback ,$filt );
		if ($list eq 'Library') {$menu->prepend($item);}
		else			{$menu->append($item);}
	}
	my $item=Gtk2::CheckMenuItem->new(_"Edit...");
	$item->set_draw_as_radio(1);
	$item->signal_connect ( activate => sub
		{ ::EditFilter(undef,$::SelectedFilter,undef, sub {::Select(filter => $_[0])});
		});
	$menu->append($item);
	if (my @SavedLists=::GetListOfSavedLists())
	{	my $submenu=Gtk2::Menu->new;
		my $list_cb=sub { ::Select( 'sort' => '', staticlist => $_[1] ) };
		for my $list (@SavedLists)
		{	my $item = Gtk2::CheckMenuItem->new($list);
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
	$menu->show_all;
	return $menu if $return;
	$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button,$::LEvent->time);
}

sub VisualsMenu
{	my $menu=Gtk2::Menu->new;
	my $cb=sub { Play_GST::set_visual($_[1]); };
	my @l=Play_GST::list_visuals();
	my $current=$::Options{gst_visual}||$l[0];
	for my $v (@l)
	{	my $item=Gtk2::CheckMenuItem->new($v);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $current eq $v;
		$item->signal_connect (activate => $cb,$v);
		$menu->append($item);
	}
	$menu->show_all;
	$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button,$::LEvent->time);
}

sub NewMenuBar
{	my $self=Gtk2::MenuBar->new;
	$self->signal_connect( button_press_event => sub
	 {	return 0 if $_[0]{busy};
		$_[0]{busy}=1;
		for my $item ($_[0]->get_children)
		{	my $ref=$item->{'ref'};
			next unless $ref->{setmenu};
			my $submenu= $ref->{setmenu}($item);
			$item->set_submenu($submenu);
			$submenu->show_all;
		};
		0;
	 });
	$self->signal_connect( selection_done => sub { $_[0]{busy}=undef; });

	return $self;
}

sub UpdateLabelsIcon
{	my $table=$_[0];
	$table->remove($_) for $table->get_children;
	return unless defined $::SongID;
	my $row=0; my $col=0;
	my $count=0;
	for my $stock ( Songs::Get_icon_list('label',$::SongID) )
	{	my $img=Gtk2::Image->new_from_stock($stock,'menu');
		$count++;
		$table->attach($img,$col,$col+1,$row,$row+1,'shrink','shrink',1,1);
		if (++$row>=1) {$row=0; $col++}
	}
	$table->show_all;
}

sub AddLabelEntry	#create entry to add a label to the current song
{	my $entry=Gtk2::Entry->new;
	$::Tooltips->set_tip($entry,_"Adds labels to the current song");
	$entry->signal_connect(activate => sub
	 {	my $label= $_[0]->get_text;
		return unless defined $::SongID & defined $label;
		$_[0]->set_text('');
		::SetLabels([$::SongID],[$label],[]);
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
	::ChooseSongsFromA($aid);
}

####################################
package Layout::Window;
use Gtk2;
our @ISA;
BEGIN {push @ISA,'Layout';}
use base 'Gtk2::Window';

my $WindowCounter=0;	#used to give an unique group id to windows

sub new
{	my ($class,$layout,$wintype,$options,$fallback)=@_;
	$fallback||='Small player';
	$wintype||='toplevel';
	my $self=bless Gtk2::Window->new($wintype), $class;
	$self->set_role($layout);
	$self->{options}=$options;
	$self->{group}='w'.$WindowCounter++;
	::Watch($self,Save=>\&SaveOptions);
	$self->set_title(::PROGRAM_NAME);
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
	unless (exists $Layout::Layouts{$layout})
	{	warn "Layout '$layout' not found, using '$fallback' instead\n";
		$layout=$fallback; #FIXME if not a player window
		$Layout::Layouts{$layout} ||= { VBmain=>'Label(text="Error : fallback layout not found")' };	#create an error layout if fallback not found
	}
	my $opt2;
	{	my $options= $::Options{'Layout_'.$layout} || $Layout::Layouts{$layout}{Default} || '';
		my @optlist=split /\s+/,$options;
		my $wopt;
		$wopt=shift @optlist if @optlist%2;	#old format (v<0.9573)
		$opt2= {@optlist};
		$opt2->{Window}||=$wopt||'';
	}
	$self->Pack($layout,$opt2);
	$self->SetWindowOptions($opt2->{Window});
	if (my $skin=$Layout::Layouts{$layout}{Skin}) { $self->set_background_skin($skin) }
	#if (my $songlist=::GetSonglist($self))	#FIXME should be done for every new group
	#{	::SetFilter($self,undef,0) unless $songlist->{type}=~m/[QL]/;
	#	$songlist->FollowSong;
	#}
	$self->init;
	::HasChanged('HiddenWidgets');
	#$self->set_opacity($self->{opacity}) if exists $self->{opacity} && $self->{opacity}!=1;
	return $self;
}
sub init
{	my $self=$_[0];
	#$self->set_position();#doesn't work before show, at least with sawfish
	$self->move($self->{x},$self->{y}) if defined $self->{x};
		my @hidden;
		@hidden=keys %{ $self->{hidden} } if $self->{hidden};
		my $widgets=$self->{widgets};
		push @hidden,$widgets->{$_}{need_hide} for grep $widgets->{$_}{need_hide}, keys %$widgets;
		@hidden=map $widgets->{$_}, @hidden;
		$_->show_all for @hidden;
		$_->hide for @hidden;
		@hidden=grep !$_->get_no_show_all, @hidden;
		$_->set_no_show_all(1) for @hidden;
		$self->show_all;
		$_->set_no_show_all(0) for @hidden;
#	if (my $h=$self->{hidden}) #restore hidden states
#	 { $self->{widgets}{$_}->hide for keys %$h; }
	$self->move($self->{x},$self->{y}) if defined $self->{x};
	$self->parse_geometry( delete $::CmdLine{geometry} ) if $::CmdLine{geometry};
}

sub set_background_skin
{	my ($self,$skin)=@_;
	my ($file,$crop,$resize)=split /:/,$skin;
	#$self->set_decorated(0);
	$self->{pixbuf}=Skin::_load_skinfile($file,$crop,$self->{layout_options});
	return unless $self->{pixbuf};
	$self->{resizeparam}=$resize;
	$self->{skinsize}='0x0';
	$self->signal_connect(style_set => sub {warn "style set : @_" if $::debug;$_[0]->set_style($_[2]);} ,$self->get_style); #FIXME find the cause of these signals, seems related to stock icons
	$self->signal_connect(configure_event => \&resize_skin_cb);
	#Gtk2::Gdk::Window->set_debug_updates(1);
	#$self->queue_draw;
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
{	my ($self,$event)=@_;
	my ($w,$h)=($event->width,$event->height);
	return 0 if $w.'x'.$h eq $self->{skinsize};
#	::IdleDo('0_resize_back_skin'.$self,1000,sub {
#Glib::Timeout->add(80,sub {
#	warn 1; my $self=$_[0];my ($w,$h)=$self->window->get_size;
	my $pb=Skin::_resize($self->{pixbuf},$self->{resizeparam},$w,$h);
	return 0 unless $pb;
	#my ($pixmap,$mask)=$pb->render_pixmap_and_mask(1); #leaks X memory for Gtk2 <1.146 or <1.153
	my $mask=Gtk2::Gdk::Bitmap->create_from_data($self->window,'',$w,$h);
	$pb->render_threshold_alpha($mask,0,0,0,0,-1,-1,1);
	$self->shape_combine_mask($mask,0,0);
	my $pixmap=Gtk2::Gdk::Pixmap->new($self->window,$w,$h,-1);
	$pb->render_to_drawable($pixmap, Gtk2::Gdk::GC->new($self->window), 0,0,0,0,-1,-1,'none',0,0);
	$self->window->set_back_pixmap($pixmap,0);
	$self->{skinsize}=$w.'x'.$h;
	$self->queue_draw;
#0;
#	},$self) if $self->{skinsize};
#$self->{skinsize}='';
	return 0;
}

sub layout_name
{	my $self=shift;
	my $id=$self->{layout};
	return $Layout::Layouts{$id}{Name} || $id;
}
sub close_window
{	my $self=shift;
	$self->SaveOptions;
	unless ($self == $::MainWindow) { $_->destroy for values %{$self->{widgets}}; $self->destroy; return }
	if ($::Options{UseTray} && $::Options{CloseToTray}) { &::ShowHide; return 1}
	else { &::Quit }
}

sub SaveOptions
{	my $self=$_[0];
	Layout::SaveOptions($self, $self->SaveWindowOptions );
}
sub SaveWindowOptions
{	my $self=$_[0];
	my %wstate;
	$wstate{size}=join 'x',$self->get_size;
	#unless ($self->{options} && $self->{options} eq 'DoNotSaveState')
	{	$wstate{pos}=join 'x',$self->get_position;
		$wstate{sticky}=1 if $self->{sticky};
		$wstate{fullscreen}=1 if $self->{fullscreen};
		$wstate{ontop}=1 if $self->{ontop};
		$wstate{below}=1 if $self->{below};
		$wstate{nodecoration}=1 unless $self->get_decorated;
		$wstate{skippager}=1 if $self->get_skip_pager_hint;
		$wstate{skiptaskbar}=1 if $self->get_skip_taskbar_hint;
	}
	my $hidden=$self->{hidden};
	if ($hidden && keys %$hidden)
	{	$wstate{hidden}=join ':', %$hidden;
	}
	return Window=> (join ',',map $_.'='.$wstate{$_}, keys %wstate);
}
sub SetWindowOptions
{	my ($self,$wopt)=@_;
	my $layouthash= $Layout::Layouts{ $self->{layout} };
	my ($x,$y,$width,$height,$sticky)=(-1,-1);
	if ($wopt=~m/=/)
	{	my %wstate= $wopt=~m/(\w+)=([^,]*)(?:,|$)/g;
		if ($self->{options} && $self->{options}=~m/UseDefaultState/)
		{	my %h= split /\s+/, ($layouthash->{Default}||'');
			$wopt= $h{Window}||'';
			#replace options by default
			my @state= ($wopt=~m/(\w+)=([^,]*)(?:,|$)/g);
			push @state, size=>$wstate{size} if $self->{options}=~m/KeepSize/;
			%wstate= @state;
		}
		($x,$y)=split 'x',$wstate{pos}  if $wstate{pos};
		($width,$height)=split 'x',$wstate{size} if $wstate{size};
		$sticky=1 if $wstate{sticky};
		$self->fullscreen, $width=$height=undef if $wstate{fullscreen};
		$self->set_keep_above(1) if $wstate{ontop};
		$self->set_keep_below(1) if $wstate{below};
		$self->set_decorated(0)  if $wstate{nodecoration};
		$self->set_skip_pager_hint(1) if $wstate{skippager};
		$self->set_skip_taskbar_hint(1) if $wstate{skiptaskbar};
		#$self->{opacity}=$wstate{opacity} if defined $wstate{opacity};
		$self->{hidden}={ $wstate{hidden}=~m/(\w+)(?::?(\d+x\d+))?/g } if $wstate{hidden};
	}
	else	#old format (v<0.9568)
	{	my @wopt=split /,/,$wopt;
		unshift @wopt,-1,-1 if @wopt<5;
		($x,$y,$width,$height,$sticky)=@wopt;
	}
	if ($width) { $self->resize($width,$height); }
	else { $self->{natural_size}=1; $self->signal_connect('map' => sub {delete $_[0]->{natural_size}}); }
	$self->stick if $sticky;
	$self->set_gravity($layouthash->{gravity}) if $layouthash->{gravity};
	if (my $scrn=Gtk2::Gdk::Screen->get_default)
	 {$x=-1 if $x>$scrn->get_width || $y>$scrn->get_height}
	if ($x>-1 && $y>-1)
	{ $self->move($x,$y);
	  $self->{x}=$x; $self->{y}=$y;	#move before show_all rarely works, so save pos to set it later
	}
	my $title=$layouthash->{Title} || _"%S by %a";
	$title=~s/^"(.*)"$/$1/;
	if (my @l=::UsedFields($title))
	{	$self->{TitleString}=$title;
		my %fields; $fields{$_}=undef for @l;
		::Watch($self,'SongID',\&UpdateWindowTitle,\%fields);
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

package Layout::Window::Popup;
use Gtk2;
our @ISA;
BEGIN {push @ISA,'Layout','Layout::Window';}

sub new
{	my ($class,$layout,$widget)=@_;
	$layout||=$::Options{LayoutT};
	my $self=Layout::Window::new($class,$layout,'popup','UseDefaultState','info');	#'info' is the fallback layout

	if ($widget)
	{	$self->{popped_from}=$widget;
		$self->set_screen($widget->get_screen);
		#$self->set_transient_for($widget->get_toplevel);
		$self->move( ::windowpos($self,$widget) );
		$self->signal_connect(enter_notify_event => \&CancelDestroy);
	}
	else	{ $self->set_position('mouse'); }
	$self->show;
	#$self->set_opacity($self->{opacity}) if exists $self->{opacity} && $self->{opacity}!=1;

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
	$frame->set_shadow_type('out');
	$self->set_border_width(0);
	$child->set_border_width(5);

		##$self->set_type_hint('tooltip'); #TEST
		##$self->set_type_hint('notification'); #TEST
		#$self->set_focus_on_map(0);
		#$self->set_accept_focus(0); #?
	$self->child->show_all;		#needed to get the true size of the window
	$self->child->realize;		#
	$self->signal_connect(leave_notify_event => sub
		{ $_[0]->StartDestroy if $_[1]->detail ne 'inferior';0; });
}

sub Popup
{	my ($widget,$addtimeout)=@_;
	my $self= find_window($widget);
	$addtimeout=0 if $self && !$self->{destroy_timeout}; #don't add timeout if there wasn't already one
	$self ||= Layout::Window::Popup->new($widget->{hover_layout},$widget);
	return 0 unless $self;
	$self->CancelDestroy;
	$self->{destroy_timeout}=Glib::Timeout->add( $addtimeout,\&DestroyNow,$self) if $addtimeout;
	0;
}

sub set_hover
{	my $widget=$_[0];
	#$widget->add_events([qw/enter-notify-mask leave-notify-mask/]);
	$widget->signal_connect(enter_notify_event =>
	    sub	{ if (!find_window($widget))
		  {	my $delay=$widget->{hover_delay}||1000;
			$widget->{hover_timeout}||= Glib::Timeout->add($delay,\&Popup,$widget);
		  }
		  else {Popup($widget)}
		  0;
		});
	$widget->signal_connect(leave_notify_event => \&CancelPopup );
}
sub find_window
{	my $widget=shift;
	my ($self)=grep $_->{popped_from} && $_->{popped_from}==$widget, Gtk2::Window->list_toplevels;
	return $self;
}

sub CancelPopup
{	my $widget=shift;
	if (my $t=delete $widget->{hover_timeout}) { Glib::Source->remove($t); }
	if (my $self=find_window($widget)) { $self->StartDestroy }
}
sub CancelDestroy
{	my $self=shift;
	if (my $t=delete $self->{destroy_timeout}) { Glib::Source->remove($t); }
}
sub StartDestroy
{	my $self=shift;
	return 0 if !$self || $self->{destroy_timeout};
	$self->{destroy_timeout}=Glib::Timeout->add( 300,\&DestroyNow,$self);
	0;
}
sub DestroyNow
{	my $self=shift;
	$self->CancelDestroy;
	$self->destroy;
	0;
}

=needsCairo
package Layout::Window::OSD;	#TEST not used yet 	#Layout::Window::OSD->new()
use Gtk2;
our @ISA;
BEGIN {push @ISA,'Layout','Layout::Window';}

sub new
{	my ($class,$layout)=@_;
	$layout||=$::Options{LayoutT};
	my $self=Layout::Window::new($class,$layout,'popup','UseDefaultState');
	$self->move( position($self) );
	$self->show;
	Glib::Timeout->add( 5000,sub {$self->destroy;0} );
	return $self;
}
sub init
{	my $self=$_[0];
	if (1)
	{	my @children=($self);
		while (my $widget=shift @children)
		{	push @children, $widget->get_children if $widget->isa('Gtk2::Container');
			unless ($widget->no_window)
			{	$widget->set_colormap($widget->get_screen->get_rgba_colormap);
				$widget->set_app_paintable(1);
				$widget->signal_connect(expose_event => \&transparent_expose_cb);
			}
		}
	}
	if (0)	#failed attempt at making it input-invisible
	{	my @children=($self);
		while (my $widget=shift @children)
		{	push @children, $widget->get_children if $widget->isa('Gtk2::Container');
			unless ($widget->no_window)
			{	$widget->realize;
				$widget->window->set_events(['exposure-mask']);
			}
		}
	}

	$self->child->show_all;		#needed to get the true size of the window
	$self->child->realize;		#
	if (1)	#make the window input-invisible
	{	$self->realize;
		my $mask=Gtk2::Gdk::Bitmap->create_from_data(undef,'',1,1);
		$self->input_shape_combine_mask($mask,0,0);
	}
}
sub transparent_expose_cb
{	my ($w,$event)=@_;
	use Cairo;
	my $cr=Gtk2::Gdk::Cairo::Context->create($event->window);
	$cr->set_operator('source');
	$cr->set_source_rgba(0, 0, 0, 0);
	$cr->rectangle($event->area);
	$cr->fill;
	return 0; #send expose to children
}

sub position	#FIXME improve
{	my ($win)=@_;
	my $h=$win->size_request->height;		# height of window to position
	my $w=$win->size_request->width;		# width of window to position
	my $screen=$win->get_screen;
	my $monitor=$screen->get_monitor_at_window($win->window);
	my ($xmin,$ymin,$monitorwidth,$monitorheight)=$screen->get_monitor_geometry($monitor)->values;
	my $xmax=$xmin + $monitorwidth;
	my $ymax=$ymin + $monitorheight;
	my $x=$xmin + $monitorwidth/2;
	my $y=$ymin + $monitorheight;

	my $ycenter=0;
	if ($x+$w/2 < $xmax && $x-$w/2 >$xmin){ $x-=int($w/2); }	# centered
	elsif ($x+$w > $xmax)	{ $x=$xmax-$w; $x=$xmin if $x<$xmin }	# right side
	else				{ $x=$xmin; }				# left side
	if ($ycenter && $y+$h/2 < $ymax && $y-$h/2 >$ymin){ $y-=int($h/2) }	# y center
	elsif ($y+$h > $ymax)  { $y-=$h; $y=$ymin if $y<$ymin }	# display above the widget
	#else			   { $y+=0; }				# display below the widget
	return $x,$y;
}
=cut

package Layout::Boxes;
use Gtk2;

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
	{	New	=> sub { PanedNew('Gtk2::HPaned',$_[1]); },
		Prefix	=> qr/([_+]*)/,
		Pack	=> \&PanedPack,
	},
	VP	=>
	{	New	=> sub { PanedNew('Gtk2::VPaned',$_[1]); },
		Prefix	=> qr/([_+]*)/,
		Pack	=> \&PanedPack,
	},
	TB	=>	#tabbed
	{	New	=> \&NewTB,
		Prefix	=> qr/((?:"[^"]*[^\\]")|[^ ]*)\s+/,
		Pack	=> \&PackTB,
	},
	MB	=>
	{	New	=> \&Layout::NewMenuBar,
		Pack	=> sub { $_[0]->append($_[1]); },
	},
	SM	=>	#submenu
	{	New	=> sub { my $item=Gtk2::MenuItem->new($_[0]{label}); my $menu=Gtk2::Menu->new; $item->set_submenu($menu); return $item; },
		Pack	=> sub { $_[0]->get_submenu->append($_[1]); },
	},
	EB	=>
	{	New	=> sub { my $self=Gtk2::Expander->new($_[0]{label}); $self->set_expanded($_[0]); $self->{SaveOptions}=sub { $_[0]->get_expanded; }; return $self; },
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
	{	New	=> sub { my @def=(.5,.5,1,1); my @opt=@{$_[0]}{qw/xalign yalign xscale yscale/}; for my $i (0..3) {$opt[$i]=$def[$i] unless defined $opt[$i]}; Gtk2::Alignment->new(@opt);},
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
{	my ($opt1,$opt2)=@_;
	my $nb=Gtk2::Notebook->new;
	$nb->set_scrollable(::TRUE);
	$nb->popup_enable;
	#$nb->signal_connect( button_press_event => sub {return !::IsEventInNotebookTabs(@_);});
	if ($opt1->{tabpos}) {$nb->set_tab_pos($opt1->{tabpos});}
	if ($opt2 && $opt2=~m/page=(\d+)/) { $nb->{SetPage}=$1; }
	$nb->{SaveOptions}=sub { 'page='.$_[0]->get_current_page };
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
	my $pane=$class->new;
	($pane->{pos1},$pane->{pos2})=split /_/,$opt if $opt;
	$pane->set_position($pane->{pos1}) if defined $pane->{pos1};
	$pane->{SaveOptions}=sub { $_[0]{pos1}.'_'.$_[0]{pos2} };
	$pane->signal_connect(size_allocate => \&Paned_size_cb ); #needed to correctly behave when a child is hidden
	return $pane;
}

sub Paned_size_cb
{	my ($self,$alloc)=@_;
	$alloc=$self->isa('Gtk2::VPaned')? $alloc->height : $alloc->width;
	if (defined $self->{pos1} && defined $self->{pos2} && $alloc != ($self->{pos1} + $self->{pos2}))
	{	if    ($self->child1_resize && !$self->child2_resize)	{ $self->{pos1}=$alloc-$self->{pos2}; }
		elsif ($self->child2_resize && !$self->child1_resize)	{ $self->{pos2}=$alloc-$self->{pos1}; }
		else { my $diff=($alloc-$self->{pos1}-$self->{pos2}); $self->{pos1}+=$diff/2; $self->{pos2}+=$diff/2; }
		$self->set_position( $self->{pos1} );
	}
	else { $self->{pos1}=$self->get_position; $self->{pos2}=$alloc-$self->{pos1}; }
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
use Gtk2;
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

package Layout::Button;
use Gtk2;
use base 'Gtk2::Button';

sub new
{	my ($class,$opt1,undef,$ref,$layout_options)=@_;
	my $self = bless Gtk2::Button->new, $class;
	$self->{opt1}=$opt1;
	my $isbutton= !exists $ref->{nobutton};
	$isbutton= $opt1->{button} if exists $opt1->{button};
	if ($isbutton)
	{	$self->set_relief( $opt1->{relief} || $ref->{relief} || 'none');
	}
	my $stock=$ref->{stock};
	if ($opt1->{stock} && !$ref->{state}) #FIXME support states
	{	$stock=[split /\s+/,$opt1->{stock}];
		$stock=$stock->[0] unless @$stock>1;
	}
	if ($opt1->{skin})
	{	my $skin=Skin->new($opt1->{skin},$self,$layout_options);
		$self->signal_connect(expose_event => \&Skin::draw,$skin);
		$self->set_app_paintable(1); #needed ?
		$self->{skin}=1;
		if (0 && $opt1->{shape}) #mess up button-press cb
		{	$self->{shape}=1;
			my $ebox=Gtk2::EventBox->new;
			$ebox->add($self);
			$self=$ebox;
		}
	}
	elsif ($stock)
	{	$self=bless Gtk2::EventBox->new, $class unless $isbutton;
		$self->{stock}=$stock;
		$self->{state}=$ref->{state} if $ref->{state};
		$self->{size}= $opt1->{size} || $ref->{size} || Layout::SIZE_BUTTONS;
		my $img=Gtk2::Image->new;
		$img->set_size_request(Gtk2::IconSize->lookup($self->{size})); #so that it always request the same size, even when no icon
		$self->add($img);
		$self->UpdateStock;
	}
	else { $self->set_label($ref->{label}||$opt1->{label}); }
	return $self;
}

sub UpdateStock
{	my ($self,undef,$index)=@_;
	my $stock=$self->{stock};
	if (my $state=$self->{state})
	{	$state=&$state;
		$stock = (ref $stock eq 'CODE')? $stock->($state) : $stock->{$state};
	}
	if (ref $stock)
	{	$stock= $stock->[ $index || 0 ];
		unless (exists $self->{hasenterleavecb})
		{	$self->{hasenterleavecb}=undef;
			$self->signal_connect(enter_notify_event => \&UpdateStock,1);
			$self->signal_connect(leave_notify_event => \&UpdateStock);
		}
	}
	$self->child->set_from_stock($stock,$self->{size});
	0;
}

package Layout::Label;
use Gtk2;

use constant
{	SPEED	=> 20,	#timeout in ms
	INCR	=> 1,	#scroll increment in pixel
};

use base 'Gtk2::EventBox';

sub new
{	my ($class,$opt1,undef,$ref,$layout_options)=@_;
	my $self = bless Gtk2::EventBox->new, $class;
	my $label=Gtk2::Label->new;
	my $xalign= exists $opt1->{xalign} ? $opt1->{xalign} : $ref->{xalign} || 0;
	my $yalign= exists $opt1->{yalign} ? $opt1->{yalign} : .5;
	$label->set_alignment($xalign,$yalign);

	my $markup= $opt1->{markup};
	$markup= $ref->{markup} unless defined $markup;
	$self->{markup}=$markup if defined $markup;
	$markup= $opt1->{markup_empty};
	$markup= $ref->{markup_empty} unless defined $markup;
	$self->{markup_empty}=$markup if defined $markup;

	my $font= $opt1->{font} || $layout_options->{DefaultFont} || $ref->{font};
	$label->modify_font(Gtk2::Pango::FontDescription->from_string($font)) if $font;
	$label->set_text($opt1->{text}) if exists $opt1->{text};
	$self->add($label);
#$self->signal_connect(enter_notify_event => sub {$_[0]->set_markup('<u>'.$_[0]->child->get_label.'</u>')});
#$self->signal_connect(leave_notify_event => sub {my $m=$_[0]->child->get_label; $m=~s#^<u>##;$m=~s#</u>$##; $_[0]->set_markup($m)});
	my $minsize= $opt1->{minsize} || $ref->{minsize};
	if ($minsize && $minsize=~m/^\d+p?$/)
	{	unless ($minsize=~s/p$//)
		{	my $lay=$label->create_pango_layout( 'X' x $minsize );
			$lay->set_font_description(Gtk2::Pango::FontDescription->from_string($font)) if $font;
			($minsize)=$lay->get_pixel_size;
		}
		$self->{expand_max}=1 if $opt1->{expand_max};
		$self->set_size_request($minsize,-1);
		$label->signal_connect(expose_event => \&expose_cb);
		$self->signal_connect(enter_notify_event => \&enter_leave_cb, INCR());
		$self->signal_connect(leave_notify_event => \&enter_leave_cb,-INCR());
	}
	elsif (defined $ref->{initsize})
	{	#$label->set_size_request($label->create_pango_layout( $ref->{initsize} )->get_pixel_size);
		my $lay=$label->create_pango_layout( $ref->{initsize} );
		$lay->set_font_description(Gtk2::Pango::FontDescription->from_string($font)) if $font;
		$label->set_size_request($lay->get_pixel_size);
		$self->{resize}=1;
	}

	return $self;
}

sub set_label
{	my $label=$_[0]->child; $label->set_label($_[1]); $label->{dx}=0;
	$_[0]->checksize;
}
sub set_markup
{	my $label=$_[0]->child; $label->set_markup($_[1]); $label->{dx}=0;
	$_[0]->checksize;
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
	elsif ($self->{expand_max})
	{	$self->{expand_max}= ($self->child->get_layout->get_pixel_size)[0]||1;
	}
}

sub enter_leave_cb
{	my ($self,$event,$inc)=@_;
	#$self->set_state($inc>0 ? 'selected' : 'normal');
	$self->{scrolltimeout}=Glib::Timeout->add(SPEED, \&Scroll,$self) unless $self->{scrolltimeout};
	$self->{scroll_inc}=$inc;
	0;
}
sub expose_cb #only for scrollable labels
{	my ($label,$event)=@_; #FIXME redraw only $event->area when possible ie : background is not a pixmap or label has not scrolled
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
	my $gc=$label->get_style->text_gc($label->state);
	my $pixmap=Gtk2::Gdk::Pixmap->new($label->window, $lw,$lh, -1);
	$pixmap->draw_drawable($gc, $label->window, $xoffset,$yoffset, $label->{dx},0,$aw,$ah);
	$pixmap->draw_layout($gc, 0,0, $layout);
	$label->window->draw_drawable($gc, $pixmap,$label->{dx},0, $xoffset,$yoffset,$aw,$ah);
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
	$self->{scrolltimeout}=0 if ($max<0) or ($dx==0 && $self->{scroll_inc}<0) or ($dx==$max && $self->{scroll_inc}>0);
	return $self->{scrolltimeout};
}

package Layout::Bar;
use Gtk2;
use base 'Gtk2::ProgressBar';

sub new
{	my ($class,$opt1,undef,$ref,$layout_options)=@_;
	my $self=bless Gtk2::ProgressBar->new, $class;
	$self->{left}=$self->{right}=0;
	$self->{max}= $ref->{max} || 1;
	my $orientation= $ref->{orientation} || 'left-to-right';
	$orientation= 'left-to-right' if $opt1->{horizontal};
	$orientation= 'bottom-to-top' if $opt1->{vertical};
	$self->set_orientation($orientation);
	$self=Layout::Bar::skin->new($opt1,$orientation,$layout_options) if $opt1->{skin};
	$self->add_events([qw/pointer-motion-mask button-press-mask button-release-mask scroll-mask/]);
	$self->signal_connect(button_press_event	=> \&button_press_cb);
	$self->signal_connect(button_release_event	=> \&button_release_cb);
	$self->signal_connect(scroll_event		=> \&scroll_cb);
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
	my @labels= map $h->{$_}, grep m/^LabelTime\d*$/, keys %$h; #get list of LabelTime in the layouts

	my $preview= defined $value ? 1 : 0;
	my $format=( $self->{max} <600 )? '%01d:%02d' : '%02d:%02d';
	for my $label (@labels)
	{	$label->{busy}=$preview;
		$label->set_label( sprintf $format,int($value/60),$value%60 ) if $preview;
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
use Gtk2;
our @ISA=('Layout::Bar');
use base 'Gtk2::EventBox';

sub new
{	my ($class,$opt1,$orientation,$layout_options)=@_; #FIXME $orientation is ignored for now
	my $self=bless Gtk2::EventBox->new,$class;
	my $hskin=$self->{handle_skin}=Skin->new($opt1->{handle_skin},undef,$layout_options);
	my $bskin=$self->{back_skin}=  Skin->new($opt1->{skin},undef,$layout_options);
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
	my $minw=$self->{handle_skin}{minwidth};
	my ($w,$h)=($self->allocation->values)[2,3];
	$w-= $self->{right}+$self->{left};
	my $x= $self->{left} + $w *$self->{fraction};
	$x-= $minw/2;
	Skin::draw($self,$event,$self->{handle_skin},int($x),$self->{top},$minw,$h-$self->{top}-$self->{bottom});
	1;
}

package Layout::Bar::Scale;
use Gtk2;
use base 'Gtk2::Scale';

sub new
{	my ($class,$opt1,undef,$ref)=@_;
	my $scale= $ref->{orientation} || 'left-to-right';
	$scale= 'left-to-right' if $opt1->{horizontal};
	$scale= 'bottom-to-top' if $opt1->{vertical};
	$scale= $scale eq 'left-to-right' ? 'Gtk2::HScale' : 'Gtk2::VScale';
	my $max= $ref->{max} || 1;
	my $self = bless $scale->new_with_range(0,$max,$max/10), $class;
	$self->set_inverted(1) if $scale eq 'Gtk2::VScale';
	$self->{vertical}= $scale eq 'Gtk2::VScale';
	$self->set_draw_value(0);
	$self->signal_connect(button_press_event => \&button_press_cb);
	$self->signal_connect(button_release_event => \&button_release_cb);
	$self->signal_connect(scroll_event	=> \&Layout::Bar::scroll_cb);
	$self->{scroll}=$ref->{scroll};
	$self->{set}=$ref->{set};
	$self->{set_preview}=$ref->{set_preview};
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
{	my $self=$_[0];
	$self->{pressed}= $self->signal_connect(value_changed  => \&value_changed_cb);
	0;
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

package Layout::AAPicture;
use Gtk2;

use base 'Gtk2::EventBox';

sub new
{	my ($class,$opt1)=@_;
	my $self = bless Gtk2::EventBox->new, $class;
	#$minsize||=$ref->{size};
	my $minsize=$opt1->{minsize};
	$self->{maxsize}=$opt1->{maxsize};
	$self->{maxsize}=500 unless defined $self->{maxsize};
	$self->{multiple}=$opt1->{multiple};
	if ($opt1->{forceratio}) { $self->{forceratio}=1; } #not sure it's still needed with the natural_size mode
	else
	{	$self->{expand_to_ratio}=1;
		$self->{expand_weight}=10;
	}
	$self->signal_connect(size_allocate => \&size_allocate_cb);
	$self->signal_connect(expose_event => \&expose_cb);
	$self->signal_connect(destroy => sub {delete $::ToDo{'8_LoadImg'.$_[0]}});
	$self->set_size_request($minsize,$minsize) if $minsize;
	$self->{key}=[];
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
	my $col=$self->{ref}{aa};
	my @files;
	for my $k (@$key)
	{	my $f=AAPicture::GetPicture($col,$k);
		push @files, $f if $f;
	}
	$self->{pixbuf}=undef;
	if (@files)
	{
	 if (@files>1 && !$self->{multiple}) {$#files=0}
	 $self->show;
	 $self->queue_draw;
	 ::IdleDo('8_LoadImg'.$self,500,sub
	 {	my ($self,@files)=@_;
		return if $self->{size} <10;
		my $size=int $self->{size}/@files;
		my @pix= grep $_, map ::PixBufFromFile($_,$size), @files;
		$self->{pixbuf}= @pix ? \@pix : undef;
		#$self->{pixbuf}=::PixBufFromFile($file,$self->{size});
		$self->queue_draw;
		$self->hide unless @pix;
	 },$self,@files);
	}
	else
	{	$self->hide unless $self->get_toplevel->{natural_size};
	}
	$self->signal_connect('map'=>sub #undo the temporary settings set in size_allocate_cb for the natural_size mode #FIXME should be simpler
	{	$self=$_[0];
		delete $self->{size} unless $self->{pixbuf} || $::ToDo{'8_LoadImg'.$self};
		$self->set_size_request(-1,-1) unless $self->{forceratio};
		$self->queue_resize;
	}) if $self->get_toplevel->{natural_size};
}

sub size_allocate_cb
{	my ($self,$alloc)=@_;
	my $max=$self->{maxsize};
	my $w=$alloc->width; my $h=$alloc->height;
	if ($self->get_toplevel->{natural_size})#set temporary settings for natural_size mode #FIXME should be simpler
	{	my $s= $w<$h ? $h : $w;
		$self->set_size_request($s,$s) if !defined $self->{size} || $s!=$self->{size};
		$self->{size}=$s;
		return;
	}

	my $s= ($self->{forceratio} xor $w<$h) ? $w : $h;

	$s=$max if $max && $s>$max;
	if (!defined $self->{size})
	{	unless ($self->{pixbuf} || $::ToDo{'8_LoadImg'.$self}) {$self->hide;return};
	}
	elsif ($self->{size}==$s) {return}
	$self->set_size_request($s,$s) if $self->{forceratio};
	$self->{size}=$s;
	$self->set(delete $self->{key});
	#::ScaleImage( $img, $s ) unless $::ToDo{'8_LoadImg'.$img};
}

sub expose_cb
{	my ($self,$event)=@_;
	my ($x,$y)=(0,0);
	my ($ww,$wh)=$self->window->get_size;
	my $pixbuf= $self->{pixbuf};
	return 1 unless $pixbuf;
	my $multiple= @$pixbuf>1 ? $self->{multiple} : undef;
	if ($multiple)
	{	if ($multiple eq 'h')	{$ww= int $ww/@$pixbuf}
		else			{$wh= int $wh/@$pixbuf}
	}
	for my $pix (@$pixbuf)
	{	my $w=$pix->get_width;
		my $h=$pix->get_height;
		my $dx= int ($ww-$w)/2;
		my $dy= int ($wh-$h)/2;
		my $gc=Gtk2::Gdk::GC->new($self->window);
		$gc->set_clip_rectangle($event->area);
		$self->window->draw_pixbuf($gc,$pix,0,0,$x+$dx,$y+$dy,-1,-1,'none',0,0);
		if ($multiple) {if ($multiple eq 'h') {$x+=$ww} else {$y+=$wh}}
	}
	1;
}


package Layout::TogButton;
use Gtk2;

use base 'Gtk2::ToggleButton';
sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self = bless Gtk2::ToggleButton->new, $class;
	my ($icon,$label);
	$label=Gtk2::Label->new($opt1->{label}) if defined $opt1->{label};
	$icon=Gtk2::Image->new_from_stock($opt1->{icon},'menu') if $opt1->{icon};
	my $child= ($label && $icon) ?	::Hpack($icon,$label) :
					$icon || $label;
	$self->add($child) if $child;
	#$self->{gravity}=$opt1{gravity};
	$self->{widget}=$opt1->{widget};
	$self->{resize}=$opt1->{resize};
	$self->signal_connect( toggled => \&toggled_cb );
	::Watch($self,'HiddenWidgets',\&UpdateToggleState);

	return $self;
}

sub UpdateToggleState
{	my $self=$_[0];
	return unless $self->{widget};
	my $layw=::get_layout_widget($self);
	return unless $layw;
	my $state=$layw->GetShowHideState($self->{widget});
	$self->{busy}=1;
	$self->set_active($state);
	delete $self->{busy};
}

sub toggled_cb
{	my $self=$_[0];
	return if $self->{busy} || !$self->{widget};
	my $layw=::get_layout_widget($self);
	return unless $layw;
	if ($self->get_active)	{ $layw->Show($self->{widget},$self->{resize}) }
	else			{ $layw->Hide($self->{widget},$self->{resize}) }
}

package Layout::MenuItem;
use Gtk2;

sub new
{	my ($opt1,$opt2)=@_;
	my $self;
	my $label=$opt1->{label};
	if ($opt1->{togglewidget})	{ $self=Gtk2::CheckMenuItem->new($label); }
	elsif ($opt1->{icon})		{ $self=Gtk2::ImageMenuItem->new($label);
					  $self->set_image( Gtk2::Image->new_from_stock($opt1->{icon}, 'menu'));
				  	}
	else				{ $self=Gtk2::MenuItem->new($label); }
	if ($opt1->{togglewidget})
	{	$self->{widget}=$opt1->{togglewidget};
		$self->{resize}=$opt1->{resize};
		$self->signal_connect( toggled => \&Layout::TogButton::toggled_cb );
		::Watch($self,'HiddenWidgets',\&Layout::TogButton::UpdateToggleState);
	}
	if ($opt1->{command})
	{	$self->signal_connect(activate => \&::run_command,$opt1->{command});
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

package Layout::LabelToggleButtons;
use base 'Gtk2::ScrolledWindow';
sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self= bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');
	$self->set_policy('automatic','automatic');
	$self->{table}=Gtk2::Table->new(1,1,::TRUE);
	$self->add_with_viewport($self->{table});
	my $field=$self->{field}= $opt1->{field} || 'label'; #FIXME check if correct type
	#::WatchSelID($self,\&update_song,[$field]);
	::Watch($self,"newgids_$field",\&update_labels);
	$self->signal_connect( size_allocate => sub { ::IdleDo( "resize_$self",1000, \&update_columns,$_[0] ); });
	return $self;
}
sub update_labels
{	my $self=shift;
	my %checks; $self->{checks}=\%checks;
	for my $label ( @{Songs::ListAll($self->{field})} )
	{	my $check= $checks{$label}= Gtk2::CheckButton->new_with_label($label);
		$check->signal_connect(toggled => sub { my $self=::find_ancestor($_[0],__PACKAGE__); return if $self->{busy}; my $field= ($_[0]->get_active ? '+' : '-').$self->{field}; Songs::Set($::SongID,$field,[$_[1]]); },$label);
	}
	$self->{width}=0;
	$self->update_columns;
	$self->update_song;
}
sub update_columns
{	my $self=shift;
	my $width=$self->child->allocation->width;
	return unless $width;
	return if $self->{width} && $width == $self->{width};
	$self->{width}=$width;
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
	$table->resize(1,1);
	my $checks=$self->{checks};
	my $maxwidth=::max( 10,map 4+$_->size_request->width, values %$checks );
	my $maxcol= int( $width / $maxwidth)||1;
	my $col=my $row=0;
	for my $widget (grep defined, map $checks->{$_}, @{Songs::ListAll($self->{field})})
	{	$table->attach($widget,$col,$col+1,$row,$row+1,['fill','expand'],'shrink',1,1);
		if (++$col==$maxcol) {$col=0; $row++;}
	}
	$table->show_all;
}

sub update_song
{	my $self=shift;
	$self->{busy}=1;
	$self->{table}->set_sensitive(defined $::SongID);
	my $checks=$self->{checks};
	for my $label (keys %$checks)
	{	my $check=$checks->{$label};
		my $on= defined $::SongID ? Songs::IsSet($::SongID,$self->{field}, $label) : 0;
		$check->set_active($on);
	}
	$self->{busy}=0;
}

package GMB::Context;
use Gtk2;
our %Contexts;

use base 'Gtk2::VBox';

sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self = bless Gtk2::VBox->new, $class;
	$self->{notebook}=Gtk2::Notebook->new;
	$self->{notebook}->set_scrollable(::TRUE);
	$self->{notebook}->popup_enable;

	$self->{group}=$opt1->{group};
	my $check= defined $self->{group} ? _"Follow selected song" : _"Follow playing song";
	$check=Gtk2::CheckButton->new($check);
	$self->{follow}= $opt2->{follow};
	for my $key (grep m/__/,keys %$opt2)
	{	my ($child,$opt)=split /__/,$key,2;
		$self->{children_opt}{$child}{$opt}= $opt2->{$key};
	}
	$check->set_active( $self->{follow} );
	$check->signal_connect(toggled => sub { $self->{follow}=$_[0]->get_active; $self->SongChanged(::GetSelID($self)) if $self->{follow}; });
	::set_drag($check, dest => [::DRAG_ID,sub
		{	my ($check,$type,@IDs)=@_;
			$self->SongChanged($IDs[0],1);
		}]);

	$self->pack_start($check,::FALSE,::FALSE,1);
	$self->add( $self->{notebook} );
	for my $c (keys %Contexts)
	{	$self->Append($c);
	}
	::WatchSelID($self,\&SongChanged);
	::Watch($self,Context=>\&Changed);
	$self->{SaveOptions}=\&SaveOptions;

	$self->{ID}=$::SongID;
	#$self->SongChanged($::SongID);

	return $self;
}

sub AddPackage
{	my ($package,$key)=@_;
	$Contexts{$key}=$package;
	::HasChanged('Context','add',$key);
}
sub RemovePackage
{	my $key=$_[0];
	::HasChanged('Context','remove',$key);
	delete $Contexts{$key};
}

sub SaveOptions
{	my $self=$_[0];
	my %opt;
	$opt{follow}=1 if $self->{follow};
	for my $w ($self->{notebook}->get_children)
	{	$self->{children_opt}{ $w->{context_key} }= $w->{widget_options};
	}
	my $ref=$self->{children_opt}||{};
	for my $child (keys %$ref)
	{	next unless $ref->{$child};
		$opt{$child.'__'.$_}= $ref->{$child}{$_} for keys %{$ref->{$child}};
	}
	return \%opt;
}

sub Changed
{	my ($self,$action,$key)=@_;
	my $notebook=$self->{notebook};
	if ($action eq 'add') { $self->Append($key); }
	elsif ($action eq 'remove')
	{	for my $w ($notebook->get_children)
		{	if ($w->{context_key} eq $key)
			 { $notebook->remove($w); $self->{children_opt}{$key}=$w->{widget_options}; $w->destroy; }
		}
	}
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless $self->{follow} || $force;
	$self->{ID}=$ID;
	my $nb=$self->{notebook};
	my $page=$nb->get_nth_page( $nb->get_current_page );
	return unless $page;
	$page->SongChanged($ID) if $page->mapped;
	#for my $w ($self->{notebook}->get_children)
	#{	$w->SongChanged($ID);
	#}
}

sub Append
{	my ($self,$key)=@_;
	my @widgets=$Contexts{$key}->new( $self->{children_opt}{$key} );
	for my $w (@widgets)
	{	$w->{context_key}=$key;
		$w->signal_connect(map => sub { $_[0]->SongChanged($self->{ID}) });
		$self->{notebook}->append_page($w, Gtk2::Label->new($w->title) );
		$self->{notebook}->set_tab_reorderable($w,::TRUE);
		#$w->SongChanged( ::GetSelID($self) );
	}
}

package ExtraWidgets;
my %Widgets;

sub SetupContainer
{	my ($container,$type,$packsub,$options)=@_;
	::Watch($container,'ExtraWidgets',\&Changed);
	$container->{ExtraWidgets_param}=[$type,$packsub,$options];
	for my $id (keys %Widgets)
	{	PackWidget($container,$id);
	}
}

sub AddWidget
{	my ($id,$type,$sub)=@_;
	if ($Widgets{$id})
	 { warn "ExtraWidget '$id' already exists\n";return }
	$Widgets{$id}=[$sub,$type];
	::HasChanged(ExtraWidgets => 'add', $id);
}
sub RemoveWidget
{	my $id=$_[0];
	delete $Widgets{$id};
	::HasChanged(ExtraWidgets => 'remove', $id);
}

sub PackWidget
{	my ($container,$id)=@_;
	my ($type,$packsub,$opt)=@{$container->{ExtraWidgets_param}};
	my ($wsub,$wtype)=@{$Widgets{$id}};
	return unless $type eq $wtype;
	my $widget=$wsub->(::get_layout_widget($container));
	return unless $widget;
	$widget->show_all;
	$widget->{ExtraWidgets_id}=$id;
	$packsub->($container,$widget,$opt->{pack}||'');
	if ($widget->isa('Gtk2::Button'))
	{	$widget->set_relief($opt->{relief}) if $opt->{relief};
	}
	if ($container->isa('Gtk2::Box'))
	{	$container->reorder_child($widget,$opt->{pos}) if $opt->{pos};
	}
}

sub Changed
{	my ($container,$action,$id)=@_;
	if ($action eq 'add')
	{	PackWidget($container,$id);
	}
	elsif ($action eq 'remove')
	{	for my $w ($container->get_children)
		{	if ($w->{ExtraWidgets_id} && $w->{ExtraWidgets_id} eq $id)
			 { $container->remove($w); $w->destroy; }
		}
	}
}



package Stars;
use Gtk2;
use base 'Gtk2::EventBox';

my (@pixbufs,$width);
use constant NBSTARS => 5;

INIT
{	@pixbufs=map Gtk2::Gdk::Pixbuf->new_from_file(::PIXPATH.'stars'.$_.'.png'), 0..NBSTARS;
	$width=$pixbufs[0]->get_width/NBSTARS;
}

sub new
{	my ($class,$nb,$sub) = @_;
	my $self = bless Gtk2::EventBox->new, $class;
	$self->{callback}=$sub;
	my $image=$self->{image}=Gtk2::Image->new;
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
	$nb=$::Options{DefaultRating} if !defined $nb || $nb eq '';
	$::Tooltips->set_tip($self,_("song rating")." : $nb %");
	$self->{image}->set_from_pixbuf( get_pixbuf($nb) );
}
sub get { shift->{nb}; }

sub click
{	my ($self,$event)=@_;
	&popup if $event->button == 3;
	my ($x)=$event->coords;
	my $nb=1+int($x/$width);
	$nb*=100/NBSTARS;
	$self->callback($nb);
	return 1;
}

sub popup
{	(my $self,$::LEvent)=@_;
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
	$menu->show_all;
	$menu->popup(undef, undef, \&::menupos, undef, $::LEvent->button, $::LEvent->time);
}

sub createmenu
{	my $IDs=$_[0]{IDs};
	my %set;
	$set{$_}++ for Songs::Map('rating',$IDs);
	my $set= (keys %set ==1) ? each %set : 'undef';
	my $cb=sub	{	Songs::Set($IDs,rating => $_[1]);
			};
	my $menu=Gtk2::Menu->new;
	for my $nb ('',0..NBSTARS)
	{	my $item=Gtk2::CheckMenuItem->new;
		my ($child,$rating)= $nb eq ''	? (Gtk2::Label->new(_"default"),'')
						: (Gtk2::Image->new_from_pixbuf($pixbufs[$nb]),$nb*100/NBSTARS);
		$item->add($child);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $set eq $rating;
		$item->signal_connect(activate => $cb, $rating);
		$menu->append($item);
	}
	return $menu;
}

sub get_pixbuf
{	my $r=$_[0]; my $def=$_[1];
	if (!defined $r || $r eq '')
	{	return undef unless $def;
		$r=$::Options{DefaultRating};
	}
	$r=sprintf '%d',$r*NBSTARS/100;
	return $pixbufs[$r];
}



package Layout::Progress;
sub new
{	my ($class,$opt1,$opt2,$ref)=@_;
	my $vert= exists $opt1->{vertical} ? $opt1->{vertical} : $ref->{vertical};
	my $self= $vert ? Gtk2::VBox->new : Gtk2::HBox->new;
	::Watch($self,Progress=>\&update);
	update($self,$_,$::Progress{$_}) for keys %::Progress;
	$self->{lastclose}=$opt1->{lastclose};
	$self->{compact}= exists $opt1->{compact} ? $opt1->{compact} : $ref->{compact};
	return $self;
}
sub new_pid
{	my ($self,$prop)=@_;
	my $hbox=Gtk2::HBox->new(0,2);
	my $vbox=Gtk2::VBox->new;
	my $label;
	my $bar=Gtk2::ProgressBar->new;
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
	my $widgets= $self->{pids}{$pid} ||= new_pid($self,$prop);
	my (undef,$bar,$label)=@$widgets;
	my $title=$prop->{title};
	my $details=$prop->{details};
	my $bartext=$prop->{bartext};
	if ($self->{compact})
	{	$bartext=$title.' ... '.$bartext;
		$::Tooltips->set_tip( $bar, $details ) if $details;
	}
	else
	{	my $markup= '<b>'.::PangoEsc($title).'</b>';
		$markup.= "\n".::PangoEsc($details) if $details;
		$label->set_markup( $markup )
	}
	$bar->set_fraction( $prop->{fraction} );
	$bar->set_text( $bartext )	if defined $bartext;
}

package Layout::Equalizer;
sub new
{	my $opt1=$_[0];
	my $self=Gtk2::HBox->new(1,0); #homogenous
	for my $i (0..9)
	{	my $adj=Gtk2::Adjustment->new(0, -1, 1, .05, .1,0);
		my $scale=Gtk2::VScale->new($adj);
		$scale->set_draw_value(0);
		$scale->set_inverted(1);
		$self->{'adj'.$i}=$adj;
		$adj->signal_connect(value_changed =>
		sub { $::Play_package->set_equalizer($_[1],$_[0]->get_value) unless $_[0]{busy}; ::HasChanged('Equalizer','value') },$i);
		$self->{labels}= $opt1->{labels} || 'x-small';
		$self->{labels}=undef if $self->{labels} eq 'none';
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
	my $ok= $::Play_package->{EQ} && $::Options{gst_use_equalizer};
	$self->set_sensitive($ok);
	if ((!$event || $event eq 'package') && $self->{labels})
	{	my ($min,$max,$unit)= $::Play_package->{EQ} ? $::Play_package->EQ_Get_Range : (-1,1,'');
		my $inc=abs($max-$min)/10;
		$unit=' '.$unit if $unit;
		$self->{unit}= $unit;
		for my $i (0..9)
		{	if ($self->{labels})
			{	my $val='-';
				$val=::PangoEsc($::Play_package->EQ_Get_Hz($i)||'?') if $::Play_package->{EQ};
				$self->{'Hzlabel'.$i}->set_markup(qq(<span size="$self->{labels}">$val</span>));
			}
			my $adj=$self->{'adj'.$i};
			$adj->{busy}=1;
			$adj->lower($min);
			$adj->upper($max);
			$adj->step_increment($inc/10);
			$adj->page_increment($inc);
			delete $adj->{busy};
		}
	}
	my @val= split /:/, $::Options{gst_equalizer};
	#@val=(0)x10 unless $ok;
	for my $i (0..9)
	{	my $val=$val[$i];
		my $adj=$self->{'adj'.$i};
		$adj->{busy}=1;
		$adj->set_value($val);
		delete $adj->{busy};
		next unless $self->{labels};
		$val=sprintf('%.1f',$val).$self->{unit};
		$self->{'Valuelabel'.$i}->set_markup(qq(<span size="$self->{labels}">$val</span>)) if $self->{labels};
	}
}

# SVBox and SHBox are Gtk2::VBox and Gtk2::HBox with a smarter size_allocate function : the normal boxes divide the extra space equally among children with the expand mode. With these boxes the extra space can be allocated to children up to a ratio of their other dimension (expand_to_ratio), or according to a weight (expand_weight)
package SVBox;
use Gtk2;
use Glib::Object::Subclass
	Gtk2::VBox::,
	signals =>
	{	size_allocate => \&SHBox::size_allocate,
	};
package SHBox;
use Gtk2;
use Glib::Object::Subclass
	Gtk2::HBox::,
	signals =>
	{	size_allocate => \&size_allocate,
	};

sub size_allocate
{	my ($self,$alloc)=@_;
	my $vertical= $self->isa('Gtk2::VBox');
	my ($x,$y,$bwidth,$bheight)=$alloc->values;
	my $olda=$self->allocation;
	 $olda->x($x); $olda->y($y);
	 $olda->width($bwidth); $olda->height($bheight);
	($y,$x,$bheight,$bwidth)=($x,$y,$bwidth,$bheight) if $vertical;
	my $border=$self->get_border_width;
	$x+=$border;  $bwidth-=$border*2;
	$y+=$border; $bheight-=$border*2;
	my $total_xreq=0; my @emax; my $ecount=0;
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
		else					{$max=$child->{expand_max}}
		if	($max)		{ $max-=$xreq; if ($max>0) {push @emax,[$max*$eweight,$max,$eweight,\@attrib]; $ecount+=$eweight;$expand=$eweight;} else {$expand=0} }
		elsif	($expand)	{$ecount+=$eweight;$expand=$eweight;}
		@attrib=($child,$expand,$fill,$pad,$type,$xreq);
		if ($type eq 'end')	{unshift @children,\@attrib} #to keep the same order as a HBox
		else			{push @children,\@attrib}
	}
	$total_xreq+=$#children*$spacing if @children;
	my $xend=$x+$bwidth;
	my $wshare; my $wrest; my $only_etr;
	if ($total_xreq<$bwidth && $ecount)
	{	my $w=$bwidth-$total_xreq;
		for my $emax (sort { $a->[0] <=> $b->[0] } @emax)
		{	my (undef,$max,$eweight,$attrib)=@$emax;
			if ($max < $w/$ecount*$eweight) {$w-=$max; push @$attrib,$max; $ecount-=$eweight;}
		}
		if ($ecount) {$wshare=$w/$ecount}
		elsif ($w) #all expands were expand_to_ratio and satisfied and space left -> share between those which are packed with expand
		{	my $count;
			for my $ref (@children)
			{	$count++ if $ref->[1]; #expand
			}
			$wshare=$w/$count if $count;
			$only_etr=1;
		}
	}
	my $homogeneous;
	if ($self->get_homogeneous)
	{	$homogeneous=($bwidth-($#children*$spacing))/@children;
	}
	for my $ref (@children)
	{	my ($child,$expand,$fill,$pad,$type,$ww,$maxedout)=@$ref;
		my $wwf= $ww;
		if ($maxedout)	{ $wwf+=$maxedout; }
		elsif ($wshare)	{ $wwf+=$wshare*$expand; }
		$wwf=$homogeneous-$pad*2 if $homogeneous;
		$ww=$wwf if $fill;
		my $wx;
		my $totalw=$pad*2+$wwf+$spacing;
		#warn "$child : $pad*2+$wwf+$spacing\n";
		$pad+=($wwf-$ww)/2;
		if ($type eq 'end')	{ $wx=$xend-$pad-$ww;   $xend-=$totalw; }
		else			{ $wx=$x+$pad;		   $x+=$totalw; }
		my $wa= $vertical ?
			Gtk2::Gdk::Rectangle->new($y, $wx, $bheight, $ww):
			Gtk2::Gdk::Rectangle->new($wx, $y, $ww, $bheight);
		$child->size_allocate($wa);
	}
}

package Skin;
use Gtk2;

sub new
{	my ($class,$string,$widget,$layout_options)=@_;
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
	$self->{layout_options}=$layout_options;
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
	my $state2=$widget->{ref}{state};
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
		my $mask=Gtk2::Gdk::Bitmap->create_from_data($widget->window,'',$pbw,$pbh);
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
	{ $options||={};
	  $file ||= $options->{SkinFile};
	  $file='' unless defined $file;
	  unless (::file_name_is_absolute($file))
	  {	my $path= $options->{SkinPath};
		$path='' unless defined $path;
		unless (::file_name_is_absolute($path))
		{	my $p= $::HomeDir.'layouts'.::SLASH.$path;
			$path= (-e $p.::SLASH.$file)? $p : $::DATADIR.::SLASH.$path;
		}
		$file= $path.::SLASH.$file if defined $path;
	  }
	  return unless -r $file;
	  $pb=Gtk2::Gdk::Pixbuf->new_from_file($file);
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
	my $pb=_load_skinfile($self->{file},$self->{crop},$self->{layout_options});
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
