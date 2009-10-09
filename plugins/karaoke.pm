# Copyright (C) 2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin Karaoke
name	Karaoke
title	Karaoke plugin
desc	Display synchronized lyrics of the current song
=cut

package GMB::Plugin::Karaoke;
use strict;
use warnings;
use base 'Gtk2::Label';
use constant
{	OPT	=> 'PLUGIN_Karaoke_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

::SetDefaultOptions(OPT, PathFile => "~/.lyrics/%a - %t.lrc",);

my $lyricswidget=
{	class		=> __PACKAGE__,
	font		=> 20,
	schange		=> \&SongChanged,
	group		=> 'Play',
	autoadd_type	=> 'context label lyrics',
	event		=> 'Time',
	update		=> \&TimeChanged,
};

sub Start
{	Layout::RegisterWidget(PluginKaraoke => $lyricswidget);
}
sub Stop
{	Layout::RegisterWidget(PluginKaraoke => undef);
}
sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Pattern to find .lrc files :");
	my $preview= Label::Preview->new(\&filename_preview, 'CurSong Option',undef,1);
	my $showbutton= Gtk2::Button->new(_"Show/Hide lyrics line");
	$showbutton->signal_connect(clicked=> sub { ::OpenSpecialWindow('Karaoke',1); });
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $entry,$preview,$showbutton;
	return $vbox;
}


sub new
{	my ($class,$opt)=@_;
	my $self = bless Gtk2::Label->new, $class;
	$self->modify_font(Gtk2::Pango::FontDescription->from_string($opt->{font})) if $opt->{font};
	$self->{attr}= $opt->{attr};
	$self->{after}=  $opt->{after} || $opt->{context};
	$self->{before}= $opt->{before}|| $opt->{context};
	$self->{after_attr}=  $opt->{after_attr} || $opt->{context_attr};
	$self->{before_attr}= $opt->{before_attr}|| $opt->{context_attr};
	#$self->set_line_wrap(1);
	return $self;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
	$t= $t ? ::PangoEsc(_"example : ".$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
	return '<small>'.$t.'</small>';
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && !$force && ( $ID==$self->{ID} );
	$self->{ID}=$ID;
	$self->{seconds}=undef;
	$self->{lasttime}=-1;
	$self->set_text('');

	my $file=::pathfilefromformat( $self->{ID}, $::Options{OPT.'PathFile'}, undef,1 );
	if ($file && -r $file)
	{	::IdleDo('7_lyrics'.$self,500,\&load_file,$self,$file);
	}
}

sub load_file
{	my ($self,$file)=@_;
	my $text='';
	if (open my$fh,'<',$file)
	{	local $/=undef; #slurp mode
		$text=<$fh>;
		close $fh;
		if (my $utf8=Encode::decode_utf8($text)) {$text=$utf8}
	}
	else {return}
	my $offset=0;
	my $needsort;
	my $lines= $self->{lines}=[];
	my $seconds= $self->{seconds}=[];
	for my $l (split /\012|\015|\015\012/,$text)
	{	if ($l=~m/^\[offset:([+-]?\d+)\]/) { $offset=$1/1000 } #Overall timestamp adjustment in milliseconds
		else	#look for format : [mm:ss.xx]lyrics line
		{	my $i=0;	#loop for cases : [mm:ss.xx][mm:ss.xx][mm:ss.xx]repeated line
			while ($l=~s/^\[(\d?\d):(\d\d)(?:\.(\d\d)\d?)?\]//) { push @$seconds, $offset+$1*60+$2+($3||0)/100; $i++ }
			push @$lines, ($l)x$i;
			$needsort=1 if $i>1;
		}
	}
	if ($needsort) #for repeated lines, as they are not properly ordered
	{	@$lines=map $lines->[$_], sort { $seconds->[$a] <=> $seconds->[$b] } 0..$#$lines;
		@$seconds=sort { $a<=>$b } @$seconds;
	}
	$self->TimeChanged;
}

sub TimeChanged
{	my $self=$_[0];
	return unless $self->{seconds};
	my $time=$::PlayTime;
	if (!defined $time) { $self->set_text(''); return }
	my $seconds= $self->{seconds};
	my $i=0;
	$i++ while $i<@$seconds && $seconds->[$i]<$time;
	$i--;
	return if $self->{lasttime}==$i;	#no need to re-display the line
	$self->{lasttime}=$i;
	my $lines= $self->{lines};
	my $line= $i>=0 ? $lines->[$i] : '';
	if ($line=~m/<\d?\d:\d\d(?:\.\d\d\d?)?>/)	#Enhanced LRC format
	{	# $line : <mm:ss.xx> word1 <mm:ss.xx> word2 <mm:ss.xx> ... lastword <mm:ss.xx>
		my @words= (0,0,0, split /<(\d?\d):(\d\d)(?:\.(\d\d)\d?)?>/, $line,-1);
		$self->{lasttime}=-1;
		$line='';
		my $prev='';
		my $found;
		while (@words>3)
		{	my ($m,$s,$c,$word)=splice @words,0,4;
			if ( !$found && $time < $m*60+$s+($c||0)/100 ) {$prev="<b>$prev</b>"; $found=1}
			$line.=$prev;
			$prev= ::PangoEsc($word);
		}
		$line.=$prev;
	}
	else { $line=::PangoEsc($line); }
	$line= "<span $self->{attr}>$line</span>" if $self->{attr};
	if (my $n=$self->{before})
	{	my $text=join "\n", map {$_>0 ? $lines->[$_] : ''}  $i-$n .. $i-1;
		$text=~s/\s*<\d?\d:\d\d(?:\.\d\d\d?)?>\s*/ /g;
		$text=::PangoEsc($text);
		$text= "<span $self->{before_attr}>$text</span>" if $self->{before_attr};
		$line= $text."\n".$line;
	}
	if (my $n=$self->{after})
	{	my $text =join "\n", map {$_<@$lines ? $lines->[$_] : ''}  $i+1 .. $i+$n;
		$text=~s/\s*<\d?\d:\d\d(?:\.\d\d\d?)?>\s*/ /g;
		$text=::PangoEsc($text);
		$text= "<span $self->{after_attr}>$text</span>" if $self->{after_attr};
		$line.= "\n".$text;
	}
	$self->set_markup($line);
}

1
