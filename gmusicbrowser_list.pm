# Copyright (C) 2005-2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;

package Browser;
use Gtk2 ;

use constant { TRUE  => 1, FALSE => 0, };

our @MenuPlaying=
(	{ label => _"Follow playing song",	code => sub { $_[0]{songlist}->FollowSong if $_[0]{songlist}->{follow}^=1; }, check => sub { $_[0]{songlist}->{follow} }, },
	{ label => _"Filter on playing Album",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('album',$::SongID) )	if defined $::SongID; }},
	{ label => _"Filter on playing Artist",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('artists',$::SongID) )if defined $::SongID; }},
	{ label => _"Filter on playing Song",	code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('title',$::SongID) )	if defined $::SongID; }},
	{ label => _"use the playing Filter",	code => sub { ::SetFilter($_[0]{songlist}, $::PlayFilter ); }, test => sub {::GetSonglist($_[0]{songlist})->{mode} ne 'playlist'}}, #FIXME	if queue use queue, if $ListMode use list
	{ label => _"Recent albums",		submenu => sub { my $sl=$_[0]{songlist};my @gid= ::uniq( Songs::Map_to_gid('album',$::Recent) ); $#gid=19 if $#gid>19; my $m=::PopupAA('album',nosort=>1,nominor=>1,widget => $_[0]{self}, list=>\@gid, cb=>sub { ::SetFilter($sl, Songs::MakeFilterFromGID('album',$_[1]) ); }); return $m; } },
	{ label => _"Recent artists",		submenu => sub { my $sl=$_[0]{songlist};my @gid= ::uniq( Songs::Map_to_gid('artist',$::Recent) ); $#gid=19 if $#gid>19; my $m=::PopupAA('artists',nosort=>1,nominor=>1,widget => $_[0]{self}, list=>\@gid, cb=>sub { ::SetFilter($sl, Songs::MakeFilterFromGID('artists',$_[1]) ); }); return $m; } },
	{ label => _"Recent songs",		submenu => sub { my @ids=@$::Recent; $#ids=19 if $#ids>19; return [map { $_,Songs::Display($_,'title') } @ids]; },
	  submenu_ordered_hash => 1,submenu_reverse=>1,		code => sub { ::SetFilter($_[0]{songlist}, Songs::MakeFilterFromID('title',$_[1]) ); }, },
);

sub makeFilterBox
{	my $box=Gtk2::HBox->new;
	my $FilterWdgt=FilterBox->new
	( sub	{	my $filt=FilterBox::posval2filter(@_);
			::SetFilter($box,$filt);
		},
	  undef,
	  FilterBox::filter2posval('title:s:')
	);
	$FilterWdgt->addtomainmenu(_"edit ..." => sub
		{	::EditFilter($box,::GetFilter($box),undef,sub {::SetFilter($box,$_[0]) if defined $_[0]});
		});
	my $okbutton=::NewIconButton('gtk-apply',undef,sub {$FilterWdgt->activate},'none');
	$okbutton->set_tooltip_text(_"apply filter");
	$box->pack_start($FilterWdgt, FALSE, FALSE, 0);
	$box->pack_start($okbutton, FALSE, FALSE, 0);
	return $box;
}

sub makeLockToggle
{	my $opt=$_[0];
	my $toggle=Gtk2::ToggleButton->new;
	$toggle->add(Gtk2::Image->new_from_stock('gmb-lock','menu'));
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
	my $songlist=$selfitem->isa('SongList') || $selfitem->isa('SongTree') ? $selfitem : ::GetSonglist($selfitem);
	my $menu= ($selfitem->isa('Gtk2::MenuItem') && $selfitem->get_submenu) || Gtk2::Menu->new;
	my $menusub=sub { $songlist->Sort($_[1]) };
	for my $name (sort keys %{$::Options{SavedSorts}})
	{   my $sort=$::Options{SavedSorts}{$name};
	    my $item = Gtk2::CheckMenuItem->new_with_label($name);
	    $item->set_draw_as_radio(1);
	    $item->set_active(1) if $songlist->{sort} eq $sort;
	    $item->signal_connect (activate => $menusub,$sort );
	    $menu->append($item);
	}
	my $itemEditSort=Gtk2::ImageMenuItem->new(_"Custom...");
	$itemEditSort->set_image( Gtk2::Image->new_from_stock('gtk-preferences','menu') );
	$itemEditSort->signal_connect (activate => sub
	{	my $sort=::EditSortOrder($selfitem,$songlist->{sort});
		$songlist->Sort($sort) if $sort;
	});
	$menu->append($itemEditSort);
	return $menu;
}

sub fill_history_menu
{	my $selfitem=$_[0];
	my $menu= $selfitem->get_submenu || Gtk2::Menu->new;
	my $mclicksub=sub   { $_[0]{middle}=1 if $_[1]->button == 2; return 0; };
	my $menusub=sub
	 { my $f=($_[0]{middle})? Filter->newadd(FALSE, ::GetFilter($selfitem,1),$_[1]) : $_[1];
	   ::SetFilter($selfitem,$f);
	 };
	for my $f (@{ $::Options{RecentFilters} })
	{	my $item = Gtk2::MenuItem->new_with_label( $f->explain );
		$item->signal_connect(activate => $menusub,$f);
		$item->signal_connect(button_release_event => $mclicksub,$f);
		$menu->append($item);
	}
	return $menu;
}

package LabelTotal;
use Gtk2;

use base 'Gtk2::Bin';

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
	{	$self=Gtk2::Button->new;
		$self->set_relief($opt->{relief});
	}
	else { $self=Gtk2::EventBox->new; }
	bless $self,$class;
	$self->{$_}= $opt->{$_} for qw/size format group/;
	$self->add(Gtk2::Label->new);
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
	::UnWatch($self,$_) for qw/SongArray SongsAdded SongsRemoved/;
}

sub button_press_event_cb
{	my ($self,$event)=@_;
	my $menu=Gtk2::Menu->new;
	for my $mode (sort {$Modes{$a}{label} cmp $Modes{$b}{label}} keys %Modes)
	{	my $item = Gtk2::CheckMenuItem->new( $Modes{$mode}{label} );
		$item->set_draw_as_radio(1);
		$item->set_active($mode eq $self->{mode});
		$item->signal_connect( activate => sub { $self->Set_mode($mode) } );
		$menu->append($item);
	 }
	$menu->show_all;
	$menu->popup(undef, undef, \&::menupos, undef, $event->button, $event->time);
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
	if (!$array)	{ $tip=$text=_"error"; }
	else		{ $text.= ::CalcListLength($array,$self->{format}); }
	my $format= $self->{size} ? '<span size="'.$self->{size}.'">%s</span>' : '%s';
	$self->child->set_markup_with_format($format,$text);
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
	return _("Listed : "), $array,  ::__('%d song','%d songs',scalar@$array);
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
	return _('Selected : '), \@list,  ::__('%d song selected','%d songs selected',scalar@list);
}

### library functions
sub library_Set
{	my $self=shift;
	::Watch($self, SongsAdded	=>\&QueueUpdateSlow);
	::Watch($self, SongsRemoved	=>\&QueueUpdateSlow);
}
sub library_Update
{	my $tip= ::__('%d song in the library','%d songs in the library',scalar@$::Library);
	return _('Library : '), $::Library, $tip;
}


package EditListButtons;
use Glib qw(TRUE FALSE);
use Gtk2;

use base 'Gtk2::HBox';

sub new
{	my ($class,$opt)=@_;
	my $self=bless Gtk2::HBox->new, $class;
	$self->{group}=$opt->{group};
	$self->{brm}=	::NewIconButton('gtk-remove',	($opt->{small} ? '' : _"Remove"),sub {::GetSonglist($self)->RemoveSelected});
	$self->{bclear}=::NewIconButton('gtk-clear',	($opt->{small} ? '' : _"Clear"),sub {::GetSonglist($self)->Empty} );
	$self->{bup}=	::NewIconButton('gtk-go-up',		undef,	sub {::GetSonglist($self)->MoveUpDown(1)});
	$self->{bdown}=	::NewIconButton('gtk-go-down',		undef,	sub {::GetSonglist($self)->MoveUpDown(0)});
	$self->{btop}=	::NewIconButton('gtk-goto-top',		undef,	sub {::GetSonglist($self)->MoveUpDown(1,1)});
	$self->{bbot}=	::NewIconButton('gtk-goto-bottom',	undef,	sub {::GetSonglist($self)->MoveUpDown(0,1)});

	$self->{brm}->set_tooltip_text(_"Remove selected songs");
	$self->{bclear}->set_tooltip_text(_"Remove all songs");

	if (my $r=$opt->{relief}) { $self->{$_}->set_relief($r) for qw/brm bclear bup bdown btop bbot/; }
	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/btop bup bdown bbot brm bclear/;

	::Watch($self,'Selection_'.$self->{group}, \&SelectionChanged);
	::Watch($self,SongArray=> \&ListChanged);
	Glib::Idle->add(sub { $self->SelectionChanged; $self->ListChanged; 0; });

	return $self;
}

sub ListChanged
{	my ($self,$array)=@_;
	my $songlist=::GetSonglist($self);
	my $watchedarray= $songlist && $songlist->{array};
	return if !$watchedarray || ($array && $watchedarray!=$array);
	$self->{bclear}->set_sensitive(scalar @$watchedarray);
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
use Gtk2;

use base 'Gtk2::HBox';

sub new
{	my $class=$_[0];
	my $self=bless Gtk2::HBox->new, $class;

	my $action_store=Gtk2::ListStore->new(('Glib::String')x3);
	for my $action (sort {$::QActions{$a}[0] <=> $::QActions{$b}[0]} keys %::QActions)
	{	$action_store->set($action_store->append, 0,$::QActions{$action}[1], 1,$::QActions{$action}[2] ,2, $action );
	}

	$self->{queuecombo}=
	my $combo=Gtk2::ComboBox->new($action_store);

	my $renderer=Gtk2::CellRendererPixbuf->new;
	$combo->pack_start($renderer,FALSE);
	$combo->add_attribute($renderer, stock_id => 0);
	$renderer=Gtk2::CellRendererText->new;
	$combo->pack_start($renderer,TRUE);
	$combo->add_attribute($renderer, text => 1);

	$combo->signal_connect(changed => sub
		{	return if $self->{busy};
			my $iter=$_[0]->get_active_iter;
			my $action=$_[0]->get_model->get_value($iter,2);
			::EnqueueAction($action);
		});
	$self->{eventcombo}=Gtk2::EventBox->new;
	$self->{eventcombo}->add($combo);
	$self->{spin}=::NewPrefSpinButton('MaxAutoFill', 1,50, step=>1, page=>5, cb=>sub
		{	return if $self->{busy};
			::QAutoFill();
		});
	$self->{spin}->set_no_show_all(1);

	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/eventcombo spin/;

	::Watch($self, QueueAction => \&Update);
	$self->Update;
	return $self;
}

sub Update
{	my $self=$_[0];
	$self->{busy}=1;
	my $action=$::QueueAction;
	$self->{queuecombo}->set_active( $::QActions{$action}[0] );
	$self->{eventcombo}->set_tooltip_text( $::QActions{$action}[3] );
	my $m=($action eq 'autofill')? 'show' : 'hide';
	$self->{spin}->$m;
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
);
our %Markup_Empty=
(	Q => _"Queue empty",
	L => _"List empty",
	A => _"Playlist empty",
	B => _"No songs found",
);

sub new
{	my $opt=$_[1];
	my $package= $opt->{songtree} ? 'SongTree' : $opt->{songlist} ? 'SongList' : 'SongList';
	$package->new($opt);
}

sub CommonInit
{	my ($self,$opt)=@_;

	%$opt=( @DefaultOptions, %$opt );
	$self->{$_}=$opt->{$_} for qw/mode group follow sort hideif hidewidget shrinkonhide markup_empty markup_library_empty/,grep(m/^activate\d?$/, keys %$opt);
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
		$self->{follow}=1 if $type eq 'A' && !defined $self->{follow}; #default to follow current song on new playlists
	}
	elsif ($type eq 'L')
	{	if (defined $EditList) { $songarray=$EditList; $EditList=undef; } #special case for editing a list via ::WEditList
		unless (defined $songarray && $songarray ne '')	#create a new list if none specified
		{	$songarray='list000';
			$songarray++ while $::Options{SavedLists}{$songarray};
		}
	}
	elsif ($type eq 'Q') { $songarray=$::Queue; }

	if ($songarray && !ref $songarray)	#if not a ref, treat it as the name of a saved list
	{	::SaveList($songarray,[]) unless $::Options{SavedLists}{$songarray}; #create new list if doesn't exists
		$songarray=$::Options{SavedLists}{$songarray};
	}
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
	$opt->{'sort'}= $self->{'sort'};
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
{	my ($self,$filter)=@_;	::red($self->{type},' ',($self->{filter} || 'no'), ' ',$filter);::callstack();
	my $list;
	if ($self->{hideif} eq 'nofilter')
	{	$self->Hide($filter->is_empty);
		return if $filter->is_empty;
	}
	$self->{filter}=$filter;
	return if $self->{ignoreSetFilter};

	$list=$filter->filter;
	Songs::SortList( $list, $self->{sort} ) if exists $self->{sort};
	$self->{array}->Replace($list,filter=>$filter);
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
	my $songarray=$self->{array};
	$songarray->Remove($self->GetSelectedRows);
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
{	my ($self,$row,$button)=@_;
	my $songarray=$self->{array};
	my $ID=$songarray->[$row];
	my $activate=$self->{'activate'.$button} || $self->{activate};
	my $aftercmd;
	$aftercmd=$1 if $activate=~s/&(.*)$//;
	if	($activate eq 'remove_and_play')
	{	$songarray->Remove([$row]);
		::Select(song=>$ID,play=>1);
	}
	elsif	($activate eq 'queue')	{ ::Enqueue($ID); }
	elsif	($activate eq 'playlist')
	{	if ($self->{filter})
		{	::Select( filter=>$self->{filter}, song=>$ID, play=>1);
		}
		elsif ($self->{type} eq 'L')
		{	::Select( staticlist=>[@$songarray], position=>$row, play=>1);
		}
		else {$activate='play'}
	}
	elsif	($activate eq 'addplay' || $activate eq 'insertplay'){ ::DoActionForList($activate,[$ID]); }
	if	($activate eq 'play')
	{	if ($self->{type} eq 'A')	{ ::Select(position=>$row,play=>1); }
		else				{ ::Select(song=>$ID,play=>1); }
	}
	::run_command($self,$aftercmd) if $aftercmd;
}

# functions for SavedLists, ie type=L
sub MakeTitleLabel
{	my $self=shift;
	my $name=$self->{array}->GetName;
	my $label=Gtk2::Label->new($name);
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
{	my ($self,$window,$window_size,$offset)=@_;
	return unless $window;
	$offset||=0;
	$window_size||=$window;
	my $type=$self->{type};
	my $markup= scalar @$::Library ? undef : $self->{markup_library_empty};
	$markup ||= $self->{markup_empty};
	if ($markup)
	{	$markup=~s#(?:\\n|<br>)#\n#g;
		my ($width,$height)=$window_size->get_size;
		my $layout= Gtk2::Pango::Layout->new( $self->create_pango_context );
		$width-=2*5;
		$layout->set_width( Gtk2::Pango->scale * $width );
		$layout->set_wrap('word-char');
		$layout->set_alignment('center');
		my $style= $self->style;
		my $font= $style->font_desc;
		$font->set_size( 2 * $font->get_size );
		$layout->set_font_description($font);
		$layout->set_markup( "\n".$markup );
		my $gc=$style->text_aa_gc($self->state);
		$window->draw_layout($gc, $offset+5,5, $layout);
	}
}

package SongList;
use Glib qw(TRUE FALSE);
use Gtk2;
use Gtk2::Pango; #for PANGO_WEIGHT_BOLD, PANGO_WEIGHT_NORMAL

use base 'Gtk2::ScrolledWindow';

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
	{	value => sub {defined $::SongID && $_[2]==$::SongID ? 'italic' : 'normal'},
		attrib => 'style',	type => 'Gtk2::Pango::Style',
	},
	boldrow =>
	{	value => sub {defined $::SongID && $_[2]==$::SongID ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL},
		attrib => 'weight',	type => 'Glib::Uint',
	},

	right_aligned_folder=>
	{	menu	=> _"Folder (right-aligned)", title => _"Folder",
		value	=> sub { Songs::Display($_[2],'path'); },
		attrib	=> 'text', type => 'Glib::String', depend => 'path',
		sort	=> 'path',	width => 200,
		init	=> { ellipsize=>'start', },
	},
	titleaa =>
	{	menu => _('Title - Artist - Album'), title => _('Song'),
		value => sub { ::ReplaceFieldsAndEsc($_[2],"<b>%t</b>\n<small><i>%a</i> - %l</small>"); },
		attrib => 'markup', type => 'Glib::String', depend => 'title artist album',
		sort => 'title:i',	noncomp => 'boldrow',		width => 200,
	},
	playandqueue =>
	{	menu => _('Playing & Queue'),		title => '',	width => 20,
		value => sub { ::Get_PPSQ_Icon($_[2]); },
		class => 'Gtk2::CellRendererPixbuf',	attrib => 'stock-id',
		type => 'Glib::String',			noncomp => 'boldrow italicrow',
		event => 'Playing Queue CurSong',
	},
	icolabel =>
	{	menu => _("Labels' Icons"),	title => '',		value => sub { $_[2] },
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
		value	=> sub { Stars::get_pixbuf( Songs::Get($_[2],'rating') ); }, #FIXME use Songs::Picture to get pixbuf
		class	=> 'Gtk2::CellRendererPixbuf',	attrib	=> 'pixbuf',
		type	=> 'Gtk2::Gdk::Pixbuf',		noncomp	=> 'boldrow italicrow',
		depend	=> 'rating',			sort	=> 'rating',
	},
  );
  %{$SLC_Prop{albumpicinfo}}=%{$SLC_Prop{albumpic}};
  $SLC_Prop{albumpicinfo}{title}=_"Album picture & info";
  $SLC_Prop{albumpicinfo}{init}={aa => 'album', markup => "<b>%a</b>%Y\n<small>%s <small>%l</small></small>"};
}

our @ColumnMenu=
(	{ label => _"_Sort by",		submenu => sub { Browser::make_sort_menu($_[0]{self}) }, },
	{ label => _"_Insert column",	submenu => sub
		{	my %names=map {my $l=$SLC_Prop{$_}{menu} || $SLC_Prop{$_}{title}; defined $l ? ($_,$l) : ()} keys %SLC_Prop;
			delete $names{$_->{colid}} for $_[0]{self}->child->get_columns;
			return \%names;
		},	submenu_reverse =>1,
	  code	=> sub { $_[0]{self}->ToggleColumn($_[1],$_[0]{pos}); },	stockicon => 'gtk-add'
	},
	{ label => sub { _('_Remove this column').' ('. ($SLC_Prop{$_[0]{pos}}{menu} || $SLC_Prop{$_[0]{pos}}{title}).')' },
	  code	=> sub { $_[0]{self}->ToggleColumn($_[0]{pos},$_[0]{pos}); },	stockicon => 'gtk-remove'
	},
	{ label => _"Follow playing song",	code => sub { $_[0]{self}->FollowSong if $_[0]{self}{follow}^=1; },
	  check => sub { $_[0]{self}{follow} }
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

	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');
	$self->set_policy('automatic','automatic');
	::set_biscrolling($self);

	#use default options for this songlist type
	my $name= 'songlist_'.$opt->{name}; $name=~s/\d+$//;
	my $default= $::Options{"DefaultOptions_$name"} || {};

	%$opt=( @DefaultOptions, %$default, %$opt );
	$self->CommonInit($opt);
	$self->{$_}=$opt->{$_} for qw/songypad playrow/;

	my $store=SongStore->new; $store->{array}=$self->{array}; $store->{size}=@{$self->{array}};
	my $tv=Gtk2::TreeView->new($store);
	$self->add($tv);
	$self->{store}=$store;

	::set_drag($tv,
	 source	=>[::DRAG_ID,sub { my $tv=$_[0]; return ::DRAG_ID,$tv->parent->GetSelectedIDs; }],
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
			if (Gtk2::Gdk->keyval_name( $event->keyval ) eq 'Delete')
			{	$tv->parent->RemoveSelected;
				return 1;
			}
			return 0;
		});
	MultiTreeView::init($tv,__PACKAGE__);
	$tv->signal_connect(cursor_changed	=> \&cursor_changed_cb);
	$tv->signal_connect(row_activated	=> \&row_activated_cb);
	#$tv->get_selection->signal_connect(changed => \&sel_changed_cb);
	$tv->get_selection->signal_connect(changed => sub { ::IdleDo('1_Changed'.$_[0],10,\&sel_changed_cb,$_[0]); }); #delay it, because it can be called A LOT when, for example, removing 10000 selected rows
	$tv->get_selection->set_mode('multiple');

	if (my $tip=$opt->{rowtip} and *Gtk2::Widget::set_has_tooltip{CODE})  # since gtk+ 2.12, Gtk2 1.160
	{	$tv->set_has_tooltip(1);
		$tip= "<b><big>%t</big></b>\\nby <b>%a</b>\\nfrom <b>%l</b>" if $tip eq '1';
		$self->{rowtip}= $tip;
		$tv->signal_connect(query_tooltip=> \&query_tooltip_cb);
	}

	# used to draw text when treeview empty
	$tv->signal_connect(expose_event=> \&expose_cb);
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
	my $tv=$self->child;
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
	my $renderer=	( $prop->{class} || 'Gtk2::CellRendererText' )->new;
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
	my $column = Gtk2::TreeViewColumn->new_with_attributes(@attributes);

	#$renderer->set_fixed_height_from_font(1);
	$column->{colid}=$colid;
	$column->set_sizing('fixed');
	$column->set_resizable(TRUE);
	$column->set_min_width(0);
	$column->set_fixed_width( $self->{colwidth}{$colid} || $prop->{width} || 100 );
	$column->set_clickable(TRUE);
	$column->set_reorderable(TRUE);

	$column->signal_connect(clicked => sub
		{	my $self=::find_ancestor($_[0]->get_widget,__PACKAGE__);
			my $s=$_[1];
			$s='-'.$s if $self->{sort} eq $s;
			$self->Sort($s);
		},$prop->{sort}) if defined $prop->{sort};
	my $tv=$self->child;
	if (defined $pos)	{ $tv->insert_column($column, $pos); }
	else			{ $tv->append_column($column); }
	#################################### connect col selection menu to right-click on column
	my $label=Gtk2::Label->new($prop->{title});
	$column->set_widget($label);
	$label->show;
	my $button_press_sub=sub
		{ my $event=$_[1];
		  return 0 unless $event->button == 3;
		  my $self=::find_ancestor($_[0],__PACKAGE__);
		  $self->SelectColumns($_[2]);	# $_[2]=$colid
		  1;
		};
	if (my $event=$prop->{event})
	{	::Watch($label,$_,sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->queue_draw if $self; }) for split / /,$event; # could queue_draw only column
	}
	my $button=$label->get_ancestor('Gtk2::Button'); #column button
	$button->signal_connect(button_press_event => $button_press_sub,$colid) if $button;
	return $column;
}

sub UpdateSortIndicator
{	my $self=$_[0];
	my $tv=$self->child;
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
	::PopupContextMenu( \@ColumnMenu, {self=>$self, 'pos' => $pos } );
}

sub ToggleColumn
{	my ($self,$colid,$colpos)=@_;
	my $tv=$self->child;
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

sub expose_cb
{	my ($tv,$event)=@_;
	my $self=$tv->parent;
	unless ($tv->get_model->iter_n_children && $event->window != $tv->window)
	{	$tv->get_bin_window->clear;
		# draw empty text when no songs
		$self->DrawEmpty($tv->get_bin_window,$tv->window, $tv->get_hadjustment->value);
	}
	return 0;
}

sub query_tooltip_cb
{	my ($tv, $x, $y, $keyb, $tooltip)=@_;
	return 0 if $keyb;
	my ($path, $column)=$tv->get_path_at_pos($x,$y);
	return 0 unless $path;
	my ($row)=$path->get_indices;
	my $self=::find_ancestor($tv,__PACKAGE__);
	my $ID=$self->{array}[$row];
	my $markup= ::ReplaceFieldsAndEsc($ID,$self->{rowtip});
	$tooltip->set_markup($markup);
	#$tv->set_tooltip_row($tooltip,$path); # => no tip displayed ! ?
	1;
}

sub PopupContextMenu
{	my ($self,$tv,$event)=@_;
	return unless @{$self->{array}}; #no context menu for empty lists
	my @IDs=$self->GetSelectedIDs;
	my %args=(self => $self, mode => $self->{type}, IDs => \@IDs, listIDs => $self->{array});
	::PopupContextMenu(\@::SongCMenu,\%args );
}

sub GetSelectedRows
{	my $self=shift;
	return [map $_->to_string, $self->child->get_selection->get_selected_rows];
}

sub drag_received_cb
{	my ($tv,$type,$dest,@IDs)=@_;
	$tv->signal_stop_emission_by_name('drag_data_received'); #override the default 'drag_data_received' handler on GtkTreeView
	my $self=$tv->parent;
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
	::drag_checkscrolling($tv,$context,$y);
	return if $x<0 || $y<0;
	my ($path,$pos)=$tv->get_dest_row_at_pos($x,$y);
	if ($path)
	{	$pos= ($pos=~m/after$/)? 'after' : 'before';
	}
	else	#cursor is in an empty (no rows) zone #FIXME also happens when above or below treeview
	{	my $n=$tv->get_model->iter_n_children;
		$path=Gtk2::TreePath->new_from_indices($n-1) if $n; #at the end
		$pos='after';
	}
	$context->{dest}=[$tv,$path,$pos];
	$tv->set_drag_dest_row($path,$pos);
	$context->status(($tv->{drag_is_source} ? 'move' : 'copy'),$time);
	return 1;
}

sub enqueue_current
{	my $self=shift;
	my $tv=$self->child;
	my ($path)= $tv->get_cursor;
	return unless $path;
	my $ID=$self->{array}[ $path->to_string ];
	::Enqueue($ID);
}

sub sel_changed_cb
{	my $treesel=$_[0];
	my $tv=$treesel->get_tree_view;
	::HasChanged('Selection_'.$tv->parent->{group});
}
sub cursor_changed_cb
{	my $tv=$_[0];
	my ($path)= $tv->get_cursor;
	return unless $path;
	my $self=$tv->parent;
	my $ID=$self->{array}[ $path->to_string ];
	::HasChangedSelID($self->{group},$ID);
}

sub row_activated_cb
{	my ($tv,$path,$column)=@_;
	my $self=$tv->parent;
	$self->Activate($path->to_string,1);
}

sub ResetModel
{	my $self=$_[0];
	my $tv=$self->child;
	$tv->set_model(undef);
	$self->{store}{size}=@{$self->{array}};
	$tv->set_model($self->{store});
	$self->UpdateSortIndicator;
	$self->Scroll_to_TopEnd();
	$self->CurSongChanged;
}

sub Scroll_to_TopEnd
{	my ($self,$end)=@_;
	my $songarray=$self->{array};
	return unless @$songarray;
	my $row= $end ? $#$songarray : 0;
	$row=Gtk2::TreePath->new($row);
	$self->child->scroll_to_cell($row,undef,::TRUE,0,0);
}

sub CurSongChanged
{	my $self=$_[0];
	$self->queue_draw if defined $self->{playrow};
	$self->FollowSong if $self->{follow};
}

sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	my $usedfields= $self->{cols_to_watch}||= do
	 {	my $tv=$self->child;
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
	$self->child->queue_draw;
}

sub SongArray_changed_cb
{	my ($self,$array,$action,@extra)=@_;
	#if ($self->{mode} eq 'playlist' && $array==$::ListPlay)
	#{	$self->{array}->Mirror($array,$action,@extra);
	#}
	return unless $self->{array}==$array;
	warn "SongArray_changed $action,@extra\n";
	my $tv=$self->child;
	my $store=$tv->get_model;
	my $treesel=$tv->get_selection;
	my @selected=map $_->to_string, $treesel->get_selected_rows;
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
		$self->queue_draw;
		#$store->rowremove($rows);
		#$store->rowinsert($destrow,scalar @$rows);
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
	my $tv=$self->child;
	#$tv->get_selection->unselect_all;
	my $songarray=$self->{array};
	return unless defined $::SongID;
	my $rowplaying;
	if ($self->{mode} eq 'playlist') { $rowplaying=$::Position; } #$::Position may be undef even if song is in list (random mode), in that case fallback to the usual case below
	$rowplaying= ::first { $songarray->[$_]==$::SongID } 0..$#$songarray unless defined $rowplaying && $rowplaying>=0;
	if (defined $rowplaying)
	{	my $path=Gtk2::TreePath->new($rowplaying);
		my $visible;
		my $win = $tv->get_bin_window;
		if ($win)	#check if row is visible -> no need to scroll_to_cell
		{	#maybe should use gtk_tree_view_get_visible_range (requires gtk 2.8)
			my $first=$tv->get_path_at_pos(0,0);
			my $last=$tv->get_path_at_pos(0,($win->get_size)[1] - 1);
			if ((!$first || $first->to_string < $rowplaying) && (!$last || $rowplaying < $last->to_string))
			{
				$visible=1;
			}
		}
		$tv->scroll_to_cell($path,undef,TRUE,.5,.5) unless $visible;
		$tv->set_cursor($path);
	}
	elsif (defined $::SongID)	#Set the song ID even if the song isn't in the list
	{ ::HasChangedSelID($self->{group},$::SongID); }
}

sub SetSelection
{	my ($self,$select)=@_;
	my $treesel=$self->child->get_selection;
	$treesel->unselect_all;
	$treesel->select_path( Gtk2::TreePath->new($_) ) for @$select;
}

#sub UpdateID	#DELME ? update individual rows or just redraw everything ?
#{	my $self=$_[0];
#	my $array=$self->{array};
#	my $store=$self->child->get_model;
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
use Gtk2;

my (%Columns,@Value,@Type);

use Glib::Object::Subclass
	Glib::Object::,
	interfaces => [Gtk2::TreeModel::],
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

sub INIT_INSTANCE {
	my $self = $_[0];
	# int to check whether an iter belongs to our model
	$self->{stamp} = $self+0;#sprintf '%d', rand (1<<31);
}
#sub FINALIZE_INSTANCE
#{	#my $self = $_[0];
#	# free all records and free all memory used by the list
#}
sub GET_FLAGS { [qw/list-only iters-persist/] }
sub GET_N_COLUMNS { $#Value }
sub GET_COLUMN_TYPE { $Type[ $_[1] ]; }
sub GET_ITER
{	my $self=$_[0]; my $path=$_[1];
	die "no path" unless $path;

	# we do not allow children
	# depth 1 = top level; a list only has top level nodes and no children
#	my $depth   = $path->get_depth;
#	die "depth != 1" unless $depth == 1;

	my $n=$path->get_indices;	#return only one value because it's a list
	#warn "GET_ITER $n\n";
	return undef if $n >= $self->{size} || $n < 0;

	#my $ID = $self->{array}[$n];
	#die "no ID" unless defined $ID;
	#return iter :
	return [ $self->{stamp}, $n, $self->{array} , undef ];
}

sub GET_PATH
{	my ($self, $iter) = @_; #warn "GET_PATH\n";
	die "no iter" unless $iter;

	my $path = Gtk2::TreePath->new;
	$path->append_index ($iter->[1]);
	return $path;
}

sub GET_VALUE
{	my $row=$_[1][1];	#warn "GET_VALUE\n";
	$Value[$_[2]]( $_[0], $row, $_[1][2][$row]  ); #args : self, row, ID
}

sub ITER_NEXT
{	#my ($self, $iter) = @_;
	my $self=$_[0];
#	return undef unless $_[1];
	my $n=$_[1]->[1]; #$iter->[1]
	#warn "GET_NEXT $n\n";
	return undef unless ++$n < $self->{size};
	return [ $self->{stamp}, $n, $self->{array}, undef ];
}

sub ITER_CHILDREN
{	my ($self, $parent) = @_; #warn "GET_CHILDREN\n";
	# this is a list, nodes have no children
	return undef if $parent;
	# parent == NULL is a special case; we need to return the first top-level row
	# No rows => no first row
	return undef unless $self->{size};
	# Set iter to first item in list
	return [ $self->{stamp}, 0, $self->{array}, undef ];
}
sub ITER_HAS_CHILD { FALSE }
sub ITER_N_CHILDREN
{	my ($self, $iter) = @_; #warn "ITER_N_CHILDREN\n";
	# special case: if iter == NULL, return number of top-level rows
	return ( $iter? 0 : $self->{size} );
}
sub ITER_NTH_CHILD
{	#my ($self, $parent, $n) = @_; #warn "ITER_NTH_CHILD\n";
	# a list has only top-level rows
	return undef if $_[1]; #$parent;
	my $self=$_[0]; my $n=$_[2];
	# special case: if parent == NULL, set iter to n-th top-level row
	return undef if $n >= $self->{size};

	return [ $self->{stamp}, $n, $self->{array}, undef ];
}
sub ITER_PARENT { FALSE }

sub search_equal_func
{	#my ($self,$col,$string,$iter)=@_;
	my $iter= $_[3]->to_arrayref($_[0]{stamp});
	my $ID= $iter->[2][ $iter->[1] ];
	my $string=uc $_[2];
	#my $r; for (qw/title album artist/) { $r=index uc(Songs::Display($ID,$_)), $string; last if $r==0 } return $r;
	index uc(Songs::Display($ID,'title')), $string;
}

sub rowremove
{	my ($self,$rows)=@_;
	for my $row (reverse @$rows)
	{	$self->row_deleted( Gtk2::TreePath->new($row) );
		$self->{size}--;
	}
}
sub rowinsert
{	my ($self,$row,$number)=@_;
	for (1..$number)
	{	$self->{size}++;
		$self->row_inserted( Gtk2::TreePath->new($row), $self->get_iter_from_string($row) );
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
	my $self=::find_ancestor($tv, $tv->{selfpkg} );
	my $but=$event->button;
	my $sel=$tv->get_selection;
	if ($but==2 && $event->type eq '2button-press') { $self->enqueue_current; return 1; }
	my $ctrl_shift=  $event->get_state * ['shift-mask', 'control-mask'];
	if ($but==1) # do not clear multi-row selection if button press on a selected row (to allow dragging selected rows)
	{{	 last if $ctrl_shift; #don't interfere with default if control or shift is pressed
		 last unless $sel->count_selected_rows  > 1;
		 my $path=$tv->get_path_at_pos($event->get_coords);
		 last unless $path && $sel->path_is_selected($path);
		 $tv->{pressed}=1;
		 return 1;
	}}
	if ($but==3)
	{	my $path=$tv->get_path_at_pos($event->get_coords);
		if ($path && !$sel->path_is_selected($path))
		{	$sel->unselect_all unless $ctrl_shift;
			#$sel->select_path($path);
			$tv->set_cursor($path);
		}
		$self->PopupContextMenu($tv,$event);
		return 1;
	}
	return 0; #let the event propagate
}

sub button_release_cb #clear selection and select current row only if the press event was on a selected row and there was no dragging
{	my ($tv,$event)=@_;
	return 0 unless $event->button==1 && $tv->{pressed};
	$tv->{pressed}=undef;
	my $path=$tv->get_path_at_pos($event->get_coords);
	return 0 unless $path;
	my $sel=$tv->get_selection;
	$sel->unselect_all;
	$sel->select_path($path);
	return 1;
}

package FilterPane;
use Gtk2;
use base 'Gtk2::VBox';

use constant { TRUE  => 1, FALSE => 0, };

our %Pages=
(	filter	=> [SavedTree		=> 'F',			'i', _"Filter"	],
	list	=> [SavedTree		=> 'L',			'i', _"List"	],
	savedtree=>[SavedTree		=> 'FL',		'i', _"Saved"	],
	folder	=> [FolderList		=> 'path',		'n', _"Folder"	],
	filesys	=> [Filesystem		=> '',			'',_"Filesystem"],
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
our @MenuPageOptions;
my @MenuSubGroup=
(	{ label => sub {_("Set subgroup").' '.$_[0]{depth}},	submenu => sub { return {0 => _"None",map {$_=>Songs::FieldName($_)} Songs::FilterListFields()}; },
		submenu_reverse => 1,	code => sub { $_[0]{self}->SetField($_[1],$_[0]{depth}) },	check => sub { $_[0]{self}{field}[$_[0]{depth}] ||0 },
	},
	{ label => sub {_("Options for subgroup").' '.$_[0]{depth}},	submenu => \@MenuPageOptions,
	  test  => sub { $_[0]{depth} <= $_[0]{self}{depth} },
	},
);

@MenuPageOptions=
(	{ label => _"show pictures",	code => sub { my $self=$_[0]{self}; $self->{lpicsize}[$_[0]{depth}]=$_[1]; $self->SetOption; },	mode => 'LS',
	  submenu => \@picsize_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{lpicsize}[$_[0]{depth}]},
		test => sub { Songs::FilterListProp($_[0]{subfield},'picture'); }, },
	{ label => _"show info",	code => sub { my $self=$_[0]{self}; $self->{lmarkup}[$_[0]{depth}]^=1; $self->SetOption; },
	  check => sub { $_[0]{self}{lmarkup}[$_[0]{depth}]}, istrue => 'aa', mode => 'LS', },
	{ label => _"show the 'All' row",	code => sub { my $self=$_[0]{self}; $self->{noall}^=1; $self->SetOption; },
	  check => sub { !$_[0]{self}{noall} }, mode => 'LS', },
	{ label => _"picture size",	code => sub { $_[0]{self}->SetOption(mpicsize=>$_[1]);  },
	  mode => 'M',
	  submenu => \@mpicsize_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{mpicsize}}, istrue => 'aa' },

	{ label => _"font size depends on",	code => sub { $_[0]{self}->SetOption(cloud_stat=>$_[1]); },
	  mode => 'C',
	  submenu => \@cloudstats_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{cloud_stat}}, },
	{ label => _"minimum font size", code => sub { $_[0]{self}->SetOption(cloud_min=>$_[1]); },
	  mode => 'C',
	  submenu => sub { [2..::min(20,$_[0]{self}{cloud_max}-1)] },  check => sub {$_[0]{self}{cloud_min}}, },
	{ label => _"maximum font size", code => sub { $_[0]{self}->SetOption(cloud_max=>$_[1]); },
	  mode => 'C',
	  submenu => sub { [::max(10,$_[0]{self}{cloud_min}+1)..40] },  check => sub {$_[0]{self}{cloud_max}}, },

	{ label => _"sort by",		code => sub { my $self=$_[0]{self}; $self->{'sort'}[$_[0]{depth}]=$_[1]; $self->SetOption; },
	  check => sub {$_[0]{self}{sort}[$_[0]{depth}]}, submenu => \%sort_menu, submenu_reverse => 1 },
	{ label => _"group by",
	  code	=> sub { my $self=$_[0]{self}; my $d=$_[0]{depth}; $self->{type}[$d]=$self->{field}[$d].'.'.$_[1]; $self->Fill('rehash'); },
	  check => sub { my $n=$_[0]{self}{type}[$_[0]{depth}]; $n=~s#^[^.]+\.##; $n },
	  submenu=>sub { Songs::LookupCode( $_[0]{subfield}, 'subtypes_menu' ); }, submenu_reverse => 1,
	  #test => sub { $FilterList::Field{ $_[0]{self}{field}[$_[0]{depth}] }{types}; },
	},
	{ repeat => sub { map [\@MenuSubGroup, depth=>$_, mode => 'S', subfield => $_[0]{self}{field}[$_], ], 1..$_[0]{self}{depth}+1; },	mode => 'L',
	},
	{ label => _"cloud mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'cloud' ? 'list' : 'cloud'),1); },
	  check => sub {$_[0]{mode} eq 'C'},	notmode => 'S', },
	{ label => _"mosaic mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'mosaic' ? 'list' : 'mosaic'),1);},
	  check => sub {$_[0]{mode} eq 'M'}, istrue => 'aa',	notmode => 'S', },
);

our @cMenu=
(	{ label=> _"Play",	code => sub { ::Select(filter=>$_[0]{filter},song=>'first',play=>1); },
		isdefined => 'filter',	stockicon => 'gtk-media-play',	id => 'play'
	},
	{ label=> _"Append to playlist",	code => sub { ::DoActionForList('addplay',$_[0]{filter}->filter); },
		isdefined => 'filter',	stockicon => 'gtk-add',	id => 'addplay',
	},
	{ label=> _"Enqueue",	code => sub { ::EnqueueFilter($_[0]{filter}); },
		isdefined => 'filter',	stockicon => 'gmb-queue',	id => 'enqueue',
	},
	{ label=> _"Set as primary filter",
		code => sub {my $fp=$_[0]{filterpane}; ::SetFilter( $_[0]{self}, $_[0]{filter}, 1, $fp->{group} ); },
		test => sub {my $fp=$_[0]{filterpane}; $fp->{nb}>1 && $_[0]{filter};}
	},
	#songs submenu :
	{	label	=> sub { my $IDs=$_[0]{filter}->filter; ::__("%d Song","%d Songs",scalar @$IDs); },
		submenu => sub { ::BuildMenu(\@::SongCMenu, { mode => 'F', IDs=>$_[0]{filter}->filter }); },
		isdefined => 'filter',
	},
	{ label=> _"Rename folder", code => sub { ::AskRenameFolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Open folder", code => sub { ::openfolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist', },
	#{ label=> _"move folder", code => sub { ::MoveFolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Scan for new songs", code => sub { ::IdleScan( map(::filename_from_unicode($_), @{$_[0]{utf8pathlist}}) ); },
		notempty => 'utf8pathlist' },
	{ label=> _"Check for updated/removed songs", code => sub { ::IdleCheck(  @{ $_[0]{filter}->filter } ); },
		isdefined => 'filter', stockicon => 'gtk-refresh', istrue => 'utf8pathlist' }, #doesn't really need utf8pathlist, but makes less sense for non-folder pages
	{ label=> _"Set Picture",	stockicon => 'gmb-picture',
		code => sub { my $gid=$_[0]{gidlist}[0]; ::ChooseAAPicture(undef,$_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { Songs::FilterListProp($_[0]{field},'picture') && $_[0]{gidlist}[0]>0; },
	},
	{ label=> _"Set icon",		stockicon => 'gmb-picture',
		code => sub { my $gid=$_[0]{gidlist}[0]; Songs::ChooseIcon($_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { Songs::FilterListProp($_[0]{field},'icon') && $_[0]{gidlist}[0]>0; },
	},
	{ label=> _"Remove label",	stockicon => 'gtk-remove',
		code => sub { my $gid=$_[0]{gidlist}[0]; ::RemoveLabel($_[0]{field},$gid); },
		onlyone=> 'gidlist',	test => sub { $_[0]{field} eq 'label' },	#FIXME ? label specific
	},
#	{ separator=>1 },
	{ label => _"Options", submenu => \@MenuPageOptions, stock => 'gtk-preferences', isdefined => 'field' },
	{ label => _"Show buttons",	code => sub { my $fp=$_[0]{filterpane}; $fp->{hidebb}^=1; if ($fp->{hidebb}) {$fp->{bottom_buttons}->hide} else {$fp->{bottom_buttons}->show} },
	  check => sub {!$_[0]{filterpane}{hidebb};} },
	{ label => _"Show tabs",	code => sub { my $fp=$_[0]{filterpane}; $fp->{hidetabs}^=1; $fp->{notebook}->set_show_tabs( !$fp->{hidetabs} ); },
	  check => sub {!$_[0]{filterpane}{hidetabs};} },
);

our @DefaultOptions=
(	pages	=> 'savedtree|artist|album|genre|date|label|folder|added|lastplay',
	nb	=> 1,	# filter level
	min	=> 1,	# filter out entries with less than $min songs
	hidebb	=> 0,	# hide button box
);

sub new
{	my ($class,$opt)=@_;
	my $self = bless Gtk2::VBox->new(FALSE, 6), $class;
	$self->{SaveOptions}=\&SaveOptions;
	%$opt=( @DefaultOptions, %$opt );
	my @pids=split /\|/, $opt->{pages};
	$self->{$_}=$opt->{$_} for qw/nb group min hidetabs/;
	$self->{main_opt}{$_}=$opt->{$_} for qw/group no_typeahead searchbox activate/; #options passed to children
	my $nb=$self->{nb};
	my $group=$self->{group};

	my $spin=Gtk2::SpinButton->new( Gtk2::Adjustment->new($self->{min}, 1, 9999, 1, 10, 0) ,10,0  );
	$spin->signal_connect( value_changed => sub { $self->update_children($_[0]->get_value); } );
	my $ResetB=::NewIconButton('gtk-clear',undef,sub { ::SetFilter($_[0],undef,$nb,$group); });
	$ResetB->set_sensitive(0);
	my $InterB=Gtk2::ToggleButton->new;
	my $InterBL=Gtk2::Label->new;
	$InterBL->set_markup('<b>&amp;</b>');  #bold '&'
	$InterB->add($InterBL);
	my $InvertB=Gtk2::ToggleButton->new;
	my $optB=Gtk2::Button->new;
	$InvertB->add(Gtk2::Image->new_from_stock('gmb-invert','menu'));
	$optB->add(Gtk2::Image->new_from_stock('gtk-preferences','menu'));
	$InvertB->signal_connect( toggled => sub {$self->{invert}=$_[0]->get_active;} );
	$InterB->signal_connect(  toggled => sub {$self->{inter} =$_[0]->get_active;} );
	$optB->signal_connect( button_press_event => \&PopupOpt );
	$optB->set_relief('none');
	my $hbox = Gtk2::HBox->new (FALSE, 6);
	$hbox->pack_start($_, FALSE, FALSE, 0) for $spin, $ResetB, $InvertB, $InterB, $optB;
	$ResetB ->set_tooltip_text(	(	$nb==1? _"reset primary filter"  :
						$nb==2?	_"reset secondary filter":
							::__x(_"reset filter {nb}",nb =>$nb)
					) );
	$InterB ->set_tooltip_text(_"toggle Intersection mode");
	$InvertB->set_tooltip_text(_"toggle Invert mode");
	$spin   ->set_tooltip_text(_"only show entries with at least n songs"); #FIXME
	$optB   ->set_tooltip_text(_"options");

	my $notebook = Gtk2::Notebook->new;
	$notebook->set_scrollable(TRUE);
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
		my $self=::find_ancestor($_[0],__PACKAGE__);
		my $pid= $self->{page}= $p->{pid};
		my $mask=	$Pages{$pid} ? 				$Pages{$pid}[2] :
				Songs::FilterListProp($pid,'multi') ?	'oni' : 'on';
		if	($mask=~m/o/)	{$optB->show}
		else			{$optB->hide}
		if	($mask=~m/n/)	{$spin->show}
		else			{$spin->hide}
		if	($mask=~m/i/)	{$InterB->show}
		else			{$InterB->hide}
	 });

	$self->add($notebook);
	$notebook->set_current_page( $setpage||0 );

	$self->{hidebb}=$opt->{hidebb};
	$hbox->hide if $self->{hidebb};
	$self->{resetbutton}=$ResetB;
	::Watch($self, SongsChanged=> \&SongsChanged_cb);
	::Watch($self, SongsAdded  => \&SongsAdded_cb);
	::Watch($self, SongsRemoved=> \&SongsRemoved_cb);
	$self->signal_connect(destroy => \&cleanup);
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
		pages	=> (join '|', map $_->{pid}, $self->{notebook}->get_children),
	);
	for my $page (grep $_->isa('FilterList'), $self->{notebook}->get_children)
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
	if ($package eq 'FilterList' || $package eq 'FolderList')
	{	$page->{Depend_on_field}=$col;
	}
	my $notebook=$self->{notebook};
	my $n=$notebook->append_page( $page, Gtk2::Label->new($label) );
	$n=$notebook->get_n_pages-1; # $notebook->append_page doesn't returns the page number before Gtk2-Perl 1.080
	$notebook->set_tab_reorderable($page,TRUE);
	$page->show_all;
	return $n;
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
	my $self=::find_ancestor($nb,__PACKAGE__);
	my $menu=Gtk2::Menu->new;
	my $cb=sub { $nb->set_current_page($_[1]); };
	my %pages;
	$pages{$_}= $Pages{$_}[3] for keys %Pages;
	$pages{$_}= Songs::FieldName($_) for Songs::FilterListFields;
	for my $page ($nb->get_children)
	{	my $pid=$page->{pid};
		my $name=delete $pages{$pid};
		my $item=Gtk2::MenuItem->new_with_label($name);
		$item->signal_connect(activate=>$cb,$nb->page_num($page));
		$menu->append($item);
	}
	$menu->append(Gtk2::SeparatorMenuItem->new);

	if (keys %pages)
	{	my $new=Gtk2::ImageMenuItem->new(_"add tab");
		$new->set_image( Gtk2::Image->new_from_stock('gtk-add','menu') );
		my $submenu=Gtk2::Menu->new;
		for my $pid (sort {$pages{$a} cmp $pages{$b}} keys %pages)
		{	my $item=Gtk2::MenuItem->new_with_label($pages{$pid});
			$item->signal_connect(activate=> sub { my $n=$self->AppendPage($pid); $self->{notebook}->set_current_page($n) });
			$submenu->append($item);
		}
		$menu->append($new);
		$new->set_submenu($submenu);
	}
	if ($nb->get_n_pages>1)
	{	my $item=Gtk2::ImageMenuItem->new(_"remove this tab");
		$item->set_image( Gtk2::Image->new_from_stock('gtk-remove','menu') );
		$item->signal_connect(activate=> \&RemovePage_cb,$self);
		$menu->append($item);
	}
	#::PopupContextMenu(\@MenuTabbedL, { self=>$self, list=>$listname, pagenb=>$pagenb, page=>$page, pagetype=>$page->{tabbed_page_type} } );
	$menu->show_all;
	$menu->popup(undef, undef, undef, undef, $event->button, $event->time);
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
			::IdleDo('9_FP'.$self,1000,\&refresh_current_page,$self) if $page->mapped;
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
	delete $::ToDo{'9_FPfull'.$self};
	my $force=delete $self->{needupdate};

	my $group=$self->{group};
	my $mynb=$self->{nb};
	return if $nb && $nb> $mynb;
	warn "Filtering list for FilterPane$mynb\n" if $::debug;
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
	my ($current)=grep $_->mapped, $self->get_field_pages;
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

sub PopupContextMenu
{	my ($page,$event,$hash,$menu)=@_;
	my $self=::find_ancestor($page,__PACKAGE__);
	$hash->{filterpane}=$self;
	$menu||=\@cMenu;
	::PopupContextMenu($menu, $hash);
}

sub PopupOpt	#Only for FilterList #FIXME should be moved in FilterList::, and/or use a common function with FilterList::PopupContextMenu
{	my ($but,$event)=@_;
	my $self=::find_ancestor($but,__PACKAGE__);
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
use Gtk2;
use base 'Gtk2::VBox';
use constant { GID_ALL => 2**32-1, GID_TYPE => 'Glib::ULong' };

our %defaults=
(	mode	=> 'list',
	type	=> '',
	lmarkup	=> 0,
	lpicsize=> 0,
	'sort'	=> 'default',
	depth	=> 0,
	noall	=> 0,
	mpicsize=> 64,
	cloud_min=> 5,
	cloud_max=> 20,
	cloud_stat=> 'count',
);

sub new
{	my ($class,$field,$opt)=@_;
	my $self = bless Gtk2::VBox->new, $class;
	$self->{no_typeahead}=$opt->{no_typeahead};
	$self->{rules_hint}=$opt->{rules_hint};

	$opt= { %defaults, %$opt };
	$self->{$_} = $opt->{$_} for qw/mode noall depth mpicsize cloud_min cloud_max cloud_stat/;
	$self->{$_} = [ split /\|/, $opt->{$_} ] for qw/sort type lmarkup lpicsize/;

	$self->{type}[0] ||= $field.'.'.(Songs::FilterListProp($field,'type')||''); $self->{type}[0]=~s/\.$//;	#FIXME
	::Watch($self, Picture_artist => \&AAPicture_Changed);	#FIXME PHASE1
	::Watch($self, Picture_album => \&AAPicture_Changed);	#FIXME PHASE1

	for my $d (0..$self->{depth})
	{	my ($field)= $self->{type}[$d] =~ m#^([^.]+)#;
		$self->{field}[$d]=$field;
		$self->{icons}[$d]= Songs::FilterListProp($field,'icon') ? (Gtk2::IconSize->lookup('menu'))[0] : 0;
	}

	#search box
	if ($opt->{searchbox} && Songs::FilterListProp($field,'search'))
	{	$self->pack_start( make_searchbox() ,::FALSE,::FALSE,1);
	}
	::Watch($self,'SearchText_'.$opt->{group},\&set_text_search);

	#interactive search box
	$self->{isearchbox}=GMB::ISearchBox->new($opt,$field,'nolabel');
	$self->pack_end( $self->{isearchbox} ,::FALSE,::FALSE,1);
	$self->signal_connect(key_press_event => \&key_press_cb); #only used for isearchbox


	$self->signal_connect(map => \&Fill);

	my $sub=\&play_current;
	if ($opt->{activate})
	{	$sub=\&enqueue_current	if $opt->{activate} eq 'queue';
		$sub=\&add_current	if $opt->{activate} eq 'addplay';
	}
	$self->{activate}=$sub;

	$self->set_mode($self->{mode});
	return $self;
}

sub SaveOptions
{	my $self=$_[0];
	my %opt;
	$opt{$_} = join '|', @{$self->{$_}} for qw/type lmarkup lpicsize sort/;
	$opt{$_} = $self->{$_} for qw/mode noall depth mpicsize cloud_min cloud_max cloud_stat/;
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
	$self->{icons}[$depth]||= Songs::FilterListProp($field,'icon') ? (Gtk2::IconSize->lookup('menu'))[0] : 0;

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
	$child->{is_a_view}=1;
	$view->signal_connect(focus_in_event	=> sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->{isearchbox}->hide; 0; });	#hide isearchbox when focus goes to the view

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
	my $sw=Gtk2::ScrolledWindow->new;
#	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);

	my $store=Gtk2::TreeStore->new(GID_TYPE);
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_rules_hint(1) if $self->{rules_hint};
	$sw->add($treeview);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_search_column(-1);	#disable gtk interactive search, use my own instead
	$treeview->set_enable_search(::FALSE);
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	my $renderer= CellRendererGID->new;
	my $column=Gtk2::TreeViewColumn->new_with_attributes('',$renderer);

	$renderer->set(prop => [@$self{qw/type lmarkup lpicsize icons/}]);	#=> $renderer->get('prop')->[0] contains $self->{type} (which is a array ref)
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

	$treeview->signal_connect( row_activated => sub
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			&{$self->{activate}};
		});
	return $sw,$treeview;
}

sub create_cloud
{	my $self=$_[0];
	$self->{mode}='cloud';
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('never','automatic');
	my $sub=Songs::DisplayFromGID_sub($self->{type}[0]);
	my $cloud= GMB::Cloud->new(\&child_selection_changed_cb,\&get_fill_data,$self->{activate},\&enqueue_current,\&PopupContextMenu,$sub);
	$sw->add_with_viewport($cloud);
	return $sw,$cloud;
}
sub create_mosaic
{	my $self=$_[0];
	$self->{mode}='mosaic';
	$self->{mpicsize}||=64;
	my $hbox=Gtk2::HBox->new(0,0);
	my $vscroll=Gtk2::VScrollbar->new;
	$hbox->pack_end($vscroll,0,0,0);
	my $mosaic= GMB::Mosaic->new(\&child_selection_changed_cb,\&get_fill_data,$self->{activate},\&enqueue_current,\&PopupContextMenu,$self->{type}[0],$vscroll);
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
	{	$self->{view}->set_cursor(Gtk2::TreePath->new_from_indices($row));
	}
	else { $self->{view}->set_cursor_to_row($row); }
}

sub make_searchbox
{	my $entry=Gtk2::Entry->new;	#FIXME tooltip
	my $clear=::NewIconButton('gtk-clear',undef,sub { $_[0]->{entry}->set_text(''); },'none' );	#FIXME tooltip
	$clear->{entry}=$entry;
	my $hbox=Gtk2::HBox->new(0,0);
	$hbox->pack_end($clear,0,0,0);
	$hbox->pack_start($entry,1,1,0);
	$entry->signal_connect(changed =>
		sub {	::IdleDo('6_UpdateSearch'.$entry,300,sub
				{	my $entry=$_[0];
					my $self=::find_ancestor($entry,__PACKAGE__);
					my $s=$entry->get_text;
					$self->set_text_search( $entry->get_text )
				},$_[0]);
		    });
	$entry->signal_connect(activate =>
		sub {	::DoTask('6_UpdateSearch'.$entry);
		    });
	return $hbox;
}
sub set_text_search
{	my ($self,$search)=@_;
	return if defined $self->{search} && $self->{search} eq $search;
	$self->{search}=$search;
	$self->{valid}=0;
	$self->Fill if $self->mapped;;
}

sub AAPicture_Changed
{	my ($self,$key)=@_;
	return if $self->{mode} eq 'cloud';
	return unless $self->{valid} && $self->{hash} && $self->{hash}{$key} && $self->{hash}{$key} >= ::find_ancestor($self,'FilterPane')->{min};
	$self->queue_draw;
}

sub selection_changed_cb
{	my $treesel=$_[0];
	child_selection_changed_cb($treesel->get_tree_view);
}

sub child_selection_changed_cb
{	my $child=$_[0];
	my $self=::find_ancestor($child,__PACKAGE__);
	return if $self->{busy};
	my $filter=$self->get_selected_filters;
	return unless $filter;
	my $filterpane=::find_ancestor($self,'FilterPane');
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub get_selected_filters
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my @filters;
	my $types=$self->{type};
	if ($self->{mode} eq 'list')
	{	my $store=$self->{view}->get_model;
		my $sel=$self->{view}->get_selection;
		my @rows=$sel->get_selected_rows;
		for my $path (@rows)
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
	my $filterpane=::find_ancestor($self,'FilterPane');
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
	{{	my $store=$self->{view}->get_model;
		my @iters=map $store->get_iter($_), $self->{view}->get_selection->get_selected_rows;
		last unless @iters;
		my $depth=$store->iter_depth($iters[0]);
		last if grep $depth != $store->iter_depth($_), @iters;
		@vals=map $store->get_value($_,0) , @iters;
		$field=$self->{field}[$depth];
	}}
	else { @vals=$self->{view}->get_selected }
	return $field,\@vals;
}

sub drag_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $field=$self->{field}[0];
	if (my $drag=Songs::FilterListProp($field,'drag'))	#return artist or album gids
	{	if ($self->{mode} eq 'list')
		{	my $store=$self->{view}->get_model;
			my @rows=$self->{view}->get_selection->get_selected_rows;
			unless (grep $_->get_depth>1, @rows)
			{	my @gids=map $store->get_value($store->get_iter($_),0), @rows;
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
	my $self=::find_ancestor($treeview,__PACKAGE__);
	my $filterpane=::find_ancestor($self,'FilterPane');
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
	my $self=::find_ancestor($child,__PACKAGE__);
	my $filterpane=::find_ancestor($self,'FilterPane');
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
	{	@list= @{ AA::GrepKeys($type,$search,\@list) };
	}
	AA::SortKeys($type,\@list,$self->{'sort'}[0]);

	my $beforeremoving0=@list;
	@list= grep $_!=0, @list;
	unshift @list,0 if $beforeremoving0!=@list;	#could be better

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
		$treeview->set('show-expanders', ($self->{depth}>0) ) if Gtk2->CHECK_VERSION(2,12,0);
		my $store=$treeview->get_model;
		my $col=$self->{col};
		my ($renderer)=($treeview->get_columns)[0]->get_cell_renderers;
		$renderer->reset;
		$self->{busy}=1;
		$store->clear;	#FIXME keep selection ?   FIXME at least when opt is true (ie lmarkup or lpicsize changed)
		my ($list)=$self->get_fill_data($opt);
		$renderer->set('all_count', $self->{all_count});
		$self->{array_offset}= $self->{noall} ? 0 : 1;	#row number difference between store and $list, needed by interactive search
		$store->set($store->append(undef),0,GID_ALL) unless $self->{noall};
		$store->set($store->append(undef),0,$_) for @$list;
		if ($self->{field}[1]) # add a chidren to every row
		{	my $first=$store->get_iter_first;
			$first=$store->iter_next($first) if $store->get($first,0)==GID_ALL; #skip "all" row
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

sub add_current
{	::DoActionForList( 'addplay',get_selected_filters($_[0])->filter );
}
sub play_current
{	::Select( filter=>get_selected_filters($_[0]), song=>'first',play=>1 );
}
sub enqueue_current
{	::EnqueueFilter( get_selected_filters($_[0]) );
}
sub PopupContextMenu
{	my ($self,undef,$event)=@_;
	$self=::find_ancestor($self,__PACKAGE__);
	my ($field,$gidlist)=$self->get_selected_list;
	my $gidall;
	if (grep GID_ALL==$_, @$gidlist) { $gidlist=[]; $gidall=1; }
	my $mainfield=Songs::MainField($field);
	my $aa= ($mainfield eq 'artist' || $mainfield eq 'album') ? $mainfield : undef; #FIXME
	my $mode= uc(substr $self->{mode},0,1); # C => cloud, M => mosaic, L => list
	FilterPane::PopupContextMenu($self,$event,{ self=> $self, filter => $self->get_selected_filters, field => $field, aa => $aa, gidlist =>$gidlist, gidall => $gidall, mode => $mode, subfield => $field, depth =>0 });
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	my $unicode=Gtk2::Gdk->keyval_to_unicode($event->keyval); # 0 if not a character
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'];
	my $shift=$state * ['shift-mask'];
	if	(lc$key eq 'f' && $ctrl) { $self->{isearchbox}->begin(); }	#ctrl-f : search
	elsif	(lc$key eq 'g' && $ctrl) { $self->{isearchbox}->search($shift ? -1 : 1);}	#ctrl-g : next/prev match
	elsif	(!$self->{no_typeahead} && $unicode && !($state * [qw/control-mask mod1-mask mod4-mask/]))
	{	$self->{isearchbox}->begin( chr $unicode );	#begin typeahead search
	}
	else	{return 0}
	return 1;
}

package FolderList;
use Gtk2;
use base 'Gtk2::ScrolledWindow';

sub new
{	my ($class,$col,$opt)=@_;
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store=Gtk2::TreeStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_search_equal_func(\&search_equal_func);
	$treeview->set_enable_search(!$opt->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(row_expanded  => \&row_expanded_changed_cb);
	$treeview->signal_connect(row_collapsed => \&row_expanded_changed_cb);
	$treeview->{expanded}={};
	my $renderer= Gtk2::CellRendererText->new;
	$store->{displayfunc}= Songs::DisplayFromHash_sub('path');
	my $column=Gtk2::TreeViewColumn->new_with_attributes(Songs::FieldName($col),$renderer);
	$column->set_cell_data_func($renderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $folder=::decode_url($store->get($iter,0));
			$cell->set( text=> $store->{displayfunc}->($folder));
		});
	$treeview->append_column($column);
	$self->add($treeview);
	$self->{treeview}=$treeview;

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
	return $self;
}

sub search_equal_func
{	#my ($store,$col,$string,$iter)=@_;
	my $store=$_[0];
	my $folder= $store->{displayfunc}( ::decode_url($store->get($_[3],0)) );
	#use ::superlc instead of uc ?
	my $string=uc $_[2];
	index uc($folder), $string;
}

sub Fill
{	warn "filling @_\n" if $::debug;
	my $self=$_[0];
	return if $self->{valid};
	my $treeview=$self->{treeview};
	my $filterpane=::find_ancestor($self,'FilterPane');
	my $href=$self->{hash}||= do
		{ my $h= Songs::BuildHash('path',$filterpane->{list});
		  my @hier;
		  while (my ($f,$n)=each %$h)
		  {	my $ref=\@hier;
			$ref=$ref->[1]{$_}||=[] and $ref->[0]+=$n   for split /$::QSLASH/o,$f;
		  }
		  for my $dir (keys %{$treeview->{expanded}})
		  {	my $ref=\@hier; my $notfound;
			$ref=$ref->[1]{$_} or $notfound=1, last  for split /$::QSLASH/o,$dir;
			if ($notfound)	{delete $treeview->{expanded}{$dir}}
			else		{ $ref->[2]=1; }
		  }
		  $hier[1]{::SLASH}=delete $hier[1]{''} if exists $hier[1]{''};
		  $hier[1];
		};
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
		push @toexpand,$store->get_path($iter) if $ref->[2];
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

sub row_expanded_changed_cb	#keep track of which rows are expanded
{	my ($treeview,$iter,$path)=@_;
	my $self=::find_ancestor($treeview,__PACKAGE__);
	return if $self->{busy};
	my $expanded=$treeview->row_expanded($path);
	$path=_treepath_to_foldername($treeview->get_model,$path);
	my $ref=[undef,$self->{hash}];
	$ref=$ref->[1]{($_ eq '' ? ::SLASH : $_)}  for split /$::QSLASH/o,$path;
	if ($expanded)
	{	$ref->[2]=1;				#for when reusing the hash
		$treeview->{expanded}{$path}=undef;	#for when reconstructing the hash
	}
	else
	{	delete $ref->[2];
		delete $treeview->{expanded}{$path};
	}
}

sub selection_changed_cb
{	my $treesel=$_[0];
	my $self=::find_ancestor($treesel->get_tree_view,__PACKAGE__);
	return if $self->{busy};
	my @paths=_get_path_selection( $self->{treeview} );
	return unless @paths;
	my $filter=_MakeFolderFilter(@paths);
	my $filterpane=::find_ancestor($self,'FilterPane');
	$filter->invert if $filterpane->{invert};
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub _MakeFolderFilter
{	my @paths=@_; #in utf8
	s#\\#\\\\#g for @paths;
	return Filter->newadd(::FALSE,map( 'path:i:'.$_, @paths ));
}

sub enqueue_current
{	my $self=$_[0];
	my @paths=_get_path_selection( $self->{treeview} );
	::EnqueueFilter( _MakeFolderFilter(@paths) );
}
sub PopupContextMenu
{	my ($self,$tv,$event)=@_;
	my @paths=_get_path_selection($tv);
	FilterPane::PopupContextMenu($self,$event,{self=>$tv, utf8pathlist => \@paths, filter => _MakeFolderFilter(@paths) });
}

sub _get_path_selection
{	my $treeview=$_[0];
	my $store=$treeview->get_model;
	my @paths=$treeview->get_selection->get_selected_rows;
	return () if @paths==0; #if no selection
	@paths=map _treepath_to_foldername($store,$_), @paths;
	return @paths;
}
sub _treepath_to_foldername
{	my $store=$_[0]; my $tp=$_[1];
	my @folders;
	my $iter=$store->get_iter($tp);
	while ($iter)
	{	unshift @folders, ::decode_url($store->get_value($iter,0));
		$iter=$store->iter_parent($iter);
	}
	$folders[0]='' if $folders[0] eq ::SLASH;
	return join(::SLASH,@folders);
}

package Filesystem;  #FIXME lots of common code with FolderList => merge it
use Gtk2;
use base 'Gtk2::ScrolledWindow';

sub new
{	my ($class,$col,$opt)=@_;
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store=Gtk2::TreeStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_enable_search(!$opt->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(row_expanded  => \&row_expanded_changed_cb);
	$treeview->signal_connect(row_collapsed => \&row_expanded_changed_cb);
	#$treeview->{expanded}={}; #not used
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( '',Gtk2::CellRendererText->new,'text',0)
		);

	$self->add($treeview);
	$self->{treeview}=$treeview;

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
	$store->set($iter,0,$root);
	$self->refresh_path($store->get_path($iter));
	$treeview->expand_to_path($store->get_path($iter));
	 #expand to home dir
	for my $folder (split /$::QSLASH/o,Glib::get_home_dir)
	{	next if $folder eq '';
		$iter=$store->iter_children($iter);
		while ($iter)
		{	last if $folder eq $store->get($iter,0);
			$iter=$store->iter_next($iter);
		}
		last unless $iter;
		$treeview->expand_to_path($store->get_path($iter));
	}
	$self->{valid}=1;
}

sub row_expanded_changed_cb
{	my ($treeview,$iter,$path)=@_;
	my $self=::find_ancestor($treeview,__PACKAGE__);
	my $store=$treeview->get_model;
	my $expanded=$treeview->row_expanded($path);
	return unless $expanded;
	return unless $self->refresh_path($path);
	$iter=$store->get_iter($path);
	$iter=$store->iter_children($iter);
	while ($iter)
	{	my $path=$store->get_path($iter);
		$self->refresh_path($path);
		$iter=$store->iter_next($iter);
	}
}

sub refresh_path
{	my ($self,$path)=@_;
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $onlyfirst=!$treeview->row_expanded($path);
	my $parent=$store->get_iter($path);
	my $folder=_treepath_to_foldername($store,$path);
	unless (-d $folder)
	{	$store->remove($parent);
		return undef;
	}
	my $ok=opendir my($dh),$folder;
	return 0 unless $ok;
	my $iter=$store->iter_children($parent);
	NEXTDIR: for my $dir (sort grep -d $folder.::SLASH.$_ , readdir $dh)
	{	next if $dir=~m#^\.#;
		while ($iter)
		{	my $c= $dir cmp $store->get($iter,0);
			unless ($c) { $iter=$store->iter_next($iter);next NEXTDIR;}
			last if $c>0;
			my $iter2=$store->iter_next($iter);
			$store->remove($iter);
			$iter=$iter2;
		}
		my $iter2=$store->insert_before($parent,$iter);
		$store->set($iter2,0,$dir);
		last if $onlyfirst;
	}
	return 1;
}

sub selection_changed_cb
{	my $treesel=$_[0];
	my $self=::find_ancestor($treesel->get_tree_view,__PACKAGE__);
	#return if $self->{busy};
	my @paths=_get_path_selection( $self->{treeview} );
	return unless @paths;
	my $filter=_MakeFolderFilter(@paths);
	my $filterpane=::find_ancestor($self,'FilterPane');
	#$filter->invert if $filterpane->{invert};
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub _MakeFolderFilter
{	my @paths=@_; #in utf8 ?
	my @list= ::FolderToIDs(0,0,@paths);
	my $filter= Filter->new('',\@list); #FIXME use a filter on path rather than a list ?
	return $filter;
}

sub enqueue_current
{	my $self=$_[0];
	my @paths=_get_path_selection( $self->{treeview} );
	::EnqueueFilter( _MakeFolderFilter(@paths) );
}
sub PopupContextMenu
{	my ($self,$tv,$event)=@_;
	my @paths=_get_path_selection($tv);
	FilterPane::PopupContextMenu($self,$event,{self=>$tv, utf8pathlist => \@paths, filter => _MakeFolderFilter(@paths) });
}

sub _get_path_selection
{	my $treeview=$_[0];
	my $store=$treeview->get_model;
	my @paths=$treeview->get_selection->get_selected_rows;
	return () if @paths==0; #if no selection
	@paths=map _treepath_to_foldername($store,$_), @paths;
	return @paths;
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
use Gtk2;
use base 'Gtk2::VBox';

use constant { TRUE  => 1, FALSE => 0, };

our @cMenu; our %Modes;
INIT
{ @cMenu=
  (	{ label => _"New filter",	code => sub { ::EditFilter($_[0]{self},undef,''); },	stockicon => 'gtk-add' },
	{ label => _"Edit filter",	code => sub { ::EditFilter($_[0]{self},undef,$_[0]{names}[0]); },
		mode => 'F',	onlyone => 'names' },
	{ label => _"Remove filter",	code => sub { ::SaveFilter($_[0]{names}[0],undef); },
		mode => 'F',	onlyone => 'names',	stockicon => 'gtk-remove' },
	{ label => _"Save current filter as",	code => sub { ::EditFilter($_[0]{self},$_[0]{curfilter},''); },
		 stockicon => 'gtk-save',	isdefined => 'curfilter',	test => sub { ! $_[0]{curfilter}->is_empty; } },
	{ label => _"Save current list as",	code => sub { $_[0]{self}->CreateNewFL('L',\@{ $_[0]{songlist}{array} }); },
		stockicon => 'gtk-save',	isdefined => 'songlist' },
	{ label => _"Edit list",	code => sub { ::WEditList( $_[0]{names}[0] ); },
		mode => 'L',	onlyone => 'names' },
	{ label => _"Remove list",	code => sub { ::SaveList($_[0]{names}[0],undef); },
		stockicon => 'gtk-remove',	mode => 'L', onlyone => 'names', },
	{ label => _"Rename",	code => sub { my $tv=$_[0]{self}{treeview}; $tv->set_cursor($_[0]{treepaths}[0],$tv->get_column(0),TRUE); },
		notempty => 'names',	onlyone => 'treepaths' },
	{ label => _"Import list",	code => sub { ::Choose_and_import_playlist_files(); }, mode => 'L', },
  );

  %Modes=
  (	F => [_"Saved filters",	'sfilter',	'SavedFilters',	\&UpdateSavedFilters,	'gmb-filter'	,\&::SaveFilter, 'filter000'],
	L => [_"Saved lists",	'slist',	'SavedLists',	\&UpdateSavedLists,	'gmb-list'	,\&::SaveList, 'list000'],
	P => [_"Playing",	'play',		undef,		\&UpdatePlayingFilters,	'gtk-media-play'	],
  );
}

sub new
{	my ($class,$mode)=@_;
	my $self = bless Gtk2::VBox->new(FALSE, 4), $class;
	my $store=Gtk2::TreeStore->new(('Glib::String')x4,'Glib::Boolean');
	$self->{treeview}=my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(FALSE);
	my $renderer0=Gtk2::CellRendererPixbuf->new;
	my $renderer1=Gtk2::CellRendererText->new;
	$renderer1->signal_connect(edited => \&name_edited_cb,$self);
	my $column=Gtk2::TreeViewColumn->new;
	$column->pack_start($renderer0,0);
	$column->pack_start($renderer1,1);
	$column->add_attribute($renderer0, 'stock-id'	=> 2);
	$column->add_attribute($renderer1, text		=> 0);
	$column->add_attribute($renderer1, editable	=> 4);
	$treeview->append_column($column);

	::set_drag($treeview, source =>
		[::DRAG_FILTER,sub
		 {	my $self=::find_ancestor($_[0],__PACKAGE__);
			my $filter=$self->get_selected_filters;
			return ::DRAG_FILTER,($filter? $filter->{string} : undef);
		 }],
		 dest =>
		[::DRAG_FILTER,::DRAG_ID,sub	#targets are modified in drag_motion callback
		 {	my ($treeview,$type,$dest,@data)=@_;
			my $self=::find_ancestor($treeview,__PACKAGE__);
			my (undef,$path)=@$dest;
			my ($name,$rowtype)=$store->get_value( $store->get_iter($path) );
			if ($type == ::DRAG_ID)
			{	if ($rowtype eq 'slist')
				{	$::Options{SavedLists}{$name}->Push(@data);
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

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);
	$sw->add($treeview);
	$self->add($sw);
	$self->{store}=$store;

	$mode||='FPL';
	my $n=0;
	for (split //,$mode)
	{	my ($label,$id,$watchid,$sub,$stock)=@{ $Modes{$_} };
		if (length($mode)!=1)
		{	$store->set($store->append(undef),0,$label,1,'root-'.$id,2,$stock);
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
	{	$iter=$store->get_iter_from_string($self->{play});
	}
	my @list=(	playfilter	=> _"Playing Filter",
			'f=artists'	=> _"Playing Artist",
			'f=album'	=> _"Playing Album",
			'f=title'	=> _"Playing Title",
		 );
	while (@list)
	{	my $id=shift @list;
		my $name=shift @list;
		$store->set($store->append($iter),0,$name,1,'play',3,$id);;
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
	{	$path=Gtk2::TreePath->new( $self->{$type} );
		$expanded=$treeview->row_expanded($path);
		$iter=$store->get_iter($path);
		$expanded=1 unless $store->iter_has_child($iter);
	}
	while (my $child=$store->iter_children($iter))
	{	$store->remove($child);
	}
	$store->set($store->append($iter),0,$_,1,$type,4,TRUE) for sort keys %{$::Options{$hkey}}; #FIXME use case and accent insensitive sort #should use GetListOfSavedLists() for SavedLists
	$treeview->expand_to_path($path) if $expanded;
	$self->{busy}=undef;
}

sub enqueue_current
{ ::EnqueueFilter($_[0]->get_selected_filters); }

sub PopupContextMenu
{	my ($self,$tv,$event)=@_;
	my @rows=$tv->get_selection->get_selected_rows;
	my $store=$tv->get_model;
	my %sel;
	for my $path (@rows)
	{	my ($name,$type)=$store->get_value($store->get_iter($path));
		next if $type=~m/^root-/;
		push @{ $sel{$type} },$name;
	}
	my %args=( self=> $self, treepaths=>\@rows, curfilter=>::GetFilter($self), filter=> $self->get_selected_filters );
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
	FilterPane::PopupContextMenu($self,$event,\%args, [@cMenu,{ separator=>1 },@FilterPane::cMenu] );
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
		my $target_id=[$::DRAGTYPES[::DRAG_ID][0],'same-app',::DRAG_ID];
		my $target_filter=[$::DRAGTYPES[::DRAG_FILTER][0],[],::DRAG_FILTER];
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

		if ($lookfor && grep $::DRAGTYPES{$_->name} ==$lookfor, $context->targets)
		{	$status='copy';
			$treeview->drag_dest_set_target_list(Gtk2::TargetList->new( @targets ));
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
	$treeview->set_cursor($path,$column,TRUE);
}

sub name_edited_cb
{	my ($cell, $path_string, $newname,$self) = @_;
	my $store=$self->{store};
	my $iter=$store->get_iter_from_string($path_string);
	my ($name,$type)=$store->get($iter,0,1);
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
	my $self=::find_ancestor($treesel->get_tree_view,__PACKAGE__);
	return if $self->{busy};
	my $filter=$self->get_selected_filters;
	return unless $filter;
	my $filterpane=::find_ancestor($self,'FilterPane');
	::SetFilter( $self, $filter, $filterpane->{nb}, $filterpane->{group} );
}

sub get_selected_filters
{	my $self=$_[0];
	my $store=$self->{store};
	my @filters;
	for my $path ($self->{treeview}->get_selection->get_selected_rows)
	{	my ($name,$type,undef,$extra)=$store->get_value($store->get_iter($path));
		next unless $type;
		if ($type eq 'sfilter') {push @filters,$::Options{SavedFilters}{$name};}
		elsif ($type eq 'slist'){push @filters,':l:'.$name;}
		elsif ($type eq 'play') {push @filters,_getplayfilter($extra);}
	}
	return undef unless @filters;
	my $filterpane=::find_ancestor($self,'FilterPane');
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
use Gtk2;
use base 'Gtk2::EventBox';

our @DefaultOptions=
(	aa	=> 'album',
	filternb=> 1,
	#nopic	=> 0,
);

sub new
{	my ($class,$opt)= @_;
	my $self=bless Gtk2::EventBox->new, $class;
	%$opt=( @DefaultOptions, %$opt );
	my $aa=$opt->{aa};
	$aa='artists' if $aa eq 'artist';
	$aa= 'album' unless $aa eq 'artists';		#FIXME PHASE1 change artist to artists
	$self->{aa}=$aa;
	$self->{filternb}=$opt->{filternb};
	$self->{group}=$opt->{group};
	$self->{nopic}=1 if $opt->{nopic};
	my $hbox= Gtk2::HBox->new;
	$self->add($hbox);
	$self->{Sel}=$self->{SelID}=undef;
	my $vbox=Gtk2::VBox->new(::FALSE, 0);
	for my $name (qw/Ltitle Lstats/)
	{	my $l=Gtk2::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle')
		{	$l->set_line_wrap(1);$l->set_ellipsize('end'); #FIXME find a better way to deal with long titles
			my $b=Gtk2::Button->new;
			$b->set_relief('none');
			$b->signal_connect(button_press_event => \&AABox_button_press_cb);
			$b->add($l);
			$l=$b;
		}
		$vbox->pack_start($l, ::FALSE,::FALSE, 2);
	}

	my $pixbox=Gtk2::EventBox->new;
	$self->{img}=my $img=Gtk2::Image->new;
	$img->{size}=0;
	$img->signal_connect(size_allocate => \&size_allocate_cb);
	$pixbox->add($img);
	$pixbox->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb,1); # 1 : mouse button 1

	my $buttonbox=Gtk2::VBox->new;
	my $Bfilter=::NewIconButton('gmb-filter',undef,sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->filter },'none');
	my $Bplay=::NewIconButton('gtk-media-play',undef,sub
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			return unless defined $self->{SelID};
			my $filter=Songs::MakeFilterFromGID($self->{aa},$self->{Sel});
			::Select(filter=> $filter, song=>'first',play=>1);
		},'none');
	$Bplay->signal_connect(button_press_event => sub	#enqueue with middle-click
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			return 0 if $_[1]->button !=2;
			my $filter= Songs::MakeFilterFromGID($self->{aa},$self->{Sel});
			if (defined $self->{SelID}) { ::EnqueueFilter($filter); }
			1;
		});
	$Bfilter->set_tooltip_text( ($aa eq 'album' ? _"Filter on this album"		: _"Filter on this artist") );
	$Bplay  ->set_tooltip_text( ($aa eq 'album' ? _"Play all songs from this album" : _"Play all songs from this artist") );
	$buttonbox->pack_start($_, ::FALSE, ::FALSE, 0) for $Bfilter,$Bplay;

	$hbox->pack_start($pixbox, ::FALSE, ::TRUE, 0);
	$hbox->pack_start($vbox, ::TRUE, ::TRUE, 0);
	$hbox->pack_start($buttonbox, ::FALSE, ::FALSE, 0);

	if ($aa eq 'artists')
	{	$self->{'index'}=0;
		$self->signal_connect(scroll_event => \&AABox_scroll_event_cb);
		my $BAlblist=::NewIconButton('gmb-playlist',undef,undef,'none');
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

sub size_allocate_cb
{	my ($img,$alloc)=@_;
	my $h=$alloc->height;
	$h=200 if $h>200;		#FIXME use a relative max value (to what?)
	return unless abs($img->{size}-$h);
	$img->{size}=$h;
	::IdleDo('3_AABscaleimage'.$img,200,\&setpic,$img);
}
sub setpic
{	my $img=shift;
	my $self= ::find_ancestor($img,__PACKAGE__);
	my $file= $img->{filename}= AAPicture::GetPicture($self->{aa},$self->{Sel});
	my $pixbuf= $file ? GMB::Picture::pixbuf($file,$img->{size}) : undef;
	$img->set_from_pixbuf($pixbuf);
}

sub AABox_button_press_cb			#popup menu
{	my ($widget,$event)=@_;
	my $self=::find_ancestor($widget,__PACKAGE__);
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
	my $self=::find_ancestor($widget,__PACKAGE__);
	return unless defined $self->{Sel};
	::PopupAA('album', from => $self->{Sel}, cb=>sub
		{	my $key=$_[1];
			my $filter= Songs::MakeFilterFromGID('album',$key);
			::SetFilter( $self, $filter, $self->{filternb}, $self->{group} );
		});
	1;
}

package SimpleSearch;
use base 'Gtk2::HBox';

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
our @DefaultOptions=
(	nb	=> 1,
	fields	=> $SelectorMenu[0][1],
);

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::HBox->new(0,0), $class;
	%$opt=( @DefaultOptions, %$opt );
	$self->{$_}=$opt->{$_} for qw/nb fields group searchfb/,keys %Options;
	my $entry=$self->{entry}=Gtk2::Entry->new;
	$self->{SaveOptions}=\&SaveOptions;
	$self->{DefaultFocus}=$entry;
	#$entry->set_width_chars($opt->{width_chars}) if $opt->{width_chars};
	$entry->signal_connect(changed => \&EntryChanged_cb);
	$entry->signal_connect(activate => \&Filter);
	$entry->signal_connect_after(activate => sub {::run_command($_[0],$opt->{activate});}) if $opt->{activate};
	unless ($opt->{noselector})
	{	for my $aref (	['gtk-find'	=> \&PopupSelectorMenu,	0, _"Search options"],
				['gtk-clear'	=> \&ClearFilter,	1, _"Reset filter"]
			     )
		{	my ($stock,$cb,$end,$tip)=@$aref;
			my $img=Gtk2::Image->new_from_stock($stock,'menu');
			my $but=Gtk2::Button->new;
			$but->add($img);
			$but->can_focus(0);
			$but->set_relief('none');
			$but->set_tooltip_text($tip);
			$but->signal_connect(expose_event => sub #prevent the button from beign drawn, but draw its child
			{	my ($but,$event)=@_;
				$but->propagate_expose($but->child,$event);
				1;
			});
			#$but->signal_connect(realize => sub { $_[0]->window->set_cursor(Gtk2::Gdk::Cursor->new('hand2')); });
			$but->signal_connect(button_press_event=> $cb);
			if ($end) { $self->pack_end($but,0,0,0); }
			else { $self->pack_start($but,0,0,0); }
			if ($stock eq 'gtk-clear')
			{	$self->{clear_button}=$but;
				$entry->signal_connect(changed => \&UpdateClearButton);
				$but->set_sensitive(0);
			}
		}
		$self->pack_start($entry,1,1,0);
		$entry->set('has-frame',0);
		$entry->signal_connect($_ => sub {$_[0]->parent->queue_draw}) for qw/focus_in_event focus_out_event/;
		$self->signal_connect(expose_event => sub #draw an entry frame inside $self
			{	my ($self,$event)=@_;
				my $entry=$self->{entry};
				if ($entry->state eq 'normal')
				{	my $s= $self->{filtered} && !$entry->is_focus;
					$entry->modify_base('normal', ($s? $entry->style->bg('selected') : undef) );
					$entry->modify_text('normal', ($s? $entry->style->text('selected') : undef) );
				}
				$entry->style->paint_flat_box( $self->window, $entry->state, 'none', $event->area, $entry, 'entry_bg', $self->allocation->values );
				$entry->style->paint_shadow( $self->window, 'normal', $entry->get('shadow-type'), $event->area, $entry, 'entry', $self->allocation->values);
				#$self->propagate_expose($_,$event) for $self->get_children;
				0;
			});
		::WatchFilter($self, $self->{group},sub {$_[0]->{filtered}=0; $_[0]->UpdateClearButton; $_[0]->queue_draw}); #to update background color and clear button
	}
	else {$self->add($entry);}
	return $self;
}
sub SaveOptions
{	my $self=$_[0];
	my %opt=(fields => $self->{fields});
	$opt{$_}=1 for grep $self->{$_}, keys %Options;
	return \%opt;
}

sub ClearFilter
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	$self->{entry}->set_text('');
	$self->Filter;
}
sub UpdateClearButton
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $on= $self->{entry}->get_text ne '' || !::GetFilter($self)->is_empty;
	$self->{clear_button}->set_sensitive($on);
}

sub ChangeOption
{	my ($self,$key,$value)=@_;
	$self->{$key}=$value;
	$self->{last_filter}=undef;
	$self->Filter;
}

sub PopupSelectorMenu
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $menu=Gtk2::Menu->new;
	my $cb=sub { $self->ChangeOption( fields => $_[1]); };
	for my $ref (@SelectorMenu)
	{	my ($label,$fields)=@$ref;
		my $item=Gtk2::CheckMenuItem->new($label);
		$item->set_active(1) if $fields eq $self->{fields};
		$item->set_draw_as_radio(1);
		$item->signal_connect(activate => $cb,$fields);
		$menu->append($item);
	}
	$menu->append(Gtk2::SeparatorMenuItem->new);
	for my $key (sort { $Options{$a} cmp $Options{$b} } keys %Options)
	{	my $item=Gtk2::CheckMenuItem->new($Options{$key});
		$item->set_active(1) if $self->{$key};
		$item->signal_connect(activate => sub
			{	$self->ChangeOption( $_[1] => $_[0]->get_active);
			},$key);
		$menu->append($item);
	}
	my $item2=Gtk2::MenuItem->new(_"Advanced Search ...");
	$item2->signal_connect(activate => sub
		{	::EditFilter($self,::GetFilter($self),undef,sub {::SetFilter($self,$_[0]) if defined $_[0]});
		});
	$menu->append($item2);
	$menu->show_all;
	my $event=Gtk2->get_current_event;
	$menu->popup(undef,undef,\&::menupos,undef,$event->button,$event->time);
}

sub Filter
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $entry=$self->{entry};
	Glib::Source->remove(delete $entry->{changed_timeout}) if $entry->{changed_timeout};
	my ($last_filter,$last_eq,@last_substr)= @{ delete $self->{last_filter} || [] };
	my $search0=my $search= $entry->get_text;
	my $filter;

	my (@filters,@or);
	my ($now_eq,@now_substr);
	while (length $search)
	{	my $op= $self->{regexp} ? 'mi' : 's';
		my $not=0;
		my $fields=$self->{fields};
		my @words;
		if ($self->{literal})
		{	push @words,$search;
			$search='';
		}
		else
		{	$search=~s/^\s+//;
			if ($search=~s#^(?:\||OR)\s+##) { push @or, scalar @filters;next; }
			$not=1 if $search=~s/^[-!]//;
			$search=~s/^\\(?=[-!O|])//;
			if ($search=~s#^([A-Za-z]\w*(?:\|[A-Za-z]\w*)*)?([:<>=~])##)
			{	my $o= $2 eq ':' ? 's' : $2 eq '~' ? 'mi' : $2 eq '=' ? 'e' : $2; #FIXME use a hash ?
				my $f= $1 || $fields;
				if (Songs::CanDoFilter($o,split /\|/, $f))
				{	$fields=$f;
					$op=$o;
				}
				else {$search=$1.$2.$search;}
			}
			{	if ($search=~s#^(['"])(.+?)(?<!\\)\1((?<!\\)\||\s+|$)##)
				{	push @words,$2;
					redo if $3 eq '|';
				}
				elsif ($search=~s#^(\S.*?)((?<!\\)\||(?<!\\)\s+|$)##)
				{	push @words,$1;
					redo if $2 eq '|';
				}
			}
			unless (@words) {push @filters,undef;next}
			#warn "$_:$words[$_].\n" for 0..$#words;
			s#\\([ "'|])#$1#g for @words;
		}

		my $and= $not ? 1 : 0;
		$not= $not ? '-' : '';
		my @f;
		for my $s (@words)
		{	my $op=$op;
			# for number fields, check if $string is a range :
			if ($op eq 'e' && $s=~m/\.\.|^[^-]+\s*-[^-]*$/ && Songs::CanDoFilter('b',split /\|/, $fields))
			{	$s=~m/(\d+\w*\s*)?(?:\.\.|-)(\s*\d+\w*)?/;
				if (defined $1 && defined $2)		{ $op='b'; $s="$1 $2"; }
				elsif (!defined $1 && defined $2)	{ $op='>'; $not=!$not; $s=$2; }
				elsif (!defined $2 && defined $1)	{ $op='<'; $not=!$not; $s=$1; }
				$not= $not ? '-' : '';
			}
			if ($self->{casesens})
			{	if ($op eq 's') {$op='S'} elsif ($op eq 'mi') {$op='m'}
			}
			push @f,Filter->newadd( $and,map "$not$_:$op:$s", split /\|/,$fields );
			#@now_substr and $now_eq are for filter comparison->optimization
			if ($op eq 's')
			{	push @now_substr,$s;
				$s='';
			}
			$now_eq.="$not$and$fields:$op:$s\x00";
		}
		push @filters, Filter->newadd(::FALSE,@f);
		$now_eq="or(@or)".$now_eq."\x00";
		while (@or)
		{	my $first=my $last=pop @or;
			$first=pop @or while @or && $or[-1]==$first-1;
			$first-- if $first>0;
			$last-- if $last>$#filters;
			splice @filters,$first,1+$last-$first, Filter->newadd(::FALSE,@filters[$first..$last]) if $last>$first;
		}
		@filters=grep defined, @filters;

		if (@filters)
		{	$filter=Filter->newadd( ::TRUE,@filters );
			if ($last_eq && !$self->{regexp} && $last_eq eq $now_eq && !grep index($now_substr[$_],$last_substr[$_])==-1, 0..$#now_substr )
			{	#optimization : indicate that this filter will only match songs that match $last_filter
				$filter->set_parent($last_filter);
				#warn "----optimization : base results on previous filter results (if cached)\n";
			}
			$self->{last_filter}=[$filter,$now_eq,@now_substr];
		}
	}
	$filter||=Filter->new;
	::SetFilter($self,$filter,$self->{nb});
	if ($self->{searchfb})
	{	::HasChanged('SearchText_'.$self->{group},$search0); #FIXME
	}
	$self->{filtered}= 1 && !$filter->is_empty; #used to set the background color
}

sub EntryChanged_cb
{	my $entry=$_[0];
	Glib::Source->remove(delete $entry->{changed_timeout}) if $entry->{changed_timeout};
	my $l= length($entry->get_text);
	my $timeout= $l>2 ? 100 : 1000;
	$entry->{changed_timeout}= Glib::Timeout->add($timeout,\&Filter,$entry);
}

package SongSearch;
use base 'Gtk2::VBox';

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::VBox->new, $class;
	my $activate= $opt->{activate} || 'queue';
	$self->{songlist}=
	my $songlist=SongList->new({type=>'S',headers=>'off',activate=>$activate,'sort'=>'title',cols=>'titleaa', group=>"$self"});
	my $hbox1=Gtk2::HBox->new;
	my $entry=Gtk2::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate =>\&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk2::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$self->pack_start($hbox1, ::FALSE,::FALSE,2);
	$self->add($songlist);
	if ($opt->{buttons})
	{	my $hbox2=Gtk2::HBox->new;
		my $Bqueue=::NewIconButton('gmb-queue',		_"Enqueue",	sub { $songlist->EnqueueSelected; });
		my $Bplay= ::NewIconButton('gtk-media-play',	_"Play",	sub { $songlist->PlaySelected; });
		my $Bclose=::NewIconButton('gtk-close',		_"Close",	sub {$self->get_toplevel->close_window});
		$hbox2->pack_end($_, ::FALSE,::FALSE,4) for $Bclose,$Bplay,$Bqueue;
		$self->pack_end($hbox2, ::FALSE,::FALSE,0);
	}

	$self->{DefaultFocus}=$entry;
	return $self;
}

sub EntryChanged_cb
{	my ($entry,$force)=@_;
	my $text=$entry->get_text;
	my $self=::find_ancestor($entry,__PACKAGE__);
	if (!$force && 2>length $text) { $self->{songlist}->Empty }
	else { $self->{songlist}->SetFilter( Filter->new('title:s:'.$text) ); }
}

package AASearch;
use base 'Gtk2::VBox';

sub new
{	my ($class,$opt)=@_;
	my $self= bless Gtk2::VBox->new, $class;
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);
	my $store=Gtk2::ListStore->new(FilterList::GID_TYPE);
	my $treeview= $self->{treeview}= Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	my $renderer= CellRendererGID->new;
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes('', $renderer, gid=>0) );
	my $sub=\&Enqueue;
	$sub=\&AddToPlaylist if $opt->{activate} && $opt->{activate} eq 'addplay';
	$treeview->signal_connect( row_activated => $sub);

	$self->{field}= $opt->{aa} || 'artists';
	$renderer->set(prop => [[$self->{field}],[1],[32],[0]], depth => 0);  # (field markup=1 picsize=32 icons=0)
	$self->{drag_type}= Songs::FilterListProp( $self->{field}, 'drag') || ::DRAG_FILTER;
	::set_drag($treeview, source =>
	    [ $self->{drag_type},
	    sub
	    {	my $self=::find_ancestor($_[0],__PACKAGE__);
		my @rows=$treeview->get_selection->get_selected_rows;
		my @gids=map $store->get_value($store->get_iter($_),0) , @rows;
		if ($self->{drag_type} != ::DRAG_FILTER)	#return artist or album gids
		{	return $self->{drag_type},@gids;
		}
		else
		{	my @f=map Songs::MakeFilterFromGID( $self->{field}, $_ ), @gids;
			my $filter= Filter->newadd(::FALSE, @f);
			return ($filter? (::DRAG_FILTER,$filter->{string}) : undef);
		}
	    }]);

	my $hbox1=Gtk2::HBox->new;
	my $entry=Gtk2::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate=> \&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk2::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$sw->add($treeview);
	$self->pack_start($hbox1, ::FALSE,::FALSE,2);
	$self->add($sw);
	if ($opt->{buttons})
	{	my $hbox2=Gtk2::HBox->new;
		my $Bqueue=::NewIconButton('gmb-queue',     _"Enqueue",	\&Enqueue);
		my $Bplay= ::NewIconButton('gtk-media-play',_"Play",	\&Play);
		my $Bclose=::NewIconButton('gtk-close',     _"Close",	sub {$self->get_toplevel->close_window});
		$hbox2->pack_end($_, ::FALSE,::FALSE,4) for $Bclose,$Bplay,$Bqueue;
		$self->pack_end($hbox2, ::FALSE,::FALSE,0);
	}

	$self->{DefaultFocus}=$entry;
	return $self;
}

sub GetFilter
{	my $self=::find_ancestor($_[0],__PACKAGE__);
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
	my $self= ::find_ancestor($entry,__PACKAGE__);
	my $store=$self->{treeview}->get_model;
	(($self->{treeview}->get_columns)[0]->get_cell_renderers)[0]->reset;
	$store->clear;
	return if !$force && 2>length $text;
	my $list= AA::GrepKeys($self->{field}, $text);
	AA::SortKeys($self->{field},$list,'alpha');
	$store->set($store->append,0,$_) for @$list;
}

sub Enqueue
{	my $filter=GetFilter($_[0]);
	::EnqueueFilter($filter) if $filter;
}
sub Play
{	my $filter=GetFilter($_[0]);
	::Select(filter => $filter,song =>'first',play=>1) if $filter;
}
sub AddToPlaylist
{	my $filter=GetFilter($_[0]);
	return unless $filter;
	my $list=$filter->filter;
	::DoActionForList('addplay',$list);
}

package CellRendererIconList;
use Glib::Object::Subclass
	'Gtk2::CellRenderer',
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
#	#my ($w,$h)=Gtk2::IconSize->lookup( $cell->get('stock-size') );
#	my ($w,$h)=Gtk2::IconSize->lookup('menu');
#	return (0,0, $nb*($w+PAD)+$cell->get('xpad')*2, $h+$cell->get('ypad')*2);
}

sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my ($field,$ID)=$cell->get(qw/field ID/);
	my @list=Songs::Get_icon_list($field,$ID);
	return unless @list;
	#my $size=$cell->get('stock-size');
	my $size='menu';
	my @pb=map $widget->render_icon($_, $size), sort @list;
	return unless @pb;
	my $state= ($flags & 'selected') ?
		( $widget->has_focus			? 'selected'	: 'active'):
		( $widget->state eq 'insensitive'	? 'insensitive'	: 'normal');

	my ($w,$h)=Gtk2::IconSize->lookup($size);
	my $room=PAD + $cell_area->height-2*$cell->get('ypad');
	my $nb=int( $room / ($h+PAD) );
	my $x=$cell_area->x+$cell->get('xpad');
	my $y=$cell_area->y+$cell->get('ypad');
	$y+=int( $cell->get('yalign') * ($room-($h+PAD)*$nb) ) if $nb>0;
	my $row=0; my $ystart=$y;
	for my $pb (@pb)
	{	$window->draw_pixbuf( $widget->style->fg_gc($state), $pb,0,0,
				$x,$y,-1,-1,'none',0,0);
		$row++;
		if ($row<$nb)	{ $y+=PAD+$h; }
		else		{ $row=0; $y=$ystart; $x+=PAD+$w; }
	}
}

package CellRendererGID;
use Glib::Object::Subclass 'Gtk2::CellRenderer',
properties => [ Glib::ParamSpec->ulong('gid', 'gid', 'group id',		0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->ulong('all_count', 'all_count', 'all_count',	0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->scalar('prop', 'prop', '[[field],[markup],[picsize]]',		[qw/readable writable/]),
		Glib::ParamSpec->int('depth', 'depth', 'depth',			0, 20, 0,	[qw/readable writable/]),
		];
use constant { PAD => 2, XPAD => 2, YPAD => 2,		P_FIELD => 0, P_MARKUP =>1, P_PSIZE=>2, P_ICON =>3, };

#sub INIT_INSTANCE
#{	#$_[0]->set(xpad=>2,ypad=>2); #Gtk2::CellRendererText has these padding values as default
#}
sub makelayout
{	my ($cell,$widget)=@_;
	my ($prop,$gid,$depth)=$cell->get(qw/prop gid depth/);
	my $layout=Gtk2::Pango::Layout->new( $widget->create_pango_context );
	my $field=$prop->[P_FIELD][$depth];
	my $markup=$prop->[P_MARKUP][$depth];
	$markup= $markup ? "<b>%a</b>%Y\n<small>%x / %s / <small>%l</small></small>" : "%a"; #FIXME
	if ($gid==FilterList::GID_ALL)
	{	$markup= ::MarkupFormat("<b>%s (%d)</b>", Songs::Field_All_string($field), $cell->get('all_count') );
	}
	#elsif ($gid==0) {  }
	else { $markup=AA::ReplaceFields( $gid,$markup,$field,::TRUE ); }
	$layout->set_markup($markup);
	return $layout;
}

sub GET_SIZE
{	my ($cell, $widget, $cell_area) = @_;
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	my ($prop,$depth)=$cell->get('prop','depth');
	my $s= $prop->[P_PSIZE][$depth] || $prop->[P_ICON][$depth];
	if ($s == -1)	{$s=$h}
	elsif ($h<$s)	{$h=$s}
	return (0,0,$w+$s+PAD+XPAD*2,$h+YPAD*2);
}

sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my $x=$cell_area->x+XPAD;
	my $y=$cell_area->y+YPAD;
	my ($prop,$gid,$depth)=$cell->get(qw/prop gid depth/);
	my $iconfield= $prop->[P_ICON][$depth];
	my $psize= $iconfield ? (Gtk2::IconSize->lookup('menu'))[0] : $prop->[P_PSIZE][$depth];
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	$psize=$h if $psize == -1;
	$w+=PAD+$psize;
	my $offy=0;
	if ($psize>$h)
	{	$offy+=int( $cell->get('yalign')*($psize-$h) );
		$h=$psize;
	}

	my $state= ($flags & 'selected') ?
		( $widget->has_focus			? 'selected'	: 'active'):
		( $widget->state eq 'insensitive'	? 'insensitive'	: 'normal');

	if ($psize && $gid!=FilterList::GID_ALL)
	{	my $field=$prop->[P_FIELD][$depth];
		my $pixbuf=	$iconfield	? $widget->render_icon(Songs::Picture($gid,$field,'icon'),'menu')||undef: #FIXME could be better
						AAPicture::pixbuf($field,$gid,$psize);
		if ($pixbuf) #pic cached -> draw now
		{	my $offy=int(($h-$pixbuf->get_height)/2);#center pic
			my $offx=int(($psize-$pixbuf->get_width)/2);
			$window->draw_pixbuf( $widget->style->black_gc, $pixbuf,0,0,
				$x+$offx, $y+$offy,-1,-1,'none',0,0);
		}
		elsif (defined $pixbuf) #pic exists but not cached -> load and draw in idle
		{	my ($tx,$ty)=$widget->widget_to_tree_coords($x,$y);
			$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
			$cell->{widget}||=$widget;
			$cell->{window}||=$window;
			$cell->{queue}{$ty}=[$tx,$ty,$gid,$psize,$h,\$field];
		}
	}

	# draw text
	$widget-> get_style-> paint_layout($window, $state, 1,
		$cell_area, $widget, undef, $x+$psize+PAD, $y+$offy, $layout);

	my $field=$prop->[P_FIELD][$depth];
	$field=~s/\..*//;
	my $starfield= $Songs::Def{$field}{starfield}; #FIXME shouldn't use Songs::Def directly
	if ($gid!=FilterList::GID_ALL && $starfield)
	{	if (my $pb= Songs::Picture($gid,$starfield,'pixbuf'))
		{	# FIXME center verticaly or resize ?
			$window->draw_pixbuf( $widget->style->black_gc, $pb,0,0, $x+XPAD+$w, $y+$offy,-1,-1,'none',0,0);
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
	{	last unless $cell->{queue} && $cell->{widget}->mapped;
		my ($y,$ref)=each %{ $cell->{queue} };
		last unless $ref;
		delete $cell->{queue}{$y};
		_drawpix($cell->{widget},$cell->{window},@$ref);
		last unless scalar keys %{ $cell->{queue} };
		return 1;
	}
	delete $cell->{queue};
	delete $cell->{widget};
	delete $cell->{window};
	return $cell->{idle}=undef;
}

sub _drawpix
{	my ($widget,$window,$ctx,$cty,$gid,$psize,$h,$fieldref)=@_;
	my ($vx,$vy,$vw,$vh)=$widget->get_visible_rect->values;
	#warn "   $gid\n";
	return if $vx > $ctx+$psize || $vy > $cty+$h || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $gid\n";
	my ($x,$y)=$widget->tree_to_widget_coords($ctx,$cty);
	my $pixbuf= AAPicture::pixbuf($$fieldref,$gid, $psize,1);
	return unless $pixbuf;

	my $offy=int( ($h-$pixbuf->get_height)/2 );#center pic
	my $offx=int( ($psize-$pixbuf->get_width )/2 );
	$window->draw_pixbuf( $widget->style->black_gc, $pixbuf,0,0,
		$x+$offx, $y+$offy, -1,-1,'none',0,0);
}

package CellRendererSongsAA;
use Glib::Object::Subclass 'Gtk2::CellRenderer',
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
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my ($r1,$r2,$row,$gid)=@{ $cell->get('ref') };	#come from CellRendererSongsAA::get_value : first_row, last_row, this_row, gid
	my $field= $cell->get('aa');
	my $format=$cell->get('markup');
	my @format= $format ? (split /\n/,$format) : ();
	$format=$format[$row-$r1];
	if ($format)
	{	my ($x, $y, $width, $height)= $cell_area->values;
		my $gc= $widget->get_style->base_gc('normal');
		$window->draw_rectangle($gc, 1, $background_area->values);# if $r1 != $r2;
		my $layout=Gtk2::Pango::Layout->new( $widget->create_pango_context );
		my $markup=AA::ReplaceFields( $gid,$format,$field,::TRUE );
		$layout->set_markup($markup);
		$gc= $widget->get_style->text_gc('normal');
		$gc->set_clip_rectangle($cell_area);
		$window->draw_layout($gc, $x, $y, $layout);
		$gc->set_clip_rectangle(undef);
#		$widget->get_style->paint_layout($window, $widget->state, 0, $cell_area, $widget, undef, $x, $y, $layout);
		return;
	}

	my $gc= $widget->get_style->base_gc('normal');
	$window->draw_rectangle($gc, 1, $background_area->values);
	my($x, $y, $width, $height)= $background_area->values; #warn "$row $x, $y, $width, $height\n";
	$y-=$height*($row-$r1 - @format);
	$height*=1+$r2-$r1 - @format;
#	my $ypad=$cell->get('ypad') + $background_area->height - $cell_area->height;
#	$y+=$ypad;
	$x+=$cell->get('xpad');
#	$height-=$ypad*2;
	$width-=$cell->get('xpad')*2;
	my $s= $height > $width ? $width : $height;
	$s=200 if $s>200;

	if ( my $pixbuf= AAPicture::pixbuf($field,$gid,$s) )
	{	my $gc=Gtk2::Gdk::GC->new($window);
		$gc->set_clip_rectangle($background_area);
		$window->draw_pixbuf( $gc, $pixbuf,0,0,	$x,$y, -1,-1,'none',0,0);
	}
	elsif (defined $pixbuf)
	{	my ($tx,$ty)=$widget->widget_to_tree_coords($x,$y);#warn "$tx,$ty <= ($x,$y)\n";
		$cell->{queue}{$r1}=[$tx,$ty,$gid,$s,$field];
		$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
		$cell->{widget}||=$widget;
		$cell->{window}||=$window;
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
	{	last unless $cell->{queue} && $cell->{widget}->mapped;
		my ($r1,$ref)=each %{ $cell->{queue} };
		last unless $ref;
		delete $cell->{queue}{$r1};
		_drawpix($cell->{widget},$cell->{window},@$ref);
		last unless scalar keys %{ $cell->{queue} };
		return 1;
	}
	delete $cell->{queue};
	delete $cell->{widget};
	delete $cell->{window};
	return $cell->{idle}=undef;
}

sub _drawpix
{	my ($widget,$window,$ctx,$cty,$gid,$s,$col)=@_; #warn "$ctx,$cty,$gid,$s\n";
	my ($vx,$vy,$vw,$vh)=$widget->get_visible_rect->values;
	#warn "   $gid\n";
	return if $vx > $ctx+$s || $vy > $cty+$s || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $gid\n";
	my ($x,$y)=$widget->tree_to_widget_coords($ctx,$cty);#warn "$ctx,$cty => ($x,$y)\n";
	my $pixbuf= AAPicture::pixbuf($col,$gid, $s,1);
	return unless $pixbuf;
	$window->draw_pixbuf( Gtk2::Gdk::GC->new($window), $pixbuf,0,0, $x,$y,-1,-1,'none',0,0);
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
use Gtk2;
use base 'Gtk2::DrawingArea';

use constant
{	XPAD => 2,	YPAD => 2,
};

sub new
{	my ($class,$selectsub,$getdatasub,$activatesub,$queuesub,$menupopupsub,$displaykeysub)=@_;
	my $self = bless Gtk2::DrawingArea->new, $class;
	$self->can_focus(::TRUE);
	$self->signal_connect(expose_event	=> \&expose_cb);
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
	$self->{queuesub}=$queuesub;
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
	my $window=$self->window;
	my ($width,$height)=$window->get_size;

	if ($width<2 && !$self->{delayed}) {$self->{delayed}=1;::IdleDo('2_resizecloud'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};
	delete $::ToDo{'2_resizecloud'.$self};

	unless (keys %$href)
	{	$self->set_size_request(-1,-1);
		$self->queue_draw;
		$self->{lines}=[];
		return;
	}
	my $filterlist= ::find_ancestor($self,'FilterList');	#FIXME should get its options another way (to keep GMB::Cloud generic)
	my $scalemin= ($filterlist->{cloud_min}||5) /10;
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
	for my $key (@$list)
	{	my $layout=Gtk2::Pango::Layout->new( $self->create_pango_context );
		my $value=sprintf '%.1f', $scalemin + $scalemax*($href->{$key}-$min)/($max-$min);
		#$layout->set_text($key);
		#$layout->get_attributes->insert( Gtk2::Pango::AttrScale->new($value) ); #need recent Gtk2
		my $text= $displaykeysub ? $displaykeysub->($key) : $key;
		$layout->set_markup('<span size="'.(10240*$value).'">'.::PangoEsc($text).'</span>');
		my ($w,$h)=$layout->get_pixel_size;
		my $bl= $self->{baselines}{$h}||= $layout->get_iter->get_baseline / Gtk2::Pango->scale; #cache not needed for $Gtk2::VERSION>1.161
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
	$self->set_size_request(-1,$y);
	$self->queue_draw;
}

sub configure_cb
{	my ($self,$event)=@_;
	return if !$self->{width} || $self->{width} eq $event->width;
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

sub expose_cb
{	my ($self,$event)=@_;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)=$event->area->values;
	$exp_x2+=$exp_x1; $exp_y2+=$exp_y1;
	my $window=$self->window;
	my $style=$self->get_style;
	#my ($width,$height)=$window->get_size;
	#warn "expose_cb : $width,$height\n";
	my $state= 	$self->state eq 'insensitive'	? 'insensitive'	: 'normal';
	my $sstate= 	$self->has_focus		? 'selected'	: 'active';
	my $gc= $style->text_gc($state);
	my $bgc= $style->base_gc($state);
	my $sgc= $style->text_gc($sstate);
	my $sbgc= $style->base_gc($sstate);
	$window->draw_rectangle($bgc,::TRUE,$event->area->values); #clear the area with the base bg color
	#$style->paint_box($window,$state,'none',undef,$self,undef,$event->area->values);

	my $lines=$self->{lines};

	for (my $i=0; $i<=$#$lines; $i+=3)
	{	my ($y1,$y2,$line)=@$lines[$i,$i+1,$i+2];
		next unless $y2>$exp_y1;
		last if $y1>$exp_y2;
		for (my $j=0; $j<=$#$line; $j+=5)
		{	my ($x1,$x2,$bl,$layout,$key)=@$line[$j..$j+4];
			next unless $x2>$exp_x1;
			last if $x1>$exp_x2;
			my $gc=$gc;
			if (exists $self->{selected}{$key})
			{	$window->draw_rectangle($sbgc,1,$x1-XPAD(),$y1-YPAD(),$x2-$x1+XPAD*2,$y2-$y1+YPAD*2);
				$gc=$sgc;
			}
			$window->draw_layout($gc,$x1,$y2-$bl,$layout);
			#$window->draw_rectangle($bgc,::TRUE,$x1,$y2-$bl,$x2-$x1,$h);
			#$style->paint_box($window,$sstate,'none',undef,$self,undef,$x1,$y2-$bl,$x2-$x1,$h) if exists $self->{selected}{$key};
			#$style->paint_layout($window,(exists $self->{selected}{$key}? $sstate : $state),::FALSE,undef,$self,undef,$x1,$y2-$bl,$layout);
		}
	}
	if ($self->{lastclick}) #paint focus indicator
	{{	my ($i,$j)=@{ $self->{lastclick} };
		my ($y1,$y2,$line)=@$lines[$i,$i+1,$i+2];
		last unless $y2>$exp_y1;
		last if $y1>$exp_y2;
		my ($x1,$x2,$bl,undef,$key)=@$line[$j..$j+4];
		last unless $x2>$exp_x1;
		last if $x1>$exp_x2;
		$style->paint_focus($window, (exists $self->{selected}{$key}? $sstate : $state), undef,$self,undef, $x1-XPAD(),$y1-YPAD(),$x2-$x1+XPAD*2,$y2-$y1+YPAD*2);
	}}
	::TRUE;
}

sub button_press_cb
{	my ($self,$event)=@_;
	$self->grab_focus;
	my $but=$event->button;
	if ($but==1 && $event->type eq '2button-press')
	{	$self->{activatesub}($self);
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
	if ($but==2 && $event->type eq '2button-press')
	{	$self->{queuesub}($self);
		return 1;
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
	$self->parent->get_vadjustment->clamp_page($y1,$y2);
}

sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	if ( $key eq 'space' || $key eq 'Return' )
	{	$self->{activatesub}($self);
		return 1;
	}
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
use Gtk2;
use base 'Gtk2::DrawingArea';

use constant
{	XPAD => 2,	YPAD => 2,
};

sub new
{	my ($class,$selectsub,$getdatasub,$activatesub,$queuesub,$menupopupsub,$col,$vscroll)=@_;
	my $self = bless Gtk2::DrawingArea->new, $class;
	$self->can_focus(::TRUE);
	$self->add_events(['pointer-motion-mask','leave-notify-mask']);
	$self->{vscroll}=$vscroll;
	$vscroll->get_adjustment->signal_connect(value_changed => \&scroll,$self);
	$self->signal_connect(scroll_event	=> \&scroll_event_cb);
	$self->signal_connect(expose_event	=> \&expose_cb);
	$self->signal_connect(focus_out_event	=> \&focus_change);
	$self->signal_connect(focus_in_event	=> \&focus_change);
	$self->signal_connect(configure_event	=> \&configure_cb);
	$self->signal_connect(drag_begin	=> \&GMB::Cloud::drag_begin_cb);
	$self->signal_connect(button_press_event=> \&GMB::Cloud::button_press_cb);
	$self->signal_connect(button_release_event=> \&GMB::Cloud::button_release_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(motion_notify_event=> \&start_tooltip);	#FIXME	use set_has_tooltip and
	$self->signal_connect(leave_notify_event=> \&abort_tooltip);	#	query_tooltip instead (requires gtk+ 2.12, Gtk2 1.160)
	$self->{selectsub}=$selectsub;
	$self->{get_fill_data_sub}=$getdatasub;
	$self->{activatesub}=$activatesub;
	$self->{queuesub}=$queuesub;
	$self->{menupopupsub}=$menupopupsub;
	$self->{col}=$col;
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
	my $window=$self->window;
	my ($width,$height)=$window->get_size;
	if ($width<2 && !$self->{delayed}) { $self->{delayed}=1; ::IdleDo('2_resizemosaic'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};
	delete $::ToDo{'2_resizemosaic'.$self};
	$self->{width}=$width;

	my $list=$self->{list};
	($list)= $self->{get_fill_data_sub}($self) unless $samelist && $samelist eq 'samelist';

	my $filterlist= ::find_ancestor($self,'FilterList');	#FIXME should get its options another way
	my $mpsize=$filterlist->{mpicsize}||64;
	$self->{picsize}=$mpsize;
	$self->{hsize}=$mpsize;
	$self->{vsize}=$mpsize;

	my $nw= int($width / ($self->{hsize}+2*XPAD)) || 1;
	my $nh= int(@$list/$nw);
	my $nwlast= @$list % $nw;
	$nh++ if $nwlast;
	$nwlast=$nw unless $nwlast;
	$self->{dim}=[$nw,$nh,$nwlast];
	$self->{list}=$list;
	#$self->set_size_request(-1,$nh*($self->{vsize}+2*YPAD));
	$self->{viewsize}[1]= $nh*($self->{vsize}+2*YPAD);
	$self->{viewwindowsize}=[$self->window->get_size];
	$self->update_scrollbar;
	$self->queue_draw;
	$self->start_tooltip;
}
sub update_scrollbar
{	my $self=$_[0];
	my $scroll= $self->{vscroll};
	my $pagesize=$self->{viewwindowsize}[1]||0;
	my $upper=$self->{viewsize}[1]||0;
	my $adj=$scroll->get_adjustment;
	my $oldpos= $adj->upper ? ($adj->page_size/2+$adj->value) / $adj->upper : 0;
	$adj->page_size($pagesize);
	if ($upper>$pagesize)	{$scroll->show; $adj->upper($upper); $scroll->queue_draw; }
	else			{$scroll->hide; $adj->upper(0);}
	$adj->step_increment($pagesize*.125);
	$adj->page_increment($pagesize*.75);
	my $newval= $oldpos*$adj->upper - $adj->page_size/2;
	$newval=$adj->upper-$pagesize if $newval > $adj->upper-$pagesize;
	$adj->set_value($newval);
}
sub scroll_event_cb
{	my ($self,$event,$pageinc)=@_;
	my $dir= ref $event ? $event->direction : $event;
	$dir= $dir eq 'up' ? -1 : $dir eq 'down' ? 1 : 0;
	return unless $dir;
	my $adj=$self->{vscroll}->get_adjustment;
	my $max= $adj->upper - $adj->page_size;
	my $value= $adj->value + $dir* ($pageinc? $adj->page_increment : $adj->step_increment);
	$value=$max if $value>$max;
	$value=0 if $value<0;
	$adj->set_value($value);
	1;
}
sub scroll
{	my ($adj,$self)=@_;
	my $new=int $adj->value;
	my $old=$self->{lastdy};
	return if $new==$old;
	$self->{lastdy}=$new;
	$self->window->scroll(0,$old-$new); #copy still valid parts and queue_draw new parts
}

sub show_tooltip
{	my $self=$_[0];
	Glib::Source->remove(delete $self->{tooltip_t}) if $self->{tooltip_t};
	$self->{tooltip_t}=Glib::Timeout->add(5000, \&abort_tooltip,$self);

	my ($window,$px,$py)=Gtk2::Gdk::Display->get_default->get_window_at_pointer;
	return 0 unless $window && $window==$self->window;
	my ($i,$j,$key)=$self->coord_to_index($px,$py);
	return 0 unless defined $key;
	my $win=$self->{tooltip_w}=Gtk2::Window->new('popup');
	#$win->{key}=$key;
	#$win->set_border_width(3);
	my $label=Gtk2::Label->new;
	$label->set_markup(AA::ReplaceFields($key,"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",$self->{col},1));
	my $request=$label->size_request;
	my ($x,$y,$w,$h)=$self->index_to_rect($i,$j);
	my ($rx,$ry)=$self->window->get_origin;
	$x+= $rx + $w/2 - $request->width/2;
	$y+= $ry + $h+YPAD+1;

	my $screen=$self->get_screen;
	my $monitor=$screen->get_monitor_at_window($self->window);
	my (undef,undef,$xmax,$ymax)=$screen->get_monitor_geometry($monitor)->values;
	$xmax-=$request->width;
	$ymax-=$request->height;
	$x=$xmax if $x>$xmax;
	$y-=$h+$request->height if $y>$ymax;

	my $frame=Gtk2::Frame->new;
	$frame->add($label);
	$win->add($frame);
	$win->move($x,$y);
	$win->show_all;
	return 0;
}

sub start_tooltip
{	my ($self,$event)=@_;
	my $timeout= $self->{tooltip_browsemode} ? 100 : 1000;
	$self->abort_tooltip;
	$self->{tooltip_t}=Glib::Timeout->add($timeout, \&show_tooltip,$self);
	return 0;
}
sub abort_tooltip
{	my $self=$_[0];
	Glib::Source->remove(delete $self->{tooltip_t}) if $self->{tooltip_t};
	if ($self->{tooltip_w})
	{	$self->{tooltip_browsemode}=1;
		Glib::Source->remove($self->{tooltip_t2}) if $self->{tooltip_t2};
		$self->{tooltip_t2}=Glib::Timeout->add(500, sub{$_[0]{tooltip_browsemode}=$_[0]{tooltip_t2}=0;} ,$self);
		$self->{tooltip_w}->destroy;
	}
	$self->{tooltip_w}=undef;
	0;
}

sub configure_cb		## FIXME I think it redraws everything even when it's not needed
{	my ($self,$event)=@_;
	return unless $self->{width};
	$self->{viewwindowsize}=[$event->width,$event->height];
	my $iw= $self->{hsize}+2*XPAD;
	if ( int($self->{width}/$iw) == int($event->width/$iw))
	{	$self->update_scrollbar;
		return;
	}
	$self->reset;
	::IdleDo('2_resizecloud'.$self,100,\&Fill,$self,'samelist');
}

sub expose_cb
{	my ($self,$event)=@_;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)=$event->area->values;
	$exp_x2+=$exp_x1; $exp_y2+=$exp_y1;
	my $dy=int $self->{vscroll}->get_adjustment->value;
	$self->start_tooltip if $self->{lastdy}!=$dy;
	$self->{lastdy}=$dy;
	my $window=$self->window;
	my $col=$self->{col};
	my $style=$self->get_style;
	#my ($width,$height)=$window->get_size;
	#warn "expose_cb : $width,$height\n";
	my $state= 	$self->state eq 'insensitive'	? 'insensitive'	: 'normal';
	my $sstate= 	$self->has_focus		? 'selected'	: 'active';
	#my $gc= $style->text_gc($state);
	my $bgc= $style->base_gc($state);
	#my $sgc= $style->text_gc($sstate);
	my $sbgc= $style->base_gc($sstate);
	$window->draw_rectangle($bgc,::TRUE,$event->area->values); #clear the area with the base bg color
	#$style->paint_flat_box( $window,$state,'none',$event->area,$self,'',$event->area->values);

	return unless $self->{list};
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $list=$self->{list};
	my $vsize=$self->{vsize};
	my $hsize=$self->{hsize};
	my $picsize=$self->{picsize};
	my $i1=int($exp_x1/($hsize+2*XPAD));
	my $i2=int($exp_x2/($hsize+2*XPAD));
	my $j1=int(($dy+$exp_y1)/($vsize+2*YPAD));
	my $j2=int(($dy+$exp_y2)/($vsize+2*YPAD));
	$i2=$nw-1 if $i2>=$nw;
	$j2=$nh-1 if $j2>=$nh;
	for my $j ($j1..$j2)
	{	my $y=$j*($vsize+2*YPAD)+YPAD - $dy;  #warn "j=$j y=$y\n";
		$i2=$nwlast-1 if $j==$nh-1;
		for my $i ($i1..$i2)
		{	my $pos=$i+$j*$nw;
			#last if $pos>$#$list;
			my $key=$list->[$pos];
			my $x=$i*($hsize+2*XPAD)+XPAD;
			my $state=$state;
			if (exists $self->{selected}{$key})
			{	$window->draw_rectangle($sbgc,1,$x-XPAD(),$y-YPAD(),$hsize+XPAD*2,$vsize+YPAD*2);
				#$state=$sstate;
				#$style->paint_flat_box( $window,$state,'none',$event->area,$self,'',
				#			$x-XPAD(),$y-YPAD(),$hsize+XPAD*2,$vsize+YPAD*2 );
			}
			#$window->draw_rectangle($style->text_gc($state),1,$x+20,$y+20,24,24); #DEBUG
			my $pixbuf= AAPicture::draw($window,$x,$y,$col,$key,$picsize);
			if ($pixbuf) {}
			elsif (defined $pixbuf)
			{	#warn "add idle\n" unless $self->{idle};
				$self->{idle}||=Glib::Idle->add(\&idle,$self);
				$self->{window}||=$window;
				$self->{queue}{$i+$j*$nw}=[$x,$y+$dy,$key,$picsize];
			}
			else
			{	my $layout=Gtk2::Pango::Layout->new( $self->create_pango_context );
				#$layout->set_text($key);
				#$layout->set_markup('<small>'.::PangoEsc($key).'</small>');
				$layout->set_markup(AA::ReplaceFields($key,"<small>%a</small>",$self->{col},1));
				$layout->set_wrap('word-char');
				$layout->set_width($hsize * Gtk2::Pango->scale);
				$layout->set_height($vsize * Gtk2::Pango->scale);
				$layout->set_ellipsize('end');
				$style->paint_layout($window, $state, 1,
					Gtk2::Gdk::Rectangle->new($x,$y,$hsize,$vsize), $self, undef, $x, $y, $layout);
			}
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
	$y+=int $self->{vscroll}->get_adjustment->value;
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
	$y-=int $self->{vscroll}->get_adjustment->value;
	return $x,$y,$self->{hsize},$self->{vsize};
}

sub redraw_keys
{	my ($self,$keyhash)=@_;
	return unless keys %$keyhash;
	my $hsize2=$self->{hsize}+2*XPAD;
	my $vsize2=$self->{vsize}+2*YPAD;
	my $y=int $self->{vscroll}->get_adjustment->value;
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
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	if ( $key eq 'space' || $key eq 'Return' )
	{	$self->{activatesub}($self);
		return 1;
	}
	my $pos=0;
	$pos=$self->{lastclick} if $self->{lastclick};
	my ($nw,$nh,$nwlast)=@{$self->{dim}};
	my $page= int($self->{vscroll}->get_adjustment->page_size / ($self->{vsize}+2*YPAD));
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
	else {return 0}
	if	($i<0)		{$j--; $i= $j<0 ? 0 : $nw-1}
	elsif	($i>=$nw)	{$j++; $i= $j>=$nh ? $nwlast-1 : 0 }
	if	($j<0)		{$j=0;$i=0}
	elsif	($j>=$nh-1)	{$j=$nh-1; $i=$nwlast-1 }
	$self->key_selected($event,$i,$j);
	return 1;
}

sub reset
{	my $self=$_[0];
	#delete $self->{list};
	delete $self->{queue};
	Glib::Source->remove( $self->{idle} ) if $self->{idle};
	delete $self->{idle};
}

sub idle
{	my $self=$_[0];#warn " ...idle...\n";
	{	last unless $self->{queue} && $self->mapped;
		my ($y,$ref)=each %{ $self->{queue} };
		last unless $ref;
		delete $self->{queue}{$y};
		_drawpix($self,$self->{window},@$ref);
		last unless scalar keys %{ $self->{queue} };
		return 1;
	}
	delete $self->{queue};
	delete $self->{window};#warn "...idle END\n";
	return $self->{idle}=undef;
}

sub _drawpix
{	my ($self,$window,$x,$y,$key,$s)=@_;
	my $vadj=$self->{vscroll}->get_adjustment;
	my $dy=int $vadj->get_value;
	my $page=$vadj->page_size;
	return if $dy > $y+$s || $dy+$page < $y; #no longer visible
#warn " drawing $key\n";
	AAPicture::draw($window,$x,$y-$dy,$self->{col},$key, $s,1);
}

package GMB::ISearchBox;	#interactive search box (search as you type)
use Gtk2;
use base 'Gtk2::HBox';

our %OptCodes=
(	casesens => 'i',	onlybegin => 'b',	onlyword => 'w',
);
our @OptionsMenu=
(	{ label => _"Case-sensitive",	code => sub { $_[0]{self}{casesens}^=1; $_[0]{self}->changed; },	check => sub { $_[0]{self}{casesens}; }, },
	{ label => _"Begin with",	code => sub { $_[0]{self}{onlybegin}^=1; $_[0]{self}{onlyword}=0; $_[0]{self}->changed;},	check => sub { $_[0]{self}{onlybegin}; }, },
	{ label => _"Words that begin with",	code => sub { $_[0]{self}{onlyword}^=1;$_[0]{self}{onlybegin}=0; $_[0]{self}->changed;},		check => sub { $_[0]{self}{onlyword}; }, },
	{ label => _"Fields",		submenu => sub { return {map { $_=>Songs::FieldName($_) } Songs::StringFields}; }, submenu_reverse => 1,
	  check => sub { $_[0]{self}{fields}; },	test => sub { !$_[0]{type} },
	  code => sub { my $toggle=$_[1]; my $l=$_[0]{self}{fields}; my $n=@$l; @$l=grep $toggle ne $_, @$l; push @$l,$toggle if @$l==$n; @$l=('title') unless @$l; $_[0]{self}->changed; }, #toggle selected field
	},
);

sub new					##currently the returned widget must be put in ->{isearchbox} of a parent widget, and this parent must have the array to search in ->{array} and have the methods get_cursor_row and set_cursor_to_row. And also select_by_filter for SongList/SongTree
{	my ($class,$opt,$type,$nolabel)=@_;
	my $self=bless Gtk2::HBox->new(0,0), $class;
	$self->{type}=$type;

	#restore options
	my $optcodes= $opt->{isearch} || '';
	for my $key (keys %OptCodes)
	{	$self->{$key}=1 if index($optcodes, $OptCodes{$key}) !=-1;
	}
	unless ($type) { $self->{fields}= [split /\|/, ($opt->{isearchfields} || 'title')]; }

	$self->{entry}=my $entry=Gtk2::Entry->new;
	$entry->signal_connect( changed => \&changed );
	my $select=::NewIconButton('gtk-index',	undef, \&select,'none',_"Select matches");
	my $next=::NewIconButton('gtk-go-down',	($nolabel ? undef : _"Next"),	 \&button_cb,'none');
	my $prev=::NewIconButton('gtk-go-up',	($nolabel ? undef : _"Previous"),\&button_cb,'none');
	$prev->{is_previous}=1;
	my $label=Gtk2::Label->new(_"Find :");
	my $options=Gtk2::Button->new;
	$options->add(Gtk2::Image->new_from_stock('gtk-preferences','menu'));
	$options->signal_connect( button_press_event => \&PopupOpt );
	$options->set_relief('none');
	$options->set_tooltip_text(_"options");

	$self->pack_start($label,0,0,2) unless $nolabel;
	$self->add($entry);
	#$_->set_focus_on_click(0) for $prev,$next,$options;
	$self->pack_start($_,0,0,0) for $prev,$next;
	$self->pack_start($select,0,0,0) unless $self->{type};
	$self->pack_end($options,0,0,0);
	$self->show_all;
	$self->set_no_show_all(1);
	$self->hide;

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
	my $entry=$self->{entry};
	if ($mode<1)
	{	$entry->modify_base('normal', undef );
		$entry->modify_text('normal', undef );
	}
	else
	{	$entry->modify_base('normal', $entry->style->bg('selected') );
		$entry->modify_text('normal', $entry->style->text('selected') );
	}

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
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $entry=$self->{entry};
	my $text=$entry->get_text;
	if ($text eq '')
	{	$self->{searchsub}=undef;
		$self->set_colors(0);
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
	else	# #search gid of type $type
	{	my $action= $self->{casesens} ? 'gid_search' : 'gid_isearch';
		my $code= Songs::Code($type,$action, GID => '$array->[$row]', RE => $re);
		$self->{searchsub}= eval 'sub { my $array=$_[0]; my $rows=$_[1]; for my $row (@$rows) { return $row if '.$code.'; } return undef; }';
	}
	if ($@) { warn "Error compiling search code : $@\n"; $self->{searchsub}=undef; }
	$self->search(0);
}

sub select
{	my $widget=$_[0];
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $parent=$self;
	$parent=$parent->parent until $parent->{isearchbox};	#FIXME could be better, maybe pass a package name to new and use ::find_ancestor($self,$self->{targetpackage});
	$parent->select_by_filter($self->{filter}) if $self->{filter};
}
sub button_cb
{	my $widget=$_[0];
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $dir= $widget->{is_previous} ? -1 : 1;
	$self->search($dir);
}
sub search
{	my ($self,$direction)=@_;
	my $search=$self->{searchsub};
	return unless $search;
	my $parent=$self;
	$parent=$parent->parent until $parent->{isearchbox};	#FIXME could be better, maybe pass a package name to new and use ::find_ancestor($self,$self->{targetpackage});
	my $array= $parent->{array}; 				#FIXME could be better
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

sub PopupOpt
{	my ($widget,$event)=@_;
	my $self=::find_ancestor($widget,__PACKAGE__);
	::PopupContextMenu(\@OptionsMenu, { self=>$self, usemenupos => 1,} );
	return 1;
}

package SongTree::ViewVBox;
use Glib::Object::Subclass
Gtk2::VBox::,
	signals => {
		set_scroll_adjustments => {
			class_closure => sub {},
			flags	      => [qw(run-last action)],
			return_type   => undef,
			param_types   => [Gtk2::Adjustment::,Gtk2::Adjustment::],
		},
	},
	#properties => [Glib::ParamSpec->object ('hadjustment','hadj','', Gtk2::Adjustment::, [qw/readable writable construct/] ),
	#		Glib::ParamSpec->object ('vadjustment','vadj','', Gtk2::Adjustment::, [qw/readable writable construct/] )],
	;


package SongTree;
use Gtk2;
use base 'Gtk2::HBox';
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
	my $self = bless Gtk2::HBox->new(0,0), $class;
	#my $self = bless Gtk2::Frame->new, $class;
	#$self->set_shadow_type('etched-in');
	#my $frame=Gtk2::Frame->new;# $frame->set_shadow_type('etched-in');

	#use default options for this songlist type
	my $name= 'songtree_'.$opt->{name}; $name=~s/\d+$//;
	my $default= $::Options{"DefaultOptions_$name"} || {};

	%$opt=( @DefaultOptions, %$default, %$opt );
	$self->{$_}=$opt->{$_} for qw/headclick songxpad songypad no_typeahead grouping/;

	#create widgets used to draw the songtree as a treeview, would be nice to do without but it's not possible currently
	$self->{stylewidget}=Gtk2::TreeView->new;
	$self->{stylewparent}=Gtk2::VBox->new; $self->{stylewparent}->add($self->{stylewidget}); #some style engines (gtk-qt) call ->parent on the parent => Gtk-CRITICAL messages if stylewidget doesn't have a parent. And needs to hold a reference to it or bad things happen
	for my $i (1,2,3)
	{	my $column=Gtk2::TreeViewColumn->new;
		my $label=Gtk2::Label->new;
		$column->set_widget($label);
		$self->{stylewidget}->append_column($column);
		my $button=::find_ancestor($label,'Gtk2::Button');
		$self->{'stylewidget_header'.$i}=$button; #must be a button which has a treeview for parent
		#$button->remove($button->child); #don't need the child
	}

	$self->{isearchbox}=GMB::ISearchBox->new($opt);
	my $view=$self->{view}=Gtk2::DrawingArea->new;
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('automatic','automatic');
	$sw->set_shadow_type('etched-in');
	::set_biscrolling($sw);
	$self->CommonInit($opt);

	my $vbox=SongTree::ViewVBox->new;
	$sw->add($vbox);
	$self->add($sw);
	$self->{headers}=SongTree::Headers->new($sw->get_hadjustment) unless $opt->{headers} eq 'off';
	$self->{vadj}=$sw->get_vadjustment;
	$self->{hadj}=$sw->get_hadjustment;
	$vbox->pack_start($self->{headers},0,0,0) if $self->{headers};
	$vbox->pack_end($self->{isearchbox},0,0,0);
	$vbox->add($view);
	$view->can_focus(::TRUE);
	$self->{DefaultFocus}=$view;
	$self->{$_}->signal_connect(value_changed => sub {$self->has_scrolled($_[1])},$_) for qw/hadj vadj/;
	$self->signal_connect(scroll_event	=> \&scroll_event_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(destroy		=> \&destroy_cb);
	$view->signal_connect(expose_event	=> \&expose_cb);
	$view->signal_connect(focus_in_event	=> sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->{isearchbox}->hide; 0; });
	$view->signal_connect(focus_in_event	=> \&focus_change);
	$view->signal_connect(focus_out_event	=> \&focus_change);
	$view->signal_connect(configure_event	=> \&configure_cb);
	$view->signal_connect(drag_begin	=> \&drag_begin_cb);
	$view->signal_connect(drag_leave	=> \&drag_leave_cb);
	$view->signal_connect(button_press_event=> \&button_press_cb);
	$view->signal_connect(button_release_event=> \&button_release_cb);

	if (my $tip=$opt->{rowtip} and *Gtk2::Widget::set_has_tooltip{CODE})  # requires gtk+ 2.12, Gtk2 1.160
	{	$view->set_has_tooltip(1);
		$tip= "<b><big>%t</big></b>\\nby <b>%a</b>\\nfrom <b>%l</b>" if $tip eq '1';
		$self->{rowtip}= $tip;
		$view->signal_connect(query_tooltip=> \&query_tooltip_cb);
	}

	::Watch($self,	CurSongID	=> \&CurSongChanged);
	::Watch($self,	SongArray	=> \&SongArray_changed_cb);
	::Watch($self,	SongsChanged	=> \&SongsChanged_cb);

	::set_drag($view,
	 source=>[::DRAG_ID,sub { my $view=$_[0]; my $self=::find_ancestor($view,__PACKAGE__); return ::DRAG_ID,$self->GetSelectedIDs; }],
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
	$self->update_columns if $self->{ready};
}
sub update_columns
{	my ($self,$nosavepos)=@_;
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
		$savedpos=$self->coord_to_path(0,int($self->{vadj}->page_size/2)) unless $nosavepos;
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
	$self->{headers}->update if $self->{headers};
}
sub set_head_columns
{	my ($self,$grouping)=@_;
	$grouping=$self->{grouping} unless defined $grouping;
	$self->{grouping}=$grouping;
	my @cols= $grouping=~m#([^|]+\|[^|]+)(?:\||$)#g; #split into pairs : "word|word"
	my $savedpos= $self->coord_to_path(0,int($self->{vadj}->page_size/2)) if $self->{ready}; #save vertical pos
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

sub GetSelectedRows
{	my $self=$_[0];
	my $songarray=$self->{array};
	return [grep vec($self->{selected},$_,1), 0..$#$songarray];
}

sub focus_change
{	my $view=$_[0];
	#my $sel=$self->{selected};
	#return unless keys %$sel;
	#FIXME could redraw only selected rows
	$view->queue_draw;
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
	{	my $adj=	$self->{ (qw/hadj vadj/)[$i] };
		my $pagesize=	$self->{viewwindowsize}[$i] ||0;
		my $upper=	$self->{viewsize}[$i] ||0;
		$adj->page_size($pagesize);
		$adj->upper($upper);
		$adj->step_increment($pagesize*.125);
		$adj->page_increment($pagesize*.75);
		if ($adj->value > $adj->upper-$pagesize) {$adj->set_value($adj->upper-$pagesize);}
		$adj->changed;
	}
}
sub has_scrolled
{	my ($self,$adj)=@_;
	delete $self->{queue};
	delete $self->{action_rectangles};
	$self->{view}->queue_draw;# FIXME replace by something like $self->{view}->window->scroll($xold-$xnew,$yold-$ynew); (must be integers), will need to clean up $self->{action_rectangles}
}

sub configure_cb
{	my ($view,$event)=@_;
	my $self=::find_ancestor($view,__PACKAGE__);
	$self->{viewwindowsize}=[$event->width,$event->height];
	$self->updateextrawidth;
	$self->update_scrollbar;
	1;
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
	my $reset;
	my $selected=\$self->{selected};
	if ($action eq 'sort')
	{	my ($sort,$oldarray)=@extra;
		$self->{'sort'}=$sort;
		my @selected=grep vec($$selected,$_,1), 0..$#$songarray;
		my @order;
		$order[ $songarray->[$_] ]=$_ for reverse 0..$#$songarray; #reverse so that in case of duplicates ID, $order[$ID] is the first row with this $ID
		my @IDs= map $oldarray->[$_], @selected;
		@selected= map $order[$_]++, @IDs; # $order->[$ID]++ so that in case of duplicates ID, the next row (with same $ID) are used
		$self->{headers}->update if $self->{headers}; #to update sort indicator
		$$selected=''; vec($$selected,$_,1)=1 for @selected;
		$self->{new_expand_state}=0;
		$self->{lastclick}=$self->{startgrow}=-1;
		#center on a song ?
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
			vec($$selected,$#$songarray,1)||=0;
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
		$self->{selected}=''; #clear selection
		$self->{lastclick}=$self->{startgrow}=-1;
		if ($action eq 'replace')
		{	$self->{new_expand_state}=0;
			$reset=1;
		}
	}
	$self->BuildTree;
	if ($reset)
	{	$self->{vadj}->set_value(0);
		$self->FollowSong if $self->{follow};
	}
	::HasChanged('Selection_'.$self->{group});
	$self->Hide(!scalar @$songarray) if $self->{hideif} eq 'empty';
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
	my $max= $adj->upper - $adj->page_size;
	my $value= $adj->value + $dir* ($pageinc? $adj->page_increment : $adj->step_increment);
	$value=$max if $value>$max;
	$value=0    if $value<0;
	$adj->set_value($value);
	1;
}
sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	my $unicode=Gtk2::Gdk->keyval_to_unicode($event->keyval); # 0 if not a character
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'];
	my $shift=$state * ['shift-mask'];
	my $row= $self->{lastclick};
	$row=0 if $row<0;
	my $list=$self->{array};
	if	($key eq 'space' || $key eq 'Return')
					{ $self->Activate($row,1); }
	elsif	($key eq 'Up')		{ $row-- if $row>0;	 $self->song_selected($event,$row); }
	elsif	($key eq 'Down')	{ $row++ if $row<$#$list;$self->song_selected($event,$row); }
	elsif	($key eq 'Home')	{ $self->song_selected($event,0); }
	elsif	($key eq 'End')		{ $self->song_selected($event,$#$list); }
	elsif	($key eq 'Left')	{ $self->scroll_event_cb('left'); }
	elsif	($key eq 'Right')	{ $self->scroll_event_cb('right'); }
	elsif	($key eq 'Page_Up')	{ $self->scroll_event_cb('up',1); }
	elsif	($key eq 'Page_Down')	{ $self->scroll_event_cb('down',1); }
	elsif	(lc$key eq 'a' && $ctrl)							#ctrl-a : select-all
		{ vec($self->{selected},$_,1)=1 for 0..$#$list; $self->UpdateSelection;}
	elsif	(lc$key eq 'f' && $ctrl) { $self->{isearchbox}->begin(); }			#ctrl-f : search
	elsif	(lc$key eq 'g' && $ctrl) { $self->{isearchbox}->search($shift ? -1 : 1);}	#ctrl-g : next/prev match
	elsif	(!$self->{no_typeahead} && $unicode && !($state * [qw/control-mask mod1-mask mod4-mask/]))
	{	$self->{isearchbox}->begin( chr $unicode );	#begin typeahead search
	}
	else	{return 0}
	return 1;
}

sub expose_cb
{	my ($view,$event)=@_;# my $time=times;
	my $self=::find_ancestor($view,__PACKAGE__);
	my $expose=$event->area;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)=$expose->values;
	$exp_x2+=$exp_x1; $exp_y2+=$exp_y1;
	my $window=$view->window;
	#my $style=Gtk2::Rc->get_style_by_paths($self->{stylewidget}->get_settings, '.GtkTreeView', '.GtkTreeView','Gtk2::TreeView');
	#$style=$style->attach($window);
	my $style=$self->get_style;
	my $nstate= $self->state eq 'insensitive' ? 'insensitive' : 'normal';
	#my $sstate=$view->has_focus ? 'selected' : 'active';
	my $sstate='selected';	#Treeview uses only state= normal, insensitive or selected
	$self->{stylewidget}->has_focus($view->has_focus); #themes engine check if the widget has focus
	my $selected=	\$self->{selected};
	my $list=	$self->{array};
	my $songcells=	$self->{cells};
	my $headcells=	$self->{headcells};
	my $vsizesong=	$self->{vsizesong};
	#$window->draw_rectangle($style->base_gc($state), 1, $expose->values);
	my $gc=$style->base_gc($nstate);
	$window->draw_rectangle($gc, 1, $expose->values);
	unless ($list && @$list)
	{	$self->DrawEmpty($window);
		return 1;
	}

	my $xadj=int $self->{hadj}->value;
	my $yadj=int $self->{vadj}->value;
	my @next;
	my ($depth,$i)=(0,1);
	my ($x,$y)=(0-$xadj, 0-$yadj);
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
		  {  my $clip=$expose->intersect( Gtk2::Gdk::Rectangle->new( $x+$cell->{x},$y,$cell->{width},$bh) );
		     if ($clip)
		     {	my $start= $self->{TREE}{lastrows}[$depth][$i-1]+1;
			my $end=   $self->{TREE}{lastrows}[$depth][$i];
			my %arg=
			(	self	=> $cell,	widget	=> $self,	style	=> $style,
				window	=> $window,	clip	=> $clip,	state	=> $nstate,
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
			$self->{queue}{$qid}=$q if $q;
		      }
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
				my $state= vec($$selected,$row,1) ? $sstate : $nstate;
				my $detail= $odd? 'cell_odd_ruled' : 'cell_even_ruled';
				#detail can have these suffixes (in order) : _ruled _sorted _start|_last|_middle
				$style->paint_flat_box( $window,$state,'none',$expose,$self->{stylewidget},$detail,
							$songs_x,$y,$songs_width,$vsizesong );
				my $x=$songs_x;
				for my $cell (@$songcells)
				{ my $width=$cell->{width};
				  $width+=$self->{extra} if $cell->{last};
				  my $clip=$expose->intersect( Gtk2::Gdk::Rectangle->new($x,$y,$width,$vsizesong) );
				  if ($clip)
				  {	my %arg=
					(state	=> $state,	self	=> $cell,	widget	=> $self,
					 style	=> $style,	window	=> $window,	clip	=> $clip,
					 ID	=> $ID,		firstrow=> $first,	lastrow => $last, row=>$row,
					 vx	=> $xadj+$x,	vy	=> $yadj+$y,
					 x	=> $x,		y	=> $y,
					 w	=> $width,	h	=> $vsizesong,
					 odd	=> $odd,
					);
					my $q= $cell->{draw}(\%arg);
					my $qid=$x.'s'.$y;
					delete $self->{queue}{$qid};
					$self->{queue}{$qid}=$q if $q;
				  }
				  $x+=$width;
				}
				if (exists $view->{drag_highlight} && $view->{drag_highlight}==$row)
				{	my $gc=$style->fg_gc('normal');
					$gc->set_clip_rectangle($expose);
					$window->draw_line($gc,$songs_x,$y,$x,$y);
					$gc->set_clip_rectangle(undef);
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
	{	last unless $self->{queue} && $self->mapped;
		my ($qid,$ref)=each %{ $self->{queue} };
		last unless $ref;
		my $context=$ref->[-1];
		my $qsub=shift @$ref;
		delete $self->{queue}{$qid} if @$ref<=1;
		my $hadj=$self->{hadj}; $context->{x}= $context->{vx} - int($hadj->value);
		my $vadj=$self->{vadj}; $context->{y}= $context->{vy} - int($vadj->value);
		&$qsub unless	   $context->{x}+$context->{w}<0
				|| $context->{y}+$context->{h}<0
				|| $context->{x}>$hadj->page_size
				|| $context->{y}>$vadj->page_size;
		last unless scalar keys %{ $self->{queue} };
		return 1;
	}
	delete $self->{queue};
	return $self->{idle}=undef;
}

sub coord_to_path
{	my ($self,$x,$y)=@_;
	$x+=int($self->{hadj}->value);
	$y+=int($self->{vadj}->value);
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
{	my ($self,$row)=@_;
	my $y=0;
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
{	my ($self,$row)=@_;
	my $y=$self->row_to_y($row);
	return unless defined $y;
	my $x= $self->{songxoffset} - int($self->{hadj}->value);
	$y-= $self->{vadj}->value;
	return Gtk2::Gdk::Rectangle->new($x, $y, $self->{songswidth}, $self->{vsizesong});
}
sub update_row
{	my ($self,$row)=@_;
	my $rect=$self->row_to_rect($row);
	my $gdkwin= $self->{view}->window;
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
{	my ($self,$up)=@_;
	my $adj=$self->{vadj};
	if ($up)	{ $adj->set_value(0); }
	else		{ $adj->set_value($adj->upper); }
}

sub drag_received_cb
{	my ($view,$type,$dest,@IDs)=@_;
	if ($type==::DRAG_FILE) #convert filenames to IDs
	{	@IDs=::FolderToIDs(1,0,map ::decode_url($_), @IDs);
		return unless @IDs;
	}
	my $self=::find_ancestor($view,__PACKAGE__);
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
	my $self=::find_ancestor($view,__PACKAGE__);

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
	{	my $self=::find_ancestor($view,__PACKAGE__);
		$self->scroll_event_cb($s);
		drag_motion_cb($view,$view->{context}, ($view->window->get_pointer)[1,2], 0 );
		return 1;
	}
	else
	{	delete $view->{scrolling};
		return 0;
	}
}
sub drag_leave_cb
{	my $view=$_[0];
	my $self=::find_ancestor($view,__PACKAGE__);
	my $row=delete $view->{drag_highlight};
	$self->update_row($row) if defined $row;
}

sub expand_colapse
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
	$view->grab_focus;
	my $self=::find_ancestor($view,__PACKAGE__);
	my $but=$event->button;
	my $answer=$self->coord_to_path($event->coords);
	my $row=$answer->{row};
	my $depth=$answer->{depth};
	return 0 unless @{$self->{array}}; #empty list
	if ((my $ref=$self->{action_rectangles}) && 0) #TESTING
	{	my $x= $event->x + int($self->{hadj}->value);
		my $y= $event->y + int($self->{vadj}->value);
		my $found;
		for my $dim (keys %$ref)
		{	my ($rx,$ry,$rw,$rh)=split /,/,$dim;
			next if $ry>$y || $ry+$rh<$y || $rx>$x || $rx+$rw<$x;
			$found=$ref->{$dim};
		}
		if ($found) {warn "actions : $_ => $found->{$_}" for keys %$found}
	}
	if ($but!=3 && $event->type eq '2button-press')
	{	return 0 unless defined $row;
		$self->Activate($row,$but);
		return 1;
	}
	if ($but==3)
	{	if (!defined $depth && !vec($self->{selected},$row,1))
		{	$self->song_selected($event,$row);
		}
		my @IDs=$self->GetSelectedIDs;
		my $list= $self->{array};
		my %args=(self => $self, mode => $self->{type}, IDs => \@IDs, listIDs => $list);
		::PopupContextMenu(\@::SongCMenu,\%args ) if @$list;

		return 1;
	}
	else# ($but==1)
	{	return 0 unless $answer;
		if (defined $depth && $answer->{area} eq 'head' || $answer->{area} eq 'collapsed')
		{	if ($answer->{area} eq 'head' && $self->{headclick} eq 'select')
			 { $self->song_selected($event,$answer->{start},$answer->{end}); return 0}
			else { $self->expand_colapse($depth,$answer->{branch}); }
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
	return 0 unless $event->button==1 && $view->{pressed};
	$view->{pressed}=undef;
	my $self=::find_ancestor($view,__PACKAGE__);
	my $answer=$self->coord_to_path($event->coords);
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
	if ($not_if_visible) {return if $y1-$vadj->value>0 && $y1+$vsize-$vadj->value-$vadj->page_size<0;}
	if ($center)
	{	my $half= $center * $vadj->page_size/2;
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
	if ($array->IsIn($::SongID))
	{	my $row= ::first { $array->[$_]==$::SongID } 0..$#$array;
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
	my $self=::find_ancestor($view,__PACKAGE__);
	my $path=$self->coord_to_path($x,$y);
	my $row=$path->{row};
	return 0 unless defined $row;
	my $ID=$self->{array}[$row];
	my $markup= ::ReplaceFieldsAndEsc($ID,$self->{rowtip});
	$tooltip->set_markup($markup);
	my $rect=$self->row_to_rect($row);
	$tooltip->set_tip_area($rect) if $rect;
	1;
}

package SongTree::Headers;
use Gtk2;
use base 'Gtk2::Viewport';
use constant TREE_VIEW_DRAG_WIDTH => 6;

our @ColumnMenu=
(	{ label => _"_Sort by",		submenu => sub { Browser::make_sort_menu($_[0]{songtree}); }
	},
	{ label => _"Set grouping",	submenu => sub {$::Options{SavedSTGroupings}}, check =>sub { $_[0]{songtree}{grouping} },
	  code => sub { $_[0]{songtree}->set_head_columns($_[1]); },
	},
	{ label => _"Edit grouping ...",	code => sub { my $songtree=$_[0]{songtree}; ::EditSTGroupings($songtree,$songtree->{grouping},undef,sub{ $songtree->set_head_columns($_[0]) if defined $_[0]; }); },
	},
	{ label => _"_Insert column",	submenu => sub
		{	my %names; $names{$_}= $SongTree::STC{$_}{menutitle}||$SongTree::STC{$_}{title} for keys %SongTree::STC;
			delete $names{$_->{colid}} for grep $_->{colid}, $_[0]{self}->child->get_children;
			return \%names;
		},	submenu_reverse =>1,
		code => sub { $_[0]{songtree}->AddColumn($_[1],$_[0]{insertpos}); }, stockicon => 'gtk-add',
	},
	{ label=> sub { _('_Remove this column').' ('.($SongTree::STC{$_[0]{colid}}{menutitle}||$SongTree::STC{$_[0]{colid}}{title}).')' },
	  code => sub { $_[0]{songtree}->remove_column($_[0]{cellnb}) },	stockicon => 'gtk-remove', isdefined => 'colid',
	},
	{ label => _"Follow playing song",	code => sub { $_[0]{songtree}->FollowSong if $_[0]{songtree}{follow}^=1; },
	  check => sub { $_[0]{songtree}{follow} }
	},
	{ label => _"Go to playing song",	code => sub { $_[0]{songtree}->FollowSong; }, },
);

sub new
{	my ($class,$adj)=@_;
	my $self=bless Gtk2::Viewport->new($adj,undef), $class;
	$self->set_size_request(1,-1);
	$self->add_events(['pointer-motion-mask','button-press-mask','button-release-mask']);
	$self->signal_connect(realize => \&update);
	$self->signal_connect(button_release_event	=> \&button_release_cb);
	$self->signal_connect(motion_notify_event	=> \&motion_notify_cb);
	$self->signal_connect(button_press_event	=> \&button_press_cb);
	my $rcstyle0=Gtk2::RcStyle->new;
	$rcstyle0->ythickness(0);
	$rcstyle0->xthickness(0);
	$self->modify_style($rcstyle0);
	return $self;
}

sub button_press_cb #begin resize
{	my ($self,$event)=@_;
	for my $button ($self->child->get_children)
	{	if ($button->{dragwin} && ($event->window == $button->{dragwin}))
		{	my $x= $event->x + $button->allocation->width;
			$self->{resizecol}=[$x,$button];
			last;
		}
		#elsif ($button->window==$event->window) {}#FIXME add column drag and drop
	}
	return 0 unless $self->{resizecol};
	Gtk2->grab_add($self);
	1;
}
sub button_release_cb #end resize
{	my $self=$_[0];
	return 0 unless $self->{resizecol};
	Gtk2->grab_remove($self);
	my $songtree=::find_ancestor($self,'SongTree');
	my $cell= $songtree->{cells}[ $self->{resizecol}[1]->{cellnb} ];
	$songtree->{colwidth}{$cell->{colid}}= $cell->{width}; #set width as default for this colid
	delete $self->{resizecol};
	_update_dragwin($_) for $self->child->get_children;
	1;
}
sub motion_notify_cb	#resize column
{	my ($self,$event)=@_;
	return 0 unless $self->{resizecol};
	my $songtree=::find_ancestor($self,'SongTree');
	my ($xstart,$button)=@{ $self->{resizecol} };
	my $cell= $songtree->{cells}[$button->{cellnb}];
	my $width=$cell->{width};
	my $newwidth= $xstart + $event->x;
	my $min= $cell->{minwidth} || 0;
	$newwidth=$min if $newwidth<$min;
	return 1 if $width==$newwidth;
	$cell->{width}=$newwidth;
	$self->{busy}=1;
	$songtree->update_columns;
	$self->{busy}=0;
	$button->set_size_request($newwidth,-1);
	1;
}

sub update
{	my $self=$_[0];
	return if $self->{busy};
	my $songtree=::find_ancestor($self,'SongTree');
	#return unless $songtree->{ready};
	$self->remove($self->child) if $self->child;
	my $hbox=Gtk2::HBox->new(0,0);
	$self->add($hbox);

	if (my $w=$songtree->{songxoffset})
	{	my $button=Gtk2::Button->new;
		$button->set_size_request($w,-1);
		$hbox->pack_start($button,0,0,0);
		$button->{insertpos}=0;
	}
	if (my $w=$songtree->{songxright})
	{	my $button=Gtk2::Button->new;
		$button->set_size_request($w,-1);
		$hbox->pack_end($button,0,0,0);
		$button->{insertpos}=@{$songtree->{cells}};
	}
	my $sort=$songtree->{sort};
	my $invsort= join ' ', map { s/^-// && $_ || '-'.$_ } split / /,$sort;
	my $i=0;
	for my $cell (@{$songtree->{cells}})
	{	my $button=Gtk2::Button->new;
		my $hbox2=Gtk2::HBox->new;
		my $label=Gtk2::Label->new( $SongTree::STC{ $cell->{colid} }{title} );
		$button->add($hbox2);
		$hbox2->add($label);
		if (defined (my $s=$cell->{sort}))
		{	$button->{sort}=$s;
			my $arrow=	$s eq $sort	? 'down':
					$s eq $invsort	? 'up'	:
					undef;
			$hbox2->pack_end(Gtk2::Arrow->new($arrow,'in'),0,0,0) if $arrow;
		}
		$label->set_alignment(0,.5);
		#FIXME	the drag_wins need to be destroyed, but this sometimes
		#	create "GdkWindow  unexpectedly destroyed" warnings
		#	$button->signal_connect(unrealize	=> \&_destroy_dragwin);
		#	$button->signal_connect(hide		=> \&_destroy_dragwin);
		$button->{cellnb}=$i++;
		$button->{colid}=$cell->{colid};
		$button->set_size_request($cell->{width},-1);
		my $expand= $i==@{$songtree->{cells}};
		$hbox->pack_start($button,$expand,$expand,0);
	}
	my $rcstyle=Gtk2::RcStyle->new;
	$rcstyle->ythickness(1);
	$rcstyle->xthickness(1);
	my @buttons=$hbox->get_children;
	for my $button (@buttons)
	{	$button->signal_connect(expose_event	=> \&button_expose_cb);
		$button->signal_connect(clicked		=> \&clicked_cb);
		$button->signal_connect(button_press_event => \&popup_col_menu);
		$button->{stylewidget}=$songtree->{stylewidget_header2};
		$button->modify_style($rcstyle);
	}
	$buttons[-1]{stylewidget}=$songtree->{stylewidget_header3};
	$buttons[0]{stylewidget}=$songtree->{stylewidget_header1};
	$hbox->show_all;
}

sub clicked_cb
{	my $button=$_[0];
	my $songtree=::find_ancestor($button,'SongTree');
	my $sort= $button->{colid} ? $button->{sort} : join ' ',map Songs::SortGroup($_), @{$songtree->{colgroup}};
	return unless defined $sort;
	$sort='-'.$sort if $sort eq $songtree->{sort};
	$songtree->Sort($sort);
}

sub popup_col_menu
{	my ($button,$event)=@_;
	return 0 unless $event->button == 3;
	my $self= ::find_ancestor($button,__PACKAGE__);
	my $songtree= ::find_ancestor($self,'SongTree');
	my $insertpos= exists $button->{cellnb} ? $button->{cellnb}+1 : $button->{insertpos};
	::PopupContextMenu(\@ColumnMenu, { self => $self, colid => $button->{colid}, cellnb =>$button->{cellnb}, insertpos =>$insertpos, songtree => $songtree });
	return 1;
}

sub button_expose_cb
{	my ($button,$event)=@_;
	my $songtree= ::find_ancestor($button,'SongTree');
	#my $style=Gtk2::Rc->get_style($button->{stylewidget});
	my $style=Gtk2::Rc->get_style_by_paths($button->get_settings, '.GtkTreeView.GtkButton', '.GtkTreeView.GtkButton','Gtk2::Button');
	$style=$style->attach($button->window);
	$style->paint_box($button->window,$button->state,'out',$event->area,$button->{stylewidget},'button',$button->allocation->values);
	$button->propagate_expose($button->child,$event) if $button->child;
	if ($button->{colid})
	{	_create_dragwin($button) unless $button->{dragwin};
		#$button->{dragwin}->raise;
	}
	1;
}

sub _create_dragwin
{	my $button=$_[0];
	my ($x,$y,$w,$h)=$button->allocation->values;
	my %attr=
	 (	window_type	=> 'child',
		wclass		=> 'only',
		cursor		=> Gtk2::Gdk::Cursor->new('sb-h-double-arrow'),
		x		=> $x+$w-(TREE_VIEW_DRAG_WIDTH/2),
		y		=> $y,
		width		=> TREE_VIEW_DRAG_WIDTH,
		height		=> $h,
		event_mask	=> ['pointer-motion-mask','button-press-mask','button-release-mask'],
	 );
	$button->{dragwin}=Gtk2::Gdk::Window->new($button->window,\%attr);
	$button->{dragwin}->set_user_data($button->window->get_user_data);
	$button->{dragwin}->show;
}
sub _destroy_dragwin
{	my $button=$_[0];
	my $dragwin=delete $button->{dragwin};
	return unless $dragwin;
	warn "destroying $dragwin\n" if $::debug;
	$dragwin->set_user_data(0); #needed ?
	$dragwin->destroy;
}
sub _update_dragwin
{	my ($button)=@_;
	return unless $button->{dragwin};
	my ($x,$y,$w)=$button->allocation->values;
	$button->{dragwin}->move($x+$w-(TREE_VIEW_DRAG_WIDTH/2), $y);
	0;
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
		    [	['layout_draw','draw = layout xd yd wd hd'],
			['markup_layout','layout = text markup rotate hide'],
			($Gtk2::VERSION<1.161 ?	['layout_size2','wr hr bl = layout markup'] : # work-around for bug #482795 in $Gtk2::VERSION<1.161
						['layout_size','wr hr bl = layout']
			),
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
		    defaults => 'w=___wr+2*___xpad,h=$_h,xpad=xpad,ypad=ypad,xalign=0,yalign=.5,size=\'menu\'',
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
{	my ($arg,$text,$markup,$rotate,$hide)=@_;
	return if $hide;
	my $pangocontext=$arg->{widget}->create_pango_context;
	if ($rotate && $Gtk2::VERSION >= ($Gtk2::VERSION<1.150 ? 1.146 : 1.154))
	{	#$pangocontext->set_base_gravity('east');
		my $matrix=Gtk2::Pango::Matrix->new;
		$matrix->rotate($rotate);
		$pangocontext->set_matrix($matrix);
	}
	my $layout=Gtk2::Pango::Layout->new($pangocontext);
	if (defined $markup) { $markup=~s#(?:\\n|<br>)#\n#g; $layout->set_markup($markup); }
	else { $text='' unless defined $text; $layout->set_text($text); }
	return $layout;
}
sub layout_size
{	my ($arg,$layout)=@_;
	return 0,0,0 unless $layout;
	my $bl=$layout->get_iter->get_baseline / Gtk2::Pango->scale;
	return $layout->get_pixel_size, $bl;
}
sub layout_size2	#version using a cache because of a memory leak in layout->get_iter (http://bugzilla.gnome.org/show_bug.cgi?id=482795) only used with gtk2-perl version <1.161
	#FIXME might not work correctly in all cases
{	my ($arg,$layout,$markup)=@_;
	return 0,0,0 unless $layout;
	my ($w,$h)=$layout->get_pixel_size;
	$markup||=''; $markup=~s#>[^<]+<#>.<#g; $markup=~s#^[^<]+##g; $markup=~s#[^>]+$##g;
	my $bl= $arg->{self}{baseline}{$h.$markup}||= $layout->get_iter->get_baseline / Gtk2::Pango->scale;
	return $w,$h,$bl;
}
sub layout_draw
{	my ($arg,$layout,$x,$y,$w,$h)=@_;
	return unless $layout;
#warn "drawing layout at x=$x y=$y text=".$layout->get_text."\n";
	$x+=$arg->{x};
	$y+=$arg->{y};
	my $clip= Gtk2::Gdk::Rectangle->new($x,$y,$w,$h)->intersect($arg->{clip});
	return unless $clip;
	$layout->set_width($w * Gtk2::Pango->scale); $layout->set_ellipsize('end'); #ellipsize
	$arg->{style}->paint_layout($arg->{window},$arg->{state},1,$clip,$arg->{widget}{stylewidget},'cellrenderertext',$x,$y,$layout);
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
	my $gc=Gtk2::Gdk::GC->new($arg->{window});
	$gc->set_clip_rectangle($arg->{clip});
	$color||= 'fg';
	$color= $color eq 'fg' ? $arg->{style}->fg('normal') : Gtk2::Gdk::Color->parse($color);
	$gc->set_rgb_fg_color($color);
	my $line='solid';#'on-off-dash' 'double-dash'
	my $cap='not-last'; #'butt' 'round' 'projecting'
	my $join='round';# 'miter' 'bevel'
	$gc->set_line_attributes($width,$line,$cap,$join);
	#my $dashes='5 5 0 5 5';
	#$gc->set_dashes(split / +/, $dashed);
#	warn "rect : $x,$y,$w,$h\n";
	$arg->{window}->draw_rectangle($gc,$filled||0,$x,$y,$w,$h);

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
	my $stylew=$arg->{self}{progressbar}||=Gtk2::ProgressBar->new;
	$arg->{style}->paint_box($arg->{window}, 'normal', 'in', $arg->{clip}, $stylew, 'though', $x, $y, $w, $h);
	$arg->{style}->paint_box($arg->{window}, 'prelight', 'out', $arg->{clip}, $stylew, 'bar', $x, $y, $w*$fill, $h);
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
	my $gc=Gtk2::Gdk::GC->new($arg->{window});
	my $line='solid';#'on-off-dash' 'double-dash'
	my $cap='not-last'; #'butt' 'round' 'projecting'
	my $join='round';# 'miter' 'bevel'
	$gc->set_line_attributes($width,$line,$cap,$join);
	$gc->set_clip_rectangle($arg->{clip});
	$color||= 'fg';
	$color= $color eq 'fg' ? $arg->{style}->fg('normal') : Gtk2::Gdk::Color->parse($color);
	$gc->set_rgb_fg_color($color);
	$arg->{window}->draw_line($gc,$x1,$y1,$x2,$y2);
}

sub pic_cached
{	my ($arg,$file,$resize,$w,$h,$xpad,$ypad,$crop,$hide)=@_;
	return undef,0 if $hide || !$file;
	if ($resize) { $w-=2*$xpad; $h-=2*$ypad; $h=0 if $h<0; $w=0 if $w<0; $resize.="_$w"."_$h"; }
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
	my ($w1,$h1)=Gtk2::IconSize->lookup($size);
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
	my $clip= Gtk2::Gdk::Rectangle->new($x,$y,$w,$h)->intersect($arg->{clip});
	return unless $clip;
	my $gc=Gtk2::Gdk::GC->new($arg->{window});
	$gc->set_clip_rectangle($clip);
	my $i=0; my $y0=$y;
	for my $icon (ref $icon ? @$icon : $icon)
	{	my $pixbuf=$arg->{widget}->render_icon($icon,$size);
		next unless $pixbuf;
		$arg->{window}->draw_pixbuf($gc, $pixbuf,0,0, $x,$y, -1,-1,'none',0,0);
		$i++;
		if ($i>=$nbh) {$y=$y0; $x+=$w1; $i=0;} else {$y+=$h1}
	}
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
	my $clip= Gtk2::Gdk::Rectangle->new($x,$y,$w,$h)->intersect($arg->{clip});
	return unless $clip;
	my $gc=Gtk2::Gdk::GC->new($arg->{window});
	$gc->set_clip_rectangle($clip);
	$arg->{window}->draw_pixbuf($gc, $pixbuf,0,0, $x,$y, -1,-1,'none',0,0);
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
use Gtk2;
use base 'Gtk2::VBox';

my %opt_types=
(	Text	=> [ sub {my $entry=Gtk2::Entry->new;$entry->set_text($_[0]); return $entry}, sub {$_[0]->get_text},1 ],
	Color	=> [	sub { Gtk2::ColorButton->new_with_color( Gtk2::Gdk::Color->parse($_[0]) ); },
			sub {my $c=$_[0]->get_color; sprintf '#%02x%02x%02x',$c->red/256,$c->green/256,$c->blue/256; }, 1 ],
	Font	=> [ sub { Gtk2::FontButton->new_with_font($_[0]); }, sub {$_[0]->get_font_name}, 1 ],
	Boolean	=> [ sub { my $c=Gtk2::CheckButton->new($_[1]); $c->set_active(1) if $_[0]; return $c }, sub {$_[0]->get_active}, 0 ],
	Number	=> [	sub {	my $s=Gtk2::SpinButton->new_with_range($_[2]{min}||0, $_[2]{max}||9999, $_[2]{step}||1);
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
	my $self = bless Gtk2::VBox->new, $class;
	my $vbox=Gtk2::VBox->new;
	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add_with_viewport($vbox);
	$self->{vbox}=$vbox;
	my $badd= ::NewIconButton('gtk-add',_"Add a group",sub {$_[0]->parent->AddRow('album|default');} );
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
	my $button=::NewIconButton('gtk-remove',undef,sub
		{ my $button=$_[0];
		  my $box=$button->parent->parent;
		  $box->parent->remove($box);
		},'none');
	my $fopt=Gtk2::Expander->new;
	my $vbox=Gtk2::VBox->new;
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_start($_,0,0,2) for $button,
		Gtk2::Label->new(_"Group by :"),	$typelist,
		Gtk2::Label->new(_"using skin :"),	$skinlist;
	my $optbox=Gtk2::HBox->new;
	my $filler=Gtk2::HBox->new;
	my $sg=Gtk2::SizeGroup->new('horizontal');
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
	my $hbox=$combo; $hbox=$hbox->parent until $hbox->{fopt};
	my $fopt=$hbox->{fopt};
	$fopt->remove($fopt->child) if $fopt->child;
	delete $fopt->{entry};
	$fopt->set_label( _"skin options" );
	my $table=Gtk2::Table->new(2,1,0); my $row=0;
	my $ref0=$SongTree::GroupSkin{$skin}{options};
	for my $key (sort keys %$ref0)
	{	my $ref=$ref0->{$key};
		my $type=$ref->{type};
		$type='Text' unless exists $opt_types{$type};
		my $l=$ref->{name}||$key;
		my $label=Gtk2::Label->new($l);
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

our %alias=( 'if' => 'iff', pesc => '::PangoEsc', ratingpic => 'Stars::get_pixbuf', min =>'::min', max =>'::max', sum =>'::sum',); #FIXME use Songs::Picture instead of Stars::get_pixbuf
our %functions=
(	formattime=> ['do {my ($f,$t,$z)=(',		'); !$t && defined $z ? $z : ::strftime($f,localtime($t)); }'],
	#sum	=>   ['do {my $sum; $sum+=$_ for ',	';$sum}'],
	average	=>   ['do {my $sum=::sum(',		'); @l ? $sum/@l : undef}'],
	#max	=>   ['do {my ($max,@l)=(',		'); $_>$max and $max=$_ for @l; $max}'],
	#min	=>   ['do {my ($min,@l)=(',		'); $_<$min and $min=$_ for @l; $min}'],
	iff	=>   ['do {my ($cond,$res,@l)=(',	'); while (@l>1) {last if $cond; $cond=shift @l;$res=shift @l;} $cond ? $res : $l[0] }'],
	size	=>   ['do {my ($l)=(',			'); ref $l ? scalar @$l : 1}'],
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
	playicon=> ['::Get_PPSQ_Icon($arg->{ID})',	undef,'Playing Queue CurSong'],
	labelicons=>['[Songs::Get_icon_list("label",$arg->{ID})]', 'label','Icons'],
	ids	=> ['$arg->{ID}'],
 },
 group=>
 {	ids	=> ['$arg->{groupsongs}'],
	year	=> ['groupyear($arg->{groupsongs})',	'year'],
	artist	=> ['groupartist($arg->{groupsongs})',	'artist'],
	album	=> ['groupalbum($arg->{groupsongs})',	'album'],
	artistid=> ['groupartistid($arg->{groupsongs})','artist'],
	albumid	=> ['groupalbumid($arg->{groupsongs})',	'album'],
	genres	=> ['groupgenres($arg->{groupsongs},genre)',	'genre'],
	labels	=> ['groupgenres($arg->{groupsongs},label)',	'label'],
	gid	=> ['Songs::Get_gid($arg->{groupsongs}[0],$arg->{grouptype})'],	#FIXME PHASE1
	title	=> ['($arg->{groupsongs} ? Songs::Get_grouptitle($arg->{grouptype},$arg->{groupsongs}) : "")'], #FIXME should the init case ($arg->{groupsongs}==undef) be treated here ?
	rating_avrg => ['do {my $sum; $sum+= $_ eq "" ?  $::Options{DefaultRating} : $_ for Songs::Map(rating=>$arg->{groupsongs}); $sum/@{$arg->{groupsongs}}; }', 'rating'], #FIXME round, int ?
	'length' => ['do {my (undef,$v)=Songs::ListLength($arg->{groupsongs}); sprintf "%d:%02d",$v/60,$v%60;}', 'length'],
	nbsongs	=> ['scalar @{$arg->{groupsongs}}'],
	disc	=> ['groupdisc($arg->{groupsongs})',	'disc'],
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
		elsif (m#\G('.*?[^\\]'|'')#gc){$r.=$1}	#string between ' '
		  #variable or function
		elsif (m#\G([-!])?(\$_?)?([a-zA-Z][:0-9_a-zA-Z]*)(\()?#gc)
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
		{	$update->{event}{$_}=undef for split / /,$e;;
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
				{	my ($func,my @keys)=@$code; #warn " -> ($func, @keys)\n";
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
{	my $songs=$_[0];
	my $l= Songs::UniqList('artist',$songs);
	return @$l==1 ? $l->[0] : $l;
}

sub groupalbum
{	my $songs=$_[0];
	my $l= Songs::UniqList('album',$songs);
	return Songs::Gid_to_Display('album',$l->[0]) if @$l==1;
	return ::__("%d album","%d albums",scalar @$l);
}
sub groupartist	#FIXME optimize PHASE1
{	my $songs=$_[0];
	my $h=Songs::BuildHash('artist',$songs);
	my $nb=keys %$h;
	return Songs::Gid_to_Display('artist',(keys %$h)[0]) if $nb==1;
	my @l=map split(/$::re_artist/o), keys %$h;
	my %h2; $h2{$_}++ for @l;
	my @common;
	for (@l) { if ($h2{$_}>=$nb) { push @common,$_; delete $h2{$_}; } }
	return @common ? join ' & ',@common : ::__("%d artist","%d artists",scalar(keys %h2));
}
sub groupgenres
{	my ($songs,$field,$common)=@_;
	my $h=Songs::BuildHash($field,$songs);
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
sub error
{	warn "unknown function : '$_[0]'\n";
}

sub playmarkup
{	my $constant=$_[0];
	return ['do { my $markup=',	'; $arg->{ID}==$::SongID ? \'<span '.$constant->{playmarkup}.'>\'.$markup."</span>" : $markup }',undef,'CurSong'];
}


=toremove
package GMB::RadioList;
use base 'Gtk2::VBox';

sub new
{	my ($class)=@_;
	my $self=bless Gtk2::VBox->new, $class;
	my $Badd=::NewIconButton('gtk-add',_"Add a radio",\&add_radio_cb);
	my $store=Gtk2::ListStore->new('Glib::Uint');
	$self->{treeview}=my $treeview=Gtk2::TreeView->new($store);
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$self->add_column(title => _"Radio title");
	$self->add_column(url => 'url');
	$self->pack_start($Badd,0,0,2);
	$self->add($sw);
	$sw->add($treeview);
	::Watch($self,RadioList=>\&Refresh);
	::Watch($self,CurSong=> sub {$_[0]->queue_draw});
	$treeview->signal_connect( row_activated => sub
		{	my ($tv,$path,$column)=@_;
			my $store=$tv->get_model;
			my $ID=$store->get($store->get_iter($path),0);
			::Select(song=>$ID,play=>1,staticlist => [$ID]);
		});
	$treeview->signal_connect(key_release_event => sub
		{	my ($tv,$event)=@_;
			if (Gtk2::Gdk->keyval_name( $event->keyval ) eq 'Delete')
			{	my $store=$tv->get_model;
				my $path=($treeview->get_cursor)[0];
				return 0 unless $path;
				my $ID=$store->get($store->get_iter($path),0);
				::SongsRemove([$ID]);
				$tv->parent->parent->Refresh;
				return 1;
			}
			return 0;
		});
	$self->Refresh;
	return $self;
}

sub add_column
{	my ($self,$field,$title)=@_;
	my $renderer=Gtk2::CellRendererText->new;
	my $column=Gtk2::TreeViewColumn->new_with_attributes($title,$renderer);
	$column->set_resizable(1);
	$column->{field}=$field;
	$column->set_cell_data_func($renderer,\&set_cell_data_cb);
	$self->{treeview}->append_column($column);
}

sub set_cell_data_cb
{	my ($column,$cell,$store,$iter)=@_;
	my $ID=$store->get($iter,0);
	my $song=$::Songs[$ID];
	my $text=	$column->{field} eq 'title' ? $song->[::SONG_TITLE] :
			$column->{field} eq 'url'   ? $song->[::SONG_UPATH].'/'.$song->[::SONG_UFILE] : '';
	my $w= (defined $::SongID && $::SongID==$ID) ? Gtk2::Pango::PANGO_WEIGHT_BOLD : Gtk2::Pango::PANGO_WEIGHT_NORMAL;
	$cell->set(text => $text);
	$cell->set(weight => $w);
}

sub add_radio_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $dialog=Gtk2::Dialog->new( _"Adding a radio", $self->get_toplevel,'destroy-with-parent',
				'gtk-add' => 'ok',
				'gtk-cancel' => 'none');
	my $table=Gtk2::Table->new(2,2,1);
	for my $ref (	['entry1',0,_"Radio title"],
			['entry2',1,_"Radio url"], )
	{	my ($key,$row,$label)=@$ref;
		$dialog->{$key}=Gtk2::Entry->new;
		$table->attach_defaults($dialog->{$key},1,2,$row,$row+1);
		$table->attach_defaults(Gtk2::Label->new($label),0,1,$row,$row+1);
	}
	$dialog->vbox->pack_start($_,0,0,2) for Gtk2::Label->new(_"Add new radio"),$table;
	$dialog->signal_connect( response => sub
		{	my ($dialog,$response)=@_;
			if ($response eq 'ok')
			{	my $name=$dialog->{entry1}->get_text;
				my $url =$dialog->{entry2}->get_text;
				::AddRadio($url,$name);
			}
			$dialog->destroy
		});
	$dialog->show_all;
}

sub Refresh
{	my $self=$_[0];
	my $store=$self->{treeview}->get_model;
	$store->clear;
	$store->set($store->append,0,$_) for @::Radio;
}
=cut

1;
