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
{	my ($file,$findlength)=@_;
	#$file=Glib->filename_from_unicode($file);
	return undef unless $file=~m/\.([^.]+)$/;
	my $format=$FORMATS{lc $1};
	return undef unless $format;
	my ($package,$formatstring,$plist)=@$format;
	my $filetag= eval { $package->new($file,$findlength); }; #filelength==1 -> may return estimated length (mp3 only)
	unless ($filetag) { warn $@ if $@; warn "can't read tags for $file\n"; return undef;}

	my @taglist;
	my %values;	#results will be put in %values
	my $estimated;
	if (my $info=$filetag->{info})	#audio properties
	{	$estimated=$info->{estimated};
		if ($info->{estimated} && $findlength!=1) { delete $info->{seconds}; delete $info->{bitrate}; }
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
	{	if ($tag eq 'vorbis')
		{	push @taglist, vorbis => $filetag->{comments};
		}
		elsif ($tag eq 'ilst')
		{	push @taglist, ilst => $filetag->{ilst};
		}
		elsif ($tag eq 'ID3v1' && $filetag->{ID3v1})
		{	push @taglist, id3v1 => { map( ($_ => $filetag->{ID3v1}[$_]), 0..6) }; #transform it into a hash
		}
		elsif ($tag eq 'ID3v2' && $filetag->{ID3v2})
	 	{	push @taglist, id3v2 => $filetag->{ID3v2}{frames};
			if ($filetag->{ID3v2s})
			{	push @taglist, id3v2 => $_->{frames} for @{ $filetag->{ID3v2s} };
			}
		}
		elsif ($tag eq 'APE' && $filetag->{APE})
		{	push @taglist, ape => $filetag->{APE}{item};
		}
		elsif ($tag eq 'lyrics3v2' && $filetag->{lyrics3v2})
		{	my $h=$filetag->{lyrics3v2}{fields};
			push @taglist, lyrics3 => { map { $_ => $h->{$_} }  keys %$h };
		}
	}
	for my $field (grep $Songs::Def{$_}{flags}=~m/r/, @Songs::Fields)
	{	for (my $i=0; $i<$#taglist; $i+=2)
		{	my $id=$taglist[$i]; #$id is type of tag : id3v1 id3v2 ape vorbis lyrics3 ilst
			my $h=$taglist[$i+1];
			my $value;
			if (defined(my $keys=$Songs::Def{$field}{$id})) #generic cases
			{	my $joinwith= $Songs::Def{$field}{join_with};
				my $split=$Songs::Def{$field}{read_split};
				my $join= $Songs::Def{$field}{flags}=~m/l/ || defined $joinwith;
				for my $key (split /\|/,$keys)
				{	$key=~s/\*$//;	#remove ';*', only used for writing tags
					($key,my @extra)= split /;/,$key,-1;  #-1 to keep empty trailing fields
					my $v=	$key=~m/^----/ ? [map $h->{$_}, grep m/^[^ ]*\Q$key\E$/, keys %$h] : #for freeform ilst fields
						$h->{$key}; #normal case
					next unless defined $v;
					$v=[$v] unless ref $v;
					if (@extra && ref $v->[0]) #for id3v2 multi fields (COMM for example)
					{	my @vals=
						     map{ my $v_ok; my $notok;
							  for my $j (0..$#extra)
							  {	my $p=$extra[$j];
								my $vj=$_->[$j];
								if ($p eq '%v') { $v_ok=$vj; }
								elsif ($p ne '' && $p ne $vj) {$notok=1;last}
							  }
							  $notok ? () : ($v_ok);
							} @$v;
						$v=\@vals;
					}
					elsif (ref $v->[0])	#for id3v2, even single values are a one-element list
					{	$v= [map @$_, @$v];
					}
					if (my $sub= $Songs::Def{$field}{preset} ) #not used
						{ @$v= map $sub->($_), @$v; next unless @$v; }
					if ($join)		{ push @$value, @$v; }
					else			{ $value= $v->[0]; last; }
				}
				if (defined $joinwith && $value) { $value=join $joinwith,@$value; }
				elsif (defined $split)	 { $value=[ map split($split,$_), @$value ]; }
			}
			elsif (my $sub=$Songs::Def{$field}{"$id:read"}) #special cases with custom function
			{	$values{$field}= $sub->($h);
				# OR just $sub->($h); ????
				# last ??? depend on return value ???
				last;
			}
			if (defined $value) { $values{$field}=$value; last }
		}
	}

	return \%values,$estimated;
}

sub Write
{	my ($ID,$modif,$errorsub)=@_; warn "Tag::Write($ID,[@$modif],$errorsub)\n";
	$modif= do { my @m; while (@$modif) { my $f=shift @$modif; my $v=shift @$modif; push @m,[$f,(ref $v ? @$v : $v )]; } \@m }; #FIXME PHASE1 TEMP
	my $file= Songs::GetFullFilename($ID);

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FileTag::FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	my ($maintag)=split / /,$format->[2],2;
	if ($maintag eq 'ID3v2' || $tag->{ID3v1})
	{	my $id3v1 = $tag->{ID3v1};
		$id3v1||=$tag->new_ID3v1 unless $::Options{TAG_id3v1_noautocreate};
		if ($id3v1)
		{	for my $aref (@$modif)
			{	my ($field,$val)=@$aref;
				my $i=$Songs::Def{$field}{id3v1};
				next unless defined $i;
				$id3v1->[$i]= $val;	# $val is a arrayref for genres
			}
		}
	}
	if ($maintag eq 'ID3v2' || $tag->{ID3v2})
	{	my $id3v2 = $tag->{ID3v2} || $tag->new_ID3v2;
		my ($ver)= $id3v2->{version}=~m/^(\d+)/;
		my @todo;
		for my $aref (@$modif)
		{	my ($field,@vals)=@$aref;
			if (my $sub=  $Songs::Def{$field}{'id3v2.'.$ver.':write'} || $Songs::Def{$field}{'id3v2:write'})
			{	push @todo, $sub->(@vals);
			}
			elsif (my $keys= $Songs::Def{$field}{'id3v2.'.$ver} || $Songs::Def{$field}{id3v2})
			{	my @keys= split /\|/,$keys;
				push @todo, $_ => undef for @keys;
				push @todo, $keys[0] => \@vals;
			}
		}
		while (@todo)
		{	my $key= shift @todo;
			my $val= shift @todo;
			($key,my @extra)=split /;/,$key,-1; #-1 to keep empty trailing fields #COMM;;;%v => key="COMM" and @extra=("","")
			my $can_be_list= $key=~s/\*$//;
			if ($val)
			{	if (@extra)
				{	for my $v (@$val)
					{	my @parts=map {$_ eq '%v' ? $v : $_} @extra;
						$id3v2->insert($key, @parts);
					}
				}
				elsif ($can_be_list)
				{	warn "\$id3v2->insert($key, @$val)";
					$id3v2->insert($key, @$val);
				}
				else { $id3v2->insert($key,$_) for reverse @$val; }
			}
			else
			{	if (@extra)
				{	my $ref=$id3v2->{frames}{$key};
					next unless $ref;
					for my $i (0..$#$ref)
					{	my $keep;
						for my $j (0..$#extra)
						{	next if $extra[$j] eq '%v' || $extra[$j] eq '';
							$keep=1 if $extra[$j] ne $ref->[$i][$j];
						}
						$id3v2->remove($key,$i) unless $keep;
					}
				}
				else { $id3v2->remove_all($key) }
			}
		}
	}
	if ($maintag eq 'vorbis')
	{	my @todo;
		for my $aref (@$modif)
		{	my ($field,@vals)=@$aref;
			if (my $sub=$Songs::Def{$field}{'vorbis:write'})
			{	push @todo, $sub->(@vals);
			}
			elsif (my $keys=$Songs::Def{$field}{vorbis})
			{	my @keys= split /\|/,$keys;
				push @todo, $_ => undef for @keys;
				push @todo, $keys[0] => \@vals;
			}
		}
		while (@todo)
		{	my $key= shift @todo;
			my $val= shift @todo;
			if ($val)		{ $tag->insert($key,$_) for reverse @$val}
			else			{ $tag->remove_all($key) }
		}
	}
	if ($maintag eq 'ilst')
	{	my @todo;
		for my $aref (@$modif)
		{	my ($field,@vals)=@$aref;
			if (my $sub=$Songs::Def{$field}{'ilst:write'})
			{	push @todo, $sub->(@vals);
			}
			elsif (my $keys=$Songs::Def{$field}{ilst})
			{	my @keys= split /\|/,$keys;
				push @todo, $_ => undef for @keys;
				$keys[0]=~s/^----/com.apple.iTunes----/;
				push @todo, $keys[0] => \@vals;
			}
		}
		while (@todo)
		{	my $key= shift @todo;
			my $val= shift @todo;
			if ($val)		{ $tag->insert($key,$_) for reverse @$val}
			else			{ $tag->remove_all($key) }
		}
	}
	if ($maintag eq 'APE' || $tag->{APE})
	{	my @todo;
		for my $aref (@$modif)
		{	my ($field,@vals)=@$aref;
			if (my $sub=$Songs::Def{$field}{'ape:write'})
			{	push @todo, $sub->(@vals);
			}
			elsif (my $keys=$Songs::Def{$field}{ape})
			{	my @keys= split /\|/,$keys;
				push @todo, $_ => undef for @keys;
				push @todo, $keys[0] => \@vals;
			}
		}
		my $ape = $tag->{APE} || $tag->new_APE;
		while (@todo)
		{	my $key= shift @todo;
			my $val= shift @todo;
			if ($val)		{ $ape->insert($key,$_) for reverse @$val}
			else			{ $ape->remove_all($key) }
		}
	}
	$tag->{errorsub}=$errorsub;
	$tag->write_file unless $::CmdLine{ro}  || $::CmdLine{rotags};
	return 1;
}

sub PixFromMusicFile
{	my ($file,$nb)=@_;
	return unless -r $file;
	my $pix;
	my $apic=1;
	my ($ext)= $file=~m/\.([^.]+)$/;
	$ext= $::Alias_ext{lc$ext} || lc$ext;
	if ($ext eq 'mp3')
	{	my $tag=Tag::MP3->new($file,0);
		unless ($tag) {warn "can't read tags for $file\n";return;}
		$pix=$tag->{ID3v2}{frames}{APIC} if $tag->{ID3v2} && $tag->{ID3v2}{frames};
	}
	elsif ($ext eq 'flac')
	{	my $tag=Tag::Flac->new($file);
		unless ($tag) {warn "can't read tags for $file\n";return;}
		$pix=$tag->{pictures}
	}
	elsif ($ext eq 'm4a')
	{	my $tag=Tag::M4A->new($file);
		unless ($tag) {warn "can't read tags for $file\n";return;}
		$pix=$tag->{ilst}{covr} if $tag->{ilst};
		$apic=0;	#not in APIC (id3v2) format
	}
	else { return }
	unless ($pix && @$pix)	{warn "no picture found in $file\n";return;}
	#if (!defined $nb && $apic && @$pix>1) {$nb=}	#FIXME if more than one picture in tag, use $pix->[$nb][1] to choose
	$nb=0 if !defined $nb || $nb>$#$pix;
	return $apic ? (map $pix->[$_][3],0..$#$pix) : @$pix if wantarray;
	return $apic ? $pix->[$nb][3] : $pix->[$nb];
}

sub GetLyrics
{	my $ID=$_[0];
	my $file= Songs::GetFullFilename($ID);
	return undef unless -r $file;

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	my $lyrics;
	for my $t (split / /, $format->[2])
	{	if ($t eq 'vorbis' && $tag->{comments}{lyrics})
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
	my $file= Songs::GetFullFilename($ID);
	return undef unless -r $file;

	my ($format)= $file=~m/\.([^.]*)$/;
	return undef unless $format and $format=$FORMATS{lc$format};
	my $tag= $format->[0]->new($file);
	unless ($tag) {warn "can't read tags for $file\n";return undef;}

	my ($t)=split / /,$format->[2],2;
	if ($t eq 'vorbis')
	{	if (exists $tag->{comments}{lyrics})
			{ $tag->edit('lyrics',0,$lyrics); }
		else	{ $tag->add('lyrics',$lyrics); }
	}
	elsif ($t eq 'APE')
	{	my $ape = $tag->{APE} || $tag->new_APE;
		if (exists $ape->{item}{lyrics})
			{ $ape->edit('Lyrics',0,$lyrics); }
		else	{ $ape->add('Lyrics',$lyrics); }
	}
	elsif ($t eq 'ID3v2')
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

our @FORMATS;
our @Tools;
INIT
{
 @Tools=
 (	{ label=> _"Capitalize",		for_all => sub { ucfirst lc $_[0]; }, },
	{ label=>_"Capitalize each words",	for_all => sub { join ' ',map ucfirst lc, split / /,$_[0]; }, },
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
	my %frames;
	$self->{frames}=\%frames;
	$self->{pf_frames}={};
	$self->{IDs}=\@IDs;

	{	my $folders= Songs::UniqList('path',\@IDs);
		my $folder=$folders->[0];
		if (@$folders>1)
		{	my $common= ::find_common_parent_folder(@$folders);
			$folder=_"different folders";
			$folder.= "\n". ::__x(_"(common parent folder : {common})",common=>$common) if length($common)>5;
		}
		my $text= ::__("%d file in {folder}","%d files in {folder}",scalar@IDs);
		$text= ::__x($text, folder => ::MarkupFormat('<small>%s</small>',$folder) );
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
		$frames{$field}=$widget;	#FIXME	rename ($frames and {combo})and maybe
		$check->{combo}=$widget;	#	remove one
		$widget->set_sensitive(FALSE);

		$check->signal_connect( toggled => sub
			{  my $check=$_[0];
			   my $active=$check->get_active;
			   $check->{combo}->set_sensitive($active);
			});
		my ($row,$col)= $widget->{noexpand} ? ($row2++,2) : ($row1++,0);
		$table->attach($check,$col++,$col,$row,$row+1,'fill','shrink',3,1);
		$table->attach($widget,$col++,$col,$row,$row+1,['fill','expand'],'shrink',3,1);
	}

	$self->pack_start($table, FALSE, TRUE, 2);
#short circuit if a LOT of songs : don't add file-specific tags, building the GUI would be too long anyway
return $self if @IDs>1000;
#######################################################
	::SortList(\@IDs,'path album disc track file');
	#edition of file-specific tags (track title)
	my $perfile_table=Gtk2::Table->new( scalar(@IDs), 10, FALSE);
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
	for my $ID (@IDs)
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

########################################################### Autofill
	my $Bautofill=Gtk2::OptionMenu->new;
	my $menu=Gtk2::Menu->new;
	$menu->append(Gtk2::MenuItem->new(_"Auto fill based on filenames ..."));
	my @files= Songs::Map('file',\@IDs); #FIXME or use Songs::Display ?
	s/\.[^.]*$//i for @files;
	my $found;
	for my $i (0..$#FORMATS)
	{	next if @files/2>(grep m/$FORMATS[$i][1]/, @files);
		my $formatname=$FORMATS[$i][0];
		$formatname=~s/(%[taldnyCV%])/Songs::FieldName($::ReplaceFields{$1})/ge;
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
	$hbox->pack_start($_, FALSE, FALSE, 0) for $BSelFields,Gtk2::VSeparator->new,$Bautofill,$BClear,$checkOBlank,$Btools,
	$self->pack_start($hbox, FALSE, FALSE, 4);
###########################################################
	return $self;
}

sub add_column
{	my ($self,$field)=@_;
	if ($self->{'pfcheck_'.$field})	#if already created -> toggle show/hide
	{	my @w=( $self->{'pfcheck_'.$field}, @{ $self->{pf_frames}{$field} } );
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
	$self->{pf_frames}{$field}=\@entries;
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
		$check->signal_connect( toggled => sub { my ($check,$i)=@_; my $self=::find_ancestor($check,__PACKAGE__); my $active=$check->get_active; $self->{pf_frames}{$_}[$i]->set_sensitive($active) for keys %{ $self->{pf_frames} } },$i);
		#$widget->signal_connect(focus_in_event=> \&scroll_to_entry);
		$table->attach($check,$col,$col+1,$row,$row+1,'fill','shrink',1,1);
		$check->show_all; warn $check;
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

sub autofill_cb
{	my ($menuitem,$self)=@_;
	my ($format,$pattern)=@{ $FORMATS[$menuitem->{'index'}] };
	my @fields= map $::ReplaceFields{$_}, $format=~m/(%[taldnyCV])/g;
	my $OBlank=$self->{AFOBlank}->get_active;
	my @vals;
	for my $ID (@{$self->{IDs}})
	{	my $file= Songs::Get($ID,'file');
		$file=~s/\.[^.]*$//;
		my @v=($file=~m/$pattern/);
		s/_/ /g for @v;		#should it be an option ?
		s/^\s+//, s/\s+$// for @v;
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
		{	my $entries=$self->{pf_frames}{$f};
			next unless $entries;
			for my $e (@$entries)
			{ my $v=shift @$varray;
			  next if $OBlank && $e->get_text ne '';
			  $e->set_text($v) if $e->is_sensitive && $v ne '';
			}
		}
	}
}

sub tool
{	my ($self,$sub)=@_;
	#my $OBlank=$self->{AFOBlank}->get_active;
	#$OBlank=0 if $ignoreOB;
	my $IDs=$self->{IDs};
	for my $wdgt ( values %{$self->{frames}}, map @$_, values %{$self->{pf_frames}} )
	{	next unless $wdgt->is_sensitive && $wdgt->can('tool');
		$wdgt->tool($sub);
	}
	#for my $entries (values %{$self->{pf_frames}})
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
	while ( my ($f,$wdgt)=each %{$self->{frames}} )
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
	while ( my ($f,$wdgt)=each %{$self->{pf_frames}} )
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

package GMB::TagEdit::EntryString;
use Gtk2;
use base 'Gtk2::Entry';

sub new
{	my ($class,$field,$ID,$width) = @_;
	my $self = bless Gtk2::Entry->new, $class;
	#$self->{field}=$field;
	my $val=Songs::Get($ID,$field);
	$self->set_text($val);
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
	my $self = bless Gtk2::Combo->new, $class;
	#$self->{field}=$field;
	GMB::ListStore::Field::setcompletion($self->entry,$field) if $listall;

	if (ref $IDs)
	{	my $values= Songs::BuildHash($field,$IDs);
		my @l=sort { $values->{$b} <=> $values->{$a} } keys %$values; #sort values by their frequency
		my $first=$l[0];
		@l= @{ Songs::Gid_to_Get($field,\@l) };
		if ($listall) { push @l, @{Songs::ListAll($field)}; }
		$self->set_case_sensitive(1);
		$self->set_popdown_strings(@l);
		$self->set_text('') unless ( $values->{$first} > @$IDs/3 );
	}
	else
	{	my $val=Songs::Get($IDs,$field);
		$self->set_text($val);
	}

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

	my $adj=Gtk2::Adjustment->new(0,0,100,5,20,0);
	my $spin=Gtk2::SpinButton->new($adj,10,0);
	my $check=Gtk2::CheckButton->new(_"use default");
	my $stars=Stars->new($init,\&update_cb);

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

package GMB::TagEdit::FlagList;
use Gtk2;
use base 'Gtk2::HBox';

sub new
{	my ($class,$field,$ID) = @_;
	my $self = bless Gtk2::HBox->new(0,0), $class;
	#$self->{field}=$field;
	$self->{ID}=$ID;
	my $label=$self->{label}=Gtk2::Label->new;
	$label->set_ellipsize('end');
	my $button= Gtk2::Button->new;
	my $entry= Gtk2::Entry->new;
	$entry->set_width_chars(12);
	$button->add($label);
	$self->pack_start($button,1,1,0);
	$self->pack_start($entry,0,0,0);
	$button->signal_connect( button_press_event => \&popup_menu_cb); #FIXME make it popup for keyboard activation too
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
	return if $text eq '';
	$self->{selected}{ $text }=1;
	$self->update;
	$entry->set_text('');
}

sub popup_menu_cb
{	my ($widget,$event)=@_;
	my $self=::find_ancestor($widget,__PACKAGE__);
	my $menu=Gtk2::Menu->new;
	my $cb= sub { $self->{selected}{ $_[1] }^=1; $self->update; };
	my @keys= sort {::superlc($a) cmp ::superlc($b)} keys %{$self->{selected}};
	return unless @keys;
	for my $key (@keys)
	{	my $item=Gtk2::CheckMenuItem->new_with_label($key);
		$item->set_active(1) if $self->{selected}{$key};
		$item->signal_connect(toggled => $cb,$key);
		$menu->append($item);
	}
	$menu->show_all;
	$menu->popup(undef,undef,\&::menupos,undef,$event->button,$event->time);
}

sub update
{	my $self=$_[0];
	my $text=join ', ', sort { ::superlc($a) cmp ::superlc($b) } grep $self->{selected}{$_}, keys %{$self->{selected}};
	$self->{label}->set_text($text);
	$self->{label}->parent->set_tooltip_text($text);
}

sub get_text
{	my $self=$_[0];
	my $h=$self->{selected};
	return [grep $h->{$_}, keys %$h];
}

package GMB::TagEdit::EntryMassList;	#for mass-editing fields with multiple values
use Gtk2;
use base 'Gtk2::HBox';

sub new
{	my ($class,$field,$IDs) = @_;
	my $self = bless Gtk2::HBox->new(1,1), $class;
	my $vbox=Gtk2::VBox->new;
	my $addbut=::NewIconButton('gtk-add',_"Add");
	my $combo=Gtk2::ComboBoxEntry->new_text;
	$combo->append_text($_) for @{ Songs::ListAll($field) };
	my $entry=$combo->child;
	$entry->set_text('');
	$vbox->pack_start($_,::FALSE,::FALSE,0) for $combo,$addbut;
	my $store=Gtk2::ListStore->new('Glib::String','Glib::Boolean','Glib::Boolean');
	my $treeview=Gtk2::TreeView->new($store);
	 my $sw=Gtk2::ScrolledWindow->new;
	 $sw->set_shadow_type('etched-in');
	 $sw->set_policy('never','automatic');
	 $sw->add($treeview);
	 $sw->set_size_request(-1, 4*$entry->size_request->height );
	$self->pack_start($_,::TRUE,::TRUE,0) for $sw,$vbox;

	for my $ref ([1,_"set"],[2,_"unset"])
	{	my ($col,$title)=@$ref;
		my $renderer=Gtk2::CellRendererToggle->new;
		$renderer->{column}=$col;
		$renderer->signal_connect(toggled => \&toggled_cb, $store);
		my $tvcolumn=Gtk2::TreeViewColumn->new_with_attributes($title, $renderer, active=>$col);
		$treeview->append_column($tvcolumn);
	}
	my $column=Gtk2::TreeViewColumn->new_with_attributes('', Gtk2::CellRendererText->new,text=>0);
	$treeview->append_column($column);
	#$treeview->set_headers_visible(0);
	$entry->signal_connect( activate => \&add_entry_text_cb);
	$addbut->signal_connect( clicked => \&add_entry_text_cb);

	my $valueshash= Songs::BuildHash($field,$IDs);
	$store->set($store->append,0=> Songs::Gid_to_Get($field,$_),1,0,2,0)  for sort keys %$valueshash; #FIXME check that fields use a gid, not the case for comments (yet ?)

	$self->{entry}=$entry;
	$self->{store}=$store;
	return $self;
}

sub add_entry_text_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $entry=$self->{entry};
	my $text=$entry->get_text;
	return if $text eq '';
	my $store=$self->{store};
	$store->set($store->append,0=>$text,1,1,2,0);
	$entry->set_text('');
}

sub toggled_cb
{	my ($cell,$path_str,$store)=@_;
	my $column=$cell->{column};
	my $iter=$store->get_iter_from_string($path_str);
	my $state=$store->get($iter,$column);
	$store->set($iter,$column, $state^1);
	$store->set($iter,($column==1 ? 2 : 1), 0) if !$state;
}

sub return_setunset
{	my $self=$_[0];
	my (@set,@unset);
	my $store=$self->{store};
	my $iter=$store->get_iter_first;
	while ($iter)
	{	my ($value,$set,$unset)=$store->get($iter,0,1,2);
		push @set,$value   if $set;
		push @unset,$value if $unset;
		$iter=$store->iter_next($iter);
	}
	return \@set,\@unset;
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
			fillsub => sub { $_[0]{frames} },
			typesub => sub {Tag::ID3v2::get_fieldtypes($_[1])},
			namesub => sub { 'id3v2.'.$_[0]{version} },
			types	=> $id3v2_types,
		},
	OGG =>	{	addlist => [qw/description genre discnumber author/,''],
			default => [qw/title artist album tracknumber date description genre/],
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
	M4A =>	{	addlist => ["\xA9cmt","\xA9wrt",qw/disk aART cpil ----/],
			default => ["\xA9nam","\xA9ART","\xA9alb",'trkn',"\xA9day","\xA9cmt","\xA9gen"],
			fillsub => sub { $_[0]{ilst} },
			typesub => \&Tag::M4A::get_fieldtypes,
			name => 'ilst',
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
	my $toadd= $tagtype->{fillsub}($tag);
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
	my $typesref=$tagtype->{types}{($tagtype->{lckeys}? lc$fname : $fname)};

	my ($name,$type,$realfname);
	if ($typesref)
	{	$type= $typesref->[TAGTYPE];
		$name=$typesref->[TAGNAME];
	}
	if ($tagtype->{typesub})
	{	(my ($type0,$name0,$realval),$realfname)= $tagtype->{typesub}($self->{tag},$fname,$nb);
		$type||=$type0;
		$name||=$name0;
		$value=$realval if defined $realval;
	}
	$name||=$fname;
	$type||='t';

	if (length($type)>1)	#frame with sub-frames (id3v2)
	{	$value||=[];
		$widget=EntryMulti->new($value,$fname,$name,$type,$realfname);
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
	 $sw->set_size_request(-1, 3*$entry->size_request->height );
	$self->pack_start($_,::TRUE,::TRUE,0) for $sw,$vbox;

	my $column=Gtk2::TreeViewColumn->new_with_attributes('', Gtk2::CellRendererText->new,text=>0);
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
	my $ref= ref $_[0] ? $_[0] : [split /\x00/,$_[0]];
	$self->addvalues(@$ref);
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
		'----' =>
			[	['',2,0,2],
				[_"Application",0,1,2],
				[_"Name",1,1,2],
			],
	);
}
use base 'Gtk2::Frame';

sub new
{	my ($class,$values,$fname,$name,$type,$realfname) = @_;
	my $self = bless Gtk2::Frame->new($name), $class;
	my $table=Gtk2::Table->new(1, 4, 0);
	$self->add($table);
	my $prop=$SUBTAGPROP{$realfname || $fname};
	my $row=0;
	my $subtag=0;
	for my $t (split //,$type)
	{	if ($t eq '*') { $self->{widgets}[0]->addvalues(@$values);last }
		my $val=$$values[$subtag]; $val='' unless defined $val;
		my ($name,$frow,$cols,$cole,$widget,$param)=
		($prop) ? @{ $prop->[$subtag] }
			: (_"unknown",$row++,1,5,undef,undef);
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
	my $loader= GMB::Picture::LoadPixData( $self->{value} ,'-300');
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
