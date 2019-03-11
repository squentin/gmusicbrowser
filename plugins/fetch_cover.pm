# Copyright (C) 2005-2014 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin FETCHCOVER
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
	RES_PER_LINE => 6,
	PREVIEW_SIZE => 100,
	GOOGLE_USER_AGENT => 'Mozilla/5.0 Gecko/20100101 Firefox/26.0', #google checks to see if the browser can handle the "standard" image search version, instead of the "basic" version. And as of the end of 2013 the "basic" version doesn't include direct url of the images, so we need to use the "standard" version
};
use constant RES_PER_PAGE => RES_PER_LINE*RES_LINES;

my %Sites=
(artist =>
 {	googlei => [_"google images","http://images.google.com/images?q=%s&imgsz=medium|large", \&parse_googlei, GOOGLE_USER_AGENT],
	lastfm => ['last.fm',"http://www.last.fm/music/%a/+images", \&parse_lastfm],
	#discogs => ['discogs.com', "http://api.discogs.com/search?f=xml&type=artists&q=%a", \&parse_discogs],
	bing =>['bing',"http://www.bing.com/images/async?q=%s", \&parse_bing],
	yahoo =>['yahoo',"http://images.search.yahoo.com/search/images?p=%s&o=js", \&parse_yahoo],
	ddg => ["DuckDuckGo","https://duckduckgo.com/?q=%s&iax=1&ia=images", \&parse_ddg],
 },
 album =>
 {	googlei => [_"google images","http://images.google.com/images?q=%s&imgsz=medium|large&imgar=ns", \&parse_googlei, GOOGLE_USER_AGENT],
	googleihi =>[_"google images (hi-res)","http://www.google.com/images?q=%s&imgsz=xlarge|xxlarge&imgar=ns", \&parse_googlei, GOOGLE_USER_AGENT],
	yahoo =>['yahoo',"http://images.search.yahoo.com/search/images?p=%s&o=js", \&parse_yahoo],
	bing =>['bing',"http://www.bing.com/images/async?q=%s&qft=+filterui:aspect-square", \&parse_bing],
	ddg => ["DuckDuckGo","https://duckduckgo.com/?q=%s&iax=1&ia=images", \&parse_ddg],
	slothradio => ['slothradio', "http://www.slothradio.com/covers/?artist=%a&album=%l", \&parse_sloth],
	#freecovers => ['freecovers.net', "http://www.freecovers.net/api/search/%s", \&parse_freecovers], #could add /Music+CD but then we'd lose /Soundtrack #API doesn't work anymore
	#rateyourmusic=> ['rateyourmusic.com', "http://rateyourmusic.com/search?searchterm=%s&searchtype=l",\&parse_rateyourmusic], # urls results in "403 Forbidden"
	#discogs => ['discogs.com', "http://api.discogs.com/search?f=xml&type=releases&q=%s", \&parse_discogs], #not sure it should be include, request too many big files from the server
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
	my ($radio1a,$radio1b)=::NewPrefRadio(OPT.'USEPATH',[_"use song folder",0, _"use :",1]);
	my ($radio2a,$radio2b)=::NewPrefRadio(OPT.'USEFILE',[_"use album name",0,  _"use :",1]);
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
	my $mainfield=Songs::MainField($field);	#'artist' or 'album'
	my $self=bless Gtk2::Window->new;
	$self->set_border_width(4);
	my $Bsearch=::NewIconButton('gtk-find',_"Search");
	my $Bcur=Gtk2::Button->new($mainfield eq 'artist' ? _"Search for current artist" : _"Search for current album");
	::set_drag($Bcur, dest =>	[::DRAG_ID, sub { $_[0]->get_toplevel->SearchID(undef,$_[2]); }], );
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
	$Bcur->signal_connect(clicked =>sub {$_[0]->get_toplevel->SearchID(undef,$::SongID)});
	$self->signal_connect( destroy => \&abort);
	$self->signal_connect( unrealize => sub {$::Options{OPT.'winsize'}=join ' ',$_[0]->get_size; });

	my $size= $::Options{OPT.'winsize'} || RES_PER_LINE*PREVIEW_SIZE.' '.RES_LINES*PREVIEW_SIZE;
	$self->resize(split ' ',$size,2);

	$self->{mainfield}=$mainfield;
	$self->{field}=$field;
	$self->{site}=$::Options{OPT.'PictureSite_'.$mainfield};
	$self->SearchID($gid,$ID);
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
{	my ($self,$gid,$ID)=@_;	#only one of $gid and $ID needs to be defined
	$self=::find_ancestor($_[0],__PACKAGE__);
	my $field= $self->{field};
	if (!defined $ID)
	{	return unless defined $gid;
		my $list= AA::GetIDs($field,$gid);
		$ID=$list->[0];
		return unless defined $ID;
	}
	elsif (!defined $gid)
	{	$gid= Songs::Get_gid($ID,$field);
		$gid= $gid->[0] if ref $gid;	#for field like artists return an array of values, use first value
	}

	$self->{gid}= $gid;
	$self->{dir}= Songs::Get($ID,'path');
	my $search=my $name= Songs::Gid_to_Get($field,$gid);
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
	$self->{user_agent}= $Sites{$self->{mainfield}}{$self->{site}}[3];
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
	$self->{url}= $url;
	$self->{searchcontext}={}; #hash that the parser can use to store data between searches
	warn "fetchcover : loading $url\n" if $::debug;
	$self->{waiting}=Simple_http::get_with_cb
	 (	cb => sub {$self->searchresults_cb(@_)},
		url => $url,	cache=>1,
		user_agent => $self->{user_agent},
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
{	my ($results,$pageurl,$searchcontext)=@_;
	$searchcontext->{baseurl}||= $pageurl;
	my @list;
	while ($results=~m#<a\s+href="/music/[^/]+/\+images/[0-9A-F]+"[^>]+?class="image-list-link"[^<]+<img[^>]+?src="([^"]+)"#gis)
	{	my $url=my $pre=$1;
		$url=~s#/i/u/avatar170s/#/i/u/#;
		$url.='.jpg';
		push @list, {url => $url, previewurl =>$pre,};
	}
	my $nexturl;
	$nexturl= $searchcontext->{baseurl}.$1 if $results=~m#<a href="(\?page=\d+)">Next</a>#;
	return \@list,$nexturl;
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
{	my ($result,$pageurl,$searchcontext)=@_;
	$searchcontext->{baseurl}||= $pageurl;
	$searchcontext->{pagecount}++;
	my @list;
	for my $res (split /<div class="rg_meta[^"]*"[^>]*>/, $result)
	{	$res=~s/(?<!\\)\\"/\\u0022/g; #escape \" to make extraction simpler, not perfect
		next unless $res=~m#"ou":"(http[^"]+)"#i;
		my $url=$1;
		#$url=~s/%([0-9A-Fa-f]{2})/chr hex($1)/gie;
		#$searchcontext->{rescount}++;
		my $preview= $res=~m/"tu":"([^"]+)"/ ? $1 : undef;
		my $ref= $res=~m/"ru":"([^"]+)"/ ? $1 : undef;
		my $desc= $res=~m/"pt":"([^"]+)"/ ? Encode::decode('utf8',$1) : undef;
		for ($url,$desc,$ref,$preview) { s/\\u([0-9A-F]{4})/chr(hex($1))/eig; } #FIXME maybe use proper json decoding library
		push @list, {url => $url, previewurl =>$preview, desc => $desc, referer=>$ref };
	}
	my $nexturl= $searchcontext->{baseurl}."&ijn=".$searchcontext->{pagecount};
	$nexturl=undef unless @list;
	return \@list,$nexturl;
}

# to get more results than the 35 on the first page, it uses the first= url argument, but it behaves strangely, in particular it includes results from previous pages, so these are ignored. The final results are not exactly those you get from the web page, but it seems good enough
sub parse_bing
{	my ($result,$pageurl,$searchcontext)=@_;
	$searchcontext->{baseurl}||= $pageurl;
	my $seen= $searchcontext->{seen}||= {};
	my @list;
	while ($result=~m/\s+m="([^"]+)"/g)
	{	my $metadata= ::decode_html(Encode::decode('utf8',$1));
		#warn $metadata;
		next unless $metadata=~m/"murl":"([^"]+)"/i;
		my $url=$1;
		my $purl= $metadata=~m/"purl":"([^"]+)"/i ? $1 : undef;
		my $turl= $metadata=~m/"turl":"([^"]+)"/i ? $1 : undef;
		#if ($seen->{$url}) { warn "result #".(++$searchcontext->{count})." was already found as #".$seen->{$url}."\n" } #DEBUG
		next if $seen->{$url};
		$seen->{$url}= ++$searchcontext->{count};
		push @list, { url=>$url, previewurl=>$turl, referer=>$purl };
		next;
	}
	my $n= ++$searchcontext->{pagecount};
	my $nexturl= $searchcontext->{baseurl}."&first=".(1+$n*100)."&count=100";
	$nexturl=undef unless @list;
	return \@list,$nexturl;
}

sub parse_yahoo
{	my ($result,$pageurl,$searchcontext)=@_;
	$searchcontext->{baseurl}||= $pageurl;
	my @list;
	if ($result=~m/^{"html":/) { $result=~s#\\(.)#$1#g; } # with the o=js parameter the result html is in a js file -> un-escape (the data is smaller with o=js)
	while ($result=~m/<li class="ld ?"([^>]+)><a +(?:target="[^"]*" +)?href=([^>]+)>(?:<img src=['"]([^'"]+)['"])?/g)
	{	my $href=$2;
		my $preview=$3;
		next unless $href=~m/imgurl=([^&"']+)[&"']/;
		my $url= 'http://'.::decode_url($1);
		my $desc;
		if ($href=~m/aria-label=["']([^"']+)["']/)
		{	$desc=$1;
			$desc=~s#&lt;/?b&gt;##g; #remove escaped bold markup around matched strings
			$desc=Encode::decode('utf8',$desc);
			$desc= ::decode_html(::decode_html($desc));
		}
		push @list, {url => $url, previewurl =>$preview, desc => $desc };
	}
	my $n= ++$searchcontext->{pagecount};
	my $nexturl= $searchcontext->{baseurl}."&b=".(1+$n*60)."&iid=Y.$n&spos".($n*12); # no idea what the parameters mean, they don't match the number of results, but it works ...
	return \@list,$nexturl;
}

sub parse_ddg
{	my ($result,$pageurl,$searchcontext)=@_;
	unless ($searchcontext->{vqd})
	{	#request to i.js don't work without a vqd number, get it from the first page
		my $vqd= $result=~m/vqd=(\d+)/ ? $1 : 0;
		my $q= $result=~m/\?q=([^&"]+)[&"]/ ? $1 : 0;
		my $url= $vqd && $q ? "https://duckduckgo.com/i.js?o=json&q=$q&vqd=$vqd&p=1" : undef;
		$searchcontext->{vqd}=$vqd;
		return [],$url,!!$url; #third return paremeter true means get next url even though no results in this query
	}
	my (@list,$nexturl);
	# for some reason next pages return some previous results, use $searchcontext->{seen} to ignore them
	my $seen= $searchcontext->{seen}||= {};
	$nexturl= 'https://duckduckgo.com/'.$1 if $result=~m#"next"\s*:\s*"(i.js[^"]+)#;
	for my $res (split /}\s*,\s*{/,$result)
	{	my @kv= $res=~m#("[^"]+"|[^:]+)\s*:\s*("[^"]*"|[^,}]*)\s*,?#g;
		s/^"([^"]*)"$/$1/ for @kv;
		my %h= @kv;
		next unless $h{image};
		$h{title}=~s#\\u(....)#chr(hex($1))#eg;
		my $url= $h{image};
		#if ($seen->{$url}) { warn "result #".($searchcontext->{count}+1)." : found previous result $seen->{$url}\n"; }
		next if $seen->{$url};
		$seen->{$url}= ++$searchcontext->{count};
		push @list, {url=> $url, previewurl=> $h{thumbnail}, desc=> $h{title}, referer=> $h{url}, };
	}
	return \@list,$nexturl;
}

sub parse_discogs
{	my $result = $_[0];
	my @list;
	while ($result =~ m#<thumb>([^<]+?)/(A|R)-(\d+)-([^<]+?)</thumb>#g)
	{	my $referer= $2 eq 'R' ? "http://www.discogs.com/viewimages?release=$3" : "";
		push @list, {url => "$1/$2-$4", previewurl => "$1/$2-$3-$4", referer=> $referer, };
	}
	return \@list;
}

sub searchresults_cb
{	my ($self,$result)=@_;
	$self->{waiting}=undef;
	warn "Getting results from $self->{url}\n" if $::Verbose;
	unless (defined $result) { stop($self,_"connection failed."); return; }
	my $parse= $Sites{$self->{mainfield}}{$self->{site}}[2];
	my ($list,$nexturl,$ignore0)=$parse->($result,$self->{url},$self->{searchcontext});
	$self->{nexturl}=$nexturl;
	#$table->set_size_request(110*5,110*int(1+@list/5));
	push @{$self->{results}}, @$list;
	my $more= @{$self->{results}} - ($self->{page}+1) * RES_PER_PAGE;
	$self->{Bnext}->set_sensitive( $more>0 || $nexturl );
	unless ($ignore0 || @{$self->{results}}) { stop($self,_"no matches found, you might want to remove some search terms."); return; }
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
		my $url= $self->{url}= delete $self->{nexturl};
		$self->{waiting}=Simple_http::get_with_cb
		 (	cb => sub {$self->searchresults_cb(@_)},
			url => $url,	cache=>1,
			user_agent => $self->{user_agent},
		 );
	}
	elsif ($#$results>=$end)
	{	$self->{Bnext}->set_sensitive(1);
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
	$result->{waiting}=Simple_http::get_with_cb(url => $result->{url}, referer=>$result->{referer}, cache=>1, cb =>
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
			$button->{url}= $result->{url};
			my $vbox=Gtk2::VBox->new(0,0);
			my $label=Gtk2::Label->new($dim);
			$vbox->add($image);
			$vbox->pack_end($label,0,0,0);
			$button->add($vbox);

			my $tip='';
			$tip=::PangoEsc($result->{desc})."\n" if $result->{desc};
			$tip.=$dim."\n".::MarkupFormat("<small>%s</small>",$result->{url});
			$button->set_tooltip_markup($tip);
			$button->signal_connect(clicked => \&set_cover);
			$button->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb,3); # 3 : mouse button 3
			::set_drag($button, source=> [::DRAG_FILE,sub { return ::DRAG_FILE,$_[0]{url} }]);
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
	$default_file=~s/$::Image_ext_re//;
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
		{	my $retry=::Retry_Dialog($!,_"Error saving picture", details=>::__x( _"Error writing '{file}'", file => ::filename_to_utf8displayname($file) ), window=>$self);
			redo if $retry eq 'retry';
			return;
		}
		close $fh;
	}
	return unless $check->get_active;
	AAPicture::SetPicture($field,$gid,$file);
}

1

