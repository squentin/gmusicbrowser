# Copyright (C) 2005-2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

BEGIN
{ require 'oggheader.pm';
  require 'mp3header.pm';
  require 'flacheader.pm';
  require 'mpcheader.pm';
  require 'apeheader.pm';
  require 'wvheader.pm';
  require 'm4aheader.pm';
}
use strict;
use warnings;
use utf8;

package FileTag;

our %FORMATS;

INIT
{
 %FORMATS=	    # module		format string			tags to look for (order is important)
 (	mp3	=> ['Tag::MP3',		'mp3 l{layer}v{versionid}',	'ID3v2 APE lyrics3v2 ID3v1',],
	oga	=> ['Tag::OGG',		'vorbis v{version}',		'vorbis',],
	flac	=> ['Tag::Flac',	'flac',				'vorbis',],
	mpc	=> ['Tag::MPC',		'mpc v{version}',		'APE ID3v2 lyrics3v2 ID3v1',],
	ape	=> ['Tag::APEfile',	'ape v{version}',		'APE ID3v2 lyrics3v2 ID3v1',],
	wv	=> ['Tag::WVfile',	'wv v{version}',		'APE ID3v1',],
	m4a	=> ['Tag::M4A',		'mp4 {traktype}',		'ilst',],
);
 $FORMATS{$_}=$FORMATS{ $::Alias_ext{$_} } for keys %::Alias_ext;
}

sub Read
{	my ($file,$findlength,$fieldlist)=@_;
	return unless $file=~m/\.([^.]+)$/;
	my $format=$FORMATS{lc $1};
	return unless $format;
	my ($package,$formatstring,$plist)=@$format;
	my $filetag= eval { $package->new($file,$findlength); }; #filelength==1 -> may return estimated length (mp3 only)
	unless ($filetag) { warn $@ if $@; warn "can't read tags for $file\n"; return }

	::setlocale(::LC_NUMERIC, 'C');
	my @taglist;
	my %values;	#results will be put in %values
	if (my $info=$filetag->{info})	#audio properties
	{	if ($findlength!=1 && $info->{estimated}) { delete $info->{$_} for qw/seconds bitrate estimated/; }
		$formatstring=~s/{(\w+)}/$info->{$1}/g;
		$values{filetype}=$formatstring;
		for my $f (grep $Songs::Def{$_}{audioinfo}, @Songs::Fields)
		{	for my $key (split /\|/,$Songs::Def{$f}{audioinfo})
			{	my $v=$info->{$key};
				if (defined $v) {$values{$f}=$v; last}
			}
		}
	}
	for my $tag (split / /,$plist)
	{	if ($tag eq 'vorbis' || $tag eq 'ilst')
		{	push @taglist, $tag => $filetag;
		}
		elsif ($filetag->{$tag})
		{	push @taglist, lc($tag) => $filetag->{$tag};
			if ($tag eq 'ID3v2' && $filetag->{ID3v2s})
			{	push @taglist, id3v2 => $_ for @{ $filetag->{ID3v2s} };
			}
		}
	}
	my @fields= $fieldlist ? split /\s+/, $fieldlist :
				 grep $Songs::Def{$_}{flags}=~m/r/, @Songs::Fields;
	for my $field (@fields)
	{	for (my $i=0; $i<$#taglist; $i+=2)
		{	my $id=$taglist[$i]; #$id is type of tag : id3v1 id3v2 ape vorbis lyrics3 ilst
			my $tag=$taglist[$i+1];
			my $value;
			my $def=$Songs::Def{$field};
			if (defined(my $keys=$def->{$id})) #generic cases
			{	my $joinwith= $def->{join_with};
				my $split=$def->{read_split};
				my $join= $def->{flags}=~m/l/ || defined $joinwith;
				for my $key (split /\s*[|&]\s*/,$keys)
				{	if ($key=~m#%i#)
					{	my $userid= $def->{userid};
						next unless defined $userid && length $userid;
						$key=~s#%i#$userid#;
					}
					my $func='postread';
					$func.=":$1" if $key=~s/^(\w+)\(\s*([^)]+?)\s*\)$/$2/; #for tag-specific postread function
					my $fpms_id; $fpms_id=$1 if $key=~m/FMPS_/ && $key=~s/::(.+)$//;
					my @v= $tag->get_values($key);
					next unless @v;
					if (defined $fpms_id) { @v= (FMPS_hash_read($v[0],$fpms_id)); next unless @v; }
					if (my $sub= $def->{$func}||$def->{postread})
					{	@v= map $sub->($_,$id,$key,$field), @v;
						next unless @v;
					}
					if ($join)	{ push @$value, @v; }
					else		{ $value= $v[0]; last; }
				}
				next unless defined $value;
				if (defined $joinwith)	{ $value= join $joinwith,@$value; }
				elsif (defined $split)	{ $value= [map split($split,$_), @$value]; }
			}
			elsif (my $sub=$def->{"$id:read"}) #special cases with custom function
			{	$values{$field}= $sub->($tag);
				last;
			}
			if (defined $value) { $values{$field}=$value; last }
		}
	}
	::setlocale(::LC_NUMERIC, '');

	return \%values;
}

sub Write
{	my ($ID,$modif,$errorsub)=@_; warn "FileTag::Write($ID,[@$modif],$errorsub)\n" if $::debug;
	my $file= Songs::GetFullFilename($ID);

	my ($format)= $file=~m/\.([^.]*)$/;
	return unless $format and $format=$FileTag::FORMATS{lc$format};
	::setlocale(::LC_NUMERIC, 'C');
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return }

	my ($maintag)=split / /,$format->[2],2;
	if (($maintag eq 'ID3v2' && !$::Options{TAG_id3v1_noautocreate}) || $tag->{ID3v1})
	{	my $id3v1 = $tag->{ID3v1} ||= $tag->new_ID3v1;
		my $i=0;
		while ($i<$#$modif)
		{	my $field=$modif->[$i++];
			my $val=  $modif->[$i++];
			my $i=$Songs::Def{$field}{id3v1};
			next unless defined $i;
			$id3v1->[$i]= $val;	# for genres $val is a arrayref
		}
	}

	my @taglist;
	if ($maintag eq 'ID3v2' || $tag->{ID3v2})
	{	my $id3v2 = $tag->{ID3v2} || $tag->new_ID3v2;
		my ($ver)= $id3v2->{version}=~m/^(\d+)/;
		push @taglist, ["id3v2.$ver",'id3v2'], $id3v2;
	}
	if ($maintag eq 'vorbis' || $maintag eq 'ilst')
	{	push @taglist, $maintag,$tag;
	}
	if ($maintag eq 'APE' || $tag->{APE})
	{	my $ape = $tag->{APE} || $tag->new_APE;
		push @taglist, 'ape', $ape;
	}
	while (@taglist)
	{	my ($id,$tag)=splice @taglist,0,2;
		my @ids= (ref $id ? @$id : ($id));
		unshift @ids, map "$_:write", @ids;
		my $i=0;
		while ($i<$#$modif)
		{	my $field=$modif->[$i++];
			my $vals= $modif->[$i++];
			$vals=[$vals] unless ref $vals;
			my $def=$Songs::Def{$field};
			my ($keys)= grep defined, map $def->{$_}, @ids;
			next unless defined $keys;
			if (ref $keys)	 # custom ":write" functions
			{	my @todo=$keys->($vals);
				while (@todo)
				{	my ($key,$val)=splice @todo,0,2;
					if (defined $val)	{ $tag->insert($key,$val) }
					else			{ $tag->remove_all($key)  }
				}
				next;
			}

			my $userid= $def->{userid};
			my ($wkey,@keys)= split /\s*\|\s*/,$keys;
			my $toremove= @keys;			#these keys will be removed
			push @keys, split /\s*&\s*/, $wkey;	#these keys will be updated (first one and ones separated by &)
			for my $key (@keys)
			{	if ($key=~m/%i/) { next unless defined $userid && length $userid; $key=~s#%i#$userid#g }
				my $func='prewrite';
				$func.=":$1" if $key=~s/^(\w+)\(\s*([^)]+?)\s*\)$/$2/; #for tag-specific prewrite function  "function( TAG )"
				my $sub= $def->{$func} || $def->{'prewrite'};
				my @v= @$vals;
				if ($toremove-- >0) { @v=(); } #remove "deprecated" keys
				elsif ($sub)
				{	@v= map $sub->($_,$ids[-1],$key,$field), @v;
				}
				if ($key=~m/FMPS_/ && $key=~s/::(.+)$//)	# FMPS list field such as FMPS_Rating_User
				{	my $v= FMPS_hash_write( $tag, $key, $1, $v[0] );
					@v= $v eq '' ? () : ($v);
				}
				$tag->remove_all($key);
				$tag->insert($key,$_) for reverse grep defined, @v;
			}
		}
	}

	$tag->{errorsub}=$errorsub;
	$tag->write_file unless $::CmdLine{ro}  || $::CmdLine{rotags};
	::setlocale(::LC_NUMERIC, '');
	return 1;
}

sub FMPS_string_to_hash
{	my $vlist=shift;
	my %h;
	for my $pair (split /;;/, $vlist)
	{	my ($key,$value)= split /::/,$pair,2;
		s#\\([;:\\])#$1#g for $key,$value;
		$h{$key}=$value;
	}
	return \%h;
}
sub FMPS_hash_to_string
{	my $h=shift;
	my @list;
	for my $key (sort keys %$h)
	{	my $v=$h->{$key};
		s#([;:\\])#\\$1#g for $key,$v;
		push @list, $key.'::'.$v;
	}
	return join ';;',@list;
}
sub FMPS_hash_read
{	my ($vlist,$id)=@_;
	return unless $vlist;
	my $h= FMPS_string_to_hash($vlist);
	my $v=$h->{$id};
	return defined $v ? ($v) : ();
}
sub FMPS_hash_write
{	my ($tag,$key,$id,$value)=@_;
	my ($vlist)= $tag->get_values($key);
	my $h=  FMPS_string_to_hash( $vlist||'' );
	if (defined $value)	{ $h->{$id}=$value; }
	else			{ delete $h->{$id}; }
	return FMPS_hash_to_string($h);
}

sub PixFromMusicFile
{	my ($file,$nb,$quiet)=@_;
	my ($h)=Read($file,0,'embedded_pictures');
	return unless $h;
	my $pix= $h->{embedded_pictures};
	unless ($pix && @$pix)	{warn "no picture found in $file\n" unless $quiet;return;}
	#FIXME filter out mimetype of "-->" (link) ?

	return ref $pix->[0] ? (map $pix->[$_][3],0..$#$pix) : @$pix if wantarray;

	if (!defined $nb) { $nb=0 }
	elsif ($nb=~m/\D/)
	{	if (ref $pix->[0]) #for APIC structures
		{	my $apic_id= $Songs::Def{$nb} && $Songs::Def{$nb}{apic_id};
			if ($apic_id)
			{	($nb)= grep $pix->[$_][1]==$apic_id ,0..$#$pix;
				return unless defined $nb;
			}
			return unless defined $nb;
		}
		elsif ($nb eq 'album') { $nb=0 }
		else { return }
	}
	elsif ($nb>$#$pix) { $nb=0 }

	return ref $pix->[0] ? $pix->[$nb][3] : $pix->[$nb];
}

sub GetLyrics
{	my $ID=shift;
	my $file= Songs::GetFullFilename($ID);
	my ($h)=Read($file,0,'embedded_lyrics');
	return unless $h;
	my $lyrics= $h->{embedded_lyrics};
	warn "no lyrics found in $file\n" unless $lyrics;
	return $lyrics;
}

sub WriteLyrics
{	my ($ID,$lyrics)=@_;
	Write($ID, [embedded_lyrics=>$lyrics], \&::Retry_Dialog);
}

package MassTag;
use Gtk2;
use constant
{	TRUE  => 1, FALSE => 0,
};

our @FORMATS;
our @FORMATS_user;
our @Tools;
INIT
{
 @Tools=
 (	{ label=> _"Capitalize",		for_all => sub { ucfirst lc $_[0]; }, },
	{ label=>_"Capitalize each word",	for_all => sub { join ' ',map ucfirst lc, split / /,$_[0]; }, },
 );
 @FORMATS=
 (	['%a - %l - %n - %t',	qr/(.+) - (.+) - (\d+) - (.+)$/],
	['%a_-_%l_-_%n_-_%t',	qr/(.+)_-_(.+)_-_(\d+)_-_(.+)$/],
	['%n - %a - %l - %t',	qr/(\d+) - (.+) - (.+) - (.+)$/],
	['(%a) - %l - %n - %t',	qr/\((.+)\) - (.+) - (\d+) - (.+)$/],
	['%a - %l - %n-%t',	qr/(.+) - (.+) - (\d+)-(.+)$/],
	['%a-%l-%n-%t',		qr/(.+)-(.+)-(\d+)-(.+)$/],
	['%a - %l-%n. %t',	qr/(.+) - (.+)-(\d+). (.+)$/],
	['%l - %n - %t',	qr/([^-]+) - (\d+) - (.+)$/],
	['%a - %n - %t',	qr/([^-]+) - (\d+) - (.+)$/],
	['%n - %l - %t',	qr/(\d+) - (.+) - (.+)$/],
	['%n - %a - %t',	qr/(\d+) - (.+) - (.+)$/],
	['(%n) %a - %t',	qr/\((\d+)\) (.+) - (.+)$/],
	['%n-%a-%t',		qr/(\d+)-(.+)-(.+)$/],
	['%n %a %t',		qr/(\d+) (.+) (.+)$/],
	['%a - %n %t',		qr/(.+) - (\d+) ([^-].+)$/],
	['%l - %n %t',		qr/(.+) - (\d+) ([^-].+)$/],
	['%n - %t',		qr/(\d+) - (.+)$/],
	['%d%n - %t',		qr/(\d)(\d\d) - (.+)$/],
	['%n_-_%t',		qr/(\d+)_-_(.+)$/],
	['(%n) %t',		qr/\((\d+)\) (.+)$/],
	['%n_%t',		qr/(\d+)_(.+)$/],
	['%n-%t',		qr/(\d+)-(.+)$/],
	['%d%n-%t',		qr/(\d)(\d\d)-(.+)$/],
	['%d-%n-%t',		qr/(\d)-(\d+)-(.+)$/],
	['cd%d-%n-%t',		qr/cd(\d+)-(\d+)-(.+)$/i],
	['Disc %d - %n - %t',	qr/Disc (\d+) - (\d+) - (.+)$/i],
	['%n %t - %a - %l',	qr/(\d+) (.+) - (.+) - (.+)$/],
	['%n %t - %l - %a',	qr/(\d+) (.+) - (.+) - (.+)$/],
	['%n. %a - %t',		qr/(\d+)\. (.+) - (.+)$/],
	['%n. %t',		qr/(\d+)\. (.+)$/],
	['%n %t',		qr/(\d+) ([^-].+)$/],
	['Track%n',		qr/[Tt]rack ?-? ?(\d+)/],
	['%n',			qr/^(\d+)$/],
	['%a - %t',		qr/(\D.+) - (.+)$/],
	['%n - %a,%t',		qr/(\d+) - (.+?),(.+)$/],
	#['TEST : %a %n %t',qr/(.+)(?: *|_)\W(?: *|_)(\d+)(?: *|_)\W(?: *|_)(.+)/],
	#['TEST : %n %t',qr/(\d+)(?: *|_)\W(?: *|_)(.+)/],
 );
# my %swap=(a => 'l', l => 'a',);
# my @tmp;
# for my $ref (@FORMATS)
# {	my ($f,$re)=@$ref;
#	push @tmp,$ref;
#	if ($f=~s/%([al])/%$swap{$1}/g) { push @tmp,[$f,$re] }
# }
# @FORMATS=@tmp;
}

use base 'Gtk2::VBox';
sub new
{	my ($class,@IDs) = @_;
	@IDs= ::uniq(@IDs);
	my $self = bless Gtk2::VBox->new, $class;

	my $table=Gtk2::Table->new (6, 2, FALSE);
	my $row1=my $row2=0;
	my %widgets;
	$self->{widgets}=\%widgets;
	$self->{pf_widgets}={};
	$self->{IDs}=\@IDs;

	# folder name at the top
	{	my $folders= Songs::UniqList('path',\@IDs);
		my $folder=$folders->[0];
		my $displaysub= Songs::DisplayFromHash_sub('path');
		if (@$folders>1)
		{	my $common= ::find_common_parent_folder(@$folders);
			$folder=_"different folders";
			$folder.= "\n". ::__x(_"(common parent folder : {common})",common=> $displaysub->($common) ) if length($common)>5;
		}
		my $text= ::__("%d file in {folder}","%d files in {folder}",scalar@IDs);
		$text= ::__x($text, folder => ::MarkupFormat('<small>%s</small>', $displaysub->($folder) ) );
		my $labelfile = Gtk2::Label->new;
		$labelfile->set_markup($text);
		$labelfile->set_selectable(TRUE);
		$labelfile->set_line_wrap(TRUE);
		$self->pack_start($labelfile, FALSE, TRUE, 2);
	}

	for my $field ( Songs::EditFields('many') )
	{	my $check=Gtk2::CheckButton->new(Songs::FieldName($field));
		my $widget=Songs::EditWidget($field,'many',\@IDs);
		next unless $widget;
		$widgets{$field}=$widget;
		$check->{widget}=$widget;
		$widget->set_sensitive(FALSE);

		$check->signal_connect( toggled => sub { my $check=shift; $check->{widget}->set_sensitive( $check->get_active ); });
		my ($row,$col)= $widget->{noexpand} ? ($row2++,2) : ($row1++,0);
		$table->attach($check,$col++,$col,$row,$row+1,'fill','shrink',3,1);
		$table->attach($widget,$col++,$col,$row,$row+1,['fill','expand'],'shrink',3,1);
	}

	$self->pack_start($table, FALSE, TRUE, 2);

	# do not add per-file part if LOTS of songs, building the GUI would be too long anyway
	$self->add_per_file_part unless @IDs>1000;
	return $self;
}

# for edition of file-specific tags (track title ...)
sub add_per_file_part
{	my $self=shift;
	my $IDs=$self->{IDs};
	Songs::SortList($IDs,'path album:i disc track file');
	my $perfile_table=Gtk2::Table->new( scalar(@$IDs), 10, FALSE);
	$self->{perfile_table}=$perfile_table;
	my $row=0;
	$self->add_column('track');
	$self->add_column('title');

	my $lastcol=1;	#for the filename column
	my $BSelFields=Gtk2::Button->new(_"Select fields");
	{	my $menu=Gtk2::Menu->new;
		my $menu_cb=sub {$self->add_column($_[1])};
		for my $f ( Songs::EditFields('per_id') )
		{	my $item=Gtk2::CheckMenuItem->new_with_label( Songs::FieldName($f) );
			$item->set_active(1) if $self->{'pfcheck_'.$f};
			$item->signal_connect(activate => $menu_cb,$f);
			$menu->append($item);
			$lastcol++;
		}
		#$menu->append(Gtk2::SeparatorMenuItem->new);
		#my $item=Gtk2::CheckMenuItem->new(_"Select files");
		#$item->signal_connect(activate => sub { $self->add_selectfile_column });
		#$menu->append($item);
		$menu->show_all;
		$BSelFields->signal_connect( button_press_event => sub
			{	my $event=$_[1];
				$menu->popup(undef,undef,\&::menupos,undef,$event->button, $event->time);
			});
		#$self->pack_start($menubar, FALSE, FALSE, 2);
		#$perfile_table->attach($menubar,7,8,0,1,'fill','shrink',1,1);
	}

	#add filename column
	$perfile_table->attach( Gtk2::Label->new(Songs::FieldName('file')) ,$lastcol,$lastcol+1,$row,$row+1,'fill','shrink',1,1);
	for my $ID (@$IDs)
	{	$row++;
		my $label=Gtk2::Label->new( Songs::Display($ID,'file') );
		$label->set_selectable(TRUE);
		$label->set_alignment(0,0.5);	#left-aligned
		$perfile_table->attach($label,$lastcol,$lastcol+1,$row,$row+1,'fill','shrink',1,1); #filename
	}

	my $Btools=Gtk2::Button->new(_"tools");
	{	my $menu=Gtk2::Menu->new;
		my $menu_cb=sub {$self->tool($_[1])};
		for my $ref (@Tools)	#currently only able to transform all entrys with the for_all function
		{	my $item=Gtk2::MenuItem->new($ref->{label});
			$item->signal_connect(activate => $menu_cb,$ref->{for_all});
			$menu->append($item) if $ref->{for_all};
		}
		$menu->show_all;
		$Btools->signal_connect( button_press_event => sub
			{	my $event=$_[1];
				$menu->popup(undef,undef,\&::menupos,undef,$event->button, $event->time);
			});
	}

	my $BClear=::NewIconButton('gtk-clear',undef,
		sub { my $self=::find_ancestor($_[0],__PACKAGE__); $self->tool(sub {''}) },
		undef,_"Clear selected fields");

	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic', 'automatic');
	$sw->add_with_viewport($perfile_table);
	$self->pack_start($sw, TRUE, TRUE, 4);

	my $store= Gtk2::ListStore->new('Glib::String','Glib::Scalar');
	$self->{autofill_combo}= my $Bautofill=Gtk2::ComboBox->new($store);
	my $renderer=Gtk2::CellRendererText->new;
	$Bautofill->pack_start($renderer,::TRUE);
	$Bautofill->add_attribute($renderer, markup => 0);
	$self->autofill_check;
	$Bautofill->signal_connect(changed => \&autofill_cb);
	::Watch( $self, AutofillFormats => \&autofill_check);

	my $checkOBlank=Gtk2::CheckButton->new(_"Auto fill only blank fields");
	$self->{AFOBlank}=$checkOBlank;
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_start($_, FALSE, FALSE, 0) for $BSelFields,Gtk2::VSeparator->new,$Bautofill,$BClear,$checkOBlank,$Btools,
	$self->pack_start($hbox, FALSE, FALSE, 4);
}

sub add_column
{	my ($self,$field)=@_;
	if ($self->{'pfcheck_'.$field})	#if already created -> toggle show/hide
	{	my @w=( $self->{'pfcheck_'.$field}, @{ $self->{pf_widgets}{$field} } );
		if ($w[0]->visible)	{ $_->hide for @w; }
		else			{ $_->show for @w; }
		return;
	}
	my $table=$self->{perfile_table};
	my $col=++$table->{col};
	my $row=0;
	my $check=Gtk2::CheckButton->new( Songs::FieldName($field) );
	my @entries;
	$self->{'pfcheck_'.$field}=$check;
	$self->{pf_widgets}{$field}=\@entries;
	for my $ID ( @{$self->{IDs}} )
	{	$row++;
		my $widget=Songs::EditWidget($field,'per_id',$ID);
		next unless $widget;
		$widget->set_sensitive(FALSE);
		$widget->signal_connect(focus_in_event=> \&scroll_to_entry);
		my $p= $widget->{noexpand} ? 'fill' : ['fill','expand'];
		$table->attach($widget,$col,$col+1,$row,$row+1,$p,'shrink',1,1);
		$widget->show_all;
		push @entries,$widget;
	}
	$check->signal_connect( toggled => sub
		{  my $active=$_[0]->get_active;
		   $_->set_sensitive($active) for @entries;
		});

	# add auto-increment button to track column
	if ($field eq 'track' && 1)	#good idea ? make entries a bit large :(
	{	#$_->set_alignment(1) for @entries;
		my $increment=sub
		 {	my $i=1;
			for my $e (@entries)
			{	my $here=$e->get_text;
				if ($here && $here=~m/^\d+$/) { $i=$here; } else { $e->set_text($i) }
				$i++;
			}
		 };
		my $button=::NewIconButton('gtk-go-down',undef,$increment,'none',_"Auto-increment track numbers");
		$button->set_border_width(0);
		$button->set_size_request();
		$check->signal_connect( toggled => sub { $button->set_sensitive($_[0]->get_active) });
		$button->set_sensitive(FALSE);
		my $hbox=Gtk2::HBox->new(0,0);
		$hbox->pack_start($_,0,0,0) for $check,$button;
		$check=$hbox;
		#$check= ::Hpack($check,$button);
	}
	$check->show_all;
	$table->attach($check,$col,$col+1,0,1,'fill','shrink',1,1);
}
sub add_selectfile_column
{	my $self=$_[0];
	if (my $l=$self->{'filetoggles'})	#if already created -> toggle show/hide
	{	if ($l->[0]->visible)	{ $_->hide for @$l; }
		else			{ $_->show for @$l; }
		return;
	}
	my @toggles;
	$self->{'filetoggles'}=\@toggles;
	my $table=$self->{perfile_table};
	my $row=0; my $col=0; my $i=0;
	for my $ID ( @{$self->{IDs}} )
	{	$row++;
		my $check=Gtk2::CheckButton->new;
		$check->set_active(1);
		$check->signal_connect( toggled => sub { my ($check,$i)=@_; my $self=::find_ancestor($check,__PACKAGE__); my $active=$check->get_active; $self->{pf_widgets}{$_}[$i]->set_sensitive($active) for keys %{ $self->{pf_widgets} } },$i);
		#$widget->signal_connect(focus_in_event=> \&scroll_to_entry);
		$table->attach($check,$col,$col+1,$row,$row+1,'fill','shrink',1,1);
		$check->show_all;
		push @toggles,$check;
		$i++;
	}
}

sub scroll_to_entry
{	my $ent=$_[0];
	if (my $sw=::find_ancestor($ent,'Gtk2::Viewport'))
	{	my ($x,$y,$w,$h)=$ent->window->get_geometry;
		$sw->get_hadjustment->clamp_page($x,$x+$w);
		$sw->get_vadjustment->clamp_page($y,$y+$h);
	};
	0;
}

sub autofill_check
{	my $self=shift;
	my $combo=$self->{autofill_combo};
	my $store=$combo->get_model;
	$store->clear;
	$store->set( $store->append, 0, ::PangoEsc(_"Auto fill based on filenames ..."));
	my @files= map ::filename_to_utf8displayname($_), Songs::Map('barefilename',$self->{IDs});
	autofill_user_formats();
	for my $ref (@FORMATS_user,@FORMATS)
	{	my ($format,$re)=@$ref;
		next if @files/2 > (grep m/$re/, @files); # ignore patterns that match less than half of the filenames
		my $formatname= '<b>'.::PangoEsc($format).'</b>';
		$formatname= GMB::Edit::Autofill_formats::make_format_name($formatname,"</b><i>%s</i><b>");
		$store->set($store->append, 0,$formatname, 1, $ref);
	}
	$store->set( $store->append, 0, ::PangoEsc(_"Edit auto-fill formats ..."), 1, \&GMB::Edit::Autofill_formats::new);
	$combo->set_active(0);
}

sub autofill_user_formats
{	my $h= $::Options{filename2tags_formats};
	return if !$h || @FORMATS_user;
	for my $format (sort keys %$h)
	{	my $re= $h->{$format};
		if (!defined $re)
		{	$re= GMB::Edit::Autofill_formats::make_default_re($format);
		}
		my $qr=eval { qr/$re/i; };
		if ($@) { warn "Error compiling regular expression for '$format' : $re\n$@"; next}
		push @FORMATS_user, [$format,$qr];
	}
}

sub autofill_cb
{	my $combo=shift;
	my $self=::find_ancestor($combo,__PACKAGE__);
	my $iter=$combo->get_active_iter;
	return unless $iter;
	my $ref=$combo->get_model->get($iter,1);
	return unless $ref;
	if (ref $ref eq 'CODE') { $ref->($self); return; }	# for edition of filename formats
	my ($format,$pattern)=@$ref;
	my @fields= GMB::Edit::Autofill_formats::find_fields($format);
	$_ eq 'album_artist' and $_='album_artist_raw' for @fields;	#FIXME find a more generic way to do that
	my $OBlank=$self->{AFOBlank}->get_active;
	my @vals;
	for my $ID (@{$self->{IDs}})
	{	my $file= Songs::Display($ID,'barefilename');
		my @v=($file=~m/$pattern/);
		s/_/ /g, s/^\s+//, s/\s+$// for @v;
		@v=('')x scalar(@fields) unless @v;
		my $n=0;
		push @{$vals[$n++]},$_ for @v;
	}
	for my $f (@fields)
	{	my $varray=shift @vals;
		my %h; $h{$_}=undef for @$varray; delete $h{''};
		if ( (keys %h)==1 )
		{	my $entry=$self->{widgets}{$f};
			if ($entry && $entry->is_sensitive)
			{	next if $OBlank && !($entry->can('is_blank') ? $entry->is_blank : $entry->get_text eq '');
				$entry->set_text(keys %h);
				next
			}
		}
		my $entries= $self->{pf_widgets}{$f};
		next unless $entries;
		for my $e (@$entries)
		{	my $v=shift @$varray;
			next if $OBlank && !($e->can('is_blank') ? $e->is_blank : $e->get_text eq '');
			$e->set_text($v) if $e->is_sensitive && $v ne '';
		}
	}
}

sub tool
{	my ($self,$sub)=@_;
	#my $OBlank=$self->{AFOBlank}->get_active;
	#$OBlank=0 if $ignoreOB;
	my $IDs=$self->{IDs};
	for my $wdgt ( values %{$self->{widgets}}, map @$_, values %{$self->{pf_widgets}} )
	{	next unless $wdgt->is_sensitive && $wdgt->can('tool');
		$wdgt->tool($sub);
	}
	#for my $entries (values %{$self->{pf_widgets}})
	#{	next unless $entries->[0]->is_sensitive && $entries->[0]->can('tool');
	#	for my $e (@$entries)
	#	{	$wdgt->tool($sub);
	#	}
	#}
}

sub save
{	my ($self,$finishsub)=@_;
	my $IDs=$self->{IDs};
	my (%default,@modif);
	while ( my ($f,$wdgt)=each %{$self->{widgets}} )
	{	next unless $wdgt->is_sensitive;
		if ($wdgt->can('return_setunset'))
		{	my ($set,$unset)=$wdgt->return_setunset;
			push @modif,"+$f",$set if @$set;
			push @modif,"-$f",$unset if @$unset;
		}
		else
		{	my $v=$wdgt->get_text;
			$default{$f}=$v;
			$f='@'.$f if ref $v;
			push @modif, $f,$v;
		}
	}
	while ( my ($f,$wdgt)=each %{$self->{pf_widgets}} )
	{	next unless $wdgt->[0]->is_sensitive;
		my @vals;
		for my $ID (@$IDs)
		{	my $v=(shift @$wdgt)->get_text;
			$v=$default{$f} if $v eq '' && exists $default{$f};
			push @vals,$v;
		}
		push @modif, '@'.$f,\@vals;
	}
	unless (@modif) { $finishsub->(); return}

	$self->set_sensitive(FALSE);
	my $progressbar = Gtk2::ProgressBar->new;
	$self->pack_start($progressbar, FALSE, TRUE, 0);
	$progressbar->show_all;
	Songs::Set($IDs,\@modif, progress=>$progressbar, callback_finish=>$finishsub, window=> $self->get_toplevel);
}

package GMB::Edit::Autofill_formats;
use base 'Gtk2::Dialog';
our $Instance;

sub new
{	my $ID= $_[0]{IDs}[0];
	if ($Instance) { $Instance->present; $Instance->{ID}=$ID; $Instance->preview_update; return };
	my $self = Gtk2::Dialog->new ("Custom auto-fill filename formats", undef, [],  'gtk-close' => 'none');
	$Instance=bless $self,__PACKAGE__;
	::SetWSize($self,'AutofillFormats');
	$self->set_border_width(4);
	$self->{ID}=$ID;
	$self->{store}=my $store= Gtk2::ListStore->new('Glib::String','Glib::String');
	$self->{treeview}=my $treeview=Gtk2::TreeView->new($store);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes(_"Custom formats", Gtk2::CellRendererText->new, text => 0 ));
	#$treeview->set_headers_visible(::FALSE);
	$treeview->signal_connect(cursor_changed=> \&cursor_changed_cb);

	my $label_format=Gtk2::Label->new(_"Filename format :");
	my $label_re=    Gtk2::Label->new(_"Regular expression :");
	$self->{entry_format}=	my $entry_format=Gtk2::Entry->new;
	$self->{entry_re}=	my $entry_re=	Gtk2::Entry->new;
	$self->{check_re}=	my $check_re=	Gtk2::CheckButton->new(_"Use default regular expression");
	$self->{error}=		my $error=	Gtk2::Label->new;
	$self->{preview}=	my $preview=	Gtk2::Label->new;
	$self->{remove_button}=	my $button_del= ::NewIconButton('gtk-remove',_"Remove");
	$self->{add_button}=	my $button_add= ::NewIconButton('gtk-save',_"Save");
	my $button_new= ::NewIconButton('gtk-new', _"New");
	$button_del->signal_connect(clicked=>\&button_cb,'remove');
	$button_add->signal_connect(clicked=>\&button_cb,'save');
	$button_new->signal_connect(clicked=>\&button_cb,'new');
	$preview->set_alignment(0,.5);
	my $sg=Gtk2::SizeGroup->new('horizontal');
	$sg->add_widget($_) for $label_format,$label_re;
	my $bbox= Gtk2::HButtonBox->new;
	$bbox->add($_) for $button_del, $button_add, $button_new;
	my $table= ::MakeReplaceTable('taAlCyndgL');	#AutoFillFields
	my $hbox= ::Hpack($treeview,'_',[[$label_format,'_',$entry_format],$table,$check_re,[$label_re,'_',$entry_re],$error,$preview,'-',$bbox]);
	$self->vbox->add($hbox);

	::set_drag($preview, dest => [::DRAG_ID,\&song_dropped]);
	$entry_format->signal_connect(changed=> \&entry_changed);
	$entry_re->signal_connect(changed=> \&preview_update);
	$check_re->signal_connect(toggled=> sub { $entry_re->set_sensitive(!$_[0]->get_active); entry_changed($_[0]); });
	$check_re->set_active(1);
	$entry_re->set_sensitive(0);
	$self->entry_changed;
	$self->fill_store;
	$self->show_all;
	$self->signal_connect( response => sub { $_[0]->destroy; $Instance=undef; });
}

sub song_dropped
{	my ($preview,$type,$ID)=@_;
	my $self= ::find_ancestor($preview,__PACKAGE__);
	$self->{ID}=$ID;
	$self->preview_update;
}

sub entry_changed
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	my $text= $self->{entry_format}->get_text;
	my $match= exists $::Options{filename2tags_formats}{$text};
	$self->{remove_button}->set_sensitive($match);
	$self->{busy}=1;
	my $selection= $self->{treeview}->get_selection;
	$selection->unselect_all;
	if ($match)
	{	my $store=$self->{store};
		my $iter=$store->get_iter_first;
		while ($iter)
		{	if ($store->get($iter,1) eq $text)
			{	$selection->select_iter($iter);
				last;
			}
			$iter=$store->iter_next($iter);
		}
	}
	$self->{add_button}->set_sensitive( length $text );
	if ($self->{check_re}->get_active)
	{	$self->{entry_re}->set_text( make_default_re($text) );
	}
	$self->{busy}=0;
	$self->preview_update;
}

sub preview_update
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	return if $self->{busy};
	my $re=$self->{entry_re}->get_text;
	my $qr=eval { qr/$re/i; };
	if ($@)
	{	$self->{error}->show;
		$self->{error}->set_markup_with_format("<i><b>%s</b></i>",_"Invalid regular expression");
		$self->{preview}->set_text('');
		return;
	}
	my $format=$self->{entry_format}->get_text;
	my @fields= map Songs::FieldName($_), find_fields($format);
	my $ID=$self->{ID};
	my $file= Songs::Display($ID,'barefilename');
	my @text=(_"Example :", Songs::FieldName('file'), $file);
	my $preview= "%s\n<i>%s</i> : <small>%s</small>\n\n";
	my @v;
	@v= ($file=~m/$qr/) if $re;
	if (@v || !$re) { $self->{error}->hide; $self->{error}->set_text(''); }
	else
	{	$self->{error}->show;
		$self->{error}->set_markup_with_format("<i><b>%s</b></i>",_"Regular expression didn't match");
	}
	s/_/ /g, s/^\s+//, s/\s+$// for @v;
	for my $i (sort { $fields[$a] cmp $fields[$b] } 0..$#fields)
	{	my $v= $v[$i];
		$v='' unless defined $v;
		push @text, $fields[$i],$v;
		$preview.= "<i>%s</i> : %s\n";
	}
	$self->{preview}->set_markup_with_format($preview,@text);
}

sub button_cb
{	my ($button,$action)=@_;
	my $self= ::find_ancestor($button,__PACKAGE__);
	my $formats= $::Options{filename2tags_formats};
	my $format= $self->{entry_format}->get_text;
	if ($action eq 'remove')
	{	delete $formats->{$format};
	}
	if ($action eq 'new' || $action eq 'remove')
	{	$self->{check_re}->set_active(1);
		$self->{entry_format}->set_text('');
	}
	else
	{	$formats->{$format}= $self->{check_re}->get_active ? undef : $self->{entry_re}->get_text;
	}
	return if $action eq 'new';
	$self->fill_store;
	@FORMATS_user=();
	::HasChanged('AutofillFormats');
}

sub fill_store
{	my $self=shift;
	my $store=$self->{store};
	$store->clear;
	my $formats= $::Options{filename2tags_formats} ||= {};
	for my $format (sort keys %$formats)
	{	my $formatname= make_format_name($format);
		$store->set($store->append, 0,$formatname, 1,$format);
	}
	$self->entry_changed;
}

sub make_format_name
{	my ($format,$markup)=@_;
	$format=~s#(\$\w+|%[a-zA-Z]|\$\{\w+\})|([%\$])\2#
		   $2 || do {	my $f= $::ReplaceFields{$1};
		   		$f=undef if $f && $Songs::Def{$f}{flags}!~m/e/;
				$f&&= Songs::FieldName($f);
				$f&&= ::MarkupFormat($markup,$f) if $markup;
				$f || $1
			    }#ge;
	return $format;
}
sub find_fields
{	my $format=shift;
	my @fields= map $::ReplaceFields{$_}, grep defined, $format=~m/ %% | \$\$ | ( \$\w+ | %[a-zA-Z] | \$\{\w+\} ) /gx;
	@fields= grep defined && $Songs::Def{$_}{flags}=~m/e/, @fields;
	return @fields;
}
sub make_default_re
{	my $re=shift;
	$re=~s#(\$\w+|%[a-zA-Z]|\$\{\w+\})|%(%)|\$(\$)|(%?[-,;\w ]+)|(.)#
		$1 ? Songs::ReplaceFields_to_re($1) :
		$2 ? $2 : $3 ? '\\'.$3 : defined $4 ? $4 : '\\'.$5 #ge;
	return $re;
}

sub cursor_changed_cb
{	my $treeview=shift;
	my $self=::find_ancestor($treeview,__PACKAGE__);
	return if $self->{busy};
	my $path=($treeview->get_cursor)[0];
	return unless $path;
	my $store=$treeview->get_model;
	my $format= $store->get( $store->get_iter($path), 1);
	my $re= $::Options{filename2tags_formats}{$format};
	$self->{entry_format}->set_text($format);
	$self->{check_re}->set_active( !defined $re );
	$self->{entry_re}->set_text($re) if defined $re;
}


package GMB::TagEdit::EntryString;
use Gtk2;
use base 'Gtk2::Entry';

sub new
{	my ($class,$field,$ID,$width,$completion) = @_;
	my $self = bless Gtk2::Entry->new, $class;
	#$self->{field}=$field;
	my $val=Songs::Get($ID,$field);
	$self->set_text($val);
	GMB::ListStore::Field::setcompletion($self,$field) if $completion;
	if ($width) { $self->set_width_chars($width); $self->{noexpand}=1; }
	return $self;
}

sub tool
{	my ($self,$sub)=@_;
	my $val= $sub->($self->get_text);
	$self->set_text($val) if defined $val;
}

package GMB::TagEdit::EntryText;
use Gtk2;
use base 'Gtk2::VBox';

sub new
{	my ($class,$field,$IDs) = @_;
	my $self = bless Gtk2::VBox->new, $class;
	my $sw = Gtk2::ScrolledWindow->new;
	 $sw->set_shadow_type('etched-in');
	 $sw->set_policy('automatic','automatic');
	$sw->add( $self->{textview}=Gtk2::TextView->new );
	$self->add($sw);
	my $val;
	if (ref $IDs)
	{	my $values= Songs::BuildHash($field,$IDs);
		my @l=sort { $values->{$b} <=> $values->{$a} } keys %$values; #sort values by their frequency
		$val=$l[0];
		$self->{IDs}=$IDs;
		$self->{field}=$field;
		$self->{append}=my $append=Gtk2::CheckButton->new(_"Append (only if not already present)");
		$self->pack_end($append,0,0,0);
	}
	else { $val=Songs::Get($IDs,$field); }
	$self->set_text($val);
	return $self;
}
sub set_text
{	my $self=shift;
	$self->{textview}->get_buffer->set_text(shift);
}
sub get_text
{	my $self=shift;
	my $buffer=$self->{textview}->get_buffer;
	my $text=$buffer->get_text( $buffer->get_bounds, 1);
	if ($self->{append} && $self->{append}->get_active)	#append
	{	my @orig= Songs::Map($self->{field},$self->{IDs});
		for my $orig (@orig)
		{	next if $text eq '';
			if ($orig eq '') { $orig=$text; }
			else
			{	next if index("$orig\n","$text\n")!=-1;		#don't append if the line(s) already exists
				$orig.="\n".$text;
			}
		}
		return \@orig;
	}
	return $text;
}
sub tool
{	&GMB::TagEdit::EntryString::tool;
}

package GMB::TagEdit::EntryNumber;
use Gtk2;
use base 'Gtk2::SpinButton';

sub new
{	my ($class,$field,$IDs,$max,$digits) = @_;
	$max||=10000000;
	$digits||=0;
	my $adj=Gtk2::Adjustment->new(0,0,$max,1,10,0);
	my $self = bless Gtk2::SpinButton->new($adj,10,$digits), $class;
	$self->{noexpand}=1;
	#$self->{field}=$field;
	my $val;
	if (ref $IDs)
	{	my $values= Songs::BuildHash($field,$IDs);
		my @l=sort { $values->{$b} <=> $values->{$a} } keys %$values; #sort values by their frequency
		$val=$l[0]; #take the most common value
	}
	else { $val=Songs::Get($IDs,$field); }
	$self->set_value($val);
	return $self;
}
sub get_text
{	$_[0]->get_value;
}
sub set_text
{	my $v=$_[1];
	$v=0 unless $v=~m/^\d+$/;
	$_[0]->set_value($v);
}
sub is_blank
{	my $self=shift;
	return ! $self->get_value;
}
sub tool
{	&GMB::TagEdit::EntryString::tool;
}

package GMB::TagEdit::EntryBoolean;
use Gtk2;
use base 'Gtk2::CheckButton';

sub new
{	my ($class,$field,$IDs) = @_;
	my $self = bless Gtk2::CheckButton->new, $class;
	$self->{noexpand}=1;
	#$self->{field}=$field;
	my $val;
	if (ref $IDs)
	{	my $values= Songs::BuildHash($field,$IDs);
		my @l=sort { $values->{$b} <=> $values->{$a} } keys %$values; #sort values by their frequency
		$val=$l[0]; #take the most common value
	}
	else { $val=Songs::Get($IDs,$field); }
	$self->set_active($val);
	return $self;
}
sub get_text
{	$_[0]->get_active;
}

package GMB::TagEdit::Combo;
use Gtk2;
use base 'Gtk2::Combo';

sub new
{	my ($class,$field,$IDs,$listall) = @_;
	my $self= bless Gtk2::Combo->new, $class;
	#$self->{field}=$field;

	my $values= Songs::BuildHash($field,$IDs);
	my @l=sort { $values->{$b} <=> $values->{$a} } keys %$values; #sort values by their frequency
	my $first=$l[0];
	@l= @{ Songs::Gid_to_Get($field,\@l) } if Songs::Field_property($field,'gid_to_get');
	if ($listall) { push @l, @{Songs::ListAll($field)}; }
	$self->set_case_sensitive(1);
	$self->set_popdown_strings(@l);
	$self->set_text('') unless ( $values->{$first} > @$IDs/3 );

	GMB::ListStore::Field::setcompletion($self->entry,$field) if $listall;

	return $self;
}

sub set_text
{	$_[0]->entry->set_text($_[1]);
}
sub get_text
{	$_[0]->entry->get_text;
}
sub tool
{	&GMB::TagEdit::EntryString::tool;
}


package GMB::TagEdit::EntryRating;
use Gtk2;
use base 'Gtk2::HBox';

sub new
{	my ($class,$field,$IDs) = @_;
	my $self = bless Gtk2::HBox->new, $class;
	#$self->{field}=$field;

	my $init;
	if (ref $IDs)
	{	my $h= Songs::BuildHash($field,$IDs);
		$init=(sort { $h->{$b} <=> $h->{$a} } keys %$h)[0];
	}
	else {	$init=Songs::Get($IDs,$field);	}

	my $adj=Gtk2::Adjustment->new(0,0,100,10,20,0);
	my $spin=Gtk2::SpinButton->new($adj,10,0);
	my $check=Gtk2::CheckButton->new(_"use default");
	my $stars=Stars->new($field,$init,\&update_cb);

	$self->pack_start($_,0,0,0) for $stars,$spin,$check;
	$self->{stars}=$stars;
	$self->{check}=$check;
	$self->{adj}=$adj;

	$self->update_cb($init);
	#$self->{modif}=0;
	$adj->signal_connect(value_changed => sub{ $self->update_cb($_[0]->get_value) });
	$check->signal_connect(toggled	   => sub{ update_cb($_[0], ($_[0]->get_active ? '' : $::Options{DefaultRating}) ) });

	return $self;
}

sub update_cb
{	my ($widget,$v)=@_;
	my $self=::find_ancestor($widget,__PACKAGE__);
	return if $self->{busy};
	$self->{busy}=1;
	$v='' unless defined $v && $v ne '' && $v!=255;
	#$self->{modif}=1;
	$self->{value}=$v;
	$self->{check}->set_active($v eq '');
	$self->{stars}->set($v);
	$v=$::Options{DefaultRating} if $v eq '';
	$self->{adj}->set_value($v);
	$self->{busy}=0;
}

sub get_text
{	$_[0]->{value};
}
sub is_blank
{	my $v=$_[0]->{value};
	$v eq '' || $v==255;
}

package GMB::TagEdit::FlagList;
use Gtk2;
use base 'Gtk2::Box';

sub new
{	my ($class,$field,$ID) = @_;
	my $self = bless Gtk2::HBox->new(0,0), $class;
	$self->{field}=$field;
	$self->{ID}=$ID;
	my $label=$self->{label}=Gtk2::Label->new;
	$label->set_ellipsize('end');
	my $button= Gtk2::Button->new;
	my $entry= Gtk2::Entry->new;
	$entry->set_width_chars(12);
	$button->add($label);
	$self->pack_start($button,1,1,0);
	$self->pack_start($entry,0,0,0);
	$button->signal_connect( clicked => \&popup_menu_cb);
	$button->signal_connect( button_press_event => sub { popup_menu_cb($_[0]); $_[0]->grab_focus;1; } );
	$entry->signal_connect( activate => \&entry_activate_cb );
	GMB::ListStore::Field::setcompletion($entry,$field);

	$self->{selected}{$_}=1 for Songs::Get_list($ID,$field);
	delete $self->{selected}{''};
	$self->update;
	return $self;
}

sub entry_activate_cb
{	my $entry=$_[0];
	my $self=::find_ancestor($entry,__PACKAGE__);
	my $text=$entry->get_text;
	if ($text eq '') { popup_add_menu($self,$entry); return }
	#return if $text eq '';
	$self->{selected}{ $text }=1;
	$self->update;
	$entry->set_text('');
}

sub popup_add_menu
{	my ($self,$widget)=@_;
	my $cb= sub { $self->{selected}{ $_[1] }= 1; $self->update; };
	my $menu=::MakeFlagMenu($self->{field},$cb);
	$menu->show_all;
	my $event=Gtk2->get_current_event;
	my $button= $event->isa('Gtk2::Gdk::Event::Button') ? $event->button : 0;
	$menu->popup(undef,undef,sub {::windowpos($_[0],$widget)},undef,$button,$event->time);
}

sub popup_menu_cb
{	my $widget=shift;
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $menu=Gtk2::Menu->new;
	my $cb= sub { $self->{selected}{ $_[1] }^=1; $self->update; };
	my @keys= ::superlc_sort(keys %{$self->{selected}});
	return unless @keys;
	for my $key (@keys)
	{	my $item=Gtk2::CheckMenuItem->new_with_label($key);
		$item->set_active(1) if $self->{selected}{$key};
		$item->signal_connect(toggled => $cb,$key);
		$menu->append($item);
	}
	$menu->show_all;
	my $event=Gtk2->get_current_event;
	my $button= $event->isa('Gtk2::Gdk::Event::Button') ? $event->button : 0;
	$menu->popup(undef,undef,\&::menupos,undef,$button,$event->time);
}

sub update
{	my $self=$_[0];
	my $h=$self->{selected};
	my $text=join '<b>, </b>', map ::PangoEsc($_), ::superlc_sort(grep $h->{$_}, keys %$h);
	#$text= ::MarkupFormat("<i>- %s -</i>",_"None") if $text eq '';
	$self->{label}->set_markup($text);
	$self->{label}->parent->set_tooltip_markup($text);
}

sub get_text
{	my $self=shift;
	my $h=$self->{selected};
	return [grep $h->{$_}, keys %$h];
}

sub is_blank
{	my $self=shift;
	my $list= $self->get_text;
	return !(@$list);
}
sub set_text		# for setting from autofill-from-filename
{	my ($self,$val)=@_;
	my @vals= grep $_ ne '', split /\s*[;,]\s*/, $val; # currently split on ; or ,
	my $selected= $self->{selected};
	$selected->{$_}=0 for keys %$selected; #remove all
	$selected->{$_}=1 for @vals;
	$self->update;
}

package GMB::TagEdit::EntryMassList;	#for mass-editing fields with multiple values
use Gtk2;
use base 'Gtk2::Box';

sub new
{	my ($class,$field,$IDs) = @_;
	my $self = bless Gtk2::VBox->new(1,1), $class;
	$self->{field}=$field;
	my $sg= Gtk2::SizeGroup->new('horizontal');
	my $entry= $self->{entry}= Gtk2::Entry->new;
	my $add= ::NewIconButton('gtk-add', undef, \&add_entry_text_cb);
	my $removeall= ::NewIconButton('gtk-clear', _"Remove all", \&clear);
	$add->signal_connect( button_press_event => sub { add_entry_text_cb($_[0]); $_[0]->grab_focus;1; } );
	for my $ref (['toadd',1,_"Add"],['toremove',-1,_"Remove"])
	{	my ($key,$mode,$text)=@$ref;
		my $label=$self->{$key}=Gtk2::Label->new;
		$label->set_ellipsize('end');
		$label->{mode}=$mode;
		my $button= Gtk2::Button->new;
		$button->add($label);
		$button->{mode}=$mode;
		$button->signal_connect( clicked => \&popup_menu_cb );
		$button->signal_connect( button_press_event => sub { popup_menu_cb($_[0]); $_[0]->grab_focus;1; } );
		my $sidelabel= Gtk2::Label->new($text);
		my $hbox= Gtk2::HBox->new(0,1);
		$hbox->pack_start($sidelabel,0,0,2);
		$hbox->pack_start($button,1,1,2);
		$hbox->pack_start($entry,0,0,0) if $mode>0;
		$hbox->pack_start($add,0,0,0) if $mode>0;
		$hbox->pack_start($removeall,0,0,0) if $mode<0;
		$self->pack_start($hbox,0,0,2);
		$sidelabel->set_alignment(0,.5);
		$sg->add_widget($sidelabel);
	}
	GMB::ListStore::Field::setcompletion($entry,$field);
	$entry->signal_connect(activate => \&add_entry_text_cb);
	my $valueshash= Songs::BuildHash($field,$IDs);
	my %selected;
	$selected{ Songs::Gid_to_Get($field,$_) }= $valueshash->{$_}==@$IDs ? 1 : 0 for keys %$valueshash;
	delete $selected{''};
	$self->{selected}=\%selected;
	$self->{all}= [keys %selected]; #all values that are set for at least one song
	$self->update;
	return $self;
}

sub update	#update the text and tooltips of buttons
{	my $self=shift;
	for my $key (qw/toadd toremove/)
	{	my $label= $self->{$key};
		my $mode= $label->{mode}; # -1 or 1
		my $h= $self->{selected};
		my $text=join '<b>, </b>', map ::PangoEsc($_), ::superlc_sort(grep $h->{$_}==$mode, keys %$h);
		#$text= ::MarkupFormat("<i>- %s -</i>",_"None") if $text eq '';
		$label->set_markup($text);
		$label->parent->set_tooltip_markup($text);	# set tooltip on button
	}
}

sub add_entry_text_cb
{	my $widget=shift;
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $entry=$self->{entry};
	my $text=$entry->get_text;
	if ($text eq '') { $self->popup_add_menu($widget); return }
	# split $text ?
	$self->{selected}{$text}=1;
	$entry->set_text('');
	$self->update;
}

sub clear # set to -1 all values present in at least one song, set to 0 values not present
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $h= $self->{selected};
	$_=0 for values %$h;
	$h->{$_}=-1 for @{$self->{all}};
	$self->update;
}

sub popup_add_menu
{	my ($self,$widget)=@_;
	my $cb= sub { $self->{selected}{ $_[1] }= 1; $self->update; };
	my $menu=::MakeFlagMenu($self->{field},$cb);
	$menu->show_all;
	my $event=Gtk2->get_current_event;
	my $button= $event->isa('Gtk2::Gdk::Event::Button') ? $event->button : 0;
	$menu->popup(undef,undef,sub {::windowpos($_[0],$widget)},undef,$button,$event->time);
}

sub popup_menu_cb
{	my $child=shift;
	my $mode=$child->{mode};
	my $self=::find_ancestor($child,__PACKAGE__);
	my $h= $self->{selected};
	my $menu=Gtk2::Menu->new;
	my $cb= sub { $self->{selected}{ $_[1] }= $_[0]->get_active ? $mode : 0; $self->update; };
	my @keys= ::superlc_sort(keys %$h);
	return unless @keys;
	for my $key (@keys)
	{	my $item=Gtk2::CheckMenuItem->new_with_label($key);
		$item->set_active(1) if $h->{$key}==$mode;
		$item->signal_connect(toggled => $cb,$key);
		$menu->append($item);
	}
	$menu->show_all;
	my $event=Gtk2->get_current_event;
	my $button= $event->isa('Gtk2::Gdk::Event::Button') ? $event->button : 0;
	$menu->popup(undef,undef,\&::menupos,undef,$button,$event->time);
	1;
}

sub return_setunset
{	my $self=$_[0];
	my (@set,@unset);
	my $h=$self->{selected};
	for my $value (keys %$h)
	{	my $mode=$h->{$value};
		if	($mode>0)	{ push @set,$value }
		elsif	($mode<0)	{ push @unset,$value }
	}
	return \@set,\@unset;
}

sub is_blank {1}
sub set_text		# for setting from autofill-from-filename
{	my ($self,$val)=@_;
	my @vals= grep $_ ne '', split /\s*[;,]\s*/, $val; # currently split on ; or ,
	my $selected= $self->{selected};
	#$selected->{$_}=0 for keys %$selected; #remove all
	$selected->{$_}=1 for @vals;
	$self->update;
}

package EditTagSimple;
use Gtk2;

use constant { TRUE  => 1, FALSE => 0, };

use base 'Gtk2::VBox';
sub new
{	my ($class,$window,$ID) = @_;
	my $self = bless Gtk2::VBox->new, $class;
	$self->{window}=$window;
	$self->{ID}=$ID;

	my $labelfile = Gtk2::Label->new;
	$labelfile->set_markup( ::ReplaceFieldsAndEsc($ID,'<small>%u</small>') );
	$labelfile->set_selectable(TRUE);
	$labelfile->set_line_wrap(TRUE);

	my $table=Gtk2::Table->new (6, 2, FALSE);
	$self->{table}=$table;
	$self->fill;

	my $advanced=Gtk2::Button->new(_("Advanced Tag Editing").' ...');
	$advanced->signal_connect( clicked => \&advanced_cb );

	$self->pack_start($labelfile,FALSE,FALSE,1);
	$self->pack_start($table, FALSE, TRUE, 2);
	$self->pack_end($advanced, FALSE, FALSE, 2);

	return $self;
}

sub fill
{	my $self=$_[0];
	my $table=$self->{table};
	my $ID=$self->{ID};
	my $row1=my $row2=0;
	for my $field ( Songs::EditFields('single') )
	{	my $widget=Songs::EditWidget($field,'single',$ID);
		next unless $widget;
		my ($row,$col)= $widget->{noexpand} ? ($row2++,2) : ($row1++,0);
		if (my $w=$self->{fields}{$field})	#refresh the fields
			{ $table->remove($w); }
		else #first time
		{	my $label=Gtk2::Label->new( Songs::FieldName($field) );
			$table->attach($label,$col,$col+1,$row,$row+1,'fill','shrink',2,2);
		}
		$table->attach($widget,$col+1,$col+2,$row,$row+1,['fill','expand'],'shrink',2,2);
		$self->{fields}{$field}=$widget;
	}
	$table->show_all;
}

sub advanced_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID=$self->{ID};
	my $dialog = Gtk2::Dialog->new (_"Advanced Tag Editing", $self->{window},
		[qw/destroy-with-parent/],
		'gtk-ok' => 'ok',
		'gtk-cancel' => 'none');
	$dialog->set_default_response ('ok');
	my $edittag=EditTag->new($dialog,$ID);
	unless ($edittag) { ::ErrorMessage(_"Can't read file or invalid file"); return }
	$dialog->vbox->add($edittag);
	::SetWSize($dialog,'AdvTag');
	$dialog->show_all;
	$self->{window}->set_sensitive(0);
	$dialog->signal_connect( response => sub
	 {	my ($dialog,$response)=@_;
		if ($response eq 'ok')
		{	$edittag->save;
			Songs::ReReadFile($ID);
			$self->fill;
		}
		$self->{window}->set_sensitive(1);
		$dialog->destroy;
	 });
}

sub save
{	my $self=shift;
	my $ID=$self->{ID};
	my $errorsub=sub {::Retry_Dialog($_[0],$self->{window});};
	my @modif;
	while (my ($field,$entry)=each %{$self->{fields}})
	{	push @modif,$field,$entry->get_text;
	}
	Songs::Set($ID,\@modif,error=>$errorsub) if @modif;
}


############################## Advanced tag editing ##############################

package EditTag;
use Gtk2;

use base 'Gtk2::VBox';

sub new
{	my ($class,$window,$ID) = @_;
	my $file= Songs::GetFullFilename($ID);
	return undef unless $file;
	my $self = bless Gtk2::VBox->new, $class;
	$self->{window}=$window;

	my $labelfile=Gtk2::Label->new;
	$labelfile->set_markup( ::ReplaceFieldsAndEsc($ID,'<small>%u</small>') );
	$labelfile->set_selectable(::TRUE);
	$labelfile->set_line_wrap(::TRUE);
	$self->pack_start($labelfile,::FALSE,::FALSE,1);
	$self->{filename}=$file;

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FileTag::FORMATS{lc$format};
	$self->{filetag}=my $filetag= $format->[0]->new($file);
	unless ($filetag) {warn "can't read tags for $file\n";return undef;}

	my @boxes; $self->{boxes}=\@boxes;
	my @tags;
	for my $t (split / /,$format->[2])
	{	if ($t eq 'vorbis' || $t eq 'ilst')	{push @tags,$filetag;}
		elsif ($t eq 'APE')
		{	if ($filetag->{APE})	{ push @tags,$filetag->{APE}; }
			elsif (!@tags)		{ push @tags,$filetag->new_APE; }
		}
		elsif ($t eq 'ID3v2')
		{	if ($filetag->{ID3v2})	{ push @tags,$filetag->{ID3v2};push @tags, @{ $filetag->{ID3v2s} } if $filetag->{ID3v2s}; }
			elsif (!@tags)		{ push @tags,$filetag->new_ID3v2; }
		}
	}
	push @tags,$filetag->{lyrics3v2} if $filetag->{lyrics3v2};

	$self->{filetag}=$filetag;
	push @boxes,TagBox->new(shift @tags);
	push @boxes,TagBox->new($_,1) for grep defined,@tags;
	push @boxes,TagBox_id3v1->new($filetag,1) if $filetag->{ID3v1};

	my $notebook=Gtk2::Notebook->new;
	for my $box (grep defined, @boxes)
	{	$notebook->append_page($box,$box->{title});
	}
	$self->add($notebook);

	return $self;
}

sub save
{	my $self=shift;
	my $modified;
	for my $box (@{ $self->{boxes} })
	{  $modified=1 if $box->save;
	}
	$self->{filetag}{errorsub}=sub {::Retry_Dialog($_[0],$self->{window});};
	$self->{filetag}->write_file if $modified && !$::CmdLine{ro} && !$::CmdLine{rotags};
}

package TagBox;
use Gtk2;
use constant
{	TRUE  => 1, FALSE => 0,
	#contents of types hashes :
	TAGNAME => 0, TAGORDER => 1, TAGTYPE => 2,
};
use base 'Gtk2::VBox';

my %DataType;
my %tagprop;

INIT
{ my $id3v2_types=
  {	#id3v2.3/4
	TIT2 => [_"Title",1],
	TIT3 => [_"Version",2],
	TPE1 => [_"Artist",3],
	TPE2 => [_"Album artist",4.5],
	TALB => [_"Album",4],
	TPOS => [_"Disc #",5],
	TRCK => [_"Track",6],
	TYER => [_"Date",7],
	COMM => [_"Comments",9],
	TCON => [_"Genre",8],
	TLAN => [_"Languages",20],
	USLT => [_"Lyrics",14],
	APIC => [_"Picture",15],
	TOPE => [_"Original Artist",40],
	TXXX => [_"Custom Text",50],
	WOAR => [_"Artist URL",50],
	WXXX => [_"Custom URL",50],
	PCNT => [_"Play counter",44],
	POPM => [_"Popularimeter",45],
	GEOB => [_"Encapsulated object",60],
	PRIV => [_"Private Data",98],
	UFID => [_"Unique file identifier",99],
	TCOP => [_("Copyright")." ©",80],
	TPRO => [_"Produced (P)",81], #FIXME find (P) symbol
	TCOM => [_"Composer",12],
	TIT1 => [_"Grouping",13],
	TENC => [_"Encoded by",51],
	TSSE => [_"Encoded with",52],
	TMED => [_"Media type"],
	TFLT => [_"File type"],
	TOAL => [_"Originaly from"],
	TOFN => [_"Original Filename"],
	TORY => [_"Original release year"],
	TPUB => [_"Label/Publisher"],
	TRDA => [_"Recording Dates"],
	TSRC => ["ISRC"],
	TCMP => [_"Compilation",60,'f'],
  };
  my $vorbis_types=
  {	title		=> [_"Title",1],
	version		=> [_"Version",2],
	artist		=> [_"Artist",3],
	album		=> [_"Album",4],
	discnumber	=> [_"Disc #",5],
	tracknumber	=> [_"Track",6],
	date		=> [_"Date",7],
	comments	=> [_"Comments",9,'M'],
	description	=> [_"Description",9,'M'],
	genre		=> [_"Genre",8],
	lyrics		=> [_"Lyrics",14,'L'],
	fmps_lyrics	=> [_"Lyrics",14,'L'],
	author		=> [_"Original Artist",40],
	metadata_block_picture=> [_"Picture",15,'tCTb'],
  };
  my $ape_types=
  {	title		=> [_"Title",1],
	artist		=> [_"Artist",3],
	album		=> [_"Album",4],
	subtitle	=> [_"Subtitle",5],
	publisher	=> [_"Publisher",14],
	conductor	=> [_"Conductor",13],
	track		=> [_"Track",6],
	genre		=> [_"Genre",8],
	composer	=> [_"Composer",12],
	comment		=> [_"Comment",9],
	copyright	=> [_"Copyright",80],
	publicationright=> [_"Publication right",81],
	year		=> [_"Year",7],
	'debut album'	=> [_"Debut Album",8],
	fmps_lyrics	=> [_"Lyrics",14,'L'],
  };
  my $lyrics3v2_types=
  {	LYR => [_"Lyrics",7,'M'],
	INF => [_"Info",6,'M'],
	AUT => [_"Author",5],
	EAL => [_"Album",4],
	EAR => [_"Artist",3],
	ETT => [_"Title",1],
  };
  my $ilst_types=
  {	"\xA9nam" => [_"Title",1],
	"\xA9ART" => [_"Artist",3],
	"\xA9alb" => [_"Album",4],
	"\xA9day" => [_"Year",8],
	"\xA9cmt" => [_"Comment",12,'M'],
	"\xA9gen" => [_"Genre",10],
	"\xA9wrt" => [_"Author",14],
	"\xA9lyr" => [_"Lyrics",50],
	"\xA9too" => [_"Encoder",51],
	'----'	  => [_"Custom",52,'ttt'],
	trkn	  => [_"Track",6],
	disk	  => [_"Disc #",7],
	aART	  => [_"Album artist",9],
	covr	  => [_"Picture",20,'p'],
	cpil	  => [_"Compilation",19,'f'],
	# pgap => gapless album
	# pcst => podcast
  };

 %tagprop=
 (	ID3v2 =>{	addlist => [qw/COMM TPOS TIT3 TCON TXXX TOPE WOAR WXXX USLT APIC POPM PCNT GEOB/],
			default => [qw/COMM TIT2 TPE1 TALB TYER TRCK TCON/],
			infosub => sub { Tag::ID3v2::get_fieldtypes($_[1]); },
			namesub => sub { 'id3v2.'.$_[0]{version} },
			types	=> $id3v2_types,
		},
	OGG =>	{	addlist => [qw/description genre discnumber author metadata_block_picture/,''],
			default => [qw/title artist album tracknumber date description genre/],
			name	=> 'vorbis comment',
			types	=> $vorbis_types,
			lckeys	=> 1,
		},
	APE=>	{	addlist => [qw/Title Subtitle Artist Album Genre Publisher Conductor Track Composer Comment Copyright Publicationright Year/,'Debut Album'],
			default => [qw/Title Artist Album Track Year Genre Comment/],
			infosub => sub { $_[0]->is_binary($_[1],$_[2]); },
			name	=> 'APE tag',
			types	=> $ape_types,
			lckeys	=> 1,
		},
	Lyrics3v2=>{	addlist => [qw/EAL EAR ETT INF AUT LYR/],
			default => [qw/EAL EAR ETT INF/],
			name	=> 'lyrics3v2 tag',
			types	=> $lyrics3v2_types,
		},
	M4A =>	{	addlist => ["\xA9cmt","\xA9wrt",qw/disk aART cpil ----/],
			default => ["\xA9nam","\xA9ART","\xA9alb",'trkn',"\xA9day","\xA9cmt","\xA9gen"],
			infosub => sub {Tag::M4A::get_field_info($_[1])},
			name	=> 'ilst',
			types	=> $ilst_types,
		},
 );
 $tagprop{Flac}=$tagprop{OGG};

 %DataType=
 (	t => ['EntrySimple'],	#text
	T => ['EntrySimple'],	#text
	M => ['EntryMultiLines'],	#multi-line text
	#l => ['EntrySimple'],	#3 letters language #unused, found only in multi-fields frames
	c => ['EntryNumber'],	#counter
	C => ['EntryNumber',255], #1 byte integer (0-255)
	n => ['EntryNumber',65535],
	b => ['EntryBinary'],	#binary
	u => ['EntryBinary'],	#unknown -> binary
	f => ['EntryBoolean'],
	p => ['EntryCover'],
	L => ['EntryLyrics'],
 );

}

sub new
{	my ($class,$tag,$option)=@_;
	my $tagtype=ref $tag; $tagtype=~s/^Tag:://i;
	unless ($tagprop{$tagtype}) {warn "unknown tag '$tagtype'\n"; return undef;}
	$tagtype=$tagprop{$tagtype};
	my $self=bless Gtk2::VBox->new,$class;
	my $name=$tagtype->{name} || $tagtype->{namesub}($tag);
	$self->{title}=$name;
	$self->{tag}=$tag;
	$self->{tagtype}=$tagtype;
	my $sw=Gtk2::ScrolledWindow->new;
	#$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$self->{table}=my $table=Gtk2::Table->new(2,2,FALSE);
	$table->{row}=0;
	$table->{widgets}=[];
	$sw->add_with_viewport($table);
	if ($option)
	{	my $checkrm=Gtk2::CheckButton->new(_"Remove this tag");
		$checkrm->signal_connect( toggled => sub
		{	my $state=$_[0]->get_active;
			$table->{deleted}=$state;
			$table->set_sensitive(!$state);
		});
		$self->pack_start($checkrm,FALSE,FALSE,2);
	}
	$self->add($sw);

	if (my $list=$tagtype->{addlist})
	{	my $addbut=::NewIconButton('gtk-add',_"add");
		my $addlist=Gtk2::ComboBox->new_text;
		my $hbox=Gtk2::HBox->new(FALSE,8);
		$hbox->pack_start($_,FALSE,FALSE,0) for $addlist,$addbut;
		$self->pack_start($hbox,FALSE,FALSE,2);
		for my $key (@$list)
		{	$key=lc$key if $tagtype->{lckeys};
			my $name=($key ne '')? $tagtype->{types}{$key}[TAGNAME] : _"(other)";
			$addlist->append_text($name);
		}
		$addlist->set_active(0);
		$addbut->signal_connect( clicked => sub
		{	my $key=$list->[ $addlist->get_active ];
			$self->addrow($key);
			Glib::Idle->add(\&scroll_to_bottom,$self);
		});
	}
	my %toadd= map { $_=>undef } $tag->get_keys;
	my @default= @{$tagtype->{'default'}};
	my $lc= $tagtype->{lckeys};
	if ($lc) { my %lc; $lc{lc()}=1 for keys %toadd; @default= grep !$lc{lc()}, @default; }
	$toadd{$_}=undef for @default;
	for my $key (sort { ($tagtype->{types}{ ($lc? lc$a : $a) }[TAGORDER]||100)
			<=> ($tagtype->{types}{ ($lc? lc$b : $b) }[TAGORDER]||100) } keys %toadd)
	{	my $nb=0;
		$self->addrow($key,$nb++,$_) for $tag->get_values($key);
		$self->addrow($key) if !$nb;
	}

	return $self;
}

sub scroll_to_bottom
{	my $self=shift;
	my $adj= $self->{table}->parent->get_vadjustment;
	$adj->clamp_page($adj->upper,$adj->upper);
	0; #called from an idle => false to disconnect idle
}

sub addrow
{	my ($self,$key,$nb,$value)=@_;
	my $table=$self->{table};
	my $row=$table->{row}++;
	my ($widget,@Todel);
	my $tagtype=$self->{tagtype};
	my $typesref=$tagtype->{types}{($tagtype->{lckeys}? lc$key : $key)};

	my ($name,$type,$realkey);
	if ($typesref)
	{	$type=$typesref->[TAGTYPE];
		$name=$typesref->[TAGNAME];
	}
	if ($tagtype->{infosub})
	{	(my $type0,$realkey,my $fallbackname,my @extra)= $tagtype->{infosub}( $self->{tag}, $key, $nb );
		$type||=$type0;
		$name||= $tagtype->{types}{$realkey}[TAGNAME] if $realkey;
		$name||= $fallbackname if $fallbackname;
		$value=[@extra, (ref $value ? @$value : $value)] if @extra;
	}
	$name||=$key;
	$type||='t';

	if (length($type)>1)	#frame with sub-frames
	{	$value||=[];
		$widget=EntryMulti->new($value,$key,$name,$type,$realkey);
		$table->attach($widget,1,3,$row,$row+1,['fill','expand'],'shrink',1,1);
	}
	else	#simple case : 1 label -> 1 value
	{	$value=$value->[0] if ref $value;
		$value='' unless defined $value;
		my $label;
		$type=$DataType{$type}[0] || 'EntrySimple';
		my $param=$DataType{$type}[1];
		if ($key eq '') { ($widget,$label)=EntryDouble->new($value); }
		else	{ $widget=$type->new($value,$param); $label=Gtk2::Label->new($name); $label->set_tooltip_text($key); }
		$table->attach($label,1,2,$row,$row+1,'shrink','shrink',1,1);
		$table->attach($widget,2,3,$row,$row+1,['fill','expand'],'shrink',1,1);
		@Todel=($label);
	}
	push @Todel,$widget;
	$widget->{key}=$key;
	$widget->{nb}=$nb;

	my $delbut=Gtk2::Button->new;
	$delbut->set_relief('none');
	$delbut->add(Gtk2::Image->new_from_stock('gtk-remove','menu'));
	$table->attach($delbut,0,1,$row,$row+1,'shrink','shrink',1,1);
	$delbut->signal_connect( clicked => sub
		{ $widget->{deleted}=1;
		  $table->remove($_) for $_[0],@Todel;
		  $table->{ondelete}($widget) if $table->{ondelete};
		});

	push @{ $table->{widgets} }, $widget;
	$table->show_all;
}

sub save
{	my $self=shift;
	my $table=$self->{table};
	my $tag=$self->{tag};
	if ($table->{deleted})
	{	$tag->removetag;
		warn "$tag removed\n" if $::debug;
		return 1;
	}
	my $modified;
	for my $w ( @{ $table->{widgets} } )
	{    if ($w->{deleted})
	     {	next unless defined $w->{nb};
		$tag->remove($w->{key},$w->{nb});
		$modified=1; warn "$tag $w->{key} deleted\n" if $::debug;
	     }
	     else
	     {	my @v=$w->return_value;
		my $v= @v>1 ? \@v : $v[0];
		next unless $w->{changed};
		if (defined $w->{nb})	{ $tag->edit($w->{key},$w->{nb},$v); }
		else			{ $tag->add( $w->{key},$v); }
		$modified=1; warn "$tag $w->{key} modified\n" if $::debug;
	     }
	}
	return $modified;
}

package TagBox_id3v1;
use Gtk2;
use constant { TRUE  => 1, FALSE => 0 };
use base 'Gtk2::VBox';

sub new
{	my ($class,$tag,$option)=@_;
	my $self=bless Gtk2::VBox->new, $class;
	$self->{title}=_"id3v1 tag";
	$self->{tag}=$tag;
	$self->{table}=my $table=Gtk2::Table->new(2,2,FALSE);
	$table->{widgets}=[];
	my $row=0;
	if ($option)
	{	my $checkrm=Gtk2::CheckButton->new(_"Remove this tag");
		$checkrm->signal_connect( toggled => sub
		{	my $state=$_[0]->get_active;
			$table->{deleted}=$state;
			$_->set_sensitive(!$state) for grep $_ ne $_[0], $table->get_children;
		});
		$table->attach($checkrm,0,2,$row,$row+1,'shrink','shrink',1,1);
		$row++;
	}
	$self->add($table);
	for my $aref ([_"Title",0,30],[_"Artist",1,30],[_"Album",2,30],[_"Year",3,4],[_"Comment",4,30],[_"Track",5,2])
	{	my $label=Gtk2::Label->new($aref->[0]);
		my $entry=EntrySimple->new( $tag->{ID3v1}[ $aref->[1] ], $aref->[2]);
		push @{ $table->{widgets} }, $entry;
		$table->attach($label,0,1,$row,$row+1,'shrink','shrink',1,1);
		$table->attach($entry,1,2,$row,$row+1,['fill','expand'],'shrink',1,1);
		$row++;
	}
	my $combo=EntryCombo->new($tag->{ID3v1}[6],\@Tag::MP3::Genres);
	push @{ $table->{widgets} }, $combo;
	$table->attach(Gtk2::Label->new(_"Genre"),0,1,$row,$row+1,'shrink','shrink',1,1);
	$table->attach($combo,1,2,$row,$row+1,['fill','expand'],'shrink',1,1);
	return $self;
}

sub save
{	my $self=shift;
	my $table=$self->{table};
	my $filetag=$self->{tag};
	if ($table->{deleted}) { $filetag->{ID3v1}=undef; return 1; }
	my $modified;
	my $wgts=$table->{widgets};
	my $id3v1= $filetag->{ID3v1} || $filetag->new_ID3v1;
	for my $i (0..5)
	{	$id3v1->[$i]=$wgts->[$i]->return_value;
		$modified=1 if $wgts->[$i]{changed};
	}
	$id3v1->[6]= $wgts->[6]->return_value;
	$modified=1 if $wgts->[6]{changed};
	return $modified;
}

package EntrySimple;
use Gtk2;
use base 'Gtk2::Entry';

sub new
{	my ($class,$init,$len) = @_;
	my $self = bless Gtk2::Entry->new, $class;
	$self->set_text($init);
	$self->set_width_chars($len) if $len;
	$self->set_max_length($len) if $len;
	$self->{init}=$init;
	return $self;
}
sub return_value
{	my $self=shift;
	my $value=$self->get_text;
	#warn "$self '$value' '$self->{init}'" if $value ne $self->{init};
	$self->{changed}=1 if $value ne $self->{init};
	return $value;
}

package EntryMultiLines;
use Gtk2;
use base 'Gtk2::ScrolledWindow';

sub new
{	my ($class,$init) = @_;
	my $self = bless Gtk2::ScrolledWindow->new, $class;
	 $self->set_shadow_type('etched-in');
	 $self->set_policy('automatic','automatic');
	$self->add( $self->{textview}=Gtk2::TextView->new );
	$self->set_text($init);
	$self->{init}=$self->get_text;
	return $self;
}
sub set_text
{	my $self=shift;
	$self->{textview}->get_buffer->set_text(shift);
}
sub get_text
{	my $self=shift;
	my $buffer=$self->{textview}->get_buffer;
	return $buffer->get_text( $buffer->get_bounds, 1);
}
sub return_value
{	my $self=shift;
	my $value=$self->get_text;
	$self->{changed}=1 if $value ne $self->{init};
	return $value;
}

package EntryDouble;
use Gtk2;
use base 'Gtk2::Entry';

sub new
{	my ($class,$init) = @_;
	my $self = bless Gtk2::Entry->new, $class;
	#$self->set_text($init);
	#$self->{init}=$init;
	$self->{keyEntry}=Gtk2::Entry->new;
	return $self,$self->{keyEntry};
}
sub return_value
{	my $self=shift;
	my $value=$self->get_text;
	$self->{key}=$self->{keyEntry}->get_text;
	$self->{changed}=1 if ($self->{key} ne '' && $value ne '');
	return $value;
}

package EntryNumber;
use Gtk2;
use base 'Gtk2::SpinButton';

sub new
{	my ($class,$init,$max) = @_;
	my $self = bless Gtk2::SpinButton->new(
		Gtk2::Adjustment->new ($init||0, 0, $max||10000000, 1, 10, 0) ,10,0  )
		, $class;
	$self->{init}=$self->get_value;
	return $self;
}
sub return_value
{	my $self=shift;
	my $value=$self->get_value;
	$self->{changed}=1 if $value ne $self->{init};
	return $value;
}

package EntryBoolean;
use Gtk2;
use base 'Gtk2::CheckButton';

sub new
{	my ($class,$init) = @_;
	my $self = bless Gtk2::CheckButton->new, $class;
	$self->set_active(1) if $init;
	$self->{init}=$init;
	return $self;
}
sub return_value
{	my $self=shift;
	my $value=$self->get_active;
	$self->{changed}=1 if ($value xor $self->{init});
	return $value;
}
package EntryCombo;
use Gtk2;
use base 'Gtk2::ComboBox';

sub new
{	my ($class,$init,$listref) = @_;
	my $self = bless Gtk2::ComboBox->new_text, $class;
	if ($init && $init=~m/\D/)
	{	my $text=$init;
		$init='';
		for my $i (0..$#$listref)
		{	if ($listref->[$i] eq $text) {$init=$i;last}
		}
	}
	for my $text (@$listref)
	{	$self->append_text($text);
	}
	$self->set_active($init) unless $init eq '';
	$self->{init}=$init;
	return $self;
}
sub return_value
{	my $self=shift;
	my $value=$self->get_active;
	$value='' if $value==-1;
	$self->{changed}=1 if $value ne $self->{init};
	return $value;
}

package EntryMulti;	#for id3v2 frames containing multiple fields
use Gtk2;

my %SUBTAGPROP; my $PICTYPE;
INIT
{ $PICTYPE=[_"other",_"32x32 PNG file icon",_"other file icon",_"front cover",_"back cover",_"leaflet page",_"media",_"lead artist",_"artist",_"conductor",_"band",_"composer",_"lyricist",_"recording location",_"during recording",_"during performance",_"movie/video screen capture",_"a bright coloured fish",_"illustration",_"band/artist logotype",_"Publisher/Studio logotype"];
  %SUBTAGPROP=		# [label,row,col_start,col_end,widget,extra_parameter]
	(	USLT => [	[_"Lang.",0,1,2,'EntrySimple',3],
				[_"Descr.",0,3,5],
				['',1,0,5,'EntryLyrics']
			],
		COMM => [	[_"Lang",0,1,2,'EntrySimple',3],
				[_"Descr.",0,3,5],
				['',1,0,5]
			],
		APIC => [	[_"MIME type",0,1,5],
				[_"Picture Type",1,1,5,'EntryCombo',$PICTYPE],
				[_"Description",2,1,5],
				['',3,0,5,'EntryCover']
			],
		GEOB => [	[_"MIME type",0,1,5],
				[_"Filename",1,1,5],
				[_"Description",2,1,5],
				['',3,0,5,'EntryBinary']	#FIXME load & save & launch?
			],
		TXXX => [	[_"Descr.",0,1,2],
				[_"Text",1,1,2]
			],
		WXXX => [	[_"Descr.",0,1,2],
				[_"URL",1,1,2]			#FIXME URL click
			],
		POPM => [	[_"email",0,1,4],
				[_"Rating",1,1,2],
				[_"counter",1,3,4]
			],
		USER => [	[_"Lang",0,1,2,'EntrySimple',3],
				[_"Terms of use",1,1,4]
			],
		OWNE => [	[_"Price paid",0,1,2],
				[_"Date of purchase",1,1,2],
				[_"Seller",2,1,2],
			],
		UFID => [	[_"Owner identifier",0,1,2],
				['',1,0,2,'EntryBinary']
			],
		PRIV => [	[_"Owner identifier",0,1,2],
				['',1,0,2,'EntryBinary']
			],
		'----' =>
			[	[_"Application",0,1,2],
				[_"Name",1,1,2],
				['',2,0,2],
			],
		'com.apple.iTunes----FMPS_Lyrics'=>
		[		[_"Application",0,1,2],
				[_"Name",1,1,2],
				['',2,0,2,'EntryLyrics'],
		],
	);
	$SUBTAGPROP{metadata_block_picture}=$SUBTAGPROP{APIC}; #for vorbis pictures
}
use base 'Gtk2::Frame';

sub new
{	my ($class,$values,$key,$name,$type,$realkey) = @_;
	my $self = bless Gtk2::Frame->new($name), $class;
	my $table=Gtk2::Table->new(1, 4, 0);
	$self->add($table);
	my $prop= $SUBTAGPROP{$key};
	$prop||= $SUBTAGPROP{$realkey} if $realkey;
	my $row=0;
	my $subtag=0;
	for my $t (split //,$type)
	{	my $val=$$values[$subtag]; $val='' unless defined $val;
		my ($name,$frow,$cols,$cole,$widget,$param)=
		($prop) ? @{ $prop->[$subtag] }
			: (_"unknown",$row++,1,5,undef,undef);
		unless ($widget)
		{	($widget,$param)=@{ $DataType{$t} };
		}
		$subtag++;
		if ($name ne '')
		{	my $label=Gtk2::Label->new($name);
			$table->attach($label,$cols-1,$cols,$frow,$frow+1,'shrink','shrink',1,1);
		}
		$widget=$widget->new( $val,$param );
		push @{ $self->{widgets} },$widget;
		$table->attach($widget,$cols,$cole,$frow,$frow+1,['fill','expand'],'shrink',1,1);
	}
	if    ($key eq 'APIC') { $self->{widgets}[3]->set_mime_entry($self->{widgets}[0]); }

	return $self;
}

sub return_value
{	my $self=shift;
	my @values;
	for my $w ( @{ $self->{widgets} } )
	{	my @v=$w->return_value;
		$self->{changed}=1 if $w->{changed};
		push @values,@v;
	}
	return @values;
}

package EntryBinary;
use Gtk2;
use base 'Gtk2::Button';

sub new
{	my $class = shift;
	my $self = bless Gtk2::Button->new(_"View binary data ..."), $class;
	$self->{init}=$self->{value}=shift;
	$self->signal_connect(clicked => \&view);
	return $self;
}
sub return_value
{	my $self=shift;
	#$self->{changed}=1 if $self->{value} ne $self->{init};
	return $self->{value};
}
sub view
{	my $self=$_[0];
	my $dialog = Gtk2::Dialog->new (_"View Binary", $self->get_toplevel,
				'destroy-with-parent',
				'gtk-close' => 'close');
	$dialog->set_default_response ('close');
	my $text;
	my $offset=0;
	while (my $b=substr $self->{value},$offset,16)
	{	$text.=sprintf "%08x  %-48s", $offset, join ' ',unpack '(H2)*',$b;
		$offset+=length $b;
		$b=~s/[^[:print:]]/./g;	#replace non-printable with '.'
		$text.="   $b\n";
	}
	my $textview=Gtk2::TextView->new;
	my $buffer=$textview->get_buffer;
	$buffer->set_text($text);
	$textview->modify_font(Gtk2::Pango::FontDescription->from_string('Monospace'));
	$textview->set_editable(0);

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never', 'automatic');
	$sw->add($textview);
	$dialog->vbox->add($sw);
	$dialog->show_all;
	$dialog->signal_connect( response => sub { $_[0]->destroy; });
}

package EntryCover;
use Gtk2;
use base 'Gtk2::HBox';

sub new
{	my $class = shift;
	my $self = bless Gtk2::HBox->new, $class;
	$self->{init}=$self->{value}=shift;
	my $img=$self->{img}=Gtk2::Image->new;
	my $vbox=Gtk2::VBox->new;
	my $eventbox=Gtk2::EventBox->new;
	$eventbox->add($img);
	$self->add($_) for $eventbox,$vbox;
	my $label=$self->{label}=Gtk2::Label->new;
	my $Bload=::NewIconButton('gtk-open',_"Replace...");
	my $Bsave=::NewIconButton('gtk-save-as',_"Save as...");
	$vbox->pack_start($_,0,0,2) for $label,$Bload,$Bsave;
	$Bload->signal_connect(clicked => \&load_cb);
	$Bsave->signal_connect(clicked => \&save_cb);
	$eventbox->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb);
	$self->{Bsave}=$Bsave;
	::set_drag($self, dest => [::DRAG_FILE,\&uri_dropped]);

	$self->set;

	return $self;
}
sub set_mime_entry
{	my $self=shift;
	$self->{mime_entry}=shift;
	$self->update_mime;
}
sub return_value
{	my $self=shift;
	$self->{changed}=1 if $self->{value} ne $self->{init} && length $self->{value};
	return $self->{value};
}
sub set
{	my $self=shift;
	my $label=$self->{label};
	my $Bsave=$self->{Bsave};
	my $length=length $self->{value};
	unless ($length) { $label->set_text(_"empty"); $Bsave->set_sensitive(0); return; }
	my $loader= GMB::Picture::LoadPixData( $self->{value} ,'-150');
	my $pixbuf;
	if (!$loader)
	{  $label->set_text(_"error");
	   $Bsave->set_sensitive(0);
	   ($self->{ext},$self->{mime})=('','');
	}
	else
	{ $pixbuf=$loader->get_pixbuf;
	  $Bsave->set_sensitive(1);
	  if ($Gtk2::VERSION >= 1.092)
	  {	my $h=$loader->get_format;
		$self->{ext} =$h->{extensions}[0];
		$self->{mime}=$h->{mime_types}[0];
	  }
	  else
	  {	($self->{ext},$self->{mime})=_identify_pictype($self->{value});
	  }
	  $label->set_text("$loader->{w} x $loader->{h} ($self->{ext} $length bytes)");
	}
	my $img=$self->{img};
	$img->set_from_pixbuf($pixbuf);
	$self->update_mime if $self->{mime_entry};
	$img->parent->{pixdata}=$self->{value}; #for zoom on click
}
sub uri_dropped
{	my $self=$_[0];
	my ($file)=split /\x0d\x0a/,$_[2];
	if ($file=~s#^file://##)
	{	$self->load_file($file)
	}
	#else #FIXME download http link
}
sub load_file
{	my ($self,$file)=@_;
	my $size=(stat $file)[7];
	my $fh; my $buffer;
	open $fh,'<',$file or return;
	binmode $fh;
	$size-=read $fh,$buffer,$size;
	close $fh;
	return unless $size==0;
	$self->{value}=$buffer;
	$self->set;
}
sub load_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $file=::ChoosePix();
	$self->load_file($file) if defined $file;
}
sub save_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	return unless length $self->{value};
	my $file=::ChooseSaveFile($self->{window},_"Save picture as",undef,'picture.'.$self->{ext});
	return unless defined $file;
	open my$fh,'>',$file or return;
	print $fh $self->{value};
	close $fh;
}

sub update_mime
{	my $self=shift;
	return unless $self->{mime};
	$self->{mime_entry}->set_text($self->{mime});
}

sub _identify_pictype	#used only if $Gtk2::VERSION < 1.092
{	$_[0]=~m/^\xff\xd8\xff\xe0..JFIF\x00/s && return ('jpg','image/jpeg');
	$_[0]=~m/^\x89PNG\x0D\x0A\x1A\x0A/ && return ('png','image/png');
	$_[0]=~m/^GIF8[79]a/ && return ('gif','image/gif');
	$_[0]=~m/^BM/ && return ('bmp','image/bmp');
	return ('','');
}

package EntryLyrics;
use Gtk2;
use base 'Gtk2::Button';

sub new
{	my $class = shift;
	my $self = bless Gtk2::Button->new(_"Edit Lyrics ..."), $class;
	$self->{init}=$self->{value}=shift;
	$self->signal_connect(clicked => \&edit);
	return $self;
}
sub return_value
{	my $self=shift;
	$self->{changed}=1 if $self->{value} ne $self->{init};
	return $self->{value};
}
sub edit
{	my $self=$_[0];
	if ($self->{dialog}) { $self->{dialog}->present; return }
	$self->{dialog}=
	::EditLyricsDialog( $self->get_toplevel, $self->{value},undef, sub
		{	my $lyrics=shift;
			$self->{value}=$lyrics if defined $lyrics;
			$self->{dialog}=undef;
		});
}
1;
