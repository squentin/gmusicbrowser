# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=for gmbplugin LYRICS
name	Lyrics
title	Lyrics plugin
desc	Search and display lyrics
=cut

package GMB::Plugin::LYRICS;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
our @ISA;
BEGIN {push @ISA,'GMB::Context';}
use base 'Gtk3::Box';
use constant
{	OPT	=> 'PLUGIN_LYRICS_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
};

my $notfound=_"No lyrics found";

my @justification=
(	left	=> _"Left aligned",
	center	=> _"Centered",
	right	=> _"Right aligned",
	fill	=> _"Justified",
);

my @ContextMenuAppend=
(	{	label	=> _"Scroll with song",		check	=> sub { $_[0]{self}{AutoScroll} },
		code	=> sub { $::Options{OPT.'AutoScroll'}= $_[1]; $_[0]{self}->SetAutoScroll; },
	},
	{	label	=> _"Hide toolbar",		check	=> sub { $_[0]{self}{HideToolbar} },
		code	=> sub { $_[0]{self}->SetToolbarHide($_[1]);  },
	},
	{	label	=> _"Choose font...",
		code	=> sub { $_[0]{self}->ChooseFont; },
	},
	{	label	=> _"Lyrics alignement",	check	=> sub { $_[0]{self}{justification} },
		submenu	=> \@justification,	submenu_reverse => 1,	submenu_ordered_hash=>1,
		code	=> sub { $_[0]{self}{textview}->set_justification( $_[0]{self}{justification}=$_[1] );  },
	},
);

my %Sites=	# id => [name,url,?post?,function]	if the function return 1 => lyrics can be saved
(	#lyrc	=>	['lyrc','http://lyrc.com.ar/en/tema1en.php','artist=%a&songname=%t'],
	#lyrc	=>	['lyrc','http://lyrc.com.ar/en/tema1en.php?artist=%a&songname=%t',undef,sub
	#	{	local $_=$_[0];
	#		return -1 if m#<a href=[^>]+add[^>]+>(?:[^<]*</?[b-z]\w*)*[^<]*Add a lyric.(?:[^<]*</?[b-z]\w*)*[^<]*</a>#i;
	#		return 1 if s#<a href="\#"[^>]+badsong[^>]+>BADSONG</a>##i;
	#		return 0;
	#	}],
	#leoslyrics =>	['leolyrics','http://api.leoslyrics.com/api_search.php?artist=%a&songtitle=%t'],
	#google	=>	['google','http://www.google.com/search?q="%a"+"%t"'],
	lyriki	=>	['lyriki','http://lyriki.com/index.php?title=%a:%t',undef,
		sub { my $no= $_[0]=~m/<div class="noarticletext">/s; $_[0]=~s/^.*<!--\s*start content\s*-->(.*?)<!--\s*end content\s*-->.*$/$1/s && !$no; }],
	#lyricsplugin => [lyricsplugin => 'http://www.lyricsplugin.com/winamp03/plugin/?title=%t&artist=%a',undef,
	#		sub { my $ok=$_[0]=~m#<div id="lyrics">.*\w\n.*\w.*</div>#s; $_[0]=~s/<div id="admin".*$//s if $ok; return $ok; }],
	lyricssongs =>	['lyrics-songs',sub {  ::ReplaceFields($_[0], "http://letras.terra.com.br/winamp.php?musica=%t&artista=%a", sub {::url_escapeall(::superlc($_[0]));})  },undef,
			sub {	my $is_suggestion= $_[0]=~m#<h3>Provável música</h3>#i;
				my $l=html_extract($_[0],div=>'letra');
				$l=~s#<div id="cabecalho">.*?</div>##s if $l; #remove header with title and artist links
				my $ref=\$_[0];
				$$ref= $l ? $l : $notfound;
				return $l && !$is_suggestion;
			}],
	lyricwiki =>	[lyricwiki => 'http://lyrics.wikia.com/%a:%t',undef,
			 sub {	return 0,'http://lyrics.wikia.com/'.$1 if $_[0]=~m#<span class="redirectText"><a href="/([^"]+)"#;
				$_[0]=~s!.*<div class='lyricbox'>.*?((?:&\#\d+;|<br ?/>|</?[bi]>){5,}).*!$1!s; #keep only the "lyric box"
				return 0 if $_[0]=~m!&#91;&#46;&#46;&#46;&#93;(?:<br ?/>)*<i>!; # truncated lyrics : "[...]" followed by italic explanation => not auto-saved
				return !!$1;
			}],	
	musixmatch =>   [musixmatch =>
                         sub {
                             ::ReplaceFields($_[0], 'https://www.musixmatch.com/lyrics/%a/%t', sub {
                                     $_[0] =~ s/ (&|\*|\-) / /gr
                                           =~ s/(\'|\,|\.) / /gr
                                           =~ s/\(.*?\)//gr # remove comments in parenthesis: a.e. (Extended Version), (Chillout Mix), etc
                                           =~ s/^\s+|\s+$//gr
                                           =~ s/\s/-/gr
                                     });
                         },
                         undef,
                         sub {
                             my $text;
                             if($_[0] =~ /"body":"(.*?)","/){
                                $text = $1 =~ s|\\n|<br>|gr =~ s|\\(["'])|$1|gr;
                             }
                             $_[0] = $text || $notfound;
                             return !!$text;
                         }],
       #lyricwikiapi => [lyricwiki => 'http://lyricwiki.org/api.php?artist=%a&song=%t&fmt=html',undef,
	#	sub { $_[0]!~m#<pre>\W*Not found\W*</pre>#s }],
	#azlyrics => [ azlyrics => 'http://search.azlyrics.com/cgi-bin/azseek.cgi?q="%a"+"%t"'],
	#Lyricsfly ?
	AUTO	=> [_"Auto",],	#special mode that search multiple sources
);

$::Options{OPT.'Font'} ||= delete $::Options{OPT.'FontSize'};	#for versions <1.1.6

if (my $site=$::Options{OPT.'LyricSite'}) { delete $::Options{OPT.'LyricSite'} unless exists $Sites{$site} } #reset selected site if no longer defined
::SetDefaultOptions(OPT, Font => 10, PathFile => "~/.lyrics/%a/%t.lyric", LyricSite => 'lyricssongs', PreferEmbeddedLyrics=>0);


my $lyricswidget=
{	class		=> __PACKAGE__,
	tabicon		=> 'gmb-lyrics',		# no icon by that name by default
	tabtitle	=> _"Lyrics",
	saveoptions	=> 'HideToolbar font follow justification edit',
	schange		=> sub { $_[0]->SongChanged($_[1]); }, #$_[1] is new ID
	group		=> 'Play',
	autoadd_type	=> 'context page lyrics text',
	justification	=> 'left',
	edit		=> 0,
};

sub Start
{	Layout::RegisterWidget(PluginLyrics => $lyricswidget);
}
sub Stop
{	Layout::RegisterWidget(PluginLyrics => undef);
}

sub new
{	my ($class,$options)=@_;
	my $self= bless Gtk3::VBox->new(0,0), $class;
	$options->{follow}=1 if not exists $options->{follow};
	$self->{$_}=$options->{$_} for qw/HideToolbar follow group font justification edit/;

	my $textview= Gtk3::TextView->new;
	$self->signal_connect(map => sub { $_[0]->SongChanged( ::GetSelID($_[0]) ); });
	$self->signal_connect_after(key_press_event	=> \&key_pressed_cb);
	$textview->signal_connect(button_release_event	=> \&button_release_cb);
	$textview->signal_connect(motion_notify_event 	=> \&update_cursor_cb);
	$textview->signal_connect(visibility_notify_event=>\&update_cursor_cb);
	$textview->signal_connect(scroll_event		=> \&scroll_cb);
	$textview->signal_connect(populate_popup	=> \&populate_popup_cb);
	$textview->set_wrap_mode('word');
	$textview->set_justification( $self->{justification} );
	$textview->set_left_margin(5);
	$textview->set_right_margin(5);
	if (my $color= $options->{color} || $options->{DefaultFontColor})
	{	$textview->override_color('normal', Gtk3::Gdk::RGBA->parse($color) );
	}
	$self->{buffer}=$textview->get_buffer;
	$self->{textview}=$textview;
	$self->{DefaultFocus}=$textview;
	my $sw= Gtk3::ScrolledWindow->new;
	$sw->set_shadow_type( $options->{shadow} || 'etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);
	my $toolbar= Gtk3::Toolbar->new;
	$toolbar->set_style( $options->{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $options->{ToolbarSize}||'small-toolbar' );
	for my $aref
	(	[backb => 'gtk-go-back',\&Back_cb,	_"Previous page"],
		[saveb => 'gtk-save',	\&Save_text,	_"Save",	_"Save lyrics"],
		[undef, 'gtk-refresh',	\&Refresh_cb,	_"Refresh"],
	)
	{	my ($key,$stock,$cb,$label,$tip)=@$aref;
		my $item= Gtk3::ToolButton->new_from_stock($stock);
		$item->set_label($label);
		$item->signal_connect(clicked => $cb);
		$item->set_tooltip_text($tip) if $tip;
		$toolbar->insert($item,-1);
		::weaken( $self->{$key}=$item ) if $key;
	}
	$self->{saveb}->set_is_important(1);

	# create follow toggle button, function from GMB::Context
	my $follow=$self->new_follow_toolitem;

	$self->{editb}= my $editmode= Gtk3::ToggleToolButton->new_from_stock('gtk-edit');
	$editmode->signal_connect(toggled=> sub { SetEditable($_[0],$_[0]->get_active); });
	$editmode->set_tooltip_text(_"Edit mode");

	my $adj= $self->{fontsize_adj}= Gtk3::Adjustment->new(10,4,80,1,5,0);
	my $zoom= Gtk3::ToolItem->new;
	my $zoom_spin= Gtk3::SpinButton->new($adj,1,0);
	$zoom->add($zoom_spin);
	$zoom->set_tooltip_text(_"Font size");
	my $source=::NewPrefCombo( OPT.'LyricSite', { map {$_=>$Sites{$_}[0]} keys %Sites} ,cb => \&Refresh_cb, toolitem=> _"Lyrics source");
	my $scroll=::NewPrefCheckButton( OPT.'AutoScroll', _"Auto-scroll", cb=>\&SetAutoScroll, tip=>_"Scroll with the song", toolitem=>1);
	$toolbar->insert($_,-1) for $editmode,$follow,$zoom,$scroll,$source;

	$self->pack_start($toolbar,0,0,0);
	$self->add($sw);
	$self->{toolbar}=$toolbar;
	$self->signal_connect(destroy => \&destroy_event_cb);

	$self->{buffer}->signal_connect(modified_changed => sub {$_[1]->set_sensitive($_[0]->get_modified);}, $self->{saveb});
	$self->{backb}->set_sensitive(0);
	$self->SetFont;
	$zoom_spin->signal_connect(value_changed=> sub { my $self= $_[0]->GET_ancestor; $self->SetFont($_[0]->get_value) });
	$self->SetToolbarHide($self->{HideToolbar});
	$self->SetAutoScroll;
	$self->SetEditable($self->{edit});

	return $self;
}
sub destroy_event_cb
{	my $self=shift;
	$self->cancel;
}

sub cancel
{	my $self=shift;
	delete $::ToDo{'8_lyrics'.$self};
	$self->{waiting}->abort if $self->{waiting};
	$self->{waiting}=$self->{pixtoload}=undef;
}

sub prefbox
{	my $vbox= Gtk3::VBox->new(::FALSE, 2);
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Lyrics file :", width=>30, tip=> _"Lyrics file name format" );
	my $preview= Label::Preview->new(preview => \&filename_preview, event => 'CurSong Option', noescape=>1,wrap=>1);
	my $autosave=::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds", tip=>_"only works with some lyrics source and when the lyrics tab is active");
	my $embed=::NewPrefCombo(OPT.'PreferEmbeddedLyrics', { 0=> _"lyrics file", 1=> _"file tag"},
		text=>_"Prefered place to load and save lyrics :");
	my $alwaysload=::NewPrefCheckButton(OPT.'AlwaysLoad' => _"Load lyrics even if lyrics panel is hidden");
	my $Bopen= Gtk3::Button->new(_"open context window");
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $embed,$entry,$preview,$autosave,$alwaysload,$Bopen;
	return $vbox;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
	$t= ::filename_to_utf8displayname($t) if $t;
	$t= $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
	return '<small>'.$t.'</small>';
}

sub SetToolbarHide
{	my ($self,$hide)=@_;
	$self->{HideToolbar}=$hide;
	my $toolbar=$self->{toolbar};
	if ($self->{HideToolbar})	{$toolbar->set_no_show_all(1); $toolbar->hide}
	else				{$toolbar->set_no_show_all(0); $toolbar->show_all}
}

sub SetEditable
{	my $self= $_[0]->GET_ancestor;
	my $on=$_[1];
	$self->{edit}=$on;
	my $view=$self->{textview};
	$view->set_editable($on);
	$view->set_cursor_visible($on);
	$self->{editb}->set_active($on) if $self->{editb}->get_active xor $on;
}

sub SetAutoScroll
{	my $self= $_[0]->GET_ancestor;
	if ($self->{AutoScroll}=$::Options{OPT.'AutoScroll'})
		{ ::Watch($self,Time => \&TimeChanged); }
	else	{ ::UnWatch($self,'Time'); };
}
sub SetFont
{	my ($self,$newfont)=@_;
	return if $self->{busy};
	$self->{busy}=1;
	my $textview=$self->{textview};
	my $font= $self->{font} || $::Options{OPT.'Font'};
	my $size;
	if ($newfont)
	{	if ($newfont=~m/\D/ || !$font) { $font=$newfont }
		else { $size=$newfont }
	}
	my $fontdesc= Pango::FontDescription::from_string($font);
	$fontdesc->set_size( $size * Pango->SCALE ) if $size;

	# update spin button
	$size= $fontdesc->get_size / Pango->SCALE;
	my $adj=$self->{fontsize_adj};
	$adj->set_value( $size );

	$::Options{OPT.'Font'}= $self->{font}= $fontdesc->to_string;
	$textview->modify_font($fontdesc);
	delete $self->{busy};
}
sub ChooseFont
{	my $self=shift;
	my $dialog= Gtk3::FontSelectionDialog->new(_"Choose font for lyrics");
	$dialog->set_font_name( $self->{font} );
	my $response= $dialog->run;
	if ($response eq 'ok')
	{	$self->SetFont( $dialog->get_font_name );
	}
	$dialog->destroy;
}

sub Set_message
{	my ($self,$text) = @_;
	$self->{buffer}->set_text("");
	my $iter=$self->{buffer}->get_start_iter;
	my $tag_noresults=$self->{buffer}->create_tag(undef,justification=>'center',font=>20,foreground_rgba=>Gtk3::Gdk::RGBA::parse('grey'));
	$self->{buffer}->insert_with_tags($iter,"\n$text",$tag_noresults);
	$self->{buffer}->set_modified(0);
}

sub Back_cb
{	my $self= $_[0]->GET_ancestor;
	my $url=pop @{$self->{history}};
	$_[0]->set_sensitive(0) unless @{$self->{history}};
	$self->{lastokurl}=undef;
	$self->load_url($url) if $url;
}
sub Refresh_cb
{	my $self= $_[0]->GET_ancestor;
	$self->SongChanged($self->{ID},'force');
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless $self->get_mapped || $::Options{OPT.'AlwaysLoad'};
	return unless defined $ID;
	return if defined $self->{ID} && !$force && ( $ID==$self->{ID} || !$self->{follow} );
	$self->cancel;	#cancel any lyrics operation in progress on an a previous song
	$self->{ID}=$ID;
	$self->{time}=undef;

	if (!$force)
	{	::IdleDo('8_lyrics'.$self,1000,\&load_from_file,$self);
	}
	else { $self->load_from_web; }
}

sub load_from_web
{	my ($self,$next)=@_;
	my $site;
	if ($next)
	{	$site = shift @{$self->{trynext}};
		if (!$site)
		{	$self->Set_message(_"No lyrics found");
			return;
		}
	}
	else
	{	$site = $::Options{OPT.'LyricSite'};
		delete $self->{trynext};
		if ($site eq 'AUTO')
		{	($site,@{$self->{trynext}})= qw/lyricssongs lyricwiki musixmatch/;	#FIXME make it configurable
		}
	}
	return unless $site;
	my (undef,$url,$post,$check)=@{$Sites{$site}};
	my $ID= $self->{ID};
	for my $val ($url,$post)
	{	next unless defined $val;
		if (ref $val) { $val= $val->($ID); }
		else { $val= ::ReplaceFields($ID, $val, \&::url_escapeall); }
	}
	return unless $url;
	::IdleDo('8_lyrics'.$self,1000,\&load_url,$self,$url,$post,$check);
}

sub TimeChanged		#scroll the text
{	my $self=$_[0];
	return unless defined $::SongID && defined $self->{ID} && $self->{ID} eq $::SongID;
	return unless defined $::PlayTime;
	my $adj=($self->get_children)[1]->get_vadjustment;
	my $range=($adj->get_upper - $adj->get_lower - $adj->get_page_size);
	return unless $range >0;
	return if $adj->get_value > $adj->get_upper - $adj->get_page_size;
	my $delta=$::PlayTime - ($self->{time} || 0);
	return if abs($delta) <1;
	my $inc=$delta / Songs::Get($::SongID,'length');
	$self->{time}=$::PlayTime;
	$adj->set_value($adj->get_value+$inc*$range);
}

sub populate_popup_cb
{	my ($textview,$menu)=@_;
	my $self= $textview->GET_ancestor;

	# add menu items for links
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$textview->get_pointer);
	if (my $url=$self->url_at_coords($x,$y))
	{	my $item2= Gtk3::MenuItem->new(_"Open link in Browser");
		$item2->signal_connect(activate => sub	{ ::openurl($url); });
		my $item3= Gtk3::MenuItem->new(_"Copy link address");
		$item3->signal_connect(activate => sub
		{	my $url=$_[1];
			my $clipboard=$_[0]->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'));
			$clipboard->set_text($url);
		},$url);
		$menu->prepend($_) for Gtk3::SeparatorMenuItem->new, $item3,$item2;
	}

	$menu->append(Gtk3::SeparatorMenuItem->new);
	::BuildMenu( \@ContextMenuAppend, { self=>$self, }, $menu );

	$menu->show_all;
}

sub html_extract
{	my ($data,$tag,$id)=@_;
	my $re=qr/<\Q$tag\E [^>]*id="(\w+)"[^>]*>|<(\/)?\Q$tag\E>/i;
	my ($start,$depth);
	while ($data=~m/$re/g)
	{	if ($2) #closing
		{	if ($depth)
			{	$depth--;
				return substr $data,$start,$+[0]-$start unless $depth;
			}
		}
		elsif ($depth)
		{	$depth++
		}
		elsif (defined $1 && $1 eq $id)
		{	$start=$-[0];
			$depth=1;
		}
	}
}

sub load_url
{	my ($self,$url,$post,$check)=@_;
	$self->Set_message(_"Loading...");
	$self->cancel;
	warn "lyrics : loading $url\n";# if $::debug;
	$self->{url}=$url;
	$self->{post}=$post;
	$self->{check}=$check; # function to check if lyrics found
	$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url,post => $post);
}

sub loaded #_very_ crude html to gtktextview renderer
{	my ($self,$data,%data_prop)=@_;
	delete $self->{waiting};
	my $type=$data_prop{type};
	my $buffer=$self->{buffer};
	my $encoding;
	unless ($data) { $data=_("Loading failed.").qq( <a href="$self->{url}">)._("retry").'</a>'; $type="text/html"; $encoding=0; }
	$self->{url}=$data_prop{url} if $data_prop{url}; #for redirections
	$buffer->delete($buffer->get_bounds);
	if ($type && $type=~m#^text/.*; ?charset=([\w-]+)#) {$encoding=$1}
	if ($type && $type!~m#^text/html#)
	{	if	($type=~m#^text/#)	{$buffer->set_text($data);}
		elsif	($type=~m#^image/#)
		{	my $loader= GMB::Picture::LoadPixData($data);
			if (my $p=$loader->get_pixbuf) {$buffer->insert_pixbuf(0,$p);}
		}
		return;
	}
	$encoding=$1 if $data=~m#<meta *http-equiv="Content-Type" *content="text/html; charset=([\w-]+)"#;
	$encoding='cp1252' if $encoding && $encoding eq 'iso-8859-1'; #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding//='cp1252'; #default encoding
	$data=Encode::decode($encoding,$data) if $encoding;

	my $oklyrics;
	if (my $check=$self->{check})
	{	($oklyrics,my $redirect)= $check->($data,$self->{ID});
		if ($redirect) { $self->load_url($redirect,undef,$check); return; }
		if ($self->{trynext} && !($oklyrics && $oklyrics>0)) { $self->load_from_web('trynext'); return }
	}
	if ($self->{lastokurl})
	{	my $history=$self->{history}||=[];
		push @$history,$self->{lastokurl};
		$#$history=20 if $#$history>20;
		$self->{backb}->set_sensitive(1) if @$history==1;
	}
	$self->{lastokurl}=$self->{url};

	for ($data)
	{s/<!--.*?-->//gs;
	 s#<noscript>.*</noscript>##gsi; #added to remove warnings from lyrc.com.ar, maybe should be restricted to lyrc.com.ar ?
	}

	my (%prop,$ul,@urls,@pixbufs,$title,%namedanchors,$li);
	my $iter=$buffer->get_start_iter;
	my @l=split /(<[^>]*>)/s, $data;
	while (defined($_=shift @l))
	{	s/[\r\n]//g;
		s/\s+/ /g;
		next if $_ eq ' ';
		s#&nbsp;# #gi;
		s#<br(?: */)?>#\n#gi;
		if ($_ eq '<pre>') {$_="\n".shift(@l)."\n"}
		if (m/^[^<]/) # insert text
		{	if ($ul && $li)
			{	$buffer->insert($iter, (' 'x$ul).' - ');
				$li=0;
			}
			my $text=::decode_html($_);
			if (keys %prop)
			{ my $tag=$buffer->create_tag(undef,%prop);
			  $buffer->insert_with_tags($iter, $text, $tag);
			}
			else	{$buffer->insert($iter, $text);}
		}
		elsif (m#^<(script|style)[ >]#i) {shift @l while @l && $l[0] ne "</$1>"}
		elsif (m#^<ul[ >]#i) {$buffer->insert($iter,"\n");$ul++}
		elsif (m#^<li[ >]#i) {$li=1}
		elsif (m#^<p[ >]#i) {$buffer->insert($iter,"\n");}
		elsif (my ($tag,$p)=m#^<(\w+) (.*)>$#)
		{	my %p;
			#$p{$1}=$3 while $p=~m/(\w+)=(["'])(.+?)\2/sg;
			$p{$1}=$3 while $p=~m/\G\s*(\w+)=(["'])(.*?)\2/gc || $p=~m/\G\s*(\w+)()=(\S+)/gc;
			if ($tag eq 'a')
			{ if	(exists $p{href}) { push @urls,$iter->get_offset,$p{href}; }
			  elsif	(exists $p{name}) { $namedanchors{$p{name}}=$iter->get_offset; }
			}
			elsif ($tag eq 'font' && 0)
				{ if (my $s=$p{size})
				  {	if ($s=~m/^\d+$/) {$prop{scale}=$s*.33}
					elsif ($s=~m/^(-?\d+)$/) {$prop{scale}||=1;$prop{scale}+=$1*.33}
					else {delete $prop{scale};}
					warn "$s => ".($prop{scale}||"")."\n";
				  }
				  else {delete $prop{scale};}
				}
			elsif ($tag=~m/^h(\d)/i)
				{ $prop{scale}=(3,2.5,2,1.5,1.2,1,.66)[$1];
				  $prop{weight}= ::PANGO_WEIGHT_BOLD if $1 eq '1';
				}
			elsif ($tag eq 'table') {$buffer->insert($iter,"\n");}
			elsif ($tag eq 'img' && exists $p{src})
			{	my $mark=$buffer->create_mark(undef,$iter,1);
				push @pixbufs,[$mark, $p{src}, (@urls%3==2 ? $urls[-1] : ())];
			}
			if (exists $p{id}) {$namedanchors{$p{id}}=$iter->get_offset;}
		}
		elsif (m#^</(\w+)>$#)
		{	if    ($1 eq 'a')	{push @urls,$iter->get_offset if @urls%3==2;}
			elsif ($1 eq 'u')	{delete $prop{underline};}
			elsif ($1 eq 'b')	{delete $prop{weight};}
			elsif ($1 eq 'i')	{delete $prop{style};}
			elsif ($1 eq 'font')	{delete $prop{scale};}
			elsif ($1=~m/^h(\d)/i)	{delete $prop{scale};delete $prop{weight};$buffer->insert($iter,"\n");}
			elsif ($1 eq 'ul')	{$buffer->insert($iter,"\n");$ul--;}
			elsif ($1 eq 'tr')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'li')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'p')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'div')	{$buffer->insert($iter,"\n");}
		}
		elsif (m#^<(\w+)>$#)
		{	if    ($1 eq 'u')	{$prop{underline}='single';}
			elsif ($1 eq 'b')	{$prop{weight}= ::PANGO_WEIGHT_BOLD;}
			elsif ($1 eq 'i')	{$prop{style}='italic';}
			elsif ($1 eq 'title')	{$title=shift @l while $l[0] ne "</$1>"}
		}
	}
	while (@urls)
	{	my ($offs1,$url,$offs2)=splice @urls,0,3;
		my $tag=$buffer->create_tag(undef,foreground => 'blue',underline => 'single');
		if ($url=~m/^#(.*)/)
		{	if (exists $namedanchors{$1}) {$url='#'.$namedanchors{$1};}
			else {next}
		}
		$tag->{url}=$url;
		$buffer->apply_tag($tag,
			$buffer->get_iter_at_offset($offs1),
			$buffer->get_iter_at_offset($offs2));
	}
	for my $url (map $_->[2], grep @$_>2, @pixbufs)
	{	next unless $url=~m/^#(.*)/;
		if (exists $namedanchors{$1}) {$url='#'.$namedanchors{$1};}
		else {$url=undef}
	}

	if (0)
	{	$self->{pixtoload}=\@pixbufs;
		::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self) if @pixbufs;
	}
	if ($oklyrics && $oklyrics>0)
	{	$self->Save_text if $::Options{OPT.'AutoSave'};
	}
	#else { $buffer->set_modified(0); }
}

sub load_pixbuf
{	my $self=shift;
	my $ref=shift @{ $self->{pixtoload} };
	return 0 unless $ref;
	my ($mark,$url,$link)=@$ref;
	$self->{waiting}=Simple_http::get_with_cb(url => $self->full_url($url), cache=>1, cb=>
	sub
	{	$self->{waiting}=undef;
		my $loader;
		$loader= GMB::Picture::LoadPixData($_[0]) if $_[0];
		if ($loader)
		{	my $buffer=$self->{buffer};
			my $iter=$buffer->get_iter_at_mark($mark);
			$buffer->delete_mark($mark);
			my $offset=$iter->get_offset;
			$buffer->insert_pixbuf($iter,$loader->get_pixbuf);
			if ($link)
			{	my $tag=$buffer->create_tag(undef,foreground => 'blue');
				$tag->{url}=$link;
				$buffer->apply_tag($tag,$buffer->get_iter_at_offset($offset),$iter);
			}
		}
		::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self); #load next
	});
#::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self) unless $self->{waiting};
}

#sub loaded_old #old method, more crude :)
#{	my $self=shift;
#	my $buffer=$self->{buffer};
#	unless ($_[0]) {$buffer->delete($buffer->get_bounds);$buffer->set_text(_"Loading failed.");return;}
#	local $_=$_[0];
#	s/[\r\n]//g;
#	s#<title>.*?</title>##;
#	s#<script .*?</script>##g;
#	s#<a href="([^"]+)">(.*?)</a>#<>$2<>$1<>#g;
#	s#<br(?: /)?>#\n#g;
#	s/<[^>]+>//g;
#	s/^\n+//;
#	s/BADSONG\n+$//;

#	$buffer->delete($buffer->get_bounds);
#	my @l=split /(<>)/,$_;
#	while (defined ($_=shift @l))
#	{	my $iter=($buffer->get_bounds)[1];
#		if ($_ eq '<>')
#		{	my ($text,undef,$url,undef)=splice @l,0,4;
#			my $tag=$buffer->create_tag(undef,foreground => 'blue',underline => 'single');
#			$tag->{url}=$url;
#			$buffer->insert_with_tags($iter, $text, $tag);
#		}
#		else { $buffer->insert($iter, $_);}
#	}
#}
my %zoomkeymap;
BEGIN { %zoomkeymap=( plus=>1, minus=>-1, KP_Add=>1, KP_Subtract=>-1 ); }
sub key_pressed_cb
{	my ($self,$event)=@_;
	my $key= Gtk3::Gdk::keyval_name( $event->keyval );
	my $state=$event->get_state;
	my $ctrl= $state * ['control-mask'] && !($state * [qw/mod1-mask mod4-mask super-mask/]); #ctrl and not alt/super
	return 0 unless $ctrl; #only ctrl- shortcuts so far
	if (lc$key eq 'e') { $self->SetEditable(!$self->{edit}); }
	elsif (exists $zoomkeymap{$key})
	{	my $size= $self->{fontsize_adj}->get_value;
		$size+= $zoomkeymap{$key};
		$self->{fontsize_adj}->set_value($size);
	}
	else {return 0}
	return 1;
}

sub scroll_cb	#zoom with ctrl-wheel
{	my ($textview,$event) = @_;
	return 0 unless $event->state >= 'control-mask';
	my $self= $textview->GET_ancestor;
	my $size= $self->{fontsize_adj}->get_value;
	$size+= $event->direction eq 'up' ? 1 : -1;
	$self->{fontsize_adj}->set_value($size);
	return 1;
}

sub button_release_cb
{	my ($textview,$event) = @_;
	my $self= $textview->GET_ancestor;
	return ::FALSE unless $event->button == 1;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $url=$self->url_at_coords($x,$y);
	$self->load_url($url) if $url;
	return ::FALSE;
}

sub url_at_coords
{	my ($self,$x,$y)=@_;
	my $iter=$self->{textview}->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		if ($tag->{url}=~m/^#(\d+)?/) { $self->scrollto($1) if defined $1; last }
		my $url= $self->full_url( $tag->{url} );
		if ($url=~m#^http://www\.lyrc\.com\.ar/en/add/add\.php\?#) {::openurl($url); return}	#lyrc specific
		return $url;
	}
}

sub scrollto
{	my ($self,$offset)=@_;
	my $iter=$self->{buffer}->get_iter_at_offset($offset);
	$self->{textview}->scroll_to_iter($iter, 0, ::TRUE, 0, .5);
}

sub full_url
{	my ($self,$url)=@_;
	return $url if $url=~m#^http://#;
	my $base=$self->{url};
	if ($url=~m#^/#){$base=~s#^(?:http://)?([^/]+).*$#$1#;}
	else		{$base=~s#[^/]*$##;}
	return $base.$url;
}


sub update_cursor_cb
{	my $textview=$_[0];
	my (undef,$wx,$wy,undef)= $textview->get_window('text')->get_pointer;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter=$textview->get_iter_at_location($x,$y);
	my $cursor='xterm';
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		$cursor='hand2';
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor}=$cursor;
	$textview->get_window('text')->set_cursor(Gtk3::Gdk::Cursor->new($cursor));
}

sub load_from_file
{	my $self=shift;
	my $ID= $self->{ID};
	my $text= $::Options{OPT.'PreferEmbeddedLyrics'} ?
		FileTag::GetLyrics($ID) || _load_from_lyrics_file($ID) :
		_load_from_lyrics_file($ID) || FileTag::GetLyrics($ID) ;

	# if no lyrics found, try the web
	unless ($text)
	{	$self->load_from_web;
		return
	}

	# display the lyrics
	my $buffer=$self->{buffer};
	$buffer->delete($buffer->get_bounds);
        $buffer->set_text($text);

	#make the title and artist bigger and bold
	my ($title,$artist)= Songs::Get($ID,qw/title artist/);
	$title='' if $title!~m/\w\w/;
	for ($title,$artist)
	{	if (m/\w\w/) {s#\W+#\\W*#g}
		else {$_=''}
	}
	$artist='(?:by\W+)?'.$artist if $artist;
	if ($text && $text=~m#^\W*($title\W*\n?(?:$artist)?)\W*\n#si)
	{ my $tag=$buffer->create_tag(undef,scale => 1.5,weight=> ::PANGO_WEIGHT_BOLD);
	  $buffer->apply_tag($tag,$buffer->get_iter_at_offset($-[0]),$buffer->get_iter_at_offset($+[0]));
	}

	$buffer->set_modified(0);
}

sub _load_from_lyrics_file
{	my $ID=shift;
	my $file=::pathfilefromformat( $ID, $::Options{OPT.'PathFile'}, undef,1 );
	return unless $file && -e $file;
	my $text= _"Loading failed.";
	if (open my$fh,'<',$file)
	{	local $/=undef; #slurp mode
		$text=<$fh>;
		close $fh;
		if (my $utf8=Encode::decode_utf8($text)) {$text=$utf8}
	}
	return $text;
}

sub Save_text
{	my $self= $_[0]->GET_ancestor;
	my $win=$self->get_toplevel;
	my $buffer=$self->{buffer};
	my $text= $buffer->get_text($buffer->get_bounds, ::FALSE);
	if ($::Options{OPT.'PreferEmbeddedLyrics'})
	{	FileTag::WriteLyrics($self->{ID},$text);
		$buffer->set_modified(0);
	}
	else
	{	my $format=$::Options{OPT.'PathFile'};
		my ($path,$file)=::pathfilefromformat( $self->{ID}, $format, undef,1 );
		unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$win); return}
		my $res=::CreateDir($path,$win,_"Error saving lyrics");
		return unless $res eq 'ok';
		if (open my$fh,'>:utf8',$path.::SLASH.$file)
		{	print $fh $text;
			close $fh;
			$buffer->set_modified(0);
			warn "Saved lyrics in ".$path.::SLASH.$file."\n" if $::debug;
		}
		else {::ErrorMessage(::__x(_("Error saving lyrics in '{file}' :\n{error}"), file => $file, error => $!),$win);}
	}
}

1
