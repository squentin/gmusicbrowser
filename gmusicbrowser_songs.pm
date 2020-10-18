# Copyright (C) 2005-2020 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

use strict;
use warnings;
use utf8;

package Songs;

#our %Songs;
our ($IDFromFile,$MissingHash,$MissingHash_ro); my $KeepIDFromFile;
our ($Artists_split_re,$Artists_title_re,$Articles_re);
my (@MissingKeyFields,@MissingKeyFields_ro);
our (%Def,%Types,%Categories,%FieldTemplates,@Fields,%HSort,%Aliases);
my %FuncCache;
INIT {
our $nan= unpack 'F', pack('F',sin(9**9**9)); # sin 9**9**9 is slighly more portable than $nan="nan", use unpack pack because the nan will be stored that way
our %timespan_menu=
(	year 	=> _("year"),
	month	=> _("month"),
	day	=> _("day"),
);
@MissingKeyFields=qw/size title album artist track/;
@MissingKeyFields_ro=qw/size modif/;
%Categories=
(	file	=> [_"File properties",10],
	audio	=> [_"Audio properties",30],
	video	=> [_"Video properties",35],
	basic	=> [_"Basic fields",20],
	extra	=> [_"Extra fields",50],
	stats	=> [_"Statistics",40],
	unknown	=> [_"Other",80],	#fallback category
	custom	=> [_"Custom",70],
	replaygain=> [_"Replaygain",60],
);
%Types=
(	generic	=>
	{	_	=> '____[#ID#]',
		get	=> '#_#',
		set	=> '#get# = #VAL#',
		display	=> '#get#',
		grouptitle=> '#display#',
		'editwidget:many'	=> sub { my $field=$_[0]; GMB::TagEdit::Combo->new(@_, Field_property($field,'edit_listall')); },
		'editwidget:single'	=> sub { my $field=$_[0]; GMB::TagEdit::EntryString->new( @_,0,Field_property($field,'edit_listall') ); },
		'editwidget:per_id'	=> sub { my $field=$_[0]; GMB::TagEdit::EntryString->new( @_,Field_properties($field,'editwidth','edit_listall') ); },
		'filter:m'	=> '#display# .=~. m"#VAL#"',			'filter_prep:m'	=> \&Filter::QuoteRegEx,
		'filter:mi'	=> '::superlc(#display#) .=~. m"#VAL#"i',	'filter_prep:mi'=> sub { Filter::QuoteRegEx( ::superlc($_[0]) )},
		'filter:si'	=> 'index( ::superlc(#display#),"#VAL#") .!=. -1',	'filter_prep:si'=> sub {quotemeta ::superlc($_[0])},
		'filter:s'	=> 'index(    #display#, "#VAL#") .!=. -1',	'filter_prep:s'=> sub {quotemeta $_[0]},
		'filter:fuzzy'	=> '.!!. Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",lc(#get#))', 'filter_prep:fuzzy'=> sub {my @arg=split / /,$_[0],2; $arg[0],quotemeta lc($arg[1])},
		'filterpat:fuzzy'=> [ round => "%d", unit => '%', min=>20, max=>99, default_value=>65, ],
		'filterdesc:fuzzy'=> [ _"%s fuzzy match with %s",_"fuzzy match", 'fuzzy string', ],
		'filterdesc:-fuzzy'=> _"no %s fuzzy match with %s",
		'filterdesc:mi'	=> [ _"matches regexp %s",_"matches regexp",'regexp',	icase=>1, ],
		'filterdesc:si'	=> [ _"contains %s",	_"contains",	'substring',	icase=>1, ],
		'filterdesc:e'	=> [ _"is equal to %s",		_"is equal to",		'string', completion=>1, ],
		'filterdesc:m'	=> [_"matches regexp %s (case sensitive)",'mi'],
		'filterdesc:s'	=> [_"contains %s (case sensitive)", 'si'],
		'filterdesc:-m'	=> _"doesn't match regexp %s (case sensitive)",
		'filterdesc:-mi'=> _"doesn't match regexp %s",
		'filterdesc:-s'	=> _"doesn't contain %s (case sensitive)",
		'filterdesc:-si'=> _"doesn't contain %s",
		'filterdesc:-e'	=> _"isn't equal to %s",
		'smartfilter:=empty' => 'e:',
		'smartfilter:=' => 'e',
		'smartfilter:#' => \&Filter::smartstring_fuzzy,
		'smartfilter::' => 'si s',
		'smartfilter:~' => 'mi m',
		default_filter	=> 'si',
		autofill_re	=> '.+',
	},
	unknown	=>
	{	parent	=> 'generic',
	},
	virtual =>
	{	parent	=> 'string',
		_	=> '#get#',
	},
	special => {},
	flags	=>		# ___index_ : binary string containing position of the data in ___values_ for each song, or 0 for no value
				# ___values_ : binary string containing the actual data (packed with w/w: number of values followed by id values)
				# ___name & ___iname : arrays containing string for each id
				# ___gid : hash containing if for each string
				# ___free_ : array containing for each size a binary sting with the free positions in ___values_
				# when there is too much unused free space, the used parts of ___values_ are copied into a new ___values_
	{	_		=> 'do { my $i= #index#; $i ? [unpack "x".$i."w/w",___values_] : 0 }',
		index		=> 'vec(___index_,#ID#,32)',
		init		=> '___name[0]="#none#"; ___iname[0]=::superlc(___name[0]); #sgid_to_gid(VAL=$_)# for #init_namearray#',
		init		=> '___name[0]="#none#"; ___iname[0]=::superlc(___name[0]); #sgid_to_gid(VAL=$_)# for #init_namearray#; ___index_="" ;___values_="\x00";',
		init_namearray	=> '@{ $::Options{Fields_options}{#field#}{persistent_values} ||= $Def{#field#}{default_persistent_values} || [] }',
		none		=> quotemeta _"None",
		default		=> '""',
		check		=> '#VAL#= do {my $v=#VAL#; my @l; if (ref $v) {@l= @$v} else {@l= split /\x00/,$v} for (@l) { tr/\x00-\x1F//d; s/\s+$//; }; @l=sort @l; \@l }',
		get_list_gid	=> 'do { my $i= #index#; $i ? (unpack "x".$i."w/w",___values_) : () }',
		get_list	=> 'do { my $i= #index#; $i ? (map ___name[$_], unpack "x".$i."w/w",___values_) : () }',
		get_gid		=> '[#get_list_gid#]',
		gid_to_get	=> '(#GID# ? ___name[#GID#] : "")',
		gid_to_display	=> '___name[#GID#]',
		s_sort		=> '(join ":", map ___name[$_],  #get_list_gid# )',
		si_sort		=> '(join ":", map ___iname[$_], #get_list_gid# )',
		always_first_gid=> 0,
		's_sort:gid'	=> '___name[#GID#]',
		'si_sort:gid'	=> '___iname[#GID#]',
		get		=> '(join "\\x00", #get_list#)',
		display		=> '(join ", ",    #get_list#)',
		newval		=> 'push @___iname, ::superlc(___name[-1]); ::IdleDo("newgids_#field#",1000,sub {  ___new=0; ::HasChanged("newgids_#field#"); }) unless ___new++;',
		sgid_to_gid	=> '___gid{#VAL#}||= do { my $i=push(@___name, #VAL#); #newval#; $i-1; }',
		set => '{	my $v=#VAL#;
				my @list= ref $v ? @$v : split /\\x00/,$v;
				if (my $i= #index#)	# add previous space to list of free spaces
				{	my $size= length pack "w/w",unpack("x".$i."w/w",___values_);
					___free_[$size].= pack "N",$i;
					if ((___freecount_+=$size) >10_000) #if more than 10k free, schedule a cleanup
					{ ___freecount_*= -100;
					  ::IdleDo("1_reclaimfree_#field#",10_000,
					  sub
					  {	@___free_=();
						___freecount_=0;
						my $new_values="\x00";
						for my $id (FIRSTID..$Songs::LastID)
						{	if (my $i= vec(___index_,$id,32))
							{	vec(___index_,$id,32)= length $new_values;
								$new_values.= pack "w/w", unpack "x".$i."w/w",___values_;
							}
						}
						___values_= $new_values;
					  });
					}
				}
				# set new values
				if (@list)
				{	my @ids;
					for my $name (sort @list)
					{	my $id= #sgid_to_gid(VAL=$name)#;
						push @ids,$id;
					}
					my $string= pack "w/w", @ids;
					my $size= length $string;
					if (___free_[$size])	# re-use old space
					{	my $i= #index#= unpack "N", substr(___free_[$size],-4,4,"");
						substr ___values_, $i, $size, $string;
						___freecount_-=$size;
					}
					else			# use new space
					{	#index#= length(___values_);
						___values_ .= $string;
					}
				}
				else { #index#=0; }
			}',
		diff		=> 'do {my $old=#get#; my $v=#VAL#; my $new= join "\\x00", @$v; $old ne $new; }', # #VAL# should be a sorted arrayref, as returned by #check#
		check_multi	=> 'for my $lref (@{#VAL#}) { for (@$lref) {tr/\x00-\x1F//d; s/\s+$//;} }',
		set_multi	=> 'do { my %h=( map(($_=>0), #get_list#)); my ($toadd,$torm,$toggle)=@{#VAL#}; $h{$_}= (exists $h{$_} ? -1 : 1) for @$toggle; $h{$_}++ for @$toadd; $h{$_}-- for @$torm; (scalar grep $h{$_}!=0, keys %h) ? [grep $h{$_}>=0, keys %h] : undef; }',
		makefilter	=> '#GID# ? "#field#:~:".___name[#GID#] : "#field#:ecount:0"',
		'filter:~'	=> '.!!. do { grep(#VAL#==$_, #get_list_gid#)}',
		'filter_prep:~'	=> '___gid{#PAT#} ||= #sgid_to_gid(VAL=#PAT#)#;',
		'filter_prephash:~' => 'return { map { #sgid_to_gid(VAL=$_)#, undef } keys %{#HREF#} }',
		'filter:h~'	=> '.!!. do {my $v=#_#; $v ? grep(exists $hash#VAL#->{$_+0}, @$v) : 0}',
		'filter:ecount'	=> '#VAL# .==. do {my $v=#_#; $v ? scalar(@$v) : 0}',
		#FIXME for filters s,m,mi,h~,  using a list of matching names in ___inames/___names could be better (using a bitstring)
		'filter:s'	=> 'do { my $v=#_#; !$v ? .0. : (.!!. grep index(___name[$_], "#VAL#")  != -1 ,@$v); }',
		'filter:si'	=> 'do { my $v=#_#; !$v ? .0. : (.!!. grep index(___iname[$_], "#VAL#") != -1 ,@$v); }',
		'filter:fuzzy'	=> 'do { my $v=#_#; !$v ? .0. : (.!!. ::first {Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",___iname[$_])} @$v); }',
		'filter:m'	=> 'do { my $v=#_#; !$v ? .0. : (.!!. grep ___name[$_]  =~ m"#VAL#"  ,@$v); }',
		'filter:mi'	=> 'do { my $v=#_#; !$v ? .0. : (.!!. grep ___iname[$_] =~ m"#VAL#"i ,@$v); }',
		'filter_prep:m'	=> \&Filter::QuoteRegEx,
		'filter_prep:mi'=> sub { Filter::QuoteRegEx( ::superlc($_[0]) )},
		'filter_prep:si'=> sub {quotemeta ::superlc($_[0])},
		'filter_prep:s' => sub {quotemeta $_[0]},
		'filter_prep:fuzzy'=>sub {my @arg=split / /,$_[0],2; $arg[0],quotemeta ::superlc($arg[1])},
		stats		=> 'do {my $v=#_#; #HVAL#{$_+0}=undef for $v ? @$v : 0;}  ---- AFTER: #HVAL#=[map ___name[$_], keys %{#HVAL#}];',
		'stats:gid'	=> 'do {my $v=#_#; #HVAL#{$_+0}=undef for $v ? @$v : 0;}',
		hashm		=> 'do {my $v=#_#; $v ? @$v : 0 }',
		'hashm:name'	=> 'do {my $v=#_#; $v ? map(___name[$_], @$v) : () }',
		is_set		=> 'my $gid=___gid{#VAL#}; my $v=#_#; $gid && $v ? (grep $_==$gid, @$v) : 0;',
		listall		=> '1..$#___name',
		'editwidget:many'	=> sub { GMB::TagEdit::EntryMassList->new(@_) },
		'editwidget:single'	=> sub { GMB::TagEdit::FlagList->new(@_) },
		'editwidget:per_id'	=> sub { GMB::TagEdit::FlagList->new(@_) },
		autofill_re	=> '.+',
		'filterdesc:~'	=> [ _"includes %s", _"includes",	'combostring', ],
		'filterdesc:-~'	=> _"doesn't include %s",
		'filterdesc:ecount:0' => _"has none",
		'filterdesc:-ecount:0'=> _"has at least one",
		'filterdesc:mi'	=> [ _"matches regexp %s",_"matches regexp",'regexp',	icase=>1, ],
		'filterdesc:si'	=> [ _"contains %s",	_"contains",	'substring',	icase=>1, ],
		'filterdesc:m'	=> [_"matches regexp %s (case sensitive)",'mi'],
		'filterdesc:s'	=> [_"contains %s (case sensitive)", 'si'],
		'filterdesc:-m'	=> _"doesn't match regexp %s (case sensitive)",
		'filterdesc:-mi'=> _"doesn't match regexp %s",
		'filterdesc:-s'	=> _"doesn't contain %s (case sensitive)",
		'filterdesc:-si'=> _"doesn't contain %s",
		'filterdesc:fuzzy'=> [ _"%s fuzzy match with %s",_"fuzzy match", 'fuzzy string', ],
		'filterdesc:-fuzzy'=> _"no %s fuzzy match with %s",
		'smartfilter:=empty' => 'ecount:0',
		'smartfilter:=' => '~',
		'smartfilter::' => 'si s',
		'smartfilter:~' => 'mi m',
		'smartfilter:#' => \&Filter::smartstring_fuzzy,
		'filterpat:fuzzy'=> [ round => "%d", unit => '%', min=>20, max=>99, default_value=>65, ],
		default_filter	=> 'si',

		load_extra	=> '___gid{#SGID#} || return;',
		save_extra	=> 'my %h; while ( my ($sgid,$gid)=each %___gid ) { $h{$sgid}= [#SUBFIELDS#] } delete $h{""}; return \%h;',

	},
	artists	=>
	{	_		=> '____[#ID#]',
		mainfield	=> 'artist',
		#plugin		=> 'picture',
#		_name		=> '__#mainfield#_name[#_#]',
#		_iname		=> '__#mainfield#_iname[#_#]',
		get		=> 'do {my $v=#_#; ref $v ? join "\\x00",map __#mainfield#_name[$_],@$v : __#mainfield#_name[$v];}',
		display		=> 'do {my $v=#_#; ref $v ? join ", ",   map __#mainfield#_name[$_],@$v : __#mainfield#_name[$v];}',
		get_gid		=> 'my $v=#_#; ref $v ? $v : [$v]',
		's_sort:gid'	=> '__#mainfield#_name[#GID#]',
		'si_sort:gid'	=> '__#mainfield#_iname[#GID#]',
		#display	=> '##mainfield#->display#',
		get_list	=> 'my @l=( ##mainfield#->get#, grep(defined, #title->get# =~ m/$Artists_title_re/g) ); my %h; grep !$h{$_}++, map split(/$Artists_split_re/), @l;',
		gid_to_get	=> '(#GID#!=1 ? __#mainfield#_name[#GID#] : "")', # or just '__#mainfield#_name[#GID#]' ?
		gid_to_display	=> '__#mainfield#_name[#GID#]',
		update	=> 'my @ids;
			for my $name (do{ #get_list# })
			{	my $id= ##mainfield#->sgid_to_gid(VAL=$name)#;
				push @ids,$id;
			}
			#_# =	@ids==1 ? $ids[0] :
				@ids==0 ? 1 :
				(___group{join(" ",map sprintf("%x",$_),@ids)}||= \@ids);', # 1 for @ids==0 is the special gid for unknown artists defined in artist's init
		'filter:m'	=> '(ref #_# ?  (.!!. grep __#mainfield#_name[$_]  =~ m"#VAL#",  @{#_#}) : (__#mainfield#_name[#_#]  .=~. m"#VAL#"))',
		'filter:mi'	=> '(ref #_# ?  (.!!. grep __#mainfield#_iname[$_] =~ m"#VAL#"i, @{#_#}) : (__#mainfield#_iname[#_#] .=~. m"#VAL#"i))',
		'filter:s'	=> '(ref #_# ?  (.!!. grep index( __#mainfield#_name[$_],"#VAL#") != -1, @{#_#}) : (index(__#mainfield#_name[#_#],"#VAL#") .!=. -1))',
		'filter:si'	=> '(ref #_# ?  (.!!. grep index( __#mainfield#_iname[$_], "#VAL#") != -1, @{#_#}) : (index(__#mainfield#_iname[#_#], "#VAL#") .!=. -1))',
		'filter:fuzzy'	=> 'do { my $v=#_#; ref $v ? (.!!. ::first {Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",__#mainfield#_iname[$_])} @$v) : .!!. Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",__#mainfield#_iname[$v]); }',
		'filter_prep:m'	=> \&Filter::QuoteRegEx,
		'filter_prep:mi'=> sub { Filter::QuoteRegEx( ::superlc($_[0]) )},
		'filter_prep:si'=> sub { quotemeta ::superlc($_[0])},
		'filter_prep:s' => sub {quotemeta $_[0]},
		'filter_prep:fuzzy'=>sub {my @arg=split / /,$_[0],2; $arg[0],quotemeta ::superlc($arg[1])},
		'filter:~'	=> '(ref #_# ?  (.!!. grep $_ == #VAL#, @{#_#}) : (#_# .==. #VAL#))',#FIXME use simpler/faster version if perl5.10 (with ~~)
		'filter_prep:~'	=> '##mainfield#->filter_prep:~#',
		'filter_prephash:~' => '##mainfield#->filter_prephash:~#',
		'filter_simplify:~' => sub { length($_[0]) ? split /$Artists_split_re/,$_[0] : $_[0]; },
		'filter:h~'	=> '(ref #_# ?  (grep .!!. exists $hash#VAL#->{$_+0}, @{#_#}) : (.!!. exists $hash#VAL#->{#_#+0}))',
		makefilter	=> '"#field#:~:".##mainfield#->gid_to_sgid#',
		#group		=> '#_# !=',
		stats		=> 'do {my $v=#_#; #HVAL#{__#mainfield#_name[$_]}=undef for ref $v ? @$v : $v;}  ---- AFTER: #HVAL#=[keys %{#HVAL#}];',
		'stats:gid'	=> 'do {my $v=#_#; #HVAL#{$_}=undef for ref $v ? @$v : $v;}  ---- AFTER: #HVAL#=[keys %{#HVAL#}];',
		hashm		=> 'do {my $v=#_#; ref $v ? @$v : $v}',
		listall		=> '##mainfield#->listall#',
		'filterdesc:~'	=> [ _"includes artist %s", _"includes artist",	'menustring', ],
		'filterdesc:-~'	=> _"doesn't include artist %s",
		'filterdesc:mi'	=> [ _"matches regexp %s",_"matches regexp",'regexp',	icase=>1, ],
		'filterdesc:si'	=> [ _"contains %s",	_"contains",	'substring',	icase=>1, ],
		'filterdesc:m'	=> [_"matches regexp %s (case sensitive)",'mi'],
		'filterdesc:s'	=> [_"contains %s (case sensitive)", 'si'],
		'filterdesc:-m'	=> _"doesn't match regexp %s (case sensitive)",
		'filterdesc:-mi'=> _"doesn't match regexp %s",
		'filterdesc:-s'	=> _"doesn't contain %s (case sensitive)",
		'filterdesc:-si'=> _"doesn't contain %s",
		'filterdesc:fuzzy'=> [ _"%s fuzzy match with %s",_"fuzzy match", 'fuzzy string', ],
		'filterdesc:-fuzzy'=> _"no %s fuzzy match with %s",
		'smartfilter:=' => '~',
		'smartfilter::' => 'si s',
		'smartfilter:~' => 'mi m',
		'smartfilter:#' => \&Filter::smartstring_fuzzy,
		'filterpat:fuzzy'=> [ round => "%d", unit => '%', min=>20, max=>99, default_value=>65, ],
		default_filter	=> 'si',
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
		init		=> '____=""; __#mainfield#_gid{""}=1; #_iname#[1]=::superlc( #_name#[1]=_("<Unknown>") );',
		get		=> 'do {my $v=#_#; $v!=1 ? #_name#[$v] : "";}',
		gid_to_get	=> '(#GID#!=1 ? #_name#[#GID#] : "")',
		gid_to_sgid	=> '(#GID#!=1 ? #_name#[#GID#] : "")',
		search_gid	=> 'my $gid=__#mainfield#_gid{#VAL#}||0; $gid>1 ? $gid : undef;',
		makefilter	=> '"#field#:~:" . #gid_to_sgid#',
		diff		=> 'do {my $old=#_#; ($old!=1 ? #_name#[$old] : "") ne #VAL# }',
		#save_extra	=> 'my %h; for my $gid (2..$##_name#) { my $v=__#mainfield#_picture[$gid]; next unless defined $v; ::_utf8_on($v); $h{ #_name#[$gid] }=$v; } return artist_pictures',
		listall		=> '2..@#_name#-1',
		load_extra	=> '__#mainfield#_gid{#SGID#} || return;',
		save_extra	=> 'my %h; while ( my ($sgid,$gid)=each %__#mainfield#_gid ) { $h{$sgid}= [#SUBFIELDS#] } delete $h{""}; return \%h;',
		#plugin		=> 'picture',
		'filter:pic'	=> '.!!. __#mainfield#_picture[#_#]',
		'filterdesc:pic:1'=> _"has a picture",
		'filterdesc:-pic:1'=> _"doesn't have a picture",
	},
	album	=>
	{	parent		=> 'fewstring',
		mainfield	=> 'album',
		_empty		=> 'vec(__#mainfield#_empty,#_#,1)',
		unknown		=> '_("<Unknown>")." "',
		init		=> '____=""; __#mainfield#_gid{"\\x00"}=1; __#mainfield#_empty=""; vec(__#mainfield#_empty,1,1)=1; __#mainfield#_sgid[1]="\\x00"; #_iname#[1]=::superlc( #_name#[1]=_("<Unknown>") );',
		findgid		=> 'do{	my $name=#VAL#; my $sgid= $name ."\\x00". ($name eq "" ?	"artist=".#artist->get# :	do {my $a=#album_artist_raw->get#; $a ne "" ?	"album_artist=$a" :	#compilation->get# ?	"compilation=1" : ""}	);
					__#mainfield#_gid{$sgid}||= do {my $n=@#_name#; if ($name eq "") {vec(__#mainfield#_empty,$n,1)=1; $name=#unknown#.#artist->get#; } push @#_name#,$name; push @__#mainfield#_sgid,$sgid; #newval#; $n; };
				    };',
		#possible sgid : album."\x00".	""				if no album name and no artist
		#				"artist=".artist		if no album name
		#				"album_artist"=album_artist	if non-empty album_artist
		#				"compilation=1"			if empty album_artist, compilation flag set
		#				""
		load		=> '#_#= #findgid#;',
		set		=> 'my $oldgid=#_#; my $newgid= #_#= #findgid#; if ($newgid+1==@#_name# && $newgid!=$oldgid) { ___picture[$newgid]= ___picture[$oldgid]; }', #same as load, but if gid changed and is new, use picture from old gid
		#newval		=> 'push @#_iname#, ::superlc( #_name#[-1] );',
		get		=> '(#_empty# ? "" : #_name#[#_#])',
		gid_to_get	=> '(vec(__#mainfield#_empty,#GID#,1) ? "" : #_name#[#GID#])',
		sgid_to_gid	=> 'do {my $s=#VAL#; __#mainfield#_gid{$s}||= do { my $n=@#_name#; if ($s=~s/\x00(\w+)=(.*)$// && $s eq "" && $1 eq "artist") { $s= #unknown#.$2; vec(__#mainfield#_empty,$n,1)=1;} push @#_name#,$s; push @__#mainfield#_sgid,#VAL#; #newval#; $n }}',
		gid_to_sgid	=> '$__#mainfield#_sgid[#GID#]',
		makefilter	=> '"#field#:~:" . #gid_to_sgid#',
		update		=> 'my $albumname=#get#; #set(VAL=$albumname)#;',
		listall		=> 'grep !vec(__#mainfield#_empty,$_,1), 2..@#_name#-1',
		'stats:artistsort'	=> '#HVAL#->{ #album_artist->get_gid# }=undef;  ---- AFTER: #HVAL#=do { my @ar= keys %{#HVAL#}; @ar>1 ? ::superlc(_"Various artists") : __artist_iname[$ar[0]]; }',
		#plugin		=> 'picture',
		load_extra	=> ' __#mainfield#_gid{#SGID#} || return;',
		save_extra	=> 'my %h; while ( my ($sgid,$gid)=each %__#mainfield#_gid ) { $h{$sgid}= [#SUBFIELDS#] } delete $h{""}; return \%h;',
		'filter:pic'	=> '.!!. __#mainfield#_picture[#_#]',
		'filterdesc:pic:1'=> _"has a picture",
		'filterdesc:-pic:1'=> _"doesn't have a picture",
		'filterpat:menustring'=> [ display=> sub { my $s=shift; $s=~s/\x00.*//; $s; } ], # could display $album by $album_artist instead

		#load_extra	=> '___pix[ #sgid_to_gid(VAL=$_[0])# ]=$_[1];',
		#save_extra	=> 'my @res; for my $gid (1..$##_name#) { my $v=___pix[$gid]; next unless length $v; push @res, [#*:gid_to_sgid(GID=$gid)#,$val]; } return \@res;',
	},
	string	=>
	{	parent		=> 'generic',
		default		=> '""',
		check		=> '#VAL#=~tr/\x1D\x00//d; #VAL#=~s/\s+$//;',	#remove trailing spaces and \x1D\x00
		diff		=> '#_# ne #VAL#',
		s_sort		=> '#_#',
		'filter:e'	=> '#_# .eq. "#VAL#"',
		hash		=> '#_#',
		group		=> '#_# ne',
		stats		=> '#HVAL#{#_#}=undef;  ---- AFTER: #HVAL#=[keys %{#HVAL#}];',
	},
	istring => # faster with case/accent insensitive operations, at the price of double memory
	{	parent	=> 'string',
		_iname	=> '___iname[#ID#]',
		set	=> '#_# = #VAL#; #_iname#= ::superlc(#VAL#);',
		si_sort	=> '#_iname#',
		'filter:si'	=> 'index( #_iname#,"#VAL#") .!=. -1',			'filter_prep:si'=> sub { quotemeta ::superlc($_[0])},
		'filter:mi'	=> '#_iname# .=~. m"#VAL#"i',			'filter_prep:mi'=> sub { Filter::QuoteRegEx( ::superlc($_[0]) )},
		'filter:fuzzy'	=> ' .!!. Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",#_iname#)',	'filter_prep:fuzzy'=> sub {my @arg=split / /,$_[0],2; $arg[0],quotemeta ::superlc($arg[1])},
	},
	text =>	#multi-lines string
	{	parent			=> 'string',
		check			=> '#VAL#=~tr/\x00-\x09\x0B\x0C\x0E-\x1F//d; #VAL#=~s/\s+$//;',
		'editwidget:single'	=> sub { GMB::TagEdit::EntryText->new(@_); },
		'editwidget:many'	=> sub { GMB::TagEdit::EntryText->new(@_); },
	},
	filename=>
	{	parent	=> 'string',
		check	=> ';',	#override string's check because not needed and filename may not be utf8
		get	=> '#_#',
		set	=> '#_#=#VAL#; ::_utf8_off(#_#);',
		display	=> '::filename_to_utf8displayname(#get#)',
		hash_to_display => '::filename_to_utf8displayname(#VAL#)', #only used by FolderList:: and MassTag::
		load	=> '#_#=::decode_url(#VAL#)',
		save	=> 'filename_escape(#_#)',
		#'filterpat:string'	=> [ display => \&::filename_to_utf8displayname, ],
	},
	fewpath=>
	{	parent	=> 'filename',
		gid	=> 'vec(____,#ID#,#bits#)',
		bits	=> 32,	#16 bits would limit it to 65k paths
		init	=> '____=""; ___gid{""}=1; ___name[1]="";',
		_	=> '___name[#gid#]',
		get	=> '___name[#gid#]',
		set	=> '#gid# = #path_to_gid#;',
		path_to_gid	=> 'do {my $v=#VAL#; ::_utf8_off($v); ___gid{$v}||= push(@___name, $v) -1; }',
		url_to_gid	=> 'do {my $v=::decode_url(#VAL#);    ___gid{$v}||= push(@___name, $v) -1; }',
		load	=> '#gid# = #url_to_gid#',
		save	=> 'filename_escape(#get#)',
	},
# 	picture =>
#	{	get_picture	=> '__#mainfield#_picture[#GID#] || $::Options{Default_picture_#mainfield#};',
#		get_pixbuf	=> 'my $file= #get_picture#; GMB::Picture::pixbuf($file);',
#		set_picture	=> '::_utf8_off(#VAL#); __#mainfield#_picture[#GID#]= #VAL# eq "" ? undef : #VAL#; ::HasChanged("Picture_#mainfield#",#GID#);',
#		'load_extra:picture'	=> 'if (#VAL# ne "") { __#mainfield#_picture[#GID#]= ::decode_url(#VAL#); }',
#		'save_extra:picture'	=> 'do { my $v=__#mainfield#_picture[#GID#]; defined $v ? ::url_escape($v) : ""; }',
#	},
 	_picture =>
	{	_		=> '__#mainfield#_picture[#GID#]',
		init		=> '@__#mainfield#_picture=(); push @GMB::Picture::ArraysOfFiles, \@__#mainfield#_picture;',
		default		=> '$::Options{Default_picture}{#mainfield#}',
		get_for_gid	=> '#_# || #default#;',
		pixbuf_for_gid	=> 'my $file= #get_for_gid#; GMB::Picture::pixbuf($file);',
		set_for_gid	=> '::_utf8_off(#VAL#); #_#= #VAL# eq "" ? undef : #VAL#; ::HasChanged("Picture_#mainfield#",#GID#);',
		load_extra	=> 'if (#VAL# ne "") { #_#= ::decode_url(#VAL#); }',
		save_extra	=> 'do { my $v=#_#; defined $v ? filename_escape($v) : ""; }',
		get		=> '__#mainfield#_picture[ ##mainfield#->get_gid# ]',
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
		check		=> '#VAL#=~tr/\x00-\x1F//d; #VAL#=~s/\s+$//;',
		default		=> '""',
		get_gid		=> '#_#',
		get		=> '#_name#[#_#]',
		diff		=> '#get# ne #VAL#',
		display 	=> '#_name#[#_#]',
		s_sort		=> '#_name#[#_#]',
		si_sort		=> '#_iname#[#_#]',
		gid_to_get	=> '#_name#[#GID#]',
		's_sort:gid'	=> '#_name#[#GID#]',
		'si_sort:gid'	=> '#_iname#[#GID#]',
		always_first_gid=> 0,
		gid_to_display	=> '#_name#[#GID#]',
		'filter:m'	=> '#_name#[#_#]  .=~. m"#VAL#"',
		'filter:mi'	=> '#_iname#[#_#] .=~. m"#VAL#"i',
		'filter:fuzzy'	=> '.!!. Filter::_fuzzy_match(#VAL1#/100,"#VAL2#",#_iname#[#_#])',	'filter_prep:fuzzy'=> sub {my @arg=split / /,$_[0],2; $arg[0],quotemeta ::superlc($arg[1])},
		'filter:si'	=> 'index( #_iname#[#_#],"#VAL#") .!=. -1',			'filter_prep:si' => sub {quotemeta ::superlc($_[0])},
		'filter:s'	=> 'index( #_name#[#_#], "#VAL#") .!=. -1',
		'filter:e'	=> '#_name#[#_#] .eq. "#VAL#"',
		'filter:~'	=> '#_# .==. #VAL#',				'filter_prep:~' => '#sgid_to_gid(VAL=#PAT#)#',
				'filter_prephash:~' => 'return {map { #sgid_to_gid(VAL=$_)#,undef} keys %{#HREF#}}',
		'filter:h~'	=> '.!!. exists $hash#VAL#->{#_#}',
#		hash		=> '#_name#[#_#]',
		hash		=> '#_#',
		#"hash:gid"	=> '#_#',
		makefilter	=> '"#field#:~:".#_name#[#GID#]',
		group		=> '#_# !=',
		stats		=> '#HVAL#{#_name#[#_#]}=undef;  ---- AFTER: #HVAL#=[keys %{#HVAL#}];',
		'stats:gid'	=> '#HVAL#{#_#}=undef;  ---- AFTER: #HVAL#=[keys %{#HVAL#}];',
		listall		=> '2..@#_name#-1',
		edit_listall	=> 1,
		parent		=> 'generic',
		maxgid		=> '@#_name#-1',
		'filterdesc:~'	=> [ _"is %s", _"is",	'menustring', ],
		'filterdesc:-~'	=> _"isn't %s",
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
		'filter:b'	=> '#_# .>=. #VAL1#  .&&.  #_# .<=. #VAL2#',
		'filter_prep:b'	=> \&filter_prep_numbers_between,
		'filter_prep:>'	=> \&filter_prep_numbers,
		'filter_prep:<'	=> \&filter_prep_numbers,
		'filter_prep:e'	=> \&filter_prep_numbers,
		'group'		=> '#_# !=',
		'stats:range'	=> 'push @{#HVAL#},#_#;  ---- AFTER: #HVAL#=do {my ($m0,$m1)=(sort {$a <=> $b} @{#HVAL#})[0,-1]; $m0==$m1 ? $m0 : "$m0 - $m1"}',
		'stats:average'	=> 'push @{#HVAL#},#_#;  ---- AFTER: #HVAL#=do { my $s=0; $s+=$_ for @{#HVAL#}; $s/@{#HVAL#}; }',
		'stats:sum'	=> '#HVAL# += #_#;',
		stats		=> '#HVAL#{#_#+0}=undef;',
		hash		=> '#_#+0',
		display		=> '(#_# ? sprintf("#displayformat#", #_# ) : "")',	#replace 0 with ""
		gid_to_display	=> '#GID#',
		get_gid		=> '#_#+0',
		makefilter	=> '"#field#:e:#GID#"',
		default		=> '0+0',	#not 0 because it needs to be true :(
		autofill_re	=> '\\d+',
		default_filter	=> '>',
		'filterdesc:e'	=> [ "= %s", "=", 'value', ],
		'filterdesc:>'	=> [ "> %s", ">", 'value', noinv=>1 ],
		'filterdesc:<'	=> [ "< %s", "<", 'value', noinv=>1 ],
		'filterdesc:-<'	=> [ "≥ %s", "≥", 'value', noinv=>1 ],
		'filterdesc:->'	=> [ "≤ %s", "≤", 'value', noinv=>1 ],
		'filterdesc:b'	=> [ _"between %s and %s", _"between", 'value value'],
		'filterdesc:-b'	=> _"not between %s and %s",
		'filterdesc:-e'	=> "≠ %s",
		'filterdesc:h'	=> [ _"in the top %s",	 _"in the top",		'number',],	# "the %s most"  "the most",  ?
		'filterdesc:t'	=> [ _"in the bottom %s",_"in the bottom",	'number',],	# "the %s least" "the least", ?
		'filterdesc:-h'	=> _"not in the top %s",
		'filterdesc:-t'	=> _"not in the bottom %s",
		'filterpat:substring'	=> [icase => 0],
		'filterpat:regexp'	=> [icase => 0],
		'smartfilter:>' => \&Filter::_smartstring_number_moreless,
		'smartfilter:<' => \&Filter::_smartstring_number_moreless,
		'smartfilter:<='=> \&Filter::_smartstring_number_moreless,
		'smartfilter:>='=> \&Filter::_smartstring_number_moreless,
		'smartfilter:=' => \&Filter::_smartstring_number,
		'smartfilter::' => \&Filter::_smartstring_number,
		'smartfilter:~' => 'm',
		'smartfilter:=empty' => 'e:0',
		'smartfilter:#' => undef,
		filter_exclude	=> 'fuzzy', # do not show these filters
		rightalign=>1,	#right-align in SongTree and SongList
	},
	'number.div' =>
	{	group		=> 'int(#_#/#ARG0#) !=',
		hash		=> 'int(#_#/#ARG0#)',		#hash:minute	=> '60*int(#_#/60)',
		#makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".(#GID# * #ARG0#)." ".((#GID#+1) * #ARG0#))',
		makefilter	=> 'Filter->newadd(1, "#field#:-<:".(#GID# * #ARG0#), "#field#:<:".((#GID#+1) * #ARG0#) )', #FIXME decimal separator must be always "."
		gid_to_display	=> '#GID# * #ARG0#',
		get_gid		=> 'int(#_#/#ARG0#)',
	},
	fewnumber =>
	{	_		=> '___value[vec(____,#ID#,#bits#)]',
		parent		=> 'number',
		bits		=> 16,
		init		=> '____=""; ___value[0]=undef;',
		set		=> 'vec(____,#ID#,#bits#) = ___gid{#VAL#}||= do { push(@___value, #VAL#+0)-1; }',
		check		=> '#VAL#= #VAL# =~m/^(-?\d*\.?\d+)$/ ? $1 : 0;',
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
		'editwidget:all'=> sub { my $field=$_[0]; GMB::TagEdit::EntryNumber->new(@_,min=>$Def{$field}{edit_min},max=>$Def{$field}{edit_max},digits=>0,mode=>$Def{$field}{edit_mode}); },
		step		=> 1, #minimum difference between 2 values, used to simplify filters
	},
	# allow overflowing values, stored in a hash, better if 0 isn't a common value as slightly less efficient
	integer_overflow =>
	{	_		=> '(vec(____,#ID#,#bits#) || $___overflow{#ID#} || 0)',
		check		=> '#VAL#= #VAL# =~m/^(\d+)$/ ? $1 : 0;',
		set		=> 'do { if (#VAL# < 2**#bits#) { (vec(____,#ID#,#bits#)= #VAL#) || delete $___overflow{#ID#}; } else { $___overflow{#ID#}= #VAL# ; vec(____,#ID#,#bits#)= 0 } }',
		parent		=> 'integer',
	},
	'integer.div' =>
	{	makefilter	=> '"#field#:b:".(#GID# * #ARG0#)." ".(((#GID#+1) * #ARG0#)-1)',
	},
	float	=>	#make sure the string doesn't have the utf8 flag, else substr won't work
	{	_		=> 'unpack("F",substr(____,#ID#<<3,8))',
		display		=> 'do {my $v=#_#; (#v_is_nan# ? #nan_display# : ::format_number($v,"#displayformat#"))}',	# replace novalue (NaN) with ""
		get		=> 'do {my $v=#_#; (#v_is_nan# ? "" : $v ); }',					#
		diff		=> ($nan==$nan ? 'do {my $new=#VAL#; $new=#nan# unless length $new; $new!=#_# }' :
						 'do {my $new=#VAL#; $new=#nan# unless length $new; my $v=#_#; $new!=$v && ($new==$new || ! #v_is_nan#) }'),
		displayformat	=> '%.2f',
		init		=> '____=" "x8;', #needs init for ID==0
		parent		=> 'number',
		nan		=> '$Songs::nan',
		v_is_nan	=> ($nan==$nan ? '($v==#nan#)' : '($v!=$v)'),	#on some system $nan!=$nan, on some not. In case nan==0, 0 will be treated as novalue, could treat novalue as 0 instead
		novalue		=> '#nan#',	#use NaN as novalue
		nan_display	=> '""',
		default		=> '#novalue#',
		set		=> 'substr(____,#ID#<<3,8)=pack("F",(length(#VAL#) ? #VAL# : #novalue#))',
		check		=> '#VAL#= #VAL# =~m/^(-?\d*\.?\d+(?:e[-+]\d+)?)$/i ? $1 : #novalue#;',
		# FIXME make sure that locale is set to C (=> '.' as decimal separator) when needed
		'editwidget:all'=> sub { my $field=$_[0]; GMB::TagEdit::EntryNumber->new(@_,min=>$Def{$field}{edit_min},max=>$Def{$field}{edit_max},signed=>1,digits=>2,mode=>'allow_empty'); },
		autofill_re	=> '-?\\d*\\.?\\d+',
		'filterpat:value' => [ digits => 2, signed=>1, round => "%.2f", ],
		n_sort		=> 'do {my $v=#_#; #v_is_nan# ? "-inf" : $v}',
		'filter:defined'	=> 'do {my $v=#_#; .!. (#v_is_nan#)}',
		'filterdesc:defined:1'	=> _"is defined",
		'filterdesc:-defined:1'	=> _"is not defined",
		'smartfilter:=empty' => '-defined:1',
		'stats:same'=> 'do {my $v1=#HVAL#; my $v2=#_#; if (defined $v1) { #HVAL#=#nan# if $v1!=$v2; } else { #HVAL#= $v2 } }',	#hval=nan if $v1!=$v2 works both if nan==nan or nan!=nan : set hval to nan if either one of them is nan or if they are not equal. That way no need to use #v_is_nan#, which would be complicated as it uses $v
	},
	'float.range'=>
	{	get_gid		=> 'do {my $v=#_#; #v_is_nan# ? #nan_gid# : int($v/#range_step#) ;}',
		nan_gid		=> '-2**31+1', #gid in FilterList are Long, 2**31-1 is GID_ALL
		always_first_gid=> -2**31+1,
		range_step	=> '1', #default step
		gid_to_display	=> '( #GID#==#nan_gid# ? _"not defined" : do {my $v= #GID# * #range_step#; "$v .. ".($v+#range_step#)})',
		gid_to_get	=> '( #GID#==#nan_gid# ? #nan# : #GID# * #range_step#)',
		hash		=> '#get_gid#',
		makefilter	=> '#GID#==#nan_gid# ? "#field#:-defined:1" : do { my $v= #GID# * #range_step#; Filter->newadd(1, "#field#:-<:".$v, "#field#:<:".($v + #range_step#)); }', #FIXME decimal separator must be always "."
		#'n_sort:gid'	=> '( do{my $n=#GID#==#nan_gid# ? "-inf" : #GID# * #range_step#;warn "#GID# => $n";$n })',
		#'n_sort:gid'	=> '( #GID#==#nan_gid# ? "-inf" : #GID# * #range_step# )',
		'n_sort:gid'	=> '#GID#', #  #nan_gid# is already the most negative number, no need to replace it with -inf
	},
	integerfloat =>		#floats that can be stored as integers
	{	parent		=> 'float',
		_		=> 'vec(____,#ID#,#bits#)/#div#',
		div		=> 100, #default: 1.23 => stored as 123, with 16bits can store values from 0 to 655.35
		bits		=> 16,
		check		=> '#VAL#= #VAL# =~m/^(-?\d*\.?\d+(?:e[-+]\d+)?)$/i && $1<2**#bits#/#div# ? $1 : 0;', # set to 0 if overflow
		set		=> 'vec(____,#ID#,#bits#)= #div# * (#VAL# || 0)',
		get_gid		=> 'vec(____,#ID#,#bits#)',
		hash		=> '#get_gid#',
		#zero_display	=> '::format_number(0,"#displayformat#")',
		zero_display	=> '""',
		display		=> 'do {my $v=#_#; $v == 0 ? #zero_display# : ::format_number($v,"#displayformat#") }',
		gid_to_display	=> 'do {my $v=#GID#; $v == 0 ? #zero_display# : ::format_number($v/#div#,"#displayformat#") }',
		makefilter	=> '"#field#:e:".(#GID#/#div#)',
	},
	'length' =>
	{	display	=> 'sprintf("%d:%02d", #_#/60, #_#%60)',
		parent	=> 'integer',
		'filter_prep:e'	=> \&::ConvertTimeLength,
		'filter_prep:>'	=> \&::ConvertTimeLength,
		'filter_prep:<'	=> \&::ConvertTimeLength,
		'filter_prep:b'	=> sub {sort {$a <=> $b} map ::ConvertTimeLength($_), split / /,$_[0],2},
	},
	'length.div' => { gid_to_display	=> 'my $v=#GID# * #ARG0#; sprintf("%d:%02d", $v/60, $v%60);', },
	size	=>
	{	display	=> '( ::format_number( #_#/'. ::MB() .',"%.1f").q( '. _("MB") .') )',
		'filter_prep:e'	=> \&::ConvertSize,
		'filter_prep:>'	=> \&::ConvertSize,
		'filter_prep:<'	=> \&::ConvertSize,
		'filter_prep:b'	=> sub {sort {$a <=> $b} map ::ConvertSize($_), split / /,$_[0],2},
		parent	=> 'integer_overflow',
		'filterpat:value' => [ unit=> \%::SIZEUNITS, default_unit=> 'm', default_value=>1, ],
	},
	'size.div'   => { gid_to_display	=> '( ::format_number( #GID# * #ARG0#/'. ::MB() .',"%d").q( '. _"MB" .') )', },
	rating	=>
	{	parent	=> 'integer',
		bits	=> 8,
		_	=> 'vec(____,#ID#,#bits#)',
		_default=> 'vec(___default_,#ID#,#bits#)',
		init	=> '____ = ___default_ = "";',
		default	=> '""',
		diff	=> '(#VAL# eq "" ? 255 : #VAL#)!=#_#',
		get	=> '(#_#==255 ? "" : #_#)',
		display	=> '(#_#==255 ? "" : #_#)',
		'stats:range'	=> 'push @{#HVAL#},#_default#;  ---- AFTER: #HVAL#=do {my ($m0,$m1)=(sort {$a <=> $b} @{#HVAL#})[0,-1]; $m0==$m1 ? $m0 : "$m0 - $m1"}',
		'stats:average'	=> 'push @{#HVAL#},#_default#;  ---- AFTER: #HVAL#=do { my $s=0; $s+=$_ for @{#HVAL#}; $s/@{#HVAL#}; }',
		check	=> '#VAL#= #VAL# =~m/^\d+$/ ? (#VAL#>100 ? 100 : #VAL#) : "";',
		set	=> '{ my $v=#VAL#; #_default#= ($v eq "" ? $::Options{DefaultRating} : $v); #_# = ($v eq "" ? 255 : $v); }',
		makefilter	=> '"#field#:~:#GID#"',
		'filter:~'	=> '#_# .==. #VAL#',
		'filter:e'	=> '#_default# .==. #VAL#',
		'filter:>'	=> '#_default# .>. #VAL#',
		'filter:<'	=> '#_default# .<. #VAL#',
		'filter:b'	=> '#_default# .>=. #VAL1#  .&&. #_default# .<=. #VAL2#',
		'filterdesc:~'	=> [_"set to %s", _"set to", 'value'],
		'filterdesc:-~'	=> _"not set to %s",,
		'filterdesc:~:255'=> 'set to default',
		'filterdesc:-~:255'=>'not set to default',
		'smartfilter:=empty' => '~:255',
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
		'filter_prep:>ago'	=> \&::ConvertTime,
		'filter_prep:<ago'	=> \&::ConvertTime,
		'filter_prep:bago'	=> sub {sort {$a <=> $b} map ::ConvertTime($_), split / /,$_[0],2},
		'filter:>ago'	=> '#_# .<. #VAL#',
		'filter:<ago'	=> '#_# .>. #VAL#',
		'filter:bago'	=> '#_# .>=. #VAL1#  .&&.  #_# .<=. #VAL2#',
		#'filterdesc:e'		=> [_"is equal to %s", _"is equal to", 'date' ],
		filter_exclude => 'e', # do not show these filters
		'filterdesc:>ago'	=> [_"more than %s ago",	_"more than",	'ago', ],
		'filterdesc:<ago'	=> [_"less than %s ago",	_"less than",	'ago', ],
		'filterdesc:>'		=> [_"after %s",		_"after",	'date', ],
		'filterdesc:<'		=> [_"before %s",		_"before",	'date', ],
		'filterdesc:b'		=> [_"between %s and %s",	_"between (absolute dates)", 'date date'],
		'filterdesc:bago'	=> [_"between %s ago and %s ago", _"between (relative dates)", 'ago ago'],
		'filterdesc:->ago'	=> _"less than %s ago",
		'filterdesc:-<ago'	=> _"more than %s ago",
		'filterdesc:->'		=> _"before %s",
		'filterdesc:-<'		=> _"after %s",
		'filterdesc:-b'		=> _"not between %s and %s",
		'filterdesc:-bago'	=> _"not between %s ago and %s ago",
		'filterdesc:h'		=> [ _"the %s most recent",	_"the most recent",	'number'],	#"the %s latest" "the latest" ?
		'filterdesc:t'		=> [ _"the %s least recent",	_"the least recent",	'number'],	#"the %s earliest" "the earliest" ?
		'filterdesc:-h'		=> _"not the %s most recent",
		'filterdesc:-t'		=> _"not the %s least recent",
		'filterpat:ago'		=> [ unit=> \%::DATEUNITS, default_unit=> 'd', ],
		'filterpat:date'	=> [ display=> sub { my $var=shift; $var= ::strftime_utf8('%c',localtime $var) if $var=~m/^\d+$/; $var; }, ],
		default_filter		=> '<ago',
		'smartfilter:>' => \&Filter::_smartstring_date_moreless,
		'smartfilter:<' => \&Filter::_smartstring_date_moreless,
		'smartfilter:<='=> \&Filter::_smartstring_date_moreless,
		'smartfilter:>='=> \&Filter::_smartstring_date_moreless,
		'smartfilter:=' => \&Filter::_smartstring_date,
		'smartfilter::' => \&Filter::_smartstring_date,
		'smartfilter:~' => 'm',
		'smartfilter:=empty' => 'e:0',

		 #for date.year, date.month, date.day :
		always_first_gid=> 0,
		group	=> '#mktime# !=',
		get_gid	=> '#_# ? #mktime# : 0',
		hash	=> '(#_# ? #mktime# : 0)',	#or use post-hash modification for 0 case
		subtypes_menu=> \%timespan_menu,
		grouptitle=> 'my $gid=#get_gid#; #gid_to_display(GID=$gid)#;',
		rightalign=>0,
	},
	'date.year' =>
	{	mktime		=> '::mktime(0,0,0,1,0,(localtime(#_#))[5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".(::mktime(0,0,0,1,0,(localtime(#GID#))[5]+1)-1))',
	},
	'date.month' =>
	{	mktime		=> '::mktime(0,0,0,1,(localtime(#_#))[4,5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%b %Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".do{my ($m,$y)= (localtime(#GID#))[4,5]; ::mktime(0,0,0,1,$m+1,$y)-1})',
	},
	'date.day' =>
	{	mktime		=> '::mktime(0,0,0,(localtime(#_#))[3,4,5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%x",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "e:0" : "b:".#GID#." ".do{my ($d,$m,$y)= (localtime(#GID#))[3,4,5]; ::mktime(0,0,0,$d+1,$m,$y)-1})',
	},
	dates_compact	=>	# ___index_ : binary string containing position (in unit of 1 date => 4 bytes) of the first date in ___values_ for each song
				# ___nb_ : binary string containing number of dates for each song
				# ___values_ : binary string containing the actual dates
				# ___free_ : array containing free positions in ___values_ for each size
	{	parent		=> 'dates',
		_		=> 'substr(___values_, #index# * #bytes#, #nb# * #bytes#)',
		index		=> 'vec(___index_,#ID#,32)',	# => max 2**32 dates
		nb		=> 'vec(___nb_,#ID#,16)',	# => max 2**16 dates per song, could maybe use 8 bits instead
		get_list	=> 'unpack("#packformat#*", #_#)',
		init		=> '___index_= ___values_= ___nb_ = "";',
		set		=> '{	my $v=#VAL#;
					my @list= !$v ? () : sort { $a <=> $b } (ref $v ? @$v : split /\D+/,$v);
					if (my $nb=#nb#) { ___free_[$nb].= pack "N",#index#; } # add previous space to list of free spaces
					if (@list)
					{	my $string= pack "#packformat#*", @list;
						my $nb= #nb#= scalar @list;
						if (___free_[$nb])	# re-use old space
						{	#index#= unpack "N", substr(___free_[$nb],-4,4,"");
							#_#= $string;
						}
						else			# use new space
						{	#index#= length(___values_)/#bytes#;
							___values_ .= $string;
						}
					}
					else { #index#=0; #nb#=0 }
				   }',
		'filter:ecount'	=> '#VAL# .==. #nb#',
		'stats:count'	=> '#HVAL# += #nb#;',
	},
	dates	=>
	{	parent		=> 'generic', # for m mi s si filters
		_		=> '____[#ID#]',
		default		=> 'undef',
		bits		=> 32,	packformat=> 'L', # replace with 64 and Q for 64bits dates
		bytes		=> '(#bits#/8)',
		check		=> ';',
		get_list	=> 'unpack("#packformat#*",#_#||"")',
		display		=> 'join("\n",map Songs::DateString($_), reverse #get_list#)',
		gid_to_get	=> '#GID#',
		gid_to_display	=> 'Songs::DateString(#GID#)',
		#n_sort		=> 'unpack("#packformat#*",substr(#_#||"",-#bytes#))', #sort by last date, not used
		'n_sort:gid'	=> '#GID#',
		get		=> 'join(" ",#get_list#)',
		set		=> '{	my $v=#VAL#;
					my @list= !$v ? () : sort { $a <=> $b } (ref $v ? @$v : split /\D+/,$v);
					#_#= !@list ? undef : pack("#packformat#*", @list);
				   }', #use undef instead of '' if no dates to save some memory
		diff		=> 'do {my $old=#_#||""; my $new=#VAL#; $new= pack "#packformat#*",sort { $a <=> $b } (ref $new ? @$new : split /\D+/,$new); $old ne $new; }',
		check_multi	=> 'for my $lref (@{#VAL#}) {@$lref=grep m/^\d+$/, @$lref}',
		set_multi	=> 'do {my %h; $h{$_}=0 for #get_list#; my ($toadd,$torm,$toggle)=@{#VAL#}; $h{$_}= (exists $h{$_} ? -1 : 1) for @$toggle; $h{$_}++ for @$toadd; $h{$_}-- for @$torm; (scalar grep $h{$_}!=0, keys %h) ? [grep $h{$_}>=0, keys %h] : undef; }',
		'filter:ecount'	=> '#VAL# .==. length(#_#)/#bytes#',
		'stats:count'	=> '#HVAL# += length(#_#)/#bytes#;',
		#example of use : Songs::BuildHash('artist',$::Library,undef,'playhistory:countrange:DATE1-DATE2'));  where DATE1 and DATE2 are secongs since epoch and DATE1<DATE2
		'stats:countrange'	=> 'INIT: my ($$date1,$$date2)= #ARG#=~m/(\d+)/g; ---- #HVAL# ++ for grep $$date1<$_ && $$date2>$_, #get_list#;', #count plays between 2 dates (in seconds since epoch)
		'stats:countafter'	=> '#HVAL# ++ for grep #ARG#<$_, #get_list#;', #count plays after date (in seconds since epoch)
		'stats:countbefore'	=> '#HVAL# ++ for grep #ARG#>$_, #get_list#;', #count plays before date (in seconds since epoch)
		stats		=> 'do {#HVAL#{$_}=undef for #get_list#;};',
		'filter:e'	=> '.!!. do{ grep($_ == #VAL#, #get_list#) }',
		'filter:>'	=> '.!!. do{ grep($_ > #VAL#, #get_list#) }',
		'filter:<'	=> '.!!. do{ grep($_ < #VAL#, #get_list#) }',
		'filter:b'	=> '.!!. do{ grep($_ >= #VAL1# && $_ <= #VAL2#, #get_list#) }',
		'filter_prep:>'	=> \&filter_prep_numbers,
		'filter_prep:<'	=> \&filter_prep_numbers,
		'filter_prep:e'	=> \&filter_prep_numbers,
		'filter_prep:b'	=> \&filter_prep_numbers_between,
		'filter_prep:>ago'	=> \&::ConvertTime,
		'filter_prep:<ago'	=> \&::ConvertTime,
		'filter_prep:bago'	=> sub {sort {$a <=> $b} map ::ConvertTime($_), split / /,$_[0],2},
		'filter:>ago'	=> '.!!. do{ grep($_ < #VAL#, #get_list#) }',
		'filter:<ago'	=> '.!!. do{ grep($_ > #VAL#, #get_list#) }',
		'filter:bago'	=> '.!!. do{ grep($_ >= #VAL1# && $_ <= #VAL2#, #get_list#) }',
		#copy of filterdesc:* smartfilter:* from date type
		'filterdesc:>ago'	=> [_"more than %s ago",	_"more than",	'ago', ],
		'filterdesc:<ago'	=> [_"less than %s ago",	_"less than",	'ago', ],
		'filterdesc:>'		=> [_"after %s",		_"after",	'date', ],
		'filterdesc:<'		=> [_"before %s",		_"before",	'date', ],
		'filterdesc:b'		=> [_"between %s and %s",	_"between (absolute dates)", 'date date'],
		'filterdesc:bago'	=> [_"between %s ago and %s ago", _"between (relative dates)", 'ago ago'],
		'filterdesc:->ago'	=> _"not more than %s ago",
		'filterdesc:-<ago'	=> _"not less than %s ago",
		'filterdesc:->'		=> _"not after %s",
		'filterdesc:-<'		=> _"not before %s",
		'filterdesc:-b'		=> _"not between %s and %s",
		'filterdesc:-bago'	=> _"not between %s ago and %s ago",
		'filterdesc:h'		=> [ _"the %s most recent",	_"the most recent",	'number'],	#"the %s latest" "the latest" ?
		'filterdesc:t'		=> [ _"the %s least recent",	_"the least recent",	'number'],	#"the %s earliest" "the earliest" ?
		'filterdesc:-h'		=> _"not the %s most recent",
		'filterdesc:-t'		=> _"not the %s least recent",
		'filterpat:ago'		=> [ unit=> \%::DATEUNITS, default_unit=> 'd', ],
		'filterpat:date'	=> [ display=> sub { my $var=shift; $var= ::strftime_utf8('%c',localtime $var) if $var=~m/^\d+$/; $var; }, ],
		default_filter		=> '<ago',
		'smartfilter:>' => \&Filter::_smartstring_date_moreless,
		'smartfilter:<' => \&Filter::_smartstring_date_moreless,
		'smartfilter:<='=> \&Filter::_smartstring_date_moreless,
		'smartfilter:>='=> \&Filter::_smartstring_date_moreless,
		'smartfilter:=' => \&Filter::_smartstring_date,
		'smartfilter::' => \&Filter::_smartstring_date,
		'smartfilter:=empty' => 'ecount:0',
		'smartfilter:#' => undef,
		filter_exclude	=> 'fuzzy', # do not show these filters

		#get_gid		=> '[#get_list#]',
		#hashm			=> '#get_list#',
		#mktime			=> '$_',
		 #for dates.year, dates.month, dates.day :
		always_first_gid=> 0,
		get_gid	=> '[#_# ? (map #mktime#,#get_list#) : 0]',
		hashm	=> '(#_# ? (map #mktime#,#get_list#) : 0)',	#or use post-hash modification for 0 case
		subtypes_menu=> \%timespan_menu,

	},
	#identical to date.*, except #_# is replaced by $_ in mktime, and "e" filter by "ecount"
	'dates.year' =>
	{	mktime		=> '::mktime(0,0,0,1,0,(localtime($_))[5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "ecount:0" : "b:".#GID#." ".(::mktime(0,0,0,1,0,(localtime(#GID#))[5]+1)-1))',
	},
	'dates.month' =>
	{	mktime		=> '::mktime(0,0,0,1,(localtime($_))[4,5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%b %Y",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "ecount:0" : "b:".#GID#." ".do{my ($m,$y)= (localtime(#GID#))[4,5]; ::mktime(0,0,0,1,$m+1,$y)-1})',
	},
	'dates.day' =>
	{	mktime		=> '::mktime(0,0,0,(localtime($_))[3,4,5])',
		gid_to_display	=> '(#GID# ? ::strftime_utf8("%x",localtime(#GID#)) : _"never")',
		makefilter	=> '"#field#:".(!#GID# ? "ecount:0" : "b:".#GID#." ".do{my ($d,$m,$y)= (localtime(#GID#))[3,4,5]; ::mktime(0,0,0,$d+1,$m,$y)-1})',
	},
	boolean	=>
	{	parent	=> 'integer',	bits => 1,
		check	=> '#VAL#= #VAL# ? 1 : 0;',
		display	=> "(#_# ? #yes# : #no#)",	yes => '_("Yes")',	no => 'q()',
		'editwidget:all'=> sub { my $field=$_[0]; GMB::TagEdit::EntryBoolean->new(@_); },
		'filterdesc:e:0'	=> [_"is false",_"is false",'',noinv=>1],
		'filterdesc:e:1'	=> [_"is true", _"is true", '',noinv=>1],
		'filterdesc:-e:0'	=> _"is true",
		'filterdesc:-e:1'	=> _"is false",
		filter_exclude => 'ALL',	#do not show filters inherited from parents
		default_filter => 'e:1',
		'smartfilter:=empty' => 'e:0',
		rightalign=>0,
	},
	shuffle=>
	{	n_sort		=> 'Songs::update_shuffle($Songs::LastID) ---- vec($Songs::SHUFFLE,#ID#,32)',
	},
	gidshuffle=>
	{	n_sort		=> 'Songs::update_shuffle(##mainfield#->maxgid#) ----  vec($Songs::SHUFFLE,##mainfield#->get_gid#,32)',
	},
	writeonly=>
	{	diff=>'1',
		set => '',
		check=>'',
	},
);
%Def=		#flags : Read Write Editable Sortable Column caseInsensitive sAve List Gettable Properties
(file	=>
 {	name	=> _"Filename",	width => 400, flags => 'fgascp_',	type => 'filename',
	'stats:filetoid' => '#HVAL#{ #file->get# }=#ID#',
	category=>'file',
	alias	=> 'filename',
 },
 id	=>
 {	type=> 'integer',
	_ => '#ID#',
	'stats:list'	=> 'push @{#HVAL#}, #ID#',
	'stats:uniq'	=> '#HVAL#=undef', #doesn't really belong here, but simpler this way
	'stats:count'	=> '#HVAL#++',
 },
 path	=>
 {	name	=> _"Folder",	width => 200, flags => 'fgascp_',	type => 'fewpath',
	'filter:i'	=> '#_# .=~. m/^#VAL#(?:$::QSLASH|$)/o',
	'filter_prep:i'	=> sub { quotemeta ::decode_url($_[0]); },
	'filterdesc:i'	=> [_"is in %s", _"is in", 'filename'],
	'filterdesc:-i'	=> _"isn't in %s",
	'filterpat:filename'	=> [ display => sub { ::filename_to_utf8displayname(::decode_url($_[0])); }, ],
	can_group=>1,
	category=>'file',
	alias	=> 'folder',
 },
 modif	=>
 {	name	=> _"Modification",	width => 160,	flags => 'fgarscp_',	type => 'date',
	FilterList => {type=>'year',},
	can_group=>1,
	category=>'file',
	alias	=> 'modified',
 },
 size	=>
 {	name => _"Size",	width => 80,	flags => 'fgarscp_',		#32bits => 4G max
	type => 'size',
	FilterList => {type=>'div.'.::MB(),},
	category=>'file',
 },
 title	=>
 {	name	=> _"Title",	width	=> 270,		flags	=> 'fgarwescpi',	type => 'istring',
	id3v1	=> 0,		id3v2	=> 'TIT2',	vorbis	=> 'title',	ape	=> 'Title',	lyrics3v2=> 'ETT', ilst => "\xA9nam",
	'filter:~' => '#_iname# .=~. m"(?:^|/) *#VAL# *(?:[/\(\[]|$)"',		'filter_prep:~'=> \&Filter::SmartTitleRegEx,
	'filter_simplify:~' => \&Filter::SmartTitleSimplify,
	'filterdesc:~'	=> [_"is smart equal to %s", _"is smart equal", 'substring'],
	'filterdesc:-~'	=> _"Isn't smart equal to %s",
	makefilter_fromID => '"title:~:" . #get#',
	edit_order=> 10, letter => 't',
	category=>'basic',
	alias_trans=> ::_p('Field_aliases',"title"),  #TRANSLATION: comma-separated list of field aliases for title, these are in addition to english aliases
	articles=>1,
 },
 artist =>
 {	name => _"Artist",	width => 200,	flags => 'fgarwescpi',
	type => 'artist',
	id3v1	=> 1,		id3v2	=> 'TPE1',	vorbis	=> 'artist',	ape	=> 'Artist',	lyrics3v2=> 'EAR', ilst => "\xA9ART",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	all_count=> _"All artists",
	apic_id	=> 8,
	picture_field => 'artist_picture',
	edit_order=> 20,	edit_many=>1,	letter => 'a',
	can_group=>1,
	#names => '::__("%d artist","%d artists",#count#);'
	category=>'basic',
	alias=> 'by',
	alias_trans=> ::_p('Field_aliases',"artist,by"),  #TRANSLATION: comma-separated list of field aliases for artist, these are in addition to english aliases
	articles=>1,
 },
 first_artist =>
 {	flags => 'fig',
	type	=> 'artist_first',	depend	=> 'artists',	name => _"Main artist",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	sortgroup=>'artist',
	can_group=>1,
	articles=>1,
 },
 artists =>
 {	flags => 'gfil',	type	=> 'artists',	depend	=> 'artist title',	name => _"Artists",
	all_count=> _"All artists",
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	articles=>1,
 },
 album =>
 {	name => _"Album",	width => 200,	flags => 'fgarwescpi',	type => 'album',
	id3v1	=> 2,		id3v2	=> 'TALB',	vorbis	=> 'album',	ape	=> 'Album',	lyrics3v2=> 'EAL', ilst => "\xA9alb",
	depend	=> 'artist album_artist_raw compilation', #because albums with no names get the name : <Unknown> (artist)
	all_count=> _"All albums",
	FilterList => {search=>1,drag=>::DRAG_ALBUM},
	apic_id	=> 3,
	picture_field => 'album_picture',
	names => '::__("%d album","%d albums",#count#);',
	edit_order=> 30,	edit_many=>1,	letter => 'l',
	can_group=>1,
	category=>'basic',
	alias=> 'on',
	alias_trans=> ::_p('Field_aliases',"album,on"),  #TRANSLATION: comma-separated list of field aliases for album, these are in addition to english aliases
	articles=>1,
 },
# genre_picture =>
# {	name		=> "Genre picture",
#	flags		=> 'g',
#	depend		=> 'genre',
#	property_of	=> 'genre',
#	mainfield	=> 'genre',
#	type		=> '_picture',
# },
 album_picture =>
 {	name		=> _"Album picture",
	flags		=> 'g',
	depend		=> 'album',
	property_of	=> 'album',
	mainfield	=> 'album',
	type		=> '_picture',
	letter		=> 'c',
 },
 artist_picture =>
 {	name		=> _"Artist picture",
	flags		=> 'g',
	depend		=> 'artist',
	property_of	=> 'artist',
	mainfield	=> 'artist',
	type		=> '_picture',
 },
 album_artist_raw =>
 {	name => _"Album artist",width => 200,	flags => 'fgarwescpi',	type => 'artist',
	id3v2	=> 'TPE2',	vorbis	=> 'albumartist|album_artist',	ape	=> 'Album Artist|Album_artist',  ilst => "aART",
	#FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	edit_order=> 35,	edit_many=>1,
	#can_group=>1,
	category=>'basic',
 },
 album_artist =>
 {	name => _"Album artist or artist",width => 200,	flags => 'fgcsi',	type => 'artist',
	FilterList => {search=>1,drag=>::DRAG_ARTIST},
	picture_field => 'artist_picture',
	_ => 'do {my $n=vec(__album_artist_raw__,#ID#,#bits#); $n==1 ? vec(__artist__,#ID#,#bits#) : $n}',
	can_group=>1,
	letter => 'A',
	depend	=> 'album_artist_raw artist album',
	category=>'basic',
	articles=>1,
 },
 album_has_picture=>
 {	name => _"Album has picture", width => 20, flags => 'fgcs',	type => 'boolean',
	_ => '!!(__#mainfield#_picture[ ##mainfield#->get_gid# ])', mainfield=> 'album',
 },
 artist_has_picture=>
 {	name => _"Artist has picture", width => 20, flags => 'fgcs',	type => 'boolean',
	_ => '!!(__#mainfield#_picture[ ##mainfield#->get_gid# ])', mainfield=> 'artist',
 },
 has_picture =>
 {	name	=> _"Embedded picture", width => 20, flags => 'fgarscp',	type => 'boolean',
	id3v2 => 'APIC',	vorbis => 'METADATA_BLOCK_PICTURE',	'ilst' => 'covr',
	category=>'extra',
	disable=>1,	options => 'disable',
 },
 has_lyrics =>
 {	name	=> _"Embedded lyrics", width => 20, flags => 'fgarscp',	type => 'boolean',
	id3v2 => 'TXXX;FMPS_Lyrics;%v | USLT;;;%v',	vorbis => 'FMPS_LYRICS|lyrics',	ape => 'FMPS_LYRICS|Lyrics',
	'ilst' => "----FMPS_Lyrics|\xA9lyr",	lyrics3v2 => 'LYR',
	category=>'extra',
	disable=>1,	options => 'disable',
 },
 compilation =>
 {	name	=> _"Compilation", width => 20, flags => 'fgarwescp',	type => 'boolean',
	id3v2 => 'TCMP',	vorbis	=> 'compilation',	ape => 'Compilation',	ilst => 'cpil',
	edit_many=>1,
	category=>'basic',
 },
 grouping =>
 {	name	=> _"Grouping",	width => 100,	flags => 'fgarwescpi',	type => 'fewstring',
	FilterList => {search=>1},
	can_group=>1,
	edit_order=> 55,	edit_many=>1,
	id3v2 => 'TIT1',	vorbis	=> 'grouping',	ape	=> 'Grouping', ilst => "\xA9grp",
	category=>'extra',
	articles=>1,
 },
 year =>
 {	name	=> _"Year",	width => 40,	flags => 'fgarwescp',	type => 'integer',	bits => 16,
	edit_max=>3000,	edit_mode=> 'year',
	check	=> '#VAL#= #VAL# =~m/(\d\d\d\d)/ ? $1 : 0;',
	id3v1	=> 3,		id3v2 => 'TDRC|TYER', 'id3v2.3'=> 'TYER|TDRC',	'id3v2.4'=> 'TDRC|TYER',	vorbis	=> 'date|year',	ape	=> 'Record Date|Year', ilst => "\xA9day",
	prewrite=> sub { $_[0] ? $_[0] : undef }, #remove tag if 0
	gid_to_display	=> '#GID# ? #GID# : _"None"',
	'stats:range'	=> '#HVAL#{#_#}=undef;  ---- AFTER: delete #HVAL#{0}; #HVAL#=do {my ($m0,$m1)=(sort {$a <=> $b} keys %{#HVAL#})[0,-1]; !defined $m0 ? "" : $m0==$m1 ? $m0 : "$m0 - $m1"}',
	editwidth => 6,
	edit_order=> 50,	edit_many=>1,	letter => 'y',
	can_group=>1,
	FilterList => {},
	autofill_re	=> '[12]\\d{3}',
	category=>'basic',
 },
 track =>
 {	name	=> _"Track",	width => 40,	flags => 'fgarwescp',
	id3v1	=> 5,		id3v2	=> 'TRCK',	vorbis	=> 'tracknumber',	ape	=> 'Track', ilst => "trkn",
	prewrite=> sub { $_[0] ? $_[0] : undef }, #remove tag if 0
	type => 'integer',	displayformat => '%02d', bits => 16,
	edit_max => 65535, 	edit_mode=> 'nozero',
	edit_order=> 20,	editwidth => 4,		letter => 'n',
	category=>'basic',
 },
 disc =>
 {	name	=> _"Disc",	width => 40,	flags => 'fgarwescp',	type => 'integer',	bits => 8,
	edit_max => 255,	edit_mode=> 'nozero',
				id3v2	=> 'TPOS',	vorbis	=> 'discnumber',	ape	=> 'discnumber', ilst => "disk|disc",
	prewrite=> sub { $_[0] ? $_[0] : undef }, #remove tag if 0
	editwidth => 4,
	edit_order=> 40,	edit_many=>1,	letter => 'd',
	can_group=>1,
	category=>'basic',
	alias	=> 'disk',
 },
 discname =>
 {	name	=> _"Disc name",	width	=> 100,		flags => 'fgarwescpi',	type => 'fewstring',
	id3v2	=> 'TSST',	vorbis	=> 'discsubtitle',	ape => 'DiscSubtitle',	ilst=> '----DISCSUBTITLE',
	edit_many=>1,
	disable=>1,	options => 'disable',
	category=>'extra',
	alias	=> 'diskname',
 },
 genre	=>
 {	name		=> _"Genres",	width => 180,	flags => 'fgarwescpil',
	 #is_set	=> '(__GENRE__=~m/(?:^|\x00)__QVAL__(?:$|\x00)/)? 1 : 0', #for random mode
	id3v1	=> 6,		id3v2	=> 'TCON',	vorbis	=> 'genre',	ape	=> 'Genre', ilst => "\xA9gen & ----genre",
	read_split	=> qr/\s*;\s*/,
	type		=> 'flags',		#default_persistent_values => \@Tag::MP3::Genres,
	none		=> quotemeta _"No genre",
	all_count	=> _"All genres",
	FilterList	=> {search=>1},
	edit_order=> 70,	edit_many=>1,	letter => 'g',
	category=>'basic',
	editsubmenu=>0,
	options	=> 'editsubmenu samemenu',
#	picture_field => 'genre_picture',
 },
 label	=>
 {	name		=> _"Labels",	width => 180,	flags => 'fgaescpil',
	 #is_set	=> '(__LABEL__=~m/(?:^|\x00)__QVAL__(?:$|\x00)/)? 1 : 0', #for random mode
	type		=> 'flags',
	iconprefix	=> 'label-',
	icon		=> sub { $Def{label}{iconprefix}.$_[0]; }, #FIXME use icon_for_gid #FIXME 2TO3 return '' if no icon file exist
	icon_for_gid	=> '"#iconprefix#".#gid_to_get#',
	all_count	=> _"All labels",
	edit_string	=> _"Edit labels",
	none		=> quotemeta _"No label",
	FilterList	=> {search=>1,icon=>1},
	icon_edit_string=> _"Choose icon for label {name}",
	edit_order=> 80,	edit_many=>1,	letter => 'L',
	category=>'extra',
	editsubmenu=>1,
	options		=> 'persistent_values editsubmenu samemenu',
	default_persistent_values => [_("favorite"),_("bootleg"),_("broken"),_("bonus tracks"),_("interview"),],
 },
 mood	=>
 {	name		=> _"Moods",	width => 180,	flags => 'fgarwescpil',
	id3v2	=> 'TMOO',	vorbis	=> 'MOOD',	ape	=> 'Mood', ilst => "----MOOD",
	read_split	=> qr/\s*;\s*/,
	type		=> 'flags',
	none		=> quotemeta _"No moods",
	all_count	=> _"All moods",
	FilterList	=> {search=>1},
	edit_order=> 71,	edit_many=>1,
	disable=>1,	options => 'disable editsubmenu samemenu',
	editsubmenu=>0,
	category=>'extra',
 },
 style	=>
 {	name	=> _"Styles",	width => 180,	flags => 'fgaescpil',
	type		=> 'flags',
	all_count	=> _"All styles",
	none		=> quotemeta _"No styles",
	FilterList	=> {search=>1,},
	edit_order=> 72,	edit_many=>1,
	disable=>1,	options => 'disable editsubmenu samemenu',
	editsubmenu=>0,
	category=>'extra',
 },
 theme	=>
 {	name	=> _"Themes",	width => 180,	flags => 'fgaescpil',
	type		=> 'flags',
	all_count	=> _"All themes",
	none		=> quotemeta _"No themes",
	FilterList	=> {search=>1,},
	edit_order=> 73,	edit_many=>1,
	disable=>1,	options => 'disable editsubmenu samemenu',
	editsubmenu=>0,
	category=>'extra',
 },
 comment=>
 {	name	=> _"Comment",	width => 200,	flags => 'fgarwescpi',		type => 'text',
	id3v1	=> 4,		id3v2	=> 'COMM;;;%v',	vorbis	=> 'description|comment|comments',	ape	=> 'Comment',	lyrics3v2=> 'INF', ilst => "\xA9cmt",	join_with => "\n",
	edit_order=> 60,	edit_many=>1,	letter => 'C',
	category=>'basic',
 },
 rating	=>
 {	name	=> _"Rating",		width => 80,	flags => 'fgaescp',	type => 'rating',
	id3v2	=> 'TXXX;FMPS_Rating_User;%v::%i & TXXX;FMPS_Rating;%v | percent( TXXX;gmbrating;%v ) | five( TXXX;rating;%v )',
	vorbis	=> 'FMPS_RATING_USER::%i & FMPS_RATING | percent( gmbrating ) | five( rating )',
	ape	=> 'FMPS_RATING_USER::%i & FMPS_RATING | percent( gmbrating ) | five( rating )',
	ilst	=> '----FMPS_Rating_User::%i & ----FMPS_Rating | percent( ----gmbrating ) | five( ----rating )',
	postread=> \&FMPS_rating_postread,
	prewrite=> \&FMPS_rating_prewrite,
	'postread:five'=> sub { my $v=shift; length $v && $v=~m/^\d+$/ && $v<=5 ? sprintf('%d',$v*20) : undef }, # for reading foobar2000 rating 0..5 ?
	'postread:percent'=> sub { $_[0] }, # for anyone who used gmbrating
	FilterList => {},
	starprefix => 'stars',
	edit_order=> 90,	edit_many=>1,
	edit_string=> _"Edit rating",
	editsubmenu=>1,
	options	=> 'rw_ userid editsubmenu stars',
	'filterpat:value' => [ round => "%d", unit => '%', max=>100, default_value=>50, ],
	category=>'basic',
	alias	=> 'stars',
 },
 ratingnumber =>	#same as rating but returns DefaultRating if rating set to default, will be replaced by rating.number or something in the future
 {	type	=> 'virtual',
	flags	=> 'g',
	depend	=> 'rating',
	get	=> '#rating->_default#',
 },
 added	=>
 {	name	=> _"Added",		width => 100,	flags => 'fgascp_',	type => 'date',
	FilterList => {type=>'month', },
	can_group=>1,
	category=>'stats',
 },
 lastplay	=>
 {	name	=> _"Last played",	width => 100,	flags => 'fgascp',	type => 'date',
	FilterList => {type=>'month',},
	can_group=>1,	letter => 'P',
	'filterdesc:e:0'	=> _"never",
	'filterdesc:-e:0'	=> _"has been played",	#FIXME better description
	category=>'stats',
	#alias	=> 'played',
 },
 playhistory	=>
 {	name	=> _"Play history",	flags => 'fgalp',	type=> 'dates_compact',
	FilterList => {type=>'month',},
	'filterdesc:ecount:0'	=> _"never",
	'filterdesc:-ecount:0'	=> _"has been played",	#FIXME better description
	alias	=> 'played',
	category=>'stats',
	disable=>0,	options => 'disable',
 },
 lastskip	=>
 {	name	=> _"Last skipped",	width => 100,	flags => 'fgascp',	type => 'date',
	FilterList => {type=>'month',},
	can_group=>1,	letter => 'K',
	'filterdesc:e:0'	=> _"never",
	'filterdesc:-e:0'	=> _"has been skipped",	#FIXME better description
	category=>'stats',
	alias	=> 'skipped',
 },
 skiphistory	=>
 {	name	=> _"Skip history",	flags => 'fgalp',	type=> 'dates_compact',
	FilterList => {type=>'month',},
	'filterdesc:ecount:0'	=> _"never",
	'filterdesc:-ecount:0'	=> _"has been skipped",	#FIXME better description
	#alias	=> 'skipped',
	category=>'stats',
	disable=>1,	options => 'disable',
 },
 playcount	=>
 {	name	=> _"Play count",	width => 50,	flags => 'fgaescp',	type => 'integer',	letter => 'p',
	options => 'rw_ userid editable',
	id3v2	=> 'TXXX;FMPS_Playcount;%v&TXXX;FMPS_Playcount_User;%v::%i',
	vorbis	=> 'FMPS_PLAYCOUNT&FMPS_PLAYCOUNT_USER::%i',
	ape	=> 'FMPS_PLAYCOUNT&FMPS_PLAYCOUNT_USER::%i',
	ilst	=> '----FMPS_Playcount&----FMPS_Playcount_User::%i',
	postread=> sub { my $v=shift; length $v ? sprintf('%d',$v) : undef },
	prewrite=> sub { sprintf('%.1f', $_[0]); },
	category=>'stats',
	alias	=> 'plays',
	edit_order=> 90,
 },
 skipcount	=>
 {	name	=> _"Skip count",	width => 50,	flags => 'fgaescp',	type => 'integer',	letter => 'k',
	category=>'stats',
	alias	=> 'skips',
	edit_order=> 91,
	options	=> 'editable',
 },
 composer =>
 {	name	=> _"Composer",		width	=> 100,		flags => 'fgarwescpi',	type => 'artist',
	id3v2	=> 'TCOM',	vorbis	=> 'composer',		ape => 'Composer',	ilst => "\xA9wrt",
	apic_id	=> 11,
	picture_field => 'artist_picture',
	FilterList => {search=>1},
	edit_many=>1,
	disable=>1,	options => 'disable samemenu',
	category=>'extra',
	articles=>1,
	samemenu=>1,
 },
 lyricist =>
 {	name	=> _"Lyricist",		width	=> 100,		flags => 'fgarwescpi',	type => 'artist',
	id3v2	=> 'TEXT',	vorbis	=> 'LYRICIST',		ape => 'Lyricist',	ilst => '---LYRICIST',
	apic_id	=> 12,
	picture_field => 'artist_picture',
	FilterList => {search=>1},
	edit_many=>1,
	disable=>1,	options => 'disable',
	category=>'extra',
	articles=>1,
 },
 conductor =>
 {	name	=> _"Conductor",	width	=> 100,		flags => 'fgarwescpi',	type => 'artist',
	id3v2	=> 'TPE3',	vorbis	=> 'CONDUCTOR',		ape => 'Conductor',	ilst => '---CONDUCTOR',
	apic_id	=> 9,
	picture_field => 'artist_picture',
	FilterList => {search=>1},
	edit_many=>1,
	disable=>1,	options => 'disable samemenu',
	category=>'extra',
	articles=>1,
 },
 remixer =>
 {	name	=> _"Remixer",	width	=> 100,		flags => 'fgarwescpi',	type => 'artist',
	id3v2	=> 'TPE4',	vorbis	=> 'REMIXER',		ape => 'MixArtist',	ilst => '---REMIXER',
	picture_field => 'artist_picture',
	FilterList => {search=>1},
	edit_many=>1,
	disable=>1,	options => 'disable samemenu',
	category=>'extra',
	articles=>1,
 },
 version=> #subtitle ?
 {	name	=> _"Version",	width	=> 150,		flags => 'fgarwescpi',	type => 'fewstring',
	id3v2	=> 'TIT3',	vorbis	=> 'version|subtitle',			ape => 'Subtitle',	ilst=> '----SUBTITLE',
	category=>'extra',
 },
 bpm	=>
 {	name	=> _"BPM",	width	=> 60,		flags => 'fgarwescp',	type => 'integer',
	id3v2	=> 'TBPM',	vorbis	=> 'BPM',	ape => 'BPM',		ilst=> 'tmpo',
	FilterList => {type=>'div.10',},
	disable=>1,	options => 'disable',
	category=>'extra',
 },
 channel=>
 {	name	=> _"Channels",		width => 50,	flags => 'fgarscp',	type => 'integer',	bits => 4,	audioinfo => 'channels',
	default_filter	 => 'e:2',
	'filterdesc:e:1' => _"is mono",
	'filterdesc:-e:1'=> _"isn't mono",
	'filterdesc:e:2' => _"is stereo",
	'filterdesc:-e:2'=> _"isn't stereo",
	category=>'audio',
 },
 bitrate=>
 {	name	=> _"Audio bitrate",	width => 90,	flags => 'fgarscp_',	type => 'integer',	bits => 16,	audioinfo => 'bitrate|bitrate_nominal|bitrate_calculated',		check	=> '#VAL#= sprintf "%.0f",#VAL#/1000;',
	display	=> '::replace_fnumber("%d kbps",#_#)',
	FilterList => {type=>'div.32',},
	'filterpat:value' => [ round => "%d", unit => 'kbps', default_value=>192 ],
	category=>'audio',
 },
 videobitrate=>
 {	name	=> _"Video bitrate",	width => 90,	flags => 'fgarscp_',	type => 'integer_overflow',	bits => 16,	audioinfo => 'video_bitrate',		check	=> '#VAL#= sprintf "%.0f",#VAL#/1000;',
	display	=> '::replace_fnumber("%d kbps",#_#)',
	FilterList => {type=>'div.128',},
	'filterpat:value' => [ round => "%d", unit => 'kbps', default_value=>1024 ],
	disable=>1,	options => 'disable',
	category=>'video',
 },
 samprate=>
 {	name	=> _"Sampling Rate",	width => 90,	flags => 'fgarscp',	type => 'fewnumber',	bits => 8,	audioinfo => 'rate',
	display	=> '::replace_fnumber("%d Hz",#_#)',
	FilterList => {},
	'filterdesc:e:44100' => _"is 44.1kHz",
	'filterpat:value' => [ round => "%d", unit => 'Hz', step=> 100, default_value=>44100 ],
	category=>'audio',
 },
 filetype=>
 {	name	=> _"Audio format",		width => 80,	flags => 'fgarscp',	type => 'fewstring',	bits => 8, #could probably fit in 4bit
	FilterList => {},
	'filterdesc:m:^mp3'	=> _"is a mp3 file",
	'filterdesc:m:^mp4 mp4a'=> _"is an aac file",
	'filterdesc:m:^mp4 alac'=> _"is an alac file",
	'filterdesc:m:^mp4'	=> _"is an mp4/m4a file",
	'filterdesc:m:^opus'	=> _"is an opus file",
	'filterdesc:m:^vorbis'	=> _"is a vorbis file",
	'filterdesc:m:^flac'	=> _"is a flac file",
	'filterdesc:m:^mpc'	=> _"is a musepack file",
	'filterdesc:m:^wv'	=> _"is a wavepack file",
	'filterdesc:m:^ape'	=> _"is an ape file",
	'filterdesc:m:^ape|^flac|^mp4 alac|^wv'	=> _"is a lossless file",
	'filterdesc:-m:^ape|^flac|^mp4 alac|^wv'=> _"is a lossy file",
	audioinfo => 'audio_format',
	category=>'audio',
	alias	=> 'type format audiotype audioformat',
 },
 container=>
 {	name	=> _"Container format",		width => 80,	flags => 'fgarscp',	type => 'fewstring',	bits => 8,
	FilterList => {},
	disable=>1,	options => 'disable',
	audioinfo => 'container_format',
	category=>'video',
 },
 videoformat=>
 {	name	=> _"Video format",		width => 80,	flags => 'fgarscp',	type => 'fewstring',	bits => 8,
	FilterList => {},
	disable=>1,	options => 'disable',
	audioinfo => 'video_format',
	category=>'video',
	alias	=> 'video videotype',
 },
 framerate=>
 {	name	=> _"Frame rate",	width => 90,	flags => 'fgarscp',	type => 'integerfloat',	audioinfo => 'framerate',
	FilterList => {},
	disable=>1,	options => 'disable',
	category=>'video',
 },
 videoratio=>
 {	name	=> _"Video ratio",	width => 90,	flags => 'fgarscp',	type => 'integerfloat',	audioinfo => 'video_ratio',
	FilterList => {},
	disable=>1,	options => 'disable',
	category=>'video',
	alias	=> 'ratio',
 },
 videowidth=>
 {	name	=> _"Video width",	width => 90,	flags => 'fgarscp',	type => 'integer',	bits => 16,	audioinfo => 'video_width',
	FilterList => {},
	disable=>1,	options => 'disable',
	category=>'video',
	alias	=> 'width',
 },
 videoheight=>
 {	name	=> _"Video height",	width => 90,	flags => 'fgarscp',	type => 'integer',	bits => 16,	audioinfo => 'video_height',
	FilterList => {},
	disable=>1,	options => 'disable',
	category=>'video',
	alias	=> 'height',
 },
 'length'=>
 {	name	=> _"Length",		width => 50,	flags => 'fgarscp_',	type => 'length',	bits => 16, # 16 bits limit length to ~18.2 hours
	audioinfo => 'seconds',		check	=> '#VAL#= sprintf "%.0f",#VAL#;',
	FilterList => {type=>'div.60',},
	'filterpat:value' => [ unit => \%::TIMEUNITS, default_unit=> 's', default_value=>1 ],
	letter => 'm',
	category=>'audio',
 },
 replaygain_track_gain=>
 {	name	=> _"Track gain",	width => 70,	flags => 'fgrwscpa',
	type	=> 'float',	check => '#VAL#= do{ #VAL# =~m/^([-+]?\d*\.?\d+)\s*(?:dB)?$/i ? $1 : #novalue#};',
	displayformat	=> '%.2f dB',
	id3v2	=> 'TXXX;replaygain_track_gain;%v',	vorbis	=> 'replaygain_track_gain',	ape	=> 'replaygain_track_gain', ilst => '----replaygain_track_gain',
	prewrite=> sub { length($_[0]) && $_[0]==$_[0] ? sprintf("%.2f dB",$_[0]) : undef }, #remove tag if empty string or NaN
	options => 'disable editable',
	category=>'replaygain',
	alias	=> 'track_gain trackgain',
	edit_max=> 120,
	edit_order=> 95,
	FilterList => {type=>'range',},
 },
 replaygain_track_peak=>
 {	name	=> _"Track peak",	width => 60,	flags => 'fgrwscpa',
	id3v2	=> 'TXXX;replaygain_track_peak;%v',	vorbis	=> 'replaygain_track_peak',	ape	=> 'replaygain_track_peak', ilst => '----replaygain_track_peak',
	prewrite=> sub { length($_[0]) && $_[0]==$_[0] ? sprintf("%.6f",$_[0]) : undef }, #remove tag if empty string or NaN
	type	=> 'float',
	options => 'disable',
	category=>'replaygain',
	alias	=> 'track_peak trackpeak',
	range_step=> '.1',
	FilterList => {type=>'range',},
 },
 replaygain_album_gain=>
 {	name	=> _"Album gain",	width => 70,	flags => 'fgrwscpa',
	type	=> 'float',	check => '#VAL#= do{ #VAL# =~m/^([-+]?\d*\.?\d+)\s*(?:dB)?$/i ? $1 : #novalue#};',
	displayformat	=> '%.2f dB',
	id3v2	=> 'TXXX;replaygain_album_gain;%v',	vorbis	=> 'replaygain_album_gain',	ape	=> 'replaygain_album_gain', ilst => '----replaygain_album_gain',
	prewrite=> sub { length($_[0]) && $_[0]==$_[0] ? sprintf("%.2f dB",$_[0]) : undef }, #remove tag if empty string or NaN
	options => 'disable editable',
	category=>'replaygain',
	alias	=> 'album_gain albumgain',
	edit_max=> 120,
	edit_order=> 96,
	edit_many=>1,
	FilterList => {type=>'range',},
 },
 replaygain_album_peak=>
 {	name	=> _"Album peak",	width => 60,	flags => 'fgrwscpa',
	id3v2	=> 'TXXX;replaygain_album_peak;%v',	vorbis	=> 'replaygain_album_peak',	ape	=> 'replaygain_album_peak', ilst => '----replaygain_album_peak',
	prewrite=> sub { length($_[0]) && $_[0]==$_[0] ? sprintf("%.6f",$_[0]) : undef }, #remove tag if empty string or NaN
	type	=> 'float',
	options => 'disable',
	category=>'replaygain',
	alias	=> 'album_peak albumpeak',
	range_step=> '.1',
	FilterList => {type=>'range',},
 },
 replaygain_reference_level=>
 {	flags => 'w',	type => 'writeonly',	#only used for writing
	id3v2	=> 'TXXX;replaygain_reference_level;%v',vorbis	=> 'replaygain_reference_level',	ape => 'replaygain_reference_level', ilst => '----replaygain_reference_level',
	category=>'replaygain',
 },

 playedlength	=> {	name=> "Played length", type=>'length', flags=> 'g',
			get => '#playcount->get# * #length->get#',  _=>'#get#',
			depend=> 'playcount length',
		   },
 version_or_empty	=> { get => 'do {my $v=#version->get#; $v eq "" ? "" : " ($v)"}',	type=> 'virtual',	depend => 'version',	flags => 'g', letter => 'V', },
 album_years	=> { name => _"Album year(s)", get => 'AA::Get("year:range","album",#album->get_gid#)',	type=> 'virtual',	depend => 'album year',	flags => 'g', letter => 'Y', }, #depends on years from other songs too
 uri		=> { get => '"file://".::url_escape(#path->get# .::SLASH. #file->get#)',	type=> 'virtual',	depend => 'file path',	flags => 'g', },
 fullfilename_raw =>{	name => _"Raw filename with path",	flags => 'g',	letter => 'f',
			get => '#fullfilename->get#',	type=> 'virtual', depend => 'file path',
		   },
 fullfilename	=> {	get	=> '#path->get# .::SLASH. #file->get#',
	 		display => '#path->display# .::SLASH. #file->display#',
			makefilter_fromID => '"fullfilename:e:" . #get#',
			type	=> 'virtual',	flags => 'g',	depend => 'file path',	letter => 'u',
			'filter:e'	=> '#ID# == #VAL#',	'filter_prep:e'=> sub { FindID($_[0]); },
		   },
 barefilename	=> {	name => _"Filename without extension",	type=> 'filename',	flags => 'g',	letter => 'o',
			get => 'do {my $s=#file->get#; $s=~s/\.[^.]+$//; $s;}',	depend => 'file',
		   },
 extension =>	   {	name => _"Filename extension",		type=> 'filename',	flags => 'g',
			get => 'do {my $s=#file->get#; $s=~s#^.*\.##; $s;}',	depend => 'file',
		   },
 title_or_file	=> {	get => '(#title->get# eq "" ? (#show_ext# ? #file->display# : #barefilename->display#) : #title->get#)',
			type=> 'virtual',	flags => 'gcs',	width	=> 270,
			name=> _"Title or filename",
			depend => 'file title', letter => 'S',	#why letter S ? :)
			options => 'show_ext', show_ext=>0,
			articles=>1,
		   },

 missing	=> { flags => 'gan', type => 'fewnumber', bits => 8, },
 missingkey	=> { get => 'join "\\x1D",'.join(',',map("#$_->get#",@MissingKeyFields)), depend => "@MissingKeyFields",	type=> 'virtual', },	#used to check if same song
 missingkey_ro	=> { get => 'join "\\x1D",'.join(',',map("#$_->get#",@MissingKeyFields_ro)), depend => "@MissingKeyFields_ro",	type=> 'virtual', },	#used to check if same song (alternate mode)

 shuffle	=> { name => _"Shuffle",	type => 'shuffle',	flags => 's', },
 album_shuffle	=> { name => _"Album shuffle",	type => 'gidshuffle',	flags => 's',	mainfield=>'album'	  },
 embedded_pictures=>
 {	flags => 'wl',	type=>'writeonly',
	id3v2 => 'APIC',	vorbis => 'METADATA_BLOCK_PICTURE',	'ilst' => 'covr',
 },
 embedded_lyrics=>
 {	flags => '',	type	=> 'virtual',
	id3v2 => 'TXXX;FMPS_Lyrics;%v | USLT;;;%v',	vorbis => 'FMPS_LYRICS|lyrics',	ape => 'FMPS_LYRICS|Lyrics',
	'ilst' => "----FMPS_Lyrics|\xA9lyr",	lyrics3v2 => 'LYR',
 },
 filetags	=>	# debug field : list of the id3v2 frames / vorbis comments
 		{	name	=> "filetags", width => 180,	flags => 'grascil', type	=> 'flags',
			"id3v2:read"	=> sub { my $tag=shift; my %res; for my $key ($tag->get_keys) { my @v=$tag->get_values($key); if ($key=~m/^TXXX$|^COMM$|^WXXX$/) { my $i= $key eq 'COMM' ? 1 : 0; $res{"$key;$_->[$i]"}=undef for @v; } else { $res{$key}=undef; } } ; return [map "id3v2_$_", keys %res]; },
			'vorbis:read'	=> sub { [map "vorbis_$_",$_[0]->get_keys] },
			'ape:read'	=> sub { [map "ape_$_",   $_[0]->get_keys] },
			'ilst:read'	=> sub { [map "ilst_$_",  $_[0]->get_keys] },
			FilterList => {search=>1,none=>1},
			none		=> quotemeta "No tags",	#not translated because made for debugging
			disable=>1,
		},
 list =>
 {	type=> 'special',
	flags	=> 'f',
	name	=> _"Lists",
	'filterdesc:~'		=> [ _"present in %s", _"present in list", 'listname',],
	'filterdesc:-~'		=> _"not present in %s",
	'filter:~'		=> '.!!. do {my $l=$::Options{SavedLists}{"#VAL#"}; $l ? $l->IsIn(#ID#) : undef}',
	default_filter		=> '~',
 },
 length_estimated =>
 {	type	=> 'boolean',
	audioinfo=> 'estimated',
	flags	=> 'gar',
 },
);

our %FieldTemplates=
(	string	=> { type=>'string',	editname=>_"string",		flags=>'fgaescp',	width=> 200,	edit_many =>1,		options=> 'customfield', articles=>1, },
	text	=> { type=>'text',	editname=>_"multi-lines string",flags=>'fgaescp',	width=> 200,	edit_many =>1,		options=> 'customfield', },
	float	=> { type=>'float',	editname=>_"float",		flags=>'fgaescp',	width=> 100,	edit_many =>1,		options=> 'customfield', desc => _"For decimal numbers", },
	boolean	=> { type=>'boolean',	editname=>_"boolean",		flags=>'fgaescp',	width=> 20,	edit_many =>1,		options=> 'customfield', },
	flags	=> { type=>'flags', 	editname=>_"flags",		flags=>'fgaescpil',	width=> 180,	edit_many =>1, can_group=>1, options=> 'customfield persistent_values editsubmenu samemenu', FilterList=> {search=>1},   desc=>_"Same type as labels", editsubmenu => 1, },
	artist	=> { type=>'artist',	editname=>_"artist",		flags=>'fgaescpi',	width=> 200,	edit_many =>1, can_group=>1, options=> 'customfield samemenu', FilterList=> {search=>1,drag=>::DRAG_ARTIST}, picture_field => 'artist_picture', articles=>1, },
	fewstring=>{ type=>'fewstring',	editname=>_"common string",	flags=>'fgaescpi',width=> 200,	edit_many =>1, can_group=>1, options=> 'customfield  samemenu', FilterList=> {search=>1}, desc=>_"For when values are likely to be repeated", articles=>1, },
	fewnumber=>{ type=>'fewnumber',	editname=>_"common number",	flags=>'fgaescp',	width=> 100,	edit_many =>1, can_group=>1, options=> 'customfield', FilterList=> {},  desc=>_"For when values are likely to be repeated" },
	integer	=> { type=>'integer',	editname=>_"integer",		flags=>'fgaescp',	width=> 100,	edit_many =>1, can_group=>1, options=> 'customfield', FilterList=> {},  desc => _"For integer numbers", },
	rating	=> { type=>'rating',	editname=>_"rating",		flags=>'fgaescp_',	width=> 80,	edit_many =>1, can_group=>1, options=> 'customfield rw_ useridwarn userid editsubmenu stars', FilterList=> {},
		     postread => \&FMPS_rating_postread,		prewrite => \&FMPS_rating_prewrite,
		     id3v2 => 'TXXX;FMPS_Rating_User;%v::%i',	vorbis	=> 'FMPS_RATING_USER::%i',	ape => 'FMPS_RATING_USER::%i',	ilst => '----FMPS_Rating_User::%i',
		     starprefix => 'stars',
		     editsubmenu => 1,
		     desc => _"For alternate ratings",
		   },
);
$FieldTemplates{$_}{category}||='custom' for keys %FieldTemplates;

our %HSort=
(	string	=> '$h->{$a} cmp $h->{$b} ||',
	number	=> '$h->{$a} <=> $h->{$b} ||',
	year2	=> 'substr($h->{$a},-4,4) cmp substr($h->{$b},-4,4) ||',
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

sub filename_escape	#same as ::url_escape but escape different characters
{	my $s=$_[0];
	::_utf8_off($s);
	$s=~s#([^/_.+'(),A-Za-z0-9- ])#sprintf('%%%02X',ord($1))#seg;
	return $s;
}

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
			($c)=grep defined,map $_->{$key}, @hashlist;
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
sub Field_property
{	my ($field_opt,$key)=@_;
	my ($field,$subtype)=split /\./,$field_opt;
	my $h= $Def{$field};
	return undef unless $h;
	while ($h)
	{	return $h->{$key} if exists $h->{$key};
		my $type= $h->{parent} || $h->{type};
		return undef unless $type;
		$h= $Types{$type};
		return $Types{"$type.$subtype"}{$key} if $subtype && $Types{"$type.$subtype"} && exists $Types{"$type.$subtype"}{$key};
	}
}
sub Field_properties
{	my ($field,@keys)=@_;
	return map Field_property($field,$_), @keys;
}

sub Fields_with_filter
{	return grep $Def{$_}{flags}=~/f/, @Fields;
}
sub filter_properties
{	my ($field,$cmd0)=@_;
	my ($inv,$cmd,$pat)= $cmd0=~m/^(-?)([^-:]+)(?::(.*))?$/;
	my @totry= ("$inv$cmd", $cmd);
	unshift @totry, "$inv$cmd:$pat", "$cmd:$pat" if defined $pat && length $pat;
	my $prop;
	for my $c (@totry)
	{	$prop= Songs::Field_property($field,"filterdesc:$c");
		next unless $prop;
		if (!ref $prop && $c=~m/:/ && $c!~m/^-/) { $prop= [$prop,$prop,'']; }
		next if !ref $prop || @$prop<2;
		if (@$prop==2) { $c= $prop->[1]; $prop= Songs::Field_property($field,"filterdesc:$c"); }
		$cmd=$c;
		last;
	}
	return $cmd,$prop;
}
sub Field_filter_choices
{	my $field=shift;
	my %filters;
	my $h= $Def{$field};
	my %exclude;
	while ($h)
	{	for my $key (keys %$h)
		{	next unless $key=~m/^filterdesc:(.+)/ && !$exclude{$1} && !$filters{$1};
			my $value= $h->{$key};
			my $f=$1;
			if (ref $value) { if (@$value<3) { $exclude{$f}=1; next } else { $value=$value->[1]; } }
			else { unless ($f=~m/:/ && $f!~m/^-/) { $exclude{$f}=1; next} }	# for constant filters eg: filterdesc:e:44100
			$filters{$f}= $value;
		}
		my $type= $h->{parent} || $h->{type};
		last unless $type;
		if (my $e= $h->{filter_exclude})	#list of filters from parent to ignore, 'ALL' for all
		{	last if $e eq 'ALL';
			$exclude{$_}=1 for split / +/, $e;
		}
		$h= $Types{$type};
	}
	return \%filters;
}
sub filter_prep_numbers { $_[0]=~m/(-?\d*\.?\d+)/; return $1 || 0 }
sub filter_prep_numbers_between { sort {$a <=> $b} map filter_prep_numbers($_), split / /,$_[0],2 }
sub FilterCode
{	my ($field,$cmd,$pat,$inv)=@_;
	my ($code,$convert)=LookupCode($field, "filter:$cmd", "filter_prep:$cmd");
	unless ($code) { warn "error can't find code for filter $field,$cmd,$pat,$inv\n"; return 1}
	$convert||=sub {quotemeta $_[0]};
	unless (ref $convert) { $convert=~s/#PAT#/\$_[0]/g; $convert=eval "sub {$convert}"; }
	$code=~s/#ID#/\$_/g;
	if ($inv)	{$code=~s#$Filter::OpRe#$Filter::InvOp{$1}#go}
	else		{$code=~s#$Filter::OpRe#$1 eq '!!' ? '' : $1#ego}
	if ($code=~m/#VAL1#/) { my @p= $convert->($pat); $code=~s/#VAL(\d)#/$p[$1-1]/g; }
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
		if ($::Options{Remove_articles} && CanRemoveArticles($field)) { $code="remove_articles($code)"; }
	}
	my $init='';
	$init=$1 if $code=~s/^(.+) +---- +//;
	my $code2=$code;
	$code =~s/#(?:GID|ID)#/\$a/g;
	$code2=~s/#(?:GID|ID)#/\$b/g;
	$code= $inv ? "$code2 $op $code" : "$code $op $code2";
	return $init,$code;
}
sub CompileArticleRE
{	my @art= split /\s+/, $::Options{Articles};
	s/_/ /g for @art; #replace _ by spaces to allow multi-word "articles", not sure if it could be useful
	@art= map quotemeta($_).(m/'$/ ? "" : "\\s+"), @art;
	my $re= '^(?:' .join('|',@art). ')';
	$Articles_re= qr/$re/i;
}
sub UpdateArticleRE
{	delete $::Delayed{'UpdateArticleRE'};
	Songs::CompileArticleRE();
	%FuncCache=();#FIXME find a better way
	Songs::Changed(undef,FieldList(true=>'articles'));
}
sub CanRemoveArticles { $Def{$_[0]}{articles}; }
sub remove_articles
{	my $s=$_[0]; $s=~s/$Articles_re//; $s;
}

sub Compile		#currently return value of the code must be a scalar
{	my ($name,$code)=@_;
	if ($::debug) { $::DebugEvaledCode{$name}=$code; $code=~s/^sub \{/sub { local *__ANON__ = 'evaled $name';/; }
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

	Field_Apply_options();
	CompileArtistsRE();
	CompileArticleRE();

	my @todo=grep !$Def{$_}{disable}, sort keys %Def;
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
	warn "\@Fields=@Fields\n" if $::debug;
	$Def{$_}{flags}||='' for @Fields;	#DELME
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
	{	my $code='my ($ID,$values,$skip_missing)= @_; my $val; my @changed;'."\n";
		for my $f (grep $Def{$_}{flags}=~m/r/, @Fields)
		{	my $c= $Def{$f}{flags}=~m/_/ ?
				"if (exists \$values->{$f})".
				"{	\$val=\$values->{$f}; #check#;\n".
				"	if (#diff#) { #set#; push \@changed,'$f'; }".
				"}\n"
				:
				"if (!\$skip_missing || exists \$values->{$f} )\n".
				"{	\$val= (exists \$values->{$f} ? \$values->{$f} : #default#);\n".
				"	#check#;".
				"	if (#diff#) { #set#; push \@changed,'$f'; }\n".
				"}";
			$code.=MakeCode($f,$c,ID => '$ID', VAL => "\$val");
		}
		$code.=' return @changed;';
		$DIFFsub= Compile(Diff =>"sub {$code}");
	}

	# create SET sub
	{	my $code=join "\n",
		'my $IDs=$_[0]; my $values=$_[1]; my %onefieldchanged; my @towrite; my %changedfields; my @changedIDs; my $i=0; my $val;',
		'my $couldneedwriting; for my $f (keys %$values) { $f=~s/^[+@]//; if ($Def{$f}{flags}=~m/w/) { $couldneedwriting=1; last; } }',
		'for my $ID (@$IDs)',
		'{	my $changed;',
		'	my $readonly=1; if ($couldneedwriting && !$::Options{TAG_nowrite_mode})',
		'	{	'.MakeCode('extension','my $format= $FileTag::FORMATS{lc(#get#)}; $readonly= !$format || $format->{ro};',ID => '$ID'),
		"	}\n\n";
		for my $f (grep $Def{$_}{flags}=~m/[aw]/, @Fields)
		{	my $ro_set= "#set#; \$changedfields{$f}=undef; \$changed=1;";
			my $set= $Def{$f}{flags}=~m/w/ ?
				"if (\$readonly) { $ro_set } else { push \@{\$towrite[\$i]}, '$f',\$val; }":
				$ro_set;
			my $c= join "\n",
				"	\$val=	exists \$values->{$f} ? 	\$values->{$f} :",
				"		exists \$values->{'\@$f'} ? 	shift \@{\$values->{'\@$f'}} :",
				"						undef;",
				"	if (defined \$val)",
				"	{	#check#;",
				"		if (#diff#) { $set }",
				"	}\n";
			if ($Def{$f}{flags}=~m/l/ && !($Def{$f}{flags}!~m/r/ && $Def{$f}{flags}=~m/w/)) # edit mode for multi-value fields, exclude write-only or read-on-demand fields (w without r) as this requires knowing the current values
			{  $c.=	"	elsif (\$val=\$values->{'+$f'})\n". # $v must contain [[toset],[torm],[toggle]]
				"	{	#check_multi#\n".
				"		if (\$val= #set_multi#) { $set }\n". # set_multi return the new arrayref if modified, undef if not changed
			   	"	}\n";
			}
			$code.= MakeCode($f,$c,ID => '$ID', VAL => "\$val");
		}
		$code.= join "\n",
		'	push @changedIDs,$ID if $changed;',
		'	$i++;',
		'}',
		#'::SongsChanged(\@changedIDs, [keys %changedfields]) if @changedIDs;',
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


	my @getfields= grep $Def{$_}{flags}=~m/g/, @Fields;
	%Aliases= map {$_=>$_} @getfields;
	for my $field (@getfields)
	{	$Aliases{$_}=$field for split / +/, ($Def{$field}{alias}||'');
	}
	#for my $field (@getfields)	# user-defined aliases
	#{	for my $alias (split / +/, ($::Options{Fields_options}{$field}{aliases}||''))
	#	{	$Aliases{ ::superlc($alias) } ||= $field;
	#	}
	#}
	for my $field (@getfields)	#translated aliases
	{	for my $alias (split /\s*,\s*/, ($Def{$field}{alias_trans}||''))
		{	$alias=~s/ /_/g;
			$Aliases{ ::superlc($alias) } ||= $field;
		}
	}
	$::ReplaceFields{'$'.$_}= $::ReplaceFields{'${'.$_.'}'}= $Aliases{$_} for keys %Aliases;


	::HasChanged('fields_reset');
	#FIXME connect them to 'fields_reset' event :
	SongList::init_textcolumns();
	SongTree::init_textcolumns();
}

sub MakeLoadSub
{	my ($extradata,@loaded_slots)=@_;
	my %extra_sub;
	my %loadedfields;
	$loadedfields{$loaded_slots[$_]}=$_ for 0..$#loaded_slots;
	# begin with a line that checks if a given path-file has already been loaded into the library
	my $pathfile_code= '$_['.$loadedfields{path}.'] ."/". $_['.$loadedfields{file}.']';
	my $code= '$uniq_check{ '.$pathfile_code.' }++ && do { warn "warning: file ".'.$pathfile_code.'." already in library, skipping.\\n"; return };'."\n";
	# new file, increment $LastID
	$code.='$LastID++;'."\n";
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
			warn "adding update code for $field\n" if $::debug && $c;
		}
		$code.=$c.";\n" if $c;

		my ($mainfield,$load_extra)=LookupCode($field,'mainfield','load_extra',[SGID=>'$_[0]']);
		$mainfield||=$field;
		if ($load_extra && $extradata->{$mainfield} && !$extra_sub{$mainfield})
		{	my $code= 'my $gid='.$load_extra.";\n";
			my $i=1;
			for my $subfield (split /\t/,$extradata->{$mainfield}[0])
			{	my $c=LookupCode($subfield,'load_extra',[GID=>'$gid',VAL=>"\$_[$i]"]);
				$code.= "\t$c;\n" if $c;
				$i++;
			}
			$extra_sub{$mainfield}= Compile("LoadSub_$mainfield" => "sub {$code}") || sub {};
		}
	}
	$code.= '; return $LastID;';
	my $loadsub= Compile(LoadSub => "my %uniq_check; sub {$code}");
	return $loadsub,\%extra_sub;
}
sub MakeSaveSub
{	my @saved_fields;
	my @code;
	my %extra_sub; my %extra_subfields;
	for my $field (sort grep $Def{$_}{flags}=~m/a/, @Fields)
	{	next if $::Options{Fields_options}{$field}{remove}; #deleted custom field
		my $save_as= $Def{$field}{_renamed_to} || $field;
		push @saved_fields,$save_as;
		push @code, Code($field, 'save|get', ID => '$_[0]');
		my ($mainfield,$save_extra)=LookupCode($field,'mainfield','save_extra');
		if ($save_extra && $Def{$field}{_properties} && ( !$mainfield || $mainfield eq $field ))
		{	my @subfields= split / /, $Def{$field}{_properties};
			if (@subfields)
			{	my @extra_code;
				for my $subfield (@subfields)
				{	my $c=LookupCode($subfield,'save_extra',[GID => '$gid']);
					push @extra_code, $c;
				}
				$extra_subfields{$save_as}= join ' ', map $Def{$_}{_renamed_to}||$_, @subfields;
				my $code= $save_extra;
				my $extra_code=join ',', @extra_code;
				$code=~s/#SUBFIELDS#/$extra_code/g;
				$extra_sub{$save_as}= Compile("SaveSub_$field" => "sub { $code }") || sub {};
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
	warn "Reading Tag for $file\n" if $::Verbose;
	my ($size,$modif)=(stat $file)[7,9];
	my $values= FileTag::Read($file,findlength=>1);
	return unless $values;
	(my $path,$file)=::splitpath($file);
	%$values=(	%$values,
			file => $file,	path=> $path,
			modif=> $modif, size=> $size,
			added=> time,
		);
	my ($ID,$wasmissing)= CheckMissing($values);
	if (defined $ID)
	{	ReReadFile($ID);
		::CheckLength($ID) if $::Options{LengthCheckMode} eq 'add' && Get($ID,'length_estimated');
		return $wasmissing ? $ID : undef;
	}

	#warn "\nNewSub(LastID=$LastID)\n";warn join("\n",map("$_=>$values->{$_}",sort keys %$values))."\n";
	$ID=$NEWsub->($values); #warn $Songs::Songs_title__[-1]." NewSub end\n";
	if ($values->{length_estimated} && $::Options{LengthCheckMode} eq 'add') { ::CheckLength($ID); }
	$IDFromFile->{$path}{$file}=$ID if $IDFromFile;
	return $ID;
}

sub ReReadFile		#force values :
			# 0=>read if file changed (size or date),
			# 1=>force read tags
			# 2=> same as 3 if estimated, else same as 0
			# 3=>force check length (and tags)
{	my ($ID,$force,$noremove)=@_;
	my $file= GetFullFilename($ID);
	if (-e $file)
	{	my ($size1,$modif1,$estimated)=Songs::Get($ID,qw/size modif length_estimated/);
		my ($size2,$modif2)=(stat $file)[7,9];
		$force||=0;
		$force= $estimated ? 3 : 0 if $force==2;
		my $checklength= ($size1!=$size2 || $force==3) ? 2 : 0;
		return 1 unless $checklength || $force || $modif1!=$modif2;
		my $notagupdate_mode= $force!=3 && FileTag::Is_ReadOnly($file); #unless forced, files in ro mode won't update values from tags
		my $values= FileTag::Read($file,findlength=>$checklength, notags=> $notagupdate_mode);
		return unless $values;
		$values->{size}=$size2;
		$values->{modif}=$modif2;
		$values->{length_estimated}||=0 if $estimated;
		my @changed=$DIFFsub->($ID,$values,$notagupdate_mode);
		Changed([$ID],@changed) if @changed;
	}
	elsif (!$noremove)	#file not found
	{	warn "Can't find file '$file'\n";
		::SongsRemove([$ID]);
	}
}

#FIXME check if fields are enabled and add a way (option?) to silently ignore disabled fields
sub Set		#can be called either with (ID,[field=>newval,...],option=>val) or (ID,field=>newval,...);  ID can be an arrayref
{	warn "Songs::Set(@_) called from : ".join(':',caller)."\n" if $::debug;
	my ($IDs,$modif,%opt);
	if (ref $_[1])	{ ($IDs,$modif,%opt)=@_ }
	else		{ ($IDs,@$modif)=@_ }
	$IDs=[$IDs] unless ref $IDs;
	my %values;
	while (@$modif)
	{	my $f=shift @$modif;
		my $val=shift @$modif;
		my $multi;
		if ($f=~s/^([-+^])//) { $multi=$1 }
		my $def= $f=~m/^@(.*)$/ ? $Def{$1} : $Def{$f};
		if (!$def)	{ warn "Songs::Set : Invalid field $f\n";next }
		my $flags=$def->{flags};
		#unless ($flags=~m/e/) { warn "Songs::Set : Field $f cannot be edited\n"; next }
		#if (my $sub=$Def{$f}{check}))
		# { my $res=$sub->($val); unless ($res) {warn "Songs::Set : Invalid value '$v' for field $f\n"; next} }
		if ($multi)	#multi eq + or - or ^  => add or remove or toggle values (for labels and genres)
		{	if ($flags!~m/l/) { warn "Songs::Set : Field $f doesn't support multiple values\n"; next }
			elsif ($flags!~m/r/ && $flags=~m/w/) { warn "Songs::Set : Can't add/remove/toggle values of multi-value field $f because it is a write-only or read-on-demand field\n"; next }
			my $array=$values{"+$f"}||=[[],[],[]];	#$array contains [[toset],[torm],[toggle]]
			my $i= $multi eq '+' ? 0 : $multi eq '^' ? 2 : 1;
			$val=[$val] unless ref $val;
			$array->[$i]=$val;
		}
		else { $values{$f}=$val }
	}
	::setlocale(::LC_NUMERIC, 'C');
	my ($changed,$towrite)= $SETsub->($IDs,\%values);
	::setlocale(::LC_NUMERIC, '');
	Changed($IDs,$changed) if %$changed;
	Write($IDs,towrite=>$towrite,%opt);
}

sub UpdateTags
{	my ($IDs,$fields,%opt)=@_;
	Write($IDs,update=>$fields,%opt);
}

sub Write
{	my ($IDs,%opt)=@_; #%opt must have either update OR towrite
	my $update=$opt{update};   # [list_of_fields_to_update]
	my $towrite=$opt{towrite}; # [[modifs_for_first_ID],[...],...]

	if (!@$IDs || ($towrite && !@$towrite)) #nothing to do
	{	$opt{callback_finish}() if $opt{callback_finish};
		return
	}

	my $i=0; my $abort; my $skip_all;
	my $pid= ::Progress( undef, end=>scalar(@$IDs), abortcb=>sub {$abort=1}, widget =>$opt{progress}, title=>_"Writing tags");
	my $errorsub=sub
	 {	my ($syserr,$details)= FileTag::Error_Message(@_);
		my $abortmsg=$opt{abortmsg};
		$abortmsg||=_"Abort mass-tagging" if @$IDs>1;
		my $errormsg= $opt{errormsg} || _"Error while writing tag";
		$errormsg.= ' ('.($i+1).'/'.@$IDs.')' if @$IDs>1;
		my $res= $skip_all;
		$res ||= ::Retry_Dialog($syserr,$errormsg, ID=>$IDs->[$i], details=>$details, window=>$opt{window}, abortmsg=>$abortmsg, many=>(@$IDs-$i)>1);
		$skip_all=$res if $res eq 'skip_all';
		if ($res eq 'abort')
		{	$opt{abortcb}() if $opt{abortcb};
			$abort=1;
		}
		return $res;
	 };

	my $write_next= sub
	 {	my $ID= $IDs->[$i];
		if (defined $ID)
		{ 	my $modif;
			if ($update)
			{	for my $field (@$update)
				{	my $v= $Def{$field}{flags}=~m/l/ ? [Get_list($ID,$field)] : Get($ID,$field);
					push @$modif, $field,$v;
				}
			}
			elsif ($towrite)
			{	$modif=$towrite->[$i];
			}
			if ($modif)
			{	my $file= Songs::GetFullFilename($ID);
				FileTag::Write($file, $modif, $errorsub);
				warn "ID=$ID towrite : ".join(' ',@$modif)."\n" if $::debug;
				::IdleCheck($ID) unless $update; # not done in update mode
			}
		}
		$i++;
		if ($abort || $i>=@$IDs)
		{	::Progress($pid, abort=>1);
			$opt{callback_finish}() if $opt{callback_finish};
			return 0;
		}
		::Progress( $pid, current=>$i );
		return 1;
	 };
	 if ($opt{noidle}) { my $c=1; $c=$write_next->() until $c==0; } else { Glib::Idle->add($write_next); }
}

sub Changed	# 2nd arg contains list of changed fields as a list or a hash ref
{	my $IDs=shift || $::Library;
	my $changed= ref $_[0] ? $_[0] : {map( ($_=>undef), @_ )};
	warn "Songs::Changed : IDs=@$IDs fields=".join(' ',keys %$changed)."\n" if $::debug;
	$IDFromFile=undef  if $IDFromFile && !$KeepIDFromFile && (exists $changed->{file} || exists $changed->{path});
	$MissingHash=   undef if $MissingHash    && grep(exists $changed->{$_}, @MissingKeyFields);
	$MissingHash_ro=undef if $MissingHash_ro && grep(exists $changed->{$_}, @MissingKeyFields_ro);
	my @needupdate;
	for my $f (keys %$changed)
	{	if (my $l=$Def{$f}{_depended_on_by}) { push @needupdate, split / /,$l; }
	}
	for my $f (sort @needupdate)
	{	next if exists $changed->{$f};
		$changed->{$f}=undef;
		if (my $update=$UPDATEsub{$f}) { warn "Updating field : $f\n" if $::debug; $update->($IDs); }
	}
	AA::Fields_Changed($changed);
	::SongsChanged($IDs,[keys %$changed]);
}

sub CheckMissing
{	my $song=$_[0];

	# different rules for read-only files as you can only use fields that can't be edited: should still be the same in file and in gmb
	my $ro_mode= FileTag::Is_ReadOnly($song->{file});  # currently ony use the extension to determine if ro, so need to send path

	if (!$ro_mode)
	{	# fallback to ro_mode if fields too empty
		$ro_mode=1 unless defined $song->{title} && length $song->{title} && (defined $song->{album} || defined $song->{artist});
		for (qw/title album artist track/) { $song->{$_}="" unless defined $song->{$_} }
		$ro_mode=1 unless length ($song->{album} . $song->{artist});
		#ugly fix, clean-up the fields so they can be compared to those in library, depends on @MissingKeyFields #FIXME should generate a function using #check# and VAL=>'$song->{$field})'
		$song->{$_}=~s/\s+$// for qw/title album artist/;
		$song->{track}= $song->{track}=~m/^(\d+)/ ? $1+0 : 0;
	}

	my $IDs;
	if ($ro_mode)
	{	return unless $song->{modif} && $song->{size}; # unlikely, but make sure they are not 0
		my $key=join "\x1D", @$song{@MissingKeyFields_ro};
		$MissingHash_ro||= BuildHash('missingkey_ro',undef,undef,'id:list');
		$IDs= $MissingHash_ro->{$key};
	}
	else
	{	my $key=join "\x1D", @$song{@MissingKeyFields};
		$MissingHash||= BuildHash('missingkey',undef,undef,'id:list');
		$IDs= $MissingHash->{$key};
	}
	return unless $IDs;

	if (@$IDs>1) #too many candidates, try to find the best one
	{	my @score;
		for my $oldID (@$IDs)
		{	my $m=0;
			$m+=2 if $song->{file} eq Get($oldID,'file');
			$m++ if $song->{path} eq Get($oldID,'path');
			#could do more checks
			push @score,$m;
		}
		my $max= ::max(@score);
		@$IDs= map $IDs->[$_], grep $score[$_]==$max, 0..$#$IDs;
		if (@$IDs>1) #still more than 1, abort, maybe could continue anyway, the files must be nearly identical anyway
		{	warn "CheckMissing: more than 1 (".@$IDs.") possible matches for $song-->{path}/$song->{file}, assume identification is unreliable, considering it a new song.\n";
			return
		}
	}
	for my $oldID (@$IDs)
	{	my $wasmissing= Get($oldID,'missing');
		my $fullfilename= GetFullFilename($oldID);
		next if !$wasmissing && -e $fullfilename; #if candidate still exists
		warn "Found missing song, formerly '$fullfilename'\n";

		my $gid=Songs::Get_gid($oldID,'album');
		if (my $pic= Picture($gid,'album','get'))
		{	my $suffix= $pic=~s/(:\w+)$// ? $1 : '';
			unless (-e $pic)
			{	my $new;
				if ($pic eq $fullfilename) # check if cover is embedded picture in this file
				{	$new= ::catfile( $song->{path}, $song->{file} ).$suffix;
					warn "setting new picture $new\n";
				}
				else
				{	# if cover was in same folder or a sub-folder, check if there based on new folder
					$new=$pic;
					my $oldpath= ::pathslash(::dirname($fullfilename));
					my $newpath= ::pathslash($song->{path});
					$new=undef unless $new=~s#^\Q$oldpath\E#$newpath# && -e $new;
				}
				Picture($gid,'album','set',$new) if $new;
			}
		}

		#remove from MissingHash, not really needed
		#if (@$IDs>1) { $MissingHash->{$key}= [grep $_!=$oldID, @$IDs]; }
		#else { delete $MissingHash->{$key}; }

		#update $IDFromFile, and prevent its destruction in Changed(), not very nice #FIXME make hashes that update themselves when possible
		$KeepIDFromFile=1;
		$IDFromFile->{$song->{path}}{$song->{file}}= delete $IDFromFile->{Get($oldID,'path')}{Get($oldID,'file')} if $IDFromFile;

		Songs::Set($oldID,file=>$song->{file},path=>$song->{path}, missing=>0);
		$KeepIDFromFile=0;

		return $oldID,$wasmissing;
	}
	return
}
sub Makesub
{	my $c=&Code;	warn "Songs::Makesub(@_) called from : ".join(':',caller)."\n" unless $c;
	$c="local *__ANON__ ='Maksub(@_)'; $c" if $::debug;
	my $sub=eval "sub {$c}";
	if ($@) { warn "Compilation error :\n code : $c\n error : $@";}
	return $sub;
}
sub Stars
{	my ($gid,$field)=@_;
	return undef if !defined $gid || $gid eq '' || $gid==255;
	my $pb= $Def{$field}{pixbuf} || $Def{'rating'}{pixbuf};
	return $pb->[ sprintf("%d",$gid/100*$#$pb) ];
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
				{	my ($initsort,$sort)=SortCode($field,0,1,1);
					my $gid2get=Code($field, 'gid_to_get', GID => '$_');
					eval "sub { $initsort; [map( $gid2get, sort {$sort} $c)]}";
				}
				else {1}
			};
	return ref $func ? $func->() : [];
}
sub Get_grouptitle
{	my ($field,$IDs)=@_;
	($FuncCache{'grouptitle '.$field}||= Makesub($field, 'grouptitle', ID => '$_[0][0]', IDs=>'$_[0]') ) ->($IDs);
}
sub Search_artistid	#return artist id or undef if not found
{	my $artistname=shift;
	my $field='artist';
	($FuncCache{'search_gid '.$field}||= Makesub($field, 'search_gid', VAL=>'$_[0]') ) ->($artistname);
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
	my $func= $FuncCache{"icon_list $field"} ||= Compile("icon_list $field", MakeCode($field,'sub {my $theme=Gtk3::IconTheme::get_default; grep $theme->lookup_icon($_,32,[]), map #icon_for_gid#, @{#get_gid#}; }',ID=>'$_[0]', GID=>'$_'));	#FIXME simplify the code-making process
	return $func->($ID);
}
sub Gid_to_Display	#convert a gid from a Get_gid to a displayable value
{	my ($field,$gid)=@_; #warn "Gid_to_Display(@_)\n";
	my $sub= $Gid_to_display{$field} || DisplayFromGID_sub($field);
	if (ref $gid) { return [map $sub->($_), @$gid] }
	return $sub->($gid);
}
sub DisplayFromGID_sub
{	my $field=$_[0];
	return $Gid_to_display{$field}||= Makesub($field, 'gid_to_display', GID => '$_[0]');
}
sub DisplayFromHash_sub	 #not a good name, very specific, only used for $field=path currently
{	my $field=$_[0];
	return $FuncCache{"DisplayFromHash_sub $field"}||= Makesub($field, 'hash_to_display', VAL => '$_[0]');
}
sub MakeFilterFromGID
{	my ($field,$gid)=@_; #warn "MakeFilterFromGID:@_\n";#warn Code($field, 'makefilter', GID => '$_[0]');
	my $sub=$FuncCache{'makefilter '.$field}||= Makesub($field, 'makefilter', GID => '$_[0]');
warn "MakeFilterFromGID => ".($sub->($gid)) if $::debug;
	return Filter->new( $sub->($gid) );
}
sub MakeFilterFromID	#should support most fields, FIXME check if works for year/artists/labels/genres/...
{	my ($field,$ID)=@_;
	return Filter->null unless $ID;	# null filter if no ID
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
sub sort_gid_by_name
{	my ($field,$gids,$h,$pre,$mode)=@_;
	$mode||='';
	my $func= $FuncCache{"sortgid $field $mode"} ||= do
		{	my ($initsort,$sort)= SortCode($field,undef,1,1);
			$pre= $pre ? $HSort{$pre} : '';
			eval 'sub {my $l=$_[0]; my $h=$_[1]; '.$initsort.'; @$l=sort { '."$pre $sort".' } @$l}';
		};
	$func->($gids,$h);
}
sub Get_all_gids	#FIXME add option to filter out values eq ''
{	my $field=$_[0];
	return UniqList($field,$::Library,1); #FIXME use ___name directly
}

sub Get		# ($ID,@fields)
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
sub IsSet	# used only once
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
	my $h=BuildHash($field,$IDs,undef,':uniq');	#my $h=BuildHash($field,$IDs,'string',':uniq'); ??????
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
	{	my ($dir,$file)= ::splitpath(::simplify_path($f));
		if (defined $file)
		{	$IDFromFile||=Build_IDFromFile();
			return $IDFromFile->{$dir}{$file};
			#return $IDFromFile->{$dir}{$file} if $IDFromFile;
			#my $m=Filter->newadd(1,'file:e:'.$file, 'path:e:'.$dir)->filter_all;
			#if (@$m)
			#{	warn "Error, more than one ID match $dir/$file" if @$m>1;
			#	return $m->[0];
			#}
		}
		return undef;
	}
	$f=undef if $f>$LastID;
	return $f;
}

sub UpdateDefaultRating
{	my $l=AllFilter('rating:~:255');
	Changed($l,'rating') if @$l;
}
sub UpdateArtistsRE
{	CompileArtistsRE();
	Songs::Changed([FIRSTID..$LastID],'artist');
}
sub CompileArtistsRE
{	my $ref1= $::Options{Artists_split_re} ||= ['\s*&\s*', '\s*;\s*', '\s*,\s+', '\s*/\s*'];
	$Artists_split_re= join '|', @$ref1;
	$Artists_split_re||='$';
	$Artists_split_re=qr/$Artists_split_re/;

	my $ref2= $::Options{Artists_title_re} ||= ['\(with\s+([^)]+)\)', '\(feat\.\s+([^)]+)\)'];
	$Artists_title_re= join '|', @$ref2;
	$Artists_title_re||='^\x00$';
	$Artists_title_re=qr/$Artists_title_re/;
}

sub DateString
{	my $time=shift;
	my ($fmt,@formats)= split /(\d+) +/, $::Options{DateFormat}||"%c";
	unless ($time)
	{	return _"never";
	}
	my $diff=time-$time;
	while (@formats)
	{	my $max=shift @formats;
		last if $diff>$max;
		$fmt=shift @formats;
	}
	::strftime_utf8($fmt,localtime $time);
}

#sub Album_Artist #guess album artist
#{	my $alb= Get($_[0],'album');
#	my %h; $h{ Get($_[0],'artist') }=undef for @{AA::GetIDs('album',$alb)};
#	my $nb=keys %h;
#	return Get($_[0],'artist') if $nb==1;
#	my @l=map split(/$Artists_split_re/), keys %h;
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
	return if ::CreateDir($dir,undef,_"Error saving icon") ne 'ok';
	my $destfile= $dir. ::SLASH. ::url_escape( Picture($gid,$field,'icon') );
	unlink $destfile.'.svg',$destfile.'.png';
	if ($file eq '0') {}	#unset icon
	elsif ($file=~m/\.svg/i)
	{	$destfile.='.svg';
		::copy($file,$destfile.'.svg');
	}
	else
	{	$destfile.='.png';
		my $pixbuf= GMB::Picture::load($file,size=>-48); # -48 means it will be resized to 48x48 if wifth or height bigger than 48
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
{	Field_property($_[0],'rightalign') || 0;
}
sub PropertyFields
{	grep $Def{$_}{flags}=~m/p/, @Fields;
}
sub InfoFields
{	my %tree;
	for my $f (grep $Def{$_}{flags}=~m/p/, @Fields)
	{	my $cat= $Def{$f}{category}||'unknown';
		push @{ $tree{$cat} }, $f;
	}
	my @list;
	for my $cat ( sort { $Categories{$a}[1] <=> $Categories{$b}[1] } keys %tree )
	{	my $fields= $tree{$cat};
		push @list, $cat, $Categories{$cat}[0], [::superlc_sort(@$fields)];
	}
	return \@list;
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
sub Field_Edit_string
{	my $f=$_[0];
	return $Def{$f} && exists $Def{$f}{edit_string} ? $Def{$f}{edit_string} : ucfirst(::__x( _"Edit {field}",field=>Songs::FieldName($f)));
}
sub FieldName
{	my $f=$_[0];
	return $Def{$f} && exists $Def{$f}{name} ? $Def{$f}{name} : ::__x(_"Unknown field ({field})",field=>$f);
}
sub MainField
{	my $f=$_[0];
	return Songs::Code($f,'mainfield') || $f;
}
sub FieldWidth
{	my $f=$_[0];
	return $Def{$f} && $Def{$f}{width} ? $Def{$f}{width} : 100;
}
sub FieldEnabled	#check if a field is enabled
{	!! grep $_[0] eq $_, @Fields;
}
sub FieldList		#return list of fields, may be filtered by type and/or a key
{	my %args=@_; # args may be type=> 'flags' or 'rating'  true=> key_that_must_be_true
	my @l= @Fields;
	if (my $type=$args{type})
	{	@l= grep { ($Def{$_}{fieldtype} || $Def{$_}{type}) eq $type} @l; # currently type flags all have a type=>'flags' in %Def, but might change, so fieldtype can overide it
	}
	if (my $true=$args{true})
	{	@l= grep $Def{$_}{$true}, @l;
	}
	return @l;
}
sub FieldType	#currently used to check "flags" or "rating" types
{	my $field=shift;
	return '' unless grep $field eq $_, @Fields;
	return $Def{$field}{fieldtype} || $Def{$field}{type}; # currently fieldtype is not used but might be useful as $Def{$field}{type} is an implementation detail and not a field property
}
sub ListGroupTypes
{	my @list= grep $Def{$_}{can_group}, @Fields;
	my @ret;
	for my $field (@list)
	{	my $val=$field;
		my $name=FieldName($field);
		my $types=LookupCode($field,'subtypes_menu');
		if ($types)
		{	$val=[map( (qq($field.$_) => "$name ($types->{$_})"), keys %$types)];
		}
		push @ret, $val,$name;
	}
	return \@ret;
}
sub WriteableFields
{	grep  $Def{$_}{flags}=~m/a/ && $Def{$_}{flags}=~m/w/, @Fields;
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
sub ReplaceFields_to_re
{	my $string=shift;
	my $field= $::ReplaceFields{$string};
	if ($field && $Def{$field}{flags}=~m/e/)
	{	return $Def{$field}{_autofill_re} ||= '('. LookupCode($field, 'autofill_re') .')';
	}
	$string=~s#(\$\{\})#\\$1#; # escape $ and {}
	return $string;
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
sub MakeSortCode
{	my $sort=shift;
	my @code;
	my $init='';
	for my $s (split / /,$sort)
	{	my ($inv,$field,$i)= $s=~m/^(-)?(\w+)(:i)?$/;
		next unless $field;
		unless ($Def{$field}) { warn "Songs::SortList : Invalid field $field\n"; next }
		unless ($Def{$field}{flags}=~m/s/) { warn "Don't know how to sort $field\n"; next }
		my ($sortinit,$sortcode)= SortCode($field,$inv,$i);
		push @code, $sortcode;
		$init.= $sortinit."; " if $sortinit;
	}
	@code=('0') unless @code;
	return $init, join(' || ',@code);
}
sub FindNext	# find the song in listref that would be right after ID if ID was in the list #could be optimized by not re-evaluating left-side for every comparison
{	my ($listref,$sort,$ID)=@_;	# list must be sorted by $sort
	my $func= $FuncCache{"FindNext $sort"} ||=
	 do {	my ($init,$code)= MakeSortCode($sort);
		$code= 'sub {my $l=$_[0];$a=$_[1]; '.$init.'for $b (@$l) { return $b if (' . $code . ')<1; } return undef;}';
		Compile("FindNext $sort", $code);
	    };
	return $func->($listref,$ID);
}
sub FindFirst		#FIXME add a few fields (like 'disc track path file') to all sort so that the sort result is constant, ie doesn't depend on the starting order
{	my ($listref,$sort)=@_;
	my $func= $FuncCache{"FindFirst $sort"} ||=
	 do {	my ($init,$code)= MakeSortCode($sort);
		$code= 'sub {my $l=$_[0];$a=$l->[0]; '.$init.'for $b (@$l) { $a=$b if (' . $code . ')>0; } return $a;}';
		Compile("FindFirst $sort", $code);
	    };
	return $func->($listref);
}
sub SortList		#FIXME add a few fields (like 'disc track path file') to all sort so that the sort result is constant, ie doesn't depend on the starting order
{	my $time=times; #DEBUG
	my $listref=$_[0]; my $sort=$_[1];
	my $func= $FuncCache{"sort $sort"} ||=
	 do {	my ($init,$code)= MakeSortCode($sort);
		$code= 'sub { my $list=shift; ' .$init. '@$list= sort {'. $code . '} @$list; }';
		Compile("sort $sort", $code);
	    };
	$func->($listref) if $func;
	warn "sort ($sort) : ".(times-$time)." s\n" if $::debug; #DEBUG
}
sub SortDepends
{	my @f=split / /,shift;
	s/^-//,s/:i$// for @f;
	return [Depends(@f)];
}
sub ReShuffle
{	$Songs::SHUFFLE='';
}
sub update_shuffle
{	my $max=shift;
	my $length= defined $Songs::SHUFFLE ? length($Songs::SHUFFLE) : 0;
	my $needed= $max+1 - $length/4;
	if ($needed>0)
	{	my @append;
		$Songs::SHUFFLE.= pack 'L*', map rand(256**4), 1..$needed;
	}
}

sub Depends
{	my @fields=@_;
	my %h;
	for my $f (grep $_ ne '', @fields)
	{	$f=~s#[.:].*##;
		next unless $f;
		unless ($Def{$f}) {warn "Songs::Depends : Invalid field $f\n";next}
		$h{$f}=undef;
		if (my $d= $Def{$f}{depend}) { $h{$_}=undef for split / /,$d; }
	}
	#delete $h{none};
	return keys %h;
}

sub CopyFields			#copy values from one song to another
{	my ($srcfile,$dstfile,@fields)=@_;
	my $IDsrc=FindID($srcfile);
	my $IDdst=FindID($dstfile);
	unless (defined $IDsrc) { warn "CopyFields : can't find $srcfile in the library\n";return 1 }
	unless (defined $IDdst) { warn "CopyFields : can't find $dstfile in the library\n";return 2 }
	#FIXME could check fields
	warn "Copying fields '@fields' from '$srcfile' to '$dstfile'\n" if $::debug;
	my @vals=Get($IDsrc,@fields);
	Set($IDdst, map { $fields[$_]=>$vals[$_] } 0..$#fields);
	return 0;

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

my %buildhash_deprecated= (idlist=>'id:list',count=>'id:count',uniq=>':uniq');
sub BuildHash
{	my ($field,$IDs,$opt,@types)=@_; #warn "Songs::BuildHash(@_)\n";
	$opt= $opt? ':'.$opt : '';
	my ($keycode,$multi)= LookupCode($field, 'hash'.$opt.'|hash', 'hashm'.$opt.'|hashm',[ID => '$ID']);
	$keycode||=$multi;
	unless ($keycode || $multi) { warn "BuildHash error : can't find code for field $field\n"; return } #could return empty hashes ?
	my $init=	$keycode=~s/^\s*INIT:(.*?)\s+----\s+//	? "$1;" : '';
	my $keyafter=	$keycode=~s/----\s+AFTER:(.*)$//	? $1 :'';
	@types=('id:count') unless @types;

	my $after='';
	my $code;
	my $i;
	for my $type (@types)
	{	$i++;
		if ($buildhash_deprecated{$type}) { warn "BuildHash: using '$type' is deprecated, use '$buildhash_deprecated{$type}' instead\n" if ::VERSION>1.1009 || $::debug; $type=$buildhash_deprecated{$type}; }
		my ($f,$opt,$arg)=split /:/,$type,3;
		$arg=~y/-A-Z0-9:.,//cd if $arg;
		$opt= $opt ? 'stats:'.$opt : 'stats';
		$f||= 'id'; # mostly for :uniq but also :list and :count
		my $c= LookupCode($f, $opt, [ID=>'$ID', ($arg ? (ARG=>"'$arg'") : () )]);
		$c=~s/\$\$/'$V'.$i.'_'/ge;	# $$name  => $V5_name  if $i==5
		$init.=";$1;" if $c=~s/^\s*INIT:(.*?)\s+----\s+//;
		my $af= $c=~s/----\s+AFTER:(.*)$//		? $1 :'';
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
	$code= "my \$lref=\$_[0]; $init; my ($hlist);\n$code;\nreturn $hlistref;";

#warn "BuildHash($field $opt,@types)=>\n$code\n";
	my $sub= eval "sub { no warnings 'uninitialized'; $code }";
	if ($@) { warn "BuildHash compilation error :\ncode: $code\nerror: $@";}
	$IDs||=[FIRSTID..$LastID];
	$sub->( $IDs ); #returns one hash ref by @types
}

sub AllFilter
{	my $filter=$_[0];
	Filter->new($filter)->filter_all;
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

use constant { PF_NAME=>0, PF_ID=>1, PF_EDIT=>2, PF_ENABLE=>3, PF_DELETE=>4 };
sub PrefFields	#preference dialog for fields
{	my $store=Gtk3::TreeStore->new('Glib::String','Glib::String','Glib::Boolean','Glib::Boolean','Glib::Boolean');
	my $treeview=Gtk3::TreeView->new($store);
	$treeview->set_headers_visible(0);
	my $rightbox=Gtk3::VBox->new;
	my $renderer=Gtk3::CellRendererText->new;
	$treeview->append_column( Gtk3::TreeViewColumn->new_with_attributes
	 ( 'field name',$renderer,text => PF_NAME, 'editable' => PF_EDIT, sensitive=>PF_ENABLE, strikethrough => PF_DELETE,
	 ));

	my @fields= grep !$Def{$_}{template} && (!$Def{$_}{disable} || ($Def{$_}{options} && $Def{$_}{options}=~m/\bdisable\b/)), keys %Def;
	@fields= grep !$Def{$_}{property_of} && $Def{$_}{name} && $Def{$_}{flags}=~m/[pc]/, @fields;
	#add custom fields
	push @fields, grep $::Options{Fields_options}{$_}{template}, keys %{$::Options{Fields_options}};

	# create the field tree
	my %tree= (custom=>{}); #always show custom category, even if empty
	for my $field (@fields)
	{	my $opt= $::Options{Fields_options}{$field};
		my $custom= $opt->{template};
		my $cat= $custom ? 'custom' : $Def{$field}{category} || 'unknown';
		my $name= $custom ? $opt->{name} : $Def{$field}{name};
		$tree{$cat}{$field}=$name;
	}

	#fill the treestore
	my $custom_root;
	for my $cat ( sort { $Categories{$a}[1] <=> $Categories{$b}[1] } keys %tree )
	{	my $names= $tree{$cat};
		my $editable= $cat eq 'custom';
		my $parent= $store->append(undef);
		$store->set( $parent, PF_NAME,$Categories{$cat}[0], PF_ID,'+'.$cat, PF_ENABLE,::TRUE); # category node
		for my $field (::sorted_keys($names))
		{	my $opt= $::Options{Fields_options}{$field};
			my $def= $Def{$field};
			my $sensitive= exists $opt->{disable} ? !$opt->{disable} : $def->{disable} ? 0 : 1;
			$store->set( $store->append($parent), PF_NAME,$names->{$field}, PF_ID,$field, PF_EDIT,$editable, PF_ENABLE,$sensitive, PF_DELETE,$opt->{remove} ); #child
		}
		$custom_root= $store->get_string_from_iter($parent) if $cat eq 'custom';
	}
	$treeview->expand_all;

	$treeview->signal_connect(cursor_changed => sub
		{	my $treeview=shift;
			my $path=($treeview->get_cursor)[0];
			my $store=$treeview->get_model;
			my ($name,$field)=$store->get( $store->get_iter($path), PF_NAME,PF_ID );
			$rightbox->remove($_) for $rightbox->get_children;
			if ($field=~m/^\+/) {return} #row is a category
			return unless $field;
			my $title=Gtk3::Label->new_with_format("<b>%s</b>",$name);
			$rightbox->pack_start($title,::FALSE,::FALSE,2);
			my $box=Gtk3::VBox->new;
			::weaken( $box->{store}=$store );
			$box->{path}=$path;
			Field_fill_option_box($box,$field);
			$rightbox->add($box);
			$rightbox->show_all;
		});
	$renderer->signal_connect(edited => sub
	    {	my ($cell,$pathstr,$newname)=@_;
		my $iter= $store->get_iter_from_string($pathstr);
		my ($oldname,$field)= $store->get($iter,PF_NAME,PF_ID);
		if ($newname eq '')
		{	$store->remove($iter) if $oldname eq '';
			$treeview->set_cursor(Gtk3::TreePath->new($custom_root));
			return;
		}
		if ($field eq '')
		{	$field= validate_custom_field_name($newname,1);
			$::Options{Fields_options}{$field} = { template => 'string', name => $newname, };
			#$Def{$field}= { template => 'string', options => $FieldTemplates{string}{options}, category=>'custom', name=>$newname };
		}
		$::Options{Fields_options}{$field}{name}= $newname;
		$store->set($iter, PF_NAME,$newname, PF_ID,$field);
		$treeview->set_cursor($store->get_path($iter));
	    });

	my $newcst=::NewIconButton('gtk-add', _"New custom field", sub
		{	my $iter=$store->append($store->get_iter_from_string($custom_root));
			$store->set($iter,PF_NAME,'',PF_ID,'',PF_EDIT,::TRUE, PF_ENABLE,::TRUE);
			my $path=$store->get_path($iter);
			$treeview->expand_to_path($path);
			$treeview->set_cursor($path, $treeview->get_column(0), ::TRUE);
		} );
	my $warning=Gtk3::Label->new;
	$warning->set_markup('<b>'.::PangoEsc(_"Settings on this page will only take effect after a restart").'</b>');
	my $sw=Gtk3::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($treeview);
	my $vbox= ::Vpack( $warning, '_',[ ['0_',$sw,$newcst], '_', $rightbox ] );

	$vbox->{gotofunc}=sub	#go to a specific row
	{	my $field=shift;
		my $parent= $store->get_iter_first;
		while ($parent)
		{	my $child= $store->iter_children($parent);
			while ($child)
			{	if ($store->get($child,PF_ID) eq $field) { $treeview->set_cursor($store->get_path($child)); return; }
				$child= $store->iter_next($child);
			}
			$parent= $store->iter_next($parent);
		}
	};

	return $vbox;
}

sub validate_custom_field_name
{	my ($field,$fallback)=@_;
	$field=~s/[^a-zA-Z0-9_]//g;  $field=~s/^\d+//; $field=~s/_+/_/g; $field=~s/_$//; # custom field id restrictions, might be relaxed in the future
	$field= ucfirst $field if $field=~m/^[a-z]/;
	my %used;
	$used{$_}=undef for keys %Def;
	$used{$Def{$_}{_renamed_to}}=undef for grep $Def{$_}{_renamed_to}, keys %Def;
	if (!$field || $field eq '' || exists $used{$field})
	{	return unless $fallback;
		$field= 'Custom' if $field eq '';
		::IncSuffix($field) while $used{$field};
	}
	return $field;
}

our %Field_options_aliases=
(	customfield	=> 'template convwarn disable remove datawarn',
	rw_		=> 'rw resetnotag',
	stars		=> 'starprefix starpreview',
);
our %Field_options=
(	#bits	=>
	#{	widget		=> 'combo',
	#	combo		=> { 32 => "32 bits", 16 => "16 bits", },
	#	'default'	=> 32,
	#},
	rw	=>
	{	widget		=> 'check',
		label		=> _"Read/write in file tag",
		'default'	=> sub		#extract rw (sorted) from default flags
		{		my $default_flags= $_[0]{flags} || '';
				$default_flags=~tr/rw//dc;
				return join '', sort split //, $default_flags;
		},
		apply		=> sub
		{		my ($def,$opt,$value)=@_;
				$def->{flags}=~s/[rw]//g;
				$def->{flags}.='rw' if $value;
		},
	},
	editable =>
	{	widget		=> 'check',
		label		=> _"Editable in song properties dialog",
		'default'	=> sub { my $default= $_[0]{flags} || ''; return $default=~m/e/ },
		apply		=> sub { my ($def,$opt,$value)=@_; $def->{flags}=~s/e//g; $def->{flags}.='e' if $value; },
	},
	resetnotag =>
	{	widget		=> 'check',
		label		=> _"Reset current value if no tag found in file",
		'default'	=> sub { my $default= $_[0]{flags} || ''; return $default!~m/_/ },
		apply		=> sub { my ($def,$opt,$value)=@_; $def->{flags}=~s/_//g; $def->{flags}.='_' if !$value; },
		update		=> sub { $_[0]{widget}->set_sensitive( $_[0]{opt}{rw} ); }, # set insensitive when tag not read/written
	},
	starprefix	=>
	{	label		=> _"Star images",
		widget		=> 'combo',
		combo		=> \&::Find_all_stars,
		tip		=> ::__x(_"You can make custom stars by putting pictures in {folder}\nThey must be named 'stars', optionally followed by a '-' and a word, followed by a number from 0 to 5 or 10\nExample: stars-custom0.png",folder=>$::HomeDir.'icons'),
	},
	starpreview	=>
	{	widget => sub
		{	my @img= map Gtk3::Image->new, 0..2;
			my $box= ::Hpack('-',reverse @img);
			$box->{img}=\@img;
			return $box;
		},
		update => sub
		{	my $arg=shift;
			my @files= ::Find_star_pictures($arg->{opt}{starprefix});
			my $img= $arg->{widget}{img};
			my @pix= map GMB::Picture::pixbuf($files[$_]), 0,int($#files/2),$#files;
			$img->[$_]->set_from_pixbuf($pix[$_]) for 0..2;
		},
	},
	editsubmenu	=>
	{	widget		=> 'check',
		label		=> _"Show edition submenu in song context menu",
	},
	samemenu	=>
	{	widget		=> 'check',
		label		=> _"Show menu items to find songs with same value",
	},
	disable	=>
	{	widget		=> 'check',
		label		=> _"Disabled",
	},
	remove	=>
	{	widget		=> 'check',
		label		=> _"Remove this field",
	},
	convwarn =>
	{	widget		=> 'label',
		label		=> _"Warning: converting existing data to this format may be lossy",
		update		=> sub			# show only when field to be disabled or removed
		{		my $arg=shift;
				my $show= $arg->{opt}{currentid} && ( $arg->{opt}{template} ne $Def{$arg->{opt}{currentid}}{template} );
				my $w= $arg->{widget};
				$w->set_visible($show);
				$w->set_no_show_all(1);
		},
	},
	datawarn =>
	{	widget		=> 'label',
		label		=> _"Warning: all existing data for this field will be lost",
		update		=> sub			# show only when field to be disabled or removed
		{		my $arg=shift;
				my $opt=$arg->{opt};
				my $show= $opt->{currentid} && ($opt->{disable} || $opt->{remove} );
				my $w= $arg->{widget};
				$w->set_visible($show);
				$w->set_no_show_all(1);
		},
	},
	useridwarn =>
	{	widget		=> 'label',
		label		=> _"Warning: an identifier is needed",
		update		=> sub
		{		my $arg=shift;
				my $show= $arg->{opt}{rw} && (!$arg->{opt}{userid} || $arg->{opt}{userid}=~m/^ *$/);
				my $w= $arg->{widget};
				$w->set_visible($show);
				$w->set_no_show_all(1);
		},
	},
	userid	=>
	{	widget		=> 'entry',
		label		=> _"Identifier in file tag",
		tip		=> _"Used to associate the saved value with a user or a function",
		update		=> sub { $_[0]{widget}->get_parent->set_sensitive( $_[0]{opt}{rw} ); }, # set insensitive when tag not read/written
	},
	template=>
	{	widget		=> \&Field_Edit_template,
		label		=> _"Field type",
	},
	persistent_values=>
	{	label		=> _("Persistent values").':',
		tip		=> _"These values will always be in the list, even if they are not used",
		default		=> sub { $_[0]{default_persistent_values} },
		widget		=> sub
		{		my (undef,$opt,$field)=@_;
				my $values= FieldType($field) eq 'flags' ? ListAll($field) : []; # check that field is live and live with correct type, else ListAll will not work
				my %valuesh; $valuesh{$_}=$_ for @$values;
				::NewPrefMultiCombo(persistent_values=>\%valuesh,opthash=>$opt,ellipsize=>'end');
		},
	},
	show_ext =>
	{	label		=> _"Show file name extension",
		widget		=> 'check',
	},
);

sub Field_fill_option_box
{	my ($vbox,$field, $keep_option, @keep_widgets)=@_;
	$_->get_parent->remove($_) for @keep_widgets;
	$vbox->remove($_) for $vbox->get_children;

	my $opt= $::Options{Fields_options}{$field} ||= {};
	#$vbox->{opt_orig}={%$opt};	#warning : shallow copy, sub-hash/array stay linked
	$vbox->{field}=$field;

	my $template=$opt->{template};
	my $def= $Def{$field};
	my $option_list= ($template ? $FieldTemplates{$template}{options} : $def->{options}) ||'';
	my $flags=	 ($template ? $FieldTemplates{$template}{flags} :   $def->{flags})   ||'';

	my $sg1=Gtk3::SizeGroup->new('horizontal');
	my %widgets; my @topack;
	$vbox->{FieldProperties}=1; #used to get back to $vbox from one of its (grand)child
	$vbox->{widget_hash}=\%widgets;
	my @options= split /\s+/, $option_list;
	while (my $option=shift @options)
	{	if (my $o=$Field_options_aliases{$option})
		{	unshift @options,split /\s+/,$o;
			next;
		}
		my $ref=$Field_options{$option};
		next unless $ref;
		my $label=  $ref->{label};
		my $widget= $ref->{widget};
		my $key= $ref->{editkey} || $option;
		my $base= $template ? $FieldTemplates{$template} : $def;
		my $value= exists $opt->{$key} ? $opt->{$key} : Field_option_default($field,$option,$base);
		my @extra;
		if ($keep_option && $keep_option eq $option) { ($widget,@extra)= @keep_widgets;  }
		elsif (ref $widget)
		{	($widget,@extra) = $widget->( $vbox, $opt, $field );
		}
		elsif ($widget eq 'check')
		{	$widget= Gtk3::CheckButton->new($label);
			undef $label;
			$widget->set_active($value);
			$widget->signal_connect(toggled => sub { $opt->{$key}= $_[0]->get_active ? 1 : 0; &Field_Edit_update });
		}
		elsif ($widget eq 'entry')
		{	$widget= Gtk3::Entry->new;
			$widget->set_text($value);
			$widget->signal_connect(changed => sub { my $t=$_[0]->get_text; if ($t=~m/^\s*$/) {delete $opt->{$key};} else {$opt->{$key}=$t;} &Field_Edit_update });
		}
		elsif ($widget eq 'combo')
		{	$widget= TextCombo->new( $ref->{combo}, $value, sub { $opt->{$key}=$_[0]->get_value; &Field_Edit_update });
		}
		elsif ($widget eq 'label')
		{	$widget= Gtk3::Label->new($label);
			undef $label;
		}
		next unless $widget;
		my $tip= $ref->{tip};
		$widget->set_tooltip_text($tip) if defined $tip;

		$widgets{$option}=$widget;

		if (defined $label)
		{	$label= Gtk3::Label->new($label);
			$sg1->add_widget($label);
			$widget= [ $label, '_',$widget ];
		}
		push @topack, $widget,@extra;
	}

	if ($flags=~m/g/)
	{	my @idlist= sort grep $Aliases{$_} eq $field, keys %Aliases;
		my $varnames= join ', ',map '$'.$_, @idlist;
		$varnames.=', %'.$def->{letter} if $def->{letter};
		my $label_var=    _("Can be used as a variable with :").' '.$varnames;
		my $label_search= _("Can be searched with :").' '.join(', ',@idlist);
		$_= Gtk3::Label->new($_) for $label_var,$label_search;
		$_->set_selectable(1) , $_->set_alignment(0,.5) , $_->set_line_wrap(1) for $label_var,$label_search;
		unshift @topack, $label_var if $varnames;
		unshift @topack, $label_search if @idlist && $flags=~m/f/;
	}
	unshift @topack, Gtk3::Label->new( $def->{desc} ) if $def->{desc};

	{	my $hbox= Gtk3::HBox->new;
		my $label1= Gtk3::Label->new(_("Field identifier").':');
		my $label_id= Gtk3::Label->new($field);
		$hbox->pack_start($_,0,0,2) for $label1,$label_id;
		if ($template) #custom fields can be renamed
		{	my $entry= Gtk3::Entry->new;
			my $bedit= Gtk3::Button->new(_"Edit");
			my $brename= Gtk3::Button->new(_"Rename");
			my $bcancel= Gtk3::Button->new(_"Cancel");
			$hbox->pack_start($_,0,0,2) for $entry,$bedit,$brename,$bcancel;
			my @edit=($entry,$brename,$bcancel);
			$hbox->{edit}= \@edit;
			$_->set_no_show_all(1) for @edit;
			$hbox->{noedit}= [$label_id,$bedit];
			$hbox->{entry}= $entry;
			$hbox->{brename}= $brename;
			$hbox->{label_id}= $label_id;
			my $toggle_edit=sub
			{	my ($button,$on)=@_;
				my $hbox= $button->get_parent;
				$_->set_visible($on) for @{$hbox->{edit}};
				$_->set_visible(!$on) for @{$hbox->{noedit}};
				my $vbox=$button; $vbox=$vbox->get_parent until $vbox->{FieldProperties};
				$hbox->{entry}->set_text($vbox->{field});
			};
			$entry->signal_connect(changed => sub { my $t= validate_custom_field_name($_[0]->get_text); $_[0]->get_parent->{newid}=$t; $_[0]->get_parent->{brename}->set_sensitive($t && $t ne $field); });
			$bedit->signal_connect(clicked=> $toggle_edit,1);
			$bcancel->signal_connect(clicked=> $toggle_edit,0);
			$brename->signal_connect(clicked=> sub
			 {	my $button=shift;
				my $new=$button->get_parent->{newid};
				$::Options{Fields_options}{$new}= delete($::Options{Fields_options}{$field});
				if (my $id=$::Options{Fields_options}{$new}{currentid})
				{	$Def{$id}{_renamed_to}=$new;
				}
				my $vbox=$button; $vbox=$vbox->get_parent until $vbox->{FieldProperties};
				$vbox->{field}= $new;
				$button->get_parent->{label_id}->set_text($new);
				$toggle_edit->($button,0);
				Field_Edit_update($vbox);
			 });
		}
		unshift @topack, $hbox;
	}

	if (!$widgets{rw})
	{	my $text= $flags=~m/rw/ ? _"Value written in file tag" :
			  $flags!~m/[rw]/ ? _"Value not written in file tag" :
			  undef;
		$text=undef if $field eq 'path' || $field eq 'file';
		unshift @topack, Gtk3::Label->new_with_format( '<small>%s</small>', $text ) if $text;
	}

	$vbox->add( ::Vpack(@topack) );
	$vbox->show_all;
	$vbox->{skip_update_row}=1;
	Field_Edit_update($vbox);
	delete $vbox->{skip_update_row};
}

sub Field_Edit_update
{	my $vbox=shift;
	$vbox=$vbox->get_parent until $vbox->{FieldProperties};
	my $field= $vbox->{field};
	my $opt= $::Options{Fields_options}{$field} ||= {};
	my $widgets= $vbox->{widget_hash};
	for my $option (sort keys %$widgets)
	{	my $update= $Field_options{$option}{update};
		next unless $update;
		$update->({ vbox=>$vbox, opt=>$opt, field=>$field, widget=>$widgets->{$option}, });
	}
	return if $vbox->{skip_update_row}; #skip updating treestore, as not needed and cause issues with row-editing not ending, not sure why
	my $store= $vbox->{store};
	my $sensitive= (exists $opt->{disable} ? $opt->{disable} : ($Def{$field} && $Def{$field}{disable})) ? 0 : 1;
	my $iter= $store->get_iter($vbox->{path});
	$store->set( $iter, PF_ENABLE, $sensitive, PF_DELETE, $opt->{remove});
	$store->set( $iter, PF_NAME,$opt->{name}, PF_ID,$field) if $opt->{template}; #only for custom fields
}

sub Field_Edit_template
{	my ($vbox,$opt,$field)=@_;
	my %templatelist;
	$templatelist{$_}= $FieldTemplates{$_}{editname} for keys %FieldTemplates;
	my $label= Gtk3::Label->new;
	my $combo= TextCombo->new(\%templatelist, $opt->{template}, sub
		{	my $combo=shift;
			my $t=$opt->{template}= $combo->get_value;
			$Def{$field}{options}= $FieldTemplates{$t}{options};
			my $focus= $combo->is_focus; #FIXME never true
			my $vbox=$combo; $vbox=$vbox->get_parent until $vbox->{FieldProperties};
			Field_fill_option_box($vbox,$field, template=>$combo,$label); # will reset the option box but keep $combo and $label
			$combo->grab_focus if $focus;	#reparenting $combo will make it lose focus, so regrab it #FIXME $focus never true
			my $desc= $FieldTemplates{$t}{desc};
			if ($desc) {$label->set_markup_with_format("<small><i>%s</i></small>",$desc);$label->show} else {$label->hide}
		});
	$label->set_no_show_all(1);
	my $desc= $FieldTemplates{$opt->{template}}{desc};
	if ($desc) {$label->set_markup_with_format("<small><i>%s</i></small>",$desc);$label->show}
	return $combo,$label;
}

sub Field_Apply_options
{	for my $field (keys %{ $::Options{Fields_options} })
	{	my $opt= $::Options{Fields_options}{$field};
		if ($opt->{remove}) { delete $::Options{Fields_options}{$field}; next; }
		my $def= $Def{$field};
		if (!$def || $def->{template})
		{	my $template=$opt->{template};
			next unless $template;	# could remove options of removed standard fields ?
			my $hash= $FieldTemplates{$template};
			next unless $hash;
			$def=$Def{$field}= { %$hash, name=>$opt->{name} }; #shallow copy of the template hash
			$opt->{currentid}=$field;
		}
		my @options= split /\s+/, $def->{options}||'';
		while (my $option=shift @options)
		{	if (my $o=$Field_options_aliases{$option})
			{	unshift @options,split /\s+/,$o;
				next;
			}
			my $ref=$Field_options{$option};
			next unless $ref;

			my $key= $ref->{editkey} || $option;
			my $value= exists $opt->{$key} ? $opt->{$key} : Field_option_default($field,$option,$def);
			if (my $apply= $ref->{apply}) { $apply->($def,$opt,$value) }
			else
			{	$def->{$key}= $value;
			}
		}
	}
}

sub Field_option_default
{	my ($field,$option,$def)=@_;
	my $ref=$Field_options{$option};
	my $default= $ref->{'default'};
	if (defined $default) { $default= $default->($def, $field) if ref $default; }
	else
	{	my $key= $ref->{editkey} || $option;
		$default= $def->{$key};
		$default='' unless defined $default;
	}
	return $default;
}

sub FMPS_rating_postread
{	my $v=shift;
	length $v && $v=~m/^\d*\.?\d+$/ ? sprintf('%d',$v*100) : undef;
}
sub FMPS_rating_prewrite
{	my $v=shift;
	($v eq '' || $v>100) ? '' : sprintf('%.6f', $v/100);
	# write a rating of '' when no rating rather than undef, so that the tag is still written (undef would remove the tag)
	# this allows us to distinguish "default rating" from "rating never written".
	# without this, it would not be possible to remove the rating (ie: set it to "default rating") when the option resetnotag is off
}


package AA;
our (%GHash,%GHash_Depend);

our %ReplaceFields=
(	'%'	=>	sub {'%'},
	a	=>	sub { my $s=Songs::Gid_to_Display($_[0],$_[1]); defined $s ? $s : $_[1]; }, #FIXME PHASE1 Gid_to_Display should return something $_[1] if no gid_to_display
	l	=>	sub { my $l=Get('length:sum',$_[0],$_[1]); $l=::__x( ($l>=3600 ? _"{hours}h{min}m{sec}s" : _"{min}m{sec}s"), hours => (int $l/3600), min => ($l>=3600 ? sprintf('%02d',$l/60%60) : $l/60%60), sec => sprintf('%02d',$l%60)); },
	L	=>	sub { ::CalcListLength( Get('id:list',$_[0],$_[1]),'length:sum' ); }, #FIXME is CalcListLength needed ?
	y	=>	sub { Get('year:range',$_[0],$_[1])||''; },
	Y	=>	sub { my $y=Get('year:range',$_[0],$_[1]); return $y? " ($y)" : '' },
	s	=>	sub { my $l=Get('id:list',$_[0],$_[1])||[]; ::__n('%d song','%d songs',scalar @$l) },
	x	=>	sub { my $nb=@{GetXRef($_[0],$_[1])}; return $_[0] ne 'album' ? ::__("%d Album","%d Albums",$nb) : ::__("%d Artist","%d Artists",$nb);  },
	X	=>	sub { my $nb=@{GetXRef($_[0],$_[1])}; return $_[0] ne 'album' ? ::__("%d Album","%d Albums",$nb) : $nb>1 ? ::__("%d Artist","%d Artists",$nb) : '';  },
	b	=>	sub {	if ($_[0] ne 'album') { my $nb=@{GetXRef($_[0],$_[1])}; return ::__("%d Album","%d Albums",$nb); }
				else
				{	my $l=Songs::UniqList('artist', Get('id:list',$_[0],$_[1]));
					return @$l==1 ? Songs::Gid_to_Display('artist',$l->[0]) : ::__("%d artist","%d artists", scalar(@$l));
				}
			    },
);

sub ReplaceFields
{	my ($gid,$format,$col,$esc)=@_;
#my $u;$u=$format; #DEBUG DELME
	$format=~s#(?:\\n|<br>)#\n#g;
	if($esc){ $format=~s/%([alLyYsxXb%r])/::PangoEsc($ReplaceFields{$1}->($col,$gid))/ge; }
	else	{ $format=~s/%([alLyYsxXb%r])/$ReplaceFields{$1}->($col,$gid)/ge; }
#warn "ReplaceFields $gid : $u => $format\n" if defined $u; #DEBUG DELME
	return $format;
}

sub CreateHash
{	my ($type,$field)=@_; warn "AA::CreateHash(@_)\n" if $::debug;
	$GHash_Depend{$_}++ for Songs::Depends($type,$field);
	return $GHash{$field}{$type}=Songs::BuildHash($field,$::Library,undef,$type);
}
sub Fields_Changed
{	my $changed=shift; #hashref with changed fields as keys
	return unless grep $AA::GHash_Depend{$_}, keys %$changed;
	undef %GHash_Depend;
	delete $GHash{$_} for keys %$changed;
	for my $field (keys %GHash)
	{	my @d0=Songs::Depends($field);
		if (grep exists $changed->{$_}, @d0)
		{	delete $GHash{$field};
			next;
		}
		my $subh=$GHash{$field};
		for my $type (keys %$subh)
		{	my @d= Songs::Depends($type);
			if (grep exists $changed->{$_}, @d) { delete $subh->{$type} }
			else { $GHash_Depend{$_}++ for @d0,@d; }
		}
	}
}
sub IDs_Changed	#called when songs are added/removed
{	undef %GHash_Depend;
	undef %GHash;
	warn "IDs_Changed\n" if $::debug;
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
	CreateHash('id:list',$field) unless $GHash{$field};
	my ($h)= values %{$GHash{$field}};
	return [keys %$h];
}

sub GetXRef # get albums/artists from artist/album
{	my ($field,$key)=@_;
	my $x= $field eq 'album' ? 'artists:gid' : 'album:gid';
	return Get($x,$field,$key) || [];
}
sub GetIDs
{	return Get('id:list',@_) || [];
}

sub GrepKeys
{	my ($field,$string,$is_regexp,$is_casesens,$list)=@_;
	$list||=GetAAList($field);
	return [@$list] unless length $string;	# m// use last regular expression used
	$string=quotemeta $string unless $is_regexp;
	my $re= $is_casesens ? qr/$string/ : qr/$string/i;
	my $displaysub=Songs::DisplayFromGID_sub($field);
	my @l=grep $displaysub->($_)=~m/$re/i, @$list;	#FIXME optimize ?
	return \@l;
}

sub SortKeys
{	my ($field,$list,$mode,$hsongs)=@_;
	my $invert= $mode && $mode=~s/^-//;
	my $h=my $pre=0;
	$mode||='';
	if ($mode eq 'songs')
	{	$h= $hsongs || GetHash('id:count',$field);
		$pre='number';
	}
	elsif ($mode eq 'length')
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
	elsif ($mode eq 'artist') #only for albums
	{	$h= GetHash('album:artistsort',$field);
		$pre='string';
	}
	Songs::sort_gid_by_name($field,$list,$h,$pre,$mode);
	@$list=reverse @$list if $invert;
	return $list;
}

sub GuessBestCommonFolder
{	my ($field,$gid)=@_;
	my $IDs= AA::GetIDs($field,$gid);
	return unless @$IDs;
	my $h= Songs::BuildHash('path',$IDs);
	my $min=int(.1*::max(values %$h)); #ignore rare folders
	my $path= ::find_common_parent_folder( grep $h->{$_}>$min,keys %$h );
	($path)=sort { $h->{$b} <=> $h->{$a} } keys %$h if length $path<5;#take most common if too differents
	return $path;
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

INIT
{ ::Watch(undef, SongsRemoved	=> sub { RemoveFromArrays($_[1],\@list_of_SongArray); });
}

sub DESTROY
{	my $self=$_[0];
	@list_of_SongArray= grep defined, @list_of_SongArray;
	::weaken($_) for @list_of_SongArray;
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
	for my $l (@need_update)
	{	@$l= grep $_,map $newIDs->[$_], @$l; #IDs start at 1, removed songs get ID=undef and are then removed by the grep $_
	}
	$init=undef; @need_update=undef;
}
sub build_presence
{	my $self=$_[0];
	my $s=''; vec($s,$_,1)=1 for @$self;
	$Presence{$self}=$s,
}
sub IsIn
{	my ($self,$ID)=@_;
	return undef unless defined $ID;
	$self->build_presence unless $Presence{$self};
	vec($Presence{$self},$ID,1);
}
sub AreIn
{	my ($self,$IDs)=@_;
	$self->build_presence unless $Presence{$self};
	return [grep defined && vec($Presence{$self},$_,1), @$IDs];
}
sub save_to_string
{	return join ' ',map $_, @{$_[0]};	#map $_ so that the numbers are not stringified => use more memory
}

sub GetName {undef}

sub RemoveFromArrays		#could probably be improved
{	my ($IDs_toremove,$list_of_arrays)=@_;
	$list_of_arrays ||= \@list_of_SongArray;
	my $isin='';
	vec($isin,$_,1)=1 for @$IDs_toremove;
	for my $self (grep defined, @$list_of_arrays)
	{	my @rows=grep vec($isin,$self->[$_],1), 0..$#$self;
		$self->Remove(\@rows,'removeIDsfromall') if @rows;
	}
}

sub RemoveIDs
{	my ($self,$IDs_toremove)=@_;
	my $isin='';
	vec($isin,$_,1)=1 for @$IDs_toremove;
	my @rows=grep vec($isin,$self->[$_],1), 0..$#$self;
	$self->Remove(\@rows) if @rows;
}

sub Sort
{	my ($self,$sort)=@_;
	my @old=@$self;
	Songs::SortList($self,$sort);
	::HasChanged('SongArray',$self,'sort',$sort,\@old);
}
sub SetSortAndFilter
{	my ($self,$sort,$filter)=@_;
	my $list=$filter->filter;
	Songs::SortList($list,$sort) if $sort;
	$self->Replace($list);
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
sub Shuffle
{	my $self=shift;
	my @rand;
	push @rand,rand for 0..$#$self;
	$self->Replace([map $self->[$_], sort { $rand[$a] <=> $rand[$b] } 0..$#$self]);
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

package SongArray::Named;
use base 'SongArray';
#just used to easily test if a songarray is a savedlist

sub GetName
{	my $self=$_[0];
	my $sl=$::Options{SavedLists};
	my ($name)= grep $sl->{$_}==$self, keys %$sl;
	return $name;	#might be undef
}

package SongArray::AutoUpdate;
use base 'SongArray';
our %Filter;
our %Sort;
our %needupdate;
my @list_of_AutoUpdate;

INIT
{ ::Watch(undef, SongsChanged	=> \&SongsChanged_cb);
  ::Watch(undef, SongsAdded	=> \&SongsAdded_cb);
  ::Watch(undef, SongsHidden	=> sub { SongArray::RemoveFromArrays($_[1],\@list_of_AutoUpdate); });
}

sub new
{	my ($class,$auto,$sort,$filter)=@_;
	if (!defined $filter)	{$filter=Filter->null}
	elsif (!ref $filter)	{$filter=Filter->new($filter)}
	my $list= $filter->filter;
	Songs::SortList($list,$sort) if @$list && $sort;
	my $self = $class->SUPER::new([@$list]);
	$Sort{$self}=$sort;
	$Filter{$self}=$filter;
	if ($auto)
	{	push @list_of_AutoUpdate,$self;
		::weaken($list_of_AutoUpdate[-1]);
	}
	return $self;
}
sub DESTROY
{	my $self=$_[0];
	delete $Filter{$self};
	delete $Sort{$self};
	delete $needupdate{$self};
	@list_of_AutoUpdate= grep defined, @list_of_AutoUpdate;
	::weaken($_) for @list_of_AutoUpdate;
	$self->SUPER::DESTROY;
}
sub SetAutoUpdate
{	my ($self,$auto)=@_;
	@list_of_AutoUpdate= grep $self!=$_, @list_of_AutoUpdate;
	push @list_of_AutoUpdate,$self if $auto;
	::weaken($_) for @list_of_AutoUpdate;
	if ($auto)
	{	my $list= $Filter{$self}->filter;
		Songs::SortList($list,$Sort{$self});
		my @old=@$self;
		@$self=@$list;
		::HasChanged('SongArray',$self,'update',\@old);
	}
	else { ::HasChanged('SongArray',$self,'mode'); }
}
sub Sort
{	my ($self,$sort)=@_;
	$Sort{$self}=$sort;
	$self->SUPER::Sort($sort);
}
sub SetSortAndFilter
{	my ($self,$sort,$filter)=@_;
	$Filter{$self}=$filter;
	$Sort{$self}=$sort;
	my $list=$filter->filter;
	Songs::SortList($list,$sort);
	$self->Replace($list);
}

sub SongsAdded_cb
{	my (undef,$IDs)=@_;
	for my $self (grep defined, @list_of_AutoUpdate)
	{	next if ($needupdate{$self}||0)>1;
		my $filter=$Filter{$self};
		my ($greponly)=$filter->info;
		if ($greponly)
		{	my $toadd=$filter->filter($IDs);
			if ($toadd)
			{	my @old=@$self;
				push @$self,@$toadd;
				if ($Presence{$self}) {vec($Presence{$self}, $_, 1)=1 for @$IDs;}
				Songs::SortList($self,$Sort{$self});
				::HasChanged('SongArray',$self,'update',\@old);
			}
		}
		else
		{	$needupdate{$self}=2;
			::IdleDo('7_autoupdate_update'.$self,6000, \&delayed_update_cb,$self);
		}
	}
}
sub delayed_update_cb
{	my $self=shift;
	my $need= delete $needupdate{$self};
	return unless $need;
	if ($need>1) { $self->_update_full }
	else
	{	my @old=@$self;
		Songs::SortList($self,$Sort{$self});
		if ("@old" ne "@$self") #only update if there was a change
		{	::HasChanged('SongArray',$self,'update',\@old);
		}
	}
}
sub _update_full
{	my $self=shift;
	delete $needupdate{$self};
	my @old=@$self;
	my $list=$Filter{$self}->filter;
	Songs::SortList($list,$Sort{$self});
	@$self=@$list;
	delete $Presence{$self};
	::HasChanged('SongArray',$self,'update',\@old);
}
sub SongsChanged_cb
{	my (undef,$IDs,$fields)=@_;
	for my $self (grep defined, @list_of_AutoUpdate)
	{	next if ($needupdate{$self}||0)>1;
		my $delayed;
		if ($Filter{$self}->changes_may_affect($IDs,$fields,$self))
		{	#re-filter and re-sort
			$needupdate{$self}=2;
			$delayed=1;
		}
		elsif ($self->AreIn($IDs) && ::OneInCommon($fields,Songs::SortDepends($Sort{$self})))
		{	#re-sort
			$needupdate{$self}=1;
			$delayed=1;
		}
		::IdleDo('7_autoupdate_update'.$self,6000, \&delayed_update_cb,$self) if $delayed;
	}
}

package SongArray::PlayList;
use base 'SongArray';

sub init
{	$::ListPlay=SongArray::PlayList->new;

	my $sort=$::Options{Sort};
	$::RandomMode= $sort=~m/^random:/ ? Random->new($sort,$::ListPlay) : undef;
	$::SortFields= $::RandomMode ? $::RandomMode->fields : Songs::SortDepends($sort);

	my $last=$::Options{LastPlayFilter} || Filter->new;
	if (ref $last && ref $last eq 'Filter')	{ $::ListPlay->SetFilter($last); }
	else					{ $::ListPlay->Replace($last); }

	::Watch(undef, SongsChanged	=> \&SongsChanged_cb);
	::Watch(undef, SongsAdded	=> \&SongsAdded_cb);
	::Watch(undef, SongsHidden	=> sub { SongArray::RemoveFromArrays($_[1],[$::ListPlay]) unless $::ListMode; });
	::Watch(undef, SongArray	=> \&SongArray_changed_cb);
	return $::ListPlay;
}

sub Sort
{	my ($self,$sort)=@_;
	my $old=$::Options{Sort};
	if ($old eq $sort && $sort=~m/shuffle/) { Songs::ReShuffle(); }
	if ($::RandomMode || $old=~m/shuffle/)	{ $::Options{Sort_LastSR}=$old; }		# save sort mode for
	elsif ($old ne '')			{ $::Options{Sort_LastOrdered}=$old; }		# quick toggle random/non-random
	$::RandomMode= $sort=~m/^random:/ ? Random->new($sort,$self) : undef;
	$::Options{Sort}=$sort;
	$::SortFields= $::RandomMode ? $::RandomMode->fields : Songs::SortDepends($sort);
	$self->UpdateSort;
	if ($::RandomMode || !@$self)	{ $::Position=undef }
	else
	{	$::Position= defined $::SongID ? ::FindPositionSong($::SongID,$self) : undef;
	}
	::QHasChanged('Sort');
	::QHasChanged('Pos');
}
sub SetSortAndFilter	#FIXME could be optimized #FIXME only called from a songtree/songlist for now, and as these calls are usually not about setting the level 0 filter, it doesn't actually change the filter for now, just the list, as it needs multi-level filters to work properly
{	my ($self,$sort,$filter)=@_;
	$self->Replace($filter->filter,filter=>$filter); #$self->SetFilter($filter); #FIXME use SetFilter once multi-level filters are implemented
	$self->Sort($sort);
}
sub Replace
{	my ($self,$newlist)=@_;
	delete $::ToDo{'7_refilter_playlist'};
	delete $::ToDo{'8_resort_playlist'};
	$newlist=SongArray->new unless defined $newlist;
	unless (ref $newlist)
	{	::SaveList($newlist,[]) unless $::Options{SavedLists}{$newlist};
		$newlist= $::Options{SavedLists}{$newlist};
	}
	$newlist= SongArray->new_copy($newlist);
	$::Position=undef;  $::ChangedPos=1;
	my $ID=$::SongID;
	$ID=undef if defined $ID && $::Options{AlwaysInPlaylist} && !$newlist->IsIn($ID);
	if (!defined $ID)
	{	$ID= $self->_FindFirst($newlist);
	}
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($newlist);
	$newlist=$self->_updatelock($ID,$newlist) if $::TogLock && defined $ID;
	@$self=@$newlist;
	delete $Presence{$self};
	$::SelectedFilter=$::PlayFilter=undef;
	if ($::RandomMode)	{ $::RandomMode->Invalidate; }
	else			{ $::SortFields=[]; $::Options{Sort}=''; ::QHasChanged('Sort'); }
	::QHasChanged('Filter');
	::HasChanged('SongArray',$self,'replace');
	_updateID($ID);
}
sub Insert
{	my ($self,$destrow,$IDs)=@_;
	$self->_staticfy;
	$self->SUPER::Insert($destrow,$IDs);
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($self);
	if (defined $::Position && $::Position>=$destrow)
	{	$::Position+=@$IDs;
		::red("position error after insert") if $self->[$::Position] != $::SongID; #DEBUG
	}
	elsif (@$self==@$IDs && !defined $::SongID)	#playlist was empty
	{	$self->Next;
	}
	::QHasChanged('Pos');

	#set Position if playlist was empty ??
}
sub Remove
{	my ($self,$rows,$fromlibrary)=@_;
	$self->_staticfy unless $fromlibrary;	#do not staticfy list for songs removed from library
	$self->SUPER::Remove($rows);
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($self)  unless $fromlibrary;
	if (@$self==0 && $::Options{AlwaysInPlaylist}) { $::Position=undef; _updateID(undef); return; }
	if ($::RandomMode)
	{	$::RandomMode->RmIDs;
		$self->Next if defined $::SongID && $::Options{AlwaysInPlaylist} && !$self->IsIn($::SongID); #skip to next song if current not in playlist
	}
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
		if ($IDchanged)
		{	if ($::Options{AlwaysInPlaylist})
			{	$self->Next;  #skip to next song if current not in playlist
			}
			else { $::Position=undef; }
		}
	}
	::QHasChanged('Pos');
}
sub Up
{	my ($self,$rows)=@_;
	$self->_staticfy;
	$rows=$self->SUPER::Up($rows);
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($self);
	return unless $rows;
	if (defined $::Position)
	{	my $pos= $::Position;
		for my $row (@$rows)
		{	if	($row==$pos)	{$pos--}
			elsif	($row==$pos+1)	{$pos++}
		}
		if ($::Position!=$pos) { $::Position=$pos; ::QHasChanged('Pos'); }
	}
}
sub Down
{	my ($self,$rows)=@_;
	$self->_staticfy;
	$rows=$self->SUPER::Down($rows);
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($self);
	return unless $rows;
	if (defined $::Position)
	{	my $pos= $::Position;
		for my $row (reverse @$rows)
		{	if	($row==$pos)	{$pos++}
			elsif	($row==$pos-1)	{$pos--}
		}
		if ($::Position!=$pos) { $::Position=$pos; ::QHasChanged('Pos'); }
	}
}
sub Move
{	my ($self,$destrow,$rows)=@_;
	$self->_staticfy;
	$self->SUPER::Move($destrow,$rows);
	$::Options{LastPlayFilter}=$::ListMode=SongArray->new_copy($self);
	if (defined $::Position)
	{	my $pos=$::Position;
		my @rows=sort { $a <=> $b } @$rows;
		my $delta=0;
		for my $row (reverse @rows)
		{	$destrow-- if $row<$destrow;
			$delta++;
			if	($row==$::Position)		{ $pos=undef; $delta=0; } #selected song has moved
			elsif	(defined $pos && $row<$pos)	{ $pos-- }
		}
		if (defined $pos)	{ $pos+=$delta if $destrow<=$pos; }
		else			{ $pos=$destrow+$delta; }

		if ($::Position!=$pos) { $::Position=$pos; ::QHasChanged('Pos'); }
	}
}

#watchers callbacks
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
	#return unless $::ListMode && $songarray==$::ListMode;
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
	$::Position=undef;  $::ChangedPos=1;
	::QHasChanged('Filter');
	::HasChanged('SongArray',$self,'replace', filter=> $::PlayFilter);
	_updateID($newID);
}
sub UpdateFilter
{	my $self=shift;
	my @oldlist=@$self;
	my $before=$::PlayFilter;
	my $newID=$self->_filter;
	if ($::PlayFilter->are_equal($before))
	{	::HasChanged('SongArray',$self,'update',\@oldlist);
	}
	else	#filter may change because of the lock
	{	::QHasChanged('Filter');
		::HasChanged('SongArray',$self,'replace', filter=> $::PlayFilter);
	}
	$::Position=undef;  $::ChangedPos=1;
	_updateID($newID);
}
sub UpdateSort
{	my $self=shift;
	my @old;
	@old=@$self unless $::RandomMode;
	$self->_sort;
	::HasChanged('SongArray',$self,'sort',$::Options{Sort},\@old) unless $::RandomMode;
	$::Position=undef;  $::ChangedPos=1;
	_updateID($::SongID);
}
sub UpdateLock
{	my $self=shift;
	$::Position=undef;  $::ChangedPos=1;
	if (defined $::ListMode) { $self->Replace($::ListMode); }
	else { $self->SetFilter($::SelectedFilter); }
}

sub InsertAtPosition
{	my ($self,$IDs)=@_;
	my $pos=defined $::Position? $::Position+1 : 0;
	$self->Insert($pos,$IDs);
}
sub Add		#only called in filter mode
{	my ($self,$IDs)=@_;
	$self->SUPER::Insert(scalar @$self,$IDs); # call SUPER::Insert directly instead of SUPER::Push because SUPER::Push calls $self->Insert and thus statify the list
	if ($::RandomMode)
	{	$::RandomMode->AddIDs(@$IDs);
	}
	elsif (my $s=$::Options{Sort})
	{	$self->SUPER::Sort($s);
	}
	if (!defined $::SongID)
	{	my $ID= $self->_FindFirst($self);
		$self->SetID($ID)
	}
	$::ChangedPos=1;
	::UpdateCurrentSong();
}

sub SetID
{	my ($self,$ID)=@_;
	$::ChangedID=1;
	$::SongID=$ID;
	if ($self->IsIn($ID) || !$::Library->IsIn($ID))
	{	::UpdateCurrentSong();
		return
	}
	if ($::TogLock && defined $ID && @$self)
	{	my $newlist=$self->_list_without_lock;
		if (::IDIsInList($newlist,$ID))		# is in list without lock -> reset lock
		{	$self->UpdateLock;
			return;
		}
	}
	if ($::Options{AlwaysInPlaylist})
	{	$self->SetFilter;	#reset filter
	}
	else
	{	::UpdateCurrentSong();
	}
}

#private functions
sub _updateID
{	my $ID=shift;
	::Stop() unless defined $ID;
	$::ChangedID=1 if !defined $::SongID || !defined $ID || $ID!=$::SongID;
	$::SongID=$ID;
	::UpdateCurrentSong();
}
sub _filter
{	my $self=shift;
	delete $::ToDo{'7_refilter_playlist'};
	my $filter=$::SelectedFilter;
	my $ID=$::SongID;
	$filter= Filter->newadd(1,$filter, Filter->newlock($::TogLock,$ID) )  if $::TogLock && defined $ID;
	$::PlayFilter=$filter;
	my $newlist=$filter->filter;
	my $need_relock;
	my $sorted;
	if (defined $ID && $::Options{AlwaysInPlaylist} && !@{ $filter->filter([$ID]) })
	{	if (!@$newlist && $::TogLock)
		{	$newlist= $::SelectedFilter->filter;
			$need_relock=1;
		}
		if ($::RandomMode) { $ID=undef; }
		elsif (my $sort=$::Options{Sort})
		{	Songs::SortList($newlist,$sort);
			$sorted=1;
			$ID= Songs::FindNext($newlist, $sort, $ID);
		}
	}
	if (!defined $ID)
	{	$ID= $self->_FindFirst($newlist);
		$need_relock=1 if $::TogLock;
	}
	$newlist=$self->_updatelock($ID,$newlist) if $need_relock;
	$self->_sort($newlist) unless $sorted;
	@$self=@$newlist;
	delete $Presence{$self};
	return $ID;
}
sub _sort
{	my ($self,$list)=@_;
	$list||=$self;
	delete $::ToDo{'8_resort_playlist'};
	if ($::RandomMode)	{ $::RandomMode->Invalidate; }
	elsif ($::Options{Sort}){ Songs::SortList($list,$::Options{Sort}); }
	elsif ($::ListMode)
	{	if ($::TogLock && $::PlayFilter)
		{	my $newlist=$::PlayFilter->filter($list);
			@$self=@$newlist;
			delete $Presence{$self};
		}
		else
		{	@$self=@$::ListMode;
		}
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
	return $::ListMode ? $::ListMode : $::SelectedFilter->filter;
}
sub _updatelock
{	my ($self,$ID,$newlist)=@_;
	if (!defined $ID)
	{	$::TogLock=undef;
		::QHasChanged('Lock');
		return $newlist;
	}
	my $lockfilter=Filter->newlock($::TogLock,$ID);
	$::PlayFilter= $::ListMode ? $lockfilter : Filter->newadd(1,$::SelectedFilter,$lockfilter);
	return $lockfilter->filter($newlist);
}
sub _staticfy
{	my $self=shift;
	delete $::ToDo{'7_refilter_playlist'};
	delete $::ToDo{'8_resort_playlist'};
	if ($::TogLock)		{ $::TogLock=undef; ::QHasChanged('Lock'); }
	unless ($::ListMode)
	{	::QHasChanged('Filter');
		::HasChanged('SongArray',$self,'mode');
	}
	$::PlayFilter=undef;
	if (!$::RandomMode && $::Options{Sort})	{ $::SortFields=[]; $::Options{Sort_LastOrdered}=$::Options{Sort}; $::Options{Sort}=''; ::QHasChanged('Sort'); }
}

#sub _updatepos
#{	$::PositionUpdate=0;
#	if (!defined $::Position && !$::RandomMode && defined $::SongID)
#	{	
#	}
#	::HasChanged('Pos');
#}


package GMB::ListStore::Field;
use base 'Gtk3::ListStore';

our %ExistingStores;

sub new
{	my ($class,$field,$noturgent)=@_; #warn "creating new store for $field\n";
	my @cols=('Glib::String');
	push @cols, 'Glib::String' if $Songs::Def{$field}{icon}; #FIXME
	my $self= bless Gtk3::ListStore->new(@cols), $class;
	$ExistingStores{$field}= $self;
	::weaken $ExistingStores{$field};
	if ($noturgent) { ::IdleDo("9_ListStore_$field",500,\&update,$field); }
	else { update($field) }
	::Watch($self,fields_reset=>\&changed);
	return $self;
}

sub getstore
{	my ($field,$noturgent)= @_; #noturgent is used for completion where the store can be filled later
	return $ExistingStores{$field} || new(__PACKAGE__,$field,$noturgent);
}
sub setcompletion
{	my ($entry,$field)=@_;
	my $completion=Gtk3::EntryCompletion->new;
	$completion->set_text_column(0);
	if ($Songs::Def{$field}{icon}) #FIXME
	{	my $cell=Gtk3::CellRendererPixbuf->new;
		$completion->pack_start($cell,0);
		$completion->add_attribute($cell,'icon-name',1);
	}
	$completion->set_model( getstore($field,1) );
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
use base 'Gtk3::ComboBox';

sub new
{	my ($class,$field,$init,$callback)=@_;
	my $store= GMB::ListStore::Field::getstore($field);
	my $self= bless Gtk3::ComboBox->new_with_model($store), $class;

	if ($Songs::Def{$field}{icon})
	{	my $cell= Gtk3::CellRendererPixbuf->new;
		# FIXME 2TO3 try to make "Gtk3::IconSize::lookup('menu')" work instead of 16,16
		$cell->set_fixed_size(16,16); # fixed size => icon or empty space
		$self->pack_start($cell,0);
		$self->set_attributes($cell,'icon-name'=>1);
	}
	my $cell= Gtk3::CellRendererText->new;
	#$cell->set(wrap_width=>500);
	#$cell->set(ellipsize=>'end');
	$self->pack_start($cell,1);
	$self->set_attributes($cell,text=>0);
	$self->{value}=$init;
	$self->update;
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
my (%CachedTime,%CachedSize,%CachedList); my $CachedTotal=0;
our (%InvOp,$OpRe);
INIT
{
  my @Oplist= qw( =~ !~   || &&   > <=   < >=   == !=   eq ne  !! !   0 1 );	#negated operators for negated filters
  %InvOp= (@Oplist, reverse @Oplist);
  $OpRe=join '|',map quotemeta, keys %InvOp;
  $OpRe=qr/\.($OpRe)\./;
  %NGrepSubs=
  (	t => sub
	     {	my ($field,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref; Songs::SortList(\$tmp, '".Songs::SortField($field)."' ); $assign @\$tmp[$inv];";
	     },
	h => sub
	     {	my ($field,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref; Songs::SortList(\$tmp, '".'-'.Songs::SortField($field)."' ); $assign @\$tmp[$inv];";
	     },
  );
}

#Filter object contains :
# - string :	string notation of the filter
# - sub    :	ref to a sub which takes a ref to an array of IDs as argument and returns a ref to the filtered array
# - greponly :	set to 1 if the sub doesn't need to filter the whole list each times -> ID can be tested individually
# - fields :	ref to a list of the columns used by the filter

sub new_from_string		#same as ->new, but don't try to _smart_simplify, as it shouldn't be needed, and require fields to be initialized
{	my ($class,$string) = @_;
	my $self=bless {string=>$string}, $class;
	return $self;
}
sub save_to_string { $_[0]->{string}; }

sub new
{	my ($class,$string,$source) = @_;
	my $self=bless {}, $class;
	if	(!defined $string)	  {$string='';}
	elsif	(ref $string && $string->isa('Filter')) {$string=$string->{string}}
	elsif	($string=~m/^\w+:-?~:/) { ($string)=_smart_simplify($string); }
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
		if (ref $f && ref $f eq 'ARRAY')	#array format : first value is true(and)/false(or) followed by filters
		{	while (ref $f)
			{	if (@$f<2) {$f=undef;last}
				if (@$f==2) { $f=$f->[1] }
				else { $f= Filter->newadd(@$f); last }	# FIXME could avoid a recursion
			}
			next unless defined $f;
		}
		$self->{source} ||= $f->{source} if ref $f;
		my $string=(ref $f)? $f->{string} : $f;
		if (!$string)
		{	next if $and;			# all and ... = ...
			$self->{string}='';		# all or  ... = all
			$self->{desc}=_"All songs";
			return $self;
		}
		elsif ($string eq 'null')
		{	next if !$and;			# null or ... = ...
			$self->{string}='null';		# null and  ... = null
			$self->{desc}=_"No songs";
			return $self;
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
			push @strings,( ($string=~m/^\w+:-?~:/)
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
	$self->{superset_filters}= \@supersets unless $sum=~m#(?:^|\x1D)\w+:-?[th]:#;	#don't use superset optimization for head/tail filters, as they are not commutative
	return $self;
}

sub null { Filter->new('null'); }

sub new_from_smartstring
{	my (undef,$string,$casesens,$regexp,$fields0)=@_;
	$fields0 ||= 'title';
	my $and= [1];
	my $or= [0,$and];
	my @parents; my @not; my $notgroup;
	while ($string=~m/\S/)
	{	$string=~s/^\s+//;
		if ($string=~s#^(?:\||OR)\s+##) { push @$or, $and=[1]; next }
		my $not= ($string=~s/^[-!]\s*// xor $notgroup);
		if ($string=~s#^\(##)				#open group
		{	push @not,$notgroup;
			$notgroup=$not;
			push @parents, $or; $and=[(1 xor $not)];
			$or=[(0 xor $not), $and];
			next;
		}
		if ($string=~s#^\)## && @parents)		#close group
		{	my $prev= $or;
			$or= pop @parents;
			$and= $or->[-1];
			push @$and, $prev;
			$notgroup=pop @not;
			next;
		}
		$string=~s/^\\(?=[-!O|\(\)])//;	#un-escape escaped negative or OR or ()

		# operator and fields
		my ($fields,$op);
		if ($string=~s&^(\w+(?:\|\w+)*)?(<=|>=|[:<>=~]|#+)&&)
		{	$fields=$1; $op=$2;
			if ($fields)
			{	my @f= grep $_, map { $Songs::Aliases{$_} || $Songs::Aliases{::superlc($_)} } split(/\|/,$fields);
				if (@f) { $fields= join '|',@f }
				else { $string= $fields.$op.$string; $fields=$op=undef; }	#no recognized field => treat $fields and $op as part of the pattern
			}
			$string=~s#^\\([:<>=~\#])#$1#g unless $op;	#un-escape escaped operators at start of string if no recognized operator
		}
		$fields ||= $fields0;
		$op||= $regexp ? '~' : ':';


		my @patterns;
		{	if ($string=~s#^(['"])##) #pattern begins with a quote
			{	my $quote=$1;
				if ($string=~s#^(.+?)(?<!\\)$quote((?<!\\)[|)]|\s+|$)##) # closing quote followed by "|", ")", space or end of string
				{	push @patterns,$1;
					$string= ")".$string if $2 eq ')';
					redo if $2 eq '|';
				}
				else { push @patterns,$string; $string=''; } # quote is never closed => pretend it is closed at the end of the string
			}
			elsif ($string=~s/^(.*?)(	(?<!\\)\| |			# ends with | => more than one pattern
							(?<!\\)(?=\)[\s|)]|\)$) |	# or with closing parenthese followed by space | ) or end-of-string
							(?<!\\)\s+ | $			# or with spaces or end-of-string
					)//x)
			{	push @patterns,$1;
				redo if $2 eq '|';
			}
		}
		s#\\([ "'|)])#$1#g for @patterns;	#un-escape escaped spaces, quotes, | and )
		# convert smart operator to internal operator and create filter for this level
		my @filters=(0 xor $notgroup);
		for my $field (split /\|/, $fields)
		{	for my $pattern (@patterns)
			{	my $filter;
				my $op1= $op=~m/^#/ ? '#' : $op;	#special case for ## and ### : use the same function as for #
				if ($pattern eq '')
				{	$filter= Songs::Field_property($field,'smartfilter:'.$op1.'empty'); #must contain operator ':' pattern
				}
				elsif (my $found= Songs::Field_property($field,'smartfilter:'.$op1))
				{	if (ref $found)
					{	$filter= $found->($pattern,$op,$casesens,$field);
					}
					else
					{	my @found=split / /,$found;
						my $realop= @found>1 ? $found[$casesens ? 1 : 0] : $found;
						$filter= $realop.':'.$pattern;
					}
				}
				next unless $filter;
				if ($not) { $filter=~s/^-//  or  $filter= '-'.$filter }
				push @filters, $field.':'.$filter;
			}
		}
		next unless @filters>1;
		push @$and, @filters>2 ? \@filters : $filters[1];
	}

	# close opened groups
	while (@parents)
	{	my $prev= $or;
		$or= pop @parents;
		$and= $or->[-1];
		push @$and, $prev;
	}
	return Filter->newadd(@$or);
}
sub _smartstring_number_check_unit
{	my ($pat,$field)=@_;
	return '' unless length $pat;
	my $opt= { @{ Songs::Field_property($field,'filterpat:value') || [] } };
	my $unit= $opt->{default_unit} || '';
	my $uhash= $opt->{unit}; $uhash={} unless $uhash && ref $uhash;
	if ($pat=~s/([a-zA-Z]+)$//)
	{	$unit= $uhash->{$1} ? $1 : $uhash->{lc$1} ? lc$1 : $unit;
	}
	$pat=~m/^(-?\d*\.?\d+)$/;
	$pat= $1||0;
	return 0 if $pat==0;
	my $unit_value= $uhash->{$unit}[0]||0;
	return $pat.$unit, $unit_value==1;
}
sub _smartstring_round_range # turn 5m into 4.5m..5.5m or 5.2m into 5.15m..5.25m
{	my ($n,$u)=@_;
	my $l=index $n,'.';
	$l= $l>0 ? length($n)-$l-1 : 0;
	my $delta= .5/(10**$l);
	return ($n-$delta).$u, ($n+$delta).$u;
}
sub _smartstring_number_moreless
{	my ($pat,$op,$casesens,$field)=@_;
	$pat=~s/,/./g; #use dot as decimal separator
	return undef unless $pat=~m/^-?\d*\.?\d+[a-zA-Z]?$/;
	($pat)= _smartstring_number_check_unit($pat,$field);
	$op= $op eq '<=' ? '->' : $op eq '>=' ? '-<' : $op;
	return $op.':'.$pat;
}
sub _smartstring_date_moreless
{	my ($pat,$op,$casesens,$field)=@_;
	my $suffix='';
	$pat=~s/,/./g; #use dot as decimal separator
	if ($pat=~m/\d[smhdwMy]/) { $suffix='ago' } #relative date filter
	else
	{	$pat= ::dates_to_timestamps($pat, ($op eq '>' || $op eq '<=')? 1:0);
	}
	return undef unless $pat;
	$op= $op eq '<=' ? '<' : $op eq '>=' ? '>' : $op;
	return $op.$suffix.':'.$pat;
}
sub _smartstring_number
{	my ($pat,$op,$casesens,$field)=@_;
	$pat=~s/,/./g; #use dot as decimal separator
	if ($pat!~m#\.\.# && ($op ne '=' || $pat!~m/^-\d*\.?\d+[a-zA-Z]?$/)) {$pat=~s/-($|-|\d*\.?\d+[a-zA-Z]?$)/..$1/}	# allow ranges using - unless = with negative number (could also check if field support negative values ?)
	if ($pat=~m/\.\./)
	{	my ($s1,$s2)= split /\s*\.\.\s*/,$pat,2;
		($_)= _smartstring_number_check_unit($_,$field) for $s1,$s2;
		return	(length $s1 && length $s2) ? "b:$s1 $s2":
			(length $s1 && !length$s2) ? "-<:".$s1	:
			(!length$s1 && length $s2) ? "->:".$s2	: undef;
	}
	return 's:'.$pat if $op eq ':';
	return undef unless $pat=~m/^-?\d*\.?\d+[a-zA-Z]?$/;
	($pat,my $is_lowest_unit)= _smartstring_number_check_unit($pat,$field);
	if (!$is_lowest_unit and my($n,$u)= $pat=~m#^(\d*\.?\d+)([a-zA-Z]+)$#i) # =5m turned into 4.5m..5.5m
	{	my ($n1,$n2)= _smartstring_round_range($n,$u);
		return "b:$n1 $n2";
	}
	return 'e:'.$pat;
}
sub _smartstring_date
{	my ($pat,$op,$casesens,$field)=@_;
	my $suffix='';
	my $date1= my $date2='';
	if ($pat=~m#\d# and ($date1,$date2)= $pat=~m#^(\d*\.?\d+[smhdwMy])?(?:\.\.|-)(\d*\.?\d+[smhdwMy])?$#i)	# relative date filter
	{	$suffix='ago';
		if	($date1 && $date1!~m/[1-9]/) {$date1=''}
		elsif	($date1 && $date2 && $date2!~m/[1-9]/) {$date2=$date1; $date1=''}
		$date1||='';
		$date2||='';
	}
	elsif ($op eq '=' and my($n,$u)= $pat=~m#^(\d*\.?\d+)([smhdwMy])$#i) # =5h turned into 4.5h..5.5h
	{	$suffix='ago';
		($date1,$date2)= $u eq 's' ? ('','') : _smartstring_round_range($n,$u);
	}
	else						# absolute date filter
	{	($date1,$date2)= ::dates_to_timestamps($pat,2);
		#$pat= "$date1..$date2" if $date1.$date2 ne '';
	}
	if ($date1.$date2 ne '')
	{	#my ($s1,$s2)= split /\s*\.\.\s*|\s*-\s*/,$pat,2;
		return	(length $date1 && length $date2) ? "b$suffix:$date1 $date2":
			(length $date1 && !length$date2) ? ">$suffix:".$date1	:
			(!length$date1 && length $date2) ? "<$suffix:".$date2	: undef;
	}
	$op= $op eq '=' ? 'e' : $casesens ? 's' : 'si';
	return $op.':'.$pat;
}

sub add_possible_superset	#indicate a possible superset filter that could be used for optimization when the result of $superset_candidate is cached
{	my $self=shift;
	my $arrayself= $self->to_array;
	my $string1= $self->{string};
	return if $string1=~m#(?:^|\x1D)\w+:-?[th]:#; # ignores filters with head/tail filters
	for my $superset_candidate (@_)
	{	my $string2= $superset_candidate->{string};
		next if $string2=~m#(?:^|\x1D)\w+:-?[th]:#; # ignores filters with head/tail filters
		next if $string2 eq $string1;
		push @{ $self->{superset_filters} }, $string2 if _is_subset($superset_candidate->to_array, $arrayself);
	}
	#if (my $l=$self->{superset_filters}) { my $s=$self->{string}."\n"; $s.=" superset: ".$_."\n" for @$l; $s=~s/\x1D/**/g;warn $s; } #DEBUG
}

sub _is_subset		# returns true if $f2 must be a subset of $f1	#$f1 and $f2 must be in array form	#doesn't check for head/tail filters
{	my ($f1,$f2)=@_;
	if (!ref $f1 && !ref $f2)
	{	return 1 if $f1 eq $f2;
		my ($field1,$op1,$pat1)= split /:/,$f1,3;
		my ($field2,$op2,$pat2)= split /:/,$f2,3;
		return 0 if $field1 ne $field2 || $op1 ne $op2;
		if ($op1 eq 's'|| $op1 eq 'si')		{ return index($pat2,$pat1)!=-1 }	# handle case-i ?
		elsif ($op1 eq '-s'|| $op1 eq '-si')	{ return index($pat1,$pat2)!=-1 }	# handle case-i ?
		elsif ($op1 eq '>' || $op1 eq '-<') { return ($pat1."\x00".$pat2) =~m/^(-?\d*\.?\d+)(\w*)\x00(-?\d*\.?\d+)\2$/ && $3>$1  }
		elsif ($op1 eq '<' || $op1 eq '->') { return ($pat1."\x00".$pat2) =~m/^(-?\d*\.?\d+)(\w*)\x00(-?\d*\.?\d+)\2$/ && $3<$1  }
		# FIXME  check these filters : b bago >ago <ago ?
		return 0;
	}

	# at least one is an array of filters
	$f1= [0,$f1] unless ref$f1;
	$f2= [0,$f2] unless ref$f2;
	if ($f1->[0] && $f2->[0])	# A & B -> C & D	# each from f1 must be a superset of one from f2
	{	for my $i (1..$#$f1)
		{	my $in_one;
			$in_one ||= _is_subset($f1->[$i],$f2->[$_]) for 1..$#$f2;
			return 0 unless $in_one;
		}
		return 1;
	}
	elsif ($f1->[0])		# A & B -> C | D	# each from f2 must be a subset of in each from f1
	{	my $not_in_one=1;
		for my $i (1..$#$f2)
		{	$not_in_one ||= ! _is_subset($f1->[$_],$f2->[$i]) for 1..$#$f1;
		}
		return !$not_in_one;
	}
	elsif ($f2->[0])		# A | B -> C & D	# one from f2 must be a subset of one from f1
	{	my $in_one;
		for my $i (1..$#$f2)
		{	$in_one ||= _is_subset($f1->[$_],$f2->[$i]) for 1..$#$f1;
		}
		return $in_one;
	}
	else				# A | B -> C | D	# each from f2 must be a subset of one from f1
	{	for my $i (1..$#$f2)
		{	my $in_one;
			$in_one ||= _is_subset($f1->[$_],$f2->[$i]) for 1..$#$f1;
			return 0 unless $in_one;
		}
		return 1;
	}
}

sub to_array	#returns an array form of the filter, first value of array is false for OR, true for AND
{	my $filter=shift;
	$filter= $filter->{string} if ref $filter;
	my $current;
	$current=[0] unless $filter=~m/^\(/;
	my @parents;
	for my $part (split /\x1D/,$filter)
	{	if ($part=~m/^\(/)		# '(|' or '(&'
		{	my $and= $part eq '(&';
			push @parents, $current if $current;
			$current=[$and];
			next;
		}
		if ($part eq ')')
		{	last unless @parents;
			$part=$current;
			$current=pop @parents;
		}
		push @$current, $part;
	}
	return $current;
}

sub _combine_ranges
{	my ($field,$and,@segs)=@_;
	my $step= Songs::Field_property($field,'step') || 0;
	my @out;
	@segs= sort { $a->[0] <=> $b->[0] } @segs;
	my ($s1,$s2);
	while (@segs)
	{	my ($s3,$s4)= @{shift @segs};
		if (defined $s1 && $s3>=$s1 && $s3<=$s2+$step)
		{	$s2=$s4 if $s2<$s4;
		}
		else { push @out, [$s1,$s2] if defined $s1; ($s1,$s2)=($s3,$s4); }
	}
	push @out, [$s1,$s2] if defined $s1;
	return map { "$field:".($and ? '-' : '').'b:'.$_->[0].' '.$_->[1] }  @out;
}
sub _between_simplify		#combine ranges of consecutive between filters into fewer ranges if possible
{	my ($and,@in)=@_;
	my @strings;
	my ($field,@segs);
	while (@in)
	{	my $s=shift @in;
		if ($s=~m/^(\w+):(-?)b:(-?\d*\.?\d+) (-?\d*\.?\d+)\x1D?$/)
		{	if (!$2 xor $and)
			{	$field||=$1;
				if ($field eq $1)
				{	push @segs, [$3,$4];	#=> combine the range
					next if @in;
				}
				else { unshift @in,$s; }
			}
		}
		if (@segs)	#change of filter or no more filters => push combined range
		{	push @strings, _combine_ranges($field,$and,@segs);
			@segs=();
		}
		else { push @strings, $s; }
		$field=undef;
	}

	s/^(\w+):(-?)b:(-?\d*\.?\d+) \3\x1D?$/"$1:$2e:$3"/e for @strings; #replace :b:5 5 by :e:5
	return @strings;
}

sub are_equal #FIXME could try harder
{	my $f1=$_[0]; my $f2=$_[1];
	($f1,my$s1)=defined $f1 ? ref $f1 ? ($f1->{string},$f1->{source}) : $f1 : '';
	($f2,my$s2)=defined $f2 ? ref $f2 ? ($f2->{string},$f2->{source}) : $f2 : '';
	return ($f1 eq $f2) && ((!$s1 || !$s2) || ($s1 && $s2 && $s1 eq $s2));
}

sub _smart_simplify	#only called for ~ filters
{	my $s=$_[0]; my $returnlist=$_[1];
	my ($field,$inv,$pat)= $s=~m/^(\w+):(-?)~:(.*)$/;
	$inv||='';
	my $sub=Songs::LookupCode($field,'filter_simplify:~');
	return $s unless $sub;
	my @pats=$sub->($pat);
	if ($returnlist || @pats==1)
	{	return map "$field:$inv~:$_" , @pats;
	}
	else
	{	return "(|\x1D".join('',map("$field:$inv~:$_\x1D", @pats)).")\x1D";
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
		my ($field,$cmdpat)=split ':',$_,2;
		$cmdpat='-'.$cmdpat unless $cmdpat=~s/^-//;
		$_= $field.':'.$cmdpat;
	}
	$self->{string}=join "\x1D",@filter;
	warn 'after invert  : '.$self->{string} if $::debug;
	return $self;
}

sub filter_all
{	$_[0]->filter( [Songs::FIRSTID..$Songs::LastID] );
}

sub filter
{	my $self=$_[0]; my $listref=$_[1];
	#my $time=times;								#DEBUG
	$listref||= $self->{source} || $::Library;
	my $sub=$self->{'sub'} || $self->makesub;
	my $on_library= ($listref == $::Library && !$self->{source});
	if ($self->{nocache}) { return $listref }
	my $already_found;
	if ($on_library && !$self->{nocache} && (%CachedList || %IdleFilter::InProgress))
	{	my $string= $self->{string};
		$CachedTime{$string}=time; # the result will be cached if it is not already => update timestamp now
		return [unpack 'L*',$CachedList{$string}] if defined $CachedList{$string};
		#warn "no exact cache for filter\n";
		if (my $idlefilter= delete $IdleFilter::InProgress{$string})
		{	$already_found= $idlefilter->{found};
			$listref= $idlefilter->{todo};
		}
		if ($self->{superset_filters})
		{	my $simplified= $self->simplify_with_superset_cache;
			#warn "filter: todo=".(scalar @$simplified)." avoided=".(@$::Library-@$simplified)."\n" if $simplified;
			$listref= $simplified if $simplified;
		}
	}
	my $r=$sub->($listref);
	$r= [ @$already_found, @$r ] if $already_found;
	#$time=times-$time; warn "filter $time s ( ".$self->{string}." )\n" if $debug;	#DEBUG
	if ($on_library && !$self->{nocache})
	{	$self->cache_result($r);
	}
	return $r;
}
sub simplify_with_superset_cache
{	my $self=shift;
	return unless $self->{superset_filters};
	my @supersets= grep defined, map $CachedList{$_}, @{$self->{superset_filters}};
	if (@supersets)
	{	#warn "found supersets : ".join(',', map length $_,@supersets)."\n";
		#warn " from : ".join(',', grep $CachedList{$_}, @{$self->{superset_filters}})."\n";
		return [unpack 'L*',(sort { length $a <=> length $b } @supersets)[0] ];	#take the smaller set, could find the intersection instead
	}
	# no cached result for superset, look if there is an idlefilter in progress that could be used
	my ($idlefilter)= sort { @{$a->{todo}} + @{$a->{found}} <=> @{$b->{todo}} + @{$b->{found}} }
		grep defined, map $IdleFilter::InProgress{$_}, @{$self->{superset_filters}};
	return [ @{$idlefilter->{todo}}, @{$idlefilter->{found}} ] if $idlefilter;
	return undef;
}
sub cache_result
{	my $string= $_[0]{string};
	my $result= $_[1];
	if ($CachedTotal>100) # trim the cache
	{	my $time=time;
		my @del_order= sort { ($time-$CachedTime{$b})*$CachedSize{$b} <=> ($time-$CachedTime{$a})*$CachedSize{$a} } keys %CachedSize;
		while ($CachedTotal>70)
		{	my $delete=shift @del_order;
			#warn "removing ".do {my $f=$delete; $f=~s/\x1D+//g; $f}." last used=".localtime($CachedTime{$delete})." size=".$CachedSize{$delete}." score=".(($time-$CachedTime{$delete})*$CachedSize{$delete})."\n";
			delete $CachedList{$delete};
			delete $CachedTime{$delete};
			$CachedTotal-= delete $CachedSize{$delete};
		}

	}
	$CachedTotal+= $CachedSize{$string}= 1+(39*@$result/(@$::Library||1));
	$CachedTime{$string}=time; # also done in filter()
	$CachedList{$string}= pack 'L*',@$result;
}
sub is_cached
{	my $self=shift;
	return exists $CachedList{$self->{string}} || $self->{nocache};
}
sub clear_cache
{	%CachedList=%CachedTime=%CachedSize=();
	$CachedTotal=0;
	IdleFilter::clear();
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
	$self->makesub unless $self->{'sub'};
	return 0 unless grep exists $self->{fields}{$_}, @$fields;
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
				my ($field,$inv,$cmd)=$icc=~m/^(\w+):(-?)([^:]+):$/;
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
				$filter[$first]="$field:".$inv."h$cmd:".$#$hashes;
			}
			$d--;
		}
		elsif ( $s=~m/^(\w+):(-?)([e~]):(.*)$/ && ($or[$d] xor $2) )
		{	$val[$d]{"$1:$2$3:"}{$4}=undef;		#add key to the hash
			push @{$ilist[$d]{"$1:$2$3:"}},$i;	#store filter index to remove it later if it is replaced
		}
	}
	my $filter=join "\x1D", grep defined,@filter; #warn "$_\n" for @filter;
	return $filter,$hashes;
}

sub singlesong_code
{	my ($self,$depends,$hashes)=@_;
	my $filter=$self->{string};
	return '1' if $filter eq '';
	return undef if $filter=~m#\x1D^\w+:-?[th]:#;
	($filter)=_optimize_with_hashes($filter,$hashes) if $hashes;
	my $code=makesub_condition($filter,$depends);
	return $code;
}

sub makesub
{	my $self=$_[0];
	my $filter=$self->{string};
	warn "makesub filter=$filter\n" if $::debug;
	$self->{fields}={};
	if ($filter eq '')		{ $self->{greponly}=$self->{nocache}=1; return $self->{'sub'}=sub {$_[0]}; }
	elsif ($filter eq 'null')	{ $self->{greponly}=$self->{nocache}=1; return $self->{'sub'}=sub { []; }; }

	($filter,my $hashes)=_optimize_with_hashes($filter);

	my $func;
	my $depends=$self->{fields}={};
	if ( $filter=~m#(?:^|\x1D)\w+:-?[th]:# ) { $func=makesub_Ngrep($filter,$depends) }
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
		{	my ($field,$inv,$cmd,$pat)= m/^(\w+):(-?)([^:]+):(.*)$/;
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
	    {	my ($field,$inv,$cmd,$pat)= $f=~m/^(\w+):(-?)([^:]+):(.*)$/;
		$depends->{$_}=undef for Songs::Depends($field);
		unless ($cmd) { warn "Invalid filter : $field $cmd $pat\n"; next; }
		if (my $sub=$NGrepSubs{$cmd})
		{	$func.= $NGrepSubs{$cmd}->($field,$pat,$listref,$in[$d],$inv);
		}
		else
		{	my $c=Songs::FilterCode($field,$cmd,$pat,$inv);
			$func.= $in[$d].'grep( '.$c . ',@{'.$listref.'});';
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

sub name
{	my $self=shift;
	my $h= $::Options{SavedFilters};
	return _"All Songs" if $self->is_empty;
	for my $name (sort keys %$h)
	{	return $name if $self->are_equal($h->{$name});
	}
	return _"Unnamed filter";
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
	    {	next if $f eq '';
		$text.= '  'x$depth;
		$text.= _explain_element($f) || _("Unknown filter :")." '$f'";
		$text.= "\n";
	    }
	}
	chomp $text;	#remove last "\n"
	return $self->{desc}=$text;
}

sub _explain_element
{	my $filter_element=shift;
	my ($field,$inv,$cmd,$pattern)= $filter_element=~m/^(\w+):(-?)([^:]+):(.*)$/;
	return unless $cmd;
	my $text= Songs::Field_property($field,"filterdesc:$inv$cmd:$pattern") || Songs::Field_property($field,"filterdesc:$inv$cmd");
	(undef,my $prop)= Songs::filter_properties($field,"$inv$cmd:$pattern");
	return unless $prop && $text;
	$text=$text->[0] if ref $text;
	my (undef,undef,$types,%opt)=@$prop;
	my (@patterns,@types);
	if ($types)
	{	@types=split / /,$types;
		@patterns= split / /,$pattern, scalar @types;
		push @patterns,('')x(@types-@patterns);
	}

	for my $pat (@patterns)
	{	my $type= shift @types;
		my $opt2= Songs::Field_property($field,'filterpat:'.$type) || [];
		my %opt2= (%opt, @$opt2);
		my $unit=$opt2{unit};
		my $round=$opt2{round};
		if (my $display= $opt2{display}) { $pat= $display->($pat); }
		elsif (($unit || $round) && $pat=~m/^(-?\d*\.?\d+)([a-zA-Z]*)$/) #numbers
		{	my $number=$1;
			my $letter=$2;
			if (ref $unit) # \%::SIZEUNITS, \%::DATEUNITS or %::TIMEUNITS
			{	if ($letter && $unit->{$letter}) { $unit= $unit->{$letter}[1] }
				else {$unit=undef}
			}
			$pat= ::format_number($number,$round);
			$pat.= " ".$unit if $unit;
		}
	}
	$text= sprintf $text, @patterns;
	return Songs::FieldName($field). ' '. $text;
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
	s#((?:\G|[^\\])(?:\\\\)*)([\$@](?:::?)?[0-9a-z])#$1\\$2#gi; #quote variable names if not already quoted
	s#^((?:.*[^\\])?(?:\\\\)*\\)$#$1\\#g; ##escape trailing '\' in impair number
	s!((?:\G|[^\\])(?:\\\\)*)\\?"!$1\\"!g; #make sure " are escaped (and only once, so that \\\" doesn't become \\\\")
	if (!eval {qr/$_/;}) { warn "invalid regular expression \"$_[0]\" : $@\n" if $::debug; return quotemeta $_[0]; }  #check if re valid, else quote everything
	return $_;
}

sub smartstring_fuzzy
{	my ($pat,$op,$casesens,$field)=@_;
	my $threshold= $pat=~s/([<>])(\d?\d)$// ?	($1 eq '>' ? $2 : int(100-100*$2/length($pat))-1) :
							$op eq '#' ? 80 : $op eq '##' ? 70 : 60;
	$threshold=20 if $threshold<20;
	$threshold=99 if $threshold>99;
	return 'fuzzy:'.$threshold.' '.$pat;
}

sub _fuzzy_match
{	my ($min,$string1,$string2)=@_;
	my $length1= length $string1;
	return index($string2,$string1)>=0 unless $length1>1;
	# fast first pass by looking at how many small substrings in common
	if ($min>.35)
	{	my @words;
		for my $l (2,3)
		{	push @words,map substr($string1,$_,$l), 0..($length1-$l);
		}
		my $common= grep index($string2,$_)>=0, @words;
		return 0 unless $common/@words > ($min-.25);
		# the main problem of this method is that longer string2 have higher scores, dividing by string2's length is not possible if you want to search sof substrings of string2
	}
	# local levenshtein distance (much slower)
	# note that some strings with low enough distance might have already been discarded because they didn't have enough small substrings in common
	my @mat=([(0)x (1+length$string2)]);
	$mat[$_]=[$_] for 1..$length1;
	for my $j (1..length $string2)
	{	for my $i (1..$length1)
		{	#if (substr($string1,$i-1,1) eq substr($string2,$j-1,1))
			if (substr($string1,$i-1,1) eq substr($string2,$j-1,1) || substr($string1,$i-1,1) eq "'" || substr($string2,$j-1,1) eq "'") # treat single quote as equal to any character
			{	my $ident= $mat[$i-1][$j-1];
				if ($i==$length1) { my $ins=$mat[$i][$j-1]; $ident=$ins if $ins<$ident; }
				$mat[$i][$j]= $ident;
			}
			else
			{	my $del= $mat[$i-1][$j]+1;
				my $ins= ($i==$length1) ? $mat[$i][$j-1] : $mat[$i][$j-1]+1;
				my $sub= $mat[$i-1][$j-1]+1;
				my $min= $del<$ins ? $del : $ins;
				$mat[$i][$j]= $min < $sub ? $min : $sub;
			}
		}
	}
	return 1-$mat[-1][-1]/$length1 > $min;
}

package IdleFilter;
our %InProgress;

sub clear { %InProgress=(); }

sub new
{	my ($class,$filter,$callback)=@_;
	$filter=Filter->new($filter) unless ref $filter;
	my ($greponly)= $filter->info;
	return 'non-grep filter' unless $greponly;
	my $self= bless {filter => $filter, callback=>$callback, started=>time }, $class;
	$self->start;
	return $self;
}
sub start
{	my $self=shift;
	$self->{idle_handle}=Glib::Idle->add(\&filter_some,$self,1000); # 1000 is very low priority (default is 200, Glib::G_PRIORITY_LOW is 300)
	$self->{count}++;
}
sub is_cached { $_[0]{filter}->is_cached; }

sub get_progress
{	my $self=shift;
	my $filter=$self->{filter};
	my $progress= $InProgress{$filter->{string}};
	unless ($progress)
	{	return 1 if $filter->is_cached;
		if ($self->{count}++ >5 || $self->{started}>15+time) # give up if progress reset too many times or if it has been too long
		{	$self->abort;
			return 0;
		}
		my $todo;
		$todo= $filter->simplify_with_superset_cache if $filter->{superset_filters};
		#warn "idlefilter: todo=".(scalar @$todo)." avoided=".(@$::Library-@$todo)."\n" if $todo;
		#warn "no cache helped\n" unless $todo;
		$todo ||= [@$::Library];
		$progress= $InProgress{$filter->{string}}= { found=>[], todo=>$todo };
	}
	return $progress;
}

sub filter_some
{	my $self=shift;
	my $filter=$self->{filter};
	my $progress= $self->get_progress;
	if (!$progress) { return $self->{idle_handle}=0 }# progress is 0 if given up
	if (ref $progress)
	{	my $sub=$filter->{'sub'} || $filter->makesub;
		my $todo= $progress->{todo};
		my @next= splice @$todo,0,100;
		push @{$progress->{found}}, @{ $sub->(\@next) };
		#warn "idlefilter $self found=".scalar(@{$progress->{found}})." todo=".scalar(@$todo)."\n";
		if (scalar @$todo) { return 1 } # not finished => keep idle
		# last batch done => put results in cache
		delete $InProgress{$filter->{string}};
		$filter->cache_result($progress->{found});
	}

	# finished
	$self->{callback}->();
	return $self->{idle_handle}=0; #remove idle
}

sub abort
{	my $self=shift;
	$self->{aborted}=1;
	Glib::Source->remove(delete $self->{idle_handle}) if $self->{idle_handle};
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
		boolean=>1,
	},
	g =>
	{	desc	=> _"Genre is set",	#depend	=> 'genre',
		default=> '.5g',
		filter	=> 'genre:~:',
		boolean=>1,
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
	M =>
	{	depend	=> 'modif',	desc	=> _"Number of days since modified",	unit	=> _"days",
		round	=> '%.1f',	default=> '1M50',
		value	=> 'modif:daycount',
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
	{	depend	=> 'rating',	desc	=> _"Rating",	unit	=> '%',
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
	{	my ($inverse,$weight,$type,$extra)=$s=~m/^(-?)(\d*\.?\d+)([a-zA-Z])(.*)/;
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

#returns a function, that function takes a listref of IDs as argument, and returns a hashref of groupid=>score
#returns nothing on error
sub MakeGroupScoreFunction
{	my ($self,$field)=@_;
	my ($keycode,$multi)= Songs::LookupCode($field, 'hash','hashm', [ID => '$_']);
	unless ($keycode || $multi) { warn "MakeGroupScoreFunction error : can't find code for field $field\n"; return } #return dummy sub ?
	($keycode,my $keyafter)= split / +---- +/,$keycode||$multi,2;
	if ($keyafter) { warn "MakeGroupScoreFunction with field $field is not supported yet\n"; return } #return dummy sub ?
	my ($before,$score)=$self->make;
	my $calcIDscore= $multi ? 'my $IDscore='.$score.'; for my $key ('.$keycode.') {$score{$key}+=$IDscore}' : "\$score\{$keycode}+=$score;";
	my $code= $before.'; sub { my %score; for (@{$_[0]}) { '.$calcIDscore.' } return \%score; }';
	my $sub=eval $code;
	if ($@) { warn "Error in eval '$code' :\n$@"; return }
	return $sub;
}

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
	{	$self->MakeScoreFunction unless $self->{UpdateIDsScore};
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
	my ($inverse,$weight,$type,$extra)=$string=~m/^(-?)(\d*\.?\d+)([a-zA-Z])(.*)/;
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
	if ($ScoreTypes{$type}{boolean})
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
	my $string_value= $ScoreTypes{$type}{boolean} ? $v : ::format_number($v,$round)." $unit";
	my $string_score= ::format_number($s,'%.2f');
	return "$string_value -> $string_score";
}


1;
