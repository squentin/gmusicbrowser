# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin DesktopWidgets
name	Desktop widgets
title	Desktop widgets plugin
desc	Open special layouts as desktop widgets
=cut

package GMB::Plugin::DesktopWidgets;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_DesktopWidgets_',
};

my $DWlist= $::Options{OPT.'list'} ||= {};
my %Displayed;
my ($OptionsBox,$Treeview,$LayoutCombo);

sub Start
{	Glib::Idle->add( sub { CreateWindow($_) for sort keys %$DWlist; 0; });
}
sub Stop
{	$_->close_window for grep $_, values %Displayed;
	%Displayed=();
}
sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	$LayoutCombo= TextCombo::Tree->new( sub {Layout::get_layout_list('D')}, undef, undef, event=>'Layouts', );
	my $layoutlabel= Gtk2::Label->new(_"Layout :");
	my $add= ::NewIconButton('gtk-add',_"Add", sub { New($LayoutCombo->get_value); });

	my $store=Gtk2::ListStore->new('Glib::String','Glib::Boolean','Glib::String');
	$Treeview=Gtk2::TreeView->new($store);
	$Treeview->set_size_request(100,($Treeview->create_pango_layout("X")->get_pixel_size)[1]*5.5); #request 5.5 lines of height (not counting row spacing)
	$Treeview->set_headers_visible(::FALSE);
	my $togglerenderer=Gtk2::CellRendererToggle->new;
	$togglerenderer->signal_connect(toggled => \&toggled);
	$Treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes( 'active', $togglerenderer, active => 1 ));
	my $renderer=Gtk2::CellRendererText->new;
	$Treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes( 'name', $renderer, text => 2 ));
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($Treeview);
	$Treeview->get_selection->signal_connect(changed => \&selchanged_cb);

	$OptionsBox=Gtk2::VBox->new(::FALSE, 2);
	$vbox->pack_start($_,::FALSE,::FALSE,2) for ::Hpack( $layoutlabel,$LayoutCombo,$add ),$sw,$OptionsBox;
	::weaken($OptionsBox);
	::weaken($Treeview);
	::weaken($LayoutCombo);
	Fill();
	return $vbox;
}

sub Fill
{	my $selected=shift;
	return unless $Treeview;
	my $store=$Treeview->get_model;
	$store->clear;
	for my $key (sort keys %$DWlist)
	{	my $layout= $DWlist->{$key}{layout};
		my $name= Layout::get_layout_name($layout);
		my $iter=$store->append;
		$store->set($iter, 0,$key, 1,!$DWlist->{$key}{dw_inactive}, 2,$name);
		$Treeview->get_selection->select_iter($iter) if $selected && $key eq $selected;
	}
}

sub Remove
{	my $key=shift;
	return unless $key;
	delete $DWlist->{$key};
	my $window= delete $Displayed{$key};
	$window->close_window if $window;
	Fill();
}

sub selchanged_cb
{	my $treesel=shift;
	$OptionsBox->remove($_) for $OptionsBox->get_children;
	my $iter=$treesel->get_selected;
	return unless $iter;
	my $key=$Treeview->get_model->get($iter,0);
	FillOptions($key);
}
sub toggled
{	my ($cell, $path_string)=@_;
	my $store=$Treeview->get_model;
	my $iter=$store->get_iter_from_string($path_string);
	my $key= $store->get($iter,0);
	my $state= $DWlist->{$key}{dw_inactive}^=1;
	$store->set($iter,1,!$state);
	if ($state)
	{	my $window= delete $Displayed{$key};
		$window->close_window if $window;
	}
	else { CreateWindow($key); }
}

sub New
{	my $layout=shift;
	return unless defined $layout;
	my $layoutdef=$Layout::Layouts{$layout};
	return unless $layoutdef;
	my $key='DesktopWidget000';
	$key++ while defined $DWlist->{$key};
	my $default_window_opt= ::ParseOptions( $layoutdef->{Window}||'' );
	my $size= $default_window_opt->{size} || '1x1';
	my ($w,$h)= $size=~m/(\d+)x(\d+)/;
	my %opt=
	(	layout		=> $layout,
		DefaultFontColor=> $layoutdef->{DefaultFontColor} || 'white',
		DefaultFont	=> $layoutdef->{DefaultFont} || 'Sans 12',
		monitor => 0,
		below	=> 1,
		opacity	=> 1,
		x	=> 0,
		y	=> 0,
		w	=> $w||1,
		h	=> $h||1,
	);
	$DWlist->{$key}= \%opt;
	CreateWindow($key);
	Fill($key);
}
sub FillOptions
{	my $key=shift;
	return unless $OptionsBox;
	my $opt= $DWlist->{$key};
	my $layout= $opt->{layout};
	my $label= Gtk2::Label->new;
	my $remove= ::NewIconButton('gtk-remove',_"Remove this widget", sub { Remove($key) });
	if ($Layout::Layouts{$layout})
	{	my $name=  $Layout::Layouts{$layout}{Name} || $layout;
		my $author=$Layout::Layouts{$layout}{Author};
		my $markup= "<b>%s</b>";
		if (defined $author)
		{	$author= _("by").' '.$author;
			$markup.= "\n<i><small>%s</small></i>";
		}
		$label->set_markup_with_format($markup,$name, $author||() );
	}
	else
	{	$label->set_markup_with_format("<b>%s</b>",_"The layout for this desktop widget is missing.");
		my $vbox= ::Hpack($label, '-',$remove);
		$OptionsBox->pack_start($vbox,::FALSE,::FALSE,2);
		$OptionsBox->show_all;
		return;
	}

	my $textcolor= Gtk2::ColorButton->new_with_color( Gtk2::Gdk::Color->parse($opt->{DefaultFontColor}) );
	$textcolor->signal_connect(color_set=>sub { $opt->{DefaultFontColor}= $_[0]->get_color->to_string; CreateWindow($key); });
	#my $set_textcolor= ::NewPrefCheckButton(OPT.'set_textcolor',_"Change default text color", cb=>\&init, widget=>$textcolor, horizontal=>1);

	my $textfont= Gtk2::FontButton->new_with_font( $opt->{DefaultFont} );
	$textfont->signal_connect(font_set=>sub { $opt->{DefaultFont}= $_[0]->get_font_name; CreateWindow($key); });

	my $adjx=Gtk2::Adjustment->new($opt->{x},0,100,1,10,0);
	my $adjy=Gtk2::Adjustment->new($opt->{y},0,100,1,10,0);
	#my $spinx=Gtk2::SpinButton->new($adjx,0,0);
	#my $spiny=Gtk2::SpinButton->new($adjy,0,0);
	my $spinx=Gtk2::HScale->new($adjx);
	my $spiny=Gtk2::HScale->new($adjy);
	$spinx->set_digits(0);
	$spiny->set_digits(0);
	$adjx->signal_connect(value_changed => sub { $opt->{x}=$_[0]->get_value; MoveWindow($key);  });
	$adjy->signal_connect(value_changed => sub { $opt->{y}=$_[0]->get_value; MoveWindow($key);  });

	my $screen= Gtk2::Gdk::Screen->get_default;
	my $monitors= $screen->get_n_monitors;
	my $adj_mon=Gtk2::Adjustment->new($opt->{monitor},0,$monitors-1,1,2,0);
	my $spin_mon= Gtk2::SpinButton->new($adj_mon,0,0);
	$spin_mon->set_sensitive(0) if $monitors<2;
	$adj_mon->signal_connect(value_changed => sub { $opt->{monitor}=$_[0]->get_value; MoveWindow($key);  });

	my $adjo=Gtk2::Adjustment->new($opt->{opacity}*100,0,100,1,10,0);
	my $spino=Gtk2::SpinButton->new($adjo,0,0);
	$adjo->signal_connect(value_changed => sub { $opt->{opacity}=$_[0]->get_value/100; my $win=$Displayed{$key}; $win->set_opacity($opt->{opacity}) if $win;  });

	my $ontop=Gtk2::CheckButton->new(_"On top of other windows instead of below");
	$ontop->set_active($opt->{ontop});
	$ontop->signal_connect(toggled=> sub { my $on=$_[0]->get_active; $opt->{ontop}=$on; $opt->{below}=!$on;	CreateWindow($key); });

	my $adjw=Gtk2::Adjustment->new($opt->{w},1,::max(2000,$opt->{w},Gtk2::Gdk::Screen->get_default->get_width),10,50,0);
	my $adjh=Gtk2::Adjustment->new($opt->{h},1,::max(2000,$opt->{h},Gtk2::Gdk::Screen->get_default->get_height),10,50,0);
	my $spinw=Gtk2::SpinButton->new($adjw,0,0);
	my $spinh=Gtk2::SpinButton->new($adjh,0,0);
	$adjw->signal_connect(value_changed => sub { $opt->{w}=$_[0]->get_value; ResizeWindow($key);  });
	$adjh->signal_connect(value_changed => sub { $opt->{h}=$_[0]->get_value; ResizeWindow($key);  });

	my $vbox= ::Vpack(
		[ $label, '-',$remove ],
		[ Gtk2::Label->new(_"Default text color"), $textcolor],
		[ Gtk2::Label->new(_"Default text font"),  $textfont],
		[ Gtk2::Label->new(_"Centered on"),  '_',$spinx, Gtk2::Label->new('%  x'), '_',$spiny, Gtk2::Label->new('%') ],
		[ Gtk2::Label->new(_"Monitor"), $spin_mon, ],
		[ Gtk2::Label->new(_"Minimum size"), $spinw, Gtk2::Label->new('x'), $spinh ],
		[ Gtk2::Label->new(_"Opacity"),  $spino, Gtk2::Label->new('%') ],
		 $ontop);
	$OptionsBox->pack_start($vbox,::FALSE,::FALSE,2);
	$OptionsBox->show_all;
}






sub CreateWindow
{	my $key=shift;
	my $opt= $DWlist->{$key};
	return unless $opt;
	return if $opt->{dw_inactive};
	delete $opt->{dw_inactive};
	$opt->{monitor}||=0;
	my $pos= $opt->{monitor}.'@'.$opt->{x}.'%x'.$opt->{y}.'%';
	my $size= $opt->{w}.'x'.$opt->{h};
	$Displayed{$key}= Layout::Window->new($opt->{layout}, %$opt, 'pos'=>$pos, size=>$size, uniqueid=>$key, ifexist=>'replace',
						fallback=> 'NONE', nodecoration=>1, skippager=>1, skiptaskbar=>1, sticky=>1,
						typehint=>'dock',
					);
}
sub MoveWindow
{	my $key=shift;
	my $win=$Displayed{$key};
	return unless $win;
	my $opt= $DWlist->{$key};
	$win->{'pos'}= $opt->{monitor}.'@'.$opt->{x}.'%x'.$opt->{y}.'%';
	my ($x,$y)=$win->Position;
	$win->move($x,$y);
}
sub ResizeWindow
{	my $key=shift;
	my $win=$Displayed{$key};
	return unless $win;

	CreateWindow($key);
	#$win->resize($DWlist->{$key}{w},$DWlist->{$key}{h});	#better, but doesn't work well with Cover widget
}

1
