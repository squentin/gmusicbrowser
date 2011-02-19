# Copyright (C) 2005-2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package Play_GST;
use strict;
use warnings;

my ($GST_ok,$GST_visuals_ok,$GST_EQ_ok,$GST_RG_ok,$playbin2_ok); our $GST_RGA_ok;
my ($PlayBin,$Sink);
my ($WatchTag,$Skip);
my (%Plugins,%Sinks);
my ($VSink,$visual_window);
my $AlreadyNextSong;
my $RG_dialog;

$::PlayPacks{Play_GST}=1; #register the package

my $reg_keep; #work-around to keep the register from being finalized in gstreamer<0.10.4 (see http://bugzilla.gnome.org/show_bug.cgi?id=324818)


BEGIN
{ %Sinks=
  (	autoaudio	=> { name => _"auto detect", },
	oss		=> { option => 'device' },
	esd		=> { option => 'host'},
	alsa		=> { option => 'device'},
	artsd		=> {},
	sdlaudio	=> {},
	gconfaudio	=> { name => _"use gnome settings"},
	halaudio	=> { name => "HAL device", option=>'udi'},
	pulse		=> { name => "PulseAudio", option=>'server device'},
	jackaudio	=> { name => "JACK", option => 'server' },
	osxaudio	=> {},
	directsound	=> {},
	#alsaspdif	=> { name => "alsa S/PDIF", option => 'card' },
	#oss4		=> {},
	#nas		=> {},
  );
  %Plugins=(	mp3	=> 'mad',	oga => 'vorbisdec',	ape => 'ffdec_ape',
		flac	=> 'flacdec',	mpc => 'musepackdec',	wv => 'wavpackdec',
		m4a	=> 'faad',
	);
  my $error;
  my $reg;
  if (grep -f $_.'/GStreamer.pm',@INC)
  {	eval {require GStreamer};
	$error="Needs GStreamer version >= 0.05\n" if !$@ && GStreamer->VERSION<.05;
	if (!$@ && !$error && GStreamer->init_check)
	{	GStreamer->init;
		$reg=GStreamer::Registry->get_default;
		$reg_keep=$reg if GStreamer->CHECK_VERSION(0,10,4);
		$playbin2_ok= $reg->lookup_feature('playbin2');
		if ( $playbin2_ok || $reg->lookup_feature('playbin') ) { $GST_ok=1; }
		else { $error="gstreamer plugin 'playbin' not found\nYou need to install at least gst-plugins-base\n"; }
	}
	else { $error=$@? $@ : "Can't initialize GStreamer.\n"; }
  }
  else {$error="GStreamer.pm not found\n";}
  if ($error) {warn "$error -> gstreamer output won't be available.\n"}
  if ($GST_ok)
  {	$::Options{gst_sink}||= (grep ($reg->lookup_feature($_.'sink'), qw/autoaudio gconfaudio alsa esd pulse oss/),'alsa')[0]; #find a default sink
	if ($reg->lookup_feature('equalizer-10bands')) { $GST_EQ_ok=1; }
	else {warn "gstreamer plugin 'equalizer-10bands' not found -> equalizer not available\n";}
	if ($reg->lookup_feature('rglimiter') && $reg->lookup_feature('rgvolume')) { $GST_RG_ok=1; }
	else {warn "gstreamer plugins 'rglimiter' and/or 'rgvolume' not found -> replaygain not available\n";}
	if ($reg->lookup_feature('rganalysis')) { $GST_RGA_ok=1; }
	else {warn "gstreamer plugins 'rganalysis' not found -> replaygain analysis not available\n";}
	$GST_visuals_ok=1;
	eval {require GStreamer::Interfaces};
	if ($@) {warn "GStreamer::Interfaces perl module not found -> visuals not available\n"; $GST_visuals_ok=0;}
	unless ($reg->lookup_feature('ximagesink'))
	{	warn "gstreamer plugin 'ximagesink' not found -> visuals not available\n"; $GST_visuals_ok=0;
	}
  }

}

sub supported_formats
{	return '' unless $GST_ok;
	my $reg=GStreamer::Registry->get_default;
	return grep $reg->lookup_feature($Plugins{$_}), keys %Plugins;
}
sub supported_sinks
{	return {} unless $GST_ok;
	my $reg=GStreamer::Registry->get_default;
	$Sinks{$_}{ok}= ! !$reg->lookup_feature($_.'sink') for keys %Sinks;
	#$::Options{gst_sink}='autoaudio' unless $Sinks{$::Options{gst_sink}};
	return {map { $_ => $Sinks{$_}{name}||$_ } grep $Sinks{$_}{ok}, keys %Sinks};
}

sub init
{	return undef unless $GST_ok;
	#createPlayBin();
	return bless { EQ=>$GST_EQ_ok, visuals => $GST_visuals_ok },__PACKAGE__;
}

sub createPlayBin
{	if ($PlayBin) { $PlayBin->get_bus->remove_signal_watch; }
	my $pb= $playbin2_ok ? 'playbin2' : 'playbin';
	$PlayBin=GStreamer::ElementFactory->make($pb => 'playbin'); #FIXME only the first one used works
	$PlayBin->set('flags' => [qw/audio soft-volume/]) if $playbin2_ok;
	$PlayBin->set(volume => ($::Volume/100)**3); 	#initialize volume, use a cubic volume scale
	my $bus=$PlayBin->get_bus;
	$bus->add_signal_watch;
#	$bus->signal_connect('message' => \&bus_message);
	$bus->signal_connect('message::eos' => \&bus_message_end);
	$bus->signal_connect('message::error' => \&bus_message_end,1);
	$bus->signal_connect('message::state-changed' => \&bus_message_state_changed);
	$PlayBin->signal_connect(about_to_finish => \&about_to_finish) if $::Options{gst_gapless};
	if ($visual_window) { create_visuals() }
}

#sub bus_message
#{	my $msg=$_[1];
#	warn 'bus: message='.$msg->type."\n" if $::debug;
#	SkipTo(undef,$Skip) if $Skip && $msg->type & 'state_changed';
#	return unless $msg->type & ['eos','error'];
#	if ($Sink->get_name eq 'server') #FIXME
#	{ $Sink->set_locked_state(1); $PlayBin->set_state('null'); $Sink->set_locked_state(0); }
#	else { $PlayBin->set_state('null'); }
#	if ($msg->type & 'error')	{ ::ErrorPlay($msg->error); }
#	else				{ ::end_of_file(); }
#}

sub bus_message_end
{	my ($msg,$error)=($_[1],$_[2]);
	#error msg if $error is true, else eos
	if ($Sink->get_name eq 'server') #FIXME
	{ $Sink->set_locked_state(1); $PlayBin->set_state('null'); $Sink->set_locked_state(0); }
	else { $PlayBin->set_state('null'); }
	if ($error)	{ ::ErrorPlay($msg->error); }
	else		{ ::end_of_file(); }
}

sub bus_message_state_changed
{	SkipTo(undef,$Skip) if $Skip;
}

sub Close
{	$Sink=undef;
}

sub GetVolume	{$::Volume}
sub GetMute	{$::Mute}
sub SetVolume
{	shift;
	my $set=shift;
	if	($set eq 'mute')	{ $::Mute=$::Volume; $::Volume=0;}
	elsif	($set eq 'unmute')	{ $::Volume=$::Mute; $::Mute=0;  }
	elsif	($set=~m/^\+(\d+)$/)	{ $::Volume+=$1; }
	elsif	($set=~m/^-(\d+)$/)	{ $::Volume-=$1; }
	elsif	($set=~m/(\d+)/)	{ $::Volume =$1; }
	$::Volume=0   if $::Volume<0;
	$::Volume=100 if $::Volume>100;
	$PlayBin->set(volume => ($::Volume/100)**3) if $PlayBin; 	#use a cubic volume scale
	::HasChanged('Vol');
	$::Options{Volume}=$::Volume;
	$::Options{Volume_mute}=$::Mute;
}

sub SkipTo
{	shift;
	$Skip=shift;
	my ($result,$state,$pending)=$PlayBin->get_state(0);
	return if $result eq 'async'; #when song hasn't started yet, needs to wait until it has started before skipping
	$PlayBin->seek(1,'time','flush','set', $Skip*1_000_000_000,'none',0);
	$Skip=undef;
}

sub Pause
{	$PlayBin->set_state('paused');
}
sub Resume
{	$PlayBin->set_state('playing');
}

sub check_sink
{	$Sink->get_name eq $::Options{gst_sink};
}
sub make_sink
{	my $sinkname=$::Options{gst_sink};
	my $sink=GStreamer::ElementFactory->make($sinkname.'sink' => $sinkname);
	return undef unless $sink;
	$sink->set(profile => 'music') if $::Options{gst_sink} eq 'gconfaudio';
	if (my $opts=$Sinks{$sinkname}{option})
	{	for my $opt (split / /, $opts)
		{	my $val=$::Options{'gst_'.$sinkname.'_'.$opt};
			next unless defined $val && $val ne '';
			$sink->set($opt => $val);
		}
	}
	return $sink;
}

sub about_to_finish	#GAPLESS
{	#warn "-------about_to_finish  $::NextFileToPlay\n";
	return unless $::NextFileToPlay;
	set_file($::NextFileToPlay);
	$AlreadyNextSong=$::NextFileToPlay;
	$::NextFileToPlay=0;
}

sub Play
{	(my($package,$file),$Skip)=@_;
	#warn "------play $file\n";
	#$PlayBin->set_state('ready');#&Stop;
	#my ($ext)=$file=~m/\.([^.]*)$/; warn $ext;
	#::ErrorPlay('not supported') and return undef  unless $Plugins{$ext};
	my $keep= $Sink && $package->check_sink;
	my $useEQ= $GST_EQ_ok && $::Options{gst_use_equalizer};
	my $useRG= $GST_RG_ok && $::Options{gst_use_replaygain};
	$keep=0 if $Sink->{EQ} xor $useEQ;
	$keep=0 if $Sink->{RG} xor $useRG;
	$keep=0 if $package->{modif}; #advanced options changed
	if ($AlreadyNextSong && $AlreadyNextSong eq $file && $keep && !$Skip)
	{	$AlreadyNextSong=undef;
		return;
	}
	if ($keep)
	{	$package->Stop(1);
	}
	else
	{	createPlayBin();
		warn "Creating new gstreamer sink\n" if $::debug;
		delete $package->{modif};
		$Sink=$package->make_sink;
		unless ($Sink) { ::ErrorPlay( ::__x(_"Can't create sink '{sink}'", sink => $::Options{gst_sink}) );return }

		my @elems;
		$Sink->{EQ}=$useEQ;
		if ($useEQ)
		{	my $equalizer=GStreamer::ElementFactory->make('equalizer-10bands' => 'equalizer');
			my @val= split /:/, $::Options{gst_equalizer};
			$equalizer->set( 'band'.$_ => $val[$_]) for 0..9;
			push @elems,$equalizer;
		}
		$Sink->{RG}=$useRG;
		if ($useRG)
		{	my ($rgv,$rgl,$ac,$ar)=	map GStreamer::ElementFactory->make($_=>$_),
					qw/rgvolume rglimiter audioconvert audioresample/;
			RG_set_options($rgv,$rgl);
			push @elems, $rgv,$rgl,$ac,$ar;
		}
		if (my $custom=$::Options{gst_custom})
		{	$custom="( $custom )" if $custom=~m/^\s*\w/ && $custom=~m/!/;	#make a Bin by default instead of a pipeline
			my $elem= eval { GStreamer::parse_launch($custom) };
			warn "gstreamer custom pipeline error : $@\n" if $@;
			if ($elem && $elem->isa('GStreamer::Bin'))
			{	my $first=my $last=$elem;
				# will work at least for simple cases #FIXME could be better
				$first=@{ $first->iterate_sorted }[0]  while $first->isa('GStreamer::Bin');
				$last =@{  $last->iterate_sorted }[-1] while  $last->isa('GStreamer::Bin');
				$elem->add_pad( GStreamer::GhostPad->new('sink', $last->get_pad('sink') ));
				$elem->add_pad( GStreamer::GhostPad->new('src', $first->get_pad('src') ));
			}
			push @elems, $elem if $elem;
		}
		if (@elems)
		{	my $sink0=GStreamer::Bin->new('sink0');
			push @elems,$Sink;
			$sink0->add(@elems);
			my $first=shift @elems;
			$first->link(@elems);
			$sink0->add_pad( GStreamer::GhostPad->new('sink', $first->get_pad('sink') ));
			$PlayBin->set('audio-sink' => $sink0);
		}
		else {$PlayBin->set('audio-sink' => $Sink);}
	}

	if ($visual_window)
	{	$visual_window->realize unless $visual_window->window;
		if (my $w=$visual_window->window) { $VSink->set_xwindow_id($w->XID); }
	}
	warn "playing $file\n";
	set_file($file);
	$PlayBin -> set_state('playing');
	$WatchTag=Glib::Timeout->add(500,\&_UpdateTime) unless $WatchTag;
}
sub set_file
{	my $f=shift;
	if ($f!~m#^([a-z]+)://#)
	{	$f=~s#([^A-Za-z0-9- /\.])#sprintf('%%%02X', ord($1))#seg;
		$f='file://'.$f;
	}
	$PlayBin -> set(uri => $f);
}

sub set_equalizer
{	my (undef,$band,$val)=@_;
	my $equalizer=$PlayBin->get_by_name('equalizer');
	$equalizer->set( 'band'.$band => $val) if $equalizer;
	my @vals= split /:/, $::Options{gst_equalizer};
	$vals[$band]=$val;
	::setlocale(::LC_NUMERIC, 'C');
	$::Options{gst_equalizer}=join ':',@vals;
	::setlocale(::LC_NUMERIC, '');
}
sub EQ_Get_Range
{	createPlayBin() unless $PlayBin;
	my ($min,$max)=(-1,1);
	{	my $equalizer=$PlayBin->get_by_name('equalizer')
		 || GStreamer::ElementFactory->make('equalizer-10bands' => 'equalizer');
		last unless $equalizer;
		my $prop= $equalizer->find_property('band0');
		last unless $prop;
		$min=$prop->get_minimum;
		$max=$prop->get_maximum;
	}
	my $unit= ($max==1 && $min==-1) ? '' : 'dB';
	return ($min,$max,$unit);
}
sub EQ_Get_Hz
{	my $i=$_[1];
	createPlayBin() unless $PlayBin;
	my $equalizer=$PlayBin->get_by_name('equalizer')
	 || GStreamer::ElementFactory->make('equalizer-10bands' => 'equalizer');
	return undef unless $equalizer;
	my $hz= $equalizer->find_property('band'.$i)->get_nick;
	if ($hz=~m/^(\d+)\s*(k?)Hz/)
	{	$hz=$1; $hz*=1000 if $2;
		$hz= $hz>=1000 ? sprintf '%.1fkHz',$hz/1000 :
				 sprintf '%dHz',$hz ;
	}
	return $hz;
}

sub create_visuals
{	unless ($VSink)
	{	$VSink=GStreamer::ElementFactory->make(ximagesink => 'ximagesink');
		return unless $VSink;
		$visual_window->realize unless $visual_window->window;
		if (my $w=$visual_window->window) { $VSink->set_xwindow_id($w->XID); }
	}
	$PlayBin->set('video-sink' => $VSink) if $PlayBin;
	$PlayBin->set('flags' => [qw/audio vis soft-volume/]) if $PlayBin && $playbin2_ok;
	set_visual();
}
sub add_visuals
{	remove_visuals() if $visual_window;
	$visual_window=shift;
	$visual_window->signal_connect(unrealize => \&remove_visuals);
	$visual_window->signal_connect(configure_event => sub {$VSink->expose if $VSink});
	$visual_window->signal_connect(expose_event => sub
		{	if ($VSink) { $VSink->expose; }
			else { create_visuals() }
			1;
		});
}
sub remove_visuals
{	$VSink->set_xwindow_id(0) if $VSink;
	$PlayBin->set('flags' => [qw/audio soft-volume/]) if $PlayBin && $playbin2_ok;
	$PlayBin->set('video-sink' => undef) if $PlayBin;
	$PlayBin->set('vis-plugin' => undef) if $PlayBin;
	$visual_window=$VSink=undef;
}
sub set_visual
{	my $visual= shift || $::Options{gst_visual} || '';
	my @l=list_visuals();
	return unless @l;
	if ($visual eq '+') #choose next visual in the list
	{	$visual=$::Options{gst_visual} || $l[0];
		my $i=0;
		for my $v (@l)
		{	last if $v eq $visual;
			$i++
		}
		$i++; $i=0 if $i>$#l;
		$visual=$l[$i];
	}
	elsif (!(grep $_ eq $visual, @l)) # if visual not found in list
	{	$visual=undef;
	}
	$visual||=$l[0];
	warn "visual=$visual\n" if $::debug;
	$::Options{gst_visual}=$visual;
	$visual=GStreamer::ElementFactory->make($visual => 'visual');
	$PlayBin->set('vis-plugin' => $visual) if $PlayBin;
	$VSink->expose;
}

sub list_visuals
{	my @visuals;
	my $reg=GStreamer::Registry->get_default;
	for my $plugin ($reg->get_plugin_list)
	{	#warn $plugin;
		for my $elem ($reg->get_feature_list_by_plugin($plugin->get_name))
		{	#warn $elem;
			if ($elem->isa('GStreamer::ElementFactory'))
			{	my $klass=$elem->get_klass;
				next unless $klass eq 'Visualization';
				#warn $elem->get_name."\n";
				#warn $elem->get_longname."\n";
				#warn $elem->get_description."\n";
				#warn $elem->get_element_type."\n";
				#warn "$klass\n";
				#warn "\n";
				push @visuals,$elem->get_name;
			}
		}
	}
	return @visuals;
}

sub _UpdateTime
{	my ($result,$state,$pending)=$PlayBin->get_state(0);
	if ($AlreadyNextSong) { warn "UpdateTime: gapless change to next song\n" if $::debug; ::end_of_file_faketime(); return 1; }
	warn "state: $result,$state,$pending\n" if $::debug;
	return 1 if $result eq 'async';
	if ($state ne 'playing' && $state ne 'paused')
	{	return 1 if $pending eq 'playing' || $pending eq 'paused';
		::ResetTime() unless 'Play_GST' ne ref $::Play_package;
		$WatchTag=undef;
		return 0;
	}
	my $query=GStreamer::Query::Position->new('time');
	if ($PlayBin->query($query))
	{	my (undef, $position)=$query->position;
		::UpdateTime( $position/1_000_000_000 );
	}
	return 1;
}

sub Stop
{	#if ($_[1]) { $Sink->set_locked_state(1); $PlayBin->set_state('null'); $Sink->set_locked_state(0);return; }
	#if ($_[1]) { $PlayBin->set_state('ready'); return;}
	#my ($result,$state,$pending)=$PlayBin->get_state(0);
	#warn "stop: state: $result,$state,$pending\n";
	#return if $state eq 'null' and $pending eq 'void-pending';
	$PlayBin->set_state('null') if $PlayBin;
	#warn "--stop\n";
}

sub RG_set_options
{	my ($rgv,$rgl)=@_;
	$rgv||=$PlayBin->get_by_name('rgvolume');
	$rgl||=$PlayBin->get_by_name('rglimiter');
	return unless $rgv && $rgl;
	$rgl->set(enabled => 0) if $::Options{gst_rg_nolimiter};
	$rgv->set('album-mode' => 1) if $::Options{gst_rg_albummode};
	$rgv->set('pre-amp' => $::Options{gst_rg_preamp}||0);
	$rgv->set('fallback-gain' => $::Options{gst_rg_fallback}||0);
	#$rgv->set(headroom => $::Options{gst_rg_headroom}||0);
}

sub RG_PrefBox
{	my ($sg1,$sg2)=@_;
	my $check=::NewPrefCheckButton(gst_use_replaygain => _"Use ReplayGain", tip=>_"Normalize volume (the files must have replaygain tags)");
	$sg1->add_widget($check);
	#my $start=Gtk2::Button->new(_ "Start ReplayGain analysis");
	my $opt  =Gtk2::Button->new(_"ReplayGain options");
	$sg2->add_widget($opt);
	$opt->signal_connect(clicked => sub
		{	if ($RG_dialog) {$RG_dialog->present;return}
			$RG_dialog= Gtk2::Dialog->new (_"ReplayGain options", undef, [], 'gtk-close' => 'close');
			$RG_dialog->signal_connect(destroy => sub {$RG_dialog=undef});
			$RG_dialog->signal_connect(response =>sub {$_[0]->destroy});
			my $update=sub { RG_set_options(); };
			my $songmenu=::NewPrefCheckButton(gst_rg_songmenu => _"Show replaygain submenu");
			my $albummode=::NewPrefCheckButton(gst_rg_albummode => _"Album mode", cb=>$update, tip=>_"Use album normalization instead of track normalization");
			my $nolimiter=::NewPrefCheckButton(gst_rg_limiter => _"Hard limiter", cb=>$update, tip=>_"Used for clipping prevention");
			my $sg1=Gtk2::SizeGroup->new('horizontal');
			my $sg2=Gtk2::SizeGroup->new('horizontal');
			my $preamp=	::NewPrefSpinButton('gst_rg_preamp',   -60,60, cb=>$update, digits=>1, rate=>.1, step=>.1, text2=> 'dB', sizeg1=>$sg1, sizeg2=>$sg2, text1=>_"pre-amp", tip=>_"Extra gain");
			my $fallback=	::NewPrefSpinButton('gst_rg_fallback', -60,60, cb=>$update, digits=>1, rate=>.1, step=>.1, text2=> 'dB', sizeg1=>$sg1, sizeg2=>$sg2, text1=>_"fallback-gain", tip=>_"Gain for songs missing replaygain tags");
			$RG_dialog->vbox->pack_start($_,0,0,2) for $albummode,$preamp,$fallback,$nolimiter,$songmenu;
			$RG_dialog->show_all;

		});
	#$start->signal_connect(clicked => sub
	#	{	my @list; my %done;
	#		for my $ID (@::Library)
	#		{	my $albumid=Songs::Get_gid($ID,'album');
	#			my $l=AA::GetIDs('album',$albumid);
	#			if (@$l>1 && Songs::Gid_to_get('album',$album) ne '')
	#			{ push @list,[@$l] unless exists $done{$album}; $done{$aid}=undef; }
	#			else { push @list,$ID; }
	#		}
	#		Analyse(\@list);
	#	});
	#$start->signal_connect(clicked => sub { Analyse(\@::Library) });
	#$start->set_sensitive(0) unless $GST_RGA_ok;
	my $box=::Hpack($check,$opt);
	$box->set_sensitive(0) unless $GST_RG_ok;
	return $box;
}

sub AdvancedOptions
{	my $self=$_[0];
	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $modif_cb= sub { $self->{modif}=1 };
	my $gapless= ::NewPrefCheckButton(gst_gapless => _"enable gapless (experimental)", cb=> $modif_cb);
	$gapless->set_sensitive(0) unless $playbin2_ok;
	$vbox->pack_start($gapless,::FALSE,::FALSE,2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $custom= ::NewPrefEntry(gst_custom => _"Custom pipeline", cb=>$modif_cb, sizeg1 => $sg1, expand => 1, tip => _"Insert this pipeline before the audio sink", history => 'gst_custom_history');
	$vbox->pack_start($custom,::FALSE,::FALSE,2);
	for my $s (sort grep $Sinks{$_}{ok} && $Sinks{$_}{option}, keys %Sinks)
	{	my $label= $Sinks{$s}{name}||$s;
		for my $opt (sort split / /,$Sinks{$s}{option})
		{	my $hbox=::NewPrefEntry("gst_${s}_$opt", "$s $opt : ", cb => $modif_cb, sizeg1 => $sg1, expand => 1);
			$vbox->pack_start($hbox,::FALSE,::FALSE,2);
		}
	}
	return $vbox;
}

package GMB::GST_ReplayGain;

my $RGA_pipeline;
my (@towrite,$writing);
my $RGA_songmenu=
{ label => _"Replaygain analysis",	notempty => 'IDs', notmode => 'P', test => sub {$Play_GST::GST_RGA_ok && $::Options{gst_rg_songmenu}; },
 submenu =>
 [	{ label => _"Scan this file",			code => sub { Analyse ($_[0]{IDs}); },		onlyone => 'IDs', },
	{ label => _"Scan per-file track gain",		code => sub { Analyse ($_[0]{IDs}); },		onlymany=> 'IDs', },
	{ label => _"Scan using tag-defined album", 	code => sub { Analyse_byAlbum ($_[0]{IDs}); },	onlymany=> 'IDs', },
	{ label => _"Scan as an album",			code => sub { Analyse([ $_[0]{IDs} ]); },	onlymany=> 'IDs', },
 ],
};
push @::SongCMenu,$RGA_songmenu;

sub Analyse_byAlbum
{	my $IDs=$_[0];
	Songs::SortList($IDs,'album');
	my @list; my @album; my $aid0;
	for my $ID (@$IDs)
	{	my $aid= Songs::Get($ID,'album');
		if (defined $aid0)
		{	if ($aid0 eq $aid) {push @album,$ID;next}	# same album
			else						# different album
			{	push @list, (@album>1 ? [@album] : $album[0]);	#add songs from previous album as a group
				$aid0=undef; @album=undef;
			}
		}
		if ($aid eq '') {push @list,$ID}	# songs with no album -> add song on its own
		else {$aid0=$aid; @album=($ID)}		# new album
	}
	if (defined $aid0) { push @list, (@album>1 ? [@album] : $album[0]); } # add songs from last album as a group
	Analyse(\@list);
}
sub Analyse
{	my @IDs= ::uniq(@{ $_[0] });
	unless ($RGA_pipeline)
	{	$RGA_pipeline=GStreamer::Pipeline->new('RGA_pipeline');
		my $audiobin=GStreamer::Bin->new('RGA_audiobin');
		#my @elems= qw/filesrc decodebin audioconvert audioresample rganalysis fakesink/;
		my ($src,$decodebin,$ac,$ar,$rganalysis,$fakesink)=
			map GStreamer::ElementFactory->make($_ => $_),
			qw/filesrc decodebin audioconvert audioresample rganalysis fakesink/;
		$audiobin->add($ac,$ar,$rganalysis,$fakesink);
		$ac->link($ar,$rganalysis,$fakesink);
		my $audiopad=$ac->get_pad('sink');
		$audiobin->add_pad(GStreamer::GhostPad ->new('sink', $audiopad));
		$RGA_pipeline->add($src,$decodebin,$audiobin);
		$src->link($decodebin);
		$decodebin->signal_connect(new_decoded_pad => \&newpad_cb);

		#@elems= map GStreamer::ElementFactory->make($_ => $_), @elems;
		#$RGA_pipeline->add(@elems);
		#my $first=shift @elems;
		#$first->link(@elems);
		my $bus=$RGA_pipeline->get_bus;
		$bus->add_signal_watch;
		$bus->signal_connect('message::error' => sub { warn "ReplayGain analysis error : ".$_[1]->error."\n"; }); #FIXME
		$bus->signal_connect('message::tag' => \&bus_message_tag);
		$bus->signal_connect('message::eos' => \&process_next);
		#FIXME check errors
	}
	push @{$RGA_pipeline->{queue}},@IDs;
	my $nb=@IDs; #warn "@IDs";
	$nb+=@$_-1 for grep ref, @IDs; #count tracks in album lists
	::Progress('replaygain', add=>$nb, abortcb=>\&StopAnalysis, title=>_"Replaygain analysis");
	process_next() unless $::Progress{replaygain}{current}; #FIXME maybe check if $RGA_pipeline is running instead
}
sub newpad_cb
{	my ($decodebin,$pad)=@_;
	my $audiopad = $RGA_pipeline->get_by_name('RGA_audiobin')->get_pad('sink');
	return if $audiopad->is_linked;
	# check media type
	my $str= $pad->get_caps->get_structure(0)->{name};
	return unless $str=~m/audio/;
	$pad->link($audiopad);
}
sub process_next
{	::Progress('replaygain', inc=>1) if $_[0]; #called from callback => one file has been scanned => increment
	unless ($RGA_pipeline) { ::Progress('replaygain', abort=>1); return; }

	my $rganalysis=$RGA_pipeline->get_by_name('rganalysis');
	my $ID;
	if (my $list=$RGA_pipeline->{albumIDs})
	{	my $i= ++$RGA_pipeline->{album_i};
		my $left= @$list -$i;
		$rganalysis->set('num-tracks' => $left);
		if ($left) {$ID=$list->[$i]; $rganalysis->set_locked_state(1); }
		else { delete $RGA_pipeline->{$_} for qw/album_i albumIDs album_tosave/; }
	}
	$RGA_pipeline->set_state('ready');
	unless (defined $ID) { $ID=shift @{$RGA_pipeline->{queue}}; };
	if (defined $ID)
	{	if (ref $ID) #album mode
		{	my $list=$RGA_pipeline->{albumIDs}=$ID;
			$rganalysis->set('num-tracks' => scalar @$list);
			$ID=$list->[0];
			$RGA_pipeline->{album_i}=0;
		}
		my $f= Songs::Get($ID,'fullfilename_raw');
		::_utf8_on($f); # pretend it's utf8 to prevent a conversion to utf8 by the bindings
		$RGA_pipeline->{ID}=$ID;
		warn "analysing [$ID] $f\n";
		$RGA_pipeline->get_by_name('filesrc')->set(location => $f);
		$rganalysis->set_locked_state(0);
		$RGA_pipeline->set_state('playing');
	}
	else
	{	$RGA_pipeline->set_state('null');
		$RGA_pipeline=undef;
	}
	1;
}
sub bus_message_tag
{	my $msg=$_[1];
	my $tags=$msg->tag_list;
	#for my $key (sort keys %$tags) {warn "key=$key => $tags->{$key}\n"}
	#FIXME should check if the message comes from the rganalysis element, but not supported by the bindings yet, instead check if any non replaygain tags => will re-write replaygain tags _before_ analysis for files without other tags
	#return if GStreamer->VERSION >=.10 && $msg->src == $RGA_pipeline->get_by_name('rganalysis'); FIXME with Gstreamer 0.10 : $message->src should work, not tested yet !!!! TESTME
	return unless exists $tags->{'replaygain-track-gain'};
	return if grep !m/^replaygain-/, keys %$tags; #if other tags than replaygain => doesn't come from the rganalysis element

	my $cID=$RGA_pipeline->{ID};
	if ($::debug)
	{	warn "done for ID=$cID\n";
		warn "done for album IDs=".join(' ',@{$RGA_pipeline->{albumIDs}})."\n" if $RGA_pipeline->{albumIDs} && $RGA_pipeline->get_by_name('rganalysis')->get('num-tracks');
		warn " $_ : @{$tags->{$_}}\n" for keys %$tags;
	}
	if ($RGA_pipeline->{albumIDs})
	{	$RGA_pipeline->{album_tosave}{ $cID }= [@$tags{'replaygain-track-gain','replaygain-track-peak'}];
		if (exists $tags->{'replaygain-album-gain'} && !$RGA_pipeline->get_by_name('rganalysis')->get('num-tracks'))
		{	#album done
			my $IDs= $RGA_pipeline->{albumIDs};
			my $gainpeak= $RGA_pipeline->{album_tosave};
			for my $ID (@$IDs)
			{	@$tags{'replaygain-track-gain','replaygain-track-peak'}= @{$gainpeak->{$ID}};
				queuewrite($ID,$tags,1);
			}
		}
	}
	else
	{	queuewrite($cID,$tags,0);
	}
	1;
}
sub queuewrite
{	my ($ID,$tags,$albumtag)=@_;
	my @keys=qw/replaygain-reference-level replaygain-track-gain replaygain-track-peak/;
	push @keys, qw/replaygain-album-gain replaygain-album-peak/ if $albumtag;
	::setlocale(::LC_NUMERIC, 'C');
	my @modif;
	for my $key (@keys)
	{	my $field=$key;
		$field=~tr/-/_/; # convert replaygain-track-gain to replaygain_track_gain ...
		push @modif, $field, "$tags->{$key}[0]";#string-ify them with C locale to make sure it's correct
	}
	::setlocale(::LC_NUMERIC, '');
	push @towrite, $ID,\@modif;
	WriteRGtags() unless $writing;
}
sub WriteRGtags
{	return $writing=0 if !@towrite;
	$writing=1;
	my $ID=   shift @towrite;
	my $modif=shift @towrite;
	Songs::Set($ID, $modif,
		abortmsg	=> _"Abort ReplayGain analysis",
		error_prefix	=> _"Error writing replaygain tags :\n",
		abortcb		=> \&StopAnalysis,
		callback_finish	=> \&WriteRGtags,
	);
}
sub StopAnalysis
{	$RGA_pipeline->set_state('null') if $RGA_pipeline;
	$RGA_pipeline=undef;
	::Progress('replaygain', abort=>1);
	@towrite=();
}

package Play_GST_server;
use Socket;
use constant { EOL => "\015\012" };
our @ISA=('Play_GST');

our %sockets;
my ($stream,$Server);

$::PlayPacks{Play_GST_server}=1; #register the package

sub init
{	return undef unless $GST_ok;
	my $ok=1;
	my $reg=GStreamer::Registry->get_default;
	for my $feature (qw/multifdsink lame audioresample audioconvert/)
	{	next if $reg->lookup_feature($feature);
		$ok=0;
		warn "gstreamer plugin '$feature' not found -> gstreamer-server mode not available\n";
	}
	return unless $ok;
	return bless { EQ=>$GST_EQ_ok },__PACKAGE__;
}

sub Close
{	close $Server if $Server;
	$Server=undef;
}

sub Stop
{	unless ($_[1])
	{	for (keys %sockets)
		{	$sockets{$_}[1]=0; $stream->signal_emit(remove => $_);
		}
	}
	if ($_[1]) { $Sink->set_locked_state(1); $PlayBin->set_state('null'); $Sink->set_locked_state(0);return; }
	else
	{	$PlayBin->set_state('null');
	}
}
#was in Play()	#for (keys %sockets) {warn "socket $_ : ".$sockets{$_}[1];;$stream->signal_emit(add => $_ ) if $sockets{$_}[1];}

sub check_sink
{	$Sink->get_name eq 'server';
}
sub make_sink
{	#return $Sink if $Sink && $Sink->get_name eq 'server';
	my $sink=GStreamer::Bin->new('server');
#	my ($aconv,$audioresamp,$vorbisenc,$oggmux,$stream)=
	(my ($aconv,$audioresamp,$lame),$stream)=
		GStreamer::ElementFactory -> make
		(	audioconvert => 'audioconvert',
			audioresample => 'audioresample',
			#vorbisenc => 'vorbisenc',
			#oggmux => 'oggmux',
			lame => 'lame',
			multifdsink => 'multifdsink',
		);
	#$sink->add($aconv,$audioresamp,$vorbisenc,$oggmux,$stream);
	$sink->add($aconv,$audioresamp,$lame,$stream);
	$aconv->link($audioresamp,$lame,$stream);
	#$aconv->link($audioresamp,$vorbisenc,$oggmux,$stream);
	$sink->add_pad( GStreamer::GhostPad->new('sink', $aconv->get_pad('sink') ));
	$stream->set('recover-policy'=>'keyframe');
	#$stream->signal_connect($_ => sub {warn "@_"},$_) for 'client-removed', 'client_added', 'client-fd-removed';
	#$stream->signal_connect('client-fd-removed' => sub { Glib::Idle->add(sub {close $sockets{$_[0]}[0]; delete $sockets{$_[0]}},$_[1]); });
	$stream->signal_connect('client-fd-removed' => sub { close $sockets{$_[1]}[0]; delete $sockets{$_[1]}; ::HasChanged('connections'); }); #FIXME not in main thread, so should be in a Glib::Idle, but doesn't work so ... ?
	#$stream->signal_connect('client-fd-removed' => sub { warn "@_ ";Glib::Idle->add(sub {warn $_[0];warn "-- $_ ".$sockets{$_} for keys %sockets;unless ($sockets{$_[0]}[1]) { close $sockets{$_[0]}[0] ;warn "closing $_[0]"; delete $sockets{$_[0]};0;} }, $_[1]) });
	return undef unless Listen();
	return $sink;
}

sub Listen
{	my $proto = getprotobyname('tcp');
	my $port=$::Options{Icecast_port};
	my $noerror;
	{	last unless socket($Server, PF_INET, SOCK_STREAM, $proto);
		last unless setsockopt($Server, SOL_SOCKET, SO_REUSEADDR,pack('l', 1));
		last unless bind($Server, sockaddr_in($port, INADDR_ANY));
		last unless listen($Server,SOMAXCONN);
		$noerror=1;
	}
	unless ($noerror)
	{	::ErrorPlay("icecast server error : $!");
		return undef;
	}
	Glib::IO->add_watch(fileno($Server),'in', \&Connection);
	warn "icecast server listening on port $port\n";
	::HasChanged('connections');
	return 1;
}

sub Connection
{	my $Client;
	return 0 unless $Server;
	my $paddr = accept($Client,$Server);
	return 1 unless $paddr;
	my($port2,$iaddr) = sockaddr_in($paddr);
	warn 'Connection from ',inet_ntoa($iaddr), " at port $port2\n";
	#warn "fileno=".fileno($Client);
	my $request=<$Client>;warn $request;
	while (<$Client>)
	{	warn $_;
		last if $_ eq EOL;
	}
	if ($request=~m#^GET /command\?cmd=(.*?) HTTP/1\.\d\015\012$#)
	{	my $cmd=::decode_url($1);
		my $content;
		if (0) #FIXME add password and disable dangerous commands (RunSysCmd, RunPerlCode and ChangeDisplay)
		{	::run_command(undef,$cmd);
			$content='Command sent.';
		}
		else {$content='Unauthorized.'}
		my $answer=
		'HTTP/1.0 200 OK'.EOL.
		'Content-Length: '.length($content).EOL.
		EOL.$content;
		send $Client,$answer.EOL,0;
		close $Client;
		return 1;	#keep listening
	}
	my $answer=
	'HTTP/1.0 200 OK'.EOL.
	'Server: iceserver/0.2'.EOL.
	"Content-Type: audio/mpeg".EOL.
	"x-audiocast-name: gmusicbrowser stream".EOL.
	'x-audiocast-public: 0'.EOL;
	send $Client,$answer.EOL,0;
	#warn $answer;
	my $fileno=fileno($Client);
	$sockets{$fileno}=[$Client,1,gethostbyaddr($iaddr,AF_INET)];
	Glib::IO->add_watch(fileno($Client),'hup',sub {warn "Connection closed"; $sockets{fileno($Client)}[1]=0; ::HasChanged('connections'); $stream->signal_emit(remove => fileno$Client);return 0; }); #FIXME never called
	$stream->signal_emit(add => fileno$Client);
	::HasChanged('connections');
	return 1;	#keep listening
}


1;
