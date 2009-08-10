# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;

package Songs;

#our %Songs;
#our %Slot; our $SlotCount=0;
our $IDFromFile;
#our $re_artist;
my (@Missing,$MissingHash,@MissingKeyFields);
our (%Def,%Types,@Fields,%GTypes,%HSort);
my %FuncCache;
INIT {
our %timespan_menu=
(	year 	=> _("year"),
	month	=> _("month"),
	day	=> _("day"),
);
@MissingKeyFields=qw/size title album artist track/;
%Types=
(	generic	=>
	{	_	=> '____[#ID#]',
		get	=> '#_#',
		set	=> '#get# = #VAL#',
		display	=> '#get#',
		grouptitle=> '#display#',
		'editwidget'		=> sub { my $field=$_[0]; GMB::TagEdit::Combo->new(@_,$Def{$field}{edit_listall}); },
		'editwidget:per_id'	=> sub { my $field=$_[0]; GMB::TagEdit::EntryString->new(@_,$Def{$field}{editwidth}); },
		'filter:m'	=> '#display# .=~. m"#VAL#"',			'filter_prep:m'	=> \&Filter::QuoteRegEx,
		'filter:mi'	=> '#display# .=~. m"#VAL#"i',			'filter_prep:mi'=> \&Filter::QuoteRegEx,
		'filter:s'	=> 'index( lc(#display#),"#VAL#") .!=. -1',	'filter_prep:s'	=> sub {quotemeta lc($_[0])},
		'filter:S'	=> 'index(    #display#, "#VAL#") .!=. -1',	'filter_prep:S'	=> sub {quotemeta $_[0]},
	},
	unknown	=>
	{	parent	=> 'generic',
	},
	virtual =>
	{	parent	=> 'string',
#		_	=> '#get#',
	},
	flags	=>
	{	_		=> '____[#ID#]',
		init		=> '___name[0]="#none#"; ___iname[0]=::superlc(___name[0]); #sgid_to_gid(VAL=$_)# for #init_namearray#',
		init_namearray	=> '()',
		default		=> '""',
		check		=> ';',
		get_list	=> 'my $v=#_#; ref $v ? map(___name[$_], @$v) : $v ? ___name[$v] : ();',
		get_gid		=> 'my $v=#_#; ref $v ? $v : [$v]',
		gid_to_get	=> '(#GID# ? ___name[#GID#] : "")',
		gid_to_display	=> '___name[#GID#]',
		's_sort:gid'	=> '___name[#GID#]',
		'si_sort:gid'	=> '___iname[#GID#]',
		get		=> 'do {my $v=#_#; !$v ? "" : ref $v ? join "\\x00",map ___name[$_],@$v : ___name[$v];}',
		newval		=> 'push @___iname, ::superlc(___name[-1]); ::IdleDo("newgids_#field#",1000,sub {  ___new=0; ::HasChanged("newgids_#field#"); }) unless ___new++;',
		sgid_to_gid	=> '___gid{#VAL#}||= do { my $i=push(@___name, #VAL#); #newval#; $i-1; }',
		set => '{my $v=#VAL#;
			my @list= sort (ref $v ? @$v : split /\\x00/,$v);
			my @ids;
			for my $name (@list)
			{	my $id= #sgid_to_gid(VAL=$name)#;
				push @ids,$id;
			}
			#_#=	@ids<2 ? $ids[0]||0 :
				(___group{join(" ",map sprintf("%x",$_),@ids)}||= \@ids);}',
		diff		=> 'do {my $v=#_#; my $old=!$v ? "" : ref $v ? join "\\x00",map ___name[$_],@$v : ___name[$v]; $v=#VAL#; my $new= join "\\x00", sort (ref $v ? @$v : split /\\x00/,$v); $old ne $new; }', #FIXME use simpler/faster version if perl5.10
		display 	=> 'do { my $v=#_#; !$v ? "" : ref $v ? join ", ",map ___name[$_],@$v : ___name[$v]; }',
		set_multi	=> 'do {my $c=#_#; my %h=( $c ? ref $c ? map((___name[$_]=>0), @$c) : (___name[$c]=>0) : ()); my $changed; my ($toadd,$torm,$toggle)=@{#VAL#}; $h{$_}++ for @$toadd; $h{$_}-- for @$torm; (scalar grep $h{$_}!=0, keys %h) ? [grep $h{$_}>=0, keys %h] : undef; }',
		makefilter	=> '#GID# ? "#field#:~:".___name[#GID#] : "#field#:ecount:0"',
		'filter:~'	=> '.!!. do {my $v=#_#; $v ? ref $v ? grep(#VAL#==$_, @$v) : ($v == #VAL#) : 0}', # is flag set #FIXME use simpler/faster version if perl5.10
		'filter_prep:~'	=> '___gid{#PAT#} ||= #sgid_to_gid(VAL=#PAT#)#;',
		'filter_prephash:~' => 'return { map { #sgid_to_gid(VAL=$_)#, undef } keys %{#HREF#} }',
		'filter:h~'	=> '.!!. do {my $v=#_#; $v ? ref $v ? grep(exists $hash#VAL#->{$_+0}, @$v) : (exists $hash#VAL#->{#_#+0}) : 0}',
		'filter:ecount'	=> '#VAL# .==. do {my $v=#_#; $v ? ref $v ? scalar(@$v) : 1 : 0}',
		#FIXME for filters s,m,mi,h~,  using a list of matching names in ___inames/___names could be better (using a bitstring)
		'filter:s'	=> 'do { my $v=#_#; !$v ? 0 : ref $v ? (grep index(___iname[$_], "#VAL#") .!=. -1 ,@$v) : (index(___iname[$v], "#VAL#") .!=. -1); }',
		'filter:S'	=> 'do { my $v=#_#; !$v ? 0 : ref $v ? (grep index(___name[$_], "#VAL#")  .!=. -1 ,@$v) : (index(___name[$v], "#VAL#")  .!=. -1); }',
		'filter:m'	=> 'do { my $v=#_#; !$v ? 0 : ref $v ? (grep ___name[$_]  .=~. m"#VAL#"  ,@$v) : ___name[$v]  .=~. m"#VAL#"; }',
		'filter:mi'	=> 'do { my $v=#_#; !$v ? 0 : ref $v ? (grep ___iname[$_] .=~. m"#VAL#"i ,@$v) : ___iname[$v] .=~. m"#VAL#"i; }',
		stats		=> 'do {my $v=#_#; #HVAL#{$_+0}=undef for ref $v ? @$v : $v;}  ----  #HVAL#=[map ___name[$_], keys %{#HVAL#}];',
		'stats:gid'	=> 'do {my $v=#_#; #HVAL#{$_+0}=undef for ref $v ? @$v : $v;}',
		hashm		=> 'do {my $v=#_#; ref $v ? @$v : $v }', #FIXME avoid stringification
		'hashm:name'	=> 'do {my $v=#_#; ref $v ? map(___name[$_], @$v) : $v ? ___name[$v] : () }',
		is_set		=> 'my $gid=___gid{#VAL#}; my $v=#_#; $gid ? ref $v ? (grep $_==$gid, @$v) : $v==$gid : 0;',
		listall		=> '1..$#___name',
		'editwidget:many'	=> sub { GMB::TagEdit::EntryMassList->new(@_) },
		'editwidget:single'	=> sub { GMB::TagEdit::FlagList->new(@_) },
		'editwidget:per_id'	=> sub { GMB::TagEdit::FlagList->new(@_) },
	},
	artists	=>
	{	_		=> '____[#ID#]',
		mainfield	=> 'artist',
		#plugin		=> 'picture',
		_name		=> '__#mainfield#_name[#_#]',
		get_gid		=> 'my $v=#_#; ref $v ? $v : [$v]',
		's_sort:gid'	=> '__#mainfield#_name[#GID#]',
		'si_sort:gid'	=> '__#mainfield#_iname[#GID#]',
		#display	=> '##mainfield#->display#',
		get_list	=> 'split /$::re_artist/o, ##mainfield#->get#', #use artist field directly, maybe do this for all of artists ?
		gid_to_get	=> '(#GID#!=1 ? __#mainfield#_name[#GID#] : "")', # or just '__#mainfield#_name[#GID#]' ?
		gid_to_display	=> '__#mainfield#_name[#GID#]',
		update	=> 'my @list= split /$::re_artist/o, ##mainfield#->get#;
			my @ids;
			for my $name (@list)
			{	my $id= ##mainfield#->sgid_to_gid(VAL=$name)#;
				push @ids,$id;
			}
			#_# =	@ids==1 ? $ids[0] :
				@ids==0 ? 0 :
				(___group{join(" ",map sprintf("%x",$_),@ids)}||= \@ids);',
		'filter:m'	=> '_name .=~. m"#VAL#"',
		'filter:mi'	=> '_name .=~. m"#VAL#"i',
		'filter:s'	=> 'index( lc(_name),"#VAL#") .!=. -1',
		'filter:S'	=> 'index(    _name, "#VAL#") .!=. -1',
		'filter:e'	=> '_name .eq. "#VAL#"',
		'filter:~'	=> '(ref #_# ?  (grep $_ .==. #VAL#, @{#_#}) : (#_# .==. #VAL#))',#FIXME use simpler/faster version if perl5.10 (with ~~)
		'filter_prep:~'	=> '##mainfield#->filter_prep:~#',
		'filter_prephash:~' => '##mainfield#->filter_prephash:~#',
		'filter_simplify:~' => sub { split /$::re_artist/o,$_[0] },
		'filter:h~'	=> '(ref #_# ?  (grep .!!. exists $hash#VAL#->{$_+0}, @#_#) : (.!!. exists $hash#VAL#->{#_#+0}))',
		makefilter	=> '"#field#:~:".##mainfield#->gid_to_sgid#',
		#group		=> '#_# !=',
		stats		=> 'do {my $v=#_#; #HVAL#{__#mainfield#_name[$_]}=undef for ref $v ? @$v : $v;}  ----  #HVAL#=[keys %{#HVAL#}];',
		'stats:gid'	=> 'do {my $v=#_#; #HVAL#{$_}=undef for ref $v ? @$v : $v;}  ----  #HVAL#=[keys %{#HVAL#}];',
		hashm		=> 'do {my $v=#_#; ref $v ? @$v : $v}', #FIXME avoid stringification
		listall		=> '##mainfield#->listall#',
	},
	artist_first =>
	{	parent	=> 'artist', #FIXME
		_	=> 'do {my $v=__artists__[#ID#]; ref $v ? $v->[0] : $v}',
		#update	=> ';',
		init	=> ';', #FIXME
	},
	artist	=>
	{	#set		=> '#_#= (#VAL# eq "" ? 0 : (__#mainfield#_gid{#VAL#}||= (push @__#mainfield#_name, #VAL#)-1));',
		parent		=> 'fewstring',
		mainfield	=> 'artist',
		pic_cache_id	=> 'a',
		init		=> '____=""; __#mainfield#_gid{""}=1; #_iname#[1]=::superlc( #_name#[1]=_("<Unknown>") );',
		get		=> 'do {my $v=#_#; $v!=1 ? #_name#[$v] : "";}',
		gid_to_get	=> '(#GID#!=1 ? #_name#[#GID#] : "")',
		gid_to_sgid	=> '(#GID#!=1 ? #_name#[#GID#] : "")',
		makefilter	=> '"#field#:~:" . #gid_to_sgid#',
		diff		=> 'do {my $old=#_#; ($old!=1 ? #_name#[$old] : "") ne #VAL# }',
		#save_extra	=> 'my %h; for my $gid (2..$##_name#) { my $v=__#mainfield#_picture[$gid]; next unless defined $v; ::_utf8_on($v); $h{ #_name#[$gid] }=$v; } return artist_pictures',
		listall		=> '2..@#_name#-1',
		load_extra	=> '__#mainfield#_gid{#SGID#} || return;',
		save_extra	=> 'my %h; while ( my ($sgid,$gid)=each %__#mainfield#_gid ) { $h{$sgid}= [#SUBFIELDS#] } delete $h{""}; return \%h;',
		#plugin		=> 'picture',
	},
	album	=>
	{	parent		=> 'fewstring',
		mainfield	=> 'album',
		pic_cache_id	=> 'b',
		_empty		=> 'vec(__#mainfield#_empty,#_#,1)',
		unknown		=> '_("<Unknown>")." "',
		init		=> '____=""; __#mainfield#_gid{"\\x00"}=1; __#mainfield#_empty=""; vec(__#mainfield#_empty,1,1)=1; #_iname#[1]=::superlc( #_name#[1]=_("<Unknown>") );',
		findgid		=> 'do{	my $name=#VAL#; my $sgid= $name ."\\x00". ($name eq "" ?	"artist=".#artist->get# :	do {my $a=#album_artist_raw->get#; $a ne "" ?	"album_artist=$a" :	#compilation->get# ?	"compilation=1" : ""}	);
					__#mainfield#_gid{$sgid}||= do {my $n=@#_name#; if ($name eq "") {vec(__#mainfield#_empty,$n,1)=1; $name=#unknown#.#artist->get#; } push @#_name#,$name; #newval#; $n; }
				    };',
		#possible sgid : album."\x00".	""				if no album name and no artist
		#				"artist=".artist		if no album name
		#				"album_artist"=album_artist	if non-empty album_artist
		#				"compilation=1"			if empty album_artist, compilation flag set
		#				""
		set		=> '#_#= #findgid#;',
		#newval		=> 'push @#_iname#, ::superlc( #_name#[-1] );',
		get		=> '(#_empty# ? "" : #_name#[#_#])',
		gid_to_get	=> '(vec(__#mainfield#_empty,#GID#,1) ? "" : #_name#[#GID#])',
		sgid_to_gid	=> 'do {my $s=#VAL#; __#mainfield#_gid{$s}||= do { my $n=@#_name#; if ($s=~s/\x00(\w+)=(.*)$// && $s eq "" && $1 eq "artist") { $s= #unknown#.$2; vec(__#mainfield#_empty,$n,1)=1;} push @#_name#,$s; #newval#; $n }}',
		#gid_to_sgid	=> 'vec(__#mainfield#_empty,#GID#,1) ? "\\x00".substr(#_name#[#GID#],length(#unknown#)) : #_name#[#GID#]',
		gid_to_sgid	=> '::first {$__#mainfield#_gid{$_}==#GID#} keys %__#mainfield#_gid;', #slower but more simple and reliable
		makefilter	=> '"#field#:~:" . #gid_to_sgid#',
		update		=> 'my $old=#get#; #_#= #findgid(VAL=$old)#;',
		listall		=> 'grep !vec(__#mainfield#_empty,$_,1), 2..@#_name#-1',
		#plugin		=> 'picture',
		load_extra	=> ' __#mainfield#_gid{#SGID#} || return;',
		save_extra	=> 'my %h; while ( my ($sgid,$gid)=each %__#mainfield#_gid ) { $h{$sgid}= [#SUBFIELDS#] } delete $h{""}; return \%h;',

#warn $Songs::Songs_album_picture__[1636];
#warn Songs::Picture(1636,"album","get");
#warn Songs::Code('album',"get_picture",GID=>'$_[0]')
		#load_extra	=> '___pix[ #sgid_to_gid(VAL=$_[0])# ]=$_[1];',
		#save_extra	=> 'my @res; for my $gid (1..$##_name#) { my $v=___pix[$gid]; next unless length $v; push @res, [#*:gid_to_sgid(GID=$gid)#,$val]; } return \@res;',
	},
	string	=>
	{	parent		=> 'generic',
		default		=> '""',
		check		=> '#VAL#=~s/\s+$//; #VAL#=~tr/\x1D\x00//d;',	#remove trailing spaces and \x1D\x00
		diff		=> '#_# ne #VAL#',
		s_sort		=> '#_#',
		'filter:e'	=> '#_# .eq. "#VAL#"',
		hash		=> '#_#',
		group		=> '#_# ne',
		stats		=> '#HVAL#{#_#}=undef;  ---- #HVAL#=[keys %{#HVAL#}];',
	},
	istring => # _much_ faster with case/accent insensitive operations, at the price of double memory
	{	parent	=> 'string',
		_iname	=> '___iname[#ID#]',
		set	=> '#_# = #VAL#; #_iname#= ::superlc(#VAL#);',
		si_sort	=> '#_iname#',
		'filter:s'	=> 'index( #_iname#,"#VAL#") .!=. -1',	'filter_prep:s'	=> sub { quotemeta ::superlc($_[0])},
	},
	filename=>
	{	parent	=> 'string',
		check	=> ';',	#override string's check because not needed and filename may not be utf8
		get	=> '::decode_url(#_#)',
		set	=> '#_#=::url_escape(#VAL#);',
		display	=> '::filename_to_utf8displayname(#get#)',
		hash_to_display => '::filename_to_utf8displayname(::decode_url(#VAL#))', #only used by FolderList::
		load	=> '#_#=#VAL#',
		save	=> '#_#',
	},
# 	picture =>
#	{	get_picture	=> '__#mainfield#_picture[#GID#] || $::Options{Default_picture_#mainfield#};',
#		get_pixbuf	=> 'my $file= #get_picture#; ::PixBufFromFile($file);',
#		set_picture	=> '::_utf8_off(#VAL#); __#mainfield#_picture[#GID#]= #VAL# eq "" ? undef : #VAL#; ::HasChanged("Picture_#mainfield#",#GID#);',
#		'load_extra:picture'	=> 'if (#VAL# ne "") { __#mainfield#_picture[#GID#]= ::decode_url(#VAL#); }',
#		'save_extra:picture'	=> 'do { my $v=__#mainfield#_picture[#GID#]; defined $v ? ::url_escape($v) : ""; }',
#	},
 	_picture =>
	{	_		=> '__#mainfield#_picture[#GID#]',
		init		=> '@__#mainfield#_picture=(); push @AAPicture::ArraysOfFiles, \@__#mainfield#_picture;',
		default		=> '$::Options{Default_picture}{#mainfield#}',
		get_for_gid	=> '#_# || #default#;',
		pixbuf_for_gid	=> 'my $file= #get_for_gid#; ::PixBufFromFile($file);',#FIXME use a cache
		set_for_gid	=> '::_utf8_off(#VAL#); #_#= #VAL# eq "" ? undef : #VAL#; ::HasChanged("Picture_#mainfield#",#GID#);',
		load_extra	=> 'if (#VAL# ne "") { #_#= ::decode_url(#VAL#); }',
		save_extra	=> 'do { my $v=#_#; defined $v ? ::url_escape($v) : ""; }',
		get		=> '__#mainfield#_picture[ #mainfield->get_gid# ]',
	},
	_stars =>	#FIXME not used everywhere
	{	_		=> 'sprintf("%d",#GID# * #nbpictures# /100)',
		pixbuf_for_gid	=> 'my $r= #_#; __#mainfield#_pixbuf[$r] ||= ::PixBufFromFile( "#fileprefix#".$r.".png" );',
	},
	fewstring=>	#for strings likely to be repeated
	{	_		=> 'vec(____,#ID#,#bits#)',
		bits		=> 32,	#32 bits by default (16 bits ?)
		mainfield	=> '#field#',
		_name		=> '__#mainfield#_name',
		_iname		=> '__#mainfield#_iname',
		sgid_to_gid	=> '__#mainfield#_gid{#VAL#}||= do { my $i=push(@#_name#, #VAL#); #newval#; $i-1; }',
		newval		=> 'push @#_iname#, ::superlc( #_name#[-1] );',
		#newval		=> 'push @#_iname#, ::superlc(#VAL#);',
		set		=> '#_# = #sgid_to_gid#;',
		init		=> '____=""; __#mainfield#_gid{""}=1; #_name#[1]=#_iname#[1]="";',
		check		=> '#VAL#=~s/\s+$//; #VAL#=~tr/\x1D\x00//d;',
		default		=> '""',
		get_gid		=> '#_#',
		get		=> '#_name#[#_#]',
		diff		=> '#get# ne #VAL#',
		display 	=> '#get#',
		s_sort		=> '#_name#[#_#]',
		si_sort		=> '#_iname#[#_#]',
		gid_to_get	=> '#_name#[#GID#]',
		's_sort:gid'	=> '#_name#[#GID#]',
		'si_sort:gid'	=> '#_iname#[#GID#]',
		gid_to_display	=> '#_name#[#GID#]',
		'filter:m'	=> '#_name#[#_#]  .=~. m"#VAL#"',
		'filter:mi'	=> '#_iname#[#_#] .=~. m"#VAL#"i',
		'filter:s'	=> 'index( #_iname#[#_#],"#VAL#") .!=. -1',	'filter_prep:s'	=> sub { quotemeta ::superlc($_[0])},
		'filter:S'	=> 'index( #_name#[#_#], "#VAL#") .!=. -1',
		'filter:e'	=> '#_name#[#_#] .eq. "#VAL#"',
		'filter:~'	=> '#_# .==. #VAL#',				'filter_prep:~' => '#sgid_to_gid(VAL=#PAT#)#',
				'filter_prephash:~' => 'return {map { #sgid_to_gid(VAL=$_)#,undef} keys %{#HREF#}}',
		'filter:h~'	=> '.!!. exists $hash#VAL#->{#_#}',
#		hash		=> '#_name#[#_#]',
		hash		=> '#_#',
		#"hash:gid"	=> '#_#',
		gid_search	=> '#_name#[#GID#] =~ m/#RE#/',
		gid_isearch	=> '#_iname#[#GID#] =~ m/#RE#/',
		makefilter	=> '"#field#:~:".#_name#[#GID#]',
		group		=> '#_# !=',
		stats		=> '#HVAL#{#_name#[#_#]}=undef;  ----  #HVAL#=[keys %{#HVAL#}];',
		'stats:gid'	=> '#HVAL#{#_#}=undef;  ----  #HVAL#=[keys %{#HVAL#}];',
		listall		=> '2..@#_name#-1',
		parent		=> 'generic',
		#gsummary	=> 'my $gids=Songs::UniqList(#field#,#IDs#); @$gids==1 ? #gid_to_display(GID=$gids->[0])# : #names(count=scalar @$gids)#;',
	},
	number	=>
	{	parent		=> 'generic',
		set		=> '#_# = #VAL#||0',
		########save		=> '(#_# || "")',
		n_sort		=> '#_#',
		'n_sort:gid'	=> '#GID#',
		diff		=> '#_# != #VAL#',
		'filter:e'	=> '#_# .==. #VAL#',
		'filter:>'	=> '#_# .>. #VAL#',
		'filter:<'	=> '#_# .<. #VAL#',
		'filter:b'	=> '#_# .>=. #VAL1#  .&&.  #_# .<. #VAL2#',
		'group'		=> '#_# !=',
		'stats:range'	=> 'push @{#HVAL#},#_#;  ---- #HVAL#=do {my ($m0,$m1)=(sort {$a <=> $b} @{#HVAL#})[0,-1]; $m0==$m1 ? $m0 : "$m0 - $m1"}',
		'stats:sum'	=> '#HVAL# += #_#;',
		stats		=> '#HVAL#{#_#+0}=undef;',
		hash		=> '#_#+0',
		display		=> '(#_# ? sprintf("#displayformat#", #_# ) : "")',	#replace 0 with ""
		gid_to_display	=> '#GID#',
		makefilter	=> '"#field#:e:#GID#"',
		default		=> '0+0',	#not 0 because it needs to be true :(
		filter_prep	=>  sub { $_[0]=~m/(\d+(?:\.\d+)?)/; return $1 || 0},
	},
	'number.div' =>
	{	group		=> 'int(#_#/#ARG0#) !=',
		hash		=> 'int(#_#/#ARG0#)',		#hash:minute	=> '60*int(#_#/60)',
		#makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".(#GID# * #ARG0#)." ".((#GID#+1) * #ARG0#))',
		makefilter	=> '"#field#:b:".(#GID# * #ARG0#)." ".((#GID#+1) * #ARG0#)',
		gid_to_display	=> '#GID# * #ARG0#',
	},
	fewnumber =>
	{	_		=> '___value[vec(____,#ID#,#bits#)]',
		parent		=> 'number',
		bits		=> 16,
		init		=> '____=""; ___value[0]=undef;',
		set		=> 'vec(____,#ID#,#bits#) = ___gid{#VAL#}||= do { push(@___value, #VAL#+0)-1; }',
		check		=> '#VAL#= #VAL# =~m/^(\d*(?:\.\d+)?)$/ ? $1 : 0;',
		displayformat	=> '%d',
	},
	integer	=>
	{	_		=> 'vec(____,#ID#,#bits#)',
		displayformat	=> '%d',
		bits		=> 32, 				#use 32 bits by default
		#check		=> '#VAL#= #VAL# =~m/^(\d+)$/ ? $1 : 0;',
		check		=> '#VAL#= #VAL# =~m/^(\d+)/ && $1<2**#bits# ? $1 : 0;',	# set to 0 if overflow
		init		=> '____="";',
		parent		=> 'number',
		'editwidget:all'=> sub { my $field=$_[0]; GMB::TagEdit::EntryNumber->new(@_,$Def{$field}{edit_max}); },
	},
	float	=>	#make sure the string doesn't have the utf8 flag, else substr won't work
	{	_		=> 'unpack("F",substr(____,#ID#<<3,8))',
		displayformat	=> '%.2f',
		init		=> '____=" "x8;', #needs init for ID==0
		parent		=> 'number',
		set		=> 'substr(____,#ID#<<3,8)=pack("F",#VAL#)',
		check		=> '#VAL#= #VAL# =~m/^(\d*(?:\.\d+)?)$/ ? $1 : 0;',
		# FIXME make sure that locale is set to C (=> '.' as decimal separator) when needed
		'editwidget:all'=> sub { GMB::TagEdit::EntryNumber->new(@_,undef,3); },
	},
	'length' =>
	{	display	=> 'sprintf("%d:%02d", #_#/60, #_#%60)',
		parent	=> 'integer',
	},
	'length.div' => { gid_to_display	=> 'my $v=#GID# * #ARG0#; sprintf("%d:%02d", $v/60, $v%60);', },
	rating	=>
	{	parent	=> 'integer',
		bits	=> 8,
		_	=> 'vec(____,#ID#,#bits#)',
		_default=> 'vec(___default_,#ID#,#bits#)',
		init	=> '____ = ___default_ = "";',
		default	=> '""',
		get	=> '(#_#==255 ? "" : #_#)',
		display	=> '(#_#==255 ? "" : #_#)',
		check	=> '#VAL#= #VAL# =~m/^\d+$/ ? (#VAL#>100 ? 100 : #VAL#) : 255;',
		set	=> '{ my $v=#VAL#; #_default#= ($v eq "" ? $::Options{DefaultRating} : $v); #_# = ($v eq "" ? 255 : $v); }',
		'filter:e'	=> '#_# .==. #VAL#',		'filter_prep:e' =>  sub { $_[0] eq "" ? 255 : $_[0]=~m/(\d+(?:\.\d+)?)/ ? $1 : 0},
		'filter:>'	=> '#_default# .>. #VAL#',
		'filter:<'	=> '#_default# .<. #VAL#',
		'filter:b'	=> '#_default# .>=. #VAL1#  .&&. #_default# .<. #VAL2#',
		n_sort		=> '#_default#',
		#array		=> '#_default#',
		gid_to_display	=> '#GID#==255 ? _"Default" : #GID#',
		percent		=> '#_default#', #for random mode
		update		=> '___default_=____; my $d=pack "C",$::Options{DefaultRating}; ___default_=~s/\xff/$d/g;',	#\xff==255 # called when $::Options{DefaultRating} has changed
		#"hash:gid"	=> '#_#',
		hash		=> '#_#',
		'editwidget:all'	=> sub {GMB::TagEdit::EntryRating->new(@_) },
	},
	date	=>
	{	parent	=> 'integer',
		display	=> 'Songs::DateString(#_#)',
		daycount=> 'do { my $t=(time-( #_# ) )/86400; ($t<0)? 0 : $t}', #for random mode
		filter_prep	=> \&::ConvertTime,
		 #for date.year, date.month, date.day :
		group	=> '#mktime# !=',
		get_gid	=> '#_# ? #mktime# : 0',
		hash	=> '(#_# ? #mktime# : 0)',	#or use post-hash modification for 0 case
		subtypes_menu=> \%timespan_menu,
		grouptitle=> 'my $gid=#get_gid#; #gid_to_display(GID=$gid)#;',
	},
	'date.year' =>
	{	mktime	=> '::mktime(0,0,0,1,0,(localtime(#_#))[5])',
		gid_to_display => '(#GID# ? ::strftime("%Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".(::mktime(0,0,0,1,0,(localtime(#GID#))[5]+1)-1))',
	},
	'date.month' =>
	{	mktime	=> '::mktime(0,0,0,1,(localtime(#_#))[4,5])',
		gid_to_display => '(#GID# ? ::strftime("%b %Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".do{my ($m,$y)= (localtime(#GID#))[4,5]; ::mktime(0,0,0,1,$m+1,$y)-1})',
	},
	'date.day' =>
	{	mktime	=> '::mktime(0,0,0,(localtime(#_#))[3,4,5])',
		gid_to_display => '(#GID# ? ::strftime("%x",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".do{my ($d,$m,$y)= (localtime(#GID#))[3,4,5]; ::mktime(0,0,0,$d+1,$m,$y)-1})',
	},
	boolean	=>
	{	parent	=> 'integer',	bits => 1,
		display	=> "(#_# ? '#yes#' : '#no#')",	yes => _"Yes",	no => "",
		'editwidget:all'=> sub { my $field=$_[0]; GMB::TagEdit::EntryBoolean->new(@_); },
	},
	shuffle=>
	{	#shuffle	=> 'vec(____,$_,32)=rand(256**4) for FIRSTID..$LastID',
		n_sort		=> 'vec(____,#ID#,32)',
		update		=> 'vec(____,#ID#,32)=rand(256**4)',	#FIXME
		init		=> '____="";',
	},
);
%Def=		#flags : Read Write Editable Sortable Column caseInsensitive sAve List Gettable
(file	=>
 {	name	=> _"Filename",	width => 400, flags => 'gasc_',	type => 'filename',
	'stats:filetoid' => '#HVAL#{ #file->get# }=#ID#',	letter => 'o',
 },
 path	=>
 {	name	=> _"Folder",	width => 200, flags => 'gasc_',	type => 'filename',
	'filter:i'	=> '#_# .=~. m/^#VAL#(?:$::QSLASH|$)/o',
	can_group=>1,
 },
 modif	=>
 {	name	=> _"Modification",	width => 160,	flags => 'gasc_',	type => 'date',
	FilterList => {type=>'year',},
	can_group=>1,
 },
 size	=>
 {	name => _"Size",	width => 80,	flags => 'gasc_',		#32bits => 4G max
	type => 'integer',
	display	=> 'sprintf("%.1fM", #_#/1024/1024)',
	filter_prep	=> \&::ConvertSize,
 },
 title	=>
 {	name	=> _"Title",	width	=> 270,		flags	=> 'garwesci',	type => 'istring',
	id3v1	=> 0,		id3v2	=> 'TIT2',	vorbis	=> 'title',	ape	=> 'Title',	lyrics3	=> 'ETT', ilst => "\xA9nam",
	'filter:~' => '#_iname# .=~. m"(?:^|/) *#VAL# *(?:[/\(\[]|$)"',		'filter_prep:~'=> \&Filter::SmartTitleRegEx,
	'filter_simplify:~' => \&Filter::SmartTitleSimplify,
	makefilter_fromID => '"title:~:" . #get#',
	edit_order=> 10, letter => 't',
 },
 artist =>
 {	name => _"Artist",	width => 200,	flags => 'garwesci',
	type => 'artist',
	id3v1	=> 1,		id3v2	=> 'TPE1',	vorbis	=> 'artist',	ape	=> 'Artist',	lyrics3	=> 'EAR', ilst => "\xA9ART",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	all_count=> _"All artists",
	picture_field => 'artist_picture',
	edit_listall => 1,
	edit_order=> 20,	edit_many=>1,	letter => 'a',
	can_group=>1,
	#names => '::__("%d artist","%d artists",#count#);'
 },
 first_artist =>
 {	flags => 'g', #CHECKME
	type	=> 'artist_first',	depend	=> 'artists',	name => _"Main artist",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	sortgroup=>'artist',
	can_group=>1,
 },
 artists =>
 {	flags => 'l',	type	=> 'artists',	depend	=> 'artist',	name => _"Artists",
	all_count=> _"All artists",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
 },
 album =>
 {	name => _"Album",	width => 200,	flags => 'garwesci',	type => 'album',
	id3v1	=> 2,		id3v2	=> 'TALB',	vorbis	=> 'album',	ape	=> 'Album',	lyrics3	=> 'EAL', ilst => "\xA9alb",
	depend	=> 'artist album_artist', #because albums with no names get the name : <Unknown> (artist)
	all_count=> _"All albums",
	FilterList => {search=>1,drag=>::DRAG_ALBUM},
	picture_field => 'album_picture',
	names => '::__("%d album","%d albums",#count#);',
	edit_order=> 30,	edit_many=>1,	letter => 'l',
	can_group=>1,
 },
 album_picture =>
 {	name		=> _"Album picture",
	flags		=> '',		#FIXME
	depend		=> 'album',
	property_of	=> 'album',
	mainfield	=> 'album',
	type		=> '_picture',
	letter		=> 'c',
 },
 artist_picture =>
 {	name		=> _"Artist picture",
	flags		=> '',		#FIXME
	depend		=> 'artist',
	property_of	=> 'artist',
	mainfield	=> 'artist',
	type		=> '_picture',
 },
 rating_picture =>
 {	name		=> _"Rating picture",
	flags		=> '',		#FIXME
	depend		=> 'rating',
	property_of	=> 'rating',
	mainfield	=> 'rating',
	type		=> '_stars',
	nbpictures	=> 5,
	fileprefix	=> ::PIXPATH.'stars',
 },
 album_artist_raw =>
 {	name => _"Album artist",width => 200,	flags => 'garwesci',	type => 'artist',
	id3v2	=> 'TPE2',	vorbis	=> 'album_artist',	ape	=> 'Album_artist',  ilst => "aART",
	#FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	edit_order=> 35,	edit_many=>1,	edit_listall => 1,
	#can_group=>1,
 },
 album_artist =>
 {	name => _"Album artist",width => 200,	flags => 'gc',	type => 'artist',
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	_ => 'do {my $n=vec(__album_artist_raw__,#ID#,#bits#); $n==1 ? vec(__artist__,#ID#,#bits#) : $n}',
	can_group=>1,
	letter => 'A',
 },
 compilation =>
 {	name	=> _"Compilation", width => 20, flags => 'garwesc',	type => 'boolean',
	id3v2 => 'TCMP',	vorbis	=> 'compilation',	ape => 'Compilation',	ilst => 'cpil',
	edit_many=>1,
	#_disabled=>1,	#not tested
 },
 grouping =>
 {	name	=> _"Grouping",	width => 100,	flags => 'garwesci',	type => 'fewstring',
	FilterList => {search=>1},
	can_group=>1,
	edit_order=> 55,	edit_many=>1,
	id3v2 => 'TIT1',	vorbis	=> 'grouping',	ape	=> 'Grouping', ilst => "\xA9grp",
 },
 year =>
 {	name	=> _"Year",	width => 40,	flags => 'garwesc',	type => 'integer',	bits => 16, edit_max=>3000,
	check	=> '#VAL#= #VAL# =~m/(\d\d\d\d)/ ? $1 : 0;',
	id3v1	=> 3,		id3v2 => 'TDRC|TYER', 'id3v2.3'=> 'TYER',	'id3v2.4'=> 'TDRC',	vorbis	=> 'date|year',	ape	=> 'Record Date|Year', ilst => "\xA9day",
	gid_to_display	=> '#GID# ? #GID# : _"None"',
	'stats:range'	=> '#HVAL#{#_#}=undef;  ---- delete #HVAL#{0}; #HVAL#=do {my ($m0,$m1)=(sort {$a <=> $b} keys %{#HVAL#})[0,-1]; !defined $m0 ? "" : $m0==$m1 ? $m0 : "$m0 - $m1"}',
	editwidth => 6,
	edit_order=> 50,	edit_many=>1,	letter => 'y',
	can_group=>1,
	FilterList => {},
 },
 track =>
 {	name	=> _"Track",	width => 40,	flags => 'garwesc',
	id3v1	=> 5,		id3v2	=> 'TRCK',	vorbis	=> 'tracknumber',	ape	=> 'Track', ilst => "trkn",
	type => 'integer',	displayformat => '%02d', bits => 8, edit_max => 255,
	edit_order=> 20,	editwidth => 4,		letter => 'n',
 },
 disc =>
 {	name	=> _"Disc",	width => 40,	flags => 'garwesc',	type => 'integer',	bits => 8, edit_max => 255,
				id3v2	=> 'TPOS',	vorbis	=> 'discnumber',	ape	=> 'discnumber', ilst => "disc",
	editwidth => 4,
	edit_order=> 40,	edit_many=>1,	letter => 'd',
	can_group=>1,
 },
 discname =>
 {	name	=> _"Disc name",	width	=> 100,		flags => 'garwesci',	type => 'fewstring',
	id3v2	=> 'TSST',	vorbis	=> 'discsubtitle',	ape => 'DiscSubtitle',	ilst=> '----DISCSUBTITLE',
	_disabled=>1,
 },
 genre	=>
 {	name		=> _"Genres",	width => 180,	flags => 'garwescil',
	 #is_set	=> '(__GENRE__=~m/(?:^|\x00)__QVAL__(?:$|\x00)/)? 1 : 0', #for random mode
	id3v1	=> 6,		id3v2	=> 'TCON*',	vorbis	=> 'genre',	ape	=> 'Genre', ilst => "\xA9gen",
	type		=> 'flags',		#init_namearray => '@Tag::MP3::Genres',
	none		=> quotemeta _"No genre",
	all_count	=> _"All genres",
	FilterList	=> {search=>1},
	edit_order=> 70,	edit_many=>1,	letter => 'g',
 },
 label	=>
 {	name		=> _"Labels",	width => 180,	flags => 'gaescil',
	 #is_set	=> '(__LABEL__=~m/(?:^|\x00)__QVAL__(?:$|\x00)/)? 1 : 0', #for random mode
	type		=> 'flags',		init_namearray	=> '@{$::Options{Labels}}',
	iconprefix	=> 'label-',
	icon		=> sub { $Def{label}{iconprefix}.::url_escape($_[0]); }, #FIXME use icon_for_gid
	icon_for_gid	=> '"#iconprefix#".::url_escape(#gid_to_get#)',
	all_count	=> _"All labels",
	none		=> quotemeta _"No label",
	FilterList	=> {search=>1,icon=>1},
	icon_edit_string=> _"Choose icon for label {name}",
	edit_order=> 80,	edit_many=>1,	letter => 'L',
 },
 comment=>
 {	name	=> _"Comment",	width => 200,	flags => 'garwesci',		type => 'string',
	id3v1	=> 4,		id3v2	=> 'COMM;;;%v',	vorbis	=> 'description|comment|comments',	ape	=> 'Comment',	lyrics3	=> 'INF', ilst => "\xA9cmt",	join_with => " ",
	edit_order=> 60,	edit_many=>1,	letter => 'C',
 },
 rating	=>
 {	name	=> _"Rating",		width => 80,	flags => 'gaesc',	type => 'rating',
	FilterList => {},
	starfield => 'rating_picture',
	edit_order=> 90,	edit_many=>1,
 },
 added	=>
 {	name	=> _"Added",		width => 100,	flags => 'gasc_',	type => 'date',
	FilterList => {type=>'year', },
	can_group=>1,
 },
 lastplay	=>
 {	name	=> _"Last played",	width => 100,	flags => 'gasc',	type => 'date',
	FilterList => {type=>'year',},
	can_group=>1,	letter => 'P',
 },
 lastskip	=>
 {	name	=> _"Last skipped",	width => 100,	flags => 'gasc',	type => 'date',
	FilterList => {type=>'year',},
	can_group=>1,	letter => 'K',
 },
 playcount	=>
 {	name	=> _"Play count",	width => 50,	flags => 'gaesc',	type => 'integer',	letter => 'p',
 },
 skipcount	=>
 {	name	=> _"Skip count",	width => 50,	flags => 'gaesc',	type => 'integer',	letter => 'k',
 },
 composer =>
 {	name	=> _"Composer",		width	=> 100,		flags => 'garwesci',	type => 'artist',
	id3v2	=> 'TCOM',	vorbis	=> 'composer',		ape => 'Composer',	ilst => "\xA9wrt",
	FilterList => {search=>1},
	_disabled=>1,
 },
 author	=>
 {	name	=> _"Author",	width	=> 100,		flags => 'garwesci',	type => 'artist',
	id3v2	=> 'TOPE',	vorbis	=> 'author',	lyrics3	=> 'AUT',	#ape => 'Author'#?? FIXME
	FilterList => {search=>1},
	_disabled=>1,
 },
 version=> #subtitle ?
 {	name	=> _"Version",	width	=> 150,		flags => 'garwesci',	type => 'string',
	id3v2	=> 'TIT3',	vorbis	=> 'version|subtitle',			ape => 'Subtitle',	ilst=> '----SUBTITLE',
 },
 channel=>
 {	name	=> _"Channels",		width => 50,	flags => 'gasc',	type => 'integer',	bits => 4,	audioinfo => 'channels', },	# are 4 bits needed ? 1bit+1 could be enough ?
 bitrate=>
 {	name	=> _"Bitrate",		width => 70,	flags => 'gasc_',	type => 'integer',	bits => 16,	audioinfo => 'bitrate|bitrate_nominal',		check	=> '#VAL#= sprintf "%.0f",#VAL#/1000;' },
 #samprate=>
 #{	name	=> _"Sampling Rate",	width => 60,	flags => 'gasc',	type => 'integer',	bits => 16,	audioinfo => 'rate', },
 samprate=>
 {	name	=> _"Sampling Rate",	width => 60,	flags => 'gasc',	type => 'fewnumber',	bits => 8,	audioinfo => 'rate', },
 filetype=>
 {	name	=> _"Type",		width => 80,	flags => 'gasc',	type => 'fewstring',	bits => 8, }, #could probably fit in 4bit
 'length'=>
 {	name	=> _"Length",		width => 50,	flags => 'gasc_',	type => 'length',	bits => 16, # 16 bits limit length to ~18.2 hours
	audioinfo => 'seconds',		check	=> '#VAL#= sprintf "%.0f",#VAL#;',
	FilterList => {type=>'div.60',},
	letter => 'm',
	rightalign=>1,	#right-align in SongTree and SongList #maybe should be done to all number columns ?
 },

 replaygain_track_gain=>
 {	name	=> _"Track gain",	width => 60,	flags => 'grwsca',
	type	=> 'float',	check => '#VAL#= #VAL# =~m/^((?:\+|-)?\d+(?:\.\d+)?)\s*(?:dB)?$/i ? $1 : 0;',
	displayformat	=> '%.2f dB',
	id3v2	=> 'TXXX;replaygain_track_gain;%v',	vorbis	=> 'replaygain_track_gain',	ape	=> 'replaygain_track_gain', ilst => '----replaygain_track_gain',
 },
 replaygain_track_peak=>
 {	name	=> _"Track peak",	width => 60,	flags => 'grwsca',
	id3v2	=> 'TXXX;replaygain_track_peak;%v',	vorbis	=> 'replaygain_track_peak',	ape	=> 'replaygain_track_peak', ilst => '----replaygain_track_peak',
	type	=> 'float',
 },
 replaygain_album_gain=>
 {	name	=> _"Album gain",	width => 60,	flags => 'grwsca',
	id3v2	=> 'TXXX;replaygain_album_gain;%v',	vorbis	=> 'replaygain_album_gain',	ape	=> 'replaygain_album_gain', ilst => '----replaygain_album_gain',
	displayformat	=> '%.2f dB',
	type	=> 'float',	check => '#VAL#= #VAL# =~m/^((?:\+|-)?\d+(?:\.\d+)?)\s*(?:dB)?$/i ? $1 : 0;',
 },
 replaygain_album_peak=>
 {	name	=> _"Album peak",	width => 60,	flags => 'grwsca',
	id3v2	=> 'TXXX;replaygain_album_peak;%v',	vorbis	=> 'replaygain_album_peak',	ape	=> 'replaygain_album_peak', ilst => '----replaygain_album_peak',
	type	=> 'float',
 },
# replaygain_reference_level=>
# {	id3v2	=> 'TXXX;replaygain_reference_level;%v',vorbis	=> 'replaygain_reference_level',ape	=> 'replaygain_reference_level', ilst => '----replaygain_reference_level',
# },
 #mp3gain : APE tags,	peak : float 	: 0.787193
 #			gain float dB 	: -1.240000 dB
 #vorbisgain :	peak float : 0.00011510 1.01959181
 #		gain +-float dB : -0.55 dB +64.82 dB
 #mp3gain creates APE tags : mp3gain_minmax and mp3gain_album_minmax
 #
 #
 #gstreamer : id3v2 tag replaygain_album_peak 0,787216365337372
 #			replaygain_track_peak 0,787216365337372
 #		ogg : 	peak 0,000115100738184992
 #			gain 64,82

 version_or_empty	=> { get => 'do {my $v=#version->get#; $v eq "" ? "" : " ($v)"}',	type=> 'virtual',	depend => 'version',	flags => 'g', letter => 'V', },
 album_years	=> { name => _"Album year(s)", get => 'AA::Get("year:range","album",#album->get_gid#)',	type=> 'virtual',	depend => 'album year',	flags => 'g', letter => 'Y', }, #depends on years from other songs too
 uri		=> { get => '"file://".::url_escape(#path->get# .::SLASH. #file->get#)',	type=> 'virtual',	depend => 'file path',	flags => 'g', },
 fullfilename_raw => { get => '#fullfilename->get#', type=> 'virtual',	flags => 'g',	depend => 'file path',	letter => 'f', },
 fullfilename	=> {	get	=> '#path->get# .::SLASH. #file->get#',
	 		display => '#path->display# .::SLASH. #file->display#',
			makefilter_fromID => '"fullfilename:e:" . ::url_escape(#get#)',
			type	=> 'virtual',	flags => 'g',	depend => 'file path',	letter => 'u',
			'filter:e'	=> '#ID# == #VAL#',	'filter_prep:e'=> sub { FindID(::decode_url($_[0])); },
		   },
 basefilename	=> { get => 'do {my $s=#file->display#; $s=~s/\.[^\.]+$//; $s;}',	type=> 'virtual',	depend => 'file',	flags => 'g', },
 #fileextension => ?
 title_or_file	=> {get => '(#title->get# eq "" ? #file->display# : #title->get#)',	type=> 'virtual',	flags => 'g', depend => 'file title', letter => 'S',},	#why letter S ? :)

 missing	=> { flags => 'gan', type => 'integer', bits => 32, }, #FIXME store it using a 8-bit relative number to $::DAYNB
 missingkey	=> { get => 'join "\\x1D",'.map("#$_->get#",join(',',@MissingKeyFields)), depend => "@MissingKeyFields",	type=> 'virtual', },	#used to check if same song

 shuffle	=> { name => _"Shuffle", type => 'shuffle', flags => 's', depend => 'added', },
 album_shuffle	=> { name => _"Album shuffle", type => 'shuffle', flags => 's',		n_sort	=> 'vec(__shuffle__,#album->get_gid#,32)',  },	#	n_sort	=> 	'#shuffle->n_sort(ID=#album->get_gid#)#'  ??
 filetags	=>	# debug field : list of the id3v2 frames / vorbis comments
 		{	name	=> "filetags", width => 180,	flags => 'grascil', type	=> 'flags',
			"id3v2:read"	=> sub { my $h=$_[0]; my %res; for my $key (keys %$h) { my $v=$h->{$key}; if ($key=~m/^TXXX$|^COMM$|^WXXX$/) { my $i= $key eq 'COMM' ? 1 : 0; $res{"$key;$_->[$i]"}=undef for @$v; } else { $res{$key}=undef; } } ; return [keys %res]; },
			#'id3v2:read'	=> sub { [keys %{$_[0]}] },
			'vorbis:read'	=> sub { [map "vorbis_$_",keys %{$_[0]}] },
			'ape:read'	=> sub { [map "ape_$_",   keys %{$_[0]}] },
			'ilst:read'	=> sub { [map "ilst_$_",  keys %{$_[0]}] },
			FilterList => {search=>1,none=>1},
			none		=> quotemeta "No tags",	#not translated because made for debugging
			#_disabled=>1,
		},
);

our %HSort=
(	string	=> '$h->{$a} cmp $h->{$b} ||',
	number	=> '$h->{$a} <=> $h->{$b} ||',
	year2	=> 'substr($h->{$a},-4,4) cmp substr($h->{$b},-4,4) ||',
);

our %GTypes= #FIXME could be better
(	idlist	=> {code => 'push @{#HVAL#}, #ID#', },
	#filetoid=> {code => '#HVAL#{ #file->get# }=#ID#',	depend=>'file',	},
	uniq	=> {code => '#HVAL#=undef'},
	count	=> {code => '#HVAL#++'},
	#length	=> {code => '__H__+=__LENGTH__',	depend=>'length',	},
	#year	=> {code => '__H__{__YEAR__}=undef',	after=>'delete __H__{""}; my @l=sort { $a <=> $b } keys %{__H__}; __H__= @l==0 ? "" : @l==1 ? $l[0] : "$l[0] - $l[-1]";',	depend=>'year',	},
	#label	=> {code => '__H__{$_}=undef for split /\x00/,__LABEL__;',	after=>'__H__=[keys %{__H__}];',	depend=>'label',	},
	#album	=> {code => '__H__{__ALBUM__}=undef',	after=>'__H__=[keys %{__H__}];',	depend=>'album',},
	#artist	=> {code => '__H__{$_}=undef for split /$::re_artist/o,__ARTIST__;',	after=>'__H__=[keys %{__H__}];',	depend=>'artist',	},
);

# discname
# version '' : " ($v)"
#


} #end of INIT block

our $OLD_FIELDS='file path modif length size bitrate filetype channel samprate title artist album disc track year version genre comment author added lastplay playcount rating label missing lastskip skipcount';
sub FieldUpgrade	#for versions <1.1
{	(split / /,$OLD_FIELDS)[$_[0]];
}

my (%Get,%Display,$DIFFsub,$NEWsub,$LENGTHsub,%UPDATEsub,$SETsub); my (%Get_gid,%Gid_to_display,%Gid_to_get);
use constant FIRSTID => 1;
our $LastID=FIRSTID-1;

sub Macro
{	local $_=shift;
	my %h=@_;
	s/#(\w+)#/exists $h{$1} ? $h{$1} : "#$1#"/eg;
	return $_;
}

#sub Find_Properties
#{	my ($field,$start)=@_;
#	($field,my $subtype)=split /\./,$field;
#	my @hashlist= ($Def{$field});
#	my $type=$Def{$field}{type};
#	warn "no type defined for field $field\n" unless $type;
#	while ($type)
#	{	push @hashlist,$Types{"$type.$subtype"} if $subtype;
#		push @hashlist,$Types{$type};
#		my $plugin=$Types{$type}{plugin};
#		push @hashlist,map $Types{$_}, split / /,$plugin if $plugin;
#		$type= $Types{$type}{parent};
#	}
#	my @found;
#	for my $h (grep defined, @hashlist)
#	{	push @found, grep index($_,$start)==0, keys %$h;
#	}
#	return sort @found;
#}
sub LookupCode
{	my ($field_opt,@actions)=@_;
	my ($field,@opt)=split /\./,$field_opt;
	my %vars;
	%vars=@{pop @actions} if ref $actions[-1];
	my @hashlist= ($Def{$field}, {field => $field});
	my $type=$Def{$field}{type};
	my $subtype=shift @opt;
	#$vars{field}=$field;
	if (@opt) { $vars{"ARG$_"}=$opt[$_] for 0..$#opt; }
	warn "no type defined for field $field\n" unless $type;
	while ($type)
	{	#warn " +type $type\n";
		push @hashlist,$Types{"$type.$subtype"} if $subtype;
		push @hashlist,$Types{$type};
		#my $plugin=$Types{$type}{plugin};
		#push @hashlist,map $Types{$_}, split / /,$plugin if $plugin;
		$type= $Types{$type}{parent};
	}
	@hashlist=grep defined, @hashlist;
	my @code;
	for my $action (@actions)
	{	my @or=split /\|/,$action;
		my $c;
		while (!$c && @or)
		{	my $key=shift @or;
			($c)=grep $_,map $_->{$key}, @hashlist;
			#if ($c) {warn " found $key for field $field\n"}
		}
		if ($c && !ref $c)
		{	1 while $c=~s/#([_0-9a-z:~.]+)#/(grep defined,map $_->{$1}, @hashlist)[0]/ge;
#			$c=~s/#(\w+)->([_0-9a-z:~.]+)(?:\((\w+)=([^)]+)\))?#/LookupCode($1,$2,($3 ? [$3 => $4] : ()))/ge;
			$c=~s/#(?:(\w+)->)?([_0-9a-z:~.]+)(?:\((\w+)=([^)]+)\))?#/LookupCode($1||$field_opt,$2,($3 ? [$3 => $4] : ()))/ge;
			$c=~s#___#__${field}_#g;
			$c=~s#([@%\$\#])__(\w+)#($1||'\$').'Songs::Songs_'.$2#ge;
			$c=~s#__(\w+)#\$Songs::Songs_$1#g;
			$c=~s/#(\w+)#/exists $vars{$1} ? $vars{$1} : "#$1#"/ge;	#variable names must be in UPPERCASE
		}
		push @code,$c;
	}
	return wantarray ? @code : $code[0];
}
sub Code
{	my ($field,$action,@h)=@_;
	my $code=LookupCode($field,$action,\@h);
	return $code;
}
sub MakeCode		#keep ?
{	my ($field,$code,@h)=@_;
	my @actions= $code=~m/#([\w\|.]+)#/g; 		#warn "field=$field : @actions";
	my (@codes)=LookupCode($field,@actions,\@h);	#warn join(' ',map {defined $_ ? 1 : 0} @codes);
	$code=~s/#[\w\|.]+#/shift @codes/ge;
	return $code;
}
sub CanDoFilter		#returns true if all @fields can do $op
{	my ($op,@fields)=@_;
	return !grep !LookupCode($_,'filter:'.$op), @fields;
}
sub FilterCode
{	my ($field,$cmd,$pat,$inv)=@_;
	my ($code,$convert)=LookupCode($field, 'filter:'.$cmd, 'filter_prep:'.$cmd.'|filter_prep');
	unless ($code) { warn "error can't find code for filter $field,$cmd,$pat,$inv\n"; return 1}
	$convert||=sub {quotemeta $_[0]};
	unless (ref $convert) { $convert=~s/#PAT#/\$_[0]/g; $convert=eval "sub {$convert}"; }
	$code=~s/#ID#/\$_/g;
	if ($inv)	{$code=~s#$Filter::OpRe#$Filter::InvOp{$1}#go}
	else		{$code=~s#$Filter::OpRe#$1 eq '!!' ? '' : $1#ego}
	if ($code=~m/#VAL1#/) { my ($p1,$p2)=map $convert->($_), split / /,$pat; $code=~s/#VAL1#/$p1/g; $code=~s/#VAL2#/$p2/g; }
	else { my $p=$convert->($pat,$field); $code=~s/#VAL#/$p/g; }
	return $code;
}
sub SortCode
{	my ($field,$inv,$insensitive,$for_gid)=@_; #warn "SortCode : @_\n";
	my ($code,$scode,$sicode)= LookupCode($field, ($for_gid ? qw/n_sort:gid s_sort:gid si_sort:gid/ : qw/n_sort s_sort si_sort/));
	my $op="<=>";
	if ($scode)
	{	$op='cmp';
		if (!$insensitive)	{ $code=$scode}
		else			{ $code= $sicode || "::superlc($scode)"; }
	}
	my $code2=$code;
	$code =~s/#(?:GID|ID)#/\$a/g;
	$code2=~s/#(?:GID|ID)#/\$b/g;
	return $inv ? "$code2 $op $code" : "$code $op $code2";
}

sub Compile		#currently return value of the code must be a scalar
{	my ($name,$code)=@_;
	if ($::debug) { $::DebugEvaledCode{$name}=$code; $code=~s/^sub {/sub { local *__ANON__ = 'evaled $name';/; }
	my $res=eval $code;
	if ($@) { warn "** Compilation error in $name\n Code:-------\n$code\n *Error:-------\n$@**\n";}
	return $res;
}

sub UpdateFuncs
{	undef %FuncCache;
	delete $Def{$_}{_depended_on_by}, delete $Def{$_}{_properties} for keys %Def;
	@Fields=();
	%Get=%Display=();	#FIXME probably more need reset

	my %done;
	my %_depended_on_by; my %_properties;
	my @todo=grep !$Def{$_}{_disabled}, keys %Def;
	while (@todo)
	{	my $count=@todo;
		for my $f (@todo)
		{	if (my $d=$Def{$f}{depend})
			{	next if grep !exists $done{$_}, split / /,$d;
				$_depended_on_by{$_}{$f}=undef for split / /,$d;
			}
			if (my $p=$Def{$f}{property_of}) {$_properties{$p}{$f}=undef}
			push @Fields,$f;
			$done{$f}=undef;
		}
		@todo=grep !exists $done{$_}, @todo;
		if ($count==@todo) { warn "Circular field dependencies, can't order these fields : @todo !\n"; push @Fields,@todo; last; }
	}
	$Def{$_}{_depended_on_by}=	join ' ',keys %{$_depended_on_by{$_}}	for keys %_depended_on_by;
	$Def{$_}{_properties}=		join ' ',keys %{$_properties{$_}} 	for keys %_properties;
warn "\@Fields=@Fields"; $Def{$_}{flags}||='' for @Fields;	#DELME
	{	my $code;
		for my $f (@Fields)
		{	$Def{$f}{flags}||='';
			$code.= (Code($f,'init')||'').";\n";
		}
		Compile(init=>$code);
	}
	for my $f (@Fields)
	{	if (my $code=Code($f, 'update', ID => '$ID'))
		{	$UPDATEsub{$f}= Compile("Update_$f"=> 'sub { for my $ID (@{$_[0]}) {'.$code.'} }');
		}
	}

	# create DIFF sub
	{	my $code='my $ID=$_[0]; my $values=$_[1]; my $val; my @changed;'."\n";
		for my $f (grep $Def{$_}{flags}=~m/r/, @Fields)
		{	my $c= $Def{$f}{flags}=~m/_/ ?
				"if (exists \$values->{$f}) { \$val=\$values->{$f}; #check#;\n".
				" if (#diff#) { #set#; push \@changed,'$f'; } }\n"
				:
				"\$val= (exists \$values->{$f} ? \$values->{$f} : #default#);\n".
				" #check#; if (#diff#) { #set#; push \@changed,'$f'; }\n";
			$code.=MakeCode($f,$c,ID => '$ID', VAL => "\$val");
		}
		#$code.='::SongsChanged([$ID],\@changed) if @changed;';
		$code.=' return @changed;';
		$DIFFsub= Compile(Diff =>"sub {$code}");
	}

	# create SET sub
	{	my $code=join "\n",
		'my $IDs=$_[0]; my $values=$_[1]; my %onefieldchanged; my @towrite; my %changedfields; my @changedIDs; my $i=0; my $val;',
		'for my $ID (@$IDs)',
		'{	my $changed;';
		for my $f (grep $Def{$_}{flags}=~m/a/, @Fields)
		{	my $set=  ($Def{$f}{flags}=~m/w/ && !$::Options{TAG_nowrite_mode}) ?
				"push \@{\$towrite[\$i]}, '$f',\$val;" :
				"#set#; \$changedfields{$f}=undef; \$changed=1;";
			my $c=	"	\$val=	exists \$values->{$f} ? 	\$values->{$f} :".
				"		exists \$values->{'\@$f'} ? 	shift \@{\$values->{'\@$f'}} :".
				"						undef;".
				"	if (defined \$val)\n".
				"	{	#check#;\n".
				"		if (#diff#) { $set }\n".
				"	}\n";
			if ($Def{$f}{flags}=~m/l/)
			{  $c.=	"	elsif (\$val=\$values->{'+$f'})". # $v must contain [[toset],[torm]] # + toggle ?
				"	{	if (\$val= #set_multi#) { $set }\n". # set_multi return the new arrayref if modified, undef if not changed
			   	"	}\n";
			}
			$code.= MakeCode($f,$c,ID => '$ID', VAL => "\$val");
		}
		$code.= join "\n",
		'	push @changedIDs,$ID if $changed;',
		'	$i++;',
		'}',
		'::SongsChanged(\@changedIDs, [keys %changedfields]) if @changedIDs;',
		'return \%changedfields, \@towrite;';
		$SETsub= Compile(Set =>"sub {$code}");
	}

	# create NEW sub
	{	my $code='$LastID++; my $values=$_[0]; my $val;'."\n";
		my %done;
		for my $f (grep $Def{$_}{flags}=~m/a/, @Fields)
		{	#$c||= '____[] = #VAL#';
			$done{$f}=undef;
			my $c=	"	\$val= exists \$values->{$f} ? \$values->{$f} : #default#;\n".
				"	#check#;\n".
				"	#set#;\n";
			#unless ($c) { warn "'set' code not found for field $f\n"; next }
			$code.=MakeCode($f,$c,ID => '$LastID', VAL => "\$val");
			#$code.= qq(;warn "\nsetting field $f :\n";);
		}
		for my $f (grep $Def{$_}{depend}, @Fields)
		{	next if exists $done{$f};
			next unless grep exists $done{$_}, split / /,$Def{$f}{depend};
			my $c=Code($f, 'update' , ID => '$LastID');
			$code.=$c.";\n" if $c;
		}
		$code.= ';return $LastID;';
		$NEWsub= Compile(New =>"sub {$code}");
	}
	{	my $code='my $size=0; my $sec=0; for my $ID (@{$_[0]}) {'
		. '$size+='.	Code('size', 	'get', ID => '$ID').';'
		. '$sec+='.	Code('length',	'get', ID => '$ID').';'
		. '} return ($size,$sec)';
		$LENGTHsub= Compile(Length =>"sub {$code}");
	}
	%::ReplaceFields= map { '%'.$Def{$_}{letter} => $_ } grep $Def{$_}{letter}, @Fields;
	$::ReplaceFields{'$'.$_}=$_ for grep $Def{$_}{flags}=~m/g/, @Fields;

	::HasChanged('fields_reset');
	#FIXME connect them to 'fields_reset' event :
	SongList::init_textcolumns();
	SongTree::init_textcolumns();
}

sub MakeLoadSub
{	my ($extradata,@loaded_slots)=@_;
	my %extra_sub;
	my $code='$LastID++; ';
	my %loadedfields;
	$loadedfields{$loaded_slots[$_]}=$_ for 0..$#loaded_slots;
	for my $field (@Fields)
	{	my $i=$loadedfields{$field};
		my $c;
		if (defined $i)
		{	$Def{$field} ||= { type => 'unknown', flags => 'a', };
			$c= Code($field, 'load|set', ID => '$LastID', VAL => "\$_[$i]");
		}
		elsif ($Def{$field}{flags}=~m/a/)
		{	$loadedfields{$field}=undef;
			$c= Code($field, 'load|set', ID => '$LastID', VAL => Code($field,'default'));
		}
		elsif (my $dep=$Def{$field}{depend})
		{	next if grep !exists $loadedfields{$_}, split / /,$dep;
			$c=Code($field, 'update', ID => '$LastID'); #FIXME maybe add {} around it, to avoid multiple my at the same level
			warn "adding update code for $field" if $c;
		}
		$code.=$c.";\n" if $c;

		my ($mainfield,$load_extra)=LookupCode($field,'mainfield','load_extra',[SGID=>'$_[0]']);
		$mainfield||=$field;
		if ($load_extra && $extradata->{$mainfield} && !$extra_sub{$mainfield})
		{	my $code= 'my $gid='.$load_extra.";\n";
			my $i=1;
			for my $subfield (split / /,$extradata->{$mainfield}[0])
			{	my $c=LookupCode($subfield,'load_extra',[GID=>'$gid',VAL=>"\$_[$i]"]);;
				$code.= "\t$c;\n" if $c;
				$i++;
			}
			$extra_sub{$mainfield}= Compile("LoadSub_$mainfield" => "sub {$code}") || sub {};
		}
	}
	$code.= '; return $LastID;';
	my $loadsub= Compile(LoadSub => "sub {$code}");
	return $loadsub,\%extra_sub;
}
sub MakeSaveSub
{	my @saved_fields;
	my @code;
	my %extra_sub; my %extra_subfields;
	for my $field (sort grep $Def{$_}{flags}=~m/a/, @Fields)
	{	push @saved_fields,$field;
		push @code, Code($field, 'save|get', ID => '$_[0]');
		my ($mainfield,$save_extra)=LookupCode($field,'mainfield','save_extra');
		if ($save_extra && ( !$mainfield || $mainfield eq $field ))
		{	my @subfields= split / /, $Def{$field}{_properties};
			if (@subfields)
			{	my @extra_code;
				for my $subfield (@subfields)
				{	my $c=LookupCode($subfield,'save_extra',[GID => '$gid']);
					push @extra_code, $c;
				}
				$extra_subfields{$field}= join ' ', @subfields;
				my $code= $save_extra;
				my $extra_code=join ',', @extra_code;
				$code=~s/#SUBFIELDS#/$extra_code/g;
				$extra_sub{$field}= Compile("SaveSub_$field" => "sub { $code }") || sub {};
			}
		}
	}

	my $code= "sub { return (\n\t".join(",\n\t",@code)."\n); }";
	my $savesub= Compile(SaveSub => $code);
	return $savesub,\@saved_fields,\%extra_sub,\%extra_subfields;
}

sub New
{	my $file=$_[0];
	#check already in @Songs#FIXME
	warn "Reading Tag for $file\n";
	my ($size,$modif)=(stat $file)[7,9];
	my ($values,$estimated)= FileTag::Read($file,1);
	unless ($values) { warn "Error reading tag for $file\n"; return undef; }
	my $path=$file;
	$path=~s/$::QSLASH([^$::QSLASH]+)$//o and $file=$1;
	%$values=(	%$values,
			file => $file,	path=> $path,
			modif=> $modif, size=> $size,
			added=> time,
		);
	if (defined( my $ID=CheckMissing($values) )) { ReReadFile($ID); return $ID; }

	#warn "\nNewSub(LastID=$LastID)\n";warn join("\n",map("$_=>$values->{$_}",sort keys %$values))."\n";
	my $ID=$NEWsub->($values);#warn $Songs::Songs_title__[-1]." NewSub end\n";
	push @$::LengthEstimated,$ID if $estimated;
	$IDFromFile->{$path}{$file}=$ID if $IDFromFile;
	return $ID;
}

sub ReReadFile
{	my $ID=$_[0]; my $force=$_[1]; warn "ReReadFile(@_) called from : ".join(':',caller)."\n";
	my $file= GetFullFilename($ID);
	if (-r $file)
	{	my ($size1,$modif1)=Songs::Get($ID,qw/size modif/);
		my ($size2,$modif2)=(stat $file)[7,9];
		my $checklength= ($size1!=$size2 || ($force && $force==2)) ? 2 : 0;
		return 1 unless $checklength || $force || $modif1!=$modif2;
		my ($values,$estimated)=FileTag::Read($file,$checklength);
		my @changed=$DIFFsub->($ID,$values);
		return unless @changed;warn "Changed fields : @changed";
		############SetDB($ID,map( ($_,$values->{$_}), @changed)); DELME
		::SongsChanged([$ID],\@changed);
		my %changed; $changed{$_}=undef for @changed;
		Changed(\%changed,[$ID]);
	}
	else	#file not found/readable
	{	warn "can't read file '$file'\n";
		::SongsRemove([$ID]);
	}
}

sub Set		#can be called either with (ID,[field=>newval,...],option=>val) or (ID,field=>newval,...);  ID can be an arrayref
{	warn "Songs::Set(@_) called from : ".join(':',caller)."\n";
	my ($IDs,$modif,%opt);
	if (ref $_[1])	{ ($IDs,$modif,%opt)=@_ }
	else		{ ($IDs,@$modif)=@_ }
	$IDs=[$IDs] unless ref $IDs;
	my %values;
	while (@$modif)
	{	my $f=shift @$modif;
		my $val=shift @$modif;
		my $multi;
		if ($f=~s/^([-+])//) { $multi=$1 }
		if (!$Def{$f} && !($f=~m/^@(.*)$/ && $Def{$1}))	{ warn "Songs::Set : Invalid field $f\n";next }
		my $flags=$Def{$f}{flags};
		#unless ($flags=~m/e/) { warn "Songs::Set : Field $f cannot be edited\n"; next }
		#if (my $sub=$Def{$f}{check}))
		# { my $res=$sub->($val); unless ($res) {warn "Songs::Set : Invalid value '$v' for field $f\n"; next} }
		if ($multi && $flags!~m/l/) { warn "Songs::Set : Field $f doesn't support multiple values\n";next }
		if ($multi)	#multi eq + or -  => remove or add values (for labels and genres)
		{	my $array=$values{"+$f"}||=[];
			my $i= $multi eq '+' ? 0 : 1;
			$val=[$val] unless ref $val;
			$array->[$i]=$val;
		}
		else { $values{$f}=$val }
	}
	my ($changed,$towrite)= $SETsub->($IDs,\%values);

	if (keys %$changed)
	{	Changed($changed,$IDs);
		warn "has changed : ".join(' ',keys %$changed);
	}
	if (@$towrite)
	{	my $i=0; my $abort;
		my $errorsub=sub
		 {	my $err=shift;
			my $abortmsg;
			$abortmsg=_"Abort mass-tagging" if (@$IDs-$i)>1;
			my $ret=::Retry_Dialog($err,$opt{window},$abort);
			$abort=1 if $ret eq 'abort';
			return $ret;
		 };
		my $pid= ::Progress( undef, end=>scalar(@$IDs), abortcb=>sub {$abort=1}, widget =>$opt{progress}, title=>_"Writing tags");
		my $progress=$opt{progress};
		Glib::Idle->add(sub
		 {	if ($towrite->[$i])
			{	FileTag::Write($IDs->[$i], $towrite->[$i], $errorsub);
				warn "ID=$IDs->[$i] towrite : ".join(' ',@{$towrite->[$i]});
				::IdleCheck($IDs->[$i]);
			}
			$i++;
			::Progress( $pid, current=>$i );
			return 0 if $abort || $i>=@$IDs;
			return 1;
		 });
	}
	$opt{callback_finish}() if $opt{callback_finish};
}

sub Changed
{	my $changed=$_[0]; my $IDs=$_[1]; 		warn "Songs::Changed : IDs=@$IDs fields=".join(' ',keys %$changed)."\n";
	$IDFromFile=undef if $IDFromFile && exists $changed->{file} || exists $changed->{path};
	AA::Fields_Changed(keys %$changed) if grep $AA::GHash_Depend{$_}, keys %$changed;
	my @needupdate;
	for my $f (keys %$changed)
	{	if (my $l=$Def{$f}{_depended_on_by}) { push @needupdate, split / /,$l; }
	}
	@needupdate= grep !exists $changed->{$_} && $UPDATEsub{$_}, @needupdate;
	warn "Update : @needupdate";
	$UPDATEsub{$_}->($IDs) for @needupdate;
	::SongsChanged($IDs,\@needupdate) if @needupdate;
}

#sub SetMany				#DELME
#{	my ($IDs,$field,$vals)=@_;
#	for my $n (0..$#$IDs)
#	{	Set($IDs->[$n], $field => $vals->[$n]);
#	}
#}

sub AddMissing	#FIXME if song in EstimatedLength, set length to 0
{	my $IDs=$_[0];
	push @Missing,@$IDs;
	$MissingHash=undef;
	#if ($MissingHash)
	#{	#for my $ID (@$IDs)
		#{	my $key=Get($ID,'missingkey');
		#	push @{ $MissingHash->{$key} },$ID;
		#}
	#}
	Set($IDs,missing=>$::DAYNB);
}
sub CheckMissing
{	return undef unless @Missing;
	my $song=$_[0];
	#my $key=Get($song,'missingkey');
	my $key=join "\x1D", @$song{@MissingKeyFields};
	$MissingHash||= BuildHash('missingkey',\@Missing,undef,'idlist');
	my $IDs=$MissingHash->{$key};
	return undef unless $IDs;
	for my $oldID (@$IDs)
	{	my $m;
		for my $f ('file','path')
		{	#$m++ if Get($song,$f) eq Get($oldID,$f);
			$m++ if $song->{$f} eq Get($oldID,$f);
		}
		next unless $m;	#must have the same path or the same filename
		# Found -> remove old ID, copy non-written song fields to new ID
		warn "Found missing song, formerly '".Get($oldID,'fullfilename')."'\n";# if $::debug;

		#remove missing
		if (@$IDs>1) { $MissingHash->{$key}= [grep $_!=$oldID, @$IDs]; }
		else { delete $MissingHash->{$key}; }
		@Missing= grep $oldID != $_, @Missing;

		#Set($oldID,missing=>undef);

		########$songref->[$_]=$Songs[$oldID][$_] for SONG_ADDED,SONG_LASTPLAY,SONG_NBPLAY,SONG_LASTSKIP,SONG_NBSKIP,SONG_RATING,SONG_LABELS,SONG_LENGTH; #SONG_LENGTH is copied to avoid the need to check length for mp3 without VBR header
		return $oldID;
	}
	return undef;
}
sub Makesub
{	my $c=&Code;	warn "Songs::Makesub(@_) called from : ".join(':',caller)."\n" unless $c;
	$c="local *__ANON__ ='Maksub(@_)'; $c" if $::debug;
	my $sub=eval "sub {$c}";
	if ($@) { warn "Compilation error :\n code : $c\n error : $@";}
	return $sub;
}
sub Picture
{	my ($gid,$field,$action,$extra)=@_;
	$action.='_for_gid';
	my $func= $FuncCache{$action.' '.$field};
	unless ($func)
	{	my $pfield=	$Def{$field}{picture_field} || $field;
		my $mainfield=	$Def{$field}{property_of}   || $field;
		$func=$FuncCache{$action.' '.$mainfield}||=$FuncCache{$action.' '.$pfield}=
			Makesub($pfield, $action, GID => '$_[0]', VAL=>'$_[1]');
		return unless $func;
	}
	$func->($gid,$extra);
#	if ($action eq 'set') { ($FuncCache{'set_for_gid '.$field}||= Makesub($field, 'set_for_gid', GID => '$_[0]', VAL=>'$_[1]') ) ->($gid,$extra); }
#	elsif ($action eq 'get') { ($FuncCache{'get_for_gid '.$field}||= Makesub($field, 'get_for_gid', GID => '$_[0]') ) ->($gid); }
#	elsif ($action eq 'pixbuf') { ($FuncCache{'pixbuf_for_gid '.$field}||= Makesub($field, 'pixbuf_for_gid', GID => '$_[0]') ) ->($gid); }
#	elsif ($action eq 'icon') { ($FuncCache{'icon_for_gid '.$field}||= Makesub($field, 'icon_for_gid', GID => '$_[0]') ) ->($gid); }
}
sub ListAll
{	my $field=$_[0];
	my $func= $FuncCache{'listall '.$field} ||=
		do	{	if ( my $c=Code($field, 'listall') )
				{	my $sort=SortCode($field,0,1,1);
					my $gid2get=Code($field, 'gid_to_get', GID => '$_');
					eval "sub {[map( $gid2get, sort {$sort} $c)]}";
				}
				else {1}
			};
	return ref $func ? $func->() : [];
}
sub Get_grouptitle
{	my ($field,$IDs)=@_;
	($FuncCache{'grouptitle '.$field}||= Makesub($field, 'grouptitle', ID => '$_[0][0]', IDs=>'$_[0]') ) ->($IDs);
}
sub Get_gid
{	my ($ID,$field)=@_;
	($Get_gid{$field}||= Makesub($field, 'get_gid', ID => '$_[0]') ) ->($ID);
#	$Get_gid{$field}->($ID);
}
sub Get_list	#rarely used, keep ?
{	my ($ID,$field)=@_;
	#FIXME check field can have multiple values
	my $func= $FuncCache{'getlist '.$field} ||= Makesub($field, 'get_list', ID => '$_[0]');
	$func->($ID);
}
sub Get_icon_list
{	my ($field,$ID)=@_;
	my $func= $FuncCache{"icon_list $field"} ||= Compile("icon_list $field", MakeCode($field,'sub {grep Gtk2::IconFactory->lookup_default($_), map #icon_for_gid#, @{#get_gid#}; }',ID=>'$_[0]', GID=>'$_'));	#FIXME simplify the code-making process
	return $func->($ID);
}
sub Gid_to_Display	#convert a gid from a Get_gid to a displayable value
{	my ($field,$gid)=@_; #warn "Gid_to_Display(@_)\n";
	my $sub= $Gid_to_display{$field} || DisplayFromGID_sub($field);
	if (ref $gid) { return [map $sub->($_), @$gid] }
	return $sub->($gid);
}
sub DisplayFromGID_sub
{	my $field=$_[0];	warn "DisplayFromGID_sub(@_)\n";
	return $Gid_to_display{$field}||= Makesub($field, 'gid_to_display', GID => '$_[0]');
}
sub DisplayFromHash_sub	 #not a good name, very specific, only used for $field=path currently
{	my $field=$_[0];
	return $FuncCache{"DisplayFromHash_sub $field"}||= Makesub($field, 'hash_to_display', VAL => '$_[0]');
}
sub MakeFilterFromGID
{	my ($field,$gid)=@_; #warn "MakeFilterFromGID:@_\n";#warn Code($field, 'makefilter', GID => '$_[0]');
	my $sub=$FuncCache{'makefilter '.$field}||= Makesub($field, 'makefilter', GID => '$_[0]');
warn "MakeFilterFromGID => ".($sub->($gid));
	return Filter->new( $sub->($gid) );
}
sub MakeFilterFromID	#should support most fields, FIXME check if works for year/artists/labels/genres/...
{	my ($field,$ID)=@_;
	if (my $code=Code($field, 'makefilter_fromID', ID => '$_[0]'))		#FIXME optimize : don't call this every time, for example check for a flag that would indicate that this field has a gid
	{	my $sub=$FuncCache{'makefilter_fromID '.$field} ||= Compile('makefilter_fromID '.$field, "sub {$code}"); #FIXME if method doesn't exist
		return Filter->new( $sub->($ID) );
	}
	else
	{	my $gid=Get_gid($ID,$field);
		if (ref $gid) { return Filter->newadd(::FALSE,map MakeFilterFromGID($field,$_), @$gid) }
		return MakeFilterFromGID($field,$gid);
	}
}

sub Gid_to_Get		#convert a gid from a Get_gid to a what Get would return
{	my ($field,$gid)=@_;
	my $sub= $Gid_to_get{$field}||= Makesub($field, 'gid_to_get', GID => '$_[0]');
	if (ref $gid) { return [map $sub->($_), @$gid] }
	return $sub->($gid);
}
#sub Gid_to_string_sub	#used to get string gid that stays valid between session #not used anymore
#{	my ($field)=@_;
#	my $sub= $FuncCache{'g_to_s:'.$field}||= Makesub($field, 'gid_to_sgid', GID => '$_[0]');
#	return $sub;
#}
#sub String_to_gid_sub #not used anymore
#{	my ($field)=@_;
#	my $sub= $FuncCache{'s_to_g:'.$field}||= Makesub($field, 'sgid_to_gid', VAL => '$_[0]');
#	return $sub;
#}
#sub sort_gid_by_name
#{	my ($field,$gids)=@_;
#	my $func= $FuncCache{'sortgid '.$field} ||= eval 'sub { '.SortCode($field,undef,1,1).' }';
#	@$gids=sort $func @$gids;
#}
sub sort_gid_by_name
{	my ($field,$gids,$h,$pre,$mode)=@_;
	$mode||='';
	my $func= $FuncCache{"sortgid $field $mode"} ||= eval 'sub {my $l=$_[0]; my $h=$_[1]; @$l=sort { '.($pre ? $HSort{$pre} : '').' '.SortCode($field,undef,1,1).' } @$l}';
	$func->($gids,$h);
}
sub Get_all_gids	#FIXME add option to filter out walues eq ''
{	my $field=$_[0];
	return UniqList($field,$::Library,1); #FIXME use ___name directly
}

sub Get		# ($ID,@fields)		#FIXME PHASE1 check if function exist for fields
{	#warn "Songs::Get(@_) called from : ".join(':',caller)."\n";
	my $ID=shift;
	return wantarray ? map (($Get{$_}||CompileGet($_))->($ID), @_) : ($Get{$_[0]}||CompileGet($_[0]))->($ID);
}
sub Display	# ($ID,@fields)
{	#warn "Songs::Display(@_) called from : ".join(':',caller)."\n";
	my $ID=shift;
	return wantarray ? map ( ($Display{$_}||CompileDisp($_))->($ID), @_) : ($Display{$_[0]}||CompileDisp($_[0]))->($ID);
}
sub DisplayEsc	# ($ID,$field)
{	return ::PangoEsc( ($Display{$_[1]}||CompileDisp($_[1]))->($_[0]) );
}
sub CompileGet
{	my ($field,$disp)=@_;
	unless ($Def{$field}{flags}=~m/g/)
	{	return $Display{$field}=$Get{$field}=sub { warn "Songs::Get or Songs::Display : Invalid field '$field'\n" };
	}
	my $get= Code($field, 'get', ID => '$_[0]');
	$get="local *__ANON__ ='getsub for $field'; $get" if $::debug;
	$Get{$field}= Compile("Get_$field"=>"sub {$get}");
	my $display= Code($field, 'display', ID => '$_[0]');
	if ($display && $display ne $get)
	{	$Display{$field}= Compile("Display_$field"=>"sub {$display}");
	}
	else { $Display{$field}=$Get{$field}; }
	return $Get{$field};
}
sub CompileDisp
{	my $field=shift;
	CompileGet($field);
	return $Display{$field};
}

sub Map
{	my ($field,$IDs)=@_; #warn "Songs::Map(@_) called from : ".join(':',caller)."\n";
	my $f= $Get{$field}||CompileGet($field);
	return map $f->($_), @$IDs;
}
sub Map_to_gid
{	my ($field,$IDs)=@_;
	return map Get_gid($_,$field), @$IDs;
}

sub GetFullFilename { Get($_[0],'fullfilename') }
#sub GetURI
#{	return map 'file://'.::url_escape($_), GetFullFilename(@_);
#}
sub IsSet
{	my ($ID,$field,$value)=@_;
	my $sub= $FuncCache{'is_set '.$field}||= Makesub($field, 'is_set', ID=>'$_[0]', VAL=>'$_[1]' );
	return $sub->($ID,$value);
}
#sub GetArtists	#not used, remove ?
#{	Get_list($_[0],'artists');
#}
sub ListLength
{	&$LENGTHsub;
}

#FIXME cache the BuildHash sub
sub UniqList #FIXME same as UniqList2. use "string" (for artist) in this one and not in UniqList2 ?
{	my ($field,$IDs,$sorted)=@_; #warn "Songs::UniqList(@_)\n";
	my $h=BuildHash($field,$IDs,undef,'uniq');	#my $h=BuildHash($field,$IDs,'string','uniq'); ??????
	return [keys %$h] unless $sorted;
	return [sort keys %$h]; #FIXME more sort modes ?
}
sub UniqList2 #FIXME MUST handle special cases, merge with UniqList ?
{	&UniqList;
}


sub Build_IDFromFile
{	$IDFromFile||=BuildHash('path',undef,undef,'file:filetoid');
}
sub FindID
{	my $f=$_[0];
	if ($f=~m/\D/)
	{	$f=~s#$::QSLASH{2,}#::SLASH#goe; #remove double SLASH
		if ($f=~s/$::QSLASH([^$::QSLASH]+)$//o)
		{	return $IDFromFile->{$f}{$1} if $IDFromFile;
			my $m=Filter->newadd(1,'file:e:'.$1, 'path:e:'.$f)->filter( [FIRSTID..$LastID] );
			if (@$m)
			{	warn "Error, more than one ID match $f/$1" if @$m>1;
				return $m->[0];
			}
		}
		return undef;
	}
	$f=undef unless defined;
	return $f;
}

sub UpdateDefaultRating
{	my $l=AllFilter('rating:e:');
	Changed({'rating'},$l) if @$l;
}

sub DateString
{	$_[0] ? scalar localtime $_[0] : _('never');
}

#sub Album_Artist #guess album artist
#{	my $alb= Get($_[0],'album');
#	my %h; $h{ Get($_[0],'artist') }=undef for @{AA::GetIDs('album',$alb)};
#	my $nb=keys %h;
#	return Get($_[0],'artist') if $nb==1;
#	my @l=map split(/$::re_artist/o), keys %h;
#	my %h2; $h2{$_}++ for @l;
#	my @common;
#	for (@l) { if ($h2{$_}>=$nb) { push @common,$_; delete $h2{$_}; } }
#	return @common ? join(' & ',@common) : _"Various artists";
#}

sub ChooseIcon	 #FIXME add a way to create a colored square/circle/... icon
{	my ($field,$gid)=@_;
	my $string= ::__x( $Def{$field}{icon_edit_string}, name=> Gid_to_Get($field,$gid) );
	my $file=::ChoosePix($::CurrentDir.::SLASH, $string, undef,'LastFolder_Icon');
	return unless defined $file;
	my $dir=$::HomeDir.'icons';
	return if ::CreateDir($dir) ne 'ok';
	my $destfile= $dir. ::SLASH. Picture($gid,$field,'icon');
	unlink $destfile.'.svg',$destfile.'.png';
	if ($file eq '0') {}	#unset icon
	elsif ($file=~m/\.svg/i)
	{	$destfile.='.svg';
		::copy($file,$destfile.'.svg');
	}
	else
	{	$destfile.='.png';
		my $pixbuf=::PixBufFromFile($file,48);
		return unless $pixbuf;
		$pixbuf->save($destfile,'png');
	}
	::LoadIcons();
}

sub FilterListFields
{	grep $Def{$_}{FilterList}, @Fields;
}
sub FilterListProp
{	my ($field,$key)=@_;
	if ($key eq 'picture') {return $Def{$field}{picture_field}}
	if ($key eq 'multi') {return $Def{$field}{flags}=~m/l/ }
	$Def{$field}{FilterList}{$key};
}
sub ColumnsKeys
{	grep $Def{$_}{flags}=~m/c/, @Fields;
}
sub ColumnAlign
{	return 0 unless $Def{$_[0]};
	return $Def{$_[0]}{rightalign};
}
sub InfoFields		#used for song info dialog, currently same fields as ColumnsKeys
{	sort { ::superlc($Def{$a}{name}) cmp ::superlc($Def{$b}{name}) } grep $Def{$_}{flags}=~m/c/, @Fields;
	#FIXME sort according to a number like $Def{$_}{order}
	#was : (qw/title artist album year track disc version genre rating label playcount lastplay skipcount lastskip added modif comment file path length size bitrate filetype channel samprate/)
}
sub SortKeys
{	grep $Def{$_}{flags}=~m/s/, @Fields;
}
sub Field_All_string
{	my $f=$_[0];
	return $Def{$f} && exists $Def{$f}{all_count} ? $Def{$f}{all_count} : _"All";
}
sub FieldName
{	my $f=$_[0];
	return $Def{$f} && exists $Def{$f}{name} ? $Def{$f}{name} : _"Unknown field ($f)";
}
sub MainField
{	my $f=$_[0];
	return Songs::Code($f,'mainfield') || $f;
}
sub FieldWidth
{	my $f=$_[0];
	return $Def{$f} && $Def{$f}{width} ? $Def{$f}{width} : 100;
}
sub ListGroupTypes
{	my @list= grep $Def{$_}{can_group}, @Fields;
	my @ret;
	for my $field (@list)
	{	my $val=$field;
		my $name=FieldName($field);
		my $types=LookupCode($field,'subtypes_menu');
		if ($types)
		{	$val=[map( ("$field.$_"=> "$name ($types->{$_})"), keys %$types)];
		}
		push @ret, $val,$name;
	}
	return \@ret;
}
sub EditFields	#type is one of qw/single many per_id/
{	my $type=$_[0];
	my @fields= grep $Def{$_}{flags}=~m/e/, @Fields;
	@fields= grep $Def{$_}{edit_many}, @fields  if $type eq 'many';
	@fields= sort	{ 	($Def{$a}{edit_order}||1000) <=> ($Def{$b}{edit_order}||1000)
				|| $Def{$a}{name} cmp $Def{$b}{name}
			} @fields;
	return @fields;
}
sub EditWidget
{	my ($field,$type,$IDs)=@_;	#type is one of qw/single many per_id/
	my ($sub)= LookupCode($field, "editwidget:all|editwidget:$type|editwidget");
	unless ($sub) {warn "Can't find editwidget for field $field\n"; return undef;}
	return $sub->($field,$IDs);
}
sub StringFields #list of fields that are strings, used for selecting fields for interactive search
{	grep SortICase($_), @Fields; #currently use SortICase #FIXME ?
}
sub SortGroup
{	my $f=$_[0];
	$f=~s#\..*##; #FIXME should be able to sort on "modif.year" and others, but for now, simplfy it into "modif"
	return $Def{$f}{sortgroup} || SortField($f);
}
sub SortICase
{	my $f=$_[0];
	return $Def{$f} && $Def{$f}{flags}=~m/i/;
}
sub SortField
{	my $f=$_[0];
	return $Def{$f} && $Def{$f}{flags}=~m/i/ ? $f.=':i' : $f;  #case-insensitive by default
}
sub FindFirst		#FIXME add a few fields (like 'disc track path file') to all sort so that the sort result is constant, ie doesn't depend on the starting order
{	my ($listref,$sort)=@_;
	my $func= $FuncCache{"FindFirst $sort"} ||=
	 do {	#my $insensitive;
		my @code;
		for my $s (split / /,$sort)
		{	my ($inv,$field,$i)= $s=~m/^(-)?(\w+)(:i)?$/;
			next unless $field;
			unless ($Def{$field}) { warn "Songs::SortList : Invalid field $field\n"; next }
			unless ($Def{$field}{flags}=~m/s/) { warn "Don't know how to sort $_[0]\n"; next }
			push @code, SortCode($field,$inv,$i);
		}
		return unless @code;
		#if ($insensitive) { my $sort0=$sort; $sort0=~s/:i//g; SortList($listref,$sort0); } #do a case-sensitive sort first (faster)
		#warn "sort function for '$sort' :\n".'sub {'.join(' || ',@code).'}'."\n" if $::debug;
		my $code= 'sub {my $l=$_[0];$a=$l->[0]; for $b (@$l) { $a=$b if (' . join(' || ',@code) . ')>0; } return $a;}';
		Compile("FindFirst $sort", $code);
	    };
	return $func->($listref);
}
sub SortList		#FIXME add a few fields (like 'disc track path file') to all sort so that the sort result is constant, ie doesn't depend on the starting order
{	my $time=times; #DEBUG
	my $listref=$_[0]; my $sort=$_[1]; warn "Songs::SortList(@_)\n";
	#warn "known sort functions :\n"; warn "$_\n" for grep m/^sort /, keys %FuncCache;
	my $func= $FuncCache{"sort $sort"} ||=
	 do {	#my $insensitive;
		my @code;
		for my $s (split / /,$sort)
		{	my ($inv,$field,$i)= $s=~m/^(-)?(\w+)(:i)?$/;
			next unless $field;
			unless ($Def{$field}) { warn "Songs::SortList : Invalid field $field\n"; next }
			unless ($Def{$field}{flags}=~m/s/) { warn "Don't know how to sort $_[0]\n"; next }
			push @code, SortCode($field,$inv,$i);
		}
		return unless @code;
		#if ($insensitive) { my $sort0=$sort; $sort0=~s/:i//g; SortList($listref,$sort0); } #do a case-sensitive sort first (faster)
		#warn "sort function for '$sort' :\n".'sub {'.join(' || ',@code).'}'."\n" if $::debug;
		my $code= 'sub {' . join(' || ',@code) . '}';
		Compile("sort $sort", $code);
	    };
	@$listref=sort $func @$listref if $func;
	$time=times-$time; warn "sort ($sort) : $time s\n"; #DEBUG
}
sub SortDepends
{	my @f=split / /,shift;
	s/^-//,s/:i$// for @f;
	return [Depends(@f)];
}
sub ReShuffle
{	my @shuffle;
	push @shuffle, rand(256**4) for 0..$LastID;
	$Songs::Songs_shuffle=pack 'L*',@shuffle; #FIXME should be eval'ed code
}

sub Depends
{	my @fields=@_;
	my %h;
	for my $f (grep $_ ne '', @fields)
	{	$f=~s#[.:].*##;
		unless ($Def{$f}) {warn "Songs::Depends : Invalid field $f\n";next}
		$h{$f}=undef;
		if (my $d= $Def{$f}{depend}) { $h{$_}=undef for split / /,$d; }
	}
	#delete $h{none};
	return keys %h;
}

sub GetTagValue #rename ?
{	my ($ID,$field)=@_;
	warn "GetTagValue : $ID,$field\n" if $::debug;
	unless ($Def{$field}{flags}=~m/g/) { warn "GetTagValue : invalid field '$field'\n"; return undef }
	$ID=FindID($ID);
	unless (defined $ID) { warn "GetTagValue : song not found\n"; return undef }
	return Get($ID,$field);
}
sub SetTagValue #rename ?
{	my ($ID,$field,$value)=@_;
	warn "SetTagValue : $ID,$field,$value\n" if $::debug;
	#unless (exists $Set{$field}) { warn "SetTagValue : invalid field\n"; return ::FALSE }
	$ID=FindID($ID);
	unless (defined $ID) { warn "SetTagValue : song not found\n"; return ::FALSE }
	Set($ID,$field=>$value);
	return ::TRUE;	#FIXME could check if it has worked
}

sub BuildHash
{	my ($field,$IDs,$opt,@types)=@_; #warn "Songs::BuildHash(@_)\n";
	$opt= $opt? ':'.$opt : '';
	my ($keycode,$multi)= LookupCode($field, 'hash'.$opt.'|hash', 'hashm'.$opt.'|hashm',[ID => '$ID']);
	unless ($keycode || $multi) { warn "BuildHash error : can't find code for field $field\n"; return } #could return empty hashes ?
	($keycode,my $keyafter)= split / +---- +/,$keycode||$multi,2;
	@types=('count') unless @types;

	my $after='';
	my $code;
	my $i;
	for my $type (@types)
	{	$i++;
		my ($f,$opt)=split /:/,$type,2;
		$opt= $opt ? 'stats:'.$opt : 'stats';
		my $c= $GTypes{$f} ? $GTypes{$f}{code} : LookupCode($f, $opt); #FIXME could be better
		$c=~s/#ID#/\$ID/g;
		($c,my $af)= split / +---- +/,$c,2;
#warn "BuildHash $field  : $f  $opt => $c // $af\n";
		my $hval= $multi ? '$h'.$i.'{$key}' : "\$h$i\{$keycode}";
		$code.=  Macro($c, HVAL=> $hval).";\n";
		$after.= Macro($keyafter, H=> 'h'.$i).";\n" if $keyafter; #not used yet
		$after.= "for my \$key (keys \%h$i) {". Macro($af, HVAL=> '$h'.$i.'{$key}')."}\n" if $af;
	}
	$code="for my \$key ($keycode) {\n  $code\n}\n" if $multi;
	$code="for my \$ID (@\$lref) {\n  $code\n}\n$after";
	my $hlist= join ',',map "\%h$_",1..$i;
	my $hlistref= join ',',map "\\\%h$_",1..$i;
	$code= "my \$lref=\$_[0]; my ($hlist);\n$code;\nreturn $hlistref;";

#warn "BuildHash($field $opt,@types)=>\n$code\n";
	my $sub= eval "sub { no warnings 'uninitialized'; $code }";
	if ($@) { warn "BuildHash compilation error :\ncode: $code\nerror: $@";}
	$IDs||=[FIRSTID..$LastID];
	$sub->( $IDs ); #returns one hash ref by @types
}

sub AllFilter
{	my $filter=$_[0];
	Filter->new($filter)->filter( [FIRSTID..$LastID] );
}

#sub GroupSub_old
#{	my $field=$_[0]; #warn "Songs::GroupSub : @_\n";
#	return $FuncCache{"GroupSub $field"} ||= do
#	 {	my $code= Code($field, 'group', ID => '-ID-');
#		$code=~s/ *(ne|!=) *$//;
#		my $op=$1||'ne';
#		my $code0=$code;
#		$code =~s/-ID-/\$list->[\$_]/g;
#		#$code0=~s/-ID-/\$list->[\$_-1]/g;
#		$code0=~s/-ID-/\$list->[\$_[1]]/g;
#		my $f=eval "sub { my \$list=\$_[0]; my \$v0=$code0; [grep {$code $op \$v0 and \$v0=$code,1;} \$_[1]+1..\$_[2] ] }";
#		#my $f=eval "sub { my \$list=\$_[0]; [grep {$code $op $code0} \$_[1]..\$_[2] ] }";
#		if ($@) { warn "GroupSub compilation error :\ncode: $code $op $code0\nerror: $@"; $f=sub {warn "invalid groupsub (field=$field)";[]}}
#		$f;
#	 };
#}
sub GroupSub
{	my $field=$_[0]; #warn "Songs::GroupSub : @_\n";
	return $FuncCache{"GroupSub $field"} ||= do
	 {	my $code= Code($field, 'group', ID => '-ID-');
		$code=~s/ *(ne|!=) *$//;
		my $op=$1||'ne';
		my $code0=$code;
		$code =~s/-ID-/\$list->[\$_]/g;
		$code0=~s/-ID-/\$list->[\$firstrow]/g;
		Compile("GroupSub $field",
		'sub {	my ($list,$lastrows_parent)=@_;
			my @lastrows;my @lastchild;
			my $firstrow=0;
			for my $lastrow (@$lastrows_parent)
			{	my $v0='.$code0.';
				push @lastrows, map $_-1, grep {'."$code $op ".'$v0 and $v0='.$code.',1;} $firstrow+1..$lastrow;
				push @lastrows, $lastrow;
				push @lastchild, $#lastrows;
				$firstrow=$lastrow+1;
			}
			return \\@lastrows,\\@lastchild;
		     }')
	    		#use a dummy function in case of error :
		 	|| sub {warn "invalid groupsub (field=$field)"; my $lastrows=$_[1]; return [@$lastrows],[0..$#$lastrows] };
	 };
}


package AA;
our (%GHash,%GHash_Depend);

our %ReplaceFields=
(	'%'	=>	sub {'%'},
	a	=>	sub { my $s=Songs::Gid_to_Display($_[0],$_[1]); defined $s ? $s : $_[1]; }, #FIXME PHASE1 Gid_to_Display should return something $_[1] if no gid_to_display
	l	=>	sub { my $l=Get('length:sum',$_[0],$_[1]); $l=::__x( ($l>=3600 ? _"{hours}h{min}m{sec}s" : _"{min}m{sec}s"), hours => (int $l/3600), min => ($l>=3600 ? sprintf('%02d',$l/60%60) : $l/60%60), sec => sprintf('%02d',$l%60)); },
	L	=>	sub { ::CalcListLength( Get('idlist',$_[0],$_[1]),'length:sum' ); }, #FIXME is CalcListLength needed ?
	y	=>	sub { Get('year:range',$_[0],$_[1]); },
	Y	=>	sub { my $y=Get('year:range',$_[0],$_[1]); return $y? " ($y)" : '' },
	s	=>	sub { my $l=Get('idlist',$_[0],$_[1])||[]; ::__('%d song','%d songs',scalar @$l) },
	x	=>	sub { my $nb=@{GetXRef($_[0],$_[1])}; return $_[0] ne 'album' ? ::__("%d Album","%d Albums",$nb) : ::__("%d Artist","%d Artists",$nb);  },
	X	=>	sub { my $nb=@{GetXRef($_[0],$_[1])}; return $_[0] ne 'album' ? ::__("%d Album","%d Albums",$nb) : $nb>1 ? ::__("%d Artist","%d Artists",$nb) : '';  },
	b	=>	sub { my $l=Songs::UniqList('artist', Get('idlist',$_[0],$_[1])); return @$l==1 ? $l->[0] : ::__("%d artist","%d artists", scalar(@$l));  },	#FIXME check if done correctly
);

sub ReplaceFields
{	my ($gid,$format,$col,$esc)=@_;
#my $u;$u=$format; #DEBUG DELME
	$format=~s#\\n#\n#g;
	if($esc){ $format=~s/%([alLyYsxXb%r])/::PangoEsc($ReplaceFields{$1}->($col,$gid))/ge; }
	else	{ $format=~s/%([alLyYsxXb%r])/$ReplaceFields{$1}->($col,$gid)/ge; }
#warn "ReplaceFields $gid : $u => $format\n" if defined $u; #DEBUG DELME
	return $format;
}

sub CreateHash
{	my ($type,$field)=@_; warn "AA::CreateHash(@_)\n";
	my @f=  $Songs::GTypes{$type} ? ($field) : ($type,$field);
	$GHash_Depend{$_}++ for Songs::Depends(@f);
	return $GHash{$field}{$type}=Songs::BuildHash($field,$::Library,undef,$type);
}
sub Fields_Changed
{	my %changed;
	$changed{$_}=undef for @_;
	undef %GHash_Depend;
	delete $GHash{$_} for keys %changed;
	for my $field (keys %GHash)
	{	my @d0=Songs::Depends($field);
		if (grep exists $changed{$_}, @d0)
		{	delete $GHash{$field};
			next;
		}
		my $subh=$GHash{$field};
		for my $type (keys %$subh)
		{	my @d;
			@d=Songs::Depends($type) unless $Songs::GTypes{$type};
			if (grep exists $changed{$_}, @d) { delete $subh->{$type} }
			else { $GHash_Depend{$_}++ for @d0,@d; }
		}
	}
}
sub IDs_Changed	#called when songs are added/removed
{	undef %GHash_Depend;
	undef %GHash;
	warn "IDs_Changed\n";
}
sub GetHash
{	my ($type,$field)=@_;
	return $GHash{$field}{$type} || CreateHash($type,$field);
}
sub Get
{	my ($type,$field,$key)=@_;
	my $h = $GHash{$field}{$type} || CreateHash($type,$field);#warn( 'DEBUG   '.join('//',(keys %$h)[0..10])."...\n key=$key => $h->{$key}\n" );
	return $h->{$key};
}
sub GetAAList
{	my $field=$_[0];
	CreateHash('idlist',$field) unless $GHash{$field};
	my ($h)= values %{$GHash{$field}};
	return [keys %$h];
}

sub GetXRef # get albums/artists from artist/album
{	my ($field,$key)=@_;
	my $x= $field eq 'album' ? 'artists:gid' : 'album:gid';
	return Get($x,$field,$key) || [];
}
sub GetIDs
{	return Get('idlist',@_) || [];
}

sub GrepKeys
{	my ($field,$string,$list)=@_;
	my $re=qr/\Q$string\E/i;
	$list||=GetAAList($field);
	my $displaysub=Songs::DisplayFromGID_sub($field);
	my @l=grep $displaysub->($_)=~m/$re/i, @$list;	#FIXME optimize ?
	return \@l;
}

sub SortKeys
{	my ($field,$list,$mode,$hsongs)=@_;
	my $invert= $mode=~s/^-//;
	my $h=my $pre=0;
	$mode||='';
	if ($mode eq 'songs') { $h=$hsongs; $pre='number'; }
	if ($mode eq 'length')
	{	$h= GetHash('length:sum',$field);
		$pre='number';
	}
	elsif ($mode eq 'year')
	{	$h= GetHash('year:range',$field);
		$pre='string';	#string because values are of the format : "1994 - 2000"
	}
	elsif ($mode eq 'year2') #use highest year
	{	$h= GetHash('year:range',$field);
		$pre='year2';	#sort using the 4 last characters
	}
	Songs::sort_gid_by_name($field,$list,$h,$pre,$mode);
	@$list=reverse @$list if $invert;
	return $list;
}

#package GMB::Filename;
#use overload ('""' => 'stringify');
#sub new
#{	my ($class,$filename)=@_;
#	::_utf8_off($filename);
#	return my $self= bless \$filename, $class;
#}
#sub stringify
#{	my $self=shift;
#	return $$self;
#}
#sub new_from_string
#{	my ($class,$string)=@_;
#	return $class->new(::decode_url($string));
#}
#sub save_to_string
#{	my $self=shift;
#	return ::url_escape($$self);
#}

package SongArray;
my @list_of_SongArray;
my @need_update;
my $init;
my %Presence;

sub DESTROY
{	my $self=$_[0];
	warn "SongArray DESTROY\n";
	@list_of_SongArray= grep defined, @list_of_SongArray;
	::weaken($_) for @list_of_SongArray; warn @list_of_SongArray." songarrays left\n";
	delete $Presence{$self};
}
sub new
{	my ($class,$ref)=@_;
	$ref||=[];
	push @need_update, $ref if $init;
	push @list_of_SongArray,$ref;
	::weaken($list_of_SongArray[-1]);
	my $self= bless $ref, $class;
	return $self;
}
sub new_copy
{	my ($class,$ref)=@_;
	$ref= $ref ? [@$ref] : [];
	return $class->new($ref);
}
sub new_from_string
{	my ($class,$string)=@_;
	my @list= map 0+$_, split / /,$string;		#0+$_ to convert to number => use less memory
	return $class->new(\@list);
}
sub start_init {$init=1}
sub updateIDs	#update IDs coming from an older session
{	my $newIDs=shift;
	$init=undef;
	while (my $l=shift @need_update)
	{	@$l= grep $_,map $newIDs->[$_], @$l; #IDs start at 1, removed songs get ID=undef and are then removed by the grep $_
	}
}
sub build_presence
{	my $self=$_[0];
	my $s=''; vec($s,$_,1)=1 for @$self;
	$Presence{$self}=$s,
}
sub IsIn
{	my ($self,$ID)=@_;
	$self->build_presence unless $Presence{$self};
	vec($Presence{$self},$ID,1);
}
sub AreIn
{	my ($self,$IDs)=@_;
	$self->build_presence unless $Presence{$self};
	return [grep vec($Presence{$self},$_,1), @$IDs];
}
sub save_to_string
{	return join ' ',map sprintf("%d",$_), @{$_[0]};	#use sprintf so that the numbers are not stringified => use more memory
}

sub GetName  #not used for now, remove ?
{	my $self=$_[0];
	my $sl=$::Options{SavedLists};
	my ($name)= grep $sl->{$_}==$self, keys %$sl;
	return $name;	#might be undef or a special name (starts with \x00)
}

sub RemoveIDsFromAll		#could probably be improved
{	my $IDs_toremove=$_[0];
	my $isin='';
	vec($isin,$_,1)=1 for @$IDs_toremove;
	for my $self (grep defined, @list_of_SongArray)
	{	my @rows=grep vec($isin,$self->[$_],1), 0..$#$self;
		$self->Remove(\@rows) if @rows;
	}
}

sub Sort
{	my ($self,$sort)=@_;
	my @old=@$self;
	Songs::SortList($self,$sort);
	::HasChanged('SongArray',$self,'sort',$sort,\@old);
}
sub SetFilter			#KEEP ?
{	my ($self,$filter)=@_;
	$filter||=Filter->new;
	my $new=$filter->filter;
	$self->Replace($new,filter=> $filter);
}
sub Replace				#DELME PHASE1 %info not used remove ?
{	my ($self,$new,%info)=@_;
	@$self= $new ? @$new : ();
	delete $Presence{$self};
	::HasChanged('SongArray',$self,'replace',%info);
}
sub Shift
{	my $self=$_[0];
	my $ID=$self->[0];
	$self->Remove([0]);
	return $ID;
}
sub Pop
{	my $self=$_[0];
	my $ID=$self->[-1];
	$self->Remove([$#$self]);
	return $ID;
}
sub Unshift
{	my ($self,$IDs)=@_;
	$self->Insert(0,$IDs);
}
sub Push
{	my ($self,$IDs)=@_;
	$self->Insert(scalar @$self,$IDs);
}
sub Insert
{	my ($self,$destrow,$IDs)=@_;
	splice @$self,$destrow,0,@$IDs;
	if ($Presence{$self}) {vec($Presence{$self}, $_, 1)=1 for @$IDs;}
	::HasChanged('SongArray',$self,'insert', $destrow,$IDs);
}
sub Remove
{	my ($self,$rows,$IDs)=@_;	#$IDs may be undef and is ignored, just there to make mirroring easier
	my @rows=sort { $a <=> $b } @$rows;
	my @IDs;
	push @IDs, splice @$self,$_,1 for reverse @rows;
	delete $Presence{$self};
	::HasChanged('SongArray',$self,'remove', \@rows,\@IDs);
}
sub Move
{	my ($self,$dest_row,$rows,$dest_row_final)=@_;	#$dest_row_final may be undef and is ignored, just there to make mirroring easier
	my @rows=sort { $a <=> $b } @$rows;
	my @IDs;
	my $dest_row_orig=$dest_row;
	for my $row (reverse @rows)
	{	push @IDs,splice @$self,$row,1;
		$dest_row-- if $row<$dest_row;
	}
	splice @$self,$dest_row,0,reverse @IDs;
	::HasChanged('SongArray',$self,'move', $dest_row_orig,\@rows,$dest_row);
	return \@rows;
}
sub Top
{	my ($self,$rows)=@_;
	$self->Move(0,$rows);
}
sub Bottom
{	my ($self,$rows)=@_;
	$self->Move(scalar @$self,$rows);
}
sub Up
{	my ($self,$rows)=@_;
	my @rows=sort { $a <=> $b } @$rows;
	my $first=0;
	shift @rows while @rows && $rows[0]==$first++; #remove rows already at the top
	return unless @rows;
	@$self[$_-1,$_]= @$self[$_,$_-1] for @rows; #move rows up
	::HasChanged('SongArray',$self,'up', \@rows);
	return \@rows;
}
sub Down
{	my ($self,$rows)=@_;
	my @rows=sort { $a <=> $b } @$rows;
	my $last=$#$self;
	pop @rows while @rows && $rows[-1]==$last--; #remove rows already at the bottom
	return unless @rows;
	@$self[$_+1,$_]= @$self[$_,$_+1] for reverse @rows; #move rows down
	::HasChanged('SongArray',$self,'down', \@rows);
	return \@rows;
}

#sub Mirror
#{	my ($self,$songarray,@args)=@_;
#	@$self=@$songarray;
#	::HasChanged('SongArray', $self, @args);
#}

package SongArray::PlayList;
use base 'SongArray';

sub init
{	$::ListPlay=SongArray::PlayList->new;

	my $sort=$::Options{Sort};
	$::RandomMode= $sort=~m/^random:/ ? Random->new($sort,$::ListPlay) : undef;
	$::SortFields= $::RandomMode ? $::RandomMode->fields : Songs::SortDepends($sort);

	my $last=$::Options{LastPlayFilter} || Filter->new; ::red(listmode=>$::ListMode);
	if (ref $last && $last->isa('Filter'))	{ $::ListPlay->SetFilter($last); }
	else					{ $::ListPlay->Replace($last); }
	 ::red(listmode=>$::ListMode);

	::Watch(undef, SongsChanged	=> \&SongsChanged_cb);
	::Watch(undef, SongsAdded	=> \&SongsAdded_cb);
	::Watch(undef, SongArray	=> \&SongArray_changed_cb);
	return $::ListPlay;
}

sub Sort
{	my ($self,$sort)=@_;
	my $old=$::Options{Sort};
	if ($::RandomMode || $old=~m/shuffle/)	{ $::Options{Sort_LastSR}=$old; }		# save sort mode for
	elsif ($old ne '')			{ $::Options{Sort_LastOrdered}=$old; }		# quick toggle random/non-random
	$::RandomMode= $sort=~m/^random:/ ? Random->new($sort,$self) : undef;
	$::Options{Sort}=$sort;
	$::SortFields= $::RandomMode ? $::RandomMode->fields : Songs::SortDepends($sort);
	$self->UpdateSort;
	if ($::RandomMode || !@$self)	{ $::Position=undef }
	else
	{	$::Position= defined $::SongID ? ::FindPositionSong($::SongID,$self) : undef;
		$::Position||=0;
	}
	::HasChanged('Sort');
	#::HasChanged('Pos');
}
sub Replace
{	my ($self,$newlist)=@_;
	delete $::ToDo{'7_refilter_playlist'};
	delete $::ToDo{'8_resort_playlist'};
	$newlist=SongArray->new unless defined $newlist;
	$::Options{LastPlayFilter}=$newlist;
	$newlist= SongArray->new_copy($newlist) if ref $newlist && ref $newlist ne 'SongArray';
	unless (ref $newlist)
	{	::SaveList($newlist,[]) unless $::Options{SavedLists}{$newlist};
		$newlist= $::Options{SavedLists}{$newlist};
	}
	$::SelectedFilter=$::PlayFilter=undef;
	$::ListMode= $newlist;
	 ::red(listmode=>$::ListMode);::callstack();
	my $ID=$::SongID;
	$ID=undef if defined $ID && !$newlist->IsIn($ID);
	if (!defined $ID)
	{	$ID= $self->_FindFirst($newlist);
	}
	$self->_updatelock($ID) if $::TogLock && defined $ID;
	@$self=@$::ListMode;
	delete $Presence{$self};
	if ($::RandomMode)	{ $::RandomMode->Invalidate; ::red("Invalidate $self ".@$self) }
	else			{ $::SortFields=[]; $::Options{Sort}=''; ::HasChanged('Sort'); }
	::HasChanged('Filter');
	::HasChanged('SongArray',$self,'replace');
	::UpdateCurrentSong(ID=>$ID);
}
sub Insert
{	my ($self,$destrow,$IDs)=@_;
	$self->_staticfy;
	$self->SUPER::Insert($destrow,$IDs);
	if (defined $::Position && $::Position>=$destrow)
	{	$::Position+=@$IDs;
		::red("position error after insert") if $self->[$::Position] != $::SongID; #DEBUG
	}
	elsif (@$self==@$IDs && !defined $::SongID)	#playlist was empty
	{	$self->Next;
	}
	::HasChanged('Pos');

	#set Position if playlist was empty ??
}
sub Remove
{	my ($self,$rows)=@_;
	$self->SUPER::Remove($rows);
	if (@$self==0) { $::Position=$::SongID=undef; _updateID(undef); return; }
	if (defined $::Position)
	{	my $pos=$::Position;
		my @rows=sort { $a <=> $b } @$rows;
		my $IDchanged;
		for my $row (reverse @rows)
		{	$IDchanged=1 if $pos==$row;
			$pos-- if $pos>=$row;
		}
		$pos=0 if $pos<0;
		$::Position=$pos;
		$self->Next if $IDchanged;
	}
	if ($::RandomMode)
	{	$::RandomMode->RmIDs;
	}
	::HasChanged('Pos');
}
sub Up
{	my ($self,$rows)=@_;
	$self->_staticfy;
	$rows=$self->SUPER::Up($rows);
	return unless $rows;
	if (defined $::Position)
	{	my $pos= $::Position;
		for my $row (@$rows)
		{	if	($row==$pos)	{$pos--}
			elsif	($row==$pos+1)	{$pos++}
		}
		if ($::Position!=$pos) { $::Position=$pos; ::HasChanged('Pos'); }
	}
}
sub Down
{	my ($self,$rows)=@_;
	$self->_staticfy;
	$rows=$self->SUPER::Down($rows);
	return unless $rows;
	if (defined $::Position)
	{	my $pos= $::Position;
		for my $row (reverse @$rows)
		{	if	($row==$pos)	{$pos++}
			elsif	($row==$pos-1)	{$pos--}
		}
		if ($::Position!=$pos) { $::Position=$pos; ::HasChanged('Pos'); }
	}
}
sub Move
{	my ($self,$destrow,$rows)=@_;
	$self->_staticfy;
	$rows=$self->SUPER::Move($destrow,$rows);
	if (defined $::Position)
	{	my $pos=$::Position;
		my @rows=sort { $a <=> $b } @$rows;
		for my $row (reverse @rows)
		{	if	($pos==$row)			{$pos=$destrow}
			elsif	($pos<$row && $destrow<$row)	{$pos++}
			elsif	($pos>$row && $destrow>$row)	{$pos--}
			$destrow++;
		}
		if ($::Position!=$pos) { $::Position=$pos; ::HasChanged('Pos'); }
	}
}

#watchers callbacks		#FIXME add a watcher for $::ListMode
sub SongsAdded_cb
{	my (undef,$IDs)=@_;
	return if $::ListMode;
	return if $::ToDo{'7_refilter_playlist'};
	return unless $::PlayFilter;
	my $toadd=$::PlayFilter->added_are_in($IDs);
	return unless $toadd;
	if (ref $toadd) { $::ListPlay->Add($toadd); }
	else
	{	::IdleDo('7_refilter_playlist',9000, \&UpdateFilter, $::ListPlay);
	}
}
sub SongsChanged_cb
{	my (undef,$IDs,$fields)=@_;
if (!$fields || grep(!defined, @$fields)) { ::callstack(@_,'fields=>',@$fields) }	#DEBUG
	return if $::ToDo{'7_refilter_playlist'};
	if ($::PlayFilter && $::PlayFilter->changes_may_affect($IDs,$fields,$::ListPlay))
	{	::IdleDo('7_refilter_playlist',9000, \&UpdateFilter, $::ListPlay);
	}
	elsif (::OneInCommon($fields,$::SortFields))
	{	::IdleDo('8_resort_playlist',5000, \&UpdateSort, $::ListPlay);
	}
}
sub SongArray_changed_cb
{	my (undef,$songarray,$action,@extra)=@_;
	return unless $::ListMode && $songarray==$::ListMode;
#	my $sameorder= $::Options{Sort} eq '';
#	if	($action eq 'sort')	{ $::ListPlay->Sort('') if $sameorder; }
#	#elsif	($action eq 'insert')	{ $::ListPlay->Insert(@extra); }
#	elsif	($action eq 'insert')
#	{	if ($sameorder) {$::ListPlay->Insert(@extra);}
#		else		{$::ListPlay->Add(@extra);}
#	}
#	#elsif	($action eq 'remove')	{ $::ListPlay->Remove(@extra); }
#	elsif	($action eq 'remove')
#	{	my ($rows,$IDs)=@extra;
#		if ($sameorder) {$::ListPlay->Remove($rows);}
#		else
#		{	my %h; $h{$_}++ for @$IDs;
#			my @rows=grep $h{$::ListPlay->[$_]} && $h{$::ListPlay->[$_]}--, 0..$#$::ListPlay;
#			$::ListPlay->Remove(\@rows);
#		}
#	}
#	elsif	($action eq 'move')	{ $::ListPlay->Move(@extra) if $sameorder; }
#	elsif	($action eq 'up')	{ $::ListPlay->Up(@extra) if $sameorder; }
#	elsif	($action eq 'down')	{ $::ListPlay->Down(@extra) if $sameorder; }
#	else				{ $::ListPlay->Replace($::ListMode); }
		#@$::ListPlay= @$songarray;
		#FIXME sort unless $sameorder;
		#::HasChanged('SongArray',$::ListPlay,'update');
}

#non-SongArray methods :
sub Next
{	::NextSong();
}
sub SetFilter
{	my ($self,$filter)=@_;
	$::ListMode=undef;
	$::Options{Sort}=$::Options{Sort_LastOrdered} unless $::Options{Sort};
	$::Options{LastPlayFilter}= $::SelectedFilter= $filter || Filter->new;
	my $newID=$self->_filter;
	::HasChanged('Filter');
	::HasChanged('SongArray',$self,'replace', filter=> $::PlayFilter);
	_updateID($newID);
}
sub UpdateFilter
{	my $self=shift;
	my @oldlist=@$self;
	my $before=$::PlayFilter;
	my $newID=$self->_filter;
	if ($before==$::PlayFilter)
	{	::HasChanged('SongArray',$self,'update',\@oldlist);
	}
	else	#filter may change because of the lock
	{	::HasChanged('Filter');
		::HasChanged('SongArray',$self,'replace', filter=> $::PlayFilter);
	}
	_updateID($newID);
}
sub UpdateSort
{	my $self=shift;
	my @old;
	@old=@$self unless $::RandomMode;
	$self->_sort;
	::HasChanged('SongArray',$self,'sort',$::Options{Sort},\@old) unless $::RandomMode;
	_updateID($::SongID);
}

sub InsertAtPosition
{	my ($self,$IDs)=@_;
	my $pos=defined $::Position? $::Position+1 : 0;
	$self->Insert($pos,$IDs);
}
sub Add
{	my ($self,$IDs)=@_;
	::red("CHECKME ListPLay->Add($self,$IDs)");
	$self->SUPER::Push($IDs);
	if ($::RandomMode)
	{	$::RandomMode->AddIDs(@$IDs);
	}
	elsif (my $s=$::Options{Sort})
	{	$self->SUPER::Sort($s);
	}
	::HasChanged('Pos');
}

sub SetID
{	my ($self,$ID)=@_;
	$::ChangedID=1;
	$::SongID=$ID;
	if ($self->IsIn($ID) || !$::Library->IsIn($ID))
	{	::UpdateCurrentSong();
		return
	}
	elsif ($::TogLock && defined $ID && @$self)
	{	my $newlist=$self->_list_without_lock;
		if (::IDIsInList($newlist,$ID))
		{	$self->_updatelock($ID,$newlist);
			$self->_sort($newlist);
			::HasChanged('SongArray',$self,'replace', filter=> $::PlayFilter);
			::UpdateCurrentSong();
			return;
		}
	}
	$self->SetFilter;
}

#private functions
sub _updateID
{	my $ID=shift;
	$::ChangedID=1 if !defined $::SongID || !defined $ID || $ID!=$::SongID;
	$::SongID=$ID;
	::UpdateCurrentSong();
}
sub _filter
{	my $self=shift;
	delete $::ToDo{'7_refilter_playlist'};
	my $filter=$::SelectedFilter;
	my $ID=$::SongID;
	$ID=undef if defined $ID && !@{ $filter->filter([$ID]) };
	$filter= Filter->newadd(1,$filter, Filter->newlock($::TogLock,$ID) )  if $::TogLock && defined $ID;
	$::PlayFilter=$::SelectedFilter;
	my $newlist=$filter->filter;
	if (!defined $ID)
	{	$ID= $self->_FindFirst($newlist);
		$self->_updatelock($ID) if $::TogLock && defined $ID;
	}
	$self->_sort($newlist);
	@$self=@$newlist;
	delete $Presence{$self};
	return $ID;
}
sub _sort
{	my ($self,$list)=@_;
	$list||=$self;
::red(scalar @$list);
	delete $::ToDo{'8_resort_playlist'};
	if ($::RandomMode)	{ $::RandomMode->Invalidate; }
	elsif ($::Options{Sort}){ Songs::SortList($list,$::Options{Sort}); }
	elsif ($::ListMode)
	{	@$self=@$::ListMode;
	}
}
sub _FindFirst
{	my ($self,$list)=@_;
	my $ID;
	if (!@$list) { $ID=undef; }
	elsif ($::RandomMode)
	{	($ID)=Random->OneTimeDraw($::RandomMode,$list,1);
	}
	else
	{	$ID=  Songs::FindFirst($list,$::Options{Sort});
	}
	return $ID;
}
sub _list_without_lock
{	my $self=shift;
	return [@$::ListMode] if $::ListMode;
	return $::SelectedFilter->filter;
}
sub _updatelock
{	my ($self,$ID,$list)=@_;
	$ID=$::SongID unless defined $ID;
	$list||= $self->_list_without_lock;
	my $lockfilter=Filter->newlock($::TogLock,$ID);
	$::PlayFilter= $::ListMode ? $lockfilter : Filter->newadd(1,$::SelectedFilter,$lockfilter);
}
sub _staticfy
{	my $self=shift;
	delete $::ToDo{'7_refilter_playlist'};
	delete $::ToDo{'8_resort_playlist'};
	return unless $::TogLock || $::PlayFilter;
	$::ListMode=SongArray->new_copy($self);
	::HasChanged('SongArray',$self,'mode');
	if ($::TogLock)		{ $::TogLock=undef;	::HasChanged('Lock');	}
	if ($::PlayFilter)	{ $::PlayFilter=undef;	::HasChanged('Filter');	}
	if (!$::RandomMode && $::Options{Sort})	{ $::SortFields=[]; $::Options{Sort}=''; ::HasChanged('Sort'); }
}

#sub _updatepos
#{	$::PositionUpdate=0;
#	if (!defined $::Position && !$::RandomMode && defined $::SongID)
#	{	
#	}
#	::HasChanged('Pos');
#}


#package SongArray::WithFilter	#DELME
#our base 'SongArray';
#our %Filter;
#sub new
#{	my ($class,$filter)=@_;
#	my $ref= $filter ? $filter->filter : undef;
#	my $self = $class->SUPER::new($ref);
#	$Filter{$self}=$filter;
#}
#sub DESTROY
#{	my $self=$_[0];
#	warn "SongArray::WithFilter DESTROY\n";
#	delete $Filter{$self};
#	$self->SUPER::DESTROY;
#}
#sub SetFilter
#{	my ($self,$filter)=@_;
#	$Filter{$self}=$filter;
#	$self->Replace($filter->filter);
#}
#sub SongAdded_cb
#{	my $IDs=shift;
#	for my $self (grep $_->isa(__PACKAGE__),@list_of_SongArray)
#	{	my $filter=$Filter{$self};
#		my ($greponly)=$filter->info;
#		if ($greponly)
#		{	my $toadd=$filter->filter($IDs);
#			$self->Push($toadd);
#		}
#		else {queue}
#	}
#}
#sub SongChanged_cb
#{	my ($IDs,$fields)=@_;
#	for my $self (grep $_->isa(__PACKAGE__),@list_of_SongArray)
#	{	my $filter=$Filter{$self};
#		my ($greponly,$depfields)=$filter->info;
#		next unless ::OneInCommon($depfields,$fields);
#		if ($IDs && $greponly)
#		{	queue
#			#$self->build_presence unless $Presence{$self};
#			#my $match=$filter->filter($IDs);
#			#my @in =grep  vec($Presence{$self},$_,1), @$IDs;
#			#my @out=grep !vec($Presence{$self},$_,1), @$IDs;
#		}
#		else {queue}
#	}
#}

package GMB::ListStore::Field;
use Gtk2;
use base 'Gtk2::ListStore';

our %ExistingStores;

sub new
{	my ($class,$field)=@_; #warn "creating new store for $field\n";
	my @cols=('Glib::String');
	push @cols, 'Glib::String' if $Songs::Def{$field}{icon}; #FIXME
	my $self= bless Gtk2::ListStore->new(@cols), $class;
	$ExistingStores{$field}= $self;
	::weaken $ExistingStores{$field};
	::IdleDo("9_ListStore_$field",500,\&update,$field);
	::Watch($self,fields_reset=>\&changed);
	return $self;
}

sub getstore
{	my $field=$_[0];
	return $ExistingStores{$field} || new(__PACKAGE__,$field);
}
sub setcompletion
{	my ($entry,$field)=@_;
	my $completion=Gtk2::EntryCompletion->new;
	$completion->set_text_column(0);
	if ($Songs::Def{$field}{icon}) #FIXME
	{	my $cell=Gtk2::CellRendererPixbuf->new;
		$completion->pack_start($cell,0);
		$completion->add_attribute($cell,'stock-id',1);
	}
	$completion->set_model( getstore($field) );
	$entry->set_completion($completion);
}

sub changed
{	@_= keys %ExistingStores unless @_;
	for my $field (@_)
	{	next unless $ExistingStores{$field};
		::IdleDo("9_ListStore_$field",5000,\&update,$field);
	}
}

sub update
{	my $field=$_[0];
	delete $::ToDo{"9_ListStore_$field"};
	my $store=$ExistingStores{$field};
	return unless $store;
	$store->{updating}=1;
	$store->clear;
	my $list=Songs::ListAll($field);
	if (my $icon=$Songs::Def{$field}{icon}) { $store->set($store->append,0,$_,1, $icon->($_)) for @$list; } #FIXME
	else	{ $store->set($store->append,0,$_) for @$list; }
	delete $store->{updating};
	::HasChanged("ListStore_$field");
}

package GMB::ListStore::Field::Combo;
use Gtk2;
use base 'Gtk2::ComboBox';

sub new
{	my ($class,$field,$init,$callback)=@_;
	my $store= GMB::ListStore::Field::getstore($field);
	my $self= bless Gtk2::ComboBox->new_with_model($store), $class;

	my $cell=Gtk2::CellRendererText->new;
	$self->pack_start($cell,1);
	$self->set_attributes($cell,text=>0);
	if ($Songs::Def{$field}{icon})
	{	my $cell=Gtk2::CellRendererPixbuf->new;
		$self->pack_start($cell,0);
		$self->set_attributes($cell,stock_id=>1);
	}
	$self->{value}=$init;
	$self->update if defined $init;
	$self->{callback}=$callback;
	$self->signal_connect( changed => \&changed_cb );
	::Watch($self,"ListStore_$field",\&update);
	return $self;
}

sub update
{	my $self=$_[0];
	my $value= $self->{value};
	return unless defined $value;
	my $store=$self->get_model;
	$self->{busy}=1;
	for (my $iter=$store->get_iter_first; $iter; $iter=$store->iter_next($iter))
	{	$self->set_active_iter($iter),last if $store->get($iter,0) eq $value;
	}
	delete $self->{busy};
}

sub changed_cb
{	my $self=$_[0];
	return if $self->{busy};
	my $store=$self->get_model;
	return if $store->{updating};
	my $iter= $self->get_active_iter;
	$self->{value}= $iter ? $store->get($iter,0) : undef;
	if (my $cb=$self->{callback})
	{	$cb->( $self,$self->{value} );
	}
}

sub get_value { $_[0]{value}; }

package Filter;

my %NGrepSubs;
my @CachedStrings; our $CachedList;
our (%InvOp,$OpRe);
INIT
{
  my @Oplist= qw( =~ !~   || &&   > <=   < >=   == !=   eq ne  !! ! );	#negated operators for negated filters
  %InvOp= (@Oplist, reverse @Oplist);
  $OpRe=join '|',map quotemeta, keys %InvOp;
  $OpRe=qr/\.($OpRe)\./;
  %NGrepSubs=
  (	t => sub
	     {	my ($field,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref; @\$tmp= sort {".Songs::SortCode($field,0)."} @\$tmp; $assign @\$tmp[$inv];";
		#return "\$tmp=$lref;Songs::SortList(\$tmp,$field);$assign @\$tmp[$inv];";
	     },
	h => sub
	     {	my ($field,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref; @\$tmp= sort {".Songs::SortCode($field,1)."} @\$tmp; $assign @\$tmp[$inv];";
		#return "\$tmp=$lref;Songs::SortList(\$tmp,-$field);$assign @\$tmp[$inv];";
	     },
	l => sub	#is in a saved lists
	     {	my ($n,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? '!' : '';
		return '$tmp={}; $$tmp{$_}=undef for @{$::Options{SavedLists}{"'."\Q$pat\E".'"}};'
			.$assign.'grep '.$inv.'exists $$tmp{$_},@{'.$lref.'};';
	     },
  );
}

#Filter object contains :
# - string :	string notation of the filter
# - sub    :	ref to a sub which takes a ref to an array of IDs as argument and returns a ref to the filtered array
# - greponly :	set to 1 if the sub dosn't need to filter the whole list each times -> ID can be tested individualy
# - fields :	ref to a list of the columns used by the filter

sub new_from_string { &new }
sub save_to_string { $_[0]->{string}; }

sub new
{	my ($class,$string,$source) = @_;
	my $self=bless {}, $class;
	if	(!defined $string)	  {$string='';}
	elsif ($string=~m/^(-)?(\d+)(\D)(.*)$/) { my $o=$string; $string=($1||'').Songs::FieldUpgrade($2).':'.($3 eq 'f' ? '~' : $3).':'.$4; warn "Old filter $o FIXME => $string\n" } #PHASE1
	elsif	($string=~m/^-?\w+:~:/) { ($string)=_smart_simplify($string); }
	$self->{string}=$string;
	$self->{source}=$source;
	return $self;
}

sub newadd
{	my ($class,$and,@filters)=@_; #warn "Filter::newadd(@_) called from : ".join(':',caller)."\n";
	my $self=bless {}, $class;
	my %sel;

	my ($ao,$re)=$and? ( '&', qr/^\(\&\x1D(.*)\)\x1D$/)
			 : ( '|', qr/^\(\|\x1D(.*)\)\x1D$/);
	my @strings;
	my @supersets;
	for my $f (@filters)
	{	$f='' unless defined $f;
		$self->{source} ||= $f->{source} if ref $f;
		my $string=(ref $f)? $f->{string} : $f;
		unless ($string)
		{	next if $and;			# all and ... = ...
			return $self->{string}='';	# all or  ... = all
		}
		if ($string=~s/$re/$1/)			# a & (b & c) => a & b & c
		{	my $d=0; my $str='';
			for (split /\x1D/,$string)
			{	if    (m/^\(/)	{$d++}
				elsif (m/^\)/)	{$d--}
				elsif (!$d)	{push @strings,$_;next}
				$str.=$_."\x1D";
				unless ($d) {push @strings,$str; $str='';}
			}
		}
		else
		{	if ($string=~m/^(-)?(\d+)(\D)(.*)$/) { warn "Old filter $string FIXME\n"; $string=($1||'').Songs::FieldUpgrade($2).":$3:".$4; warn " => $string\n"} #PHASE1
			push @strings,( ($string=~m/^-?\w+:~:/)
					? _smart_simplify($string,!$and)
					: $string
				      );
		}
		if ($and)
		{	push @supersets, $string;
			push @supersets, @{$f->{superset_filters}} if ref $f && $f->{superset_filters};
		}
	}

	@strings=_between_simplify($and,@strings);

	my %exist;
	my $sum=''; my $count=0;
	for my $s (@strings)
	{	$s.="\x1D" unless $s=~m/\x1D$/;
		next if $exist{$s}++;		#remove duplicate filters
		$sum.=$s; $count++;
	}
	$sum="($ao\x1D$sum)\x1D" if $count>1;

	$self->{string}=$sum;
	warn "Filter->newadd=".$self->{string}."\n" if $::debug;
	$self->{superset_filters}= \@supersets unless $sum=~m#(?:^|\x1D)-?\w*:[th]:#;	#don't use superset optimization for head/tail filters, as they are not commutative
	return $self;
}

sub set_parent	#indicate that this filter will only match songs that match $superset_filter, used for optimization when the result of $superset_filter is cached
{	my ($self,$superset_filter)=@_;
	$self->{superset_filters}=[ $superset_filter->{string} ] unless $superset_filter->{string} eq $self->{string};
}

sub _between_simplify #not tested enough
{	my $and=shift;
	my @strings;
	my (%between,%max,%min);
	for my $s (@_)
	{	if ($s=~m/^(-?\w+):b:(\d+) (\d+)\x1D?$/)
		{	if ($s!~m/^-/ xor $and)		#=> combine the range
			{	my $end=$between{$1}{$2};
				$between{$1}{$2}=$3 unless $end && $end>$3;
				warn "{$1}{$2}=$3";
			}
			else	#=> reduce to common range
			{	my $max=$max{$1}; my $min=$min{$1};
				$max{$1}=$3 unless defined $max && $max<$3;
				$min{$1}=$2 unless defined $min && $min>$2;
			}
		}
#FIXME >/< or >=/<= problem
#		elsif (m/^(\w+):>:(\d+)\x1D?$/ || m/^-(\w+):<:(\d+)\x1D?$/)
#		{	my $min=$min{$1};
#			$min{$1}=$2 unless defined $min && ($min>$2 xor $and);
#		}
#		elsif (m/^(\w+):<:(\d+)\x1D?$/ || m/^-(\w+):>:(\d+)\x1D?$/)
#		{	my $max=$max{$1};
#			$max{$1}=$2 unless defined $max && ($max<$2 xor $and);
#		}
		else {push @strings,$s}
	}
	for my $s (keys %min)
	{	my $min=$min{$s};
		if (exists $max{$s}) { push @strings,"$s:b:$min $max{$s}"; delete $max{$s} }
		else { push @strings,"$s:>:$min{$s}";warn "FIXME"; }#not used for now, see above >/< or >=/<= problem
	}
	for my $s (keys %max)
	{	push @strings,"$s:<:$max{$s}";warn "FIXME";#not used for now, see above >/< or >=/<= problem
	}
	for my $s (keys %between)
	{	my $h=$between{$s};
		my @l=sort {$a<=>$b} keys %$h;
		warn "@l";
		my @replace; my $i=0;
		while ($i<=$#l)
		{	my $start=$l[$i];
			my $end=$h->{$start};
			while ($i<$#l && $l[$i+1]<=$end+1) { my $end2=$h->{$l[$i+1]}; $end=$end2 if $end2>$end; $i++ }
			push @strings,"$s:b:$start $end";
			#warn " -> $s:b:$start $end";
			$i++;
		}
	}
	s/^(-?\w+):b:(\d+) \2\x1D?$/"$1:e:".($2? $2:'')/e for @strings; #replace :b:5 5 by :e:5
	return @strings;
}


sub are_equal #FIXME could try harder
{	my $f1=$_[0]; my $f2=$_[1];
	($f1,my$s1)=defined $f1 ? ref $f1 ? ($f1->{string},$f1->{source}) : $f1 : '';
	($f2,my$s2)=defined $f2 ? ref $f2 ? ($f2->{string},$f2->{source}) : $f2 : '';
	return ($f1 eq $f2) && ((!$s1 && !$s2) || $s1 eq $s2);
}

sub _smart_simplify	#only called for ~ filters
{	my $s=$_[0]; my $returnlist=$_[1];
	my ($inv,$field,$pat)= $s=~m/^(-)?(\w+):~:(.*)$/;
	$inv||='';
	my $sub=Songs::LookupCode($field,'filter_simplify:~');
	return $s unless $sub;
	my @pats=$sub->($pat);
	if ($returnlist || @pats==1)
	{	return map $inv.$field.':~:'.$_ , @pats;
	}
	else
	{	return "(|\x1D".join('',map($inv.$field.':~:'.$_."\x1D", @pats)).")\x1D";
	}
}

sub newlock #FIXME PHASE1 remove ? use MakeFilterFromID instead
{	my ($class,$field,$ID)=@_;
	return Songs::MakeFilterFromID($field,$ID);
}

sub invert
{	my $self=shift;
	$self->{'sub'}=undef;
	warn 'before invert : '.$self->{string} if $::debug;
	my @filter=split /\x1D/,$self->{string};
	for (@filter)
	{	s/^\(\&$/(|/ && next;
		s/^\(\|$/(&/ && next;
		next if $_ eq ')';
		$_='-'.$_ unless s/^-//;
	}
	$self->{string}=join "\x1D",@filter;
	warn 'after invert  : '.$self->{string} if $::debug;
	return $self;
}

sub filter
{	my $self=$_[0]; my $listref=$_[1];
	#my $time=times;								#DEBUG
	$listref||= $self->{source} || $::Library;
	my $sub=$self->{'sub'} || $self->makesub;
	my $on_library= ($listref == $::Library && !$self->{source});
	if ($CachedList && $on_library)
	{	return [unpack 'L*',$CachedList->{$self->{string}}] if $CachedList->{$self->{string}};
		#warn "no exact cache for filter\n";
		if ($self->{superset_filters})
		{	my @supersets= grep defined, map $CachedList->{$_}, @{$self->{superset_filters}};
			if (@supersets)
			{	#warn "found supersets : ".join(',', map length $_,@supersets)."\n";
				#warn " from : ".join(',', grep $CachedList->{$_}, @{$self->{superset_filters}})."\n";
				$listref= [unpack 'L*',(sort { length $a <=> length $b } @supersets)[0] ];	#take the smaller set, could find the intersection instead
			}
		}
	}
	my $r=$sub->($listref);
	#$time=times-$time; warn "filter $time s ( ".$self->{string}." )\n" if $debug;	#DEBUG
	if ($on_library)
	{	$CachedList->{$self->{string}}= pack 'L*',@$r;
		push @CachedStrings,$self->{string};
		delete $CachedList->{shift @CachedStrings} if @CachedStrings>5;	#keep 5 results max	#FIXME : keep recently used results
	}
	return $r;
}

sub info
{	my $self=shift;
	$self->makesub unless $self->{'sub'};
	return $self->{greponly}, keys %{$self->{fields}};
}
sub added_are_in		#called with $IDs of a SongsAdded event, return true if new songs may match the filter. If greponly filter, returns a ref to a list of new IDs that match, or false if none match
{	my ($self,$IDs)=@_;
	$self->makesub unless $self->{'sub'};
	if ($self->{greponly})
	{	my $toadd=$self->filter($IDs);
		$toadd=0 unless @$toadd;
		return $toadd;
	}
	return 1;
}
sub changes_may_affect		#called with $IDs and $fields of a SongsChanged event, return true if the changes might require an update. Tries harder if a songarray is specified and a greponly filter
{	my ($self,$IDs,$fields,$songarray)=@_;		#$songarray argument is optional, currently untested
	return 0 unless grep exists $self->{fields}{$_}, @$fields;
	$self->makesub unless $self->{'sub'};
	if ($songarray && $self->{greponly})
	{	my $before= $songarray->AreIn($IDs);
		my $after=  $self->filter($IDs);
		return 1 if @$after != @$before;
		for my $i (0..$#$before) { return 1 if $before->[$i]!=$after->[$i]; }
		return 0;
	}
	return 1;
}

sub _optimize_with_hashes	# optimization for some special cases
{	my @filter=split /\x1D/,$_[0];
	return ($_[0]) if @filter<3;
	my $hashes=$_[1] || [];
	my $d=0; my (@or,@val,@ilist);
	for my $i (0..$#filter)
	{	my $s=$filter[$i];
		if    ($s=~m/^\(/)	  { $d++; $or[$d]=($s eq '(|')? 1 : 0; }
		elsif ($s eq ')')
		{	my $vd=delete $val[$d];
			my $ilist=delete $ilist[$d];
			while (my ($icc,$h)=each %$vd)
			{	next unless (keys %$h)>2; #only optimize if more than 2 keys
				my ($inv,$field,$cmd)=$icc=~m/^(-?)(\w+):([^:]+):$/;
				my ($ok,$prephash)=Songs::LookupCode($field, 'filter:h'.$cmd, 'filter_prephash:'.$cmd, [HREF=> '$_[0]']);
				next unless $ok;
				if ($prephash)
				{	$prephash= Songs::Compile('filter_prephash:'.$cmd,"sub {$prephash}") unless ref $prephash;
					$h=$prephash->($h);
				}
				my $l=$ilist->{$icc}; #index list of filters to be replaced
				my $first=$l->[0]; my $last=$l->[-1];
				if ( $last-$first==$#$l
					&& $filter[$first-1] && $filter[$first-1]=~m/^\(/
					&& $filter[$last+1] eq ')'
				   )
				 {push @$l,$first-1,$last+1} #add ( && ) to the removed filters if all those inside are replaced by the hash
				$filter[$_]=undef for @$l; #remove filters to be replaced by the hash
				push @$hashes,$h;
				$filter[$first]="$inv$field:h$cmd:".$#$hashes;
			}
			$d--;
		}
		elsif ( $s=~m/^(-?)(\w+):([e~]):(.*)$/ && ($or[$d] xor $1) )
		{	$val[$d]{"$1$2:$3:"}{$4}=undef;		#add key to the hash
			push @{$ilist[$d]{"$1$2:$3:"}},$i;	#store filter index to remove it later if it is replaced
		}
	}
	my $filter=join "\x1D", grep defined,@filter; #warn "$_\n" for @filter;
	return $filter,$hashes;
}

sub singlesong_code
{	my ($self,$depends,$hashes)=@_;
	my $filter=$self->{string};
	return '1' if $filter eq '';
	return undef if $filter=~m#\x1D^-?\w*:[thal]:#;
	($filter)=_optimize_with_hashes($filter,$hashes) if $hashes;
	my $code=makesub_condition($filter,$depends);
	return $code;
}

sub makesub
{	my $self=$_[0];
	my $filter=$self->{string};
	warn "makesub filter=$filter\n" if $::debug;
	$self->{fields}={};
	if ($filter eq '') { return $self->{'sub'}=sub {$_[0]}; }

	($filter,my $hashes)=_optimize_with_hashes($filter);

	my $func;
	my $depends=$self->{fields}={};
	if ( $filter=~m#(?:^|\x1D)-?\w*:[thl]:# ) { $func=makesub_Ngrep($filter,$depends) }
	else
	{	$self->{greponly}=1;
		$func=makesub_condition($filter,$depends);
		$func='[ grep {'.$func.'} @{$_[0]} ];';
	}

	my $before='';
	if ($hashes) {$before.="my \$hash$_=\$hashes->[$_];"  for 0..$#$hashes;}
	warn "filter=$filter \$sub=eval $before; sub{ $func }\n" if $::debug;
	my $sub=eval "$before; sub {$func}";
	if ($@) { warn "filter error :\n code:\n$before; sub {$func}\n error:\n$@"; $sub=sub {$_[0]}; }; #return empty filter if compilation error
	return $self->{'sub'}=$sub;
}

sub makesub_condition
{	my $filter=$_[0];
	my $depends=$_[1]||{};
	my $func='';
	my $op=' && ';
	my @ops;
	my $first=1;
	for (split /\x1D/,$filter)
	{	if (m/^\(/)
		{	$func.=$op unless $first;
			$func.='(';
			push @ops,$op;
			$op=($_ eq '(|')? ' || ' : ' && ';
			$first=1;
		}
		elsif ($_ eq ')') { $func.=')'; $op=pop @ops; }
		else
		{	my ($inv,$field,$cmd,$pat)= m/^(-?)(\w*):([^:]+):(.*)$/;
			$depends->{$_}=undef for Songs::Depends($field);
			$func.=$op unless $first;
			$func.= Songs::FilterCode($field,$cmd,$pat,$inv);
			$first=0;
		}
	}
	return $func;
}
sub makesub_Ngrep	## non-grep filter
{	my @filter= split /\x1D/,$_[0];
	my $depends=$_[1]||{};

	{	my $d=0; my $c=0;
		for (@filter)
		{	if    (m/^\(/)	  {$d++}
			elsif ($_ eq ')') {$d--}
			elsif ($d==0)	  {$c++}
		}
		@filter=('(',@filter,')') if $c;
	}
	my $d=0;
	my $func='my @hash; my @list=($_[0]); my $tmp;';
	my @out=('@{$_[0]}'); my @in; my @outref;
	my $listref='$_[0]';
	for my $f (@filter)
	{   if ($f=~m/^[\(\)]/)
	    {	if ($f ne ')') #$f begins with '('
		{	$d++;
			$func.='@{$list['.$d.']}=@{$list['.($d-1).']};';
			if ($f eq '(|')
			{	$func.=		    '$hash['.$d.']={};';
				$out[$d]=    'keys %{$hash['.$d.']}';
				$outref[$d]='[keys %{$hash['.$d.']}]';
				$in[$d]=	    '$hash['.$d.']{$_}=undef for ';
				}
			else	# $f eq '(&' or '('
			{	$outref[$d]='$list['.$d.']';
				$out[$d]= '@{$list['.$d.']}';
				$in[$d]=  '@{$list['.$d.']}=';
			}
			$listref='$list['.$d.']';
		}
		else # $f eq ')'
		{	$d--; if ($d<0) { warn "invalid filter\n"; return undef; }
			$func.=($d==0)	? 'return '.$outref[1].';'
					:   $in[$d].$out[$d+1].';';
		}
	    }
	    else
	    {	my ($inv,$field,$cmd,$pat)= $f=~m/^(-?)(\w*):([^:]+):(.*)$/;
		$depends->{$_}=undef for Songs::Depends($field);
		unless ($cmd) { warn "Invalid filter : $field $cmd $pat\n"; next; }
		if (my $sub=$NGrepSubs{$cmd})
		{	$func.= $NGrepSubs{$cmd}->($field,$pat,$listref,$in[$d],$inv);
		}
		else
		{	my $c=Songs::FilterCode($field,$cmd,$pat,$inv);
			$func.= $in[$d].'grep '.$c . ',@{'.$listref.'};';
		}
	    }
	}
	return $func;
}

sub is_empty
{	my $f=$_[0];
	return 1 unless defined $f;
	return if $f->{source}; #FIXME
	$f=$f->{string} if ref $f;
	return ($f eq '');
}

sub explain	# return a string describing the filter
{	my $self=shift;
	return $self->{desc} if $self->{desc};
	my $filter=$self->{string};
	return _"All" if $filter eq '';
	my $text=''; my $depth=0;
	for my $f (split /\x1D/,$filter)
	{   if ($f=~m/^\(/)		# '(|' or '(&'
	    {	$text.=' 'x$depth++;
		$text.=($f eq '(|')? _"Any of :" : _"All of :";
		$text.="\n";
	    }
	    elsif ($f eq ')') { $depth--; }
	    else
	    {   next if $f eq '';
		my ($pos,@vals)=FilterBox::filter2posval($f);
		$text.='  'x$depth;
		if (defined $pos) { $text.=FilterBox::posval2desc($pos,@vals)."\n"; }
		else { $text.="Unknown filter : '$f'(FIXME)\n"; }
	    }
	}
	chomp $text;	#remove last "\n"
	return $self->{desc}=$text;
}

sub SmartTitleSimplify
{	my $s=$_[0];
	$s=~s#(?<=.) *[\(\[].*##;	#remove '(...' unless '(' is at the begining of the string
	my @pats=grep m/\S/, split / *\/+ */,$s;
	return @pats;
}
sub SmartTitleRegEx
{	local $_=quotemeta ::superlc($_[0]);
	s#\\'# ?. ?#g;		#for 's == is ...
	s#\Bing\b#in[g']#g;
	s#\\ is\b#(?:'s|\\ is)#ig;
	s#\\ (?:and|\\&|et)\\ #\\ (?:and|\\&|et)\\ #ig;
	s#\\[-,.]#.?#g;
	s# ?\\\?# ?\\?#g;
	return $_;
}
sub QuoteRegEx
{	local $_=$_[0];
	s#^((?:.*[^\\])?(?:\\\\)*\\)$#$1\\#g; ##escape trailing '\' in impair number
	s!((?:\G|[^\\])(?:\\\\)*)\\?"!$1\\"!g; #make sure " are escaped (and only once, so that \\\" doesn't become \\\\")
	return $_;
}

package Random;
our %ScoreTypes;

INIT
{
  %ScoreTypes=
 (	f =>
	{	desc	=> _"Label is set",	#depend	=> 'label',
		default=> '.5f',
		filter	=> 'label:~:',
	},
	g =>
	{	desc	=> _"Genre is set",	#depend	=> 'genre',
		default=> '.5g',
		filter	=> 'genre:~:',
	},
	l =>
	{	depend	=> 'lastplay',	desc	=> _"Number of days since last played",	unit	=> _"days",
		round	=> '%.1f',	default=> '-1l10',
		value	=> 'lastplay:daycount',
		time_dependant =>1,
	},
	L =>
	{	depend	=> 'lastskip',	desc	=> _"Number of days since last skipped",	unit	=> _"days",
		round	=> '%.1f',	default=> '1L10',
		value	=> 'lastskip:daycount',
		time_dependant =>1,
	},
	a =>
	{	depend	=> 'added',	desc	=> _"Number of days since added",	unit	=> _"days",
		round	=> '%.1f',	default=> '1a50',
		value	=> 'added:daycount',
		time_dependant =>1,
	},
	n =>
	{	depend	=> 'playcount',	desc	=> _"Number of times played",	unit	=> _"times",
		round	=> '%d',	default=> '1n5',
		value	=> 'playcount:get',
	},
	N =>
	{	depend	=> 'skipcount',	desc	=> _"Number of times skipped",	unit	=> _"times",
		round	=> '%d',	default=> '-1N5',
		value	=> 'skipcount:get',
	},
	r =>
	{	depend	=> 'rating',	desc	=> _"Rating",	unit	=> '%%',
		round	=> '%d',	default=> '1r0_.1_.2_.3_.4_.5_.6_.7_.8_.9_1',
		value	=> 'rating:percent',	#score	=> sub { my ($value,$extra)=@_;my @l=split /,/,$extra; return undef unless @l==11; return '('.$extra.')[int('.$value.'/10)]' },
	},
 );
}

sub new
{	my ($class,$string,$list)=@_;
	my $self=bless {}, $class;
	$string=~s/^random://;
	$self->{string}=$string;
	$self->{lref}=$list;
	return $self;
}
sub OneTimeDraw
{	my ($class,$string,$list,$nb)=@_;
	$string=$string->{string} if ref $string;
	my $self=$class->new($string,$list);
	$self->Draw($nb);
}

sub fields
{	my $self=shift;
	$self->make unless exists $self->{depends};
	return [split / /,$self->{depends}];
}

sub make
{	my $self=shift;
	return ($self->{before},$self->{score}) if $self->{score};
	$self->{hashes}=[];
	my %depends;
	my @scores;
	::setlocale(::LC_NUMERIC, 'C');
	for my $s ( split /\x1D/, $self->{string} )
	{	my ($inverse,$weight,$type,$extra)=$s=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)/;
		next unless $type;
		my $score;
		if (my $value=$ScoreTypes{$type}{value})
		{	$score= Songs::Code(split(/:/,$value), ID => '$_', QVAL => quotemeta $extra);
			$depends{$_}=undef for Songs::Depends( $ScoreTypes{$type}{depend} );
		}
		else
		{	my $filter= ($ScoreTypes{$type}{filter} || '').$extra;
			$filter=Filter->new($filter);
			$score= $filter->singlesong_code(\%depends,$self->{hashes});
		}
		$self->{time_computed}=1 if $ScoreTypes{$type}{time_dependant}; #indicate that the values must be recomputed as time pass
		if ($type eq 'f' || $type eq 'g')
		{	#$score=&$score($extra);
		}
		elsif ($type eq 'r')
		{	my @l=split /,/,$extra;
			next unless @l==11;
			$score='('.$extra.')[int('.$score.'/10)]';
		}
		else
		{	$inverse=!$inverse;
			if (my $halflife=$extra)
			{	my $lambda=log(2)/$halflife;
				$score="exp(-$lambda*$score)";
			}
			else {$score='0';}
		}
		$inverse=($inverse)? '1-':'';
		$score=(1-$weight).'+'.$weight.'*('.$inverse.$score.')';
		push @scores,$score;
	}
	unless (@scores) { @scores=(1); }
	$self->{depends}=join ' ',keys %depends;
	$self->{before}='';
	if ($self->{hashes}) { $self->{before}.="my \$hash$_=\$self->{hashes}[$_];"  for 0..$#{$self->{hashes}}; }
	$self->{score}="\n(".join(")\n*(",@scores).')';
	::setlocale(::LC_NUMERIC, '');
	return ($self->{before}, $self->{score});
}

#sub SetList
#{	my ($self,$list)=@_;
#	$self->{lref}=$list;
#	$self->{valid}=0;;
#}
sub MakeScoreFunction
{	my $self=shift;
	my @Score;
	$self->{Slist}=\@Score;
	my ($before,$score)=$self->make;
	my $func= $before.'; sub { $Score[$_]='.$score.' for @{$_[0]}; }';
	my $sub=eval $func;
	if ($@) { warn "Error in eval '$func' :\n$@"; $Score[$_]=1 for @{$_[0]}; }
	$self->{UpdateIDsScore}=$sub;
}
sub AddIDs
{	my $self=shift;
	$self->{UpdateIDsScore}(\@_) if $self->{valid};
	$self->{Sum}=undef;
}
sub RmIDs
{	$_[0]{Sum}=undef;
}
sub Invalidate
{	my $self=shift;
	#@{ $self->{Slist} }=();
	$self->{valid}=0;
}

sub Draw
{	my ($self,$nb,$no_list)=@_;
	#my $time=times;
	#(re)compute scores if invalid or (older than 10 min and time-dependant)
	if (!$self->{valid} || ($self->{time_computed} && time-$self->{time_computed}>10*60))
	{	::red( "recompute for list with $self->{lref} ".@{$self->{lref}}." IDs");
		$self->MakeScoreFunction unless $self->{UpdateIDsScore};
		$self->{UpdateIDsScore}($self->{lref});
		$self->{time_computed}=time if $self->{time_computed};
		$self->{valid}=1;
		$self->{Sum}=undef;
	}
	my $lref=$self->{lref};
	my @scores=@{ $self->{Slist} };
	my (@list,$sum);
	if ($no_list)	#list of IDs that must not be picked
	{	my %no;
		$no{$_}++ for @$no_list;
		@list=grep !$no{$_}, @$lref;
		$sum=0;
		$sum+=$scores[$_] for @list;
	}
	else
	{	@list=@$lref;
		$sum=$self->{Sum};
		if (!defined $sum)
		{	$sum=0;
			$sum+=$scores[$_] for @$lref;
			$self->{Sum}=$sum;
		}
	}
	if ($nb) { $nb=@list if $nb>@list; }
	else
	{	return () if defined $nb;
		$nb=@list;
	}
	my @drawn;
	#my $time=times;
	my (@chunknb,@chunksum);
	if ($nb>1)
	{	my $chunk=0; my $count;
		my $size=int(@list/60); $size=15 if $size<15;
		for my $id (@list)
		{	$chunksum[$chunk]+=$scores[$id];
			$chunknb[$chunk]++;
			$count||=$size;
			$chunk++ unless --$count;
		}
	}
	else { $chunksum[0]=$sum; $chunknb[0]=@list; }
	#warn "\@chunknb=@chunknb\n"   if $::debug;
	#warn "\@chunksum=@chunksum\n" if $::debug;
	NEXTDRAW:while ($nb>0)
	{	last unless $sum>0;
		my $r=rand $sum; my $savedr=$r;
		my $start=my $chunk=0;
		until ($chunksum[$chunk]>$r)
		{	$start+=$chunknb[$chunk];
			$r-=$chunksum[$chunk++];
			#warn "no more chunks : savedr=$savedr r=$r chunk=$chunk" if $chunk>$#chunksum;
			last NEXTDRAW if $chunk>$#chunksum;#FIXME rounding error
		}
		for my $i ($start..$start+$chunknb[$chunk]-1)
		{	next if ($r-=$scores[$list[$i]])>0;
			$nb--;
			my $id=splice @list,$i,1;
			push @drawn,$id;
			$sum-=$scores[$id];
			if (--$chunknb[$chunk]) { $chunksum[$chunk]-=$scores[$id]; }
			else
			{	splice @chunknb,$chunk,1;
				splice @chunksum,$chunk,1;
			}
			next NEXTDRAW;
		}
		#warn $r; warn $nb;
		last;
	}
	#warn "drawing took ".(times-$time)." s\n" if $::debug;

	if ($nb && @list)	#if still need more -> select at random (no weights)
	{	$nb=@list if $nb>@list;
		my @rand; push @rand,rand for @list;
		push @drawn,map $list[$_], (sort { $rand[$a] <=> $rand[$b] } 0..$#list)[0..$nb-1];
	}
	return @drawn;
}

sub MakeTab
{	my ($self,$nbcols)=@_;
	my ($before,$score)=$self->make;
	my $func= $before.'my $sum;my @tab=(0)x'.$nbcols.'; for (@$::ListPlay) { $sum+=my $s='.$score.'; $tab[int(.5+'.($nbcols-1).'*$s)]++;}; return \@tab,$sum;';
	my ($tab,$sum)=eval $func;
	if ($@)
	{	warn "Error in eval '$func' :\n$@";
		$tab=[(0)x$nbcols]; $sum=@$::ListPlay;
	}
	return $tab,$sum;
}

sub CalcScore
{	my ($self,$ID)=@_;
	my ($before,$score)=$self->make;
	local $_=$ID;	#ID needs to be in $_ for eval
	eval $before.$score;
}

sub MakeExample
{	my ($class,$string,$ID)=@_;
	::setlocale(::LC_NUMERIC, 'C');
	my ($inverse,$weight,$type,$extra)=$string=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)/;
	return 'error' unless $type;
	my $round=$ScoreTypes{$type}{round}||'%s';
	my $unit= $ScoreTypes{$type}{unit}||'';
	my $value=$ScoreTypes{$type}{value};
	if ($value) { $value= Songs::Code(split(/:/,$value), ID => '$_', QVAL => quotemeta $extra); }
	else
	{	my $filter= ($ScoreTypes{$type}{filter} || '').$extra;
		$filter=Filter->new($filter);
		$value= $filter->singlesong_code();
	}
	my $score;
	if ($type eq 'f' || $type eq 'g')
	{	$score=$value;
		$value="($score)? '"._("true")."' : '"._("false")."'";
	}
	elsif ($type eq 'r')
	{	my @l=split /,/,$extra;
		return 'error' unless @l==11;
		$score='('.$extra.')[int('.$value.'/10)]';
	}
	else
	{	$inverse=!$inverse;
		if (my $halflife=$extra)
		{	my $lambda=log(2)/$halflife;
			$score="exp(-$lambda*$value)";
		}
		else {$score='0';}
	}
	$inverse=($inverse)? '1-':'';
	$score=(1-$weight).'+'.$weight.'*('.$inverse.$score.')';
	::setlocale(::LC_NUMERIC, '');
	my $func='return (('.$value.'),('.$score.'));';
	local $_=$ID;	#ID needs to be in $_ for eval
	my ($v,$s)=eval $func;
	return 'error' if $@;
	return sprintf("$round $unit -> %.2f",$v,$s);
}


1;
