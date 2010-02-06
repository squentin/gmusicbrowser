# Copyright (C) 2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin TitleBar
name	Titlebar
title	Titlebar overlay plugin
desc	Display a special layout in or around the titlebar of the focused window
=cut

package GMB::Plugin::TitleBar;
use strict;
use warnings;
use Gnome2::Wnck;
use constant
{	OPT	=> 'PLUGIN_TITLEBAR_',
};

::SetDefaultOptions(OPT, offy=>4, offx=>24, refpoint=>'upper_left', layout=>'O_play', textcolor=>'white', textfont=>'Sans 7', set_textfont=>1);

my ($Screen,$Handle,$Popupwin,$ActiveWindow);

my %refpoints=
(	upper_left	=> _"Upper left",
	upper_right	=> _"Upper right",
	lower_left	=> _"Lower left",
	lower_right	=> _"Lower right",
);

sub Start
{	$Screen=Gnome2::Wnck::Screen->get_default;
	$Handle= $Screen->signal_connect(active_window_changed=> \&window_changed);
	init();
}
sub Stop
{	$Popupwin->close_window if $Popupwin;
	$Screen->signal_handler_disconnect($Handle);
	$ActiveWindow->signal_handler_disconnect( $ActiveWindow->{handle} ) if $ActiveWindow && $ActiveWindow->{handle};
	$ActiveWindow=$Popupwin=$Screen=$Handle=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $layout=::NewPrefCombo(OPT.'layout'=> Layout::get_layout_list('O'), cb=> \&init, text =>_"Overlay layout :",tree=>1, sizeg1=>$sg1,sizeg2=>$sg2);
	my $refpoint=::NewPrefCombo(OPT.'refpoint'=> \%refpoints, cb=> \&move, text =>_"Reference point :", sizeg1=>$sg1,sizeg2=>$sg2);
	my $offx=::NewPrefSpinButton(OPT.'offx', -999,999, cb=>\&move, step=>1, page=>5, text1=>_"x offset :", sizeg1=>$sg1);
	my $offy=::NewPrefSpinButton(OPT.'offy', -999,999, cb=>\&move, step=>1, page=>5, text1=>_"y offset :", sizeg1=>$sg1);
	my $notdialog=::NewPrefCheckButton(OPT.'notdialog',_"Don't add the overlay to dialogs", cb=>\&init);

	my $textcolor= Gtk2::ColorButton->new( Gtk2::Gdk::Color->parse($::Options{OPT.'textcolor'}) );
	$textcolor->signal_connect(color_set=>sub { $::Options{OPT.'textcolor'}=$_[0]->get_color->to_string; init(); });
	my $set_textcolor= ::NewPrefCheckButton(OPT.'set_textcolor',_"Change default text color", cb=>\&init, widget=>$textcolor, horizontal=>1);

	my $font= Gtk2::FontButton->new_with_font( $::Options{OPT.'textfont'} );
	$font->signal_connect(font_set=>sub { $::Options{OPT.'textfont'}=$_[0]->get_font_name; init(); });
	my $set_font= ::NewPrefCheckButton(OPT.'set_textfont',_"Change default text font and size", cb=>\&init, widget=>$font, horizontal=>1);

	$vbox->pack_start($_,::FALSE,::FALSE,2) for $layout,$refpoint,$offx,$offy,$set_textcolor,$set_font,$notdialog;
	return $vbox;
}

sub init
{	my @moreoptions;
	push @moreoptions, DefaultFontColor=> $::Options{OPT.'textcolor'}  if $::Options{OPT.'set_textcolor'};
	push @moreoptions, DefaultFont=>      $::Options{OPT.'textfont'}   if $::Options{OPT.'set_textfont'};
	$Popupwin=Layout::Window->new
	(	$::Options{OPT.'layout'},	fallback=>'O_play',	title=>"gmusicbrowser_titlebar_overlay",
		uniqueid=>'titlebar',		ifexist=>'replace',
		wintype=>'popup',		transparent=>1,			ontop=>1,
		@moreoptions,
	);
	window_changed($Screen);
}

sub move
{	return unless $Popupwin && $ActiveWindow;
	my ($x,$y,$w,$h) = $ActiveWindow->get_geometry;
	my (undef,undef,$pw,$ph)=$Popupwin->window->get_geometry;
	my $ref= $::Options{OPT.'refpoint'};
	my $offx=$::Options{OPT.'offx'};
	my $offy=$::Options{OPT.'offy'};
	if ($ref=~m/right/) { $x+=$w-$pw; $offx*=-1; }
	if ($ref=~m/lower/) { $y+=$h-$ph; $offy*=-1; }
	$x+=$offx;
	$y+=$offy;
	$Popupwin->move($x,$y);
	if (1)	#hide it if there is a window above
	{	for my $win (reverse $Screen->get_windows_stacked)	#go through windows from top to bottom
		{	last if $ActiveWindow==$win;			#until the active window
			next unless $win->is_visible_on_workspace($ActiveWindow->get_workspace);
			my ($x0,$y0,$w0,$h0)= $win->get_geometry;
			if ($x+$pw>$x0 && $x0+$w0>$x && $y+$ph>$y0 && $y0+$h0>$y) { $Popupwin->hide; return }
		}
	}
	$Popupwin->show;
	$Popupwin->move($x,$y); #repeat because it probably didn't move if it was hidden
}

sub window_changed
{	my $screen=shift;
	my $active=$screen->get_active_window;
	return if !$active && $ActiveWindow && $ActiveWindow->is_visible_on_workspace($screen->get_active_workspace);
	if ($ActiveWindow && $ActiveWindow->{handle})
	{	$ActiveWindow->signal_handler_disconnect( $ActiveWindow->{handle} );
	}
	$ActiveWindow=$active;
	if ($ActiveWindow)
	{	my $type= $ActiveWindow->get_window_type;
		$ActiveWindow=undef unless $type eq 'normal' || ($type eq 'dialog' && !$::Options{OPT.'notdialog'});
	}
	if ($ActiveWindow && !$ActiveWindow->is_fullscreen)
	{	$ActiveWindow->{handle}= $ActiveWindow->signal_connect(geometry_changed=> \&move);
		move();
	}
	else
	{	$Popupwin->hide;
	}
}

1
