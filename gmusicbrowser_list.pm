# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
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

our @MenuPlaying=		# sub parameters : @_= (menuitem)
(	{ label => _"Follow playing song",	code => sub { $_[0]{songlist}->FollowSong if $_[0]{songlist}->{TogFollow}^=1; }, check => sub { $_[0]{songlist}->{TogFollow} }, },
	{ label => _"Filter on playing Album",	code => sub { ::SetFilter($_[0]{songlist}, ::SONG_ALBUM. 'e'.$::Songs[$::SongID][::SONG_ALBUM] ) if defined $::SongID; }},
	{ label => _"Filter on playing Artist",	code => sub { ::SetFilter($_[0]{songlist}, ::SONG_ARTIST.'~'.$::Songs[$::SongID][::SONG_ARTIST]) if defined $::SongID; }},
	{ label => _"Filter on playing Song",	code => sub { ::SetFilter($_[0]{songlist}, ::SONG_TITLE. '~'.$::Songs[$::SongID][::SONG_TITLE] ) if defined $::SongID; }},
	{ label => _"use the playing Filter",	code => sub { ::SetFilter($_[0]{songlist}, $::PlayFilter ); }, test => sub {::GetSonglist($_[0]{songlist})->{mode} ne 'playlist'}}, #FIXME	if queue use queue, if $ListMode use list
);

sub makeFilterBox
{	my $box=Gtk2::HBox->new;
	my $FilterWdgt=FilterBox->new
	( sub	{	my $filt=FilterBox::posval2filter(@_);
			::SetFilter($box,$filt);
		},
	  undef,
	  FilterBox::filter2posval(::SONG_TITLE.'s')
	);
	$FilterWdgt->addtomainmenu(_"edit ..." => sub
		{	::EditFilter($box,::GetFilter($box),undef,sub {::SetFilter($box,$_[0]) if defined $_[0]});
		});
	my $okbutton=::NewIconButton('gtk-apply',undef,sub {$FilterWdgt->activate},'none');
	$::Tooltips->set_tip($okbutton,_"apply filter");
	$box->pack_start($FilterWdgt, FALSE, FALSE, 0);
	$box->pack_start($okbutton, FALSE, FALSE, 0);
	return $box;
}

sub makeLockToggle
{	my $opt1=$_[0];
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
	::WatchFilter($toggle,$opt1->{group},sub
		{	my ($self,undef,$group)=@_;
			my $filter=$::Filters_nb{$group}[0];
			my $empty=Filter::is_empty($filter);
			$self->{busy}=1;
			$self->set_active(!$empty);
			$self->{busy}=0;
			my $desc=($empty? _("No locked filter") : _("Locked on :\n").$filter->explain);
			$::Tooltips->set_tip($self ,$desc);
		});
	return $toggle;
}

sub make_playing_menu
{	my $menu= ::PopupContextMenu(\@MenuPlaying, { songlist => ::GetSonglist($_[0]) });
	return $menu;
}

sub make_sort_menu
{	my $selfitem=$_[0];
	my $songlist=$selfitem->isa('SongList') || $selfitem->isa('SongTree') ? $selfitem : ::GetSonglist($selfitem);
	my $menu=Gtk2::Menu->new;
	my $menusub=sub { $songlist->Sort($_[1]) };
	for my $name (sort keys %::SavedSorts)
	{   my $sort=$::SavedSorts{$name};
	    my $item = Gtk2::CheckMenuItem->new($name);
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

sub make_history_menuitem
{	my $opt1=$_[0];
	my $self=Gtk2::MenuItem->new(_"Recent Filters");
	$self->{recent}=[ map Filter->new($_),split /\x00/,$::Options{RecentFilters}||'' ];
	$self->{SaveOptions}=sub { $::Options{RecentFilters}=join "\x00",map $_->{string},@{ $_[0]->{recent} }; return undef; };
	::WatchFilter($self,$opt1->{group},sub
	 {	my ($self,$filter)=@_;
		my $recent=$self->{recent};
		my $string=$filter->{string};
		my @recent=($filter,grep $_->{string} ne $string,@$recent);
		pop @recent if @recent>20;
		$self->{recent}=\@recent;
	 });
	return $self;
}

sub make_history_menu
{	my $selfitem=$_[0];
	my $menu=Gtk2::Menu->new;
	my $mclicksub=sub   { $_[0]{middle}=1 if $_[1]->button == 2; return 0; };
	my $menusub=sub
	 { my $f=($_[0]{middle})? Filter->newadd(FALSE, ::GetFilter($selfitem,1),$_[1]) : $_[1];
	   ::SetFilter($selfitem,$f);
	 };
	for my $f (@{ $selfitem->{recent} })
	{	my $item = Gtk2::MenuItem->new( $f->explain );
		$item->signal_connect(activate => $menusub,$f);
		$item->signal_connect(button_release_event => $mclicksub,$f);
		$menu->append($item);
	}
	return $menu;
}

package LabelTotal;
use Gtk2;

use base 'Gtk2::Button';

our %Modes=
(	list	 => [_"Listed songs",	\&Set_list],
	library	 => [_"Library",	\&Set_library],
	selected => [_"Selected songs",	\&Set_selected],
);

sub new
{	my ($class,$opt1) = @_;
	my $self = bless Gtk2::Button->new, $class;
	$self->set_relief('none');
	my $mode=$opt1->{mode} || 'list';
	$self->{size}=$opt1->{size};
	$self->{format}= ($opt1->{format} && $opt1->{format} eq 'short') ? 'short' : 'long';
	$self->{group}=$opt1->{group};
	$self->add(Gtk2::Label->new);
	$self->signal_connect( destroy => \&Remove);
	$self->signal_connect( button_press_event => \&button_press_event_cb);
	$self->{watch}=::AddWatcher();
	$self->Set_mode($mode);
	return $self;
}

sub Set_mode
{	my ($self,$mode)=@_;
	$self->Remove;
	my $updatedo=&{ $Modes{$mode}[1] }($self);
	::IdleDo('9_Total'.$self,10,$updatedo,$self);
	$self->{SaveOptions}=$mode;
}

sub Remove
{	my $self=shift;
	delete $::ToDo{'9_Total'.$self};
	::RemoveWatcher($self->{watch});
	::UnWatchFilter($self,$self->{group});
	::UnWatch($self,'Selection_'.$self->{group});
}

sub Update_text
{	my ($self,$text,$array)=@_;
	$text.= ::CalcListLength($array,$self->{format});
	$text= ::PangoEsc($text);
	$text= '<span size="'.$self->{size}.'">'.$text.'</span>' if $self->{size};
	$self->child->set_markup($text);
}

sub button_press_event_cb
{	(my $self,$::LEvent)=@_;
	my $menu=Gtk2::Menu->new;
	for my $mode (sort {$Modes{$a}[0] cmp $Modes{$b}[0]} keys %Modes)
	{	my $item = Gtk2::CheckMenuItem->new( $Modes{$mode}[0] );
		$item->set_draw_as_radio(1);
		$item->set_active($mode eq $self->{SaveOptions});
		$item->signal_connect( activate => sub { $self->Set_mode($mode) } );
		$menu->append($item);
	 }
	$menu->show_all;
	$menu->popup(undef, undef, \&::menupos, undef, $::LEvent->button, $::LEvent->time);
}

sub Set_list
{	my $self=shift;
	::WatchFilter($self,$self->{group},\&Queue_list);
	return \&Update_list;
}
sub Queue_list
{	my $self=shift;
	::IdleDo('9_Total'.$self, 1000,\&Update_list,$self);
}
sub Update_list
{	my $self=shift;
	my $songlist=::GetSonglist($self);
	return unless $songlist;
	my $array=$songlist->{array};
	$self->Update_text(_("Listed : "),$array);
	$::Tooltips->set_tip( $self, ::GetFilter($self)->explain );
	my $sub=sub {$self->Queue_list};
	::ChangeWatcher( $self->{watch}, $array, [::SONG_LENGTH,::SONG_SIZE], $sub, $sub);
}

sub Set_selected
{	my $self=shift;
	::Watch($self,'Selection_'.$self->{group},\&Queue_selected);
	return \&Update_selected;
}
sub Queue_selected
{	my $self=shift;
	::IdleDo('9_Total'.$self, 500,\&Update_selected,$self);
}
sub Update_selected
{	my $self=shift;
	my $songlist=::GetSonglist($self);
	return unless $songlist;
	my $array=$songlist->{array};
	my @list=$songlist->GetSelectedIDs;
	$self->Update_text(_('Selected : '),\@list);
	$::Tooltips->set_tip( $self, ::__('%d song selected','%d songs selected',scalar@list) );
	::ChangeWatcher( $self->{watch}, \@list, [::SONG_LENGTH,::SONG_SIZE], sub {$self->Queue_selected} );
}

sub Set_library
{	my $self=shift;
	my $sub= sub { ::IdleDo('9_Total'.$self, 4000,\&Update_library,$self); };
	::ChangeWatcher( $self->{watch},undef, [::SONG_LENGTH,::SONG_SIZE],$sub,$sub,$sub);
	return \&Update_library;
}
sub Update_library
{	my $self=shift;
	$self->Update_text(_('Library : '),\@::Library);
	$::Tooltips->set_tip( $self, ::__('%d song in the library','%d songs in the library',scalar@::Library) );
}

package TabbedLists;
use Gtk2;
use base 'Gtk2::Notebook';

my %PagesTypes=
(	L => {New => \&newlist,		stockicon => 'gmb-list',	WatchID=>1, save => sub {$_[0]{listname}} },
	B => {New => \&newfilter,	stockicon => 'gmb-filter',	WatchID=>1 },
	Q => {New => \&newqueue,	stockicon => 'gmb-queue',	WatchID=>1 },
	P => {New => \&Layout::Page::new,	save=> sub {$_[0]{layout}}, stringopt =>1,WatchID=>1 },
	A => {New => \&newplaylist,	stockicon => 'gtk-media-play',	WatchID=>1 },
);

our @MenuTabbedL=
(	{ label => _"New list",	  code => sub { $_[0]{self}->newtab('L'); }, stockicon => 'gtk-add', },
	#{ label => _"New filter", code => sub { $_[0]{self}->newtab('B'); }, stockicon => 'gtk-add', },
	{ label => _"Open Queue", code => sub { $_[0]{self}->newtab('Q'); }, stockicon => 'gmb-queue',
		test => sub { !grep $_->{tabbed_page_type} eq 'Q', $_[0]{self}->get_children } },
	{ label => _"Open Playlist", code => sub { $_[0]{self}->newtab('A'); }, stockicon => 'gtk-media-play',
		test => sub { !grep $_->{tabbed_page_type} eq 'A', $_[0]{self}->get_children } },
	{ label => _"Open existing list", code => sub { $_[0]{self}->newtab(L=>$_[1]); },
		submenu => sub { my %h; $h{$_->{listname}}=1 for grep $_->{tabbed_page_type} eq 'L', $_[0]{self}->get_children; return [grep !$h{$_}, keys %::SavedLists]; } },
	{ label => _"Open page layout", code => sub { $_[0]{self}->newtab(P=>$_[1]); },
		submenu => sub { Layout::get_layout_list('P') } },
	{ label => _"Delete list", code => sub { ::SaveList($_[0]{page}{listname},undef); },
		test => sub {$_[0]{pagetype} eq 'L'} },
	{ label => _"Rename", code => \&rename_current_tab,
		test => sub {$_[0]{pagetype} eq 'L'} },
	{ label => _"Close",	code => sub { $_[0]{self}->close_tab($_[0]{page}); }, },
);

sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self = bless Gtk2::Notebook->new, $class;
	$self->set_scrollable(1);
	$self->{SaveOptions}=\&SaveOptions;
	$self->{group}=$opt1->{group};
	$self->signal_connect(switch_page => \&SwitchedPage);
	$self->signal_connect(button_press_event => \&button_press_event_cb);
	$self->{tabcount}=0;
	if ($opt2 && keys %$opt2)
	{	for my $n (sort {$a<=>$b} grep s/^page(\d+)$/$1/, keys %$opt2)
		{	my @args=split /\|/,$opt2->{'page'.$n};
			my ($type,$extra,$opt)=map Encode::decode('utf8',::decode_url($_)), @args;
			unless ($PagesTypes{$type}{stringopt})
			{	my %opt2= $opt=~m/(\w+)=([^,]*)(?:,|$)/g;
				$opt=\%opt2;
			}
			$self->newtab($type,$extra,$opt);
		}
		for my $key (keys %$opt2)
		{	$self->{default}{$1}=$opt2->{$key} if $key=~m/^([ALQ])default$/;
		}
		$self->set_current_page($opt2->{currentpage});
	}

	::Watch($self, SavedLists => sub
	 {	my ($self,$name,$type,$newname)=@_;
		for my $page (grep $_->{tabbed_page_type} eq 'L', $self->get_children)
		{	next if $name ne $page->{tabbed_listname};
			if ($type && $type eq 'renamedto')
			{	$page->{tabbed_listname}=$newname;
				$page->{tabbed_page_label}->set_text($newname);
			}
			elsif (!exists $::SavedLists{$name})
			{	$self->close_tab($page);
			}
		}
	 });

	$self->newtab('A') unless $self->{tabcount};
	return $self;
}

sub button_press_event_cb
{	my ($self,$event)=@_;
	return 0 if $event->button != 3;
	my $pagenb=$self->get_current_page;
	my $page=$self->get_nth_page($pagenb);
	my $listname= $page? $page->{listname} : undef;
	$::LEvent=$event;
	::PopupContextMenu(\@MenuTabbedL, { self=>$self, list=>$listname, pagenb=>$pagenb, page=>$page, pagetype=>$page->{tabbed_page_type} } );
	return 1;
}

sub newlist
{	my ($self,$group,$name,$opt2)=@_;
	my $page=SongList->new({type=>'L',activate=>'playlist',group=>$group},$opt2);
	unless (defined $name)
	{	$name='list000';
		$name++ while $::SavedLists{$name};
	}
	::SaveList($name,[]) unless $::SavedLists{$name};
	$page->SetList($name);
	$page->{tabbed_listname}=$name;
	return $page,$name;
}
sub newfilter
{	my ($self,$group,$name,$opt2)=@_;
	my $page=SongList->new({type=>'B',activate=>'play',group=>$group},$opt2);
	unless (defined $name)
	{	$name='filter000';
		$name++ while $::SavedFilters{$name};
		::SaveFilter($name,undef);
	}
	$page->SetFilter(Filter->new(::SONG_TITLE.'slove'));# just a test filter
	return $page,$name;
}
sub newqueue
{	my ($self,$group,undef,$opt2)=@_;
	my $page=SongList->new({type=>'Q',activate=>'play',group=>$group},$opt2);
	$page->SetList();
	return $page,_"Queue";
}
sub newplaylist
{	my ($self,$group,undef,$opt2)=@_;
	my $page=SongList->new({type=>'B',group=>$group,mode=>'playlist'},$opt2);
	return $page,_"Playlist";
}

sub newtab
{	my ($self,$type,$extra,$opt2)=@_;
	my $ref=$PagesTypes{$type};
	my $group=$self.'_'.$self->{tabcount}++;
	if (!$opt2 && $type=~m/^[ALQ]$/)
	{	if ($self->get_children)
		{	my $page=$self->get_nth_page($self->get_current_page);
			$opt2=$page->SaveOptions if $page && $page->{tabbed_page_type} eq $type;
		}
		if (!$opt2 &&  $self->{default}{$type})
		{	$opt2=::decode_url($self->{default}{$type});
			my %opt2= $opt2=~m/(\w+)=([^,]*)(?:,|$)/g;
			$opt2=\%opt2;
		}
	}
	my ($page,$name)=&{$ref->{New}} ($self,$group,$extra,$opt2);
	$page->{tabbed_page_type}=$type;
	::Watch($self,'SelectedID_'.$group,\&UpdateSelectedID) if $ref->{WatchID};
	$page->{tabbed_page_label}=my $label=Gtk2::Label->new($name);
	my $icon= $ref->{stockicon}||$page->{stockicon};
	$icon=Gtk2::Image->new_from_stock($icon,'menu') if defined $icon;

	#small close button
	my $close=Gtk2::Button->new;
	$close->set_relief('none');
	$close->can_focus(0);
	$close->signal_connect(clicked => sub {my $self=::find_ancestor($_[0],__PACKAGE__); $self->close_tab($page);});
	$close->add(Gtk2::Image->new_from_stock('gtk-close','menu'));
	my $req=$close->child->requisition; $close->set_size_request(Gtk2::IconSize->lookup('menu'));
	my $rcstyle=Gtk2::RcStyle->new;
	$rcstyle->ythickness(0);
	$close->modify_style($rcstyle);
	$close->set_border_width(0);

	my $tab=::Hpack('4',$icon,'2_', $label,$close);
	$tab->set_spacing(0); #FIXME Hpack options should be enough
	$self->append_page($page,$tab);
	$self->set_tab_reorderable($page,::TRUE);
	$tab->show_all;
	$self->show_all;
	$self->set_current_page($self->get_n_pages-1);
}
sub close_tab
{	my ($self,$page)=@_;
	my $type=$page->{tabbed_page_type};
	if ($type=~m/^[ALQ]$/ && $page->{SaveOptions})
	{	my $opt=&{ $page->{SaveOptions} }($page);
		$opt=join ',',map $_.'='.$opt->{$_}, keys %$opt;
		$self->{default}{$type}= ::url_escapeall( $opt );
	}
	$self->remove($page);
	$page->destroy;
	$self->newtab('A') unless $self->get_children;
}

sub rename_current_tab
{	my $page=$_[0]{page};
	my $tab=$_[0]{self}->get_tab_label($page);
	my $label=$page->{tabbed_page_label};
	my $entry=Gtk2::Entry->new;
	$entry->set_has_frame(0);
	$entry->set_inner_border(undef) if *Gtk2::Entry::set_inner_border{CODE}; #Gtk2->CHECK_VERSION(2,10,0);
	$entry->set_text( $page->{listname} );
	$entry->set_size_request( 20+$label->allocation->width ,-1);
	$_->hide for grep !$_->isa('Gtk2::Image'), $tab->get_children;
	$tab->pack_start($entry,::FALSE,::FALSE,2);
	$entry->grab_focus;
	$entry->show_all;
	$entry->signal_connect(key_press_event => sub #abort if escape
		{	my ($entry,$event)=@_;
			return 0 unless Gtk2::Gdk->keyval_name( $event->keyval ) eq 'Escape';
			$entry->set_text($page->{listname});
			$entry->set_sensitive(0);  #trigger the focus-out event
			1;
		});
	$entry->signal_connect(activate => sub {$_[0]->set_sensitive(0)}); #trigger the focus-out event
	$entry->signal_connect(focus_out_event => sub
	 {	my $entry=$_[0];
		my $new=$entry->get_text;
		$tab->remove($entry);
		$_->show for $tab->get_children;
		if ($new ne '' && !exists $::SavedLists{$new})
		{	::SaveList($page->{listname},undef,$new);
		}
		0;
	 });
}

sub SwitchedPage
{	my ($self,undef,$pagenb)=@_;
	my $page=$self->get_nth_page($pagenb);
	my $group=$page->{group};
#	if (my $layw=::get_layout_widget($self)) #should be done on init too
#	{	$page=undef unless $page->isa('SongList') || $page->isa('SongTree');
#		$layw->{'songlist'.$self->{group}}=$page;
#	}
	$self->{active_group}=$group;
	my $ID=$self->{selectedID}{$group};
	::HasChanged('SelectedID_'.$self->{group},$ID,$self->{group}) if defined $ID;
}

sub UpdateSelectedID
{	my ($self,$ID,$group)=@_;
	$self->{selectedID}{$group}=$ID;
	return unless $self->{active_group} eq $group;
	::HasChanged('SelectedID_'.$self->{group},$ID,$self->{group}) if defined $ID;
}

sub SaveOptions
{	my $self=$_[0];
	my $count=0;
	my %opt;
	for my $page ($self->get_children)
	{	my $type=$page->{tabbed_page_type};
		my $sub=$PagesTypes{$type}{save};
		my @args=($type);
		push @args, ($sub ? &$sub($page) :'');
		if ($page->{SaveOptions})
		{	my $opt= &{ $page->{SaveOptions} }($page);
			unless ($PagesTypes{$type}{stringopt})
			{ $opt=join ',',map $_.'='.$opt->{$_}, keys %$opt; }
			push @args,$opt;
		}
		$opt{ 'page'.($count++) }=join '|',map ::url_escapeall($_),@args;
	}
	if ($self->{default})
	{	$opt{$_.'default'}=$self->{default}{$_} for keys %{$self->{default}};
	}
	$opt{currentpage}=$self->get_current_page;
	return \%opt;
}

package Layout::Page;
use base 'Gtk2::Frame';
our @ISA;
push @ISA,'Layout';

sub new
{	my (undef,$group,$layout,$opt2)=@_;
	my $self=bless Gtk2::Frame->new, 'Layout::Page';
	$self->set_shadow_type('etched-in');
	$self->{SaveOptions}=\&Layout::SaveOptions;
	$self->{group}=$group;
	$self->Pack($layout,$opt2);
	$self->{stockicon}=$Layout::Layouts{$layout}{stockicon};
	$self->show_all;

	return $self,$layout;
}

package EditListButtons;
use Glib qw(TRUE FALSE);
use Gtk2;

use base 'Gtk2::HBox';

sub new
{	my ($class,$opt1)=@_;
	my $self=bless Gtk2::HBox->new, $class;
	$self->{group}=$opt1->{group};
	$self->{brm}=	::NewIconButton('gtk-remove',	($opt1->{small} ? '' : _"Remove"),sub {::GetSonglist($self)->RemoveSelected});
	$self->{bclear}=::NewIconButton('gtk-clear',	($opt1->{small} ? '' : _"Clear"),sub {::GetSonglist($self)->Empty} );
	$self->{bup}=	::NewIconButton('gtk-go-up',		undef,	sub {::GetSonglist($self)->MoveOne(1)});
	$self->{bdown}=	::NewIconButton('gtk-go-down',		undef,	sub {::GetSonglist($self)->MoveOne(0)});
	$self->{btop}=	::NewIconButton('gtk-goto-top',		undef,	sub {::GetSonglist($self)->MoveMax(1)});
	$self->{bbot}=	::NewIconButton('gtk-goto-bottom',	undef,	sub {::GetSonglist($self)->MoveMax(0)});

	$::Tooltips->set_tip($self->{brm},_"Remove selected songs");
	$::Tooltips->set_tip($self->{bclear},_"Remove all songs");

	if ($opt1->{relief}) { $self->{$_}->set_relief($opt1->{relief}) for qw/brm bclear bup bdown btop bbot/; }
	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/btop bup bdown bbot brm bclear/;

	::Watch($self,'Selection_'.$self->{group}, \&SelectionChanged);
	::Watch($self,'List_'.$self->{group}, \&ListChanged);

	return $self;
}

sub ListChanged
{	my ($self,$array)=@_;
	$self->{bclear}->set_sensitive(scalar @$array);
}

sub SelectionChanged
{	my ($self)=@_;
	my $songlist=::GetSonglist($self);
	my @rows;
	if ($songlist)
	{	@rows=map $_->to_string, $songlist->child->get_selection->get_selected_rows; #FIXME support SongTree
	}
	if (@rows)
	{	$self->{brm}->set_sensitive(1);
		my $i=0;
		$i++ while $i<@rows && $rows[$i]==$i;
		$self->{$_}->set_sensitive($i!=@rows) for qw/btop bup/;
		$i=$#rows;
		my $array=$songlist->{array};
		$i-- while $i>-1 && $rows[$i]==$#$array-$#rows+$i;
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
	$self->{spin}=::NewPrefSpinButton('MaxAutoFill',sub
		{	return if $self->{busy};
			::HasChanged('Queue','action');
		},1,0,1,50,1,5);
	$self->{spin}->set_no_show_all(1);

	$self->pack_start($self->{$_},FALSE,FALSE,2) for qw/eventcombo spin/;

	::Watch($self, Queue => \&Update);
	$self->Update;
	return $self;
}

sub Update
{	my $self=$_[0];
	$self->{busy}=1;
	my $action=$::QueueAction;
	$self->{queuecombo}->set_active( $::QActions{$action}[0] );
	$::Tooltips->set_tip( $self->{eventcombo}, $::QActions{$action}[3] );
	my $m=($action eq 'autofill')? 'show' : 'hide';
	$self->{spin}->$m;
	$self->{spin}->set_value($::Options{MaxAutoFill});
	delete $self->{busy};
}

package SongList;
use Glib qw(TRUE FALSE);
use Gtk2;
use Gtk2::Pango; #for PANGO_WEIGHT_BOLD, PANGO_WEIGHT_NORMAL

use base 'Gtk2::ScrolledWindow';

our %SLC_Prop;
INIT
{ no warnings 'uninitialized';
  %SLC_Prop=
  (	#PlaycountBG => #TEST
#	{	value => sub { $_[1][2][::SONG_NBPLAY] ? 'grey' : '#ffffff'; },
#		attrib => 'cell-background',	type => 'Glib::String',
#	},
	italicrow =>
	{	value => sub {$_[0]{boldrow}==$_[1][1] ? 'italic' : 'normal'},
		attrib => 'style',	type => 'Gtk2::Pango::Style',
	},
	boldrow =>
	{	value => sub {$_[0]{boldrow}==$_[1][1] ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL},
		attrib => 'weight',	type => 'Glib::Uint',
	},
	titleaa =>
	{	menu => _('Title - Artist - Album'), title => _('Song'),
		value => sub { my $ID=$_[0]{array}[ $_[1][1] ]; return ::ReplaceFieldsAndEsc($ID,"<b>%t</b>\n<small><i>%a</i> - %l</small>"); },
		attrib => 'markup', type => 'Glib::String', depend => [::SONG_TITLE,::SONG_ARTIST,::SONG_ALBUM],
		sort => ::SONG_TITLE,	noncomp => ['boldrow'],		width => 200,
	},
	titleorfile =>
	{	title => _('Title or filename'),
		value => sub { my $ID=$_[0]{array}[ $_[1][1] ]; return ::ReplaceFields($ID,"%S"); },
		attrib => 'text', type => 'Glib::String', depend => [::SONG_TITLE,::SONG_FILE],
		sort => ::SONG_TITLE,	width => 200,
	},
	playandqueue =>
	{	menu => _('Playing & Queue'),		title => '',	width => 20,
		value => sub { my $ID=$_[0]{array}[ $_[1][1] ]; ::Get_PPSQ_Icon($ID,$_[0]{boldrow}!=$_[1][1]); },
		class => 'Gtk2::CellRendererPixbuf',	attrib => 'stock-id',
		type => 'Glib::String',			noncomp =>['boldrow','italicrow'],
		event => [qw/Playing Queue SongID/],
	},
	icolabel =>
	{	menu => _("Labels' Icons"),	title => '',		value => sub { $_[1][2][::SONG_LABELS]; },
		class => 'CellRendererIconList',attrib => 'iconlist',	type => 'Glib::Scalar',
		depend => [::SONG_LABELS],	sort => ::SONG_LABELS,	noncomp => ['boldrow','italicrow'],
		event => 'Icons', 		width => 50,
	},
	albumpic =>
	{	title => _("Album picture"),	width => 100,
		value => sub
		{	my $array=$_[0]{array};
			my $key=$_[1][2][::SONG_ALBUM];
			my $row=my $r1=my $r2=$_[1][1];
			$r1-- while $r1>0	 && $::Songs[$array->[$r1-1]][::SONG_ALBUM] eq $key;
			$r2++ while $r2<$#$array && $::Songs[$array->[$r2+1]][::SONG_ALBUM] eq $key;
			return [$r1,$r2,$row,$key];
		},
		class => 'CellRendererSongsAA',	attrib => 'ref',	type => 'Glib::Scalar',
		depend => [::SONG_ALBUM],	sort => ::SONG_ALBUM,	noncomp => ['boldrow','italicrow'],
		init => {aa => ::SONG_ALBUM},
		event => 'AAPicture',
	},
	artistpic =>
	{	title => _("Artist picture"),
		value => sub
		{	my $array=$_[0]{array};
			my $key=$_[1][2][::SONG_ARTIST];
			($key)= split $::re_artist, $key;
			my $row=my $r1=my $r2=$_[1][1];
			$r1-- while $r1>0	 && (split $::re_artist,$::Songs[$array->[$r1-1]][::SONG_ARTIST])[0] eq $key;
			$r2++ while $r2<$#$array && (split $::re_artist,$::Songs[$array->[$r2+1]][::SONG_ARTIST])[0] eq $key;
			return [$r1,$r2,$row,$key];
		},
		class => 'CellRendererSongsAA',	attrib => 'ref',	type => 'Glib::Scalar',
		depend => [::SONG_ARTIST],	sort => ::SONG_ARTIST,	noncomp => ['boldrow','italicrow'],
		init => {aa => ::SONG_ARTIST, markup => '<b>%a</b>'},	event => 'AAPicture',
	},
	stars	=>
	{	title => _("Rating"),
		menu => _("Rating (picture)"),
		value => sub { Stars::get_pixbuf( $_[1][2][::SONG_RATING] ); },
		class => 'Gtk2::CellRendererPixbuf',	attrib => 'pixbuf',
		type => 'Gtk2::Gdk::Pixbuf',		noncomp =>['boldrow','italicrow'],
		depend => [::SONG_RATING],		sort => ::SONG_RATING,
	},
  );
  %{$SLC_Prop{albumpicinfo}}=%{$SLC_Prop{albumpic}};
  $SLC_Prop{albumpicinfo}{title}=_"Album picture & info";
  $SLC_Prop{albumpicinfo}{init}={aa => ::SONG_ALBUM, markup => "<b>%a</b>%Y\n<small>%s <small>%l</small></small>"};

  for my $n (grep $::TagProp[$_], 0..$#::TagProp)
  {	my ($title,$id,$t,$width)=@{$::TagProp[$n]};
	next unless defined $title;
	my $sub=($t eq 'd')? eval 'sub{my $v=$_[1][2]['.$n.']; $v ? scalar localtime $v : "'._('never').'"}'	:
		($t eq 'l')? eval 'sub{my $v=$_[1][2]['.$n.'];sprintf "%d:%02d",$v/60,$v%60}'	:
		($t eq 'f')? eval 'sub{join ", ",split(/\x00/,$_[1][2]['.$n.'])}'		:
			     eval 'sub{$_[1][2]['.$n.']}';
	$SLC_Prop{$id}=	{	title => $title,	value => $sub,	attrib => 'text',
				type => 'Glib::String',	depend => [$n],	sort => $n,	width => $width,
			};
   }

   $SLC_Prop{'length'}{init}{xalign}=1; #right-align length #maybe should be done to all number columns ?

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
	{ label => _"Follow playing song",	code => sub { $_[0]{self}->FollowSong if $_[0]{self}{TogFollow}^=1; },
	  check => sub { $_[0]{self}{TogFollow} }
	},
	{ label => _"Go to playing song",	code => sub { $_[0]{self}->FollowSong; }, },
);

sub new
{	my ($class,$opt1,$opt2) = @_;
	$opt2->{sort}=join('_',::SONG_UPATH,::SONG_ALBUM,::SONG_DISC,::SONG_TRACK,::SONG_UFILE) unless defined $opt2->{sort};
	$opt2->{cols}='playandqueue_title_artist_album_date_length_track_ufile_lastplay_playcount_rating' unless defined $opt2->{cols};
	my $array=[];
	#my $store=SongStore->new(array => $array);
	my $store=SongStore->new; $store->{array}=$array; #small work-around for bug in Glib<1.105 when used with perl 5.8.8
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type('etched-in');
	$self->set_policy('automatic','automatic');
	::set_biscrolling($self);
	my $tv=Gtk2::TreeView->new($store);
	$self->add($tv);
	if ($opt2->{colwidth} || $opt2->{cols}=~m/^\d/) #for option format version <0.9584
	{	my @old_id=qw/ufile upath modif length size bitrate filetype channels samprate title artist album disc track date version genre comment author added lastplay playcount rating label boldrow titleaa playandqueue icolabel/;
		my @s=split /_/, $opt2->{colwidth}||'';
		$self->{colwidth}{$old_id[$_]}=$s[$_] for 0..$#s;
		$opt2->{cols}=~s/(\d+)/$old_id[$1]/g;
	}
	for my $key (keys %$opt2)
	{	next unless $key=~m/^cw_(.*)$/;
		$self->{colwidth}{$1}=$opt2->{$key};
	}
	$self->{sort}=$opt2->{sort};
	$self->{sort}=~tr/_/ /;
	$self->{TogFollow}=1 if $opt2->{follow};
	$self->{array}=$array;
	$self->{store}=$store;
	$self->{IDsToAdd}=[];
	$self->{$_}=$opt1->{$_} for qw/type group/,grep m/^activate\d?$/, keys %$opt1;
	$self->{songypad}= $opt1->{songypad} if exists $opt1->{songypad};
	$self->{mode}= $opt1->{mode} || '';
	$self->{playrow}= defined $opt1->{playrow} ? $opt1->{playrow} : 'boldrow';

	::set_drag($tv,
	source=>[::DRAG_ID,sub { my $tv=$_[0]; $tv->parent->GetSelectedIDs; }],
	dest =>	[::DRAG_ID,::DRAG_FILE,\&drag_received_cb],
	motion => \&drag_motion_cb,
		);
	$tv->signal_connect(drag_data_delete => sub { $_[0]->signal_stop_emission_by_name('drag_data_delete'); }); #ignored

	$tv->set_rules_hint(TRUE);
	$tv->get_selection->set_mode('multiple');
	$tv->set_headers_clickable(TRUE);
	$tv->set_headers_visible(FALSE) if $opt1->{headers} && $opt1->{headers} eq 'off';
	$tv->set('fixed-height-mode' => TRUE);
	#$self->{searchcol}=::SONG_TITLE;
	#$tv->set_search_column( $self->{searchcol} );
	$tv->set_enable_search(!$opt1->{no_typeahead});
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
	$tv->get_selection->signal_connect(changed => \&sel_changed_cb);

	$self->AddColumn($_) for split '_',$opt2->{cols};

	$self->{watcher}||=::AddWatcher();
	$self->signal_connect(destroy => \&removewatchers);
	::Watch($self,'SongID',\&UpdateSelID);
	::WatchFilter($self,$opt1->{group}, \&SetFilter ) unless $self->{type} && $self->{type} eq 'Q' || $self->{type} eq 'L'; #FIXME clean this mess
	$self->{SaveOptions}=\&SaveOptions;
	$self->{DefaultFocus}=$tv;
	if ($self->{mode} eq 'playlist')
	{	$self->{OnChange}=\&PlaylistUpdate;
		::Watch($self,Filter=> \&SetPlaylistFilter);
		::Watch($self,Sort  => \&SetPlaylistSort);
		$self->{sort}= $::Options{Sort}=~m/^r/ ? $::Options{AltSort} : $::Options{Sort};
	}
	#elsif ($self->{mode} eq 'noall') { $tv->show_all; $self->set_no_show_all(1); }
	$self->{hideif}=$opt1->{hideif} || '';
	$self->{hidewidget}=$opt1->{hidewidget};
	$self->{shrinkonhide}=$opt1->{shrinkonhide};

	if ($self->{mode} eq 'playlist') # FIXME a real mess between group filter init and playlist synchro :(
	{	$self->{from_playlist}=1;
		::SetFilter($self,undef,1);
		$self->{from_playlist}=undef;
		@{ $self->{array} }=@::ListPlay;
	}

	$self->{need_init}=1;
	$self->signal_connect(show => sub
		{	my $self=$_[0];
			return 0 unless delete $self->{need_init};
			unless ($self->{type} && $self->{type} eq 'Q' || $self->{type} eq 'L')
			{	::SetFilter($self,undef,0) unless $self->{filter};
				$self->FollowSong;
			}
			0;
		});
	return $self;
}

sub removewatchers
{	my $self=shift;
	::RemoveWatcher( $self->{watcher} );
}

sub SaveOptions
{	my $self=shift;
	my %opt;
	my $tv=$self->child;
	my $sort=$self->{'sort'};
	$sort=~tr/ /_/;
	$opt{sort}=$sort;
	#save displayed cols
	$opt{cols}=join '_',(map $_->{colid},$tv->get_columns);
	#save their width
	$opt{ 'cw_'.$_ }=$self->{colwidth}{$_} for keys %{$self->{colwidth}};
	$opt{ 'cw_'.$_->{colid} }=$_->get_width for $tv->get_columns;
	$opt{follow}=1 if $self->{TogFollow};
	return \%opt;
}

sub AddColumn
{	my ($self,$colid,$pos)=@_;
	$colid='playcount' if $colid eq 'nbplay'; #for version<0.9607 #DELME
	my $prop=$SLC_Prop{$colid};
	unless ($prop) {warn "Ignoring unknown column $colid\n"; return undef}
	my $renderer=	( $prop->{class} || 'Gtk2::CellRendererText' )->new;
	if (my $init=$prop->{init})
	{	$renderer->set($_ => $init->{$_}) for keys %$init;
	}
	$renderer->set(ypad => $self->{songypad}) if exists $self->{songypad};
	my $colnb=SongStore::get_column_number($colid);
	my $attrib=$prop->{attrib};
	my @attributes=($prop->{title},$renderer,$attrib,$colnb);
	my $playrow=$self->{playrow};
	if (my $ref=$prop->{noncomp}) { $playrow=undef if (grep $_ eq $playrow,@$ref); }
	push @attributes,$SLC_Prop{$playrow}{attrib},SongStore::get_column_number($playrow) if $playrow;
#	$playrow='PlaycountBG'; #TEST
#	push @attributes,$SLC_Prop{$playrow}{attrib},SongStore::get_column_number($playrow); #TEST
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
		{ $::LEvent=$_[1];
		  return 0 unless $::LEvent->button == 3;
		  my $self=::find_ancestor($_[0],__PACKAGE__);
		  $self->SelectColumns($_[2]);	# $_[2]=$colid
		  1;
		};
	if (my $event=$prop->{event})
	{	$event=[$event] unless ref $event;
		::Watch($label,$_,sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->queue_draw if $self; }) for @$event; # could queue_draw only column
	}
	my $button=$label->get_ancestor('Gtk2::Button'); #column button
	$button->signal_connect(button_press_event => $button_press_sub,$colid) if $button;
	return $column;
}

sub UpdateSortIndicator
{	my $self=$_[0];
	my $tv=$self->child;
	return if $self->{no_sort_indicator};
	my $s=$self->{sort};
	$_->set_sort_indicator(FALSE) for grep $_->get_sort_indicator, $tv->get_columns;
	if ($s=~m/^(-)?([0-9]+)$/)
	{	my $order=($1)? 'descending' : 'ascending';
		my @cols=grep defined($SLC_Prop{$_->{colid}}{sort}) && $SLC_Prop{$_->{colid}}{sort}==$2, $tv->get_columns;
		for my $col (@cols)
		{ $col->set_sort_indicator(TRUE);
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
	$self->UpdateWatcher;
}

sub UpdateWatcher
{	my $self=$_[0];
	my $tv=$self->child;
	my $cols=$self->{cols_to_watch}||=[ map @{ $SLC_Prop{ $_->{colid} }{depend} || [] }, $tv->get_columns ];
	::ChangeWatcher
	(	$self->{watcher},
		$self->{array},
		$cols,
		sub{$self->UpdateID(@_)},
		sub{$self->RemoveID(@_)},
		 #keep list up to date with the filter in playlist mode
		($self->{mode} eq 'playlist' ? sub {$self->QueueIDsToAdd(@_)} : undef ),
		($self->{mode} eq 'playlist' && !$::ListMode ? $self->{filter} : undef )
	);
}

sub PopupContextMenu
{	my ($self,$tv,$event)=@_;
	my @IDs=$self->GetSelectedIDs;
	$::LEvent=$event;
	my %args=(self => $self, mode => $self->{type}, IDs => \@IDs, listIDs => $self->{array});
	::PopupContextMenu(\@::SongCMenu,\%args ) if @{$self->{array}};
}

sub GetSelectedIDs
{	my $self=$_[0];
	my @rows=$self->child->get_selection->get_selected_rows;
	my @IDs=map $self->{array}[$_->to_string], @rows;
	return @IDs;
}

sub PlaySelected
{	my $self=$_[0];
	my @IDs=$self->GetSelectedIDs;
	::Select(song=>'first',play=>1,staticlist => \@IDs ) if @IDs;
}
sub EnqueueSelected
{	my $self=$_[0];
	my @IDs=$self->GetSelectedIDs;
	::Enqueue(@IDs) if @IDs;
}

sub drag_received_cb
{	my ($tv,$type,$dest,@IDs)=@_;
	$tv->signal_stop_emission_by_name('drag_data_received'); #override the default 'drag_data_received' handler on GtkTreeView
	if ($type==::DRAG_FILE) #convert filenames to IDs
	{	$::Options{test}=$IDs[0];
		@IDs=map @$_,grep ref,map ::ScanFolder(::decode_url($_)), grep s#^file://##, @IDs;
		return unless @IDs;
	}
	my $self=$tv->parent;
	my (undef,$path,$pos)=@$dest;
	my $row=$path? ($path->get_indices)[0] : scalar@{$self->{array}};
	$row++ if $path && $pos && $pos eq 'after';
	my $store=$tv->get_model;
	if ($tv->{drag_is_source})
	{	for my $oldrow (reverse map $_->to_string, $tv->get_selection->get_selected_rows)
		{	$store->rowremove($oldrow);
			$row-- if $row>$oldrow;
		}
	}
	my @newpaths;
	$store->rowinsert($row,@IDs);
	if ($tv->{drag_is_source})
	{	$tv->get_selection->select_range( Gtk2::TreePath->new($row), Gtk2::TreePath->new($row+@IDs-1) );
	}
	$self->OnChange;
}

sub drag_motion_cb
{	my ($tv,$context,$x,$y,$time)=@_;# warn "drag_motion_cb @_";
	::drag_checkscrolling($tv,$context,$y);
	my ($path,$pos)=$tv->get_dest_row_at_pos($x,$y);	#FIXME sometimes : "Gtk-CRITICAL **: gtk_tree_view_get_dest_row_at_pos: assertion `drag_x >= 0' failed"
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
	my $row=($tv->get_cursor)[0]->to_string;
	my $ID=$self->{array}[$row];
	::Enqueue($ID);
}

sub sel_changed_cb
{	my $treesel=$_[0];
	my $tv=$treesel->get_tree_view;
	::HasChanged('Selection_'.$tv->parent->{group});
}
sub cursor_changed_cb
{	my $tv=$_[0];
	my $row=($tv->get_cursor)[0]->to_string;
	return unless defined $row;
	my $self=$tv->parent;
	my $ID=$self->{array}[$row];
	::HasChanged('SelectedID_'.$self->{group},$ID,$self->{group});
}

sub row_activated_cb
{	my ($tv,$path,$column)=@_;
	my $self=$tv->parent;
	::SongListActivate($self,$path->to_string,1);
}

sub PlaylistUpdate
{	my $self=$_[0];
	return unless $self->{mode} eq 'playlist';
	return if $self->{from_playlist};
	$self->{from_playlist}=1;
	::Select(song=>'trykeep', staticlist=>$self->{array} );
	$self->{from_playlist}=undef;
}

sub SetFilter
{	my ($self,$filter)=@_;
	my $list;
	if ($self->{hideif} eq 'nofilter')
	{	$self->Hide($filter->is_empty);
		return if $filter->is_empty;
	}
	if ($self->{mode} eq 'playlist')
	{	if ($self->{from_playlist})	{ $filter=$::PlayFilter || Filter->new; $list=\@::ListPlay; }
		else				{ ::Select( filter=>::GetFilter($self) ); return; }
	}
	$self->{filter}=$filter;
	$self->{IDsToAdd}=[];
	$self->update_begin;
	@{ $self->{array} }= defined $list ? @$list : @{ $filter->filter };
	if ($list) { $self->OnChange; } #doesn't need to be sorted but needs to call OnChange which is otherwise called at the end of SortList
	else { ::SortList( $self->{array}, $self->{sort} ); }
	$self->update_end;
}

sub update_begin
{	$_[0]->child->set_model(undef);
}
sub update_end
{	my $self=$_[0];
	my $tv=$self->child;
	$tv->set_model($self->{store});
#	$tv->set_search_column($self->{searchcol}); #setting model to undef reset search_column => re-set it
#	$tv->scroll_to_cell(Gtk2::TreePath->new(0)) if @{$self->{array}}>0;
	# test about a "Modification of a read-only value attempted" error
	my $row=$_[1] || 0;
	$row=Gtk2::TreePath->new($row) unless ref $row;
	$tv->scroll_to_cell($row,undef,::TRUE,0,0) if @{$self->{array}}>0;
#
	$self->UpdateSelID;
	$self->UpdateWatcher;
}

sub UpdateSelID
{	my $self=$_[0];
	$self->{store}->updateboldrow;
	$self->FollowSong if $self->{TogFollow};
}

sub FollowSong
{	my $self=$_[0];
	my $tv=$self->child;
	#$tv->get_selection->unselect_all;
	my $rowplaying=$tv->get_model->{boldrow};
	if ($rowplaying>-1)
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
	{ ::HasChanged('SelectedID_'.$self->{group},$::SongID,$self->{group}); }
}

sub Sort
{	my ($self,$sort)=@_;
	if ($self->{mode} eq 'playlist' && !$self->{from_playlist})
	{	::Select('sort'=>$sort);return;
	}
	warn "Reordering... ($sort) \n" if $::debug;
	my $tv=$self->child;
	my $treesel=$tv->get_selection;
	$self->{sort}=$sort;
	my $array=$self->{array};
	my @selected=map $array->[ $_->to_string ], $treesel->get_selected_rows;
	#@selected now contains selected IDs
	$treesel->unselect_all;
	$self->update_begin;
	if ($self->{IDsToAdd}) {push @$array,@{$self->{IDsToAdd}}; $self->{IDsToAdd}=[];}
	::SortList($array,$sort);
	$self->update_end;
	my @order;
	#restore selection
	$order[ $$array[$_] ]=$_ for 0..$#$array;
	#$order[$ID] contains the new row number of $ID
	$treesel->select_path( Gtk2::TreePath->new($order[$_]) ) for @selected;
	warn "Reordering...done\n" if $::debug;
	$self->UpdateSortIndicator;
	$self->OnChange;
}

sub OnChange	#the list in the treeview has changed
{	my $self=$_[0];
	if ($self->{mode} eq 'list')
	{	$self->{listbusy}=1;
		my $name=$self->{listname};
		my $listref=defined $name ? $::SavedLists{$name} : \@::Queue;
		@$listref=@{ $self->{array} };

		if (defined $name)	{ ::HasChanged('SavedLists',$name); }
		else			{ ::HasChanged('Queue'); }

		delete $self->{listbusy};
	}
	my $array=$self->{array};
	$self->Hide(!scalar @$array) if $self->{hideif} eq 'empty';
	::HasChanged('List_'.$self->{group},$array);
	&{ $self->{OnChange} }($self) if $self->{OnChange};
}
sub UpdateList	# update the list when the watched list has changed
{	my ($self,$type,@extra)=@_;
	return if $self->{listbusy};
	my $listref;
	my $name=$self->{listname};
	if (defined $name)
	{	return unless defined $type && $name eq $type;
		$type=$extra[0];
		if ($type && $type eq 'renamedto') { $self->SetList($extra[1],1); return; }
		elsif ($type && $type eq 'remove') {return}
		$listref=$::SavedLists{$name};
	}
	else {$listref=\@::Queue}
	my $array=$self->{array};
	$type||='';
	my $store=$self->child->get_model;
	if ($type eq 'shift')
	{	$store->rowremove(0);
		$self->UpdateWatcher;
	}
	elsif ($type eq 'push')
	{	my $row=@$array;
		$store->rowinsert($row,@$listref[$row..$#$listref]);
		$self->UpdateWatcher;
	}
	elsif ($type eq 'action') {}#FIXME should be a different watcher
	else
	{	$self->update_begin;
		@$array=@$listref;
		$self->update_end;
	}
	$self->OnChange;
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

sub SetList
{	my ($self,$name,$noupdate)=@_;
	$self->{mode}='list';
	$self->{type}= defined $name ? 'L' : 'Q';
	$self->{listname}=$name;
	$self->UpdateList($name) unless $noupdate;
	::Watch($self,(defined $name ? 'SavedLists' : 'Queue'),\&UpdateList);
	#$self->get_toplevel->set_title( _("Editing list : ").$name ) if $self->{changetitle};
}

sub SetType
{	my ($self,$type,$extra,$noupdate)=@_;

	::UnWatch($self,$_) for qw/SavedLists Queue/;
	delete $self->{listname};

	$self->{type}=$type;
	if ($type eq 'L')
	{	$self->{mode}='list';
		$self->{listname}=$extra;
		$self->UpdateList($extra) unless $noupdate;
		::Watch($self,'SavedLists',\&UpdateList);
		#$self->get_toplevel->set_title( _("Editing list : ").$name ) if $self->{changetitle};
	}
	elsif ($type eq 'Q')
	{	$self->{mode}='list';
		$self->UpdateList() unless $noupdate;
		::Watch($self,'Queue',\&UpdateList);
	}
	elsif ($type eq 'B')
	{
	}
}

sub MoveOne
{	my ($self,$up)=@_;
	my $listref=$self->{array};
	my $selection=$self->child->get_selection;
	my @rows=map $_->to_string, $selection->get_selected_rows;
	my @newsel;
	#my ($path)=$self->child->get_visible_range;
	#$self->update_begin;
	while (@rows)
	{	my $cur=my $last=my $first=shift @rows;
		$cur=$last=shift @rows while @rows && $rows[0]==$cur+1;
		if ($up)
		{	if ($first==0) { push @newsel,$first..$last; next; }
			splice @$listref,$last,0,splice(@$listref,$first-1,1);
			push @newsel,($first-1)..($last-1);
		}
		else
		{	if ($last==$#$listref) { push @newsel,$first..$last; next; }
			splice @$listref,$first,0,splice(@$listref,$last+1,1);
			push @newsel,($first+1)..($last+1);
		}
	}
	#$self->update_end($path);
	my ($first,$last)=$self->child->get_visible_range;
	$self->child->get_model->rowchanged($_) for $first->to_string .. $last->to_string;
	$self->SetSelection(\@newsel);
	$self->OnChange;
}
sub MoveMax
{	my ($self,$top)=@_;
	my $listref=$self->{array};
	my $selection=$self->child->get_selection;
	my @newsel;
	my @rows=reverse map $_->to_string, $selection->get_selected_rows;
	return unless @rows;
	#@rows=sort {$b <=> $a } @rows; #if get_selection return unsorted row number
	my @IDs;
	$self->update_begin;
	unshift @IDs,splice @$listref,$_,1 for @rows;
	if ($top)
	{	unshift @$listref,@IDs;
		@newsel=0..(@rows-1);
	}
	else #bottom
	{	push @$listref,@IDs;
		@newsel=(@$listref-@rows)..$#$listref;
	}
	$self->update_end( ($top? 0 : $#$listref) );
	$self->SetSelection(\@newsel);
	$self->OnChange;
}
sub SetSelection
{	my ($self,$select)=@_;
	my $treesel=$self->child->get_selection;
	$treesel->unselect_all;
	$treesel->select_path( Gtk2::TreePath->new($_) ) for @$select;
}

sub Empty
{	my $self=shift;
	$self->update_begin;
	@{ $self->{array} }=();
	$self->update_end;
	$self->OnChange;
}

sub RemoveSelected
{	my $self=shift;
	my $tv=$self->child;
	my $store=$tv->get_model;
	my @rows=sort {$b <=> $a} map $_->to_string, $tv->get_selection->get_selected_rows;
	$tv->get_selection->unselect_all;
	$store->rowremove($_) for @rows;
	$self->OnChange;
}

sub RemoveID
{	my $self=$_[0];
	my $store=$self->child->get_model;
	my $array=$self->{array};
	my %toremove;
	$toremove{$_}=undef for @_;
	warn "remove ID @_\n" if $::debug;
	my $row=@$array;
	while ($row-->0)
	{ my $ID=$$array[$row];
	  next unless exists $toremove{$ID};
	  $store->rowremove($row);
	  #delete $toremove{$ID};
	  #last unless (keys %toremove);
	}
	my $toadd=$self->{IDsToAdd};
	if (@$toadd && keys %toremove)
	{ @$toadd=grep !exists $toremove{$_},@$toadd; }
}
sub UpdateID
{	my $self=$_[0];
	my $array=$self->{array};
	my $store=$self->child->get_model;
	my %updated;
	warn "update ID @_\n" if $::debug;
	$updated{$_}=undef for @_;
	my $row=@$array;
	while ($row-->0)	#FIXME maybe only check displayed rows
	{ my $ID=$$array[$row];
	  next unless exists $updated{$ID};
	  $store->rowchanged($row);
	  #delete $updated{$ID};
	  #last unless (keys %updated);
	}
}

sub AddQueuedIDs
{	my $self=$_[0];
	return unless @{$self->{IDsToAdd}};
	$self->{from_playlist}=1;
	$self->Sort($self->{'sort'});
	$self->{from_playlist}=undef;
}

sub QueueIDsToAdd	#FIXME IDs are not re-checked by watcher until they are actually added, could be no longer matching the filter
{	my $self=shift;
	push @{$self->{IDsToAdd}},@_;
	::IdleDo('7_SongListAdd_'.$self,1500,\&AddQueuedIDs,$self)
}

# methods for playlist mode
sub SetPlaylistSort
{	my $self=$_[0];
	$self->{from_playlist}=1;
	my $sort= $::Options{Sort}=~m/^r/ ? $::Options{AltSort} : $::Options{Sort};
	$self->Sort($sort) if $sort ne $self->{sort};;
	$self->{from_playlist}=undef;
}
sub SetPlaylistFilter
{	my $self=$_[0];
	$self->{from_playlist}=1;
	$self->SetFilter;
	$self->{from_playlist}=undef;
}

################################################################################
package SongStore;
use Glib qw(TRUE FALSE);
use Gtk2;

my (%Columns,@Value,@Type);

use Glib::Object::Subclass
	Glib::Object::,
	interfaces => [Gtk2::TreeModel::],
	properties => [ Glib::ParamSpec->scalar
			('array',		 #name
			 'array',		 #nickname
			 'arrayref',		 #blurb
			 [qw/readable writable/] #flags
			)],
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
	my $self = shift;
	# Random int to check whether an iter belongs to our model
	$self->{stamp} = sprintf '%d', rand (1<<31);
	$self->{boldrow}=-1;
}
sub FINALIZE_INSTANCE
{	#my $self = shift;
	# free all records and free all memory used by the list
}
sub GET_FLAGS { [qw/list-only iters-persist/] }
sub GET_N_COLUMNS { $#Value }
sub GET_COLUMN_TYPE { $Type[ $_[1] ]; }
sub GET_ITER
{	my ($self, $path) = @_; #warn "GET_ITER\n";
	die "no path" unless $path;

	# we do not allow children
	# depth 1 = top level; a list only has top level nodes and no children
#	my $depth   = $path->get_depth;
#	die "depth != 1" unless $depth == 1;

#	my @indices = $path->get_indices;
#	my $n = $indices[0]; # the n-th top level row
#	my $n=($path->get_indices)[0];
	my $n=$path->get_indices;	#return only one value because it's a list
	return undef if $n >= @{$self->{array}} || $n < 0;

	#my $ID = $self->{array}[$n];
	#die "no ID" unless defined $ID;
	#return iter :
	#return [ $self->{stamp}, $n, undef, undef ];
	return [ $self->{stamp}, $n, $::Songs[ $self->{array}[$n] ] , undef ];
}

sub GET_PATH
{	my ($self, $iter) = @_; #warn "GET_PATH\n";
	die "no iter" unless $iter;

	my $path = Gtk2::TreePath->new;
	$path->append_index ($iter->[1]);
	return $path;
}

sub GET_VALUE
{	goto &{ $Value[$_[2]] };
#	my ($self, $iter, $column) = ($_[0],$_[1],$_[2]); #warn "GET_VALUE\n";
#	#die "bad iter" unless $iter;
#	return  ( ($self->{boldrow} == $iter->[1])
#		  ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL
#		) if $column==::SONGLAST+1;
#	#return undef if $column > ::SONGLAST;
#	my $val=$iter->[2][$column];
#
#	my $t=$Type[$column];
#	#use POSIX qw(strftime); $now_string = strftime '%d-%m-%y %H:%M', localtime;
#	return  (!$t	  )? $val					:
#		($t eq 'd')? ($val ? scalar localtime $val : 'never')	:
#		($t eq 'l')? (sprintf '%d:%02d',$val/60,$val%60)	:
#		($t eq 'f')? (join ', ',split(/\x00/,$val))		:
#			     $val;
#	#return $ref->[$column];
}

sub ITER_NEXT
{	my $self=$_[0];		#warn "GET_NEXT\n";#my ($self, $iter) = @_;
#	return undef unless $_[1];
	my $n=$_[1]->[1]; #$iter->[1]
	return undef unless ++$n < @{$self->{array}};
	return [ $self->{stamp}, $n, $::Songs[ $self->{array}[$n] ], undef ];
}

sub ITER_CHILDREN
{	my ($self, $parent) = @_; #warn "GET_CHILDREN\n";
	# this is a list, nodes have no children
	return undef if $parent;

	# parent == NULL is a special case; we need to return the first top-level row
	# No rows => no first row
	return undef unless @{ $self->{array} };

	# Set iter to first item in list
	return [ $self->{stamp}, 0, $::Songs[ $self->{array}[0] ],undef ];
	#return [ $self->{stamp}, 0, undef, undef ];
}
sub ITER_HAS_CHILD { FALSE }
sub ITER_N_CHILDREN
{	my ($self, $iter) = @_; #warn "ITER_N_CHILDREN\n";
	# special case: if iter == NULL, return number of top-level rows
	return ( $iter? 0 : scalar @{$self->{array}} );
}
sub ITER_NTH_CHILD {
	my ($self, $parent, $n) = @_; #warn "ITER_NTH_CHILD\n";
	# a list has only top-level rows
	return undef if $parent;
	# special case: if parent == NULL, set iter to n-th top-level row
	return undef if $n >= @{$self->{array}};

	#my $ID = $self->{array}[$n];
	#die "no record" unless defined $ID;
	#return [ $self->{stamp}, $n, undef, undef ];
	return [ $self->{stamp}, $n,  $::Songs[ $self->{array}[$n] ] , undef ];
}
sub ITER_PARENT { FALSE }

sub search_equal_func
{	my ($self,$col,$string,$iter)=@_;
	$iter= $iter->to_arrayref($self->{stamp});
	#my $r; for (::SONG_TITLE,::SONG_ALBUM,::SONG_ARTIST) { $r=index uc$iter->[2][$_], uc$string; last if $r==0 } return $r;
	index uc$iter->[2][::SONG_TITLE], uc$string;
}

sub rowremove
{	my ($self,$row)=($_[0],$_[1]);
	splice @{$self->{array}}, $row ,1;
	if    ($self->{boldrow}>$row)  { $self->{boldrow}-- }
	elsif ($self->{boldrow}==$row) { $self->{boldrow}=-1}
	$self->row_deleted( Gtk2::TreePath->new($row) );
}
sub rowinsert
{	my ($self,$row,@IDs)=@_;
	splice @{ $self->{array} }, $row, 0, @IDs;
	$self->{boldrow}+=@IDs if $self->{boldrow}>=$row;
	for (@IDs)
	{	$self->{boldrow}=$row if $self->{boldrow}==-1 && defined $::SongID && $_==$::SongID;
		$self->row_inserted( Gtk2::TreePath->new($row), $self->get_iter_from_string($row) );
		$row++;
	}
}
sub rowchanged
{	my ($self,$row)=($_[0],$_[1]);
	my $iter=$self->get_iter_from_string($row);
	return unless $iter;
	$self->row_changed( $self->get_path($iter), $iter);
}

sub updateboldrow
{	my $self=$_[0];
	my $array=$self->{array};
	if ($self->{boldrow}!=-1)
	{	my $row=$self->{boldrow};
		$self->{boldrow}=-1;
		$self->rowchanged($row);
	}
	if (defined $::SongID)
	{ for my $row (0..$#$array)		#search row of currently playing
	  { if ($::SongID==$$array[$row])	#add bold to currently playing
	    {	$self->{boldrow}=$row;
		$self->rowchanged($row);
		last;
	    }
	  }
	}
}

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
	if ($but==1) # do not clear multi-row selection if button press on a selected row (to allow dragging selected rows)
	{{	 last if $event->get_state * ['shift-mask', 'control-mask']; #don't interfere with default if control or shift is pressed
		 last unless $sel->count_selected_rows  > 1;
		 my $path=$tv->get_path_at_pos($event->get_coords);
		 last unless $path && $sel->path_is_selected($path);
		 $tv->{pressed}=1;
		 return 1;
	}}
	if ($but==3)
	{	my $add= $event->get_state * ['shift-mask', 'control-mask'];
		my $path=$tv->get_path_at_pos($event->get_coords);
		if ($path && !$sel->path_is_selected($path))
		{	$sel->unselect_all unless $add;
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
(	filter	=> [SavedTree		=> 'F',			0b001, _"Filter"],
	list	=> [SavedTree		=> 'L',			0b001, _"List"],
	savedtree=>[SavedTree		=> 'FL',		0b001, _"Saved"],
	artist	=> [FilterList		=> ::SONG_ARTIST,	0b111],
	album	=> [FilterList		=> ::SONG_ALBUM,	0b110],
	added	=> [FilterList		=> ::SONG_ADDED,	0b110],
	modif	=> [FilterList		=> ::SONG_MODIF,	0b110],
	lastplay=> [FilterList		=> ::SONG_LASTPLAY,	0b110],
	genre	=> [FilterList		=> ::SONG_GENRE,	0b111],
	date	=> [FilterList		=> ::SONG_DATE,		0b110],
	label	=> [FilterList		=> ::SONG_LABELS,	0b111],
	rating	=> [FilterList		=> ::SONG_RATING,	0b110],
	folder	=> [FolderList		=> ::SONG_UPATH,	0b010],
	filesys	=> [Filesystem		=> '',			0b000, _"Filesystem"],
);

my @picsize_menu=
(	_("no pictures")	=>  0,
	_("automatic size")	=>'a',
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

my %sort_menu=
(	year	=> _("year"),
	year2	=> _("year (highest)"),
	alpha	=> _("alphabetical"),
	songs	=> _("number of songs in filter"),
	'length'=> _("length of songs"),
);
my %sort_menu_album=
(	%sort_menu,
	artist => _("artist")
);

my %timespan_menu=
(	year 	=> _("year"),
	month	=> _("month"),
	day	=> _("day"),
);

our @MenuPageOptions=
(	{ label => _"show pictures",	code => sub { my $self=$_[0]{self}; $self->{picsize}=$_[1]; $self->Fill('optchanged'); },	test => sub {$_[0]{self}{mode} eq 'list'},
	  submenu => \@picsize_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{picsize}}, istrue => 'aa' },
	{ label => _"show info",	code => sub { my $self=$_[0]{self}; $self->{showinfo}^=1; $self->Fill('optchanged'); },
	  check => sub {$_[0]{self}{showinfo}}, istrue => 'aa', test => sub {$_[0]{self}{mode} eq 'list'}, },
	{ label => _"picture size",	code => sub { my $self=$_[0]{self}; $self->{mpicsize}=$_[1]; $self->Fill('optchanged'); },	test => sub {$_[0]{self}{mode} eq 'mosaic'},
	  submenu => \@mpicsize_menu,	submenu_ordered_hash => 1,  check => sub {$_[0]{self}{mpicsize}}, istrue => 'aa' },
	{ label => _"sort by",		code => sub { my $self=$_[0]{self}; $self->{sort}=$_[1]; $self->Fill('optchanged'); },
	  check => sub {$_[0]{self}{sort}}, istrue => 'aa', submenu => sub { $_[0]{col}==::SONG_ALBUM ? \%sort_menu_album : \%sort_menu; }, submenu_reverse => 1 },
	{ label => _"Group by",		code => sub { my $self=$_[0]{self}; $self->{timespan}=$_[1]; $self->Fill('rehash'); },
	  check => sub {$_[0]{self}{timespan}}, submenu => \%timespan_menu, submenu_reverse => 1,
	  test => sub { my $c=$_[0]{col}; $c==::SONG_ADDED || $c==::SONG_LASTPLAY || $c==::SONG_MODIF },
	},
	{ label => _"cloud mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'cloud' ? 'list' : 'cloud'),1); },
	  check => sub {$_[0]{self}{mode} eq 'cloud'}, },
	{ label => _"mosaic mode",	code => sub { my $self=$_[0]{self}; $self->set_mode(($self->{mode} eq 'mosaic' ? 'list' : 'mosaic'),1);},
	  check => sub {$_[0]{self}{mode} eq 'mosaic'}, istrue => 'aa' },
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
	{ label=> _"Rename folder", code => sub { ::AskRenameFolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Open folder", code => sub { ::openfolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist', },
	#{ label=> _"move folder", code => sub { ::MoveFolder($_[0]{utf8pathlist}[0]); }, onlyone => 'utf8pathlist',	test => sub {!$::CmdLine{ro}}, },
	{ label=> _"Scan for new songs", code => sub { ::IdleScan( map(::filename_from_unicode($_), @{$_[0]{utf8pathlist}}) ); },
		notempty => 'utf8pathlist' },
	{ label=> _"Check for updated/removed songs", code => sub { ::IdleCheck(  @{ $_[0]{filter}->filter } ); },
		isdefined => 'filter', stockicon => 'gtk-refresh', istrue => 'utf8pathlist' }, #doesn't really need utf8pathlist, but makes less sense for non-folder pages
	{ label=> _"Set Picture", code => sub { my $key=$_[0]{keylist}[0]; ::ChooseAAPicture(undef,$_[0]{col},$key); }, stockicon => 'gmb-picture', onlyone=> 'keylist', istrue => 'aa' },
#	{ separator=>1 },
	{ label => _"Options", submenu => \@MenuPageOptions, stock => 'gtk-preferences', isdefined => 'col' },
	{ label => _"Show buttons",	code => sub { my $fp=$_[0]{filterpane}; $fp->{hidebb}^=1; if ($fp->{hidebb}) {$fp->{bottom_buttons}->hide} else {$fp->{bottom_buttons}->show} },
	  check => sub {!$_[0]{filterpane}{hidebb};} },
);

sub new
{   my ($class,$opt1,$opt2)=@_;
    my $self = bless Gtk2::VBox->new(FALSE, 6), $class;
    $self->{SaveOptions}=\&SaveOptions;
    my $pages= $opt1->{pages} || 'savedtree|artist|album|genre|date|label|folder|added|lastplay|rating';
    $pages=$opt2->{pages} if $opt2->{pages} && length($opt2->{pages})==length($pages);
    my @pids=split /\|/, $pages;
    my $nb=$opt1->{nb};
    $nb=1 unless defined $nb;
    $self->{nb}=$nb;
    my $group=$self->{group}=$opt1->{group};
    $self->{min}=$opt2->{min}||1;

    my $spin=Gtk2::SpinButton->new( Gtk2::Adjustment->new($self->{min}, 1, 9999, 1, 10, 0) ,10,0  );
    $spin->signal_connect( value_changed => sub { $self->update($_[0]->get_value); } );
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
    $::Tooltips->set_tip($ResetB, (	$nb==1? _"reset primary filter"  :
					$nb==2?	_"reset secondary filter":
						::__x(_"reset filter {nb}",nb =>$nb)
				  ) );
    $::Tooltips->set_tip($InterB, _"toggle Intersection mode");
    $::Tooltips->set_tip($InvertB,_"toggle Invert mode");
    $::Tooltips->set_tip($spin,   _"minimum number of songs"); #FIXME
    $::Tooltips->set_tip($optB,   _"options");

    my $notebook = Gtk2::Notebook->new;
    $notebook->set_scrollable(TRUE);
    $notebook->popup_enable;
    $notebook->set_show_tabs(FALSE) if @pids==1;

    my $setpage=0;
    my @fieldlist;
    for my $pid (@pids)
    {	next unless $Pages{$pid};
	my ($package,$col,undef,$label)=@{ $Pages{$pid} };
	my $page=$package->new($col,$opt1,$opt2,$pid);
	$page->{pid}=$pid;
	if ($col=~m/^\d+$/)
	{	$self->{$col}=$page;
		push @fieldlist,$col;
		$label=$::TagProp[$col][0];
	}
	$notebook->append_page( $page, Gtk2::Label->new($label) );
	$notebook->set_tab_reorderable($page,TRUE);
	if ($opt2->{page} && $opt2->{page} eq $pid) { $setpage=$notebook->get_n_pages-1 }
    }
    $self->{fieldlist}=\@fieldlist;

    $self->pack_end($hbox, FALSE, FALSE, 0);
    $notebook->show_all; #needed to set page in this sub

    $hbox->show_all;
    $_->set_no_show_all(1) for $spin,$InterB,$optB;
    $hbox->set_no_show_all(1);
    $self->{bottom_buttons}=$hbox;
    $notebook->signal_connect(switch_page => sub
	{	my $p=$_[0]->get_nth_page($_[2]);
		$self->{page}=$p->{pid};
		my $mask=$Pages{$p->{pid}}[2];
		if	($mask & 0b100)	{$optB->show}
		else			{$optB->hide}
		if	($mask & 0b010)	{$spin->show}
		else			{$spin->hide}
		if	($mask & 0b001)	{$InterB->show}
		else			{$InterB->hide}
	});

    $notebook->set_current_page( $setpage );

    $opt2->{hidebb}=$opt1->{hide} unless exists $opt2->{hidebb};
    $self->{hidebb}=$opt2->{hidebb}||0;
    $hbox->hide if $self->{hidebb};
    $self->add($notebook);
    $self->{resetbutton}=$ResetB;
    $self->{notebook}=$notebook;
    $self->{watcher}=::AddWatcher();
    $self->signal_connect(destroy => \&removewatchers);
    ::WatchFilter($self,$opt1->{group},\&updatefilter);
    return $self;
}

sub SaveOptions
{	my $self=shift;
	my %opt;
	$opt{hidebb}=$self->{hidebb};
	$opt{page}=$self->{page};
	$opt{min}=$self->{min};
	$opt{pages}=join '|', map $_->{pid}, $self->{notebook}->get_children;
	for my $col (::SONG_ARTIST,::SONG_ALBUM,::SONG_GENRE,::SONG_DATE,::SONG_LABELS)
	{	my $page=$self->{$col};
		next unless $page;
		my $pid=$page->{pid};
		if (my $c=$page->{mode})
		{	$opt{$pid.'mode'}=$c if $c ne 'list'; #cloud or mosaic mode
		}
		if ($col==::SONG_ARTIST || $col==::SONG_ALBUM)
		{	$opt{$pid.'psize'}=$page->{picsize};
			$opt{$pid.'info'}=$page->{showinfo};
			$opt{$pid.'sort'}=$page->{'sort'};
			$opt{$pid.'mpsize'}=$page->{mpicsize};
		}
		elsif ($col==::SONG_ADDED || $col==::SONG_MODIF || $col==::SONG_LASTPLAY)
		{	$opt{$pid.'timespan'}=$page->{timespan};
		}
	}
	return \%opt;
}

sub updatefilter
{	my ($self,undef,undef,$nb)=@_;
	my $group=$self->{group};
	my $mynb=$self->{nb};
	return if $nb && $nb> $mynb;
	warn "Filtering list for FilterPane$mynb\n" if $::debug;
	my $currentf=$::Filters_nb{$group}[$mynb];
	$self->{resetbutton}->set_sensitive( !Filter::is_empty($currentf) );
	my $filt=Filter->newadd(TRUE, map($::Filters_nb{$group}[$_],0..($mynb-1)) );
	return if $self->{list} && Filter::are_equal($filt,$self->{filter});
	$self->{filter}=$filt;

	my $lref=$filt->is_empty ? \@::Library
				 : $filt->filter;
	$self->{list}=$lref;

	#warn "filter :".$filt->{string}.($filt->{source}?  " with source" : '')." songs=".scalar(@$lref)."\n";
	my $updatesub=sub { ::IdleDo('9_FP'.$self,1000,\&update,$self); };
	my $addsub=sub { push @$lref,@_; &$updatesub; };
	my $rmsub=sub { my %h; $h{$_}=undef for @_; @$lref=grep !exists $h{$_},@$lref; &$updatesub; };
	my $refiltersub=sub { ::IdleDo('9_FPfull'.$self,5000,\&updatefilter,$self); };
	delete $::ToDo{'9_FP'.$self};
	delete $::ToDo{'9_FPfull'.$self};
	if ($lref == \@::Library)
	{	$lref=undef;
		$addsub=$rmsub= $updatesub;	#don't need and MUSTN'T update @$lref
	}
	::ChangeWatcher( $self->{watcher},$lref,
		$self->{fieldlist},
		$updatesub,$rmsub,$addsub,$filt,$refiltersub );
	$self->update;
}

sub update
{  my ($self,$min)=@_;
   if ($min) { $self->{min}=$min; }
   if (!$self->{list} || $::ToDo{'9_FPfull'.$self}) { $self->updatefilter; return; }
   warn "Updating FilterPane".$self->{nb}."\n" if $::debug;
   if (!$min || $::ToDo{'9_FP'.$self})
   {	$self->{$_}{hash}=undef for @{ $self->{fieldlist} };
	delete $::ToDo{'9_FP'.$self};
   }
   for my $col (@{ $self->{fieldlist} })
   {	my $page=$self->{$col};
	$page->{valid}=0;		# set dirty flag for this col
	$page->Fill if $page->mapped;	# update now if col displayed
   }
}

sub removewatchers
{	my $self=shift;
	delete $::ToDo{'9_FP'.$self};
	delete $::ToDo{'9_FPfull'.$self};
	::RemoveWatcher( $self->{watcher} );
}

sub PopupContextMenu
{	my ($page,$event,$hash,$menu)=@_;
	$::LEvent=$event;
	my $self=::find_ancestor($page,__PACKAGE__);
	$hash->{filterpane}=$self;
	$menu||=\@cMenu;
	::PopupContextMenu($menu, $hash);
}

sub PopupOpt
{	my ($but,$event)=@_;
	my $self=::find_ancestor($but,__PACKAGE__);
	$::LEvent=$event;
	my $nb=$self->{notebook};
	my $page=$nb->get_nth_page( $nb->get_current_page );
	my $aa= ($page->{col}==::SONG_ARTIST || $page->{col}==::SONG_ALBUM);
	::PopupContextMenu(\@MenuPageOptions, { self=>$page, aa=>$aa, col => $page->{col}} );
	return 1;
}

package FilterList;
use Gtk2;
use base 'Gtk2::VBox';

our %TimeSpan=
(	year => [ '%Y', '%Y',
			sub { ::mktime(0,0,0,1,0,$_[0]-1900) },
			sub { return 0 unless $_[0]; my $y= (localtime($_[0]))[5]; return ::mktime(0,0,0,1,0,$y+1)-1; },
		],
	month=> [ '%Y%m', '%b %Y',
			sub { my ($y,$m)= $_[0]=~m/^(\d{4})(\d\d)$/; return ::mktime(0,0,0,1,$m-1,$y-1900); },
			sub { return 0 unless $_[0]; my ($m,$y)= (localtime($_[0]))[4,5]; $m++; if ($m==12) {$m=0;$y++} return ::mktime(0,0,0,1,$m,$y)-1; },
		],
	day  => [ '%Y%m%d', '%x',
			sub { my ($y,$m,$d)= $_[0]=~m/^(\d{4})(\d\d)(\d\d)$/; return ::mktime(0,0,0,$d,$m-1,$y-1900); },
			sub { return 0 unless $_[0]; my ($d,$m,$y)= (localtime($_[0]))[3,4,5]; return ::mktime(59,59,23,$d,$m,$y); },
		],
);

our @hashsub;
{ no warnings 'uninitialized';
  $hashsub[::SONG_RATING]= sub { my $lref=$_[0]; my %h; $h{ $::Songs[$_][::SONG_RATING] }++  for @$lref; return \%h };
  $hashsub[::SONG_DATE]= sub { my $lref=$_[0]; my %h; $h{ $::Songs[$_][::SONG_DATE] }++  for @$lref; return \%h };
  $hashsub[::SONG_ALBUM]=sub { my $lref=$_[0]; my %h; $h{ $::Songs[$_][::SONG_ALBUM] }++ for @$lref; return \%h };
  $hashsub[::SONG_ARTIST]=sub{ my $lref=$_[0]; my %h; $h{$_}++ for map split(/$::re_artist/o,$::Songs[$_][::SONG_ARTIST]),@$lref; return \%h };
  $hashsub[::SONG_GENRE]=sub { my $lref=$_[0]; my %h; $h{$_}++ for map split(/\x00/, $::Songs[$_][::SONG_GENRE]), @$lref; return \%h };
  $hashsub[::SONG_LABELS]=sub { my $lref=$_[0]; my %h; $h{$_}++ for map split(/\x00/, $::Songs[$_][::SONG_LABELS]), @$lref; return \%h };
  $hashsub[::SONG_ADDED]=sub { my $lref=$_[0]; my ($f,undef,$sub)=@{$TimeSpan{$_[1]}}; my %h; $h{ ::strftime($f,localtime($::Songs[$_][::SONG_ADDED])) }++  for @$lref; %h= map {&$sub($_),$h{$_}} keys %h; return \%h };
  $hashsub[::SONG_MODIF]=sub { my $lref=$_[0]; my ($f,undef,$sub)=@{$TimeSpan{$_[1]}}; my %h; $h{ ::strftime($f,localtime($::Songs[$_][::SONG_MODIF])) }++  for @$lref; %h= map {&$sub($_),$h{$_}} keys %h; return \%h };
  $hashsub[::SONG_LASTPLAY]=sub { my $lref=$_[0]; my ($f,undef,$sub)=@{$TimeSpan{$_[1]}}; my %h; $h{ ::strftime($f,localtime($::Songs[$_][::SONG_LASTPLAY]||0)) }++  for @$lref; %h= map {&$sub($_),$h{$_}} keys %h; my $zero=&$sub(::strftime($f,localtime(0))); $h{0}=delete $h{$zero} if exists $h{$zero}; return \%h };
  #$hashsub[::SONG_ARTIST]=sub { my $t=times;my $lref=$_[0]; my %h; $h{ $::Songs[$_][::SONG_ARTIST] }++  for @$lref;while (my($key,$v)=each %h) {my @k=split /$::re_artist/o,$key; if (@k>1) {$h{$_}+=$v for @k;delete $h{$key};}; }; warn (times-$t);return \%h };
  #$hashsub[::SONG_GENRE]=sub { my $t=times;my $lref=$_[0]; my %h; $h{ $::Songs[$_][::SONG_GENRE] }++  for @$lref;while (my($key,$v)=each %h) {my @k=split /\x00/,$key; if (@k>1) {$h{$_}+=$v for @k;delete $h{$key};}; }; warn (times-$t);return \%h };
}

my @colcmd;
$colcmd[::SONG_DATE]	='e';
$colcmd[::SONG_ALBUM]	='e';
$colcmd[::SONG_ARTIST]	='~';
$colcmd[::SONG_GENRE]	='f';
$colcmd[::SONG_LABELS]	='f';
$colcmd[::SONG_ADDED]	='b';
$colcmd[::SONG_MODIF]	='b';
$colcmd[::SONG_LASTPLAY]='b';
$colcmd[::SONG_RATING]='e';

sub new
{	my ($class,$col,$opt1,$opt2,$pid)=@_;
	my $self = bless Gtk2::VBox->new, $class;
	$self->{col}=$col;
	$self->{no_typeahead}=$opt1->{no_typeahead};

	if ($col==::SONG_ARTIST || $col==::SONG_ALBUM)
	{	::Watch($self,AAPicture => \&AAPicture_Changed);
		$self->{picsize}=	$opt2->{$pid.'psize'}|| 0;
		$self->{showinfo}=	$opt2->{$pid.'info'} || 0;
		$self->{sort}=		$opt2->{$pid.'sort'} || 'alpha';
		$self->{mpicsize}=	$opt2->{$pid.'mpsize'}|| 64;
	}
	elsif ($col==::SONG_ADDED || $col==::SONG_LASTPLAY || $col==::SONG_MODIF)
	{	$self->{timespan}=	$opt2->{$pid.'timespan'}|| 'year';
		$self->{sort}='numeric';
	}
	elsif ($col==::SONG_RATING) { $self->{sort}='numeric'; }

	#search box
	if ($col != ::SONG_DATE && $opt1->{searchbox} && $col!=::SONG_ADDED && $col!=::SONG_MODIF && $col!=::SONG_LASTPLAY && $col!=::SONG_RATING)
	{	$self->pack_start( make_searchbox() ,::FALSE,::FALSE,1);
	}
	::Watch($self,'SearchText_'.$opt1->{group},\&set_text_search);

	$self->{colcmd}=$col.$colcmd[$col];
	$self->signal_connect(map => \&Fill);

	my $sub=\&play_current;
	if ($opt1->{activate})
	{	$sub=\&enqueue_current	if $opt1->{activate} eq 'queue';
		$sub=\&add_current	if $opt1->{activate} eq 'addplay';
	}
	$self->{activate}=$sub;

	my $mode= $opt2->{$pid.'mode'} || 'list';
	$mode='cloud' if $opt2->{$pid.'cloud'}; #old option
	$self->set_mode($mode);

	return $self;
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

	my $drag_type=	$self->{col}==::SONG_ARTIST ? ::DRAG_ARTIST :
			$self->{col}==::SONG_ALBUM  ? ::DRAG_ALBUM  :
			::DRAG_FILTER;
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
	my $sw=Gtk2::ScrolledWindow->new;
#	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);

	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$sw->add($treeview);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_enable_search(!$self->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	my $col=$self->{col};
	my $column=Gtk2::TreeViewColumn->new;
	if ($col==::SONG_LABELS)
	{	my $renderer0=Gtk2::CellRendererPixbuf->new;
		$column->pack_start($renderer0,0);
		$column->set_cell_data_func($renderer0, sub { my (undef,$cell,$store,$iter)=@_; my $label=$store->get($iter,0); $cell->set('stock-id','label-'.$label) });
	}
	my $renderer=	($col==::SONG_ARTIST || $col==::SONG_ALBUM)
			? CellRendererAA->new
			: Gtk2::CellRendererText->new;
	$column->pack_start($renderer,1);
	if ($col==::SONG_ADDED || $col==::SONG_LASTPLAY || $col==::SONG_MODIF)
	{	$column->set_cell_data_func($renderer, sub { my ($column,$cell,$store,$iter)=@_; my $time=$store->get($iter,0); $cell->set(text=> $time ? ::strftime($TimeSpan{$self->{timespan}}[1],localtime($time)) : _"never" ) });
	}
	elsif ($col==::SONG_RATING) { $column->set_cell_data_func($renderer, sub { my ($column,$cell,$store,$iter)=@_; my $val=$store->get($iter,0); $cell->set(text=> $val eq '' ? _"default" : $val ) }); }
	else {$column->add_attribute($renderer, text => 0);}
	$treeview->append_column($column);

	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect(changed =>\&selection_changed_cb);

	$treeview->signal_connect( row_activated => sub
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			goto $self->{activate};
		});
	return ($sw,$treeview);
}

sub create_cloud
{	my $self=$_[0];
	$self->{mode}='cloud';
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('never','automatic');
	my $sub;
	my $col=$self->{col};
	if ($col==::SONG_ADDED || $col==::SONG_LASTPLAY || $col==::SONG_MODIF)
	{	$sub= sub { my $time=$_[0]; $time ? ::strftime($TimeSpan{$self->{timespan}}[1],localtime($time)) : _"never"; };
	}
	elsif ($col==::SONG_RATING)
	{	$sub= sub { my $val=$_[0]; $val eq '' ? _"default" : $val; };
	}
	my $cloud= Cloud->new(\&child_selection_changed_cb,\&get_fill_data,$self->{activate},\&enqueue_current,\&PopupContextMenu,$sub);
	$sw->add_with_viewport($cloud);
	return ($sw,$cloud);
}
sub create_mosaic
{	my $self=$_[0];
	$self->{mode}='mosaic';
	my $hbox=Gtk2::HBox->new(0,0);
	my $vscroll=Gtk2::VScrollbar->new;
	$hbox->pack_end($vscroll,0,0,0);
	my $mosaic= Mosaic->new(\&child_selection_changed_cb,\&get_fill_data,$self->{activate},\&enqueue_current,\&PopupContextMenu,$self->{col},$vscroll);
	$hbox->add($mosaic);
	return ($hbox,$mosaic);
}

sub drag_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	if ($self->{col}==::SONG_ARTIST || $self->{col}==::SONG_ALBUM)
	{	return @{$self->get_selected};
	}
	else
	{	my $filter=$self->get_selected_filters;
		return ($filter? $filter->{string} : undef);
	}
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
	my $vals=$self->get_selected;
	return undef unless @$vals;
	my $col=$self->{col};
	if ($col==::SONG_ADDED || $col==::SONG_MODIF || $col==::SONG_LASTPLAY)
	{	my $sub=$TimeSpan{$self->{timespan}}[3];
		@$vals=map $self->{colcmd}.$_.' '.&$sub($_) , @$vals;
	}
	else {	@$vals=map $self->{colcmd}.$_ , @$vals; }
	my $filterpane=::find_ancestor($self,'FilterPane');
	my $i=$filterpane->{inter} && $col!=::SONG_ALBUM && $col!=::SONG_DATE && $col!=::SONG_ADDED && $col!=::SONG_MODIF && $col!=::SONG_LASTPLAY && $col!=::SONG_RATING;
	my $filter=Filter->newadd($i,@$vals);
	$filter->invert if $filterpane->{invert};
	return $filter;
}
sub get_selected
{	my $self=$_[0];
	my @vals;
	if ($self->{mode} eq 'list')
	{	my $store=$self->{view}->get_model;
		my @rows=$self->{view}->get_selection->get_selected_rows;
		@vals=map $store->get_value($store->get_iter($_),0) , @rows;
	}
	else
	{	@vals=$self->{view}->get_selected;
	}
	return \@vals;
}

sub get_fill_data
{	my ($child,$opt)=@_;
	my $self=::find_ancestor($child,__PACKAGE__);
	my $filterpane=::find_ancestor($self,'FilterPane');
	my $col=$self->{col};
	$self->{hash}=undef if $opt && $opt eq 'rehash';
	my $href= $self->{hash} ||= &{ $hashsub[$col] }($filterpane->{list},$self->{timespan});
	$self->{valid}=1;
	my $min=$filterpane->{min};
	my $search=$self->{search};
	my @l=grep $$href{$_} >= $min, keys %$href;
	@l=grep m/\Q$search\E/i, @l  if defined $search && $search ne '';
	if (!$self->{sort} || $self->{sort} eq 'alpha')
	{	#@l=sort {lc$a cmp lc$b}
		@l=sort {::NFKD(lc$a) cmp ::NFKD(lc$b)}
		   sort {$a cmp $b} @l;#the case-sensitive sort is used to speed up the following utf8 case-insensitive sort
	}
	elsif ($self->{sort} eq 'numeric') { no warnings; @l=sort {$a <=> $b} @l; }
	elsif ($self->{sort} eq 'length')
	{	my $aa= $col==::SONG_ARTIST ? \%::Artist : \%::Album;
		no warnings 'uninitialized';
		@l=sort { $aa->{$a}[::AALENGTH] <=> $aa->{$b}[::AALENGTH] || ::NFKD(lc$a) cmp ::NFKD(lc$b) } @l;
	}
	elsif ($self->{sort} eq 'year')
	{	my $aa= $col==::SONG_ARTIST ? \%::Artist : \%::Album;
		no warnings 'uninitialized';
		@l=sort { $aa->{$a}[::AAYEAR] cmp $aa->{$b}[::AAYEAR] || ::NFKD(lc$a) cmp ::NFKD(lc$b) } @l;
	}
	elsif ($self->{sort} eq 'year2') #use highest year
	{	my $aa= $col==::SONG_ARTIST ? \%::Artist : \%::Album;
		no warnings 'uninitialized';
		@l=sort { substr($aa->{$a}[::AAYEAR],-4,4) cmp substr($aa->{$b}[::AAYEAR],-4,4) || ::NFKD(lc$a) cmp ::NFKD(lc$b) } @l;
	}
	elsif ($self->{sort} eq 'artist') #only for albums
	{	my %aartist;
		for my $alb (@l)
		{	my $h= $::Album{$alb}[::AAXREF];
			$aartist{$alb}= ::NFKD(lc( (sort { $h->{$b} <=> $h->{$a} } keys %$h)[0] ));
		}
		@l=sort { $aartist{$a} cmp $aartist{$b} || ::NFKD(lc$a) cmp ::NFKD(lc$b) } @l;
	}
	elsif ($self->{sort} eq 'songs') #number of songs in filter
	{	@l=sort { $href->{$a} <=> $href->{$b} || ::NFKD(lc$a) cmp ::NFKD(lc$b) } @l;
	}
	return \@l,$href;
}

sub Fill
{	warn "filling @_\n" if $::debug;
	my ($self,$opt)=@_;
	$opt=undef unless $opt && ($opt eq 'optchanged' || $opt eq 'rehash');
	return if $self->{valid} && !$opt;
	if ($self->{mode} eq 'list')
	{	my $treeview=$self->{view};
		my $store=$treeview->get_model;
		$self->{busy}=1;
		$store->clear;	#FIXME keep selection ?   FIXME at least when opt is true (ie showinfo or picsize changed)
		my $col=$self->{col};
		(($treeview->get_columns)[0]->get_cell_renderers)[0]->reset if ($col==::SONG_ARTIST || $col==::SONG_ALBUM);
		my ($list)=$self->get_fill_data($opt);
		$store->set($store->append,0,$_) for @$list;
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
	my $keylist=$self->get_selected;
	my $col=$self->{col};
	my $aa= $col==::SONG_ARTIST ? 'artist':
		$col==::SONG_ALBUM  ? 'album' :
		undef;
	FilterPane::PopupContextMenu($self,$event,{ self=> $self, filter => $self->get_selected_filters, col => $col, aa => $aa, keylist =>$keylist });
}

package FolderList;
use Gtk2;
use base 'Gtk2::ScrolledWindow';

sub new
{	my ($class,$col,$opt1,$opt2)=@_;
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store=Gtk2::TreeStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_enable_search(!$opt1->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(row_expanded  => \&row_expanded_changed_cb);
	$treeview->signal_connect(row_collapsed => \&row_expanded_changed_cb);
	$treeview->{expanded}={};
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( $::TagProp[$col][0],Gtk2::CellRendererText->new,'text',0)
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
		return ($filter? $filter->{string} : undef);
	    }]);
	MultiTreeView::init($treeview,__PACKAGE__);
	return $self;
}

sub Fill
{	warn "filling @_\n" if $::debug;
	my $self=$_[0];
	return if $self->{valid};
	my $treeview=$self->{treeview};
	my $filterpane=::find_ancestor($self,'FilterPane');
	my $href=$self->{hash}||= do
		{ my %h; $h{ $::Songs[$_][::SONG_UPATH] }++ for @{ $filterpane->{list} };
		  my @hier;
		  while (my ($f,$n)=each %h)
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
		$store->set($iter,0,$name);
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
	return Filter->newadd(::FALSE,map( ::SONG_UPATH.'i'.$_, @paths ));
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
{	my ($store,$tp)=($_[0],$_[1]);
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
use Gtk2;
use base 'Gtk2::ScrolledWindow';

sub new
{	my ($class,$col,$opt1,$opt2)=@_;
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	$self->set_shadow_type ('etched-in');
	$self->set_policy ('automatic', 'automatic');
	::set_biscrolling($self);

	my $store=Gtk2::TreeStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->set_enable_search(!$opt1->{no_typeahead});
	#$treeview->set('fixed-height-mode' => ::TRUE);	#only if fixed-size column
	$treeview->signal_connect(row_expanded  => \&row_expanded_changed_cb);
	$treeview->signal_connect(row_collapsed => \&row_expanded_changed_cb);
	$treeview->{expanded}={};
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
		return ($filter? $filter->{string} : undef);
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
	for my $folder (split /$::QSLASH/,Glib::get_home_dir)
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
{	my @paths=@_; #in utf8
	#s#\\#\\\\#g for @paths;
	my @list;
	push @list, @{ ::ScanFolder($_) } for @paths;
	my $filter= Filter->new('',\@list);
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
{	my ($store,$tp)=($_[0],$_[1]);
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
		stockicon => 'gtk-remove',	mode => 'L' },
	{ label => _"Rename",	code => sub { my $tv=$_[0]{self}{treeview}; $tv->set_cursor($_[0]{treepaths}[0],$tv->get_column(0),TRUE); },
		notempty => 'names',	onlyone => 'treepaths' },
  );

  %Modes=
  (	F => [_"Saved filters",	'sfilter',	'SavedFilters',	\&UpdateSavedFilters,	'gmb-filter'	],
	L => [_"Saved lists",	'slist',	'SavedLists',	\&UpdateSavedLists,	'gmb-list'	],
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
	$column->add_attribute($renderer0, 'stock-id' => 2);
	$column->add_attribute($renderer1, text => 0);
	$column->add_attribute($renderer1, editable => 4);
	$treeview->append_column($column);

	::set_drag($treeview, source =>
		[::DRAG_FILTER,sub
		 {	my $self=::find_ancestor($_[0],__PACKAGE__);
			my $filter=$self->get_selected_filters;
			return ($filter? $filter->{string} : undef);
		 }],
		 dest =>
		[::DRAG_FILTER,::DRAG_ID,sub	#targets are modified in drag_motion callback
		 {	my ($treeview,$type,$dest,@data)=@_;
			my $self=::find_ancestor($treeview,__PACKAGE__);
			my (undef,$path)=@$dest;
			my ($name,$rowtype)=$store->get_value( $store->get_iter($path) );
			if ($type == ::DRAG_ID)
			{	if ($rowtype eq 'slist')
				{	push @{$::SavedLists{$name}},@data;
					::HasChanged('SavedLists',$name,'push');
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
		&$sub($self);
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
	{	$path=Gtk2::TreePath->new( $self->{play} );
		$iter=$store->get_iter($path);
	}
	my @list=(	playfilter	=> _"Playing Filter",
			artist		=> _"Playing Artist",
			album		=> _"Playing Album",
			title		=> _"Playing Title",
		 );
	while (@list)
	{	my $id=shift @list;
		my $name=shift @list;
		$store->set($store->append($iter),0,$name,1,'play',3,$id);;
	}
	$treeview->expand_to_path($path);
}

sub UpdateSavedFilters
{	$_[0]->fill_savednames('sfilter',\%::SavedFilters);
}
sub UpdateSavedLists
{	return if $_[2] && $_[2] eq 'push';
	$_[0]->fill_savednames('slist',\%::SavedLists);
}
sub fill_savednames
{	my ($self,$type,$href)=@_;
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
	$store->set($store->append($iter),0,$_,1,$type,4,TRUE) for sort keys %$href;
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
				undef;
		$args{names}=$sel{$mode};
	}
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
	my $iter=$store->get_iter( Gtk2::TreePath->new($path_string) );
	my ($name,$type)=$store->get($iter,0,1);
	my $sub= $type eq 'sfilter' ? \&::SaveFilter : \&::SaveList;
	#$self->{busy}=1;
	&$sub($name,undef,$newname);
	#$self->{busy}=undef;
	#$store->set($iter, 0, $newname);
}

sub CreateNewFL
{	my ($self,$mode,$data)=@_;
	my ($type,$name,$savesub,$hash)= ($mode eq 'F') ? ('sfilter','filter000',\&::SaveFilter,\%::SavedFilters)
							: ('slist','list000',\&::SaveList,\%::SavedLists);
	while ($hash->{$name}) {$name++}
	return if $hash->{$name};
	&$savesub($name,$data);

	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	my $iter;
	if (defined $self->{$type})
	{	my $path=Gtk2::TreePath->new( $self->{$type} );
		$iter=$store->get_iter($path);
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
{	my $self=shift;
	my $store=$self->{store};
	my @filters;
	for my $path ($self->{treeview}->get_selection->get_selected_rows)
	{	my ($name,$type,undef,$extra)=$store->get_value($store->get_iter($path));
		next unless $type;
		if ($type eq 'sfilter') {push @filters,$::SavedFilters{$name};}
		elsif ($type eq 'slist'){push @filters,'l'.$name;}
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
	elsif (defined $::SongID)
	{ if ($extra eq 'title')	{ $filter= ::SONG_TITLE. '~'.$::Songs[$::SongID][::SONG_TITLE]; }
	  elsif ($extra eq 'artist')	{ $filter= ::SONG_ARTIST. '~'.$::Songs[$::SongID][::SONG_ARTIST]; }
	  elsif ($extra eq 'album')	{ $filter= ::SONG_ALBUM. 'e'.$::Songs[$::SongID][::SONG_ALBUM]; }
	}
	$filter= Filter->new($filter) unless ref $filter;
	return $filter;
}

package AABox;
use Gtk2;
use base 'Gtk2::EventBox';

use constant { TRUE  => 1, FALSE => 0, };

sub new
{	my ($class,$opt1)= @_;
	my $self = bless Gtk2::EventBox->new, $class;
	my $col= $opt1->{aa} eq 'artist' ? ::SONG_ARTIST : ::SONG_ALBUM;
	$self->{Col}=$col;
	$self->{filternb}= defined $opt1->{filternb} ? $opt1->{filternb} : 1;
	$self->{group}=$opt1->{group};
	$self->{nopic}=1 if $opt1->{nopic};
	my $hbox = Gtk2::HBox->new (FALSE, 6);
	$self->add($hbox);
	($self->{AAref},$self->{fcmd})= $col==::SONG_ARTIST ? (\%::Artist,$col.'~') : (\%::Album,$col.'e');
	$self->{Sel}='';
	$self->{SelID}=-1;
	my $vbox = Gtk2::VBox->new(FALSE, 0);
	for my $name (qw/Ltitle Lstats/)
	{	my $l=Gtk2::Label->new('');
		$self->{$name}=$l;
		$l->set_justify('center');
		if ($name eq 'Ltitle')
		{	$l->set_line_wrap(TRUE);$l->set_ellipsize('end'); #FIXME find a better way to deal with long titles
			my $b=Gtk2::Button->new;
			$b->set_relief('none');
			$b->signal_connect(button_press_event => \&AABox_button_press_cb);
			$b->add($l);
			$l=$b;
		}
		$vbox->pack_start($l, FALSE,FALSE, 2);
	}

	my $pixbox=Gtk2::EventBox->new;
	$self->{img}=my $img=Gtk2::Image->new;
	$img->{size}=0;
	$img->signal_connect(size_allocate => \&size_allocate_cb);
	$pixbox->add($img);
	$pixbox->signal_connect(button_press_event => \&::pixbox_button_press_cb,1); # 1 : mouse button 1

	my $buttonbox=Gtk2::VBox->new(FALSE, 4);
	my $Bfilter=::NewIconButton('gmb-filter',undef,sub { $self->filter },'none');
	$::Tooltips->set_tip($Bfilter, ($col==::SONG_ARTIST ? _"Filter on this artist" : _"Filter on this album") );
	my $Bplay=::NewIconButton('gtk-media-play',undef,sub
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			return if $self->{SelID}==-1;
			::Select(filter=> $self->{fcmd}.$self->{Sel}, song=>'first',play=>1);
		},'none');
	$Bplay->signal_connect(button_press_event => sub	#enqueue with middle-click
		{	my $self=::find_ancestor($_[0],__PACKAGE__);
			return 0 if $_[1]->button !=2;
			if ($self->{SelID}!=-1) { ::EnqueueFilter( Filter->new($self->{fcmd}.$self->{Sel})); }
			1;
		});
	$::Tooltips->set_tip($Bplay, ($col==::SONG_ARTIST ? _"Play all songs from this artist" : _"Play all songs from this album") );
	$buttonbox->pack_start($_, FALSE, FALSE, 0) for ($Bfilter,$Bplay);

	$hbox->pack_start($pixbox, FALSE, TRUE, 0);
	$hbox->pack_start($vbox, TRUE, TRUE, 0);
	$hbox->pack_start($buttonbox, FALSE, FALSE, 0);

	if ($col==::SONG_ARTIST)
	{	$self->{'index'}=0;
		$self->signal_connect(scroll_event => \&AABox_scroll_event_cb);
		my $BAlblist=::NewIconButton('gmb-playlist',undef,undef,'none');
		$BAlblist->signal_connect(button_press_event => \&AlbumListButton_press_cb,$self);
		$::Tooltips->set_tip($BAlblist,_"Choose Album From this Artist");
		$buttonbox->pack_start($BAlblist, FALSE, FALSE, 0);
	}
	#else
	#{	#my $BAlblist=::NewIconButton('gmb-playlist',undef,undef,'none');
		#$buttonbox->pack_start($BAlblist, FALSE, FALSE, 0);
		#$BAlblist->signal_connect ('clicked' => sub
		#{	$self->{list}^=1;
		#	$self->update();
		#});
		#my $store=Gtk2::ListStore->new('Glib::String');
		#my $treeview=Gtk2::TreeView->new($store);
		#$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		#( 'albums from artist',Gtk2::CellRendererText->new,'text',0)
		#);
		#my $sw = Gtk2::ScrolledWindow->new;
		#$sw->set_shadow_type ('etched-in');
		#$sw->set_policy ('automatic', 'automatic');
		#$sw->add($treeview);
	#}

	::set_drag($self, source =>
	 [($col==::SONG_ARTIST ? ::DRAG_ARTIST : ::DRAG_ALBUM), sub { $_[0]{Sel}; } ],
	 dest => [::DRAG_ID,::DRAG_FILE,sub
	 {	my ($self,$type,@values)=@_;
		if ($type==::DRAG_FILE)
		{	my $key=$self->{Sel};
			my $AAref=$self->{AAref};
			my $file=$values[0];
			if ($file=~s#^file://##)
			{	$AAref->{$key}[::AAPIXLIST]=::decode_url($file);
				::HasChanged(AAPicture => $key);
			}
			#else #FIXME download http link, ask filename
		}
		else # $type is ID
		{	$self->id_set($values[0]);
		}
	 }]);

	$self->signal_connect(button_press_event => \&AABox_button_press_cb);
	::Watch($self,AAPicture=>\&AAPicture_Changed);
	::Watch($self,'SelectedID_'.$self->{group},\&id_set);
	$self->{watcher_list}=::AddWatcher();
	$self->{watcher_id}=::AddWatcher();
	$self->signal_connect(destroy => \&remove);
	return $self;
}
sub remove
{	my $self=shift;
	delete $::ToDo{'9_AABox'.$self};
	::RemoveWatcher($self->{watcher_id});
	::RemoveWatcher($self->{watcher_list});
}

sub AAPicture_Changed
{	my ($self,$key)=@_;
	$self->pic_set( $self->{AAref}{ $self->{Sel} }[::AAPIXLIST] ) if $key eq $self->{Sel};
}

sub update_id
{	my $self=shift;
	my $ID=$self->{SelID};
	$self->{SelID}=-1;
	$self->{Sel}='';
	$self->id_set($ID);
}

sub clear
{	my $self=shift;
	$self->{SelID}=-1;
	$self->{Sel}='';
	$self->pic_set(undef);
	$self->{$_}->set_text('') for qw/Ltitle Lstats/;
	::ChangeWatcher($self->{watcher_id});
	::ChangeWatcher($self->{watcher_list});
	delete $::ToDo{'9_AABox'.$self};
}

sub id_set
{	my ($self,$ID)=@_;
	return if $self->{SelID}==$ID;
	$self->{SelID}=$ID;
	::ChangeWatcher($self->{watcher_id},[$ID],$self->{Col},
		sub {$self->update_id}, sub {$self->clear;} );
	my $key=$::Songs[$ID][ $self->{Col} ];
	if ( $self->{Col}==::SONG_ARTIST )
	{	my @l=split /$::re_artist/o,$::Songs[$ID][::SONG_ARTIST];
		$self->{'index'}%=@l;
		$key=$l[$self->{'index'}];
	}
	$self->update($key) unless $key eq $self->{Sel};
}

sub update
{	my ($self,$key)=@_;
	#return if $self->{Sel} eq $key;
	if (defined $key) { $self->{Sel}=$key; }
	else		  { $key=$self->{Sel}; }
	my $col=$self->{Col};
	my $AAref=$self->{AAref}{$key};
	#FIXME check if undef ??
	my $Listref=$AAref->[::AALIST];
	#set picture
	$self->pic_set($AAref->[::AAPIXLIST]);
	#set labels
	$self->{Ltitle}->set_markup( ::ReplaceAAFields($key,"<big><b>%a</b></big>",$col,1) );
	$self->{Lstats}->set_markup( ::ReplaceAAFields($key,"%s\n%X\n<small>%L\n%y</small>",$col,1) );

	delete $::ToDo{'9_AABox'.$self};
	my $updatesub=sub
	{	::IdleDo('9_AABox'.$self,1000,\&update,$self);
		::ChangeWatcher($self->{watcher_list}); #inactivate watcher
	};
	::ChangeWatcher($self->{watcher_list},$Listref,
		[::SONG_ALBUM,::SONG_ARTIST,::SONG_LENGTH,::SONG_SIZE,::SONG_DATE],
		$updatesub,$updatesub,$updatesub);
}

sub filter
{	my $self=shift;
	return if $self->{SelID}==-1;
	::SetFilter( $self, $self->{fcmd}.$self->{Sel}, $self->{filternb}, $self->{group} );
}

sub pic_set
{	my ($self,$file)=@_;
	return if $self->{nopic};
	my $img=$self->{img};
	::ScaleImageFromFile( $img, $img->{size}, $file );
}

sub size_allocate_cb
{	my ($img,$alloc)=@_;
	my $h=$alloc->height;
	$h=200 if $h>200;		#FIXME use a relative max value (to what?)
	return if abs($img->{size}-$h)<6;
	$img->{size}=$h;
	::ScaleImage( $img, $img->{size} );
}

sub AABox_button_press_cb			#popup menu
{	my ($widget,$event)=@_;
	my $self=::find_ancestor($widget,__PACKAGE__);
	return 0 unless $self;
	return 0 if $self == $widget && $event->button != 3;
	return if $self->{SelID}==-1;
	$::LEvent=$event;
	::PopupContextMenu(\@::cMenuAA,{self=>$self, col=>$self->{Col}, key=>$self->{Sel}, ID=>$self->{SelID}, filternb => $self->{filternb}, mode => 'B'});
	return 1;
}

sub AABox_scroll_event_cb
{	my ($self,$event)=@_;
	my @l=split /$::re_artist/o,$::Songs[$self->{SelID}][::SONG_ARTIST];
	return 0 unless @l>1;
	$self->{'index'}+=($event->direction eq 'up')? 1 : -1;
	$self->{'index'}%=@l;
	$self->update( $l[$self->{'index'}] );
	1;
}

sub AlbumListButton_press_cb
{	(undef,$::LEvent,my $self)=@_;
	return if $self->{Sel} eq '';
	::PopupAA(::SONG_ALBUM,$self->{Sel},sub
		{	my $key=$_[1];
			::SetFilter( $self, ::SONG_ALBUM.'e'.$key, $self->{filternb}, $self->{group} );
		});
	1;
}

package SimpleSearch;
use base 'Gtk2::HBox';

our @SelectorMenu=
(	[_"Search Title, Artist and Album", ::SONG_TITLE.'s_'.::SONG_ARTIST.'s_'.::SONG_ALBUM.'s' ],
	[_"Search Title, Artist, Album, Comment, Label and Genre", ::SONG_TITLE.'s_'.::SONG_ARTIST.'s_'.::SONG_ALBUM.'s_'.::SONG_COMMENT.'s_'.::SONG_LABELS.'s_'.::SONG_GENRE.'s' ],
	[_"Search Title",	::SONG_TITLE.'s'],
	[_"Search Artist",	::SONG_ARTIST.'s'],
	[_"Search Album",	::SONG_ALBUM.'s'],
	[_"Search Comment",	::SONG_COMMENT.'s'],
	[_"Search Label",	::SONG_LABELS.'s'],
	[_"Search Genre",	::SONG_GENRE.'s'],
);

sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self= bless Gtk2::HBox->new(0,0), $class;
	my $nb=$opt1->{nb};
	my $entry=$self->{entry}=Gtk2::Entry->new;
	$self->{fields}= $opt2->{fields} || ::SONG_TITLE.'s_'.::SONG_ARTIST.'s_'.::SONG_ALBUM.'s';
	$self->{wordsplit}=$opt2->{wordsplit}||0;
	$self->{nb}=defined $nb ? $nb : 1;
	$self->{group}=$opt1->{group};
	$self->{searchfb}=$opt1->{searchfb};
	#$self->{activate}=$opt1->{activate};
	$self->{SaveOptions}=\&SaveOptions;
	$self->{DefaultFocus}=$entry;
	$entry->signal_connect(changed => \&EntryChanged_cb);
	$entry->signal_connect(activate => \&Filter);
	$entry->signal_connect_after(activate => sub {::run_command($_[0],$opt1->{activate});}) if $opt1->{activate};
	unless ($opt1->{noselector})
	{	for my $aref (	['gtk-find'=> \&PopupSelectorMenu,0],
				['gtk-clear',sub {my $e=$_[0]->parent->{entry}; $e->set_text(''); Filter($e); },1]
			     )
		{	my ($stock,$cb,$end)=@$aref;
			my $img=Gtk2::Image->new_from_stock($stock,'menu');
			my $but=Gtk2::Button->new;
			$but->add($img);
			$but->can_focus(0);
			$but->set_relief('none');
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
				$entry->signal_connect(changed => sub { $_[0]->parent->{clear_button}->set_sensitive($_[0]->get_text ne '' ); });
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
				{	my $s= $self->{filtered};
					$entry->modify_base('normal', ($s? $entry->style->bg('selected') : undef) );
					$entry->modify_text('normal', ($s? $entry->style->text('selected') : undef) );
				}
				$entry->style->paint_flat_box( $self->window, $entry->state, 'none', $event->area, $entry, 'entry_bg', $self->allocation->values );
				$entry->style->paint_shadow( $self->window, 'normal', $entry->get('shadow-type'), $event->area, $entry, 'entry', $self->allocation->values);
				#$self->propagate_expose($_,$event) for $self->get_children;
				0;
			});
		::WatchFilter($self, $self->{group},sub {$_[0]->{filtered}=0;$_[0]->queue_draw}); #to update background color
	}
	else {$self->add($entry);}
	return $self;
}
sub SaveOptions
{	my $self=$_[0];
	return { fields => $self->{fields}, wordsplit => $self->{wordsplit} };
}

sub PopupSelectorMenu
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $menu=Gtk2::Menu->new;
	my $cb=sub { $self->{fields}=$_[1]; };
	for my $ref (@SelectorMenu)
	{	my ($label,$fields)=@$ref;
		my $item=Gtk2::CheckMenuItem->new($label);
		$item->set_active(1) if $fields eq $self->{fields};
		$item->set_draw_as_radio(1);
		$item->signal_connect(activate => $cb,$fields);
		$menu->append($item);
	}
	my $item1=Gtk2::CheckMenuItem->new(_"Split on words");
	$item1->set_active(1) if $self->{wordsplit};
	$item1->signal_connect(activate => sub
		{	$self->{wordsplit}=$_[0]->get_active;
		});
	$menu->append($item1);
	my $item2=Gtk2::MenuItem->new(_"Advanced Search ...");
	$item2->signal_connect(activate => sub
		{	::EditFilter($self,::GetFilter($self),undef,sub {::SetFilter($self,$_[0]) if defined $_[0]});
		});
	$menu->append($item2);
	$menu->show_all;
	$::LEvent=Gtk2->get_current_event;
	$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button,$::LEvent->time);
}

sub Filter
{	my $entry=$_[0];
	Glib::Source->remove(delete $entry->{changed_timeout}) if $entry->{changed_timeout};
	my $self=::find_ancestor($entry,__PACKAGE__);
	my $text=$entry->get_text;
	my $filter;
	if ($text ne '')
	{	my @strings= $self->{wordsplit}? (split / +/,$text) : ($text);
		my @filters;
		for my $string (@strings)
		{	push @filters,Filter->newadd( ::FALSE,map $_.$string, split /_/,$self->{fields} );
		}
		$filter=Filter->newadd( ::TRUE,@filters );
	}
	else {$filter=Filter->new}
	::SetFilter($self,$filter,$self->{nb});
	if ($self->{searchfb})
	{	::HasChanged('SearchText_'.$self->{group},$text);
	}
	$self->{filtered}= 1 && !$filter->is_empty; #used to set the background color
}

sub EntryChanged_cb
{	my $entry=$_[0];
	Glib::Source->remove(delete $entry->{changed_timeout}) if $entry->{changed_timeout};
	$entry->{changed_timeout}= Glib::Timeout->add(1000,\&Filter,$entry);
}

package SongSearch;
use base 'Gtk2::VBox';

sub new
{	my ($class,$opt1)=@_;
	my $self= bless Gtk2::VBox->new, $class;
	my $activate= $opt1->{activate} || 'queue';
	$self->{songlist}=
	my $songlist=SongList->new({type=>'S',headers=>'off',activate=>$activate,'sort'=>::SONG_TITLE,cols=>'titleaa', group=>"$self"});
	my $hbox1=Gtk2::HBox->new;
	my $entry=Gtk2::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate =>\&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk2::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$self->pack_start($hbox1, ::FALSE,::FALSE,2);
	$self->add($songlist);
	if ($opt1->{buttons})
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
	else { $self->{songlist}->SetFilter( Filter->new(::SONG_TITLE.'s'.$text) ); }
}

package AASearch;
use base 'Gtk2::VBox';

sub new
{	my ($class,$opt1)=@_;
	my $self= bless Gtk2::VBox->new, $class;
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	::set_biscrolling($sw);
	my $store=Gtk2::ListStore->new('Glib::String');
	$self->{treeview}=
	 my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(::FALSE);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( '', CellRendererAA->new, 'text',0)
		);
	my $sub=\&Enqueue;
	$sub=\&AddToPlaylist if $opt1->{activate} && $opt1->{activate} eq 'addplay';
	$treeview->signal_connect( row_activated => $sub);
	my $col=$self->{col}= ($opt1->{aa} && $opt1->{aa} eq 'artist' ? ::SONG_ARTIST : ::SONG_ALBUM );
	$self->{picsize}=32; $self->{showinfo}=1;

	::set_drag($treeview, source => [($col==::SONG_ALBUM ? ::DRAG_ALBUM : ::DRAG_ARTIST),
	    sub
	    {	my $treeview=$_[0];
		my @rows=$treeview->get_selection->get_selected_rows;
		return map $store->get_value($store->get_iter($_),0) , @rows;
	    }]);

	$self->{cmd}= $col==::SONG_ARTIST ? '~' : 'e';
	my $hbox1=Gtk2::HBox->new;
	my $entry=Gtk2::Entry->new;
	$entry->signal_connect(changed => \&EntryChanged_cb,0);
	$entry->signal_connect(activate=> \&EntryChanged_cb,1);
	$hbox1->pack_start( Gtk2::Label->new(_"Search : ") , ::FALSE,::FALSE,2);
	$hbox1->pack_start($entry, ::TRUE,::TRUE,2);
	$sw->add($treeview);
	$self->pack_start($hbox1, ::FALSE,::FALSE,2);
	$self->add($sw);
	if ($opt1->{buttons})
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
	my $aa=$store->get( $store->get_iter($path) );
	return Filter->new( $self->{col}.$self->{cmd}.$aa );
}

sub EntryChanged_cb
{	my ($entry,$force)=@_;
	my $text=$entry->get_text;
	my $self= ::find_ancestor($entry,__PACKAGE__);
	my $ref= $self->{col}==::SONG_ARTIST ? \%::Artist : \%::Album;
	my $store=$self->{treeview}->get_model;
	(($self->{treeview}->get_columns)[0]->get_cell_renderers)[0]->reset;
	$store->clear;
	return if !$force && 2>length $text;
	my $re=qr/\Q$text\E/i;
	$store->set($store->append,0,$_) for sort {lc$a cmp lc$b} grep m/$re/, keys %$ref;
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
	properties => [ Glib::ParamSpec->scalar
			('iconlist',		 #name
			 'iconlist',		 #nickname
			 '\x00-separated list of stock-id', #blurb
			 [qw/readable writable/] #flags
			)];

use constant PAD => 2;

sub GET_SIZE
{	my ($cell, $widget, $cell_area) = @_;
	my $list=$cell->get('iconlist');
	return (0,0,0,0) unless defined $list;
	my $nb=@{[ split /\x00/,$list ]};
	#my ($w,$h)=Gtk2::IconSize->lookup( $cell->get('stock-size') );
	my ($w,$h)=Gtk2::IconSize->lookup('menu');
	return (0,0, $nb*($w+PAD)+$cell->get('xpad')*2, $h+$cell->get('ypad')*2);
}

sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my $list=$cell->get('iconlist');
	return unless defined $list;
	#my $size=$cell->get('stock-size');
	my $size='menu';
	my $state;
	if ($flags & 'selected')
	{	$state = $widget->has_focus ? 'selected' : 'active';
	}
	else
	{	$state = $widget->state eq 'insensitive' ? 'insensitive' : 'normal';
	}
	my ($w,$h)=Gtk2::IconSize->lookup($size);
	my $room=PAD + $cell_area->height-2*$cell->get('ypad');
	my $nb=int( ($room) / ($h+PAD) );
	my $x=$cell_area->x+$cell->get('xpad');
	my $y=$cell_area->y+$cell->get('ypad');
	$y+=int( $cell->get('yalign') * ($room-($h+PAD)*$nb) ) if $nb>0;
	my $row=0; my $ystart=$y;
	for my $stock ( sort split /\x00/,$list )
	{	my $pb=$widget->render_icon('label-'.$stock, $size );
		next unless $pb;
		$window->draw_pixbuf( $widget->style->fg_gc($state), $pb,0,0,
				$x,$y,-1,-1,'none',0,0);
		$row++;
		if ($row<$nb)	{ $y+=PAD+$h; }
		else		{ $row=0; $y=$ystart; $x+=PAD+$w; }
	}
}

package CellRendererAA;
use Glib::Object::Subclass 'Gtk2::CellRendererText';

use constant PAD => 2;

sub makelayout
{	my ($cell,$widget)=@_;
	my $text=$cell->get('text');
	my $layout=Gtk2::Pango::Layout->new( $widget->create_pango_context );
	if (my $format=$widget->parent->parent->{showinfo})
	{	my $col= $widget->parent->parent->{col};
		$format="<b>%a</b>%Y\n<small>%s <small>%l</small></small>" if $format eq '1';
		$text=::ReplaceAAFields( $text,$format,$col,::TRUE );
		$layout->set_markup($text);
		#$text.="\n".@{$ref->[::AALIST]}.' songs '.$s;
	}
	else { $layout->set_text($text); }
	return $layout;
}

sub GET_SIZE
{	my ($cell, $widget, $cell_area) = @_;
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	my $s=$widget->parent->parent->{picsize};
	if ($s eq 'a')	{$s=$h}
	elsif ($h<$s)	{$h=$s}
	return (0,0,$w+$s+PAD+$cell->get('xpad')*2,$h+$cell->get('ypad')*2);
}

sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my $s=$widget->parent->parent->{picsize};
	my $x=$cell_area->x+$cell->get('xpad');
	my $y=$cell_area->y+$cell->get('ypad');
	my $text=$cell->get('text');
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	$s=$h if $s eq 'a';
	$w+=PAD+$s;
	my $offy=0;
	if ($s>$h)
	{	$offy+=int( $cell->get('yalign')*($s-$h) );
		$h=$s;
	}

	my $state;
	if ($flags & 'selected')
	{	$state = $widget->has_focus ? 'selected' : 'active';
	}
	else
	{	$state = $widget->state eq 'insensitive' ? 'insensitive' : 'normal';
	}
	{	last unless $s;
		my $col=$widget->parent->parent->{col};
		my $pixbuf= AAPicture::pixbuf($col,$text,$s);
		if ($pixbuf) #pic cached -> draw now
		{	my $offy=int(($h-$pixbuf->get_height)/2);#center pic
			my $offx=int(($s-$pixbuf->get_width )/2);
			$window->draw_pixbuf( Gtk2::Gdk::GC->new($window), $pixbuf,0,0,
				$x+$offx, $y+$offy,-1,-1,'none',0,0);
		}
		elsif (defined $pixbuf) #pic exists but not cached -> load and draw in idle
		{	my ($tx,$ty)=$widget->widget_to_tree_coords($x,$y);
			$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
			$cell->{widget}||=$widget;
			$cell->{window}||=$window;
			$cell->{queue}{$ty}=[$tx,$ty,$text,$s,$h];
		}
	}
	$widget-> get_style-> paint_layout($window, $state, 1,
		$cell_area, $widget, undef, $x+$s+PAD, $y+$offy, $layout);
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
{	my ($widget,$window,$ctx,$cty,$text,$s,$h)=@_;
	my ($vx,$vy,$vw,$vh)=$widget->get_visible_rect->values;
	#warn "   $text\n";
	return if $vx > $ctx+$s || $vy > $cty+$h || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $text\n";
	my ($x,$y)=$widget->tree_to_widget_coords($ctx,$cty);
	my $col=$widget->parent->parent->{col};
	my $pixbuf= AAPicture::pixbuf($col,$text, $s,1);
	return unless $pixbuf;

	my $offy=int( ($h-$pixbuf->get_height)/2 );#center pic
	my $offx=int( ($s-$pixbuf->get_width )/2 );
	$window->draw_pixbuf( Gtk2::Gdk::GC->new($window), $pixbuf,0,0,
		$x+$offx, $y+$offy, -1,-1,'none',0,0);
}

package CellRendererSongsAA;
use Glib::Object::Subclass 'Gtk2::CellRenderer',
properties => [ Glib::ParamSpec->scalar
			('ref',		 #name
			 'ref',		 #nickname
			 'array : [r1,r2,row,key]', #blurb
			 [qw/readable writable/] #flags
			),
		Glib::ParamSpec->int('aa','aa','use album or artist column', 0, ::SONGLAST, ::SONG_ALBUM, [qw/readable writable/]),
		Glib::ParamSpec->string('markup','markup','show info', '', [qw/readable writable/]),
		];

use constant PAD => 2;

sub GET_SIZE { (0,0,-1,-1) }


sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my ($r1,$r2,$row,$key)=@{ $cell->get('ref') };
	my $col= $cell->get('aa');
	my $format=$cell->get('markup');
	my @format= $format ? (split /\n/,$format) : ();
	$format=$format[$row-$r1];
	if ($format)
	{	my ($x, $y, $width, $height)= $cell_area->values;
		my $gc= $widget->get_style->base_gc('normal');
		$window->draw_rectangle($gc, 1, $background_area->values);# if $r1 != $r2;
		my $layout=Gtk2::Pango::Layout->new( $widget->create_pango_context );
		my $markup=::ReplaceAAFields( $key,$format,$col,::TRUE );
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
	my($x, $y, $width, $height)= $background_area->values;# warn "$row $x, $y, $width, $height\n";
	$y-=$height*($row-$r1 - @format);
	$height*=1+$r2-$r1 - @format;
#	my $ypad=$cell->get('ypad') + $background_area->height - $cell_area->height;
#	$y+=$ypad;
	$x+=$cell->get('xpad');
#	$height-=$ypad*2;
	$width-=$cell->get('xpad')*2;
	my $s= $height > $width ? $width : $height;
	$s=200 if $s>200;

	if ( my $pixbuf= AAPicture::pixbuf($col,$key,$s) )
	{	my $gc=Gtk2::Gdk::GC->new($window);
		$gc->set_clip_rectangle($background_area);
		$window->draw_pixbuf( $gc, $pixbuf,0,0,	$x,$y, -1,-1,'none',0,0);
	}
	elsif (defined $pixbuf)
	{	my ($tx,$ty)=$widget->widget_to_tree_coords($x,$y);
		$cell->{queue}{$r1}=[$tx,$ty,$key,$s,$col];
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
{	my ($widget,$window,$ctx,$cty,$key,$s,$col)=@_; #warn "$ctx,$cty,$key,$s\n";
	my ($vx,$vy,$vw,$vh)=$widget->get_visible_rect->values;
	#warn "   $key\n";
	return if $vx > $ctx+$s || $vy > $cty+$s || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $key\n";
	my ($x,$y)=$widget->tree_to_widget_coords($ctx,$cty);
	my $pixbuf= AAPicture::pixbuf($col,$key, $s,1);
	return unless $pixbuf;
	$window->draw_pixbuf( Gtk2::Gdk::GC->new($window), $pixbuf,0,0, $x,$y,-1,-1,'none',0,0);
}

package Cloud;
use Gtk2;
use base 'Gtk2::DrawingArea';

use constant
{	XPAD => 2,	YPAD => 2,
	MINSCALE => .5,	MAXSCALE => 2,
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
{	my ($self,$opt)=@_;
	my ($list,$href)= &{ $self->{get_fill_data_sub} }($self,$opt);
	my $window=$self->window;
	my ($width,$height)=$window->get_size;

	if ($width<2 && !$self->{delayed}) {$self->{delayed}=1;::IdleDo('2_resizecloud'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};

	#warn "Fill : $width,$height\n";
	delete $::ToDo{'2_resizecloud'.$self};
	unless (keys %$href)
	{	$self->set_size_request(-1,-1);
		$self->queue_draw;
		$self->{lines}=[];
		return;
	}
	$self->{width}=$width;#warn "$self : filling with width=$width\n";
	my $lastkey;
	if ($self->{lastclick})
	{	my ($i,$j)=@{ delete $self->{lastclick} };
		$lastkey=$self->{lines}[$i+2][$j+4];
	}
	my @lines;
	$self->{lines}=\@lines;
	my $line=[];
	my ($min,$max)=(1,1);
	for (values %$href) {$max=$_ if $max<$_}
	if ($min==$max) {$max++;$min--;}
	my ($x,$y)=(XPAD,YPAD); my ($hmax,$bmax)=(0,0);
	my $displaykeysub=$self->{displaykeysub};
	my $inverse;
	$inverse=1 if $self->get_direction eq 'rtl';
	::setlocale(::LC_NUMERIC,'C'); #for the sprintf in the loop
	for my $key (@$list)
	{	my $layout=Gtk2::Pango::Layout->new( $self->create_pango_context );
		my $value=sprintf '%.1f',MINSCALE+(MAXSCALE-MINSCALE())*($href->{$key}-$min)/($max-$min);
		#$layout->set_text($key);
		#$layout->get_attributes->insert( Gtk2::Pango::AttrScale->new($value) ); #need recent Gtk2
		my $text= $displaykeysub ? &$displaykeysub($key) : $key;
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
{	my ($self,$event)=@_;#warn "$self : resized to width=".$event->width."\n";
	#warn "configure_cb : ".$event->width."\n";
	return if !$self->{width} || $self->{width} eq $event->width;
	#$self->Fill;
	::IdleDo('2_resizecloud'.$self,100,\&Fill,$self);
}

sub focus_change
{	my $self=$_[0];
	my $sel=$self->{selected};
	return unless keys %$sel;
	#FIXME could redraw only selected keys
	$self->queue_draw;
}

sub expose_cb
{	my ($self,$event)=@_;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)=$event->area->values;
	$exp_x2+=$exp_x1; $exp_y2+=$exp_y1;
	my $window=$self->window;
	my $style=$self->get_style;
	#my ($width,$height)=$window->get_size;
	#warn "expose_cb : $width,$height\n";
	my $state= $self->state eq 'insensitive' ? 'insensitive' : 'normal';
	my $sstate= $self->has_focus ? 'selected' : 'active';
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
	{	&{ $self->{activatesub} }($self);
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
	{	&{ $self->{queuesub} }($self);
		return 1;
	}
	if ($but==3)
	{	my ($i,$j,$key)=$self->coord_to_index($event->get_coords);
		if (defined $key && !exists $self->{selected}{$key})
		{	$self->key_selected($event,$i,$j);
		}
		&{ $self->{menupopupsub} }($self,undef,$event);
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


sub key_selected
{	my ($self,$event,$i,$j)=@_;
	$self->scroll_to_index($i,$j);
	my $key=$self->{lines}[$i+2][$j+4];
	unless ($event->get_state >= ['control-mask'])
	{	$self->{selected}={};
	}
	if ($event->get_state >= ['shift-mask'] && $self->{lastclick})
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
				$self->{selected}{$key}=undef;
				$j1+=5;
			}
			$j1=0;
			$i1+=3;
		}
	}
	elsif (exists $self->{selected}{$key})
	{	delete $self->{selected}{$key};
		delete $self->{startgrow};
	}
	else
	{	$self->{selected}{$key}=undef;
		delete $self->{startgrow};
	}
	$self->{lastclick}=[$i,$j];

	$self->queue_draw;
	&{ $self->{selectsub} }($self);
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
	{	&{ $self->{activatesub} }($self);
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

package Mosaic;
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
	$vscroll->get_adjustment->signal_connect(value_changed => sub {$self->queue_draw});
	$self->signal_connect(scroll_event	=> \&scroll_event_cb);
	$self->signal_connect(expose_event	=> \&expose_cb);
	$self->signal_connect(focus_out_event	=> \&focus_change);
	$self->signal_connect(focus_in_event	=> \&focus_change);
	$self->signal_connect(configure_event	=> \&configure_cb);
	$self->signal_connect(drag_begin	=> \&Cloud::drag_begin_cb);
	$self->signal_connect(button_press_event=> \&Cloud::button_press_cb);
	$self->signal_connect(button_release_event=> \&Cloud::button_release_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(motion_notify_event=> \&start_tooltip);
	$self->signal_connect(leave_notify_event=> \&abort_tooltip);
	$self->{selectsub}=$selectsub;
	$self->{get_fill_data_sub}=$getdatasub;
	$self->{activatesub}=$activatesub;
	$self->{queuesub}=$queuesub;
	$self->{menupopupsub}=$menupopupsub;
	$self->{col}=$col;
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
	my $list=$self->{list};
	($list)= &{ $self->{get_fill_data_sub} }($self) unless $samelist && $samelist eq 'samelist';
	my $window=$self->window;
	my ($width,$height)=$window->get_size;

	if ($width<2 && !$self->{delayed}) {$self->{delayed}=1;::IdleDo('2_resizecloud'.$self,100,\&Fill,$self);return}
	delete $self->{delayed};

	delete $::ToDo{'2_resizecloud'.$self};
	$self->{width}=$width;#warn "$self : filling with width=$width\n";

	my $mpsize=$self->parent->parent->{mpicsize}||64;
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
	#FIXME copy part that is still visible and queue_draw only what has changed
	$adj->set_value($value);
	1;
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
	$label->set_markup(::ReplaceAAFields($key,"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",$self->{col},1));
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

sub configure_cb
{	my ($self,$event)=@_;
	return unless $self->{width};
	$self->{viewwindowsize}=[$event->width,$event->height];
	my $iw= $self->{hsize}+2*XPAD;
	if ( int($self->{width}/$iw) == int($event->width/$iw))
	{	$self->update_scrollbar;
		return;
	}
	$self->reset;
	$self->Fill('samelist');
}

sub expose_cb
{	my ($self,$event)=@_;
	my ($exp_x1,$exp_y1,$exp_x2,$exp_y2)=$event->area->values;
	$exp_x2+=$exp_x1; $exp_y2+=$exp_y1;
	my $dy=$self->{vscroll}->get_adjustment->value;
	$self->start_tooltip if exists $self->{lastdy} && $self->{lastdy}!=$dy;
	$self->{lastdy}=$dy;
	my $window=$self->window;
	my $col=$self->{col};
	my $style=$self->get_style;
	#my ($width,$height)=$window->get_size;
	#warn "expose_cb : $width,$height\n";
	my $state= $self->state eq 'insensitive' ? 'insensitive' : 'normal';
	my $sstate=$self->has_focus ? 'selected' : 'active';
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
				$layout->set_markup('<small>'.::PangoEsc($key).'</small>');
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
	my $sel=$self->{selected};
	return unless keys %$sel;
	#FIXME could redraw only selected keys
	$self->queue_draw;
}

sub coord_to_index
{	my ($self,$x,$y)=@_;
	$y+=$self->{vscroll}->get_adjustment->value;
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
	$y-=$self->{vscroll}->get_adjustment->value;
	return $x,$y,$self->{hsize},$self->{vsize};
}

sub key_selected
{	my ($self,$event,$i,$j)=@_;
	$self->scroll_to_row($j);
	my ($nw)=@{$self->{dim}};
	my $list=$self->{list};
	my $pos=$i+$j*$nw;
	my $key=$list->[$pos];
	unless ($event->get_state >= ['control-mask'])
	{	$self->{selected}={};
	}
	if ($event->get_state >= ['shift-mask'] && defined $self->{lastclick})
	{	$self->{startgrow}=$self->{lastclick} unless defined $self->{startgrow};
		my $i1=$self->{startgrow};
		my $i2=$pos;
		($i1,$i2)=($i2,$i1) if $i1>$i2;
		$self->{selected}{ $list->[$_] }=undef for $i1..$i2;
	}
	elsif (exists $self->{selected}{$key})
	{	delete $self->{selected}{$key};
		delete $self->{startgrow};
	}
	else
	{	$self->{selected}{$key}=undef;
		delete $self->{startgrow};
	}
	$self->{lastclick}=$pos;
	$self->queue_draw;
	&{ $self->{selectsub} }($self);
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
	{	&{ $self->{activatesub} }($self);
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
	my $dy=$vadj->get_value;
	my $page=$vadj->page_size;
	return if $dy > $y+$s || $dy+$page < $y; #no longer visible
#warn " drawing $key\n";
	AAPicture::draw($window,$x,$y-$dy,$self->{col},$key, $s,1);
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
	#properties => [	Glib::ParamSpec->object ('hadjustment','hadj','', Gtk2::Adjustment::, [qw/readable writable construct/] ),
	#		Glib::ParamSpec->object ('vadjustment','vadj','', Gtk2::Adjustment::, [qw/readable writable construct/] )],
	;


package SongTree;
use Gtk2;
use base 'Gtk2::HBox';

use constant
{	BRANCH_VALUE => 0, BRANCH_EXP => 1, BRANCH_START => 2, BRANCH_END => 3, BRANCH_HEIGHT => 4, BRANCH_CHILD => 5,
};

our %STC;
INIT
{ for my $n (grep $::TagProp[$_], 0..$#::TagProp)
  {	my ($title,$id,$t,$width)=@{$::TagProp[$n]};
	next unless defined $title;
	$STC{$id}=	{	title => $title,
				sort => $n,	width => $width,
				#elems=> ['text=text(text=$'.$id.')'],
				elems=> ['text=text(markup=playmarkup(pesc($'.$id.')))'],
				songbl=>'text',	hreq => 'text:h',
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

our %Groupings; #defined in main, should the hash be in main ?

our %GroupBy=
(	artist	=> [_"artist",	::SONG_ARTIST],
	album	=> [_"album",	::SONG_ALBUM],
	year	=> [_"year",	::SONG_DATE],
	folder	=> [_"folder",	::SONG_UPATH],
	disc	=> [_"disc",	::SONG_DISC],
);

sub new
{	my ($class,$opt1,$opt2)=@_;
	my $self = bless Gtk2::HBox->new(0,0), $class;
	#my $self = bless Gtk2::Frame->new, $class;
	#$self->set_shadow_type('etched-in');
	#my $frame=Gtk2::Frame->new;# $frame->set_shadow_type('etched-in');

	$self->{songxpad}= exists $opt1->{songxpad} ? $opt1->{songxpad} : 4;
	$self->{songypad}= exists $opt1->{songypad} ? $opt1->{songypad} : 4;

	#create widgets used to draw the songtree as a treeview, would be nice to do without but it's not possible currently
	$self->{stylewidget}=Gtk2::TreeView->new;
	$self->{stylewparent}=Gtk2::VBox->new; $self->{stylewparent}->add($self->{stylewidget}); #some style engines (gtk-qt) call ->parent on the parent => Gtk-CRITICAL messages if stylewidget doesn't have a parent. And needs to hold a reference to it or bad things happen
	#$self->{stylewidget}->set_name('SongTree');
	for my $i (1,2,3)
	{	my $column=Gtk2::TreeViewColumn->new;
		my $label=Gtk2::Label->new;
		$column->set_widget($label);
		$self->{stylewidget}->append_column($column);
		my $button=::find_ancestor($label,'Gtk2::Button');
		$self->{'stylewidget_header'.$i}=$button; #must be a button which has a treeview for parent
		#$button->remove($button->child); #don't need the child
	}

	my $view=$self->{view}=Gtk2::DrawingArea->new;
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('automatic','automatic');
	$sw->set_shadow_type('etched-in');
	::set_biscrolling($sw);
	my $vbox=SongTree::ViewVBox->new;
	$sw->add($vbox);
	$self->add($sw);
	$self->{headers}=SongTree::Headers->new($sw->get_hadjustment) unless $opt1->{headers} && $opt1->{headers} eq 'off';
	$self->{vadj}=$sw->get_vadjustment;
	$self->{hadj}=$sw->get_hadjustment;
	$vbox->pack_start($self->{headers},0,0,0) if $self->{headers};
	$vbox->add($view);
	$view->can_focus(::TRUE);
	$self->{DefaultFocus}=$view;
	$self->{$_}->signal_connect(value_changed => sub {$self->has_scrolled($_[1])},$_) for qw/hadj vadj/;
	$self->signal_connect(scroll_event	=> \&scroll_event_cb);
	$self->signal_connect(key_press_event	=> \&key_press_cb);
	$self->signal_connect(destroy		=> \&destroy_cb);
	$view->signal_connect(expose_event	=> \&expose_cb);
	$view->signal_connect(focus_out_event	=> \&focus_change);
	$view->signal_connect(focus_in_event	=> \&focus_change);
	$view->signal_connect(configure_event	=> \&configure_cb);
	$view->signal_connect(drag_begin	=> \&drag_begin_cb);
	$view->signal_connect(drag_leave	=> \&drag_leave_cb);
	$view->signal_connect(button_press_event=> \&button_press_cb);
	$view->signal_connect(button_release_event=> \&button_release_cb);

	$self->{need_init}=1; #last initialization is done in the first configure_event

	$self->{$_}=$opt1->{$_} for grep m/^activate\d?$/, keys %$opt1;
	$self->{mode}= $opt1->{mode} || '';
	$self->{type}='B';
	::WatchFilter($self,$opt1->{group}, \&SetFilter );
	::Watch($self,'SongID',\&UpdateSelID);
	$self->{watcher1}=::AddWatcher();
	$self->{watcher2}=::AddWatcher();

	::set_drag($view,
	 source=>[::DRAG_ID,sub { my $view=$_[0]; my $self=::find_ancestor($view,__PACKAGE__); $self->GetSelectedIDs; }],
	 dest => [::DRAG_ID,::DRAG_FILE,\&drag_received_cb],
	 motion=>\&drag_motion_cb,
		);

	$self->{grouping}= $opt2->{grouping} || 'album|pic';
	$opt2->{cols}||='playandqueue_title_artist_album_date_length_track_ufile_lastplay_playcount_rating';
	$opt2->{sort}=join('_',::SONG_UPATH,::SONG_ALBUM,::SONG_DISC,::SONG_TRACK,::SONG_UFILE) unless defined $opt2->{sort};
	$self->{sort}=$opt2->{sort};
	$self->{sort}=~tr/_/ /;
	$self->{TogFollow}=1 if $opt2->{follow};

	for my $key (keys %$opt2)
	{	next unless $key=~m/^cw_(.*)$/;
		$self->{colwidth}{$1}=$opt2->{$key};
	}
	$self->AddColumn($_) for split '_',$opt2->{cols};
	$self->{SaveOptions}=\&SaveOptions;
	return $self;
}

sub destroy_cb
{	my $self=$_[0];
	::RemoveWatcher($self->{watcher1});
	::RemoveWatcher($self->{watcher2});
	delete $self->{$_} for keys %$self;#it's important to delete $self->{queue} to destroy references cycles, better delete all keys to be sure
}

sub SaveOptions
{	my $self=shift;
	my %opt;
	my $sort=$self->{sort};
	$sort=~tr/ /_/;
	$opt{sort}=$sort;
	$opt{cols}=	join '_', map $_->{colid}, @{$self->{cells}};
	$opt{grouping}=	"'".$self->{grouping}."'";
	#save cols width
	$opt{ 'cw_'.$_ }=$self->{colwidth}{$_} for sort keys %{$self->{colwidth}};
	$opt{follow}=1 if $self->{TogFollow};
	#warn "$_ $opt{$_}\n" for sort keys %opt;
	return \%opt;
}

sub UpdateWatcher
{	my $self=$_[0];
	my %watchcol;
	for my $cell (@{$self->{cells}},@{$self->{headcells}})
	{	my $wc=$cell->{watchcol};
		next unless defined $wc;
		if (ref $wc)	{$watchcol{$_}=undef for @$wc}
		else		{$watchcol{$wc}=undef}
	}

	::ChangeWatcher
	(	$self->{watcher1},
		$self->{array},
		[keys %watchcol],
		sub{$self->{view}->queue_draw},
		sub{$self->RemoveID(\@_)},
		undef,
		undef,
	);
	::ChangeWatcher
	(	$self->{watcher2},
		$self->{array},
		[grep defined, map $_->{col}, @{$self->{headcells}}],
		sub{$self->rowchanged(\@_)},
		undef,
		undef,
		undef,
	);
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
	$vsizesong=GMB::Cell::init_songs($self,$self->{cells}) if $self->{cols_changed};
	$self->{cols_changed}=undef;
	for my $cell (@{ $self->{cells} })
	{	my $colid=$cell->{colid};
		$cell->{width}= $self->{colwidth}{$colid} || $STC{$colid}{width} unless exists $cell->{width};
		delete $cell->{last};
		my $watch=$cell->{event};
		if (defined $watch) { $watch=[$watch] unless ref $watch; $self->{events_to_watch}{$_}=undef for @$watch; }
		$songswidth+=$cell->{width};
	}
	$self->{cells}[-1]{last}=1; #this column gets the extra width
	$self->{songswidth}=$songswidth;
	if (!$self->{vsizesong} || $self->{vsizesong}!=$vsizesong)
	{	$self->{vsizesong}=$vsizesong;
		#warn "new vsizesong : $vsizesong\n";
		$savedpos=$self->coord_to_path(0,int($self->{vadj}->page_size/2)) unless $nosavepos;
		$self->update_height_of_path if $self->{ready};
	}
	my $w= $songswidth;
	for my $cell (reverse @{$self->{headcells}} )
	{	$w+= $cell->{left} + $cell->{right};
		$cell->{width}=$w;
		my $watch=$cell->{event};
		if (defined $watch) { $watch=[$watch] unless ref $watch; $self->{events_to_watch}{$_}=undef for @$watch; }
	}
	$self->{viewsize}[0]= $w;

	if (my $ew=$self->{events_to_watch}) {::Watch($self->{view},$_,sub {$_[0]->queue_draw;}) for keys %$ew;}

	$self->updateextrawidth(0);
	$self->scroll_to_row($savedpos->{hirow}||0,1) if $savedpos;
	$self->update_scrollbar;
	$self->UpdateWatcher;
	delete $self->{queue};
	$self->{view}->queue_draw;
	$self->{headers}->update if $self->{headers};
}
sub set_head_columns
{	my ($self,$grouping)=@_;
	$grouping=$self->{grouping} unless defined $grouping;
	$self->{grouping}=$grouping;
	my @cols= $grouping=~m#([^|]+\|[^|]+)(?:\||$)#g; #split into "word|word"
	my $savedpos= $self->coord_to_path(0,int($self->{vadj}->page_size/2)) if $self->{ready}; #save vertical pos
	$self->{headcells}=[];
	$self->{colgroup}=[];
	$self->{songxoffset}=0;
	$self->{songxright}=0;
	$self->{cols2_to_watch}={};
	my $depth=0;
	if (@cols)
	{ for my $colskin (@cols)
	  {	my ($col,$skin)=split /\|/,$colskin;
		next unless $col;
		my $cell= GMB::Cell->new_group( $self,$depth,$col,$GroupBy{$col}[1],$skin );
		#$cell->{skin}=$skin;
		$cell->{x}=$self->{songxoffset};
		$self->{songxoffset}+=$cell->{left};
		$self->{songxright}+=$cell->{right};
		#$cell->{width}=$col->{width}; #FIXME use saved width ?
		push @{$self->{colgroup}},  $col;
		push @{$self->{headcells}}, $cell;
		$depth++;
	  }
	  $self->{listmode}=undef;
	}
	else
	{	$self->{headcells}[0]{$_}=0 for qw/left right x head tail/;
		$self->{listmode}=1;
	}

	$self->update_columns(1);
	$self->BuildTree;
	$self->scroll_to_row($savedpos->{hirow}||0,1) if $savedpos;
}

sub GetSelectedIDs
{	my $self=$_[0];
	my $list=$self->{array};
	my $selected=$self->{selected};
	return map $list->[$_], grep $selected->[$_], 0..$#$selected;
}

sub focus_change
{	my $view=$_[0];
	#my $sel=$self->{selected};
	#return unless keys %$sel;
	#FIXME could redraw only selected keys
	$view->queue_draw;
}

sub Sort
{	my ($self,$sort)=@_;
	$self->{sort}=$sort;
	::SortList($self->{array},$sort);
	$self->BuildTree;
	$self->{headers}->update if $self->{headers}; #to update sort indicator
}

sub buildexpstate	#FIXME find a better way to do this
{	my $self=$_[0]; my $time=times;
	my @exp; my $depth=0;
	my @children=@{ $self->{root} };
	while (@children)
	{	my @todo=@children;
		@children=();
		for my $current (@todo)
		{	my $exp= $current->[BRANCH_EXP];
			$exp[$depth][$_]=$exp for $current->[BRANCH_START] .. $current->[BRANCH_END];
			push @children, @{$current->[BRANCH_CHILD]} if $current->[BRANCH_CHILD];
		}
		$depth++;
	}
	#for (0..20) { warn "row $_ : ".$exp[0][$_].' '.$exp[1][$_]."\n" } warn "\n";
	#warn 'buildexpstate '.(times-$time)."s\n";
	return \@exp;
}

sub SetFilter
{	my ($self,$filter)=@_;
	$self->{filter}=$filter;
	$self->{array}= [@{ $filter->filter }];
	::SortList($self->{array},$self->{sort}) if exists $self->{sort};
	$self->BuildTree;
	$self->{vadj}->set_value(0);
	$self->FollowSong if $self->{TogFollow};
}

sub BuildTree
{	my $self=$_[0]; #my $time=times;
	my $expstate=delete $self->{expstate};
	my $list=$self->{array};
	return unless $list;

	my $colgroup=$self->{colgroup};
	delete $self->{queue};
	$self->{selected}=[];
	$self->{root}=[];
	$self->{startgrow}=$self->{lastclick}=undef;

	my $vsizesong=$self->{vsizesong};

	my $height=0;
	if (@$list==0)
	{
	}
	elsif (!$self->{listmode}) # tree
	{ my $maxdepth=$#$colgroup;
	  #warn "Building Tree\n";

	  my $root=[undef,1,0,$#$list];
	  my $parents=[$root];
	  my @toupdate;
	  my $defaultexp=1;
	  for my $depth (0..$maxdepth)
	  {	my $col=$GroupBy{ $colgroup->[$depth] }[1];
		my $toupdate=$toupdate[$depth]=[];
		my @next;
		for my $branch (@$parents)
		{	my @child;
			my (undef,$exp,$start,$end)=@$branch;
#FIXME			$exp=0 if # $expstate && !$expstate->[$d][$i];
			push(@child,[$::Songs[$list->[$start]][$col],$defaultexp,$start,$_-1]), $start=$_ for (grep $::Songs[$list->[$_]][$col] ne $::Songs[$list->[$_-1]][$col], $start+1..$end),$end+1;
			$branch->[BRANCH_CHILD]=\@child;
			push @next, @child;
			if ($exp)
			{	push @$toupdate,@child; }
#			else { $branch->[BRANCH_HEIGHT]=$vcollapse[$depth]; }
		}
		$parents=\@next;
		$depth++;
	  }
#warn 'BuildTree 1st part '.(times-$time)."s\n";
	  for my $depth (reverse 0..$#toupdate)
	  {	my $cell= $self->{headcells}[$depth];
		my $headtail= $cell->{head}+$cell->{tail};
		my $vcollapse= $cell->{vcollapse};
		my $vmin= $cell->{vmin};
		for my $branch (@{$toupdate[$depth]})
		{	my @child;
			my (undef,$exp,$start,$end,undef,$child)=@$branch;
			my $h;
			$branch->[BRANCH_EXP]=$exp=$expstate->[$depth][$start] if  $expstate;
			if ($exp)
			{	if ($child) { $h+=$_->[BRANCH_HEIGHT] for @$child; }
				else {$h=$vsizesong*($end-$start+1);}
				$h+= $headtail;
				$h=$vmin if $h<$vmin;
			}
			else {$h=$vcollapse;}
			$branch->[BRANCH_HEIGHT]=$h;
		}
	  }
	  $self->{root}=$root=$root->[BRANCH_CHILD];
	  $height+=$_->[BRANCH_HEIGHT] for @$root;
	}
	else # list
	{	$height= @$list*$vsizesong;
		$self->{root}=[['',1,0,$#$list,$height]];  #depends on BRANCH_ values
	}
	  #----------------------------------
	$self->{viewsize}[1]= $height;
	$self->update_scrollbar;
	$self->{view}->queue_draw;
	$self->{ready}=1;#warn 'BuildTree total '.(times-$time)."s\n";
}

sub update_scrollbar
{	my $self=$_[0];
	for my $i (0,1)
	{	my $adj= $self->{ (qw/hadj vadj/)[$i] };
		my $pagesize=$self->{viewwindowsize}[$i]||0;
		my $upper=$self->{viewsize}[$i]||0;
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
	#FIXME copy part that is still visible and queue_draw only what has changed, will need to clean up $self->{action_rectangles}
	delete $self->{queue};
	delete $self->{action_rectangles};
	$self->{view}->queue_draw;
}

sub configure_cb
{	my ($view,$event)=@_;
	my $self=::find_ancestor($view,__PACKAGE__);
	$self->{viewwindowsize}=[$event->width,$event->height];
	if (delete $self->{need_init})
	{	$self->set_head_columns();
		::SetFilter($self,undef,0);	#FIXME
		$self->FollowSong;
	}
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
	$value=0 if $value<0;
	$adj->set_value($value);
	1;
}
sub key_press_cb
{	my ($self,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );

	my $row=0;
	$row=$self->{lastclick} if $self->{lastclick};
	my $list=$self->{array};
	if (	$key eq 'space'
	    ||	$key eq 'Return') { ::SongListActivate($self,$row,1); }
	elsif	($key eq 'Up')		{$row-- if $row>0;	$self->song_selected($event,$row); }
	elsif	($key eq 'Down')	{$row++ if $row<$#$list;$self->song_selected($event,$row); }
	elsif	($key eq 'Home')	{$self->song_selected($event,0); }
	elsif	($key eq 'End')		{$self->song_selected($event,$#$list); }
	elsif	($key eq 'Left')	{ $self->scroll_event_cb('left'); }
	elsif	($key eq 'Right')	{ $self->scroll_event_cb('right'); }
	elsif	($key eq 'Page_Up')	{ $self->scroll_event_cb('up',1); }
	elsif	($key eq 'Page_Down')	{ $self->scroll_event_cb('down',1); }
	elsif	($key eq 'a' && $event->get_state >= ['control-mask']) { $self->{selected}=[(1)x@{$self->{array}}]; $self->{view}->queue_draw;}
	else {return 0}
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
	my $state= $self->state eq 'insensitive' ? 'insensitive' : 'normal';
	#my $sstate=$view->has_focus ? 'selected' : 'active';
	my $sstate='selected';	#Treeview uses only state= normal, insensitive or selected
	$self->{stylewidget}->has_focus($view->has_focus); #themes engine check if the widget has focus
	my $selected=$self->{selected};
	my $branch=$self->{root};
	my $list=$self->{array};
	my @songcells=@{ $self->{cells} };
	my @headcells=@{ $self->{headcells} };
	my $vsizesong=$self->{vsizesong};
	#$window->draw_rectangle($style->base_gc($state), 1, $expose->values);
	my $gc=$style->base_gc($state);
	$window->draw_rectangle($gc, 1, $expose->values);
	return 1 unless $list && @$list;

	my $xadj=int $self->{hadj}->value;
	my $yadj=int $self->{vadj}->value;
	my (@parents,@path,@yend);
	my ($depth,$i)=(0,0);
	my ($x,$y)=(0-$xadj, 0-$yadj);
	my $songxpad=$self->{songxpad};
	my $songypad=$self->{songypad};
	my $songs_x= $x+$self->{songxoffset};
	my $songs_width=$self->{songswidth};

	my $maxy=$self->{viewsize}[1]-$yadj;
	$exp_y2=$maxy if $exp_y2>$maxy; #don't try to draw past the end

	while ($y<=$exp_y2)
	{	my $current=$branch->[$i];
		my $bh=$current->[BRANCH_HEIGHT];  #warn "i=$i/$#$branch y=$y bh=$bh current : @$current\n";
		my $yend=$y+$bh;
		if ($yend>$exp_y1)
		{ #warn "entering ".$current->[0]." (bh=$bh) y=$y\n";
		  my $cell=$headcells[$depth];
		  if ($cell->{head} || $cell->{left} || $cell->{right})
		  {  my $clip=$expose->intersect( Gtk2::Gdk::Rectangle->new( $x+$cell->{x},$y,$cell->{width},$bh) );
		     if ($clip)
		     {	my ($key,$expanded,$start,$end)=@$current; #depends on BRANCH_ constants
			my %arg=
			(	self	=> $cell,	widget	=> $self,	style	=> $style,
				window	=> $window,	clip	=> $clip,	state	=> $state,
				depth	=> $depth,	expanded=> $expanded,
				vx	=> $xadj+$x+$cell->{x},		vy	=> $yadj+$y,
				x	=> $x+$cell->{x},		y	=> $y,
				w	=> $cell->{width},		h	=> $bh,
				grouptype => $cell->{grouptype},	groupkey=> $key,
				groupsongs=> [@{$self->{array}}[$start..$end]],
			);
			my $q=&{$cell->{draw}}(\%arg);
			my $qid=$depth.'g'.($yadj+$y);
			delete $self->{queue}{$qid};
			$self->{queue}{$qid}=$q if $q;
		      }
		  }
		  $y+= $current->[BRANCH_EXP] ? $cell->{head} : $cell->{vcollapse};
		  if ($current->[BRANCH_EXP]) #expanded
		  { if (my $child=$current->[BRANCH_CHILD])
		    {	push @parents,$branch; #warn "i=$i new branch : $child, parent=@parents\n";
			$branch=$child;
			push @path,$i;
			push @yend,$yend;
			$depth++;
			$i=0;
			next;
		    }
		    else #songs
		    {	my $first=$current->[BRANCH_START];
			my $last= $current->[BRANCH_END];
			my $h=($last-$first+1)*$vsizesong;
			last if $y>$exp_y2;
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
				my $state= $selected->[$row] ? $sstate : $state;
				my $detail= $odd? 'cell_odd_ruled' : 'cell_even_ruled';
				#detail can have these suffixes (in order) : _ruled _sorted _start|_last|_middle
				$style->paint_flat_box( $window,$state,'none',$expose,$self->{stylewidget},$detail,
							$songs_x,$y,$songs_width,$vsizesong );
				my $x=$songs_x;
				for my $cell (@songcells)
				{ my $width=$cell->{width};
				  $width+=$self->{extra} if $cell->{last};
				  my $clip=$expose->intersect( Gtk2::Gdk::Rectangle->new($x,$y,$width,$vsizesong) );
				  if ($clip)
				  {	my %arg=
					(state	=> $state,	self	=> $cell,	widget	=> $self,
					 style	=> $style,	window	=> $window,	clip	=> $clip,
					 ID	=> $ID,		song	=> $::Songs[$ID],
					 vx	=> $xadj+$x,	vy	=> $yadj+$y,
					 x	=> $x,		y	=> $y,
					 w	=> $width,	h	=> $vsizesong,
					 odd	=> $odd,
					);
					my $q=&{$cell->{draw}}(\%arg);
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
		while ($i>=$#$branch)
		{	# warn "end branch=$branch i=$i\n";
			$depth--;
			$branch=pop @parents;
			last unless $branch;
			$i=pop @path;
			#$y+=$headcells[$depth]{tail};
			$y=pop @yend;
			# warn " -> branch=$branch i=$i\n";
		}
		last unless $branch;
		$i++;
	}
	if (!$self->{idle} && $self->{queue})
	{	$self->{idle}||=Glib::Idle->add(\&expose_queue,$self);
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
	my (@parents,@path,@yend);
	my ($depth,$i)=(0,0);
	my ($hirow,$area,$row);
	my $branch=$self->{root};
	my $current;
	############# find vertical position
	while ($branch)
	{	$current=$branch->[$i];  #warn "i=$i/$#$branch y=$y current : $current->[0]\n";
		last unless $current;
		my $bh=$current->[BRANCH_HEIGHT];
		my $yend=$y-$bh;
		if ($y>=0 && $yend<0)
		{ if ($current->[BRANCH_EXP]) #expanded
		  {	my $head= $self->{headcells}[$depth]{head};
			if ($y-$head<=0) #head
			{	my $after= $y > $head/2;
				$hirow= $current->[BRANCH_START];
				$area='head';
				last;
			}
			$y-=$head;
			if (my $child=$current->[BRANCH_CHILD])
		  	{	push @parents,$branch; #warn "i=$i new branch : $child, parent=@parents\n";
				push @path,$i;
				push @yend,$yend;
				$depth++;
				$branch=$child;
				$i=0;
				my $cell=$self->{headcells}[$depth];
				redo;
			}
			else #songs
		  	{	my $first=$current->[BRANCH_START];
				my $last= $current->[BRANCH_END];
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
			$hirow= $current->[BRANCH_END]+1;
			$area='tail';
			last;
		  }
		  else #collapsed group
		  {	my $after= $y > $bh/2;
			$hirow=$after ? $current->[BRANCH_START] : $current->[BRANCH_END]+1;
			$area='collapsed';
			last;
		  }
		}
		$y=$yend;
		while ($i>=$#$branch)
		{	#warn "end branch=$branch depth=$depth i=$i \@yend=@yend\n";
			$depth--;
			$branch=pop @parents;
			last unless $branch;
			$y=pop @yend; #warn "y=$y\n";
			$i=pop @path;
			my $cell=$self->{headcells}[$depth];
			if ($y<0)
			{	my $current=$branch->[$i];
				$area='tail';
				$hirow= $current->[BRANCH_END]+1;
				last;
			}
		}
		$i++;
	}
	unless (@path)
	{	$area||='end'; #empty space at the end
	}
	return undef unless $area;

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
			start	=> $current->[BRANCH_START],
			end	=> $current->[BRANCH_END],
			depth	=> $depth,
			row	=> $row,
			hirow	=> $hirow,
			area	=> $area,
			harea	=> $harea,
			x	=> $x2,
			y	=> $y,
			col	=> $col,
		};
}

sub row_to_path #used only by row_to_branch which is not used
{	my ($self,$row)=@_;
	my $branch=$self->{root};
	my $i=0; my @path;

	{	my $current=$branch->[$i];
		if ($current->[BRANCH_START] >$row && $current->[BRANCH_END] <$row)
		{	if (my $child=$current->[BRANCH_CHILD])
			{	$branch=$child;
				push @path,$i;
				$i=0;
				redo;
			}
			return \@path;
		}
	}
	return undef;
}
sub row_to_y
{	my ($self,$row)=@_;
	my $branch=$self->{root};
	my $y=0;
	my $depth=0;

	{	my $i=0;
		while ($branch->[$i][BRANCH_END]<$row)
		{	$y+=$branch->[$i][BRANCH_HEIGHT];
			$i++;
			return 0 if $i > $#$branch;
		}
		$y+= $self->{headcells}[$depth]{head};
		return $y unless $branch->[$i][BRANCH_EXP];
		my $child=$branch->[$i][BRANCH_CHILD];
		unless ($child)
		{	my $first=$branch->[$i][BRANCH_START];
			$y+= $self->{vsizesong}*($row-$first);
			return $y;
		}
		$branch=$child;
		$depth++;
		redo;
	}
}
sub update_row
{	my ($self,$row)=@_;
	my $y=$self->row_to_y($row);
	return unless defined $y;
	my $x= $self->{songxoffset} - int($self->{hadj}->value);
	$y-= $self->{vadj}->value;
	$self->{view}->queue_draw_area($x, $y, $self->{songswidth}, $self->{vsizesong});
}

sub MoveOne #FIXME implement
{
}
sub MoveMax #FIXME implement
{
}
sub RemoveSelected
{	my $self=shift;
	my $selected=$self->{selected};
	my @rows=grep $selected->[$_], 0..$#$selected;
	$self->rowremove(\@rows);
}

sub rowinsert
{	my ($self,$row,$IDs)=@_;
	my $list=$self->{array};
	if (!$self->{listmode})
	{	$self->{expstate}||=$self->buildexpstate;
		my $rowref=$row;
		$rowref++;
		$rowref=$#$list if $rowref > $#$list;
		splice @$list, $row, 0, @$IDs;
		for my $exp (@{ $self->{expstate} })
		{	splice @$exp,$row,0, ($exp->[$rowref])x@$IDs;
		}
	}
	else { splice @$list, $row, 0, @$IDs; }
	splice @{ $self->{selected} }, $row, 0, (undef)x@$IDs   if @{ $self->{selected} } > $row;
	$self->{lastclick}+=@$IDs if defined $self->{lastclick} && $self->{lastclick} > $row;
	delete $self->{startgrow};
	$self->BuildTree;
}
sub RemoveID
{	my ($self,$IDs)=@_;
	my %h;
	$h{$_}=undef for @$IDs;
	my $array=$self->{array};
	my @list;
	for my $i (0..$#$array)
	{	push @list,$i if exists $h{$array->[$i]};
	}
	$self->rowremove(\@list) if @list;
}
sub rowremove
{	my ($self,$rows,$norebuildtree)=@_;
	@$rows= sort {$b <=> $a} @$rows;
	if (!$self->{listmode})
	{	$self->{expstate}=$self->buildexpstate;
		for my $expd (@{ $self->{expstate} })
		{	splice @$expd, $_, 1 for @$rows;
		}
	}
	for my $row (@$rows)
	{	splice @{ $self->{array} }, $row, 1;
		splice @{ $self->{selected} }, $row, 1;
		$self->{lastclick}-- if defined $self->{lastclick} && $self->{lastclick} > $row;
	}
	delete $self->{startgrow};
	return if $norebuildtree;
	$self->BuildTree;
}
sub rowchanged
{	my $self=$_[0]; #my ($self,@rows)=@_;
	if (!$self->{listmode})
	{	$self->{expstate}=$self->buildexpstate;
	}
	$self->BuildTree;
}

sub drag_received_cb
{	my ($view,$type,$dest,@IDs)=@_;
	if ($type==::DRAG_FILE) #convert filenames to IDs
	{	@IDs=map @$_,grep ref,map ::ScanFolder(::decode_url($_)), grep s#^file://##, @IDs;
		return unless @IDs;
	}
	my $self=::find_ancestor($view,__PACKAGE__);
	my (undef,$row)=@$dest;
	return unless defined $row; #FIXME
#warn "dropped, insert before row $row, song : ".$::Songs[$self->{array}[$row]][::SONG_TITLE]."\n";
	my $selected=$self->{selected};
	if ($view->{drag_is_source})
	{	my @rows=reverse grep $selected->[$_], 0..$#$selected;
		$_<$row && $row-- for @rows;
		$self->rowremove(\@rows,1); # 1 as 2nd argument to delay update of the tree, the rowinsert will do it
	}
	$self->rowinsert($row,\@IDs);
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

sub path_to_branch
{	my ($self,$path)=@_;
	my @path=@$path;
	my $branch=$self->{root};
	$branch=$branch->[shift @path][BRANCH_CHILD] while @path>1;
	return $branch->[$path[0]];
}

sub row_to_branch #not used
{	my ($self,$row)=@_;
	my $path=$self->row_to_path($row);
	return $self->path_to_branch($path);
}

sub expand_colapse
{	my ($self,$path)=@_;
	my $branch=$self->path_to_branch($path);
	$branch->[BRANCH_EXP]^=1;
	$self->update_height_of_path($path);
}

sub update_height_of_path
{	my ($self,$updatepath)=@_;
	delete $self->{queue};
	my $root=$self->{root};
	my @toupdate;
	my ($depth,$i)=(0,0); my @parents; my $oldheight;
	if ($updatepath)
	{	my @path=@$updatepath;
		while (@path>1)
		{	my $i=shift @path;
			if ($root->[$i][BRANCH_HEIGHT]<=$self->{headcells}[$depth]{vmin}) {@path=($i);last}
			push @toupdate, $root->[$i];
			$root=$root->[$i][BRANCH_CHILD];
			$depth++;
		}
		$i=shift @path;
		$oldheight=$root->[$i][BRANCH_HEIGHT];
	}
	else { $oldheight=$self->{viewsize}[1]; push @parents,undef; } #update whole tree

	my $branch=$root;
	my @headcells=@{ $self->{headcells} };
	my $y=0; my @path; my @y;

	while ($branch)
	{	my $current=$branch->[$i];# warn "@$current\n";
		my $ystart=$y;
		if ($current->[BRANCH_EXP]) #expanded
		{	$y+=$headcells[$depth]{head}; #warn "+head y=$y\n";
			if (my $child=$current->[BRANCH_CHILD])
			{	push @parents,$branch;
				push @y, $ystart;
				$branch=$child;
				push @path,$i;
				$depth++;
				$i=0;
				redo;
			}
			my $first=$current->[BRANCH_START];
			my $last= $current->[BRANCH_END];
			$y+= ($last-$first+1)*$self->{vsizesong};  #warn "+songs y=$y\n";
			$y+=$headcells[$depth]{tail};  #warn "+tail y=$y\n";
			if ($y-$ystart < $headcells[$depth]{vmin}) { $y= $headcells[$depth]{vmin}+$ystart }
		}
		else
		{	$y+=$headcells[$depth]{vcollapse};  #warn "+vcollapse y=$y\n";
		}
		$branch->[$i][BRANCH_HEIGHT]=$y-$ystart;
		last unless @parents;
		while ($i>=$#$branch)
		{	$depth--;
			$branch=pop @parents;
			last unless $branch;
			$y+=$headcells[$depth]{tail}; #warn "+tail depth=$depth\n";
			$i=pop @path;
			my $ystart=pop @y;
			####		warn "old : ".$branch->[$i][BRANCH_HEIGHT]." new : ".($y-$ystart)."\n";
			if ($y-$ystart < $headcells[$depth]{vmin}) { $y= $headcells[$depth]{vmin}+$ystart }
			$branch->[$i][BRANCH_HEIGHT]=$y-$ystart;
		}
		last unless @parents;
		$i++;
	}
	#update parents
	$depth=@toupdate;
	my $diff= $y-$oldheight; #warn "y=$y old=$oldheight diff=$diff depth=$depth\n";
	while ($depth)
	{	$depth--;
		my $parent=pop @toupdate;
		my $old=$parent->[BRANCH_HEIGHT];
		if ($old+$diff < $headcells[$depth]{vmin}) { $diff= $headcells[$depth]{vmin}-$old; } #warn " depth=$depth new diff=$diff\n"
		$parent->[BRANCH_HEIGHT]+= $diff;
	}
	$self->{viewsize}[1]+= $diff;

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
	if (my $ref=$self->{action_rectangles} && 0) #TESTING
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
		::SongListActivate($self,$row,$but);
		return 1;
	}
	if ($but==3)
	{	if (!defined $depth && !$self->{selected}[$row])
		{	$self->song_selected($event,$row);
		}
		my @IDs=$self->GetSelectedIDs;
		my $list= $self->{array};
		$::LEvent=$event;
		my %args=(self => $self, mode => $self->{type}, IDs => \@IDs, listIDs => $list);
		::PopupContextMenu(\@::SongCMenu,\%args ) if @$list;

		return 1;
	}
	else# ($but==1)
	{	return 0 unless $answer;
		if (defined $depth && $answer->{area} eq 'head' || $answer->{area} eq 'collapsed')
		{	#$self->song_selected($event,$answer->{start},$answer->{end});
			$self->expand_colapse($answer->{path});
			return 1;
		}
		elsif (defined $depth && $answer->{harea} eq 'left')
		{	$self->song_selected($event,$answer->{start},$answer->{end});
			return 0;
		}
		if (defined $row)
		{	if ( $event->get_state * ['shift-mask', 'control-mask'] || !$self->{selected}[$row] )
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

sub UpdateSelID
{	my $self=$_[0];
	$self->FollowSong if $self->{TogFollow};
}
sub FollowSong
{	my $self=$_[0];
	return unless defined $::SongID;
	my $array=$self->{array};
	return unless $array;
	for my $i (0..$#$array)
	{	next unless $array->[$i] == $::SongID;
		$self->{selected}=[];
		$self->{selected}[$i]=1;
		$self->scroll_to_row($i,1,1);
	}
	::HasChanged('SelectedID_'.$self->{group},$::SongID,$self->{group});
}

sub song_selected
{	my ($self,$event,$idx1,$idx2)=@_;
	return if $idx1<0 || $idx1 >= @{$self->{array}};
	$idx2=$idx1 unless defined $idx2;
	$self->scroll_to_row($idx1);
	::HasChanged('SelectedID_'.$self->{group},$self->{array}[$idx1],$self->{group});
	unless ($event->get_state >= ['control-mask'])
	{	$self->{selected}=[];
	}
	if ($event->get_state >= ['shift-mask'] && defined $self->{lastclick})
	{	$self->{startgrow}=$self->{lastclick} unless defined $self->{startgrow};
		my $i1=$self->{startgrow};
		my $i2=$idx1;
		if ($i1>$i2)	{ ($i1,$i2)=($i2,$i1) }
		else		{ $i2=$idx2 }
		$self->{selected}[$_]=1 for $i1..$i2;
	}
	elsif (!grep !$self->{selected}[$_], $idx1..$idx2)
	{	delete $self->{selected}[$_] for  $idx1..$idx2;
		delete $self->{startgrow};
	}
	#elsif ($self->{selected}[$idx])
	#{	delete $self->{selected}[$idx];
	#	delete $self->{startgrow};
	#}
	else
	{	$self->{selected}[$_]=1 for $idx1..$idx2;
		delete $self->{startgrow};
	}
	$self->{lastclick}=$idx1;
	::HasChanged('Selection_'.$self->{group});

	$self->queue_draw;
}

package SongTree::Headers;
use Gtk2;
use base 'Gtk2::Viewport';
use constant TREE_VIEW_DRAG_WIDTH => 6;

our @ColumnMenu=
(	{ label => _"_Sort by",		submenu => sub { Browser::make_sort_menu($_[0]{songtree}); }
	},
	{ label => _"Set grouping",	submenu => \%SongTree::Groupings,
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
	{ label => _"Follow playing song",	code => sub { $_[0]{songtree}->FollowSong if $_[0]{songtree}{TogFollow}^=1; },
	  check => sub { $_[0]{songtree}{TogFollow} }
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
	if ($self->{resizecol})
	{	Gtk2->grab_remove($self);
		my $songtree=::find_ancestor($self,'SongTree');
		my $cell= $songtree->{cells}[ $self->{resizecol}[1]->{cellnb} ];
		$songtree->{colwidth}{$cell->{colid}}= $cell->{width}; #set width as default for this colid
		delete $self->{resizecol};
		_update_dragwin($_) for $self->child->get_children;
	}
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
	my $rcstyle0=Gtk2::RcStyle->new;
	$rcstyle0->ythickness(0);
	$rcstyle0->xthickness(0);
	$self->modify_style($rcstyle0);

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
	my $invsort=my $sort=$songtree->{sort};
	$invsort='-'.$invsort unless $invsort=~s/^-//; #FIXME support complex sort
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
	my $sort= $button->{colid} ? $button->{sort} : join ' ',map $SongTree::GroupBy{$_->{col}}[1], @{$songtree->{headcells}};
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
	$::LEvent=$event;
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
		$button->{dragwin}->raise;
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
	warn "destroying $button->{dragwin}\n" if $button->{dragwin};
	$button->{dragwin}->set_user_data(0) if $button->{dragwin}; #FIXME
	$button->{dragwin}->destroy if $button->{dragwin};
	$button->{dragwin}=undef;
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
		    	['aapic_cached','aap queue = picsize aa aakey aanb hide'],
			 $drawpix,$padandalignx,$padandaligny,
		    ],
		    defaults =>
		    	'x=0,y=0,w=___picsize+2*___xpad,h=___picsize+2*___ypad,xpad=xpad,ypad=ypad,xalign=.5,yalign=.5,aanb=0,aa=$_grouptype,aakey=$_groupkey,picsize=min(___w+2*___xpad,___h+2*___ypad)',
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
	$sort=~s#([a-z]+)#$::TagIndex{$1}#ig if defined $sort;
	my $self=bless {colid => $colid, width => $width, 'sort' => $sort }, $class;
	return $self;
}

sub init_songs
{	my ($widget,$cells)=@_;
	my $initcontext={ widget => $widget, init=>1, };
	my $constant={ xpad=>$widget->{songxpad}, ypad=>$widget->{songypad}, playmarkup=>'weight="bold"' };
	my @blh; my @y_refs;
	my @Deps;
	for my $cell (@$cells)
	{	my $colid=$cell->{colid};
		my (@draw,@elems);
		for my $part (@{ $SongTree::STC{$colid}{elems} })
		{	my ($eid,$elem,$opt)= $part=~m/^(\w+)=(\w+)\s*\((.*)\)$/;
			next unless $elem;
			push @elems,[$eid.':',$elem,$opt];
			push @draw,$eid;
		}
		my $h =$SongTree::STC{$colid}{hreq};
		my $bl=$SongTree::STC{$colid}{songbl};
		push @elems, ['',undef,"hreq=$h"] if $h;
		my ($dep,$update)=createdep(\@elems,'song',$constant);
		$cell->{event}= [keys %{$update->{event}}] if $update->{event};
		$cell->{watchcol}=[keys %{$update->{col}}] if $update->{col};
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
{	my ($class,$widget,$depth,$grouptype,$colnb,$skin)=@_;
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
		{	col	=> $colnb,
			grouptype=> $grouptype,
			depth	=> $depth,
		#	watchcol=> $colnb,
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
	$self->{watchcol}=[keys %{$update->{col}}] if $update->{col};
	for my $key (keys %hide)
	{	my $hide;
		$hide='!' if $hide{$key};
		$hide.= '$arg->{expanded}';
		$hide.= '|| ('.$dep->{$key}[0].')' if exists $dep->{$key};
		$dep->{$key}[0]= $hide;
	}

	my $initcontext={groupkey  =>'', widget => $widget, expanded =>1, init=>1, depth => $depth, grouptype =>$grouptype};
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
	if (defined $markup) { $markup=~s#\\n#\n#g; $layout->set_markup($markup); }
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
	my $cached=AAPicture::load_file($file,$crop,$resize);
	return $cached||$resize, !$cached;
}
sub pic_size
{	my ($arg,$cached,$file,$crop,$hide)=@_;
	return undef,0,0 if $hide || !$file;
	my $pixbuf=$cached;
	unless (ref $cached) #=> cached is resize_w_h
	{	$pixbuf=AAPicture::load_file($file,$crop,$cached,1);
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
{	my ($arg,$picsize,$aa,$aakey,$aanb,$hide)=@_;
	return undef,0 if $hide;
	#$aa||=$arg->{grouptype};
	#$aakey||=$arg->{groupkey};
	#$now=1 if $param->{notdelayed};
	if ($aa) { $aa= $aa eq 'artist' ? ::SONG_ARTIST : $aa eq 'album' ? ::SONG_ALBUM : undef; }
	return undef,0 unless $aa;
	if ($aa==::SONG_ARTIST) {$aakey=(split /$::re_artist/o,$aakey)[ $aanb ];}
	my $pixbuf=AAPicture::pixbuf($aa,$aakey,$picsize);
	my ($aap,$queue)=	$pixbuf		? ($pixbuf,undef) :
				defined $pixbuf ? ([$aa,$aakey,$picsize],1) :
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

package EditSTGroupings;
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
	my $typelist=TextCombo->new({map {$_ => $SongTree::GroupBy{$_}[0]} keys %SongTree::GroupBy}, $type );
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
		my $entry= &{$opt_types{$type}[0]}($v,$l,$ref);
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
				my $v= &{ $opt_types{$type}[1] }($h->{$key});
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

our %alias=( 'if' => 'iff', pesc => '::PangoEsc', ratingpic => 'Stars::get_pixbuf');
our %functions=
(	formattime=> ['do { my ($f,$t,$z)=(',		'); !$t && defined $z ? $z : ::strftime($f,localtime($t)); }'],
	sum	=>   ['do {my $sum; $sum+=$_ for ',	';$sum}'],
	average	=>   ['do {my $sum; my @l=(',		'); $sum+=$_ for @l; @l ? $sum/@l : undef}'],
	max	=>   ['do {my ($max,@l)=(',		'); $_>$max and $max=$_ for @l; $max}'],
	min	=>   ['do {my ($min,@l)=(',		'); $_<$min and $min=$_ for @l; $min}'],
	iff	=>   ['do {my ($cond,$res,@l)=(',	'); while (@l>1) {last if $cond; $cond=shift @l;$res=shift @l;} $cond ? $res : $l[0] }'],
	playmarkup=> \&playmarkup,
);
$functions{$_}=undef for qw/ucfirst uc lc chr ord not ::PangoEsc Stars::get_pixbuf index length substr join sprintf warn abs int rand/;
our %vars2=
(song=>
 {	title	=> ['$arg->{song}[::SONG_TITLE]',	::SONG_TITLE],
	artist	=> ['$arg->{song}[::SONG_ARTIST]',	::SONG_ARTIST],
	album	=> ['$arg->{song}[::SONG_ALBUM]',	::SONG_ALBUM],
	date	=> ['$arg->{song}[::SONG_DATE]',	::SONG_DATE],
	year	=> ['$arg->{song}[::SONG_DATE]',	::SONG_DATE],
	track	=> ['$arg->{song}[::SONG_TRACK]',	::SONG_TRACK],
	disc	=> ['$arg->{song}[::SONG_DISC]',	::SONG_DISC],
	comment	=> ['$arg->{song}[::SONG_COMMENT]',	::SONG_COMMENT],
	playcount=>['$arg->{song}[::SONG_NBPLAY]',	::SONG_NBPLAY],
	skipcount=>['$arg->{song}[::SONG_NBSKIP]',	::SONG_NBSKIP],
	ufile	=> ['$arg->{song}[::SONG_UFILE]',	::SONG_UFILE],
	upath	=> ['$arg->{song}[::SONG_UPATH]',	::SONG_UPATH],
	version	=> ['$arg->{song}[::SONG_VERSION]',	::SONG_VERSION],
	rating	=> ['$arg->{song}[::SONG_RATING]',	::SONG_RATING],
	channel	=> ['$arg->{song}[::SONG_CHANNELS]',	::SONG_CHANNELS],
	samprate=> ['$arg->{song}[::SONG_SAMPRATE]',	::SONG_SAMPRATE],
	bitrate	=> ['$arg->{song}[::SONG_BITRATE]',	::SONG_BITRATE],
	filetype=> ['$arg->{song}[::SONG_FORMAT]',	::SONG_FORMAT],
	size	=> ['$arg->{song}[::SONG_SIZE]',	::SONG_SIZE],
	length_	=> ['$arg->{song}[::SONG_LENGTH]',	::SONG_LENGTH],
	lastplay_=>['$arg->{song}[::SONG_LASTPLAY]',	::SONG_LASTPLAY],
	lastskip_=>['$arg->{song}[::SONG_LASTSKIP]',	::SONG_LASTSKIP],
	added_	=> ['$arg->{song}[::SONG_ADDED]',	::SONG_ADDED],
	modif_	=> ['$arg->{song}[::SONG_MODIF]',	::SONG_MODIF],
	genre	=> ['join(", ", split(/\\x00/, $arg->{song}[::SONG_GENRE]))',	::SONG_GENRE],
	label	=> ['join(", ", split(/\\x00/, $arg->{song}[::SONG_LABELS]))',	::SONG_LABELS],
	lastplay=> ['do { my $v=$arg->{song}[::SONG_LASTPLAY]; $v ? scalar localtime $v : "'.quotemeta(_("never")).'"}',::SONG_LASTPLAY],
	lastskip=> ['do { my $v=$arg->{song}[::SONG_LASTSKIP]; $v ? scalar localtime $v : "'.quotemeta(_("never")).'"}',::SONG_LASTSKIP],
	added	=> ['do { my $v=$arg->{song}[::SONG_ADDED]; $v ? scalar localtime $v : "'.quotemeta(_("never")).'"}',	::SONG_ADDED],
	modif	=> ['do { my $v=$arg->{song}[::SONG_MODIF]; $v ? scalar localtime $v : "'.quotemeta(_("never")).'"}',	::SONG_MODIF],
	'length'=> ['do { my $v=$arg->{song}[::SONG_LENGTH];sprintf "%d:%02d",$v/60,$v%60;}',		::SONG_LENGTH],
	progress=> ['$arg->{ID}==$::SongID ? $::PlayTime/$arg->{song}[::SONG_LENGTH] : 0',	::SONG_LENGTH,[qw/SongID Time/]],
	queued	=> ['do {my $i;my $f;for (@::Queue) {$i++; $f=$i,last if $arg->{ID}==$_};$f}',undef,'Queue'],
	playing => ['$arg->{ID}==$::SongID',		undef,'SongID'],
	playicon=> ['::Get_PPSQ_Icon($arg->{ID})',	undef,[qw/Playing Queue SongID/]],
	labelicons=>['[grep Gtk2::IconFactory->lookup_default($_),map \'label-\'.$_,split /\\x00/,$arg->{song}[::SONG_LABELS]]',::SONG_LABELS,'Icons'],
 },
 group=>
 {	year	=> ['groupyear($arg->{groupsongs})',	::SONG_DATE],
	artist	=> ['groupartist($arg->{groupsongs})',	::SONG_ARTIST],
	album	=> ['groupalbum($arg->{groupsongs})',	::SONG_ALBUM],
	genres	=> ['groupgenres($arg->{groupsongs},::SONG_GENRE)',	::SONG_GENRE],
	labels	=> ['groupgenres($arg->{groupsongs},::SONG_LABELS)',	::SONG_LABELS],
 	title	=> ['$arg->{groupkey}'],
	rating_avrg => ['do {my $sum; $sum+= $_ eq "" ?  $::Options{DefaultRating} : $_ for map $::Songs[$_][::SONG_RATING],@{$arg->{groupsongs}}; $sum/@{$arg->{groupsongs}}; }',::SONG_RATING], #FIXME round, int ?
	'length' => ['do {my $v; $v+=$_ for map $::Songs[$_][::SONG_LENGTH],@{$arg->{groupsongs}}; sprintf "%d:%02d",$v/60,$v%60;}',::SONG_LENGTH],
	nbsongs	=> ['scalar @{$arg->{groupsongs}}'],
	disc	=> ['groupdisc($arg->{groupsongs})',	::SONG_DISC],
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
					{	$ref=&$ref($constant) if ref $ref eq 'CODE';
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
		{	$update->{col}{$_}=undef for (ref $c ? @$c : $c);
		}
		if (defined $e)
		{	$update->{event}{$_}=undef for (ref $e ? @$e : $e);
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
	elsif ($var) {&$coderef($var)}
	else { return $coderef}
}

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

sub groupyear
{	my $songs=$_[0];
	my %h;
	my @y=sort { $a <=> $b } grep $_,map $::Songs[$_][::SONG_DATE], @$songs;
	my $years='';
	if (@y) {$years=$y[0]; $years.=' - '.$y[-1] if $y[-1]!=$years; }
	return $years;
}
sub groupalbum
{	my $songs=$_[0];
	my %h; $h{ $::Songs[$_][::SONG_ALBUM] }=undef for @$songs;
	my $nb=keys %h;
	return (keys %h)[0] if $nb==1;
	return ::__("%d album","%d albums",$nb);
}
sub groupartist
{	my $songs=$_[0];
	my %h; $h{ $::Songs[$_][::SONG_ARTIST] }=undef for @$songs;
	my $nb=keys %h;
	return (keys %h)[0] if $nb==1;
	my @l=map split(/$::re_artist/o), keys %h;
	my %h2; $h2{$_}++ for @l;
	my @common;
	for (@l) { if ($h2{$_}>=$nb) { push @common,$_; delete $h2{$_}; } }
	return @common ? join ' & ',@common : ::__("%d artist","%d artists",scalar(keys %h2));
}
sub groupgenres
{	my ($songs,$field,$common)=@_;
	my %h;
	for my $ID (@$songs)
	{	$h{$_}++ for split /\x00/, $::Songs[$ID][$field];
	}
	delete $h{''};
	return join ', ',sort ($common? grep($h{$_}==@$songs,keys %h) : keys %h);
}
sub groupdisc
{	my $songs=$_[0];
	my %h;
	$h{$_}++ for map $::Songs[$_][::SONG_DISC], @$songs;
	delete $h{''};
	if ((keys %h)==1 && (values %h)[0]==@$songs) {return (keys %h)[0]}
	else {return ''}
}
sub error
{	warn "unknown function : '$_[0]'\n";
}

sub playmarkup
{	my $constant=$_[0];
	return ['do { my $markup=',	'; $arg->{ID}==$::SongID ? \'<span '.$constant->{playmarkup}.'>\'.$markup."</span>" : $markup }',undef,'SongID'];
}



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
	::Watch($self,SongID=> sub {$_[0]->queue_draw});
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
				::SongRemove($ID);
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

1;
