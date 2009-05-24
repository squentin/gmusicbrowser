# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
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
}
use strict;
use warnings;


package ReadTag;

our %FORMATS;
my (%TAGKEYS,%LYRICS3KEYS,%APEKEYS);

INIT
{
 %FORMATS=
 (	mp3	=> ['Tag::MP3',	'mp3 l{layer}v{versionid}',	[qw/ID3v2 APE lyrics3v2 ID3v1/],],
	ogg	=> ['Tag::OGG', 'ogg v{version}',		['vorbis'],],
	flac	=> ['Tag::Flac','flac',				['vorbis'],],
	mpc	=> ['Tag::MPC',	'mpc v{version}',		[qw/APE ID3v2 lyrics3v2 ID3v1/],],
	ape	=> ['Tag::APEfile','ape v{version}',		[qw/APE ID3v2 lyrics3v2 ID3v1/],],
	wv	=> ['Tag::WVfile','wv v{version}',		[qw/APE ID3v1/],],
);
#$FORMATS{wvc}=$FORMATS{wv};

 %TAGKEYS=
 (TIT2 => ::SONG_TITLE,		title		=> ::SONG_TITLE,
  TPE1 => ::SONG_ARTIST,	artist		=> ::SONG_ARTIST,
  TALB => ::SONG_ALBUM,		album		=> ::SONG_ALBUM,
  TRCK => ::SONG_TRACK,		tracknumber	=> ::SONG_TRACK,
  TYER => ::SONG_DATE,		year		=> ::SONG_DATE,
  TDRC => ::SONG_DATE,		date		=> ::SONG_DATE,
  COMM => ::SONG_COMMENT,	description	=> ::SONG_COMMENT,
  comments => ::SONG_COMMENT,	comment		=> ::SONG_COMMENT,
  TCON => ::SONG_GENRE,		genre		=> ::SONG_GENRE,
  TPOS => ::SONG_DISC,		discnumber	=> ::SONG_DISC,
  TIT3 => ::SONG_VERSION,	version		=> ::SONG_VERSION,
  TOPE => ::SONG_AUTHOR,	author		=> ::SONG_AUTHOR,
 );

 %APEKEYS= #http://www.ikol.dk/~jan/musepack/klemm/www.personal.uni-jena.de/~pfk/mpp/sv8/apetag.html
 ( Title => ::SONG_TITLE,	Artist=> ::SONG_ARTIST,		Album => ::SONG_ALBUM,
   Track => ::SONG_TRACK,	Comment=>::SONG_COMMENT,	Genre => ::SONG_GENRE,
   Year  => ::SONG_DATE,	'Record Date'=> ::SONG_DATE,
 );

 %LYRICS3KEYS=	#http://www.id3.org/lyrics3200.html
 ( ETT => ::SONG_TITLE,		EAR => ::SONG_ARTIST,		EAL => ::SONG_ALBUM,
   INF => ::SONG_COMMENT,	AUT => ::SONG_AUTHOR,
 );

}

sub Read
{	my ($aref,$file,$findlength)=@_;
	#$file=Glib->filename_from_unicode($file);
	return undef unless $file=~m/\.([^.]+)$/;
	my $format=$FORMATS{lc $1};
	return undef unless $format;
	my $filetag= eval { $format->[0]->new($file,$findlength); }; #filelength==1 -> may return estimated length (mp3 only)
	unless ($filetag) { warn $@ if $@; warn "can't read tags for $file\n"; return undef;}

	my @tag;
	my $formatstring=$format->[1];
	for my $t (@{$format->[2]})
	{if ($t eq 'vorbis')
	 {	for my $key ($filetag->listkeys)
		{	if ( defined (my $n=$TAGKEYS{lc $key}) )
			{	my @vals=$filetag->keyvalues($key);
				push @{ $tag[$n] },@vals;
			}
		}
	 }
	 elsif ($t eq 'ID3v1' && $filetag->{ID3v1})
	 {	my @id3v1=@{ $filetag->{ID3v1} };
		#warn "*$_*\n" for @id3v1;
		$id3v1[5]='' unless $id3v1[5];	# for ::SONG_TRACK, to ignore '0'
		for (::SONG_TITLE,::SONG_ARTIST,::SONG_ALBUM,::SONG_DATE,::SONG_COMMENT,::SONG_TRACK,::SONG_GENRE)
		  { push @{$tag[$_]},shift @id3v1; }
	 }
	 elsif ($t eq 'ID3v2')
	 {	my @id3v2s;
		push @id3v2s,$filetag->{ID3v2} if $filetag->{ID3v2};
		push @id3v2s,@{ $filetag->{ID3v2s} } if $filetag->{ID3v2s};
		for my $ID3v2 ( @id3v2s )
		{	for my $fname (qw/TIT2 TPE1 TALB TDRC TYER TRCK TPOS TIT3 COMM/)
			{	next unless exists $ID3v2->{frames}{$fname};
				my $i=($fname eq 'COMM')? 2 : 0;
				push @{ $tag[$TAGKEYS{$fname}] },$$_[$i] for @{ $ID3v2->{frames}{$fname} };
				#warn "/$$_[$i]/\n" for @{ $ID3v2->{$fname} };
			}
			if (exists $ID3v2->{frames}{TCON}) { push @{ $tag[$TAGKEYS{TCON}] },@$_ for @{ $ID3v2->{frames}{TCON} }; }
		}
	 }
	 elsif ($t eq 'APE' && $filetag->{APE})
	 {	while (my ($k,$v)=each %{ $filetag->{APE}{item} })
		{	push @{$tag[ $APEKEYS{$k} ]},@$v if exists $APEKEYS{$k};
		}
	 }
	 elsif ($t eq 'lyrics3v2' && $filetag->{lyrics3v2})
	 {	while (my ($k,$v)=each %{ $filetag->{lyrics3v2}{fields} })
			{	push @{$tag[ $LYRICS3KEYS{$k} ]},$v if exists $LYRICS3KEYS{$k};
			}
	 }
	}
	my $estimated;
	if (my $info=$filetag->{info})
	{	$estimated=$info->{estimated};
		if ( exists $info->{seconds}
		     && ( !$estimated || ($findlength && !$$aref[::SONG_LENGTH]) )
		   )	#don't replace existing values for length and bitrate by estimated values (for mp3)
		{	$$aref[::SONG_LENGTH]= sprintf '%.0f',$info->{seconds};
			my $bitrate=$info->{bitrate} || $info->{bitrate_nominal};	#FIXME
			$$aref[::SONG_BITRATE]=sprintf '%.0f',$bitrate/1000;
		}
		$formatstring=~s/{(\w+)}/$info->{$1}/g;
		$$aref[::SONG_FORMAT]=$formatstring;
		$$aref[::SONG_CHANNELS]=$info->{channels};
		$$aref[::SONG_SAMPRATE]=$info->{rate};
	}
	SetTags($aref,\@tag);

	return ($estimated? 2 : 1);
}

sub SetTags
{	my ($aref,$tags)=($_[0],$_[1]);
	for my $n (@::TAGSREADFROMTAGS)
	{	$$aref[$n]=undef;
		my $tag=$tags->[$n];
		next unless $tag;
		s/\s+$// for @$tag;
		tr/\x1D\x00//d for @$tag;
		if ($n==::SONG_GENRE)
		{	my %genres;
			$genres{ucfirst $_}=undef for grep $_ ne '', @$tag;
			$$aref[$n]=join("\x00",sort keys %genres)."\x00";
			next;
		}
		if ($n==::SONG_COMMENT)
		{	my %h;
			$$aref[$n]=join ' ',			 #FIXME join with \n ?
				grep !($_ eq '' || $h{$_}++), @$tag; #remove duplicated or empty comments
			next;
		}
		my $val;
		for (@$tag)
		{	if ($n==::SONG_TRACK)
			  { s#(\d+)/\d+#$1#; $val=sprintf '%02d',$_ if m/^\d+$/; }
			elsif ($n==::SONG_DATE) { $val=$1 if m/(\d{4})/;  }
			#else { $val=$_ if defined $_; }
			else { $val=$_; }
			last if defined $val;
		}
		$$aref[$n]=$val;
	}
	unless ($$aref[::SONG_ALBUM])
	{	$$aref[::SONG_ALBUM]='<Unknown>';
		$$aref[::SONG_ALBUM].=' ('.$$aref[::SONG_ARTIST].')' if $$aref[::SONG_ARTIST];
	}
	$$aref[::SONG_ARTIST]='<Unknown>' unless $$aref[::SONG_ARTIST];
}

sub FindTrueMP3Length
{	my $file=Glib->filename_from_unicode(shift);
	my $mp3=Tag::MP3->new($file,2);	#the 2 force return true length only
	unless ($mp3 && $mp3->{info}) {warn "can't find length for $file, probably invalid file.\n";return undef;}
	my $s= sprintf '%.0f',$mp3->{info}{seconds};
	my $br=sprintf '%.0f',$mp3->{info}{bitrate};
	return ($s,$br);
}

sub PixFromMusicFile
{	my $file=$_[0];
	#$file=Glib->filename_from_unicode($file);
	return undef unless -r $file;
	my $pix;
	if ($file=~m/\.mp3$/i)
	{	my $tag=Tag::MP3->new($file,0);
		unless ($tag) {warn "can't read tags for $file\n";return undef;}
		unless ($tag->{ID3v2} && $tag->{ID3v2}{frames}{APIC})
			{warn "no picture found in $file\n";return undef;}
		$pix=$tag->{ID3v2}{frames}{APIC};
	}
	elsif ($file=~m/\.flac$/i)
	{	my $tag=Tag::Flac->new($file);
		unless ($tag) {warn "can't read tags for $file\n";return undef;}
		unless ($tag->{pictures})
			{warn "no picture found in $file\n";return undef;}
		$pix=$tag->{pictures};
	}
	else { return undef }
	my $nb=0;
	#if (@$pix>1) {$nb=}	#FIXME if more than one picture in tag, use $pix->[$nb][1] to choose
	return $pix->[$nb][3];
}

sub GetLyrics
{	my $ID=$_[0];
	my $file=$::Songs[$ID][::SONG_PATH].::SLASH.$::Songs[$ID][::SONG_FILE];
	return undef unless -r $file;

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	my $lyrics;
	for my $t (@{$format->[2]})
	{	if ($t eq 'vorbis' && $tag->{comments}{lyrics}) #FIXME lYriCs
		{	$lyrics=$tag->{comments}{lyrics}[0];
		}
		elsif ($t eq 'APE' && $tag->{item}{Lyrics})
		{	$lyrics=$tag->{item}{Lyrics}[0];
		}
		elsif ($t eq 'ID3v2' && $tag->{ID3v2} && $tag->{ID3v2}{frames}{USLT})
		{	$lyrics=$tag->{ID3v2}{frames}{USLT};
			my $nb=0;
			#if (@$lyrics>1) {$nb=}	#FIXME if more than one lyrics in tag, use $lyrics->[$nb][0] or [1] to choose
			$lyrics=$lyrics->[$nb][2];
		}
		elsif ($t eq 'lyrics3v2' && $tag->{lyrics3v2} && $tag->{lyrics3v2}{fields}{LYR})
		{	$lyrics=$tag->{lyrics3v2}{fields}{LYR};
		}
		last if $lyrics;
	}
	warn "no lyrics found in $file\n" unless $lyrics;
	return $lyrics;
}

sub WriteLyrics
{	return if $::CmdLine{ro} || $::CmdLine{rotags};
	my ($ID,$lyrics)=@_;
	my $file=$::Songs[$ID][::SONG_PATH].::SLASH.$::Songs[$ID][::SONG_FILE];
	return undef unless -r $file;

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	if ($format->[2][0] eq 'vorbis')
	{	if (exists $tag->{comments}{lyrics})
			{ $tag->edit('lyrics',0,$lyrics); }
		else	{ $tag->add('lyrics',$lyrics); }
	}
	elsif ($format->[2][0] eq 'APE')
	{	my $ape = $tag->{APE} || $tag->new_APE;
		if (exists $ape->{item}{lyrics})
			{ $ape->edit('Lyrics',0,$lyrics); }
		else	{ $ape->add('Lyrics',$lyrics); }
	}
	elsif ($format->[2][0] eq 'ID3v2')
	{	my $id3v2 = $tag->{ID3v2} || $tag->new_ID3v2;
		if ($tag->{ID3v2}{frames}{USLT})
		{	my $nb=0; #FIXME
			$id3v2->edit('USLT',$nb,'','',$lyrics);
		}
		else { $id3v2->add('USLT','','',$lyrics); }
	}
	else {return undef}
	$tag->{errorsub}=\&::Retry_Dialog;
	$tag->write_file
}

package MassTag;
use Gtk2;
use constant
{	TRUE  => 1, FALSE => 0,
};

my @FORMATS; my %WIDTH;
INIT
{
 %WIDTH=
 (	::SONG_TRACK,4,
	::SONG_DISC, 4,
	::SONG_DATE, 6,
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
 );

}

use base 'Gtk2::VBox';
sub new
{	my ($class,$window,@IDs) = @_; #FIXME remove duplicates in @IDs
	my $self = bless Gtk2::VBox->new, $class;
	$self->{window}=$window;

	my $table=Gtk2::Table->new (6, 2, FALSE);
	my $row=0;
	my %frames;
	$self->{frames}=\%frames;
	$self->{pf_frames}={};
	$self->{IDs}=\@IDs;

	{	my %h; $h{$::Songs[$_][::SONG_UPATH]}=undef for @IDs;
		my $text= ::__("%d file in {folder}","%d files in {folder}",scalar@IDs);
		my $folder=(keys %h==1) ? '<small>'.::PangoEsc( $::Songs[$IDs[0]][::SONG_UPATH] ).'</small>'
					: ::__("one folder","different folders",scalar(keys %h));
		$text= ::__x($text,folder => $folder);
		my $labelfile = Gtk2::Label->new;
		$labelfile->set_markup($text);
		$labelfile->set_selectable(TRUE);
		$labelfile->set_line_wrap(TRUE);
		$self->pack_start($labelfile, FALSE, TRUE, 2);
	}

	no warnings 'uninitialized';
	for my $field (::SONG_ARTIST,::SONG_ALBUM,::SONG_DISC,::SONG_DATE,::SONG_COMMENT,::SONG_GENRE)
	{	my $check=Gtk2::CheckButton->new($::TagProp[$field][0]);
		my $combo=Gtk2::Combo->new;
		my %value;
		if ($field==::SONG_GENRE)
		{	$value{$_}++ for map split(/\x00/, $::Songs[$_][::SONG_GENRE]), @IDs;
			$combo=EntryList->new(undef,'g');
			$combo->addvalues( grep($value{$_}==@IDs, keys %value) );
			$frames{$field}=$combo;
		}
		else
		{	$value{ $::Songs[$_][$field] }++ for @IDs;	#check undef
			if ($field==::SONG_ARTIST) { delete $value{'<Unknown>'}; }
			elsif ($field==::SONG_ALBUM) {delete $value{$_} for grep m/^<Unknown>/, keys %value; }
			@_=sort { $value{$b} <=> $value{$a} } keys %value;	#sort values by their frequency
			if	($field==::SONG_ARTIST)	{push @_,sort keys %::Artist}
			#elsif	($field==::SONG_ALBUM)	{push @_,sort keys %::Album} #maybe not a good idea
			$combo->set_case_sensitive(TRUE);
			$combo->set_popdown_strings(@_);
			$combo->entry->set_text('') unless ( $value{$_[0]} > @IDs/3 );
			$frames{$field}=$combo->entry;
		}
		$combo->set_sensitive(FALSE);
		$check->{combo}=$combo;
		$check->signal_connect( toggled => sub
			{  my $check=$_[0];
			   my $active=$check->get_active;
			   $check->{combo}->set_sensitive($active);
			   $check->{addchk}->set_sensitive($active) if exists $check->{addchk};
			});
		$table->attach($check,0,1,$row,$row+1,'fill','shrink',1,1);
		$table->attach($combo,1,2,$row,$row+1,['fill','expand'],'shrink',1,1);
		if ($field==::SONG_COMMENT || $field==::SONG_GENRE)
		{	my $chk=Gtk2::CheckButton->new(_"Remove existing");
			$self->{add}{$field}=1;
			$chk->signal_connect( toggled => sub
				{	my $self=::find_ancestor($_[0],__PACKAGE__);
					$self->{add}{$field}=!($_[0]->get_active);
				});
			$table->attach($chk,2,3,$row,$row+1,'fill','shrink',1,1);
			$check->{addchk}=$chk;
			$chk->set_sensitive(FALSE);
		}
		$row++;
	}

	$self->pack_start($table, FALSE, TRUE, 2);
#short circuit if a LOT of songs : don't add file-specific tags, building the GUI would be too long anyway
return $self if @IDs>1000;
#######################################################
	::SortList(\@IDs,join(' ',::SONG_UPATH,::SONG_DISC,::SONG_TRACK,::SONG_UFILE));
	#edition of file-specific tags (track title)
	my $perfile_table=Gtk2::Table->new( scalar(@IDs), 6, FALSE);
	$self->{perfile_table}=$perfile_table;
	$row=0;
	for my $ID (@IDs)
	{	$row++;
		my $label=Gtk2::Label->new($::Songs[$ID][::SONG_UFILE]);
		$label->set_selectable(TRUE);
		$label->set_alignment(0,0.5);	#left-aligned
		$perfile_table->attach($label,7,8,$row,$row+1,'fill','shrink',1,1); #filename
	}
	$self->add_column(::SONG_TRACK);
	$self->add_column(::SONG_TITLE);

	my $BSelFields=Gtk2::Button->new(_"Select fields");
	{	my $menu=Gtk2::Menu->new;
		my $menu_cb=sub {$self->add_column($_[1])};
		for my $f (::SONG_DISC,::SONG_TRACK,::SONG_TITLE,::SONG_ARTIST,::SONG_ALBUM,::SONG_DATE,::SONG_COMMENT)
		{	my $item=Gtk2::CheckMenuItem->new($::TagProp[$f][0]);
			$item->set_active(1) if $self->{'pfcheck'.$f};
			$item->signal_connect(activate => $menu_cb,$f);
			$menu->append($item);
		}
		$menu->show_all;
		$BSelFields->signal_connect( button_press_event => sub
			{	$::LEvent=$_[1];
				$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button, $::LEvent->time);
			});
		#$self->pack_start($menubar, FALSE, FALSE, 2);
		#$perfile_table->attach($menubar,7,8,0,1,'fill','shrink',1,1);
	}

	my $Btools=Gtk2::Button->new('tools');
	{	my $menu=Gtk2::Menu->new;
		my $menu_cb=sub {$self->tool($_[1])};
		for my $ref
		(	[_"Capitalize",sub { ucfirst $_[1]; }],
		)
		{	my $item=Gtk2::MenuItem->new($ref->[0]);
			$item->signal_connect(activate => $menu_cb,$ref->[1]);
			$menu->append($item);
		}
		$menu->show_all;
		$Btools->signal_connect( button_press_event => sub
			{	$::LEvent=$_[1];
				$menu->popup(undef,undef,\&::menupos,undef,$::LEvent->button, $::LEvent->time);
			});
	}

	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic', 'automatic');
	$sw->add_with_viewport($perfile_table);
	$self->pack_start($sw, TRUE, TRUE, 4);
########################################################### Autofill
	my $Bautofill=Gtk2::OptionMenu->new;
	my $menu=Gtk2::Menu->new;
	$menu->append(Gtk2::MenuItem->new(_"Auto fill based on filenames ..."));
	my @files=map $::Songs[$_][::SONG_UFILE], @IDs;
	s/\.[^.]*$//i for @files;
	my $found;
	for my $i (0..$#FORMATS)
	{	next if @files/2>(grep m/$FORMATS[$i][1]/, @files);
		my $formatname=$FORMATS[$i][0];
		$formatname=~s/%([taldnyCV%])/$::ReplaceFields{$1}[1]/g;
		my $item=Gtk2::MenuItem->new_with_label($formatname);
		$item->{'index'}=$i;
		$item->signal_connect(activate => \&autofill_cb,$self);
		$menu->append($item);
		$found++;
	}
	$Bautofill->set_menu($menu);
	my $checkOBlank=Gtk2::CheckButton->new(_"Auto fill only blank fields");
	$self->{AFOBlank}=$checkOBlank;
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_start($_, FALSE, FALSE, 0) for $BSelFields,Gtk2::VSeparator->new,$Bautofill,$checkOBlank; #$Btools,
	$self->pack_start($hbox, FALSE, FALSE, 4);
###########################################################
	return $self;
}

sub add_column
{	my ($self,$field)=@_;
	if ($self->{'pfcheck'.$field})	#if already created -> toggle show/hide
	{	my @w=( $self->{'pfcheck'.$field}, @{ $self->{pf_frames}{$field} } );
		if ($w[0]->visible)	{ $_->hide for @w; }
		else			{ $_->show for @w; }
		return;
	}
	my $table=$self->{perfile_table};
	my $col=$table->{col}++;
	my $row=0;
	my $check=Gtk2::CheckButton->new($::TagProp[$field][0]);
	$self->{'pfcheck'.$field}=$check;
	$table->attach($check,$col,$col+1,$row,$row+1,'fill','shrink',1,1);
	$check->show;
	my @entrys;
	for my $ID ( @{$self->{IDs}} )
	{	$row++;
		my $ent=Gtk2::Entry->new;
		my $v=$::Songs[$ID][$field];
		$v=undef if $v && ($field==::SONG_ARTIST && $v eq '<Unknown>')
				|| ($field==::SONG_ALBUM && $v=~m/^<Unknown>/);
		$ent->set_text($v) if defined $v;
		$ent->set_sensitive(FALSE);
		$ent->signal_connect(focus_in_event=> \&scroll_to_entry);
		my $p=['fill','expand'];
		if (exists $WIDTH{$field})
		{	$ent->set_width_chars( $WIDTH{$field} );
			$p='fill';
		}
		$table->attach($ent,$col,$col+1,$row,$row+1,$p,'shrink',1,1);
		$ent->show;
		push @entrys,$ent;
	}
	$check->signal_connect( toggled => sub
		{  my $active=$_[0]->get_active;
		   $_->set_sensitive($active) for @entrys;
		});
	$self->{pf_frames}{$field}=\@entrys;
}

sub scroll_to_entry
{	my $ent=$_[0];
	if (my $sw=::find_ancestor($ent,'Gtk2::ScrolledWindow'))
	{	my ($x,$y,$w,$h)=$ent->window->get_geometry;
		$sw->get_hadjustment->clamp_page($x,$x+$w);
		$sw->get_vadjustment->clamp_page($y,$y+$h);
	};
	0;
}

sub autofill_cb
{	my ($menuitem,$self)=@_;
	my ($format,$pattern)=@{ $FORMATS[$menuitem->{'index'}] };
	my @fields= map $::ReplaceFields{$_}[2][0], grep $_ ne '%', $format=~m/%([taldnyCV%])/g;
	my $OBlank=$self->{AFOBlank}->get_active;
	my @vals;
	for my $ID (@{$self->{IDs}})
	{	my $file=$::Songs[$ID][::SONG_UFILE];
		$file=~s/\.[^.]*$//i;
		my @v=($file=~m/$pattern/);
		s/^ +//,s/ +$// for @v;
		@v=('')x scalar(@fields) unless @v;
		my $n=0;
		push @{$vals[$n++]},$_ for @v;
	}
	for my $f (@fields)
	{	my $varray=shift @vals;
		my %h; $h{$_}=undef for @$varray; delete $h{''};
		if ( (keys %h)==1 )
		{	my $entry=$self->{frames}{$f};
			next unless $entry && $entry->is_sensitive;
			next if $OBlank && $entry->get_text ne '';
			$entry->set_text(keys %h);
		}
		else
		{	my $entrys=$self->{pf_frames}{$f};
			next unless $entrys;
			for my $e (@$entrys)
			{ my $v=shift @$varray;
			  next if $OBlank && $e->get_text ne '';
			  $e->set_text($v) if $e->is_sensitive && $v ne '';
			}
		}
	}
}

sub tool
{	my ($self,$sub)=@_;
	my $OBlank=$self->{AFOBlank}->get_active;
	my $IDs=$self->{IDs};
	while (my($f,$wdgt)=each %{$self->{frames}})
	{	next if $f==::SONG_GENRE;
		my $v=$wdgt->get_text;
		next if !$wdgt->is_sensitive || $OBlank && $v ne '';
		$v=&$sub($f,$v);
		$wdgt->set_text($v) if defined $v;
	}
	while (my($f,$entrys)=each %{$self->{pf_frames}})
	{	for my $e (@$entrys)
		{	my $v=$e->get_text;
			next if !$e->is_sensitive || $OBlank && $v ne '';
			$v=&$sub($f,$v);
			$e->set_text($v) if defined $v;
		}
	}
}

sub save
{	no warnings 'uninitialized';
	my ($self,$finishsub)=@_;
	my $IDs=$self->{IDs};
	my %set;
	while ( my ($f,$wdgt)=each %{$self->{frames}} )
	{	next unless $wdgt->is_sensitive;
		$set{$f}=($f==::SONG_GENRE)? [$wdgt->return_value] : $wdgt->get_text;
		warn "$::TagProp[$f][0]=$set{$f}\n" if $::debug;
	}
	while ( my ($f,$wdgt)=each %{$self->{pf_frames}} )
	{	next unless $$wdgt[0]->is_sensitive;
		my $default;
		if (exists $set{$f})	#if both per_file and one_for_all_files
		{	$default=$set{$f};
			$set{$f}={};
		}
		for my $ID (@$IDs)
		{  my $v=(shift @$wdgt)->get_text;
		   $v=$default if defined $default && $v eq '';
		   $v='' if $v eq $::Songs[$ID][$f];	#don't write if not modified
		   $set{$f}{$ID}=$v;			#won't be written if eq ''
		}
	}

	$self->set_sensitive(FALSE);
	my $progressbar = Gtk2::ProgressBar->new;
	$self->pack_start($progressbar, FALSE, TRUE, 0);
	$progressbar->show_all;
	my $IDcount=0;
	my $errorsub=sub
	{	my $err=shift;
		my $abort;
		$abort=_"Abort mass-tagging" if (@$IDs-$IDcount)>1;
		my $ret=::Retry_Dialog($err,$self->{window},$abort);
		$self->{abort}=1 if $ret eq 'abort';
		return $ret;
	};
	unless (keys %set) { &$finishsub(); return}
	Glib::Idle->add( sub	#FIXME without a closure would be cleaner
	 {	my $ID=$IDs->[$IDcount];
		my @modif;
		while (my ($field,$val)=each %set)
		{	if (ref $val eq 'HASH') { $val=$$val{$ID}; next if $val eq ''; }
			push @modif,[$field,$self->{add}{$field},$val];
		}
		SimpleTagWriting::set($ID,\@modif,$errorsub) if @modif;
		::IdleCheck($ID);
		$progressbar->set_fraction(++$IDcount/@$IDs);
		return 1 unless $self->{abort} || $IDcount>$#$IDs;
		&$finishsub();
		return 0;  #remove idle
	 });
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
	my $row=0;
	no warnings 'uninitialized';
	for my $field (::SONG_TITLE,::SONG_ARTIST,::SONG_ALBUM,::SONG_TRACK,::SONG_DISC,::SONG_DATE,::SONG_COMMENT,::SONG_GENRE)
	{	my $label=Gtk2::Label->new($::TagProp[$field][0]);
		my $entry=($field==::SONG_GENRE)? EntryList->new(undef,'g') : Gtk2::Entry->new;
		#$combo->set_case_sensitive(TRUE);
		#if	($field==::SONG_ARTIST)	{ $combo->set_popdown_strings(sort keys %::Artist); }
		#elsif	($field==::SONG_ALBUM)	{ $combo->set_popdown_strings(sort keys %::Album); }
		my $v=$::Songs[$ID][$field];
		$v=undef if $v && ($field==::SONG_ARTIST && $v eq '<Unknown>')
				|| ($field==::SONG_ALBUM && $v=~m/^<Unknown>/);
		$entry->set_text($v) if defined $v;
		$table->attach($label,0,1,$row,$row+1,'fill','shrink',1,1);
		$table->attach($entry,1,2,$row,$row+1,['fill','expand'],'shrink',1,1);
		$row++;
		$self->{fields}{$field}=$entry;
	}

	my $advanced=Gtk2::Button->new(_"Advanced Tag Editing".' ...');
	$advanced->signal_connect( clicked => \&advanced_cb );

	$self->pack_start($labelfile,FALSE,FALSE,1);
	$self->pack_start($table, FALSE, TRUE, 2);
	$self->pack_end($advanced, FALSE, FALSE, 2);

	return $self;
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
	{ my ($dialog,$response)=@_;
	  if ($response eq 'ok')
	  {	$edittag->save;
		::SongCheck($ID);
		no warnings 'uninitialized';
		#refresh the fields
		for my $field (::SONG_TITLE,::SONG_ARTIST,::SONG_ALBUM,::SONG_TRACK,::SONG_DISC,::SONG_DATE,::SONG_COMMENT,::SONG_GENRE)
		{	$self->{fields}{$field}->set_text( $::Songs[$ID][$field] );
		}
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
	{	if ($field==::SONG_GENRE)
		{	my @vals=$entry->return_value;
			next unless $entry->{changed};
			push @modif,[$field,0,\@vals];
		}
		else
		{	my $val=$entry->get_text;
			my $old=$::Songs[$ID][$field];
			$old='' unless defined $old;
			next if $val eq $old;
			push @modif,[$field,0,$val];
		}
	}
	SimpleTagWriting::set($ID,\@modif,$errorsub) if @modif;
}

package SimpleTagWriting;
use constant
{	K_VORBIS => 0, K_ID3V2 => 1, K_APE => 2, K_ID3V1 => 3,
};
my %TAGCODE;
INIT
{
 %TAGCODE=
(::SONG_ARTIST, [qw/artist TPE1 Artist 1/],
 ::SONG_ALBUM,	[qw/album TALB Album 2/],
 ::SONG_DATE,	[qw/date TYER Year 3/],
 ::SONG_COMMENT,[[qw/description comment comments/],qw/COMM-- Comment 4/],
 ::SONG_GENRE,	[qw/genre TCON Genre 6/],
 ::SONG_DISC,	[qw/discnumber TPOS discnumber/],
 ::SONG_VERSION,[qw/version TIT3 Subtitle/],
 ::SONG_TITLE,	[qw/title TIT2 Title 0/],
 ::SONG_TRACK,	[qw/tracknumber TRCK Track 5/],
 'replaygain-track-gain' => [qw/replaygain_track_gain TXXX-replaygain_track_gain replaygain_track_gain/],
 'replaygain-track-peak' => [qw/replaygain_track_peak TXXX-replaygain_track_peak replaygain_track_peak/],
 'replaygain-album-gain' => [qw/replaygain_album_gain TXXX-replaygain_album_gain replaygain_album_gain/],
 'replaygain-album-peak' => [qw/replaygain_album_peak TXXX-replaygain_album_peak replaygain_album_peak/],
 'replaygain-reference-level' => [qw/replaygain_reference_level TXXX-reference_level replaygain_reference_level/],
);
}

sub set
{	my ($ID,$modif,$errorsub) = @_;

	if ($::Options{TAG_nowrite_mode}) #no-write mode
	{	my $song=$::Songs[$ID];
		my @newtag;
		for my $n (@::TAGSREADFROMTAGS)
		{	my $v=$song->[$n];
			$newtag[$n]=  $n==::SONG_GENRE
					? [ split /\x00/,$v ]
					: [defined $v ? $v : ()];
		}
		my @changed; my $aa;
		for my $aref (@$modif)
		{	my ($field,$add,@vals)=@$aref;
			next unless $field=~m/^\d+$/; #ignore fields that are not in @::Songs
			@vals=@{$vals[0]} if ref $vals[0];
			$newtag[$field]=[] unless $add;
			push @{$newtag[$field]}, @vals;
			push @changed,$field;
			$aa=1 if $field==::SONG_ALBUM || $field==::SONG_ARTIST || $field==::SONG_DATE;# ||$field==::SONG_LENGTH;
		}
		my @old=@$song;
		ReadTag::SetTags($song,\@newtag);
		if ($aa) { ::RemoveAA($ID,\@old); ::AddAA($ID); }
		::SongChanged($ID, @changed );
		return 1;
	}

	my $file=$::Songs[$ID][::SONG_PATH].::SLASH.$::Songs[$ID][::SONG_FILE];

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$ReadTag::FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	my $maintag=$format->[2][0];
	if ($maintag eq 'ID3v2' || $tag->{ID3v1})
	{	my $id3v1 = $tag->{ID3v1} || $tag->new_ID3v1;
		for my $aref (@$modif)
		{	my ($field,$add,@vals)=@$aref;
			my $i=$TAGCODE{$field}[K_ID3V1];
			$id3v1->[$i]=$vals[0] if defined $i;
		}
	}
	if ($maintag eq 'ID3v2' || $tag->{ID3v2})
	{	my $id3v2 = $tag->{ID3v2} || $tag->new_ID3v2;
		for my $aref (@$modif)
		{	my ($field,$add,@vals)=@$aref;
			my ($key,@extra)=split /-/,$TAGCODE{$field}[K_ID3V2],-1; #-1 to keep empty trailing fields #COMM-- => key="COMM" and @extra=("","")
			@vals=@{$vals[0]} if ref $vals[0];
			unshift @vals,@extra;
			unless ($add)
			{	if (my $subkey=$extra[0]) #for TXXX fields with a non-null description => remove only those with same description
				{	my $frames= $id3v2->{frames}{$key};
					if ($frames) { $id3v2->remove($key,$_) for grep $frames->[$_] && $frames->[$_][0] eq $subkey, 0..$#$frames; }
				}
				else { $id3v2->remove_all($key) unless $add; }
			}
			next if $field eq ::SONG_GENRE && !@vals;
			$id3v2->insert($key,@vals);
			if ($field eq ::SONG_DATE && $id3v2->{version}==4 && $vals[0]=~m/^\d{4}$/) { $id3v2->remove_all('TDRC'); $id3v2->insert('TDRC',$vals[0]); } #special-case: write a TDRC field for id3v2.4 in addition to TYER  #FIXME only support the yyyy format, could try to convert the date to yyyy-MM-ddTHH:mm:ss format
		}
	}
	if ($maintag eq 'vorbis')
	{	for my $aref (@$modif)
		{	my ($field,$add,@vals)=@$aref;
			@vals=@{$vals[0]} if ref $vals[0];
			my $key=$TAGCODE{$field}[K_VORBIS];
			if (ref $key)
			{	unless ($add) {$tag->remove_all($_) for @$key};
				$key=$key->[0];
			}
			$tag->remove_all($key) unless $add;
			$tag->insert($key,$_) for reverse @vals;
		}
	}
	if ($maintag eq 'APE' || $tag->{APE})
	{	my $ape = $tag->{APE} || $tag->new_APE;
		for my $aref (@$modif)
		{	my ($field,$add,@vals)=@$aref;
			my $key=$TAGCODE{$field}[K_APE];
			@vals=@{$vals[0]} if ref $vals[0];
			$ape->remove_all($key) unless $add;
			$ape->insert($key,$_) for reverse @vals;
		}
	}
	$tag->{errorsub}=$errorsub;
	$tag->write_file unless $::CmdLine{ro}  || $::CmdLine{rotags};
	return 1;
}

package EditTag;
use Gtk2;

use base 'Gtk2::VBox';

sub new
{	my ($class,$window,$ID) = @_;
	my $file=$::Songs[$ID][::SONG_PATH].::SLASH.$::Songs[$ID][::SONG_FILE];
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
	return undef unless $format and $format=$ReadTag::FORMATS{lc$format};
	$self->{filetag}=my $filetag= $format->[0]->new($file);
	unless ($filetag) {warn "can't read tags for $file\n";return undef;}

	my @boxes; $self->{boxes}=\@boxes;
	my @tags;
	for my $t (@{$format->[2]})
	{	if ($t eq 'vorbis')		{push @tags,$filetag;}
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
	TALB => [_"Album",4],
	TPOS => [_"Disc #",5],
	TRCK => [_"Track",6],
	TYER => [_"Date",7],
	COMM => [_"Comments",9],
	TCON => [_"Genres",8],
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
	lyrics		=> [_"Lyrics",14,'M'],
	author		=> [_"Original Artist",40],
  };
  my $ape_types=
  {	Title		=> [_"Title",1],
	Artist		=> [_"Artist",3],
	Album		=> [_"Album",4],
	Subtitle	=> [_"Subtitle",5],
	Publisher	=> [_"Publisher",14],
	Conductor	=> [_"Conductor",13],
	Track		=> [_"Track",6],
	Genre		=> [_"Genre",8],
	Composer	=> [_"Composer",12],
	Comment		=> [_"Comment",9],
	Copyright	=> [_"Copyright",80],
	Publicationright=> [_"Publication right",81],
	Year		=> [_"Year",7],
	'Debut Album'	=> [_"Debut Album",8],
  };
  my $lyrics3v2_types=
  {	LYR => [_"Lyrics",7,'M'],
	INF => [_"Info",6,'M'],
	AUT => [_"Author",5],
	EAL => [_"Album",4],
	EAR => [_"Artist",3],
	ETT => [_"Title",1],
  };


 %tagprop=
 (	ID3v2 =>{	addlist => [qw/COMM TPOS TIT3 TCON TXXX TOPE WOAR WXXX USLT APIC POPM PCNT GEOB/],
			default => [qw/COMM TIT2 TPE1 TALB TYER TRCK TCON/],
			fillsub => sub { $_[0]{frames} },
			typesub => sub {Tag::ID3v2::get_fieldtypes($_[1])},
			namesub => sub { 'id3v2.'.$_[0]{version} },
			types	=> $id3v2_types,
		},
	OGG =>	{	addlist => [qw/comments genre discnumber author/,''],
			default => [qw/title artist album tracknumber date comments genre/],
			fillsub => sub { $_[0]{comments} },
			name	=> 'vorbis comment',
			types	=> $vorbis_types,
			lckeys	=> 1,
		},
	APE=>	{	addlist => [qw/Title Subtitle Artist Album Genre Publisher Conductor Track Composer Comment Copyright Publicationright Year/,'Debut Album'],
			default => [qw/Title Artist Album Track Year Genre Comment/],
			fillsub => sub { $_[0]{item} },
			typesub => sub {($_[0] && defined $_[2])? $_[0]{item_type}{$_[1]}[$_[2]] : undef; },
			name	=> 'APE tag',
			types	=> $ape_types,
		},
	Lyrics3v2=>{	addlist => [qw/EAL EAR ETT INF AUT LYR/],
			default => [qw/EAL EAR ETT INF/],
			fillsub => sub { $_[0]{fields} },
			name	=> 'lyrics3v2 tag',
			types	=> $lyrics3v2_types,
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
	b => ['EntryBinary'],	#binary
	u => ['EntryBinary'],	#unknown -> binary
 );

}

sub new
{	my ($class,$tag,$option)=@_;
	my $tagtype=ref $tag; $tagtype=~s/^Tag:://i;
	unless ($tagprop{$tagtype}) {warn "unknown tag '$tagtype'\n"; return undef;}
	$tagtype=$tagprop{$tagtype};
	my $self=bless Gtk2::VBox->new,$class;
	my $name=$tagtype->{name} || &{ $tagtype->{namesub} }($tag);
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
		for my $frame (@$list)
		{	my $name=($frame ne '')? $tagtype->{types}{$frame}[TAGNAME] : _"(other)";
			$addlist->append_text($name);
		}
		$addlist->set_active(0);
		$addbut->signal_connect( clicked => sub
		{	my $fname=$list->[ $addlist->get_active ];
			$self->addrow($fname);
		});
	}
	my $toadd=&{ $tagtype->{fillsub} }($tag);
	for (@{$tagtype->{default}})
	{	$toadd->{$_}=undef unless defined $toadd->{$_};
	}
	my $lc=$tagtype->{lckeys};
	for my $fname (sort { ($tagtype->{types}{ ($lc? lc$a : $a) }[TAGORDER]||100)
			  <=> ($tagtype->{types}{ ($lc? lc$b : $b) }[TAGORDER]||100) } keys %$toadd)
	{	my $type;
		if (defined $toadd->{$fname})
		{	my $val=$toadd->{$fname};
			if (ref $val)
			{	my $nb=0;
				for my $v (@$val) { $self->addrow($fname,$nb++,$v); }
			}
			else { $self->addrow($fname,0,$val); }
		}
		else	{ $self->addrow($fname); }
	}

	return $self;
}


sub addrow
{	my ($self,$fname,$nb,$value)=@_;
	my $table=$self->{table};
	my $row=$table->{row}++;
	my ($widget,@Todel);
	my $tagtype=$self->{tagtype};
	my $type;
	$type=&{ $tagtype->{typesub} }($self->{tag},$fname,$nb) if $tagtype->{typesub};
	$type||='t';
	my $name=$tagtype->{types}{($tagtype->{lckeys}? lc$fname : $fname)}[TAGNAME]||$fname;
	if (length($type)>1)	#frame with sub-frames (id3v2)
	{	$value||=[];
		$widget=EntryMulti->new($value,$fname,$name,$type);
		$table->attach($widget,1,3,$row,$row+1,['fill','expand'],'shrink',1,1);
	}
	else	#simple case : 1 label -> 1 value
	{	$value=$value->[0] if ref $value;
		$value='' unless defined $value;
		my $label;
		$type=$DataType{$type}[0] || 'EntrySimple';
		my $param=$DataType{$type}[1];
		if ($fname eq '') { ($widget,$label)=EntryDouble->new($value); }
		else	{ $widget=$type->new($value,$param); $label=Gtk2::Label->new($name); }
		$table->attach($label,1,2,$row,$row+1,'shrink','shrink',1,1);
		$table->attach($widget,2,3,$row,$row+1,['fill','expand'],'shrink',1,1);
		@Todel=($label);
	}
	push @Todel,$widget;
	$widget->{fname}=$fname;
	$widget->{nb}=$nb;

	my $delbut=Gtk2::Button->new;
	$delbut->set_relief('none');
	$delbut->add(Gtk2::Image->new_from_stock('gtk-remove','menu'));
	$table->attach($delbut,0,1,$row,$row+1,'shrink','shrink',1,1);
	$delbut->signal_connect( clicked => sub
		{ $widget->{deleted}=1;
		  $table->remove($_) for $_[0],@Todel;
		  &{ $table->{ondelete} }($widget) if $table->{ondelete};
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
		warn "$tag removed" if $::debug;
		return 1;
	}
	my $modified;
	for my $w ( @{ $table->{widgets} } )
	{    if ($w->{deleted})
	     {	next unless defined $w->{nb};
		$tag->remove($w->{fname},$w->{nb});
		$modified=1; warn "$tag $w->{fname} deleted" if $::debug;
	     }
	     else
	     {	my @v=$w->return_value;
		next unless $w->{changed};
		if (defined $w->{nb})	{ $tag->edit($w->{fname},$w->{nb},@v); }
		else			{ $tag->add( $w->{fname},	  @v); }
		$modified=1; warn "$tag $w->{fname} modified" if $::debug;
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
	$filetag->{ID3v1}=my $id3v1 = [];
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
	$self->{fnameEntry}=Gtk2::Entry->new;
	return $self,$self->{fnameEntry};
}
sub return_value
{	my $self=shift;
	my $value=$self->get_text;
	$self->{fname}=$self->{fnameEntry}->get_text;
	$self->{changed}=1 if ($self->{fname} ne '' && $value ne '');
	return $value;
}

package EntryNumber;
use Gtk2;
use base 'Gtk2::SpinButton';

sub new
{	my ($class,$init,$max) = @_;
	my $self = bless Gtk2::SpinButton->new(
		Gtk2::Adjustment->new ($init||0, 0, $max||10000000, 1, 10, 1) ,10,0  )
		, $class;
	$self->{init}=$self->get_adjustment->get_value;
	return $self;
}
sub return_value
{	my $self=shift;
	my $value=$self->get_adjustment->get_value;
	$self->{changed}=1 if $value ne $self->{init};
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

package EntryList;
use Gtk2;
use base 'Gtk2::HBox';

sub new
{	my ($class,undef,$list) = @_;
	my $self = bless Gtk2::HBox->new, $class;
	$self->{hlist}={};
	my $vbox=Gtk2::VBox->new;
	my $bbox=Gtk2::HButtonBox->new;
	$bbox->set_layout('start');
	my $addbut=::NewIconButton('gtk-add',_"Add");
	my $rmbut=::NewIconButton('gtk-remove',_"Remove");
	$bbox->pack_start($_,0,1,0) for $addbut,$rmbut;
	my $combo=Gtk2::Combo->new;#my $combo=Gtk2::ComboBoxEntry->new_text;
	if ($list eq 'g')	#fill popdown strings with all genres present in library
	{	#$combo->append_text($_) for ::GetGenresList;
		$combo->set_popdown_strings(@{ ::GetGenresList() });
	}
	my $entry=$combo->entry;#my $entry=$combo->child;
	$entry->set_text('');
	#$entry->set_width_chars(4);
	$vbox->pack_start($_,::FALSE,::FALSE,0) for $combo,$bbox;
	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	 my $sw=Gtk2::ScrolledWindow->new;
	 $sw->set_shadow_type('etched-in');
	 $sw->set_policy('never','automatic');
	 $sw->add($treeview);
	 $sw->set_size_request(-1, 3*$entry->size_request->height ); #FIXME find a better way to get ~3 rows visible
	$self->pack_start($_,::TRUE,::TRUE,0) for $sw,$vbox;

	my $column=Gtk2::TreeViewColumn->new_with_attributes('', Gtk2::CellRendererText->new,'text',0);
	$treeview->append_column($column);
	$treeview->set_headers_visible(0);
	$rmbut->set_sensitive(0);
	$treeview->get_selection->signal_connect (changed => sub
		{	$rmbut->set_sensitive($_[0]->count_selected_rows);
			1;
		});
	$entry->signal_connect( activate => \&add_entry_text_cb);
	$addbut->signal_connect( clicked => \&add_entry_text_cb);
	$rmbut->signal_connect( clicked => sub
		{	my ($path)=$treeview->get_selection->get_selected_rows;
			my $iter=$store->get_iter($path);
			delete $self->{hlist}{ $store->get($iter,0) };
			$store->remove($iter);
			1;
		});

	$self->{entry}=$entry;
	$self->{store}=$store;
	#$self->{init}=$init;	#initial values are passed with the 'addvalues' method FIXME
	return $self;
}
sub add_entry_text_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $text=$self->{entry}->get_text;
	return if $text eq '';
	$self->addvalues($text);
	$self->{entry}->set_text('');
}

sub addvalues
{	my ($self,@add)=@_;
	$self->{init}||=\@add;
	my $href=$self->{hlist};
	$href->{$_}=1 for @add;
	my $store=$self->{store};
	$store->clear;
	$store->set($store->append,0,$_) for sort keys %$href;
}
sub return_value
{	my $self=shift;
	my %h;
	$h{$_}=1 for @{ $self->{init} };
	$h{$_}|=2 for keys %{ $self->{hlist} };
	$self->{changed}=1 if grep $_ ne 3, values %h;
	return sort keys %{ $self->{hlist} };
}
sub get_text
{	my $self=shift;
	return	( $self->{init} && @{$self->{init}}==1 )
		? $self->{init}[0] : '';
}
sub set_text
{	my $self=shift;
	$self->{init}=undef;
	$self->{hlist}={};
	$_[0]='' unless defined $_[0];
	$self->addvalues( split(/\x00/,$_[0]) );
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
		TCON => [	['',0,0,1,'EntryList','g']
			],
		TLAN => [	['',0,0,1,'EntryList','l']
			],
	);
}
use base 'Gtk2::Frame';

sub new
{	my ($class,$values,$fname,$name,$type) = @_;
	my $self = bless Gtk2::Frame->new($name), $class;
	my $table=Gtk2::Table->new(1, 4, 0);
	$self->add($table);
	my $prop=(exists $SUBTAGPROP{$fname})? $SUBTAGPROP{$fname} :
		#($fname=~m/^T/)	     ? $SUBTAGPROP{TXXX}   :
		#($fname=~m/^W/)	     ? $SUBTAGPROP{WXXX}   :
						undef;
	my $row=0;
	my $subtag=0;
	for my $t (split //,$type)
	{	if ($t eq '*') { $self->{widgets}[0]->addvalues(@$values);last }
		my $val=$$values[$subtag]; $val='' unless defined $val;
		my ($name,$frow,$cols,$cole,$widget,$param)=
		($prop) ? @{ $prop->[$subtag] }
			: ('unknown',$row++,1,5,undef,undef);
		unless ($widget)
		{	($widget,$param)=@{ $DataType{$t} };
		}
		warn "$fname $subtag $t $widget\n" if $::debug;
		$subtag++;
		if ($name ne '')
		{	my $label=Gtk2::Label->new($name);
			$table->attach($label,$cols-1,$cols,$frow,$frow+1,'shrink','shrink',1,1);
		}
		$widget=$widget->new( $val,$param );
		push @{ $self->{widgets} },$widget;
		$table->attach($widget,$cols,$cole,$frow,$frow+1,['fill','expand'],'shrink',1,1);
	}
	if ($fname eq 'APIC') { $self->{widgets}[3]->set_mime_entry($self->{widgets}[0]); }
	elsif ($fname eq 'COMM') { $self->{suggest}=$self->{widgets}[2]; }	#$self->{widgets}[2] is main entry for COMM tag
	elsif ($fname eq 'TCON') { $self->{suggest}=$self->{widgets}[0]; }

	return $self;
}
sub get_text	#for suggest a COMM tag or TCON tag
{	my $self=shift;
	return '' unless $self->{suggest};
	$self->{suggest}->get_text;
}
sub set_text	#for suggest a COMM tag or TCON tag
{	my $self=shift;
	return unless $self->{suggest};
	$self->{suggest}->set_text(shift);
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
	{	$text.=sprintf '%08x  ',$offset;
		my $l=length $b;
		$text.=sprintf '%02x 'x$l,map(ord,split //,$b);
		$text.='   'x(16-$l);
		$b=~s/[^[:print:]]/./g;	#replace non-printable with '.'
		$text.="   $b\n";
		$offset+=$l;
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
	$dialog->signal_connect( response => sub
		{	$_[0]->destroy;
		});
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
	$self->add($_) for $img,$vbox;
	my $label=$self->{label}=Gtk2::Label->new;
	my $Bload=::NewIconButton('gtk-open',_"Replace...");
	my $Bsave=::NewIconButton('gtk-save-as',_"Save as...");
	$vbox->pack_start($_,0,0,2) for $label,$Bload,$Bsave;
	$Bload->signal_connect(clicked => \&load_cb);
	$Bsave->signal_connect(clicked => \&save_cb);
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
	my $loader=::LoadPixData( $self->{value} ,'-300');
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
	$_[0]=~m/^\x89PNG\x0D\x0A\x1A\x0A/s && return ('png','image/png');
	$_[0]=~m/^GIF8[79]a/s && return ('gif','image/gif');
	$_[0]=~m/^BM/s && return ('bmp','image/bmp');
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
