# Copyright (C) 2015 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

BEGIN
{	require Glib::Object::Introspection;
	warn "Using Glib::Object::Introspection version ".Glib::Object::Introspection->VERSION."\n" if $::debug;
	Glib::Object::Introspection->setup(basename => 'Gst', version => '1.0', package => 'GStreamer1');
	$::gstreamer_version='1.x';
	GStreamer1::init_check([ $0, @ARGV ]) or die "Can't initialize gstreamer-1.x\n";
	my $reg= GStreamer1::Registry::get();
	$reg->lookup_feature('playbin') or die "gstreamer-1.x plugin 'playbin' not found.\n";
}

package Play_GST;
use strict;
use warnings;

my ($GST_visuals_ok,$GST_EQ_ok,$GST_RG_ok); our $GST_RGA_ok;
my ($VolumeBusy,$VolumeHasChanged);
my (%Plugins,%Sinks);
$::PlayPacks{Play_GST}=1; #register the package
my $support_install_missing;

BEGIN
{ %Sinks=
  (	autoaudio	=> { name => _"auto detect", },
	oss		=> { option => 'device' },
	oss4		=> { option => 'device' },
	alsa		=> { option => 'device' },
	openal		=> {},
	pulse		=> { name => "PulseAudio", option=>'server device'},
	jackaudio	=> { name => "JACK", option => 'server' },
	osxaudio	=> { option => 'device' },
	directsound	=> {},
  );
  %Plugins=(	mp3 => 'flump3dec mad mpg123audiodec avdec_mp3',
		oga => 'vorbisdec',			flac=> 'flacdec',
		ape => 'avdec_ape ffdec_ape',		wv  => 'wavpackdec',
		mpc => 'musepackdec avdec_mpc8',	m4a => 'faad',
		opus => 'opusdec',
  );

  my $reg= GStreamer1::Registry::get();
  $Sinks{$_}{ok}= ! !$reg->lookup_feature($_.'sink') for keys %Sinks;
  if ($reg->lookup_feature('equalizer-10bands')) { $GST_EQ_ok=1; }
  else {warn "gstreamer1 plugin 'equalizer-10bands' not found -> equalizer not available\n";}
  if ($reg->lookup_feature('rglimiter') && $reg->lookup_feature('rgvolume')) { $GST_RG_ok=1; }
  else {warn "gstreamer1 plugins 'rglimiter' and/or 'rgvolume' not found -> replaygain not available\n";}
  if ($reg->lookup_feature('rganalysis')) { $GST_RGA_ok=1; }
  else {warn "gstreamer1 plugins 'rganalysis' not found -> replaygain analysis not available\n";}

  #some functions that should be accessible from perl but are not currently (Glib::Object::Introspection-0.027)
  *GStreamer1::Bin::add_many= sub {my $b=shift;$b->add($_) for @_} unless *GStreamer1::Bin::add_many{CODE};
  *GStreamer1::Element::link_many= sub {while (@_>1){my $e=shift;$e->link($_[0])} } unless *GStreamer1::Element::link_many{CODE};

  $GST_visuals_ok=1;
  # don't know what features are needed for visuals in gstreamer-1.x
  #unless ($reg->lookup_feature('????'))
  #{	warn "gstreamer plugin '????' not found -> visuals not available\n"; $GST_visuals_ok=0;
  #}
  # setup the gstvideooverlay interface (used for telling playbin the window ID to use for visuals)
  eval { Glib::Object::Introspection->setup(basename => 'GstVideo', version => '1.0', package => 'GStreamer1::Video'); }; #unless *GStreamer1::Video::VideoOverlay::set_window_handle{CODE};
  if ($@)
  {	$GST_visuals_ok=0;
	warn "Can't setup GStreamer1::Video::VideoOverlay -> visuals not available:\n $@\n";
  }

  if (1)
  {	eval { Glib::Object::Introspection->setup(basename => 'GstPbutils', version => '1.0', package => 'GStreamer1::Pbutils') }; # unless *GStreamer1::Pbutils::pb_utils_init{CODE};
	if (!$@)
	{	GStreamer1::Pbutils::pb_utils_init();
		$support_install_missing=1 if GStreamer1::Pbutils::install_plugins_supported();
		warn "gstreamer says Installing missing plugins not supported by this system\n" if $::debug;
	}
	else { warn "Can't setup GStreamer1::Pbutils -> Installing missing plugins not supported\n"; }
  }
}

sub supported_formats
{	my $reg= GStreamer1::Registry::get;
	my @found;
	for my $type (keys %Plugins)
	{	push @found, $type if grep $reg->lookup_feature($_), split / +/, $Plugins{$type};
	}
	return @found;
}
sub supported_sinks
{	my $reg= GStreamer1::Registry::get;
	$Sinks{$_}{ok}= ! !$reg->lookup_feature($_.'sink') for keys %Sinks;
	return {map { $_ => $Sinks{$_}{name}||$_ } grep $Sinks{$_}{ok}, keys %Sinks};
}

sub init
{	my $reg= GStreamer1::Registry::get();
	$::Options{gst_sink}='' unless $reg->lookup_feature( ($::Options{gst_sink}||'').'sink' );
	$::Options{gst_sink}||= (grep ($reg->lookup_feature($_.'sink'), qw/autoaudio pulse alsa oss oss4/),'autoaudio')[0]; #find a default sink
	return bless { EQ=>$GST_EQ_ok, EQpre=>$GST_EQ_ok, visuals => $GST_visuals_ok, RG=>$GST_RG_ok },__PACKAGE__;
}


sub create_playbin
{	my $self=shift;
	my $pb= GStreamer1::ElementFactory::make('playbin' => 'playbin');
	if ($self->{playbin})
	{	$self->{playbin}->get_bus->remove_signal_watch; #not sure if needed
		$self->{playbin}->set_state('null');
	}
	$self->{playbin}=$pb;
	$pb->set('flags' => [qw/audio soft-volume/]);
	$self->SetVolume(''); #initialize volume
	my $bus=$pb->get_bus;
	::weaken( $bus->{self}=$self );
	::weaken( $pb->{self} =$self );
	$bus->add_signal_watch;
	$pb->signal_connect("notify::volume" => sub { Glib::Idle->add(\&VolumeChanged,$_[0]) unless $VolumeHasChanged++; },100000) if $::Options{gst_monitor_pa_volume}; # can cause a freeze in some circumstances, in particular when using the scroll wheel on the time bar, see perl-glib bug #620099 (https://bugzilla.gnome.org/show_bug.cgi?id=620099)
#	$bus->signal_connect('message' => \&bus_message);
	$bus->signal_connect('message::element' => \&bus_message_missing_plugin) if $support_install_missing;
	$bus->signal_connect('message::eos' => \&bus_message_end,0);
	$bus->signal_connect('message::error' => \&bus_message_end,1);
	$bus->signal_connect('message::state-changed' => \&bus_message_state_changed);
	$pb->signal_connect(about_to_finish => \&about_to_finish) if $::Options{gst_gapless};
	$self->connect_visuals if $self->{has_visuals};
}

sub _parse_error
{	my $msg=shift;
	my $s=$msg->get_structure;
	return $s->get_value('gerror')->message, $s->get_string('debug');
}

sub bus_message_end
{	my ($msg,$error)=($_[1],$_[2]);
	my $self=$_[0]{self};
	#error msg if $error is true, else eos
	if ($self->{continuous}) { $self->{sink}->set_locked_state(1); $self->{playbin}->set_state('null'); $self->{sink}->set_locked_state(0); }
	else { $self->{playbin}->set_state('null'); }
	if ($error)	{ ::ErrorPlay(_parse_error($msg)); } #can't use $msg->parse_error as it doesn't work currently : "FIXME - GI_TYPE_TAG_ERROR" (Glib::Object::Introspection-0.027)
	else		{ ::end_of_file(); }
}

sub bus_message_missing_plugin
{	my ($bus,$msg)=@_;
	return unless GStreamer1::Pbutils::is_missing_plugin_message($msg);
	my $details=GStreamer1::Pbutils::missing_plugin_message_get_installer_detail($msg);
	warn "missing plugin details: ".$details."\n" if $::debug;
	GStreamer1::Pbutils::install_plugins_async([$details],undef,
	 sub
	 {	return unless $_[0]=~/success/; # success or partial_success
		GStreamer1::update_registry(); #FIXME "Applications should assume that the registry update is neither atomic nor thread-safe and should therefore not have any dynamic pipelines running (including the playbin and decodebin elements) and should also not create any elements or access the GStreamer registry while the update is in progress"
	 });
}

# when a song starts playing, notify::volume callbacks are called, which causes glib to hang (see https://bugzilla.gnome.org/show_bug.cgi?id=620099#c11) if a skip is done at the same moment
# using freeze_notify until the skip is done mostly avoid the problem
# setting state to paused until the skip is done also mostly avoid the problem
# but the hang still happens in some cases, in particular when using the scroll wheel to change the position in the song, and also very rarely when starting a song
my $StateChanged;
sub bus_message_state_changed	# used to wait for the right state to do the skip
{	my $self=$_[0]{self};
	return unless $self || $self->{skip};
	return if $self->{state_changed};
	my $playbin= $self->{playbin};
	$self->{state_changed}=1;
	$self->{playbin}->freeze_notify unless $self->{notify_frozen}; $self->{notify_frozen}=1; #freeze notify until skip is done
	Glib::Idle->add(sub
	{	$self->SkipTo($self->{skip}) if $self->{skip}; # this will only skip if the state is right, else will wait for another state change
		unless ($self->{skip}) { $self->{playbin}->thaw_notify if delete $self->{notify_frozen}; } #if skip is done, unfreeze
		$self->{state_changed}=0;
		0;
	});
}


sub check_sink
{	my $self=shift;
	$self->{sink}->get_name eq $::Options{gst_sink};
}

sub create_sink
{	my $self=shift;
	my $sinkname=$::Options{gst_sink};
	my $sink=GStreamer1::ElementFactory::make($sinkname.'sink' => $sinkname);
	return undef unless $sink;
	#$sink->set(profile => 'music') if $::Options{gst_sink} eq 'gconfaudio';
	if (my $opts=$Sinks{$sinkname}{option})
	{	for my $opt (split / /, $opts)
		{	my $val=$::Options{'gst_'.$sinkname.'_'.$opt};
			next unless defined $val && $val ne '';
			$sink->set($opt => $val);
		}
	}
	$self->{sink}=$sink;
}

sub init_sink
{	my $self=shift;
	delete $self->{modif};
	$self->create_sink;
	my $sink= $self->{sink};
	unless ($sink) { ::ErrorPlay( ::__x(_"Can't create sink '{sink}'", sink => $::Options{gst_sink}) );return }

	my @elems;
	$sink->{EQ}= $GST_EQ_ok && $::Options{use_equalizer};
	if ($sink->{EQ})
	{	my $preamp=   GStreamer1::ElementFactory::make('volume' => 'equalizer-preamp');
		my $equalizer=GStreamer1::ElementFactory::make('equalizer-10bands' => 'equalizer');
		my @val= split /:/, $::Options{equalizer};
		::setlocale(::LC_NUMERIC, 'C');
		$equalizer->set( 'band'.$_ => $val[$_]) for 0..9;
		$preamp->set( volume => $::Options{equalizer_preamp}**3);
		::setlocale(::LC_NUMERIC, '');
		push @elems,$preamp,$equalizer;
	}
	$sink->{RG}= $GST_RG_ok && $::Options{use_replaygain};
	if ($sink->{RG})
	{	my ($rgv,$rgl,$ac,$ar)=	map GStreamer1::ElementFactory::make($_=>$_),
				qw/rgvolume rglimiter audioconvert audioresample/;
		$self->RG_set_options($rgv,$rgl);
		push @elems, $rgv,$rgl,$ac,$ar;
	}
	if (my $custom=$::Options{gst_custom})
	{	$custom="( $custom )" if $custom=~m/^\s*\w/ && $custom=~m/!/;	#make a Bin by default instead of a pipeline
		my $elem= eval { GStreamer1::parse_launch($custom) };
		warn "gstreamer custom pipeline error : $@\n" if $@;
		if ($elem && $elem->isa('GStreamer1::Bin'))
		{	my $first=my $last=$elem;
			# will work at least for simple cases #FIXME could be better
			$first=($first->list_iterate_sorted)[0]  while $first->isa('GStreamer1::Bin');
			$last =($last->list_iterate_sorted)[-1] while  $last->isa('GStreamer1::Bin');
			$elem->add_pad( GStreamer1::GhostPad->new('sink', $last->get_static_pad('sink') ));
			$elem->add_pad( GStreamer1::GhostPad->new('src', $first->get_static_pad('src') ));
		}
		push @elems, $elem if $elem;
	}
	my $playbin= $self->{playbin};
	if (@elems)
	{	my $sink0=GStreamer1::Bin->new('sink0');
		push @elems,$sink;
		$sink0->add_many(@elems);
		my $pad= $elems[0]->get_static_pad('sink');
		GStreamer1::Element::link_many(@elems);
		$sink0->add_pad( GStreamer1::GhostPad->new('sink',$pad));
		$playbin->set('audio-sink' => $sink0);
	}
	else {$playbin->set('audio-sink' => $sink);}
}

#convenience function for getting a list instead of having to deal with iterators
sub GStreamer1::Bin::list_iterate_sorted
{	my $bin=shift;
	my $iter= $bin->iterate_sorted;
	my @children;
	$iter->foreach(sub {push @children,$_[0]});
	return @children;
}

sub about_to_finish	#GAPLESS
{	#warn "-------about_to_finish  $::NextFileToPlay\n";
	my $self=$_[0]{self};
	return unless $self && $::NextFileToPlay;
	$self->set_file($::NextFileToPlay);
	$self->{already_next_song}=$::NextFileToPlay;
	$::NextFileToPlay=0;
}

sub Play
{	my($self,$file,$skip)=@_;
	$self->{skip}=$skip;
	my $sink= $self->{sink};
	my $keep= $sink && $self->check_sink;
	if ($keep)
	{	my $useEQ= $GST_EQ_ok && $::Options{use_equalizer};
		my $useRG= $GST_RG_ok && $::Options{use_replaygain};
		$keep=0 if $sink->{EQ} xor $useEQ;
		$keep=0 if $sink->{RG} xor $useRG;
		$keep=0 if $self->{modif}; #advanced options changed
	}
	if ($self->{already_next_song} && $self->{already_next_song} eq $file && $keep && !$skip)
	{	$self->{already_next_song}=undef;
		return;
	}
	$self->{already_next_song}=undef;
	if ($keep)
	{	$self->Stop(1);
	}
	else
	{	$self->create_playbin;
		warn "Creating new gstreamer sink\n" if $::debug;
		$self->init_sink;
	}

	warn "playing $file\n" if $::Verbose;
	$self->set_file($file);
	my $newstate='playing'; $self->{state_after_skip}=undef;
	if ($skip) { $newstate='paused'; $self->{state_after_skip}='playing'; }
	$self->{playbin}->set_state($newstate);
	$self->{watch_tag} ||= Glib::Timeout->add(500,\&UpdateTime,$self);
}
sub set_file
{	my ($self,$f)=@_;
	if ($f!~m#^([a-z]+)://#)
	{	$f=~s#([^A-Za-z0-9-/\.])#sprintf('%%%02X', ord($1))#seg;
		$f='file://'.$f;
	}
	$self->{playbin}->set(uri => $f);
}

sub UpdateTime
{	my $self=shift;
	my $playbin= $self->{playbin};
	my ($result,$state,$pending)= $playbin->get_state(0);
	warn "state: $result,$state,$pending\n" if $::debug;
	return 1 if $result eq 'async';
	if ($state ne 'playing' && $state ne 'paused')
	{	return 1 if $pending eq 'playing' || $pending eq 'paused';
		::ResetTime() unless $self->{continuous};
		$self->{watch_tag}=undef;
		return 0;
	}
	my $query=GStreamer1::Query->new_position('time');
	if ($playbin->query($query))
	{	my (undef, $position)=$query->parse_position;
		$position/=1_000_000_000;
		if ($self->{already_next_song} && $position<$::PlayTime)
		{	warn "UpdateTime: gapless change to next song\n" if $::debug;
			::end_of_file_faketime();
		}
		::UpdateTime($position);
	}
	return 1;
}

sub Stop
{	my $self=shift;
	if (my $playbin= $self->{playbin})
	{	if ($self->{continuous}) { $self->{sink}->set_locked_state(1); $playbin->set_state('null'); $self->{sink}->set_locked_state(0); }
		else { $playbin->set_state('null'); }
	}
	$self->{state_after_skip}=undef;
	$self->{already_next_song}=undef;
	if (my $w=$self->{visual_window}) { $w->queue_draw }
}

sub SkipTo
{	my ($self,$skip)=@_;
	$self->{skip}=$skip;
	my $playbin= $self->{playbin};
	my ($result,$state,$pending)=$playbin->get_state(0);
	return if $result eq 'async'; #when song hasn't started yet, needs to wait until it has started before skipping
	$playbin->seek(1,'time','flush','set', $skip*1_000_000_000,'none',0);
	if (my $new=delete $self->{state_after_skip}) { $playbin->set_state($new); }
	delete $self->{skip};
}

sub Pause
{	my $self=shift;
	$self->{playbin}->set_state('paused');
	$self->{state_after_skip}=undef;
}
sub Resume
{	my $self=shift;
	$self->{playbin}->set_state('playing');
	$self->{state_after_skip}=undef;
}

sub GetVolume	{$::Volume}
sub GetMute	{$::Mute}
sub SetVolume
{	my ($self,$set)=@_;
	if	($set eq 'mute')	{ $::Mute=$::Volume; $::Volume=0;}
	elsif	($set eq 'unmute')	{ $::Volume=$::Mute; $::Mute=0;  }
	elsif	($set=~m/^\+(\d+)$/)	{ $::Volume+=$1; }
	elsif	($set=~m/^-(\d+)$/)	{ $::Volume-=$1; }
	elsif	($set=~m/(\d+)/)	{ $::Volume =$1; }
	$::Volume=0   if $::Volume<0;
	$::Volume=100 if $::Volume>100;
	$self->{volume_busy}=1;
	my $pb= $self->{playbin};
	$pb->set(volume => ( ($::Mute||$::Volume) /100)**3, mute => !!$::Mute) if $pb; 	#use a cubic volume scale
	$self->{volume_busy}=0;
	$::Options{Volume}=$::Volume;
	$::Options{Volume_mute}=$::Mute;
	::QHasChanged('Vol');
}
sub VolumeChanged
{	$VolumeHasChanged=0;
	my $self=$_[0]{self};
	return 0 if $self->{volume_busy};
	return 0 unless $self->{playbin};
	my ($volume,$mute)= $self->{playbin}->get('volume','mute');
	$volume= $volume ** (1/3) *100; #use a cubic volume scale
	$volume= sprintf '%d',$volume;
	$volume=100 if $volume>100;
	#return 0 unless $volume!=$::Volume || ($mute xor !!$::Mute);
	if ($mute)	{ $::Mute=$volume; $::Volume=0; }
	else		{ $::Mute=0; $::Volume=$volume; }
	$::Options{Volume}=$::Volume;
	$::Options{Volume_mute}=$::Mute;
	::QHasChanged('Vol');
	0; #called from an idle
}

sub set_equalizer_preamp
{	my ($self,$volume)=@_;
	my $preamp= $self->{playbin} && $self->{playbin}->get_by_name('equalizer-preamp');
	$preamp->set( volume => $volume**3) if $preamp;
}
sub set_equalizer
{	my ($self,$values)=@_;
	my $equalizer= $self->{playbin} && $self->{playbin}->get_by_name('equalizer');
	return unless $equalizer;
	my @vals= split /:/,$values;
	$equalizer->set( 'band'.$_ => $vals[$_] ) for 0..9;
}

sub _throwaway_equalizer #return false if option to sync is disabled
{	$::Options{gst_sync_EQpresets} && GStreamer1::ElementFactory::make('equalizer-10bands' => 'equalizer');
}
sub EQ_Import_Presets
{	my $equalizer= _throwaway_equalizer;
	return unless $equalizer;
	my $new;
	for my $name (@{ $equalizer->get_preset_names })
	{	next if $::Options{equalizer_presets}{$name}; #ignore if one by that name already exist
		$new++;
		$equalizer->load_preset($name);
		$::Options{equalizer_presets}{$name}= join ':',map $equalizer->get('band'.$_), 0..9;
	}
	::HasChanged('Equalizer','presetlist') if $new;
}
sub EQ_Save_Preset
{	my (undef,$name,$values)=@_;
	my $equalizer= _throwaway_equalizer;
	return unless $equalizer;
	if ($values)
	{	my @vals= split /:/,$values;
		$equalizer->set( 'band'.$_ => $vals[$_]) for 0..9;
		$equalizer->save_preset($name);
	}
	else
	{	$equalizer->delete_preset($name)
	}
}

sub EQ_Get_Range
{	my $self=shift;
	$self->create_playbin unless $self->{playbin};
	my ($min,$max)=(-1,1);
	{	my $equalizer= $self->{playbin}->get_by_name('equalizer')
		 || GStreamer1::ElementFactory::make('equalizer-10bands' => 'equalizer');
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
{	my ($self,$i)=@_;
	$self->create_playbin unless $self->{playbin};
	my $equalizer=  $self->{playbin}->get_by_name('equalizer')
	 || GStreamer1::ElementFactory::make('equalizer-10bands' => 'equalizer');
	return undef unless $equalizer;
	my $hz= $equalizer->find_property('band'.$i)->get_nick;
	if ($hz=~m/^(\d+)\s*(k?)Hz/)
	{	$hz=$1; $hz*=1000 if $2;
		$hz= $hz>=1000 ? sprintf '%.1fkHz',$hz/1000 :
				 sprintf '%dHz',$hz ;
	}
	return $hz;
}

sub RG_set_options
{	my ($self,$rgv,$rgl)=@_;
	my $playbin= $self->{playbin};
	return unless $playbin;
	$rgv||=$playbin->get_by_name('rgvolume');
	$rgl||=$playbin->get_by_name('rglimiter');
	return unless $rgv && $rgl;
	$rgl->set(enabled	=> $::Options{rg_limiter});
	$rgv->set('album-mode'	=> !!$::Options{rg_albummode});
	$rgv->set('pre-amp'	=> $::Options{rg_preamp}||0);
	$rgv->set('fallback-gain'=>$::Options{rg_fallback}||0);
	#$rgv->set(headroom => $::Options{gst_rg_headroom}||0);
}

sub AdvancedOptions
{	my $self=shift;
	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $modif_cb= sub { $self->{modif}=1 };
	my $gapless= ::NewPrefCheckButton(gst_gapless => _"enable gapless (experimental)", cb=> $modif_cb);
	$vbox->pack_start($gapless,::FALSE,::FALSE,2);

	my $monitor_volume= ::NewPrefCheckButton(gst_monitor_pa_volume => _("Monitor the pulseaudio volume").' '._("(unstable)"), cb=> $modif_cb, tip=>_"Makes gmusicbrowser monitor its pulseaudio volume, so that external changes to its volume are known.");
	$vbox->pack_start($monitor_volume,::FALSE,::FALSE,2);

	my $sync_EQpresets= ::NewPrefCheckButton(gst_sync_EQpresets => _"Synchronize equalizer presets", cb=> sub { EQ_Import_Presets(); $modif_cb->() }, tip=>_"Imports gstreamer presets, and synchronize modifications made with gmusicbrowser");
	$vbox->pack_start($sync_EQpresets,::FALSE,::FALSE,2);

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

sub add_visuals
{	my ($self,$window)=@_;
	::weaken( $window->{playobject}=$self );
	unshift @{$self->{visual_windows}}, $window; ::weaken($self->{visual_windows}[0]);
	$self->{has_visuals}++;
	$window->set_double_buffered(0);
	$window->signal_connect(unrealize => sub { my $self=$_[0]{playobject}; $self->remove_visuals($_[0]) if $self; });
	$window->signal_connect(expose_event => sub
	 {	my $self=$_[0]{playobject};
		if ($self && $_[0]{visuals_on} && defined $::TogPlay) { $self->{playbin}->expose }
		else #not connected or stopped -> draw black background
		{	my ($widget,$event)=@_;
			$widget->window->draw_rectangle($widget->style->black_gc,::TRUE,$event->area->values);
		}
		1;
	 });
	if ($window->window) { $self->connect_visuals }
	else
	{	$window->signal_connect(realize => sub { my $self=$_[0]{playobject}; $self->connect_visuals if $self; });
	}
}

sub connect_visuals
{	my $self=shift;
	my ($window)= grep $_ && $_->window, @{$self->{visual_windows}};
	return unless $window && $self->{playbin};
	if (my $w=$self->{visual_window}) { return if $w==$window; $w->{visuals_on}=0; $w->queue_draw; }
	$self->{visual_window}= $window;
	$window->{visuals_on}=1;
	$self->create_playbin unless $self->{playbin};
	$self->{playbin}->set_window_handle($window->window->XID);
	$self->{playbin}->set('flags' => [qw/audio soft-volume vis/]);
	$self->{playbin}->set('force-aspect-ratio',0);
	$self->set_visual;
}
sub remove_visuals
{	my ($self,$window)=@_;
	my $wlist= $self->{visual_windows};
	@$wlist= grep $_ && $_!=$window, @$wlist;
	::weaken($_) for @$wlist; #re-weaken references (the grep above made them strong again)
	$self->{has_visuals}= @$wlist;
	return unless $window->{visuals_on};
	$window->{visuals_on}=0;
	my $new= $wlist->[0];
	if ($new && $new->window) { $self->connect_visuals($new) }
	elsif ($self->{playbin})
	{	$self->{playbin}->set('flags' => [qw/audio soft-volume/]);
		$self->{playbin}->set_window_handle(0);
		$self->{visual_window}= undef;
	}
}
sub set_visual
{	my $self=shift;
	my $visual= shift || $::Options{gst_visual} || '';
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
	$visual= GStreamer1::ElementFactory::make($visual => 'visual');
	if (my $pb=$self->{playbin})
	{	$pb->set('vis-plugin' => $visual);
		$pb->expose;
	}
}
sub list_visuals
{	my @visuals;
	my $reg= GStreamer1::Registry::get;
	for my $plugin (@{$reg->get_plugin_list})
	{	#warn $plugin->get_name;
		my $list=$reg->get_feature_list_by_plugin($plugin->get_name);
		next unless $list;
		for my $elem (@$list)
		{	if ($elem->isa('GStreamer1::ElementFactory'))
			{	my $klass= $elem->get_metadata('klass');
				next unless $klass eq 'Visualization';
				push @visuals,$elem->get_name;
			}
		}
	}
	return @visuals;
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
	{ label => _"Scan as an album",			code => sub { Analyse([join ' ',@{ $_[0]{IDs} }]); },	onlymany=> 'IDs', },
 ],
};
push @::SongCMenu,$RGA_songmenu;

sub Analyse_full
{	my $added='';
	my @todo;
	my $IDs_in_album=  Filter->new('album:-e:')->filter;	#get songs with an album name
	my ($again,$apeak,$ids)=Songs::BuildHash('album',$IDs_in_album,undef,'replaygain_album_gain:same','replaygain_album_peak:same','id:list');
	for my $aid (keys %$again)
	{	next if @{$ids->{$aid}}<2;	#ignore albums with less than 2 songs
		my $gain= $again->{$aid};
		my $peak= $apeak->{$aid};
		next if $gain==$gain && $peak==$peak;	#NaN : album gain/peak not defined or not the same for all songs from album
		my $IDs= $ids->{$aid};
		push @todo,join ' ',@$IDs;
		vec($added,$_,1)=1 for @$IDs;
	}
	my $IDs_no_rg= Filter->newadd(0, 'replaygain_track_gain:-defined:1', 'replaygain_track_peak:-defined:1')->filter;
	push @todo, grep !vec($added,$_,1), @$IDs_no_rg;
	Analyse(\@todo) if @todo;
}

sub Analyse_byAlbum
{	my @IDs= ::uniq(@{ $_[0] });
	my $hash= Songs::BuildHash('album',\@IDs,undef,'id:list');
	my @list;
	for my $aid (keys %$hash)
	{	my $IDs= $hash->{$aid};
		if (@$IDs<2 || Songs::Gid_to_Get('album',$aid) eq '') { push @list, @$IDs; } #no album name or only 1 song in album => push as single songs
		else { push @list, join ' ',@$IDs; } # push as an album
	}
	Analyse(\@list);
}
sub Analyse
{	my $IDs= shift;
	unless ($RGA_pipeline)
	{	$RGA_pipeline=GStreamer1::Pipeline->new('RGA_pipeline');
		my $audiobin=GStreamer1::Bin->new('RGA_audiobin');
		my ($src,$decodebin,$ac,$ar,$rganalysis,$fakesink)=
			map GStreamer1::ElementFactory::make($_ => $_),
			qw/filesrc decodebin audioconvert audioresample rganalysis fakesink/;
		$audiobin->add_many($ac,$ar,$rganalysis,$fakesink);
		$ac->link_many($ar,$rganalysis,$fakesink);
		my $audiopad=$ac->get_static_pad('sink');
		$audiobin->add_pad(GStreamer1::GhostPad ->new('sink', $audiopad));
		$RGA_pipeline->add_many($src,$decodebin,$audiobin);
		$src->link($decodebin);
		$decodebin->signal_connect(pad_added => \&newpad_cb);

		my $bus=$RGA_pipeline->get_bus;
		$bus->add_signal_watch;
		$bus->signal_connect('message::error' => sub { warn "ReplayGain analysis error : ".join(":\n ",Play_GST::_parse_error($_[1]))."\n"; }); #can't use $msg->parse_error as it doesn't work currently : "FIXME - GI_TYPE_TAG_ERROR" (Glib::Object::Introspection-0.027)
		$bus->signal_connect('message::tag' => \&bus_message_tag);
		$bus->signal_connect('message::eos' => \&process_next);
		#FIXME check errors
	}
	my $queue= $RGA_pipeline->{queue}||= [];
	my $nb=0; for my $q (@$queue) { $nb++ for $q=~m/\d+/g; } #count tracks in album lists
	@$queue= ::uniq(@$queue,@$IDs); #remove redundant IDs
	$nb=-$nb; for my $q (@$queue) { $nb++ for $q=~m/\d+/g; } #count nb of added tracks
	::Progress('replaygain', add=>$nb, abortcb=>\&StopAnalysis, title=>_"Replaygain analysis");
	process_next() unless $::Progress{replaygain}{current}; #FIXME maybe check if $RGA_pipeline is running instead
}
sub newpad_cb
{	my ($decodebin,$pad)=@_;
	my $audiopad = $RGA_pipeline->get_by_name('RGA_audiobin')->get_static_pad('sink');
	return if $audiopad->is_linked;
	# check media type
	my $str= $pad->get_current_caps->get_structure(0)->get_name;
	return unless $str=~m/audio/;
	$pad->link($audiopad);
}
sub process_next
{	::Progress('replaygain', inc=>1) if $_[0]; #called from callback => one file has been scanned => increment
	unless ($RGA_pipeline) { ::Progress('replaygain', abort=>1); return; }

	my $rganalysis= $RGA_pipeline->get_by_name('rganalysis');
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
	{	my @list= split / +/,$ID;
		if (@list>1) #album mode
		{	$RGA_pipeline->{albumIDs}= \@list;
			$rganalysis->set('num-tracks' => scalar @list);
			$ID=$list[0];
			$RGA_pipeline->{album_i}=0;
		}
		my $f= Songs::Get($ID,'fullfilename_raw');
		::_utf8_on($f); # pretend it's utf8 to prevent a conversion to utf8 by the bindings
		$RGA_pipeline->{ID}=$ID;
		warn "Analysing [$ID] $f\n" if $::Verbose;
		$RGA_pipeline->get_by_name('filesrc')->set(location => $f);
		$RGA_pipeline->set_state('playing');
		if ($rganalysis->is_locked_state) # for album mode: unlock $rganalysis
		{	#For some reason, GStreamer 1.0's rganalysis element produces an error here unless a flush has been performed
			# http://66125.n4.nabble.com/Problem-with-GStreamer-1-0-EOS-and-set-locked-state-tp4656994.html
			# work-around found in https://bitbucket.org/fk/rgain thanks
			my $pad= $rganalysis->get_static_pad('src');
			$pad->send_event( GStreamer1::Event->new_flush_start );
			$pad->send_event( GStreamer1::Event->new_flush_stop(1) );
			$rganalysis->set_locked_state(0);
		}
	}
	else
	{	$RGA_pipeline->set_state('null');
		$RGA_pipeline=undef;
	}
	1;
}
sub bus_message_tag
{	my $msg=$_[1];
	my $taglist=$msg->parse_tag;
	#warn $tags->to_string;
	#warn GStreamer1::tag_get_type('replaygain-track-gain');
	my (%tags,$count);
	for my $field (qw/replaygain-reference-level replaygain-track-gain replaygain-track-peak replaygain-album-gain replaygain-album-peak/)
	{	my ($nvalues,$firstvalue)= $taglist->get_double($field);
		next unless $nvalues;
		$count++;
		$tags{$field}= $firstvalue;
		#warn "$field: $firstvalue\n";
	}
	return unless $count && $count == $taglist->n_tags; #if other tags than replaygain => doesn't come from the rganalysis element

	my $cID=$RGA_pipeline->{ID};
	if ($::debug)
	{	warn "done for ID=$cID\n";
		warn "done for album IDs=".join(' ',@{$RGA_pipeline->{albumIDs}})."\n" if $RGA_pipeline->{albumIDs} && $RGA_pipeline->get_by_name('rganalysis')->get('num-tracks');
		for my $f (sort keys %tags) { warn " $f : $tags{$f}\n" }
	}
	if ($RGA_pipeline->{albumIDs})
	{	# album mode: store the values for when album is done
		$RGA_pipeline->{album_tosave}{ $cID }= [@tags{'replaygain-track-gain','replaygain-track-peak'}];
		if (exists $tags{'replaygain-album-gain'} && !$RGA_pipeline->get_by_name('rganalysis')->get('num-tracks'))
		{	#album done
			my $IDs= $RGA_pipeline->{albumIDs};
			my $gainpeak= $RGA_pipeline->{album_tosave};
			for my $ID (@$IDs)
			{	@tags{'replaygain-track-gain','replaygain-track-peak'}= @{$gainpeak->{$ID}};
				queuewrite($ID,\%tags,1);
			}
		}
	}
	else
	{	queuewrite($cID,\%tags,0);
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
		push @modif, $field, "$tags->{$key}";#string-ify them with C locale to make sure it's correct
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
		errormsg	=> _"Error while writing replaygain data",
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

my %Encodings;

BEGIN
{ %Encodings=
  (	vorbis	=> { pipeline=>'vorbisenc oggmux',	mime=>'application/ogg',},
	mp3	=> { pipeline=>'lamemp3enc',		mime=>'audio/mpeg'},
  );
}

$::PlayPacks{Play_GST_server}=1; #register the package

sub init
{	my $ok=1;
	my $reg= GStreamer1::Registry::get;
	for my $feature (qw/multifdsink lamemp3enc audioresample audioconvert/)
	{	next if $reg->lookup_feature($feature);
		$ok=0;
		warn "gstreamer plugin '$feature' not found -> gstreamer-server mode not available\n";
	}
	return unless $ok;
	return bless { EQ=>$GST_EQ_ok, visuals => $GST_visuals_ok, RG=>$GST_RG_ok },__PACKAGE__;
}

sub Close
{	my $self=shift;
	close $self->{server} if $self->{server};
	$self->{server}=$self->{sink}=undef;
}

sub Play
{	my $self=shift;
	$self->{continuous}=1;
	Play_GST::Play($self,@_);
}

sub Stop
{	my ($self,$partialstop)=@_;
	unless ($partialstop)
	{	my $sockets= $self->{stream}{sockets};
		for (keys %$sockets)
		{	$sockets->{$_}[1]=0; $self->{stream}->signal_emit(remove => $_);
		}
		$self->{continuous}=0;
	}
	Play_GST::Stop($self);
}

sub check_sink {1}
sub create_sink
{	my $self=shift;
	my $sink=GStreamer1::Bin->new('server');
	my @pipeline=(qw/audioconvert audioresample/);
	my $encoding= $::Options{gst_server_encoding}||'';
	$encoding= 'mp3' unless $Encodings{$encoding};
	$self->{encoding}= $encoding;
	push @pipeline, split / +/, $Encodings{$encoding}{pipeline};
	push @pipeline, 'multifdsink';
	my ($aconv,@elems)= map GStreamer1::ElementFactory::make($_=>$_), @pipeline;
	$sink->add_many($aconv,@elems);
	$aconv->link_many(@elems);
	my $stream= $self->{stream}= pop @elems;
	$stream->{sockets}={};
	$sink->add_pad( GStreamer1::GhostPad->new('sink', $aconv->get_static_pad('sink') ));
	$stream->set('recover-policy'=>'keyframe');
	#$stream->signal_connect($_ => sub {warn "@_"},$_) for 'client-removed', 'client_added', 'client-fd-removed';
	$stream->signal_connect('client-fd-removed' => sub { my $sockets=$_[0]{sockets}; close $sockets->{$_[1]}[0]; delete $sockets->{$_[1]}; ::QHasChanged('connections'); });
	return undef unless $self->Listen;
	return $self->{sink}=$sink;
}

sub Listen
{	my $self=shift;
	my $server;
	my $proto = getprotobyname('tcp');
	my $port=$::Options{Icecast_port};
	my $noerror;
	{	last unless socket($server, PF_INET, SOCK_STREAM, $proto);
		last unless setsockopt($server, SOL_SOCKET, SO_REUSEADDR,pack('l', 1));
		last unless bind($server, sockaddr_in($port, INADDR_ANY));
		last unless listen($server,SOMAXCONN);
		$noerror=1;
	}
	unless ($noerror)
	{	::ErrorPlay("icecast server error : $!");
		return undef;
	}
	$self->{server}= $server;
	Glib::IO->add_watch(fileno($server),'in', \&Connection,$self);
	warn "icecast server listening on port $port\n";
	::HasChanged('connections');
	return 1;
}

sub Connection
{	my $self=$_[2];
	my $client;
	return 0 unless $self->{server};
	my $paddr = accept($client,$self->{server});
	return 1 unless $paddr;
	my($port2,$iaddr) = sockaddr_in($paddr);
	warn 'Connection from ',inet_ntoa($iaddr), " at port $port2\n" if $::Verbose;
	my $request=<$client>;
	warn " $request" if $::debug;
	while (<$client>)
	{	warn " $_" if $::debug;
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
		send $client,$answer.EOL,0;
		close $client;
		return 1;	#keep listening
	}
	my $answer=
	'HTTP/1.0 200 OK'.EOL.
	'Server: iceserver/0.2'.EOL.
	"Content-Type: ".$Encodings{$self->{encoding}}{mime}.EOL.
	"x-audiocast-name: gmusicbrowser stream".EOL.
	'x-audiocast-public: 0'.EOL;
	send $client,$answer.EOL,0;
	#warn $answer;
	my $stream=$self->{stream};
	my $fileno=fileno($client);
	$stream->{sockets}{$fileno}=[$client,1,gethostbyaddr($iaddr,AF_INET)];
	Glib::IO->add_watch($fileno,'hup',sub {warn "Connection closed"; my $stream=$_[2]; $stream->{sockets}{$fileno}[1]=0; ::HasChanged('connections'); $stream->signal_emit(remove => $fileno);return 0; },$stream); #FIXME never called
	$stream->signal_emit(add => $fileno);
	::HasChanged('connections');
	return 1;	#keep listening
}

sub get_connections
{	my $self=shift;
	return () unless $self->{stream};
	my $s= $self->{stream}{sockets};
	return map $s->{$_}[2], grep $s->{$_}[1],keys %$s;
}

1;
