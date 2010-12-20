# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin FETCHCOVER
name	Picture finder
title	Picture finder plugin
desc	Adds a menu entry to artist/album context menu, allowing to search the picture/cover in google and save it.
=cut

package GMB::Plugin::FETCHCOVER;
use strict;
use warnings;
require $::HTTP_module;
use base 'Gtk2::Window';
use constant
{	OPT => 'PLUGIN_FETCHCOVER_',
	RES_LINES => 4,
	RES_PER_LINE => 5,
	PREVIEW_SIZE => 100,
};
use constant RES_PER_PAGE => RES_PER_LINE*RES_LINES;

my %Sites=
(artist =>
 {	googlei => ['google images',"http://images.google.com/images?q=%s&imgsz=medium|large", \&parse_googlei],
	lastfm => ['last.fm',"http://www.last.fm/music/%a/+images", \&parse_lastfm],
 },
 album =>
 {	googlei => ['google images',"http://images.google.com/images?q=%s&imgsz=medium|large", \&parse_googlei],
	slothradio => ['slothradio', "http://www.slothradio.com/covers/?artist=%a&album=%l", \&parse_sloth],
	#itunesgrabber => ['itunesgrabber',"http://www.thejosher.net/iTunes/index.php?artist=%a&album=%l", \&parse_itunesgrabber],
	freecovers => ['freecovers.net', "http://www.freecovers.net/api/search/%s", \&parse_freecovers], #could add /Music+CD but then we'd lose /Soundtrack
	#rateyourmusic=> ['rateyourmusic.com', "http://rateyourmusic.com/search?searchterm=%s&searchtype=l",\&parse_rateyourmusic], # urls results in "403 Forbidden"
 },
);

my %menuitem=
(	label => _"Search for a picture on internet",					#label of the menu item
	code => sub { Fetch($_[0]{mainfield},$_[0]{gid},$_[0]{ID}); },			#when menu item selected
	test => sub {$_[0]{mainfield} eq 'album' || $_[0]{mainfield} eq 'artist'},	#the menu item is displayed if returns true
);
my %fpane_menuitem=
(	label=> _"Search for a picture on internet",
	code => sub { Fetch($_[0]{field},$_[0]{gidlist}[0]); },
	onlyone=> 'gidlist',	#menu item is hidden if more than one album/artist is selected
	istrue => 'aa',		#menu item is hidden for non artist/album (aa) FPanes
);

::SetDefaultOptions(OPT, USEFILE => 1, COVERFILE => 'cover', PictureSite_artist => 'googlei', PictureSite_album => 'googlei');

sub Start
{	push @::cMenuAA,\%menuitem;
	push @FilterPane::cMenu, \%fpane_menuitem;
}
sub Stop
{	@::cMenuAA=  grep $_!=\%menuitem, @::SongCMenu;
	@FilterPane::cMenu= grep $_!=\%fpane_menuitem, @FilterPane::cMenu;
}

sub prefbox
{	my $check1=::NewPrefCheckButton(OPT.'ASK',_"Ask confirmation only if file already exists");
	my $check2=::NewPrefCheckButton(OPT.'UNIQUE',_"Find a unique filename if file already exists");
	my $entry1=::NewPrefEntry(OPT.'COVERPATH');
	my $entry2=::NewPrefEntry(OPT.'COVERFILE');
	my ($radio1a,$radio1b)=::NewPrefRadio(OPT.'USEPATH',undef,_"use song folder",0,_"use :",1);
	my ($radio2a,$radio2b)=::NewPrefRadio(OPT.'USEFILE',undef,_"use album name",0,_"use :",1);
	my $frame1=Gtk2::Frame->new(_"default folder");
	my $frame2=Gtk2::Frame->new(_"default filename");
	my $vbox1=::Vpack( $radio1a,[$radio1b,$entry1] );
	my $vbox2=::Vpack( $radio2a,[$radio2b,$entry2] );
	$frame1->add($vbox1);
	$frame2->add($vbox2);
	return ::Vpack( $frame1,$frame2,$check1,$check2 );
}

sub Fetch
{	my ($field,$gid,$ID)=@_;
	unless (defined $ID)
	{	my $list= AA::GetIDs($field,$gid);
		$ID=$list->[0];
		return unless defined $ID;
	}
	my $mainfield=Songs::MainField($field);	#'artist' or 'album'
	my $self=bless Gtk2::Window->new;
	$self->set_border_width(4);
	my $Bsearch=::NewIconButton('gtk-find',_"Search");
	my $Bcur=Gtk2::Button->new($mainfield eq 'artist' ? _"Search for current artist" : _"Search for current album");
	::set_drag($Bcur, dest =>	[::DRAG_ID, sub { $_[0]->get_toplevel->SearchID($_[2]); }], );
	my $Bclose=Gtk2::Button->new_from_stock('gtk-close');
	my @entry;
	push @entry, $self->{"searchentry_$_"}=Gtk2::Entry->new for qw/s a l/;
	$self->{searchentry_s}->set_tooltip_text(_"Keywords");
	$self->{searchentry_a}->set_tooltip_text(_"Artist");
	$self->{searchentry_l}->set_tooltip_text(_"Album");
	my $source=::NewPrefCombo( OPT.'PictureSite_'.$mainfield, {map {$_=>$Sites{$mainfield}{$_}[0]} keys %{$Sites{$mainfield}}} , cb => \&combo_changed_cb);
	#$self->{Bnext}=	my $Bnext=::NewIconButton('gtk-go-forward',"More");
	$self->{Bnext}=		my $Bnext=Gtk2::Button->new(_"More results");
	$self->{Bstop}=		my $Bstop=Gtk2::Button->new_from_stock('gtk-stop');
	$self->{progress}=	my $pbar =Gtk2::ProgressBar->new;
	$self->{table}=		my $table=Gtk2::Table->new(RES_LINES,RES_PER_LINE,::TRUE);
	$self->add( ::Vpack
			(	[map( {('_',$_)} @entry), $Bsearch, $Bstop, $source],
				'_',$table,
				'-', ['_',$pbar , '-', $Bclose,$Bnext,$Bcur]
			) );
	for (@entry)
	{	$_->signal_connect(  activate => \&NewSearch );
		$_->show_all;
		$_->set_no_show_all(1);
	}
	$self->show_all;
	$Bsearch->signal_connect( clicked => \&NewSearch );
	$Bstop->signal_connect( clicked => sub {$_[0]->get_toplevel->stop });
	$Bclose->signal_connect(clicked => sub {$_[0]->get_toplevel->destroy});
	$Bnext->signal_connect( clicked => sub {$_[0]->get_toplevel->NextPage});
	$Bcur->signal_connect(clicked =>sub {$_[0]->get_toplevel->SearchID($::SongID)});
	$self->signal_connect( destroy => \&abort);
	$self->signal_connect( unrealize => sub {$::Options{OPT.'winsize'}=join ' ',$_[0]->get_size; });

	my $size= $::Options{OPT.'winsize'} || RES_PER_LINE*PREVIEW_SIZE.' '.RES_LINES*PREVIEW_SIZE;
	$self->resize(split ' ',$size,2);

	$self->{mainfield}=$mainfield;
	$self->{field}=$field;
	$self->{site}=$::Options{OPT.'PictureSite_'.$mainfield};
	$self->SearchID($ID);
	$self->UpdateSite;
}

sub combo_changed_cb
{	my $self=$_[0]->get_toplevel;
	$self->{site}=$::Options{OPT.'PictureSite_'.$self->{mainfield}};
	$self->UpdateSite;
	$self->NewSearch;
}
sub UpdateSite
{	my $self=$_[0];
	my $url=$Sites{$self->{mainfield}}{$self->{site}}[1];
	for my $l (qw/s a l/)
	{	my $entry=$self->{"searchentry_$l"};
		if ($url=~m/\%$l/)	{$entry->show}
		else			{$entry->hide}
	}
}

sub SearchID
{	my ($self,$ID)=@_;
	$self=::find_ancestor($_[0],__PACKAGE__);

	$self->{gid}= Songs::Get_gid($ID,$self->{field});
	$self->{dir}= Songs::Get($ID,'path');
	my $search=my $name= Songs::Get($ID,$self->{field});
	$search="\"$search\"" unless $search eq '';
	my $albumname='';
	my $artistname='';
	if ($self->{mainfield} eq 'album')
	{	$albumname=$name;
		$artistname= Songs::Get($ID,'album_artist');
		$search.=" \"$artistname\"" unless $search eq '' || $artistname eq '';
	}
	else { $artistname=$name }
	$self->set_title(_("Searching for a picture of : ").$name);
	$self->{searchentry_s}->set_text($search);
	$self->{searchentry_a}->set_text($artistname);
	$self->{searchentry_l}->set_text($albumname);
	$self->NewSearch;
}

sub NewSearch
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $url=$Sites{$self->{mainfield}}{$self->{site}}[1];
	my %letter;
	for my $l (qw/s a l/)
	{	next unless $url=~m/\%$l/;
		my $s= $self->{"searchentry_$l"}->get_text;
		$s=~s/^\s+//; $s=~s/\s+$//;
	       	return if $s eq '';
		$letter{$l}=::url_escapeall($s);
	}
	$self->abort;
	$self->{results}=[];
	$self->{page}=0;
	$self->InitPage;
	$url=~s/%([sal])/$letter{$1}/g;
	warn "fetchcover : loading $url\n" if $::debug;
	$self->{waiting}=Simple_http::get_with_cb
	 (	cb => sub {$self->searchresults_cb(@_)},
		url => $url,	cache=>1
	 );
}

sub InitPage
{	my $self=$_[0];
	$self->abort;
	$self->{loaded}=0;
	$self->{Bnext}->set_sensitive(0);
	$self->{Bstop}->set_sensitive(1);
	$self->{progress}->set_fraction(0);
	$self->{progress}->show;
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
}

sub PrevPage
{	my $self=$_[0];
	return unless $self->{page};
	$self->{page}--;
	$self->InitPage;
	::IdleDo('8_FetchCovers'.$self,100,\&get_next,$self);
}

sub NextPage
{	my $self=$_[0];
	$self->{page}++;
	$self->InitPage;
	::IdleDo('8_FetchCovers'.$self,100,\&get_next,$self);
}

sub parse_rateyourmusic
{	my $result=$_[0];
	my @list;
	while ($result=~m#a title="\[Album(\d+)\]"#g)
	{	push @list,
		{	url=> "http://static.rateyourmusic.com/album_images/$1.jpg",
			previewurl => "http://static.rateyourmusic.com/album_images/s$1.jpg",
		};
	}
	return \@list;
}
sub parse_freecovers #FIXME could use a XML module	#can provide backcover and more too
{	my $result=$_[0];
	my @list;
	while ($result=~m#<title>(.+?)</title>#gs)
	{	my $res=$1;
		my %res;
		$res{desc}= ::decode_html(Encode::decode('cp1252',$1)) if $res=~m#<name>([^<]+)</name>#; #FIXME not sure of the encoding
		while ($res=~m#<cover>(.+?)</cover>#gs)
		{	my $res=$1;
			next unless $res=~m#<type>front</type>#;
			$res{url}=$1 if $res=~m#<preview>([^<]+)</preview>#;
			$res{previewurl}=$1 if $res=~m#<thumbnail>([^<]+)</thumbnail>#;
			last;
		}
		push @list, \%res if $res{url};
	}
	return \@list;
}
sub parse_lastfm
{	my $result=$_[0];
	my @list;
	while ($result=~m#<a href="/music/[^/]+/\+images/\d+"[^>]+?class="pic".+?<img [^>]+?src="([^"]+)"#gs)
	{	my $url=my $pre=$1;
		$url=~s#/\w+/(\d+.jpg)$#/_/$1#; ### /126b/123456.jpg -> /_/123456.jpg
		push @list, {url => $url, previewurl =>$pre,};
	}
	my $nexturl;
	$nexturl='http://www.lastfm.com'.$1 if $result=~m#<a href="([^"]+)" class="nextlink">#;
	return \@list,$nexturl;
}
sub parse_itunesgrabber
{	my $result=$_[0];
	my @list;
	push @list,{url=>$1} if $result=~m#Album art found.*?<a href="([^"]+)"#;
	return \@list;
}
sub parse_sloth
{	my $result=$_[0];
	my @list;
	while ($result=~m#<div class="album\d+"><img src="([^"]+)"#g)
	{	push @list, {url => $1};
	}
	my $nexturl;
	$nexturl='http://www.slothradio.com/covers/'.$1 if $result=~m#<div class="pages">[^<>]*(?:\s*<a href="[^"]+">\d+</a>)*\s*\d\s+<a href="([^"]+)">\d+</a>#;
	return \@list,$nexturl;
}
sub parse_googlei
{	my $result=$_[0];
	my @list;
	if ($result=~m#dyn.setResults\([^)](.*)\)#)	#parse google image results #assumes no unencoded ')' in the array of results
	{	my @matches=split /\],\["/,$1;	#not very reliable
		for my $m (@matches)
		{	my @fields=split /["\]],["\[]/,$m;
			my $url=$fields[3];
			my $desc=$fields[6]; $desc=~s#\\x([0-9a-f]{2})#chr(hex $1)#gie; $desc=~s#</?b>##g;
			$desc=Encode::decode('cp1252',$desc); #FIXME not sure of the encoding
			$desc=::decode_html($desc);
			my $preview='http://images.google.com/images?q=tbn:'.$fields[2].$url;
			push @list, {url => $url, previewurl =>$preview, desc => $desc };
		}
	}
	my $nexturl;
	if ($result=~m#<a href="(/images\?[^>"]*)"( [^>]*)?class=pn\b#)
	{	$nexturl='http://images.google.com'.$1;
		$nexturl=~s#&amp;#&#g;
	}
	return \@list,$nexturl;
}

sub searchresults_cb
{	my ($self,$result)=@_;
	$self->{waiting}=undef;
	unless (defined $result) { stop($self,_"connection failed."); return; }
	my $parse= $Sites{$self->{mainfield}}{$self->{site}}[2];
	my ($list,$nexturl)=$parse->($result);
	$self->{nexturl}=$nexturl;
	#$table->set_size_request(110*5,110*int(1+@list/5));
	push @{$self->{results}}, @$list;
	my $more= @{$self->{results}} - ($self->{page}+1) * RES_PER_PAGE;
	$self->{Bnext}->set_sensitive( $more>0 || $nexturl );
	unless (@{$self->{results}}) { stop($self,_"no matches found, you might want to remove some search terms."); return; }
	::IdleDo('8_FetchCovers'.$self,100,\&get_next,$self);
}

sub abort
{	my $self=$_[0];
	my $results=$self->{results};
	for my $r ($self,@$results)
	{	delete $r->{done};
		$r->{waiting}->abort if $r->{waiting};
		delete $r->{waiting};
	}
	delete $self->{waiting};
	delete $::ToDo{'8_FetchCovers'.$self};
}

sub stop
{	my ($self,$error)=@_;
	$self->abort;
	$self->{Bstop}->set_sensitive(0);
	#$self->{progress}->set_fraction(1);
	$self->{progress}->hide;
	if ($error)
	{	my $l=Gtk2::Label->new($error);
		$l->show;
		$self->{table}->attach($l,0,5,0,1,'fill','fill',1,1);
	}
}

sub get_next
{	my $self=shift;
	my $results=$self->{results};
	my $res_id;
	my $waiting;
	my $start= $self->{page} * RES_PER_PAGE;
	my $end= $start + RES_PER_PAGE -1;
	if ($#$results<$end && $self->{nexturl})
	{	#load next page
		$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->searchresults_cb(@_)}, url => delete $self->{nexturl}, cache=>1);
	}
	$end=$#$results if $#$results<$end;
	for my $id ($start .. $end)
	{	#warn "$id : waiting=".$results->[$id]{waiting}." done=".$results->[$id]{done};
		if ($results->[$id]{waiting}) {$waiting++; next};
		next if $results->[$id]{done};
		$res_id=$id;
		last;
	}
	unless (defined $res_id || $waiting || $self->{waiting})
	{	$self->stop;
		return;
	}
	return unless defined $res_id;
	return if $waiting && $waiting > 3; #no more than 4 pictures at once

	my $result=$self->{results}[$res_id];
	$result->{waiting}=Simple_http::get_with_cb(url => $result->{url}, cache=>1, cb =>
	sub
	{	my $pixdata=$_[0];
		$result->{waiting}=undef;
		my $loader;
		$loader= GMB::Picture::LoadPixData($pixdata,PREVIEW_SIZE) if $pixdata;
		if ($loader)
		{	my $dim=$loader->{w}.' x '.$loader->{h};
			my $table=$self->{table};
			my $pixbuf=$loader->get_pixbuf;
			my $image=Gtk2::Image->new_from_pixbuf($pixbuf);
			my $button=Gtk2::Button->new;
			$button->{pixdata}=$pixdata;
			$button->{ext}=	($Gtk2::VERSION >= 1.092)?
					  $loader->get_format->{extensions}[0]
					: ( EntryCover::_identify_pictype($pixdata) )[0];
			$button->{ext}='jpg' if $button->{ext} eq 'jpeg';
			my $vbox=Gtk2::VBox->new(0,0);
			my $label=Gtk2::Label->new($dim);
			$vbox->add($image);
			$vbox->pack_end($label,0,0,0);
			$button->add($vbox);

			my $tip='';
			$tip=$result->{desc}."\n" if $result->{desc};
			$tip.=$dim."\n".$result->{url};
			$button->set_tooltip_text($tip);
			$button->signal_connect(clicked => \&set_cover);
			$button->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb,3); # 3 : mouse button 3
			$button->set_relief('none');
			$button->show_all;
			my $i= $res_id % RES_PER_PAGE;
			my $y=int( $i/RES_PER_LINE);
			my $x= $i % RES_PER_LINE;
			$table->attach($button,$x,$x+1,$y,$y+1,'fill','fill',1,1);
			$result->{done}=1;
			$self->{loaded}++;
		}
		elsif ($result->{previewurl})
		{	$result->{originurl}=$result->{url};
			$result->{url}=delete $result->{previewurl};
		}
		else { $result->{done}='error'; $self->{loaded}++; }
		$self->{progress}->set_fraction( $self->{loaded} / ( @{$self->{results}} - RES_PER_PAGE*$self->{page} ));
		::IdleDo('8_FetchCovers'.$self,100,\&get_next,$self);
	});
	::IdleDo('8_FetchCovers'.$self,1000,\&get_next,$self);
}

sub set_cover
{	my $button=$_[0];
	my $self=::find_ancestor($button,__PACKAGE__);
	my $field=$self->{field};
	my $gid=  $self->{gid};
	my $name= Songs::Gid_to_Get($field,$gid);
	my $text;
	if ($self->{mainfield} eq 'album')
	{	$text=::__x(_"Use this picture as cover for album '{album}'", album => $name);
	}
	else
	{	$text=::__x(_"Use this picture for artist '{artist}'", artist => $name);
	}
	my $check=Gtk2::CheckButton->new( $text );
	$check->set_active(1);
	my $default_file=	$::Options{OPT.'USEFILE'} ?
				$::Options{OPT.'COVERFILE'} : $name;
	$default_file=~s/\.(?:jpe?g|png|gif)$//;
	$default_file.='.'.$button->{ext};
	$default_file=::filename_from_unicode(::CleanupFileName($default_file));
	my $default_dir=$::Options{OPT.'COVERPATH'} || '';
	$default_dir=::filename_from_unicode(::CleanupDirName($default_dir));
	$default_dir=$self->{dir} unless $::Options{OPT.'USEPATH'} && -d $default_dir;
	if ($::Options{OPT.'UNIQUE'})
	{	while (-e $default_dir.::SLASH.$default_file) #find a unique name
		{ last unless $default_file=~s/(?:_(\d+))?\.(\w+)$/'_'.($1? $1+1 : 1).".$2"/e ; }
	}
	my $file=$default_dir.::SLASH.$default_file;
	if (!$::Options{OPT.'ASK'} || -e $file)
	{$file=::ChooseSaveFile($self,_"Save picture as",
		$default_dir,$default_file,
		$check);
	}
	return unless $file;

	#write file
	{	my $fh;
		my $ok= open $fh,'>',$file;
		if ($ok)
		{	$ok= print $fh $button->{pixdata};
			unlink $file unless $ok;
		}
		unless ($ok)
		{	my $retry=::Retry_Dialog( ::__x( _"Error writing '{file}'", file => ::filename_to_utf8displayname($file) )." :\n$!." ,$self);
			redo if $retry eq 'yes';
			return;
		}
		close $fh;
	}
	return unless $check->get_active;
	AAPicture::SetPicture($field,$gid,$file);
}

1

__END__
xml.amazon.com/onca/xml3?t=webservices-20&dev-t=%l&KeywordSearch=%s&mode=music&type=heavy&locale=us&page=1&f=xml
