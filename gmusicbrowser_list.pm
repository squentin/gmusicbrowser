# Copyright (C) 2005-2020 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;

package Browser;
use constant { TRUE  => 1, FALSE => 0, };

our @MenuPlaying=
(	{ label => _"Follow playing song",	code => sub { $_[0]{songlist}->FollowSong if $_[0]{songlist}->{follow}; }, toggleoption => 'songlist/follow' },
	{ label => _"Filter on playing Album",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('album',$::SongID) )	if defined $::SongID; }},
	{ label => _"Filter on playing Artist",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('artists',$::SongID) )if defined $::SongID; }},
	{ label => _"Filter on playing Song",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('title',$::SongID) )	if defined $::SongID; }},
	{ label => _"Use the playing filter",	code => sub { ::SetFilter($_[0]{songlist}, $::PlayFilter ); }, test => sub {::GetSonglist($_[0]{songlist})->{mode} ne 'playlist'}}, #FIXME	if queue use queue, if $ListMode use list
	{ label => _"Recent albums",		submenu => sub { my $sl=$_[0]{songlist};my @gid= ::uniq( Songs::Map_to_gid('album',$::Recent) ); $#gid=19 if $#gid>19; my $m=::PopupAA('album',nosort=>1,nominor=>1,widget => $_[0]{self}, list=>\@gid, cb=>sub { ::SetFilter($sl, $_[0]{filter}); }); return $m; } },
	{ label => _"Recent artists",		submenu => sub { my $sl=$_[0]{songlist};my @gid= ::uniq( Songs::Map_to_gid('artist',$::Recent) ); $#gid=19 if $#gid>19; my $m=::PopupAA('artists',nosort=>1,nominor=>1,widget => $_[0]{self}, list=>\@gid, cb=>sub { ::SetFilter($sl, $_[0]{filter}); }); return $m; } },
	{ label => _"Recent songs", submenu_use_markup => 1, submenu_ordered_hash => 1, submenu_reverse=>1,
	  submenu => sub { my @ids=@$::Recent; $#ids=19 if $#ids>19; return [map {$_, ::ReplaceFieldsAndEsc($_, ::__x( _"{song} by {artist}", song => "<b>%S</b>%V", artist => "%a"))} @ids]; },
	  code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('title',$_[1]) ); }, },
);

sub makeFilterBox
{	my $box= Gtk3::Box->new('horizontal',2);
	my $FilterWdgt=GMB::FilterBox->new
	( sub	{ my $filt=shift; ::SetFilter($box,$filt); },
	  undef,
	  'title:si:',
		_"Edit filter..." => sub
		{	::EditFilter($box,::GetFilter($box),undef,sub {::SetFilter($box,$_[0]) if defined $_[0]});
		});
	my $okbutton=::NewIconButton('gtk-apply',undef,sub {$FilterWdgt->activate},'none');
	$okbutton->set_tooltip_text(_"apply filter");
	$box->add($FilterWdgt);
	$box->add($okbutton);
	return $box;
}

sub makeLockToggle
{	my $opt=$_[0];
	my $toggle= Gtk3::ToggleButton->new;
	$toggle->set_relief( $opt->{relief} ) if $opt->{relief};
	$toggle->add(Gtk3::Image->new_from_stock('channel-secure-symbolic','menu'));
	#$toggle->set_active(1) if $self->{Filter0};
	$toggle->signal_connect( clicked =>sub
		{	my $self=$_[0];
			return if $self->{busy};
			my $f=::GetFilter($self,0);
			my $empty=Filter::is_empty($f);
			if ($empty)	{ ::SetFilter($self,::GetFilter($self),0); }
			else		{ ::SetFilter($self,undef,0); }
		});
	$toggle->signal_connect (button_press_event => sub
		{	my ($self,$event)=@_;
			return 0 unless $event->button==3;
			::SetFilter($self,::GetFilter($self),0);
			1;
		});
	::set_drag($toggle, dest => [::DRAG_FILTER,sub {::SetFilter($_[0],$_[2],0);}]);
	::WatchFilter($toggle,$opt->{group},sub
		{	my ($self,undef,undef,$group)=@_;
			my $filter=$::Filters{$group}[0+1]; #filter for level 0
			my $empty=Filter::is_empty($filter);
			$self->{busy}=1;
			$self->set_active(!$empty);
			$self->{busy}=0;
			my $desc=($empty? _("No locked filter") : _("Locked on :\n").$filter->explain);
			$self->set_tooltip_text($desc);
		});
	return $toggle;
}

sub make_sort_menu
{	my $selfitem=$_[0];
	my $songlist= $selfitem->isa('SongList::Common') ? $selfitem : ::GetSonglist($selfitem);
	my $menu= ($selfitem->can('get_submenu') && $selfitem->get_submenu) || Gtk3::Menu->new;
	my $menusub=sub { $songlist->Sort($_[1]) };
	for my $name (sort keys %{$::Options{SavedSorts}})
	{   my $sort=$::Options{SavedSorts}{$name};
	    my $item= Gtk3::CheckMenuItem->new_with_label($name);
	    $item->set_draw_as_radio(1);
	    $item->set_active(1) if $songlist->{sort} eq $sort;
	    $item->signal_connect (activate => $menusub,$sort );
	    $menu->append($item);
	}
	my $itemEditSort= Gtk3::ImageMenuItem->new(_"Custom...");
	$itemEditSort->set_image( Gtk3::Image->new_from_stock('emblem-system-symbolic','menu') );
	$itemEditSort->signal_connect (activate => sub
	{	my $sort=::EditSortOrder($selfitem,$songlist->{sort});
		$songlist->Sort($sort) if $sort;
	});
	$menu->append($itemEditSort);
	return $menu;
}

sub fill_history_menu
{	my $selfitem=$_[0];
	my $menu= $selfitem->get_submenu || Gtk3::Menu->new;
	my $mclicksub=sub   { $_[0]{middle}=1 if $_[1]->button == 2; return 0; };
	my $menusub=sub
	 { my $f=($_[0]{middle})? Filter->newadd(FALSE, ::GetFilter($selfitem,1),$_[1]) : $_[1];
	   ::SetFilter($selfitem,$f);
	 };
	for my $f (@{ $::Options{RecentFilters} })
	{	my $item = Gtk3::MenuItem->new_with_label( $f->explain );
		$item->signal_connect(activate => $menusub,$f);
		$item->signal_connect(button_release_event => $mclicksub,$f);
		$menu->append($item);
	}
	return $menu;
}

package LabelTotal;
use base 'Gtk3::Bin';

our %Modes=
(	list	 => {label=> _"Listed songs",	setup => \&list_Set,	update=>\&list_Update,		delay=> 1000,	},
	filter	 => {label=> _"Filter",		setup => \&filter_Set,	update=>\&filter_Update,	delay=> 1500,	},
	library	 => {label=> _"Library",	setup => \&library_Set,	update=>\&library_Update,	delay=> 4000,	},
	selected => {label=> _"Selected songs", setup => \&selected_Set,update=>\&selected_Update,	delay=> 500,	},
);

our @default_options=
(	button =>1, format => 'long', relief=> 'none', mode=> 'list',
);

sub new
{	my ($class,$opt) = @_;
	%$opt=( @default_options, %$opt );
	my $self;
	if ($opt->{button})
	{	$self= Gtk3::Button->new;
		$self->set_relief($opt->{relief});
	}
	else { $self=Gtk3::EventBox->new; }
	bless $self,$class;
	$self->{$_}= $opt->{$_} for qw/size format group noheader/;
	$self->add(Gtk3::Label->new);
	$self->signal_connect( destroy => \&Remove);
	$self->signal_connect( button_press_event => \&button_press_event_cb);
	::Watch($self, SongsChanged	=> \&SongsChanged_cb);
	$self->Set_mode($opt->{mode});
	return $self;
}

sub Set_mode
{	my ($self,$mode)=@_;
	$self->Remove;
	$self->{mode}=$mode;
	$Modes{ $self->{mode} }{setup}->($self);
	$self->QueueUpdateFast;
}

sub Remove
{	my $self=shift;
	delete $::ToDo{'9_Total'.$self};
	::UnWatchFilter($self,$self->{group});
	::UnWatch($self,'Selection_'.$self->{group});
	::UnWatch($self,$_) for qw/SongArray SongsAdded SongsHidden SongsRemoved/;
}

sub button_press_event_cb
{	my ($self,$event)=@_;
	my $menu= Gtk3::Menu->new;
	for my $mode (sort {$Modes{$a}{label} cmp $Modes{$b}{label}} keys %Modes)
	{	my $item= Gtk3::CheckMenuItem->new( $Modes{$mode}{label} );
		$item->set_draw_as_radio(1);
		$item->set_active($mode eq $self->{mode});
		$item->signal_connect( activate => sub { $self->Set_mode($mode) } );
		$menu->append($item);
	 }
	::PopupMenu($menu);
}

sub QueueUpdateFast
{	my $self=shift;
	$self->{needupdate}=2;
	::IdleDo('9_Total'.$self, 10, \&Update, $self);
}
sub QueueUpdateSlow
{	my $self=shift;
	return if $self->{needupdate};
	$self->{needupdate}=1;
	my $maxdelay= $Modes{ $self->{mode} }{delay};
	::IdleDo('9_Total'.$self, $maxdelay, \&Update, $self);
}
sub Update
{	my $self=shift;
	delete $::ToDo{'9_Total'.$self};
	my ($text,$array,$tip)= $Modes{ $self->{mode} }{update}->($self);
	$text='' if $self->{noheader};
	if (!$array)	{ $tip=$text=_"error"; }
	else		{ $text.= ::CalcListLength($array,$self->{format}); }
	my $format= $self->{size} ? '<span size="'.$self->{size}.'">%s</span>' : '%s';
	$self->get_child->set_markup_with_format($format,$text);
	$self->set_tooltip_text($tip);
	$self->{needupdate}=0;
}

sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	return if $self->{needupdate};
	my $needupdate= $fields && (grep $_ eq 'length' || $_ eq 'size', @$fields);
	if (!$needupdate && $self->{mode} eq 'filter')
	{	my $filter=::GetFilter($self);
		$needupdate=$filter->changes_may_affect($IDs,$fields);
	}
	#if in list mode, could check : return if $IDs && !$songarray->AreIn($IDs)
	$self->QueueUpdateSlow if $needupdate;
}

### filter functions
sub filter_Set
{	my $self=shift;
	::WatchFilter($self,$self->{group},	\&QueueUpdateFast);
	::Watch($self, SongsAdded	=>	\&SongsChanged_cb);
	::Watch($self, SongsRemoved	=>	\&SongsChanged_cb);
	::Watch($self, SongsHidden	=>	\&SongsChanged_cb);
}
sub filter_Update
{	my $self=shift;
	my $filter=::GetFilter($self);
	my $array=$filter->filter;
	return _("Filter : "), $array, $filter->explain;
}

### list functions
sub list_Set
{	my $self=shift;
	::Watch($self, SongArray	=>\&list_SongArray_changed);
}
sub list_SongArray_changed
{	my ($self,$array,$action)=@_;
	return if $self->{needupdate};
	my $array0=::GetSongArray($self) || return;
	return unless $array0==$array;
	return if grep $action eq $_, qw/mode sort move up down/;
	$self->QueueUpdateFast;
}
sub list_Update
{	my $self=shift;
	my $array=::GetSongArray($self) || return;
	return _("Listed : "), $array,  ::__n('%d song','%d songs',scalar@$array);
}

### selected functions
sub selected_Set
{	my $self=shift;
	::Watch($self,'Selection_'.$self->{group}, \&QueueUpdateFast);
}
sub selected_Update
{	my $self=shift;
	my $songlist=::GetSonglist($self);
	return unless $songlist;
	my @list=$songlist->GetSelectedIDs;
	return _('Selected : '), \@list,  ::__n('%d song selected','%d songs selected',scalar@list);
}

### library functions
sub library_Set
{	my $self=shift;
	::Watch($self, SongsAdded	=>\&QueueUpdateSlow);
	::Watch($self, SongsRemoved	=>\&QueueUpdateSlow);
	::Watch($self, SongsHidden	=>\&QueueUpdateSlow);
}
sub library_Update
{	my $tip= ::__n('%d song in the library','%d songs in the library',scalar@$::Library);
	return _('Library : '), $::Library, $tip;
}


package EditListButtons;
use Glib qw(TRUE FALSE);
use base 'Gtk3::Box';

sub new
{	my ($class,$opt)=@_;
	my $self= ($opt->{orientation}||'') eq 'vertical' ? Gtk3::VBox->new : Gtk3::HBox->new;
	bless $self, $class;

	$self->{group}=$opt->{group};
	$self->{bshuffle}=::NewIconButton('media-playlist-shuffle-symbolic',($opt->{small} ? '' : _"Shuffle"),sub {::GetSongArray($self)->Shuffle});
	$self->{brm}=	::NewIconButton('list-remove-symbolic',	($opt->{small} ? '' : _"Remove"),sub {::GetSonglist($self)->RemoveSelected});
	$self->{bclear}=::NewIconButton('edit-clear-symbolic',	($opt->{small} ? '' : _"Clear"),sub {::GetSonglist($self)->Empty} );
	$self->{bup}=	::NewIconButton('go-up-symbolic',		undef,	sub {::GetSonglist($self)->MoveUpDown(1)});
	$self->{bdown}=	::NewIconButton('go-down-symbolic',		undef,	sub {::GetSonglist($self)->MoveUpDown(0)});
	$self->{btop}=	::NewIconButton('go-top-symbolic',		undef,	sub {::GetSonglist($self)->MoveUpDown(1,1)});
	$self->{bbot}=	::NewIconButton('go-bottom-symbolic',	undef,	sub {::GetSonglist($self)->MoveUpDown(0,1)});

	$self->{brm}->set_tooltip_text(_"Remove selected songs");
	$self->{bclear}->set_tooltip_text(_"Remove all songs");

	if (my $r=$opt->{relief}) { $self->{$_}->set_relief($r) for qw/brm bclear bup bdown btop bbot bshuffle/; }
	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/btop bup bdown bbot brm bclear bshuffle/;

	::Watch($self,'Selection_'.$self->{group}, \&SelectionChanged);
	::Watch($self,SongArray=> \&ListChanged);
	$self->{PostInit}= sub { $self->SelectionChanged; $self->ListChanged; };

	return $self;
}

sub ListChanged
{	my ($self,$array)=@_;
	my $songlist=::GetSonglist($self);
	my $watchedarray= $songlist && $songlist->{array};
	return if !$watchedarray || ($array && $watchedarray!=$array);
	$self->{bclear}->set_sensitive(@$watchedarray>0);
	$self->{bshuffle}->set_sensitive(@$watchedarray>1);
	$self->set_sensitive( !$songlist->{autoupdate} );
	$self->set_visible( !$songlist->{autoupdate} );
}

sub SelectionChanged
{	my ($self)=@_;
	my $rows;
	my $songlist=::GetSonglist($self);
	if ($songlist)
	{	$rows=$songlist->GetSelectedRows;
	}
	if ($rows && @$rows)
	{	$self->{brm}->set_sensitive(1);
		my $i=0;
		$i++ while $i<@$rows && $rows->[$i]==$i;
		$self->{$_}->set_sensitive($i!=@$rows) for qw/btop bup/;
		$i=$#$rows;
		my $array=$songlist->{array};
		$i-- while $i>-1 && $rows->[$i]==$#$array-$#$rows+$i;
		$self->{$_}->set_sensitive($i!=-1) for qw/bbot bdown/;
	}
	else
	{	$self->{$_}->set_sensitive(0) for qw/btop bbot brm bup bdown/;
	}
}

package QueueActions;
use Glib qw(TRUE FALSE);
use base 'Gtk3::Box';

sub new
{	my $class=$_[0];
	my $self= bless Gtk3::HBox->new, $class;

	my $action_store= Gtk3::ListStore->new(('Glib::String')x3);

	$self->{queuecombo}=
	my $combo= Gtk3::ComboBox->new_with_model($action_store);

	my $renderer= Gtk3::CellRendererPixbuf->new;
	$combo->pack_start($renderer,FALSE);
	$combo->add_attribute($renderer, stock_id => 0);
	$renderer= Gtk3::CellRendererText->new;
	$combo->pack_start($renderer,TRUE);
	$combo->add_attribute($renderer, text => 1);

	$combo->signal_connect(changed => sub
		{	return if $self->{busy};
			my $iter=$_[0]->get_active_iter;
			my $action=$_[0]->get_model->get_value($iter,2);
			::EnqueueAction($action);
		});
	$self->{eventcombo}= Gtk3::EventBox->new;
	$self->{eventcombo}->add($combo);
	$self->{spin}=::NewPrefSpinButton('MaxAutoFill', 1,50, step=>1, page=>5, cb=>sub
		{	return if $self->{busy};
			::HasChanged('QueueAction','maxautofill');
		});
	$self->{spin}->set_no_show_all(1);

	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/eventcombo spin/;

	::Watch($self, QueueAction => \&Update);
	::Watch($self, QueueActionList => \&Fill);
	$self->Fill;
	return $self;
}

sub Fill
{	my $self=shift;
	my $store= $self->{queuecombo}->get_model;
	$self->{busy}=1;
	$store->clear;
	delete $self->{actionindex};
	my $i=0;
	for my $action (::List_QueueActions(0))
	{	$store->set($store->append, 0,$::QActions{$action}{icon}, 1,$::QActions{$action}{short} ,2, $action );
		$self->{actionindex}{$action}=$i++;
	}
	$self->Update;
}

sub Update
{	my $self=$_[0];
	$self->{busy}=1;
	my $action=$::QueueAction;
	$self->{queuecombo}->set_active( $self->{actionindex}{$action} );
	$self->{eventcombo}->set_tooltip_text( $::QActions{$action}{long} );
	$self->{spin}->set_visible($::QActions{$action}{autofill});
	$self->{spin}->set_value($::Options{MaxAutoFill});
	delete $self->{busy};
}

package SongList::Common;	#common functions for SongList and SongTree
our %Register;
our $EditList;	#list that will be used in 'editlist' mode, used only for editing a list in a separate window

our @DefaultOptions=
(	'sort'	=> 'path album:i disc track file',
	hideif	=> '',
	colwidth=> '',
	autoupdate=>1,
);
our %Markup_Empty=
(	Q => _"Queue empty",
	L => _"List empty",
	A => _"Playlist empty",
	B => _"No songs found",
	S => _"No songs found",
);

sub new
{	my $opt=$_[1];
	my $package= $opt->{songtree} ? 'SongTree' : $opt->{songlist} ? 'SongList' : 'SongList';
	$package->new($opt);
}

sub CommonInit
{	my ($self,$opt)=@_;

	%$opt=( @DefaultOptions, %$opt );
	$self->{$_}=$opt->{$_} for qw/mode group follow sort hideif hidewidget shrinkonhide markup_empty markup_library_empty autoupdate/,grep(m/^activate\d?$/, keys %$opt);
	$self->{mode}||='';
	my $type= $self->{type}=
				$self->{mode} eq 'playlist' ? 'A' :
				$self->{mode} eq 'editlist' ? 'L' :
				$opt->{type} || 'B';
	$self->{mode}='playlist' if $type eq 'A';
	 #default double-click action :
	$self->{activate} ||=	$type eq 'L' ? 'playlist' :
				$type eq 'Q' ? 'remove_and_play' :
				'play';
	$self->{activate2}||='queue' unless $type eq 'Q'; #default to 'queue' songs when double middle-click

	$self->{markup_empty}= $Markup_Empty{$type} unless defined $self->{markup_empty};
	$self->{markup_library_empty}= _"Library empty.\n\nUse the settings dialog to add music."
		unless defined $self->{markup_library_empty} or $type=~m/[QL]/;

	::WatchFilter($self,$self->{group}, \&SetFilter ) if $type!~m/[QL]/;
	$self->{need_init}=1;
	$self->signal_connect_after(show => sub
		{	my $self=$_[0];
			return unless delete $self->{need_init};
			if ($self->{type}=~m/[QLA]/)
			{	$self->SongArray_changed_cb($self->{array},'replace');
			}
			else { ::InitFilter($self); }
		});
	$self->signal_connect_after('map' => sub { $_[0]->FollowSong }) unless $self->{type}=~m/[QL]/;

	$self->{colwidth}= { split / +/, $opt->{colwidth} };

	my $songarray=$opt->{songarray};
	if ($type eq 'A')
	{	#$songarray= SongArray->new_copy($::ListPlay);
		$self->{array}=$songarray=$::ListPlay;
		$self->{sort}= $::RandomMode ? $::Options{Sort_LastOrdered} : $::Options{Sort};
		$self->UpdatePlayListFilter;
		::Watch($self,Filter=>  \&UpdatePlayListFilter);
		$self->{follow}=1 if !defined $self->{follow}; #default to follow current song on new playlists
	}
	elsif ($type eq 'L')
	{	if (defined $EditList) { $songarray=$EditList; $EditList=undef; } #special case for editing a list via ::WEditList
		unless (defined $songarray && $songarray ne '')	#create a new list if none specified
		{	$songarray='list000';
			$songarray++ while $::Options{SavedLists}{$songarray};
		}
	}
	elsif ($type eq 'Q') { $songarray=$::Queue; }
	elsif ($type eq 'B' || $type eq 'S') { $songarray=SongArray::AutoUpdate->new($self->{autoupdate},$self->{sort}); }

	if ($songarray && !ref $songarray)	#if not a ref, treat it as the name of a saved list
	{	::SaveList($songarray,[]) unless $::Options{SavedLists}{$songarray}; #create new list if doesn't exists
		$songarray=$::Options{SavedLists}{$songarray};
	}
	$self->{follow}=0 if !defined $self->{follow};

	delete $self->{autoupdate} unless $songarray && $songarray->isa('SongArray::AutoUpdate');
	$self->{array}= $songarray || SongArray->new;

	$self->RegisterGroup($self->{group});
	$self->{SaveOptions}=\&CommonSave;
}
sub RegisterGroup
{	my ($self,$group)=@_;
	$Register{ $group }=$self;
	::weaken($Register{ $group });	#or use a destroy cb ?
}
sub UpdatePlayListFilter
{	my $self=shift;
	$self->{ignoreSetFilter}=1;
	::SetFilter($self,$::PlayFilter,0);
	$self->{ignoreSetFilter}=0;
}
sub CommonSave
{	my $self=shift;
	my $opt= $self->SaveOptions;
	$opt->{$_}= $self->{$_} for qw/sort rowtip/;
	$opt->{autoupdate}=$self->{autoupdate} if exists $self->{autoupdate};
	$opt->{follow}= ! !$self->{follow};

	#save options as default for new SongTree/SongList of same type
	my $name= $self->isa('SongTree') ? 'songtree_' : 'songlist_';
	$name= $name.$self->{name}; $name=~s/\d+$//;
	$::Options{"DefaultOptions_$name"}={%$opt};

	if ($self->{type} eq 'L' && defined(my $n= $self->{array}->GetName)) { $opt->{type}='L'; $opt->{songarray}=$n; }
	return $opt;
}

sub Sort
{	my ($self,$sort)=@_;
	$self->{array}->Sort($sort);
}
sub SetFilter
{	my ($self,$filter)=@_;#	::red($self->{type},' ',($self->{filter} || 'no'), ' ',$filter);::callstack();
	if ($self->{hideif} eq 'nofilter')
	{	$self->Hide($filter->is_empty);
		return if $filter->is_empty;
	}
	$self->{filter}=$filter;
	return if $self->{ignoreSetFilter};
	$self->{array}->SetSortAndFilter($self->{sort},$filter);
}
sub Empty
{	my $self=shift;
	$self->{array}->Replace;
}

sub GetSelectedIDs
{	my $self=shift;
	my $rows=$self->GetSelectedRows;
	my $array=$self->{array};
	return map $array->[$_], @$rows;
}
sub PlaySelected ##
{	my $self=$_[0];
	my @IDs=$self->GetSelectedIDs;
	::Select(song=>'first',play=>1,staticlist => \@IDs ) if @IDs;
}
sub EnqueueSelected##
{	my $self=$_[0];
	my @IDs=$self->GetSelectedIDs;
	::Enqueue(@IDs) if @IDs;
}
sub RemoveSelected
{	my $self=shift;
	return if $self->{autoupdate}; #can't remove selection from an always-filtered list
	my $songarray=$self->{array};
	$songarray->Remove($self->GetSelectedRows);
}

sub PopupContextMenu
{	my $self=shift;
	#return unless @{$self->{array}}; #no context menu for empty lists
	my @IDs=$self->GetSelectedIDs;
	my %args=(self => $self, mode => $self->{type}, IDs => \@IDs, listIDs => $self->{array});
	$args{allowremove}=1 unless $self->{autoupdate};
	::PopupContextMenu(\@::SongCMenu,\%args);
}

sub MoveUpDown
{	my ($self,$up,$max)=@_;
	my $songarray=$self->{array};
	my $rows=$self->GetSelectedRows;
	if ($max)
	{	if ($up){ $songarray->Top($rows); }
		else	{ $songarray->Bottom($rows); }
		$self->Scroll_to_TopEnd(!$up);
	}
	else
	{	if ($up){ $songarray->Up($rows) }
		else	{ $songarray->Down($rows) }
	}
}

sub Hide
{	my ($self,$hide)=@_;
	my $name=$self->{hidewidget} || $self->{name};
	my $toplevel=::get_layout_widget($self);
	unless ($toplevel)
	{	$self->{need_hide}=$name if $hide;
		return;
	}
	if ($hide)	{ $toplevel->Hide($name,$self->{shrinkonhide}) }
	else		{ $toplevel->Show($name,$self->{shrinkonhide}) }
}

sub Activate
{	my ($self,$button)=@_;
	my $row= $self->GetCurrentRow;
	return unless defined $row;
	my $songarray=$self->{array};
	my $ID=$songarray->[$row];
	my $activate=$self->{'activate'.$button} || $self->{activate};
	my $aftercmd;
	$aftercmd=$1 if $activate=~s/&(.*)$//;

	if	($activate eq 'playlist')	{ ::Select( staticlist=>[@$songarray], position=>$row, play=>1); }
	elsif	($activate eq 'filter_and_play'){ ::Select(filter=>$self->{filter}, song=>$ID, play=>1); }
	elsif	($activate eq 'filter_sort_and_play'){ ::Select(sort=>$self->{sort}, filter=>$self->{filter}, song=>$ID, play=>1); }
	elsif	($activate eq 'remove_and_play')
	{	$songarray->Remove([$row]);
		::Select(song=>$ID,play=>1);
	}
	elsif	($activate eq 'remove') 	{ $songarray->Remove([$row]); }
	elsif	($activate eq 'properties')	{ ::DialogSongProp($ID); }
	elsif	($activate eq 'play')
	{	if ($self->{type} eq 'A')	{ ::Select(position=>$row,play=>1); }
		else				{ ::Select(song=>$ID,play=>1); }
	}
	else	{ ::DoActionForList($activate,[$ID]); }

	::run_command($self,$aftercmd) if $aftercmd;
}

# functions for dynamic titles
sub DynamicTitle
{	my ($self,$format)=@_;
	return $format unless $format=~m/%n/;
	my $label=Gtk3::Label->new;
	$label->{format}=$format;
	::weaken( $label->{songarray}=$self->{array} );
	::Watch($label,SongArray=> \&UpdateDynamicTitle);
	UpdateDynamicTitle($label);
	return $label;
}
sub UpdateDynamicTitle
{	my ($label,$array)=@_;
	return if $array && $array != $label->{songarray};
	my $format=$label->{format};
	my $nb= @{ $label->{songarray} };
	$format=~s/%(.)/$1 eq 'n' ? $nb : $1/eg;
	$label->set_text($format);
}

# functions for SavedLists, ie type=L
sub MakeTitleLabel
{	my $self=shift;
	my $name=$self->{array}->GetName;
	my $label=Gtk3::Label->new($name);
	::weaken( $label->{songlist}=$self );
	::Watch($label,SavedLists=> \&UpdateTitleLabel);
	return $label;
}
sub UpdateTitleLabel
{	my ($label,$list,$action,$newname)=@_;
	return unless $action && $action eq 'renamedto';
	my $self=$label->{songlist};
	my $old=$label->get_text;
	my $new=$self->{array}->GetName;
	return if $old eq $new;
	$label->set_text($new);
}
sub RenameTitleLabel
{	my ($label,$newname)=@_;
	my $self=$label->{songlist};
	my $oldname=$self->{array}->GetName;
	return if $newname eq '' || exists $::Options{SavedLists}{$newname};
	::SaveList($oldname,$self->{array},$newname);
}
sub DeleteList
{	my $self=shift;
	my $name=$self->{array}->GetName;
	::SaveList($name,undef) if defined $name;
}

sub DrawEmpty
{	my ($self,$cr,$widget,$width)=@_;
	$widget||=$self;
	my $type=$self->{type};
	my $markup= scalar @$::Library ? undef : $self->{markup_library_empty};
	$markup ||= $self->{markup_empty};
	if ($markup)
	{	$markup=~s#(?:\\n|<br>)#\n#g;
		my $layout= $self->create_pango_layout;
		$width-=2*5;
		$layout->set_width( Pango->SCALE * $width );
		$layout->set_wrap('word-char');
		$layout->set_alignment('center');
		my $style= $widget->get_style_context;
		$markup="<big><big><big><big>\n<span foreground=\"grey\">$markup</span></big></big></big></big>";
		$layout->set_markup($markup);
		$style->render_layout($cr,5,5,$layout);
	}
}

sub SetRowTip
{	my ($self,$tip)=@_;
	$tip= "<b><big>%t</big></b>\\nby <b>%a</b>\\nfrom <b>%l</b>" if $tip && $tip eq '1';	#for rowtip=1, deprecated
	$self->{rowtip}=$tip||'';
	$self->set_has_tooltip(!!$tip);
}

sub EditRowTip
{	my $self=shift;
	if ($self->{rowtip_edit}) { $self->{rowtip_edit}->present; return; }
	my $dialog= Gtk3::Dialog->new(_"Edit row tip", $self->get_toplevel,
		[qw/destroy-with-parent/],
		'gtk-apply' => 'apply',
		'gtk-ok' => 'ok',
		'gtk-cancel' => 'none',
	);
	::weaken( $self->{rowtip_edit}=$dialog );
	::SetWSize($dialog,'RowTip');
	$dialog->set_default_response('ok');
	my $combo= Gtk3::ComboBoxText->new_with_entry;
	my $hist= $::Options{RowTip_history} ||=[	_("Play count").' : $playcount\\n'._("Last played").' : $lastplay',
							'<b>$title</b>\\n'._('<i>by</i> %a\\n<i>from</i> %l'),
							'$title\\n$album\\n$artist\\n<small>$comment</small>',
							'$comment',
						];
	$combo->append_text($_) for @$hist;
	my $entry= $combo->get_child;
	$entry->set_text($self->{rowtip});
	$entry->set_activates_default(::TRUE);
	my $preview= Label::Preview->new(event => 'CurSong', wrap=>1, entry=>$entry, noescape=>1,
		format=>'<small><i>'._("example :")."\n\n</i></small>%s",
		preview => sub { defined $::SongID ? ::ReplaceFieldsAndEsc($::SongID,$_[0]) : $_[0]; },
		);
	$preview->set_alignment(0,.5);
	$dialog->get_content_area->pack_start($_,::FALSE,::FALSE,4) for $combo,$preview;
	$dialog->show_all;
	$dialog->signal_connect( response => sub
	 {	my ($dialog,$response)=@_;
		my $tip=$entry->get_text;
		if ($response eq 'ok' || $response eq 'apply')
		{	::PrefSaveHistory(RowTip_history=>$tip) if $tip;
			$self->SetRowTip($tip);
		}
		$dialog->destroy unless $response eq 'apply';
	 });
}

package SongList;
use Glib qw(TRUE FALSE);
use base 'Gtk3::ScrolledWindow';

our @ISA;
our %SLC_Prop;
INIT
{ unshift @ISA, 'SongList::Common';
  %SLC_Prop=
  (	#PlaycountBG => #TEST
#	{	value => sub { Songs::Get($_[2],'playcount') ? 'grey' : '#ffffff'; },
#		attrib => 'cell-background',	type => 'Glib::String',
#		#can't be updated via a event key, so not updated on its own for now, but will be updated if a playcount row is present
#	},
	# italicrow & boldrow are special 'playrow', can't be updated via a event key, a redraw is made when CurSong changed if $self->{playrow}
	italicrow =>
	{	value => sub { &_is_current_row ? ::PANGO_STYLE_ITALIC : ::PANGO_STYLE_NORMAL; },
		attrib => 'style',	type => 'Glib::Uint',
	},
	boldrow =>
	{	value => sub { &_is_current_row ? ::PANGO_WEIGHT_BOLD : ::PANGO_WEIGHT_NORMAL; },
		attrib => 'weight',	type => 'Glib::Uint',
	},

	right_aligned_folder=>
	{	menu	=> _("Folder (right-aligned)"), title => _("Folder"),
		value	=> sub { Songs::Display($_[2],'path'); },
		attrib	=> 'text', type => 'Glib::String', depend => 'path',
		sort	=> 'path',	width => 200,
		init	=> { ellipsize=>'start', },
	},
	titleaa =>
	{	menu => _('Title - Artist - Album'), title => _('Song'),
		value => sub { ::ReplaceFieldsAndEsc($_[2],"<b>%t</b>%V\n<small><i>%a</i> - %l</small>"); },
		attrib => 'markup', type => 'Glib::String', depend => 'title version artist album',
		sort => 'title:i',	noncomp => 'boldrow',		width => 200,
	},
	playandqueue =>
	{	menu => _('Playing and queue icons'),		title => '',	width => 20,
		value => sub { my $i=::Get_PPSQ_Icon($_[2], !&_is_current_row); $i && ::check_icon_name($i); },
		class => 'Gtk3::CellRendererPixbuf',	attrib => 'icon-name',
		type => 'Glib::String',			noncomp => 'boldrow italicrow',
		event => 'Playing Queue CurSong',
	},
	playandqueueandtrack =>
	{	menu => _('Play, queue or track'),	title => '#', width => 20,
		value => sub { my $ID=$_[2]; ::Get_PPSQ_Icon($ID, !&_is_current_row, 'text') || Songs::Display($ID,'track'); },
		type => 'Glib::String',			attrib	=> 'markup',	yalign => '0.5',
		event => 'Playing Queue CurSong',	sort	=> 'track',
		depend=> 'track',
	},
	icolabel =>
	{	menu => _("Labels' icons"),	title => '',		value => sub { $_[2] },
		class => 'CellRendererIconList',attrib => 'ID',	type => 'Glib::Uint',
		depend => 'label',	sort => 'label:i',	noncomp => 'boldrow italicrow',
		event => 'Icons', 		width => 50,
		init => {field => 'label'},
	},
	albumpic =>
	{	title => _("Album picture"),	width => 100,
		value => sub { CellRendererSongsAA::get_value('album',$_[0]{array},$_[1]); },
		class => 'CellRendererSongsAA',	attrib => 'ref',	type => 'Glib::Scalar',
		depend => 'album',	sort => 'album:i',	noncomp => 'boldrow italicrow',
		init => {aa => 'album'},
		event => 'Picture_album',
	},
	artistpic =>
	{	title => _("Artist picture"),
		value => sub { CellRendererSongsAA::get_value('first_artist',$_[0]{array},$_[1]); },
		class => 'CellRendererSongsAA',	attrib => 'ref',	type => 'Glib::Scalar',
		depend => 'artist',	sort => 'artist:i',	noncomp => 'boldrow italicrow',
		init => {aa => 'first_artist', markup => '<b>%a</b>'},	event => 'Picture_artist',
	},
	stars	=>
	{	title	=> _("Rating"),			menu	=> _("Rating (picture)"),
		value	=> sub { Songs::Stars( Songs::Get($_[2],'rating'),'rating'); },
		class	=> 'Gtk3::CellRendererPixbuf',	attrib	=> 'pixbuf',
		type	=> 'Gtk3::Gdk::Pixbuf',		noncomp	=> 'boldrow italicrow',
		depend	=> 'rating',			sort	=> 'rating',
	},
	rownumber=>
	{	menu => _("Row number"),	title => '#',		width => 50,
		value => sub { $_[1]+1 },
		type => 'Glib::String',		attrib	=> 'text',	init => { xalign => 1, },
	},
  );
  %{$SLC_Prop{albumpicinfo}}=%{$SLC_Prop{albumpic}};
  $SLC_Prop{albumpicinfo}{title}=_"Album picture & info";
  $SLC_Prop{albumpicinfo}{init}={aa => 'album', markup => "<b>%a</b>%Y\n<small>%s <small>%l</small></small>"};
}

sub _is_current_row # (store,row,ID)=@_
{	defined $::SongID && $_[2]==$::SongID && (!$_[0]{is_playlist} || !defined $::Position || $::Position==$_[1]);
}

our @ColumnMenu=
(	{ label => _"_Sort by",		submenu => sub { Browser::make_sort_menu($_[0]{self}) }, },
	{ label => _"_Insert column",	submenu => sub
		{	my %names=map {my $l=$SLC_Prop{$_}{menu} || $SLC_Prop{$_}{title}; defined $l ? ($_,$l) : ()} keys %SLC_Prop;
			delete $names{$_->{colid}} for $_[0]{self}->get_child->get_columns;
			return \%names;
		},	submenu_reverse =>1,
	  code	=> sub { $_[0]{self}->ToggleColumn($_[1],$_[0]{pos}); },	stockicon => 'list-add-symbolic'
	},
	{ label => sub { _('_Remove this column').' ('. ($SLC_Prop{$_[0]{pos}}{menu} || $SLC_Prop{$_[0]{pos}}{title}).')' },
	  code	=> sub { $_[0]{self}->ToggleColumn($_[0]{pos},$_[0]{pos}); },	stockicon => 'list-remove-symbolic'
	},
	{ label => _("Edit row tip").'...', code => sub { $_[0]{self}->EditRowTip; },
	},
	{ label => _"Keep list filtered and sorted",	code => sub { $_[0]{self}{array}->SetAutoUpdate( $_[0]{self}{autoupdate} ); },
	  toggleoption => 'self/autoupdate',	mode => 'B',
	},
	{ label => _"Follow playing song",	code => sub { $_[0]{self}->FollowSong if $_[0]{self}{follow}; },
	  toggleoption => 'self/follow',
	},
	{ label => _"Go to playing song",	code => sub { $_[0]{self}->FollowSong; }, },
);

our @DefaultOptions=
(	cols		=> 'playandqueue title artist album year length track file lastplay playcount rating',
	playrow 	=> 'boldrow',
	headers 	=> 'on',
	no_typeahead	=> 0,
);

sub init_textcolumns	#FIXME support calling it multiple times => remove columns for removed fields, update added columns ?
{
	for my $key (Songs::ColumnsKeys())
	{	$SLC_Prop{$key}=
		{	title	=> Songs::FieldName($key),	value	=> sub { Songs::Display($_[2],$key)},
			type	=> 'Glib::String',		attrib	=> 'text',
			sort	=> Songs::SortField($key),	width	=> Songs::FieldWidth($key),
			depend	=> join(' ',Songs::Depends($key)),
		};
		$SLC_Prop{$key}{init}{xalign}=1 if Songs::ColumnAlign($key);
	}
}

sub new
{	my ($class,$opt) = @_;

	my $self= bless Gtk3::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');
	$self->set_policy('automatic','automatic');
	::set_biscrolling($self);

	#use default options for this songlist type
	my $name= 'songlist_'.$opt->{name}; $name=~s/\d+$//;
	my $default= $::Options{"DefaultOptions_$name"} || {};

	%$opt=( @DefaultOptions, %$default, %$opt );
	$self->CommonInit($opt);
	$self->{$_}=$opt->{$_} for qw/songypad playrow/;

	my $store=SongStore->new;
	$store->set_array($self->{array});
	$store->{is_playlist}= $self->{mode} eq 'playlist';
	my $tv= Gtk3::TreeView->new($store);
	$self->add($tv);
	$self->{store}=$store;

	::set_drag($tv,
	 source	=>[::DRAG_ID,sub { my $tv=$_[0]; return ::DRAG_ID,$tv->get_parent->GetSelectedIDs; }],
	 dest	=>[::DRAG_ID,::DRAG_FILE,\&drag_received_cb],
	 motion	=> \&drag_motion_cb,
		);
	$tv->signal_connect(drag_data_delete => sub { $_[0]->signal_stop_emission_by_name('drag_data_delete'); }); #ignored

	$tv->set_rules_hint(TRUE);
	$tv->set_headers_clickable(TRUE);
	$tv->set_headers_visible(FALSE) if $opt->{headers} eq 'off';
	$tv->set('fixed-height-mode' => TRUE);
	$tv->set_enable_search(!$opt->{no_typeahead});
	$tv->set_search_equal_func(\&SongStore::search_equal_func);
	$tv->signal_connect(key_release_event => sub
		{	my ($tv,$event)=@_;
			if (Gtk3::Gdk::keyval_name( $event->keyval ) eq 'Delete')
			{	$tv->get_parent->RemoveSelected;
				return 1;
			}
			return 0;
		});
	MultiTreeView::init($tv,__PACKAGE__);
	$tv->signal_connect(cursor_changed	=> \&cursor_changed_cb);
	$tv->signal_connect(row_activated	=> \&row_activated_cb);
	$tv->get_selection->signal_connect(changed => \&sel_changed_cb);
	$tv->get_selection->set_mode('multiple');
	$tv->signal_connect(query_tooltip=> \&query_tooltip_cb);
	$self->SetRowTip($opt->{rowtip});

	# used to draw text when treeview empty
	$tv->signal_connect_after(draw => \&draw_cb);
	$tv->get_hadjustment->signal_connect_swapped(changed=> sub { my $tv=shift; $tv->queue_draw unless $tv->get_model->iter_n_children },$tv);

	$self->AddColumn($_) for split / +/,$opt->{cols};
	$self->AddColumn('title') unless $tv->get_columns; #make sure there is at least one column

	::Watch($self,	SongArray	=> \&SongArray_changed_cb);
	::Watch($self,	SongsChanged	=> \&SongsChanged_cb);
	::Watch($self,	CurSongID	=> \&CurSongChanged);
	$self->{DefaultFocus}=$tv;

	return $self;
}

sub SaveOptions
{	my $self=shift;
	my %opt;
	my $tv=$self->get_child;
	#save displayed cols
	$opt{cols}=join ' ',(map $_->{colid},$tv->get_columns);
	#save their width
	my %width;
	$width{$_}=$self->{colwidth}{$_} for keys %{$self->{colwidth}};
	$width{ $_->{colid} }=$_->get_width for $tv->get_columns;
	$opt{colwidth}= join ' ',map "$_ $width{$_}", sort keys %width;
	return \%opt;
}

sub AddColumn
{	my ($self,$colid,$pos)=@_;
	my $prop=$SLC_Prop{$colid};
	unless ($prop) {warn "Ignoring unknown column $colid\n"; return undef}
	my $renderer=	( $prop->{class} || 'Gtk3::CellRendererText' )->new;
	if (my $init=$prop->{init})
	{	$renderer->set(%$init);
	}
	$renderer->set(ypad => $self->{songypad}) if defined $self->{songypad};
	my $colnb=SongStore::get_column_number($colid);
	my $attrib=$prop->{attrib};
	my @attributes=($prop->{title},$renderer,$attrib,$colnb);
	if (my $playrow=$self->{playrow})
	{	if (my $noncomp=$prop->{noncomp}) { $playrow=undef if (grep $_ eq $playrow, split / /,$noncomp); }
		push @attributes,$SLC_Prop{$playrow}{attrib},SongStore::get_column_number($playrow) if $playrow;
		#$playrow='PlaycountBG'; #TEST
		#push @attributes,$SLC_Prop{$playrow}{attrib},SongStore::get_column_number($playrow); #TEST
	}
	my $column= Gtk3::TreeViewColumn->new_with_attributes(@attributes);

	#$renderer->set_fixed_height_from_font(1);
	$column->{colid}=$colid;
	$column->set_sizing('fixed');
	$column->set_resizable(TRUE);
	$column->set_min_width(0);
	$column->set_fixed_width( $self->{colwidth}{$colid} || $prop->{width} || 100 );
	$column->set_clickable(TRUE);
	$column->set_reorderable(TRUE);

	# sort column on click
	$column->signal_connect(clicked => sub
		{	my $self= $_[0]->get_button->GET_ancestor;
			my $s=$_[1];
			$s='-'.$s if $self->{sort} eq $s;
			$self->Sort($s);
		},$prop->{sort}) if defined $prop->{sort};
	my $tv= $self->get_child;
	if (defined $pos)	{ $tv->insert_column($column, $pos); }
	else			{ $tv->append_column($column); }
	$column->set_title($prop->{title});
	if (my $event=$prop->{event})
	{	::Watch($column,$_,\&_redraw_column) for split / /,$event; #redraw column on event
	}
	# connect col selection menu to right-click on column
	$column->get_button->signal_connect(button_press_event => sub
		{ my ($colbutton,$event,$colid)=@_;
		  return 0 unless $event->button == 3;
		  my $self= $colbutton->GET_ancestor;
		  $self->SelectColumns($colid);
		  1;
		}, $colid);
	return $column;
}

sub _redraw_column
{	my $col=$_[0];
	my $tv= $col->get_tree_view;
	$tv->queue_draw_area( $col->get_x_offset, 0,$col->get_width, $tv->get_allocated_height);
}

sub UpdateSortIndicator
{	my $self=$_[0];
	my $tv= $self->get_child;
	$_->set_sort_indicator(FALSE) for grep $_->get_sort_indicator, $tv->get_columns;
	return if $self->{no_sort_indicator};
	if ($self->{sort}=~m/^(-)?([^ ]+)$/)
	{	my $order=($1)? 'descending' : 'ascending';
		my @cols=grep( ($SLC_Prop{$_->{colid}}{sort}||'') eq $2, $tv->get_columns);
		for my $col (@cols)
		{	$col->set_sort_indicator(TRUE);
			$col->set_sort_order($order);
		}
	}
}

sub SelectColumns
{	my ($self,$pos)=@_;
	::PopupContextMenu( \@ColumnMenu, {self=>$self, 'pos' => $pos, mode=>$self->{type}, } );
}

sub ToggleColumn
{	my ($self,$colid,$colpos)=@_;
	my $tv=$self->get_child;
	my $position;
	my $n=0;
	for my $column ($tv->get_columns)
	{	if ($column->{colid} eq $colid)
		{	$self->{colwidth}{$colid}= $column->get_width;
			$tv->remove_column($column);
			undef $position;
			last;
		}
		$n++;
		$position=$n if $column->{colid} eq $colpos;
	}
	$self->AddColumn($colid,$position) if defined $position;
	$self->AddColumn('title') unless $tv->get_columns; #if removed the last column
	$self->{cols_to_watch}=undef; #to force update list of columns to watch
}

sub set_has_tooltip { $_[0]->get_child->set_has_tooltip($_[1]) }

sub draw_cb
{	my ($tv,$cr)=@_;
	if (!$tv->get_model->iter_n_children && $cr->should_draw_window($tv->get_bin_window))
	{	# draw empty text when no songs
		$tv->get_parent->DrawEmpty($cr, $tv, $tv->get_window->get_width);
	}
}

sub query_tooltip_cb
{	my ($tv, $x, $y, $keyb, $tooltip)=@_;
	return 0 if $keyb;
	my ($path, $column)=$tv->get_path_at_pos($tv->convert_widget_to_bin_window_coords($x,$y));
	return 0 unless $path;
	my ($row)=$path->get_indices;
	my $self= $tv->GET_ancestor;
	my $ID=$self->{array}[$row];
	return unless defined $ID;
	my $markup= ::ReplaceFieldsAndEsc($ID,$self->{rowtip});
	$tooltip->set_markup($markup);
	$tv->set_tooltip_row($tooltip,$path);
	1;
}

sub GetCurrentRow
{	my $self=shift;
	my $tv=$self->get_child;
	my ($path)= $tv->get_cursor;
	return unless $path;
	my $row=$path->to_string;
	return $row;
}

sub GetSelectedRows
{	my $self=shift;
	my ($paths)= $self->get_child->get_selection->get_selected_rows;
	return [map $_->to_string, @$paths];
}

sub drag_received_cb
{	my ($tv,$type,$dest,@IDs)=@_;
	$tv->signal_stop_emission_by_name('drag_data_received'); #override the default 'drag_data_received' handler on GtkTreeView
	my $self=$tv->get_parent;
	my $songarray=$self->{array};
	my (undef,$path,$pos)=@$dest;
	my $row=$path? ($path->get_indices)[0] : scalar@{$self->{array}};
	$row++ if $path && $pos && $pos eq 'after';

	if ($tv->{drag_is_source})
	{	$songarray->Move($row,$self->GetSelectedRows);
		return;
	}

	if ($type==::DRAG_FILE) #convert filenames to IDs
	{	@IDs=::FolderToIDs(1,0,map ::decode_url($_), @IDs);
		return unless @IDs;
	}
	$songarray->Insert($row,\@IDs);
}

sub drag_motion_cb
{	my ($tv,$context,$x,$y,$time)=@_;# warn "drag_motion_cb @_";
	my $self=$tv->get_parent;
	if ($self->{autoupdate}) { $context->status('default',$time); return } # refuse any drop if autoupdate is on
	::drag_checkscrolling($tv,$context,$y);
	return if $x<0 || $y<0;
	my ($path,$pos)=$tv->get_dest_row_at_pos($x,$y);
	if ($path)
	{	$pos= ($pos=~m/after$/)? 'after' : 'before';
	}
	else	#cursor is in an empty (no rows) zone #FIXME also happens when above or below treeview
	{	my $n=$tv->get_model->iter_n_children;
		$path= Gtk3::TreePath->new_from_indices($n-1) if $n; #at the end
		$pos='after';
	}
	$context->{dest}=[$tv,$path,$pos];
	$tv->set_drag_dest_row($path,$pos);
	$context->status(($tv->{drag_is_source} ? 'move' : 'copy'),$time);
	return 1;
}

sub sel_changed_cb
{	my $treesel=$_[0];
	my $group= $treesel->get_tree_view->get_parent->{group};
	::IdleDo('1_Changed'.$group,10, \&::HasChanged, 'Selection_'.$group);	#delay it, because it can be called A LOT when, for example, removing 10000 selected rows
}
sub cursor_changed_cb
{	my $tv=$_[0];
	my ($path)= $tv->get_cursor;
	return unless $path;
	my $self= $tv->get_parent;
	my $ID=$self->{array}[ $path->to_string ];
	::HasChangedSelID($self->{group},$ID);
}

sub row_activated_cb
{	my ($tv,$path,$column)=@_;
	my $self= $tv->get_parent;
	$self->Activate(1);
}

sub ResetModel
{	my $self=$_[0];
	my $tv= $self->get_child;
	$tv->set_model(undef);
	$self->{store}->set_array($self->{array});
	$tv->set_model($self->{store});
	$self->UpdateSortIndicator;

	my $ID=::GetSelID($self);
	my $songarray=$self->{array};
	if (defined $ID && $songarray->IsIn($ID))	#scroll to last selected ID if in the list
	{	my $row= ::first { $songarray->[$_]==$ID } 0..$#$songarray;
		$row= Gtk3::TreePath->new($row);
		$tv->get_selection->select_path($row);
		$tv->scroll_to_cell($row,undef,::TRUE,0,0);
	}
	else
	{	$self->Scroll_to_TopEnd();
		$self->FollowSong if $self->{follow};
	}
}

sub Scroll_to_TopEnd
{	my ($self,$end)=@_;
	my $songarray=$self->{array};
	return unless @$songarray;
	my $row= $end ? $#$songarray : 0;
	$row= Gtk3::TreePath->new($row);
	$self->get_child->scroll_to_cell($row,undef,::TRUE,0,0);
}

sub CurSongChanged
{	my $self=$_[0];
	$self->queue_draw if $self->{playrow};
	$self->FollowSong if $self->{follow};
}

sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	my $usedfields= $self->{cols_to_watch}||= do
	 {	my $tv= $self->get_child;
		my %h;
		for my $col ($tv->get_columns)
		{	if (my $d= $SLC_Prop{ $col->{colid} }{depend})
			{	$h{$_}=undef for split / /,$d;
			}
		}
		[keys %h];
	 };
	return unless ::OneInCommon($fields,$usedfields);
	if ($IDs)
	{	my $changed=$self->{array}->AreIn($IDs);
		return unless @$changed;
		#call UpdateID(@$changed) ? update individual rows or just redraw everything ?
	}
	$self->get_child->queue_draw;
}

sub SongArray_changed_cb
{	my ($self,$array,$action,@extra)=@_;
	#if ($self->{mode} eq 'playlist' && $array==$::ListPlay)
	#{	$self->{array}->Mirror($array,$action,@extra);
	#}
	return unless $self->{array}==$array;
	warn "SongArray_changed $action,@extra\n" if $::debug;
	my $tv= $self->get_child;
	my ($selected_rows,$store)= $tv->get_selection->get_selected_rows;
	my @selected= map $_->to_string, @$selected_rows;
	my $updateselection;
	if ($action eq 'sort')
	{	my ($sort,$oldarray)=@extra;
		$self->{'sort'}=$sort;
		my @order;
		$order[ $array->[$_] ]=$_ for reverse 0..$#$array; #reverse so that in case of duplicates ID, $order[$ID] is the first row with this $ID
		my @IDs= map $oldarray->[$_], @selected;
		@selected= map $order[$_]++, @IDs; # $order->[$ID]++ so that in case of duplicates ID, the next row (with same $ID) are used
		$self->ResetModel;
		#$self->UpdateSortIndicator; #not needed : already called by $self->ResetModel
		$updateselection=1;
	}
	elsif ($action eq 'update')	#should only happen when in filter mode, so no duplicates IDs
	{	my $oldarray=$extra[0];
		my @selectedID;
		$selectedID[$oldarray->[$_]]=1 for @selected;
		@selected=grep $selectedID[$array->[$_]], 0..$#$array;
		# lie to the model, just tell it that some rows were removed/inserted and refresh
		# if it cause a problem, just use $self->ResetModel; instead
		my $diff= @$array - @$oldarray;
		if	($diff>0) { $store->rowinsert(scalar @$oldarray,$diff); }
		elsif	($diff<0) { $store->rowremove([$#$array+1..$#$oldarray]); }
		$self->queue_draw;
		$updateselection=1;
	}
	elsif ($action eq 'insert')
	{	my ($destrow,$IDs)=@extra;
		#$_>=$destrow and $_+=@$IDs for @selected; #not needed as the treemodel will update the selection
		$store->rowinsert($destrow,scalar @$IDs);
	}
	elsif ($action eq 'move')
	{	my (undef,$rows,$destrow)=@extra;
		my $i= my $j= my $delta=0;
		if (@selected)
		{ for my $row (0..$selected[-1])
		  {	if ($row==$destrow+$delta) {$delta-=@$rows}
			if ($i<=$#$rows && $row==$rows->[$i]) #row moved
			{	if ($selected[$j]==$rows->[$i]) { $selected[$j]=$destrow+$i; $j++; } #row moved and selected
				$delta++; $i++;
			}
			elsif ($row==$selected[$j])	#row selected
			{ $selected[$j]-=$delta; $j++; }
		  }
		  $updateselection=1;
		}
		#$self->queue_draw; # a simple queue_draw used to be enough in gtk2, but does nothing in gtk3 (even though simply moving the mouse over the rows correctly update them) so rowremove and rowinsert are needed
		$store->rowremove($rows);
		$store->rowinsert($destrow,scalar @$rows);
	}
	elsif ($action eq 'up')
	{	my $rows=$extra[0];
		my $i=0;
		for my $row (@$rows)
		{	$i++ while $i<=$#selected && $selected[$i]<$row-1;
			last if $i>$#selected;
			if	($selected[$i]==$row-1)	{ $selected[$i]++ unless $i<=$#selected && $selected[$i+1]==$row;$updateselection=1; }
			elsif	($selected[$i]==$row)	{ $selected[$i]--;$updateselection=1; $i++ }
		}
		$self->queue_draw;
	}
	elsif ($action eq 'down')
	{	my $rows=$extra[0];
		my $i=$#selected;
		for my $row (reverse @$rows)
		{	$i-- while $i>=0 && $selected[$i]>$row+1;
			last if $i<0;
			if	($selected[$i]==$row+1)	{ $selected[$i]-- unless $i>=0 && $selected[$i-1]==$row;$updateselection=1; }
			elsif	($selected[$i]==$row)	{ $selected[$i]++;$updateselection=1; $i-- }
		}
		$self->queue_draw;
	}
	elsif ($action eq 'remove')
	{	my $rows=$extra[0];
		$store->rowremove($rows);
		$self->ResetModel if @$array==0; #don't know why, but when the list is not empty and adding/removing columns that result in a different row height; after removing all the rows, and then inserting a row, the row height is reset to the previous height. Doing a reset model when the list is empty solves this.
	}
	elsif ($action eq 'mode' || $action eq 'proxychange') {return} #the list itself hasn't changed
	else #'replace' or unknown action
	{	$self->ResetModel;		#FIXME if replace : check if a filter is in $extra[0]
		#$treesel->unselect_all;
	}
	$self->SetSelection(\@selected) if $updateselection;
	$self->Hide(!scalar @$array) if $self->{hideif} eq 'empty';
}

sub FollowSong
{	my $self=$_[0];
	my $tv= $self->get_child;
	#$tv->get_selection->unselect_all;
	my $songarray=$self->{array};
	return unless defined $::SongID;
	my $rowplaying;
	if ($self->{mode} eq 'playlist') { $rowplaying=$::Position; } #$::Position may be undef even if song is in list (random mode), in that case fallback to the usual case below
	$rowplaying= ::first { $songarray->[$_]==$::SongID } 0..$#$songarray unless defined $rowplaying && $rowplaying>=0;
	if (defined $rowplaying)
	{	my $path= Gtk3::TreePath->new($rowplaying);
		my ($first,$last)= $tv->get_visible_range;
		#check if row is visible -> no need to scroll_to_cell
		my $afterfirst= !$first || $first->to_string < $rowplaying;
		my $beforelast= !$last  || $rowplaying < $last->to_string;
		$tv->scroll_to_cell($path,undef,TRUE,.5,.5) unless $afterfirst && $beforelast;
		$tv->set_cursor($path,undef,FALSE);
	}
	elsif (defined $::SongID)	#Set the song ID even if the song isn't in the list
	{ ::HasChangedSelID($self->{group},$::SongID); }
}

sub SetSelection
{	my ($self,$select)=@_;
	my $treesel= $self->get_child->get_selection;
	$treesel->unselect_all;
	$treesel->select_path( Gtk3::TreePath->new($_) ) for @$select;
}

#sub UpdateID	#DELME ? update individual rows or just redraw everything ?
#{	my $self=$_[0];
#	my $array=$self->{array};
#	my $store=$self->get_child->get_model;
#	my %updated;
#	warn "update ID @_\n" if $::debug;
#	$updated{$_}=undef for @_;
#	my $row=@$array;
#	while ($row-->0)	#FIXME maybe only check displayed rows
#	{ my $ID=$$array[$row];
#	  next unless exists $updated{$ID};
#	  $store->rowchanged($row);
#	  #delete $updated{$ID};
#	  #last unless (keys %updated);
#	}
#}

################################################################################
package SongStore;
use Glib qw(TRUE FALSE);

my (%Columns,@Value,@Type,@Indices,@Instances);

use Glib::Object::Subclass
	Glib::Object::,
	interfaces => [Gtk3::TreeModel::],
	;

sub get_column_number
{	my $colid=$_[0];
	my $colnb=$Columns{$colid};
	unless (defined $colnb)
	{	push @Value, $SongList::SLC_Prop{$colid}{value};
		push @Type, $SongList::SLC_Prop{$colid}{type};
		$colnb= $Columns{$colid}= $#Value;
	}
	return $colnb;
}

sub set_array
{	my ($self,$array)=@_;
	$self->{array}= $array;
	$self->{size}= @$array;
	push @Indices, @Indices..@$array-1;
}

sub INIT_INSTANCE
{	my $self= $_[0];
	# int to check whether an iter belongs to our model
	$self->{stamp}= sprintf '%d',rand(1<<31); #$self & 2**32-1; #needs to be 32 bits, as 64 bits numbers make it crash
	push @Instances, $self;
	::weaken($Instances[-1]);
}
sub FINALIZE_INSTANCE
{	my $self= $_[0];
	# free all records and free all memory used by the list
	@Instances= grep $_!=$self, @Instances;
	my $max= ::max(0,map $_->{size},@Instances);
	$#Indices= $max-1 if $max<@Indices;
}
sub GET_FLAGS { [qw/list-only iters-persist/] }
sub GET_N_COLUMNS { $#Value }
sub GET_COLUMN_TYPE { $Type[ $_[1] ]; }
sub GET_ITER
{	#warn "GET_ITER @_\n";
	#warn "GET_ITER ".(++$::getiter)."\n";
	my $self=$_[0]; my $path=$_[1];
	my $n=$path->get_indices;	#return only one value because it's a list
	return FALSE,undef if $n >= $self->{size} || $n < 0;
	return TRUE, Gtk3::TreeIter->new( stamp=>$self->{stamp}, user_data=>\$Indices[$n] );
}

sub GET_PATH
{	#my ($self,$iter)= @_; #warn "GET_PATH @_\n";
	my $nref= $_[1]->user_data;
	my $path= Gtk3::TreePath->new;
	$path->append_index($$nref);
	return $path;
}

sub GET_VALUE
{	#warn "GET_VALUE @_\n";
	#my ($self,$iter)= @_;
	my $self=$_[0]; 
	my $nref=$_[1]->user_data;
	my $row= $$nref;
	my $value= $Value[$_[2]]( $self, $row, $self->{array}[$row]  );  #args : self, row, ID
	return Glib::Object::Introspection::GValueWrapper->new($Type[$_[2]], $value);
}

sub ITER_NEXT
{	#warn "ITER_NEXT @_\n";
	#warn "next ".(++$::getnext)."\n";
	#my ($self,$iter)= @_;
	my $nref=$_[1]->user_data;
	return FALSE unless $$nref < $_[0]{size}-1;
	$_[1]->user_data( \$Indices[$$nref+1] );
	return TRUE;
}

sub ITER_CHILDREN
{	my ($self, $parent) = @_; #warn "GET_CHILDREN\n";
	# this is a list, nodes have no children
	return FALSE,undef if $parent;
	# parent == NULL is a special case; we need to return the first top-level row
	# No rows => no first row
	return FALSE,undef unless $self->{size};
	# Set iter to first item in list
	return TRUE, Gtk3::TreeIter->new( stamp=>$self->{stamp}, user_data=>\$Indices[0] );
}
sub ITER_HAS_CHILD { FALSE }
sub ITER_N_CHILDREN
{	#warn "ITER_N_CHILDREN @_\n";
	my ($self,$iter)= @_;
	# special case: if iter == NULL, return number of top-level rows
	return ( $iter? 0 : $self->{size} );
}
sub ITER_NTH_CHILD
{	#warn "ITER_NTH_CHILD @_\n";
	#my ($self, $parent, $n)= @_;
	# a list has only top-level rows
	return FALSE,undef if $_[1]; #$parent;
	my $self=$_[0]; my $n=$_[2];
	# special case: if parent == NULL, set iter to n-th top-level row
	return FALSE,undef if $n >= $self->{size};
	return TRUE, Gtk3::TreeIter->new( stamp=>$self->{stamp}, user_data=>\$Indices[$n] );
}
sub ITER_PARENT { FALSE }

# REF_NODE and UNREF_NODE are not needed, but bindings complain if not there
sub REF_NODE {}
sub UNREF_NODE {}

sub search_equal_func
{	my ($self,$col,$string,$iter)=@_;
	my $nref= $iter->user_data;
	my $ID= $self->{array}[$$nref];
	#my $r; for (qw/title album artist/) { $r=index uc(Songs::Display($ID,$_)), $string; last if $r==0 } return $r;
	index uc(Songs::Display($ID,'title')), uc($string);
}

sub rowremove
{	my ($self,$rows)=@_;
	for my $row (reverse @$rows)
	{	$self->row_deleted( Gtk3::TreePath->new($row) );
		$self->{size}--;
	}
}
sub ROW_DELETED {}
sub ROW_INSERTED {}
sub rowinsert
{	my ($self,$row,$number)=@_; #warn "rowinsert $self,$row,$number\n";
	push @Indices, @Indices..$self->{size}+$number;
	for (1..$number)
	{	$self->{size}++;
		$self->row_inserted( Gtk3::TreePath->new($row), $self->get_iter_from_string($row) );
		$row++;
	}
}
#sub rowchanged	#not used anymore
#{	my $self=$_[0]; my $row=$_[1];
#	my $iter=$self->get_iter_from_string($row);
#	return unless $iter;
#	$self->row_changed( $self->get_path($iter), $iter);
#}

package MultiTreeView;
#for common functions needed to support correct multi-rows drag and drop in treeviews

sub init
{	my ($tv,$selfpkg)=@_;
	$tv->{selfpkg}=$selfpkg;
	$tv->{drag_begin_cb}=\&drag_begin_cb;
	$tv->signal_connect(button_press_event=> \&button_press_cb);
	$tv->signal_connect(button_release_event=> \&button_release_cb);
}

sub drag_begin_cb
{	my ($tv,$context)=@_;# warn "drag_begin @_";
	$tv->{pressed}=undef;
}

sub button_press_cb
{	my ($tv,$event)=@_;
	return 0 if $event->get_window!=$tv->get_bin_window; #ignore click outside the bin_window (for example the column headers) #not sure still needed
	my $self= $tv->GET_ancestor( $tv->{selfpkg} );
	my $but=$event->button;
	my $sel=$tv->get_selection;
	if ($but!=1 && $event->type eq '2button-press')
	{	$self->Activate($but);
		return 1;
	}
	my $ctrl_shift=  $event->get_state * ['shift-mask', 'control-mask'];
	if ($but==1) # do not clear multi-row selection if button press on a selected row (to allow dragging selected rows)
	{{	 last if $ctrl_shift; #don't interfere with default if control or shift is pressed
		 last unless $sel->count_selected_rows  > 1;
		 my ($path)= $tv->get_path_at_pos($event->get_coords);
		 last unless $path && $sel->path_is_selected($path);
		 $tv->{pressed}=1;
		 return 1;
	}}
	if ($but==3)
	{	my ($path)= $tv->get_path_at_pos($event->get_coords);
		if ($path && !$sel->path_is_selected($path))
		{	$sel->unselect_all unless $ctrl_shift;
			#$sel->select_path($path);
			$tv->set_cursor($path,undef,::FALSE);
		}
		$self->PopupContextMenu;
		return 1;
	}
	return 0; #let the event propagate
}

sub button_release_cb #clear selection and select current row only if the press event was on a selected row and there was no dragging
{	my ($tv,$event)=@_;
	return 0 unless $event->button==1 && $tv->{pressed};
	$tv->{pressed}=undef;
	my ($path)= $tv->get_path_at_pos($event->get_coords);
	return 0 unless $path;
	my $sel=$tv->get_selection;
	$sel->unselect_all;
	$sel->select_path($path);
	return 1;
}

package FilterPane;
use base 'Gtk3::Box';

use constant { TRUE  => 1, FALSE => 0, };

our %Pages=
(	filter	=> [SavedTree		=> 'F',			'i', _"Filter"	],
	list	=> [SavedTree		=> 'L',			'i', _"List"	],
	savedtree=>[SavedTree		=> 'FL',		'i', _"Saved"	],
	folder	=> [FolderList		=> 'path',		'n', _"Folder"	],
	filesys	=> [Filesystem		=> '',			'',_"Filesystem"],
);

our @MenuMarkupOptions=
(	"%a",
	"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",
	"<b>%a</b>%Y\n<small>%b</small>",
	"<b>%a</b>%Y\n<small>%b</small>\n<small>%s <small>%l</small></small>",
	"<b>%y %a</b>",
);
my @picsize_menu=
(	_("no pictures")	=>  0,
	_("automatic size")	=> -1,
	_("small size")		=> 16,
	_("medium size")	=> 32,
	_("big size")		=> 64,
);
my @mpicsize_menu=
(	_("small size")		=> 32,
	_("medium size")	=> 64,
	_("big size")		=> 96,
	_("huge size")		=> 128,
);
my @cloudstats_menu=
(	_("number of songs")	=> 'count',
	_("rating average")	=> 'rating:average',
	_("play count average")	=> 'playcount:average',
	_("skip count average")	=> 'skipcount:average',
),

my %sort_menu=
(	year => _("year"),
	year2=> _("year (highest)"),
	alpha=> _("alphabetical"),
	songs=> _("number of songs in filter"),
	'length'=> _("length of songs"),
);
my %sort_menu_album=
(	%sort_menu,
	artist => _("artist")
);
my @sort_menu_append=
(	{separator=>1},
	{ label=> _"reverse order", check=> sub { $_[0]{self}{'sort'}[$_[0]{depth}]=~m/^-/ },
	  code=> sub { my $self=$_[0]{self}; $self->{'sort'}[$_[0]{depth}]=~s/^(-)?/$1 ? "" : "-"/e; $self->SetOption; }
	},
);

our @MenuPageOptions;
my @MenuSubGroup=
(	{ label => sub {_("Set subgroup").' '.$_[0]{depth}},	submenu => sub { return {0 => _"None",map {$_=>Songs::FieldName($_)} Songs::FilterListFields()}; },
	  first_key=> "0",	submenu_reverse => 1,
	  code	=> sub { $_[0]{self}->SetField($_[1],$_[0]{depth}) },
	  check	=> sub { $_[0]{self}{field}[$_[0]{depth}] ||0 },
	},
	{ label => sub {_("Options for subgroup").' '.$_[0]{depth}},	submenu => \@MenuPageOptions,
	  test  => sub { $_[0]{depth} <= $_[0]{self}{depth} },
	},
);

@MenuPageOptions=
(	{ label => _"show pictures",	code => sub { my $self=$_[0]{self}; $self->{lpicsize}[$_[0]{depth}]=$_[1]; $self->SetOption; },	mode => 'LS',
	  submenu => \@picsize_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{lpicsize}[$_[0]{depth}]},
		test => sub { Songs::FilterListProp($_[0]{subfield},'picture'); }, },
	{ label => _"text format",	code => sub { my $self=$_[0]{self}; $self->{lmarkup}[$_[0]{depth}]= $_[1]; $self->SetOption; },
	  submenu => sub{	my $field= $_[0]{self}{type}[ $_[0]{depth} ];
		  		my $gid= Songs::Get_gid($::SongID,$field); $gid=$gid->[0] if ref $gid;
				return unless $gid;	# option not shown if no current song, FIXME could try to find a song in the library
		  		return [ map { AA::ReplaceFields( $gid,$_,$field,::TRUE ), ($_ eq "%a" ? 0 : $_) } @MenuMarkupOptions ];
	  		},	submenu_ordered_hash => 1, submenu_use_markup => 1,
	  check => sub { $_[0]{self}{lmarkup}[$_[0]{depth}]}, istrue => 'aa', mode => 'LS', },
	{ label => _"text mode",	code => sub { $_[0]{self}->SetOption(mmarkup=>$_[1]); },
	  submenu => [ 0 => _"None", below => _"Below", right => _"Right side", ], submenu_ordered_hash => 1, submenu_reverse => 1,
	  check => 'self/mmarkup', mode => 'M', },
	{ label => _"picture size",	code => sub { $_[0]{self}->SetOption(mpicsize=>$_[1]);  },
	  mode => 'M',
	  submenu => \@mpicsize_menu,	submenu_ordered_hash => 1,  check => 'self/mpicsize', istrue => 'aa' },

	{ label => _"font size depends on",	code => sub { $_[0]{self}->SetOption(cloud_stat=>$_[1]); },
	  mode => 'C',
	  submenu => \@cloudstats_menu,	submenu_ordered_hash => 1,  check => 'self/cloud_stat', },
	{ label => _"minimum font size", code => sub { $_[0]{self}->SetOption(cloud_min=>$_[1]); },
	  mode => 'C',
	  submenu => sub { [2..::min(20,$_[0]{self}{cloud_max}-1)] },  check => 'self/cloud_min', },
	{ label => _"maximum font size", code => sub { $_[0]{self}->SetOption(cloud_max=>$_[1]); },
	  mode => 'C',
	  submenu => sub { [::max(10,$_[0]{self}{cloud_min}+1)..40] },  check => 'self/cloud_max', },

	{ label => _"sort by",		code => sub { my $self=$_[0]{self}; $self->{'sort'}[$_[0]{depth}]=$_[1]; $self->SetOption; },
	  check => sub {$_[0]{self}{sort}[$_[0]{depth}]}, submenu =>  sub { $_[0]{field} eq 'album' ? \%sort_menu_album : \%sort_menu; },
	  submenu_reverse => 1,		append => \@sort_menu_append,
	},
	{ label => _"group by",
	  code	=> sub { my $self=$_[0]{self}; my $d=$_[0]{depth}; $self->{type}[$d]=$self->{field}[$d].'.'.$_[1]; $self->Fill('rehash'); },
	  check => sub { my $n=$_[0]{self}{type}[$_[0]{depth}]; $n=~s#^[^.]+\.##; $n },
	  submenu=>sub { Songs::LookupCode( $_[0]{self}{field}[$_[0]{depth}], 'subtypes_menu' ); }, submenu_reverse => 1,
	  #test => sub { $FilterList::Field{ $_[0]{self}{field}[$_[0]{depth}] }{types}; },
	},
	{ repeat => sub { map [\@MenuSubGroup, depth=>$_, mode => 'S', subfield => $_[0]{self}{field}[$_], ], 1..$_[0]{self}{depth}+1; },	mode => 'L',
	},
	{ label => _"cloud mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'cloud' ? 'list' : 'cloud'),1); },
	  check => sub {$_[0]{mode} eq 'C'},	notmode => 'S', },
	{ label => _"mosaic mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'mosaic' ? 'list' : 'mosaic'),1);},
	  check => sub {$_[0]{mode} eq 'M'},	notmode => 'S',
	  test => sub { Songs::FilterListProp($_[0]{field},'picture') },
	},
	{ label => _"show the 'All' row",	code => sub { $_[0]{self}->SetOption; },  toggleoption => '!self/noall', mode => 'L',
	},
	{ label => _"show histogram background",code => sub { $_[0]{self}->SetOption; },  toggleoption => 'self/histogram', mode => 'L',
	},
	{ label => _"ignore the 'none' row for histogram",code => sub { $_[0]{self}->SetOption; },  toggleoption => 'self/histogram_ignore_none',  mode => 'L', sensitive=>sub{ $_[0]{self}{histogram} }, test=>sub { Songs::FilterListProp($_[0]{field},'multi'), },
	},
);

our @cMenu=
(	{ label=> _"Play",	code => sub { ::Select(filter=>$_[0]{filter},song=>'first',play=>1); },
		isdefined => 'filter',	stockicon => 'media-playback-start-symbolic',	id => 'play'
	},
	{ label=> _"Append to playlist",	code => sub { ::DoActionForList('addplay',$_[0]{filter}->filter); },
		isdefined => 'filter',	stockicon => 'list-add-symbolic',	id => 'addplay',
	},
	{ label=> _"Enqueue",	code => sub { ::EnqueueFilter($_[0]{filter}); },
		isdefined => 'filter',	stockicon => 'format-indent-more-symbolic',	id => 'enqueue',
	},
	{ label=> _"Set as primary filter",
		code => sub {my $fp=$_[0]{filterpane}; ::SetFilter( $_[0]{self}, $_[0]{filter}, 1, $fp->{group} ); },
		test => sub {my $fp=$_[0]{filterpane}; $fp->{nb}>1 && $_[0]{filter};}
	},
	#songs submenu :
	{	label	=> sub { my $IDs=$_[0]{filter}->filter; ::__n("%d song","%d songs",scalar @$IDs); },
		submenu => sub { ::BuildMenuOptional(\@::SongCMenu, { mode => 'F', IDs=>$_[0]{filter}->filter }); },
		isdefined => 'filter',
	},
	{ label=> _"Rename folder", code => sub { ::AskRenameFolder($_[0]{rawpathlist}[0]); }, onlyone => 'rawpathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Open folder", code => sub { ::openfolder( $_[0]{rawpathlist}[0] ); }, onlyone => 'rawpathlist', },
	#{ label=> _"move folder", code => sub { ::MoveFolder($_[0]{pathlist}[0]); }, onlyone => 'pathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Scan for new songs", code => sub { ::IdleScan( @{$_[0]{rawpathlist}} ); },
		notempty => 'rawpathlist' },
	{ label=> _"Check for updated/removed songs", code => sub { ::IdleCheck(  @{ $_[0]{filter}->filter } ); },
		isdefined => 'filter', stockicon => 'view-refresh-symbolic', istrue => 'pathlist' }, #doesn't really need pathlist, but makes less sense for non-folder pages
	{ label=> _"Set Picture",	stockicon => 'folder-pictures-symbolic',
		code => sub { my $gid=$_[0]{gidlist}[0]; ::ChooseAAPicture(undef,$_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { Songs::FilterListProp($_[0]{field},'picture') && $_[0]{gidlist}[0]>0; },
	},
	{ label => _"Auto-select Pictures",	code => sub { ::AutoSelPictures( $_[0]{field}, @{ $_[0]{gidlist} } ); },
		onlymany=> 'gidlist',	test => sub { $_[0]{field} eq 'album' }, #test => sub { Songs::FilterListProp($_[0]{field},'picture'); },
		stockicon => 'folder-pictures-symbolic',
	},
	{ label=> _"Set icon",		stockicon => 'folder-pictures-symbolic',
		code => sub { my $gid=$_[0]{gidlist}[0]; Songs::ChooseIcon($_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { Songs::FilterListProp($_[0]{field},'icon') && $_[0]{gidlist}[0]>0; },
	},
	{ label=> _"Remove label",	stockicon => 'list-remove-symbolic',
		code => sub { my $gid=$_[0]{gidlist}[0]; ::RemoveLabel($_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { $_[0]{field} eq 'label' && $_[0]{gidlist}[0] !=0 },	#FIXME make it generic rather than specific to field label ? #FIXME find a better way to check if gid is special than comparing it to 0
	},
	{ label=> _"Rename label",
		code => sub { my $gid=$_[0]{gidlist}[0]; ::RenameLabel($_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { $_[0]{field} eq 'label' && $_[0]{gidlist}[0] !=0 },	#FIXME make it generic rather than specific to field label ? #FIXME find a better way to check if gid is special than comparing it to 0
	},
#	{ separator=>1 },
	# only 1 option for folderview so don't put it in option menu
	{ label => _"Simplify tree", code => sub { $_[0]{self}->SetOption(simplify=>$_[1]); },
	  submenu => [ never=>_"Never", smart=>_"Only whole levels", always=>_"Always" ],
	  submenu_ordered_hash => 1, submenu_reverse => 1,
	  check => 'self/simplify',  istrue=>'folderview',
	},
	{ label => _"Options", submenu => \@MenuPageOptions, stock => 'emblem-system-symbolic', isdefined => 'field' },
	{ label => _"Show buttons",	toggleoption => '!filterpane/hidebb',	code => sub { my $fp=$_[0]{filterpane}; $fp->{bottom_buttons}->set_visible(!$fp->{hidebb}); }, },
	{ label => _"Show tabs",	toggleoption => '!filterpane/hidetabs',	code => sub { my $fp=$_[0]{filterpane}; $fp->{notebook}->set_show_tabs( !$fp->{hidetabs} ); }, },
);

our @DefaultOptions=
(	pages	=> 'savedtree|artists|album|genre|date|label|folder|added|lastplay|rating',
	nb	=> 1,	# filter level
	min	=> 1,	# filter out entries with less than $min songs
	hidebb	=> 0,	# hide button box
	tabmode	=> 'text', # text, icon or both
	hscrollbar=>1,
);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::VBox->new(FALSE, 6), $class;
	$self->{SaveOptions}=\&SaveOptions;
	%$opt=( @DefaultOptions, %$opt );
	my @pids=split /\|/, $opt->{pages};
	$self->{$_}=$opt->{$_} for qw/nb group min hidetabs tabmode/, grep(m/^activate\d?$/, keys %$opt);
	$self->{main_opt}{$_}=$opt->{$_} for qw/group no_typeahead searchbox rules_hint hscrollbar/; #options passed to children
	my $nb=$self->{nb};
	my $group=$self->{group};

	my $spin= Gtk3::SpinButton->new( Gtk3::Adjustment->new($self->{min}, 1, 9999, 1, 10, 0) ,10,0  );
	$spin->signal_connect( value_changed => sub { $self->update_children($_[0]->get_value); } );
	my $ResetB=::NewIconButton('edit-clear-symbolic',undef,sub { ::SetFilter($_[0],undef,$nb,$group); });
	$ResetB->set_sensitive(0);
	my $InterB= Gtk3::ToggleButton->new;
	my $InterBL=Gtk3::Label->new;
	$InterBL->set_markup('<b>&amp;</b>');  #bold '&'
	$InterB->add($InterBL);
	my $InvertB= Gtk3::ToggleButton->new;
	my $optB= Gtk3::Button->new;
	$InvertB->add(Gtk3::Image->new_from_stock('media-playlist-repeat-symbolic','menu'));
	$optB->add(Gtk3::Image->new_from_stock('view-list-symbolic','menu'));
	$InvertB->signal_connect( toggled => sub {$self->{invert}=$_[0]->get_active;} );
	$InterB->signal_connect(  toggled => sub {$self->{inter} =$_[0]->get_active;} );
	$optB->signal_connect( button_press_event => \&PopupOpt );
	$optB->set_relief('none');
	my $hbox= Gtk3::HBox->new(FALSE, 6);
	$hbox->pack_start($_, FALSE, FALSE, 0) for $spin, $ResetB, $InvertB, $InterB, $optB;
	$ResetB ->set_tooltip_text(	(	$nb==1? _"reset primary filter"  :
						$nb==2?	_"reset secondary filter":
							::__x(_"reset filter {nb}",nb =>$nb)
					) );
	$InterB ->set_tooltip_text(_"toggle Intersection mode");
	$InvertB->set_tooltip_text(_"toggle Invert mode");
	$spin   ->set_tooltip_text(_"only show entries with at least n songs"); #FIXME
	$optB   ->set_tooltip_text(_"options");

	my $notebook= Gtk3::Notebook->new;
	$notebook->set_scrollable(TRUE);
	if (my $tabpos=$opt->{tabpos})
	{	($tabpos,$self->{angle})= $tabpos=~m/^(left|right|top|bottom)?(90|180|270)?/;
		$notebook->set_tab_pos($tabpos) if $tabpos;
	}
	#$notebook->popup_enable;
	$self->{hidetabs}= (@pids==1) unless defined $self->{hidetabs};
	$notebook->set_show_tabs( !$self->{hidetabs} );
	$self->{notebook}=$notebook;

	my $setpage;
	for my $pid (@pids)
	{	my $n=$self->AppendPage($pid,$opt->{'page_'.$pid});
		if ($opt->{page} && $opt->{page} eq $pid) { $setpage=$n }
	}
	$self->AppendPage('album') if $notebook->get_n_pages == 0;	# fallback in case no pages has been added

	$self->pack_end($hbox, FALSE, FALSE, 0);
	$notebook->show_all; #needed to set page in this sub

	$hbox->show_all;
	$_->set_no_show_all(1) for $hbox,$spin,$InterB,$optB;
	$self->{bottom_buttons}=$hbox;
	$notebook->signal_connect( button_press_event => \&button_press_event_cb);
	$notebook->signal_connect( switch_page => sub
	 {	my $p=$_[0]->get_nth_page($_[2]);
		my $self= $_[0]->GET_ancestor;
		$self->{DefaultFocus}=$p;
		my $pid= $self->{page}= $p->{pid};
		my $mask=	$Pages{$pid} ? 				$Pages{$pid}[2] :
				Songs::FilterListProp($pid,'multi') ?	'oni' : 'on';
		$optB->set_visible  ( scalar $mask=~m/o/ );
		$spin->set_visible  ( scalar $mask=~m/n/ );
		$InterB->set_visible( scalar $mask=~m/i/ );
	 });

	$self->add($notebook);
	$notebook->set_current_page( $setpage||0 );

	$self->{hidebb}=$opt->{hidebb};
	$hbox->hide if $self->{hidebb};
	$self->{resetbutton}=$ResetB;
	::Watch($self, Icons => \&icons_changed);
	::Watch($self, SongsChanged=> \&SongsChanged_cb);
	::Watch($self, SongsAdded  => \&SongsAdded_cb);
	::Watch($self, SongsRemoved=> \&SongsRemoved_cb);
	::Watch($self, SongsHidden => \&SongsRemoved_cb);
	$self->signal_connect(destroy => \&cleanup);
	$self->{needupdate}=1;
	::WatchFilter($self,$opt->{group},\&updatefilter);
	::IdleDo('9_FPfull'.$self,100,\&updatefilter,$self);
	return $self;
}

sub SaveOptions
{	my $self=shift;
	my @opt=
	(	hidebb	=> $self->{hidebb},
		min	=> $self->{min},
		page	=> $self->{page},
		hidetabs=> $self->{hidetabs},
		pages	=> (join '|', map $_->{pid}, $self->{notebook}->get_children),
	);
	for my $page (grep $_->can('SaveOptions'), $self->{notebook}->get_children)
	{	my %pageopt=$page->SaveOptions;
		push @opt, 'page_'.$page->{pid}, { %pageopt } if keys %pageopt;
	}
	return \@opt;
}

sub AppendPage
{	my ($self,$pid,$opt)=@_;
	my ($package,$col,$label);
	if ($Pages{$pid})
	{	($package,$col,undef,$label)=@{ $Pages{$pid} };
	}
	elsif ( grep $_ eq $pid, Songs::FilterListFields() )
	{	$package='FilterList';
		$col=$pid;
		$label=Songs::FieldName($col);
	}
	else {return}
	$opt||={};
	my %opt=( %{$self->{main_opt}}, %$opt);
	my $page=$package->new($col,\%opt); #create new page
	$page->{pid}=$pid;
	$page->{page_name}=$label;
	if ($package eq 'FilterList' || $package eq 'FolderList')
	{	$page->{Depend_on_field}=$col;
	}
	my $notebook=$self->{notebook};
	my $n=$notebook->append_page( $page, $self->create_tab($page) );
	$notebook->set_tab_reorderable($page,TRUE);
	$page->show_all;
	return $n;
}
sub create_tab
{	my ($self,$page)=@_;
	my $pid=$page->{pid};
	my $img;
	my $angle= $self->{angle} || 0;
	my $label= Gtk3::Label->new( $page->{page_name} );
	$label->set_angle($angle) if $angle;

	# set base gravity to auto so that rotated tabs handle vertical scripts (asian languages) better
	$label->get_pango_context->set_base_gravity('auto');

	if ($self->{tabmode} ne 'text')
	{	my $icon= "gmb-tab-$pid";
		$img= Gtk3::Image->new_from_stock($icon,'menu');
		$label=undef if $img && $self->{tabmode} eq 'icon';
	}
	my $tab;
	if ($img && $label)
	{	$tab= $angle%180 ? Gtk3::VBox->new(FALSE,0) : Gtk3::HBox->new(FALSE,0);
		my @pack= $angle%180 ? ($label,TRUE,$img,FALSE) : ($img,FALSE,$label,TRUE);
		$tab->pack_start( $pack[$_], $pack[$_+1],$pack[$_+1],0 ) for 0,2;
	}
	else { $tab= $img || $label; }
	$tab->show_all;
	return $tab;
}
sub icons_changed	# 2TO3 is it needed ?
{	my $self=shift;
	if ($self->{tabmode} ne 'text')
	{	my $notebook=$self->{notebook};
		for my $page ($notebook->get_children)
		{	$notebook->set_tab_label( $page, $self->create_tab($page) );
		}
	}
}
sub RemovePage_cb
{	my $self=$_[1];
	my $nb=$self->{notebook};
	my $n=$nb->get_current_page;
	my $page=$nb->get_nth_page($n);
	my $pid=$page->{pid};
	my $col;
	if ($Pages{$pid}) { $col=$Pages{$pid}[1] if $Pages{$pid}[0] eq 'FolderList'; }
	else { $col=$pid; }
	$nb->remove_page($n);
}

sub button_press_event_cb
{	my ($nb,$event)=@_;
	return 0 if $event->button != 3;
	return 0 unless ::IsEventInNotebookTabs($nb,$event);  #to make right-click on tab arrows work
	my $self= $nb->GET_ancestor;
	my $menu= Gtk3::Menu->new;
	my $cb=sub { $nb->set_current_page($_[1]); };
	my %pages;
	$pages{$_}= $Pages{$_}[3] for keys %Pages;
	$pages{$_}= Songs::FieldName($_) for Songs::FilterListFields;
	for my $page ($nb->get_children)
	{	my $pid=$page->{pid};
		my $name=delete $pages{$pid};
		my $item= Gtk3::MenuItem->new_with_label($name);
		$item->signal_connect(activate=>$cb,$nb->page_num($page));
		$menu->append($item);
	}
	$menu->append(Gtk3::SeparatorMenuItem->new);

	if (keys %pages)
	{	my $new= Gtk3::ImageMenuItem->new(_"Add tab");
		$new->set_image( Gtk3::Image->new_from_stock('tab-new-symbolic','menu') );
		my $submenu= Gtk3::Menu->new;
		for my $pid (sort {$pages{$a} cmp $pages{$b}} keys %pages)
		{	my $item= Gtk3::ImageMenuItem->new_with_label($pages{$pid});
			$item->set_image( Gtk3::Image->new_from_stock("gmb-tab-$pid",'menu') );
			$item->signal_connect(activate=> sub { my $n=$self->AppendPage($pid); $self->{notebook}->set_current_page($n) });
			$submenu->append($item);
		}
		$menu->append($new);
		$new->set_submenu($submenu);
	}
	if ($nb->get_n_pages>1)
	{	my $item= Gtk3::ImageMenuItem->new(_"Remove this tab");
		$item->set_image( Gtk3::Image->new_from_stock('list-remove-symbolic','menu') );
		$item->signal_connect(activate=> \&RemovePage_cb,$self);
		$menu->append($item);
	}
	#::PopupContextMenu(\@MenuTabbedL, { self=>$self, list=>$listname, pagenb=>$pagenb, page=>$page, pagetype=>$page->{tabbed_page_type} } );
	::PopupMenu($menu,event=>$event,nomenupos=>1);
	return 1;
}

sub SongsAdded_cb
{	my ($self,$IDs)=@_;
	return if $self->{needupdate};
	if ( $self->{filter}->added_are_in($IDs) )
	{	$self->{needupdate}=1;
		::IdleDo('9_FPfull'.$self,5000,\&updatefilter,$self);
	}
}

sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	return if $self->{needupdate};
	if ( $self->{filter}->changes_may_affect($IDs,$fields) )
	{	$self->{needupdate}=1;
		::IdleDo('9_FPfull'.$self,5000,\&updatefilter,$self);
	}
	else
	{	for my $page ( $self->get_field_pages )
		{	next unless $page->{valid} && $page->{hash};
			my @depends= Songs::Depends( $page->{Depend_on_field} );
			next unless ::OneInCommon(\@depends,$fields);
			$page->{valid}=0;
			$page->{hash}=undef;
			::IdleDo('9_FP'.$self,1000,\&refresh_current_page,$self) if $page->get_mapped;
		}
	}
}
sub SongsRemoved_cb
{	my ($self,$IDs)=@_;
	return if $self->{needupdate};
	my $list=$self->{list};
	my $changed=1;
	if ($list!=$::Library)					#CHECKME use $::Library or a copy ?
	{	my $isin='';
		vec($isin,$_,1)=1 for @$IDs;
		my $before=@$list;
		@$list=grep !vec($isin,$_,1), @$list;
		$changed=0 if $before==@$list;
	}
	$self->invalidate_children if $changed;
}

sub updatefilter
{	my ($self,undef,$nb)=@_;
	my $mynb=$self->{nb};
	return if $nb && $nb> $mynb;

	delete $::ToDo{'9_FPfull'.$self};
	my $force=delete $self->{needupdate};
	warn "Filtering list for FilterPane$mynb\n" if $::debug;
	my $group=$self->{group};
	my $currentf=$::Filters{$group}[$mynb+1];
	$self->{resetbutton}->set_sensitive( !Filter::is_empty($currentf) );
	my $filt=Filter->newadd(TRUE, map($::Filters{$group}[$_+1],0..($mynb-1)) );
	return if !$force && $self->{list} && Filter::are_equal($filt,$self->{filter});
	$self->{filter}=$filt;

	my $lref=$filt->is_empty ? $::Library			#CHECKME use $::Library or a copy ?
				 : $filt->filter;
	$self->{list}=$lref;

	#warn "filter :".$filt->{string}.($filt->{source}?  " with source" : '')." songs=".scalar(@$lref)."\n";
	$self->invalidate_children;
}

sub invalidate_children
{	my $self=shift;
	for my $page ( $self->get_field_pages )
	{	$page->{valid}=0;
		$page->{hash}=undef;
	}
	::IdleDo('9_FP'.$self,1000,\&refresh_current_page,$self);
}
sub update_children
{	my ($self,$min)=@_;
	$self->{min}=$min;
	if (!$self->{list} || $self->{needupdate}) { $self->updatefilter; return; }
	warn "Updating FilterPane".$self->{nb}."\n" if $::debug;
	for my $page ( $self->get_field_pages )
	{	$page->{valid}=0;		# set dirty flag for this page
	}
	$self->refresh_current_page;
}
sub refresh_current_page
{	my $self=shift;
	delete $::ToDo{'9_FP'.$self};
	my ($current)=grep $_->get_mapped, $self->get_field_pages;
	if ($current) { $current->Fill }	# update now if page is displayed
}
sub get_field_pages
{	grep $_->{Depend_on_field}, $_[0]->{notebook}->get_children;
}

sub cleanup
{	my $self=shift;
	delete $::ToDo{'9_FP'.$self};
	delete $::ToDo{'9_FPfull'.$self};
}

sub Activate
{	my ($page,$button,$filter)=@_;
	my $self= $page->GET_ancestor;
	$button||=1;
	my $action= $self->{"activate$button"} || $self->{activate} || ($button==2 ? 'queue' : 'play');
	my $aftercmd;
	$aftercmd=$1 if $action=~s/&(.*)$//;
	::DoActionForFilter($action,$filter);
	::run_command($self,$aftercmd) if $aftercmd;
}

sub PopupContextMenu
{	my ($page,$hash,$menu)=@_;
	my $self= $page->GET_ancestor;
	$hash->{filterpane}=$self;
	$menu||=\@cMenu;
	::PopupContextMenu($menu, $hash);
}

sub PopupOpt	#Only for FilterList #FIXME should be moved in FilterList::, and/or use a common function with FilterList::PopupContextMenu
{	my $self= $_[0]->GET_ancestor;
	my $nb=$self->{notebook};
	my $page=$nb->get_nth_page( $nb->get_current_page );
	my $field=$page->{field}[0];
	my $mainfield=Songs::MainField($field);
	my $aa= ($mainfield eq 'artist' || $mainfield eq 'album') ? $mainfield : undef; #FIXME
	my $mode= uc(substr $page->{mode},0,1); # C => cloud, M => mosaic, L => list
	::PopupContextMenu(\@MenuPageOptions, { self=>$page, aa=>$aa, field => $field, mode => $mode, subfield => $field, depth =>0, usemenupos => 1,} );
	return 1;
}

package FilterList;
use base 'Gtk3::Box';
use constant { GID_ALL => 2**31-1, GID_TYPE => 'Glib::Long' };

our %defaults=
(	mode	=> 'list',
	type	=> '',
	lmarkup	=> 0,
	lpicsize=> 0,
	'sort'	=> 'default',
	depth	=> 0,
	noall	=> 0,
	histogram=>0,
	histogram_ignore_none=>0,
	mmarkup => 0,
	mpicsize=> 64,
	cloud_min=> 5,
	cloud_max=> 20,
	cloud_stat=> 'count',
);

sub new
{	my ($class,$field,$opt)=@_;
	my $self= bless Gtk3::VBox->new, $class;

	$opt= { %defaults, %$opt };
	$self->{$_} = $opt->{$_} for qw/mode noall histogram histogram_ignore_none depth mmarkup mpicsize cloud_min cloud_max cloud_stat no_typeahead rules_hint hscrollbar/;
	$self->{$_} = [ split /\|/, $opt->{$_} ] for qw/sort type lmarkup lpicsize/;

	$self->{type}[0] ||= $field.'.'.(Songs::FilterListProp($field,'type')||''); $self->{type}[0]=~s/\.$//;	#FIXME
	::Watch($self, Picture_artist => \&AAPicture_Changed);	#FIXME PHASE1
	::Watch($self, Picture_album => \&AAPicture_Changed);	#FIXME PHASE1

	for my $d (0..$self->{depth})
	{	my ($field)= $self->{type}[$d] =~ m#^([^.]+)#;
		$self->{field}[$d]=$field;
		$self->{icons}[$d]= Songs::FilterListProp($field,'icon') ? $::IconSize{menu} : 0;
	}

	#search box
	if ($opt->{searchbox} && Songs::FilterListProp($field,'search'))
	{	$self->pack_start( make_searchbox() ,::FALSE,::FALSE,1);
	}
	::Watch($self,'SearchText_'.$opt->{group},\&set_text_search);

	#interactive search box
	$self->{isearchbox}=GMB::ISearchBox->new($opt,$self->{type}[0],'nolabel');
	$self->pack_end( $self->{isearchbox} ,::FALSE,::FALSE,1);
	$self->signal_connect(key_press_event => \&key_press_cb); #only used for isearchbox
	$self->signal_connect(map => \&Fill);

	$self->set_mode($self->{mode});
	return $self;
}

sub SaveOptions
{	my $self=$_[0];
	my %opt;
	$opt{$_} = join '|', @{$self->{$_}} for qw/type lmarkup lpicsize sort/;
	$opt{$_} = $self->{$_} for qw/mode noall histogram histogram_ignore_none depth mmarkup mpicsize cloud_min cloud_max cloud_stat/;
	for (keys %opt) { delete $opt{$_} if $opt{$_} eq $defaults{$_}; }	#remove options equal to default value
	delete $opt{type} if $opt{type} eq $self->{pid};			#remove unneeded type options
	return %opt, $self->{isearchbox}->SaveOptions;
}

sub SetField
{	my ($self,$field,$depth)=@_;
	$self->{field}[$depth]=$field;
	my $type=Songs::FilterListProp($field,'type');
	$self->{type}[$depth]= $type ? $field.'.'.$type : $field;
	$self->{lpicsize}[$depth]||=0;
	$self->{lmarkup}[$depth]||=0;
	$self->{'sort'}[$depth]||='default';
	$self->{icons}[$depth]||= Songs::FilterListProp($field,'icon') ? $::IconSize{menu} : 0;

	my $i=0;
	$i++ while $self->{field}[$i];
	$self->{depth}=$i-1;

	$self->Fill('optchanged');
}

sub SetOption
{	my ($self,$key,$value)=@_;
	$self->{$key}=$value if $key;
	$self->Fill('optchanged');
}

sub set_mode
{	my ($self,$mode,$fillnow)=@_;
	for my $child ($self->get_children)
	{	$self->remove($child) if $child->{is_a_view};
	}

	my ($child,$view)= 	$mode eq 'cloud' ? $self->create_cloud	:
				$mode eq 'mosaic'? $self->create_mosaic :
				$self->create_list;
	$self->{view}=$view;
	$self->{DefaultFocus}=$view;
	$child->{is_a_view}=1;
	$view->signal_connect(focus_in_event	=> sub { my $self= $_[0]->GET_ancestor; $self->{isearchbox}->parent_has_focus; 0; });	#hide isearchbox when focus goes to the view

	my $drag_type=	Songs::FilterListProp( $self->{field}[0], 'drag') || ::DRAG_FILTER;
	::set_drag( $view, source => [$drag_type,\&drag_cb]);
	MultiTreeView::init($view,__PACKAGE__) if $mode eq 'list'; #should be in create_list but must be done after set_drag

	$child->show_all;
	$self->add($child);
	$self->{valid}=0;
	$self->Fill if $fillnow;
}

sub create_list
{	my $self=$_[0];
	$self->{mode}='list';
	my $field=$self->{field}[0];
	my $sw= Gtk3::ScrolledWindow->new;
#	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);

	my $store= Gtk3::TreeStore->new(GID_TYPE);
	my $treeview= Gtk3::TreeView->new($store);
	$treeview->set_rules_hint(1) if $self->{rules_hint};
	$sw->add($treeview);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_search_column(-1);	#disable gtk interactive search, use my own instead
	$treeview->set_enable_search(::FALSE);
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	my $renderer= CellRendererGID->new;
	my $column= Gtk3::TreeViewColumn->new_with_attributes('',$renderer);

	$renderer->set(prop => [@$self{qw/type lmarkup lpicsize icons hscrollbar/}]);	#=> $renderer->get('prop')->[0] contains $self->{type} (which is a array ref)
	#$column->add_attribute($renderer, gid => 0);
	$column->set_cell_data_func($renderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $gid=$store->get($iter,0);
			my $depth=$store->iter_depth($iter);
			$cell->set( gid=>$gid, depth=>$depth);# 'is-expander'=> $depth < $store->{depth});
		});
	$treeview->append_column($column);
	$treeview->signal_connect(row_expanded  => \&row_expanded_cb);
	#$treeview->signal_connect(row_collapsed => sub { my $store=$_[0]->get_model;my $iter=$_[1]; while (my $iter=$store->iter_nth_child($iter,1)) { $store->remove($iter) } });

	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect(changed =>\&selection_changed_cb);

	$treeview->signal_connect( row_activated => sub { Activate($_[0],1); });
	return $sw,$treeview;
}

sub Activate
{	my ($view,$button)=@_;
	my $self= $view->GET_ancestor;
	my $filter= $self->get_selected_filters;
	return unless $filter; #nothing selected
	FilterPane::Activate($self,$button,$filter);
}

sub create_cloud
{	my $self=$_[0];
	$self->{mode}='cloud';
	my $sw= Gtk3::ScrolledWindow->new;
	$sw->set_policy('never','automatic');
	my $sub=Songs::DisplayFromGID_sub($self->{type}[0]);
	my $cloud= GMB::Cloud->new2(\&child_selection_changed_cb,\&get_fill_data, \&Activate,\&PopupContextMenu,$sub);
	$sw->add($cloud);
	return $sw,$cloud;
}
sub create_mosaic
{	my $self=$_[0];
	$self->{mode}='mosaic';
	$self->{mpicsize}||=64;
	my $hbox= Gtk3::HBox->new(0,0);
	my $vscroll= Gtk3::VScrollbar->new;
	$hbox->pack_end($vscroll,0,0,0);
	my $mosaic= GMB::Mosaic->new(\&child_selection_changed_cb,\&get_fill_data,\&Activate,\&PopupContextMenu,$self->{type}[0],$vscroll);
	$hbox->add($mosaic);
	return $hbox,$mosaic;
}

sub get_cursor_row
{	my $self=$_[0];
	if ($self->{mode} eq 'list')
	{	my ($path)=$self->{view}->get_cursor;
		return $path ? $path->to_string : undef;
	}
	else { return $self->{view}->get_cursor_row; }
}
sub set_cursor_to_row
{	my ($self,$row)=@_;
	if ($self->{mode} eq 'list')
	{	$self->{view}->set_cursor(Gtk3::TreePath->new_from_indices($row),undef,::FALSE);
	}
	else { $self->{view}->set_cursor_to_row($row); }
}

sub make_searchbox
{	my $entry= Gtk3::Entry->new;	#FIXME tooltip
	my $clear=::NewIconButton('edit-clear-symbolic',undef,sub { $_[0]->{entry}->set_text(''); },'none' );	#FIXME tooltip
	$clear->{entry}=$entry;
	my $hbox= Gtk3::HBox->new(0,0);
	$hbox->pack_end($clear,0,0,0);
	$hbox->pack_start($entry,1,1,0);
	$entry->signal_connect(changed =>
		sub {	::IdleDo('6_UpdateSearch'.$entry,300,sub
				{	my $entry=$_[0];
					my $self= $entry->GET_ancestor;
					my $s=$entry->get_text;
					$self->set_text_search( $entry->get_text, 0,0 )
				},$_[0]);
		    });
	$entry->signal_connect(activate =>
		sub {	::DoTask('6_UpdateSearch'.$entry);
		    });
	return $hbox;
}
sub set_text_search
{	my ($self,$search,$is_regexp,$is_casesens)=@_;
	return if defined $self->{search} && $self->{search} eq $search
		&& !($self->{search_is_regexp}   xor $is_regexp)
		&& !($self->{search_is_casesens} xor $is_casesens);
	$self->{search}=$search;
	$self->{search_is_regexp}= $is_regexp||0;
	$self->{search_is_casesens}= $is_casesens||0;
	$self->{valid}=0;
	$self->Fill if $self->get_mapped;
}

sub AAPicture_Changed
{	my ($self,$key)=@_;
	return if $self->{mode} eq 'cloud';
	return unless $self->{valid} && $self->{hash} && $self->{hash}{$key} && $self->{hash}{$key} >= $self->GET_ancestor('FilterPane')->{min};
	$self->queue_draw;
}

sub selection_changed_cb
{	my $treesel=$_[0];
	child_selection_changed_cb($treesel->get_tree_view);
}

sub child_selection_changed_cb
{	my $child=$_[0];
	my $self= $child->GET_ancestor;
	return if $self->{busy};
	my $filter=$self->get_selected_filters;
	return unless $filter;
	my $filterpane= $self->GET_ancestor('FilterPane');
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub get_selected_filters
{	my $self= $_[0]->GET_ancestor;
	my @filters;
	my $types=$self->{type};
	if ($self->{mode} eq 'list')
	{	my $sel=$self->{view}->get_selection;
		my ($rows,$store)= $sel->get_selected_rows;
		for my $path (@$rows)
		{	my $iter=$store->get_iter($path);
			if ($store->get_value($iter,0)==GID_ALL) { return Filter->new; }
			my @parents= $iter;
			unshift @parents,$iter while $iter=$store->iter_parent($iter);
			next if grep $sel->iter_is_selected($parents[$_]), 0..$#parents-1;#skip if one parent is selected
			my @f=map Songs::MakeFilterFromGID( $types->[$_], $store->get_value($parents[$_],0)), 0..$#parents;
			push @filters,Filter->newadd(1, @f);
		}
	}
	else
	{	my $vals=$self->get_selected;
		@filters=map Songs::MakeFilterFromGID($types->[0],$_), @$vals;
	}
	return undef unless @filters;
	my $field=$self->{field}[0];
	my $filterpane= $self->GET_ancestor('FilterPane');
	my $i= $filterpane->{inter} && Songs::FilterListProp($field,'multi');
	my $filter=Filter->newadd($i,@filters);
	$filter->invert if $filterpane->{invert};
	return $filter;
}
sub get_selected	#not called for list => only called for cloud or mosaic
{	return [$_[0]->{view}->get_selected];
}

sub get_selected_list
{	my $self=$_[0];
	my $field=$self->{field}[0];
	my @vals;
	if ($self->{mode} eq 'list') #only returns selected rows if they are all at the same depth
	{{	my ($rows,$store)= $self->{view}->get_selection->get_selected_rows;
		my @iters= map $store->get_iter($_), @$rows;
		last unless @iters;
		if ($store->get_value($iters[0],0)==GID_ALL)	# assumes "All row" first iter
		{	my $iter= $store->get_iter_first;	# this iter is "All row" -> not added
			# "all row" is selected, replace iters list by list of all iters of first depth
			@iters=();
			push @iters,$iter while $iter=$store->iter_next($iter);
			last unless @iters;
		}
		my $depth=$store->iter_depth($iters[0]);
		last if grep $depth != $store->iter_depth($_), @iters;
		@vals=map $store->get_value($_,0) , @iters;
		$field=$self->{field}[$depth];
	}}
	else { @vals=$self->{view}->get_selected }
	return $field,\@vals;
}

sub drag_cb
{	my $self= $_[0]->GET_ancestor;
	my $field=$self->{field}[0];
	if (my $drag=Songs::FilterListProp($field,'drag'))	#return artist or album gids
	{	if ($self->{mode} eq 'list')
		{	my ($rows,$store)= $self->{view}->get_selection->get_selected_rows;
			unless (grep $_->get_depth>1, @$rows)
			{	my @gids=map $store->get_value($store->get_iter($_),0), @$rows;
				warn "dnd : gids=@gids\n";
				if (grep $_==GID_ALL, @gids) {return ::DRAG_FILTER,'';}	#there is an "all-row"
				return $drag,@gids;
			}
			#else : rows of depth>0 selected => fallback to get_selected_filters
		}
	}
	my $filter=$self->get_selected_filters;
	return ($filter? (::DRAG_FILTER,$filter->{string}) : undef);
}

sub row_expanded_cb
{	my ($treeview,$piter,$path)=@_;
	my $self= $treeview->GET_ancestor;
	my $filterpane= $self->GET_ancestor('FilterPane');
	my $store=$treeview->get_model;
	my $depth=$store->iter_depth($piter);
	my @filters;
	for (my $iter=$piter; $iter; $iter=$store->iter_parent($iter) )
	{	push @filters, Songs::MakeFilterFromGID($self->{type}[$store->iter_depth($iter)], $store->get($iter,0));
	}
	my $list=$filterpane->{list};
	$list= Filter->newadd(1,@filters)->filter($list);
	my $type=$self->{type}[$depth+1];
	my $h=Songs::BuildHash($type,$list,'gid');
	my $children=AA::SortKeys($type,[keys %$h],$self->{'sort'}[$depth+1]);
	for my $i (0..$#$children)
	{	my $iter= $store->iter_nth_child($piter,$i) || $store->append($piter);
		$store->set($iter,0,$children->[$i]);
	}
	while (my $iter=$store->iter_nth_child($piter,$#$children+1)) { $store->remove($iter) }

	if ($depth<$self->{depth}-1)	#make sure every child has a child if $depth not the deepest
	{	for (my $iter=$store->iter_children($piter); $iter; $iter=$store->iter_next($iter) )
		{	$store->append($iter) unless $store->iter_children($iter);
		}
	}
}

sub get_fill_data
{	my ($child,$opt)=@_;
	my $self= $child->GET_ancestor;
	my $filterpane= $self->GET_ancestor('FilterPane');
	my $type=$self->{type}[0];
	$self->{hash}=undef if $opt && $opt eq 'rehash';
	my $href= $self->{hash} ||= Songs::BuildHash($type,$filterpane->{list},'gid');
	$self->{valid}=1;
	$self->{all_count}= keys %$href;	#used to display how many artists/album/... there is in this filter
	my $min=$filterpane->{min};
	my $search=$self->{search};
	my @list;
	if ($min>1)
	{	@list=grep $$href{$_} >= $min, keys %$href;
	}
	else { @list=keys %$href; }
	if (defined $search && $search ne '')
	{	@list= @{ AA::GrepKeys($type,$search,$self->{search_is_regexp},$self->{search_is_casesens},\@list) };
	}
	AA::SortKeys($type,\@list,$self->{'sort'}[0]);

	my $always_first= Songs::Field_property($type,'always_first_gid');
	if (defined $always_first)	#special gid that should always appear first
	{	my $before=@list;
		@list= grep $_!=$always_first, @list;
		unshift @list,$always_first if $before!=@list;
	}

	$self->{array}=\@list; #used for interactive search

	if ($self->{mode} eq 'cloud' && $self->{cloud_stat} ne 'count')	#FIXME update cloud when used fields change
	{	$href=Songs::BuildHash($type,$filterpane->{list},'gid',$self->{cloud_stat});
	}

	return \@list,$href;
}

sub Fill
{	warn "filling @_\n" if $::debug;
	my ($self,$opt)=@_;
	$opt=undef unless $opt && ($opt eq 'optchanged' || $opt eq 'rehash');
	return if $self->{valid} && !$opt;
	if ($self->{mode} eq 'list')
	{	my $treeview=$self->{view};
		$treeview->set('show-expanders', ($self->{depth}>0) );
		my $store=$treeview->get_model;
		my $col=$self->{col};
		my ($renderer)=($treeview->get_columns)[0]->get_cells;
		$renderer->reset;
		$self->{busy}=1;
		$store->clear;	#FIXME keep selection ?   FIXME at least when opt is true (ie lmarkup or lpicsize changed)
		my ($list,$href)=$self->get_fill_data($opt);
		$renderer->set('all_count', $self->{all_count});
		my $max=0;
		if ($self->{histogram})
		{	$max= ::max( $self->{histogram_ignore_none} ? (map $href->{$_}, grep $_!=0, keys %$href)
								    : values %$href);
		}
		$renderer->set( hash=>$href, max=> $max, ignore_none=>$self->{histogram_ignore_none} );
		$self->{array_offset}= $self->{noall} ? 0 : 1;	#row number difference between store and $list, needed by interactive search
		$store->set($store->prepend(undef),0,$_) for reverse @$list;	# prepend because filling is a bit faster in reverse
		$store->set($store->prepend(undef),0,GID_ALL) unless $self->{noall};

		if ($self->{field}[1]) # add a children to every row
		{	my $first=$store->get_iter_first;
			$first=$store->iter_next($first) if $first && $store->get($first,0)==GID_ALL; #skip "all" row
			for (my $iter=$first; $iter; $iter=$store->iter_next($iter))
			{	$store->append($iter);
			}
		}
		$self->{busy}=undef;
	}
	else
	{	$self->{view}->reset_selection unless $opt;
		$self->{view}->Fill($opt);
	}
}

sub PopupContextMenu
{	my $self= $_[0]->GET_ancestor;
	my ($field,$gidlist)=$self->get_selected_list;
	my $mainfield=Songs::MainField($field);
	my $aa= ($mainfield eq 'artist' || $mainfield eq 'album') ? $mainfield : undef; #FIXME
	my $mode= uc(substr $self->{mode},0,1); # C => cloud, M => mosaic, L => list
	FilterPane::PopupContextMenu($self,{ self=> $self, filter => $self->get_selected_filters, field => $field, aa => $aa, gidlist =>$gidlist, mode => $mode, subfield => $field, depth =>0 });
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	my $unicode= Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	my $shift=$state * ['shift-mask'];
	if	(lc$key eq 'f' && $ctrl) { $self->{isearchbox}->begin(); }	#ctrl-f : search
	elsif	(lc$key eq 'g' && $ctrl) { $self->{isearchbox}->search($shift ? -1 : 1);}	#ctrl-g : next/prev match
	elsif	($key eq 'F3' && !$mod)	 { $self->{isearchbox}->search($shift ? -1 : 1);}	#F3 : next/prev match
	elsif	(!$self->{no_typeahead} && $unicode && $unicode!=32 && !$mod)
	{	$self->{isearchbox}->begin( chr $unicode );	#begin typeahead search
	}
	else	{return 0}
	return 1;
}

package FolderList;
use base 'Gtk3::ScrolledWindow';
use constant { IsExpanded=>1, HasSongs=>2 };

sub new
{	my ($class,$col,$opt)=@_;
	my $self= bless Gtk3::ScrolledWindow->new, $class;
	#$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store= Gtk3::TreeStore->new('Glib::String');
	my $treeview= Gtk3::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_search_equal_func(\&search_equal_func);
	$treeview->set_enable_search(!$opt->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(row_expanded  => \&row_expanded_changed_cb);
	$treeview->signal_connect(row_collapsed => \&row_expanded_changed_cb);
	$treeview->{expanded}={};
	my $renderer= Gtk3::CellRendererText->new;
	$store->{displayfunc}= Songs::DisplayFromHash_sub('path');
	my $column= Gtk3::TreeViewColumn->new_with_attributes(Songs::FieldName($col),$renderer);
	$column->set_cell_data_func($renderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $folder=::decode_url($store->get($iter,0));
			$cell->set( text=> $store->{displayfunc}->($folder));
		});
	$treeview->append_column($column);
	$self->add($treeview);
	$self->{treeview}=$treeview;
	$self->{DefaultFocus}=$treeview;

	$self->signal_connect(map => \&Fill);

	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect (changed =>\&selection_changed_cb);
	::set_drag($treeview, source => [::DRAG_FILTER,sub
	    {	my @paths=_get_path_selection( $_[0] );
		return undef unless @paths;
		my $filter=_MakeFolderFilter(@paths);
		return ::DRAG_FILTER,($filter? $filter->{string} : undef);
	    }]);
	MultiTreeView::init($treeview,__PACKAGE__);

	$self->{simplify}= $opt->{simplify} || 'smart';

	return $self;
}
sub SaveOptions
{	return simplify => $_[0]{simplify};
}

sub search_equal_func
{	#my ($store,$col,$string,$iter)=@_;
	my $store=$_[0];
	my $folder= $store->{displayfunc}( ::decode_url($store->get($_[3],0)) );
	#use ::superlc instead of uc ?
	my $string=uc $_[2];
	index uc($folder), $string;
}

sub SetOption
{	my ($self,$key,$value)=@_;
	$self->{$key}=$value if $key;
	$self->{valid}=0;
	delete $self->{hash};
	$self->Fill;
}
sub Fill
{	warn "filling @_\n" if $::debug;
	my $self=$_[0];
	return if $self->{valid};
	my $treeview=$self->{treeview};
	my $filterpane= $self->GET_ancestor('FilterPane');
	my $href=$self->{hash}||= BuildTreeRef($filterpane->{list},$treeview->{expanded},$self->{simplify});
	my $min=$filterpane->{min};
	my $store=$treeview->get_model;
	$self->{busy}=1;
	$store->clear;	#FIXME keep selection

	#fill the store
	my @toadd; my @toexpand;
	push @toadd,$href->{$_},$_,undef  for sort grep $href->{$_}[0]>=$min, keys %$href;
	while (my ($ref,$name,$iter)=splice @toadd,0,3)
	{	my $iter=$store->append($iter);
		$store->set($iter,0, Songs::filename_escape($name));
		push @toexpand,$store->get_path($iter) if ($ref->[2]||0) & IsExpanded;
		if ($ref->[1]) #sub-folders
		{ push @toadd, $ref->[1]{$_},$_,$iter  for sort grep $ref->[1]{$_}[0]>=$min, keys %{$ref->[1]}; }
	}

	# expand tree to first fork
	if (my $iter=$store->get_iter_first)
	{	$iter=$store->iter_children($iter) while $store->iter_n_children($iter)==1;
		$treeview->expand_to_path( $store->get_path($iter) );
	}
	#expand previously expanded rows
	$treeview->expand_row($_,::FALSE) for @toexpand;

	$self->{busy}=undef;
	$self->{valid}=1;
}

sub BuildTreeRef
{	my ($IDs,$expanded,$simplify)=@_;
	my $h= Songs::BuildHash('path',$IDs);
	my @hier;
	# build structure : each folder is [nb_of_songs,children_hash,flags]
	# children_hash: {child_foldername}= arrayref_of_subfolder
	# flags: IsExpanded HasSongs
	while (my ($f,$n)=each %$h)
	{	my $ref=\@hier;
		$ref=$ref->[1]{$_}||=[] and $ref->[0]+=$n   for split /$::QSLASH/o,$f;
		$ref->[2]|= HasSongs;
	}
	# restore expanded state
	for my $dir (keys %$expanded)
	{	my $ref=\@hier; my $notfound;
		$ref=$ref->[1]{$_} or $notfound=1, last  for split /$::QSLASH/o,$dir;
		if ($notfound)	{delete $expanded->{$dir}}
		else	{ $ref->[2]|= IsExpanded; }
	}
	# simplify tree by fusing folders with their sub-folder, if without songs and only one sub-folder
	if ($simplify ne 'never')
	{	my @tosimp= (\@hier);
		while (@tosimp)
		{	my $parent=shift @tosimp;
			my (@tofuse,@nofuse);
			while (my ($path,$ref)=each %{$parent->[1]})
			{	my @child= keys %{$ref->[1]};
				# if only one child and no songs of its own
				if (@child==1 && !(($ref->[2]||0) & HasSongs)) { push @tofuse,$path; }
				else { push @nofuse,$path }
			}
			# 'smart' mode: only simplify if all siblings can be simplified
			if ($simplify eq 'smart' && @nofuse) { push @nofuse,@tofuse; @tofuse=(); }
			push @tosimp, map $parent->[1]{$_}, @nofuse;
			for my $path (@tofuse)
			{	my $ref= $parent->[1]{$path};
				my @child= keys %{$ref->[1]};
				unless (@child==1 && !(($ref->[2]||0) & HasSongs)) { push @tosimp,$ref; next }
				delete $parent->[1]{$path};
				$path.= ::SLASH.$child[0];
				$parent->[1]{$path}= delete $ref->[1]{$child[0]};
				redo; #fuse until more than one child or songs of its own
			}
		}
	}
	$hier[1]{::SLASH}=delete $hier[1]{''} if exists $hier[1]{''};
	return $hier[1];
}

sub row_expanded_changed_cb	#keep track of which rows are expanded
{	my ($treeview,$iter,$path)=@_;
	my $self= $treeview->GET_ancestor;
	return if $self->{busy};
	my $expanded=$treeview->row_expanded($path);
	$path= ::decode_url(_treepath_to_foldername($treeview->get_model,$path));
	my $ref=[undef,$self->{hash}];
	$ref=$ref->[1]{($_ eq '' ? ::SLASH : $_)}  for split /$::QSLASH/o,$path;
	if ($expanded)
	{	$ref->[2]|= IsExpanded;			#for when reusing the hash
		$treeview->{expanded}{$path}=undef;	#for when reconstructing the hash
	}
	else
	{	$ref->[2]&=~ IsExpanded if $ref->[2]; # remove IsExpanded flag
		delete $treeview->{expanded}{$path};
	}
}

sub selection_changed_cb
{	my $treesel=$_[0];
	my $self= $treesel->get_tree_view->GET_ancestor;
	return if $self->{busy};
	my @paths=_get_path_selection( $self->{treeview} );
	return unless @paths;
	my $filter=_MakeFolderFilter(@paths);
	my $filterpane= $self->GET_ancestor('FilterPane');
	$filter->invert if $filterpane->{invert};
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub _MakeFolderFilter
{	return Filter->newadd(::FALSE,map( "path:i:$_", @_ ));
}

sub Activate
{	my ($self,$button)=@_;
	my @paths=_get_path_selection( $self->{treeview} );
	my $filter= _MakeFolderFilter(@paths);
	FilterPane::Activate($self,$button,$filter);
}
sub PopupContextMenu
{	my $self=shift;
	my $tv=$self->{treeview};
	my @paths=_get_path_selection($tv);
	my @raw= map ::decode_url($_), @paths;
	FilterPane::PopupContextMenu($self,{self=>$self, rawpathlist=> \@raw, pathlist => \@paths, filter => _MakeFolderFilter(@paths), folderview=>1, });
}

sub _get_path_selection
{	my $treeview=$_[0];
	my ($paths,$store)= $treeview->get_selection->get_selected_rows;
	return () unless $paths; #if no selection
	return map _treepath_to_foldername($store,$_), @$paths;
}
sub _treepath_to_foldername
{	my $store=$_[0]; my $tp=$_[1];
	my @folders;
	my $iter=$store->get_iter($tp);
	while ($iter)
	{	unshift @folders, $store->get_value($iter,0);
		$iter=$store->iter_parent($iter);
	}
	$folders[0]='' if $folders[0] eq ::SLASH;
	return join(::SLASH,@folders);
}

package Filesystem;  #FIXME lots of common code with FolderList => merge it
use base 'Gtk3::ScrolledWindow';

sub new
{	my ($class,$col,$opt)=@_;
	my $self= bless Gtk3::ScrolledWindow->new, $class;
	#$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store= Gtk3::TreeStore->new('Glib::String','Glib::Uint');
	my $treeview= Gtk3::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_enable_search(!$opt->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(test_expand_row  => \&row_expand_cb);
	my $renderer= Gtk3::CellRendererText->new;
	my $column= Gtk3::TreeViewColumn->new_with_attributes('',$renderer);
	$column->set_cell_data_func($renderer, \&cell_data_func_cb);
	$treeview->append_column($column);

	$self->add($treeview);
	$self->{treeview}=$treeview;
	$self->{DefaultFocus}=$treeview;

	$self->signal_connect(map => \&Fill);

	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect (changed =>\&selection_changed_cb);
	# drag and drop doesn't work with filter using a special source, which is the case here
#	::set_drag($treeview, source => [::DRAG_FILTER,sub
#	    {	my @paths=_get_path_selection( $_[0] );
#		return undef unless @paths;
#		my $filter=_MakeFolderFilter(@paths);
#		return ::DRAG_FILTER,($filter? $filter->{string} : undef);
#	    }]);
	::set_drag($treeview, source => [::DRAG_ID,sub
	    {	my @paths=_get_path_selection( $_[0] );
		return undef unless @paths;
		my $filter=_MakeFolderFilter(@paths);
		return undef unless $filter;
		my @list= @{$filter->filter};
		::SortList(\@list);
		return ::DRAG_ID,@list;
	    }]);
	MultiTreeView::init($treeview,__PACKAGE__);
	return $self;
}

sub Fill
{	warn "filling @_\n" if $::debug;
	my $self=$_[0];
	return if $self->{valid};
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $iter=$store->append(undef);
	my $root= ::SLASH;
	$root='C:' if $^O eq 'MSWin32'; #FIXME Win32 find a way to list the drives
	$store->set($iter,0, ::url_escape($root));
	my $treepath= $store->get_path($iter);
	 #expand to home dir
	for my $folder (split /$::QSLASH/o, ::url_escape(Glib::get_home_dir))
	{	next if $folder eq '';
		$self->refresh_path($treepath,1);
		$iter=$store->iter_children($iter);
		while ($iter)
		{	last if $folder eq $store->get($iter,0);
			$iter=$store->iter_next($iter);
			$treepath=$store->get_path($iter);
		}
		last unless $iter;
	}
	$self->refresh_path($treepath,1);
	$treeview->expand_to_path($treepath);
	$self->{valid}=1;
}

sub cell_data_func_cb
{	my ($tvcolumn,$cell,$store,$iter)=@_;
	my $folder=::decode_url($store->get($iter,0));
	$cell->set( text=> ::filename_to_utf8displayname($folder) );
	my $treeview= $tvcolumn->get_tree_view;
	Glib::Timeout->add(10,\&idle_load,$treeview) unless $treeview->{queued_load};
	push @{$treeview->{queued_load}}, $store->get_path($iter);
}
sub idle_load
{	my $treeview=shift;
	my $queue=$treeview->{queued_load};
	return 0 unless $queue;
	my ($first,$last)= $treeview->get_visible_range;
	unless ($first && $last) { @$queue=(); return 0 }
	while (my $path=shift @$queue)
	{	next unless $path->compare($first)>=0 && $path->compare($last)<=0; # ignore if out of view
		my $self= $treeview->GET_ancestor;
		my $partial=$self->refresh_path($path);
		if ($partial) { unshift @$queue,$path; return 1 }
		last if Gtk3::events_pending;
	}
	return 1 if @$queue;
	delete $treeview->{queued_load};
	return 0;
}

sub row_expand_cb
{	my ($treeview,$iter,$path)=@_;
	my $self= $treeview->GET_ancestor;
	$self->refresh_path($path,1);
	return !$treeview->get_model->iter_children($iter);
}

sub refresh_path
{	my ($self,$path,$force)=@_;
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $parent=$store->get_iter($path);
	my $folder=_treepath_to_foldername($store,$path);
	return 0 unless $folder;
	$folder= ::decode_url($folder);
	my @subfolders;
	my $full= $force || $treeview->row_expanded($path);
	my $continue;
	if ($self->{in_progress})
	{	if ($full || $self->{in_progress}{folder} ne $folder) { delete $self->{in_progress}; }
		else {$continue=1}
	}
	my $dh; my $lastmodif;
	if (!$continue) # check folder is there and if treeview up-to-date
	{	my $ok=opendir $dh,$folder;
		unless ($ok) { $store->remove($parent) unless -d $folder; return 0; }
		$lastmodif= (stat $dh)[9] || 1;# ||1 to ùake sure it isn't 0, as 0 means not read
		my $lastrefresh=$store->get($parent,1);
		return 0 if $lastmodif==$lastrefresh && !$force;
	}
	if ($full)
	{	@subfolders= grep !m#^\.# && -d $folder.::SLASH.$_, readdir $dh;
		close $dh;
	}
	else # the content of the folder will be search for subfolders in chunks (-d can sometimes be slow)
	{	my $progress= $self->{in_progress} ||= { list=>[], found=>[], lastmodif=>$lastmodif, folder=>$folder };
		my $list=  $progress->{list};
		my $found= $progress->{found};
		if (!$continue)
		{	@$list= grep !m#^\.#, readdir $dh;
			close $dh;
		}
		while (@$list)
		{	return 1 if Gtk3::events_pending; # continue later
			my $dir=shift @$list;
			push @$found,$dir if -d $folder.::SLASH.$dir;
		}
		@subfolders=@$found;
		$lastmodif= $progress->{lastmodif};
		delete $self->{in_progress};
	}
	# got the list of subfolders, update the treeview
	$store->set($parent,1,$lastmodif);
	my $iter=$store->iter_children($parent);
	NEXTDIR: for my $dir (sort @subfolders)
	{	$dir= ::url_escape($dir);
		while ($iter)
		{	my $c= $dir cmp $store->get($iter,0);
			unless ($c) { $iter=$store->iter_next($iter); next NEXTDIR; } #folder already there
			last if $c<0;
			# there should be no subfolders before => remove them
			my $iter2=$store->iter_next($iter);
			$store->remove($iter);
			$iter=$iter2;
		}
		# add subfolder
		my $iter2=$store->insert_before($parent,$iter);
		$store->set($iter2,0,$dir,1,0);
		my $dummy=$store->insert_after($iter2,undef);
		$store->set($dummy,0,"",1,0); #add dummy child
	}
	while ($iter) #no more subfolders => remove any trailing folders
	{	my $iter2=$store->iter_next($iter);
		$store->remove($iter);
		$iter=$iter2;
	}
	return 0;
}

sub selection_changed_cb
{	my $treesel=$_[0];
	my $self= $treesel->get_tree_view->GET_ancestor;
	#return if $self->{busy};
	my @paths=_get_path_selection( $self->{treeview} );
	return unless @paths;
	my $filter=_MakeFolderFilter(@paths);
	my $filterpane= $self->GET_ancestor('FilterPane');
	#$filter->invert if $filterpane->{invert};
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub _MakeFolderFilter
{	my @paths= map ::decode_url($_), @_;
	my @list= ::FolderToIDs(0,0,@paths);
	my $filter= Filter->new('',\@list); #FIXME use a filter on path rather than a list ?
	return $filter;
}

sub Activate
{	my ($self,$button)=@_;
	my @paths=_get_path_selection( $self->{treeview} );
	my $filter= _MakeFolderFilter(@paths);
	FilterPane::Activate($self,$button,$filter);
}
sub PopupContextMenu
{	my $self=$_[0];
	my $tv=$self->{treeview};
	my @paths=_get_path_selection($tv);
	my @raw= map ::decode_url($_), @paths;
	FilterPane::PopupContextMenu($self,{self=>$self, rawpathlist=> \@raw, pathlist => \@paths, filter => _MakeFolderFilter(@paths) });
}

sub _get_path_selection
{	my $treeview=$_[0];
	my ($paths,$store)= $treeview->get_selection->get_selected_rows;
	return () unless $paths; #if no selection
	return map _treepath_to_foldername($store,$_), @$paths;
}
sub _treepath_to_foldername
{	my $store=$_[0]; my $tp=$_[1];
	my @folders;
	my $iter=$store->get_iter($tp);
	while ($iter)
	{	unshift @folders, $store->get_value($iter,0);
		$iter=$store->iter_parent($iter);
	}
	if ($^O eq 'MSWin32') { $folders[0].=::SLASH if @folders==1 }
	else { $folders[0]='' if @folders>1; }
	return join(::SLASH,@folders);
}

package SavedTree;
use base 'Gtk3::Box';

use constant { TRUE  => 1, FALSE => 0, COL_name=>0, COL_type=>1, COL_icon=>2, COL_extra=>3, COL_editable=>4 };

our @cMenu; our %Modes;
INIT
{ @cMenu=
  (	{ label => _"New filter",	code => sub { ::EditFilter($_[0]{self},undef,''); },	stockicon => 'list-add-symbolic' },
	{ label => _"Edit filter",	code => sub { ::EditFilter($_[0]{self},undef,$_[0]{names}[0]); },
		mode => 'F',	onlyone => 'names' },
	{ label => _"Remove filter",	code => sub { ::SaveFilter($_[0]{names}[0],undef); },
		mode => 'F',	onlyone => 'names',	stockicon => 'list-remove-symbolic' },
	{ label => _"Save current filter as",	code => sub { ::EditFilter($_[0]{self},$_[0]{curfilter},''); },
		 stockicon => 'document-save-as-symbolic',	isdefined => 'curfilter',	test => sub { ! $_[0]{curfilter}->is_empty; } },
	{ label => _"Save current list as",	code => sub { $_[0]{self}->CreateNewFL('L',[@{ $_[0]{songlist}{array} }]); },
		stockicon => 'document-save-as-symbolic',	isdefined => 'songlist' },
	{ label => _("Edit list").'...',	code => sub { ::WEditList( $_[0]{names}[0] ); },
		mode => 'L',	onlyone => 'names' },
	{ label => _"Remove list",	code => sub { ::SaveList($_[0]{names}[0],undef); },
		stockicon => 'list-remove-symbolic',	mode => 'L', onlyone => 'names', },
	{ label => _"Rename",	code => sub { my $tv=$_[0]{self}{treeview}; $tv->set_cursor($_[0]{treepaths}[0],$tv->get_column(0),TRUE); },
		notempty => 'names',	onlyone => 'treepaths' },
	{ label => _("Import list").'...',	code => sub { ::Choose_and_import_playlist_files($_[0]{self}); }, mode => 'L', },
  );

  %Modes=
  (	F => [_"Saved filters",	'sfilter',	'SavedFilters',	\&UpdateSavedFilters,	'view-list-symbolic'	,\&::SaveFilter, 'filter000'],
	L => [_"Saved lists",	'slist',	'SavedLists',	\&UpdateSavedLists,	'view-list-symbolic'	,\&::SaveList, 'list000'],
	P => [_"Playing",	'play',		undef,		\&UpdatePlayingFilters,	'media-playback-start-symbolic'	],
  );
}

sub new
{	my ($class,$mode,$opt)=@_;
	my $self= bless Gtk3::VBox->new(FALSE,4), $class;
	my $store= Gtk3::TreeStore->new(('Glib::String')x4,'Glib::Boolean');
	$self->{treeview}= my $treeview= Gtk3::TreeView->new($store);
	$self->{DefaultFocus}=$treeview;
	$treeview->set_headers_visible(FALSE);
	my $renderer0= Gtk3::CellRendererPixbuf->new;
	my $renderer1= Gtk3::CellRendererText->new;
	$renderer1->signal_connect(edited => \&name_edited_cb,$self);
	my $column= Gtk3::TreeViewColumn->new;
	$column->pack_start($renderer0,0);
	$column->pack_start($renderer1,1);
	$column->add_attribute($renderer0, icon_name	=> COL_icon);
	$column->add_attribute($renderer1, text		=> COL_name);
	$column->add_attribute($renderer1, editable	=> COL_editable);
	$treeview->append_column($column);

	::set_drag($treeview, source =>
		[::DRAG_FILTER,sub
		 {	my $self= $_[0]->GET_ancestor;
			my $filter=$self->get_selected_filters;
			return ::DRAG_FILTER,($filter? $filter->{string} : undef);
		 }],
		 dest =>
		[::DRAG_FILTER,::DRAG_ID,sub	#targets are modified in drag_motion callback
		 {	my ($treeview,$type,$dest,@data)=@_;
			my $self= $treeview->GET_ancestor;
			my (undef,$path)=@$dest;
			my ($name,$rowtype)=$store->get( $store->get_iter($path), 0,1 );
			if ($type == ::DRAG_ID)
			{	if ($rowtype eq 'slist')
				{	$::Options{SavedLists}{$name}->Push(\@data);
				}
				else
				{	$self->CreateNewFL('L',\@data);
				}
			}
			elsif ($type == ::DRAG_FILTER)
			{	$self->CreateNewFL('F', Filter->new($data[0]) );
			}
		 }],
		motion => \&drag_motion_cb);

	MultiTreeView::init($treeview,__PACKAGE__);
	$treeview->signal_connect( row_activated => \&row_activated_cb);
	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect( changed => \&sel_changed_cb);

	my $sw= ::new_scrolledwindow($treeview);
	::set_biscrolling($sw);
	$self->add($sw);
	$self->{store}=$store;

	$mode||='FPL';
	my $n=0;
	for (split //,$mode)
	{	my ($label,$id,$watchid,$sub,$stock)=@{ $Modes{$_} };
		if (length($mode)!=1)
		{	$store->set($store->append(undef), COL_name,$label, COL_type,'root-'.$id, COL_icon,$stock);
			$self->{$id}=$n++; #path of the root for this id
		}
		::Watch($self,$watchid,$sub) if $watchid;
		$sub->($self);
	}
	$treeview->expand_all;

	return $self;
}

sub UpdatePlayingFilters
{	my $self=$_[0];
	my ($path,$iter);
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	if (defined $self->{play})
	{	$path= Gtk3::TreePath->new( $self->{play} );
		$iter=$store->get_iter($path);
	}
	my @list=(	playfilter	=> _"Playing Filter",
			'f=artists'	=> _"Playing Artist",
			'f=album'	=> _"Playing Album",
			'f=title'	=> _"Playing Title",
		 );
	while (@list)
	{	my $id=shift @list;
		my $name=shift @list;
		$store->set($store->append($iter), COL_name,$name, COL_type,'play', COL_extra,$id);
	}
	$treeview->expand_to_path($path);
}

sub UpdateSavedFilters
{	$_[0]->fill_savednames('sfilter','SavedFilters');
}
sub UpdateSavedLists
{	return if $_[2] && $_[2] eq 'push';
	$_[0]->fill_savednames('slist','SavedLists');
}
sub fill_savednames
{	my ($self,$type,$hkey)=@_;
	$self->{busy}=1;
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $path;
	my $expanded; my $iter;
	if (defined $self->{$type})
	{	$path= Gtk3::TreePath->new( $self->{$type} );
		$expanded=$treeview->row_expanded($path);
		$iter=$store->get_iter($path);
		$expanded=1 unless $store->iter_has_child($iter);
	}
	while (my $child=$store->iter_children($iter))
	{	$store->remove($child);
	}
	$store->set($store->append($iter), COL_name,$_, COL_type,$type, COL_editable,TRUE) for sort keys %{$::Options{$hkey}}; #FIXME use case and accent insensitive sort #should use GetListOfSavedLists() for SavedLists
	$treeview->expand_to_path($path) if $expanded;
	$self->{busy}=undef;
}

sub PopupContextMenu
{	my $self=shift;
	my $tv=$self->{treeview};
	my ($rows,$store)= $tv->get_selection->get_selected_rows;
	my %sel;
	for my $path (@$rows)
	{	my ($name,$type)= $store->get($store->get_iter($path), COL_name, COL_type);
		next if $type=~m/^root-/;
		push @{ $sel{$type} },$name;
	}
	my %args=( self=> $self, treepaths=>$rows, curfilter=>::GetFilter($self), filter=> $self->get_selected_filters );
	if ((keys %sel)==1)
	{	my ($mode)=($args{mode})=keys %sel;
		$args{mode}=	$mode eq 'sfilter'	? 'F' :
				$mode eq 'slist'	? 'L' :
				'';
		$args{names}=$sel{$mode};
	}
	else { $args{mode}=''; }
	my $songlist=::GetSonglist($self);
	$args{songlist}=$songlist if $songlist;
	FilterPane::PopupContextMenu($self,\%args, [@cMenu,{ separator=>1 },@FilterPane::cMenu] );
}

sub drag_motion_cb
{	my ($treeview,$context,$x,$y,$time)=@_;
	::drag_checkscrolling($treeview,$context,$y);
	my $store=$treeview->get_model;
	my ($path,$pos)=$treeview->get_dest_row_at_pos($x,$y);
	my $status;
	{	last if !$path || $treeview->{drag_is_source};
		my $type=$store->get_value( $store->get_iter($path) ,1);
		last unless $type;
		my $target_id=     Gtk3::TargetEntry->new($::DRAGTYPES[::DRAG_ID][0],    'same-app',::DRAG_ID);
		my $target_filter= Gtk3::TargetEntry->new($::DRAGTYPES[::DRAG_FILTER][0],[],        ::DRAG_FILTER);
		my $lookfor; my @targets;
		if ($type eq 'root-sfilter')
		{	$lookfor=::DRAG_FILTER;
			@targets=($target_filter,$target_id);
		}
		elsif ($type=~m/slist$/)
		{	$lookfor=::DRAG_ID;
			@targets=($target_id,$target_filter);
		}
		else {last}

		if ($lookfor && grep $::DRAGTYPES{$_->name} == $lookfor, $context->list_targets )
		{	$status='copy';
			$treeview->drag_dest_set_target_list(Gtk3::TargetList->new( \@targets ));
		}
	}
	unless ($status) { $status='default'; $path=undef; }
	$context->{dest}=[$treeview,$path];
	$treeview->set_drag_dest_row($path,'into-or-after');
	$context->status($status, $time);
	return 1;
}

sub row_activated_cb
{	my ($treeview,$path,$column)=@_;
	# rename, not sure if i
	$treeview->set_cursor($path,$column,TRUE);
}

sub Activate
{	my ($self,$button)=@_;
	my $filter= $self->get_selected_filters;
	FilterPane::Activate($self,$button,$filter);
}

sub name_edited_cb
{	my ($cell, $path_string, $newname,$self) = @_;
	my $store=$self->{store};
	my $iter=$store->get_iter_from_string($path_string);
	my ($name,$type)=$store->get($iter,COL_name,COL_type);
	my $sub= $type eq 'sfilter' ? \&::SaveFilter : \&::SaveList;
	#$self->{busy}=1;
	$sub->($name,undef,$newname);
	#$self->{busy}=undef;
	#$store->set($iter, 0, $newname);
}

sub CreateNewFL
{	my ($self,$mode,$data)=@_;
	my ($type,$hkey,$savesub,$name)= @{$Modes{$mode}}[1,2,5,6];
	while ($::Options{$hkey}{$name}) {$name++}
	return if $::Options{$hkey}{$name};
	$savesub->($name,$data);

	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $iter;
	if (defined $self->{$type})
	{	$iter=$store->get_iter_from_string( $self->{$type} );
	}
	$iter=$store->iter_children($iter);
	while ($iter)
	{	last if $store->get($iter,0) eq $name;
		$iter=$store->iter_next($iter);
	}
	return unless $iter;
	my $path=$store->get_path($iter);
	$self->{busy}=1;
	$treeview->set_cursor($path,$treeview->get_column(0),TRUE);
	$self->{busy}=undef;
}

sub sel_changed_cb
{	my $treesel=$_[0];
	my $self= $treesel->get_tree_view->GET_ancestor;
	return if $self->{busy};
	my $filter=$self->get_selected_filters;
	return unless $filter;
	my $filterpane= $self->GET_ancestor('FilterPane');
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub get_selected_filters
{	my $self=$_[0];
	my @filters;
	my ($paths,$store)= $self->{treeview}->get_selection->get_selected_rows;
	for my $path (@$paths)
	{	my ($name,$type,$extra)= $store->get($store->get_iter($path), COL_name, COL_type, COL_extra);
		next unless $type;
		if ($type eq 'sfilter') {push @filters,$::Options{SavedFilters}{$name};}
		elsif ($type eq 'slist'){push @filters,'list:~:'.$name;}
		elsif ($type eq 'play') {push @filters,_getplayfilter($extra);}
	}
	return undef unless @filters;
	my $filterpane= $self->GET_ancestor('FilterPane');
	my $filter=Filter->newadd( $filterpane->{inter},@filters );
	$filter->invert if $filterpane->{invert};
	return $filter;
}

sub _getplayfilter
{	my $extra=$_[0];
	my $filter;
	if ($extra eq 'playfilter')	{ $filter=$::PlayFilter }
	elsif (defined $::SongID && $extra=~s/^f=//)
	{ $filter= Songs::MakeFilterFromID($extra,$::SongID);
	}
	return $filter;
}

package GMB::AABox;
use base 'Gtk3::Bin';

our @DefaultOptions=
(	aa	=> 'album',
	filternb=> 1,
	#nopic	=> 0,
);

sub new
{	my ($class,$opt)= @_;
	my $self= bless Gtk3::EventBox->new, $class;
	%$opt=( @DefaultOptions, %$opt );
	my $aa=$opt->{aa};
	$aa='artists' if $aa eq 'artist';
	$aa= 'album' unless $aa eq 'artists';		#FIXME PHASE1 change artist to artists
	$self->{aa}=$aa;
	$self->{filternb}=$opt->{filternb};
	$self->{group}=$opt->{group};
	$self->{nopic}=1 if $opt->{nopic};
	my $hbox= Gtk3::HBox->new;
	$self->add($hbox);
	$self->{Sel}=$self->{SelID}=undef;
	my $vbox= Gtk3::VBox->new(::FALSE, 0);
	for my $name (qw/Ltitle Lstats/)
	{	my $l= Gtk3::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle')
		{	$l->set_line_wrap(1);$l->set_ellipsize('end'); #FIXME find a better way to deal with long titles
			my $b= Gtk3::Button->new;
			$b->set_relief('none');
			$b->signal_connect(button_press_event => \&AABox_button_press_cb);
			$b->add($l);
			$l=$b;
		}
		$vbox->pack_start($l, ::FALSE,::FALSE, 2);
	}

	$self->{img}= my $img= Gtk3::EventBox->new;
	$img->{size}=0;
	$img->signal_connect(size_allocate => \&size_allocate_cb) unless $self->{nopic};
	$img->signal_connect(draw=> \&pic_draw_cb) unless $self->{nopic};
	$img->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb,1); # 1 : mouse button 1

	my $buttonbox= Gtk3::VBox->new;
	my $Bfilter=::NewIconButton('view-list-symbolic',undef,sub { my $self= $_[0]->GET_ancestor; $self->filter },'none');
	my $Bplay=::NewIconButton('media-playback-start-symbolic',undef,sub
		{	my $self= $_[0]->GET_ancestor;
			return unless defined $self->{SelID};
			my $filter=Songs::MakeFilterFromGID($self->{aa},$self->{Sel});
			::Select(filter=> $filter, song=>'first',play=>1);
		},'none');
	$Bplay->signal_connect(button_press_event => sub	#enqueue with middle-click
		{	my $self= $_[0]->GET_ancestor;
			return 0 if $_[1]->button !=2;
			my $filter= Songs::MakeFilterFromGID($self->{aa},$self->{Sel});
			if (defined $self->{SelID}) { ::EnqueueFilter($filter); }
			1;
		});
	$Bfilter->set_tooltip_text( ($aa eq 'album' ? _"Filter on this album"		: _"Filter on this artist") );
	$Bplay  ->set_tooltip_text( ($aa eq 'album' ? _"Play all songs from this album" : _"Play all songs from this artist") );
	$buttonbox->pack_start($_, ::FALSE, ::FALSE, 0) for $Bfilter,$Bplay;

	$hbox->pack_start($img, ::FALSE, ::TRUE, 0);
	$hbox->pack_start($vbox, ::TRUE, ::TRUE, 0);
	$hbox->pack_start($buttonbox, ::FALSE, ::FALSE, 0);

	if ($aa eq 'artists')
	{	$self->{'index'}=0;
		$self->signal_connect(scroll_event => \&AABox_scroll_event_cb);
		$self->add_events(['scroll-mask']);
		my $BAlblist=::NewIconButton('media-optical-symbolic',undef,undef,'none');
		$BAlblist->signal_connect(button_press_event => \&AlbumListButton_press_cb);
		$BAlblist->set_tooltip_text(_"Choose Album From this Artist");
		$buttonbox->pack_start($BAlblist, ::FALSE, ::FALSE, 0);
	}

	my $drgsrc=$aa eq 'album' ? ::DRAG_ALBUM : ::DRAG_ARTIST;
	::set_drag($self, source =>
	 [$drgsrc, sub { $drgsrc,$_[0]{Sel}; } ],
	 dest => [::DRAG_ID,::DRAG_FILE,sub
	 {	my ($self,$type,@values)=@_;
		if ($type==::DRAG_FILE)
		{	return unless defined $self->{Sel};
			my $file=$values[0];
			if ($file=~s#^file://##)
			{	AAPicture::SetPicture($self->{aa},$self->{Sel},::decode_url($file));
			}
			#else #FIXME download http link, ask filename
		}
		else # $type is ID
		{	$self->id_set($values[0]);
		}
	 }]);

	$self->signal_connect(button_press_event => \&AABox_button_press_cb);
	::Watch($self,"Picture_".($aa eq 'album' ? 'album' : 'artist') =>\&AAPicture_Changed);
	::WatchSelID($self,\&id_set);
	::Watch($self, SongsChanged=> \&SongsChanged_or_added_cb);
	::Watch($self, SongsAdded  => \&SongsChanged_or_added_cb);
	::Watch($self, SongsRemoved=> \&SongsRemoved_cb);
	::Watch($self, SongsHidden => \&SongsRemoved_cb);
	$self->signal_connect(destroy => \&remove);
	return $self;
}
sub remove
{	my $self=$_[0];
	delete $::ToDo{'9_AABox'.$self};
}

sub AAPicture_Changed
{	my ($self,$key)=@_;
	return unless defined $self->{Sel};
	return unless $key eq $self->{Sel};
	$self->pic_update;
}

sub update_id
{	my $self=$_[0];
	my $ID=$self->{SelID};
	$self->{SelID}=$self->{Sel}=undef;
	$self->id_set($ID);
}

sub clear
{	my $self=$_[0];
	$self->{SelID}=$self->{Sel}=undef;
	$self->pic_update;
	$self->{$_}->set_text('') for qw/Ltitle Lstats/;
	delete $::ToDo{'9_AABox'.$self};
}

sub id_set
{	my ($self,$ID)=@_;
	return if defined $self->{SelID} && $self->{SelID}==$ID;
	$self->{SelID}=$ID;
	my $key= Songs::Get_gid($ID,$self->{aa});
	if ( $self->{aa} eq 'artists' ) #$key is an array ref
	{	$self->{'index'}%= @$key;
		$key= $key->[ $self->{'index'} ];
	}
	$self->update($key) unless defined $self->{Sel} && $key == $self->{Sel};
}

sub update
{	my ($self,$key)=@_;
	#return if $self->{Sel} == $key;
	if (defined $key) { $self->{Sel}=$key; }
	else		  { $key=$self->{Sel}; }
	return unless defined $key;
	my $aa=$self->{aa};
	$self->pic_update;
	$self->{Ltitle}->set_markup( AA::ReplaceFields($key,"<big><b>%a</b></big>",$aa,1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($key,"%s\n%X\n<small>%L\n%y</small>",$aa,1) );

	delete $::ToDo{'9_AABox'.$self};
	$self->{needupdate}=0;
}

sub SongsChanged_or_added_cb
{	my ($self,$IDs,$fields)=@_;	#fields is undef if SongsAdded
	return if $self->{needupdate};
	# could check if is in list or in filter, is it worth it ?
	return if $fields && !::OneInCommon($fields,[qw/artist album length size year/]);
	$self->{needupdate}=1;
	::IdleDo('9_AABox'.$self,1000,\&update,$self);
}
sub SongsRemoved_cb
{	my ($self,$IDs)=@_;
	return if $self->{needupdate};
	$self->{needupdate}=1;
	::IdleDo('9_AABox'.$self,1000,\&update,$self);
}

sub filter
{	my $self=$_[0];
	return unless defined $self->{Sel};
	::SetFilter( $self, Songs::MakeFilterFromGID($self->{aa},$self->{Sel}), $self->{filternb}, $self->{group} );
}

sub pic_update
{	my $self=shift;
	return if $self->{nopic};
	my $img=$self->{img};
	delete $img->{pixbuf};
	::IdleDo('3_AABscaleimage'.$img,200,\&setpic,$img);
}

sub pic_draw_cb
{	my ($img,$cr)=@_;
	my $pixbuf= $img->{pixbuf};
	return 1 unless $pixbuf;
	my $ww= $img->get_allocated_width;
	my $wh= $img->get_allocated_height;
	my $w= $pixbuf->get_width;
	my $h= $pixbuf->get_height;
	my $x= int ($ww-$w)*.5;
	my $y= int ($wh-$h)*.5;
	$cr->translate($x,$y);
	$cr->set_source_pixbuf($pixbuf,0,0);
	$cr->paint;
	1;
}

sub size_allocate_cb
{	my ($img,$alloc)=@_;
	my $h=$alloc->{height};
	$h=200 if $h>200;		#FIXME use a relative max value (to what?)
	$h= int($h/4)*4; # try to limit the number of resize of the picture
	return unless abs($img->{size}-$h);
	$img->{size}=$h;
	$img->set_size_request($h,1);
	::IdleDo('3_AABscaleimage'.$img,200,\&setpic,$img);
}
sub setpic
{	my $img=shift;
	my $self= $img->GET_ancestor;
	return unless defined $self->{SelID};
	my $file= $img->{filename}= AAPicture::GetPicture($self->{aa},$self->{Sel});
	my $pixbuf= $file ? GMB::Picture::pixbuf($file,$img->{size}) : undef;
	$img->{pixbuf}= $pixbuf;
	$img->set_visible($pixbuf);
	$img->queue_resize;
	$img->queue_draw;
}

sub AABox_button_press_cb			#popup menu
{	my ($widget,$event)=@_;
	my $self= $widget->GET_ancestor;
	return 0 unless $self;
	return 0 if $self == $widget && $event->button != 3;
	return unless defined $self->{SelID};
	::PopupAAContextMenu({self=>$self, field=>$self->{aa}, gid=>$self->{Sel}, ID=>$self->{SelID}, filternb => $self->{filternb}, mode => 'B'});
	return 1;
}

sub AABox_scroll_event_cb
{	my ($self,$event)=@_;
	my $l= Songs::Get_gid($self->{SelID},'artists');
	return 0 unless @$l>1;
	$self->{'index'}+=($event->direction eq 'up')? 1 : -1;
	$self->{'index'}%=@$l;
	$self->update( $l->[$self->{'index'}] );
	1;
}

sub AlbumListButton_press_cb
{	my ($widget,$event)=@_;
	my $self= $widget->GET_ancestor;
	return unless defined $self->{Sel};
	::PopupAA('album', from => $self->{Sel}, cb=>sub
		{	my $filter= $_[0]{filter};
			::SetFilter( $self, $filter, $self->{filternb}, $self->{group} );
		});
	1;
}

package SimpleSearch;
use base 'Gtk3::Entry';

our @SelectorMenu= #the first one is the default
(	[_"Search Title, Artist and Album", 'title|artist|album' ],
	[_"Search Title, Artist, Album, Comment, Label and Genre", 'title|artist|album|comment|label|genre' ],
	[_"Search Title, Artist, Album, Comment, Label, Genre and Filename", 'title|artist|album|comment|label|genre|file' ],
	[_"Search Title",	'title'],
	[_"Search Artist",	'artist'],
	[_"Search Album",	'album'],
	[_"Search Comment",	'comment'],
	[_"Search Label",	'label'],
	[_"Search Genre",	'genre'],
);

our %Options=
(	casesens	=> _"Case sensitive",
	literal		=> _"Literal search",
	regexp		=> _"Regular expression",
);
our %Options2=
(	autofilter	=> _"Auto filter",
	suggest		=> _"Show suggestions",
);
our @DefaultOptions=
(	nb	=> 1,
	fields	=> $SelectorMenu[2][1],
	autofilter =>1,
);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::Entry->new, $class;
	%$opt=( @DefaultOptions, %$opt );
	$self->signal_connect(changed => \&EntryChanged_cb);
	$self->signal_connect(activate => \&DoFilter);
	$self->signal_connect(activate => \&CloseSuggestionMenu);
	$self->signal_connect(key_press_event => \&key_press_event_cb);
	$self->signal_connect_after(activate => sub {::run_command($_[0],$opt->{activate});}) if $opt->{activate};
	$self->set_max_width_chars($opt->{minwidthchar}) if $opt->{minwidthchar};
	$self->set_max_width_chars($opt->{maxwidthchar}) if $opt->{maxwidthchar};
	unless ($opt->{noselector})
	{	$self->set_icon_from_icon_name('primary','edit-find-symbolic');
		$self->set_icon_from_icon_name('secondary','edit-clear-symbolic');
		$self->set_icon_activatable($_,1) for qw/primary secondary/;
		$self->set_icon_tooltip_text('primary',_"Search options");
		$self->set_icon_tooltip_text('secondary',_"Reset filter");
		$self->set_icon_sensitive('secondary',0);
		$self->signal_connect(changed => \&UpdateClearButton);
		$self->signal_connect(icon_press => sub { my ($self,$iconpos)=@_; if ($iconpos eq 'primary') {$self->PopupSelectorMenu} else {$self->ClearFilter} });
		$self->signal_connect(focus_out_event => \&focus_changed_cb);
		$self->signal_connect(focus_in_event  => \&focus_changed_cb);
		$self->signal_connect(scroll_event    => \&scroll_event_cb);
		$self->add_events('scroll-mask');
	}
	$self->{$_}=$opt->{$_} for qw/nb fields group searchfb/,keys %Options,keys %Options2;
	$self->{SaveOptions}=\&SaveOptions;
	::WatchFilter($self, $self->{group},sub { $_[0]->Update_bg(0); $_[0]->UpdateClearButton;}) unless $opt->{noselector}; #to update background color and clear button
	return $self;
}

sub SaveOptions
{	my $self=$_[0];
	my %opt=(fields => $self->{fields});
	$opt{$_}= $self->{$_} ? 1 : 0 for keys %Options, keys %Options2;
	return \%opt;
}

sub ClearFilter
{	my $self=shift;
	my $event= Gtk3::get_current_event;
	my $text='';
	if ($event->isa('Gtk3::Gdk::EventButton') && $event->button == 2) #paste clipboard if middle-click
	{	my $clip= $self->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('PRIMARY'))->wait_for_text;
		$text=$1 if $clip=~m/([^\n\r]+)/;
	}
	$self->set_text($text);
	$self->DoFilter;
}
sub UpdateClearButton
{	my $self=shift;
	my $on= $self->get_text ne '' || !::GetFilter($self)->is_empty;
	$self->set_icon_sensitive('secondary',$on);
}
sub focus_changed_cb { $_[0]->Update_bg; 0; }
sub Update_bg
{	my ($self,$on)=@_;
	$self->{filtered}=$on if defined $on;
	$self->set_progress_fraction( !$self->has_focus && $self->{filtered} );  #used to set the background color
}

sub ChangeOption
{	my ($self,$key,$value)=@_;
	$self->{$key}=$value;
	$self->DoFilter unless $self->get_text eq '';
}

sub PopupSelectorMenu
{	my $self=shift;
	my $menu= Gtk3::Menu->new;
	my $cb=sub { $self->ChangeOption( fields => $_[1]); };
	for my $ref (@SelectorMenu)
	{	my ($label,$fields)=@$ref;
		my $item= Gtk3::CheckMenuItem->new($label);
		$item->set_active(1) if $fields eq $self->{fields};
		$item->set_draw_as_radio(1);
		$item->signal_connect(activate => $cb,$fields);
		$menu->append($item);
	}
	my $item1= Gtk3::MenuItem->new(_"Select search fields");
	$item1->set_submenu( ::BuildChoiceMenu(
					{ map { $_=>Songs::FieldName($_) } Songs::StringFields(),qw/file path year/,},
					'reverse' =>1, return_list=>1,
					check=> sub { [split /\|/,$self->{fields}]; },
					code => sub { $self->ChangeOption(fields=> join '|',@{$_[1]} ); },
				) );
	$menu->append($item1);
	$menu->append(Gtk3::SeparatorMenuItem->new);
	for my $key (sort { $Options{$a} cmp $Options{$b} } keys %Options)
	{	my $item= Gtk3::CheckMenuItem->new($Options{$key});
		$item->set_active(1) if $self->{$key};
		$item->signal_connect(activate => sub
			{	$self->ChangeOption( $_[1] => $_[0]->get_active);
			},$key);
		$menu->append($item);
	}
	$menu->append(Gtk3::SeparatorMenuItem->new);
	for my $key (sort { $Options2{$a} cmp $Options2{$b} } keys %Options2)
	{	my $item= Gtk3::CheckMenuItem->new($Options2{$key});
		$item->set_active(1) if $self->{$key};
		$item->signal_connect(activate => sub
			{	$self->{$_[1]}= $_[0]->get_active;
			},$key);
		$menu->append($item);
	}
	my $item2= Gtk3::MenuItem->new(_"Advanced Search ...");
	$item2->signal_connect(activate => sub
		{	::EditFilter($self,::GetFilter($self),undef,sub {::SetFilter($self,$_[0]) if defined $_[0]});
		});
	$menu->append($item2);
	::PopupMenu($menu);
}

sub GetFilter
{	my $self=shift;
	my $search= $self->get_text;

	my $filter;
	if (length $search)
	{	if ($self->{literal})
		{	my $op= $self->{regexp} ? ($self->{casesens} ? 'm' : 'mi') : ($self->{casesens} ? 's' : 'si');
			my $fields=$self->{fields};
			$filter= Filter->newadd(0, map($_.':'.$op.':'.$search, split /\|/, $self->{fields}) );
		}
		else
		{	$filter= Filter->new_from_smartstring($search,$self->{casesens},$self->{regexp},$self->{fields});
		}
		# optimization : see if it can use previous search
		my $last_filter= delete $self->{last_filter};
		$filter->add_possible_superset($last_filter) if $last_filter;
		$self->{last_filter}=$filter;
	}
	else { $filter= Filter->new }
	return $filter;
}

sub AutoFilter
{	my ($self,$event,$force)=@_;
	if ($::debug) { warn "AutoFilter: $event".($force ? ' force':'')."\n" }
	unless ($event eq 'filter_ready' || $event eq 'time_ready') {warn 'error'; return}
	$self->{$event}=1;
	return unless $self->{filter_ready} && $self->{time_ready};
	my $idlefilter=$self->{idlefilter};
	if (!$force && $idlefilter && !$idlefilter->is_cached) { warn "AutoFilter: restart\n" if $::debug; $idlefilter->start; return } #for case where filter was finished before first timeout, but since the cache was flushed, retry unless the second timeout has expired
	Glib::Source->remove(delete $self->{changed_timeout}) if $self->{changed_timeout};
	Glib::Source->remove(delete $self->{idlefilter_timeout}) if $self->{idlefilter_timeout};
	$self->DoFilter if $self->{autofilter};
}

sub StartIdleFilter
{	my $self=shift;
	my $search=$self->get_text;
	my $previous= delete $self->{idlefilter};
	my $filter= ::SimulateSetFilter( $self,$self->GetFilter, $self->{nb} );
	#warn "idle $search\n";
	my $new= IdleFilter->new($filter,sub { $self->AutoFilter('filter_ready')});
	$self->{idlefilter}=$new if ref $new;
	$previous->abort if $previous;
}

sub DoFilter
{	my $self=shift;
	Glib::Source->remove(delete $self->{changed_timeout}) if $self->{changed_timeout};
	my $idlefilter= delete $self->{idlefilter};
	$idlefilter->abort if $idlefilter;

	my $filter= $self->GetFilter;
	::SetFilter($self,$filter,$self->{nb});
	if ($self->{searchfb})
	{	my $search= $self->get_text;
		::HasChanged('SearchText_'.$self->{group},$search); #FIXME
	}
	$self->Update_bg( !$filter->is_empty );
}

sub EntryChanged_cb
{	my $self=shift;
	$self->Update_bg(0);
	my $l= length($self->get_text);
	delete $self->{filter_ready};
	delete $self->{time_ready};
	Glib::Source->remove(delete $self->{changed_timeout}) if $self->{changed_timeout};
	Glib::Source->remove(delete $self->{idlefilter_timeout}) if $self->{idlefilter_timeout};
	if ($self->{autofilter})
	{	# 1st timeout : do not filter before this minimum timeout, even if filter is ready
		my $timeout= $l<2 ? 800 : 300;
		$self->{changed_timeout}= Glib::Timeout->add($timeout,sub { $self->AutoFilter('time_ready'); 0 });
		# 2nd timeout : filter even if idlefilter not finished
		$timeout= $l<4 ? 3000 : 2000;
		$self->{idlefilter_timeout}= Glib::Timeout->add($timeout,sub { $self->AutoFilter('filter_ready','force'); 0 });
	}
	$self->StartIdleFilter if $self->{autofilter} || ($l>2 && !$self->{suggest});
	if ($self->{suggest})
	{	Glib::Source->remove(delete $self->{suggest_timeout}) if $self->{suggest_timeout};
		my $timeout= $l<2 ? 0 : $l==2 ? 200 : 100;
		if ($timeout)	{ $self->{suggest_timeout}= Glib::Timeout->add($timeout,\&UpdateSuggestionMenu,$self); }
		else		{ $self->CloseSuggestionMenu; }
	}
}

sub key_press_event_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name($event->keyval);
	if ($key eq 'Escape') { $self->set_text(''); }
	else {return 0}
	return 1;
}

sub scroll_event_cb	#increase/decrease numbers when using the wheel over them
{	my ($self,$event)=@_;
	my $dir= $event->direction;
	$dir= $dir eq 'up' ? 1 : $dir eq 'down' ? -1 : 0;
	return 0 unless $dir;
	# translate coord, not sure if could be simpler
	my ($x,$y)= $event->get_window->coords_to_parent($event->x,$event->y);
	my $alloc= $self->get_allocation;
	my $textarea= $self->get_text_area;
	$x-= $alloc->{x} + $textarea->{x};
	$y-= $alloc->{y} + $textarea->{y};
	return 0 if $x<0 || $y<0 || $x>$textarea->{width} || $y>$textarea->{height}; #ignore if pointer outside the text area
	my $text0= $self->get_text;
	my ($offx,$offy)= $self->get_layout_offsets;
	$x+= $textarea->{x} - $offx;
	my $layout= $self->get_layout;
	my ($inside,$index,$trailing)= $layout->xy_to_index(Pango->SCALE *$x,0); #y always 0, as only one line
	$index= $x<0	? 0 :			# if pointer before the text
		$inside	? $self->layout_index_to_text_index($index) :
			  length($text0)-1;	# if pointer after the text, do as if at the end of text
	my $pos=0;
	my $text='';
	my $found;
	for my $string (split /(\|| +|(?<=\d)(?=(?:\.\.|[.,]?-)\d))/,$text0)
	{	my $l= length $string;
		if (!$found && $pos<=$index && $pos+$l>=$index && $string=~m/\d/)
		{	$string= _smart_incdec($string,$dir);
			$found= $pos+length $string;
		}
		$pos+= $l;
		$text.=$string;
	}
	if ($found) { $self->set_text($text); $self->set_position($found); return 1; }
	0;
}
sub _smart_incdec # increase/decrease the lowest significant digit in the number of the string
{	my ($string,$inc)=@_;
	my @parts= reverse split /(\.\.|\d*[.,]\d+|\d+)/,$string;

	for my $part (@parts)
	{	if ($part=~m#^(\d*)([.,])(\d+)$#)
		{	my $d=$3+$inc;
			my $n=$1;
			my $l1=length $3;
			my $l2=length $d;
			if ($d<0)
			{	if ($n) { $d="9"x$l1; $n--;}
				else	{ $d="0"x$l1 }
			}
			elsif ($l2>$l1) { $d="0"x$l1; $n++; }
			elsif ($l2<$l1) { $d="0"x($l1-$l2).$d }
			$part= $n.$2.$d;
			last;
		}
		elsif ($part=~m#^\d+$#)
		{	$part+=$inc;
			$part=0 if $part<0;
			last;
		}
	}
	return join '',reverse @parts;
}

sub CloseSuggestionMenu
{	my $self=shift;
	Glib::Source->remove(delete $self->{suggest_timeout}) if $self->{suggest_timeout};
	my $menu= delete $self->{matchmenu};
	return unless $menu;
	$menu->cancel;
	$menu->destroy;
}

sub UpdateSuggestionMenu
{	my $self=shift;
	if ($self->{matchmenu} && !$self->{matchmenu}->get_mapped) { $self->CloseSuggestionMenu; }
	Glib::Source->remove(delete $self->{suggest_timeout}) if $self->{suggest_timeout};
	my $refresh= !!$self->{matchmenu};
	my $menu= $self->{matchmenu} ||= Gtk3::Menu->new;
	if ($refresh) { $menu->remove($_) for $menu->get_children; }

	my $window= $self->get_window;
	my $h=$self->size_request->height;
	my $w=$self->size_request->width;
	my $monitor= $self->get_display->get_monitor_at_window($window);
	my $geometry= $monitor->get_geometry;
	my ($xmin,$ymin,$monitorwidth,$monitorheight)= @$geometry{qw/x y width height/};
	my $xmax=$xmin + $monitorwidth;
	my $ymax=$ymin + $monitorheight;
	my ($x,$y)= $window->get_origin;	# position of the parent widget on the screen
	my $dx= $window->get_width;		# its width
	my $dy= $window->get_height;		# its height
	if (!$self->get_has_window)
	{	my $alloc= $self->get_allocation;
		(my$x2,my$y2,$dx,$dy)= @$alloc{qw/x y width height/};
		$x+=$x2;$y+=$y2;
	}
	my $above=0;
	my $height=$ymax-$y-$h;
	if ($height<$y-$ymin) { $height=$y-$ymin; $above=1; }
	$height*=.9;

	my $found;
	my $text= $self->get_text;
	for my $field (qw/artists album genre label title/)
	{	my $list;
		if ($field eq 'title')
		{	my $filter= Filter->new('title:si:'.$text);
			$filter->add_possible_superset($self->{last_suggestion_filter}) if $self->{last_suggestion_filter};
			$self->{last_suggestion_filter}=$filter;
			$list= $filter->filter;
			next unless @$list;
			Songs::SortList($list,'-rating -playcount -lastplay');
		}
		else
		{	$list= AA::GrepKeys($field, $text);
			next unless @$list;
			#AA::SortKeys($field,$list,'alpha');
			AA::SortKeys($field,$list,'songs'); @$list= reverse @$list;
			# remove 0 songs ?
		}
		$found=1;
		my $item0= Gtk3::MenuItem->new;
		my $label0= Gtk3::Label->new;
		$label0->set_markup_with_format("<i> %s : %d</i>", Songs::FieldName($field), scalar(@$list));
		$label0->set_alignment(1,.5);
		$item0->add($label0);
		$item0->show_all;
		$menu->append($item0);
		$height-= ($item0->get_preferred_height)[1];
		my $format=	$field eq 'album'	? "<b>%a</b>%Y\n<small>%s by %b</small>":
				$field=~m/^artists?$/	? "<b>%a</b>\n<small>%x %s%Y</small>"	:
				$field eq 'title'	? "<b>%t</b>\n<small><small>by</small> %a <small>from</small> %l</small>":
							  "<b>%a</b> (<small>%s</small>)";
		if ($field eq 'title')	{ $item0->set_sensitive(0) }
		else
		{	$item0->{field}=$field;
			$item0->{list}=$list;
			$item0->{format}=$format;
			$item0->signal_connect(button_press_event => \&SuggestionMenu_field_expand) unless $field eq 'title';
		}
		for my $i (0..::min(4,$#$list))
		{	my $val= $list->[$i];
			my $item;
			if ($field eq 'artists' || $field eq 'album') #FIXME be more generic
			{	if ( my $img=AAPicture::newimg($field,$val,32) )
				{	$item=Gtk3::ImageMenuItem->new;
					$item->set_image($img);
				}
			}
			elsif ($field eq 'label') #FIXME be more generic
			{	if (my $icon=Songs::Picture($val,$field,'icon'))
				{	$item=Gtk3::ImageMenuItem->new;
					$item->set_image( Gtk3::Image->new_from_stock($icon,'menu') );
				}
			}
			$item||= Gtk3::MenuItem->new;
			my $markup;
			if ($field eq 'title') { $markup=::ReplaceFieldsAndEsc($val,$format); }
			else
			{	$markup=AA::ReplaceFields($val,$format,$field,1);
			}
			my $label= Gtk3::Label->new;
			$label->set_markup($markup);
			$label->set_ellipsize('end');
			$label->set_alignment(0,.5);
			$item->{val}=$val;
			$item->{field}=$field;
			$item->signal_connect(button_press_event => sub { $_[0]{middle}=$_[1]->button==2; });
			$item->signal_connect(activate=> \&SuggestionMenu_item_activated_cb);
			$item->add($label);
			$item->show_all;
			$menu->append($item); #needs to be added to menu to get its real height
			$height-= ($item->get_preferred_height)[1];
			if ($height<0)
			{	$menu->remove($item);
				$menu->remove($item0) if $i==0;
				last;
			}
		}
		last if $height<0;
	}
	unless ($found)
	{	$self->CloseSuggestionMenu;
		return;
	}
	$menu->set_size_request($w*2,-1);
	$menu->show_all;
	$menu->set_take_focus(0);
	if ($menu->get_mapped)
	{	$menu->reposition;
		$menu->set_active(0);
	}
	else
	{	$menu->attach_to_widget($self, sub {'empty detaching callback'});
		$menu->signal_connect(key_press_event => \&SuggestionMenu_key_press_cb);
		$menu->signal_connect(selection_done  => sub  {$_[0]->get_attach_widget->CloseSuggestionMenu});
		$menu->popup(undef,undef,sub { my $menu=shift; $x, ($above ? $y-($menu->get_preferred_height)[1] : $y+$h); },undef,0,Gtk3::get_current_event_time);
	}
}
sub SuggestionMenu_key_press_cb
{	my ($menu,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	if (grep $key eq $_, qw/Up Down Return Right/)
	{	my @items=$menu->get_children;
		if ($key eq 'Up'   && $items[0]->state  eq 'prelight')	{ $items[0] ->deselect; return 1 }
		if ($key eq 'Down' && $items[-1]->state eq 'prelight')	{ $items[-1]->deselect; return 1 }
		if ($key eq 'Return' || $key eq 'Right')
		{	my ($item)= grep $_->state eq 'prelight', @items;
			if ($item)
			{	SuggestionMenu_field_expand($item) if $item->{list};
				return 0;
			}
		}
		else {	return 0 }
	}
	#return 0 if grep $key eq $_, qw/Up Down/;
	$menu->get_attach_widget->event($event);	# redirect the event to the entry
	1;
}
sub SuggestionMenu_item_activated_cb
{	my $item=shift;
	my $self=  $item->GET_ancestor; # use the attach_widget to get back to self
	my $val=   $item->{val};
	my $field= $item->{field};
	my $filter;
	if ($field eq 'title')
	{	$filter= Songs::MakeFilterFromID($field,$val);
	}
	else
	{	$filter= Songs::MakeFilterFromGID($field,$val);
	}
	if (my $watch=delete $self->{changed_timeout}) { Glib::Source->remove($watch); }
	$self->CloseSuggestionMenu;
	if ($item->{middle})
	{	my $IDs= $field eq 'title' ? [$val] : $filter->filter;
		::DoActionForList('queue', $IDs);
	}
	else { ::SetFilter($self,$filter,$self->{nb}); }
}

sub SuggestionMenu_field_expand
{	my $item=shift;
	return 0 if $item->get_submenu;
	my $submenu=::PopupAA($item->{field}, list=>$item->{list}, format=>$item->{format}, cb => sub { my $item=$_[0]{menuitem}; $item->{field}=$_[0]{field}; $item->{val}=$_[0]{key}; SuggestionMenu_item_activated_cb($item); });
	$item->set_submenu($submenu);
	return 0;
}


package SongSearch;
use base 'Gtk3::Box';

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::Box->new('vertical',0), $class;
	my %sl_opt=( type=>'S', headers=>'off', 'sort'=>'title', cols=>'titleaa', group=>"$self", name=>'songsearch' );
	$sl_opt{$_}= $opt->{$_} for grep m/^activate\d?/, keys %$opt;
	$sl_opt{activate} ||= 'queue';
	$self->{songlist}= my $songlist= SongList->new(\%sl_opt);
	my $hbox1= Gtk3::HBox->new;
	my $entry= Gtk3::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate =>\&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk3::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$self->add($hbox1);
	$self->pack_start($songlist, ::TRUE,::TRUE,0);
	if ($opt->{buttons})
	{	my $hbox2= Gtk3::HBox->new;
		my $Bqueue=::NewIconButton('format-indent-more-symbolic',		_"Enqueue",	sub { $songlist->EnqueueSelected; });
		my $Bplay= ::NewIconButton('media-playback-start-symbolic',	_"Play",	sub { $songlist->PlaySelected; });
		my $Bclose=::NewIconButton('close-symbolic',			_"Close",	sub {$self->get_toplevel->close_window});
		$hbox2->pack_end($_, ::FALSE,::FALSE,4) for $Bclose,$Bplay,$Bqueue;
		$self->pack_end($hbox2, ::FALSE,::FALSE,0);
	}

	$self->{DefaultFocus}=$entry;
	return $self;
}

sub EntryChanged_cb
{	my ($entry,$force)=@_;
	my $text=$entry->get_text;
	my $self= $entry->GET_ancestor;
	if (!$force && 2>length $text) { $self->{songlist}->Empty }
	else { $self->{songlist}->SetFilter( Filter->new('title:si:'.$text) ); }
}

package AASearch;
use base 'Gtk3::Box';

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::Box->new('vertical',0), $class;
	my $store= Gtk3::ListStore->new(FilterList::GID_TYPE);
	my $treeview= $self->{treeview}= Gtk3::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	my $sw= ::new_scrolledwindow($treeview,'etched-in');
	::set_biscrolling($sw);
	my $renderer= CellRendererGID->new;
	$treeview->append_column( Gtk3::TreeViewColumn->new_with_attributes('', $renderer, gid=>0) );
	$self->{activate}= $opt->{activate} || 'queue';
	$treeview->signal_connect( row_activated => \&Activate);

	$self->{field}= $opt->{aa} || 'artists';
	$renderer->set(prop => [[$self->{field}],[1],[32],[0]], depth => 0);  # (field markup=1 picsize=32 icons=0)
	$self->{drag_type}= Songs::FilterListProp( $self->{field}, 'drag') || ::DRAG_FILTER;
	::set_drag($treeview, source =>
	    [ $self->{drag_type},
	    sub
	    {	my $self= $_[0]->GET_ancestor;
		my ($rows,$store)= $self->{treeview}->get_selection->get_selected_rows;
		my @gids= map $store->get_value($store->get_iter($_),0) , @$rows;
		if ($self->{drag_type} != ::DRAG_FILTER)	#return artist or album gids
		{	return $self->{drag_type},@gids;
		}
		else
		{	my @f=map Songs::MakeFilterFromGID( $self->{field}, $_ ), @gids;
			my $filter= Filter->newadd(::FALSE, @f);
			return ($filter? (::DRAG_FILTER,$filter->{string}) : undef);
		}
	    }]);

	my $hbox1= Gtk3::HBox->new;
	my $entry= Gtk3::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate=> \&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk3::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$self->add($hbox1);
	$self->pack_start($sw, ::TRUE,::TRUE,0);
	if ($opt->{buttons})
	{	my $hbox2= Gtk3::HBox->new;
		my $Bqueue=::NewIconButton('format-indent-more-symbolic',		_"Enqueue",	\&Enqueue);
		my $Bplay= ::NewIconButton('media-playback-start-symbolic',	_"Play",	\&Play);
		my $Bclose=::NewIconButton('clost-symbolic',			_"Close",	sub {$self->get_toplevel->close_window});
		$hbox2->pack_end($_, ::FALSE,::FALSE,4) for $Bclose,$Bplay,$Bqueue;
		$self->pack_end($hbox2, ::FALSE,::FALSE,0);
	}

	$self->{DefaultFocus}=$entry;
	EntryChanged_cb($entry,1);
	return $self;
}

sub GetFilter
{	my $self= $_[0]->GET_ancestor;
	my $treeview=$self->{treeview};
	my $path=($treeview->get_cursor)[0];
	return undef unless $path;
	my $store=$treeview->get_model;
	my $gid=$store->get_value( $store->get_iter($path),0 );
	return Songs::MakeFilterFromGID( $self->{field}, $gid );
}

sub EntryChanged_cb
{	my ($entry,$force)=@_;
	my $text=$entry->get_text;
	my $self= $entry->GET_ancestor;
	my $store=$self->{treeview}->get_model;
	(($self->{treeview}->get_columns)[0]->get_cells)[0]->reset;
	$store->clear;
	#return if !$force && 2>length $text;
	my $list= AA::GrepKeys($self->{field}, $text);
	AA::SortKeys($self->{field},$list,'alpha');
	$store->set($store->append,0,$_) for @$list;
}

sub Activate
{	my $self= $_[0]->GET_ancestor;
	my $filter=GetFilter($self);
	my $action= $self->{activate};
	my $aftercmd;
	$aftercmd=$1 if $action=~s/&(.*)$//;
	::DoActionForFilter($action,$filter);
	::run_command($self,$aftercmd) if $aftercmd;
}

sub Enqueue
{	my $filter=GetFilter($_[0]);
	::DoActionForFilter('queue',$filter);
}
sub Play
{	my $filter=GetFilter($_[0]);
	::DoActionForFilter('play',$filter);
}

package CellRendererIconList;
use Glib::Object::Subclass
	'Gtk3::CellRenderer',
	properties =>	[ Glib::ParamSpec->ulong('ID','ID','Song ID',		0,2**32-1,0,	[qw/readable writable/]),
			  Glib::ParamSpec->string('field','field','field id',	'label',	[qw/readable writable/]),
			];

use constant PAD => 2;

sub GET_SIZE
{	my ($cell, $widget, $cell_area) = @_;
	return (0,0,0,0);
#	my $list=$cell->get('iconlist');
#	return (0,0,0,0) unless defined $list;
#	my $nb=@$list;
#	my $w= my $h= $::IconSize{menu};
#	return (0,0, $nb*($w+PAD)+$cell->get('xpad')*2, $h+$cell->get('ypad')*2);
}

sub RENDER
{	my ($cell, $cr, $widget, $background_area, $cell_area, $flags)= @_;
	my ($field,$ID)=$cell->get(qw/field ID/);
	my @list=Songs::Get_icon_list($field,$ID);
	return unless @list;
	my $size= $::IconSize{menu};
	my $theme= Gtk3::IconTheme::get_default;
	my @pb= map $theme->load_icon($_,$size,['force-size']), sort @list;
	return unless @pb;

	my $w= my $h= $size+PAD;
	my $room=PAD + $cell_area->{height}-2*$cell->get('ypad');
	my $nb=int( $room / $h );
	my $x=$cell_area->{x}+$cell->get('xpad');
	my $y=$cell_area->{y}+$cell->get('ypad');
	$y+=int( $cell->get('yalign') * ($room-$h*$nb) ) if $nb>0;
	my $row=0;
	for my $pb (@pb)
	{	$cr->translate($x,$y);
		$cr->set_source_pixbuf($pb,0,0);
		$cr->paint;
		if (++$row<$nb)	{ $x=0; $y=$h; }
		else		{ $x=$w; $y= -$h*($row-1); $row=0; }
	}
}

package CellRendererGID;
use Glib::Object::Subclass 'Gtk3::CellRenderer',
properties => [ Glib::ParamSpec->long('gid', 'gid', 'group id',		-2**31+1, 2**31-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->ulong('all_count', 'all_count', 'all_count',	0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->ulong('max', 'max', 'max number of songs',	0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->scalar('prop', 'prop', '[[field],[markup],[picsize]]',		[qw/readable writable/]),
		Glib::ParamSpec->scalar('hash', 'hash', 'gid to song count',			[qw/readable writable/]),
		Glib::ParamSpec->int('depth', 'depth', 'depth',			0, 20, 0,	[qw/readable writable/]),
		Glib::ParamSpec->boolean('ignore_none','ignore none','ignore the none row in histogram',0, [qw/readable writable/]),
		];
use constant { PAD => 2, XPAD => 2, YPAD => 2,		P_FIELD => 0, P_MARKUP =>1, P_PSIZE=>2, P_ICON =>3, P_HORIZON=>4 };

#sub INIT_INSTANCE
#{	#$_[0]->set(xpad=>2,ypad=>2); #Gtk2::CellRendererText has these padding values as default
#}
sub makelayout
{	my ($cell,$widget)=@_;
	my ($prop,$gid,$depth)=$cell->get(qw/prop gid depth/);
	my $layout= $widget->create_pango_layout;
	my $field=$prop->[P_FIELD][$depth];
	my $markup=$prop->[P_MARKUP][$depth];
	$markup= !$markup ? "%a" : $markup eq 1 ? "<b>%a</b>%Y\n<small>%s <small>%l</small></small>" : $markup;
	if ($gid==FilterList::GID_ALL)
	{	$markup= ::MarkupFormat("<b>%s (%d)</b>", Songs::Field_All_string($field), $cell->get('all_count') );
	}
	#elsif ($gid==0) {  }
	else { $markup=AA::ReplaceFields( $gid,$markup,$field,::TRUE ); }
	$layout->set_markup($markup);
	return $layout;
}

sub GET_SIZE
{	my ($cell,$widget,$cell_area)= @_;
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	my ($prop,$depth)=$cell->get('prop','depth');
	my $s= $prop->[P_PSIZE][$depth] || $prop->[P_ICON][$depth];
	if ($s == -1)	{$s=$h}
	elsif ($h<$s)	{$h=$s}
	my $width= $prop->[P_HORIZON] ? $w+$s+PAD+XPAD*2 : 0;
	#return (0,0,$width,$h+YPAD*2);
	return ($width,$h+YPAD*2,0,0);	# for some reason the width and height need to be returned as 3rd and 4th values instead of 1st and 2nd, the other 2 values seem to be ignored
}

sub RENDER
{	my ($cell, $cr, $widget, $background_area, $cell_area, $flags)= @_;
	my $x=$cell_area->{x}+XPAD;
	my $y=$cell_area->{y}+YPAD;
	my ($prop,$gid,$depth,$hash,$max,$ignore_none)=$cell->get(qw/prop gid depth hash max ignore_none/);
	my $iconfield= $prop->[P_ICON][$depth];
	my $psize= $iconfield ? $::IconSize{menu} : $prop->[P_PSIZE][$depth];
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	$psize=$h if $psize == -1;
	$w+=PAD+$psize;
	my $offy=0;
	if ($psize>$h)
	{	$offy+=int( $cell->get('yalign')*($psize-$h) );
		$h=$psize;
	}

	# draw picture
	if ($psize && $gid!=FilterList::GID_ALL)
	{	my $field=$prop->[P_FIELD][$depth];
		my $pixbuf=	$iconfield	? (::get_pixbuf_for_label_icon($field,$gid) || undef) :
						AAPicture::pixbuf($field,$gid,$psize,::FALSE);
		if ($pixbuf) #pic cached -> draw now
		{	my $offy=int(($h-$pixbuf->get_height)/2);#center pic
			my $offx=int(($psize-$pixbuf->get_width)/2);
			$cr->save;
			$cr->translate( $x+$offx, $y+$offy);
			$cr->set_source_pixbuf($pixbuf,0,0);
			$cr->paint;
			$cr->restore;
		}
		elsif (defined $pixbuf) #pic exists but not cached -> load and draw in idle
		{	my ($tx,$ty)=$widget->convert_widget_to_tree_coords($x,$y);
			$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
			$cell->{widget}||=$widget;
			$cell->{queue}{$ty}=[$tx,$ty,$gid,$psize,$h,\$field];
		}
	}

	# draw histogram background
	if ($max && !$depth && !($flags & 'selected') && $gid!=FilterList::GID_ALL && !($gid==0 && $ignore_none))	#draw histogram only works for depth==0
	{	# if parent widget is a scrolledwindow, maxwidth use the visible width instead of the total width of the treeview
		my $parent= $widget->get_parent;
		my $maxwidth= $parent->isa('Gtk3::ScrolledWindow') ? $parent->get_hadjustment->get_page_size : $cell_area->{width};
		$maxwidth-= 3*XPAD+$psize;
		$maxwidth=5 if $maxwidth<5;
		my $width= $hash->{$gid} / $max * $maxwidth;
		#my $color= Gtk3::Gdk::RGBA::parse("red"); #FIXME add a color option
		my $color= $widget->get_style_context->get_color($widget->get_state);
		$color->alpha(.2);	# use fg color with 20% alpha, maybe find a better way to choose a good background color
		$cr->set_source_gdk_rgba($color);
		$cr->rectangle( $x+$psize+PAD, $cell_area->{y}, $width, $cell_area->{height} );
		$cr->fill;
	}

	# draw text
	my $style= $widget->get_style_context;
	$style->render_layout($cr, $x+$psize+PAD, $y+$offy, $layout);

	# draw stars
	my $field=$prop->[P_FIELD][$depth];
	$field=~s/\..*//;
	my $has_stars= Songs::FieldType($field) eq 'rating';
	if ($gid!=FilterList::GID_ALL && $has_stars)
	{	if (my $pb= Songs::Stars($gid,$field))
		{	# FIXME center vertically or resize ?
			# make stars horizontally aligned
			  $layout->set_text("XXX"); #FIXME should use a field property for that
			  my $wmax= ($layout->get_pixel_size)[0];
			  $w=$wmax unless $w>$wmax;
			$cr->translate($x+XPAD+$w, $y+$offy);
			$cr->set_source_pixbuf($pb,0,0);
			$cr->paint;
		}
	}
}

sub reset
{	my $cell=$_[0];
	delete $cell->{queue};
	Glib::Source->remove( $cell->{idle} ) if $cell->{idle};
	delete $cell->{idle};
}

sub idle
{	my $cell=$_[0];
	{	last unless $cell->{queue} && $cell->{widget}->get_mapped;
		my ($y,$ref)=each %{ $cell->{queue} };
		last unless $ref;
		delete $cell->{queue}{$y};
		_drawpix($cell->{widget},@$ref);
		last unless scalar keys %{ $cell->{queue} };
		return 1;
	}
	delete $cell->{queue};
	delete $cell->{widget};
	return $cell->{idle}=undef;
}

sub _drawpix
{	my ($widget,$ctx,$cty,$gid,$psize,$h,$fieldref)=@_;
	my $visible= $widget->get_visible_rect;
	my ($vx,$vy,$vw,$vh)= @$visible{qw/x y width height/};
	#warn "   $gid\n";
	return if $vx > $ctx+$psize || $vy > $cty+$h || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $gid\n";
	my ($x,$y)=$widget->convert_tree_to_widget_coords($ctx,$cty);
	my $pixbuf= AAPicture::pixbuf($$fieldref,$gid, $psize,::TRUE);
	return unless $pixbuf;

	my $offy=int( ($h-$pixbuf->get_height)/2 );#center pic
	my $offx=int( ($psize-$pixbuf->get_width )/2 );

	# queue a redraw, should be fine as the picture should still be in the cache as the cache is cleared in an idle that has lower priority than the redrawing operations
	$widget->queue_draw_area($x+$offx, $y+$offy, $psize, $psize);

	# the following draw the picture immediately, but has issues of sometime the whole widget being redrawn without the pictures drawn from here
	#my $gdkwin= $widget->get_bin_window;
	#my $drawingcontext= $gdkwin->begin_draw_frame( Cairo::Region->create({x=>$x+$offx,y=>$y+$offy,width=>$psize,height=>$psize}) );
	#my $cr= $drawingcontext->get_cairo_context;
	#$cr->translate($x+$offx,$y+$offy);
	#$cr->set_source_pixbuf($pixbuf,0,0);
	#$cr->paint;
	#$gdkwin->end_draw_frame($drawingcontext);
}

package CellRendererSongsAA;
use Glib::Object::Subclass 'Gtk3::CellRenderer',
properties => [ Glib::ParamSpec->scalar
			('ref',		 #name
			 'ref',		 #nickname
			 'array : [r1,r2,row,gid]', #blurb
			 [qw/readable writable/] #flags
			),
		Glib::ParamSpec->string('aa','aa','use album or artist column', 'album',[qw/readable writable/]),
		Glib::ParamSpec->string('markup','markup','show info', '',		[qw/readable writable/]),
		];

use constant PAD => 2;

sub GET_SIZE { (0,0,-1,-1) }


sub RENDER
{	my ($cell, $cr, $widget, $background_area, $cell_area, $flags)= @_;
	my ($r1,$r2,$row,$gid)=@{ $cell->get('ref') };	#come from CellRendererSongsAA::get_value : first_row, last_row, this_row, gid
	my $field= $cell->get('aa');
	my $format=$cell->get('markup');
	my @format= $format ? (split /\n/,$format) : ();
	$format=$format[$row-$r1]; #get format line for this_row
	if ($format)
	{	my $layout= $widget->create_pango_layout;
		my $style= $widget->get_style_context;
		my $markup=AA::ReplaceFields( $gid,$format,$field,::TRUE );
		$layout->set_markup($markup);
		$style->render_layout($cr, $cell_area->{x}, $cell_area->{y}, $layout);
		return;
	}

	my($x,$y,$width,$height)= @$background_area{qw/x y width height/};
	my $xpad= $cell->get('xpad');
	$x += $xpad;
	$width-= $xpad*2;
	$y-= $height*($row-$r1 - @format);
	$height*= 1+$r2-$r1 - @format;
	my $s= $height > $width ? $width : $height;
	$s=200 if $s>200;
	$cr->translate($x,$y);
	if ( my $pixbuf= AAPicture::pixbuf($field,$gid,$s) )
	{	$cr->set_source_pixbuf($pixbuf,0,0);
		$cr->paint;
	}
	elsif (defined $pixbuf) # pixbuf not in cache -> queue its drawing
	{	my ($tx,$ty)=$widget->convert_widget_to_tree_coords($x,$y);#warn "$tx,$ty <= ($x,$y)\n";
		$cell->{queue}{$r1}=[$tx,$ty,$gid,$s,\$field];
		$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
		$cell->{widget}||=$widget;
	}
}

sub reset #not used FIXME should be reset when songlist change
{	my $cell=$_[0];
	delete $cell->{queue};
	Glib::Source->remove( $cell->{idle} ) if $cell->{idle};
	delete $cell->{idle};
}

sub idle
{	my $cell=$_[0];
	{	last unless $cell->{queue} && $cell->{widget}->get_mapped;
		my ($r1,$ref)=each %{ $cell->{queue} };
		last unless $ref;
		delete $cell->{queue}{$r1};
		_drawpix($cell->{widget},@$ref);
		last unless scalar keys %{ $cell->{queue} };
		return 1;
	}
	delete $cell->{queue};
	delete $cell->{widget};
	return $cell->{idle}=undef;
}

sub _drawpix
{	my ($widget,$ctx,$cty,$gid,$size,$fieldref)=@_; #warn "$ctx,$cty,$gid,$s\n";
	my $visible= $widget->get_visible_rect;
	my ($vx,$vy,$vw,$vh)= @$visible{qw/x y width height/};
	#warn "   $gid\n";
	return if $vx > $ctx+$size || $vy > $cty+$size || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $gid\n";
	my $pixbuf= AAPicture::pixbuf($$fieldref,$gid,$size,::TRUE);
	return unless $pixbuf;
	my ($x,$y)=$widget->convert_tree_to_widget_coords($ctx,$cty);#warn "$ctx,$cty => ($x,$y)\n";

	# queue a redraw, should be fine as the picture should still be in the cache as the cache is cleared in an idle that has lower priority than the redrawing operations
	#$widget->queue_draw_area($x, $y, $size, $size);
	$widget->get_bin_window->invalidate_rect({x=>$x,y=>$y,width=>$size,height=>$size});

	# the following draw the picture immediately, but has issues of sometime the whole widget being redrawn without the pictures drawn from here
	#my $gdkwin= $widget->get_bin_window;
	#my $drawingcontext= $gdkwin->begin_draw_frame( Cairo::Region->create({x=>$x,y=>$y,width=>$size,height=>$size}) );
	#my $cr= $drawingcontext->get_cairo_context;
	#$cr->translate($x,$y);
	#$cr->set_source_pixbuf($pixbuf,0,0);
	#$cr->paint;
	#$gdkwin->end_draw_frame($drawingcontext);
}

sub get_value
{	my ($field,$array,$row)=@_;
	my $r1=my $r2=$row;
	my $gid=Songs::Get_gid($array->[$row],$field);
	$r1-- while $r1>0	 && Songs::Get_gid($array->[$r1-1],$field) == $gid; #find first row with this gid
	$r2++ while $r2<$#$array && Songs::Get_gid($array->[$r2+1],$field) == $gid; #find last row with this gid
	return [$r1,$r2,$row,$gid];
}

package GMB::Cloud;
use Glib::Object::Subclass
  Gtk3::DrawingArea::,
	interfaces => [Gtk3::Scrollable::],
	properties => [Glib::ParamSpec->object ('hadjustment','hadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->object ('vadjustment','vadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->enum   ('hscroll-policy','hpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		       Glib::ParamSpec->enum   ('vscroll-policy','vpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		      ],
	;

use constant
{	XPAD => 6,	YPAD => 6, #lower padding values may cause the focus indicator to be drawn on the text
};

sub GET_BORDER
{	return ::FALSE,undef;
}

sub new2
{	my ($class,$selectsub,$getdatasub,$activatesub,$menupopupsub,$displaykeysub)=@_;
	my $self= GMB::Cloud->new;
	$self->set_can_focus(::TRUE);
	$self->add_events([qw/button-press-mask scroll-mask/]);
	$self->get_style_context->add_class(Gtk3::STYLE_CLASS_VIEW);
	#$self->get_style_context->add_class(Gtk3::STYLE_CLASS_CELL);

	$self->signal_connect(draw		=> \&draw_cb);
	$self->signal_connect(focus_out_event	=> \&focus_change);
	$self->signal_connect(focus_in_event	=> \&focus_change);
	$self->signal_connect(configure_event	=> \&configure_cb);
	$self->signal_connect(drag_begin	=> \&drag_begin_cb);
	$self->signal_connect(button_press_event=> \&button_press_cb);
	$self->signal_connect(button_release_event=> \&button_release_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->{selectsub}=$selectsub;
	$self->{get_fill_data_sub}=$getdatasub;
	$self->{activatesub}=$activatesub;
	$self->{menupopupsub}=$menupopupsub;
	$self->{displaykeysub}=$displaykeysub;
	$self->{selected}={};
	return $self;
}

sub get_selected
{	sort keys %{$_[0]{selected}};
}
sub reset_selection
{	$_[0]{selected}={};
	$_[0]{lastclick}=undef;
	$_[0]{startgrow}=undef;
}

sub Fill	#FIXME should be called when signals ::style-set and ::direction-changed are received because I keep layout objects
{	my ($self)=@_;
	my ($list,$href)= $self->{get_fill_data_sub}($self);
	my $width= $self->get_allocated_width;
	my $height= $self->get_allocated_height;

	if ($width<2 && !$self->{delayed}) {$self->{delayed}=1;::IdleDo('2_resizecloud'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};
	delete $::ToDo{'2_resizecloud'.$self};

	unless (keys %$href)
	{	$self->set_size_request(-1,-1);
		$self->queue_draw;
		$self->{lines}=[];
		return;
	}
	my $filterlist= $self->GET_ancestor('FilterList');	#FIXME should get its options another way (to keep GMB::Cloud generic)
	my $scalemin= ($filterlist->{cloud_min}||6) /10;
	my $scalemax= ($filterlist->{cloud_max}||20) /10;
	warn "Cloud : scalemin=$scalemin scalemax=$scalemax\n" if $::debug;
	$scalemax=$scalemin+.5 if $scalemin>=$scalemax;
	$scalemax-=$scalemin;
	$self->{width}=$width;
	my $lastkey;
	if ($self->{lastclick})
	{	my ($i,$j)=@{ delete $self->{lastclick} };
		$lastkey=$self->{lines}[$i+2][$j+4];
	}
	my @lines;
	$self->{lines}=\@lines;
	my $line=[];
	my ($min,$max)=(0,1);
	#for (values %$href) {$max=$_ if $max<$_}
	for (map $href->{$_}, @$list) {$max=$_ if $max<$_}
	if ($min==$max) {$max++;$min--;}
	my ($x,$y)=(XPAD,YPAD); my ($hmax,$bmax)=(0,0);
	my $displaykeysub=$self->{displaykeysub};
	my $inverse= ($self->get_direction eq 'rtl');
	::setlocale(::LC_NUMERIC,'C'); #for the sprintf in the loop
	my $pango_context= $self->get_pango_context;
	for my $key (@$list)
	{	my $layout= Pango::Layout->new($pango_context);
		my $value=sprintf '%.1f', $scalemin + $scalemax*($href->{$key}-$min)/($max-$min);
		my $text= $displaykeysub ? $displaykeysub->($key) : $key;
		$layout->set_markup('<span size="'.(10240*$value).'"> '.::PangoEsc($text).'</span> ');
		my ($w,$h)=$layout->get_pixel_size;
		my $bl= $layout->get_iter->get_baseline / Pango->SCALE;
		if ( $x+$w+XPAD > $width )
		{	push @lines, $y,$y+$bmax,$line;
			$x=XPAD; $y+=YPAD*2+$bmax; $hmax=$bmax=0;
			$line=[];
		}
		if (defined $lastkey && $lastkey eq $key)
		 { $lastkey=undef; $self->{lastclick}=[scalar@lines,scalar@$line]; }
		if ($inverse)	{ unshift @$line, $width-$x-$w, $width-$x, $bl,$layout,$key; }
		else		{ push	  @$line, $x,		$x+$w,	   $bl,$layout,$key; }
		#push @$line, $x,$x+$w,$bl,$layout,$key;
		$hmax=$h if $h>$hmax; $bmax=$bl if $bl>$bmax;
		$x+=$w+XPAD*2;
	}
	::setlocale(::LC_NUMERIC,'');
	push @lines, $y,$y+$bmax,$line;
	$y+=YPAD+$bmax;
	$self->set_size_request(50,-1);
	my $adj= $self->get_vadjustment;
	$adj->set_upper($y);
	$self->queue_draw;
}

sub configure_cb
{	my ($self,$event)=@_;
	return if !$self->{width} || $self->{width} eq $event->width;
	$self->get_vadjustment->set_page_size($event->height);
	::IdleDo('2_resizecloud'.$self,500,\&Fill,$self);
}

sub focus_change
{	my $self=$_[0];
	my $sel=$self->{selected};
	return unless keys %$sel;
	#FIXME could redraw only selected keys
	$self->queue_draw;
	0;
}

sub draw_cb
{	my ($self,$cr)=@_;
	my $yoffset= $self->get_vadjustment->get_value;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)= $cr->clip_extents;
	my $style= $self->get_style_context;
	$style->render_background($cr, $exp_x1, $exp_y1, $exp_x2-$exp_x1, $exp_y2-$exp_y1);

	my $lines=$self->{lines};
	my ($lasti,$lastj)= @{ $self->{lastclick} || [-1,-1] };

	for (my $i=0; $i<=$#$lines; $i+=3)
	{	my ($y1,$y2,$line)=@$lines[$i,$i+1,$i+2];
		$y2-= $yoffset;
		next unless $y2>$exp_y1;
		$y1-= $yoffset;
		last if $y1>$exp_y2;
		for (my $j=0; $j<=$#$line; $j+=5)
		{	my ($x1,$x2,$bl,$layout,$key)=@$line[$j..$j+4];
			next unless $x2>$exp_x1;
			last if $x1>$exp_x2;
			my $restore;
			if (exists $self->{selected}{$key})
			{	$restore=1;
				$style->save;
				$style->set_state( $style->get_state + 'selected' );
				# render selected background
				$style->render_background($cr, $x1-XPAD, $y1-YPAD, $x2-$x1+XPAD*2, $y2-$y1+YPAD*2);
			}
			# render text
			$style->render_layout($cr,$x1,$y2-$bl,$layout);
			# render focus indicator
			if ($lasti==$i && $lastj==$j) { $style->render_focus($cr, $x1-XPAD, $y1-YPAD, $x2-$x1+XPAD*2, $y2-$y1+YPAD*2); }
			$style->restore if $restore;
		}
	}
	::TRUE;
}

sub button_press_cb
{	my ($self,$event)=@_;
	$self->grab_focus;
	my $but=$event->button;
	if ($event->type eq '2button-press')
	{	$self->{activatesub}($self,$but);
		return 1;
	}
	if ($but==1)
	{	my ($i,$j,$key)=$self->coord_to_index($event->get_coords);
		return 0 unless defined $j;
		if ( $event->get_state * ['shift-mask', 'control-mask'] || !exists $self->{selected}{$key} )
			{ $self->key_selected($event,$i,$j);}
		else	{ $self->{pressed}=1; }
		return 0;
	}
	if ($but==3)
	{	my ($i,$j,$key)=$self->coord_to_index($event->get_coords);
		if (defined $key && !exists $self->{selected}{$key})
		{	$self->key_selected($event,$i,$j);
		}
		$self->{menupopupsub}($self,undef,$event);
		return 1;
	}
	1;
}
sub button_release_cb
{	my ($self,$event)=@_;
	return 0 unless $event->button==1 && $self->{pressed};
	$self->{pressed}=undef;
	my ($i,$j)=$self->coord_to_index($event->get_coords);
	return 0 unless defined $j;
	$self->key_selected($event,$i,$j);
	return 1;
}
sub drag_begin_cb
{	$_[0]->{pressed}=undef;
}

sub get_cursor_row
{	my $self=$_[0];
	return 0 unless $self->{lastclick};
	my ($ci,$cj)=@{$self->{lastclick}};
	my $row=0;
	my $lines=$self->{lines};
	for (my $i=0; $i<=$#$lines; $i+=3)
	{	my $line=$lines->[$i+2];
		for (my $j=0; $j<=$#$line; $j+=5)
		{	return $row if $i==$ci && $j==$cj;
			$row++;
		}
	}
	return 0;
}
sub set_cursor_to_row
{	my ($self,$row)=@_;
	my $lines=$self->{lines};
	for (my $i=0; $i<=$#$lines; $i+=3)
	{	my $line=$lines->[$i+2];
		for (my $j=0; $j<=$#$line; $j+=5)
		{	unless ($row--) { $self->key_selected(undef,$i,$j); return }
		}
	}
}

sub select_all
{	my $self=shift;
	my $selected=$self->{selected};
	my $lines=$self->{lines};
	for (my $i=0; $i<=$#$lines; $i+=3)
	{	my $line=$lines->[$i+2];
		for (my $j=0; $j<=$#$line; $j+=5)
		{	my $key=$line->[$j+4];
			$selected->{$key}=undef;
		}
	}
	$self->queue_draw;
	$self->{selectsub}($self);
}

sub key_selected
{	my ($self,$event,$i,$j)=@_;
	$self->scroll_to_index($i,$j);
	my $key=$self->{lines}[$i+2][$j+4];
	my $selected=$self->{selected};
	unless ($event && $event->get_state >= ['control-mask'])
	{	%$selected=();
	}
	if ($event && $event->get_state >= ['shift-mask'] && $self->{lastclick})
	{	my $start=$self->{startgrow}||=$self->{lastclick};
		my ($i2,$j2)=@$start;
		my ($i1,$j1)=($i,$j);
		if ($i2<$i1 || $i2==$i1 && $j2<$j1)
		{	($i1,$j1,$i2,$j2)=($i2,$j2,$i1,$j1);
		}
		while ($i1 <= $i2)
		{	my $line=$self->{lines}[$i1+2];
			my $jmax= $i1==$i2 ? $j2 : $#$line;
			while ($j1 <= $jmax)
			{	my $key=$line->[$j1+4];
				$selected->{$key}=undef;
				$j1+=5;
			}
			$j1=0;
			$i1+=3;
		}
	}
	elsif (exists $selected->{$key})
	{	delete $selected->{$key};
		delete $self->{startgrow};
	}
	else
	{	$selected->{$key}=undef;
		delete $self->{startgrow};
	}
	$self->{lastclick}=[$i,$j];

	$self->queue_draw;
	$self->{selectsub}($self);
}

sub coord_to_index
{	my ($self,$x,$y)=@_;
	$y+= $self->get_vadjustment->get_value;
	my $lines=$self->{lines};
	my ($i,$j);
	for ($i=0; $i<=$#$lines; $i+=3)
	{	next if $y > $lines->[$i+1]+YPAD;
		last unless $y > $lines->[$i]-YPAD();
		my $line=$lines->[$i+2];
		for ($j=0; $j<=$#$line; $j+=5)
		{	next if $x > $line->[$j+1]+XPAD;
			last unless $x > $line->[$j]-XPAD();
			my $key=$line->[$j+4];
			return ($i,$j,$key);
		}
		last;
	}
}

sub scroll_to_index
{	my ($self,$i,$j)=@_;
	my ($y1,$y2)=@{$self->{lines}}[$i,$i+1];
	$self->get_parent->get_vadjustment->clamp_page($y1,$y2);
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	my $shift=$state * ['shift-mask'];
	if (($key eq 'space' || $key eq 'Return') && !$mod && !$shift)
	{	$self->{activatesub}($self,1);
		return 1;
	}
	elsif (lc$key eq 'a' && $ctrl)	{ $self->select_all; return 1; }	#ctrl-a : select-all

	my ($i,$j)=(0,0);
	($i,$j)=@{$self->{lastclick}} if $self->{lastclick};
	my $lines=$self->{lines};
	my $jmax=@{$lines->[$i+2]}-5;
	my $j_check;
	if ($key eq 'Left')
	{	if	($j>4) {$j-=5}
		elsif	($i>2) {$i-=3; $j_check=2;}
	}
	elsif ($key eq 'Right')
	{	if	( $j < $jmax )		{$j+=5}
		elsif	( $i< @$lines-3 )	{$i+=3;$j=0;}
	}
	elsif ($key eq 'Up')
	{	if	($i>2)	{$i-=3; $j_check=1; }
		else		{$j=0}
	}
	elsif ($key eq 'Down')
	{	if ( $i< @$lines-3 )	{$i+=3; $j_check=1;}
		else			{$j=$jmax;}
	}
	else {return 0}
	if ($j_check)
	{	$jmax=@{$lines->[$i+2]}-5;
		$j=$jmax if $j_check==2 || $j > $jmax;
	}
	$self->key_selected($event,$i,$j);
	return 1;
}

package GMB::Mosaic;
use Glib::Object::Subclass
  Gtk3::Widget::,
	interfaces => [Gtk3::Scrollable::],
	properties => [Glib::ParamSpec->object ('hadjustment','hadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->object ('vadjustment','vadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->enum   ('hscroll-policy','hpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		       Glib::ParamSpec->enum   ('vscroll-policy','vpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		      ],
	;

use constant
{	XPAD => 2,	YPAD => 2,
};

sub GET_BORDER
{	return ::FALSE,undef;
}

sub new
{	my ($class,$selectsub,$getdatasub,$activatesub,$menupopupsub,$field,$vscroll)=@_;
	my $self= bless Gtk3::DrawingArea->new, $class;
	$self->get_style_context->add_class(Gtk3::STYLE_CLASS_VIEW);
	$self->set_can_focus(::TRUE);
	$self->set_has_tooltip(::TRUE);
	$self->add_events([qw/button-press-mask pointer-motion-mask leave-notify-mask scroll-mask/]);
	$self->{vscroll}=$vscroll;
	$vscroll->get_adjustment->signal_connect(value_changed => \&scroll,$self);
	$self->signal_connect(scroll_event	=> \&scroll_event_cb);
	$self->signal_connect(draw		=> \&draw_cb);
	$self->signal_connect(focus_out_event	=> \&focus_change);
	$self->signal_connect(focus_in_event	=> \&focus_change);
	$self->signal_connect(configure_event	=> \&configure_cb);
	$self->signal_connect(drag_begin	=> \&GMB::Cloud::drag_begin_cb);
	$self->signal_connect(button_press_event=> \&GMB::Cloud::button_press_cb);
	$self->signal_connect(button_release_event=> \&GMB::Cloud::button_release_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(query_tooltip	=> \&query_tooltip_cb);
	$self->{selectsub}=$selectsub;
	$self->{get_fill_data_sub}=$getdatasub;
	$self->{activatesub}=$activatesub;
	$self->{menupopupsub}=$menupopupsub;
	$self->{field}=$field;
	$self->{lastdy}=0;

	return $self;
}

sub get_selected
{	sort keys %{$_[0]{selected}};
}
sub reset_selection
{	$_[0]{selected}={};
	$_[0]{lastclick}=undef;
	$_[0]{startgrow}=undef;
}

sub Fill
{	my ($self,$samelist)=@_;
	my $width= $self->get_allocated_width;
	my $height=$self->get_allocated_height;
	if ($width<2 && !$self->{delayed}) { $self->{delayed}=1; ::IdleDo('2_resizemosaic'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};
	delete $::ToDo{'2_resizemosaic'.$self};
	$self->abort_queue;
	$self->{width}=$width;

	my $list=$self->{list};
	($list)= $self->{get_fill_data_sub}($self) unless $samelist && $samelist eq 'samelist';

	my $filterlist= $self->GET_ancestor('FilterList');	#FIXME should get its options another way
	my $mpsize=$filterlist->{mpicsize}||64;
	$self->{picsize}=$mpsize;
	$self->{hsize}=$mpsize;
	$self->{vsize}=$mpsize;

	$self->{markup}= $self->{markup_pos}= '';
	if ($filterlist->{mmarkup})
	{	$self->{markup_pos}= $filterlist->{mmarkup};
		$self->{markup}= my $markup= $self->{field} eq 'album'  ? "<small><b>%a</b></small>\n<small>%b</small>"
									: "<small><b>%a</b></small>\n<small>%X</small>";
		my @heights;
		for my $m (split /\n/, $markup)
		{	my $lay=$self->create_pango_layout($m);
			push @heights, ($lay->get_pixel_size)[1];
		}
		$self->{markup_heights}=\@heights;
		if ($self->{markup_pos} eq 'right')
		{	$self->{markup_width}= ::max(120,$mpsize*1.2);
			$self->{hsize}+=$self->{markup_width};
		}
		else
		{	$self->{markup_width}=$mpsize;
			$self->{vsize}+= 2*YPAD;
			$self->{vsize}+=$_ for @heights;
		}
	}

	my $nw= int($width / ($self->{hsize}+2*XPAD)) || 1;
	my $nh= int(@$list/$nw);
	my $nwlast= @$list % $nw;
	$nh++ if $nwlast;
	$nwlast=$nw unless $nwlast;
	$self->{dim}=[$nw,$nh,$nwlast];
	$self->{list}=$list;
	$self->set_size_request($self->{hsize}+2*XPAD,$self->{vsize}+2*YPAD);
	$self->{viewsize}[1]= $nh*($self->{vsize}+2*YPAD);
	$self->{viewwindowsize}=[$width,$height];
	$self->update_scrollbar;
	$self->queue_draw;
}

sub update_scrollbar
{	my $self=$_[0];
	my $scroll= $self->{vscroll};
	my $pagesize=$self->{viewwindowsize}[1]||0;
	my $upper=$self->{viewsize}[1]||0;
	my $adj=$scroll->get_adjustment;
	my $oldpos=  $adj->get_value;
	my $oldupper=$adj->get_upper;
	# calculate the old position in a 0 to 1 scale
	$oldpos= !($oldupper && $oldpos) ?			0: # at the beginning => stay there
		 $oldupper<=$oldpos+$adj->get_page_size ?	1: # at the end => stay there
							($adj->get_page_size/2+$oldpos) / $oldupper; #base position on middle of current position
	$adj->set_page_size($pagesize);
	if ($upper>$pagesize)	{$scroll->show; $scroll->queue_draw; }
	else			{$scroll->hide; $upper=0;}
	$adj->set_upper($upper);
	$adj->set_step_increment($pagesize*.125);
	$adj->set_page_increment($pagesize*.75);
	my $newval= $oldpos*$upper - $adj->get_page_size/2;
	$newval= $upper-$pagesize if $newval > $upper-$pagesize;
	$newval=0 if $newval<0;
	$adj->set_value($newval);
}
sub scroll_event_cb
{	my ($self,$event,$pageinc)=@_;
	my $dir= ref $event ? $event->direction : $event;
	$dir= $dir eq 'up' ? -1 : $dir eq 'down' ? 1 : 0;
	return unless $dir;
	if ($event->state >= 'control-mask')	# increase/decrease picture size
	{	my $filterlist= $self->GET_ancestor('FilterList');
		my $size= $filterlist->{mpicsize} - 8*$dir;
		return if $size<16 || $size>1024;
		$filterlist->SetOption(mpicsize=>$size);
		return 1;
	}
	my $adj=$self->{vscroll}->get_adjustment;
	my $max= $adj->get_upper - $adj->get_page_size;
	my $value= $adj->get_value + $dir* ($pageinc? $adj->get_page_increment : $adj->get_step_increment);
	$value=$max if $value>$max;
	$value=0 if $value<0;
	$adj->set_value($value);
	1;
}
sub scroll
{	my ($adj,$self)=@_;
	my $new= int $adj->get_value;
	my $old=$self->{lastdy};
	return if $new==$old;
	$self->{lastdy}=$new;
	$self->get_window->scroll(0,$old-$new); #copy still valid parts and queue_draw new parts
}

sub query_tooltip_cb
{	my ($self,$x,$y,$keyboard,$tooltip)=@_;
	return ::FALSE if $keyboard;
	my ($i,$j,$key)=$self->coord_to_index($x,$y);
	return ::FALSE unless defined $key;
	my ($rx,$ry,$rw,$rh)=$self->index_to_rect($i,$j);
	$tooltip->set_tip_area({x=>$rx, y=>$ry, width=>$rw, height=>$rh});
	$tooltip->set_markup( AA::ReplaceFields($key,"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",$self->{field},1) );
	return ::TRUE;
}

sub configure_cb		## FIXME I think it redraws everything even when it's not needed
{	my ($self,$event)=@_;
	return 1 unless $self->{width};
	$self->{viewwindowsize}=[$event->width,$event->height];
	my $iw= $self->{hsize}+2*XPAD;
	if ( int($self->{width}/$iw) == int($event->width/$iw))
	{	$self->update_scrollbar;
		return 1;
	}
	$self->abort_queue;
	::IdleDo('2_resizecloud'.$self,100,\&Fill,$self,'samelist');
	return 1;
}

sub draw_cb
{	my ($self,$cr)=@_;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)= $cr->clip_extents;
	my $dy=int $self->{vscroll}->get_adjustment->get_value;
	$self->{lastdy}=$dy;
	my $style= $self->get_style_context;
	$style->render_background($cr, $exp_x1, $exp_y1, $exp_x2-$exp_x1, $exp_y2-$exp_y1);
	return unless $self->{list};

	my $field=$self->{field};
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $list=$self->{list};
	my $vsize=$self->{vsize};
	my $hsize=$self->{hsize};
	my $picsize=$self->{picsize};
	my @markup= $self->{markup} ? (split /\n/,$self->{markup}) : ();
	my $markup_width= $self->{markup_width};
	my $mheights= $self->{markup_heights};
	my $i1=int($exp_x1/($hsize+2*XPAD));
	my $i2=int($exp_x2/($hsize+2*XPAD));
	my $j1=int(($dy+$exp_y1)/($vsize+2*YPAD));
	my $j2=int(($dy+$exp_y2)/($vsize+2*YPAD));
	$i2=$nw-1 if $i2>=$nw;
	$j2=$nh-1 if $j2>=$nh;
	for my $j ($j1..$j2)
	{	my $y=$j*($vsize+2*YPAD)+YPAD - $dy;
		$i2=$nwlast-1 if $j==$nh-1;
		for my $i ($i1..$i2)
		{	my $pos=$i+$j*$nw;
			#last if $pos>$#$list;
			my $key=$list->[$pos];
			my $x=$i*($hsize+2*XPAD)+XPAD;
			my $restore;
			if (exists $self->{selected}{$key})
			{	$restore=1;
				$style->save;
				$style->set_state( $style->get_state + 'selected' );
				# render selected background
				$style->render_background($cr, $x-XPAD, $y-YPAD, $hsize+XPAD*2, $vsize+YPAD*2);
			}
			my $pixbuf= AAPicture::draw($cr,$x,$y,$field,$key,$picsize);
			if ($pixbuf) {}
			elsif (defined $pixbuf)
			{	$self->{idle}||=Glib::Idle->add(\&idle,$self);
				$self->{queue}{$i+$j*$nw}=[$x,$y+$dy,$key,$picsize];
			}
			elsif (!@markup) # draw text in place of picture if no picture
			{	my $layout= $self->create_pango_layout;
				$layout->set_markup(AA::ReplaceFields($key,"<small>%a</small>",$field,1));
				$layout->set_wrap('word-char');
				$layout->set_width($hsize * Pango->SCALE);
				$layout->set_height($vsize * Pango->SCALE);
				my $yoffset=0;
				my (undef,$logical_rect)= $layout->get_pixel_extents;
				my $free_height= $vsize - $logical_rect->{height};
				if ($free_height>1) { $yoffset= int($free_height/2); }	#center vertically
				$layout->set_ellipsize('end');
				$layout->set_alignment('center');
				$cr->save;
				$cr->rectangle($x,$y,$hsize,$vsize);
				$cr->clip;
				$style->render_layout($cr,$x,$y+$yoffset,$layout);
				$cr->restore;
				$style->restore if $restore;
				next;
			}
			# draw text below or beside picture
			my ($xm,$ym,$align)= $self->{markup_pos} eq 'right' ? ($x+$picsize+XPAD,$y,'left') : ($x,$y+$picsize+YPAD,'center');
			my $i=0;
			for my $markup (@markup)
			{	my $layout= $self->create_pango_layout;
				$layout->set_markup(AA::ReplaceFields($key,$markup,$field,1));
				$layout->set_width($markup_width * Pango->SCALE);
				$layout->set_alignment($align);
				my $height= $mheights->[$i++];
				$layout->set_height($height * Pango->SCALE);
				$layout->set_ellipsize('end');
				$cr->save;
				$cr->rectangle($xm,$ym,$markup_width,$height);
				$cr->clip;
				$style->render_layout($cr,$xm,$ym,$layout);
				$cr->restore;
				$ym+=$height;
			}
			$style->restore if $restore;
		}
	}
	1;
}

sub focus_change
{	my $self=$_[0];
	$self->redraw_keys($self->{selected});
	0;
}

sub coord_to_index
{	my ($self,$x,$y)=@_;
	$y+=int $self->{vscroll}->get_adjustment->get_value;
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $i=int($x/($self->{hsize}+2*XPAD));
	return undef if $i>=$nw;
	my $j=int($y/($self->{vsize}+2*YPAD));
	return undef if $j>=$nh;
	return undef if $j==$nh-1 && $i>=$nwlast;
	my $key=$self->{list}[$i+$j*$nw];
	return $i,$j,$key;
}
sub index_to_rect
{	my ($self,$i,$j)=@_;
	my $x=$i*($self->{hsize}+2*XPAD)+XPAD;
	my $y=$j*($self->{vsize}+2*YPAD)+YPAD;
	$y-=int $self->{vscroll}->get_adjustment->get_value;
	return $x,$y,$self->{hsize},$self->{vsize};
}

sub redraw_keys
{	my ($self,$keyhash)=@_;
	return unless keys %$keyhash;
	my $hsize2=$self->{hsize}+2*XPAD;
	my $vsize2=$self->{vsize}+2*YPAD;
	my $y=int $self->{vscroll}->get_adjustment->get_value;
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $height= $self->{viewwindowsize}[1];
	my $j1=int($y/($self->{vsize}+2*YPAD));
	my $j2=int(($y+$height)/($self->{vsize}+2*YPAD));
	for my $j ($j1..$j2)
	{	for my $i (0..$nw-1)
		{	my $key=$self->{list}[$i+$j*$nw];
			next unless defined $key;
			next unless exists $keyhash->{$key};
			$self->queue_draw_area($i*$hsize2,$j*$vsize2-$y,$hsize2,$vsize2);
		}
	}
}

sub key_selected
{	my ($self,$event,$i,$j)=@_;
	$self->scroll_to_row($j);
	my ($nw)=@{$self->{dim}};
	my $list=$self->{list};
	my $pos=$i+$j*$nw;
	my $key=$list->[$pos];
	my $selected=$self->{selected};
	my %changed;
	$changed{$_}=1 for keys %$selected;
	unless ($event && $event->get_state >= ['control-mask'])
	{	%$selected=();
	}
	if ($event && $event->get_state >= ['shift-mask'] && defined $self->{lastclick})
	{	$self->{startgrow}=$self->{lastclick} unless defined $self->{startgrow};
		my $i1=$self->{startgrow};
		my $i2=$pos;
		($i1,$i2)=($i2,$i1) if $i1>$i2;
		$selected->{ $list->[$_] }=undef for $i1..$i2;
	}
	elsif (exists $selected->{$key})
	{	delete $selected->{$key};
		delete $self->{startgrow};
	}
	else
	{	$selected->{$key}=undef;
		delete $self->{startgrow};
	}
	$self->{lastclick}=$pos;
	$changed{$_}-- for keys %$selected;
	$changed{$_} or delete $changed{$_} for keys %changed;
	$self->redraw_keys(\%changed);
	$self->{selectsub}($self);
}

sub get_cursor_row
{	my $self=$_[0];
	return $self->{lastclick}||0;
}
sub set_cursor_to_row
{	my ($self,$row)=@_;
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $i=$row % $nw;
	my $j=int($row/$nw);
	$self->key_selected(undef,$i,$j);
}

sub scroll_to_row
{	my ($self,$j)=@_;
	my $y1=$j*($self->{vsize}+2*YPAD)+YPAD;
	my $y2=$y1+$self->{vsize};
	$self->{vscroll}->get_adjustment->clamp_page($y1,$y2);
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	my $shift=$state * ['shift-mask'];
	if ( ($key eq 'space' || $key eq 'Return') && !$mod && !$shift )
	{	$self->{activatesub}($self,1);
		return 1;
	}
	my $pos=0;
	$pos=$self->{lastclick} if $self->{lastclick};
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $page= int($self->{vscroll}->get_adjustment->get_page_size / ($self->{vsize}+2*YPAD));
	my $i=$pos % $nw;
	my $j=int($pos/$nw);
	if	($key eq 'Left')	{$i--}
	elsif	($key eq 'Right')	{$i++}
	elsif	($key eq 'Up')		{$j--}
	elsif	($key eq 'Down')	{$j++}
	elsif	($key eq 'Home')	{$i=$j=0; }
	elsif	($key eq 'End')		{$i=$nwlast-1; $j=$nh-1;}
	elsif	($key eq 'Page_Up')	{ $j-=$page; }
	elsif	($key eq 'Page_Down')	{ $j+=$page; }
	elsif	(lc$key eq 'a' && $ctrl)							#ctrl-a : select-all
		{ $self->{selected}{$_}=undef for @{ $self->{list} }; $self->queue_draw; $self->{selectsub}($self); return 1; }
	else {return 0}
	if	($i<0)		{$j--;$i=$nw-1;}
	elsif	($i>=$nw)	{$j++;$i=0;}
	if	($j<0)		{$j=0;$i=0}
	elsif	($j==$nh-1)	{$i=$nwlast-1 if $i>=$nwlast}
	elsif	($j>$nh-1)	{$j=$nh-1; $i=$nwlast-1 }
	$self->key_selected($event,$i,$j);
	return 1;
}

sub abort_queue
{	my $self=$_[0];
	delete $self->{queue};
	Glib::Source->remove( $self->{idle} ) if $self->{idle};
	delete $self->{idle};
}

sub idle
{	my $self=$_[0];
	{	last unless $self->{queue} && $self->get_mapped;
		my ($y,$ref)=each %{ $self->{queue} };
		last unless $ref;
		delete $self->{queue}{$y};
		_drawpix($self,@$ref);
		last unless scalar keys %{ $self->{queue} };
		return 1;
	}
	delete $self->{queue};
	return $self->{idle}=undef;
}

sub _drawpix
{	my ($self,$x,$y,$key,$s)=@_;
	my $vadj=$self->{vscroll}->get_adjustment;
	my $dy=int $vadj->get_value;
	my $page=$vadj->get_page_size;
	return if $dy > $y+$s || $dy+$page < $y; #no longer visible

	my $gdkwin= $self->get_window;
	my $drawingcontext= $gdkwin->begin_draw_frame( Cairo::Region->create({x=>$x,y=>$y-$dy,width=>$s,height=>$s}) );
	my $cr= $drawingcontext->get_cairo_context;
	AAPicture::draw($cr,$x,$y-$dy,$self->{field},$key, $s,::TRUE);
	$gdkwin->end_draw_frame($drawingcontext);
}

package GMB::ISearchBox;	#interactive search box (search as you type)
use base 'Gtk3::Box';

our %OptCodes=
(	casesens => 'i',	onlybegin => 'b',	onlyword => 'w',	hidenomatch => 'h',
);
our @OptionsMenu=
(	{ label => _"Case-sensitive",	toggleoption => 'self/casesens',	code => sub { $_[0]{self}->changed; }, },
	{ label => _"Begin with",	toggleoption => 'self/onlybegin',	code => sub { $_[0]{self}{onlyword}=0; $_[0]{self}->changed;}, },
	{ label => _"Words that begin with",	toggleoption => 'self/onlyword',code => sub { $_[0]{self}{onlybegin}=0; $_[0]{self}->changed;},	},
	{ label => _"Hide non-matching",toggleoption=> 'self/hidenomatch',	code => sub { $_[0]{self}{close_button}->set_visible($_[0]{self}{hidenomatch}); $_[0]{self}->changed;}, test=> sub { $_[0]{self}{type} } },
	{ label => _"Fields",		submenu => sub { return {map { $_=>Songs::FieldName($_) } Songs::StringFields}; }, submenu_reverse => 1,
	  check => 'self/fields',	test => sub { !$_[0]{self}{type} },
	  code => sub { my $toggle=$_[1]; my $l=$_[0]{self}{fields}; my $n=@$l; @$l=grep $toggle ne $_, @$l; push @$l,$toggle if @$l==$n; @$l=('title') unless @$l; $_[0]{self}->changed; }, #toggle selected field
	},
);

sub new					##currently the returned widget must be put in ->{isearchbox} of a parent widget, and this parent must have the array to search in ->{array} and have the methods get_cursor_row and set_cursor_to_row. And also select_by_filter for SongList/SongTree
{	my ($class,$opt,$type,$nolabel)=@_;
	my $self= bless Gtk3::HBox->new(0,0), $class;
	$self->{type}=$type;

	#restore options
	my $optcodes= $opt->{isearch} || '';
	for my $key (keys %OptCodes)
	{	$self->{$key}=1 if index($optcodes, $OptCodes{$key}) !=-1;
	}
	unless ($type) { $self->{fields}= [split /\|/, ($opt->{isearchfields} || 'title')]; }

	$self->{entry}= my $entry= Gtk3::Entry->new;
	$entry->signal_connect( changed => \&changed );
	$entry->signal_connect(key_press_event	=> \&key_press_event_cb);
	my $select=::NewIconButton('gtk-index',	undef, \&select,'none',_"Select matches");
	my $next=::NewIconButton('go-down-symbolic',	($nolabel ? undef : _"Next"),	 \&button_cb,'none');
	my $prev=::NewIconButton('go-up-symbolic',	($nolabel ? undef : _"Previous"),\&button_cb,'none');
	$prev->{is_previous}=1;
	my $close= $self->{close_button}= ::NewIconButton('window-close-symbolic', undef, \&close,'none');
	my $label= Gtk3::Label->new(_"Find :");
	my $options=Gtk3::Button->new;
	$options->add(Gtk3::Image->new_from_stock('emblem-system-symbolic','menu'));
	$options->signal_connect( button_press_event => \&PopupOpt );
	$options->set_relief('none');
	$options->set_tooltip_text(_"options");

	# when text not found: currently use 'warning' class from theme, could use a custom 'notfound' one, and define it as having a red background here
	$entry->set_name('isearchbox_entry');
	#my $css= Gtk3::CssProvider->new; # make it global ?  add_provider_for_screen
	#$css->load_from_data("#isearchbox_entry.notfound { background-color: #f3a5b5; }");
	#$entry->get_style_context->add_provider($css,Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION );
	$self->{class_notfound}='warning'; #or "error" or a custom "notfound"

	$self->pack_start($close,0,0,0);
	$self->pack_start($label,0,0,2) unless $nolabel;
	$self->add($entry);
	#$_->set_focus_on_click(0) for $prev,$next,$options;
	$self->pack_start($_,0,0,0) for $prev,$next;
	$self->pack_start($select,0,0,0) unless $self->{type};
	$self->pack_end($options,0,0,0);
	$self->show_all;
	$self->set_no_show_all(1);
	$self->hide;
	$close->set_no_show_all(1);
	$close->hide unless $self->{hidenomatch};

	return $self;
}

sub SaveOptions
{	my $self=$_[0];
	my $opt=join '', map $OptCodes{$_}, grep $self->{$_}, sort keys %OptCodes;
	my @opt;
	push @opt, isearch => $opt if $opt ne '';
	unless ($self->{type}) { push @opt, isearchfields => join '|',@{$self->{fields}}; }
	return @opt;
}

sub set_colors
{	my ($self,$mode)=@_;	#mode : -1 not found, 0 : neutral, 1 : found
	my $style= $self->{entry}->get_style_context;
	my $class= $self->{class_notfound};
	if ($mode==-1)
	{	$style->add_class($class);
	}
	else
	{	$style->remove_class($class);
	}
}

sub key_press_event_cb	# hide with Escape
{	my ($entry,$event)=@_;
	return 0 unless Gtk3::Gdk::keyval_name($event->keyval) eq 'Escape';
	my $self= $entry->GET_ancestor;
	my $newfocus= $self->Get_listwidget;
	$newfocus= $newfocus->{DefaultFocus} while $newfocus->{DefaultFocus};
	$newfocus->grab_focus;
	$self->close;
	return 1;
}
sub close
{	my $self= $_[0]->GET_ancestor;
	if ($self->{hidenomatch}) { $self->{entry}->set_text(''); $self->hide; }
}

sub parent_has_focus
{	my $self=shift;
	$self->hide unless length($self->{entry}->get_text) && $self->{hidenomatch};
}

sub begin
{	my ($self,$text)=@_;
	$self->show;
	my $entry=$self->{entry};
	$entry->grab_focus;
	if (defined $text)
	{	$entry->set_text($text);
		$entry->set_position(-1);
	}
	else {	$self->set_colors(0); }
}

sub changed
{	my $self= $_[0]->GET_ancestor;
	$self->{searchsub}=undef;
	my $entry=$self->{entry};
	my $text=$entry->get_text;
	if ($text eq '' && !$self->{hidenomatch})
	{	$self->set_colors(0);
		return;
	}
	$text=::superlc($text) unless $self->{casesens};
	my $re= $self->{onlybegin} ? '^' : $self->{onlyword} ? '\b' : '';
	$re.= quotemeta $text;
	my $type= $self->{type};
	if (!$type)	#search song IDs
	{	my $fields= $self->{fields};
		my $filter= $self->{casesens} ? ':m:' : ':mi:';
		$filter.=$re;
		$filter=Filter->newadd(::FALSE,map $_.$filter, @$fields);
		my $code=$filter->singlesong_code();
		$self->{filter}=$filter;
		$self->{searchsub}= eval 'sub { my $array=$_[0]; my $rows=$_[1]; for my $row (@$rows) { local $_=$array->[$row]; return $row if '.$code.'; } return undef; }';
		#$self->{searchsub}= eval "sub { local \$_=\$_[0]; return $code }";
	}
	elsif ($self->{hidenomatch})
	{	$self->Get_listwidget->set_text_search($re,1,$self->{casesens});
	}
	else	# #search gid of type $type
	{	my $code= Songs::Code($type,'gid_to_display', GID => '$array->[$row]');
		$re= $self->{casesens} ? qr/$re/ : qr/$re/i;
		$self->{searchsub}= eval 'sub { my $array=$_[0]; my $rows=$_[1]; for my $row (@$rows) { return $row if ::superlc('.$code.')=~m/$re/; } return undef; }';
	}
	if ($@) { warn "Error compiling search code : $@\n"; $self->{searchsub}=undef; }
	$self->search(0);
}

sub select
{	my $widget=$_[0];
	my $self= $widget->GET_ancestor;
	my $parent= $self->Get_listwidget;
	$parent->select_by_filter($self->{filter}) if $self->{filter};
}
sub button_cb
{	my $widget=$_[0];
	my $self= $widget->GET_ancestor;
	my $dir= $widget->{is_previous} ? -1 : 1;
	$self->search($dir);
}
sub search
{	my ($self,$direction)=@_;
	my $search=$self->{searchsub};
	return unless $search;
	my $parent= $self->Get_listwidget;
	my $array= $parent->{array}; 				#FIXME could be better
	return unless @$array;
	my $offset=$parent->{array_offset}||0;
	my $start= $parent->get_cursor_row;
	$start-= $offset;
	my @rows= ($start..$#$array, 0..$start-1);
	shift @rows if $direction;
	@rows=reverse @rows if $direction<0;
	my $found=$search->($array,\@rows);
	if (defined $found)
	{	$parent->set_cursor_to_row($found+$offset);
		$self->set_colors(1);
	}
	else {	$self->set_colors(-1); }
}

sub Get_listwidget
{	my $parent=shift;
	$parent=$parent->get_parent until $parent->{isearchbox};	#FIXME could be better, maybe pass a package name to new and use $self->GET_ancestor($self->{targetpackage});
	return $parent;
}

sub PopupOpt
{	my $self= $_[0]->GET_ancestor;
	::PopupContextMenu(\@OptionsMenu, { self=>$self, usemenupos => 1,} );
	return 1;
}

package SongTree::ViewVBox;
use Glib::Object::Subclass
Gtk3::VBox::,
#	signals => {
#		set_scroll_adjustments => {
#			class_closure => sub {},
#			flags	      => [qw(run-last action)],
#			return_type   => undef,
#			param_types   => [Gtk3::Adjustment::, Gtk3::Adjustment::],
#		},
#	},
	interfaces => [Gtk3::Scrollable::],
	properties => [Glib::ParamSpec->object ('hadjustment','hadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->object ('vadjustment','vadj','', Gtk3::Adjustment::, [qw/readable writable construct/] ),
		       Glib::ParamSpec->enum   ('hscroll-policy','hpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		       Glib::ParamSpec->enum   ('vscroll-policy','vpol','', "Gtk3::ScrollablePolicy", "GTK_SCROLL_MINIMUM", [qw/readable writable/]),
		      ],
	;

sub GET_BORDER
{	my $songtree= $_[0]->get_parent;
	$songtree->{view}->get_border;
}

package SongTree;
use base 'Gtk3::ScrolledWindow';
our @ISA;
our %STC;
INIT { unshift @ISA, 'SongList::Common'; }

sub init_textcolumns	#FIXME support calling it multiple times => remove columns for removed fields, update added columns ?
{ for my $key (Songs::ColumnsKeys())
  {	my $align= Songs::ColumnAlign($key) ? ',x=-text:w' : '';	#right-align if Songs::ColumnAlign($key)
	$STC{$key}=
	{	title	=> Songs::FieldName($key),
		sort	=> Songs::SortField($key),
		width	=> Songs::FieldWidth($key),
		#elems	=> ['text=text(text=$'.$id.')'],
		elems	=> ['text=text(markup=playmarkup(pesc($'.$key."))$align)"],
		songbl	=>'text',
		hreq	=> 'text:h',
	};
  }
}

our %GroupSkin;
#=(	default	=> {	head => 'title:h',
#			vcollapse =>'head',
#			elems =>
#			[	'title=text(markup=\'<b><big>\'.pesc($title).\'</big></b>\',pad=4)',
#			],
#		   },
# );

our @DefaultOptions=
(	headclick	=> 'collapse', #  'select'
	# FIXME could try to get SongTree style GtkTreeView::horizontal-separator and others as default values
	songxpad	=> 4,	# space between columns
	songypad	=> 4,	# space between rows
	headers		=> 'on',
	no_typeahead	=> 0,
	cols		=> 'playandqueue title artist album year length track file lastplay playcount rating',
);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk3::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');

	#use default options for this songlist type
	my $name= 'songtree_'.$opt->{name}; $name=~s/\d+$//;
	my $default= $::Options{"DefaultOptions_$name"} || {};

	%$opt=( @DefaultOptions, %$default, %$opt );
	$self->{$_}=$opt->{$_} for qw/headclick songxpad songypad no_typeahead grouping/;

	$self->{isearchbox}=GMB::ISearchBox->new($opt);
	my $vbox=SongTree::ViewVBox->new;
	::set_biscrolling($self);
	$self->CommonInit($opt);

	$self->add($vbox);
	$self->{headerheight}=0;
	my $view= $self->{view}= SongTree::EmptyTreeView->new($self->get_hadjustment, ($opt->{headers} eq 'off'));
	$self->{vadj}= $self->get_vadjustment;
	$self->{hadj}= $self->get_hadjustment;
	$vbox->add($view);
	$vbox->pack_end($self->{isearchbox},0,0,0);
	$self->set_can_focus(::TRUE);
	$view->set_can_focus(::FALSE);
#	$self->{DefaultFocus}=$view;
	$view->add_events([qw/button-press-mask/]);
	$self->{$_}->signal_connect(value_changed => sub {$self->has_scrolled($_[0])},$_) for qw/hadj vadj/;
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(destroy		=> \&destroy_cb);
	$view->signal_connect(draw		=> \&draw_cb);
	$self->signal_connect(focus_in_event	=> sub { $_[0]->{isearchbox}->parent_has_focus; 0; });
	$self->signal_connect(focus_in_event	=> \&focus_change);
	$self->signal_connect(focus_out_event	=> \&focus_change);
	$view->signal_connect_after(size_allocate=>\&reconfigure_cb);
	#$view->signal_connect(realize		=> \&reconfigure_cb);
	$view->signal_connect(drag_begin	=> \&drag_begin_cb);
	$view->signal_connect(drag_leave	=> \&drag_leave_cb);
	$view->signal_connect(button_press_event=> \&button_press_cb);
	$view->signal_connect(button_release_event=> \&button_release_cb);
	$view->signal_connect(query_tooltip=> \&query_tooltip_cb);
	$self->SetRowTip($opt->{rowtip});

	::Watch($self,	CurSongID	=> \&CurSongChanged);
	::Watch($self,	SongArray	=> \&SongArray_changed_cb);
	::Watch($self,	SongsChanged	=> \&SongsChanged_cb);

	::set_drag($view,
	 source=>[::DRAG_ID,sub { my $view=$_[0]; my $self= $view->GET_ancestor; return ::DRAG_ID,$self->GetSelectedIDs; }],
	 dest => [::DRAG_ID,::DRAG_FILE,\&drag_received_cb],
	 motion=>\&drag_motion_cb,
		);

	#$self->{grouping}='album|pic' unless defined $self->{grouping};
	$self->{grouping}= ($self->{type}=~m/[QLA]/ ? '' : 'album|pic') unless defined $self->{grouping};

	$self->AddColumn($_) for split / +/,$opt->{cols};
	unless ($self->{cells}) { $self->AddColumn('title'); } #to ensure there is at least 1 column

	$self->{selected}='';
	$self->{lastclick}=$self->{startgrow}=-1;
	$self->set_head_columns;
	return $self;
}

sub destroy_cb
{	my $self=$_[0];
	delete $self->{$_} for keys %$self;#it's important to delete $self->{queue} to destroy references cycles, better delete all keys to be sure
}

sub SaveOptions
{	my $self=shift;
	my %opt=( $self->{isearchbox}->SaveOptions );
	$opt{$_}=$self->{$_} for qw/grouping/;
	$opt{cols}=	join ' ', map $_->{colid}, @{$self->{cells}};
	#save cols width
	$opt{colwidth}= join ' ',map $_.' '.$self->{colwidth}{$_}, sort keys %{$self->{colwidth}};
	#warn "$_ $opt{$_}\n" for sort keys %opt;
	return \%opt;
}

sub AddColumn
{	my ($self,$colid,$pos)=@_;
	return unless $STC{$colid};
	my $cells=$self->{cells}||=[];
	$pos=@{$self->{cells}} unless defined $pos;
	my $width= $self->{colwidth}{$colid} || $STC{$colid}{width} || 50;
	splice @$cells, $pos,0,GMB::Cell->new_songcol($colid,$width);
	$self->{cols_changed}=1;
	$self->update_columns if $self->{ready};
}
sub remove_column
{	my ($self,$cellnb)=@_;
	my $cell= $self->{cells}[$cellnb];
	splice @{$self->{cells}}, $cellnb, 1;
	$self->{cols_changed}=1;
	unless (@{$self->{cells}}) { $self->AddColumn('title'); } #to ensure there is at least 1 column
	$self->update_columns if $self->{ready};
}
sub update_columns
{	my ($self,$nosavepos,$change_col_width)=@_;
	my $savedpos;
	my $songswidth=0;
	if (my $ew=$self->{events_to_watch}) {::UnWatch($self->{view},$_) for keys %$ew;}
	delete $self->{events_to_watch};
	my $baseline=0;
	my $vsizesong=$self->{vsizesong};
	$vsizesong=GMB::Cell::init_songs($self,$self->{cells},$self->{songxpad},$self->{songypad}) if $self->{cols_changed};
	$self->{cols_changed}=undef;
	my %fields_to_watch;
	for my $cell (@{ $self->{cells} })
	{	my $colid=$cell->{colid};
		$cell->{width}= $self->{colwidth}{$colid} || $STC{$colid}{width} unless exists $cell->{width};
		delete $cell->{last};
		if (my $watch=$cell->{event})	{ $self->{events_to_watch}{$_}=undef for @$watch; }
		if (my $fields=$cell->{watchfields}) { $fields_to_watch{$_}=undef for @$fields; }
		$songswidth+=$cell->{width};
	}
	$self->{cells}[-1]{last}=1; #this column gets the extra width
	$self->{songswidth}=$songswidth;
	if (!$self->{vsizesong} || $self->{vsizesong}!=$vsizesong)	#if height of rows has changed
	{	$self->{vsizesong}=$vsizesong;
		#warn "new vsizesong : $vsizesong\n";
		$savedpos=$self->coord_to_path(0,int($self->{vadj}->get_page_size/2)) unless $nosavepos;
		$self->compute_height if $self->{ready};
	}
	my $w= $songswidth;
	for my $cell (reverse @{$self->{headcells}} )
	{	$w+= $cell->{left} + $cell->{right};
		$cell->{width}=$w;
		if (my $watch=$cell->{event}) { $self->{events_to_watch}{$_}=undef for @$watch; }
		if (my $fields=$cell->{watchfields}) { $fields_to_watch{$_}=undef for @$fields; }
	}
	$self->{viewsize}[0]= $w;

	$self->{fields_to_watch2}=[keys %fields_to_watch];	#FIXME could call Songs::Depends only once now rather than multiple times for each column in GMB::Expression::parse ????
	if (my $ew=$self->{events_to_watch}) {::Watch($self->{view},$_,sub {$_[0]->queue_draw;}) for keys %$ew;}

	$self->updateextrawidth(0);
	$self->scroll_to_row($savedpos->{hirow}||0,1) if $savedpos;
	$self->update_scrollbar;
	delete $self->{queue};
	$self->{view}->queue_draw;
	$self->update_sorted_column;
	$self->{view}->update unless $change_col_width;
}
sub set_head_columns
{	my ($self,$grouping)=@_;
	$grouping=$self->{grouping} unless defined $grouping;
	$self->{grouping}=$grouping;
	my @cols= $grouping=~m#([^|]+\|[^|]+)(?:\||$)#g; #split into pairs : "word|word"
	my $savedpos= $self->coord_to_path(0,int($self->{vadj}->get_page_size/2)) if $self->{ready}; #save vertical pos
	$self->{headcells}=[];
	$self->{colgroup}=[];
	$self->{songxoffset}=0;
	$self->{songxright}=0;
	my $depth=0;
	my @fields;
	if (@cols)
	{ for my $colskin (@cols)
	  {	my ($col,$skin)=split /\|/,$colskin;
		next unless $col;
		push @fields,$col;
		my $cell= GMB::Cell->new_group( $self,$depth,$col,$skin );
		#$cell->{skin}=$skin;
		$cell->{x}=$self->{songxoffset};
		$self->{songxoffset}+=$cell->{left};
		$self->{songxright}+=$cell->{right};
		#$cell->{width}=$col->{width}; #FIXME use saved width ?
		push @{$self->{colgroup}},  $col;
		push @{$self->{headcells}}, $cell;
		$depth++;
	  }
	}
	else
	{	$self->{headcells}[0]{$_}=0 for qw/left right x head tail vmin/;
	}
	$self->{fields_to_watch1}=[Songs::Depends(@fields)];

	$self->update_columns(1);
	$self->BuildTree unless $self->{need_init};
	$self->scroll_to_row($savedpos->{hirow}||0,1) if $savedpos;
}

sub set_has_tooltip { $_[0]{view}->set_has_tooltip($_[1]) }

sub GetCurrentRow
{	my $self=shift;
	my $row=$self->{lastclick};
	return $row;
}

sub GetSelectedRows
{	my $self=$_[0];
	my $songarray=$self->{array};
	return [grep vec($self->{selected},$_,1), 0..$#$songarray];
}

sub focus_change
{	my $self=$_[0];
	#my $sel=$self->{selected};
	#return unless keys %$sel;
	#FIXME could redraw only selected rows
	$self->{view}->queue_draw;
	1;
}

sub buildexpstate
{	my $self=$_[0];
#my $time=times;	#DEBUG
	my @exp;
	my $maxdepth=$#{ $self->{headcells} };
	for my $depth (0..$maxdepth)
	{	my $string='';
		my $expanded= $self->{TREE}{expanded}[$depth];
		my $lastrows= $self->{TREE}{lastrows}[$depth];
		my $firstrow=-1;
		for my $i (1..$#$lastrows)
		{	my $lastrow=$lastrows->[$i];
			$string.= $expanded->[$i]x($lastrow-$firstrow);
			$firstrow=$lastrow;
		}
		push @exp,$string;#warn $string;
	}
	$self->{new_expand_state}=\@exp;
#warn 'buildexpstate '.(times-$time)."s\n";	#DEBUG
	return \@exp;
}

sub BuildTree
{	my $self=shift;
#my $time=times;
	my $expstate=delete $self->{new_expand_state};
	my $list=$self->{array};
	return unless $list;

	my $colgroup=$self->{colgroup};
	delete $self->{queue};

	my $vsizesong=$self->{vsizesong};

	my $maxdepth=$#$colgroup;
 #warn "Building Tree\n";
	my $defaultexp=1;
	$self->{TREE}{lastrows}=$self->{TREE}{expanded}=undef;
	for my $depth (0..$maxdepth)
	{	my $col= $colgroup->[$depth];
		#my $func= Songs::GroupSub($col);
		my $lastrows_parent= $depth==0 ? [-1,$#$list] : $self->{TREE}{lastrows}[$depth-1];
		my ($lastrows,$lastchild)= @$list ? Songs::GroupSub($col)->($list,$lastrows_parent) : ([-1],[0]);
		#my @lastrows;my @lastchild;
		#my $firstrow=0;
		#for my $lastrow (@$lastrows_parent)
		#{	push @lastrows, map $_-1, @{ $func->($list,$firstrow,$lastrow) } if $lastrow-$firstrow>1;
		#	push @lastrows, $lastrow;
		#	push @lastchild, $#lastrows;
		#	$firstrow=$lastrow+1;
		#}
		#$self->{TREE}{lastrows}[$depth]=\@lastrows;
		#$self->{TREE}{lastchild}[$depth-1]=\@lastchild if $depth>=1;
		$self->{TREE}{lastrows}[$depth]=$lastrows;
		$self->{TREE}{lastchild}[$depth-1]=$lastchild if $depth>=1;
		my $exp;
		if (!$expstate) { $exp=[($defaultexp)x@$lastrows]; }
		else
		{	$exp=shift @$expstate;
			$exp= [0,map substr($exp,$lastrows->[$_]+1,1), 0..$#$lastrows-1];
		}
		$self->{TREE}{expanded}[$depth]=$exp;
	}
	$self->{TREE}{expanded}[0]||=[0,1];
	$self->{TREE}{lastrows}[0]||=[-1,$#$list];
#warn 'BuildTree 1st part '.(times-$time)."s\n";
	$self->compute_height;
	#$self->{viewsize}[1]= $height;
	#$self->update_scrollbar;
	#$self->{view}->queue_draw;
	$self->{ready}=1;
#warn 'BuildTree total '.(times-$time)."s\n";
}

sub update_scrollbar
{	my $self=$_[0];
	for my $i (0,1)
	#for my $i (1)
	{	my $adj=	$self->{ (qw/hadj vadj/)[$i] };
		my $pagesize=	$self->{viewwindowsize}[$i] ||0;
		my $upper=	$self->{viewsize}[$i] ||0;
		my $value= $adj->get_value;
		$upper+= $self->{headerheight} if $i==1;
		$value= $upper-$pagesize if $value > $upper-$pagesize;
		$adj->configure($value, 0, $upper, $pagesize*.1, $pagesize*.9, $pagesize);
	}
	#for some reason page size get set to the width without the vertical scrollbar, resulting in not being able to right scroll to the end, this force the vertical scrollbar on to avoid that problem
	$self->set(vscrollbar_policy=> ( $self->{viewsize}[1] + ($self->{headerheight}||0) > $self->{viewwindowsize}[1] ? 'always' : 'automatic')) if $self->{viewwindowsize}[1];
}
sub has_scrolled
{	my ($self,$adj)=@_;
	delete $self->{queue};
	delete $self->{action_rectangles};
	$self->{view}->queue_draw; # FIXME replace by something like $self->{view}->get_window->scroll($xold-$xnew,$yold-$ynew); (must be integers), will need to clean up $self->{action_rectangles}
}

sub reconfigure_cb #should be configure_cb but don't get configure event from TreeView
{	my $view=$_[0];
	my $self= $view->GET_ancestor;
	my $window= $view->get_window;
	return unless $window;
	my (undef,$h)= $view->convert_bin_window_to_widget_coords(0,0);
	$self->{headerheight}=$h;
	$self->{viewwindowsize}=[$window->get_width,$window->get_height];
	$self->updateextrawidth;
	$self->update_scrollbar;
}
sub updateextrawidth
{	my ($self,$old)=@_;
	$old=$self->{extra} unless defined $old;
	my $extra= ($self->{viewwindowsize}[0]||0) - $self->{viewsize}[0];
	$extra=0 if $extra<0;
	my $diff= $extra - $old;
	$_->{width}+=$diff for @{$self->{headcells}};
	$self->{songswidth}+=$diff;
	$self->{extra}=$extra;
}

sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	return if $IDs && !@{ $self->{array}->AreIn($IDs) };	#ignore changes to songs not in the list
	if ( ::OneInCommon($fields,$self->{fields_to_watch1}) )	#changes include a field used to group songs => rebuild
	{	$self->buildexpstate;	#save expanded state for each song
		$self->BuildTree;
	}
	elsif ( ::OneInCommon($fields,$self->{fields_to_watch2}) )
	{	$self->{view}->queue_draw;	#could redraw only affected visible rows, but probably not worth it => so just redraw everything
	}
}

sub SongArray_changed_cb
{	my ($self,$songarray,$action,@extra)=@_;
	#if ($self->{mode} eq 'playlist' && $songarray==$::ListPlay)
	#{	$self->{array}->Mirror($songarray,$action,@extra);
	#}
	return unless $self->{array}==$songarray;
	#warn "SongArray_changed $action,@extra\n";
	my $center;
	my $selected=\$self->{selected};
	if ($action eq 'sort')
	{	my ($sort,$oldarray)=@extra;
		$self->{'sort'}=$sort;
		my @selected=grep vec($$selected,$_,1), 0..$#$songarray;
		my @order;
		$order[ $songarray->[$_] ]=$_ for reverse 0..$#$songarray; #reverse so that in case of duplicates ID, $order[$ID] is the first row with this $ID
		my @IDs= map $oldarray->[$_], @selected;
		@selected= map $order[$_]++, @IDs; # $order->[$ID]++ so that in case of duplicates ID, the next row (with same $ID) are used
		$self->update_sorted_column;
		$self->{view}->update; #to update sort indicator
		$$selected=''; vec($$selected,$_,1)=1 for @selected;
		$self->{new_expand_state}=0;
		$self->{lastclick}=$self->{startgrow}=-1;
		$center=1;
	}
	elsif ($action eq 'update')	#should only happen when in filter mode, so no duplicates IDs
	{	my $oldarray=$extra[0];
		# translate selection to new order :
		my @selected;
		$selected[$oldarray->[$_]]=vec($$selected,$_,1) for 0..$#$oldarray;
		$$selected='';
		vec($$selected,$_,1)=1 for grep $selected[$songarray->[$_]], 0..$#$songarray;

		#translate expstate to new order :
		my @newexp;
		for my $string (@{ $self->buildexpstate })
		{	my @exp;
			$exp[$oldarray->[$_]]=substr($string,$_,1) for 0..$#$oldarray;
			my $new='';
			$new.= defined($_) ? $_ : 1 for map $exp[$_], @$songarray;
			push @newexp, $new;
		}
		$self->{new_expand_state}=\@newexp;
		$self->{lastclick}=$self->{startgrow}=-1;
	}
	elsif ($action eq 'insert')
	{	my ($destrow,$IDs)=@extra;
		vec($$selected,$#$songarray,1)||=0;	#make sure $$selected has a value for every row
		my $string=unpack 'b*',$$selected;
		substr($string,$destrow,0,'0'x@$IDs);
		$$selected=pack 'b*',$string;
		my $exp=$self->buildexpstate;
		substr($_,$destrow,0,'1'x@$IDs) for @$exp;
		$_>=$destrow and $_+=@$IDs for $self->{lastclick}, $self->{startgrow};
	}
	elsif ($action eq 'move')
	{	my (undef,$rows,$destrow)=@extra;
		vec($$selected,$#$songarray,1)||=0;
		my $string=unpack 'b*',$$selected;
		for my $s ($string,@{ $self->buildexpstate })
		{	my $toinsert='';
			$toinsert.=substr($s,$_,1,'') for reverse @$rows;
			substr($s,$destrow,0,reverse $toinsert);
		}
		$$selected=pack 'b*',$string;
	}
	elsif ($action eq 'up')
	{	my $rows=$extra[0];
		for my $row (@$rows)
		{	   ( vec($$selected,$row-1,1),	vec($$selected,$row,1)	 )
			 = ( vec($$selected,$row,1),	vec($$selected,$row-1,1) );
			$self->{lastclick}-- if $self->{lastclick}==$row;
			$self->{startgrow}-- if $self->{startgrow}==$row;
		}
		for my $exp (@{ $self->buildexpstate })
		{	 (substr($exp,$_-1,1),	substr($exp,$_,1)  )
			=(substr($exp,$_,1),	substr($exp,$_-1,1)) for @$rows
		}
	}
	elsif ($action eq 'down')
	{	my $rows=$extra[0];
		for my $row (reverse @$rows)
		{	   ( vec($$selected,$row+1,1),	vec($$selected,$row,1)	 )
			 = ( vec($$selected,$row,1),	vec($$selected,$row+1,1) );
			$self->{lastclick}++ if $self->{lastclick}==$row;
			$self->{startgrow}++ if $self->{startgrow}==$row;
		}
		for my $exp (@{ $self->buildexpstate })
		{	 (substr($exp,$_+1,1),	substr($exp,$_,1)  )
			=(substr($exp,$_,1),	substr($exp,$_+1,1)) for reverse @$rows
		}
	}
	elsif ($action eq 'remove')
	{	if (@$songarray)
		{	my $rows=$extra[0];
			vec($$selected,@$rows+$#$songarray,1)||=0; 	#make sure $$selected has a value for every row, unlike $songarray $selected is not yet updated, so its last_row= @$rows+$#$songarray
			my $string=unpack 'b*',$$selected;
			for my $s ($string,@{ $self->buildexpstate })
			{	substr($s,$_,1,'') for reverse @$rows;
			}
			$$selected=pack 'b*',$string;
			for my $refrow ($self->{lastclick},$self->{startgrow})
			{	$refrow >= $_ and $refrow-- for reverse @$rows;
			}
		}
		else {$self->{lastclick}=$self->{startgrow}=-1;$$selected='';}
	}
	elsif ($action eq 'mode' || $action eq 'proxychange') {return} #the list itself hasn't changed
	else #'replace' or unknown action
	{	#FIXME if replace : check if a filter is in $extra[0]
		$$selected=''; #clear selection
		$self->{lastclick}=$self->{startgrow}=-1;
		if ($action eq 'replace')
		{	$self->{new_expand_state}=0;
			$center=1;
		}
	}
	$self->BuildTree;
	if ($center)
	{	$self->{vadj}->set_value(0);
		my $ID=::GetSelID($self);
		if (defined $ID && $songarray->IsIn($ID))	#scroll to last selected ID if in the list
		{	my $row= ::first { $songarray->[$_]==$ID } 0..$#$songarray;
			if ($$selected eq '') {	$self->set_cursor_to_row($row); }	# scroll to row and select it
			else { $self->scroll_to_row($row,1,1); }			# scroll to row but keep selection
		}
		elsif ($self->{follow}) { $self->FollowSong; }
	}
	::HasChanged('Selection_'.$self->{group});
	$self->Hide(!scalar @$songarray) if $self->{hideif} eq 'empty';
}

sub update_sorted_column
{	my $self=shift;
	my $sort= $self->{'sort'};
	my $invsort= join ' ', map { s/^-// && $_ || '-'.$_ } split / /,$sort;
	for my $cell (@{$self->{cells}})
	{	my $s= $cell->{sort} || '';
		my $arrow=	$s eq $sort	? 'down':
				$s eq $invsort	? 'up'	:
				undef;
		if ($arrow)	{ $cell->{sorted}=$arrow; } # used by SongTree to draw background of cells differently for sorted column
		else		{ delete $cell->{sorted}; } # and by SongTree::Headers to draw up/down arrow
	}
}

sub scroll_event_cb
{	my ($self,$event,$pageinc)=@_;
	my $dir= ref $event ? $event->direction : $event;
	(my $adj,$dir)=	$dir eq 'up'	? (vadj =>-1) :
			$dir eq 'down'	? (vadj => 1) :
			$dir eq 'left'	? (hadj =>-1) :
			$dir eq 'right'	? (hadj => 1) :
			undef;
	return 0 unless $adj;
	$adj=$self->{$adj};
	my $max= $adj->get_upper - $adj->get_page_size;
	my $value= $adj->get_value + $dir* ($pageinc? $adj->get_page_increment : $adj->get_step_increment);
	$value=$max if $value>$max;
	$value=0    if $value<0;
	$adj->set_value($value);
	1;
}
sub key_press_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	my $unicode= Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	my $mod=  $state * [qw/control-mask mod1-mask mod4-mask super-mask/]; # no modifier ctrl/alt/super
	my $shift=$state * ['shift-mask'];
	my $row= $self->{lastclick};
	$row=0 if $row<0;
	my $list=$self->{array};
	if	(($key eq 'space' || $key eq 'Return') && !$mod && !$shift)
					{ $self->Activate(1); }
	elsif	($key eq 'Up')		{ $row-- if $row>0;	 $self->song_selected($event,$row); }
	elsif	($key eq 'Down')	{ $row++ if $row<$#$list;$self->song_selected($event,$row); }
	elsif	($key eq 'Home')	{ $self->song_selected($event,0); }
	elsif	($key eq 'End')		{ $self->song_selected($event,$#$list); }
	elsif	($key eq 'Left')	{ $self->scroll_event_cb('left'); }
	elsif	($key eq 'Right')	{ $self->scroll_event_cb('right'); }
	elsif	($key eq 'Page_Up')	{ $self->scroll_event_cb('up',1); }	#FIXME should select song too
	elsif	($key eq 'Page_Down')	{ $self->scroll_event_cb('down',1); }	#FIXME should select song too
	elsif	($key eq 'Delete')	{ $self->RemoveSelected; }
	elsif	(lc$key eq 'a' && $ctrl)							#ctrl-a : select-all
		{ vec($self->{selected},$_,1)=1 for 0..$#$list; $self->UpdateSelection;}
	elsif	(lc$key eq 'f' && $ctrl) { $self->{isearchbox}->begin(); }			#ctrl-f : search
	elsif	(lc$key eq 'g' && $ctrl) { $self->{isearchbox}->search($shift ? -1 : 1);}	#ctrl-g : next/prev match
	elsif	($key eq 'F3' && !$mod)	 { $self->{isearchbox}->search($shift ? -1 : 1);}	#F3 : next/prev match
	elsif	(!$self->{no_typeahead} && $unicode && $unicode!=32 && !$mod)			# character except space, no modifier
	{	$self->{isearchbox}->begin( chr $unicode );	#begin typeahead search
	}
	else	{return 0}
	return 1;
}

sub draw_cb
{	my ($view,$cr)=@_;# my $time=times;
	return 0 if $view->{drawing};
	my $self= $view->GET_ancestor;
	my ($exp_x1,$exp_y1,$exp_w,$exp_h)= $cr->clip_extents;
	my $headerheight= $self->{headerheight};

	# let the treeview widget draw headers
	$cr->save;
	$cr->rectangle( $exp_x1, ::min($exp_y1,$headerheight), $exp_w, ::max($exp_h,$headerheight) );
	$cr->clip;
	$view->{drawing}=1;
	$view->draw($cr);
	$view->{drawing}=0;
	$cr->restore;

	my $window= $view->get_window;
	if ($exp_y1<$headerheight)
	{	$exp_h-= $exp_y1;
		return if $exp_h<1;
		$exp_y1= $headerheight;
		$cr->rectangle( $exp_x1, $exp_y1, $exp_w, $exp_h );
		$cr->clip;
	}
	my $exp_x2= $exp_x1+$exp_w;
	my $exp_y2= $exp_y1+$exp_h;
	my $style=  $view->get_style_context;
	my $nstate= $self->get_state eq 'insensitive' ? 'insensitive' : 'normal';
	my $sstate= $self->has_focus ? 'selected' : 'active';
	my $selected=	\$self->{selected};
	my $list=	$self->{array};
	my $songcells=	$self->{cells};
	my $headcells=	$self->{headcells};
	my $vsizesong=	$self->{vsizesong};
	unless ($list && @$list)
	{	$self->DrawEmpty($cr,undef,$window->get_width);
		return 1;
	}

	my $xadj= int $self->{hadj}->get_value;
	my $yadj= int $self->{vadj}->get_value;
	my @next;
	my ($depth,$i)=(0,1);
	my ($x,$y)= (0-$xadj, $headerheight-$yadj);
	my $songs_x= $x+$self->{songxoffset};
	my $songs_width=$self->{songswidth};

	my $maxy=$self->{viewsize}[1]-$yadj;
	$exp_y2=$maxy if $exp_y2>$maxy; #don't try to draw past the end

	my $heights= $self->{TREE}{height};
	my $max=$#{$heights->[$depth]};
	my $maxdepth=$#$heights;
	while ($y<=$exp_y2)
	{	if ($i>$max)
		{	last unless $depth;
			$depth--;
			($y,$i,$max)=splice @next,-3;
			next;
		}
		my $bh= $heights->[$depth][$i];
		my $yend=$y+$bh;

		if ($yend>$exp_y1)
		{ my $cell=$headcells->[$depth];
		  my $expanded=$self->{TREE}{expanded}[$depth][$i];
		  if ($cell->{head} || $cell->{left} || $cell->{right})
		  {  $cr->save;
		     $cr->rectangle( $x+$cell->{x}, $y, $cell->{width}, $bh );
		     $cr->clip;
		     my $intersect= $cr->get_clip_rectangle;
		     if ($intersect->{width} && $intersect->{height})
		     {	my $start= $self->{TREE}{lastrows}[$depth][$i-1]+1;
			my $end=   $self->{TREE}{lastrows}[$depth][$i];
			my %arg=
			(	self	=> $cell,	widget	=> $self,	style	=> $style,
				cr	=> $cr,		state	=> $nstate,
				depth	=> $depth,	expanded=> $expanded,
				vx	=> $xadj+$x+$cell->{x},		vy	=> $yadj+$y,
				x	=> $x+$cell->{x},		y	=> $y,
				w	=> $cell->{width},		h	=> $bh,
				grouptype => $cell->{grouptype},
				groupsongs=> [@$list[$start..$end]],
				odd	=> $i%2,	 row=>$i,
			);
			my $q= $cell->{draw}(\%arg);
			my $qid=$depth.'g'.($yadj+$y);
			delete $self->{queue}{$qid};
			delete $arg{cr};
			delete $arg{style};
			$self->{queue}{$qid}=$q if $q;
		     }
		     $cr->restore;
		  }
		  if ($expanded)
		  { $y+=$cell->{head};
		    last if $y>$exp_y2;
		    if ($depth<$maxdepth)
		    {	push @next, $yend,$i+1,$max;
			$max=$self->{TREE}{lastchild}[$depth][$i];
			$i=  $self->{TREE}{lastchild}[$depth][$i-1]+1;
			$depth++;
			next;
		    }
		    else #songs
		    {	my $first= $self->{TREE}{lastrows}[$depth][$i-1]+1;
			my $last=  $self->{TREE}{lastrows}[$depth][$i];
			my $h=($last-$first+1)*$vsizesong;
			if ($y+$h>$exp_y1)
			{ my $skip=0;
			  $last-= int(-.5+($y+$h-$exp_y2)/$vsizesong) if $y+$h>$exp_y2;
			  if ($y<$exp_y1)
			  {	$skip=int(($exp_y1-$y)/$vsizesong);
				$first+=$skip;
				$y+=$vsizesong*$skip;
			  }
			  my $odd=$skip%2;
			  for my $row ($first..$last)
			  {	my $ID=$list->[$row];
				#my $detail= $odd? 'cell_odd_ruled' : 'cell_even_ruled';
				#detail can have these suffixes (in order) : _ruled _sorted _start|_last|_middle
#				$style->paint_flat_box( $window,$state,'none',$expose,$self->{stylewidget},$detail,
#							$songs_x,$y,$songs_width,$vsizesong );
				my $restore;
				my $state=$nstate;
				my $is_selected=0;
				if (vec($$selected,$row,1))
				{	$restore=1;
					$is_selected=1;
					$state=$sstate;
					$style->save;
					$style->set_state( $style->get_state + 'selected' );
					$style->render_background($cr, $songs_x, $y, $songs_width, $vsizesong);
				}
				my $x=$songs_x;
				for my $cell (@$songcells)
				{ my $width=$cell->{width};
				  $width+=$self->{extra} if $cell->{last};
				  $cr->save;
				  $cr->rectangle( $x, $y, $width, $vsizesong );
				  $cr->clip;
				  my $intersect= $cr->get_clip_rectangle;
				  if ($intersect->{width} && $intersect->{height})
				  {	if ($cell->{sorted}) 	# if column is sorted, redraw background with '_sorted' hint
					{	#$style->paint_flat_box( $window,$state,'none',$expose,$self->{stylewidget},$detail.'_sorted',
						#	$x,$y,$width,$vsizesong );
					}

					my %arg=
					(state	=> $state,	self	=> $cell,	widget	=> $self,
					 style	=> $style,	cr	=> $cr,
					 ID	=> $ID,		firstrow=> $first,	lastrow => $last, row=>$row,
					 vx	=> $xadj+$x,	vy	=> $yadj+$y,
					 x	=> $x,		y	=> $y,
					 w	=> $width,	h	=> $vsizesong,
					 odd	=> $odd,	selected=> $is_selected,
					 currentsong => ($::SongID && $ID==$::SongID && ($self->{mode} ne 'playlist' || !defined $::Position || $::Position==$row)),
					);

					my $q= $cell->{draw}(\%arg);
					my $qid=$x.'s'.$y;
					delete $self->{queue}{$qid};
					delete $arg{cr};
					delete $arg{style};
					$self->{queue}{$qid}=$q if $q;
				  }
				  $x+=$width;
		 		  $cr->restore;
				}
				$style->restore if $restore;
				if (exists $view->{drag_highlight} && $view->{drag_highlight}==$row)
				{	$style->render_line($cr, $songs_x,$y,$x,$y);
				}
				$y+=$vsizesong;
				$odd^=1;
			  }
			}
			#else {$y+=$h}
		    }
		    #$y+=$cell->{tail};
		  }
		}
		$y=$yend; #end of branch
		$i++;
	}
	if ($self->{queue})
	{	$self->{idle} ||= Glib::Idle->add(\&expose_queue,$self);
	}
	#warn 'expose : '.(times-$time)."s\n";
	1;
}

sub expose_queue
{	my $self=$_[0];
	{	last unless $self->{queue} && $self->get_mapped;
		my ($qid,$ref)=each %{ $self->{queue} };
		last unless $ref;
		my $context=$ref->[-1];
		my $qsub=shift @$ref;
		delete $self->{queue}{$qid} if @$ref<=1;
		my $hadj=$self->{hadj}; $context->{x}= $context->{vx} - int($hadj->get_value);
		my $vadj=$self->{vadj}; $context->{y}= $context->{vy} - int($vadj->get_value);
		unless (   $context->{x}+$context->{w}<0	|| $context->{y}+$context->{h}<0
			|| $context->{x}>$hadj->get_page_size	|| $context->{y}>$vadj->get_page_size)
		{	my $view= $self->{view};
			my $gdkwin= $view->get_window;
			my $rect= {x=>$context->{x}, y=>$context->{y}, width=>$context->{w}, height=>$context->{h}};
			my $drawingcontext= $gdkwin->begin_draw_frame( Cairo::Region->create($rect) );
			$context->{cr}= $drawingcontext->get_cairo_context;
				# shouldn't be needed by my understanding of gdk_window_begin_draw_frame's description, but is
				$context->{cr}->gdk_rectangle($rect);
				$context->{cr}->clip;
			my $style= $context->{style}= $view->get_style_context;
			my $restore;
			if ($context->{selected})
			{	$restore=1;
				$style->save;
				$style->set_state( $style->get_state + 'selected' );
			}
			&$qsub;
			$style->restore if $restore;
			$gdkwin->end_draw_frame($drawingcontext);
			delete $context->{cr};
			delete $context->{style};
		}
		last unless scalar keys %{ $self->{queue} };
		return 1;
	}
	delete $self->{queue};
	return $self->{idle}=undef;
}

sub coord_to_path
{	my ($self,$x,$y,$raw)=@_;  # raw if hasn't been corrected by treeview
	$y-= $self->{headerheight} if $raw;
	return undef if $y<0; # headers

	$x+= int($self->{hadj}->get_value) if $raw;;
	$y+= int($self->{vadj}->get_value);
	return undef unless @{$self->{array}};
	my $vsizesong= $self->{vsizesong};
	my (@next,@path);
	my ($depth,$i)=(0,1);
	my ($hirow,$area,$row);
	my $heights= $self->{TREE}{height};
	my $max=$#{$heights->[$depth]};
	my $maxdepth=$#$heights;
	############# find vertical position
	while (1)
	{	if ($i>$max)
		{	last unless $depth;
			$depth--;
			($y,$i,$max)=splice @next,-3;
			pop @path;
			if ($y<0)
			{	$area='tail';
				$hirow= $self->{TREE}{lastrows}[$depth][$i]+1;
				last;
			}
			next;
		}
		my $bh= $heights->[$depth][$i];
		my $yend=$y-$bh;
		if ($y>=0 && $yend<0)
		{ if ($self->{TREE}{expanded}[$depth][$i]) #expanded
		  {	my $head= $self->{headcells}[$depth]{head};
			if ($y-$head<=0) #head
			{	my $after= $y > $head/2;
				$hirow= $self->{TREE}{lastrows}[$depth][$i-1]+1;
				$area='head';
				last;
			}
			$y-=$head;
			if ($depth<$maxdepth)
		  	{	push @next, $yend,$i+1,$max;
				push @path,$i;
				$max=$self->{TREE}{lastchild}[$depth][$i];
				$i=  $self->{TREE}{lastchild}[$depth][$i-1]+1;
				$depth++;
				next;
			}
			else #songs
		  	{	my $first= $self->{TREE}{lastrows}[$depth][$i-1]+1;
				my $last=  $self->{TREE}{lastrows}[$depth][$i];
				my $h=($last-$first+1)*$vsizesong;
				if ($y-$h<=0)
				{	$row= int( $y/$vsizesong );
					my $after= int( .5+$y/$vsizesong ) <= $row;
					$row+=$first;
					$hirow=$row+1-$after;
					$area='songs';
					last;
				}
			}
			$hirow= $self->{TREE}{lastrows}[$depth][$i]+1;
			$area='tail';
			last;
		  }
		  else #collapsed group
		  {	my $after= $y > $bh/2;
			my $i2= $after ? $i-1 : $i;
			$hirow= $self->{TREE}{lastrows}[$depth][$i2]+1;
			$area='collapsed';
			last;
		  }
		}
		$y=$yend;
		$i++;
	}
	unless (@path)
	{	$area||='end'; #empty space at the end
	}
	return undef unless $area;
	my $depth0=$depth;

	############# find horizontal position
	push @path,$i;
	my $hdepth=0; my ($x2,$col);
	my $harea='left';
	for my $cell (@{$self->{headcells}})
	{	$x-=$cell->{left};
		last if $x<=0;
		$hdepth++;
		$x2=$x;
	}
	if ($x>0 && $x<$self->{songswidth} && $area eq 'songs')
	{	$harea='songs';
		$depth=undef;
		$col=0;
		while ($x>0)
		{	$x-=$self->{cells}[$col]{width};
			last if $x<0;
			$col++;
			$x2=$x;
			last unless $self->{cells}[$col];
		}
		$y %= $vsizesong;
	}
	if ($x>$self->{songswidth})
	{	$x-=$self->{songswidth};
		$harea='right';
		for my $cell (reverse @{$self->{headcells}})
		{	$x-=$cell->{right};
			last if $x<0;
			$hdepth--;
			$x2=$x;
		}
	}
	if (defined $depth && $hdepth<$depth)
	{	$depth=$hdepth;
		$#path=$depth;
	}
	return	{	path	=> \@path,
			start	=> $self->{TREE}{lastrows}[$depth0][$i-1]+1,
			end	=> $self->{TREE}{lastrows}[$depth0][$i],
			depth	=> $depth,
			row	=> $row,
			hirow	=> $hirow,
			area	=> $area,
			harea	=> $harea,
			x	=> $x2,
			y	=> $y,
			col	=> $col,
			branch	=> $i,
		};
}

sub row_to_y
{	my ($self,$row,$raw)=@_;
	my $y= $raw ? $self->{headerheight} : 0;
	my $depth=0;
	my $i=1;
	my $maxdepth= $#{ $self->{TREE}{lastrows} };
	my $lastrows= $self->{TREE}{lastrows}[$depth];
	my $heights= $self->{TREE}{height}[$depth];
	while ($i<=$#$lastrows)
	{	if ($row>$lastrows->[$i-1] && $row<=$lastrows->[$i])
		{	return $y unless $self->{TREE}{expanded}[$depth][$i];
			$y+= $self->{headcells}[$depth]{head};
			if ($depth<$maxdepth)
			{	$i=$self->{TREE}{lastchild}[$depth][$i-1]+1;
				$depth++;
				$lastrows= $self->{TREE}{lastrows}[$depth];
				$heights= $self->{TREE}{height}[$depth];
				next;
			}
			my $first= $self->{TREE}{lastrows}[$depth][$i-1]+1;
			$y+= $self->{vsizesong}*($row-$first);
			return $y;
		}
		$y+=$heights->[$i];
		$i++;
	}
	return 0;
}
sub row_to_rect
{	my ($self,$row,$raw)=@_;
	my $y=$self->row_to_y($row,$raw);
	return unless defined $y;
	my $x= $self->{songxoffset};
	$x-= int $self->{hadj}->get_value if $raw;
	$y-= int $self->{vadj}->get_value;
	return { x=>$x, y=>$y, width=>$self->{songswidth}, height=>$self->{vsizesong} };
}
sub update_row
{	my ($self,$row)=@_;
	my $rect=$self->row_to_rect($row,1);
	my $gdkwin= $self->{view}->get_window;
	$gdkwin->invalidate_rect($rect,0) if $rect && $gdkwin;
}
#sub update_row
#{	my ($self,$row)=@_;
#	my $y=$self->row_to_y($row);
#	return unless defined $y;
#	my $x= $self->{songxoffset} - int($self->{hadj}->value);
#	$y-= $self->{vadj}->value;
#	$self->{view}->queue_draw_area($x, $y, $self->{songswidth}, $self->{vsizesong});
#}


sub Scroll_to_TopEnd
{	my ($self,$end)=@_;
	my $adj=$self->{vadj};
	if ($end)	{ $adj->set_value($adj->get_upper - $adj->get_page_size); }
	else		{ $adj->set_value(0); }
}

sub drag_received_cb
{	my ($view,$type,$dest,@IDs)=@_;
	if ($type==::DRAG_FILE) #convert filenames to IDs
	{	@IDs=::FolderToIDs(1,0,map ::decode_url($_), @IDs);
		return unless @IDs;
	}
	my $self= $view->GET_ancestor;

	my (undef,$row)=@$dest;
	return unless defined $row; #FIXME
#warn "dropped, insert before row $row, song : ".Songs::Display($self->{array}[$row],'title')."\n";
	my $songarray=$self->{array};
	if ($view->{drag_is_source})
	{	$songarray->Move($row,$self->GetSelectedRows);
	}
	else { $songarray->Insert($row,\@IDs); }
}
sub drag_motion_cb
{	my ($view,$context,$x,$y,$time)=@_;
	my $self= $view->GET_ancestor;
	if ($self->{autoupdate}) { $context->status('default',$time); return } # refuse any drop if autoupdate is on

	#check scrolling
	if	($y-$self->{vsizesong}<=0)				{$view->{scroll}='up'}
	elsif	($y+$self->{vsizesong} >= $self->{viewwindowsize}[1])	{$view->{scroll}='down'}
	else {delete $view->{context};delete $view->{scroll}}
	if ($view->{scroll})
	{	$view->{scrolling}||=Glib::Timeout->add(200, \&drag_scrolling_cb,$view);
		$view->{context}||=$context;
	}

	my $answer=$self->coord_to_path($x,$y);
	my $row=$answer->{hirow};
	$row=@{$self->{array}} unless defined $row;
	$self->update_row($view->{drag_highlight}) if defined $view->{drag_highlight};
	$view->{drag_highlight}=$row;
	$self->update_row($row);
	$context->{dest}=[$view,$row];
	$context->status(($view->{drag_is_source} ? 'move' : 'copy'),$time);
	return 1;
}
sub drag_scrolling_cb
{	my $view=$_[0];
	if (my $s=$view->{scroll})
	{	my $self= $view->GET_ancestor;
		$self->scroll_event_cb($s);
		drag_motion_cb($view,$view->{context}, ($view->get_window->get_pointer)[1,2], 0 );
		return 1;
	}
	else
	{	delete $view->{scrolling};
		return 0;
	}
}
sub drag_leave_cb
{	my $view=$_[0];
	my $self= $view->GET_ancestor;
	my $row=delete $view->{drag_highlight};
	$self->update_row($row) if defined $row;
}

sub expand_collapse
{	my ($self,$depth,$i)=@_;
	$self->{TREE}{expanded}[$depth][$i]^=1;
	$self->compute_height;	# FIXME could compute only ($depth,$i)
}

sub compute_height
{	my ($self)=@_;
	delete $self->{queue};
	$self->{TREE}{height}=[];
	my $vsizesong=$self->{vsizesong};
	my $headcells=$self->{headcells};
	my $maxdepth=$#$headcells;
	for my $depth (reverse 0..$maxdepth)
	{	my $headcell=$headcells->[$depth];
		my $vmin=$headcell->{vmin};
		my $headtail= $headcell->{head} + $headcell->{tail};
		my $vcollapsed=$headcell->{vcollapse};
		my $expanded=	$self->{TREE}{expanded}[$depth];
		my $height=	$self->{TREE}{height}[$depth]=[0];
		if ($depth==$maxdepth)
		{	my $lastrows=$self->{TREE}{lastrows}[$depth];
			my $firstrow=-1;
			for my $i (1..$#$lastrows)
			{	my $lastrow=$lastrows->[$i];
				my $h;
				if ($expanded->[$i])
				{	$h= $headtail+ $vsizesong * ($lastrow-$firstrow);
					$h=$vmin if $h<$vmin;
				}
				else { $h=$vcollapsed }
				$height->[$i]=$h;
				$firstrow=$lastrow;
			}
		}
		else
		{	my $lastchild=	$self->{TREE}{lastchild}[$depth];
			my $hchildren=	$self->{TREE}{height}[$depth+1];
			my $firstchild=1;
			for my $i (1..$#$lastchild)
			{	my $lastchild=$lastchild->[$i];
				my $h;
				if ($expanded->[$i])
				{	$h= $headtail;
					$h+= $hchildren->[$_] for $firstchild..$lastchild;
					$h=$vmin if $h<$vmin;
				}
				else { $h=$vcollapsed }
				$height->[$i]=$h;
				$firstchild=$lastchild+1;
			}
		}
	}

	my $height0=$self->{TREE}{height}[0];
	my $h=0;
	$h+=$_ for @$height0;
	$self->{viewsize}[1]= $h;
#warn "total height=$h";

	$self->update_scrollbar;
	$self->{view}->queue_draw;
}

sub button_press_cb
{	my ($view,$event)=@_;
	my $self= $view->GET_ancestor;
	$self->grab_focus;
	my $but=$event->button;
	my $answer=$self->coord_to_path($event->get_coords);
	my $row=   $answer && $answer->{row};
	my $depth= $answer && $answer->{depth};
	if ((my $ref=$self->{action_rectangles}) && 0) #TESTING
	{	my $x= $event->x;
		my $y= $event->y + int($self->{vadj}->get_value) + $self->{headerheight};
		my $found;
		for my $dim (keys %$ref)
		{	my ($rx,$ry,$rw,$rh)=split /,/,$dim;
			next if $ry>$y || $ry+$rh<$y || $rx>$x || $rx+$rw<$x;
			$found=$ref->{$dim};
		}
		if ($found) {warn "actions : $_ => $found->{$_}" for keys %$found}
	}
	if ($event->type eq '2button-press')
	{	return 0 unless $answer; #empty list
		return 0 unless $answer->{area} eq 'songs';
		$self->Activate($but);
		return 1;
	}
	if ($but==3)
	{	if ($answer && !defined $depth && !vec($self->{selected},$row,1))
		{	$self->song_selected($event,$row);
		}
		$self->PopupContextMenu;
		return 1;
	}
	else# ($but==1)
	{	return 0 unless $answer;
		if (defined $depth && $answer->{area} eq 'head' || $answer->{area} eq 'collapsed')
		{	if ($answer->{area} eq 'head' && $self->{headclick} eq 'select')
			 { $self->song_selected($event,$answer->{start},$answer->{end}); return 0}
			else { $self->expand_collapse($depth,$answer->{branch}); }
			return 1;
		}
		elsif (defined $depth && $answer->{harea} eq 'left' || $answer->{harea} eq 'right')
		{	$self->song_selected($event,$answer->{start},$answer->{end});
			return 0;
		}
		if (defined $row)
		{	if ( $event->get_state * ['shift-mask', 'control-mask'] || !vec($self->{selected},$row,1) )
				{ $self->song_selected($event,$row); }
			else	{ $view->{pressed}=1; }
		}
		return 0;
	}
	1;
}
sub button_release_cb
{	my ($view,$event)=@_;
	return 0 unless $view->{pressed};
	$view->{pressed}=undef;
	my $self= $view->GET_ancestor;
	my $answer=$self->coord_to_path($event->get_coords);
	$self->song_selected($event,$answer->{row});
	return 1;
}
sub drag_begin_cb
{	$_[0]->{pressed}=undef;
}

sub scroll_to_row #FIXME simplify
{	my ($self,$row,$center,$not_if_visible)=@_;
	my $vsize=$self->{vsizesong};
	my $y1=my $y2=$self->row_to_y($row);
	my $vadj=$self->{vadj};
	if ($not_if_visible) {return if $y1-$vadj->get_value >0 && $y1+$vsize-$vadj->get_value-$vadj->get_page_size <0;}
	if ($center)
	{	my $half= $center * $vadj->get_page_size/2;
		$y1-=$half-$vsize/2;
		$y2+=$half+$vsize/2;
	}
	else
	{	$y1-=$vsize;
		$y2+=$vsize*2;
	}
	$vadj->clamp_page($y1,$y2+2);
}

sub CurSongChanged
{	my $self=$_[0];
	$self->FollowSong if $self->{follow};
}
sub FollowSong
{	my $self=$_[0];
	return unless defined $::SongID;
	my $array=$self->{array};
	return unless $array;
	my $row;
	if ($self->{mode} eq 'playlist') { $row=$::Position; }
	if ($array->IsIn($::SongID))
	{	$row= ::first { $array->[$_]==$::SongID } 0..$#$array unless defined $row && $row>=0;
		$self->set_cursor_to_row($row);
	}
	::HasChangedSelID($self->{group},$::SongID);
}

sub get_cursor_row
{	my $self=$_[0];
	my $row=$self->{lastclick};
	if ($row<0)
	{	my $path=$self->coord_to_path(0,0);
		$row= ref $path ? $path->{row} : 0 ;
	}
	return $row;
}

sub set_cursor_to_row
{	my ($self,$row)=@_;
	$self->song_selected(undef,$row,undef,'noscroll');
	$self->scroll_to_row($row,1,1);
}

sub song_selected
{	my ($self,$event,$idx1,$idx2,$noscroll)=@_;
	return if $idx1<0 || $idx1 >= @{$self->{array}};
	$idx2=$idx1 unless defined $idx2;
	$self->scroll_to_row($idx1) unless $noscroll;
	::HasChangedSelID($self->{group},$self->{array}[$idx1]);
	unless ($event && $event->get_state >= ['control-mask'])
	{	$self->{selected}='';
	}
	if ($event && $event->get_state >= ['shift-mask'] && $self->{lastclick}>=0)
	{	$self->{startgrow}=$self->{lastclick} unless $self->{startgrow}>=0;
		my $i1=$self->{startgrow};
		my $i2=$idx1;
		if ($i1>$i2)	{ ($i1,$i2)=($i2,$i1) }
		else		{ $i2=$idx2 }
		vec($self->{selected},$_,1)=1 for $i1..$i2;
	}
	elsif (!grep !vec($self->{selected},$_,1), $idx1..$idx2)
	{	vec($self->{selected},$_,1)=0 for  $idx1..$idx2;
		$self->{startgrow}=-1;
	}
	#elsif (vec($self->{selected},$idx,1))
	#{	vec($self->{selected},$idx,1)=0
	#	$self->{startgrow}=-1;
	#}
	else
	{	vec($self->{selected},$_,1)=1 for $idx1..$idx2;
		$self->{startgrow}=-1;
	}
	$self->{lastclick}=$idx1;
	$self->UpdateSelection;
}
sub select_by_filter
{	my ($self,$filter)=@_;
	my $array=$self->{array};
	my $IDs= $filter->filter($array);
	my %h; $h{$_}=undef for @$IDs;
	$self->{selected}=''; #clear selection
	vec($self->{selected},$_,1)=1 for grep exists $h{$array->[$_]}, 0..$#$array;
	$self->{startgrow}=$self->{lastclick}=-1;
	$self->UpdateSelection;
}

sub UpdateSelection
{	my $self=shift;
	::HasChanged('Selection_'.$self->{group});
	$self->{view}->queue_draw;
}

sub query_tooltip_cb
{	my ($view, $x, $y, $keyb, $tooltip)=@_;
	return 0 if $keyb;
	my $self= $view->GET_ancestor;
	my $path=$self->coord_to_path($x,$y,1);
	my $row=$path->{row};
	return 0 unless defined $row;
	my $ID=$self->{array}[$row];
	return unless defined $ID;
	my $markup= ::ReplaceFieldsAndEsc($ID,$self->{rowtip});
	$tooltip->set_markup($markup);
	my $rect=$self->row_to_rect($row,1);
	$tooltip->set_tip_area($rect) if $rect;
	1;
}

package SongTree::EmptyTreeView;	# empty Gtk3::TreeView used to have real treeview column headers, the songtree is drawn on it
use base 'Gtk3::TreeView';

our @ColumnMenu=
(	{ label => _"_Sort by",		submenu => sub { Browser::make_sort_menu($_[0]{songtree}); }
	},
	{ label => _"Set grouping",	submenu => sub {$::Options{SavedSTGroupings}}, check => 'songtree/grouping',
	  code => sub { $_[0]{songtree}->set_head_columns($_[1]); },
	},
	{ label => _"Edit grouping ...",	code => sub { my $songtree=$_[0]{songtree}; ::EditSTGroupings($songtree,$songtree->{grouping},undef,sub{ $songtree->set_head_columns($_[0]) if defined $_[0]; }); },
	},
	{ label => _"_Insert column",	submenu => sub
		{	my %names; $names{$_}= $SongTree::STC{$_}{menutitle}||$SongTree::STC{$_}{title} for keys %SongTree::STC;
			delete $names{$_->{colid}} for grep $_->{colid}, map $_->get_button, $_[0]{self}->get_columns;
			return \%names;
		},	submenu_reverse =>1,
		code => sub { $_[0]{songtree}->AddColumn($_[1],$_[0]{insertpos}); }, stockicon => 'list-add-symbolic',
	},
	{ label=> sub { _('_Remove this column').' ('.($SongTree::STC{$_[0]{colid}}{menutitle}||$SongTree::STC{$_[0]{colid}}{title}).')' },
	  code => sub { $_[0]{songtree}->remove_column($_[0]{cellnb}) },	stockicon => 'list-remove-symbolic', isdefined => 'colid',
	},
	{ label => _("Edit row tip").'...', code => sub { $_[0]{songtree}->EditRowTip; },
	},
	{ label => _"Keep list filtered and sorted",	code => sub { $_[0]{songtree}{array}->SetAutoUpdate( $_[0]{songtree}{autoupdate} ); },
	  toggleoption => 'songtree/autoupdate',	mode => 'B',
	},
	{ label => _"Follow playing song",	code => sub { $_[0]{songtree}->FollowSong if $_[0]{songtree}{follow}; },
	  toggleoption => 'songtree/follow',
	},
	{ label => _"Go to playing song",	code => sub { $_[0]{songtree}->FollowSong; }, },
);

sub new
{	my ($class,$adj,$hide)=@_;
	my $store= Gtk3::ListStore->new('Glib::Uint'); #just used to create a valid treeview
	my $self= bless Gtk3::TreeView->new($store), $class;
	$self->set_headers_visible(::FALSE) if $hide;
	$self->set_hadjustment($adj);
	$self->set_column_drag_function(\&column_drag_function);
	return $self;
}

sub update
{	my $self=$_[0];
	my $songtree= $self->GET_ancestor('SongTree');
	$self->remove_column($_) for $self->get_columns;

	my $count=0;
	if (my $w=$songtree->{songxoffset})
	{	my $column= Gtk3::TreeViewColumn->new;
		$self->append_column($column);
		$column->set_fixed_width($w);
		$count++;
		my $button= $column->get_button;
		$button->{insertpos}=0;
	}
	my $i=0;
	for my $cell (@{$songtree->{cells}})
	{	my $column= Gtk3::TreeViewColumn->new;
		my $title= $SongTree::STC{ $cell->{colid} }{title};
		$column->set_title( $title ) if defined $title;
		my $button= $column->get_button;
		$button->{sort}=$cell->{sort};
		$button->{cellnb}=$i++;
		$button->{colid}=$cell->{colid};
		$column->set_fixed_width($cell->{width});
		$column->{position}= $count++;
		$column->set_resizable(::TRUE);
		$column->set_clickable(::TRUE);
		$column->set_reorderable(::TRUE);
		$self->append_column($column);
		$column->signal_connect(notify=> \&property_changed_cb);
		#my $expand= $i==@{$songtree->{cells}};
	}
	if (my $w=$songtree->{songxright})
	{	my $column= Gtk3::TreeViewColumn->new;
		$self->append_column($column);
		$column->set_fixed_width($w);
		my $button= $column->get_button;
		$button->{insertpos}=@{$songtree->{cells}};
	}
	for my $column ($self->get_columns)
	{	my $button= $column->get_button;
		$button->signal_connect(clicked	=> \&clicked_cb);
		$button->signal_connect(button_press_event => \&popup_col_menu);
	}
	$self->update_sort_indicators;
}

sub property_changed_cb
{	my ($column,$prop)=@_;
	my $name= $prop->{name};
	if ($name eq 'width')
	{	my $self= $column->get_tree_view;
		my $songtree= $self->GET_ancestor('SongTree');
		my $nb= $column->get_button->{cellnb};
		return unless defined $nb; #shouldn't happen
		my $new= $column->get_width;
		my $cell= $songtree->{cells}[$nb];
		my $old= $cell->{width};
		return if $old==$new;
		$cell->{width}= $new;
		$songtree->update_columns(::FALSE,::TRUE);
	}
	elsif ($name eq 'x-offset')
	{	my $self= $column->get_tree_view;
		if ($self->get_column( $column->{position} ) != $column)
		{	::IdleDo('0_ColumnsChanged'.$self,10, \&update_column_order, $self);
		}
	}
}

sub update_column_order
{	my $self=shift;
	my @neworder;
	my $n=0;
	while (my $column= $self->get_column($n))
	{	my $nb= $column->get_button->{cellnb};
		push @neworder,$nb if defined $nb;
		$n++;
	}
	my $songtree= $self->GET_ancestor('SongTree');
	my $cells= $songtree->{cells};
	if (@$cells!=@neworder) {warn "error moving column, new number of columns doesn't match old number\n"; return;}
	@$cells= @$cells[@neworder];
	$songtree->{cols_changed}=1;
	$songtree->update_columns;
}

sub column_drag_function
{	my ($treeview,$column,$left,$right)=@_;
	#my $nb= $column->get_button->{cellnb};
	#return 0 unless defined $nb;
	my $nb_l= $left  && defined $left->get_button->{cellnb};
	my $nb_r= $right && defined $right->get_button->{cellnb};
	return 0 if !$left  && !$nb_r;
	return 0 if !$right && !$nb_l;
	return 1;
}

sub popup_col_menu
{	my ($button,$event)=@_;
	return 0 unless $event->button == 3;
	my $self= $button->GET_ancestor;
	my $songtree= $self->GET_ancestor('SongTree');
	my $insertpos= exists $button->{cellnb} ? $button->{cellnb}+1 : $button->{insertpos};
	::PopupContextMenu(\@ColumnMenu, { self => $self, colid => $button->{colid}, cellnb =>$button->{cellnb}, insertpos =>$insertpos, songtree => $songtree, mode=>$songtree->{type}, });
	return 1;
}

sub clicked_cb
{	my $button=$_[0];
	my $songtree= $button->GET_ancestor('SongTree');
	my $sort= $button->{colid} ? $button->{sort} : join ' ',map Songs::SortGroup($_), @{$songtree->{colgroup}};
	return unless defined $sort;
	$sort='-'.$sort if $sort eq $songtree->{sort}; #FIXME handle multi-fields columns correctly
	$sort=~s/^--//;
	$songtree->Sort($sort);
}

sub update_sort_indicators
{	my $self=shift;
	my $songtree= $self->GET_ancestor('SongTree');
	my $sort= $songtree->{sort};
	my $inv_sort= '-'.$sort;
	$inv_sort=~s/^--//;
	my %order=( $sort=>'ascending', $inv_sort=>'descending' );
	for my $column ($self->get_columns)
	{	my $button= $column->get_button;
		my $colsort= $button->{sort};
		my $order= $colsort && $order{$colsort};
		$column->set_sort_indicator($order ? 1 : 0);
		$column->set_sort_order($order) if $order;
	}
}

package GMB::Cell;

my $drawpix=	['pixbuf_draw','draw = pixbuf xd yd wd hd'];
my $padandalignx=['pad_and_align', 'xd wd = x xpad pad xalign wr w'];
my $padandaligny=['pad_and_align', 'yd hd = y ypad pad yalign hr h'];
my $optpad=	['optpad', 'xpad ypad = pad'];
sub optpad #
{	return $_[1],$_[1];
}
our %GraphElem=
(	text	=>{ functions =>
		    [	['layout_draw','draw = layout xd yd wd hd rotate'],
			['markup_layout','layout = text markup hide'],
			['layout_size','wr hr bl = layout'],
			$padandalignx,$padandaligny,
		    ],
		    defaults =>
		    	'w=___wr+2*___xpad,h=___hr+2*___ypad,xpad=xpad,ypad=ypad,yalign=.5,rotate=0,blp=___bl+___ypad',
		    optional =>
		    [	$optpad,
		    ],
		  },
	rect	=>{ functions =>
		    [	['box_draw','draw = x y w h color filled width hide'],
		    ],
		    defaults =>	'color=0,filled=0,x=0,y=0,w=$_w-___x,h=$_h-___y,width=1',
		  },
	pbar	=>{ functions =>
		    [	['pbar_draw','draw = x y w h fill hide'],
		    ],
		    defaults =>	'fill=0,x=0,y=0,w=$_w-___x,h=$_h-___y',
		  },
	line	=>{ functions =>
		    [	['line_draw','draw = x1 y1 x2 y2 color width hide'],
		    ],
		    defaults =>	'color=0,x1=0,y1=0,x2=___x1,y2=___y1,width=1',
		  },
	aapic	=>{ functions =>
		    [	['aapic_size','pixbuf wr hr = aap'],
		    	['aapic_cached','aap queue = picsize aa ids aanb hide'],
			 $drawpix,$padandalignx,$padandaligny,
		    ],
		    defaults =>
		    	'x=0,y=0,w=___picsize+2*___xpad,h=___picsize+2*___ypad,xpad=xpad,ypad=ypad,xalign=.5,yalign=.5,aanb=0,aa=$_grouptype,ids=$ids,picsize=min(___w+2*___xpad,___h+2*___ypad)',
		    optional =>
		    [	$optpad,
		    ],
		  },
	picture	=>{ functions =>
		    [	['pic_cached','cached queue = file resize? w? h? xpad ypad crop hide'],
		    	['pic_size','pixbuf wr hr = cached file crop hide'],
		    	$drawpix,$padandalignx,$padandaligny,
		    ],
		    defaults => 'x=0,y=0,xalign=.5,yalign=.5,resize=0,w=0,h=0,crop=0,xpad=xpad,ypad=ypad,w=___wr+2*___xpad,h=___hr+2*___ypad',
		    optional =>
		    [	$optpad,
		    ],
		  },
	icon	=>{ functions =>
		    [	['icon_size','wr hr nbh w1 h1 = size icon y h xpad ypad hide'],
			['icon_draw','draw = icon size xd yd wd hd nbh w1 h1 hide'],
			$padandalignx,$padandaligny,
		    ],
		    defaults => 'w=___wr+2*___xpad,h=$_h,xpad=xpad,ypad=ypad,xalign=0,yalign=.5,size=16',
		    optional =>
		    [	$optpad,
		    ],
		  },
	action=>{ functions =>
		    [	['set_action','draw = x y w h actions hide'],
		    ],
		    defaults => 'x=0,y=0,w=$_w,h=$_h',
		  },
#	expander=>{ functions =>
#		    [	['exp_size','wr hr = hide'],
#			['exp_draw','draw = xd yd wd hd hide'],
#			$padandalignx,$padandaligny,
#		    ],
#		  },

	blalign	=>{ functions =>
		    [	['blalign','h = y ref','y = blp h'],
		    ],
		    defaults => 'y=0,ref=0',
		  },
	xalign	=>{ functions =>
		    [	['align','w = align x ref','x = w'],
		    ],
		    defaults => 'ref=___align',
		  },
	yalign	=>{ functions =>
		    [	['align','h = align y ref','y = h'],
		    ],
		    defaults => 'ref=___align',
		  },
	xpack	=>{ functions =>
		    [	['epack','w = x pad','x = w'],
		    ],
		    defaults => 'ref=0,pad=0',
		  },
	ypack	=>{ functions =>
		    [	['epack','h = y pad','y = h'],
		    ],
		    defaults => 'ref=0,pad=0',
		  },
);

sub new_songcol
{	my ($class,$colid,$width)=@_;
	my $sort= $SongTree::STC{$colid}{sort};
	my $self=bless {colid => $colid, width => $width, 'sort' => $sort }, $class;
	return $self;
}

sub init_songs
{	my ($widget,$cells,$xpad,$ypad)=@_;
	my $initcontext={ widget => $widget, init=>1, };
	my $constant={ xpad=>$xpad, ypad=>$ypad, playmarkup=> 'weight="bold"' };	#FIXME should be quoted : q('weight="bold"')
	my @blh; my @y_refs;
	my @Deps;
	for my $cell (@$cells)
	{	my $colid=$cell->{colid};
		my $def= $SongTree::STC{$colid} || {};
		my (@draw,@elems);
		for my $part (@{ $def->{elems} })
		{	my ($eid,$elem,$opt)= $part=~m/^(\w+)=(\w+)\s*\((.*)\)$/;
			next unless $elem;
			push @elems,[$eid.':',$elem,$opt];
			push @draw,$eid;
		}
		my $h = $def->{hreq};
		my $bl= $def->{songbl};
		push @elems, ['',undef,"hreq=$h"] if $h;
		my ($dep,$update)=createdep(\@elems,'song',$constant);
		$cell->{event}= [keys %{$update->{event}}] if $update->{event};
		$cell->{watchfields}=[keys %{$update->{col}}] if $update->{col};
		$cell->{draw}=\@draw;

		m/^(\w+:)init_(\w+)$/ and ($dep->{$_},$dep->{$1.$2})=($dep->{$1.$2},$dep->{$_}) for keys %$dep; #exchange init_* keys with normal keys
		push @Deps,$dep;
		if ($bl)
		{	my @init;
			push @init, $_.':blp', $_.':h' for split /\|/,$bl;
			$dep->{init}=[undef, @init];
			my $var=GMB::Expression::Make($dep,'init',$initcontext);
			push @blh,$var->{$_} for @init;
			push @y_refs, \$dep->{$_.':y'} for split /\|/,$bl;
		}
	}
	if (@blh)
	{	my ($h,@y)=blalign(undef,0,0,@blh);	#compute the y of elements aligned with songbl
		${$y_refs[$_]}= [ $y[$_]||0 ] for 0..$#y;	#set the y
	}
	my $maxh=1;
	for my $cell (@$cells)
	{	my $dep=shift @Deps;
		if ($dep->{hreq})
		{	my $var=GMB::Expression::Make($dep,'hreq',$initcontext);
			my $h= $var->{hreq}||0;
			$maxh=$h if $h > $maxh;
		}
		m/^(\w+:)init_(\w+)$/ and $dep->{$1.$2}=$dep->{$_} for keys %$dep; #revert init_ keys
		$cell->{draw}=GMB::Expression::MakeMake($dep,$cell->{draw});
	}
	return $maxh;
}

sub new_group
{	my ($class,$widget,$depth,$grouptype,$skin)=@_;
	my $constant={ xpad=>0, ypad=>0, };
	if ($skin=~s#\((.*)\)$##) #skin options
	{	my $opt=::ParseOptions($1);
		for my $key (keys %$opt)
		{	my $v=::decode_url($opt->{$key});
			$v=~s#'#\\'#g;
			$constant->{$key}="'$v'";
		}
	}
	if (my $ref0=$SongTree::GroupSkin{$skin}{options})
	{	for my $key (keys %$ref0) { $constant->{$key}="'".$ref0->{$key}{default}."'" unless exists $constant->{$key} }
	}
	my $def=$SongTree::GroupSkin{$skin} || {};
	my $self=bless
		{	grouptype=> $grouptype,
			depth	=> $depth,
		}, $class;
	my @elems;
	my @draw; my %hide;
	for my $part (@{$def->{elems}})
	{	my ($eid,$exp,$elem,$opt)= $part=~m/^(\w+)=([+-])?(\w+)\s*\((.*)\)$/;
		next unless $elem;
		push @elems,[$eid.':',$elem,$opt];
		$hide{$eid.':hide'}= ($exp eq '+') if defined $exp;
		push @draw,$eid;
	}
	my @init=map $_.'='.($def->{$_}||0), qw/head tail left right vmin vcollapse/;
	push @elems, ['',undef,join ',',@init];
	my ($dep,$update)=createdep(\@elems,'group',$constant);
	$self->{event}=[keys %{$update->{event}}] if $update->{event};
	$self->{watchfields}=[keys %{$update->{col}}] if $update->{col};
	for my $key (keys %hide)
	{	my $hide;
		$hide='!' if $hide{$key};
		$hide.= '$arg->{expanded}';
		$hide.= '|| ('.$dep->{$key}[0].')' if exists $dep->{$key};
		$dep->{$key}[0]= $hide;
	}

	my $initcontext={widget => $widget, expanded =>1, init=>1, depth => $depth, grouptype =>$grouptype};
	$dep->{init}=[undef,qw/head tail left right vmin/];
	m/^(\w+:)init_(\w+)$/ and ($dep->{$_},$dep->{$1.$2})=($dep->{$1.$2},$dep->{$_}) for keys %$dep; #exchange init_* keys with normal keys
	my $var=GMB::Expression::Make($dep,'init',$initcontext);
	$self->{$_}=$var->{$_} for qw/head tail left right vmin/;

	$dep->{init0}=[undef,'vcollapse'];
	$initcontext->{expanded}=0;
	my $var0=GMB::Expression::Make($dep,'init0',$initcontext);
	$self->{vcollapse}=$var0->{vcollapse};

	m/^(\w+:)init_(\w+)$/ and $dep->{$1.$2}=$dep->{$_} for keys %$dep; #revert init_ keys
	$self->{draw}=GMB::Expression::MakeMake($dep,\@draw);
	return $self;
}

sub createdep
{	my ($elems,$context,$constant)=@_;
	my (%update,%dep,%default,%children);
	#process options
	for my $elem (@$elems)
	{	my ($eid,$elem,$opt)=@$elem;
		$opt=GMB::Expression::split_options($opt,$eid);
		$children{$eid.'children'}= delete $opt->{$eid.'children'};
		GMB::Expression::parse($opt,$context,\%update,\%dep,$constant);
		if ($elem && $GraphElem{$elem} && $GraphElem{$elem}{defaults})
		{	my $default= $GraphElem{$elem}{defaults};
			$default=~s/___/$eid/g;
			$default=GMB::Expression::split_options($default,$eid);
			delete $default->{$_} for keys %$opt;
			GMB::Expression::parse($default,$context,\%update,\%default,$constant);
		}
	}
	#process functions
	for my $elem (@$elems)
	{	my ($eid,$elem)=@$elem;
		next unless $elem && $GraphElem{$elem};
		for my $ref (@{ $GraphElem{$elem}{functions} })
		{	my ($code,$params,$cparams)=@$ref;
			my ($out,$in)=split /\s*=\s*/, $params,2;
			my @in=  map $eid.$_, split / +/,$in;
			my @out= map $eid.$_, split / +/,$out;
			$code=__PACKAGE__.'::'.$code unless $code=~m/::/;
			if ($children{$eid.'children'} && $cparams)
			{	($out,$in)=split /\s*=\s*/, $cparams,2;
				for my $child (split /\|/,$children{$eid.'children'})
				{	push @in,  map $child.':'.$_, split / +/,$in;
					push @out, map $child.':'.$_, split / +/,$out;
				}
			}
			$code=[$code,@out];# if @out >1;
			$default{$_}=[$code,@in] for @out;
			#warn "$_ code=$code->[0] with (@in)\n" for @out;
		}
	}
	#process optional functions
	for my $elem (@$elems)
	{	my ($eid,$elem)=@$elem;
		next unless $elem && $GraphElem{$elem};
		my $optional= $GraphElem{$elem}{optional};
		next unless $optional;
		for my $ref (@$optional)
		{	my ($code,$params)=@$ref;
			my ($out,$in)=split /\s*=\s*/, $params,2;
			my @in=  map $eid.$_, split / +/,$in;
			my @out= map $eid.$_, split / +/,$out;
			my $present= grep exists $dep{$_}, @in;
			next unless $present==@in;
			$code=__PACKAGE__.'::'.$code unless $code=~m/::/;
			$code=[$code,@out];# if @out >1;
			$dep{$_}=[$code,@in] for @out;
			#warn "$_ code=$code->[0] with (@in)\n" for @out;
		}
	}
	$dep{'@DEFAULT'}=\%default;
	return \%dep,\%update;
}

sub markup_layout
{	my ($arg,$text,$markup,$hide)=@_;
	return if $hide;
	my $pangocontext=$arg->{widget}{view}->create_pango_context;
	my $layout= Pango::Layout->new($pangocontext);
	if (defined $markup) { $markup=~s#(?:\\n|<br>)#\n#g; $layout->set_markup($markup); }
	else { $text='' unless defined $text; $layout->set_text($text); }
	return $layout;
}
sub layout_size
{	my ($arg,$layout)=@_;
	return 0,0,0 unless $layout;
	my $bl= $layout->get_iter->get_baseline / Pango->SCALE;
	return $layout->get_pixel_size, $bl;
}
sub layout_draw
{	my ($arg,$layout,$x,$y,$w,$h,$rotate)=@_;
	return unless $layout;
#warn "drawing layout at x=$x y=$y width=>$w, height=>$h text=".$layout->get_text."\n";
	$x+=$arg->{x};
	$y+=$arg->{y};
	my $cr= $arg->{cr};
	$cr->save;
	$cr->rectangle($x,$y,$w,$h);
	$cr->clip;
	my $intersect= $cr->get_clip_rectangle;
	if ($intersect->{width} && $intersect->{height})
	{	$layout->set_width($w * Pango->SCALE);
		$layout->set_ellipsize('end'); #ellipsize
		if ($rotate)
		{	my $matrix= Pango::Matrix->new(xx=>1,xy=>0,yx=>0,yy=>1,x0=>0,y0=>0); #FIXME should be default for Pango::Matrix->new, ask maintainer of Gtk3.pm, cause all widgets to throw 'invalid matrix (not invertible)' errors when some values are not set properly
			$matrix->rotate($rotate);
			$layout->get_context->set_matrix($matrix);
			$layout->get_context->set_base_gravity('auto'); #so that vertical script is not rotated when the string is drawn vertically, barely tested
			my $rect= $layout->get_extents;
			my ($minx,$miny);
			# should use $matrix->transform_rectangle but it segfaults for some reason
			# transform the rectangle and find its bounding box, and take the top-left coordinates
			for my $sx ($rect->{x},$rect->{x}+$rect->{width})
			{	for my $sy ($rect->{y},$rect->{y}+$rect->{height})
				{	my $mx= $sx * $matrix->xx + $sy * $matrix->xy + $matrix->x0;
					my $my= $sx * $matrix->yx + $sy * $matrix->yy + $matrix->y0;
					$minx= $mx unless defined $minx && $minx<$mx;
					$miny= $my unless defined $miny && $miny<$my;
				}
			}
			$cr->translate( -int($minx/Pango->SCALE), -int($miny/Pango->SCALE));
		}
		$arg->{style}->render_layout($cr,$x,$y,$layout);
	}
	$cr->restore;
#	my $gc=$arg->{style}->text_gc($arg->{state});
#	$gc->set_clip_rectangle($clip);
#	$arg->{window}->draw_layout($gc,$x,$y,$layout);
#	$gc->set_clip_rectangle(undef);
}
sub box_draw
{	my ($arg,$x,$y,$w,$h,$color,$filled,$width,$hide)=@_;
	return if $hide;
	$x+=$arg->{w} if $x<0;
	$y+=$arg->{h} if $y<0;
	$w+=$arg->{w} if $w<=0;
	$h+=$arg->{h} if $h<=0;
	$x+=$arg->{x};
	$y+=$arg->{y};

	my $cr= $arg->{cr};
	$cr->save;
	if ($color && $color ne 'fg') #2TO3 fg color probably not right FIXME
	{	$color= Gtk3::Gdk::RGBA::parse($color);
		$cr->set_source_gdk_rgba($color) if $color;
	}
	$cr->set_line_width($width);
	$cr->rectangle($x,$y,$w,$h);
  	$cr->stroke_preserve;
	$cr->fill if $filled;
	$cr->restore;
}
sub pbar_draw
{	my ($arg,$x,$y,$w,$h,$fill,$hide)=@_;
	return if $hide;
	$x+=$arg->{w} if $x<0;
	$y+=$arg->{h} if $y<0;
	$w+=$arg->{w} if $w<=0;
	$h+=$arg->{h} if $h<=0;
	$x+=$arg->{x};
	$y+=$arg->{y};
	$fill=0 if $fill<0;
	$fill=1 if $fill>1;
	my $cr=    $arg->{cr};
	my $style= $arg->{style};
	$style->save;
	#$style->add_class(Gtk3::STYLE_CLASS_PROGRESSBAR);
	$style->add_class(Gtk3::STYLE_CLASS_TROUGH);
	$style->render_background($cr,$x,$y,$w,$h);
	$style->render_frame($cr,$x,$y,$w,$h);
	$style->add_class(Gtk3::STYLE_CLASS_PROGRESSBAR);
	$style->remove_class(Gtk3::STYLE_CLASS_TROUGH);
	$style->render_background($cr,$x,$y,$w*$fill,$h);
	$style->restore;
}
sub line_draw
{	my ($arg,$x1,$y1,$x2,$y2,$color,$width,$hide)=@_;
	return if $hide;
	my ($offx,$offy)= @{$arg}{'x','y'};
	$x1+=$arg->{w} if $x1<0;
	$x2+=$arg->{w} if $x2<0;
	$y1+=$arg->{h} if $y1<0;
	$y2+=$arg->{h} if $y2<0;
	$x1+=$offx; $y1+=$offy;
	$x2+=$offx; $y2+=$offy;

	my $cr= $arg->{cr};
	$cr->save;
	if ($color && $color ne 'fg')
	{	$color= Gtk3::Gdk::RGBA::parse($color);
		$cr->set_source_gdk_rgba($color) if $color;
		$cr->set_line_width($width);
		$cr->move_to($x1,$y1);
		$cr->line_to($x2,$y2);
		$cr->stroke;
	}
	else #2TO3 FIXME set width ?
	{	$arg->{style}->render_line($cr,$x1,$y1,$x2,$y2);
	}
	$cr->restore;
}

sub pic_cached
{	my ($arg,$file,$resize,$w,$h,$xpad,$ypad,$crop,$hide)=@_;
	return undef,0 if $hide || !$file;
	if (defined $w || defined $h)
	{	if (defined $w)	{ $w-=2*$xpad; return undef,0 if $w<=0 }
		else {$w=0; $resize='ratio'}
		if (defined $h)	{ $h-=2*$ypad; return undef,0 if $h<=0 }
		else {$h=0; $resize='ratio'}
		$resize||='s';
		$resize.="_$w"."_$h";
	}
	my $cached=GMB::Picture::load_skinfile($file,$crop,$resize);
	return $cached||$resize, !$cached;
}
sub pic_size
{	my ($arg,$cached,$file,$crop,$hide)=@_;
	return undef,0,0 if $hide || !$file;
	my $pixbuf=$cached;
	unless (ref $cached) #=> cached is resize_w_h
	{	$pixbuf=GMB::Picture::load_skinfile($file,$crop,$cached,1);
	}
	return undef,0,0 unless $pixbuf;
	return $pixbuf,$pixbuf->get_width,$pixbuf->get_height;
}
sub icon_size
{	my ($arg,$size,$icon,$y,$h,$xpad,$ypad,$hide)=@_;
	return 0,0,0,0,0 if $hide;
	$size= $::IconSize{$size}||16 if $size=~m/\D/;
	my ($w1,$h1)=($size,$size);
	my $nb= ref $icon ? @$icon : (defined $icon && $icon ne '');
	return 0,0 unless $nb;
	$y||=0;
	$y+=$arg->{h} if $y<0;
	$h||=0;
	$h+=$arg->{h}-$y if $h<=0;
	$h+=$ypad;
	$w1+=$xpad;
	$h1+=$ypad;
	my $nbh=$nb;
	if ($nb*$h1>$h) { $nbh=int($h/$h1) }
	$nbh=1 unless $nbh;
	my $hr= $nbh*$h1-$ypad;
	my $wr= $w1*(int($nb/$nbh) + (($nb % $nbh) ? 1 : 0));
	return $wr,$hr,$nbh,$w1,$h1;
}
sub icon_draw
{	my ($arg,$icon,$size,$x,$y,$w,$h,$nbh,$w1,$h1,$hide)=@_;
	return if $hide;
	return unless defined $icon && $icon ne '';
	$x+=$arg->{x};
	$y+=$arg->{y};
	my $cr= $arg->{cr};
	$cr->save;
	$cr->rectangle($x,$y,$w,$h);
	$cr->clip;
	my $intersect= $cr->get_clip_rectangle;
	if ($intersect->{width} && $intersect->{height})
	{	my $row=0;
		my $theme= Gtk3::IconTheme::get_default;
		for my $name (ref $icon ? @$icon : $icon)
		{	$name= $::IconsFallbacksCache{$name} || $name;
			my $iconinfo= Gtk3::IconTheme::get_default->lookup_icon($name,$size,['force-size']);
			next unless $iconinfo;
			my $pixbuf= $iconinfo->load_icon;
			next unless $pixbuf;
			$cr->translate($x,$y);
			$cr->set_source_pixbuf($pixbuf,0,0);
			$cr->paint;
			if (++$row<$nbh) { $x=0; $y=$h1; }
			else		 { $x=$w1; $y= -$h1*($row-1); $row=0; }
		}
	}
	$cr->restore;
}

sub pad_and_align
{	my ($context,$x,$xpad,$pad,$xalign,$wr,$w)=@_;
	$xpad||= $pad||0;
	$xalign||= 0;
	$x||=0;
	$x+=$context->{w} if $x<0;
	$w||=$wr+2*$xpad;
	$w+=$context->{w}-$x if $w<=0;
	my $wd= $w -2*$xpad;
	$x+= $xpad + $xalign *($wd-$wr);
	return $x,$wd;
}

sub aapic_cached
{	my ($arg,$picsize,$aa,$ids,$aanb,$hide)=@_;
	return undef,0 if $hide;
	#$aa||=$arg->{grouptype};
	#$now=1 if $param->{notdelayed};
	my $gid;
	if (ref $ids) { $gid= (::uniq( Songs::Map_to_gid($aa,$ids)))[$aanb]; }
	elsif (!$aanb){ $gid= Songs::Get_gid($ids,$aa); }
	my $pixbuf= defined $gid ? AAPicture::pixbuf($aa,$gid,$picsize) : undef;
	my ($aap,$queue)=	$pixbuf		?	($pixbuf,undef) :
				defined $pixbuf ?	([$aa,$gid,$picsize],1) :
							(undef,undef);
	return $aap,$queue;
}
sub aapic_size
{	my ($arg,$aap,$queue)=@_;
	return undef,0,0 unless $aap;
	my $pixbuf=  (ref $aap eq 'ARRAY') ? AAPicture::pixbuf(@$aap,1) : $aap;
	return undef,0,0 unless $pixbuf;
	return $pixbuf,$pixbuf->get_width,$pixbuf->get_height;
}
sub pixbuf_draw
{	my ($arg,$pixbuf,$x,$y,$w,$h)=@_;
	return unless $pixbuf;
	$x+=$arg->{x};
	$y+=$arg->{y};
	my $cr= $arg->{cr};
	$cr->save;
	$cr->rectangle($x,$y,$w,$h);
	$cr->clip;
	my $intersect= $cr->get_clip_rectangle;
	if ($intersect->{width} && $intersect->{height})
	{	$cr->translate($x,$y);
		$cr->set_source_pixbuf($pixbuf,0,0);
		$cr->paint;
	}
	$cr->restore;
}

#sub exp_size
#{	my ($arg,$hide)=@_;
#	return 0,0 if $hide;
#	return wr hr;
#}
#sub exp_draw
#{	my ($arg,$xd,$yd,$wd,$hd,$hide)=@_;
#	$style->paint_expander($window, $state_type, $area, $widget, $detail, $x, $y, $expander_style);
#}

sub set_action #TESTING
{	my ($arg,$x,$y,$w,$h,$actions,$hide)=@_;
	return if $hide || !ref $actions;
	$x+=$arg->{vx};
	$y+=$arg->{vy};
	my %ac=@$actions;
	$arg->{widget}{action_rectangles}{join ',',$x,$y,$w,$h}{$_}=$ac{$_} for keys %ac;
}

sub blalign #align baselines
{	my (undef,$y,$ref,@blh)=@_; #warn "blalign <- ($y,$ref,@blh)\n";
	my @y; my ($min,$max)=($y,0);
	for (my $i=0;$i<@blh;$i+=2)
	{	my $cy= $y - $blh[$i];
		$min=$cy if $min>$cy;
		push @y,$cy;
		$cy+=$blh[$i+1];
		$max=$cy if $max<$cy;
	}#warn " @y  max=$max min=$min\n";
	my $h=$max-$min;
	$_-= $min+$h*$ref-$y for @y;
	#warn "blalign -> ($h,@y)\n";
	return $h,@y;
}
sub align
{	my (undef,$align,$x,$ref,@cw)=@_;# warn "align <- ($align,$x,$ref,@cw)\n";
	$ref=$align unless defined $ref;
	my $max=0;
	$max<$_ and $max=$_ for @cw;
	$max*=$align;
	my @x=map $x - $max*$ref + $align*($max-$_), @cw;
	#warn "align -> ($max,@x)\n";
	return $max,@x;
}
sub epack
{	my (undef,$x,$pad,@cw)=@_;
	$pad||=0;
	my @x;
	for my $cw (@cw)
	{	push @x,$x;
		$x+= $cw+$pad;
	}
	return $x,@x;
}

package GMB::Edit::STGroupings;
use base 'Gtk3::Box';

my %opt_types=
(	Text	=> [ sub {my $entry=Gtk3::Entry->new;$entry->set_text($_[0]); return $entry}, sub {$_[0]->get_text},1 ],
	Color	=> [	sub { Gtk3::ColorButton->new_with_rgba( Gtk3::Gdk::RGBA::parse($_[0]) ); },
			sub {my $c=$_[0]->get_color; sprintf '#%02x%02x%02x',$c->red/256,$c->green/256,$c->blue/256; }, 1 ],
	Font	=> [ sub { Gtk3::FontButton->new_with_font($_[0]); }, sub {$_[0]->get_font_name}, 1 ],
	Boolean	=> [ sub { my $c=Gtk3::CheckButton->new($_[1]); $c->set_active(1) if $_[0]; return $c }, sub {$_[0]->get_active}, 0 ],
	Number	=> [	sub {	my $s=Gtk3::SpinButton->new_with_range($_[2]{min}||0, $_[2]{max}||9999, $_[2]{step}||1);
				$s->set_digits($_[2]{digits}) if $_[2]{digits};
				#::setlocale(::LC_NUMERIC,'C');
				$s->set_value($_[0]);
				#::setlocale(::LC_NUMERIC,'');
				return $s;
			    },
			sub { ::setlocale(::LC_NUMERIC,'C'); my $v=''.$_[0]->get_value; ::setlocale(::LC_NUMERIC,''); return $v}, 1 ],
	Combo => [ sub  { my @l=split( /\|/,$_[2]{list} );
			  my @l2;
			  while (@l) { my $w=shift @l; $w.="|".shift(@l) while @l && $w=~s/\\$//; push @l2,$w; }
			  TextCombo->new( \@l2, $_[0]);
		 	},
		   sub {$_[0]->get_value},1 ],
);

sub new
{	my ($class,$dialog,$init) = @_;
	my $self= bless Gtk3::VBox->new, $class;
	my $vbox=Gtk3::VBox->new;
	my $sw = Gtk3::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($vbox);
	$self->{vbox}=$vbox;
	my $badd= ::NewIconButton('list-add-symbolic',_"Add a group",sub {$_[0]->get_parent->AddRow('album|default');} );
	$self->add($sw);
	$self->pack_start($badd,0,0,2);
	$self->Set($init);
	return $self;
}

sub Set
{	my ($self,$string)=@_;
	my $vbox=$self->{vbox};
	$vbox->remove($_) for $vbox->get_children;
	for my $group ($string=~m#([^|]+\|[^|]+)(?:\||$)#g) #split into "word|word"
	{	$self->AddRow($group);
	}
}

sub AddRow
{	my ($self,$string)=@_;
	my ($type,$skin)=split /\|/,$string;
	my $opt;
	if ($skin=~s/\((.*)\)$//) { $opt=::ParseOptions($1) }
	my $typelist=TextCombo::Tree->new( Songs::ListGroupTypes(), $type );
	my $skinlist=TextCombo->new({map {$_ => $SongTree::GroupSkin{$_}{title}||$_} keys %SongTree::GroupSkin}, $skin, \&skin_changed_cb );
	my $button=::NewIconButton('list-remove-symbolic',undef,sub
		{ my $button=$_[0];
		  my $box= $button->get_parent->get_parent;
		  $box->get_parent->remove($box);
		},'none');
	my $fopt= Gtk3::Expander->new;
	my $vbox= Gtk3::VBox->new;
	my $hbox= Gtk3::HBox->new;
	$hbox->pack_start($_,0,0,2) for $button,
		Gtk3::Label->new(_"Group by :"),	$typelist,
		Gtk3::Label->new(_"using skin :"),	$skinlist;
	my $optbox= Gtk3::HBox->new;
	my $filler= Gtk3::HBox->new;
	my $sg= Gtk3::SizeGroup->new('horizontal');
	$sg->add_widget($_) for $button,$filler;
	$optbox->pack_start($_,0,0,2) for $filler,$fopt;
	$vbox->pack_start($_,0,0,2) for $hbox,$optbox;
	$vbox->{type}=$typelist;
	$vbox->{skin}=$skinlist;
	$vbox->{fopt}=$fopt;
	$fopt->set_no_show_all(1);
	$vbox->show_all;
	skin_changed_cb($skinlist,$opt);
	$self->{vbox}->pack_start($vbox,0,0,2);
}

sub skin_changed_cb
{	my ($combo,$opt)=@_;
	my $skin=$combo->get_value;
	my $hbox=$combo; $hbox=$hbox->get_parent until $hbox->{fopt};
	my $fopt=$hbox->{fopt};
	$fopt->remove($fopt->get_child) if $fopt->get_child;
	delete $fopt->{entry};
	$fopt->set_label( _"skin options" );
	my $table= Gtk3::Table->new(2,1,0); my $row=0;
	my $ref0=$SongTree::GroupSkin{$skin}{options};
	for my $key (sort keys %$ref0)
	{	my $ref=$ref0->{$key};
		my $type=$ref->{type};
		$type='Text' unless exists $opt_types{$type};
		my $l=$ref->{name}||$key;
		my $label= Gtk3::Label->new($l);
		$label->set_alignment(0,.5);
		my $v=$ref->{default};
		$v=::decode_url($opt->{$key}) if $opt && exists $opt->{$key};
		$v='' unless defined $v;
		my $entry= $opt_types{$type}[0]($v,$l,$ref);
		my $x=0;
		if ($opt_types{$type}[2])
		{	$table->attach($label, 0, 1, $row, $row+1, ['expand','fill'], [], 2, 2);
			$x=1;
		}
		$table->attach($entry, $x, 2, $row, $row+1, ['expand','fill'], [], 2, 2);
		$row++;
		$fopt->{entry}{$key}=$entry;
	}
	if ($fopt->{entry})
	{	$fopt->add($table);
		$table->show_all;
		$fopt->show;
	}
	else {$fopt->hide}
}

sub Result
{	my $self=shift;
	my $vbox=$self->{vbox};
	my @groups;
	for my $hbox ($vbox->get_children)
	{	my $type=$hbox->{type}->get_value;
		my $skin=$hbox->{skin}->get_value;
		my $group="$type|$skin";
		if (my $h=$hbox->{fopt}{entry})
		{	my @opt;
			for my $key (sort keys %$h)
			{	my $type=$SongTree::GroupSkin{$skin}{options}{$key}{type};
				my $v= $opt_types{$type}[1]($h->{$key});
				push @opt,$key.'='.::url_escapeall($v);
			}
			$group.='('.join(',',@opt).')';
		}
		push @groups,$group;
	}
	return join '|',@groups;
}

package GMB::Expression;
no warnings;

our %alias=( 'if' => 'iff', pesc => '::PangoEsc', min =>'::min', max =>'::max', sum =>'::sum',);
our %functions=
(	formattime=> ['do {my ($f,$t,$z)=(',		'); !$t && defined $z ? $z : ::strftime_utf8($f,localtime($t)); }'],
	#sum	=>   ['do {my $sum; $sum+=$_ for ',	';$sum}'],
	average	=>   ['do {my $sum=::sum(',		'); @l ? $sum/@l : undef}'],
	#max	=>   ['do {my ($max,@l)=(',		'); $_>$max and $max=$_ for @l; $max}'],
	#min	=>   ['do {my ($min,@l)=(',		'); $_<$min and $min=$_ for @l; $min}'],
	iff	=>   ['do {my ($cond,$res,@l)=(',	'); while (@l>1) {last if $cond; $cond=shift @l;$res=shift @l;} $cond ? $res : $l[0] }'],
	size	=>   ['do {my ($l)=(',			'); ref $l ? scalar @$l : 1}'],
	ratingpic=>  ['Songs::Stars(',		',"rating");'],
	playmarkup=> \&playmarkup,
);
$functions{$_}||=undef for qw/ucfirst uc lc chr ord not index length substr join sprintf warn abs int rand/, values %alias;
our %vars2=
(song=>
 {	#ufile #REMOVED PHASE1 fix the doc
	#upath #REMOVED PHASE1 fix the doc
	progress=> ['$arg->{ID}==$::SongID ? $::PlayTime/Songs::Get($arg->{ID},"length") : 0',	'length','CurSong Time'],
	queued	=> ['do {my $i;my $f;for (@$::Queue) {$i++; $f=$i,last if $arg->{ID}==$_};$f}',undef,'Queue'],
	playing => ['$arg->{ID}==$::SongID',		undef,'CurSong'],
	playicon=> ['::Get_PPSQ_Icon($arg->{ID},!$arg->{currentsong})',	undef,'Playing Queue CurSong'],
	labelicons=>['[Songs::Get_icon_list("label",$arg->{ID})]', 'label','Icons'],
	ids	=> ['$arg->{ID}'],
 },
 group=>
 {	ids	=> ['$arg->{groupsongs}'],
	year	=> ['groupyear($arg->{groupsongs})',	'year'],
	artist	=> ['groupartist("artist",$arg->{groupsongs})',	'artist'],
	album_artist=>  ['groupartist("album_artist",$arg->{groupsongs})',	'album_artist'],
	album_artistid=>['groupartistid("album_artist",$arg->{groupsongs})',	'album_artist'],
	album	=> ['groupalbum($arg->{groupsongs},0)',	'album'],
	albumraw=> ['groupalbum($arg->{groupsongs},1)',	'album'],
	artistid=> ['groupartistid($arg->{groupsongs})','artist'],
	albumid	=> ['groupalbumid($arg->{groupsongs})',	'album'],
	genres	=> ['groupgenres($arg->{groupsongs},"genre")',	'genre'],
	labels	=> ['groupgenres($arg->{groupsongs},"label")',	'label'],
	gid	=> ['Songs::Get_gid($arg->{groupsongs}[0],$arg->{grouptype})'],	#FIXME PHASE1
	title	=> ['($arg->{groupsongs} ? Songs::Get_grouptitle($arg->{grouptype},$arg->{groupsongs}) : "")'], #FIXME should the init case ($arg->{groupsongs}==undef) be treated here ?
	rating_avrg => ['do {my $sum; $sum+= $_ for Songs::Map(ratingnumber=>$arg->{groupsongs}); $sum/@{$arg->{groupsongs}}; }', 'rating'], #FIXME round, int ?
	'length' => ['do {my (undef,$v)=Songs::ListLength($arg->{groupsongs}); sprintf "%d:%02d",$v/60,$v%60;}', 'length'],
	nbsongs	=> ['scalar @{$arg->{groupsongs}}'],
	disc	=> ['groupdisc($arg->{groupsongs})',	'disc'],
	discname=> ['groupdiscname($arg->{groupsongs})','discname'],
 }
);

my %PCompl=( '{','}',  '(',')',  '[',']' , '"', =>0, "'"=>0,  );

sub split_options #doesn't work the same as ParseOptions : count parens and don't remove quotes #FIXME find a way to merge them ?
{	(local $_,my $prefix)=@_;
	my %opt;
	while (1)
	{	my ($key,$begin,$end,@closing);
		if (m#\G\s*(\w+)=#gc) {$key=$1;$begin=pos}
		else {last}
		while (m#\G[^]["'{}(),]*#gc && m#\G(.)#gc)
		{	if ($1 eq ',')
			{	next if @closing;
				$end=pos()-1;
				last;
			}
			my $c= $PCompl{$1};
			if ($c) { push @closing,$c; }	#opening (, [ or {
			elsif (defined $c)		#quote " or '
			{	if ($1 eq '"')	{m#\G(?:[^"\\]|\\.)*"#gc}
				else		{m#\G(?:[^'\\]|\\.)*'#gc}
			}
			else				#closing ), ], or }
			{	shift @closing if $closing[0] eq $1;
			}
		}
		my $l= ($end||pos) -$begin;
		$opt{$prefix.$key}= substr $_,$begin,$l;
		$key=undef;
		last unless $end;
	}
	return \%opt;
}

sub parse
{	my ($hash,$context,$update,$code_dep,$constant)=@_;
	my (%funcused,%var2used,%argused,@watch);

	while ( (my$key,local $_)=each %$hash )
	{ my (@f_end,@pcount,$pcount,%var1used); my $r=''; my $depth=0;
	  while (1)
	  {	while (m#\G\s*([([])#gc) # opening ( or [
		{	$depth++;
			$r.=$1;
			$pcount++;
		}
		m#\s*#g;
		if (m#\G(-?\d*\.?\d+)#gc)	{$r.=$1}	#number
		elsif (m#\G(''|'.*?[^\\]')#gc)	{$r.=$1}	#string between ' '
		  #variable or function
		elsif (m#\G([-!]\s*)?(\$_?)?([a-zA-Z][:0-9_a-zA-Z]*)(\()?#gc)
		{	last if $2 && $4;
			$r.=$1 if $1;
			my $v=$3;
			$v=$alias{$v} if $alias{$v};
			if ($4)		#functions
			{	my ($pre,$post);
				if (exists $functions{$v})
				{	$funcused{$v}++;
					if (my $ref=$functions{$v})
					{	$ref=$ref->($constant) if ref $ref eq 'CODE';
						$pre=$ref->[0];
						$post=$ref->[1];
						push @watch,[undef,$ref->[2],$ref->[3]] if @$ref>2;
					}
					else { $pre=$v.'('; $post=')'; }
				}
				else { $pre='error('; $post=')'; }
				$r.= $pre;
				push @f_end, $post;
				push @pcount,$pcount;
				$pcount=0;
				$depth++;
				next;
			}
			elsif ($2)
			{	if   ($2 eq '$')
				{	$var2used{$v}++;
					my $ref=$vars2{$context}{$v};
					if ($ref)
					{	push @watch,$ref;
						$r.='('.$ref->[0].')';
					}
					elsif ($context eq 'song') #for normal fields
					{	my $action= $v=~s/_$// ? 'get' : 'display';
						push @watch,[undef,$v];
						$r.='('.Songs::Code($v,$action, ID => '$arg->{ID}').')';
					}
					else {$r.= "'unknown var \\'$v\\''"};
				}
				else	{ $argused{$v}++; $r.="\$arg->{$v}"; }
			}
			elsif (exists $constant->{$v}) { $r.=$constant->{$v}; }
			else		{ $var1used{$v}++; $r.="\$var{'$v'}"; }
		}
		else {last}
		while (m#\G\s*([])])#gc) # closing ) or ]
		{	next if $depth==0;
			$depth--;
			if ($pcount) {$pcount--;$r.=$1;}
			elsif (@f_end) {$r.=pop @f_end; $pcount=pop @pcount}
			else {$r.=$1;}
		}
		if ( m#\G\s*([!=<>]=|[-+.,%*/<>]|&&|\|\|)#gc
		  || m#\G\s*((?:x|eq|lt|gt|cmp|le|ge|ne|or|xor|and)\s)#gc) {$r.=$1}
		else {last}
	  } # end of parsing for $key

	  $code_dep->{$key}= [$r,(keys %var1used ? keys %var1used : ())];
	  if (length $_!=pos)
	  {	warn "$_\n->$r\n";
		warn "** error at ".pos()." **\n\n";
	  }
	} #done all keys

	if ($update)
	{ for my $ref (@watch)
	  {	my (undef,$c,$e)=@$ref;
		if (defined $c)
		{	$update->{col}{$_}=undef for Songs::Depends(split / /,$c);
		}
		if (defined $e)
		{	$update->{event}{$_}=undef for split / /,$e;
		}
	  }
	}
}

sub MakeMake
{	my ($dep,$targets)=@_;
	my (@targets0,@targets1);
	my $dep0=$dep->{'@DEFAULT'};
	for my $eid (@$targets)
	{	if ($dep0->{$eid.':queue'}) { push @targets0,$eid.':queue'; push @targets1,$eid; }
		elsif ($dep0->{$eid.':draw'}) { push @targets0,$eid.':draw'; }
	}
	my $sub='sub {my $arg=$_[0]; my %var; my @queued; my @queuedif;';
	my @notdone; my %done;
	my $inqueue;
	while (1)
	{	my $target=shift @targets0;
		unless ($target)
		{	$target= shift @targets1;
			last unless $target;
			push @targets0,@notdone;
			@notdone=();
			$inqueue=1;
			$sub.="push \@queuedif,'$target:queue'; push \@queued, sub {";
			$target.=':draw';
		}
		($sub,my $notdone)=Make($dep,$target,undef,\%done,$sub);
		push @notdone,$target if exists $notdone->{$target};
		if ($inqueue)
		{	$sub.='};' unless @targets0;
		}
	}
	if ($inqueue)
	{	$sub.='while (my $if=shift @queuedif) { if ($var{$if}) {last} else {my $sub=shift @queued; &$sub} }';
		$sub.='return @queued ? [@queued,$arg] : undef;';
	}
	$sub.='}';
	warn "Couldn't evaluate : @notdone\n" if @notdone;

	my $coderef=eval $sub; warn "GMBMakeMake : $sub\n" if $::debug;
	if ($@) {warn "\n";my $c=1; for (split "\n",$sub) {warn "$c $_\n";$c++};warn "$sub\n** error : $@\n"; $coderef=sub {};}
	return $coderef;
}

sub Make
{	my ($dep,$target,$var,$done,$sub)=@_;
	my $compile= $done? 0 : 1;
	my $dep0=$dep->{'@DEFAULT'};
	$done||={};
	$sub||='my $arg=$_[0]; my %var;';
	my %todo=($target => undef);
	while (exists $todo{$target})
	{	#warn "\ntodo :",(join ',',keys %todo),"\n";
		my $previous=join ',',keys %todo;
		for my $key (keys %todo)
		{	#warn "key=$key -- $dep->{$key} --- $dep0->{$key}\n";
			my ($code,@deps)=@{ $dep->{$key}||$dep0->{$key} };
		   	my $notnow;
			for (@deps)
			{	my $d=$_;
				my $opt= $d=~s#\?$##;
				next if exists $done->{$d} || !exists $dep->{$d} && ($opt || !exists $dep0->{$d});
				#warn " -> todo $d\n";
				$todo{$d}=undef;
				$notnow=1;
			}
			unless ($notnow)
			{	#warn "$key ---found in ($code,@deps)\n";
				if (ref $code)
				{	my ($func, @keys)=@$code; #warn " -> ($func, @keys)\n";
					my $out=join ',',map "'$_'", @keys;
					my $in= join ',',map "'$_'", @deps; $in=~s#\?##g;
					$out= @keys>1 ? "\@var{$out}" : "\$var{$out}";
					$in = @deps>1 ? "\@var{$in}"  : "\$var{$in}";
					$sub.= "$out=$func(\$arg,$in);\n";
					for (@keys) { delete $todo{$_}; $done->{$_}=undef; }
					last;
				}
				else
				{	$sub.="\$var{'$key'}=$code;\n" if defined $code;
					delete $todo{$key};
					$done->{$key}=undef;
					next;
				}
			}
		}
		my $new=join ',',keys %todo;
		if ($previous eq $new)
		{	warn "** column definition unsolvable for $new **\n" if $compile;
			last;
		}
	}
	unless ($compile) { return $sub,\%todo }
	$sub.='return \%var;'; warn "\nGMBMake : sub=\n".$sub."\n\n" if $::debug;
	my $coderef=eval "sub {$sub}";
	if ($@) {warn "\n";my $c=1; for (split "\n",$sub) {warn "$c $_\n";$c++};warn "** error : $@\n"; $coderef=sub {};}
	elsif ($var) { $coderef->($var); }
	else { return $coderef}
}

=unused
sub average #not used
{	my $sum;
	$sum+=$_ for @_;
	return (@_? $sum/@_ : undef);
}
sub max #not used
{	my $max=shift;
	$_>$max and $max=$_ for @_;
	return $max;
}
sub min #not used
{	my $min=shift;
	$_<$min and $min=$_ for @_;
	return $min;
}
sub iff #not used
{	my $cond=shift;
	while (@_>2)
	{	my $res=shift;
		return $res if $cond;
		$cond=shift;
	}
	return $cond ? $_[0] : $_[1];
}

=cut

sub groupyear
{	my $songs=$_[0];
	my %h;
	my @y=sort { $a <=> $b } grep $_,Songs::Map('year',$songs);
	my $years='';
	if (@y) {$years=$y[0]; $years.=' - '.$y[-1] if $y[-1]!=$years; }
	return $years;
}

sub groupalbumid
{	my $songs=$_[0];
	my $l= Songs::UniqList('album',$songs);
	return @$l==1 ? $l->[0] : $l;
}
sub groupartistid		##FIXME PHASE1 use artists instead ?
{	my ($field,$songs)=@_;
	my $l= Songs::UniqList($field,$songs);
	return @$l==1 ? $l->[0] : $l;
}

sub groupalbum
{	my ($songs,$raw)=@_;
	my $l= Songs::UniqList('album',$songs);
	if (@$l==1)
	{	my $album= $raw ? Songs::Gid_to_Get('album',$l->[0]) : Songs::Gid_to_Display('album',$l->[0]);
		$album='' unless defined $album;
		return $album;
	}
	return ::__("%d album","%d albums",scalar @$l);
}
sub groupartist	#FIXME optimize PHASE1
{	my ($field,$songs)=@_;
	my $h=Songs::BuildHash($field,$songs);
	my $nb=keys %$h;
	return Songs::Gid_to_Display($field,(keys %$h)[0]) if $nb==1;
	my @l=map split(/$Songs::Artists_split_re/), keys %$h;
	my %h2; $h2{$_}++ for @l;
	my @common;
	for (@l) { if ($h2{$_}>=$nb) { push @common,$_; delete $h2{$_}; } }
	return @common ? join ' & ',@common : ::__("%d artist","%d artists",scalar(keys %h2));
}
sub groupgenres
{	my ($songs,$field,$common)=@_;
	my $h=Songs::BuildHash($field,$songs,'name');
	delete $h->{''};
	return join ', ',sort ($common? grep($h->{$_}==@$songs,keys %$h) : keys %$h);
}
sub groupdisc
{	my $songs=$_[0];
	my $h=Songs::BuildHash('disc',$songs);
	delete $h->{''};
	if ((keys %$h)==1 && (values %$h)[0]==@$songs) {return (keys %$h)[0]}
	else {return ''}
}
sub groupdiscname
{	my $songs=$_[0];
	if (Songs::FieldEnabled('discname'))
	{	my $h=Songs::BuildHash('discname',$songs);
		if ((keys %$h)==1 && (values %$h)[0]==@$songs)
		{	my $name= Songs::Gid_to_Display('discname',(keys %$h)[0]);
			return $name if length $name;
		}
		else { return '' } #no common discname
	}
	# if discname field not enabled or no discname, try to make a discname using the disc number
	my $d=groupdisc($songs);
	return $d ? ::__x(_"disc {disc}",disc =>$d) : '';
}
sub error
{	warn "unknown function : '$_[0]'\n";
}

sub playmarkup
{	my $constant=$_[0];
	return ['do { my $markup=',	'; $arg->{currentsong} ? \'<span '.$constant->{playmarkup}.'>\'.$markup."</span>" : $markup }',undef,'CurSong'];
}

1;
