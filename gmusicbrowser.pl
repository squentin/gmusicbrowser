#!/usr/bin/perl

# Copyright (C) 2005-2014 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation
#
# Gmusicbrowser is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;

package main;
use Gtk2 '-init';
use Glib qw/filename_from_unicode filename_to_unicode/;
use POSIX qw/setlocale LC_NUMERIC LC_MESSAGES LC_TIME strftime mktime getcwd _exit/;
use Encode qw/_utf8_on _utf8_off/;
{no warnings 'redefine'; #some work arounds for old versions of perl-Gtk2 and/or gtk2
 *filename_to_utf8displayname=\&Glib::filename_display_name if *Glib::filename_display_name{CODE};
 *PangoEsc=\&Glib::Markup::escape_text if *Glib::Markup::escape_text{CODE}; #needs perl-Gtk2 version >=1.092
 *Gtk2::Notebook::set_tab_reorderable=	sub {} unless *Gtk2::Notebook::set_tab_reorderable{CODE};
 *Gtk2::AboutDialog::set_url_hook=	sub {} unless *Gtk2::AboutDialog::set_url_hook{CODE};	#for perl-Gtk2 version <1.080~1.083
 *Gtk2::Label::set_ellipsize=		sub {} unless *Gtk2::Label::set_ellipsize{CODE};	#for perl-Gtk2 version <1.080~1.083
 *Gtk2::Pango::Layout::set_height=	sub {} unless *Gtk2::Pango::Layout::set_height{CODE};	#for perl-Gtk2 version <1.180  pango <1.20
 *Gtk2::Label::set_line_wrap_mode=	sub {} unless *Gtk2::Label::set_line_wrap_mode{CODE};	#for gtk2 version <2.9 or perl-Gtk2 <1.131
 *Gtk2::Scale::add_mark=		sub {} unless *Gtk2::Scale::add_mark{CODE};		#for gtk2 version <2.16 or perl-Gtk2 <1.230
 *Gtk2::ImageMenuItem::set_always_show_image= sub {} unless *Gtk2::ImageMenuItem::set_always_show_image{CODE};#for gtk2 version <2.16 or perl-Gtk2 <1.230
 *Gtk2::Widget::set_visible= sub { my ($w,$v)=@_; if ($v) {$w->show} else {$w->hide} } unless *Gtk2::Widget::set_visible{CODE}; #for gtk2 version <2.18 or perl-Gtk2 <1.231
 unless (*Gtk2::Widget::set_tooltip_text{CODE})		#for Gtk2 version <2.12
 {	my $Tooltips=Gtk2::Tooltips->new;
	*Gtk2::Widget::set_tooltip_text= sub { $Tooltips->set_tip($_[0],$_[1]); };
	*Gtk2::Widget::set_tooltip_markup= sub { my $markup=$_[1]; $markup=~s/<[^>]*>//g; ;$Tooltips->set_tip($_[0],$markup); }; #remove markup
	*Gtk2::ToolItem::set_tooltip_text= sub { $_[0]->set_tooltip($Tooltips,$_[1],''); };
	*Gtk2::ToolItem::set_tooltip_markup= sub { my $markup=$_[1]; $markup=~s/<[^>]*>//g; $_[0]->set_tooltip($Tooltips,$markup,''); };
 }
 my $set_clip_rectangle_orig=\&Gtk2::Gdk::GC::set_clip_rectangle;
 *Gtk2::Gdk::GC::set_clip_rectangle=sub { &$set_clip_rectangle_orig if $_[1]; } if $Gtk2::VERSION <1.102; #work-around $rect can't be undef in old bindings versions
 if (eval($POSIX::VERSION)<1.18) #previously, date strings returned by strftime needed to be decoded by the locale encoding
 {	my ($encoding)= setlocale(LC_TIME)=~m#\.([^@]+)#;
	$encoding='cp'.$encoding if $^O eq 'MSWin32' && $encoding=~m/^\d+$/;
	if (!Encode::resolve_alias($encoding)) {warn "Can't find dates encoding used for dates, (LC_TIME=".setlocale(LC_TIME)."), dates may have wrong encoding\n";$encoding=undef}
	*strftime_utf8= sub { $encoding ? Encode::decode($encoding, &strftime) : &strftime; };
 }
}
use List::Util qw/min max sum first/;
use File::Copy;
use Fcntl qw/O_NONBLOCK O_WRONLY O_RDWR SEEK_SET/;
use Scalar::Util qw/blessed weaken refaddr/;
use Unicode::Normalize 'NFKD'; #for accent-insensitive sort and search, only used via superlc()
use Carp;
$SIG{INT} = \&Carp::confess;

#use constant SLASH => ($^O  eq 'MSWin32')? '\\' : '/';
use constant SLASH => '/'; #gtk file chooser use '/' in win32 and perl accepts both '/' and '\'

# Find dir containing other files (*.pm & pix/) -> $DATADIR
use FindBin;
our $DATADIR;
BEGIN
{ my @dirs=(	$FindBin::RealBin,
		join (SLASH,$FindBin::RealBin,'..','share','gmusicbrowser') #FIXME remove, all perl files will be in $FindBin::RealBin, gmusicbrowser.pl symlinked to /usr/bin/gmusibrowser
	   );
  ($DATADIR)=grep -e $_.SLASH.'gmusicbrowser_layout.pm', @dirs;
  die "Can't find folder containing data files, looked in @dirs\n" unless $DATADIR;
}
use lib $DATADIR;

use constant
{
 TRUE  => 1,
 FALSE => 0,
 VERSION => '1.1013',
 VERSIONSTRING => '1.1.13',
 PIXPATH => $DATADIR.SLASH.'pix'.SLASH,
 PROGRAM_NAME => 'gmusicbrowser',

 DRAG_STRING	=> 0, DRAG_USTRING	=> 1, DRAG_FILE		=> 2,
 DRAG_ID	=> 3, DRAG_ARTIST	=> 4, DRAG_ALBUM	=> 5,
 DRAG_FILTER	=> 6, DRAG_MARKUP	=> 7,

 PI    => 4 * atan2(1, 1),	#needed for cairo rotation functions
};

sub _ ($) {$_[0]}	#dummy translation functions
sub _p ($$) {_($_[1])}
sub __ { sprintf( ($_[2]>1 ? $_[1] : $_[0]), $_[2]); }
sub __p {shift;&__}
sub __x { my ($s,%h)=@_; $s=~s/{(\w+)}/$h{$1}/g; $s; }
BEGIN
{no warnings 'redefine';
 my $localedir=$DATADIR;
 $localedir= $FindBin::RealBin.SLASH.'..'.SLASH.'share' unless -d $localedir.SLASH.'locale';
 $localedir.=SLASH.'locale';
 my $domain='gmusicbrowser';
 eval {require Locale::Messages;};
 if ($@)
 {	eval {require Locale::gettext};
	if ($@) { warn "neither Locale::Messages, nor Locale::gettext found -> no translations\n"; }
	elsif ($Locale::gettext::VERSION<1.04) { warn "Needs at least version 1.04 of Locale::gettext, v$Locale::gettext::VERSION found -> no translations\n" }
	else
	{	warn "Locale::Messages not found, using Locale::gettext instead\n" if $::debug;
		my $d= eval { Locale::gettext->domain($domain); };
		if ($@) { warn "Locale::gettext error : $@\n -> no translations\n"; }
		else
		{	$d->dir($localedir);
			*_=sub ($) { $d->get($_[0]); };
			*__=sub { sprintf $d->nget(@_),$_[2]; };
		}
	}
 }
 else
 {	Locale::Messages::textdomain($domain);
	Locale::Messages::bindtextdomain($domain=> $localedir);
	Locale::Messages::bind_textdomain_codeset($domain=> 'utf-8');
	Locale::Messages::bind_textdomain_filter($domain=> \&Locale::Messages::turn_utf_8_on);
	*_  = \&Locale::Messages::gettext;
	*_p = \&Locale::Messages::pgettext;
	*__ =sub { sprintf Locale::Messages::ngettext(@_),$_[2]; };
	*__p=sub { sprintf Locale::Messages::npgettext(@_),$_[3];};
 }
}

our $QSLASH;	#quoted SLASH for use in regex

# %html_entities and decode_html() are only used if HTML::Entities is not found
my %html_entities=
(	amp => '&', 'lt' => '<', 'gt' => '>', quot => '"', apos => "'",
	raquo => '»', copy => '©', middot => '·',
	acirc => 'â', eacute => 'é', egrave => 'è', ecirc => 'ê',
	agrave=> 'à', ccedil => 'ç',
);
sub decode_html
{	my $s=shift;
	$s=~s/&(?:#(\d+)|#x([0-9A-F]+)|([a-z]+));/$1 ? chr($1) : $2 ? chr(hex $2) : $html_entities{$3}||'?'/egi;
	return $s;
}
BEGIN
{	no warnings 'redefine';
	eval {require HTML::Entities};
	*decode_html= \&HTML::Entities::decode_entities unless $@;
	$QSLASH=quotemeta SLASH;
}

sub file_name_is_absolute
{	my $path=shift;
	$^O eq 'MSWin32' ? $path=~m#^\w:$QSLASH#o : $path=~m#^$QSLASH#o;
}
sub rel2abs
{	my ($path,$base)=@_;
	return $path if file_name_is_absolute($path);
	$base||= POSIX::getcwd;
	return catfile($base,$path);
}
sub catfile
{	my $path=join SLASH,@_;
	$path=~s#$QSLASH{2,}#SLASH#goe;
	return $path;
}
sub pathslash
{	#return catfile($_[0],'');
	my $path=shift;
	$path.=SLASH unless $path=~m/$QSLASH$/o;
	return $path;
}
sub simplify_path
{	my ($path,$end_with_slash)=@_;
	1 while $path=~s#$QSLASH+[^$QSLASH]+$QSLASH\.\.(?:$QSLASH+|$)#SLASH#oe;
	return cleanpath($path,$end_with_slash);
}
sub cleanpath	#remove repeated slashes, /./, and make sure it (does or doesn't) end with a slash
{	my ($path,$end_with_slash)=@_;
	$path=~s#$QSLASH\.$QSLASH#SLASH#goe;
	$path=~s#$QSLASH{2,}#SLASH#goe;
	$path=~s#$QSLASH$##o;
	$path.=SLASH if $end_with_slash || $path!~m#$QSLASH#o; # $end_with_slash or root folder
	return $path;
}
sub splitpath
{	my $path=shift;
	my $file= $path=~s#$QSLASH+([^$QSLASH]+)$##o ? $1 : '';
	$path.=SLASH unless $path=~m#$QSLASH#o; #root folder
	return $path,$file;
}
sub dirname
{	(&splitpath)[0];
}
sub parentdir
{	my $path=shift;
	$path=~s#$QSLASH+$##o;
	return $path=~m#$QSLASH#o ? dirname($path) : undef;
}
sub basename
{	my $file=shift;
	return $file=~m#([^$QSLASH]+)$#o ? $1 : '';
}
sub barename #filename without extension
{	my $file=&basename;
	my $ext= $file=~s#\.([^.]*)$##o ? $1 : '';
	return wantarray ? ($file,$ext) : $file;
}

our %Alias_ext;	#define alternate file extensions (ie: .ogg files treated as .oga files)
INIT {%Alias_ext=(ogg=> 'oga', m4b=>'m4a');} #needs to be in a INIT block because used in a INIT block in gmusicbrowser_tags.pm
our @ScanExt= qw/mp3 ogg oga flac mpc ape wv m4a m4b/;

our ($Verbose,$debug);
our %CmdLine;
our ($HomeDir,$SaveFile,$FIFOFile,$ImportFile,$DBus_id,$DBus_suffix);
our $TempDir;
sub find_gmbrc_file { my @f= map $_[0].$_, '','.gz','.xz'; return wantarray ? (grep { -e $_ } @f) : first { -e $_ } @f }
my $gmbrc_ext_re= qr/\.gz$|\.xz$/;

# Parse command line
BEGIN	# in a BEGIN block so that commands for a running instance are sent sooner/faster
{ $DBus_id='org.gmusicbrowser'; $DBus_suffix='';

  my $default_home= Glib::get_user_config_dir.SLASH.'gmusicbrowser';
  if (!-d $default_home && -d (my $old= Glib::get_home_dir.SLASH.'.gmusicbrowser' ) )
  {	warn "Using folder $old for configuration, you could move it to $default_home to conform to the XDG Base Directory Specification\n";
	$default_home=$old;
  }

my $help=PROGRAM_NAME.' v'.VERSIONSTRING." (c)2005-2014 Quentin Sculo
options :
-nocheck: don't check for updated/deleted songs on startup
-noscan	: don't scan folders for songs on startup
-demo	: don't save settings/tags on exit
-ro	: prevent modifying/renaming/deleting song files
-rotags	: prevent modifying tags of music files
-play	: start playing on startup
-gst	: use gstreamer
-nogst  : do not use gstreamer
-server	: send playing song to connected icecast clent
-port N : listen for connection on port N in icecast server mode
-verbose: print some info, like the file being played
-debug	: print lots of mostly useless informations, implies -verbose
-backtrace : print a backtrace for every warning
-nodbus	: do not provide DBus services
-dbus-id KEY : append .KEY to the DBus service id used by gmusicbrowser (org.gmusicbrowser)
-nofifo : do not create/use named pipe
-F FIFO, -fifo FILE	: use FIFO as named pipe to receive commands (instead of 'gmusicbrowser.fifo' in default folder)
-C FILE, -cfg FILE	: use FILE as configuration file (instead of 'gmbrc' in default folder),
			  if FILE is a folder, sets the default folder to FILE.
-l NAME, -layout NAME	: Use layout NAME for player window
+plugin NAME		: Enable plugin NAME
-plugin NAME		: Disable plugin NAME
-noplugins		: Disable all plugins
-searchpath FOLDER	: Additional FOLDER to look for plugins and layouts
-use-gnome-session 	: Use gnome libraries to save tags/settings on session logout
-workspace N		: move initial window to workspace N (requires Gnome2::Wnck)
-gzip			: force not compressing gmbrc
+gzip			: force compressing gmbrc with gzip
+xz			: force compressing gmbrc with xz

-cmd CMD		: add CMD to the list of commands to execute
-ifnotrunning MODE	: change behavior when no running gmusicbrowser instance is found
	MODE can be one of :
	* normal (default)	: launch a new instance and execute commands
	* nocmd			: launch a new instance but discard commands
	* abort			: do nothing
-nolaunch		: same as : -ifnotrunning abort
Running instances of gmusicbrowser are detected via the fifo or via DBus.
To run more than one instance, use a unique fifo and a unique DBus-id, or deactivate them.

Options to change what is done with files/folders passed as arguments (done in running gmusicbrowser if there is one) :
-playlist		: Set them as playlist (default)
-enqueue		: Enqueue them
-addplaylist		: Add them to the playlist
-insertplaylist		: Insert them in the playlist after current song
-add			: Add them to the library

-tagedit FOLDER_OR_FILE ... : Edittag mode
-listplugin	: list the available plugins and exit
-listcmd	: list the available fifo commands and exit
-listlayout	: list the available layouts and exit
";
  unshift @ARGV,'-tagedit' if $0=~m/tagedit/;
  $CmdLine{gst}=0;
  my (@files,$filescmd,@cmd,$ignore);
  my $ifnotrunning='normal';
   while (defined (my $arg=shift))
   {	if   ($arg eq '-c' || $arg eq '-nocheck')	{$CmdLine{nocheck}=1}
	elsif($arg eq '-s' || $arg eq '-noscan')	{$CmdLine{noscan}=1}
	elsif($arg eq '-demo')		{$CmdLine{demo}=1}
	elsif($arg eq '-play')		{$CmdLine{play}=1}
	elsif($arg eq '-hide')		{$CmdLine{hide}=1}
	elsif($arg eq '-server')	{$CmdLine{server}=1}
	elsif($arg eq '-nodbus')	{$CmdLine{noDBus}=1}
	elsif($arg eq '-nogst')		{$CmdLine{gst}=0}
	elsif($arg eq '-gst')		{$CmdLine{gst}=1}
	elsif($arg eq '-ro')		{$CmdLine{ro}=$CmdLine{rotags}=1}
	elsif($arg eq '-rotags')	{$CmdLine{rotags}=1}
	elsif($arg eq '-port')		{$CmdLine{port}=shift if $ARGV[0]}
	elsif($arg eq '-verbose')	{$Verbose=1}
	elsif($arg eq '-debug')		{$debug=$Verbose=4}
	elsif($arg eq '-backtrace')	{ $SIG{ __WARN__ } = \&Carp::cluck; $SIG{ __DIE__ } = \&Carp::confess; }
	elsif($arg eq '-nofifo')	{$FIFOFile=''}
	elsif($arg eq '-workspace')	{$CmdLine{workspace}=shift if defined $ARGV[0]} #requires Gnome2::Wnck
	elsif($arg eq '-C' || $arg eq '-cfg')		{$CmdLine{savefile}=shift if $ARGV[0]}
	elsif($arg eq '-F' || $arg eq '-fifo')		{$FIFOFile=rel2abs(shift) if $ARGV[0]}
	elsif($arg eq '-l' || $arg eq '-layout')	{$CmdLine{layout}=shift if $ARGV[0]}
	elsif($arg eq '-import')	{ $ImportFile=rel2abs(shift) if $ARGV[0]}
	elsif($arg eq '-searchpath')	{ push @{ $CmdLine{searchpath} },shift if $ARGV[0]}
	elsif($arg=~m/^([+-])plugin$/)	{ $CmdLine{plugins}{shift @ARGV}=($1 eq '+') if $ARGV[0]}
	elsif($arg eq '-noplugins')	{ $CmdLine{noplugins}=1; delete $CmdLine{plugins}; }
	elsif($arg=~m/^([+-])gzip$/)	{ $CmdLine{gzip}= $1 eq '+' ? 'gzip':''}
	elsif($arg=~m/^([+-])xz$/)	{ $CmdLine{gzip}= $1 eq '+' ? 'xz':''}
	elsif($arg eq '-geometry')	{ $CmdLine{geometry}=shift if $ARGV[0]; }
	elsif($arg eq '-tagedit')	{ $CmdLine{tagedit}=1; $ignore=1; last; }
	elsif($arg eq '-listplugin')	{ $CmdLine{pluginlist}=1; $ignore=1; last; }
	elsif($arg eq '-listcmd')	{ $CmdLine{cmdlist}=1; $ignore=1; last; }
	elsif($arg eq '-listlayout')	{ $CmdLine{layoutlist}=1; $ignore=1; last; }
	elsif($arg eq '-cmd')		{ push @cmd, shift if $ARGV[0]; }
	elsif($arg eq '-ifnotrunning')	{ $ifnotrunning=shift if $ARGV[0]; }
	elsif($arg eq '-nolaunch')	{ $ifnotrunning='abort'; }
	elsif($arg eq '-dbus-id')	{ if (my $id=shift) { if ($id=~m/^\w+$/) { $DBus_id.= $DBus_suffix='.'.$id; } else { warn "invalid dbus-id '$id', only letters, numbers and _ allowed\n" }; } }
	elsif($arg eq '-add')		{ $filescmd='AddToLibrary'; }
	elsif($arg eq '-playlist')	{ $filescmd='OpenFiles'; }
	elsif($arg eq '-enqueue')	{ $filescmd='EnqueueFiles'; }
	elsif($arg eq '-addplaylist')	{ $filescmd='AddFilesToPlaylist'; }
	elsif($arg eq '-insertplaylist'){ $filescmd='InsertFilesInPlaylist'; }
	elsif($arg eq '-use-gnome-session'){ $CmdLine{UseGnomeSession}=1; }
	elsif($arg=~m#^http://# || -e $arg) { push @files,$arg }
	else
	{	warn "unknown option '$arg'\n" unless $arg=~/^--?h(elp)?$/;
		print $help;
		exit;
	}
   }
   unless ($ignore)
   {	# filenames given in the command line
	if (@files)
	{	for my $f (@files)
		{	unless ($f=~m#^http://#)
			{	$f=rel2abs($f);
				$f=~s/([^A-Za-z0-9])/sprintf('%%%02X', ord($1))/seg; #FIXME use url_escapeall, but not yet defined
			}
		}
		$filescmd ||= 'OpenFiles';
		my $cmd="$filescmd(@files)";
		push @cmd, $cmd;
	}

	# determine $HomeDir $SaveFile $ImportFile and $FIFOFile
	my $save= delete $CmdLine{savefile};
	if (defined $save)
	{	my $isdir= $save=~m#/$#;	## $save is considered a folder if ends with a "/"
		$save= rel2abs($save);
		if (-d $save || $isdir) { $HomeDir = $save; }
		else			{ $SaveFile= $save; }
	}
	warn "using '$HomeDir' folder for saving/setting folder instead of '$default_home'\n" if $debug && $HomeDir;
	$HomeDir= pathslash(cleanpath($HomeDir || $default_home)); # $HomeDir must end with a slash
	if (!-d $HomeDir)
	{	warn "Creating folder $HomeDir\n";
		my $current='';
		for my $dir (split /$QSLASH/o,$HomeDir)
		{	$current.=SLASH.$dir;
			next if -d $current;
			die "Can't create folder $HomeDir : $!\n" unless mkdir $current;
		}
	}
	# auto import from old v1.0 tags file if using default savefile, it doesn't exist and old tags file exists
	if (!$SaveFile && !find_gmbrc_file($HomeDir.'gmbrc') && -e $HomeDir.'tags') { $ImportFile||=$HomeDir.'tags'; }

	$SaveFile||= $HomeDir.'gmbrc';
	$FIFOFile= $HomeDir.'gmusicbrowser.fifo' if !defined $FIFOFile && $^O ne 'MSWin32';

	#check if there is an instance already running
	my $running;
	if ($FIFOFile && -p $FIFOFile)
	{	my @c= @cmd ? @cmd : ('Show');	#fallback to "Show" command
		my $ok=sysopen my$fifofh,$FIFOFile, O_NONBLOCK | O_WRONLY;
		if ($ok)
		{	print $fifofh "$_\n" and $running=1 for @c;
			close $fifofh;
			$running&&= "using '$FIFOFile'";
		}
		else {warn "Found orphaned fifo '$FIFOFile' : previous session wasn't closed properly\n"}
	}
	if (!$running && !$CmdLine{noDBus})
	{	eval {require 'gmusicbrowser_dbus.pm'}
		|| warn "Error loading gmusicbrowser_dbus.pm :\n$@ => controlling gmusicbrowser through DBus won't be possible.\n\n";
		eval
		{	my $bus= $GMB::DBus::bus || die;
			my $service = $bus->get_service($DBus_id) || die;
			my $object = $service->get_object('/org/gmusicbrowser', 'org.gmusicbrowser') || die;
			$object->RunCommand($_) for @cmd;
		};
		$running="using DBus id=$DBus_id" unless $@;
	}
	if ($running)
	{	warn "Found a running instance ($running)\n";
		exit;
	}
	else
	{	exit if $ifnotrunning eq 'abort';
		@cmd=() if $ifnotrunning eq 'nocmd';
	}
	$CmdLine{runcmd}=\@cmd if @cmd;
   }
}
# end of command line handling

our $HTTP_module;
BEGIN{
require 'gmusicbrowser_songs.pm';
require 'gmusicbrowser_tags.pm';
require 'gmusicbrowser_layout.pm';
require 'gmusicbrowser_list.pm';
$HTTP_module=	-e $DATADIR.SLASH.'simple_http_wget.pm' && (grep -x $_.SLASH.'wget', split /:/, $ENV{PATH})	? 'simple_http_wget.pm' :
		-e $DATADIR.SLASH.'simple_http_AE.pm'   && (grep -f $_.SLASH.'AnyEvent'.SLASH.'HTTP.pm', @INC)	? 'simple_http_AE.pm' :
		'simple_http.pm';
#warn "using $HTTP_module for http requests\n";
#require $HTTP_module;
$TempDir= Glib::get_tmp_dir.SLASH; _utf8_off($TempDir); #turn utf8 flag off to not auto-utf8-upgrade other filenames in the same strings
}

our $CairoOK;
my ($UseGtk2StatusIcon,$TrayIconAvailable);
BEGIN
{ if (*Gtk2::StatusIcon::set_has_tooltip{CODE}) { $TrayIconAvailable= $UseGtk2StatusIcon= 1; }
  else
  {	eval { require Gtk2::TrayIcon; $TrayIconAvailable=1; };
	if ($@) { warn "Gtk2::TrayIcon not found -> tray icon won't be available\n"; }
  }
  eval { require Cairo; $CairoOK=1; };
  if ($@) { warn "Cairo perl module not found -> transparent windows and other effects won't be available\n"; }
}

our $Image_ext_re; # = qr/\.(?:jpe?g|png|gif|bmp)$/i;
BEGIN
{ my $re=join '|', sort map @{$_->{extensions}}, Gtk2::Gdk::Pixbuf->get_formats;
  $Image_ext_re=qr/\.(?:$re)$/i;
}

##########

#our $re_spaces_unlessinbrackets=qr/([^( ]+(?:\(.*?\))?)(?: +|$)/; #breaks "widget1(options with spaces) widget2" in "widget1(options with spaces)" and "widget2" #replaced by ExtractNameAndOptions

my ($browsercmd,$opendircmd);

#changes to %QActions must be followed by a call to Update_QueueActionList()
# changed : called from Queue or QueueAction changed
# action : called when queue is empty
# keep : do not clear mode once empty
# save : save mode when RememberQueue is on
# condition : do not show mode if return false
# order : used to sort modes
# autofill : indicate that this mode use the maxautofill value
# can_next : this mode can be use with $NextAction
our %QActions=
(	''	=> {order=>0,				short=> _"normal",		long=> _"Normal mode", can_next=>1, },
	autofill=> {order=>10, icon=>'gtk-refresh',	short=> _"autofill",		long=> _"Auto-fill queue",					changed=>\&QAutoFill,	 keep=>1,save=>1,autofill=>1, },
	'wait'	=> {order=>20, icon=>'gmb-wait',	short=> _"wait for more",	long=> _"Wait for more when queue empty",	action=>\&Stop,	changed=>\&QWaitAutoPlay,keep=>1,save=>1, },
	stop	=> {order=>30, icon=>'gtk-media-stop',	short=> _"stop",		long=> _"Stop when queue empty",		action=>\&Stop,
			can_next=>1, long_next=>_"Stop after this song", },
	quit	=> {order=>40, icon=>'gtk-quit',	short=> _"quit",		long=> _"Quit when queue empty",		action=>\&Quit,
			can_next=>1, long_next=>_"Quit after this song"},
	turnoff => {order=>50, icon=>'gmb-turnoff',	short=> _"turn off",		long=> _"Turn off computer when queue empty", 	action=>sub {Stop(); TurnOff();},
			condition=> sub { $::Options{Shutdown_cmd} }, can_next=>1, long_next=>_"Turn off computer after this song"},
);

our %StockLabel=( 'gmb-turnoff' => _"Turn Off" );

our @DRAGTYPES;
@DRAGTYPES[DRAG_FILE,DRAG_USTRING,DRAG_STRING,DRAG_MARKUP,DRAG_ID,DRAG_ARTIST,DRAG_ALBUM,DRAG_FILTER]=
(	['text/uri-list'],
	['text/plain;charset=utf-8'],
	['STRING'],
	['markup'],
	[SongID =>
		{ DRAG_FILE,	sub { Songs::Map('uri',\@_); },
		  DRAG_ARTIST,	sub { @{Songs::UniqList('artist',\@_,1)}; },
		  DRAG_ALBUM,	sub { @{Songs::UniqList('album',\@_,1)}; },
		  DRAG_USTRING,	sub { (@_==1)? Songs::Display($_[0],'title') : __("%d song","%d songs",scalar@_) },
		  #DRAG_STRING,	undef, #will use DRAG_USTRING
		  DRAG_STRING,	sub { Songs::Map('uri',\@_); },
		  DRAG_FILTER,	sub {Filter->newadd(FALSE,map 'title:~:'.Songs::Get($_,'title'),@_)->{string}},
		  DRAG_MARKUP,	sub {	return ReplaceFieldsAndEsc($_[0],_"<b>%t</b>\n<small><small>by</small> %a\n<small>from</small> %l</small>") if @_==1;
					my $nba=@{Songs::UniqList2('artist',\@_)};
			  		my $artists= ($nba==1)? Songs::DisplayEsc($_[0],'artist') : __("%d artist","%d artists",$nba);
			  		__x(	_("{songs} by {artists}") . "\n<small>{length}</small>",
						songs => __("%d song","%d songs",scalar@_),
						artists => $artists,
						'length' => CalcListLength(\@_,'length')
					)},
		}],
	[Artist => {	DRAG_USTRING,	sub { (@_<10)? join("\n",@{Songs::Gid_to_Display('artist',\@_)}) : __("%d artist","%d artists",scalar@_) },
			#DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_STRING,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->filter; SortList($l); Songs::Map('uri',$l); },
			DRAG_FILE,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->filter; SortList($l); Songs::Map('uri',$l); },
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->filter; SortList($l); @$l; },
		}],
	[Album  => {	DRAG_USTRING,	sub { (@_<10)? join("\n",@{Songs::Gid_to_Display('album',\@_)}) : __("%d album","%d albums",scalar@_) },
			#DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_STRING,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->filter; SortList($l); Songs::Map('uri',$l); },
			DRAG_FILE,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->filter; SortList($l); Songs::Map('uri',$l); },
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->filter; SortList($l); @$l; },
		}],
	[Filter =>
		{	DRAG_USTRING,	sub {Filter->new($_[0])->explain},
			#DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_STRING,	sub { my $l=Filter->new($_[0])->filter; SortList($l); Songs::Map('uri',$l); },
			DRAG_ID,	sub { my $l=Filter->new($_[0])->filter; SortList($l); @$l; },
			DRAG_FILE,	sub { my $l=Filter->new($_[0])->filter; SortList($l); Songs::Map('uri',$l); },
		}
	],
);
our %DRAGTYPES;
$DRAGTYPES{$DRAGTYPES[$_][0]}=$_ for DRAG_FILE,DRAG_USTRING,DRAG_STRING,DRAG_ID,DRAG_ARTIST,DRAG_ALBUM,DRAG_FILTER,DRAG_MARKUP;

our @submenuRemove=
(	{ label => sub {$_[0]{mode} eq 'Q' ? _"Remove from queue" : $_[0]{mode} eq 'A' ? _"Remove from playlist" : _"Remove from list"},	code => sub { $_[0]{self}->RemoveSelected; }, mode => 'BLQA', istrue=> 'allowremove', },
	{ label => _"Remove from library",	code => sub { SongsRemove($_[0]{IDs}); }, },
	{ label => _"Remove from disk",		code => sub { DeleteFiles($_[0]{IDs}); },	test => sub {!$CmdLine{ro}},	stockicon => 'gtk-delete' },
);
our @submenuQueue=
(	{ label => _"Prepend",			code => sub {  QueueInsert( @{ $_[0]{IDs} } ); }, },
	{ label => _"Replace",			code => sub { ReplaceQueue( @{ $_[0]{IDs} } ); }, },
	{ label => _"Append",			code => sub {      Enqueue( @{ $_[0]{IDs} } ); }, },
);
#modes : S:Search, B:Browser, Q:Queue, L:List, P:Playing song in the player window, F:Filter Panels (submenu "x songs")
our @SongCMenu=
(	{ label => _"Song Properties",	code => sub { DialogSongProp (@{ $_[0]{IDs} }); },	onlyone => 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Songs Properties",	code => sub { DialogSongsProp(@{ $_[0]{IDs} }); },	onlymany=> 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Play Only Selected",code => sub { Select(song => 'first', play => 1, staticlist => $_[0]{IDs} ); },
		onlymany => 'IDs', 	stockicon => 'gtk-media-play'},
	{ label => _"Play Only Displayed",code => sub { Select(song => 'first', play => 1, staticlist => \@{$_[0]{listIDs}} ); },
		test => sub { @{$_[0]{IDs}}<2 }, notmode => 'A',	onlymany => 'listIDs',	stockicon => 'gtk-media-play' },
	{ label => _"Enqueue Selected",		code => sub { Enqueue(@{ $_[0]{IDs} }); },	submenu3=> \@submenuQueue,
		notempty => 'IDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Enqueue Displayed",	code => sub { Enqueue(@{ $_[0]{listIDs} }); },
		empty => 'IDs',	notempty=> 'listIDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Add to list",	submenu => \&AddToListMenu,	notempty => 'IDs' },
	{ label => _"Edit Labels",	submenu => \&LabelEditMenu,	notempty => 'IDs' },
	{ label => _"Edit Rating",	submenu => sub{ Stars::createmenu('rating',$_[0]{IDs}); },	notempty => 'IDs' },
	{ label => _"Find songs with the same names",	code => sub { SearchSame('title',$_[0]) },	mode => 'B',	notempty => 'IDs' },
	{ label => _"Find songs with same artists",	code => sub { SearchSame('artists',$_[0])},	mode => 'B',	notempty => 'IDs' },
	{ label => _"Find songs in same albums",	code => sub { SearchSame('album',$_[0]) },	mode => 'B',	notempty => 'IDs' },
	{ label => _"Rename file",	code => sub { DialogRename(	@{ $_[0]{IDs} }); },	onlyone => 'IDs',	test => sub {!$CmdLine{ro}}, },
	{ label => _"Mass Rename",	code => sub { DialogMassRename(	@{ $_[0]{IDs} }); },	onlymany=> 'IDs',	test => sub {!$CmdLine{ro}}, },
	{ label => _"Copy",	code => sub { CopyMoveFilesDialog($_[0]{IDs},TRUE); },
		notempty => 'IDs',	stockicon => 'gtk-copy', notmode => 'P' },
	{ label => _"Move",	code => sub { CopyMoveFilesDialog($_[0]{IDs},FALSE); },
		notempty => 'IDs',	notmode => 'P',	test => sub {!$CmdLine{ro}}, },
	#{ label => sub {'Remove from '.($_[0]{mode} eq 'Q' ? 'queue' : 'this list')}, code => sub { $_[0]{self}->RemoveSelected; },	stockicon => 'gtk-remove',	notempty => 'IDs', mode => 'LQ' }, #FIXME
	{ label => _"Remove",	submenu => \@submenuRemove,	stockicon => 'gtk-remove',	notempty => 'IDs',	notmode => 'P' },
	{ label => _"Re-read tags",	code => sub { ReReadTags(@{ $_[0]{IDs} }); },
		notempty => 'IDs',	notmode => 'P',	stockicon => 'gtk-refresh' },
	{ label => _"Same Title",     submenu => sub { ChooseSongsTitle(	$_[0]{IDs}[0] ); },	mode => 'P' },
	{ label => _"Edit Lyrics",	code => sub { EditLyrics(	$_[0]{IDs}[0] ); },	mode => 'P' },
	{ label => _"Lookup in google",	code => sub { Google(		$_[0]{IDs}[0] ); },	mode => 'P' },
	{ label => _"Open containing folder",	code => sub { openfolder( Songs::Get( $_[0]{IDs}[0], 'path') ); },	onlyone => 'IDs' },
	{ label => _"Queue options", submenu => \@Layout::MenuQueue, mode => 'Q', }
);
our @cMenuAA=
(	{ label => _"Lock",	code => sub { ToggleLock($_[0]{lockfield}); }, check => sub { $::TogLock && $::TogLock eq $_[0]{lockfield}}, mode => 'P',
	  test	=> sub { $_[0]{field} eq $_[0]{lockfield} || $_[0]{gid} == Songs::Get_gid($::SongID,$_[0]{lockfield}); },
	},
	{ label => _"Lookup in AMG",	code => sub { AMGLookup( $_[0]{mainfield}, $_[0]{aaname} ); },
	  test => sub { $_[0]{mainfield} =~m/^album$|^artist$|^title$/; },
	},
	{ label => _"Filter",		code => sub { Select(filter => Songs::MakeFilterFromGID($_[0]{field},$_[0]{gid})); },	stockicon => 'gmb-filter', mode => 'P' },
	{ label => \&SongsSubMenuTitle,		submenu => \&SongsSubMenu, },
	{ label => sub {$_[0]{mode} eq 'P' ? _"Display Songs" : _"Filter"},	code => \&FilterOnAA,
		test => sub { GetSonglist( $_[0]{self} ) }, },
	{ label => _"Set Picture",	code => sub { ChooseAAPicture($_[0]{ID},$_[0]{mainfield},$_[0]{gid}); },
		stockicon => 'gmb-picture' },
);

our @TrayMenu=
(	{ label=> sub {$::TogPlay ? _"Pause" : _"Play"}, code => \&PlayPause,	stockicon => sub { $::TogPlay ? 'gtk-media-pause' : 'gtk-media-play'; }, id=>'playpause' },
	{ label=> _"Stop", code => \&Stop,	stockicon => 'gtk-media-stop' },
	{ label=> _"Next", code => \&NextSong,	stockicon => 'gtk-media-next', id=>'next', },
	{ label=> _"Recently played", submenu => sub { my $m=ChooseSongs([GetPrevSongs(8)]); }, stockicon => 'gtk-media-previous' },
	{ label=> sub {$::TogLock && $::TogLock eq 'first_artist'? _"Unlock Artist" : _"Lock Artist"},	code => sub {ToggleLock('first_artist');} },
	{ label=> sub {$::TogLock && $::TogLock eq 'album' ? _"Unlock Album"  : _"Lock Album"},	code => sub {ToggleLock('album');} },
	{ label=> _"Windows",	code => \&PresentWindow,	submenu_ordered_hash =>1,
		submenu => sub {  [map { $_->layout_name => $_ } grep $_->isa('Layout::Window'), Gtk2::Window->list_toplevels];  }, },
	{ label=> sub { IsWindowVisible($::MainWindow) ? _"Hide": _"Show"}, code => sub { ShowHide(); }, id=>'showhide', },
	{ label=> _"Fullscreen",	code => \&ToggleFullscreenLayout,	stockicon => 'gtk-fullscreen' },
	{ label=> _"Settings",		code => 'OpenPref',	stockicon => 'gtk-preferences' },
	{ label=> _"Quit",		code => \&Quit,		stockicon => 'gtk-quit' },
);

our %Artists_split=
(	'\s*&\s*'		=> "&",
	'\s*\\+\s*'		=> "+",
	'\s*\\|\s*'		=> "|",
	'\s*;\s*'		=> ";",
	'\s*/\s*'		=> "/",
	'\s*,\s+'		=> ", ",
	',?\s+and\s+'		=> "and",	#case-sensitive because the user might want to use "And" in artist names that should NOT be splitted
	',?\s+And\s+'		=> "And",
	'\s+featuring\s+'	=> "featuring",
	'\s+feat\.\s+'		=> "feat.",
);
our %Artists_from_title=
(	'\(with\s+([^)]+)\)'		=> "(with X)",
	'\(feat\.\s+([^)]+)\)'		=> "(feat. X)",
	'\(featuring\s+([^)]+)\)'	=> "(featuring X)",
);


#a few inactive debug functions
sub red {}
sub blue {}
sub callstack {}

sub url_escapeall
{	my $s=$_[0];
	_utf8_off($s); # or "use bytes" ?
	$s=~s#([^A-Za-z0-9])#sprintf('%%%02X', ord($1))#seg;
	return $s;
}
sub url_escape
{	my $s=$_[0];
	_utf8_off($s);
	$s=~s#([^/\$_.+!*'(),A-Za-z0-9-])#sprintf('%%%02X',ord($1))#seg;
	return $s;
}
sub decode_url
{	my $s=$_[0];
	return undef unless defined $s;
	_utf8_off($s);
	$s=~s#%([0-9A-F]{2})#chr(hex $1)#ieg;
	return $s;
}

sub PangoEsc	# escape special chars for pango ( & < > ) #replaced by Glib::Markup::escape_text if available
{	local $_=$_[0];
	return '' unless defined;
	s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g;
	s/"/&quot;/g; s/'/&apos;/g; # doesn't seem to be needed
	return $_;
}
sub MarkupFormat
{	my $format=shift;
	sprintf $format, map PangoEsc($_), @_;
}
sub Gtk2::Label::new_with_format
{	my $class=shift;
	my $label=Gtk2::Label->new;
	$label->set_markup( MarkupFormat(@_) );
	return $label;
}
sub Gtk2::Label::set_markup_with_format
{	my $label=shift;
	$label->set_markup( MarkupFormat(@_) );
}
sub Gtk2::Dialog::add_button_custom
{	my ($dialog,$text,$response_id,%args)=@_;
	my ($icon,$tip,$secondary)=@args{qw/icon tip secondary/};
	my $button= Gtk2::Button->new;
	$button->set_image( Gtk2::Image->new_from_stock($icon,'menu') ) if $icon;
	$button->set_label($text);
	$button->set_use_underline(1);
	$button->set_tooltip_text($tip) if defined $tip;
	$dialog->add_action_widget($button,$response_id);
	if ($secondary)
	{	my $bb=$button->parent;
		if ($bb && $bb->isa('Gtk2::ButtonBox')) { $bb->set_child_secondary($button,1); }
	}
	return $button;
}

sub Gtk2::Window::force_present #force bringing the window to the current workspace, $win->present does not always do that
{	my $win=shift;
	unless ($win->window && ($win->window->get_state >= 'sticky')) { $win->stick; $win->unstick; }
	$win->present;
}
sub IncSuffix	# increment a number suffix from a string
{	$_[0] =~ s/(?<=\D)(\d*)$/sprintf "%0".length($1)."d",($1||1)+1/e;
}
my $thousandsep= POSIX::localeconv()->{thousands_sep};
sub format_integer
{	my $n=shift;
	$n =~ s/(?<=\d)(?=(?:\d\d\d)+\b)/$thousandsep/g;
	$n;
}
sub Ellipsize
{	my ($string,$max)=@_;
	return length $string>$max+3 ? substr($string,0,$max)."\x{2026}" : $string;
}
sub Clamp
{	$_[0] > $_[2] ? $_[2] : $_[0] < $_[1] ? $_[1] : $_[0];
}

sub CleanupFileName
{	local $_=$_[0];
	s#[[:cntrl:]/:><*?"\\^]##g;
	s#^[- ]+##g;
	$_=substr $_,0,255 if length>255;
	s/[. ]+$//g;
	return $_;
}
sub CleanupDirName
{	local $_=$_[0];
	if ($^O eq 'MSWin32')	{ s#[[:cntrl:]/:><*?"^]##g; }
	else			{ s#[[:cntrl:]:><*?"\\^]##g;}
	s#^[- ]+##g;
	$_=substr $_,0,255 if length>255;
	s/[. ]+$//g;
	return $_;
}

sub uniq
{	my %h;
	map { $h{$_}++ == 0 ? $_ : () } @_;
}

sub superlc	##lowercase, normalize and remove accents/diacritics #not sure how good it is
{	my $s=NFKD($_[0]);
	$s=~s/\pM//og;	#remove Marks (see perlunicode)
	$s=Unicode::Normalize::compose($s); #probably better to recompose #is it worth it ?
	return lc $s;
}
sub superlc_sort
{	return sort {superlc($a) cmp superlc($b)} @_;
}
sub sorted_keys		#return keys of $hash sorted by $hash->{$_}{$sort_subkey} or by $hash->{$_} using superlc
{	my ($hash,$sort_subkey)=@_;
	if (defined $sort_subkey)
	{	return sort { superlc($hash->{$a}{$sort_subkey}) cmp superlc($hash->{$b}{$sort_subkey}) } keys %$hash;
	}
	else
	{	return sort { superlc($hash->{$a}) cmp superlc($hash->{$b}) } keys %$hash;
	}
}

sub WordIn #return true if 1st argument is a word in contained in the 2nd argument (space-separated words)
{	return 1 if first {$_[0] eq $_} split / +/,$_[1];
	return 0;
}

sub OneInCommon	#true if at least one string common to both list
{	my ($l1,$l2)=@_;
	($l1,$l2)=($l2,$l1) if @$l1>@$l2;
	return 0 if @$l1==0;
	if (@$l1==1) { my $s=$l1->[0]; return defined first {$_ eq $s} @$l2 }
	my %h;
	$h{$_}=undef for @$l1;
	return 1 if defined first { exists $h{$_} } @$l2;
	return 0;
}

sub find_common_parent_folder
{	my @folders= uniq(@_);
	my $folder=$folders[0];
	my $nb=@folders;
	return $folder if $nb==1;
	$folder=~s/$QSLASH+$//o;
	until ($nb==grep m/^\Q$folder\E(?:$QSLASH|$)/, @folders)
	{	$folder='' unless $folder=~m/$QSLASH/o;	#for win32 drives
		last unless $folder=~s/$QSLASH[^$QSLASH]+$//o;
	}
	$folder.=SLASH unless $folder=~m/$QSLASH/o;
	return $folder;
}

sub ExtractNameAndOptions
{	local $_=$_[0];		#the passed string is modified unless wantarray
	my $prefixre=$_[1];
	my @res;
	while ($_ ne '')
	{	s#^\s*##;
		my $prefix;
		if ($prefixre)
		{	$prefix=$1 if s/^$prefixre//;
		}
		m/[^(\s]*/g; #name in "name(options...)"
		my $depth=0;
		$depth=1 if m#\G\(#gc;
		while ($depth)
		{	m#\G(?:[^()]*[^()\\])?([()])?#gc;		#search next ()
			last unless $1;			#end of string
#			next if "\\" eq substr($_,pos()-2,1);#escaped () => ignore
			if ($1 eq '(')	{$depth++}
			else		{$depth--}
		}
		my $str=substr $_,0,pos,'';
		$str=~s#\\([()])#$1#g; #unescape ()
		$str=[$str,$prefix] if $prefixre;
		$_[0]=$_ , return $str unless wantarray;
		push @res, $str;
	}
	return @res;
}
sub ParseOptions
{	local $_=$_[0]; #warn "$_\n";
	my %opt;
	while (m#\G\s*([^= ]+)=\s*#gc)
	{	my $key=$1;
		if (m#\G(["'])#gc) #quotted
		{	my $q= $1 ;
			my $v;
			if (m#\G((?:[^$q\\]|\\.)*)$q#gc)
			{	$v=$1;
				$v=~s#\\$q#$q#g;
			}
			else
			{	print "Can't find end of quote in ".(substr $_,pos()-1)."\n";
			}
			$opt{$key}=$v;
			m#\G[^,]*(?:,|$)#gc; #skip the rest
		}
		else
		{	m#\G([^,]*?)\s*(?:,|$)#gc;
			$opt{$key}=$1;
		}
	}
	#warn " $_ => $opt{$_}\n" for sort keys %opt; warn "\n";
	return \%opt;
}

sub ReplaceExpr { my $expr=shift; $expr=~s#\\}#}#g; warn "FIXME : ReplaceExpr($expr)"; return ''; } #FIXME
sub ReplaceExprUsedFields {} #FIXME

our %ReplaceFields; #used in gmusicbrowser_tags for auto-fill FIXME PHASE1
	#o => 'basefilename', maybe should be usage specific (=>only for renaming)

sub UsedFields
{	my $s=$_[0];
	my @f= grep defined, map $ReplaceFields{$_}, $s=~m/(%[a-zA-Z])/g;
	push @f, $s=~m#\$([a-zA-Z]\w*)#g;
	push @f, ReplaceExprUsedFields($_) for $s=~m#\${(.*?(?<!\\))}#g;
	return Songs::Depends(@f);
}
sub ReplaceFields
{	my ($ID,$string,$esc,$special)=@_;
	$special||={};
	my $display= $esc ? ref $esc ? sub { $esc->(Songs::Display(@_)) } : \&Songs::DisplayEsc : \&Songs::Display;
	$string=~s#(?:\\n|<br>)#\n#g;
	$string=~s#([%\$]){2}|(%[a-zA-Z]|\$[a-zA-Z\$]\w*)|\${(.*?(?<!\\))}#
		$1			? $1 :
		defined $3		? ReplaceExpr($3) :
		exists $special->{$2}	? do {my $s=$special->{$2}; ref $s ? $s->($ID,$2) : $s} :
		do {my $f=$ReplaceFields{$2}; $f ? $display->($ID,$f) : $2}
		#ge;
	return $string;
}
sub ReplaceFieldsAndEsc
{	ReplaceFields($_[0],$_[1],1);
}
sub ReplaceFieldsForFilename
{	# use filename_from_unicode for everything but %o (existing filename in unknown encoding), leave %o as is
	my $f= ReplaceFields( $_[0], filename_from_unicode($_[1]), \&Glib::filename_from_unicode, {"%o"=> sub { Songs::Get($_[0],'barefilename') }, } );
	CleanupFileName($f);
}
sub MakeReplaceTable
{	my ($fields,%special)=@_;
	my $table=Gtk2::Table->new (4, 2, FALSE);
	my $row=0; my $col=0;
	for my $letter (split //,$fields)
	{	for my $text ( '%'.$letter, $special{$letter}||Songs::FieldName($ReplaceFields{'%'.$letter}) )
		{	my $l=Gtk2::Label->new($text);
			$table->attach($l,$col++,$col,$row,$row+1,'fill','shrink',4,1);
			$l->set_alignment(0,.5);
		}
		if ($col++>3) { $row++; $col=0; }
	}
	$table->set_col_spacing(2, 30);
	my $align=Gtk2::Alignment->new(.5, .5, 0, 0);
	$align->add($table);
	return $align;
}
sub MakeReplaceText
{	my ($fields,%special)=@_;
	my $text=join "\n", map "%$_ : ". ($special{$_}||Songs::FieldName($ReplaceFields{'%'.$_})), split //,$fields;
	return $text;
}

our %DATEUNITS=
(		s => [1,_"seconds"],
		m => [60,_"minutes"],
		h => [3600,_"hours"],
		d => [86400,_"days"],
		w => [604800,_"weeks"],
		M => [2592000,_"months"],
		y => [31536000,_"years"],
);
our %SIZEUNITS=
(		b => [1,_"bytes"],
		k => [1000,_"KB"],
		m => [1000000,_"MB"],
);

sub strftime_utf8
{	utf8::upgrade($_[0]); &strftime;
}

# english and localized, full and abbreviated, day names
my %DAYS=( map( {	::superlc(strftime_utf8('%a',0,0,0,1,0,100,$_))=>$_,
			::superlc(strftime_utf8('%A',0,0,0,1,0,100,$_))=>$_
		} 0..6), sun=>0,mon=>1,tue=>2,wed=>3,thu=>4,fri=>5,sat=>6);
# english and localized, full and abbreviated, month names
my %MONTHS=( map( {	::superlc(strftime_utf8('%b',0,0,0,1,$_,100))=>$_+1,
			::superlc(strftime_utf8('%B',0,0,0,1,$_,100))=>$_+1
		  } 0..11), jan=>1,feb=>2,mar=>3,apr=>4,may=>5,jun=>6,jul=>7,aug=>8,sep=>9,oct=>10,nov=>11,dec=>12);
for my $h (\%DAYS,\%MONTHS)	#remove "." at the end of some localized day/month names
{	for my $key (keys %$h) { $h->{$key}= delete $h->{"$key."} if $key=~s/\.$//; }
}
sub dates_to_timestamps
{	my ($dates,$mode)=@_;	#mode : 0: begin date, 1: end date, 2: range
	if ($mode==2 && $dates!~m/\.\./ && $dates=~m/^[^-]*-[^-]*$/) { $dates=~s/-/../; } # no '..' and only one '-' => replace '-' by '..'
	my ($date1,$range,$date2)=split /(\s*\.\.\s*)/,$dates,2;
	if    ($mode==0) { $date2=0; }
	elsif ($mode==1) { $date2||=$date1; $date1=0; }
	elsif ($mode==2) { $date2=$date1 unless $range; }
	my $end=0;
	for my $date ($date1,$date2)
	{	if (!$date) {$date='';next}
		elsif ($date=~m/^\d{9,}$/) {next} #seconds since epoch
		my $past_step=1;
		my $past_var;
		my ($y,$M,$d,$h,$m,$s,$pm);
		{	($y,$M,$d,$h,$m,$s)= $date=~m#^(\d\d\d\d)(?:[-/.](\d\d?)(?:[-/.](\d\d?)(?:[-T ](\d\d?)(?:[:.](\d\d?)(?:[:.](\d\d?))?)?)?)?)?$# and last; # yyyy/MM/dd hh:mm:ss
			($h,$m,$s,$pm)=	$date=~m#^(\d\d?)[:](?:(\d\d?)(?:[:](\d\d?))?)?([ap]m?)?$#i and last; #hh:mm:ss or hh:mm or hh:
			($d,$M,$y)=	$date=~m#^(\d\d?)(?:[-/.](\d\d?)(?:[-/.](\d\d\d\d))?)?$# and last; # dd/MM or dd/MM/yyyy
			($M,$y)=	$date=~m#^(\d\d?)[-/.](\d\d\d\d)$# and last; # MM/yyyy
			($y,$M,$d)=	$date=~m#^(\d{4})(\d\d)(\d\d)$# and last; # yyyyMMdd
			if ($date=~m#^(?:(\d\d?)[-/. ]?)?(\p{Alpha}+)(?:[-/. ]?(\d\d(?:\d\d)?))?$# && (my $month=$MONTHS{::superlc($2)})) # jan or jan99 or 10jan or 10jan12 or jan2012
			{	($d,$M,$y)=($1,$month,$3);
				last;
			}
			if (defined(my $wday=$DAYS{::superlc$date})) #name of week day
			{	my ($now_day,$now_wday)= (localtime)[3,6];
				$d= $now_day - $now_wday + $wday;
				$past_step=7; $past_var=3; #remove 7days if in future
				last;
			}
			$date='';
		}
		next unless $date;
		if (defined $y)
		{	$y= $y>100 ? $y-=1900 : $y<70 ? $y+100 : $y;	#>100 => 4digits year, <70 : 2digits 20xx year, else 2digits 19xx year
		}
		$M-- if defined $M;
		$h+=( $pm=~m/^pm?$/ ? $h!=12 ? 12 : 0 : $h==12 ? -12 : 0 ) if defined $pm && defined $h;
		my @now= (localtime)[0..5];
		for ($y,$M,$d,$h,$m,$s)	#complete relative dates with current date
		{	last if defined;
			$_= pop @now;
		}
		$past_var= scalar @now unless defined $past_var; #unit to change if in the future
		if ($end)	#if end date increment the smallest defined unit (to get the end of day/month/year/hour/min + 1 sec)
		{	for ($s,$m,$h,$d,$M,$y)
			{	if (defined) { $_++; last; }
			}
		}
		my @date= ($s||0,$m||0,$h||0,$d||1,$M||0,$y);
		$date= ::mktime(@date);
		if ($past_var<6 && $date>time) #for relative dates, choose between previous and next match (for example, this year's july or previous year's july)
		{	$date[$past_var]-= $past_step;
			my $date_past= ::mktime(@date);
			#use date in the past unless it's an end date and makes more sense relative to the first date
			$date= $date_past unless $end && $date1 && $date>$date1 && $date_past<=$date1;
		}
		$date-- if $end;
	}
	continue {$end=1}
	return $mode==0 ? $date1 : $mode==1 ? $date2 : ($date1,$date2);
}

sub ConvertTime	# convert date pattern into nb of seconds
{	my ($date,$unit)= $_[0]=~m/^\s*(\d*\.?\d+)\s*([a-zA-Z]*)\s*$/;
	return 0 unless $date;
	if (my $ref= $DATEUNITS{$unit}) { $date*= $ref->[0] }
	elsif ($unit) { warn "ignoring unknown unit '$unit'\n" }
	return time-$date;
}
sub ConvertSize
{	my ($size,$unit)= $_[0]=~m/^\s*(\d*\.?\d+)\s*([a-zA-Z]*)\s*$/;
	return 0 unless $size;
	if (my $ref= $SIZEUNITS{lc$unit}) { $size*= $ref->[0] }
	elsif ($unit) { warn "ignoring unknown unit '$unit'\n" }
	return $size;
}

#---------------------------------------------------------------
our $DAYNB=int(time/86400)-12417;#number of days since 01 jan 2004

our ($Library,$PlaySource);#,@Radio);
our (%GlobalBoundKeys,%CustomBoundKeys);

our ($SelectedFilter,$PlayFilter); our (%Filters,%FilterWatchers,%Related_FilterWatchers); our %SelID;
#our %SavedFilters;our (%SavedSorts,%SavedWRandoms);our %SavedLists;
my $SavedListsWatcher;
our $ListPlay;
our ($TogPlay,$TogLock);
our ($RandomMode,$SortFields,$ListMode);
our ($SongID,$prevID,$Recent,$RecentPos,$Queue); our $QueueAction=our $NextAction='';
our ($Position,$ChangedID,$ChangedPos,@NextSongs,$NextFileToPlay);
our ($MainWindow,$FullscreenWindow); my $OptionsDialog;
my $TrayIcon;
my %Editing; #used to keep track of opened song properties dialog and lyrics dialog
our $PlayTime;
our ($StartTime,$StartedAt,$PlayingID, @Played_segments);
our $CurrentDir=$ENV{PWD};
$ENV{'PULSE_PROP_media.role'}='music';				# role hint for pulseaudio
$ENV{'PULSE_PROP_application.icon_name'}='gmusicbrowser';	# icon hint for pulseaudio, could also use Gtk2::Window->set_default_icon_name

our (%ToDo,%TimeOut);
my %EventWatchers;#for Save Vol Time Queue Lock Repeat Sort Filter Pos CurSong Playing SavedWRandoms SavedSorts SavedFilters SavedLists Icons Widgets connections
# also used for SearchText_ SelectedID_ followed by group id
# Picture_#mainfield#

my (%Watched,%WatchedFilt);
my ($IdleLoop,@ToAdd_Files,@ToAdd_IDsBuffer,@ToScan,%FollowedDirs,%AutoPicChooser);
our %Progress; my $ProgressWindowComing;
my $ToCheck=GMB::JobIDQueue->new(title	=> _"Checking songs",);
my $ToReRead=GMB::JobIDQueue->new(title	=> _"Re-reading tags",);
my $ToCheckLength=GMB::JobIDQueue->new(title	=> _"Checking length/bitrate",details	=> _"for files without a VBR header",);
my ($CheckProgress_cb,$ScanProgress_cb,$ProgressNBSongs,$ProgressNBFolders);
my %Plugins;
my $ScanRegex;

my %Encoding_pref;
$Encoding_pref{$_}=-2 for qw/null AdobeZdingbat ascii-ctrl dingbats MacDingbats/; #don't use these
$Encoding_pref{$_}=-1 for qw/UTF-32BE UTF-32LE/; #these can generate lots of warnings, skip them when trying encodings
$Encoding_pref{$_}=2 for qw/utf8 cp1252 iso-8859-15/; #use these first when trying encodings

#Default values
our %Options=
(	Layout		=> 'Lists, Library & Context',
	LayoutT		=> 'full with buttons',
	LayoutB		=> 'Browser',
	LayoutF		=> 'default fullscreen',
	LayoutS		=> 'Search',
	IconTheme	=> '',
	MaxAutoFill	=> 5,
	Repeat		=> 1,
	Sort		=> 'shuffle',		#default sort order
	Sort_LastOrdered=> 'path file',
	Sort_LastSR	=> 'shuffle',
	Sessions	=> '',
	StartCheck	=> 0,	#check if songs have changed on startup
	StartScan	=> 0,	#scan @LibraryPath on startup for new songs
	Labels		=> [_("favorite"),_("bootleg"),_("broken"),_("bonus tracks"),_("interview"),_("another example")],
	FilenameSchema	=> ['%a - %l - %n - %t','%l - %n - %t','%n-%t','%d%n-%t'],
	FolderSchema	=> ['%A/%l','%A','%A/%Y-%l','%A - %l'],
	PlayedMinPercent=> 80,	# Threshold to count a song as played in percent
	PlayedMinSeconds=> 600,	# Threshold to count a song as played in seconds
	DefaultRating	=> 50,
#	Device		=> 'default',
#	amixerSMC	=> 'PCM',
#	gst_sink	=> 'alsa',
	gst_use_equalizer=>0,
	gst_equalizer	=> '0:0:0:0:0:0:0:0:0:0',
	gst_equalizer_preamp => 1,
	gst_use_replaygain=>1,
	gst_rg_limiter	=> 1,
	gst_rg_preamp	=> 0,
	gst_rg_fallback	=> 0,
	gst_rg_songmenu => 0,
	Icecast_port	=> '8000',
	UseTray		=> 1,
	CloseToTray	=> 0,
	ShowTipOnSongChange	=> 0,
	TrayTipTimeLength	=> 3000, #in ms
	TAG_use_latin1_if_possible => 1,
	TAG_no_desync		=> 1,
	TAG_keep_id3v2_ver	=> 0,
	'TAG_write_id3v2.4'	=> 0,
	TAG_id3v1_encoding	=> 'iso-8859-1',
	AutoRemoveCurrentSong	=> 0,
	LengthCheckMode		=> 'add',
	CustomKeyBindings	=> {},
	VolumeStep		=> 10,
	DateFormat_history	=> ['%c 604800 %A %X 86400 Today %X 60 now'],
	AlwaysInPlaylist	=> 1,
	PixCacheSize		=> 60,	# in MB

	SavedSTGroupings=>
	{	_"None"			=> '',
		_"Artist & album"	=> 'artist|simple|album|pic',
		_"Album with picture"	=> 'album|pic',
		_"Album"		=> 'album|simple',
		_"Folder"		=> 'folder|artistalbum',
	},
	SavedWRandoms=>
	{	_"by rating"	=> 'random:1r0,.1,.2,.3,.4,.5,.6,.7,.8,.9,1',
		_"by play count"=> 'random:-1n5',
		_"by lastplay"	=> 'random:1l10',
		_"by added"	=> 'random:-1a50',
		_"by lastplay & play count"	=> 'random:1l10'."\x1D".'-1n5',
		_"by lastplay & bootleg"	=> 'random:1l10'."\x1D".'-.5fbootleg',
	},
	SavedSorts=>
	{	  _"Path,File"	=> 'path file',
		_"Date"		=> 'year',
		_"Title"	=> 'title',
		_"Last played"	=> 'lastplay',
		_"Artist,Album,Disc,Track"	=> 'artist album disc track',
		_"Artist,Date,Album,Disc,Track"	=> 'artist year album disc track',
		_"Path,Album,Disc,Track,File"	=> 'path album disc track file',
		_"Shuffled albums"		=> 'album_shuffle disc track file',
		_"Shuffled albums, shuffled tracks"		=> 'album_shuffle shuffle',
	},
);

our $GlobalKeyBindings='Insert OpenSearch c-q Quit a-q EnqueueSelected p PlayPause c OpenContext q OpenQueue ca-f ToggleFullscreenLayout F11 ToggleFullscreen';
%GlobalBoundKeys=%{ make_keybindingshash($GlobalKeyBindings) };


sub make_keybindingshash
{	my $keybindings=$_[0];
	my @list= ref $keybindings ? %$keybindings : ExtractNameAndOptions($keybindings);
	my %h;
	while (@list>1)
	{	my $key=shift @list;
		my $cmd=shift @list;
		my $mod='';
		$mod=$1 if $key=~s/^([caws]+-)//;
		my @keys=($key);
		@keys=(lc$key,uc$key) if $key=~m/^[A-Za-z]$/;
		$h{$mod.$_}=$cmd for @keys;
	}
	return \%h;
}
sub keybinding_longname
{	my $key=$_[0];
	return $key unless $key=~s/^([caws]+)-//;
	my $mod=$1;
	my %h=(	c => _p('Keyboard',"Ctrl"),	#TRANSLATION: Ctrl key
		a => _p('Keyboard',"Alt"),	#TRANSLATION: Alt key
		w => _p('Keyboard',"Win"),	#TRANSLATION: Windows key
		s => _p('Keyboard',"Shift"),	#TRANSLATION: Shift key
	);
	my $name=join '',map $h{$_}, split //,$mod;
	return $name.'-'.$key;
}

our ($NBVolIcons,$NBQueueIcons); our %TrayIcon;
my $icon_factory;

my %IconsFallbacks=
(	'gmb-queue0'	   => 'gmb-queue',
	'gmb-queue-window' => 'gmb-queue',
	'gmb-random-album' => 'gmb-random',
	'gmb-view-fullscreen'=>'gtk-fullscreen',
);

sub LoadIcons
{	my %icons;
	unless (Gtk2::Stock->lookup('gtk-fullscreen'))	#for gtk version 2.6
	{ $icons{'gtk-fullscreen'}=PIXPATH.'fullscreen.png';
	}

	#load default icons
	opendir my$dh,PIXPATH;
	for my $file (grep m/^(?:gmb|plugin)-.*\.(?:png|svg)$/ && -f PIXPATH.$_, readdir $dh)
	{	my $name=$file;
		$name=~s/\.[^.]+$//;
		$icons{$name}=PIXPATH.$file;
	}
	closedir $dh;

	#load plugins icons
	if (-d (my $dir=$HomeDir.'plugins'))
	{	opendir my($dh),$dir;
		for my $file (grep m/\.(?:png|svg)$/ && -f $dir.SLASH.$_, readdir $dh)
		{	my $name='plugin-'.$file;
			$name=~s/\.[^.]+$//;
			$icons{$name}= $dir.SLASH.$file;
		}
		closedir $dh;
	}

	my @dirs=($HomeDir.'icons');
	if (my $theme=$Options{IconTheme})
	{	my $dir= $HomeDir.'icons'.SLASH.$theme;
		$dir=PIXPATH.$theme unless -d $dir;
		unshift @dirs,$dir;
	}
	#load theme icons and customs icons
	for my $dir (@dirs)
	{	next unless -d $dir;
		opendir my($dh),$dir;
		for my $file (grep m/\.(?:png|svg)$/ && -f $dir.SLASH.$_, readdir $dh)
		{	my $name=$file;
			$name=~s/\.[^.]+$//;
			$name=Encode::decode('utf8',::decode_url($name));
			$icons{$name}= $dir.SLASH.$file;
		}
		closedir $dh;
	}

	eval { Gtk2::Window->set_default_icon_from_file( delete $icons{gmusicbrowser} || PIXPATH.'gmusicbrowser.png' ); };
	warn $@ if $@;

	#trayicons
	{	%TrayIcon=();
		my $prefix= $TrayIcon{'default'}= $icons{trayicon} || PIXPATH.'trayicon.png';
		$prefix=~s/\.[^.]+$//;
		for my $key (qw/play pause/)
		{	($TrayIcon{$key})= grep -r $_, map "$prefix-$key.$_",qw/png svg/;
		}
		UpdateTrayIcon(1);
	}

	$NBVolIcons=0;
	$NBVolIcons++ while $icons{'gmb-vol'.$NBVolIcons};
	$NBQueueIcons=0;
	$NBQueueIcons++ while $icons{'gmb-queue'.($NBQueueIcons+1)};

	# find rating pictures
	for my $field (keys %Songs::Def)
	{	my $format= $Songs::Def{$field}{starprefix};
		next unless $format;
		if ($format!~m#^/#)
		{	for my $path (reverse PIXPATH,@dirs)
			{	next unless -f $path.SLASH.$format.'0.svg' || -f $path.SLASH.$format.'0.png';
				$format= $path.SLASH.$format;
				last;
			}
		}
		$format.= (-f $format.'0.svg') ? "%d.svg" : "%d.png";
		my $max=0;
		$max++ while -f sprintf($format,$max+1);
		$Songs::Def{$field}{pixbuf}= [ map eval {Gtk2::Gdk::Pixbuf->new_from_file( sprintf($format,$_) )}, 0..$max ];
		$Songs::Def{$field}{nbpictures}= $max;
	}

	$icon_factory->remove_default if $icon_factory;
	$icon_factory=Gtk2::IconFactory->new;
	$icon_factory->add_default;
	for my $stock_id (keys %icons,keys %IconsFallbacks)
	{	next if $stock_id=~m/^trayicon/;
		my %h= ( stock_id => $stock_id );
			#label    => $$ref[1],
			#modifier => [],
			#keyval   => $Gtk2::Gdk::Keysyms{L},
			#translation_domain => 'gtk2-perl-example',
		if (exists $StockLabel{$stock_id}) { $h{label}=$StockLabel{$stock_id}; }
		Gtk2::Stock->add(\%h) unless Gtk2::Stock->lookup($stock_id);

		my $icon_set;
		if (my $file=$icons{$stock_id})
		{	$icon_set= eval {Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file($file) )};
			warn $@ if $@;
		}
		elsif (my $fallback=$IconsFallbacks{$stock_id})
		{	$icon_set= $icon_factory->lookup($fallback) || Gtk2::IconFactory->lookup_default($fallback);
		}
		next unless $icon_set;
		$icon_factory->add($stock_id,$icon_set);
	}
	$_->queue_draw for Gtk2::Window->list_toplevels;
	HasChanged('Icons');
}
sub GetIconThemesList
{	my %themes;
	$themes{''}=_"default";
	for my $dir (PIXPATH,$HomeDir.'icons'.SLASH)
	{	next unless -d $dir;
		opendir my($dh),$dir;
		$themes{$_}=$_ for grep !m/^\./ && -d $dir.$_, readdir $dh;
		closedir $dh;
	}
	return \%themes;
}

##########

our %Command=		#contains sub,description,argument_tip, argument_regex or code returning a widget, or '0' to hide it from the GUI edit dialog
(	NextSongInPlaylist=> [\&NextSongInPlaylist,		_"Next Song In Playlist"],
	PrevSongInPlaylist=> [\&PrevSongInPlaylist,		_"Previous Song In Playlist"],
	NextAlbum	=> [sub {NextDiff('album')},		_"Next Album",],
	NextArtist	=> [sub {NextDiff('first_artist')},	_"Next Artist",],
	NextSong	=> [\&NextSong,				_"Next Song"],
	PrevSong	=> [\&PrevSong,				_"Previous Song"],
	PlayPause	=> [\&PlayPause,			_"Play/Pause"],
	Forward		=> [\&Forward,				_"Forward",_"Number of seconds",qr/^\d+$/],
	Rewind		=> [\&Rewind,				_"Rewind",_"Number of seconds",qr/^\d+$/],
	Seek		=> [sub {SkipTo($_[1])},		_"Seek",_"Number of seconds",qr/^\d+$/],
	Stop		=> [\&Stop,				_"Stop"],
	Pause		=> [sub {Pause() if $TogPlay; },	_"Pause"],
	Play		=> [sub {PlayPause() unless $TogPlay; },_"Play"],
	Browser		=> [\&OpenBrowser,			_"Open Browser"],
	OpenQueue	=> [\&EditQueue,			_"Open Queue window"],
	OpenSearch	=> [sub { Layout::Window->new($Options{LayoutS}, uniqueid=>'Search'); },	_"Open Search window"],
	OpenContext	=> [\&ContextWindow,			_"Open Context window"],
	OpenCustom	=> [sub { Layout::Window->new($_[1]); },	_"Open Custom window",_"Name of layout", sub { TextCombo::Tree->new( Layout::get_layout_list() ); }],
	PopupCustom	=> [sub { PopupLayout($_[1],$_[0]); },		_"Popup Custom window",_"Name of layout", sub { TextCombo::Tree->new( Layout::get_layout_list() ); }],
	CloseWindow	=> [sub { $_[0]->get_toplevel->close_window if $_[0];}, _"Close Window"],
	SetPlayerLayout => [sub { SetOption(Layout=>$_[1]); CreateMainWindow(); },_"Set player window layout",_"Name of layout", sub {  TextCombo::Tree->new( Layout::get_layout_list('G') ); }, ],
	OpenPref	=> [sub{ PrefDialog($_[1]); },		_"Open Preference window"],
	OpenSongProp	=> [sub { DialogSongProp($SongID) if defined $SongID }, _"Edit Current Song Properties"],
	EditSelectedSongsProperties => [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DialogSongsProp(@IDs) if @IDs; },		_"Edit selected song properties"],
	ShowHide	=> [sub {ShowHide();},			_"Show/Hide"],
	Show		=> [sub {ShowHide(1);},			_"Show"],
	Hide		=> [sub {ShowHide(0);},			_"Hide"],
	Quit		=> [\&Quit,				_"Quit"],
	Save		=> [sub {SaveTags(1)},			_"Save Tags/Options"],
	ChangeDisplay	=> [\&ChangeDisplay,			_"Change Display",_"Display (:1 or host:0 for example)",qr/:\d/],
	GoToCurrentSong => [\&Layout::GoToCurrentSong,		_"Select current song"],
	DeleteSelected	=> [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DeleteFiles(\@IDs); },		_"Delete Selected Songs"],
	QueueInsertSelected=>[sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; QueueInsert(@IDs); },		_"Insert Selected Songs at the top of the queue"],
	EnqueueSelected => [\&Layout::EnqueueSelected,		_"Enqueue Selected Songs"],
	EnqueueArtist	=> [sub {EnqueueSame('artist',$SongID)},_"Enqueue Songs from Current Artist"], # or use field 'artists' or 'first_artist' ?
	EnqueueAlbum	=> [sub {EnqueueSame('album',$SongID)},	_"Enqueue Songs from Current Album"],
	EnqueueAction	=> [sub {EnqueueAction($_[1])},		_"Enqueue Action", _"Queue mode" ,sub { TextCombo->new({map {$_ => $QActions{$_}{short}} sort keys %QActions}) }],
	SetNextAction	=> [sub {SetNextAction($_[1])},		_"Set action when song ends", _"Action" ,sub { TextCombo->new({map {$_ => $QActions{$_}{short}} sort grep $QActions{$_}{can_next}, keys %QActions}) }],
	ClearQueue	=> [\&::ClearQueue,			_"Clear queue"],
	ClearPlaylist	=> [sub {Select(staticlist=>[])},	_"Clear playlist"],
	IncVolume	=> [sub {ChangeVol('up')},		_"Increase Volume"],
	DecVolume	=> [sub {ChangeVol('down')},		_"Decrease Volume"],
	TogMute		=> [sub {ChangeVol('mute')},		_"Mute/Unmute"],
	RunSysCmd	=> [sub {call_run_system_cmd($_[0],$_[1],0,0)},
		_"Run system command",_("System command")."\n"._("Some variables such as %f (current song filename) are available"),qr/./],
	RunShellCmd	=> [sub {call_run_system_cmd($_[0],$_[1],0,1)},
		_"Run shell command",_("Shell command")."\n"._("Some variables such as %f (current song filename) are available"),qr/./],
	RunSysCmdOnSelected	=> [sub {call_run_system_cmd($_[0],$_[1],1,0)},
		_"Run system command on selected songs",_("System command")."\n"._("Some variables such as %f (current song filename) are available")."\n"._('One command is used per selected songs, unless $files is used, which is replaced by the list of selected files'),qr/./],
	RunShellCmdOnSelected	=> [sub {call_run_system_cmd($_[0],$_[1],1,1)},
		_"Run shell command on selected songs",_("Shell command")."\n"._("Some variables such as %f (current song filename) are available")."\n"._('One command is used per selected songs, unless $files is used, which is replaced by the list of selected files'),qr/./],
	RunPerlCode	=> [sub {eval $_[1]},			_"Run perl code",_"perl code",qr/./],
	TogArtistLock	=> [sub {ToggleLock('first_artist')},	_"Toggle Artist Lock"],
	TogAlbumLock	=> [sub {ToggleLock('album')},		_"Toggle Album Lock"],
	TogSongLock	=> [sub {ToggleLock('fullfilename')},	_"Toggle Song Lock"],
	ToggleRandom	=> [\&ToggleSort, _"Toggle between Random/Shuffle and Ordered"],
	SetSongRating	=> [sub
	{	return unless defined $SongID && $_[1]=~m/^([-+])?(\d*)$/;
		my $r=$2;
		if ($1)
		{	my $step= $r||10;
			$step*=-1 if $1 eq '-';
			$r= Songs::Get($SongID, 'ratingnumber') + $step;
		}
		Songs::Set($SongID, rating=> $r);
	},	_"Set Current Song Rating", _("Rating between 0 and 100, or empty for default")."\n"._("Can be relative by using + or -"), qr/^[-+]?\d*$/],
	ToggleFullscreen=> [\&Layout::ToggleFullscreen,		_"Toggle fullscreen mode"],
	ToggleFullscreenLayout=> [\&ToggleFullscreenLayout, _"Toggle the fullscreen layout"],
	OpenFiles	=> [\&OpenFiles, _"Play a list of files", _"url-encoded list of files",0],
	AddFilesToPlaylist=> [sub { DoActionForList('addplay',Uris_to_IDs($_[1])); }, _"Add a list of files/folders to the playlist", _"url-encoded list of files/folders",0],
	InsertFilesInPlaylist=> [sub { DoActionForList('insertplay',Uris_to_IDs($_[1])); }, _"Insert a list of files/folders at the start of the playlist", _"url-encoded list of files/folders",0],
	EnqueueFiles	=> [sub { DoActionForList('queue',Uris_to_IDs($_[1])); }, _"Enqueue a list of files/folders", _"url-encoded list of files/folders",0],
	AddToLibrary	=> [sub { AddPath(1,split / /,$_[1]); }, _"Add files/folders to library", _"url-encoded list of files/folders",0],
	SetFocusOn	=> [sub { my ($w,$name)=@_;return unless $w; $w=get_layout_widget($w);$w->SetFocusOn($name) if $w;},_"Set focus on a layout widget", _"Widget name",0],
	ShowHideWidget	=> [sub { my ($w,$name)=@_;return unless $w; $w=get_layout_widget($w);$w->ShowHide(split / +/,$name,2) if $w;},_"Show/Hide layout widget(s)", _"|-separated list of widget names",0],
	PopupTrayTip	=> [sub {ShowTraytip($_[1])}, _"Popup Traytip",_"Number of milliseconds",qr/^\d*$/ ],
	SetSongLabel	=> [sub{ Songs::Set($SongID,'+label' => $_[1]); }, _"Add a label to the current song", _"Label",qr/./],
	UnsetSongLabel	=> [sub{ Songs::Set($SongID,'-label' => $_[1]); }, _"Remove a label from the current song", _"Label",qr/./],
	ToggleSongLabel	=> [sub{ Songs::Set($SongID,'^label' => $_[1]); }, _"Toggle a label of the current song", _"Label",qr/./],
	PlayListed	=> [sub{ my $songlist=GetSonglist($_[0]) or return; Select(song => 'first', play => 1, staticlist => $songlist->{array} ); }, _"Play listed songs"],
	ClearPlayFilter	=> [sub {Select(filter => '') if defined $ListMode || !$SelectedFilter->is_empty;}, _"Clear playlist filter"],
	MenuPlayFilter	=> [sub { Layout::FilterMenu(); }, _"Popup playlist filter menu"],
	MenuPlayOrder	=> [sub { Layout::SortMenu(); },   _"Popup playlist order menu"],
	MenuQueue	=> [sub { PopupContextMenu(\@Layout::MenuQueue,{ID=>$SongID, usemenupos=>1}); }, _"Popup queue menu"],
	ReloadLayouts	=> [ \&Layout::InitLayouts, _"Re-load layouts", ],
	ChooseSongFromAlbum=> [sub {my $ID= $_[0] ? GetSelID($_[0]) : $::SongID; ChooseSongsFromA( Songs::Get_gid($ID,'album'),nocover=>1 ); }, ],
);

sub run_command
{	my ($self,$cmd)=@_; #self must be a widget or undef
	$cmd="$1($2)" if $cmd=~m/^(\w+) (.*)/;
	($cmd, my$arg)= $cmd=~m/^(\w+)(?:\((.*)\))?$/;
	warn "executing $cmd($arg) (with self=$self)" if $::debug;
	if (my $ref=$Command{$cmd})	{ $ref->[0]->($self,$arg); }
	else { warn "Unknown command '$cmd' => can't execute '$cmd($arg)'\n" }
}

sub split_with_quotes
{	local $_=shift;
	s#\\(.)#$1 eq '"' ? "\\34" : $1 eq "'" ? "\\39" : $1 eq ' ' ? "\\32" : "\\92".$1#ge;
	my @w= m/([^"'\s]+|"[^"]+"|'[^']+')/g;
	for (@w) #remove quotes and put back unused backslashes
	{	if    (s/^"//) {s/"$//; s#\\39#\\92'#g; s#\\32#\\92 #g;}
		elsif (s/^'//) {s/'$//; s#\\34#\\92"#g; s#\\32#\\92 #g;}
	}
	s#\\(\d\d)#chr $1#ge for @w;
	return @w;
}

sub call_run_system_cmd
{	my ($widget,$cmd,$use_selected,$use_shell)=@_;
	my @IDs;
	if ($use_selected || $cmd=~s#%F\b#\$files#)
	{	if ($widget and my $songlist=GetSonglist($widget)) { @IDs= $songlist->GetSelectedIDs; }
		unless (@IDs) { warn "Not executing '$cmd' because no song is selected in the current window\n"; return }
	}
	else { @IDs=($SongID) if defined $SongID; }
	run_system_cmd($cmd,\@IDs,$use_shell);
}
sub run_system_cmd
{	my ($cmd,$IDs,$use_shell)=@_;
	return unless $cmd=~m/\S/; #check if command is empty
	$cmd=Encode::encode("utf8", $cmd);
	my $join=' ';
	if (!$use_shell) { $join="\x00"; $cmd= join $join,split_with_quotes($cmd); }
	my $quotesub= sub { my $s=$_[0]; if (utf8::is_utf8($s)) { $s=Encode::encode("utf8",$s); } $use_shell ? quotemeta($s) : $s; };
	my (@cmds,$files);
	if ($cmd=~m/\$files\b/) { $files= join $join,map $quotesub->(Songs::GetFullFilename($_)),@$IDs; }
	if (@$IDs>1 && !$files) { @cmds= map ReplaceFields($_,$cmd,$quotesub), @$IDs; }
	else { @cmds=( ReplaceFields($IDs->[0],$cmd,$quotesub, {'$files'=>$files}) ); }
	if ($use_shell) { my $shell= $ENV{SHELL} || 'sh'; @cmds= map [$shell,'-c',$_], @cmds; }
	else { @cmds= map [split /\x00/,$_], @cmds; }
	forksystem(@cmds);
}

sub forksystem
{	use POSIX ':sys_wait_h';	#for WNOHANG in waitpid
	my @cmd=@_; #can be (cmd,arg1,arg2,...) or ([cmd1,arg1,arg2,...],[cmd2,$arg1,arg2,...])
	if (ref $cmd[0] && @cmd==1) { @cmd=@{$cmd[0]}; } #simplify if only 1 command
	my $ChildPID=fork;
	if (!defined $ChildPID) { warn ::ErrorMessage("forksystem : fork failed : $!"); }
	if ($ChildPID==0) #child
	{	if (ref $cmd[0])
		{	system @$_ for @cmd;	#execute multiple commands, one at a time, from the child process
		}
		else { exec @cmd; }	#execute one command in the child process
		POSIX::_exit(0);
	}
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
}


if ($CmdLine{cmdlist})
{	print "Available commands (for fifo or layouts) :\n";
	my ($max)= sort {$b<=>$a} map length, keys %Command;
	for my $cmd (sort keys %Command)
	{	my $short= $Command{$cmd}[1];
		next unless defined $short;
		my $tip= $Command{$cmd}[2] || '';
		if ($tip) { $tip=~s/\n.*//s; $tip=" (argument : $tip)"; }
		printf "%-${max}s : %s %s\n", $cmd, $short, $tip;
	}
	exit;
}
my $fifofh;
if ($FIFOFile)
{	if (-e $FIFOFile) { unlink $FIFOFile unless -p $FIFOFile; }
	else
	{	#system('mknod',$FIFOFile,'p'); #can't use mknod to create fifo on freeBSD
		system 'mkfifo',$FIFOFile;
	}
	if (-p $FIFOFile)
	{	sysopen $fifofh,$FIFOFile, O_NONBLOCK;
		#sysopen $fifofh,$FIFOFile, O_NONBLOCK | O_RDWR;
		Glib::IO->add_watch(fileno($fifofh),['in','hup'], \&CmdFromFIFO);
	}
}

Glib::set_application_name(PROGRAM_NAME);
Gtk2::AboutDialog->set_url_hook(sub {openurl($_[1])});

Edittag_mode(@ARGV) if $CmdLine{tagedit};

#make this a plugin ? don't know if it's possible, it may need to run early
my $gnomeclient;
if ($CmdLine{UseGnomeSession})
{ eval		# use the gnome libraries, if present, to enable some session management
  {	require Gnome2;
	#my $application=Gnome2::Program->init(PROGRAM_NAME, VERSION, 'libgnomeui');
	my $application=Gnome2::Program->init(PROGRAM_NAME, VERSION);
	$gnomeclient=Gnome2::Client->master();
	$gnomeclient->signal_connect('die' => sub { Gtk2->main_quit; });
	$gnomeclient->signal_connect(save_yourself => sub { SaveTags(); return 1 });
	#$gnomeclient->set_restart_command($0,'-C',$SaveFile); #FIXME
	#$gnomeclient->set_restart_style('if-running');
  };
  if ($@) {warn "Error loading Gnome2.pm => can't use gnome-session :\n $@\n"}
}

#-------------INIT-------------

{	Watch(undef, SongArray	=> \&SongArray_changed);
	Watch(undef, $_	=> \&QueueChanged) for qw/QueueAction Queue/;
	Watch(undef, $_	=> \&QueueUpdateNextSongs) for qw/Playlist Queue Sort Pos QueueAction/;
	Watch(undef, $_ => sub { return unless defined $SongID && $TogPlay; HasChanged('PlayingSong'); }) for qw/CurSongID Playing/;
	Watch(undef,RecentSongs	=> sub { UpdateRelatedFilter('Recent'); });
	Watch(undef,NextSongs	=> sub { UpdateRelatedFilter('Next'); });
	Watch(undef,CurSong	=> sub { UpdateRelatedFilter('Play'); });
}
our ($Play_package,%PlayPacks); my ($PlayNext_package,$Vol_package);
for my $file (qw/gmusicbrowser_123.pm gmusicbrowser_mplayer.pm gmusicbrowser_gstreamer-0.10.pm gmusicbrowser_server.pm/)
{	eval { require $file } || warn $@;	#each file sets $::PlayPacks{PACKAGENAME} to 1 for each of its included playback packages
}

LoadPlugins();
if ($CmdLine{pluginlist}) { warn "$_ : $Plugins{$_}{name}\n" for sort keys %Plugins; exit; }
$SIG{HUP} = 'IGNORE';
ReadSavedTags();
$Options{AutoRemoveCurrentSong}=0 if $CmdLine{demo};

# global Volume and Mute are used only for gstreamer and mplayer in SoftVolume mode
our $Volume= $Options{Volume};
$Volume=100 unless defined $Volume;
our $Mute= $Options{Volume_mute} || 0;

$PlayPacks{$_}= $_->init for keys %PlayPacks;

%CustomBoundKeys= %{ make_keybindingshash($Options{CustomKeyBindings}) };

$Options{version}=VERSION;
LoadIcons();

{	my $pp=$Options{AudioOut};
	$pp= $Options{use_GST_for_server} ? 'Play_GST_server' : 'Play_Server' if $CmdLine{server};
	$pp='Play_GST' if $CmdLine{gst};
	for my $p ($pp, qw/Play_GST Play_123 Play_mplayer Play_GST_server Play_Server/)
	{	next unless $p && $PlayPacks{$p};
		$pp=$p;
		last;
	}
	$Options{AudioOut}||=$pp;
	$PlayNext_package=$PlayPacks{$pp};
	SwitchPlayPackage();
}

IdleCheck() if $Options{StartCheck} && !$CmdLine{nocheck};
IdleScan()  if $Options{StartScan}  && !$CmdLine{noscan};
$Options{Icecast_port}=$CmdLine{port} if $CmdLine{port};

#$ListMode=[] if $CmdLine{empty};

$ListPlay=SongArray::PlayList->init;
Play() if $CmdLine{play} && !$PlayTime;

#SkipTo($PlayTime) if $PlayTime; #gstreamer (how I use it) needs the mainloop running to skip, so this is done after the main window is created

Layout::InitLayouts;
ActivatePlugin($_,'startup') for grep $Options{'PLUGIN_'.$_}, sort keys %Plugins;
Update_QueueActionList();
QueueChanged() if $QueueAction;

CreateMainWindow( $CmdLine{layout}||$Options{Layout} );
ShowHide(0) if $CmdLine{hide} || ($Options{StartInTray} && $Options{UseTray} && $TrayIconAvailable);
SkipTo($PlayTime) if $PlayTime; #done only now because of gstreamer

CreateTrayIcon();

if (my $cmds=delete $CmdLine{runcmd}) { run_command(undef,$_) for @$cmds; }
$SIG{TERM} = \&Quit;

#--------------------------------------------------------------
Gtk2->main;
exit;

sub Edittag_mode
{	my @dirs=@_;
	$Songs::Def{$_}{flags}=~m/w/ || $Songs::Def{$_}{flags}=~s/e// for keys %Songs::Def; #quick hack to remove fields that are not written in the tag from the mass-tagging dialog
	FirstTime(); Post_ReadSavedTags();
	LoadIcons(); #for stars edit widget that shouldn't be shown anyway
	$Options{LengthCheckMode}='never';
	$_=rel2abs($_) for @dirs;
	IdleScan(@dirs);
	Gtk2->main_iteration while Gtk2->events_pending;

	my $dialog = Gtk2::Dialog->new( _"Editing tags", undef,'modal',
				'gtk-save' => 'ok',
				'gtk-cancel' => 'none');
	$dialog->signal_connect(destroy => sub {exit});
	$dialog->set_default_size(500, 600);
	my $edittag;
	if (@$Library==1)
	{	$edittag=EditTagSimple->new($dialog,$Library->[0]);
		$dialog->signal_connect( response => sub
		 {	my ($dialog,$response)=@_;
			$edittag->save if $response eq 'ok';
			exit;
		 });
	}
	elsif (@$Library>1)
	{	$edittag=MassTag->new(@$Library);
		$dialog->signal_connect( response => sub
		 {	my ($dialog,$response)=@_;
			if ($response eq 'ok') { $edittag->save( sub {exit} ); }
			else {exit}
		 });
	}
	else {die "No songs found.\n";}
	$dialog->vbox->add($edittag);
	$dialog->show_all;
	Gtk2->main;
}

sub ChangeDisplay
{	my $display=$_[1];
	my $screen=0;
	$screen=$1 if $display=~s/\.(\d+)$//;
	$display=Gtk2::Gdk::Display->open($display);
	return unless $display && $screen < $display->get_n_screens;
	Gtk2::Gdk::DisplayManager->get->set_default_display($display);
	$screen=$display->get_screen($screen);
	for my $win (Gtk2::Window->list_toplevels)
	{	$win->set_screen($screen);
	}
}

sub filename_to_utf8displayname	#replaced by Glib::filename_display_name if available
{	my $utf8name=eval {filename_to_unicode($_[0])};
	if ($@)
	{	$utf8name=$_[0];
		#$utf8name=~s/[\x80-\xff]/?/gs; #doesn't seem to be needed
	}
	return $utf8name;
}

sub get_event_window
{	my $widget=shift;
	$widget||= Gtk2->get_event_widget(Gtk2->get_current_event);
	return find_ancestor($widget,'Gtk2::Window');
}
sub get_layout_widget
{	find_ancestor($_[0],'Layout');
}
sub find_ancestor
{	my ($widget,$class)=@_;
	until ( $widget->isa($class) )
	{	$widget= $widget->isa('Gtk2::Menu')? $widget->get_attach_widget : $widget->parent;
		#warn "Can't find ancestor $class of widget $_[0]\n" unless $widget;
		return undef unless $widget;
	}
	return $widget;
}

sub HVpack
{	my ($vertical,@list)=@_;
	my $pad=2;
	my $end=FALSE;
	my $box= $vertical ? Gtk2::VBox->new : Gtk2::HBox->new;
	while (@list)
	{	my $w=shift @list;
		next unless defined $w;
		my $exp=FALSE;
		unless (ref $w)
		{	if ($w eq 'compact') { $pad=0; $box->set_spacing(0); next }
			$exp=$w=~m/_/;
			$end=1 if $w=~m/-/;
			$pad=$1 if $w=~m/(\d+)/;
			$w=shift @list;
			next unless $w;
		}
		if (ref $w eq 'ARRAY')
		{	$w=HVpack(!$vertical,@$w);
		}
		if ($end)	{$box->pack_end  ($w,$exp,$exp,$pad);}
		else		{$box->pack_start($w,$exp,$exp,$pad);}
	}
	return $box;
}

sub Hpack { HVpack(0,@_); }
sub Vpack { HVpack(1,@_); }

sub new_scrolledwindow
{	my ($widget,$shadow)=@_;
	my $sw= Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in') if $shadow;
	$sw->set_policy('automatic','automatic');
	$sw->add($widget);
	return $sw;
}

sub IsEventInNotebookTabs
{	my ($nb,$event)=@_;
	my (@rects)= map $_->allocation, grep $_->mapped, map $nb->get_tab_label($_), $nb->get_children;
	my ($bw,$bh)=$nb->get('tab-hborder','tab-vborder');
	my $x1=min(map $_->x,@rects)-$bw;
	my $y1=min(map $_->y,@rects)-$bh;
	my $x2=max(map $_->x+$_->width,@rects)+$bw;
	my $y2=max(map $_->y+$_->height,@rects)+$bh;
	my ($x,$y)=$event->window->get_position;
	$x+=$event->x;
	$y+=$event->y;
	#warn "$x1,$y1,$x2,$y2  $x,$y";
	return ($x1<$x && $x2>$x && $y1<$y && $y2>$y);
}

sub TurnOff
{	my $dialog=Gtk2::MessageDialog->new
	(	$MainWindow,[qw/modal destroy-with-parent/],
		'warning','none',''
	);
	$dialog->add_buttons('gtk-cancel' => 2, 'gmb-turnoff'=> 1);
	my $sec=21;
	my $timer=sub	#FIXME can be more than 1 second
		{ 	return 0 unless $sec;
			if (--$sec) {$dialog->set_markup(::PangoEsc(_("About to turn off the computer in :")."\n".__("%d second","%d seconds",$sec)))}
			else { $dialog->response(1); }
			return $sec;
		};
	Glib::Timeout->add(1000, $timer);
	&$timer; #init the timer
	$dialog->show_all;
	my $ret=$dialog->run;
	$dialog->destroy;
	$sec=0;
	return if $ret==2;
	Quit('turnoff');
}
sub Quit
{	my $turnoff;
	$turnoff=1 if $_[0] && $_[0] eq 'turnoff';
	$Options{SavedPlayTime}= $PlayTime if $Options{RememberPlayTime};
	&Stop if defined $TogPlay;
	@ToScan=@ToAdd_Files=();
	CloseTrayTip();
	SaveTags();
	HasChanged('Quit');
	unlink $FIFOFile if $FIFOFile;
	Gtk2->main_quit;
	exec $Options{Shutdown_cmd} if $turnoff && $Options{Shutdown_cmd};
	exit;
}

sub CmdFromFIFO
{	while (my $cmd=<$fifofh>)
	{	chomp $cmd;
		next if $cmd eq '';
		$cmd="$1($2)" if $cmd=~m/^(\w+) (.*)/;
		($cmd, my$arg)= $cmd=~m/^(\w+)(?:\((.*)\))?$/;
		#if ($cmd eq 'Print') {print $fifofh "Told to print : $arg\n";return}
		if (exists $Command{$cmd}) { Glib::Timeout->add(0, sub { $Command{$cmd}[0]($_[0],$arg); 0;},GetActiveWindow()); warn "fifo:received $cmd\n" if $debug; }
		else {warn "fifo:received unknown command : '$cmd'\n"}
	}
	if (1) #FIXME replace 1 by gtk+ version check once the gtk+ bug is fixed (http://bugzilla.gnome.org/show_bug.cgi?id=321053)
	{	#work around gtk bug that use 100% cpu after first command : close and reopen fifo
		close $fifofh;
		sysopen $fifofh,$FIFOFile, O_NONBLOCK;
		#sysopen $fifofh,$FIFOFile, O_NONBLOCK | O_RDWR;

		Glib::IO->add_watch(fileno($fifofh),['in','hup'], \&CmdFromFIFO);
		return 0; #remove previous watcher
	}
	1;
}

sub GetActiveWindow
{	my ($win)= sort {$b->{last_focused} <=> $a->{last_focused}} grep $_->{last_focused}, Gtk2::Window->list_toplevels;
	return $win;
}

sub SearchPicture	# search for file with a relative path among a few folders, used to find pictures used by layouts
{	my ($file,@paths)=@_;
	return $file if file_name_is_absolute($file);
	push @paths, $HomeDir.'layouts', $CmdLine{searchpath}, PIXPATH, $DATADIR.SLASH.'layouts';	#add some default folders
	@paths= grep defined, map ref() ? @$_ : $_, @paths;
	for (@paths) { $_=dirname($_) if -f; }		#replace files by their folder
	my $found=first { -f $_.SLASH.$file } @paths;
	return cleanpath($found.SLASH.$file) if $found;
	warn "Can't find file '$file' (looked in : @paths)\n";
	return undef;
}

sub FileList
{	my ($re,@search)=@_;
	my @found;
	@search=grep defined, @search;
	@search=map ref() ? @$_ : $_, @search;
	for my $search (@search)
	{	if (-f $search) { push @found,$search if $search=~$re; next; }
		next unless -d $search;
		opendir my($dir),$search;
		push @found, map $search.SLASH.$_,sort grep m/$re/, readdir $dir;
		close $dir;
	}
	return grep -f, @found;
}
sub LoadPlugins
{	my @list= FileList( qr/\.p[lm]$/, $DATADIR.SLASH.'plugins', $HomeDir.'plugins', $CmdLine{searchpath} );

	my %loaded; $loaded{$_}= $_->{file} for grep $_->{loaded}, values %Plugins;
	for my $file (grep !$loaded{$_}, @list)
	{	warn "Reading plugin $file\n" if $::debug;
		my ($found,$id);
		open my$fh,'<:utf8',$file or do {warn "error opening $file : $!\n";next};
		while (my $line=<$fh>)
		{	if ($line=~m/^=(?:begin |for )?gmbplugin(?: ([A-Za-z]\w*))?/)
			{	my $id=$1;
				my %plug= (version=>0,desc=>'',);
				while ($line=<$fh>)
				{	$line=~s/\s*[\n\r]+$//;
					last if $line eq '=cut' || $line eq '=end gmbplugin';
					my ($key,$val)= $line=~m/^\s*(\w+):?\s+(.+)/;
					next unless $key;
					if ($key eq 'id') { $id=$val }
					elsif ($key eq 'desc')
					{	$plug{desc} .= _($val)."\n";
					}
					elsif ($key eq 'author')
					{	push @{$plug{author}}, $val;
					}
					else { $plug{$key}=$val; }
				}
				last unless $id;
				last unless $plug{name};
				chomp $plug{desc};
				$plug{file}=$file;
				$plug{version}=$1+($2||0)/100+($3||0)/10000 if $plug{version}=~m#(\d+)(?:\.(\d+)(?:\.(\d+)))#;
				$plug{$_}=_($plug{$_}) for grep $plug{$_}, qw/name title/;
				$found++;
				if ($Plugins{$id})
				{	last if $Plugins{$id}{loaded} || $Plugins{$id}{version}>=$plug{version};
				}
				warn "found plugin $id ($plug{name})\n" if $::debug;
				$Plugins{$id}=\%plug;
				last;
			}
			elsif ($line=~m/^\s*[^#\n\r]/) {last} #read until first non-empty and non-comment line
		}
		close $fh;
		warn "No plugin found in $file, maybe it uses an old format\n" unless $found;
	}
}
sub PluginsInit
{	if (delete $CmdLine{noplugins}) { $Options{'PLUGIN_'.$_}=0 for keys %Plugins; }
	my $h=delete $CmdLine{plugins};
	for my $p (keys %$h)
	{	if (!$Plugins{$p}) { warn "Unknown plugin $p\n";next }
		$Options{'PLUGIN_'.$p}=$h->{$p};
	}
	ActivatePlugin($_,'init') for grep $Options{'PLUGIN_'.$_}, sort keys %Plugins;
}

# $startup can be undef, 'init' or 'startup'
# - 'init' when called after loading settings, run Init if defined
# - 'startup' when called after the songs are loaded, run Start if defined
# - undef when activated by the user, runs Init then Start
sub ActivatePlugin
{	my ($plugin,$startup)=@_;
	my $ref=$Plugins{$plugin};
	if ( $ref->{loaded} || do $ref->{file} )
	{	$ref->{loaded}=1;
		delete $ref->{error};
		my $package='GMB::Plugin::'.$plugin;
		if ($startup && $startup eq 'init')
		{	if ($package->can('Init'))
			{	$package->Init;
				warn "Plugin $plugin initialized.\n" if $debug;
			}
		}
		else
		{	$package->Init if !$startup && $package->can('Init');
			$package->Start($startup) if $package->can('Start');
			warn "Plugin $plugin activated.\n" if $debug;
		}
		$Options{'PLUGIN_'.$plugin}=1;
	}
	elsif (!$startup || $startup eq 'init')
	{	warn "plugin $ref->{file} failed : $@\n";
		$ref->{error}=$@;
	}
}
sub DeactivatePlugin
{	my $plugin=$_[0];
	my $package='GMB::Plugin::'.$plugin;
	delete $Options{'PLUGIN_'.$plugin};
	return unless $Plugins{$plugin}{loaded};
	warn "Plugin $plugin De-activated.\n" if $debug;
	$package->Stop if $package->can('Stop');
}
sub CheckPluginRequirement
{	my $plugin=shift;
	my $ref=$Plugins{$plugin};
	my $msg='';
	if (my $req=$ref->{req})
	{	my @req;
		my @suggest;
		while ($req=~m/\bperl\(([\w:]+)(?:\s*,\s*([-\.\w ]+))?\)/ig)
		{	my ($module,$packages)=($1,$2);
			my $file="/$module.pm";
			$file=~s#::#/#g;
			if (!grep -f $_.$file, @INC)
			{	push @req, __x( _"the {name} perl module",name=>$module);
				push @suggest, $packages;
			}
		}
		while ($req=~m/\bexec\((\w+)(?:\s*,\s*([-\.\w ]+))?\)/ig)
		{	my ($exec,$packages)=($1,$2);
			if (!grep -x $_.$exec, split /:/, $ENV{PATH})
			{	push @req, __x( _"the command {name}",name=>$exec);
				push @suggest, $packages;
			}
		}
		while ($req=~m/\bfile\(([-\w\.\/]+)(?:\s*,\s*([-\.\w ]+))?\)/ig)
		{	my ($file,$packages)=($1,$2);
			if (!-r $file)
			{	push @req, __x( _"the file {name}",name=>$file);
				push @suggest, $packages;
			}
		}
		return unless @req;
		my $msg= PangoEsc(_"This plugin requires :")."\n\n";
		while (@req)
		{	my $r=shift @req;
			my $packages=shift @suggest;
			$packages= $packages ? ("Possible package names providing this :".' '.$packages."\n") : '';
			$msg.= MarkupFormat("- %s\n<small>%s</small>\n", $r, $packages);
		}
		return $msg;
	}
}

sub ChangeVol
{	my $cmd;
	if ($_[0] eq 'mute')
	{	$cmd=$Vol_package->GetMute? 'unmute':'mute' ;
	}
	else
	{	$cmd=(ref $_[0])? $_[1]->direction : $_[0];
		if	($Vol_package->GetMute)	{$cmd='unmute'}
		elsif	($cmd eq 'up')	{$cmd="+$Options{VolumeStep}"}
		elsif	($cmd eq 'down'){$cmd="-$Options{VolumeStep}"}
	}
	warn "volume $cmd ...\n" if $debug;
	UpdateVol($cmd);
	warn "volume $cmd" if $debug;
}

sub UpdateVol
{	$Vol_package->SetVolume($_[0]);
}
sub GetVol
{	$Vol_package->GetVolume;
}
sub GetMute
{	$Vol_package->GetMute;
}

sub FirstTime
{	#Default filters
	$Options{SavedFilters}=
	{	_"never played"		=> 'playcount:<:1',
		_"50 Most Played"	=> 'playcount:h:50',
		_"50 Last Played"	=> 'lastplay:h:50',
		_"50 Last Added"	=> 'added:h:50',
		_"Played Today"		=> 'lastplay:<ago:1d',
		_"Added Today"		=> 'added:<ago:1d',
		_"played>4"		=> 'playcount:>:4',
		_"not bootleg"		=> 'label:-~:bootleg',
	};
	$_=Filter->new($_) for values %{ $Options{SavedFilters} };

	my @dirs= reverse map $_.SLASH.'gmusicbrowser', Glib::get_system_config_dirs;
	for my $dir ($DATADIR,@dirs)
	{	next unless -r $dir.SLASH.'gmbrc.default';
		open my($fh),'<:utf8', $dir.SLASH.'gmbrc.default';
		my @lines=<$fh>;
		close $fh;
		chomp @lines;
		my $opt={};
		ReadRefFromLines(\@lines,$opt);
		%Options= ( %Options, %$opt );
	}

	Post_Options_init();
}


my %artistsplit_old_to_new=	#for versions <= 1.1.5 : to upgrade old ArtistSplit regexp to new default regexp
(	' & '	=> '\s*&\s*',
	', '	=> '\s*,\s+',
	' \\+ '	=> '\s*\\+\s*',
	'; *'	=> '\s*;\s*',
	';'	=> '\s*;\s*',
);

sub ReadOldSavedTags
{	my $fh=$_[0];
	while (<$fh>)
	{	chomp; last if $_ eq '';
		$Options{$1}=$2 if m/^([^=]+)=(.*)$/;
	}
	my $oldversion=delete $Options{version} || VERSION;
	if ($oldversion<0.9464) {delete $Options{$_} for qw/BrowserTotalMode FilterPane0Page FilterPane0min FilterPane1Page FilterPane1min LCols LSort PlayerWinPos SCols Sticky WSBrowser WSEditQueue paned StickyFilters/;} #cleanup old options
	$Options{'123options_mpg321'}=delete $Options{'123options_mp3'};
	$Options{'123options_ogg123'}=delete $Options{'123options_ogg'};
	$Options{'123options_flac123'}=delete $Options{'123options_flac'};
	delete $Options{$_} for qw/Device 123options_mp3 123options_ogg 123options_flac test Diacritic_sort gst_volume Simplehttp_CacheSize/; #cleanup old options
	delete $Options{$_} for qw/SavedSongID SavedPlayTime Lock SavedSort/; #don't bother supporting upgrade for these
	$Options{CustomKeyBindings}= { ExtractNameAndOptions($Options{CustomKeyBindings}) };
	delete $Options{$_} for grep m/^PLUGIN_MozEmbed/,keys %Options; #for versions <=1.0
	delete $Options{$_} for grep m/^PLUGIN_WebContext_Disable/,keys %Options;
	delete $Options{$_} for grep m/^Layout(?:LastSeen)?_/, keys %Options;
	$Options{WindowSizes}{$_}= join 'x',split / /,delete $Options{"WS$_"} for map m/^WS(.*)/, keys %Options;
	delete $Options{RecentFilters};	#don't bother upgrading them
	$Options{FilenameSchema}=	[split /\x1D/,$Options{FilenameSchema}];
	$Options{FolderSchema}=		[split /\x1D/,$Options{FolderSchema}];
	$Options{LibraryPath}= delete $Options{Path};
	$Options{Labels}=delete $Options{Flags} if $oldversion<=0.9571;
	$Options{Labels}=[ split "\x1D",$Options{Labels} ] unless ref $Options{Labels};	#for version <1.1.2
	$Options{Artists_split_re}= [ map { $artistsplit_old_to_new{$_}||$_ } grep $_ ne '$', split /\|/, delete $Options{ArtistSplit} ];
	$Options{TrayTipDelay}&&=900;

	Post_Options_init();

	my $oldID=-1;
	no warnings 'utf8'; # to prevent 'utf8 "\xE9" does not map to Unicode' type warnings about path and file which are stored as they are on the filesystem #FIXME find a better way to read lines containing both utf8 and unknown encoding
	my ($loadsong)=Songs::MakeLoadSub({},split / /,$Songs::OLD_FIELDS);
	my (%IDforAlbum,%IDforArtist);
	my @newIDs; SongArray::start_init();
	my @missing;
	my $lengthcheck=SongArray->new;
	while (<$fh>)
	{	chomp; last if $_ eq '';
		$oldID++;
		next if $_ eq ' ';	#deleted entry
		s#\\([n\\])#$1 eq "n" ? "\n" : "\\"#ge unless $oldversion<0.9603;
		my @song=split "\x1D",$_,-1;

		next unless $song[0] && $song[1] && $song[2]; # 0=SONG_FILE 1=SONG_PATH 2=SONG_MODIF
		my $album=$song[11]; my $artist=$song[10];
		$song[10]=~s/^<Unknown>$//;	#10=SONG_ARTIST
		$song[11]=~s/^<Unknown>.*//;	#11=SONG_ALBUM
		$song[12]=~s#/.*$##; 		##12=SONG_DISC
		#$song[13]=~s#/.*$##; 		##13=SONG_TRACK
		for ($song[0],$song[1]) { _utf8_off($_); $_=Songs::filename_escape($_) } # file and path
		my $misc= $song[24]||''; #24=SONG_MISSINGSINCE also used for estimatedlength and radio
		next if $misc eq 'R'; #skip radios (was never really enabled)
		$song[24]=0 unless $misc=~m/^\d+$/;
		my $ID= $newIDs[$oldID]= $loadsong->(@song);
		$IDforAlbum{$album}=$IDforArtist{$artist}=$ID;
		push @$lengthcheck,$ID if $misc eq 'l';
		if ($misc=~m/^\d+$/ && $misc>0) { push @missing,$ID }
		else { push @$Library,$ID };
	}
	Songs::AddMissing(\@missing, 'init') if @missing;
	while (<$fh>)
	{	chomp; last if $_ eq '';
		my ($key,$p)=split "\x1D";
		next if $p eq '';
		_utf8_off($p);
		my $ID=$IDforArtist{$key};
		next unless defined $ID;
		my $gid=Songs::Get_gid($ID,'artist');
		Songs::Picture($gid,'artist_picture','set',$p);
	}
	while (<$fh>)
	{	chomp; last if $_ eq '';
		my ($key,$p)=split "\x1D";
		next if $p eq '';
		_utf8_off($p);
		my $ID=$IDforAlbum{$key};
		next unless defined $ID;
		my $gid=Songs::Get_gid($ID,'album');
		Songs::Picture($gid,'album_picture','set',$p);
	}
	$Options{$_}={} for qw/SavedFilters SavedSorts SavedWRandoms SavedLists SavedSTGroupings/;
	while (<$fh>)
	{	chomp;
		my ($key,$val)=split "\x1D",$_,2;
		$key=~s/^(.)//;
		if ($1 eq 'F')
		{	$val=~s/((?:^|\x1D)-?)(\d+)?([^0-9()])/$1.(defined $2? Songs::FieldUpgrade($2) : '').":$3:"/ge;
			$val=~s/((?:^|\x1D)-?(?:label|genre)):e:(?=\x1D|$)/$1:ecount:0/g;
			$val=~s/((?:^|\x1D)-?(?:label|genre)):f:/$1:~:/g;
			$Options{SavedFilters}{$key}=Filter->new_from_string($val);
		}
		elsif ($1 eq 'S')
		{	$Options{SavedSorts}{$key}=$val;
		}
		elsif ($1 eq 'R')
		{	$Options{SavedWRandoms}{$key}=$val;
		}
		elsif ($1 eq 'L')
		{	$Options{SavedLists}{$key}= SongArray::Named->new_from_string($val);
		}
		elsif ($1 eq 'G')
		{	$Options{SavedSTGroupings}{$key}=$val;
		}
	}

	if (my $f=delete $Options{LastPlayFilter})
	{	if ($f=~s/^(filter|savedlist|list) //)
		{	$Options{LastPlayFilter}=
			$1 eq 'filter' ?	Filter->new_from_string($f) :
			$1 eq 'savedlist' ?	$f		:
			$1 eq 'list' ?		SongArray->new_from_string($f):
			undef;
		}
	}
	s/^r/random:/ || s/([0-9s]+)(i?)/($1 eq 's' ? 'shuffle' : Songs::FieldUpgrade($1)).($2 ? ':i' : '')/ge
		for values %{$Options{SavedSorts}},values %{$Options{SavedWRandoms}},$Options{Sort},$Options{AltSort};
	$Options{Sort_LastOrdered}=$Options{Sort_LastSR}= delete $Options{AltSort};
	if ($Options{Sort}=~m/random|shuffle/) { $Options{Sort_LastSR}=$Options{Sort} } else { $Options{Sort_LastOrdered}=$Options{Sort}||'path file'; }

	$Options{SongArray_Recent}= SongArray->new_from_string(delete $Options{RecentIDs});
	SongArray::updateIDs(\@newIDs);
	SongArray->new($Library);	#done after SongArray::updateIDs because doesn't use old IDs
	Songs::Set($_,length_estimated=>1) for @$lengthcheck;
	$Options{LengthCheckMode}='add';
}

sub Filter_new_from_string_with_upgrade	# for versions <=1.1.7
{	my @filter=split /\x1D/,$_[1];
	my @new;
	for my $f (@filter)
	{	if ($f=~m/^[()]/) { push @new,$f; next }
		my ($field,$cmd,$pat)=split ':',$f,3;
		if    ($cmd eq 's') {$cmd='si'}
		elsif ($cmd eq 'S') {$cmd='s'}
		elsif ($cmd eq 'l') { $field='list'; $cmd='e'; }
		elsif ($cmd eq 'i') { $pat=~s#([^/\$_.+!*'(),A-Za-z0-9-])#sprintf('%%%02X',ord($1))#seg; }
		elsif ($field eq 'rating' && $cmd eq 'e') { $cmd='~'}
		elsif ($cmd=~m/^[b<>]$/ && $field=~m/^-?lastplay$|^-?lastskip$|^-?added$|^-?modif$/)
		{	if ($pat=~m/[a-zA-Z]/)
			{	$cmd=	$cmd eq '<' ? '>ago' :
					$cmd eq '>' ? '<ago' : 'bago';
			}
			else { $pat=~s/(\d\d\d\d)-(\d\d?)-(\d\d?)/mktime(0,0,0,$3,$2-1,$1-1900)/eg }
		}
		elsif ($cmd eq 'b')
		{	my ($n1,$n2)= split / /,$pat;
			if ($field=~s/^-//)	{ push @new, '(|', "$field:<:$n1",  "$field:->:$n2",')'; }
			else			{ push @new, '(&', "$field:-<:$n1", "$field:<:$n2" ,')'; }
			next
		}
		$cmd= '-'.$cmd if $field=~s/^-//;
		push @new, "$field:$cmd:$pat";
	}
	my $string= join "\x1D", @new;
	return Filter->new_from_string_real($string);
}

sub ReadSavedTags	#load tags _and_ settings
{	my ($fh,$loadfile,$ext)= Open_gmbrc( $ImportFile || $SaveFile,0);
	unless ($fh)
	{	if ($loadfile && -e $loadfile && -s $loadfile)
		{	die "Can't open '$loadfile', aborting...\n" unless $fh;
		}
		else
		{	FirstTime();
			Post_ReadSavedTags();
			return;
		}
	}
	warn "Reading saved tags in $loadfile ...\n";
	$SaveFile.=$1 if $loadfile=~m#($gmbrc_ext_re)# && $SaveFile!~m#$gmbrc_ext_re#; # will use .gz/.xz to save if read from a .gz/.xz gmbrc

	setlocale(LC_NUMERIC, 'C');  # so that '.' is used as a decimal separator when converting numbers into strings
	# read first line to determine if old version, version >1.1.7 stars with "# gmbrc version=",  version <1.1 starts with a letter, else it's version<=1.1.7 (starts with blank or # (for comments) or [ (section name))
	my $firstline=<$fh>;
	unless (defined $firstline) { die "Can't read '$loadfile', aborting...\n" }
	my $oldversion;
	if ($firstline=~m/^#?\s*gmbrc version=(\d+\.\d+)/) { $oldversion=$1 }
	elsif ($ext) { die "Can't find gmbrc header in '$loadfile', aborting...\n" }	# compressed gmbrc not supported with old versions, because can't seek backward in compressed fh
	elsif ($firstline=~m/^\w/) { seek $fh,0,SEEK_SET; ReadOldSavedTags($fh); $oldversion=1 }
	else	# version <=1.1.7
	{	seek $fh,0,SEEK_SET;
		no warnings qw/redefine once/;
		*Filter::new_from_string_real= \&Filter::new_from_string;
		*Filter::new_from_string= \&Filter_new_from_string_with_upgrade;
	}
	if (!$oldversion || $oldversion>1) # version >=1.1
	{	my %lines;
		my $section='HEADER';
		while (<$fh>)
		{	if (m/^\[([^]]+)\]/) {$section=$1; next}
			chomp;
			next unless length;
			push @{$lines{$section}},$_;
		}
		close $fh;
		unless ($lines{Options}) { warn "Can't find Options section in '$loadfile', it's probably not a gmusicbrowser save file -> aborting\n"; exit 1; }
		SongArray::start_init(); #every SongArray read in Options will be updated to new IDs by SongArray::updateIDs later
		ReadRefFromLines($lines{Options},\%Options);
		$oldversion||=delete $Options{version} || VERSION;  # for version <=1.1.7
		if ($oldversion>VERSION) { warn "Loading a gmbrc saved with a more recent version of gmusicbrowser, try upgrading gmusicbrowser if there are problems\n"; }
		if ($oldversion<1.10091) {delete $Options{$_} for qw/Diacritic_sort gst_volume Simplehttp_CacheSize mplayer_use_replaygain/;} #cleanup old options
		if ($oldversion<=1.1011) {delete $Options{$_} for qw/ScanPlayOnly/;} #cleanup old options
		$Options{AutoRemoveCurrentSong}= delete $Options{TAG_auto_check_current} if $oldversion<1.1005 && exists $Options{TAG_auto_check_current};
		$Options{PlayedMinPercent}= 100*delete $Options{PlayedPercent} if exists $Options{PlayedPercent};
		if ($Options{ArtistSplit}) # for versions <= 1.1.5
		{	$Options{Artists_split_re}= [ map { $artistsplit_old_to_new{$_}||$_ } grep $_ ne '$', split /\|/, delete $Options{ArtistSplit} ];
		}
		if ($oldversion<1.1007) { for my $re (@{$Options{Artists_split_re}}) { $re='\s*,\s+' if $re eq '\s*,\s*'; } }
		if ($oldversion<1.1008) { my $d=$Options{TrayTipDelay}||0; $Options{TrayTipDelay}= $d==1 ? 900 : $d; }

		Post_Options_init();

		my $songs=$lines{Songs};
		my $fields=shift @$songs;
		my ($loadsong,$extra_sub)=Songs::MakeLoadSub(\%lines,split /\t/,$fields);
		my @newIDs;
		while (my $line=shift @$songs)
		{	my ($oldID,@vals)= split /\t/, $line,-1;
			s#\\x([0-9a-fA-F]{2})#chr hex $1#eg for @vals;
			$newIDs[$oldID]= $loadsong->(@vals);
		}
		#load fields properties, like album pictures ...
		for my $extra (keys %$extra_sub)
		{	my $lines=$lines{$extra};
			next unless $lines;
			shift @$lines;	#my @properties=split / /, shift @$lines;
			my $sub=$extra_sub->{$extra};
			while (my $line=shift @$lines)
			{	my ($key,@vals)= split /\t/, $line,-1;
				s#\\x([0-9a-fA-F]{2})#chr hex $1#eg for $key,@vals;
				$sub->($key,@vals);
			}
		}
		SongArray::updateIDs(\@newIDs);
		if (my $l=delete $Options{SongArray_Estimated}) # for $oldversion<1.1008
		{	$Recent= SongArray->new; # $Recent is used in SongsChanged() so must exists, will be replaced
			Songs::Set($_,length_estimated=>1) for @$l;
			$Options{LengthCheckMode}='add';
		}
		my $mfilter= $Options{MasterFilterOn} && $Options{MasterFilter} || '';
		my $filter= Filter->newadd(TRUE,'missing:e:0', $mfilter);
		$Library=[];	#dummy array to avoid a warning when filtering in the next line
		$Library= SongArray->new( $filter->filter_all );
		Songs::AddMissing( Songs::AllFilter('missing:-e:0'), 'init' );
	}

	if ($oldversion<=1.1009)
	{	bless $_,'SongArray::Named' for values %{$Options{SavedLists}}; #named lists now use SongArray::Named instead of plain SongArray
		no warnings 'once';
		for my $floatvector ($Songs::Songs_replaygain_track_gain__,$Songs::Songs_replaygain_track_peak__,$Songs::Songs_replaygain_album_gain__,$Songs::Songs_replaygain_album_peak__)
		{	$floatvector=  pack "F*",map $_||"nan", unpack("F*",$floatvector) if $floatvector; # undef is now stored as nan rather than 0, upgrade assuming all 0s were undef
		}
	}
	elsif ($oldversion==1.100901) #fix version 1.1.9.1 mistakenly upgrading by replacing float values of 0 by inf instead of nan
	{	for my $floatvector ($Songs::Songs_replaygain_track_gain__,$Songs::Songs_replaygain_track_peak__,$Songs::Songs_replaygain_album_gain__,$Songs::Songs_replaygain_album_peak__)
		{ $floatvector=  pack "F*",map {$_!="inf" ? $_ : "nan"} unpack("F*",$floatvector) if $floatvector; }
	}

	delete $Options{LastPlayFilter} unless $Options{RememberPlayFilter};
	$QueueAction= $Options{QueueAction} || '';
	unless ($Options{RememberQueue})
	{	$Options{SongArray_Queue}=undef;
		$QueueAction= '';
	}
	if ($Options{RememberPlayFilter})
	{	$TogLock=$Options{Lock};
	}
	if ($Options{RememberPlaySong} && $Options{SavedSongID})
	 { $SongID= (delete $Options{SavedSongID})->[0]; }
	if ($Options{RememberPlaySong} && $Options{RememberPlayTime}) { $PlayTime=delete $Options{SavedPlayTime}; }
	$Options{LibraryPath}||=[];
	$Options{LibraryPath}= [ map url_escape($_), split "\x1D", $Options{LibraryPath}] unless ref $Options{LibraryPath}; #for versions <=1.1.1
	&launchIdleLoop;

	setlocale(LC_NUMERIC, '');
	warn "Reading saved tags in $loadfile ... done\n";
	Post_ReadSavedTags();
}
sub Post_Options_init
{	PluginsInit();
	Songs::UpdateFuncs();
}
sub Post_ReadSavedTags
{	$Library||= SongArray->new;
	$Recent= $Options{SongArray_Recent}	||= SongArray->new;
	$Queue=  $Options{SongArray_Queue}	||= SongArray->new;
	$Options{LibraryPath}||=[];
	#CheckLength() if $Options{LengthCheckMode} eq 'add';
}

sub Open_gmbrc
{	my ($file,$write)=@_;
	my $encoding='utf8';
	my ($fh,$ext,@cmd);
	if ($write)
	{	my @cmd;
		if    ($file=~m#\.gz$#)	{ $ext='.gz'; @cmd=qw/gzip/; }
		elsif ($file=~m#\.xz$#)	{ $ext='.xz'; @cmd=qw/xz -0/; }
		if (@cmd)
		{	if (findcmd($cmd[0]))
			{	open $fh,'|-:'.$encoding,"@cmd > \Q$file\E"  or warn "Failed opening '$file' for writing (using $cmd[0]) : $!\n";
			}
			else { $file=~s#\.xz$|\.gz$##; @cmd=(); warn "Can't find $cmd[0], saving without compression\n"; }
		}
		if (!@cmd)
		{	open $fh,'>:'.$encoding,$file  or warn "Failed opening '$file' for writing : $!\n";
			$ext='';
		}
		return ($fh,$file,$ext);
	}
	else # open for reading
	{	unless (-e $file)	#if not found as is try with/without .gz/.xz
		{	$file=~s#$gmbrc_ext_re##;
			$file= find_gmbrc_file($file);
		}
		return unless $file;
		if (-z $file) { warn "Warning: save file '$file' is empty\n"; return }
		my $cmpr;
		if ($file=~m#(\.gz|\.xz)$#) { $cmpr=$ext=$1; }
		else
		{	open $fh,'<',$file  or warn "Failed opening '$file' for reading : $!\n";
			$cmpr=$ext='';

			# check if file compressed in spite of not having a .gz/.xz extension
			binmode($fh);	# need to read binary data, so do not set utf8 layer yet
			read $fh,my($header),6;
			if    ($header =~m#^\x1f\x8b#)	  { $cmpr='.gz'; } #gzip header : will open it as a .gz file
			elsif ($header eq "\xFD7zXZ\x00") { $cmpr='.xz'; } #xz header
			else { seek $fh,0,SEEK_SET; binmode($fh,':utf8'); } #no gzip header, rewind, and set utf8 layer
		}
		if    ($cmpr eq '.gz')	{ @cmd=qw/gzip -cd/; }
		elsif ($cmpr eq '.xz')	{ @cmd=qw/xz -cd/; }
		if (@cmd)
		{	close $fh if $fh;	#close compressed files without extension
			if (findcmd($cmd[0]))
			{	open $fh,'-|:'.$encoding,"@cmd \Q$file\E"  or warn "Failed opening '$file' for reading (using $cmd[0]) : $!\n";
			}
			else { warn "Can't find $cmd[0], you could uncompress '$file' manually\n"; }
		}
		return ($fh,$file,$ext,$cmpr);
	}
}

sub SaveTags	#save tags _and_ settings
{	my $fork=shift; #if true, save in a forked process
	HasChanged('Save');
	if ($CmdLine{demo}) { warn "-demo option => not saving tags/settings\n" if $Verbose || !$fork; return }

	my $ext='';
	my $SaveFile= $SaveFile; #do a local copy to locally remove .gz extension if present
	$ext=$1 if $SaveFile=~s#($gmbrc_ext_re)$##; #remove .gz/.xz extension from the copy of $SaveFile, put it in $ext
	if (exists $CmdLine{gzip}) { $ext= $CmdLine{gzip} eq 'gzip' ? '.gz' : $CmdLine{gzip} eq 'xz' ? '.xz' : '' }
	#else { $ext='.gz' } # use gzip by default

	my ($savedir,$savefilename)= splitpath($SaveFile);
	unless (-d $savedir) { warn "Creating folder $savedir\n"; mkdir $savedir or warn $!; }
	opendir my($dh),$savedir;
	unlink $savedir.SLASH.$_ for grep m/^\Q$savefilename\E\.new\.\d+(?:$gmbrc_ext_re)?$/, readdir $dh; #delete old temporary save files
	closedir $dh;

	if ($fork)
	{	my $pid= fork;
		if (!defined $pid) { $fork=undef; } # error, fallback to saving in current process
		elsif ($pid)
		{	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
			return
		}
	}

	setlocale(LC_NUMERIC, 'C');
	$Options{Lock}= $TogLock || '';
	$Options{SavedSongID}= SongArray->new([$SongID]) if $Options{RememberPlaySong} && defined $SongID;
	$Options{QueueAction}= $QActions{$QueueAction}{save} ? $QueueAction : '';

	$Options{SavedOn}= time;

	my $tooold=0;
	my @sessions=split ' ',$Options{Sessions};
	unless (@sessions && $DAYNB==$sessions[0])
	{	unshift @sessions,$DAYNB;
		$tooold=pop @sessions if @sessions>20;
		$Options{Sessions}=join ' ',@sessions;
	}
	for my $key (keys %{$Options{Layouts}}) #cleanup options for layout that haven't been seen for a while
	{	my $lastseen=$Options{LayoutsLastSeen}||={};
		if 	(exists $Layout::Layouts{$key})	{ delete $lastseen->{$key}; }
		elsif	(!$lastseen->{$key})		{ $lastseen->{$key}=$DAYNB; }
		elsif	($lastseen->{$key}<$tooold)	{ delete $_->{$key} for $Options{Layouts},$lastseen; }
	}

	local $SIG{PIPE} = 'DEFAULT';	# default is, for some reason, IGNORE, which causes "gzip: stdout: Broken pipe" after closing $fh when using gzip for unclear reasons
	my $error;
	(my$fh,my$tempfile,$ext)= Open_gmbrc("$SaveFile.new.$$"."$ext",1);
	unless ($fh) { warn "Save aborted\n"; POSIX::_exit(0) if $fork; return; }
	warn "Writing tags in $SaveFile$ext ...\n" if $Verbose || !$fork;

	print $fh "# gmbrc version=".VERSION." time=".time."\n"  or $error||=$!;

	my $optionslines=SaveRefToLines(\%Options);
	print $fh "[Options]\n$$optionslines\n"  or $error||=$!;

	my ($savesub,$fields,$extrasub,$extra_subfields)=Songs::MakeSaveSub();
	print $fh "[Songs]\n".join("\t",@$fields)."\n"  or $error||=$!;
	for my $ID (@{ Songs::AllFilter('missing:-b:1 '.($tooold||1)) })
	{	my @vals=$savesub->($ID);
		s#([\x00-\x1F\\])#sprintf "\\x%02x",ord $1#eg for @vals;
		my $line= join "\t", $ID, @vals;
		print $fh $line."\n"  or $error||=$!;
	}
	#save fields properties, like album pictures ...
	for my $field (sort keys %$extrasub)
	{	print $fh "\n[$field]\n$extra_subfields->{$field}\n"  or $error||=$!;
		my $h= $extrasub->{$field}->();
		for my $key (sort keys %$h)
		{	my $vals= $h->{$key};
			s#([\x00-\x1F\\])#sprintf "\\x%02x",ord $1#eg for $key,@$vals;
			$key=~s#^\[#\\x5b#; #escape leading "["
			my $line= join "\t", @$vals;
			next if $line=~m/^\t*$/;
			print $fh "$key\t$line\n"  or $error||=$!;
		}
	}
	close $fh  or $error||=$!;
	setlocale(LC_NUMERIC, '');
	if ($error)
	{	rename $tempfile,$SaveFile.'.error'.$ext;
		warn "Writing tags in $SaveFile$ext ... error : $error\n";
		POSIX::_exit(1) if $fork;
		return;
	}
	if ($fork && !-e $tempfile) { POSIX::_exit(0); } #tempfile disappeared, probably deleted by a subsequent save from another process => ignore
	my $previous= $SaveFile.$ext;
	$previous= find_gmbrc_file($SaveFile) unless -e $previous;
	if ($previous) #keep some old files as backup
	{	{	my ($bfh,$previousbak,$ext2,$cmpr)= Open_gmbrc($SaveFile.'.bak'.$ext,0);
			last unless $bfh;
			local $_; my $date;
			while (<$bfh>) { if (m/^SavedOn:\s*(\d+)/) {$date=$1;last} last if m/^\[(?!Options])/}
			close $bfh;
			last unless $date;
			$date=strftime('%Y%m%d',localtime($date));
			if (find_gmbrc_file($SaveFile.'.bak.'.$date)) { unlink $previousbak; last} #remove .bak if already a backup for that day
			rename $previousbak, "$SaveFile.bak.$date$ext2"  or warn $!;
			if (!$cmpr && (!exists $CmdLine{gzip} || $CmdLine{gzip})) #compress old backups unless "-gzip" option is used
			{	my $cmd= $CmdLine{gzip} || 'xz';
				$cmd= findcmd($cmd,'xz','gzip');
				system($cmd,'-1','-f',"$SaveFile.bak.$date") if $cmd;
			}

			my @files=FileList(qr/^\Q$savefilename\E\.bak\.\d{8}(?:$gmbrc_ext_re)?$/, $savedir);
			last unless @files>5;
			splice @files,-5;	#keep the 5 newest versions
			unlink @files;
		}
		my $rename= $previous;
		$rename=~s#($gmbrc_ext_re?)$#.bak$1#;
		rename $previous, $rename  or warn $!;
		unlink $_ for find_gmbrc_file($SaveFile); #make sure there is no other old gmbrc without .bak, as they could cause confusion
	}
	rename $tempfile,$SaveFile.$ext  or warn $!;
	warn "Writing tags in $SaveFile$ext ... done\n" if $Verbose || !$fork;
	POSIX::_exit(0) if $fork;
}

sub ReadRefFromLines	# convert a string written by SaveRefToLines to a hash/array # can only read a small subset of YAML
{	my ($lines,$return)=@_;
	my @todo;
	my ($ident,$ref)=(0,$return);
	my $parentval; my @objects;
	for my $line (@$lines)
	{	next if $line=~m/^\s*(?:#|$)/;	#skip comment or empty line
		my ($d,$array,$key,$val)= $line=~m/^(\s*)(?:(-)|(?:("[^"]*"|\S*)\s*:))\s*(.*)$/;
		$d= length $d;
		if ($parentval)		#first value of new array or hash
		{	next unless $d>=$ident;
			push @todo, $ref,$ident;
			$ident=$d;
			$ref=$$parentval= $array ? [] : {};
			$parentval=undef;
		}
		elsif ($ident-$d)
		{	next unless $ident>$d;
			while ($ident>$d) { $ident=pop @todo; $ref=pop @todo; }
		}
		if (!$array && $key=~s/^"//) { $key=~s/"$//; $key=~s#\\x([0-9a-fA-F]{2})#chr hex $1#ge; }
		$val=~s/\s+$//;
		my $class;
		if ($val=~m/^!/) #object
		{	if ($val=~s/^!([^ !]+)\s*//) {$class=$1}
			else { warn "Unsupported value : '$val'\n"; next }
		}
		if ($val eq '')	#array or hash or object as array/hash
		{	$parentval= $array ? \$ref->[@$ref] : \$ref->{$key};
			push @objects, $class,$parentval if $class;
		}
		else		#scalar or empty array/hash or object as string
		{	if ($val eq '~') {$val=undef}
			elsif ($val=~m/^'(.*)'$/) {$val=$1; $val=~s/''/'/g; }
			elsif ($val=~m/^"(.*)"$/)
			{	$val=$1;
				$val=~s/\\"/"/g;
				$val=~s#\\x([0-9a-fA-F]{2})#chr hex $1#ge;
			}
			elsif ($val eq '[]') {$val=[];}
			elsif ($val eq '{}') {$val={};}
			if ($class)	{ $val= $class->new_from_string($val); }
			if ($array)	{ push @$ref,$val; }
			else		{ $ref->{$key}=$val; }
		}
	}
	while (@objects)
	{	my ($class,$ref)= splice @objects,-2; #start with the end -> if object contain other objects they will be created first
		$$ref= $class->new_from_string($$ref);
	}
	return @todo ? $todo[0] : $ref;
}


sub SaveRefToLines	#convert hash/array into a YAML string readable by ReadRefFromLines
{	my $ref=$_[0];
	my (@todo,$keylist,$ref_is_array);
	my $lines='';
	my $pre='';
	my $depth=0;
	if (ref $ref eq 'ARRAY'){ $keylist=0; $ref_is_array=1; }
	else			{ $keylist=[sort keys %$ref]; }
	while (1)
	{	my ($val,$next,$up);
		if ($ref_is_array) #ARRAY
		{	if ($keylist<@$ref)
			{	$val=$ref->[$keylist++];
				$lines.= $pre.'-';
				$next=$val if ref $val;
			}
			else {$up=1}
		}
		else #HASH
		{	if (@$keylist)
			{	my $key=shift @$keylist;
				$val=$ref->{$key};
				if ($key eq '') {$key='""'}
				elsif ($key=~m/[\x00-\x1f\n:# ]/ || $key=~m#^\W#)
				{	$key=~s/([\x00-\x1f\n"\\])/sprintf "\\x%02x",ord $1/ge;
					$key=qq/"$key"/;
				}
				$lines.= $pre.$key.':';
				$next=$val if ref $val;
			}
			else {$up=1}
		}
		if ($next)
		{	my $is_array= ref $next eq 'ARRAY';
			my $is_string;
			if (!$is_array && ref $next ne 'HASH') #save object
			{	$val=$next->save_to_string;
				$lines.= ' !'.ref($next);
				if (!ref $val) { $is_string=1 }
				else { $next=$val; $is_array= UNIVERSAL::isa($val,"ARRAY") ? 1 : 0; }
			}
			if (!$is_string)
			{	if    ( $is_array && !@$next)		{ $lines.=" []\n";next; }
				elsif (!$is_array && !keys(%$next))	{ $lines.=" {}\n";next; }
				$lines.="\n";
				$depth++;
				$pre='  'x$depth;
				push @todo,$ref,$ref_is_array,$keylist;
				$ref=$next;
				$ref_is_array= $is_array;
				if ($ref_is_array)	{ $keylist=0; }
				else			{ $keylist=[sort keys %$ref]; }
				next;
			}
		}
		elsif ($up)
		{	if ($depth)
			{	$depth--;
				$pre='  'x$depth;
				($ref,$ref_is_array,$keylist)= splice @todo,-3;
				next;
			}
			else {last}
		}
		if (!defined $val) {$val='~'}
		elsif ($val eq '') {$val="''"}
		elsif ($val=~m/[\x00-\x1f\n:#]/ || $val=~m#^'#)
		{	$val=~s/([\x00-\x1f\n"\\])/sprintf "\\x%02x",ord $1/ge;
			$val=qq/"$val"/;
		}
		elsif ($val=~m/^\W/ || $val=~m/\s$/ || $val=~m/^true$|^false$|^null$/i)
		{	$val=~s/'/''/g;
			$val="'$val'";
		}
		$lines.= ' '.$val."\n";
	}
	return \$lines;
}

sub SetWSize
{	my ($win,$wkey,$default)=@_;
	$win->set_role($wkey);
	$win->set_name($wkey);
	my $prevsize= $Options{WindowSizes}{$wkey} || $default;
	$win->resize(split 'x',$prevsize,2) if $prevsize;
	$win->signal_connect(unrealize => sub
		{ $Options{WindowSizes}{$_[1]}=join 'x',$_[0]->get_size; }
		,$wkey);
}

sub Rewind
{	my $sec=$_[1];
	return unless $sec;
	$sec=(defined $PlayTime && $PlayTime>$sec)? $PlayTime-$sec : 0;
	SkipTo($sec);
}
sub Forward
{	my $sec=$_[1];
	return unless $sec;
	$sec+=$PlayTime if defined $PlayTime;
	SkipTo($sec);
}

sub SkipTo
{	return unless defined $SongID;
	my $sec=shift;
	if (defined $PlayingID && defined $PlayTime) # if song already playing
	{	push @Played_segments, $StartedAt, $PlayTime;
		$StartedAt=$sec;
		$Play_package->SkipTo($sec);
	}
	else	{ Play($sec); }
	::QHasChanged( Seek => $sec );
}

sub PlayPause
{	if (defined $TogPlay)	{ Pause()} #paused or playing => resume or pause
	else			{ Play() } #stopped => play
}

sub Pause
{	if ($TogPlay)
	{	$Play_package->Pause;
		$TogPlay=0;
	}
	elsif (defined $TogPlay)
	{	$Play_package->Resume;
		$TogPlay=1;
	}
	HasChanged('Playing');
}

sub Play
{	return unless defined $SongID;
	my $sec=shift;
	$sec=undef unless $sec && !ref $sec;
	&Played if defined $PlayingID;
	$StartedAt=$sec||0;
	$StartTime=time;
	$PlayingID=$SongID;
	$Play_package->Play( Songs::GetFullFilename($SongID), $sec);
	my $wasplaying=$TogPlay;
	$TogPlay=1;
	UpdateTime(0);
	HasChanged('Playing') unless $wasplaying;
}

sub ErrorPlay
{	my ($error,$details)=@_;
	$error= __x( _"Playing error : {error}", error=> $error );
	warn $error."\n";
	return if $Options{IgnorePlayError};
	my $dialog = Gtk2::MessageDialog->new
		( $MainWindow, [qw/modal destroy-with-parent/],
		  'error','close','%s',
		  $error
		);
	if ($details)
	{	my $expander=Gtk2::Expander->new(_"Error details");
		$details= Gtk2::Label->new($details);
		$details->set_line_wrap(1);
		$details->set_selectable(1);
		$expander->add($details);
		$dialog->vbox->pack_start($expander,0,0,2);
	}
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
	#$dialog->signal_connect( response => sub {$_[0]->destroy});
	$PlayingID=undef; #will avoid counting the song as played or skipped
	Stop();
}

sub end_of_file_faketime
{	UpdateTime( Songs::Get($SongID,'length') );
	end_of_file();
}

sub end_of_file
{	SwitchPlayPackage() if $PlayNext_package;
	&Played;
	ResetTime();
	&NextSong if $TogPlay;
}

sub Stop
{	warn "stop\n" if $::debug;
	undef $TogPlay;
	$Play_package->Stop;
	SwitchPlayPackage() if $PlayNext_package;
	HasChanged('Playing');
	&Played;
	ResetTime();
}

sub SwitchPlayPackage
{	$Play_package->Close if $Play_package && $Play_package->can('Close');
	$Play_package=$PlayNext_package;
	$PlayNext_package=undef;
	$Play_package->Open if $Play_package->can('Open');
	$Vol_package=$Play_package;
	$Vol_package=$Play_package->VolInit||$Play_package if $Play_package->can('VolInit');
	HasChanged('AudioBackend');
	HasChanged('Equalizer','package');
	HasChanged('Vol');
}

sub UpdateTime
{	return if defined $PlayTime && $_[0] == $PlayTime;
	$PlayTime=$_[0];
	HasChanged('Time');
}
sub ResetTime
{	undef $PlayTime;
	HasChanged('Time');
}

sub AddToRecent	#add song to recently played list
{	my $ID=shift;
	unless (@$Recent && $Recent->[0]==$ID)
	{	$Recent->Unshift([$ID]);	#FIXME make sure it's not too slow, put in a idle ?
		$Recent->Pop if @$Recent>80;	#
	}
}

sub Coverage	# find number of unique seconds played from a list of start,stop times
{	my @segs=@_;
	my $sum=0;
	while (@segs)
	{	my ($start,$stop)=splice @segs,0,2;
		my $i=0;
		my $th=.5;	#threshold : ignore differences of less than .5s
		while ($i<@segs)
		{	my $s1=$segs[$i];
			my $s2=$segs[$i+1];
			if ($start-$s1<=$th && $s1-$stop<=$th || $start-$s2<=$th && $s2-$stop<=$th) # segments overlap
			{	$stop =$s2 if $s2>$stop;
				$start=$s1 if $s1<$start;
				splice @segs,$i,2;
				$i=0;
			}
			else { $i+=2; }
		}
		my $length= $stop-$start;
		$sum+= $length if $length>$th;
	}
	return $sum;
}

sub Played
{	return unless defined $PlayingID;
	my $ID=$PlayingID;
	warn "Played : $ID $StartTime $StartedAt $PlayTime\n" if $debug;
	AddToRecent($ID) unless $Options{AddNotPlayedToRecent};
	return unless defined $PlayTime;
	push @Played_segments, $StartedAt, $PlayTime;
	my $seconds=Coverage(@Played_segments); # a bit overkill :)

	my $length= Songs::Get($ID,'length');
	my $coverage_ratio= $length ? $seconds / Songs::Get($ID,'length') : 1;
	my $partial= $Options{PlayedMinPercent}/100 > $coverage_ratio && $Options{PlayedMinSeconds} > $seconds;
	HasChanged('Played',$ID, !$partial, $StartTime, $seconds, $coverage_ratio, \@Played_segments);
	$PlayingID=undef;
	@Played_segments=();

	if ($partial) #FIXME maybe only count as a skip if played less than ~20% ?
	{	my $nb= 1+Songs::Get($ID,'skipcount');
		Songs::Set($ID, skipcount=> $nb, lastskip=> $StartTime, '+skiphistory'=>$StartTime);
	}
	else
	{	my $nb= 1+Songs::Get($ID,'playcount');
		Songs::Set($ID, playcount=> $nb, lastplay=> $StartTime, '+playhistory'=>$StartTime);
	}
}

our %PPSQ_Icon;
INIT
{ %PPSQ_Icon=
 (	play	=> ['gtk-media-play', '<span font_family="Sans">▶</span>'],
	pause	=> ['gtk-media-pause','<span font_family="Sans">▮▮</span>'],
	stop	=> ['gtk-media-stop', '<span font_family="Sans">■</span>'],
 );
}
sub Get_PPSQ_Icon	#for a given ID, returns the Play, Pause, Stop or Queue icon, or undef if none applies
{	my ($ID,$notcurrent,$text)=@_;
	my $currentsong= !$notcurrent && defined $SongID && $ID==$SongID;
	my $status;
	if ($currentsong)	# playing or paused or stopped
	{	$status= $TogPlay		? 'play' :
			 defined $TogPlay	? 'pause':
						  'stop';
		$status= $PPSQ_Icon{$status}[$text ? 1 : 0];
	}
	elsif (@$Queue && $Queue->IsIn($ID))	#queued
	{	my $n;
		if ($NBQueueIcons || $text)
		{	my $max= $NBQueueIcons||10;
			$max= @$Queue unless $max < @$Queue;
			$n= first { $Queue->[$_]==$ID } 0..$max-1;
		}
		if ($text) { $status= defined $n ? "<b>Q<sup><small>".($n+1)."</small></sup></b>" : "<b>Q<sup><small>+</small></sup></b>"; }
		else	   { $status= defined $n ? "gmb-queue".($n+1) : 'gmb-queue0'; }
	}
	return $status;
}

sub ClearQueue
{	$Queue->Replace();
	#$QueueAction='';
	#HasChanged('QueueAction');
}

sub EnqueueSame
{	my ($field,$ID)=@_;
	my $filter=Songs::MakeFilterFromID($field,$ID);
	EnqueueFilter($filter);
}
sub EnqueueFilter
{	my $l=$_[0]->filter;
	Enqueue(@$l);
}
sub Enqueue
{	my @l=@_;
	SortList(\@l) if @l>1;
	@l=grep $_!=$SongID, @l  if @l>1 && defined $SongID;
	$Queue->Push(\@l);
	# ToggleLock($TogLock) if $TogLock;	#unset lock
}
sub QueueInsert
{	my @l=@_;
	SortList(\@l) if @l>1;
	@l=grep $_!=$SongID, @l  if @l>1 && defined $SongID;
	$Queue->Unshift(\@l);
}
sub ReplaceQueue
{	$Queue->Replace();
	&Enqueue; #keep @_
}
sub SetNextAction
{	$NextAction=shift;
	HasChanged('QueueAction');
}
sub EnqueueAction
{	$QueueAction=shift;
	HasChanged('QueueAction');
}
sub QAutoFill
{	return unless $QueueAction eq 'autofill';
	my $nb=$Options{MaxAutoFill}-@$Queue;
	return unless $nb>0;
	# FIXME shuffle list if !$RandomMode instead of using Random ?
	my $random= $RandomMode ||  Random->new('random:',$ListPlay);
	my @IDs=$random->Draw($nb,$Queue);
	return unless @IDs;
	$Queue->Push(\@IDs);
}
sub QWaitAutoPlay
{	return unless $QueueAction eq 'wait';
	return if $TogPlay || !@$Queue;
	Select(song => ($Queue->Shift), play=>1);
}
sub QueueChanged
{	if ($QueueAction && $QActions{$QueueAction})
	{	my $cb= $QActions{$QueueAction}{changed};
		IdleDo('1_QAuto',10,$cb) if $cb;
	}
}
sub Update_QueueActionList
{	if ($QueueAction)	#check if current one is still valid
	{	my $ok;
		if (my $prop= $QActions{$QueueAction})
		{	my $condition= $prop->{condition};
			$ok=1 if !$condition || $condition->();
		}
		EnqueueAction('') unless $ok;
	}
	QHasChanged('QueueActionList');
}
sub List_QueueActions
{	my $nextonly=shift;
	my @list= grep { !$QActions{$_}{condition} || $QActions{$_}{condition}() } keys %QActions;
	if ($nextonly) { @list= grep $QActions{$_}{can_next}, @list; }
	return sort {$QActions{$a}{order} <=> $QActions{$b}{order} || $a cmp $b} @list;
}

sub GetNeighbourSongs
{	my $nb=shift;
	$ListPlay->UpdateSort if $ToDo{'8_resort_playlist'};
	my $pos=$Position||0;
	my $begin=$pos-$nb;
	my $end=$pos+$nb;
	$begin=0 if $begin<0;
	$end=$#$ListPlay if $end>$#$ListPlay;
	return @$ListPlay[$begin..$end];
}

sub PrevSongInPlaylist
{	$ListPlay->UpdateSort if $ToDo{'8_resort_playlist'};
	my $pos=$Position;
	if (!defined $pos) { $pos=0; if ($RandomMode) {} }	#FIXME PHASE1 in case random
	if ($pos==0)
	{	return unless $Options{Repeat};
		$pos=$#$ListPlay;
	}
	else { $pos--; }
	SetPosition($pos);
}
sub NextSongInPlaylist
{	$ListPlay->UpdateSort if $ToDo{'8_resort_playlist'};
	my $pos=$Position;
	if (!defined $pos) { $pos=0;  if ($RandomMode) {} }	#FIXME PHASE1 in case random
	if ($pos==$#$ListPlay)
	{	return unless $Options{Repeat};
		$pos=0;
	}
	else { $pos++ }
	SetPosition($pos);
}

sub GetNextSongs	##if no aguments, returns next song and makes the changes assuming it is to become next song (remove it from queue, ...)
{	my ($nb,$onlyIDs)=@_; # if $nb is defined : passive query, do not make any change to queue or other things
	my $passive= defined $nb ? 1 : 0;
	$nb||=1;
	my @IDs;
	{ if ($NextAction)
	  {	push @IDs, ($passive ? $QActions{$NextAction}{short} : $NextAction)  unless $onlyIDs;
		unless ($passive || $QActions{$NextAction}{keep}) { SetNextAction('') }
		last;
	  }
	  if (@$Queue)
	  {	unless ($passive) { my $ID=$Queue->Shift; return $ID; }
		push @IDs,_"Queue" unless $onlyIDs;
		if ($nb>@$Queue) { push @IDs,@$Queue; $nb-=@$Queue; }
		else { push @IDs,@$Queue[0..$nb-1]; last; }
	  }
	  if ($QueueAction)
	  {	push @IDs, ($passive ? $QActions{$QueueAction}{short} : $QueueAction)  unless $onlyIDs;
		unless ($passive || $QActions{$QueueAction}{keep}) { EnqueueAction('') }
		last;
	  }
	  return unless @$ListPlay;
	  $ListPlay->UpdateSort if $ToDo{'8_resort_playlist'};
	  if ($RandomMode)
	  {	push @IDs,_"Random" if $passive && !$onlyIDs;
		push @IDs,$RandomMode->Draw($nb,((defined $SongID && @$ListPlay>1)? [$SongID] : undef));
		last;
	  }
	  my $pos;
	  $pos=FindPositionSong( $IDs[-1],$ListPlay ) if @IDs;
	  $pos= defined $Position ? $Position : -1  unless defined $pos;
	  if ($pos==-1 && !$ListMode)
	  {	my $ID= @IDs ? $IDs[-1] : $::SongID;
		if (defined $ID)
		{	$ID= Songs::FindNext($ListPlay, $Options{Sort}, $ID);
			$pos=FindPositionSong( $ID,$ListPlay );
			$pos=-1 if !defined $pos;
		}
	  }
	  push @IDs,_"Next" if $passive && !$onlyIDs;
	  while ($nb)
	  {	if ( $pos+$nb > $#$ListPlay )
		{	push @IDs,@$ListPlay[$pos+1..$#$ListPlay];
			last unless $Options{Repeat}; #FIXME repeatlock modes
			$nb-=$#$ListPlay-$pos;
			$pos=-1;
		}
		else { push @IDs,@$ListPlay[$pos+1..$pos+$nb]; last; }
	  }
	}
	return wantarray ? @IDs : $IDs[0];
}

sub PrepNextSongs
{	if ($NextAction) { @NextSongs=() }
	elsif ($RandomMode) { @NextSongs=@$Queue; $#NextSongs=9 if $#NextSongs>9; }
	else
	{	@NextSongs= GetNextSongs(10,'onlyIDs');
	}
	my $nextID=$NextSongs[0];
	$NextFileToPlay= defined $nextID ? Songs::GetFullFilename($nextID) : undef;
	warn "Next file to play : $::NextFileToPlay\n" if $::debug;
	::HasChanged('NextSongs');
}
sub QueueUpdateNextSongs
{	IdleDo('2_PrepNextSongs',100,\&PrepNextSongs);
	$NextFileToPlay=undef; @NextSongs=();
}

sub GetPrevSongs
{	my $nb=shift||1;
	my $list=($nb>1)? 1 : 0;
	my @IDs;
	push @IDs,_"Recently played" if $list;
	if ($nb>@$Recent) { push @IDs,@$Recent; }
	else { push @IDs,@$Recent[0..$nb-1]; }
	return $list ? @IDs : $IDs[0];
}

sub PrevSong
{	#my $ID=GetPrevSongs();
	return if @$Recent==0;
	$RecentPos||=0;
	if ($SongID==$Recent->[$RecentPos]) {$RecentPos++}
	my $ID=$Recent->[$RecentPos];
	return unless defined $ID;
	$RecentPos++;
	Select(song => $ID);
}
sub NextSong
{	my $ID=GetNextSongs();
	if (!defined $ID)  { Stop(); return; }
	if ($ID=~m/^\D/) { my $prop=$QActions{$ID}; $prop->{action}() if $prop && $prop->{action}; return }
	my $pos=$Position;
	if ( defined $pos && $pos<$#$ListPlay && $ListPlay->[$pos+1]==$ID ) { SetPosition($pos+1); }
	else { Select(song => $ID); }
}
sub NextDiff	#go to next song whose $field value is different than current's
{	my $field=$_[0];
	if (!defined $SongID) { NextSong(); return}
	my $filter= Songs::MakeFilterFromID($field,$SongID)->invert;
	if (@$Queue)
	{	my $list=$filter->filter($Queue);
		if (@$list)
		{	my $ID=$list->[0];
			my $row=first { $Queue->[$_]==$ID } 0..$#$Queue;
			$Queue->Remove([0..$row]);
			Select(song => $ID);
			return
		}
		else { $Queue->Replace(); } #empty queue if not matching song in it
	}
	# look at $QueueAction ? #FIXME
	my $playlist=$ListPlay;
	my $position=$Position||0;
	if ($TogLock && $TogLock eq $field)	 #remove lock on a different field if not found ?
	{	$playlist=$SelectedFilter->filter;
		SortList($playlist) unless $RandomMode;
		$position=FindPositionSong($SongID,$playlist);
	}
	my $list;
	if ($RandomMode) { $list= $filter->filter($playlist); }
	else
	{	my @rows=$position..$#$playlist;
		push @rows, 0..$position-1 if $Options{Repeat};
		@$list=map $playlist->[$_], @rows;
		$list=$filter->filter($list);
	}
	if (@$list)	#there is at least one matching  song
	{	my $ID;
		if ($RandomMode)
		{	($ID)=Random->OneTimeDraw($RandomMode,$list,1);
		}
		else	{ $ID=$list->[0]; }
		Select(song => $ID);
	}
	else	{ Stop(); }	#no matching song found in playlist => Stop (or do nothing ?)
}

sub ToggleLock
{	my ($col,$set)=@_;
	if ($set || !$TogLock || $TogLock ne $col)
	{	$TogLock=$col;
		#&ClearQueue;
	}
	else {undef $TogLock}
	$ListPlay->UpdateLock;
	HasChanged('Lock');
}

sub SetRepeat
{	$::Options{Repeat}=$_[0]||0;
	::HasChanged('Repeat');
}

sub DoActionForFilter
{	my ($action,$filter)=@_;
	$filter||= Filter->new;
	$action||='play';
	if    ($action eq 'play')	{ Select( filter=>$filter, song=>'first',play=>1 ); }
	else				{ DoActionForList($action,$filter->filter); }
}
sub DoActionForList
{	my ($action,$list)=@_;
	return unless ref $list && @$list;
	$action||='playlist';
	my @list=@$list;
	# actions that don't need/want the list to be sorted (Enqueue will sort it itself)
	if	($action eq 'queue')		{ Enqueue(@list) }
	elsif	($action eq 'queueinsert')	{ QueueInsert(@list) }
	elsif	($action eq 'replacequeue')	{ ReplaceQueue(@list) }
	elsif	($action eq 'properties')	{ DialogSongsProp(@list) }
	else
	{ # actions that need the list to be sorted
	 SortList(\@list) if @list>1;
	 if	($action eq 'playlist')		{ $ListPlay->Replace(\@list); }
	 elsif	($action eq 'addplay')		{ $ListPlay->Push(\@list); }
	 elsif	($action eq 'insertplay')	{ $ListPlay->InsertAtPosition(\@list); }
	 else	{ warn "Unknown action '$action'\n"; }
	}
}

sub SongArray_changed
{	my (undef,$songarray,$action,@extra)=@_;
	if ($songarray->isa('SongArray::Named')) { Songs::Changed(undef,'list'); } # simulate modifcation of the fake "list" field
	if ($songarray==$Queue)
	{	HasChanged('Queue',$action,@extra);
	}
	elsif ($songarray==$Recent) { IdleDo('2_RecentSongs',750,\&HasChanged,'RecentSongs'); }
	elsif ($songarray==$ListPlay)
	{	HasChanged('Playlist',$action,@extra);
	}
}

sub ToggleSort
{	my $s= ($RandomMode || $Options{Sort}=~m/shuffle/) ? $Options{Sort_LastOrdered} : $Options{Sort_LastSR};
	Select('sort' => $s);
}
sub Select_sort {Select('sort' => $_[0])}
#CHECKME if everything works with sort="",     with source	with empty Library  with !defined $SongID	implement row=> or pos=>
sub Select	#Set filter, sort order, selected song, playing state, staticlist, source
{	my %args=@_;
#::callstack(@_);
	my ($filter,$sort,$song,$staticlist,$pos)=@args{qw/filter sort song staticlist position/};
	$SongID=undef if $song && $song eq 'first';
	$song=undef if $song && $song=~m/\D/;
	if (defined $filter)
	{	if ($song) { $SongID=$song; $ChangedID=$ChangedPos=1; }
		$filter= Filter->new($filter) unless ref $filter;
		if ($sort) { $ListPlay->SetSortAndFilter($sort,$filter) }
		else { $ListPlay->SetFilter($filter); }
	}
	elsif (defined $sort) { $ListPlay->Sort($sort) }
	elsif ($staticlist)
	{	if (defined $pos) { $Position=$pos; $SongID=$staticlist->[$pos]; $ChangedID=$ChangedPos=1; }
		$ListPlay->Replace($staticlist);
	}
	elsif (defined $song) { $ListPlay->SetID($song) }
	elsif (defined $pos) { SetPosition($pos) }
	Play() if $args{play} && !$TogPlay;
}

sub SetPosition
{	$Position=shift;
	#check within bounds ?
	$SongID=$ListPlay->[$Position];
	$ChangedPos=$ChangedID=1;
	UpdateCurrentSong();
}
sub UpdateCurrentSong
{	#my $force=shift;
	if ($ChangedID)
	{	AddToRecent($prevID) if defined $prevID && $Options{AddNotPlayedToRecent};
		$prevID=$SongID;
		QHasChanged('CurSongID',$SongID);
		QHasChanged('CurSong',$SongID);
		ShowTraytip($Options{TrayTipTimeLength}) if $TrayIcon && $Options{ShowTipOnSongChange} && !$FullscreenWindow;
		IdleDo('CheckCurrentSong',1000,\&CheckCurrentSong) if defined $SongID;
		if (defined $RecentPos && (!defined $SongID || $SongID!=$Recent->[$RecentPos-1])) { $RecentPos=undef }
		$ChangedPos=1;
	}
	if ($ChangedPos)
	{	if (!defined $SongID || $RandomMode) { $Position=undef; }
		elsif (!defined $Position || $ListPlay->[$Position]!=$SongID)
		{	my $start=$Position;
			$start=-1 unless defined $start;
			$Position=undef;
			for my $i ($start+1..$#$ListPlay, 0..$start-1) {$Position=$i if $ListPlay->[$i]==$SongID}
		}
		QHasChanged('Pos','song');
	}
	#   Stop(); if  !defined $SongID ???????
	#if	($forceplay)			{Play()}
	if	($ChangedID)
	{	if	($TogPlay)		{Play()}
		elsif	(defined $TogPlay)	{Stop()}
	}
	$ChangedID=$ChangedPos=0;
}

#sub UpdateSongID			#CHECKME use -1 instead of undef for Position ???
#{	my ($type,$ID,$force)=@_;
#::callstack(@_);
#	if ($type eq 'position')
#	{	if ($ID!=$Position || $force) { $ChangedPos=1; $Position=$ID; }
#		$ID=$ListPlay->[$ID];
#	}
#	if (!defined $ID)
#	{	$ChangedID=$ChangedPos=1;
#		$Position=$SongID=undef;
#		Stop();
#	}
#	elsif (!defined $SongID || $ID!=$SongID)
#	{	$ChangedID=1; $SongID=$ID;
#		IdleCheck($SongID) if $Options{TAG_auto_check_current};
#		if (defined $RecentPos && (!defined $SongID || $SongID!=$Recent->[$RecentPos-1])) { $RecentPos=undef }
#	}
#	if ($RandomMode) { $Position=undef; $ChangedPos=1; }
#	elsif ($type ne 'position' && (!defined $Position || $ListPlay->[$Position]!=$SongID))
#	{	my $start=$Position;
#		$Position=undef;
#		for my $i ($start+1..$#$ListPlay, 0..$start-1) {$Position=$i if $ListPlay->[$i]==$SongID}
#		$ChangedPos=1;
#	}
#	if ($ChangedID)
#	{	HasChanged('CurSong',$SongID);
#		ShowTraytip($Options{TrayTipTimeLength}) if $TrayIcon && $Options{ShowTipOnSongChange} && !$FullscreenWindow;
#	}
#	if ($ChangedPos)
#	{	HasChanged('Pos','song');
#	}
#	if ( $force || $ChangedID )
#	{	if	($TogPlay)		{Play()}
#		elsif	(defined $TogPlay)	{Stop()}
#	}
#	$ChangedID=$ChangedPos=0;
#}

sub IDIsInList
{	my ($list,$ID)=@_;
	return $list->IsIn($ID) unless ref $list eq 'ARRAY';
	($list->[$_]==$ID) and return 1 for 0..$#$list;
	return 0;
}
sub FindPositionSong	#DELME
{	my ($ID,$list)=@_;
	return undef unless defined $ID;
	for my $i (0..$#$list) {return $i if $list->[$i]==$ID}
	return undef;	#not found
}
sub FindFirstInListPlay		#Choose a song in @$lref based on sort order, if possible in the current playlist. In sorted order, choose a song after current song
{	my $lref=shift;
	my $sort=$Options{Sort};
	my $ID;
	my %h;
	$h{$_}=undef for @$lref;
	my @l=grep exists $h{$_}, @$ListPlay;
	if ($sort=~m/^random:/)
	{	$lref=\@l if @l;
		($ID)=Random->OneTimeDraw($sort,$lref,1);
		$ID=$lref->[ int(rand(scalar@$lref)) ] unless defined $ID;
	}
	else
	{	@l=@$lref unless @l;
		push @l,$SongID if defined $SongID && !exists $h{$SongID};
		SortList(\@l);
		if (defined $SongID)
		{ for my $i (0..$#l-1)
		   { next if $l[$i]!=$SongID; $ID=$l[$i+1]; last; }
		}
		$ID=$l[0] unless defined $ID;
	}
	return $ID;
}

sub Shuffle
{	Songs::ReShuffle() if $Options{Sort} eq 'shuffle';
	Select('sort' => 'shuffle');
}

sub SortList	#sort @$listref according to current sort order, or last ordered sort if no current sort order
{	my $listref=shift;
	my $sort=$Options{Sort};
	if ($sort=~m/^random:/)
	{	@$listref=Random->OneTimeDraw($sort,$listref);
	}
	else	# generate custom sort function
	{	$sort=$Options{Sort_LastOrdered} if $sort eq '';
		Songs::SortList($listref,$sort);
	}
}

sub ExplainSort
{	my ($sort,$usename)=@_;
	return _"no order" if $sort eq '';
	my $rand= $sort=~m/^random:/;

	if ($usename || $rand)
	{	my $h= $rand ? $Options{SavedWRandoms} : $Options{SavedSorts};
		for my $name (sort keys %$h)
		{	return $name if $h->{$name} eq $sort;
		}
	}
	if ($rand) { return _"unnamed random mode"; }	 #describe ?

	my @text;
	for my $f (split / /,$sort)
	{	my $field= $f=~s/^-// ? '-' : '';
		my $i= $f=~s/:i$//;
		$field.= Songs::FieldName($f);
		$field.=_"(case insensitive)" if $i;
		push @text,$field;
	}
	return join ', ',@text;
}

sub ReReadTags
{	my $state=Gtk2->get_current_event_state;
	if ( @_ && $state && $state >= ['shift-mask'] ) { $ToCheckLength->add(\@_); }
	else
	{	my $ref= @_ ? \@_ : $Library;
		$ToReRead->add($ref);
	}
	&launchIdleLoop;
}
sub CheckCurrentSong
{	return unless defined $::SongID;
	my $lengthcheck= $Options{LengthCheckMode} eq 'current' || $Options{LengthCheckMode} eq 'add' ? 2 : 0;
	Songs::ReReadFile($::SongID,$lengthcheck, !$Options{AutoRemoveCurrentSong} );
}
sub CheckLength
{	my $ref= @_ ? \@_ : Filter->new('length_estimated:e:1')->filter;
	$ToCheckLength->add($ref);
	&launchIdleLoop;
}
sub IdleCheck
{	my $ref= @_ ? \@_ : $Library;
	$ToCheck->add($ref);
	&launchIdleLoop;
}
sub IdleScan
{	@_=map decode_url($_), @{$Options{LibraryPath}} unless @_;
	push @ToScan,@_;
	&launchIdleLoop;
}

sub IdleDo
{	my $task_id=shift;
	my $timeout=shift;
	$ToDo{$task_id}=\@_;
	$TimeOut{$task_id}||=Glib::Timeout->add($timeout,\&DoTask,$task_id) if $timeout;
	&launchIdleLoop unless defined $IdleLoop;
}
sub DoTask
{	my $task_id=shift;
	delete $TimeOut{$task_id};
	my $aref=delete $ToDo{$task_id};
	if ($aref)
	{ my $sub=shift @$aref;
	  $sub->(@$aref);
	}
	0;
}

sub launchIdleLoop
{	$IdleLoop||=Glib::Idle->add(\&IdleLoop);
}

sub IdleLoop
{	if (@$ToCheck)
	{	CheckProgress_cb(1) unless $CheckProgress_cb;
		Songs::ReReadFile($ToCheck->next);
	}
	elsif (@$ToReRead)
	{	CheckProgress_cb(1) unless $CheckProgress_cb;
		Songs::ReReadFile($ToReRead->next,1);
	}
	elsif (@ToAdd_Files)  { SongAdd(shift @ToAdd_Files); }
	elsif (@ToAdd_IDsBuffer>1000)	{ SongAdd_now() }
	elsif (@ToScan) { $ProgressNBFolders++; ScanFolder(shift @ToScan); }
	elsif (@ToAdd_IDsBuffer)	{ SongAdd_now() }
	elsif (%ToDo)	{ DoTask( (sort keys %ToDo)[0] ); }
	elsif (@$ToCheckLength)	 #to replace estimated length/bitrate by real one(for mp3s without VBR header)
	{	CheckProgress_cb(1) unless $CheckProgress_cb;
		Songs::ReReadFile( $ToCheckLength->next, 3);
	}
	else
	{	$ProgressNBFolders=$ProgressNBSongs=0;
		undef $Songs::IDFromFile;

		warn "IdleLoop End\n" if $debug;
		undef $IdleLoop;
	}
	return $IdleLoop;
}

sub OpenBrowser
{	OpenSpecialWindow('Browser');
}
sub ContextWindow
{	OpenSpecialWindow('Context');
}
sub EditQueue
{	OpenSpecialWindow('Queue');
}
sub OpenSpecialWindow
{	my ($type,$toggle)=@_;
	my $layout= $type eq 'Browser' ? $Options{LayoutB} : $type;
	my $ifexist= $toggle ? 'toggle' : 'present';
	Layout::Window->new($layout, ifexist => $ifexist, uniqueid=>$type);
}

sub SetFullScreenMode
{	ToggleFullscreenLayout() if $_[0] xor $FullscreenWindow;
}
sub ToggleFullscreenLayout
{	if ($FullscreenWindow)
	{	$FullscreenWindow->close_window;
	}
	else
	{	$FullscreenWindow=Layout::Window->new($Options{LayoutF},fullscreen=>1);
		$FullscreenWindow->signal_connect(destroy => sub { $FullscreenWindow=undef; });
		if ($Options{StopScreensaver} && findcmd('xdg-screensaver'))
		{	my $h={ XID => $FullscreenWindow->window->XID};
			my $sub=sub
			 {	my $p=$TogPlay;
				$p=0 if $h->{destroy} || !$Options{StopScreensaver};
				if ($p xor $h->{ScreenSaverStopped})
				{	my $cmd= $p ? 'suspend' : 'resume';
					$cmd="xdg-screensaver $cmd ".$h->{XID};
					warn $cmd if $debug;
					system $cmd;
					$h->{ScreenSaverStopped}=$TogPlay;
				}
			 };
			&$sub();
			Watch($h, Playing=> $sub);
			$FullscreenWindow->signal_connect(destroy => sub { UnWatch($h,'Playing'); $h->{destroy}=1; &$sub(); });
		}
	}
	HasChanged('FullScreen',!!$FullscreenWindow);
}

sub WEditList
{	my $name=$_[0];
	my ($window)=grep exists $_->{editing_listname} && $_->{editing_listname} eq $name, Gtk2::Window->list_toplevels;
	if ($window) { $window->force_present; return; }
	$SongList::Common::EditList=$name; #list that will be used by SongList/SongTree in 'editlist' mode
	$window=Layout::Window->new('EditList', 'pos'=>undef);
	$SongList::Common::EditList=undef;
	$window->{editing_listname}=$name;
	Watch($window, SavedLists => sub	#close window if the list is deleted, update title if renamed
		{	my ($window,$name,$info,$newname)=@_;
			return if $window->{editing_listname} ne $name;
			return unless $info;
			my $songlist=$window->{widgets}{SongList};
			if ($info eq 'renamedto')
			{	$window->set_title( _("Editing list : ").$newname );
				$window->{editing_listname}=$newname;
			}
			elsif ($info eq 'remove')
			{	$window->close_window
			}
		});
	$window->set_title( _("Editing list : ").$name );
}

sub CalcListLength	#if $return, return formated string (0h00m00s)
{	my ($listref,$return)=@_;
	my ($size,$sec)=Songs::ListLength($listref);
	warn 'ListLength: '.scalar @$listref." Songs, $sec sec, $size bytes\n" if $debug;
	$size=sprintf '%.0f',$size/1024/1024;
	my $m=int($sec/60); $sec=sprintf '%02d',$sec%60;
	my $h=int($m/60);     $m=sprintf '%02d',$m%60;
	my $nb=@$listref;
	my @values=(hours => $h, min =>$m, sec =>$sec, size => $size);
	if ($return eq 'long')
	{	my $format= $h? _"{hours} hours {min} min {sec} s ({size} M)" : _"{min} min {sec} s ({size} M)";
		return __("%d Song","%d Songs",$nb) .', '. __x($format, @values);
	}
	elsif ($return eq 'short')
	{	my $format= $h? _"{hours}h {min}m {sec}s ({size}M)" : _"{min}m {sec}s ({size}M)";
		return __("%d Song","%d Songs",$nb) .', '.__x($format, @values);
	}
	elsif ($return eq 'queue')
	{	return _"Queue empty" if $nb==0;
		my $format= $h? _"{hours}h{min}m{sec}s" : _"{min}m{sec}s";
		return __("%d song in queue","%d songs in queue",$nb) .' ('. __x($format, @values) . ')';
	}
	else
	{	my $format= $h? _"{hours}h {min}m {sec}s ({size}M)" : _"{min}m {sec}s ({size}M)";
		return __x($format, @values);
	}
}

# http://www.allmusic.com/search/artist/%s    artist search
# http://www.allmusic.com/search/album/%s    album search
sub AMGLookup
{	my ($col,$key)=@_;
	my $opt1=	$col eq 'artist' ? 'artist' :
			$col eq 'album'  ? 'album' :
			$col eq 'title'	 ? 'song' : '';
	return unless $opt1;
	my $url='http://www.allmusic.com/search/'.$opt1.'/';
	$key=url_escape($key);
	openurl($url.$key);
}

sub Google
{	my $ID=shift;
	my $lang='';
	$lang="hl=$1&" if setlocale(LC_MESSAGES)=~m/^([a-z]{2})(?:_|$)/;
	my $url='http://google.com/search?'.$lang."q=";
	my @q=grep $_ ne '', Songs::Get($ID,qw/title_or_file artist album/);
	$url.=url_escape(join('+',@q));
	openurl($url);
}
sub openurl
{	my $url=shift;
	if ($^O eq 'MSWin32') { system "start $url"; return }
	$browsercmd||=findcmd($Options{OpenUrl},qw/xdg-open gnome-open firefox epiphany konqueror galeon/);
	unless ($browsercmd) { ErrorMessage(_"No web browser found."); return }
	$url=quotemeta $url;
	system "$browsercmd $url &"; #FIXME if xdg-open is used, don't launch with "&" and check error code
}
sub openfolder
{	my $dir=shift;
	if ($^O eq 'MSWin32') { system qq(start "$dir"); return } #FIXME if $dir contains "
	$opendircmd||=findcmd($Options{OpenFolder},qw/xdg-open gnome-open nautilus konqueror thunar/);
	unless ($opendircmd) { ErrorMessage(_"No file browser found."); return }
	$dir=quotemeta $dir;
	system "$opendircmd $dir &";
}
sub findcmd
{	for my $cmd (grep defined,@_)
	{	my $exe= (split / /,$cmd)[0];
		next unless grep -x $_.SLASH.$exe, split /:/, $ENV{PATH};
		return $cmd;
	}
	return undef;
}

sub ChooseAAPicture
{	my ($ID,$col,$key)=@_;
	my $path;
	if (defined $ID) { $path=Songs::Get($ID,'path'); }
	else
	{	my $h=Songs::BuildHash('path', AA::GetIDs($col,$key));
		my $min=int(.1*max(values %$h)); #ignore rare folders
		$path= ::find_common_parent_folder( grep $h->{$_}>$min,keys %$h );
		($path)=sort { $h->{$b} <=> $h->{$a} } keys %$h if length $path<5;#take most common if too differents
	}
	my $title= sprintf(_"Choose picture for '%s'",Songs::Gid_to_Display($col,$key));
	my $file=ChoosePix($path,$title, AAPicture::GetPicture($col,$key));
	AAPicture::SetPicture($col,$key,$file) if defined $file;
}

sub ChooseSongsTitle		#Songs with the same title
{	my $ID=$_[0];
	my $filter=Songs::MakeFilterFromID('title',$ID);
	my $list= $filter->filter;
	return 0 if @$list<2 || @$list>100;	#probably a problem if it finds >100 matching songs, and making a menu with a huge number of items is slow
	my @list=grep $_!=$ID,@$list;
	Songs::SortList(\@list,'artist:i album:i');
	return ChooseSongs( \@list, markup=> __x( _"by {artist} from {album}", artist => "<b>%a</b>", album => "%l")."<i>%V</i>"); #FIXME show version in a better way
}

sub ChooseSongsFromA	#FIXME limit the number of songs if HUGE number of songs (>100-200 ?)
{	my ($album,%opt)=@_;
	return unless defined $album;
	my $list= AA::GetIDs(album=>$album);
	Songs::SortList($list,'disc track file');
	if (Songs::Get($list->[0],'disc'))
	{	my $disc=''; my @list2;
		for my $ID (@$list)
		{	my $d=Songs::Get($ID,'disc');
			if ($d && $d ne $disc)
			{	push @list2,__x(_"disc {disc}",disc =>$d);
				$disc=$d;
				if (Songs::FieldEnabled('discname'))
				{	my $name=Songs::Get($ID,'discname');
					$list2[-1].=" : $name" if length $name;
				}
			}
			push @list2,$ID;
		}
		$list=\@list2;
	}
	my $menu = ChooseSongs($list, markup=>'%n %S<small>%V</small>', cb=>$opt{cb});
	$menu->show_all;
	unless ($opt{nocover})
	{	my $h=$menu->size_request->height;
		my $w=$menu->size_request->width;
		my $maxwidth= $menu->get_screen->get_width;
		my $cols= $menu->{cols};	#array containing the number of entries in each column of the menu
		my $nbcols= @$cols;
		my $height= max(@$cols);
		my $picsize= $w/$nbcols;
		if ($maxwidth > $picsize*($nbcols+1))  # check if fits in the screen
		{	$picsize=200 if $picsize<200 && $maxwidth > 200*($nbcols+1);
			#$picsize=$h if $picsize>$h;
			if ( my $img= AAPicture::newimg(album=>$album, $picsize) )
			{	my $item=Gtk2::MenuItem->new;
				$item->add($img);
				my $row0=0;
				if ($w>$h && $nbcols==1)	# if few songs put the cover below
				{	$nbcols=0;
					$row0= $height;
				}
				$menu->attach($item, $nbcols, $nbcols+1, $row0, $height+1);
				$item->signal_connect(enter_notify_event=> sub {1});
				$item->show_all;
			}
		}
	}

=old tests for cover
	elsif (0) #TEST not used
	{	my $picsize=$menu->size_request->height;
		$picsize=220 if $picsize>220;
		if ( my $img= AAPicture::newimg(album=>$album, $picsize) )
		{	my $item=Gtk2::MenuItem->new;
			$item->add($img);
			my $col= @{$menu->{cols}};
			#$menu->attach($item, $col, $col+1, 0, scalar @$list);
			$item->show_all;
	$menu->signal_connect(size_request => sub {my ($self,$req)=@_;warn $req->width;return if $self->{busy};$self->{busy}=1;my $rw=$self->get_toplevel->size_request->width;$self->get_toplevel->set_size_request($rw+$picsize,-1);$self->{busy}=undef;});
	my $sub=sub {my ($self,$alloc)=@_;warn $alloc->width;return if $self->{done};$alloc->width($alloc->width-$picsize/$col);$self->{done}=1;$self->size_allocate($alloc);};
	$_->signal_connect(size_allocate => $sub) for $menu->get_children;
		#		$item->signal_connect(size_allocate => sub  {my ($self,$alloc)=@_;warn $alloc->width;return if $self->{busy};$self->{busy}=1;my $w=$self->get_toplevel;$w->set_size_request($w->size_request->width-$alloc->width+$picsize+20,-1);$alloc->width($picsize+20);$self->size_allocate($alloc);});
		}
	}
	elsif ( my $pixbuf= AAPicture::pixbuf(album=>$album,undef,1) ) #TEST not used
	{
	 my $request=$menu->size_request;
	 my $rwidth=$request->width;
	 my $rheight=$request->height;
	 my $w=200;
	 #$w=500-$rwidth if $rwidth <300;
	 $w=300-$rwidth if $rwidth <100;
	 my $h=200;
	 $h=$rheight if $rheight >$h;
	 my $r= $pixbuf->get_width / $pixbuf->get_height;
	 #warn "max $w $h   r=$r\n";
	 if ($w>$h*$r)	{$w=int($h*$r);}
	 else		{$h=int($w/$r);}
	 my $h2=$rheight; $h2=$h if $h>$h2;
	 #warn "=> $w $h\n";
	 $pixbuf=$pixbuf->scale_simple($w,$h,'bilinear');
#	 $menu->set_size_request(1000+$rwidth+$w,$h2);

#	$menu->signal_connect(size_request => sub {my ($self,$req)=@_;warn $req->width;return if $self->{busy};$self->{busy}=1;my $rw=$self->get_toplevel->size_request->width;$self->get_toplevel->set_size_request($rw+$w,-1);$self->{busy}=undef;});

	 $menu->signal_connect(size_allocate => sub
		{	# warn join(' ', $_[1]->values);
			my ($self,$alloc)=@_;
			return if $self->{picture_added};
			$self->{picture_added}=1;

			my $window=$self->parent;
			$window->remove($self);
			my $hbox=Gtk2::HBox->new(0,0);
			my $frame=Gtk2::Frame->new;
			my $image=Gtk2::Image->new_from_pixbuf($pixbuf);
			$frame->add($image);
			$frame->set_shadow_type('out');
			$hbox->pack_start($self,0,0,0);
			$hbox->pack_start($frame,1,1,0);
			$window->add($hbox);
			$hbox->show_all;
			#$window->set_size_request($rwidth+$w,$h2);
			$self->set_size_request($rwidth,-1);
		});
	}
=cut

	if (defined wantarray)	{return $menu}
	PopupMenu($menu,usemenupos=>1);
}

sub ChooseSongs
{	my ($IDs,%opt)=@_;
	my @IDs=@$IDs;
	return unless @IDs;
	my $format = $opt{markup} || __x( _"{song} by {artist}", song => "<b>%t</b>%V", artist => "%a");
	my $lcallback= $opt{cb} || sub { Select(song => $_[1]) };
	my $menu = Gtk2::Menu->new;
	my $activate_callback=sub
	 {	my $item=shift;
		return if $item->get_submenu;
		my $ID=$item->{ID};
		if ($item->{middle}) { Enqueue($ID); }
		else { $lcallback->($item,$ID); }
	 };
	my $click_callback=sub
	 { my ($item,$event)=@_;
	   if	($event->button == 2)
	   {	$item->{middle}=1;
		my $state=Gtk2->get_current_event_state;
		if ( $state && ($state >= ['shift-mask'] || $state >= ['control-mask']) ) #keep the menu up if ctrl or shift pressed
		{	$item->parent->{keep_it_up}=1; $activate_callback->($item);
			return 1;
		}
	   }
	   elsif($event->button == 3)
	   {	my $submenu=BuildMenu(\@SongCMenu,{mode => 'P', IDs=> [$item->{ID}]});
		$submenu->show_all;
		$_[0]->set_submenu($submenu);
		#$submenu->signal_connect( selection_done => sub {$menu->popdown});
		#$submenu->show_all;
		#$submenu->popup(undef,undef,undef,undef,$event->button,$event->time);
		return 0; #return 0 so that the item receive the click and popup the submenu
	   }
	   return 0;
	 };

	my $event= Gtk2->get_current_event;
	my $screen= $event ? $event->get_screen : Gtk2::Gdk::Screen->get_default;
	my $item_sample= Gtk2::ImageMenuItem->new('X'x45);
	#my $maxrows=30; my $maxcols=3;
	my $maxrows=int(.8*$screen->get_height / $item_sample->size_request->height);
	my $maxcols=int(.7*$screen->get_width / $item_sample->size_request->width);
	$maxrows=20 if $maxrows<20;
	$maxcols=1 if $maxcols<1;
	my @columns=(0);
	if (@IDs<=$maxrows)
	{	@columns=(scalar @IDs);
	}
	else
	{	#create one column for each disc/category
		for my $i (0..$#IDs)
		{	if ($IDs[$i]!~m/^\d+$/ && $columns[-1]) { push @columns,0 }
			$columns[-1]++;
		}
		my @new=(0);
		if (@columns==1)	#one column => split it into multiple columns if too big
		{	my $rows= shift @columns;
			my $cols= POSIX::ceil($rows/$maxrows);
			$cols=$maxcols if $cols>$maxcols; #currently if too many songs, create taller columns, better for scrolling
			my $part= int($rows/$cols);
			my $left= $rows % $part;
			for my $c (1..$cols) { push @columns, $part+($c<=$left ? 1 : 0); }
		}
		else	#multiple columns => try to combine them
		{	my $c=0;
			my $r= $columns[$c++];
			while ($r)
			{	if ($new[-1]> 1.2*@IDs/$maxcols){ push @new,0; }
				if ($new[-1]+$r<$maxrows*1.1)	{ $new[-1]+=$r; $r=0 }
				elsif ($r<$maxrows*1.1)		{ push @new,$r; $r=0 }
				elsif ($new[-1]<$maxrows-2)	{ my $part= $maxrows-$new[-1]; $r-=$part; $new[-1]+=$part; }
				else { push @new,0; }
				$r ||= $columns[$c++];
			}
			@columns=@new if @new<=$maxcols; #too many columns => forget trying to combine categories, will use a submenu for each
		}
	}

	if (@columns>$maxcols) #use submenus if too many columns
	{	my $row=0;
		for my $c (@columns)
		{	my ($title,@songs)= splice @IDs,0,$c;
			my $item= Gtk2::MenuItem->new;
			my $label=Gtk2::Label->new_with_format("<b>%s</b>", $title);
			$label->set_max_width_chars(45);
			$label->set_ellipsize('end');
			$item->add($label);
			my $submenu= ChooseSongs(\@songs,markup=>$format);
			$item->set_submenu($submenu);
			$menu->attach($item, 0,1, $row,$row+1); $row++;
		}
		$menu->{cols}= [scalar @columns];
	}
	else
	{	my $row=0; my $col=0;
		for my $ID (@IDs)
		{   my $label=Gtk2::Label->new;
		    my $item;
		    if ($ID=~m/^\d+$/) #songs
		    {	$item=Gtk2::ImageMenuItem->new;
			$item->set_always_show_image(1);
			$label->set_alignment(0,.5); #left-aligned
			$label->set_markup( ReplaceFieldsAndEsc($ID,$format) );
			$item->{ID}=$ID;
			$item->signal_connect(activate => $activate_callback);
			$item->signal_connect(button_press_event => $click_callback);
			$item->signal_connect(button_release_event => sub { return 1 if delete $_[0]->parent->{keep_it_up}; 0; });
			#set_drag($item, source => [::DRAG_ID,sub {::DRAG_ID,$ID}]);
		    }
		    else	# "title" items
		    {	$item=Gtk2::MenuItem->new;
			$label->set_markup_with_format("<b>%s</b>",$ID);
			$item->signal_connect(enter_notify_event=> sub {1});
		    }
		    $label->set_max_width_chars(45);
		    $label->set_ellipsize('end');
		    $item->add($label);
		    $menu->attach($item, $col, $col+1, $row, $row+1);
		    if (++$row>=$columns[$col]) {$row=0;$col++;}
		}
		$menu->{cols}= \@columns;
	}

	my $update_icons= sub
	{	for my $item ($_[0]->get_children)
		{	my $ID=$item->{ID};
			next unless defined $ID;
			my $icon= Get_PPSQ_Icon($ID) || '';
			next unless $icon || $item->get_image;
			$item->set_image( Gtk2::Image->new_from_stock($icon,'menu') );
		}
	};
	::Watch($menu,$_,$update_icons) for qw/CurSongID Playing Queue/; #update queue/playing icon when needed
	$update_icons->($menu);

	if (defined wantarray)	{return $menu}
	PopupMenu($menu);
}

sub PopupAA
{	my ($field,%args)=@_;
	my ($list,$from,$callback,$format,$widget,$nosort,$nominor,$noalt)=@args{qw/list from cb format widget nosort nominor noalt/};
	return undef unless @$Library;
	my $isaa= $field eq 'album' || $field eq 'artist' || $field eq 'artists';
	$format||="%a"; # "<b>%a</b>%Y\n<small>%s <small>%l</small></small>"

#### make list of albums/artists
	my @keys;
	if (defined $list) { @keys=@$list; }
	elsif ($isaa && defined $from)
	{	if ($field eq 'album')
		{ my %alb;
		  $from=[$from] unless ref $from;
		  for my $artist (@$from)
		  {	push @{$alb{$_}},$artist for @{ AA::GetXRef(artists=>$artist) };  }
		  #{	$alb{$_}=undef for @{ AA::GetXRef(artist=>$artist) };  }
		  #@keys=keys %alb;
		  my %art_keys;
		  while (my($album,$list)=each %alb)
		  {	my $artist=join ' & ',map Songs::Gid_to_Display('artist',$_), @$list; #FIXME PHASE1
			push @{$art_keys{$artist}},$album;
		  }
		  if (1==keys %art_keys)
		  {	@keys=@{ $art_keys{ (keys %art_keys)[0] } };
		  }
		  else	#multiple artists -> create a submenu for each artist
		  {	my $menu=Gtk2::Menu->new;
			for my $artist (keys %art_keys)
			{	my $item=Gtk2::MenuItem->new_with_label($artist);
				$item->set_submenu(PopupAA('album', %args, list=> $art_keys{$artist}));
				$menu->append($item);
			}
			if (defined wantarray) {return $menu}
			PopupMenu($menu);
			return;
		  }
		}
		else
		{ @keys= @{ AA::GetXRef(album=>$from) }; }
	}
	else { @keys=@{ AA::GetAAList($field) }; }

#### callbacks
	my $maincallback=sub		#jump to first song
	   {	my ($item,$key)=@_;
		return if $item->get_submenu;
		my $IDs=AA::GetIDs($field,$key);
		if ($item->{middle})	{ Enqueue(@$IDs); }	#enqueue artist/album on middle-click
		else
		{	my $ID=FindFirstInListPlay( $IDs );
			Select(song => $ID);
		}
	   };
	$maincallback= sub { my ($item,$key)=@_; return if $item->get_submenu; $callback->( {menuitem=>$item,field=>$field,key=>$key,filter=>Songs::MakeFilterFromGID($field,$key)} ); } if $callback;
	my $songcb= $callback ? sub { my ($item,$ID)=@_; $callback->( {menuitem=>$item,field=>'id',key=>$ID,filter=>Songs::MakeFilterFromID('title',$ID)} ); } : undef;
	my $altcallback= $field eq 'album' && !$noalt ?
		sub	#Albums button-press event : set up a songs submenu on right-click, alternate action on middle-click
		{	my ($item,$event,$key)=@_;
			if ($event->button==3)
			{	my $submenu=ChooseSongsFromA($key,nocover=>1,cb=>$songcb);
				$item->set_submenu($submenu);
			}
			elsif ($event->button==2) { $item->{middle}=1; }
			0; #return 0 so that the item receive the click and popup the submenu
		}:
		$isaa && !$noalt ?
		sub	#Artists button-press event : set up an album submenu on right-click, alternate action on middle-click
		{	my ($item,$event,$key)=@_;
			if ($event->button==3)
			{	my $submenu=PopupAA('album', from=>$key, cb=>$args{cb});
				$item->set_submenu($submenu);
			}
			elsif ($event->button==2) { $item->{middle}=1; }
			0;
		}:
		sub	#not album nor artist
		{	my ($item,$event,$key)=@_;
			if ($event->button==2) { $item->{middle}=1; }
			0;
		};

	my $event=Gtk2->get_current_event;
	my $screen= $widget ? $widget->get_screen : $event ? $event->get_screen : Gtk2::Gdk::Screen->get_default;
	my $max= .7*$screen->get_height;
	my $maxwidth=.15*$screen->get_width;
	#my $minsize=Gtk2::ImageMenuItem->new('')->size_request->height;

	my $createAAMenu=sub
	{	my ($start,$end,$names,$keys)=@_;
		my $nb=$end-$start+1;
		return unless $nb;
		my $cols= $nb<$max/32 ? 1 : $nb<$max/32 ? 2 : 3;
		my $rows=int($nb/$cols);
		my $size= $max/$rows < 90 ? 32 : $max/$rows < 200 ? 64 : 128; # choose among 3 possible picture sizes, trying to keep the menu height reasonable
		my $maxwidth= $cols==1 ? $maxwidth*1.5 : $maxwidth;
		my $row=0; my $col=0;
		my $menu = Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $key=$keys->[$i];
			my $item=Gtk2::ImageMenuItem->new;
			$item->set_always_show_image(1); # to override /desktop/gnome/interface/menus_have_icons gnome setting
			my $label=Gtk2::Label->new;
			$label->set_alignment(0,.5);
			$label->set_markup( AA::ReplaceFields($key,$format,$field,1) );
			my $req=$label->size_request->width;
			if ($label->size_request->width>$maxwidth) { $label->set_size_request($maxwidth,-1); } #FIXME doesn't work as I want, used to force wrapping at a smaller width than default, but result in requesting $maxwidth when the width of the wrapped text may be significantly smaller
			$label->set_line_wrap(TRUE);
			$item->add($label);
			$item->signal_connect(activate => $maincallback,$key);
			$item->signal_connect(button_press_event => $altcallback,$key) if $altcallback;
			#$menu->append($item);
			$menu->attach($item, $col, $col+1, $row, $row+1); if (++$row>$rows) {$row=0;$col++;}
			if ($isaa)
			{	my $img=AAPicture::newimg($field,$key,$size);
				$item->set_image($img) if $img;
			}
		}
		return $menu;
	}; #end of createAAMenu

	my $min= $field eq 'album' ? $Options{AlbumMenu_min} : $isaa ? $Options{ArtistMenu_min} : 0;
	$min=0 if $nominor;
	my @keys_minor;
	if ($min)
	{	@keys= grep {  @{ AA::GetAAList($field,$_) }>$min or push @keys_minor,$_ and 0 } @keys;
		if (!@keys) {@keys=@keys_minor; undef @keys_minor;}
	}

	Songs::sort_gid_by_name($field,\@keys) unless $nosort;
	my @names=@{Songs::Gid_to_Display($field,\@keys)}; #convert @keys to list of names

	my @common_args= (widget=>$widget, makemenu=>$createAAMenu, cols=>3, height=>32+2);
	my $menu=Breakdown_List(\@names, keys=>\@keys, @common_args);
	return undef unless $menu;
	if (@keys_minor)
	{	Songs::sort_gid_by_name($field,\@keys_minor) unless $nosort;
		my @names=@{Songs::Gid_to_Display($field,\@keys)};
		my $item=Gtk2::MenuItem->new('minor'); #FIXME
		my $submenu=Breakdown_List(\@names, keys=>\@keys_minor, @common_args);
		$item->set_submenu($submenu);
		$menu->append($item);
	}

	$menu->show_all;
	if (defined wantarray) {return $menu}
	PopupMenu($menu);
}

sub Breakdown_List
{	my ($names,%options)=@_;
	my ($min,$opt,$max,$makemenu,$keys,$widget)=@options{qw/min opt max makemenu keys widget/};
	$widget ||= Gtk2->get_current_event; #used to find current screen
	my $screen= $widget ? $widget->get_screen : Gtk2::Gdk::Screen->get_default; # FIXME is that ok for multi-monitors ?
	my $maxheight= $screen->get_height;


	if (!$min || !$opt || !$max) #find minimum/optimum/maximum number of entries that the menu/submenus should have
	{	my $height=$options{height};
		if (!$height) { my $dummyitem=Gtk2::MenuItem->new("dummy"); $height=$dummyitem->size_request->height; }
		my $maxnb= $maxheight/$height;
		$maxnb=10 if $maxnb<10; #probably shouldn't happen, in case number too low assume the screen can fit 10 items
		my $cols= $options{cols}||1;
		$max= int($maxnb*.8)*($cols**.9);	# **9 to reduce max height and optimum height when using columns
		$opt= int($maxnb*.65)*($cols**.9);
		$min= int($maxnb*.3)*$cols;
	}

	# short-cut if no need to create sub-menus
	if ($#$names<=$max) { return $makemenu ? $makemenu->(0,$#$names,$names,$keys) : [0,$#$names] }

	# check if needs more than 1 level of submenus
	if ($makemenu && !$options{norecurse})
	{	my $dummyitem=Gtk2::MenuItem->new("dummy");
		my $height=$dummyitem->size_request->height;
		my $parentopt= .65*$maxheight/$height;
		$parentopt=.65*10 if $parentopt<.65*10; #probably shouldn't happen, in case number too low assume the screen can fit 10 items
		if ($#$names > $parentopt*$opt)
		{	my @childarg=(%options,min=>$min,opt=>$opt,max=>$max,makemenu=>$makemenu,norecurse=>1);
			$min*=$parentopt; $max*=$parentopt; $opt*=$parentopt;
			$makemenu= sub
			{	my ($start,$end,$names,$keys)=@_;
				my @names2=@$names[$start..$end];
				my $keys2;
				@$keys2= @$keys[$start..$end] if $keys && @$keys;
				Breakdown_List(\@names2,@childarg,keys=>$keys2);
			};
		}
	}

	my @bounds;
	for my $start (0..$#$names)
	{	my $name1= $start==0 ?  '' : superlc($names->[$start-1]);
		my $name2= superlc($names->[$start]);
		my $name3= $start==$#$names ?  '' : superlc($names->[$start+1]);
		my ($c1,$c3); my $pos=0;
		until (defined $c1 && defined $c3)
		{	my $l2=substr $name2,$pos,1;
			unless (defined $c1)
			{	my $l1=substr $name1,$pos,1;
				$c1=substr $name2,0,$pos+1 unless defined $l1 &&  $l1 eq $l2 && $pos<length $name2;
			}
			unless (defined $c3)
			{	my $l3=substr $name3,$pos,1;
				$c3=substr $name2,0,$pos+1 unless defined $l3 &&  $l3 eq $l2 && $pos<length $name2;
			}
			$pos++;
		}
		push @bounds,[$c1,$c3];
	}

	my @chunk;
	my @toobig=(1)x@bounds;
	my $len=1;
	# calculate size of chunks for a max length of $len and redo with $len++ for chunks too big (>$max)
	{	my $c=0;
		for my $pos (0..$#bounds)
		{	if (length $bounds[$pos][0]<=$len) {$c=0} else {$c++}
			$chunk[$pos]=$c if $toobig[$pos];
		}
		$c=0;
		for my $pos (reverse 0..$#bounds)
		{	if ($pos==$#bounds || length $bounds[$pos+1][0]<=$len) {$c=0} else {$c++}
			if ($toobig[$pos])
			{	$chunk[$pos]+=$c+1;
				$toobig[$pos]=0 unless $chunk[$pos]>$max*.4;
			}
		}
		#for my $pos (0..$#bounds)	#DEBUG
		#{	print "(pos=$pos) $len|| $bounds[$pos][0] $bounds[$pos][1] $chunk[$pos]\n";
		#}
		$len++;
		redo if grep $_, @toobig;
	}
	my @breakpoints=(0); my @length=(0);
	my $pos=0;
	push @bounds,[' ']; #so that $bounds[$pos][0] is defined even for the last iteration of the loop
	while ($pos<@chunk)
	{	my $size=$chunk[$pos];
		$pos+=$size;
		push @breakpoints,$pos;
		push @length,length $bounds[$pos][0];
		#print "$#length : ".$bounds[$pos-1][1]."->'$bounds[$pos][0]' len=".(length $bounds[$pos][0])." (pos=$pos)\n"; #DEBUG
	}
#	push @breakpoints,$#$names+1; push @length,1;


	# find best combination of chunks
	# @todo will contain path that need exploring, put in $final when finished,
	# as each breakpoint is explored, only the best path is kept among those that used this breakpoint
	my @todo= ([0]); #start with breakpoint 0
	my $final;
	my @bestscore=(0);
	while (@todo)
	{	my $path0=shift @todo;
		my $i0= $path0->[-1];
		my $score0= $bestscore[$i0];
		for my $i ($i0+1 .. $#breakpoints)
		{	my $nb=$breakpoints[$i]-$breakpoints[$i0];
			next if $nb<$min && $i<$#breakpoints;
			my $malus=	$nb>$max ? 50*($nb-$max)**2 :
					$nb<$min ? 20*($min-$nb)**2 : 0;
			my $score= $score0 + $length[$i]*200 + abs($nb-$opt) + $malus;
			if ($bestscore[$i]) #if a path already used that breakpoint, compare the score
			{	next if $bestscore[$i]<$score; # ignore the new path if not better
				#new path has a better score => remove all paths that used that breakpoint
				@todo=grep {!grep $_==$i, @$_} @todo; # could use smart match but deprecated : @todo=grep !($i~~@$_), @todo;
			}
			$bestscore[$i]=$score;
			my $path= [@$path0,$i];
			my $nbafter=$#$names-$breakpoints[$i]+1;
			if ($nbafter==0) {$final=$path} else {push @todo,$path}
			last if $nb>$max && $nbafter>$min;
		}
	}
	shift  @$final; #remove the starting 0
	@breakpoints= map $breakpoints[$_], @$final;
	#warn "min=$min opt=$opt max=$max\n". "sizes: ".join(',',map $breakpoints[$_]-$breakpoints[$_-1], 1..$#breakpoints)."\n";

	# build @menu result with for each item : start and end position, start and end letters
	my @menus; my $start=0;
	for my $end (@breakpoints)
	{	my $c1=$bounds[$start][0];
		my $c2=$bounds[$end-1][1];
		for my $i (0..length($c1)-1)
		{	my $c2i=substr $c2,$i,1;
			if ($c2i eq '') { $c2.=$c2i= superlc(substr $names->[$end-1],$i,1); }
			last if substr($c1,$i,1) ne $c2i;
		}
		push @menus,[$start,$end-1,$c1,$c2];
		$start=$end;
	}

	return @menus unless $makemenu;
	my $menu;
	if (@menus>1)
	{	$menu=Gtk2::Menu->new;
		# jump to entry when a letter is pressed
		$menu->signal_connect(key_press_event => sub
		 {	my ($menu,$event)=@_;
			my $unicode=Gtk2::Gdk->keyval_to_unicode($event->keyval); # 0 if not a character
			if ($unicode)
			{	my $chr=uc chr $unicode;
				for my $item ($menu->get_children)
				{	if ($chr ge uc$item->{start} && $chr le uc$item->{end})
					{	$menu->select_item($item);
						return 1;
					}
				}
			}
			0;
		 });
		# Build menu items and submenus
		for my $ref (@menus)
		{	my ($start,$end,$c1,$c2)=@$ref;
			$c1=ucfirst$c1; $c2=ucfirst$c2;
			$c1.='-'.$c2 if $c2 ne $c1;
			my $item=Gtk2::MenuItem->new_with_label($c1);
			$item->{start}= substr $c1,0,1;
			$item->{end}=   substr $c2,0,1;
			$item->{menuargs}= [$start,$end,$names,$keys];
			# only build submenu when the item is selected
			$item->signal_connect(activate => sub
				{	my $args=delete $_[0]{menuargs};
					return unless $args;
					my $submenu= $makemenu->(@$args);
					$item->set_submenu($submenu);
					$submenu->show_all;
				});
			#my $submenu= $makemenu->($start,$end,$names,$keys);
			#$item->set_submenu($submenu);
			$item->set_submenu(Gtk2::Menu->new);
			$menu->append($item);
		}
	}
	elsif (@menus==1) { $menu= $makemenu->(0,$#$names,$names,$keys); }
	else {return undef}

	return $menu;
}

sub BuildToolbar
{	my ($tbref,%args)=@_;
	my $toolbar=Gtk2::Toolbar->new;
	$toolbar->set_style( $args{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $args{ToolbarSize}||'small-toolbar' );
	$toolbar->{tbref}= $tbref;
	$toolbar->{getcontext}= $args{getcontext} || sub {};
	my @update;
	for my $i (@$tbref)
	{	my $toggle= $i->{toggle} || $i->{toggleoption};
		my $item;
		if (my $stock=$i->{stockicon})
		{	if ($toggle)	{ $item= Gtk2::ToggleToolButton->new_from_stock($stock); }
			else		{ $item= Gtk2::ToolButton->new_from_stock($stock); }
		}
		elsif (my $widget=$i->{widget})
		{	$widget= $item= $widget->(\%args);
			$item= Gtk2::ToolItem->new;
			$item->add($widget);
		}
		next unless $item;

		$item->set_is_important(1) if $i->{important};
		my $label= $i->{label};
		$label=$label->(\%args) if ref $label;
		$item->set_label($label) if $label && $item->isa('Gtk2::ToolButton');
		my $tip=$i->{tip} || $label;
		$tip=$tip->(\%args) if ref $tip;
		$item->set_tooltip_text($tip) if $tip;

		if ($toggle)
		{	my $active;
			if (ref $toggle) { $active= $toggle->(\%args); }
			else
			{	my ($not,$ref)=ParseKeyPath(\%args,$toggle);
				$item->{toggleref}= $ref;
				$item->{togglerefnot}= $not;
				$active= ($$ref xor $not);
			}
			$item->set_active(1) if $active;
		}
		if (my $cb=$i->{cb})
		{	my $sub= sub
			 {	my $toolbar=$_[0]->parent;
				return if $toolbar->{busy};
				if (my $ref=$_[0]->{toggleref}) { $$ref^=1 }
				$cb->({$toolbar->{getcontext}($toolbar)})
			 };
			if ($toggle) { $item->signal_connect(toggled => $sub); }
			else { $item->signal_connect(clicked => $sub); }
		}
		$toolbar->insert($item,-1);
		if (my $key=$i->{keyid}||="$i") { $toolbar->{$key}=$item; }
	}
	return $toolbar;
}
sub UpdateToolbar
{	my $toolbar=shift;
	my $tbref= $toolbar->{tbref};
	my $args= {$toolbar->{getcontext}->($toolbar)};
	$toolbar->{busy}=1;
	for my $i (@$tbref)
	{	my $key=$i->{keyid};
		my $item=$toolbar->{$key};
		next unless $item;
		if (my $ref=$item->{toggleref}) { $item->set_active($$ref xor $item->{togglerefnot}); }
		elsif (my $toggle=$i->{toggle}) { $item->set_active( $toggle->($args) ); }
	}
	delete $toolbar->{busy};
}

sub ParseKeyPath
{	my ($ref,$keypath)=@_;
	my $not= $keypath=~s/^!//;
	my @parents= split /\//,$keypath;
	my $last=pop @parents;
	for my $key (@parents)
	{	$ref= $ref->{$key};
		if (!ref $ref) { $ref={}; warn "ParseKeyPath error keypath=$keypath invalid\n"; last }
	}
	return $not, \$ref->{$last};
}

sub BuildMenu
{	my ($mref,$args,$menu)=@_;
	$args ||={};
	$menu ||= Gtk2::Menu->new; #append to menu if menu given as agrument
	for my $m (@$mref)
	{	next if $m->{ignore};
		next if $m->{type}	&& index($args->{type},	$m->{type})==-1;
		next if $m->{mode}	&& index($m->{mode},	$args->{mode})==-1;
		next if $m->{notmode}	&& index($m->{notmode},	$args->{mode})!=-1;
		next if $m->{isdefined}	&&   grep !defined $args->{$_}, split /\s+/,$m->{isdefined};
		#next if $m->{notdefined}&&   grep defined $args->{$_}, split /\s+/,$m->{notdefined};
		next if $m->{istrue}	&&   grep !$args->{$_}, split /\s+/,$m->{istrue};
		next if $m->{isfalse}	&&   grep $args->{$_},  split /\s+/,$m->{isfalse};
		next if $m->{empty}	&& (  $args->{ $m->{empty} }	&& @{ $args->{ $m->{empty}   } }!=0 );
		next if $m->{notempty}	&& ( !$args->{ $m->{notempty} }	|| @{ $args->{ $m->{notempty}} }==0 );
		next if $m->{onlyone}	&& ( !$args->{ $m->{onlyone}  }	|| @{ $args->{ $m->{onlyone} } }!=1 );
		next if $m->{onlymany}	&& ( !$args->{ $m->{onlymany} }	|| @{ $args->{ $m->{onlymany}} }<2  );
		next if $m->{test}	&& !$m->{test}($args);

		if (my $mod=$m->{change_input}) { $args={ %$args, @$mod };next } #modify $args for next menu entries

		my $label=$m->{label};
		$label=$label->($args) if ref $label;
		my $item;
		if ($m->{separator})
		{	$item=Gtk2::SeparatorMenuItem->new;
		}
		elsif (my $icon=$m->{stockicon})
		{	$item=Gtk2::ImageMenuItem->new($label);
			$icon= $icon->($args) if ref $icon;
			$item->set_image( Gtk2::Image->new_from_stock($icon,'menu') );
		}
		elsif (my $keypath=$m->{toggleoption})
		{	$item=Gtk2::CheckMenuItem->new($label);
			my ($not,$ref)=ParseKeyPath($args,$keypath);
			$item->{toggleref}= $ref;
			$item->set_active(1) if $$ref xor $not;
		}
		elsif ( ($m->{check} || $m->{radio}) && !$m->{submenu})
		{	$item=Gtk2::CheckMenuItem->new($label);
			my $func= $m->{check} || $m->{radio};
			$item->set_active(1) if $func->($args);
			$item->set_draw_as_radio(1) if $m->{radio};
		}
		elsif ( my $include=$m->{include} ) #append items made by $include
		{	$include= $include->($args,$menu) if ref $include eq 'CODE';
			if (ref $include eq 'ARRAY') { BuildMenu($include,$args,$menu); }
			next;
		}
		elsif ( my $repeat=$m->{repeat} )
		{	my @menus= $repeat->($args);
			for my $submenu (@menus)
			{	my ($menuarray,@extra)=@$submenu;
				BuildMenu($menuarray,{%$args,@extra},$menu);
			}
			next;
		}
		else	{ $item=Gtk2::MenuItem->new($label); }

		if (my $i=$m->{sensitive}) { $item->set_sensitive(0) unless $i->($args) }
		if (my $id=$m->{id}) {$item->{id}=$id}

		if (my $submenu=$m->{submenu})
		{	$submenu=$submenu->($args) if ref $submenu eq 'CODE';
			if ($m->{code}) { $submenu=BuildChoiceMenu($submenu, %$m, args=>$args); }
			elsif (ref $submenu eq 'ARRAY') { $submenu=BuildMenuOptional($submenu,$args); }
			next unless $submenu;
			if (my $append=$m->{append})	#append to submenu
			{	BuildMenu($append,$args,$submenu);
			}
			$item->set_submenu($submenu);
		}
		else
		{	$item->{code}=$m->{code};
			$item->signal_connect (activate => sub
				{	my ($self,$args)=@_;
					if (my $ref=$self->{toggleref}) { $$ref^=1 }
					my $on; $on=$self->get_active if $self->isa('Gtk2::CheckMenuItem');
					if (my $code=$self->{code})
					{	if (ref $code) { $code->($args,$on); }
						else { run_command(undef,$code); }
					}
				},$args);
			if (my $submenu3=$m->{submenu3})	# set a submenu on right-click
			{	$submenu3= BuildMenu($submenu3,$args);
				$item->signal_connect (button_press_event => sub { my ($item,$event,$submenu3)=@_; return 0 unless $event->button==3; $item->{code}=undef;  $item->set_submenu($submenu3); $submenu3->show_all; 0;  },$submenu3);
			}
			elsif (my $code3=$m->{code3})		# alternate action on right-click
			{	$item->signal_connect (button_press_event => sub { my ($item,$event,$code3)=@_; $item->{code}=$code3 if $event->button==3; 0;  }, $code3);
			}
		}
		$menu->append($item);
	}
	return $menu;
}
sub BuildMenuOptional
{	my $menu= &BuildMenu;
	return $menu->get_children ? $menu : undef;
}
sub PopupContextMenu
{	my $args=$_[1];
	my $menu=BuildMenu(@_);
	PopupMenu($menu,nomenupos=>!$args->{usemenupos},self=>$args->{self});
}

sub PopupMenu
{	my ($menu,%args)=@_;
	return unless $menu->get_children;
	$menu->show_all;
	my $event= $args{event} || Gtk2->get_current_event;
	my $widget= $args{self} || Gtk2->get_event_widget($event);
	$menu->attach_to_widget($widget,undef) if $widget && !$menu->get_attach_widget;
	my $posfunction= $args{posfunction}; # usually undef
	my $button=my $time=0;
	if ($event)
	{	$time= $event->time;
		$button= $event->button if $event->isa('Gtk2::Gdk::Event::Button');
		if (!$posfunction && !$args{nomenupos} && $event->window)
		{	my ($w,$h)= $event->window->get_size;
			$posfunction=\&menupos if $h<300; #ignore the event's widget if too big, widget can be the whole window if coming from a shortcut key, it makes no sense poping-up a menu next to the whole window
		}
	}
	$menu->popup(undef,undef,$posfunction,undef,$button,$time);
}
sub menupos	# function to position popupmenu below clicked widget
{	my $event=Gtk2->get_current_event;
	my $w=$_[0]->size_request->width;		# width of menu to position
	my $h=$_[0]->size_request->height;		# height of menu to position
	my $ymax=$event->get_screen->get_height;	# height of the screen
	my ($x,$y)=$event->window->get_origin;		# position of the clicked widget on the screen
	my ($dw,$dy)=$event->window->get_size;		# width and height of the clicked widget
	if ($dy+$y+$h > $ymax)  { $y-=$h; $y=0 if $y<0 }	# display above the widget
	else			{ $y+=$dy; }			# display below the widget
	if ($event->isa('Gtk2::Gdk::Event::Button'))
	{	if ($w < $dw && $event->x -$w > 100) # if mouse horizontally far from menu, try to position it closer
		{	my $newx= $event->x - .5*$w;
			#$newx= 0 if $newx<0;
			$newx= $dw-$w if $newx>$dw-$w;
			$x+=$newx;
		}
	}
	return $x,$y;
}

sub BuildChoiceMenu
{	my ($choices,%options)=@_;
	my $menu= delete $options{menu} || Gtk2::Menu->new;	# append items to an existing menu or create a new menu
	my $args= $options{args};
	my $tree=		$options{submenu_tree}		|| $options{tree};
	my $reverse=		$options{submenu_reverse}	|| $options{'reverse'}		|| $tree;
	my $ordered_hash=	$options{submenu_ordered_hash}	|| $options{ordered_hash}	|| $tree;
	my $firstkey=		$options{first_key};	#used to put one of the choices on top
	my (@labels,@values);
	if ($ordered_hash)
	{	my $i=0;
		while ($i<$#$choices)
		 { push @labels,$choices->[$i++]; push @values,$choices->[$i++]; }
	}
	elsif (ref $choices eq 'ARRAY')	{@labels=@values=@$choices}
	else				{@labels=keys %$choices; @values=values %$choices;}
	if ($reverse) { my @t=@values; @values=@labels; @labels=@t; }
	my @order= 0..$#labels;
	@order=sort {superlc($labels[$a]) cmp superlc($labels[$b])} @order if ref $choices eq 'HASH' || $tree;

	my $selection;
	my $smenu_callback=sub
	 {	my $sub=$_[1];
		my $selected= $_[0]{selected};
		if ($selection && $options{return_list})
		{	$selection->{$selected} ^=1;
			$selected= [sort grep $selection->{$_}, keys %$selection];
		}
		$sub->($args, $selected);
	 };
	my ($check,$radio);
	$check= $options{check}($args) if $options{check};
	if (defined $check)
	{	$selection={};
		if (ref $check)	{ $selection->{$_}=1 for @$check; }
		else
		{	$radio=1 unless $options{radio_as_checks};
			$selection->{$check}=1;
		}
	}
	for my $i (@order)
	{	my $label=$labels[$i];
		my $value=$values[$i];
		my $item=Gtk2::MenuItem->new_with_label($label);
		if (ref $value && $tree)
		{	my $submenu= BuildChoiceMenu( $value, %options );
			next unless $submenu;
			$item->set_submenu($submenu);
		}
		else
		{	if ($selection)
			{	$item=Gtk2::CheckMenuItem->new_with_label($label);
				$item->set_active(1) if $selection->{$value};
				$item->set_draw_as_radio(1) if $radio;
			}
			$item->{selected}= $value;
			$item->signal_connect(activate => $smenu_callback, $options{code} );
		}
		$item->child->set_markup( $item->child->get_label ) if $options{submenu_use_markup};
		if (defined $firstkey && $firstkey eq $value) { $menu->prepend($item); }
		else { $menu->append($item); }
	}
	$menu=undef unless @order; #empty submenu
	return $menu;
}

sub set_drag
{	my ($widget,%params)=@_;
	if (my $dragsrc=$params{source})
	{	( my $type, $widget->{dragsrc} )= @$dragsrc;
		$widget->drag_source_set( ['button1-mask'],['copy','move'],
			map [ $DRAGTYPES[$_][0], [] , $_ ], $type,
				keys %{$DRAGTYPES[$type][1]} );
		$widget->signal_connect(drag_data_get => \&drag_data_get_cb);
		$widget->signal_connect(drag_begin => \&drag_begin_cb);
		$widget->signal_connect(drag_end => \&drag_end_cb);
	}
	if (my $dragdest=$params{dest})
	{	my @types=@$dragdest;
		$widget->{dragdest}= pop @types;
		$widget->drag_dest_set(	'all',['copy','move'],
			map [ $DRAGTYPES[$_][0], ($_==DRAG_ID ? 'same-app' : []) , $_ ], @types );
		$widget->signal_connect(drag_data_received => \&drag_data_received_cb);
		$widget->signal_connect(drag_leave => \&drag_leave_cb);
		$widget->signal_connect(drag_motion => $params{motion}) if $params{motion}; $widget->{drag_motion_cb}=$params{motion};
	}
}

sub drag_begin_cb	#create drag icon
{	my ($self,$context)=@_;# warn "drag_begin_cb @_";
	$self->signal_stop_emission_by_name('drag_begin');
	$self->{drag_is_source}=1;
	my $sub= $self->{dragsrc};
	my ($srcinfo,@values)=&$sub($self);
	unless (@values) { $context->abort($context->start_time); return; } #FIXME no data -> should abort the drag
	$context->{data}=\@values;
	$context->{srcinfo}=$srcinfo;
	my $plaintext;
	{	$sub=$DRAGTYPES[$srcinfo][1]{&DRAG_MARKUP};
		last if $sub;
		$plaintext=1;
		$sub=$DRAGTYPES[$srcinfo][1]{&DRAG_USTRING};
		last if $sub;
		$sub=sub { join "\n",@_ };
	}
	my $text=&$sub(@values);
	###### create pixbuf from text
	return if !defined $text || $text eq '';
	my $layout=Gtk2::Pango::Layout->new( $self->create_pango_context );
	if ($plaintext) { $layout->set_text($text);   }
	else		{ $layout->set_markup($text); }
	my $PAD=3;
	my ($w,$h)=$layout->get_pixel_size; $w+=$PAD*2; $h+=$PAD*2;
	my $pixmap = Gtk2::Gdk::Pixmap->new($self->window,$w,$h,-1);
	my $style=$self->style;
	$pixmap->draw_rectangle($style->bg_gc('normal'),TRUE,0,0,$w,$h);
	$pixmap->draw_rectangle($style->fg_gc('normal'),FALSE,0,0,$w-1,$h-1);
	$pixmap->draw_layout(   $style->text_gc('normal'), $PAD, $PAD, $layout);
	$context->set_icon_pixmap($pixmap->get_colormap,$pixmap,undef,$w/2,$h);
	######
	$self->{drag_begin_cb}($self,$context) if $self->{drag_begin_cb};
}
sub drag_end_cb
{	shift->{drag_is_source}=undef;
}
sub drag_leave_cb
{	my ($self,$context)=@_;
	delete $self->{scroll};
	delete $self->{context};
}

sub drag_data_get_cb
{	my ($self,$context,$data,$destinfo,$time)=@_; #warn "drag_data_get_cb @_";
	#my $sub= $self->{dragsrc};
	return unless $context->{data};
	my @values=@{ $context->{data} };#my @values=$sub->($self); return unless @values;
	my $srcinfo=$context->{srcinfo};
	if ($destinfo != $srcinfo)
	{	my $convsub=$DRAGTYPES[$srcinfo][1]{$destinfo};
		if ($destinfo==DRAG_STRING) { my $sub=$DRAGTYPES[$srcinfo][1]{DRAG_USTRING()}; $convsub||=sub { map Encode::encode('iso-8859-1',$_), &$sub }; } #not sure of the encoding I should use, it's for app that don't accept 'text/plain;charset=UTF-8', only found/tested with gnome-terminal
		@values=$convsub?  $convsub->(@values)  :  ();
	}
	$data->set($data->target,8, join("\x0d\x0a",@values) ) if @values;
}
sub drag_data_received_cb
{	my ($self,$context,$x,$y,$data,$info,$time)=@_;# warn "drag_data_received_cb @_";
	my $ret=my $del=0;
	$self->{dragdest_suggested_action}= $context->suggested_action; #should maybe have been passed in dragdest arguments, but would require editing all existing dragdest functions
	if ($data->length >=0 && $data->format==8)
	{	my @values=split "\x0d\x0a",$data->data;
		s#file:/(?!/)#file:///# for @values; #some apps send file:/path instead of file:///path
		_utf8_on($_) for @values;
		unshift @values,$context->{dest} if $context->{dest} && $context->{dest}[0]==$self;
		$self->{dragdest} ($self, $::DRAGTYPES{$data->target->name} , @values);
		$ret=1;#$del=1;
	}
	$context->finish($ret,$del,$time);
}

sub drag_checkscrolling	#check if need scrolling
{	my ($self,$context,$y)=@_;
	my $yend=$self->get_visible_rect->height;
	if	($y<40)		{$self->{scroll}=-1}
	elsif	($y>$yend-10)	{$self->{scroll}=1}
	else { delete $self->{scroll};delete $self->{context}; }
	if ($self->{scroll})
	{	$self->{scrolling}||=Glib::Timeout->add(200, \&drag_scrolling_cb,$self);
		$self->{context}||=$context;
	}
}
sub drag_scrolling_cb
{	my $self=$_[0];
	if (my $s=$self->{scroll})
	{	my ($align,$path)=($s<0)? (.1, $self->get_path_at_pos(0,0))
					: (.9, $self->get_path_at_pos(0,$self->get_visible_rect->height));
		$self->scroll_to_cell($path,undef,::TRUE,$align) if $path;
		$self->{drag_motion_cb}( $self,$self->{context}, ($self->window->get_pointer)[1,2], 0 ) if $self->{drag_motion_cb};
		return 1;
	}
	else
	{	delete $self->{scrolling};
		return 0;
	}
}

sub set_biscrolling #makes the mouse wheel scroll vertically when the horizontal scrollbar has grab (boutton pressed on the slider)
{	my $sw=$_[0];
	if (*Gtk2::ScrolledWindow::get_hscrollbar{CODE}) #needs gtk>=2.8
	{	my $scrollbar=$sw->get_hscrollbar;
		$scrollbar->signal_connect(scroll_event =>
			sub { return 0 unless $_[0]->has_grab; $_[0]->parent->propagate_event($_[1]);1; });
		#and vice-versa
		$scrollbar=$sw->get_vscrollbar;
		$scrollbar->signal_connect(scroll_event =>
			sub { return 0 unless $_[0]->has_grab; $_[0]->parent->get_hscrollbar->propagate_event($_[1]);1; });
	}
}

sub CreateDir
{	my ($path,$win,$errormsg,$abortmsg,$many)=@_;
	my $current='';
	for my $dir (split /$QSLASH/o,$path)
	{	$dir= CleanupFileName($dir);
		next if $dir eq '' || $dir eq '.';
		$current.=SLASH.$dir;
		next if -d $current;
		until (mkdir $current)
		{	#if (-f $current) { ErrorMessage("Can't create folder '$current' :\na file with that name exists"); return undef }
			my $details= __x( _"Can't create folder: {path}", path => filename_to_utf8displayname($current));
			$errormsg||= _"Error creating folder";
			my $ret= Retry_Dialog($!,$errormsg, details=>$details, window=>$win, abortmsg=>$abortmsg, many=>$many);
			return $ret unless $ret eq 'retry';
		}
	}
	return 'ok';
}

sub CopyMoveFilesDialog
{	my ($IDs,$copy)=@_;
	my $msg=$copy	?	_"Choose directory to copy files to"
			:	_"Choose directory to move files to";
	my $newdir=ChooseDir($msg, path=>Songs::Get($IDs->[0],'path').SLASH);
	CopyMoveFiles($IDs,copy=>$copy,basedir=>$newdir) if defined $newdir;
}

#$fnformat=$1 if $dirformat=~s/$QSLASH([^$QSLASH]*%\w[^$QSLASH]*)//o;
sub CopyMoveFiles
{	my ($IDs,%options)=@_;
	my ($copy,$basedir,$dirformat,$fnformat,$parentwindow)= @options{qw/copy basedir dirformat filenameformat parentwindow/};
	return if !$copy && $CmdLine{ro};
	my ($sub,$errormsg0,$abortmsg)=  $copy	?	(\&copy,_"Copy failed",_"abort copy")
						:	(\&move,_"Move failed",_"abort move") ;
	my $action=($copy) ?	__("Copying file","Copying %d files",scalar@$IDs) :
				__("Moving file", "Moving %d files", scalar@$IDs) ;

	my $dialog = Gtk2::Dialog->new( $action, $parentwindow, [],
			'gtk-cancel' => 'none',
			);
	my $label=Gtk2::Label->new($action);
	my $progressbar=Gtk2::ProgressBar->new;
	my $cancel;
	my $cancelsub=sub {$cancel=1};
	$dialog->signal_connect( response => $cancelsub);
	my $vbox=Gtk2::VBox->new(FALSE, 2);
	$dialog->vbox->pack_start($_, FALSE, TRUE, 3) for $label,$progressbar;
	$dialog->show_all;
	my $done=0;

	my ($owrite_all,$skip_all,$createdir_skip_all);
COPYNEXTID:for my $ID (@$IDs)
	{	last if $cancel;
		$progressbar->set_fraction($done/@$IDs);
		Gtk2->main_iteration while Gtk2->events_pending;
		last if $cancel;
		$done++;
		my $errormsg= $errormsg0;
		$errormsg.= " ($done/".@$IDs.')' if @$IDs>1;
		my ($olddir,$oldfile)= Songs::Get($ID, qw/path file/);
		my $old=$olddir.SLASH.$oldfile;
		my $newfile=$oldfile;
		my $newdir= $olddir.SLASH;
		$dirformat='' unless defined $dirformat;
		if ($basedir || $dirformat ne '')
		{	$newdir=pathfromformat($ID,$dirformat,$basedir);
			my $res= $createdir_skip_all;
			$res ||= CreateDir($newdir, $dialog, $errormsg, $abortmsg,$done<@$IDs);
			$createdir_skip_all=$res if $res eq 'skip_all';
			last if $res eq 'abort';
			next unless $res eq 'ok';
		}
		if ($fnformat)
		{	$newfile=filenamefromformat($ID,$fnformat,1);
			next unless defined $newfile;
		}
		my $new=$newdir.$newfile;
		next if $old eq $new;
		#warn "from $old\n to $new\n";
		if (-f $new) #if file already exists
		{	my $ow=$owrite_all;
			$ow||=OverwriteDialog($dialog,$new,$done<@$IDs);
			$owrite_all=$ow if $ow=~m/all$/;
			next if $ow=~m/^no/;
		}
		until ($sub->($old,$new))
		{	my $res= $skip_all;
			my $details= join "\n", __x(_"Source: {file}",file=> filename_to_utf8displayname($old)), __x(_"Destination: {file}",file=> filename_to_utf8displayname($new));
			$res ||= Retry_Dialog($!,$errormsg, ID=>$ID, details=> $details, window=>$dialog, abortmsg=>$abortmsg, many=>$done<@$IDs);
			if (-f $new && -f $old && ((-s $new) - (-s $old) <0)) { unlink $new } #delete partial copy
			$skip_all=$res if $res eq 'skip_all';
			last COPYNEXTID if $res eq 'abort';
			next COPYNEXTID if $res ne 'retry';
		}
		unless ($copy)
		{	$newdir= cleanpath($newdir);
			my @modif;
			push @modif, path => $newdir  if $olddir ne $newdir;
			push @modif, file => $newfile if $oldfile ne $newfile;
			Songs::Set($ID, @modif);
		}
	}
	$dialog->destroy;
}

sub ChooseDir
{	my ($msg,%opt)=@_;
	my ($path,$extrawidget,$remember_key,$multiple,$allowfiles) = @opt{qw/path extrawidget remember_key multiple allowfiles/};
	my $mode= $allowfiles ? 'open' : 'select-folder';
	# there is no mode in Gtk2::FileChooserDialog that let you select both files or folders (Bug #136294), so use Gtk2::FileChooserWidget directly as it doesn't interfere with the ok button (in "open" mode pressing ok in a Gtk2::FileChooserDialog while a folder is selected go inside that folder rather than emiiting the ok response with that folder selected)
	my $dialog=Gtk2::Dialog->new($msg,undef,[], 'gtk-ok' => 'ok', 'gtk-cancel' => 'none');
	my $filechooser=Gtk2::FileChooserWidget->new($mode);
	$dialog->vbox->add($filechooser);
	$dialog->set_border_width(5);			# mimick the normal open dialog
	$dialog->get_action_area->set_border_width(5);	#
	$dialog->vbox->set_border_width(5);		#
	$dialog->vbox->set_spacing(5);			#
	::SetWSize($dialog,'ChooseDir','750x580');

	if (ref $allowfiles) { FileChooser_add_filters($filechooser,@$allowfiles); }

	if ($remember_key)	{ $path= $Options{$remember_key}; }
	elsif ($path)		{ $path= url_escape($path); }
	$filechooser->set_current_folder_uri("file://".$path) if $path;
	$filechooser->set_extra_widget($extrawidget) if $extrawidget;
	$filechooser->set_select_multiple(1) if $multiple;

	my @paths;
	$dialog->show_all;
	if ($dialog->run eq 'ok')
	{	for my $path ($filechooser->get_uris)
		{	next unless $path=~s#^file://##;
			$path=decode_url($path);
			next unless -e $path;
			next unless $allowfiles or -d $path;
			push @paths, $path;
		}
	}
	else {@paths=()}
	if ($remember_key) { my $uri=$filechooser->get_current_folder_uri; $uri=~s#^file://##; $Options{$remember_key}= $uri; }
	$dialog->destroy;
	return @paths if $multiple;
	return $paths[0];
}

#sub ChooseDir_old
#{	my ($msg,$path) = @_;
#	my $DirSelector=Gtk2::FileSelection->new($msg);
#	$DirSelector->file_list->set_sensitive(FALSE);
#	$DirSelector->set_filename(filename_to_utf8displayname($path)) if -d $path;
#	if ($DirSelector->run eq 'ok')
#	{   $path=filename_from_unicode($DirSelector->get_filename);
#	    $path=undef unless -d $path;
#	}
#	else {$path=undef}
#	$DirSelector->destroy;
#	return $path;
#}

sub FileChooser_add_filters
{	my ($filechooser,@patterns)=@_;
	for my $aref (@patterns)
	{	my $filter= Gtk2::FileFilter->new;
		if ($aref->[1])	{ $filter->add_mime_type($_)	for split / /,$aref->[1]; }
		if ($aref->[2])	{ $filter->add_pattern($_)	for split / /,$aref->[2]; }
		$filter->set_name($aref->[0]);
		$filechooser->add_filter($filter);
	}
}

sub ChooseFiles
{	my ($text,%opt)=@_;
	$text||=_"Choose files";
	my ($extrawidget,$remember_key,$patterns,$multiple,$parent) = @opt{qw/extrawidget remember_key patterns multiple parent/};
	my $dialog=Gtk2::FileChooserDialog->new($text,$parent,'open',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none');
	$dialog->set_extra_widget($extrawidget) if $extrawidget;
	$dialog->set_select_multiple(1) if $multiple;
	FileChooser_add_filters($dialog,@$patterns);
	if ($remember_key)
	{	my $path= decode_url($Options{$remember_key});
		$dialog->set_current_folder($path);
	}

	my $response=$dialog->run;
	my @files;
	if ($response eq 'ok')
	{	@files=$dialog->get_filenames;
		eval { $_=filename_from_unicode($_); } for @files;
		_utf8_off($_) for @files;# filenames that failed filename_from_unicode still have their uft8 flag on
	}
	if ($remember_key) { $Options{$remember_key}= url_escape($dialog->get_current_folder); }
	$dialog->destroy;
	return @files;
}

sub ChoosePix
{	my ($path,$text,$file,$remember_key)=@_;
	$text||=_"Choose Picture";
	my $dialog=Gtk2::FileChooserDialog->new($text,undef,'open',
					_"no picture" => 'reject',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none');

	FileChooser_add_filters($dialog,
		[_"Pictures and music files",'image/*','*.mp3 *.flac *.m4a *.m4b *.ogg *.oga' ],
		[_"Pictures files",'image/*'],
		["Pdf",undef,'*.pdf'],
		[_"All files",undef,'*'],
	);

	my $preview=Gtk2::VBox->new;
	my $label=Gtk2::Label->new;
	my $image=Gtk2::Image->new;
	my $eventbox=Gtk2::EventBox->new;
	$eventbox->add($image);
	$eventbox->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb);
	my $max=my $nb=0; my $lastfile;
	my $prev= NewIconButton('gtk-go-back',   undef, sub { $_[0]->parent->parent->{set_pic}->(-1); });
	my $next= NewIconButton('gtk-go-forward',undef, sub { $_[0]->parent->parent->{set_pic}->(1); });
	my $more= Gtk2::HButtonBox->new;
	$more->add($_) for $prev,$next;
	$preview->pack_start($_,FALSE,FALSE,2) for $more,$eventbox,$label;
	$dialog->set_preview_widget($preview);
	#$dialog->set_use_preview_label(FALSE);
	$preview->{set_pic}=sub
		{ my $inc=shift;
		  $nb+=$inc if $inc;
		  $nb=0 if $nb<0 || $nb>=$max;
		  my $file=$lastfile;
		  $file.=":$nb" if $nb;
		  GMB::Picture::ScaleImage($image,150,$file);
		  my $p=$image->{pixbuf};
		  if ($p) { $label->set_text($p->get_width.' x '.$p->get_height); }
		  else { $label->set_text(''); }
		  $more->set_visible($max>1);
		  $prev->set_sensitive($nb>0);
		  $next->set_sensitive($nb<$max-1);
		  $dialog->set_preview_widget_active($p || $nb);
		};
	my $update_preview=sub
		{ my ($dialog,$file)=@_;
		  unless ($file)
		  {	$file= $dialog->get_preview_uri;
			$file= ($file && $file=~s#^file://##) ? decode_url($file) : undef;
		  }
		  unless ($file && -f $file) { $preview->hide; return }
		  $preview->show;
		  $max=0;
		  $nb=0 unless $lastfile && $lastfile eq $file;
		  $lastfile=$file;
		  if ($file=~m/\.(?:mp3|flac|m4a|m4b|oga|ogg)$/i)
		  {	my @pix= FileTag::PixFromMusicFile($file);
			$max=@pix;
		  }
		  elsif ($file=~m/\.pdf$/i) { $max=GMB::Picture::pdf_pages($file) }
		  $preview->{set_pic}->();
		};
	$dialog->signal_connect(update_preview => $update_preview);

	$preview->show_all;
	$more->set_no_show_all(1);
	$dialog->set_preview_widget_active(0);
	if ($remember_key)	{ $path= $Options{$remember_key}; }
	elsif ($path)		{ $path= url_escape($path); }
	if ($file && $file=~s/:(\d+)$//) { $nb=$1; $lastfile=$file; }
	if ($file && -f $file)	{ $dialog->set_filename($file); $update_preview->($dialog,$file); }
	elsif ($path)		{ $dialog->set_current_folder_uri( "file://$path" ); }

	my $response=$dialog->run;
	my $ret;
	if ($response eq 'ok')
	{	$ret= $dialog->get_uri;
		$ret= $ret=~s#^file://## ? $ret=decode_url($ret) : undef;
		unless (-e $ret) { warn "can't find $ret\n"; $ret=undef; }
		$ret.=":$nb" if $nb;
	}
	elsif ($response eq 'reject') {$ret='0'}
	else {$ret=undef}
	if ($remember_key) { my $uri=$dialog->get_current_folder_uri; $uri=~s#^file://##; $Options{$remember_key}= $uri; }
	$dialog->destroy;
	return $ret;
}

#sub ChoosePix_old
#{	my ($path,$text)=@_;
#	my $PixSelector=Gtk2::FileSelection->new($text||'Choose Picture');
#	$PixSelector->add_button(_"no picture",'reject'); #FIXME add before ok and cancel buttons
#	my $flist=$PixSelector->file_list;
#	my $dialog_hbox=$flist->parent->parent->parent; #FIXME
#	my $previewbox=Gtk2::VBox->new(FALSE,2);
#	my $frame=Gtk2::Frame->new('Preview');
#	my $eventbox=Gtk2::EventBox->new;
#	my $img=Gtk2::Image->new;
#	$eventbox->add($img);
#	$frame->add($eventbox);
#	$eventbox->signal_connect(button_press_event => \&GMB::Picture::pixbox_button_press_cb);
#	$frame->set_size_request(155,155);
#	my $label=Gtk2::Label->new;
#	$PixSelector->set_filename(filename_to_utf8displayname($path.SLASH)) if $path &&  -d $path;
#	$previewbox->pack_start($_,FALSE,FALSE,2) for $frame,$label;
#	$PixSelector->selection_entry->signal_connect(changed => sub
#		{	my ($file)=$PixSelector->get_selections;
#			$file=filename_from_unicode($file);
#			GMB::Picture::ScaleImage($img,150,$file);
#			my $p=$img->{pixbuf};
#			my $text=$p? $p->get_width.' x '.$p->get_height  : '';
#			$label->set_text($text);
#			$img->show_all;
#		});
#	$previewbox->show_all;
#	$dialog_hbox->pack_start($previewbox,FALSE,FALSE,2);
#	$PixSelector->complete ('*.jpg');
#	my $response = $PixSelector->run;
#	my $ret;
#	if ($response eq 'ok')
#	{	$ret=filename_from_unicode($PixSelector->get_filename);
#		#$ret=$PixSelector->get_filename;
#		unless (-r $ret) { warn "can't read $ret\n"; $ret=undef; }
#	}
#	elsif ($response eq 'reject') {$ret='0'}
#	else {$ret=undef}
#	$PixSelector->destroy;
#	return $ret;
#}

sub ChooseSaveFile
{	my ($window,$msg,$path,$file,$widget) = @_;
	my $dialog=Gtk2::FileChooserDialog->new($msg,$window,'save',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none',
					);
	#$dialog->set_current_folder($path) if defined $path;
	$dialog->set_filename($path.SLASH.'*') if defined $path;
	$dialog->set_current_name(filename_to_utf8displayname($file)) if defined $file;
	$dialog->set_extra_widget($widget) if $widget;

	if ($dialog->run eq 'ok')
	{   $file=$dialog->get_filename;
	}
	else {$file=undef}
	$dialog->destroy;
	if (defined $file && -f $file)
	{	my $res=OverwriteDialog($window,$file);
		if ($res ne 'yes') {$file=undef;}
		$dialog->destroy;
	}
	return $file;
}

sub OverwriteDialog
{	my ($window,$file,$multiple)=@_;
	my $dialog = Gtk2::MessageDialog->new
	( $window,
	  [qw/modal destroy-with-parent/],
	  'warning','yes-no','%s',
	  __x( _"'{file}' exists. Overwrite ?", file => filename_to_utf8displayname($file) )
	);
	if ($multiple)
	{	$dialog->add_button(_"yes to all",'1');
		$dialog->add_button(_"no to all",'2');
	}
	$dialog->show_all;
	my $ret=$dialog->run;
	$dialog->destroy;
	$ret=2 unless $ret;
	$ret=	($ret eq '1')	? 'yesall':
		($ret eq '2')	? 'noall' :
		($ret)		? $ret	  :
		'no';
	return $ret;
}

my $LastErrorShowDetails;
sub Retry_Dialog	#returns one of 'retry abort skip skip_all'
{	my ($syserr,$summary,%args)=@_;		#$summary should say what action lead to this error ie: "Error while writing tag"
	my ($details,$window,$abortmsg,$many,$ID)=@args{qw/details window abortmsg many ID/};
	my $dialog = Gtk2::MessageDialog->new($window, [qw/modal destroy-with-parent/], 'error','none','%s', $summary);
	$dialog->format_secondary_text("%s",$syserr);
	$dialog->set_title($summary);
	$dialog->add_button_custom(_"_Retry",    1, icon=>'gtk-refresh');
	$dialog->add_button_custom(_"_Cancel",   2, icon=>'gtk-cancel', tip=>$abortmsg);
	$dialog->add_button_custom(_"_Skip",     3, icon=>'gtk-go-forward', tip=>_"Proceed to next item.") if $many;
	$dialog->add_button_custom(_"Skip _All", 4, tip=>_"Skip this and any further errors.") if $many;
	my $expander;
	if ($details)
	{	my $label= Gtk2::Label->new($details);
		$label->set_line_wrap(1); #FIXME making the label resize with the dialog would be nice but complicated with gtk2
		$label->set_selectable(1);
		$label->set_padding(2,5);
		$label->set_alignment(0,.5);
		$expander=Gtk2::Expander->new(_"Show more error details");
		$expander->add($label);
		$dialog->vbox->add($expander);
		$expander->set_expanded( time-($LastErrorShowDetails||0) <6 );#set expanded if recently showed a error dialog that was left expanded
	}
	$dialog->show_all;
	my $ret=$dialog->run;
	$LastErrorShowDetails= ($expander->get_expanded ? time : undef) if $expander;
	$dialog->destroy;
	$ret=0 if $ret!~m/^[1234]$/;
	return (qw/abort retry abort skip skip_all/)[$ret];
}

sub ErrorMessage
{	my ($err,$window)=@_;
	warn "$err\n";
	my $dialog = Gtk2::MessageDialog->new
	( $window,
	  [qw/modal destroy-with-parent/],
	  'error','close','%s',
	  $err
	);
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
}

sub EditLyrics
{	my $ID=$_[0];
	if (exists $Editing{'L'.$ID}) { $Editing{'L'.$ID}->force_present; return; }
	my $lyrics=FileTag::GetLyrics($ID);
	$lyrics='' unless defined $lyrics;
	$Editing{'L'.$ID}=
	  EditLyricsDialog(undef,$lyrics,_("Lyrics for ").Songs::Display($ID,'fullfilename'),sub
	   {	delete $Editing{'L'.$ID};
		FileTag::WriteLyrics($ID,$_[0]) if defined $_[0];
	   });
}

sub EditLyricsDialog
{	my ($window,$init,$text,$sub)=@_;
	my $dialog = Gtk2::Dialog->new ($text||_"Edit Lyrics", $window,'destroy-with-parent');
	my $bsave=$dialog->add_button('gtk-save' => 'ok');
		  $dialog->add_button('gtk-cancel' => 'none');
	$dialog->set_default_response ('ok');
	my $textview=Gtk2::TextView->new;
	my $buffer=$textview->get_buffer;
	$buffer->set_text($init);
	$buffer->signal_connect( changed => sub { $bsave->set_sensitive( $buffer->get_text($buffer->get_bounds,1) ne $init); });
	$bsave->set_sensitive(0);

	my $sw= new_scrolledwindow($textview,'etched-in');
	$dialog->vbox->add($sw);
	SetWSize($dialog,'Lyrics');
	$dialog->show_all;
	$dialog->signal_connect( response => sub
		{	my ($dialog,$response,$sub)=@_;
			my $lyrics;
			$lyrics=$buffer->get_text( $buffer->get_bounds, 1) if $response eq 'ok';
			$dialog->destroy;
			$sub->($lyrics) if $sub;
		},$sub);
	return $dialog;
}

sub DeleteFiles
{	return if $CmdLine{ro};
	my $IDs=$_[0];
	return unless @$IDs;
	my $text=(@$IDs==1)? "'".Songs::Display($IDs->[0],'file')."'" : __("%d file","%d files",scalar @$IDs);
	my $dialog = Gtk2::MessageDialog->new
		( ::get_event_window(),
		  'modal',
		  'warning','cancel','%s',
		  __x(_("About to delete {files}\nAre you sure ?"), files => $text)
		);
	$dialog->add_button("gtk-delete", 2);
	$dialog->show_all;
	if ('2' eq $dialog->run)
	{ my $skip_all;
	  my $done=0;
	  for my $ID (@$IDs)
	  {	my $f= Songs::GetFullFilename($ID);
		unless (unlink $f)
		{	my $res= $skip_all;
			my $errormsg= _"Deletion failed";
			$errormsg.= ' ('.($done+1).'/'.@$IDs.')' if @$IDs>1;
			$res ||= ::Retry_Dialog($!,$errormsg, ID=>$ID, details=>__x(_("Failed to delete '{file}'"), file => filename_to_utf8displayname($f)), window=>$dialog, many=>(@$IDs-$done)>1);
			$skip_all=$res if $res eq 'skip_all';
			redo if $res eq 'retry';
			last if $res eq 'abort';
		}
		$done++;
		IdleCheck($ID);
	  }
	}
	$dialog->destroy;
}

sub filenamefromformat
{	my ($ID,$format,$ext)=@_;	# $format is in utf8
	my $s= ReplaceFieldsForFilename($ID,$format);
	if ($ext)
	{	$s= Songs::Get($ID,'barefilename') if $s eq '';
		$s.= '.'.Songs::Get($ID,'extension');  #add extension
	}
	elsif ($s=~m/^\.\w+$/)			#only extension -> base name on song's filename
	{	$s= Songs::Get($ID,'barefilename').$s;
	}
	return $s;
}
sub pathfromformat
{	my ($ID,$format,$basefolder,$icase)=@_;		# $format is in utf8, $basefolder is a byte string
	my $path= defined $basefolder ? $basefolder.SLASH : '';
	if ($format=~s#^([^\$%]*$QSLASH)##)					# move constant part of format in path
	{	my $constant=$1;
		$path.= filename_from_unicode($constant);	# calling filename_from_unicode directly on $1 causes strange bugs afterward (with perl-Glib-1.222)
	}
	$path=~s#^~($QSLASH)#$ENV{HOME}$1#o;				# replace leading ~/ by homedir
	$path= Songs::Get($ID,'path').SLASH.$path if $path!~m#^$QSLASH#o; # use song's path as base for relative paths
	$path= simplify_path($path,1);
	for my $f0 (split /$QSLASH+/o,$format)
	{	my $f= ReplaceFieldsForFilename($ID,$f0);
		next if $f=~m/^\.\.?$/;
		if ($icase && $f0 ne $f)
		{	$f=ICasePathFile($path,$f);
		}
		$path.=$f.SLASH;
	}
	return cleanpath($path,1);
}
sub pathfilefromformat
{	my ($ID,$format,$ext,$icase)=@_;	# $format is in utf8
	my ($path,$file)= $format=~m/^(?:(.*)$QSLASH)?([^$QSLASH]+)$/o;
	#return undef unless $file;
	$file='' unless defined $file;
	$path='' unless defined $path;
	$path=pathfromformat($ID,$path,undef,$icase);
	$file=filenamefromformat($ID,$file,$ext);
	$file=ICasePathFile($path,$file) if $icase;
	return undef unless $file;
	return wantarray ? ($path,$file) : $path.$file;
}
sub ICasePathFile	#tries to find an existing file/folder with different case
{	my ($path,$folder)=@_;
	return $folder unless -e $path;
	unless (-e $path.$folder)
	{	opendir my($d),$path;
		my @files=readdir $d;
		closedir $d;
		my $lc=lc$folder;	#or superlc ?
		my ($found)=grep $lc eq lc, @files;
		$folder=$found if defined $found;
	}
	return $folder;
}
sub CaseSensFile	#find case-sensitive filename from a case-insensitive filename
{	my $file0=shift;
	return $file0 if -e $file0;
	my $file='';
	for my $f (split /$QSLASH+/o,$file0)
	{	$f=ICasePathFile( $file||SLASH, $f);
		$file.=$f.SLASH;
	}
	chop $file; #remove last SLASH
	return $file;
}

sub DialogMassRename
{	return if $CmdLine{ro};
	my @IDs= uniq(@_); #remove duplicates IDs in @_ => @IDs
	Songs::SortList(\@IDs,'path album:i disc track file');
	my $dialog = Gtk2::Dialog->new
			(_"Mass Renaming", undef,
			 [qw/destroy-with-parent/],
			 'gtk-ok'	=> 'ok',
			 'gtk-cancel'	=> 'none',
			);
	$dialog->set_border_width(4);
	$dialog->set_default_response('ok');
	SetWSize($dialog,'MassRename','650x550');
	my $table=MakeReplaceTable('talydnAYo');
	my $combo=	NewPrefComboText('FilenameSchema');
	my $comboFolder=NewPrefComboText('FolderSchema');
	$combo->child->set_activates_default(TRUE);
	my $folders=0;
	###
	my $notebook=Gtk2::Notebook->new;
	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview1=Gtk2::TreeView->new($store);
	my $treeview2=Gtk2::TreeView->new($store);
	my $func1=sub
	  {	my (undef,$cell,$store,$iter)= @_;
		my $ID=$store->get($iter,0);
		my $text= $folders ? Songs::Display($ID,'fullfilename') : Songs::Display($ID,'file');
		$cell->set(text=>$text);
	  };
	my $func2=sub
	  {	my (undef,$cell,$store,$iter)=@_;
		my $ID=$store->get($iter,0);
		my $text=filenamefromformat($ID,$combo->get_active_text,1);
		if ($folders)
		{	my $base=  decode_url($Options{BaseFolder});
			my $fmt= $comboFolder->get_active_text;
			$text= pathfromformat($ID,$fmt,$base) . $text;
		}
		$cell->set(text=> filename_to_utf8displayname($text) );
	  };
	for ( [$treeview1,_"Old name",$func1], [$treeview2,_"New name",$func2] )
	{	my ($tv,$title,$func)=@$_;
		$tv->set_headers_visible(FALSE);
		my $renderer=Gtk2::CellRendererText->new;
		my $col=Gtk2::TreeViewColumn->new_with_attributes($title,$renderer);
		$col->set_cell_data_func($renderer, $func);
		$col->set_sizing('fixed');
		$col->set_resizable(TRUE);
		$tv->append_column($col);
		$tv->set('fixed-height-mode' => TRUE);
		my $sw= new_scrolledwindow($tv,'etched-in');
		$notebook->append_page($sw,$title);
	}
	$treeview2->parent->set_vadjustment( $treeview1->parent->get_vadjustment ); #sync vertical scrollbars
	#sync selections :
	my $busy;
	my $syncsel=sub { return if $busy;$busy=1;my $path=$_[0]->get_selected_rows; $_[1]->get_selection->select_path($path);$busy=undef;};
	$treeview1->get_selection->signal_connect(changed => $syncsel,$treeview2);
	$treeview2->get_selection->signal_connect(changed => $syncsel,$treeview1);

	$store->set( $store->prepend,0, $_ ) for reverse @IDs; # prepend because filling is a bit faster in reverse

	my $refresh=sub { $treeview2->queue_draw; };
	$combo->signal_connect(changed => $refresh);
	$comboFolder->signal_connect(changed => $refresh);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entrybase=NewPrefFileEntry('BaseFolder',_("Base Folder :"), folder =>1, cb => $refresh, sizeg1=>$sg1,sizeg2=>$sg2, history_key=>'BaseFolder_history');
	my $labelfolder=Gtk2::Label->new(_"Folder pattern :");

	my $title=Gtk2::Label->new(_"Rename/move files based on these fields :");
	#my $checkfile=	Gtk2::CheckButton->new(_"Rename files using this pattern :");
	my $checkfile=	Gtk2::Label->new(_"Rename files using this pattern :");
	my $checkfolder=Gtk2::CheckButton->new(_"Move Files to :");
	$sg1->add_widget($labelfolder);
	$sg2->add_widget($comboFolder);
	my $albox=Gtk2::Alignment->new(0,0,1,1);
	$albox->set_padding(0,0,20,0);
	$albox->add( Vpack($entrybase,[$labelfolder,$comboFolder]) );
	$checkfolder->signal_connect(toggled => sub {$folders=$_[0]->get_active; $albox->set_sensitive($folders); $treeview1->queue_draw; $treeview2->queue_draw; });
	$albox->set_sensitive($folders);
	my $vbox=Vpack	(	$title,$table,
				[$checkfile,$combo],
				$checkfolder,
				$albox,
			);
	$dialog->vbox->pack_start($vbox,FALSE,FALSE,3);
	$dialog->vbox->pack_start($notebook,TRUE,TRUE,5);

	$notebook->show_all;
	$notebook->set_current_page(1);
	$dialog->show_all;

	$treeview1->realize; #FIXME without it, scrollbars synchronization doesn't work until treeview1 is displayed (by clicking on the 1st tab)

	$dialog->signal_connect( response => sub
	 {	my ($dialog,$response)=@_;
		if ($response eq 'ok')
		{ my $format=$combo->get_active_text;
		  if ($folders)
		  {	my $base0= my $base= decode_url( $Options{BaseFolder} );
			unless ( defined $base ) { ErrorMessage(_("You must specify a base folder"),$dialog); return }
			until ( -d $base ) { last unless $base=parentdir($base);  }
			unless ( -w $base ) { ErrorMessage(__x(_("Can't write in base folder '{folder}'."), folder => filename_to_utf8displayname($base0)),$dialog); return }
			$dialog->set_sensitive(FALSE);
			my $folderformat=$comboFolder->get_active_text;
			CopyMoveFiles(\@IDs,copy=>FALSE,basedir=>$base0,dirformat=>$folderformat,filenameformat=>$format,parentwindow=>$dialog);
		  }
		  elsif ($format)
		  {	$dialog->set_sensitive(FALSE);
			CopyMoveFiles(\@IDs,copy=>FALSE,filenameformat=>$format,parentwindow=>$dialog);
		  }
		}
		$dialog->destroy;
	 });
}

sub RenameFile
{	my ($dir,$old,$newutf8,$window)=@_;
	my $new= CleanupFileName(filename_from_unicode($newutf8));
	return unless length $new;
	{	last if $new eq '';
		last if $old eq $new;
		if (-f $dir.SLASH.$new)
		{	my $res=OverwriteDialog($window,$new);
			return unless $res eq 'yes';
			redo;
		}
		elsif (!rename $dir.SLASH.$old, $dir.SLASH.$new)
		{	my $res= Retry_Dialog($!,_"Renaming failed", window=>$window, details=>
				__x( _"From: {oldname}\nTo: {newname}",	oldname => filename_to_utf8displayname($old),
									newname => filename_to_utf8displayname($new)));
			return unless $res eq 'retry';
			redo;
		}
	}
	return $new;
}

sub RenameSongFile
{	my ($ID,$newutf8,$window)=@_;
	my ($dir,$old)= Songs::Get($ID,qw/path file/);
	my $new=RenameFile($dir,$old,$newutf8,$window);
	Songs::Set($ID, file=> $new) if defined $new;
}

sub DialogRename
{	return if $CmdLine{ro};
	my $ID=$_[0];
	my $dialog = Gtk2::Dialog->new (_"Rename File", undef, [],
				'gtk-ok'	=> 'ok',
				'gtk-cancel'	=> 'none');
	$dialog->set_default_response ('ok');
	my $table=Gtk2::Table->new(4,2);
	my $row=0;
	for my $col (qw/title artist album disc track/)
	{	my $val=Songs::Display($ID,$col);
		next if ($col eq 'disc' || $col eq 'track') && !$val;
		my $lab1=Gtk2::Label->new;
		my $lab2=Gtk2::Label->new($val);
		$lab1->set_markup_with_format("<b>%s :</b>", Songs::FieldName($col));
		$lab1->set_padding(5,0);
		$lab1->set_alignment(1,.5);
		$lab2->set_alignment(0,.5);
		$lab2->set_line_wrap(1);
		$lab2->set_selectable(TRUE);
		$table->attach_defaults($lab1,0,1,$row,$row+1);
		$table->attach_defaults($lab2,1,2,$row,$row+1);
		$row++;
	}
	my ($name,$ext)= Songs::Display($ID,'barefilename','extension');
	my $entry=Gtk2::Entry->new;
	$entry->set_activates_default(TRUE);
	$entry->set_text($name);
	my $label_ext=Gtk2::Label->new('.'.$ext);
	$dialog->vbox->add($table);
	$dialog->vbox->add(Hpack('_',$entry,0,$label_ext));
	SetWSize($dialog,'Rename','300x180');

	$dialog->show_all;
	$dialog->signal_connect( response => sub
	 {	my ($dialog,$response)=@_;
		if ($response eq 'ok')
		{	my $name=$entry->get_text;
			RenameSongFile($ID,"$name.$ext",$dialog) if $name=~m/\S/;
		}
		$dialog->destroy;
	 });
}

sub GetListOfSavedLists
{	return sort { superlc($a) cmp superlc($b) } keys %{$Options{SavedLists}};
}

sub AddToListMenu
{	my @keys=GetListOfSavedLists();
	return undef unless @keys;
	my $IDs=$_[0]{IDs};
	my $menusub=sub {my $key=$_[1]; $Options{SavedLists}{$key}->Push($IDs); };

	my $makemenu=sub
	{	my ($start,$end,$keys)=@_;
		my $menu=Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $l=$keys->[$i];
			my $item=Gtk2::MenuItem->new_with_label($l);
			$item->signal_connect(activate => $menusub,$l);
			$menu->append($item);
		}
		return $menu;
	};
	my $menu=Breakdown_List(\@keys, makemenu=>$makemenu);
	return $menu;
}

sub LabelEditMenu
{	my $IDs=$_[0]{IDs};
	my $field='label';
	my ($hash)=Songs::BuildHash($field,$IDs,'name');
	$_=	$_==0	  ? 0 :
		$_==@$IDs ? 1 :
		2
	 for values %$hash;
	my $menusub_toggled=sub
	 {	my $f=$_[1];
		if ($_[0]->get_active)	{ Songs::Set($IDs,"+$field",$f); }
		else			{ Songs::Set($IDs,"-$field",$f); }
	 };
	MakeFlagMenu($field,$menusub_toggled,$hash);
}

sub MakeFlagMenu	#FIXME special case for no @keys, maybe a menu with a greyed-out item "no #none#"
{	my ($field,$callback,$hash)=@_;
	my @keys= @{Songs::ListAll($field)};
	my $makemenu=sub
	{	my ($start,$end,$keys)=@_;
		my $menu=Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $key=$keys->[$i];
			my $item;
			if ($hash)
			{	$item=Gtk2::CheckMenuItem->new_with_label($key);
				my $state= $hash->{$key}||0;
				if ($state==1){ $item->set_active(1); }
				elsif ($state==2)  { $item->set_inconsistent(1); }
				$item->signal_connect(toggled => $callback,$key);
			}
			else
			{	$item=Gtk2::MenuItem->new_with_label($key);
				$item->signal_connect(activate => $callback,$key);
			}
			$menu->append($item);
		}
		return $menu;
	};
	my $menu=Breakdown_List(\@keys, makemenu=>$makemenu);
	return $menu;
}

sub PopupAAContextMenu
{	my $args=$_[0];
	$args->{mainfield}= Songs::MainField($args->{field});
	$args->{lockfield}= $args->{field} eq 'artists' ? 'first_artist' : $args->{field};
	$args->{aaname}= Songs::Gid_to_Get($args->{field},$args->{gid});
	defined wantarray ? BuildMenu(\@cMenuAA, $args) : PopupContextMenu(\@cMenuAA, $args);
}

sub FilterOnAA
{	my ($widget,$field,$gid,$filternb)=@{$_[0]}{qw/self field gid filternb/};
	$filternb=1 unless defined $filternb;
	::SetFilter($widget, Songs::MakeFilterFromGID($field,$gid), $filternb);
}
sub SearchSame
{	my $field=$_[0];
	my ($widget,$IDs,$filternb)=@{$_[1]}{qw/self IDs filternb/};
	$filternb=1 unless defined $filternb;
	my $filter=Filter->newadd(FALSE, map Songs::MakeFilterFromID($field,$_), @$IDs);
	::SetFilter($widget,$filter,$filternb);
}

sub SongsSubMenuTitle
{	my $nb=@{ AA::GetIDs($_[0]{field},$_[0]{gid}) };
	return __("%d Song","%d Songs",$nb);
}
sub SongsSubMenu
{	my %args=%{$_[0]};
	$args{mode}='S';
	$args{IDs}=\@{ AA::GetIDs($args{field},$args{gid}) };
	BuildMenuOptional(\@SongCMenu,\%args);
}

sub ArtistContextMenu
{	my ($artists,$params)=@_;
	$params->{field}='artists';
	if (@$artists==1) { PopupAAContextMenu({%$params,gid=>$artists->[0]}); return; }
	my $menu = Gtk2::Menu->new;
	for my $ar (@$artists)
	{	my $name= Songs::Gid_to_Get('artists',$ar);
		my $item=Gtk2::MenuItem->new_with_label($name);
		my $submenu= PopupAAContextMenu({%$params,gid=>$ar});
		$item->set_submenu($submenu);
		$menu->append($item);
	}
	PopupMenu($menu,nomenupos=>1);
}

=deprecated
sub EditLabels
{	my @IDs=@_;
	my $vbox=Gtk2::VBox->new;
	my $table=Gtk2::Table->new(int((keys %Labels)/3),3,FALSE);
	my %checks;
	my $changed;
	my $row=0; my $col=0;
	my $addlabel=sub
	 {	my $label=$_[0];
		my $check=Gtk2::CheckButton->new_with_label($label);
		my $state= @{ Filter->new( 'label:~:'.$label )->filter(\@IDs)};
		if ($state==@IDs) { $check->set_active(1); }
		elsif ($state>0)  { $check->set_inconsistent(1); }
		$check->signal_connect( toggled => sub	{  $_[0]->set_inconsistent(0); $changed=1 });
		$checks{$label}=$check;
		if ($col==3) {$col=0; $row++;}
		$table->attach($check,$col,$col+1,$row,$row+1,['fill','expand'],'shrink',1,1);
		$col++;
	 };
	$addlabel->($_) for @{ Songs::ListAll('label') };
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add_with_viewport($table);
	$vbox->add($sw);
	my $entry=Gtk2::Entry->new;
	my $addnew=sub
	 {	my $label=$entry->get_text;
		$entry->grab_focus;
		return unless $label;
		$entry->set_text('');
		$addlabel->($label) unless exists $checks{$label};
		$checks{$label}->set_active(1);
		$checks{$label}->show_all;
	 };
	my $button=NewIconButton('gtk-add',_"Add new label",$addnew);
	$entry->signal_connect( activate => $addnew );
	$vbox->pack_end( Hpack($entry,$button), FALSE, FALSE, 2 );

	$vbox->{save}=sub
	{	return unless $changed;
		no warnings;
		my @toremove; my @toadd;
		while (my ($label,$check)=each %checks)
		{	next if $check->get_inconsistent;
			if ($check->get_active) { push @toadd,$label }
			else			{ push @toremove,$label }
		}
		my @args;
		push @args,"+label",\@toadd if @toadd;
		push @args,"-label",\@toremove if @toremove;
		Songs::Set(\@IDs,@args);
	};
	return $vbox;
}
=cut

sub DialogSongsProp
{	my @IDs=@_;
	my $dialog = Gtk2::Dialog->new (_"Edit Multiple Songs Properties", undef,
				'destroy-with-parent',
				'gtk-save' => 'ok',
				'gtk-cancel' => 'none');
	$dialog->set_default_response ('ok');
	my $notebook = Gtk2::Notebook->new;
	#$notebook->set_tab_border(4);
	#$dialog->vbox->add($notebook);

	my $edittag=MassTag->new(@IDs);
	$dialog->vbox->add($edittag);

	SetWSize($dialog,'MassTag','520x650');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
		{	my ($dialog,$response)=@_;
			if ($response eq 'ok')
			{ $dialog->action_area->set_sensitive(FALSE);
			  $edittag->save( sub {$dialog->destroy;} ); #the closure will be called when tagging finished #FIXME not very nice
			}
			else { $dialog->destroy; }
		});
}

sub DialogSongProp
{	my $ID=$_[0];
	if (exists $Editing{$ID}) { $Editing{$ID}->force_present; return; }
	my $dialog = Gtk2::Dialog->new (_"Song Properties", undef, []);
	my $advanced_button=$dialog->add_button_custom(_("Advanced").'...', 1, icon=>'gtk-edit', tip=>_"Advanced Tag Editing", secondary=>1);
	$dialog->add_buttons('gtk-save','ok', 'gtk-cancel','none');

	$dialog->set_default_response ('ok');
	$Editing{$ID}=$dialog;
	my $notebook = Gtk2::Notebook->new;
	$notebook->set_tab_border(4);
	$dialog->vbox->add($notebook);

	my $edittag=  EditTagSimple->new($dialog,$ID);
	my $songinfo= Layout::SongInfo->new({ID=>$ID});
	$notebook->append_page( $edittag,	Gtk2::Label->new(_"Edit"));
	$notebook->append_page( $songinfo,	Gtk2::Label->new(_"Info"));

	SetWSize($dialog,'SongInfo','420x540');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
	{	warn "EditTag response : @_\n" if $debug;
		my ($dialog,$response)=@_;
		if ($response eq '1') { $edittag->advanced; return; }
		$edittag->save if $response eq 'ok';
		delete $Editing{$ID};
		$dialog->destroy;
	});
}

sub SongsChanged
{	warn "SongsChanged @_\n" if $debug;
	my ($IDs,$fields)=@_;
	Filter::clear_cache();
	if (defined $SongID && (grep $SongID==$_,@$IDs)) # if current song is part of the changed songs
	{	$ListPlay->UpdateLock if $TogLock && OneInCommon([Songs::Depends($TogLock)],$fields);
		HasChanged('CurSong',$SongID);
	}
	for my $group (keys %SelID)
	{	HasChangedSelID($group,$SelID{$group}) if grep $SelID{$group}==$_, @$IDs;
	}
	QHasChanged('NextSongs')   if OneInCommon($IDs,\@NextSongs);
	QHasChanged('RecentSongs') if OneInCommon($IDs,$Recent);
	HasChanged(SongsChanged=>$IDs,$fields);
	GMB::ListStore::Field::changed(@$fields);
}
sub SongAdd		#only called from IdleLoop
{	my $ID=Songs::New($_[0]);
	return unless defined $ID;
	push @ToAdd_IDsBuffer,$ID;
	$ProgressNBSongs++;
	#IdleDo('0_AddIDs',30000,\&SongAdd_now);
}
sub SongAdd_now
{	push @ToAdd_IDsBuffer,@_;
	return unless @ToAdd_IDsBuffer;
	my @IDs=@ToAdd_IDsBuffer; #FIXME remove IDs already in Library	#FIXME check against master filter ?
	@ToAdd_IDsBuffer=();
	Filter::clear_cache();
	AA::IDs_Changed();
	$Library->Push(\@IDs);
	HasChanged(SongsAdded=>\@IDs);
	AutoSelPictures(album=> @{Songs::UniqList(album=>\@IDs)});
}
sub SongsRemove
{	my $IDs=$_[0];
	Filter::clear_cache();
	for my $ID (@$IDs, map("L$_", @$IDs)) { $::Editing{$ID}->destroy if exists $::Editing{$ID};}
	AA::IDs_Changed();
	SongArray::RemoveIDsFromAll($IDs);
	$RecentPos-- while $RecentPos && $Recent->[$RecentPos-1]!=$SongID; #update RecentPos if needed

	HasChanged(SongsRemoved=>$IDs);
	Songs::AddMissing($IDs);
}
sub UpdateMasterFilter
{	SongAdd_now();	#flush waiting list
	my @diff;
	$diff[$_]=1 for @$Library;
	my $mfilter= $Options{MasterFilterOn} && $Options{MasterFilter} || '';
	my $newlist= Filter->newadd(TRUE,'missing:e:0', $mfilter)->filter_all;
	$diff[$_]+=2 for @$newlist;
	my @toadd= grep $diff[$_]==2, @$newlist;
	my @toremove= grep $diff[$_] && $diff[$_]==1, 0..$#diff;
	Filter::clear_cache();
	AA::IDs_Changed();
	$Library->Replace($newlist);
	HasChanged(SongsRemoved=> \@toremove);
	HasChanged(SongsAdded=> \@toadd);
}


our %playlist_file_parsers;
INIT
{%playlist_file_parsers=
 (	m3u => \&m3u_to_files,
	pls => \&pls_to_files,
 );
}
sub m3u_to_files
{	my $content=shift;
	my @files= grep m#\S# && !m/^\s*#/, split /[\n\r]+/, $content;
	s#^\s*## for @files;
	return @files;
}
sub pls_to_files
{	my $content=shift;
	my @files= grep m/^File\d+=/, split /[\n\r]+/, $content;
	s#^File\d+=\s*## for @files;
	return @files;
}

sub Parse_playlist_file	#return filenames from playlist files (.m3u, .pls, ...)
{	my $pl_file=shift;
	my ($basedir,$name)= splitpath($pl_file);
	($name,my $ext)= barename($name);
	my $sub= $playlist_file_parsers{lc $ext};
	if (!$sub) { warn "Unsupported playlist format '$name.$ext'\n" }
	open my($fh),'<',$pl_file  or do {warn "Error reading $pl_file : $!"; return};
	my $content = do { local( $/ ) ; <$fh> } ;
	close $fh;
	my @list;
	for my $file ($sub->($content))
	{	if ($file=~s#^file://##) { $file=decode_url($file); }
		elsif ($file=~m#^http://#) {next} #ignored for now
		#push @list, CaseSensFile( rel2abs($file,$basedir) );
		push @list,$file;
	}
	if (1) # try hard to find the correct filenames by trying different encodings and case-incensivity
	{	my @enc= sort { ($Encoding_pref{$b}||0) <=> ($Encoding_pref{$a}||0) } grep {($Encoding_pref{$_}||0) >=0} Encode->encodings(':all');
		for my $enc (@enc)
		{	my @found;
			my @test=@list;
			eval {	no warnings;
				for my $file (@test)
				{	Encode::from_to($file,$enc, 'UTF-8', Encode::FB_CROAK);
					$file &&= CaseSensFile(rel2abs($file,$basedir));
					if ($file && -f $file) { push @found,$file } else {last}
				}
			};
			if (@found==@list)
			{	warn "playlist import: using encoding $enc\n" if $::debug;
				$Encoding_pref{$enc}||=1; #give some priority to found encoding
				return @found;
			}
		}
	}
	return map CaseSensFile(rel2abs($_,$basedir)), @list;
}

sub Import_playlist_file	#create saved lists from playlist files (.m3u, .pls, ...)
{	my $pl_file=shift;
	warn "Importing $pl_file\n" if $Verbose;
	my @files=Parse_playlist_file($pl_file);
	my @list; my @toadd;
	for my $file (@files)
	{	my $ID=Songs::FindID($file);
		#unless (defined $ID) {warn "Can't find file $file in the library\n"; next}
		unless (defined $ID)
		{	$ID=Songs::New($file);
			push @toadd,$ID if defined $ID;
		}
		#unless (defined $ID) {warn "Can't add file $file\n"; next}
		next unless defined $ID;
		push @list,$ID;
	}
	SongAdd_now(@toadd) if @toadd; #add IDs to the Library if needed
	if (@list) { printf STDERR "$pl_file lists %d files, %d were found, %d were not already in the library\n",scalar @files, scalar @list, scalar @toadd if $Verbose || @files!=@list; }
	else { warn "No file from '$pl_file' found in the library\n"; return }
	my $name= filename_to_unicode(barename($pl_file));
	$name= _"imported list" unless $name=~m/\S/;
	::IncSuffix($name) while $Options{SavedLists}{$name}; #find a new name
	SaveList($name,\@list);
}
sub Choose_and_import_playlist_files
{	my $parentwin= $_[0] && $_[0]->get_toplevel;
	my $pattern=join ' ',map "*.$_", sort keys %playlist_file_parsers;
	my @files=ChooseFiles(_"Choose playlist files to import",
		remember_key=>'LastFolder_playlists', multiple=>1, parent=>$parentwin,
		patterns=>[[_"Playlist files",undef,$pattern ]]);
	Import_playlist_file($_) for @files;
}

sub OpenFiles
{	my $IDs=Uris_to_IDs($_[1]);
	Select(song=>'first',play=>1,staticlist => $IDs) if @$IDs;
}

sub Uris_to_IDs
{	my @urls=split / +/,$_[0];
	#@urls= grep !m#^http://#, @urls;
	$_=decode_url($_) for @urls;
	my @IDs=FolderToIDs(1,1,@urls);
	return \@IDs;
}

sub FolderToIDs
{	my ($add,$recurse,@dirs)=@_;
	s#^file://## for @dirs;
	@dirs= map cleanpath($_), @dirs;
	my @files;
	MakeScanRegex() unless $ScanRegex;
	while (defined(my $dir=shift @dirs))
	{	if (-d $dir)
		{	if (opendir my($DIRH),$dir)
			{	my @list= map $dir.SLASH.$_, grep !m#^\.#, readdir $DIRH;
				closedir $DIRH;
				push @files, grep -f && m/$ScanRegex/, @list;
				push @dirs, grep -d, @list   if $recurse;
			}
			else { warn "Can't open folder $dir : $!\n"; }
		}
		elsif (-f $dir)
		{	if ($dir=~m/$ScanRegex/) { push @files,$dir; }
			elsif ($dir=~m/\.([^.]*)$/ && $playlist_file_parsers{lc $1}) #playlist files (.m3u, .pls, ...)
			{	push @files, Parse_playlist_file($dir);
			}
		}
	}
	my @IDs; my @toadd;
	for my $file (@files)
	{	my $ID=Songs::FindID($file);# check if missing => check if modified
		unless (defined $ID)
		{	$ID=Songs::New($file);
			push @toadd,$ID if defined $ID;
		}
		push @IDs,$ID if defined $ID;
	}
	SongAdd_now(@toadd) if $add && @toadd; #add IDs to the Library if needed
	return @IDs;
}

sub MakeScanRegex
{	my %ext; $ext{$_}=1 for @ScanExt;
	my $ignore= $Options{ScanIgnore} || [];
	delete $ext{$_} for @$ignore;
	my $re=join '|', sort keys %ext;
	warn "Scan regular expression is empty\n" unless $re;
	$ScanRegex=qr/\.(?:$re)$/i;
}

sub ScanFolder
{	warn "Scanning : @_\n" if $Verbose;
	my $dir=$_[0];
	$dir=~s#^file://##;
	$dir=cleanpath($dir);
	MakeScanRegex() unless $ScanRegex;
	Songs::Build_IDFromFile() unless $Songs::IDFromFile;
	$ScanProgress_cb ||= Glib::Timeout->add(500,\&ScanProgress_cb);
	my @files;
	if (-d $dir)
	{	if (opendir my($DIRH),$dir)
		{	@files=readdir $DIRH;
			closedir $DIRH;
		}
		else { warn "ScanFolder: can't open folder $dir : $!\n"; return }
	}
	elsif (-f $dir)
	{	($dir,my $file)=splitpath($dir);
		@files=($file) if $file;
	}
	else {warn "ScanFolder: can't find $dir\n"}
	#my @toadd;
	for my $file (@files)
	{	next if $file=~m#^\.#;		# skip . .. and hidden files/folders
		my $path_file=$dir.SLASH.$file;
		#if (-d $path_file) { push @ToScan,$path_file; next; }
		if (-d $path_file)
		{	#next if $notrecursive;
			# make sure it doesn't look in the same dir twice due to symlinks
			my $real= -l $path_file ? simplify_path(rel2abs(readlink($path_file),$dir)) : $path_file;
			next if exists $FollowedDirs{$real};
			$FollowedDirs{$real}=undef;
			push @ToScan,$path_file;
			next;
		}
		next unless $file=~$ScanRegex;
		#my $ID=Songs::FindID($path_file);
		my $ID=$Songs::IDFromFile->{$dir}{$file};
		if (defined $ID)
		{	next unless Songs::Get($ID,'missing');
			Songs::Set($ID,missing => 0);
			$ToReRead->add($ID);	#or $ToCheck ? 
			push @ToAdd_IDsBuffer,$ID;
		}
		else
		{	#$ID=Songs::New($path_file);
			push @ToAdd_Files, $path_file;
		}
	}
	unless (@ToScan)
	{	AbortScan();
	}
	&launchIdleLoop unless $IdleLoop;
}

sub CheckProgress_cb
{	my $init=$_[0];
	$CheckProgress_cb||=Glib::Timeout->add(500, \&CheckProgress_cb,0);
	return if $init;
	my @job_id=qw/check reread lengthcheck/;
	my $running;
	for my $jobarray ($ToCheck,$ToReRead,$ToCheckLength)
	{	my $id=shift @job_id;
		if (@$jobarray)
		{	::Progress($id,	aborthint=>_"Stop checking",
					bartext	=> '$current / $end',
					abortcb	=> sub { $jobarray->abort; },
					$jobarray->progress, #returns title, details(optional), current, end
			);
			$running=1;
		}
		elsif ($Progress{$id}) { ::Progress($id, abort=>1); }
	}
	return 1 if $running;
	return $CheckProgress_cb=0;
}

sub AbortScan
{	@ToScan=(); undef %FollowedDirs;
}
sub ScanProgress_cb
{	if (@ToScan || @ToAdd_Files)
	{	my $total= @ToScan + $ProgressNBFolders;
		Progress('scan',title	=> _"Scanning",
				details	=> __("%d song added","%d songs added", $ProgressNBSongs),
				bartext	=>__("%d folder","%d folders", $ProgressNBFolders),
				current	=> $ProgressNBFolders,
				end	=>$total,
				abortcb	=>\&AbortScan,
				aborthint=> _"Stop scanning",
			);
		return 1;
	}
	else
	{	::Progress('scan', abort=>1);
		return $ScanProgress_cb=0;
	}
}

sub AutoSelPictures
{	my ($field,@gids)=@_;
	my $ref= $AutoPicChooser{$field} ||= { todo=>[] };
	unshift @{$ref->{todo}}, @gids;
	$ref->{idle}||= Glib::Idle->add(\&AutoSelPictures_do_next,$field);
	$ref->{timeout}||= Glib::Timeout->add(1000,\&AutoSelPictures_progress_cb,$field);	#if @{$ref->{todo}}>10 ??
}
sub AutoSelPictures_do_next
{	my $field=shift;
	my $ref= $AutoPicChooser{$field};
	return 0 unless $ref;
	my $gid= shift @{$ref->{todo}};
	AutoSelPicture($field,$gid);
	$ref->{done}++;
	return 1 if @{$ref->{todo}};
	delete $AutoPicChooser{$field};
	return 0;
}
sub AutoSelPictures_progress_cb
{	my $field=shift;
	my $ref= $AutoPicChooser{$field};
	unless ($ref) { Progress('autopic_'.$field, abort=>1); return 0; }
	return 0 unless $ref;
	my $done= $ref->{done}||0;
	Progress('autopic_'.$field, title => _"Selecting pictures", current=> $done, end=> $done+@{$ref->{todo}}, abortcb=> sub { delete $AutoPicChooser{$field}; }, aborthint=> _"Stop selecting pictures", );
	return scalar @{$ref->{todo}};
}

sub AutoSelPicture
{	my ($field,$gid,$force)=@_;

	unless ($force)
	# return if picture already set and existing
	{	my $file= AAPicture::GetPicture($field,$gid);
		if (defined $file)
		{	return unless $file; # file eq '0' => no picture
			if ($file=~m/\.(?:mp3|flac|m4a|m4b|oga|ogg)(?::\w+)?$/) { return if FileTag::PixFromMusicFile($file,undef,1); }
			else { return if -e $file }
		}
	}

	my $IDs= AA::GetIDs($field,$gid);
	return unless @$IDs;

	my $set;
	my %pictures_files;
	for my $m (qw/embedded guess/)
	{	if ($m eq 'embedded')
		{	my @files= grep m/\.(?:mp3|flac|m4a|m4b|ogg|oga)$/i, Songs::Map('fullfilename',$IDs);
			if (@files)
			{	$set= first { FileTag::PixFromMusicFile($_,$field,1) && $_ } sort @files;
			}
		}
		elsif ($m eq 'guess')
		{	warn "Selecting cover for ".Songs::Gid_to_Get($field,$gid)."\n" if $::debug;

			my $path= Songs::BuildHash('path', $IDs);
			for my $folder (keys %$path)
			{	my $count_in_folder= AA::Get('id:count','path',$folder);
				#warn " removing $folder $count_in_folder != $path->{$folder}\n" if $count_in_folder != $path->{$folder} if $::debug;
				delete $path->{$folder} if $count_in_folder != $path->{$folder};
			}
			next unless keys %$path;
			my $common= find_common_parent_folder(keys %$path);
			if (length $common >5)	# ignore common parent folder if too short #FIXME compare the depth of $common with others, ignore it if more than 1 or 2 depth diff
			{	if (!$path->{$common})
				{	my $l=Filter->new( 'path:i:'.$common)->filter;
					#warn " common=$common ".scalar(@$l)." == ".scalar(@$IDs)." ? \n" if $::debug;
					$common=undef if @$l != @$IDs;
				}
				$path->{$common}= @$IDs if $common;
			}
			my @folders= sort { $path->{$b} <=> $path->{$a} } keys %$path;

			my @words= split / +/, Songs::Gid_to_Get($field,$gid);
			tr/0-9A-Za-z//cd for @words;
			@words=grep length>2, @words;

			my %found;
			for my $folder (@folders)
			{	opendir my($dh), $folder;
				for my $file (grep m/$Image_ext_re/, readdir $dh)
				{	my $score=0;
					if ($field eq 'album') { $score+=100 if $file=~m/(?:^|[^a-zA-Z])(?:cover|front|folder|thumb|thumbnail)[^a-zA-Z]/i; }
					elsif ( index($file,$field)!=-1 ) { $score+=10 }
					#$score-- if $file=~m/\b(?:back|cd|inside|booklet)\b/;
					$score++ if $file=~m/\.jpe?g$/;
					$score+=10 for grep index($file,$_)!=-1, @words;
					$found{ $folder.SLASH.$file }= $score;
					warn " $file $score\n" if $::debug;
				}
				last if %found; #don't look in other folders if found at least a picture
			}
			($set)= sort { $found{$b} <=> $found{$a} } keys %found;
		}
		last if $set;
	}
	if ($set) { AAPicture::SetPicture($field, $gid, $set); }
}


sub AboutDialog
{	my $dialog=Gtk2::AboutDialog->new;
	$dialog->set_version(VERSIONSTRING);
	$dialog->set_copyright("Copyright © 2005-2014 Quentin Sculo");
	#$dialog->set_comments();
	$dialog->set_license("Released under the GNU General Public Licence version 3\n(http://www.gnu.org/copyleft/gpl.html)");
	$dialog->set_website('http://gmusicbrowser.org');
	$dialog->set_authors('Quentin Sculo <squentin@free.fr>');
	$dialog->set_artists("tango icon theme : Jean-Philippe Guillemin\nelementary icon theme : Simon Steinbeiß");
	$dialog->set_translator_credits( join "\n", sort
		'French : Quentin Sculo, Jonathan Fretin, Frédéric Urbain, Brice Boucard, Hornblende & mgrubert',
		'Hungarian : Zsombor',
		'Spanish : Martintxo, Juanjo & Elega',
		'German : vlad & staubi',
		'Polish : Robert Wojewódzki, tizzilzol team',
		'Swedish : Olle Sandgren',
		'Chinese : jk',
		'Czech : Vašek Kovářík',
		'Portuguese : Sérgio Marques',
		'Portuguese (Brazillian) : Gleriston Sampaio',
		'Korean : bluealbum',
		'Russian : tin',
		'Italian : Michele Giampaolo',
		'Dutch : Gijs Timmers',
		'Japanese : Sunatomo',
		'Serbian : Саша Петровић',
		'Finnish : Jiri Grönroos',
		'Chinese(Taiwan) : Hiunn-hué',
		'Greek : Elias',
	);
	$dialog->signal_connect( response => sub { $_[0]->destroy if $_[1] eq 'cancel'; }); #used to worked without this, see http://mail.gnome.org/archives/gtk-perl-list/2006-November/msg00035.html
	$dialog->show_all;
}

sub PrefDialog
{	my $goto= $_[0] || $Options{LastPrefPage} || 'library';
	if ($OptionsDialog) { $OptionsDialog->force_present; }
	else
	{	$OptionsDialog=my $dialog = Gtk2::Dialog->new (_"Settings", undef,[]);
		my $about_button=$dialog->add_button('gtk-about',1);
		$dialog->add_button('gtk-close','close');
		my $bb=$about_button->parent;
		if ($bb && $bb->isa('Gtk2::ButtonBox')) { $bb->set_child_secondary($about_button,1); }
		$dialog->set_default_response ('close');
		SetWSize($dialog,'Pref');

		my $notebook = Gtk2::Notebook->new;
		for my $pagedef
		(	[library=>_"Library",	PrefLibrary()],
			#[labels=>_"Labels",	PrefLabels()],
			[audio	=>_"Audio",	PrefAudio()],
			[layouts=>_"Layouts",	PrefLayouts()],
			[misc	=>_"Misc.",	PrefMisc()],
			[fields	=>_"Fields",	Songs::PrefFields()],
			[plugins=>_"Plugins",	PrefPlugins()],
			[keys	=>_"Keys",	PrefKeys()],
			[tags	=>_"Tags",	PrefTags()],

		)
		{	my ($key,$label,$page)=@$pagedef;
			$notebook->append_page( $page, Gtk2::Label->new($label));
			$notebook->{pages}{$key}=$page;
		}
		$notebook->signal_connect(switch_page=> sub
		{	my $page=$_[0]->get_nth_page($_[2]);
			my $h=$_[0]{pages};
			($Options{LastPrefPage})=grep $h->{$_}==$page, keys %$h;
		});
		$dialog->{notebook}=$notebook;
		$dialog->vbox->pack_start($notebook,TRUE,TRUE,4);

		$dialog->signal_connect( response => sub
		{	if ($_[1] eq '1') {AboutDialog();return};
			$OptionsDialog=undef;
			$_[0]->destroy;
		});
		$dialog->show_all;
	}

	# turn to $goto page
	($goto,my $arg)= split /:/,$goto,2;
	my $notebook= $OptionsDialog->{notebook};
	if (my $page=$notebook->{pages}{$goto})
	{	$notebook->set_current_page($notebook->page_num($page));
		if ($arg && $page->{gotofunc}) { $page->{gotofunc}->($arg) }
	}
}

sub PrefKeys
{	my $vbox=Gtk2::VBox->new;
	my $store=Gtk2::ListStore->new(('Glib::String')x3);
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
	 ( _"Key",Gtk2::CellRendererText->new,text => 0
	 ));
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
	 ( _"Command",Gtk2::CellRendererText->new,text => 1
	 ));
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($treeview);
	$vbox->add($sw);

	my $refresh_sub=sub
	 {	$store->clear;
		my $list= $Options{CustomKeyBindings};
		for my $key (sort keys %$list)
		{	my ($cmd,$arg)=  $list->{$key}=~m/^(\w+)(?:\((.*)\))?$/;
			$cmd=$Command{$cmd}[1];
			$cmd.="($arg)" if defined $arg;
			my $longkey=keybinding_longname($key);
			$store->set($store->append,0,$longkey,1,$cmd,2,$key);
		}
		%CustomBoundKeys=%{ make_keybindingshash($Options{CustomKeyBindings}) };
	 };

	my $refresh_sensitive;
	my $key_entry=Gtk2::Entry->new;
	$key_entry->{key}='';
	$key_entry->set_tooltip_text(_"Press a key or a key combination");
	$key_entry->set_editable(FALSE);
	$key_entry->signal_connect(key_press_event => sub
	 {	my ($entry,$event)=@_;
		my $keyname=Gtk2::Gdk->keyval_name($event->keyval);
		my $mod; #warn $event->state; warn $keyname;
		$mod.='c' if $event->state >= 'control-mask';
		$mod.='a' if $event->state >= 'mod1-mask';
		$mod.='w' if $event->state >= 'mod4-mask'; # use 'super-mask' ???
		$mod.='s' if $event->state >= 'shift-mask';
		#warn "mod=$mod";
		if (defined $keyname && !WordIn($keyname,'Shift_L Control_L Alt_L Super_L ISO_Level3_Shift Multi_key Menu Control_R Shift_R'))
		{	$keyname=$mod.'-'.$keyname if $mod;
			$entry->{key}=$keyname;
			$keyname=keybinding_longname($keyname);
			$entry->set_text($keyname);
			&$refresh_sensitive;
		}
		return 1;
	 });

	my $combochanged;
	my $entry_extra=Gtk2::Alignment->new(.5,.5,1,1);
	my $combo=TextCombo->new( {map {$_ => $Command{$_}[1]}
					sort {$Command{$a}[1] cmp $Command{$b}[1]}
					grep defined $Command{$_}[1] && !defined $Command{$_}[3] || ref $Command{$_}[3],
					keys %Command
				  });
	my $vsg=Gtk2::SizeGroup->new('vertical');
	$vsg->add_widget($_) for $key_entry,$combo;
	$combochanged=sub
	 {	my $cmd=$combo->get_value;
		my $child=$entry_extra->child;
		$entry_extra->remove($child) if $child;
		if ($Command{$cmd}[2])
		{	$entry_extra->set_tooltip_text($Command{$cmd}[2]);
			$child= (ref $Command{$cmd}[3] eq 'CODE')?	$Command{$cmd}[3]()  : Gtk2::Entry->new;
			$child->signal_connect(changed => $refresh_sensitive);
			$entry_extra->add( $child );
			$vsg->add_widget($child);
			$entry_extra->parent->show_all;
		}
		else
		{	$entry_extra->parent->hide;
		}
		&$refresh_sensitive;
	 };
	$combo->signal_connect( changed => $combochanged );

	my $butadd= ::NewIconButton('gtk-add',_"Add shorcut key",sub
	 {	my $cmd=$combo->get_value;
		return unless defined $cmd;
		my $key=$key_entry->{key};
		return if $key eq '';
		if (my $child=$entry_extra->child)
		{	my $extra= (ref $child eq 'Gtk2::Entry')? $child->get_text : $child->get_value;
			$cmd.="($extra)" if $extra ne '';
		}
		$Options{CustomKeyBindings}{$key}=$cmd;
		&$refresh_sub;
	 });
	my $butrm=  ::NewIconButton('gtk-remove',_"Remove",sub
	 {	my $iter=$treeview->get_selection->get_selected;
		my $key=$store->get($iter,2);
		delete $Options{CustomKeyBindings}{$key};
		&$refresh_sub;
	 });

	$treeview->get_selection->signal_connect(changed => sub
	 {	$butrm->set_sensitive( $_[0]->count_selected_rows );
	 });
	$_->set_sensitive(FALSE) for $butadd,$butrm;
	$refresh_sensitive=sub
	 {	my $ok=0;
		{	last if $key_entry->{key} eq '';
			my $cmd=$combo->get_value;
			last unless defined $cmd;
			if ($Command{$cmd}[2])	{ my $re=$Command{$cmd}[3]; last if $re && ref($re) ne 'CODE' && $entry_extra->child->get_text!~m/$re/; }
			$ok=1;
		}
		$butadd->set_sensitive( $ok );
	 };


	 $vbox->pack_start(
	   Vpack([	[ 0, Gtk2::Label->new(_"Key") , $key_entry ],
			[ 0, Gtk2::Label->new(_"Command") , $combo ],
			[ 0, Gtk2::Label->new(_"Arguments") , $entry_extra ],
		  ],[$butadd,$butrm]
		),FALSE,FALSE,2);
	&$refresh_sub;
	&$combochanged;

	return $vbox;
}

sub PrefPlugins
{	LoadPlugins();
	my $hbox=Gtk2::HBox->new;
	unless (keys %Plugins) {my $label=Gtk2::Label->new(_"no plugins found"); $hbox->add($label);return $hbox}
	my $store=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::Boolean');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(FALSE);
	my $renderer = Gtk2::CellRendererToggle->new;
	my $rightbox=Gtk2::VBox->new;
	my $plugtitle=Gtk2::Label->new;
	my $plugdesc=Gtk2::Label->new;
	$plugdesc->set_line_wrap(1);
	$plugtitle->set_justify('center');
	my $plug_box;
	my $plugin;

	my $sub_update= sub
	 {	return unless $plugin;
		my $pref=$Plugins{$plugin};
		if ($plug_box && $plug_box->parent) { $plug_box->parent->remove($plug_box); }
		my $title= MarkupFormat('<b>%s</b>', $pref->{title}||$pref->{name} );
		$title.= "\n". MarkupFormat('<small><a href="%s">%s</a></small>', $pref->{url},$pref->{url} )	if $pref->{url};
		if (my $aref=$pref->{author})
		{	my ($format,@vars)= ('%s : ', _"by");
			for my $author (@$aref)
			{	if ($author=~m/(.*?)\s*<([-\w.]+@[-\w.]+)>$/)	#format : Name <email@example.com>
				{	$format.='<a href="mailto:%s">%s</a>, ';
					push @vars, $2,$1;
				}
				else
				{	$format.='%s, ';
					push @vars, $author;
				}
			}
			$format=~s/, $//;
			$title.= "\n". MarkupFormat("<small>$format</small>",@vars);
		}
		$plugtitle->set_markup($title);
		$plugdesc->set_text( $pref->{desc} );
		if (my $error=$pref->{error})
		{	$plug_box=Gtk2::Label->new;
			if (my $req= CheckPluginRequirement($plugin) )
			{	$plug_box->set_markup($req);
			}
			else
			{	$error=PangoEsc($error);
				$error=~s#(\(\@INC contains: .*)#<small>$1</small>#s;
				$plug_box->set_markup( MarkupFormat("<b>%s</b>\n", _("Error :")) .$error);
				$plug_box->set_line_wrap(1);
			}
			$plug_box->set_selectable(1);
		}
		elsif ($pref->{loaded})
		{	my $package='GMB::Plugin::'.$plugin;
			$plug_box=$package->prefbox;
			$plug_box->set_sensitive(0) if $plug_box && !$Options{'PLUGIN_'.$plugin};
		}
		else
		{	$plug_box=Gtk2::Label->new(_"Plugin not loaded");
		}
		if ($plug_box)
		{	$rightbox->add($plug_box);
			$plug_box->show_all;
		}
	 };

	$renderer->signal_connect(toggled => sub
	 {	my ($cell, $path_string)=@_;
		my $iter=$store->get_iter_from_string($path_string);
		my $plugin=$store->get($iter, 0);
		my $key='PLUGIN_'.$plugin;
		if ($Options{$key})	{DeactivatePlugin($plugin)}
		else			{ActivatePlugin($plugin)}
		&$sub_update;
		$store->set ($iter, 2, $Options{$key});
	 });
	$treeview->append_column
	 ( Gtk2::TreeViewColumn->new_with_attributes('on',$renderer,active => 2)
	 );
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
	 ( 'plugin name',Gtk2::CellRendererText->new,text => 1
	 ));
	$store->set($store->append,0,$_,1,$Plugins{$_}{name},2,$Options{'PLUGIN_'.$_})
		for sort {lc$Plugins{$a}{name} cmp lc$Plugins{$b}{name}} keys %Plugins;
	#my $plugin;
	$treeview->signal_connect(cursor_changed => sub
		{	my $path=($treeview->get_cursor)[0];
			$plugin=$store->get( $store->get_iter($path), 0);
			&$sub_update;
		});

	$hbox->{gotofunc}=sub	#go to a specific row
	{	my $plugin=shift;
		my $iter= $store->get_iter_first;
		while ($iter)
		{	if (lc($store->get($iter,0)) eq lc$plugin) { $treeview->set_cursor($store->get_path($iter)); last; }
			$iter=$store->iter_next($iter);
		}
	};

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($treeview);
	$hbox->pack_start($sw,FALSE,FALSE,2);
	$rightbox->pack_start($plugtitle,FALSE,FALSE,2);
	$rightbox->pack_start($plugdesc,FALSE,FALSE,2);
	$hbox->add($rightbox);
	return $hbox;
}
sub LogView
{	my $store=shift;
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
	 ( 'log',Gtk2::CellRendererText->new,text => 0
	 ));
	$treeview->set_headers_visible(FALSE);
	return new_scrolledwindow($treeview,'etched-in');
}
sub SetDefaultOptions
{	my $prefix=shift;
	while (my ($key,$val)=splice @_,0,2)
	{	$Options{$prefix.$key}=$val unless defined $Options{$prefix.$key};
	}
}

sub PrefAudio
{	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my ($radio_gst,$radio_123,$radio_mp,$radio_ice)=NewPrefRadio('AudioOut',
		[ gstreamer		=> 'Play_GST',
		  'mpg123/ogg123/...'	=> 'Play_123',
		  mplayer		=> 'Play_mplayer',
		  _"icecast server"	=> sub {$Options{use_GST_for_server}? 'Play_GST_server' : 'Play_Server'},
		], cb=>sub
		{	my $p=$Options{AudioOut};
			return if $PlayPacks{$p}==$Play_package;
			$PlayNext_package=$PlayPacks{$p};
			SwitchPlayPackage() unless defined $PlayTime;
			$ScanRegex=undef;
		}, markup=> '<b>%s</b>',);

	#123
	my $vbox_123=Gtk2::VBox->new (FALSE, 2);
	my $adv1=PrefAudio_makeadv('Play_123','123');
	$vbox_123->pack_start($_,FALSE,FALSE,2) for $radio_123,$adv1;

	#gstreamer
	my $vbox_gst=Gtk2::VBox->new (FALSE, 2);
	if (exists $PlayPacks{Play_GST})
	{	my $hbox2=NewPrefCombo(gst_sink => Play_GST->supported_sinks, text => _"output device :", sizeg1=>$sg1, sizeg2=> $sg2);
		my $EQbut=Gtk2::Button->new(_"Open Equalizer");
		$EQbut->signal_connect(clicked => sub { OpenSpecialWindow('Equalizer'); });
		my $EQcheck=NewPrefCheckButton(gst_use_equalizer => _"Use Equalizer", cb=>sub { HasChanged('Equalizer'); });
		$sg1->add_widget($EQcheck);
		$sg2->add_widget($EQbut);
		my $EQbox=Hpack($EQcheck,$EQbut);
		$EQbox->set_sensitive(0) unless $PlayPacks{Play_GST} && $PlayPacks{Play_GST}{EQ};
		my $adv2=PrefAudio_makeadv('Play_GST','gstreamer');
		my $albox=Gtk2::Alignment->new(0,0,1,1);
		$albox->set_padding(0,0,15,0);
		$albox->add(Vpack($hbox2,$EQbox,$adv2));
		$vbox_gst->pack_start($_,FALSE,FALSE,2) for $radio_gst,$albox;
	}
	else
	{	$vbox_gst->pack_start($_,FALSE,FALSE,2) for $radio_gst,Gtk2::Label->new(_"GStreamer module not loaded.");
	}

	#icecast
	my $vbox_ice=Gtk2::VBox->new(FALSE, 2);
	$Options{use_GST_for_server}=0 unless $PlayPacks{Play_GST_server};
	my $usegst=NewPrefCheckButton(use_GST_for_server => _"Use gstreamer",cb=>sub {$radio_ice->signal_emit('toggled');}, tip=>_"without gstreamer : one stream per file, one connection at a time\nwith gstreamer : one continuous stream, multiple connection possible");
	my $hbox3=NewPrefEntry('Icecast_port',_"port :");
	my $albox=Gtk2::Alignment->new(0,0,1,1);
	$albox->set_padding(0,0,15,0);
	$albox->add(Vpack($usegst,$hbox3));
	$vbox_ice->pack_start($_,FALSE,FALSE,2) for $radio_ice,$albox;

	#mplayer
	my $vbox_mp=Gtk2::VBox->new(FALSE, 2);
	my $adv4=PrefAudio_makeadv('Play_mplayer','mplayer');
	$vbox_mp->pack_start($_,FALSE,FALSE,2) for $radio_mp,$adv4;

	$vbox_123->set_sensitive($PlayPacks{Play_123});
	$vbox_gst->set_sensitive($PlayPacks{Play_GST});
	$vbox_ice->set_sensitive($PlayPacks{Play_Server});
	$vbox_mp ->set_sensitive($PlayPacks{Play_mplayer});
	$usegst->set_sensitive($PlayPacks{Play_GST_server});

	#replaygain
	my $rg_check= ::NewPrefCheckButton(gst_use_replaygain => _"Use ReplayGain", tip=>_"Normalize volume (the files must have replaygain tags)", cb=>\&Set_replaygain );
	my $rg_cb= sub { my $p=$Options{AudioOut}; $p&&=$PlayPacks{$p}; $_[0]->set_sensitive( $p && $p->{RG} ); };
	Watch($rg_check, Option=> $rg_cb );
	$rg_cb->($rg_check);
	my $rga_start=Gtk2::Button->new(_"Start ReplayGain analysis");
	$rga_start->set_tooltip_text(_"Analyse and add replaygain tags for all songs that don't have replaygain tags, or incoherent album replaygain tags");
	$rga_start->signal_connect(clicked => \&GMB::GST_ReplayGain::Analyse_full);
	$rga_start->set_sensitive($Play_GST::GST_RGA_ok);
	my $rg_opt= Gtk2::Button->new(_"ReplayGain options");
	$rg_opt->signal_connect(clicked => \&replaygain_options_dialog);
	$sg1->add_widget($rg_check);
	$sg2->add_widget($rg_opt);

	my $vbox=Vpack( $vbox_gst, Gtk2::HSeparator->new,
			$vbox_123, Gtk2::HSeparator->new,
			$vbox_mp,  Gtk2::HSeparator->new,
			$vbox_ice, Gtk2::HSeparator->new,
			[$rg_check,$rg_opt,($Glib::VERSION >= 1.251 ? $rga_start : ())],
			NewPrefCheckButton(IgnorePlayError => _"Ignore playback errors", tip=>_"Skip to next song if an error occurs"),
		      );
	return $vbox;
}

sub PrefAudio_makeadv
{	my ($package,$name)=@_;
	$package=$PlayPacks{$package};
	my $hbox=Gtk2::HBox->new(TRUE, 2);
	if (1)
	{	my $label=Gtk2::Label->new;
		$label->signal_connect(realize => sub	#delay finding supported formats because mplayer is slow
			{	my @ext;
				for my $e (grep !$::Alias_ext{$_}, $package->supported_formats)
				{	push @ext, join '/', $e, sort grep $::Alias_ext{$_} eq $e,keys %::Alias_ext;
				}
				my $list=join ' ',sort @ext;
				$_[0]->set_markup_with_format('<small>%s</small>', _("supports : ").$list) if $list;
			}) if $package;
		$hbox->pack_start($label,TRUE,TRUE,4);
	}
	if (1)
	{	my $label=Gtk2::Label->new;
		$label->set_markup_with_format('<small>%s</small>', _"advanced options");
		my $but=Gtk2::Button->new;
		$but->add($label);
		$but->set_relief('none');
		$hbox->pack_start($but,TRUE,TRUE,4);
		$but->signal_connect(clicked =>	sub #create dialog
		 {	my $but=$_[0];
			if ($but->{dialog} && !$but->{dialog}{destroyed}) { $but->{dialog}->force_present; return; }
			my $d=$but->{dialog}= Gtk2::Dialog->new(__x(_"{outputname} output settings",outputname => $name), undef,[],'gtk-close' => 'close');
			$d->set_default_response('close');
			my $box=$package->AdvancedOptions;
			$d->vbox->add($box);
			$d->signal_connect( response => sub { $_[0]{destroyed}=1; $_[0]->destroy; });
			$d->show_all;
		 });
	}
	return $hbox;
}

my $RG_dialog;
sub replaygain_options_dialog
{	if ($RG_dialog) {$RG_dialog->force_present;return}
	$RG_dialog= Gtk2::Dialog->new (_"ReplayGain options", undef, [], 'gtk-close' => 'close');
	$RG_dialog->signal_connect(destroy => sub {$RG_dialog=undef});
	$RG_dialog->signal_connect(response =>sub {$_[0]->destroy});
	my $songmenu=::NewPrefCheckButton(gst_rg_songmenu => _("Show replaygain submenu").($Glib::VERSION >= 1.251 ? '' : ' '._"(unstable)"));
	my $albummode=::NewPrefCheckButton(gst_rg_albummode => _"Album mode", cb=>\&Set_replaygain, tip=>_"Use album normalization instead of track normalization");
	my $nolimiter=::NewPrefCheckButton(gst_rg_limiter => _"Hard limiter", cb=>\&Set_replaygain, tip=>_"Used for clipping prevention");
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $preamp=	::NewPrefSpinButton('gst_rg_preamp',   -60,60, cb=>\&Set_replaygain, digits=>1, rate=>.1, step=>.1, sizeg1=>$sg1, sizeg2=>$sg2, text=>_"pre-amp : %d dB", tip=>_"Extra gain");
	my $fallback=	::NewPrefSpinButton('gst_rg_fallback', -60,60, cb=>\&Set_replaygain, digits=>1, rate=>.1, step=>.1, sizeg1=>$sg1, sizeg2=>$sg2, text=>_"fallback-gain : %d dB", tip=>_"Gain for songs missing replaygain tags");
	$RG_dialog->vbox->pack_start($_,0,0,2) for $albummode,$preamp,$fallback,$nolimiter,$songmenu;
	$RG_dialog->show_all;

	$songmenu->set_sensitive( $Play_GST::GST_RGA_ok );
	# nolimiter not available with mplayer
	my $nolimiter_update= sub { $_[0]->set_sensitive( $Options{AudioOut} ne 'Play_mplayer'); };
	Watch($nolimiter, Option=> $nolimiter_update );
	$nolimiter_update->($nolimiter);
}
sub Set_replaygain { $Play_package->RG_set_options() if $Play_package->can('RG_set_options'); }

sub PrefMisc
{	#Default rating
	my $DefRating=NewPrefSpinButton('DefaultRating',0,100, step=>10, page=>20, text=>_"Default rating : %d %", cb=> sub
		{ IdleDo('0_DefaultRating',500,\&Songs::UpdateDefaultRating);
		});

	my $checkR1=NewPrefCheckButton(RememberPlayFilter => _"Remember last Filter/Playlist between sessions");
	my $checkR3=NewPrefCheckButton( RememberPlayTime  => _"Remember playing position between sessions");
	my $checkR2=NewPrefCheckButton( RememberPlaySong  => _"Remember playing song between sessions", widget=> $checkR3);
	my $checkR4=NewPrefCheckButton( RememberQueue  => _"Remember queue between sessions");

	#Proxy
	my $ProxyCheck=NewPrefCheckButton(Simplehttp_Proxy => _"Connect through a proxy",
		widget=>Hpack(	NewPrefEntry(Simplehttp_ProxyHost => _"Proxy host :"),
				NewPrefEntry(Simplehttp_ProxyPort => _"port :"),
			)
		);

	#xdg-screensaver
	my $screensaver=NewPrefCheckButton(StopScreensaver => _"Disable screensaver when fullscreen and playing", tip=>_"requires xdg-screensaver");
	$screensaver->set_sensitive(0) unless findcmd('xdg-screensaver');
	#shutdown
	my $shutentry=NewPrefEntry(Shutdown_cmd => _"Shutdown command :", tip => _"Command used when\n'turn off computer when queue empty'\nis selected", cb=> \&Update_QueueActionList);

	#artist splitting
	my $asplit= NewPrefMultiCombo( Artists_split_re=>\%Artists_split,
		text=>_"Split artist names on :", tip=>_"Used for the Artists field", separator=> '  ',
		empty=>_"no splitting", cb=>\&Songs::UpdateArtistsRE );
	#artist in title
	my $atitle= NewPrefMultiCombo( Artists_title_re=>\%Artists_from_title,
		text=>_"Extract guest artist from title :", tip=>_"Used for the Artists field", separator=> '  ',
		empty=>_"ignore title", cb=>\&Songs::UpdateArtistsRE );

	#date format
	my $dateex= mktime(5,4,3,2,0,(localtime)[5]);
	my $datetip= join "\n", _"use standard strftime variables",	_"examples :",
			map( sprintf("%s : %s",$_,strftime_utf8($_,localtime($dateex))), split(/ *\| */,"%a %b %d %H:%M:%S %Y | %A %B %I:%M:%S %p %Y | %d/%m/%y %H:%M | %X %x | %F %r | %c | %s") ),
			'',
			_"Additionally this format can be used :\n default number1 format1 number2 format2 ...\n dates more recent than number1 seconds will use format1, ...";
	my $datefmt=NewPrefEntry(DateFormat => _"Date format :", tip => $datetip, history=> 'DateFormat_history');
	#%c 604800 %A %X 86400 Today %X
	my $preview= Label::Preview->new
	(	event => 'Option', format=> MarkupFormat('<small><i>%s</i></small>', _"example : %s"),
		preview =>
		# sub { Songs::DateString(localtime $dateex)}
		sub {	my @sec= ($dateex,map time-$_, ($::Options{DateFormat}||'')=~m/(\d+) +/g);
			join "\n", '', map Songs::DateString($_), @sec;
		    }
	);
	my $datealign=Gtk2::Alignment->new(0,.5,0,0);
	$datealign->add($datefmt);

	my $volstep= NewPrefSpinButton('VolumeStep',1,100, step=>1, text=>_"Volume step :", tip=>_"Amount of volume changed by the mouse wheel");
	my $always_in_pl=NewPrefCheckButton(AlwaysInPlaylist => _"Current song must always be in the playlist", tip=> _"- When selecting a song, the playlist filter will be reset if the song is not in it\n- Skip to another song when removing the current song from the playlist");
	my $pixcache= NewPrefSpinButton('PixCacheSize',1,1000, text=>_"Picture cache : %d MB", cb=>\&GMB::Cache::trim);

	my $recent_include_not_played= NewPrefCheckButton(AddNotPlayedToRecent => _"Recent songs include skipped songs that haven't been played.", tip=> _"When changing songs, the previous song is added to the recent list even if not played at all.");

	my $playedpercent= NewPrefSpinButton('PlayedMinPercent'	,0,100,  text=>_"Threshold to count a song as played : %d %");
	my $playedseconds= NewPrefSpinButton('PlayedMinSeconds'	,0,99999,text=>_"or %d seconds");

	my $vbox= Vpack( $checkR1,$checkR2,$checkR4, $DefRating,$ProxyCheck, $asplit, $atitle,
			[0,$datealign,$preview], $screensaver,$shutentry, $always_in_pl,
			$recent_include_not_played, $volstep, $pixcache,
			[ $playedpercent, $playedseconds ],
		);
	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add_with_viewport($vbox);
	return $sw;
}

sub PrefLayouts
{	my $vbox=Gtk2::VBox->new (FALSE, 2);

	#Tray
	my $traytiplength=NewPrefSpinButton('TrayTipTimeLength', 0,100000, step=>100, text=>_"Display tray tip for %d ms");
	my $checkT5=NewPrefCheckButton(StartInTray => _"Start in tray");
	my $checkT2=NewPrefCheckButton(CloseToTray => _"Close to tray");
	my $checkT3=NewPrefCheckButton(ShowTipOnSongChange => _"Show tray tip on song change", widget=>$traytiplength);
	my $checkT4=NewPrefSpinButton('TrayTipDelay', 0,10000, step=>100, text=> _"Delay before showing tray tip popup on mouse over : %d ms", cb=>\&SetTrayTipDelay);
	my $checkT1=NewPrefCheckButton( UseTray => _"Show tray icon",
					cb=> sub { &CreateTrayIcon; },
					widget=> Vpack($checkT5,$checkT4,$checkT3)
					);
	$checkT1->set_sensitive($TrayIconAvailable);

	#layouts
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my @layouts_combos;
	for my $layout	( [ 'Layout', 'G',_"Player window layout :", sub {CreateMainWindow();}, ],
			  [ 'LayoutB','B',_"Browser window layout :", ],
			  [ 'LayoutT','T',_"Tray tip window layout :", ],
			  [ 'LayoutF','F',_"Full screen layout :", ],
			  [ 'LayoutS','S',_"Search window layout :", ],
			)
	{	my ($key,$type,$text,$cb)=@$layout;
		my $combo= NewPrefLayoutCombo($key,$type,$text,$sg1,$sg2,$cb);
		push @layouts_combos, $combo;
	}
	my $reloadlayouts=Gtk2::Alignment->new(0,.5,0,0);
	$reloadlayouts->add( NewIconButton('gtk-refresh',_"Re-load layouts",\&Layout::InitLayouts) );

	#fullscreen button
	my $fullbutton=NewPrefCheckButton(AddFullscreenButton => _"Add a fullscreen button", cb=>sub { Layout::WidgetChangedAutoAdd('Fullscreen'); }, tip=>_"Add a fullscreen button to layouts that can accept extra buttons");


	my $icotheme=NewPrefCombo(IconTheme=> GetIconThemesList(), text =>_"Icon theme :", sizeg1=>$sg1,sizeg2=>$sg2, cb => \&LoadIcons);

	#packing
	$vbox->pack_start($_,FALSE,FALSE,1) for @layouts_combos,$reloadlayouts,$checkT1,$checkT2,$fullbutton,$icotheme;
	return $vbox;
}

sub CreateMainWindow
{	my $layout=shift;
	$layout=$Options{Layout} unless defined $layout;
	$MainWindow->{quitonclose}=0 if $MainWindow;
	$MainWindow=Layout::Window->new( $layout, uniqueid=> 'MainWindow', ifexist => 'replace');
	$MainWindow->{quitonclose}=1;
}

sub PrefTags
{	my $vbox=Gtk2::VBox->new (FALSE, 2);
	my $warning=Gtk2::Label->new;
	$warning->set_markup_with_format('<b>%s</b>', _"Warning : these are advanced options, don't change them unless you know what you are doing.");
	$warning->set_line_wrap(1);
	my $checkv4=NewPrefCheckButton('TAG_write_id3v2.4',_"Create ID3v2 tags as ID3v2.4", tip=>_"Use ID3v2.4 instead of ID3v2.3 when creating an ID3v2 tag, ID3v2.3 are probably better supported by other softwares");
	my $checklatin1=NewPrefCheckButton(TAG_use_latin1_if_possible => _"Use latin1 encoding if possible in id3v2 tags", tip=>_"the default is utf16 for ID3v2.3 and utf8 for ID3v2.4");
	my $check_unsync=NewPrefCheckButton(TAG_no_desync => _"Do not unsynchronise id3v2 tags", tip=>_"itunes doesn't support unsynchronised tags last time I checked, mostly affect tags with pictures");
	my @Encodings= grep {($Encoding_pref{$_}||0)>=-1} Encode->encodings(':all');
	my $id3v1encoding=NewPrefCombo(TAG_id3v1_encoding => \@Encodings, text => _"Encoding used for id3v1 tags :");
	my $nowrite=NewPrefCheckButton(TAG_nowrite_mode => _"Do not write the tags", tip=>_"Will not write the tags except with the advanced tag editing dialog. The changes will be kept in the library instead.\nWarning, the changes for a song will be lost if the tag is re-read.");
	my $noid3v1=NewPrefCheckButton(TAG_id3v1_noautocreate=> _"Do not create an id3v1 tag in mp3 files", tip=>_"Only affect mp3 files that do not already have an id3v1 tag");
	my $updatetags= Gtk2::Button->new(_"Update tags...");
	$updatetags->signal_connect(clicked => \&UpdateTags);
	my $updatetags_box= Gtk2::HBox->new(0,0);
	$updatetags_box->pack_start($updatetags,FALSE,FALSE,2);

	$vbox->pack_start($_,FALSE,FALSE,1) for $warning,$checkv4,$checklatin1,$check_unsync,$id3v1encoding,$noid3v1,$nowrite,$updatetags_box;
	return $vbox;
}

sub UpdateTags
{	my $dialog=Gtk2::Dialog->new(_"Update tags", undef, [],
		'gtk-ok' => 'ok',
		'gtk-cancel' => 'none');
	my $table=Gtk2::Table->new(2,2);
	my %checks;
	$checks{$_}= Songs::FieldName($_) for Songs::WriteableFields();
	my $rowmax= (keys %checks)/3; #split in 3 columns
	my $row=my $col=0;
	for my $field (sorted_keys(\%checks))
	{	my $check= Gtk2::CheckButton->new( $checks{$field} );
		$checks{$field}=$check;
		$table->attach_defaults($check,$col,$col+1,$row,$row+1);
		$row++;
		if ($row>=$rowmax) {$col++; $row=0}
	}
	my $label1= Gtk2::Label->new(_"Write value of selected fields in the tags. Useful for fields that were previously not written to tags, to make sure the current value is written.");
	my $label2= Gtk2::Label->new(_"Selected songs to update :");
	my $IDs;
	$dialog->{label}= my $label3= Gtk2::Label->new(_("Whole library")."\n"._"Drag and drop songs here to replace the selection.");
	$label3->set_justify('center');
	$dialog->vbox->pack_start($_,FALSE,FALSE,4) for $label1, $table, $label2, $label3;
	$_->set_line_wrap(1) for $label1, $label2, $label3;
	$dialog->show_all;
	::set_drag($dialog, dest => [::DRAG_ID,sub { my ($dialog,$type,@IDs)=@_; $IDs=\@IDs; $dialog->{label}->set_text( ::__('%d song','%d songs',scalar @IDs) ); }]);

	$dialog->signal_connect( response => sub
		{	my ($dialog,$response)=@_;
			$IDs||= [@$::Library];
			my @fields= sort grep $checks{$_}->get_active, keys %checks;
			if ($response eq 'ok' && @fields && @$IDs)
			{	$dialog->set_sensitive(0);
				my $progressbar = Gtk2::ProgressBar->new;
				$dialog->vbox->pack_start($progressbar, 0, 0, 0);
				$progressbar->show_all;
				Songs::UpdateTags($IDs,\@fields, progress => $progressbar, callback_finish=> sub {$dialog->destroy});
			}
			else {$dialog->destroy}
		});
}

sub AskRenameFolder
{	my ($parent,$old)=splitpath($_[0]);
	$parent= cleanpath($parent,1);
	my $dialog=Gtk2::Dialog->new(_"Rename folder", undef,
			[qw/modal destroy-with-parent/],
			'gtk-ok' => 'ok',
			'gtk-cancel' => 'none');
	$dialog->set_default_response('ok');
	$dialog->set_border_width(3);
	my $entry=Gtk2::Entry->new;
	$entry->set_activates_default(TRUE);
	$entry->set_text( filename_to_utf8displayname($old) );
	$dialog->vbox->pack_start( Gtk2::Label->new(_"Rename this folder to :") ,FALSE,FALSE,1);
	$dialog->vbox->pack_start($entry,FALSE,FALSE,1);
	$dialog->show_all;
	{	last unless $dialog->run eq 'ok';
		my $new=$entry->get_text;
		last if $new eq '';
		last if $new=~m/$QSLASH/o;	#FIXME allow moving folder
		$old= $parent.$old.SLASH;
		$new= $parent.filename_from_unicode($new).SLASH;
		last if $old eq $new;
		-d $new and ErrorMessage(__x(_"{folder} already exists",folder=> filename_to_utf8displayname($new) )) and last; #FIXME use an error dialog
		rename $old,$new
			or ErrorMessage(__x(_"Renaming {oldname}\nto {newname}\nfailed : {error}",
				oldname=> filename_to_utf8displayname($old),
				newname=> filename_to_utf8displayname($new),
				error=>$!))
			and last; #FIXME use an error dialog
		UpdateFolderNames($old,$new);
	}
	$dialog->destroy;
}

sub MoveFolder #FIXME implement
{	my ($parent,$folder)=splitpath($_[0]);
	$parent= cleanpath($parent,1);
	my $new=ChooseDir(_"Move folder to", path=>$parent);
	return unless $new;
	my $old=$parent.$folder.SLASH;
	$new.=SLASH.$folder.SLASH;
#	if ( move(filename_from_unicode($old),filename_from_unicode($new)) )
	if (0) #FIXME implement move folders
	{	UpdateFolderNames($old,$new);
	}
}

sub UpdateFolderNames
{	my ($oldpath,$newpath)=@_;
	$_=cleanpath($_) for $oldpath,$newpath;
	my $filter= 'path:i:'.Songs::filename_escape($oldpath);
	utf8::upgrade($filter); #for unclear reasons, it is needed for non-utf8 folder names. Things should be clearer once the filter code is changed to keep patterns in variables, instead of including them in the eval
	my $renamed=Songs::AllFilter($filter);

	my $pattern=qr/^\Q$oldpath\E/;
	my @newpath;
	for my $ID (@$renamed)
	{	my $path= Songs::Get($ID,'path');
		$path=~s/$pattern/$newpath/;
		push @newpath,$path;
	}
	Songs::Set($renamed,'@path'=>\@newpath) if @$renamed;

	GMB::Picture::UpdatePixPath($oldpath,$newpath);
}

sub PrefLibrary
{	my $store=Gtk2::ListStore->new('Glib::String','Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(FALSE);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( _"Folders to search for new songs",Gtk2::CellRendererText->new,'text',1)
		);
	my $refresh=sub
	{	my ($store,$changed_key)=@_;
		return if $changed_key && $changed_key ne 'LibraryPath';
		$store->clear;
		$store->set($store->append,0,$_,1,filename_to_utf8displayname(decode_url($_))) for sort @{$Options{LibraryPath}};
	};
	$refresh->($store);
	Watch($store, options => $refresh);
	::set_drag($treeview, dest => [::DRAG_FILE,sub
		{	my ($treeview,$type,@list)=@_;
			AddPath(1,@list);
		}]);

	my $addbut=NewIconButton('gtk-add',_"Add folder", sub { ChooseAddPath(1); });
	my $rmdbut=NewIconButton('gtk-remove',_"Remove");

	my $selection=$treeview->get_selection;
	$selection->set_mode('multiple');
	$selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$rmdbut->set_sensitive($sel);
		});
	$rmdbut->set_sensitive(FALSE);
	$rmdbut->signal_connect( clicked => sub
	{	my @rows= $selection->get_selected_rows;
		for my $path (@rows)
		{	my $iter=$store->get_iter($path);
			next unless $iter;
			my $s= $store->get($iter,0);
			@{$Options{LibraryPath}}=grep $_ ne $s, @{$Options{LibraryPath}};
		}
		HasChanged(options=>'LibraryPath');
	});

	my $sw= new_scrolledwindow($treeview,'etched-in');
	my $extensions= NewPrefMultiCombo(ScanIgnore => {map {$_=>$_} @ScanExt},
		text=>_"Ignored file extensions :", tip=>_"Files with these extensions won't be added", empty=>_"none",
		cb=>sub {$ScanRegex=undef}, );

	my $CScan=NewPrefCheckButton(StartScan => _"Search for new songs on startup");
	my $CCheck=NewPrefCheckButton(StartCheck => _"Check for updated/deleted songs on startup");
	my $BScan= NewIconButton('gtk-refresh',_"scan now", sub { IdleScan();	});
	my $BCheck=NewIconButton('gtk-refresh',_"check now",sub { IdleCheck();	});
	my $label=Gtk2::Label->new(_"Folders to search for new songs");

	my $reorg=Gtk2::Button->new(_("Reorganize files and folders").'...');
	$reorg->signal_connect( clicked => sub
	{	return unless @$Library;
		DialogMassRename(@$Library);
	});

	my $autoremove= NewPrefCheckButton( AutoRemoveCurrentSong => _"Automatically remove current song if not found");
	my $lengthcheck= NewPrefCombo( LengthCheckMode => { never=>_"Never", current=>_"When current song", add=>_"When added", },
		text=>	_"Check real length of mp3",
		tip =>	_("mp3 files without a VBR header requires a full scan to check its real length and bitrate")."\n".
			_('You can force a check for these files by holding shift when selecting "Re-read tags"')
		);
	my $Blengthcheck= NewIconButton('gtk-refresh',_"check length now",sub { CheckLength(); });
	$Blengthcheck->{timeout}= Glib::Timeout->add(1000, \&PrefLibrary_update_checklength_button,$Blengthcheck);#refresh it 1s after creation
	Watch($Blengthcheck,$_=> sub { my ($button,$IDs,$fields)=@_; $button->{timeout}||= Glib::Timeout->add(2000, \&PrefLibrary_update_checklength_button,$button) if !$fields || grep($_ eq 'length_estimated', @$fields); } ) for qw/SongsAdded SongsChanged/; #refresh it 2s after a change

	my $masterfilter= FilterCombo->new( $Options{MasterFilter}, sub { $Options{MasterFilter}=$_[1]; UpdateMasterFilter(); } );
	my $masterfiltercheck= NewPrefCheckButton( MasterFilterOn=> _"Use a master filter", widget=>$masterfilter, cb=>\&UpdateMasterFilter, horizontal=>1 );
	my $librarysize= Label::Preview->new(
		event => 'SongsRemoved SongsAdded',
		preview=> sub
		{	my $listtotal=Filter->new('missing:e:0')->filter_all;
			my $lib= scalar @$Library;
			my $excl= scalar(@$listtotal)-$lib;
			my $s= __("Library size : %d song","Library size : %d songs",$lib);
			$s.= ' '. __("(%d song excluded)", "(%d songs excluded)",$excl) if $excl;
			return $s;

		} );

	my $sg1=Gtk2::SizeGroup->new('horizontal');
	$sg1->add_widget($_) for $BScan,$BCheck,$Blengthcheck;
	my $vbox=Vpack( 1,$label,
			'_',$sw,
			[$addbut,$rmdbut,'-',$reorg],
			[$CCheck,'-',$BCheck],
			[$CScan,'-',$BScan],
			$extensions,
			$autoremove,
			[$lengthcheck,'-',$Blengthcheck],
			$masterfiltercheck,
			$librarysize,
		      );
	return $vbox;
}
sub ChooseAddPath
{	my ($addtolibrary,$allowfiles)=@_;
	$allowfiles&&= [ [_"Music files", undef, join(' ',map '*.'.$_, sort @ScanExt) ], [_"All files",undef,'*']  ];
	my @dirs=ChooseDir(_"Choose folder to add", remember_key=>'LastFolder_Add', multiple=>1, allowfiles=>$allowfiles);
	@dirs=map url_escape($_), @dirs;
	AddPath($addtolibrary,@dirs);
}
sub AddPath
{	my ($addtolibrary,@dirs)=@_;
	s#^file://## for @dirs;
	@dirs= grep !m#^\w+://#, @dirs;
	my $changed;
	for my $dir (@dirs)
	{	my $d=cleanpath(decode_url($dir));
		if (!-d $d) { ScanFolder($d); next }
		IdleScan($d);
		next unless $addtolibrary;
		next if (grep $dir eq $_,@{$Options{LibraryPath}});
		push @{$Options{LibraryPath}},$dir;
		$changed=1;
	}
	HasChanged(options=>'LibraryPath') if $changed;
}
sub PrefLibrary_update_checklength_button
{	my $button=shift;
	my $l= Filter->new('length_estimated:e:1')->filter;
	$button->set_sensitive(@$l>0);
	my $text= @$l ?	__("%d song","%d songs",scalar @$l) :
			_"no songs needs checking";
	$button->set_tooltip_text($text);
	return $button->{timeout}=0;
}

sub RemoveLabel		#FIXME ? label specific
{	my ($field,$gid)=@_;
	my $label= Songs::Gid_to_Display($field,$gid);
	#my $IDlist= Songs::AllFilter( MakeFilterFromGID('label',$gid) );
	my $IDlist= Songs::MakeFilterFromGID($field,$gid)->filter;
	if (my $nb=@$IDlist)
	{	my $dialog = Gtk2::MessageDialog->new
			( ::get_event_window(),
			  [qw/modal destroy-with-parent/],
			  'warning','ok-cancel',
			  __("This label is set for %d song.","This label is set for %d songs.",$nb)."\n".
			  __x(_"Are you sure you want to delete the '{label}' label ?", label => $label)
			);
		$dialog->show_all;
		if ($dialog->run ne 'ok') {$dialog->destroy;return;}
		$dialog->destroy;
		Songs::Set($IDlist,'-label',$label);
	}
	@{$Options{Labels}}= grep $_ ne $label, @{$Options{Labels}};
}

sub PrefLabels	#DELME PHASE1 move the functionality elsewhere
{	my $vbox=Gtk2::VBox->new(FALSE,2);
	my $store=Gtk2::ListStore->new('Glib::String','Glib::Int','Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	my $renderer=Gtk2::CellRendererText->new;
	$renderer->set(editable => TRUE);
	$renderer->signal_connect(edited => sub
	    {	my ($cell,$pathstr,$new)=@_;
		$new=~s/\x00//g;
		return if ($new eq '') || exists $::Labels{$new};
		my $iter=$store->get_iter_from_string($pathstr);
		my ($old,$nb)=$store->get_value($iter);
		return if $new eq $old;
		$store->set($iter,0,$new,2,'label-'.$new);
		$::Labels{$new}=delete $::Labels{$old};
		#FIXME maybe should rename the icon file if it exist
		return unless $nb;
		my $l= Songs::AllFilter( 'label:~:'.$old );
		Songs::Set($l,'+label',$new,'-label',$old);
	    });
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( '',Gtk2::CellRendererPixbuf->new,'stock-id',2)
		);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( _"Label",$renderer,'text',0)
		);
	my $renderer_nb=Gtk2::CellRendererText->new;
	$renderer_nb->set(xalign=>1);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( _"# songs",$renderer_nb,'text',1)
		);
	$treeview->append_column(Gtk2::TreeViewColumn->new); #empty, used to prevent the "# songs" column from being too wide
	my $fillsub=sub
	    {	delete $ToDo{'9_Labels'};
		$store->clear;
		my $set=Songs::BuildHash('label');
		for my $f (@{ Songs::ListAll('label') })
		{	$store->set($store->append, 0,$f, 1,$set->{$f}||0, 2,'label-'.$f);
		}
	    };
	#my $watcher;
	$vbox->signal_connect(realize => sub
		{  #warn "realize @_\n" if $debug;
		   my $sub=sub { IdleDo('9_Labels',3000,$fillsub); };
		   #$watcher=AddWatcher(undef,'label',$sub);
		   &$fillsub;
		 });
	$vbox->signal_connect(unrealize => sub
		{  #warn "unrealize @_\n" if $debug;
		   delete $ToDo{'9_Labels'};
		   #RemoveWatcher($watcher);
		});

	my $delbut=NewIconButton('gtk-remove',_"Remove label",sub
		{	my ($row)=$treeview->get_selection->get_selected_rows;
			return unless defined $row;
			my $iter=$store->get_iter($row);
			my ($label,$nb)=$store->get_value($iter);
			if ($nb)
			{	my $dialog = Gtk2::MessageDialog->new
					( $treeview->get_toplevel,
					  [qw/modal destroy-with-parent/],
					  'warning','ok-cancel','%s',
					  __("This label is set for %d song.","This label is set for %d songs.",$nb)."\n".
					  __x("Are you sure you want to delete the '{label}' label ?", label => $label)
					);
				$dialog->show_all;
				if ($dialog->run ne 'ok') {$dialog->destroy;return;}
				my $l= Songs::AllFilter( 'label:~:'.$label );
				Songs::Set($l,'-label',$label);
				$dialog->destroy;
			}
			$store->remove($iter);
			@{$Options{Labels}}= grep $_ ne $label, @{$Options{Labels}};
		});
	my $addbut=NewIconButton('gtk-add',_"Add label",sub
		{	my $iter=$store->append;
			$store->set($iter,0,'',1,0);
			$treeview->set_cursor($store->get_path($iter), $treeview->get_column(1), TRUE);
		});
#	my $iconbut=NewIconButton('gmb-picture',_"Set icon",sub
#		{	my ($row)=$treeview->get_selection->get_selected_rows;
#			return unless defined $row;
#			my $iter=$store->get_iter($row);
#			my ($label)=$store->get_value($iter);
#			Songs::ChooseIcon('label',$gid); 		#needs gid
#		});

	$delbut->set_sensitive(FALSE);
	#$iconbut->set_sensitive(FALSE);
	$treeview->get_selection->signal_connect( changed => sub
		{	my $s=$_[0]->count_selected_rows;
			$delbut->set_sensitive($s);
			#$iconbut->set_sensitive($s);
		});

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($treeview);
	$vbox->add($sw);
	$vbox->pack_start( Hpack($addbut,$delbut) ,FALSE,FALSE,2); #,$iconbut

	return $vbox;
}

sub SetOption
{	my ($key,$value)=@_;
	$Options{$key}=$value;
	HasChanged(Option => $key);
}

sub NewPrefRadio
{	my ($key,$text_val,%opt)=@_;
	my $sub=$opt{cb};
	my $init=$Options{$key};
	$init='' unless defined $init;
	my $cb=sub
		{	return unless $_[0]->get_active;
			my $val=$_[1];
			$val=&$val if ref $val;
			SetOption($key,$val);
			&$sub if $sub;
		};
	my ($radio,@radios);
	my $i=0;
	while ($i<$#$text_val)
	{	my $text= $text_val->[$i++];
		my $val0= $text_val->[$i++];
		push @radios, $radio=Gtk2::RadioButton->new($radio);
		my $label=Gtk2::Label->new_with_format($opt{markup}||'%s', $text);
		$radio->add($label);
		my $val= ref $val0 ? &$val0 : $val0;
		$radio->set_active(1) if $val eq $init;
		$radio->signal_connect(toggled => $cb,$val0);
	}
	return @radios;
}
sub NewPrefCheckButton
{	my ($key,$text,%opt)=@_;
	my ($sub,$tip,$widget,$horizontal,$sizeg,$toolitem)=@opt{qw/cb tip widget horizontal sizegroup toolitem/};
	my $init= $Options{$key};
	my $check=Gtk2::CheckButton->new($text);
	$sizeg->add_widget($check) if $sizeg;
	$check->set_active(1) if $init;
	$check->signal_connect( toggled => sub
	{	my $val=($_[0]->get_active)? 1 : 0;
		SetOption($_[1],$val);
		$_[0]{dependant_widget}->set_sensitive( $_[0]->get_active )  if $_[0]{dependant_widget};
		&$sub if $sub;
	},$key);
	$check->set_tooltip_text($tip) if defined $tip;
	my $return=$check;
	if ($widget)
	{	if ($horizontal)
		{	$return=Hpack(0,$check,$widget);
		}
		else
		{	my $albox=Gtk2::Alignment->new(0,0,1,1);
			$albox->set_padding(0,0,15,0);
			$albox->add($widget);
			$widget=$albox;
			$return=Vpack($check,$albox);
		}
		::weaken( $check->{dependant_widget}=$widget );
		$widget->set_sensitive(0) unless $init;
	}
	elsif ($toolitem)
	{	my $titem=Gtk2::ToolItem->new;
		$titem->add($check);
		my $item=Gtk2::CheckMenuItem->new($text);
		$item->set_active(1) if $init;
		$titem->set_proxy_menu_item($key,$item);
		$item->signal_connect(toggled => sub
		{	return if $_[0]->{busy};
			$check->set_active($_[0]->get_active);
		});
		$check->signal_connect( toggled => sub
		{	my $item=$_[0]->parent->retrieve_proxy_menu_item;
			$item->{busy}=1;
			$item->set_active($_[0]->get_active);
			delete $item->{busy};
		});
		return $titem;
	}
	return $return;
}
sub NewPrefEntry
{	my ($key,$text,%opt)=@_;
	my ($cb,$sg1,$sg2,$tip,$hide,$expand,$history,$width)=@opt{qw/cb sizeg1 sizeg2 tip hide expand history width/};
	my ($widget,$entry);
	if ($history)
	{	$widget=Gtk2::ComboBoxEntry->new_text;
		$entry= $widget->child;
		my $hist= $Options{$history} || [];
		$widget->append_text($_) for @$hist;
		$widget->signal_connect( destroy => sub { PrefSaveHistory($history,$_[0]->get_active_text); } );
	}
	else { $widget=$entry=Gtk2::Entry->new; }

	$entry->set_width_chars($width) if $width;

	$sg2->add_widget($widget) if $sg2;
	$widget->set_tooltip_text($tip) if defined $tip;

	if (defined $text)
	{	my $box=Gtk2::HBox->new;
		my $label=Gtk2::Label->new($text);
		$label->set_alignment(0,.5);
		$box->pack_start($label,FALSE,FALSE,2);
		$box->pack_start($widget,$expand,$expand,2);
		$sg1->add_widget($label) if $sg1;
		$widget=$box;
	}

	$entry->set_visibility(0) if $hide;
	$entry->set_text($Options{$key}) if defined $Options{$key};
	$entry->signal_connect( changed => sub
	{	SetOption($_[1], $_[0]->get_text);
		&$cb if $cb;
	},$key);
	return $widget;
}

sub NewPrefComboText
{	my ($key)=@_;
	my $combo=Gtk2::ComboBoxEntry->new_text;
	my $hist= $Options{$key} || [];
	$combo->append_text($_) for @$hist;
	$combo->set_active(0);
	$combo->signal_connect( destroy => sub { PrefSaveHistory($key,$_[0]->get_active_text); } );
	return $combo;
}
sub PrefSaveHistory	#to be used with NewPrefComboText and NewPrefFileEntry
{	my ($key,$newvalue,$max)=@_;
	$max||=10;
	my $hist= $Options{$key} ||= [];
	@$hist= ($newvalue, grep $_ ne $newvalue, @$hist);
	$#$hist=$max if $#$hist>$max;
}

sub NewPrefFileEntry
{	my ($key,$text,%opt)=@_;
	my ($folder,$sg1,$sg2,$tip,$cb,$key_history)=@opt{qw/folder sizeg1 sizeg2 tip cb history_key/};
	my $label=Gtk2::Label->new($text);
	my $widget=my $entry=Gtk2::Entry->new;
	if ($key_history)
	{	$widget=Gtk2::ComboBoxEntry->new_text;
		$entry=$widget->child;
		my $hist= $Options{$key_history} || [];
		$widget->append_text(decode_url($_)) for grep length, @$hist; #won't work with filenames with broken encoding
	}
	my $button=NewIconButton('gtk-open');
	my $hbox=Gtk2::HBox->new;
	my $hbox2=Gtk2::HBox->new(FALSE,0);
	$hbox2->pack_start($widget,TRUE,TRUE,0);
	$hbox2->pack_start($button,FALSE,FALSE,0);
	$hbox->pack_start($_,FALSE,FALSE,2)  for $label,$hbox2;
	$label->set_alignment(0,.5);

	my $enc_warning=Gtk2::Label->new(_"Warning : using a folder with invalid encoding, you should rename it.");
	$enc_warning->set_no_show_all(1);
	my $vbox=Gtk2::VBox->new(FALSE,0);
	$vbox->pack_start($hbox,FALSE,FALSE,0);
	$vbox->pack_start($enc_warning,FALSE,FALSE,2);

	if ($sg1) { $sg1->add_widget($label); $label->set_alignment(0,.5); }
	if ($sg2) { $sg2->add_widget($hbox2); }

	$entry->set_tooltip_text($tip) if defined $tip;
	if (defined $Options{$key})
	{	$entry->set_text(filename_to_utf8displayname(decode_url($Options{$key})));
		$enc_warning->show if url_escape($entry->get_text) ne $Options{$key};
	}

	my $busy;
	$entry->signal_connect( changed => sub
	{	return if $busy;
		SetOption( $key, url_escape($_[0]->get_text) );
		$enc_warning->hide;
		&$cb if $cb;
	});
	$button->signal_connect( clicked => sub
	{	my $file= $folder? ChooseDir($text, path=>$Options{$key}) : undef;
		return unless $file;
		# could simply $entry->set_text(), but wouldn't work with filenames with broken encoding
		SetOption( $key, url_escape($file) );
		$busy=1; $entry->set_text(filename_to_utf8displayname($file)); $busy=undef;
		$enc_warning->set_visible( url_escape($entry->get_text) ne $Options{$key} );
		&$cb if $cb;
	});
	$entry->signal_connect( destroy => sub { PrefSaveHistory($key_history,url_escape($_[0]->get_text)); } ) if $key_history;
	return $vbox;
}
sub NewPrefSpinButton
{	my ($key,$min,$max,%opt)=@_;
	my ($text,$text1,$text2,$sg1,$sg2,$tip,$sub,$climb_rate,$digits,$stepinc,$pageinc,$wrap)=@opt{qw/text text1 text2 sizeg1 sizeg2 tip cb rate digits step page wrap/};	#FIXME using text1 and text2 is deprecated and will be removed, use text with %d instead, for example text=>"value : %d seconds"
	$stepinc||=1;
	$pageinc||=$stepinc*10;
	$climb_rate||=1;
	$digits||=0;
	($text1,$text2)= split /\s*%d\s*/,$text,2 if $text;
	$text1=Gtk2::Label->new($text1) if defined $text1 && $text1 ne '';
	$text2=Gtk2::Label->new($text2) if defined $text2 && $text2 ne '';
	my $adj=Gtk2::Adjustment->new($Options{$key}||=0,$min,$max,$stepinc,$pageinc,0);
	my $spin=Gtk2::SpinButton->new($adj,$climb_rate,$digits);
	$spin->set_wrap(1) if $wrap;
	$adj->signal_connect(value_changed => sub
	 {	SetOption( $_[1], $_[0]->get_value);
		&$sub if $sub;
	 },$key);
	$spin->set_tooltip_text($tip) if defined $tip;
	if ($sg1 && $text1) { $sg1->add_widget($text1); $text1->set_alignment(0,.5); }
	if ($sg2) { $sg2->add_widget($spin); }
	if ($text1 or $text2)
	{	my $hbox=Gtk2::HBox->new;
		$hbox->pack_start($_,FALSE,FALSE,2) for grep $_, $text1,$spin,$text2;
		return $hbox;
	}
	return $spin;
}

sub NewPrefCombo
{	my ($key,$list,%opt)=@_;
	my ($text,$cb0,$sg1,$sg2,$toolitem,$tree,$tip,$event)=@opt{qw/text cb sizeg1 sizeg2 toolitem tree tip event/};
	my $cb=sub
		{	SetOption($key,$_[0]->get_value);
			&$cb0 if $cb0;
		};
	my $class= $tree ? 'TextCombo::Tree' : 'TextCombo';
	my $combo= $class->new( $list, $Options{$key}, $cb, event=>$event );
	my $widget=$combo;
	if (defined $text)
	{	my $label=Gtk2::Label->new($text);
		my $hbox=Gtk2::HBox->new;
		$hbox->pack_start($_,FALSE,FALSE,2) for $label,$combo;
		$sg1->add_widget($label) if $sg1;
		$sg2->add_widget($combo) if $sg2;
		$label->set_alignment(0,.5);
		$widget=$hbox;
	}
	$widget->set_tooltip_text($tip) if defined $tip;
	if (defined $toolitem)
	{	$widget= $combo->make_toolitem($toolitem,$key,$widget);
	}
	return $widget;
}

sub NewPrefLayoutCombo
{	my ($key,$type,$text,$sg1,$sg2,$cb)=@_;
	my $buildlist= sub { Layout::get_layout_list($type) };
	my $combo= NewPrefCombo($key => $buildlist, text => $text, sizeg1=>$sg1,sizeg2=>$sg2, tree=>1, cb => $cb, event=>'Layouts');
	my $set_tooltip= sub	#show layout author in tooltip
	 {	return if $_[1] && $_[1] ne $key;
		my $layoutdef= $Layout::Layouts{$Options{$key}};
		my $tip= $layoutdef->{PATH}.$layoutdef->{FILE}.':'.$layoutdef->{LINE};
		if (my $author= $layoutdef->{Author}) {	$tip= _("by")." $author\n$tip"; }
		$_[0]->set_tooltip_text($tip);
	 };
	Watch( $combo, Option => $set_tooltip);
	$set_tooltip->($combo);
	return $combo;
}

sub NewPrefMultiCombo
{	my ($key,$possible_values_hash,%opt)=@_;
	my $sep= $opt{separator}|| ', ';
	my $display_cb= $opt{display} || sub
	 {	my $values= $Options{$key} || [];
		return $opt{empty} unless @$values;
		return join $sep,map $possible_values_hash->{$_}||=qq("$_"), @$values;
	 };
	$display_cb= sub {$opt{display}} if !ref $display_cb; # label in the button is a constant
	my $button= Gtk2::Button->new;

	my $label_value= Gtk2::Label->new;
	#$label_value->set_ellipsize('end');
	my $hbox=Gtk2::HBox->new(0,0);
	$hbox->pack_start($label_value,1,1,2);
	$hbox->pack_start($_,0,0,2) for Gtk2::VSeparator->new, Gtk2::Arrow->new('down','none');
	$button->add($hbox);
	$label_value->set_text( $display_cb->() );

	my $change_cb=sub
	 {	my $button= $_[0]{button};
		$Options{$key}= $_[1];
		$label_value->set_text( $display_cb->() );
		$opt{cb}->() if $opt{cb};
	 };
	my $click_cb=sub
	 {	my ($button,$event)=@_;
		my $menu=BuildChoiceMenu
		(	$possible_values_hash,
			check=> sub { $Options{$key}||[] },
			code => $change_cb,
			'reverse'=>1, return_list=>1,
			args => {button=>$button},
		);
		PopupMenu($menu,event=>$event);
		1;
	 };

	$button->signal_connect(button_press_event=> \&$click_cb);
	my $widget=$button;
	if (defined $opt{text})
	{	my $hbox0= Gtk2::HBox->new;
		my $label= Gtk2::Label->new($opt{text});
		$hbox0->pack_start($_, FALSE, FALSE, 2) for $label,$button;
		$widget=$hbox0;
	}
	$widget->set_tooltip_text($opt{tip}) if $opt{tip};
	return $widget;
}

sub NewIconButton
{	my ($icon,$text,$coderef,$style,$tip)=@_;
	my $but=Gtk2::Button->new;
	$but->set_relief($style) if $style;
	#$but->set_image(Gtk2::Image->new_from_stock($icon,'menu'));
	#$but->set_label($text) if $text;
#	my $widget=Gtk2::Image->new_from_stock($icon,'large-toolbar');
	my $widget=Gtk2::Image->new_from_stock($icon,'menu');
	if ($text)
	{	my $box=Gtk2::HBox->new(FALSE, 4);
		$box->pack_start($_, FALSE, FALSE, 2)	for $widget,Gtk2::Label->new($text);
		$widget=$box;
	}
	$but->add($widget);
	$but->signal_connect(clicked => $coderef) if $coderef;
	$but->set_tooltip_text($tip) if defined $tip;
	return $but;
}

sub EditWeightedRandom
{	my ($widget,$sort,$name,$sub)=@_;
	my $dialog=GMB::Edit->new($widget,'WRandom',$sort,$name);
	return $dialog->Result($sub);
}
sub EditSortOrder
{	my ($widget,$sort,$name,$sub)=@_;
	my $dialog=GMB::Edit->new($widget,'Sort',$sort,$name);
	return $dialog->Result($sub);
}
sub EditFilter
{	my ($widget,$filter,$name,$sub)=@_;
	my $dialog=GMB::Edit->new($widget,'Filter',$filter,$name);
	$sub||='' unless wantarray;#FIXME
	return $dialog->Result($sub);
}
sub EditSTGroupings
{	my ($widget,$filter,$name,$sub)=@_;
	my $dialog=GMB::Edit->new($widget,'STGroupings',$filter,$name);
	return $dialog->Result($sub);
}

sub SaveSFRG
{	my ($key,$name,$val,$newname)=@_;
	my $saved=$Options{$key};
	if (defined $newname)	{$saved->{$newname}=delete $saved->{$name};}
	elsif (defined $val)	{$saved->{$name}=$val;}
	else			{delete $saved->{$name};}
	HasChanged($key);
}
sub SaveFilter		{ SaveSFRG('SavedFilters',@_);	}
sub SaveList
{	my ($name,$val,$newname)=@_;
	my $saved=$Options{SavedLists};
	if (defined $newname)
	{	$saved->{$newname}=delete $saved->{$name};
		HasChanged('SavedLists',$name,'renamedto',$newname);
		HasChanged('SavedLists',$newname);
	}
	elsif (defined $val)
	{	if (my $songarray= $saved->{$name})	{ $songarray->Replace($val); return }
		else					{ $saved->{$name}= SongArray::Named->new_copy($val); HasChanged('SavedLists',$name); }
	}
	else	{ delete $saved->{$name}; HasChanged('SavedLists',$name,'remove'); }
	Songs::Changed(undef,'list'); # simulate modifcation of the fake "list" field
}

sub Watch
{	my ($object,$key,$sub)=@_;
	unless ($object) { push @{$EventWatchers{$key}},$sub; return } #for permanent watch
	warn "watch $key $object\n" if $debug;
	my $cbkey= 'WatchUpdate_'.$key;		# key used to store the callback(s) in the object's hash
	if (my $existing=$object->{$cbkey})	# object is watching the event with multiple callbacks
	{	$object->{$cbkey}= $existing= [$existing] if ref $existing ne 'ARRAY';
		push @$existing, $sub;
	}
	else
	{	push @{$EventWatchers{$key}},$object; weaken($EventWatchers{$key}[-1]);
		$object->{$cbkey}=$sub;
	}
	$object->{Watcher_DESTROY}||=$object->signal_connect(destroy => \&UnWatch_all) unless ref $object eq 'HASH' || !$object->isa('Gtk2::Object');
}
sub UnWatch		# warning: if one object watch the same event with multiple callbacks, all of them will be removed
{	my ($object,$key)=@_;
	warn "unwatch $key $object\n" if $debug;
	@{$EventWatchers{$key}}=grep defined && $_ != $object, @{$EventWatchers{$key}};
	weaken($_) for @{$EventWatchers{$key}}; #re-weaken references (the grep above made them strong again)
	delete $object->{'WatchUpdate_'.$key};
}
sub UnWatch_all #for when destructing object (unwatch Watch() AND WatchFilter())
{	my $object=shift;
	UnWatch($object,$_) for map m/^WatchUpdate_(.+)/, keys %$object;
	UnWatchFilter($object,$_) for map m/^UpdateFilter_(.+)/, keys %$object;
}

sub QHasChanged
{	my ($key,@args)=@_;
	IdleDo("1_HasChanged_$key",250,\&HasChanged,$key,@args);
}
sub HasChanged
{	my ($key,@args)=@_;
	delete $ToDo{"1_HasChanged_$key"};
	return unless $EventWatchers{$key};
	my @list=@{$EventWatchers{$key}};
	warn "HasChanged $key -> updating @list\n" if $debug;
	for my $r ( @list )
	{	my ($sub,$o)= ref $r eq 'CODE' ? ($r) : ($r->{'WatchUpdate_'.$key},$r);
		next unless $sub;
		if (ref $sub eq 'ARRAY')
		{	$_->($o,@args) for @$sub;
		}
		else { $sub->($o,@args) }
	};
}

sub GetSelID
{	my $group= ref $_[0] ? $_[0]{group} : $_[0];
	$group=~s/:[\w.]+$//;
	return	$group=~m/^Next(\d*)$/		? $NextSongs[($1||0)] :
		$group=~m/^Recent(\d*)$/	? $Recent->[($1||0)] :
		$group ne 'Play'		? $SelID{$group} :
		$SongID;
}
sub WatchSelID
{	my ($object,$sub,$fields)=@_; #fields are ignored for now
	my $group=$object->{group};
	$group=~s/:[\w.]+$//;
	my $key= $group=~m/^Next\d*$/ ? 'NextSongs' : $group=~m/^Recent\d*$/ ? 'RecentSongs' : $group ne 'Play' ? 'SelectedID_'.$group : 'CurSong';
	if ($group=~m/^(?:Recent|Next)\d*$/) { my $orig=$sub; $sub=sub { $orig->( $_[0],GetSelID($_[0]) ); }; } #so that $sub gets the ID as argument in the same way as other cases (SelectedID_ and CurSong)
	Watch($object,$key,$sub);
}
sub UnWatchSelID
{	my $object=$_[0];
	my $group=$object->{group};
	$group=~s/:[\w.]+$//;
	my $key= $group=~m/^Next\d*$/ ? 'NextSongs' : $group=~m/^Recent\d*$/ ? 'RecentSongs' : $group ne 'Play' ? 'SelectedID_'.$group : 'CurSong';
	UnWatch($object,$key);
}
sub HasChangedSelID
{	my ($group,$ID)=@_;
	return if $group=~m/:/;
	if (defined $ID){ $SelID{$group}=$ID; }
	else		{ delete $SelID{$group}; }
	UpdateRelatedFilter($group);
	HasChanged('SelectedID_'.$group,$ID,$group);
}
sub UpdateRelatedFilter
{	my $group=shift;
	my $re= $group=~m/^(?:Next|Recent)\d*$/ ? qr/^\Q$group\E\d*:(.+)/ : qr/^\Q$group\E:(.+)/;
	for my $group0 (keys %Related_FilterWatchers)
	{	next unless $group0=~m/$re/;
		my $filter= Songs::MakeFilterFromID($1,GetSelID($group));
		SetFilter(undef,$filter,1,$group0);
	}
}

#doesn't change the filter, but return the filter that would result for the widget
sub SimulateSetFilter
{	my ($object,$filter,$level,$group)=@_;
	$level=1 unless defined $level;
	$group=$object->{group} unless defined $group;
	$group=get_layout_widget($object)->{group} unless defined $group;
	my $filters= $Filters{$group}||=[];	# $filters->[0] is the sum filter, $filters->[$n+1] is filter for level $n
	$filter=Filter->new($filter) unless defined $filter && ref $filter eq 'Filter';
	return Filter->newadd(TRUE, map($filters->[$_], 1..$level), $filter);
}
sub SetFilter
{	my ($object,$filter,$level,$group)=@_;
	$level=1 unless defined $level;
	$group=$object->{group} unless defined $group;
	$group=get_layout_widget($object)->{group} unless defined $group;
	my $filters= $Filters{$group}||=[];	# $filters->[0] is the sum filter, $filters->[$n+1] is filter for level $n
	$filter=Filter->new($filter) unless defined $filter && ref $filter eq 'Filter';
	$filters->[$level+1]=$filter;	#set filter for level $level
	$#$filters=$level+1;		#set higher level filters to undef by truncating the array
	$filters->[0]= Filter->newadd(TRUE, map($filters->[$_], 1..$#$filters) ); #sum filter
	AddToFilterHistory( $filters->[0] );
	for my $r ( @{$FilterWatchers{$group}} ) { $r->{'UpdateFilter_'.$group}($r,$Filters{$group}[0],$level,$group) };
	if ($group eq 'Play') { $ListPlay->SetFilter($filters->[0]) }
}
sub RefreshFilters
{	my ($object,$group)=@_;
	$group=$object->{group} unless defined $group;
	$group=get_layout_widget($object)->{group} unless defined $group;
	for my $r ( @{$FilterWatchers{$group}} ) { $r->{'UpdateFilter_'.$group}($r,$Filters{$group}[0],undef,$group) };
}
sub AddToFilterHistory
{	my $filter=$_[0];
	my $recent=$::Options{RecentFilters}||=[];
	my $string=$filter->{string};
	return if $string eq 'null';
	@$recent=($filter, grep $_->{string} ne $string, @$recent);
	pop @$recent if @$recent>20;
}
sub GetFilter
{	my ($object,$nb)=@_;
	my $group=$object->{group};
	$group=get_layout_widget($object)->{group} unless defined $group;
	return defined $nb ? $Filters{$group}[$nb+1] : $Filters{$group}[0];
}
sub GetSonglist
{	my $object=$_[0];
	my $layw=get_layout_widget($object);
	my $group=$object->{group};
	$group=$layw->{group} if !defined $group && $layw;
	return $SongList::Common::Register{$group};
}
sub GetSongArray
{	my $sl= GetSonglist($_[0]);
	return $sl && $sl->{array};
}
sub InitFilter
{	my $group=shift;
	$group=$group->{group} if ref $group;
	return if $Filters{$group}[0];
	my $filter;
	if ($group=~m/(.+):([\w.]+)$/)
	{	$filter= Songs::MakeFilterFromID($2,GetSelID($1));
	}
	SetFilter(undef,$filter,1,$group);
}
sub WatchFilter
{	my ($object,$group,$sub)=@_;
	warn "watch filter $group $object\n" if $debug;
	push @{$FilterWatchers{$group}},$object;
	$object->{'UpdateFilter_'.$group}=$sub;
	if ($group=~m/:[\w.]+$/)
	{	$Related_FilterWatchers{$group}++;
		#$Filters{$group}[0]||=$Filters{$group}[1+1]||= Filter->null;
		#$Filters{$group}[0]||=$Filters{$group}[1+1]||=Filter->new;
	}
	IdleDo('1_init_filter'.$group,0, \&InitFilter, $group);
	$object->{Watcher_DESTROY}||=$object->signal_connect(destroy => \&UnWatch_all) unless ref $object eq 'HASH' || !$object->isa('Glib::Object');
}
sub UnWatchFilter
{	my ($object,$group)=@_;
	warn "unwatch filter $group $object\n" if $debug;
	if ($group=~m/:[\w.]+$/)
	{	unless (--$Related_FilterWatchers{$group})
		{	delete $Related_FilterWatchers{$group};
		}
	}
	delete $object->{'UpdateFilter_'.$group};
	my $ref=$FilterWatchers{$group};
	@$ref=grep $_ ne $object, @$ref;
	unless (@$ref)
	{	delete $_->{$group} for \%Filters,\%FilterWatchers;
	}
}

sub Progress
{	my $pid=shift;
	my $self= {@_};
	if (!defined $pid)	#new one
	{	$pid="$self";
		$Progress{$pid}=$self;
	}
	elsif (!$Progress{$pid})
	{	return if $self->{abort};
		$Progress{$pid}=$self;
	}
	else		#update existing
	{	$Progress{$pid}{$_}=$self->{$_} for keys %$self;
		$Progress{$pid}{partial}=0 if $self->{inc} || exists $self->{current};
		$self= $Progress{$pid};
	}
	$self->{end}+=delete $self->{add} if $self->{add};
	$self->{current}++ if delete $self->{inc};
	$self->{fraction}= (($self->{partial}||0) +  ($self->{current}||=0)) / ($self->{end}||1);

	if (my $w=$self->{widget}) { $w->set_fraction( $self->{fraction} ); }
	delete $Progress{$pid} if $self->{abort} or $self->{current}>=$self->{end}; # finished
	HasChanged(Progress =>$pid,$Progress{$pid});
	if ( $Progress{$pid} && !$self->{widget} && (!$EventWatchers{Progress} || @{$EventWatchers{Progress}}==0))	#if no widget => create progress window
	{	#create the progress window only after a short timeout to ignore short jobs
		$ProgressWindowComing ||= Glib::Timeout->add(1000,
		    sub {	my $still_progress = grep !$Progress{$_}{widget}, keys %Progress;
				my $still_no_widget= !$EventWatchers{Progress} || @{$EventWatchers{Progress}}==0;
				Layout::Window->new('Progress') if $still_progress && $still_no_widget;
				return $ProgressWindowComing=0;
			});
	}
	return $pid;
}

sub PresentWindow
{	my $win=$_[1];
	$win->force_present;
	$win->set_skip_taskbar_hint(FALSE) unless $win->{skip_taskbar_hint};
}

sub PopupLayout
{	my ($layout,$widget)=@_;
	return if $widget && $widget->{PoppedUpWindow};
	my $popup=Layout::Window::Popup->new($layout,$widget);
}

sub UpdateTrayIcon
{	my $force=shift;
	return unless $TrayIcon;
	return unless $force || $TrayIcon{play} || $TrayIcon{pause};
	my $state= !defined $TogPlay ? 'default' : $TogPlay ? 'play' : 'pause';
	$state='default' unless $TrayIcon{$state};
	my $pb= $TrayIcon{'PixBuf_'.$state} ||= eval {Gtk2::Gdk::Pixbuf->new_from_file($TrayIcon{$state})};
	my $widget= $TrayIcon->isa('Gtk2::StatusIcon') ? $TrayIcon : $TrayIcon->child->child;
	$widget->set_from_pixbuf($pb);
}

sub Gtk2::StatusIcon::child {$_[0]}

sub CreateTrayIcon
{	if ($TrayIcon)
	{	return if $Options{UseTray};
		$TrayIcon->destroy unless $TrayIcon->isa('Gtk2::StatusIcon');
		$TrayIcon=undef;
		return;
	}
	elsif (!$Options{UseTray} || !$TrayIconAvailable)	 {return}

	my $eventbox;
	if ($UseGtk2StatusIcon)
	{	$TrayIcon= $eventbox= Gtk2::StatusIcon->new;
	}
	else	# use Gtk2::TrayIcon
	{	$TrayIcon= Gtk2::TrayIcon->new(PROGRAM_NAME);
		$eventbox=Gtk2::EventBox->new;
		$eventbox->set_visible_window(0);
		my $img=Gtk2::Image->new;

		Glib::Timeout->add(1000,sub {$TrayIcon->{respawn}=1 if $TrayIcon; 0;});
		 #recreate Trayicon if it is deleted, for example when the gnome-panel crashed, but only if it has lived >1sec to avoid an endless loop
		$TrayIcon->signal_connect(delete_event => sub
		 {	my $respawn=$TrayIcon->{respawn};
			$TrayIcon=undef;
			CreateTrayIcon() if $respawn;
			0;
		 });
		$eventbox->add($img);
		$TrayIcon->add($eventbox);
		Layout::Window::make_transparent($TrayIcon) if $CairoOK;
		$TrayIcon->show_all;
	}

	SetTrayTipDelay();
	Layout::Window::Popup::set_hover($eventbox);

	$eventbox->signal_connect(scroll_event => \&::ChangeVol);
	$eventbox->signal_connect(button_press_event => sub
		{	my $b=$_[1]->button;
			if	($b==3) { &TrayMenuPopup }
			elsif	($b==2) { &PlayPause}
			else		{ ShowHide() }
			1;
		});

	UpdateTrayIcon(1);
	Watch($TrayIcon, Playing=> sub { UpdateTrayIcon(); });
}
sub SetTrayTipDelay
{	return unless $TrayIcon;
	$TrayIcon->child->{hover_delay}= $Options{TrayTipDelay}||1;
}
sub TrayMenuPopup
{	CloseTrayTip();
	$TrayIcon->{block_popup}=1;
	my $menu=Gtk2::Menu->new;
	$menu->signal_connect( selection_done => sub {$TrayIcon->{block_popup}=undef});
	PopupContextMenu(\@TrayMenu, {usemenupos=>1}, $menu);
}
sub CloseTrayTip
{	return unless $TrayIcon;
	my $traytip=$TrayIcon->child->{PoppedUpWindow};
	$traytip->DestroyNow if $traytip;
}
sub ShowTraytip
{	return 0 if !$TrayIcon || $TrayIcon->{block_popup};
	Layout::Window::Popup::Popup($TrayIcon->child,$_[0]);
}
sub windowpos	# function to position window next to clicked widget ($event can be a widget)
{	my ($win,$event)=@_;
	return (0,0) unless $event;
	my $h=$win->size_request->height;		# height of window to position
	my $w=$win->size_request->width;		# width of window to position
	my $screen=$event->get_screen;
	my ($monitor,$x,$y,$dx,$dy);
	if ($event->isa('Gtk2::StatusIcon'))
	{	($x,$y,$dx,$dy)=($event->get_geometry)[1]->values; # position and size of statusicon
		$monitor=$screen->get_monitor_at_point($x,$y);
	}
	else
	{	$monitor=$screen->get_monitor_at_window($event->window);
		($x,$y)=$event->window->get_origin;		# position of the clicked widget on the screen
		($dx,$dy)=$event->window->get_size;		# width,height of the clicked widget
		if ($event->isa('Gtk2::Widget') && $event->no_window)
		{	(my$x2,my$y2,$dx,$dy)=$event->allocation->values;
			$x+=$x2;$y+=$y2;
		}
	}
	my ($xmin,$ymin,$monitorwidth,$monitorheight)=$screen->get_monitor_geometry($monitor)->values;
	my $xmax=$xmin + $monitorwidth;
	my $ymax=$ymin + $monitorheight;

	my $ycenter=0;
	if ($x+$dx/2+$w/2 < $xmax && $x+$dx/2-$w/2 >$xmin){ $x-=int($w/2-$dx/2); }	# centered
	elsif ($x+$dx+$w > $xmax)	{ $x=max($xmax-$w,$xmin) }		# right side
	else				{ $x=$xmin; }				# left side
	if ($ycenter && $y+$h/2 < $ymax && $y-$h/2 >$ymin){ $y-=int($h/2) }	# y center
	elsif ($dy+$y+$h > $ymax)	{ $y=max($y-$h,$ymin) }			# display above the widget
	else				{ $y+=$dy; }				# display below the widget
	return $x,$y;
}

sub IsWindowVisible
{	my $win=shift;
	my $visible=!$win->{iconified};
	$visible=0 unless $win->visible;
	if ($visible)
	{	my ($mw,$mh)= $win->get_size;
		my ($mx,$my)= $win->get_position;
		my $screen=Gtk2::Gdk::Screen->get_default;
		$visible=0 if $mx+$mw<0 || $my+$mh<0 || $mx>$screen->get_width || $my>$screen->get_height;
	}
	return $visible;
}
sub ShowHide
{	my $hide= defined $_[0] ? !$_[0] : IsWindowVisible($MainWindow);
	my (@windows)=grep $_->isa('Layout::Window') && $_->{showhide} && $_!=$MainWindow, Gtk2::Window->list_toplevels;
	if ($hide)
	{	#hide
		#warn "hiding\n";
		for my $win ($MainWindow,@windows)
		{	next unless $win;
			$win->{saved_position}=join 'x',$win->get_position;
			$win->{skip_taskbar_hint}=$win->get_skip_taskbar_hint;
			$win->set_skip_taskbar_hint(TRUE);
			$win->hide;
		}
	}
	else
	{	#show
		#warn "showing\n";
		my $screen=Gtk2::Gdk::Screen->get_default;
		my $scrw=$screen->get_width;
		my $scrh=$screen->get_height;
		for my $win (@windows,$MainWindow)
		{	next unless $win;
			my ($x,$y)= $win->{saved_position} ? split('x', delete $win->{saved_position}) : $win->get_position;
			my ($w,$h)= $win->get_size;
			#warn "move($x,$y)\n";
			if ($x+$w<0 || $y+$h<0 || $x>$scrw || $y>$scrh)
			{	$x%= $scrw;
				$y%= $scrh;
			}
			$win->move($x,$y);
			$win->show;
			$win->move($x,$y);
			$win->deiconify if $win->{iconified};
			$win->set_skip_taskbar_hint(FALSE) unless delete $win->{skip_taskbar_hint};
			#$win->set_opacity($win->{opacity}) if exists $win->{opacity} && $win->{opacity}!=1; #need to re-set it, is it a gtk bug, metacity bug ?
		}
		$MainWindow->force_present;
	}
	QHasChanged('Windows');
}

package GMB::Edit;
use base 'Gtk2::Dialog';

my %refs;

INIT
{ %refs=
  (	Filter	=> [	_"Filter edition",		'SavedFilters',		_"saved filters",
			_"name of the new filter",	_"save filter as",	_"delete selected filter",	'600x260'],
	Sort	=> [	_"Sort mode edition",		'SavedSorts',		_"saved sort modes",
			_"name of the new sort mode",	_"save sort mode as",	_"delete selected sort mode",	'600x320'],
	WRandom	=> [	_"Random mode edition",		'SavedWRandoms',	_"saved random modes",
			_"name of the new random mode", _"save random mode as", _"delete selected random mode",	'600x450'],
	STGroupings => [_"SongTree groupings edition", 'SavedSTGroupings',	_"saved groupings",
			_"name of the new grouping",	_"save grouping as",	_"delete selected grouping"],
  );
}

sub new
{	my ($class,$window,$type,$init,$name) = @_;
	$window=$window->get_toplevel if $window;
	my $typedata=$refs{$type};
	my $self = bless Gtk2::Dialog->new( $typedata->[0], $window,[qw/destroy-with-parent/]), $class;
	$self->add_button('gtk-cancel' => 'none');
	if (defined $name && $name ne '')
	{	my $button=::NewIconButton('gtk-save', ::__x( _"save as '{name}'", name => $name) );
		$button->can_default(::TRUE);
		$self->add_action_widget( $button,'ok' );
		$self->{save_name}=$name;
	}
	else
	{	$self->{save_name_entry}=Gtk2::Entry->new if defined $name; # eq ''
		$self->add_button('gtk-ok' => 'ok');
	}
	$self->set_default_response('ok');
	$self->set_border_width(3);

	$self->{key}=$typedata->[1];
	$self->{hash}=$::Options{$self->{key}};
	::Watch($self,$self->{key},\&Fill);

	if (defined $name)
	{	if ($name eq '')
		{	$name=_"noname";
			::IncSuffix($name) while $self->{hash}{$name};
		}
		else { $init=$self->{hash}{$name} unless defined $init; }
	}

	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
#	$treeview->set_headers_visible(::FALSE);
	my $renderer=Gtk2::CellRendererText->new;
	$renderer->signal_connect(edited => \&name_edited_cb,$self);
	$renderer->set(editable => 1);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( $typedata->[2],$renderer,'text',0)
		);
	my $sw= ::new_scrolledwindow($treeview,'etched-in');
	my $butrm=::NewIconButton('gtk-remove',_"Remove");
	$treeview->get_selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$butrm->set_sensitive($sel);
		});
	$butrm->set_sensitive(0);
	$butrm->signal_connect(clicked => \&Remove_cb,$self);
	my $butsave=::NewIconButton('gtk-save');
	my $NameEntry=Gtk2::Entry->new;
	$NameEntry->signal_connect(changed => sub { $butsave->set_sensitive(length $_[0]->get_text); });
	$butsave->signal_connect(  clicked  => sub {$self->Save});
	$NameEntry->signal_connect(activate => sub {$self->Save});
	$butsave->set_sensitive(0);
	$NameEntry->set_text($name) if defined $name;
	$NameEntry->set_tooltip_text($typedata->[3]);
	$butsave  ->set_tooltip_text($typedata->[4]);
	$butrm    ->set_tooltip_text($typedata->[5]);

	$self->{entry}=$NameEntry;
	$self->{store}=$store;
	$self->{treeview}=$treeview;
	$self->Fill;
	my $package='GMB::Edit::'.$type;
	my $editobject=$package->new($self,$init);
	$self->vbox->add( ::Hpack( [[0,$NameEntry,$butsave],'_',$sw,$butrm], '_',$editobject) );
	if ($self->{save_name_entry}) { $editobject->pack_start(::Hpack(Gtk2::Label->new('Save as : '),$self->{save_name_entry}), ::FALSE,::FALSE, 2); $self->{save_name_entry}->set_text($name); }
	$self->{editobject}=$editobject;

	::SetWSize($self,'Edit'.$type,$typedata->[6]);
	$self->show_all;

	$treeview->get_selection->unselect_all;
	$treeview->signal_connect(cursor_changed => \&cursor_changed_cb,$self);

	return $self;
}

sub name_edited_cb
{	my ($cell, $path_string, $newname,$self) = @_;
	my $store=$self->{store};
	my $iter=$store->get_iter_from_string($path_string);
	my $name=$store->get($iter,0);
	#$self->{busy}=1;
	::SaveSFRG($self->{key}, $name, undef,$newname);
	#$self->{busy}=undef;
	#$store->set($iter, 0, $newname);
}

sub Remove_cb
{	my $self=$_[1];
	my $path=($self->{treeview}->get_cursor)[0]||return;
	my $store=$self->{store};
	my $name=$store->get( $store->get_iter($path) ,0);
	::SaveSFRG($self->{key}, $name, undef);
}

sub Save
{	my $self=shift;
	my $name=$self->{entry}->get_text;
	return unless $name;
	my $result=$self->{editobject}->Result;
	::SaveSFRG($self->{key}, $name, $result);
}

sub Fill
{	my $self=shift;
	return if $self->{busy};
	my $store=$self->{store};
	$store->clear;
	$store->set($store->append,0,$_) for sort keys %{ $self->{hash} };
}

sub cursor_changed_cb
{	my ($treeview,$self)=@_;
	my $store=$self->{store};
	my ($path)=$treeview->get_cursor;
	return unless $path;
	my $name=$store->get( $store->get_iter($path) ,0);
	$self->{entry}->set_text($name);
	$self->{editobject}->Set( $self->{hash}{$name} );
}

sub Result
{	my ($self,$sub)=@_;
	if (defined $sub)
	{	$self->add_button('gtk-apply','apply') if $sub;
		$self->signal_connect( response =>sub
		 {	my $ans=$_[1];
			if ($ans eq 'ok' || $ans eq 'apply')
			{	my $result=$self->{editobject}->Result;
				$self->{save_name}=$self->{save_name_entry}->get_text if $self->{save_name_entry};
				::SaveSFRG($self->{key}, $self->{save_name}, $result)
					 if $ans eq 'ok' && defined $self->{save_name} && $self->{save_name} ne '';
				$sub->($result) if $sub;
				return if $ans eq 'apply';
			}
			$self->destroy;
		 });
		return;
	}
	my $result;
	if ('ok' eq $self->run) #FIXME stop using this, always supply a $sub
	{	$result=$self->{editobject}->Result;
	}
	$self->destroy;
	return $result;
}


package GMB::Edit::Filter;
use base 'Gtk2::Box';
use constant
{  TRUE  => 1, FALSE => 0,
   C_NAME => 0,	C_FILTER => 1,
   DEFAULT_FILTER => 'title:si:',
};

sub new
{	my ($class,$dialog,$init) = @_;
	my $self = bless Gtk2::VBox->new, $class;

	my $store=Gtk2::TreeStore->new('Glib::String','Glib::Scalar');
	$self->{treeview}=
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes(
		_("filters") => Gtk2::CellRendererText->new,
		text => C_NAME) );
	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');

	my $butadd= ::NewIconButton('gtk-add',_"Add");
	my $butadd2=::NewIconButton('gtk-add',_"Add multiple condition");
	my $butrm=  ::NewIconButton('gtk-remove',_"Remove");
	$butadd->signal_connect( clicked => \&Add_cb);
	$butadd2->signal_connect(clicked => \&Add_cb);
	$butrm->signal_connect(  clicked => \&Rm_cb );
	$butrm->set_sensitive(FALSE);
	$butadd->{filter}= DEFAULT_FILTER;
	$butadd2->{filter}="(\x1D".DEFAULT_FILTER."\x1D)";

	$treeview->get_selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$butrm->set_sensitive($sel);
		});
	$self->{fbox}=
	my $fbox=Gtk2::EventBox->new;
	my $bbox=Gtk2::HButtonBox->new;
	$bbox->add($_) for $butadd,$butadd2,$butrm;
	$sw->add($treeview);
	$self->add($sw);
	$self->pack_start($fbox, FALSE, FALSE, 1);
	$self->pack_start($bbox, FALSE, FALSE, 1);

	$treeview->signal_connect(cursor_changed => \&cursor_changed_cb);
	$treeview->signal_connect(key_press_event=> \&key_press_cb);

	::set_drag($treeview,
	source=>[::DRAG_FILTER,sub
		{	my $treeview=$_[0];
			my $self=::find_ancestor($treeview,__PACKAGE__);
			my $f=$self->Result( ($treeview->get_cursor)[0] );
			return (::DRAG_FILTER,($f->{string}||undef));
		}],
	dest =>	[::DRAG_FILTER,sub
		{	my ($treeview,$type,$dest,$filter)=@_;
			my $self=::find_ancestor($treeview,__PACKAGE__);
			#$self->signal_stop_emission_by_name('drag_data_received');
			return if $treeview->{drag_is_source} && !$store->iter_has_child($store->get_iter_first);
			my (undef,$path,$pos)=@$dest;
			#warn "-------- $filter,$path,$pos";
			my $rowref_todel;
			$rowref_todel=Gtk2::TreeRowReference->new($treeview->get_model,($treeview->get_cursor)[0]) if $treeview->{drag_is_source};
			$self->Set($filter,$path,$pos);
			if ($rowref_todel)
			{	my $path=$rowref_todel->valid	?
					$rowref_todel->get_path	: $pos=~m/after$/ ?
					Gtk2::TreePath->new_from_indices(0,0)	  :
					Gtk2::TreePath->new_from_indices(0,1);
				$self->Remove_path($path);
			}
		}],
	motion => sub
		{	my ($treeview,$context,$x,$y,$time)=@_;# warn "drag_motion_cb @_";
			my $store=$treeview->get_model;
			my ($path,$pos)=$treeview->get_dest_row_at_pos($x,$y);
			$path||=Gtk2::TreePath->new_first;
			$pos||='after';

			if ($treeview->{drag_is_source})
			{	my $sourcepath=($treeview->get_cursor)[0];
				if ($sourcepath->is_ancestor($path) || !$sourcepath->compare($path))
				{	$treeview->set_drag_dest_row(undef,$pos);
					$context->status('default', 0);
					return 0;
				}
			}

			my $iter=$store->get_iter($path);
			if (!$store->iter_has_child($iter))				{ $pos=~s/^into-or-//; }
			elsif ($pos!~m/^into-or-/ && !$store->iter_parent($iter))	{ $pos='into-or-'.$pos; }
			#warn "$pos, ".$self->Result($path,$pos)->{string};
			$context->{dest}=[$treeview,$path,$pos];
			$treeview->set_drag_dest_row($path,$pos);
			$context->status(($treeview->{drag_is_source} ? 'move' : 'copy'),0);
			return 1;
		});
	$self->Set($init);

	return $self;
}

sub Add_cb
{	my $button=shift;
	my $self= ::find_ancestor($button,__PACKAGE__);
	my $path=($self->{treeview}->get_cursor)[0];
	$path||=Gtk2::TreePath->new_first;
	$self->Set( $button->{filter}, $path);
}
sub Rm_cb
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	my $treeview=$self->{treeview};
	my ($path)=$treeview->get_cursor;
	return unless $path;
	my $oldpath=$self->Remove_path($path);
	$oldpath->prev or $oldpath->up;
	$oldpath=Gtk2::TreePath->new_first unless $oldpath->get_depth;
	$treeview->set_cursor($oldpath);
}
sub Remove_path
{	my ($self,$path)=@_;
	my $store=$self->{treeview}->get_model;
	my $iter=$store->get_iter($path);
	my $parent=$store->iter_parent($iter);
	while ($parent && $store->iter_n_children($parent)<2)
	{	my $p=$store->iter_parent($parent);
		$iter=$parent;
		$parent=$p;
	}
	my $oldpath=$store->get_path($iter);
	$store->remove($iter);
	# recreate a default entry if no more entry :
	$self->Set(DEFAULT_FILTER) unless $store->get_iter_first;
	return $oldpath;
}

sub key_press_cb
{	my ($tv,$event)=@_;
	my $key=Gtk2::Gdk->keyval_name( $event->keyval );
	if ($key eq 'Delete') { Rm_cb($tv); return 1 }
	return 0;
}

sub cursor_changed_cb
{	my $treeview=shift;
	my $self= ::find_ancestor($treeview,__PACKAGE__);
	my $fbox=$self->{fbox};
	my $store=$treeview->get_model;
	my ($path,$co)=$treeview->get_cursor;
	return unless $path;
	#warn "row : ",$path->to_string," / col : $co\n";
	$fbox->remove($fbox->child) if $fbox->child;
	my $iter=$store->get_iter($path);
	my $box;
	if ($store->iter_has_child($iter))
	{	$box=Gtk2::HBox->new;
		my $state=$store->get($iter,C_FILTER);
		my $group;
		for my $ao ('&','|')
		{	my $name=($ao eq '&')? _"All of :":_"Any of :";
			my $b=Gtk2::RadioButton->new($group,$name);
			$group=$b unless $group;
			$b->set_active(1) if $ao eq $state;
			$b->signal_connect( toggled => sub
			{	return unless $_[0]->get_active;
				_set_row($store, $iter, $ao);
			});
			$box->add($b);
		}
	}
	else
	{	$box=GMB::FilterBox->new
		(	undef,
			sub
			{	warn "filter : @_\n" if $::debug;
				my $filter=shift;
				_set_row($store, $iter, $filter);
			},
			$store->get($iter,C_FILTER),
		);
	}
	$fbox->add($box);
	$fbox->show_all;
}

sub Set
{	my ($self,$filter,$startpath,$startpos)=@_;
	$filter=$filter->{string} if ref $filter;
	$filter='' if !defined $filter || $filter eq 'null';
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;

	my $iter;
	if ($startpath)
	{	$iter=$store->get_iter($startpath);
		my $parent=$store->iter_parent($iter);
		if (!$parent && !$store->iter_has_child($iter)) #add a root
		{	$parent=$store->prepend(undef);
			_set_row($store, $parent, '&');
			my $new=$store->append($parent);
			$store->set($new,$_,$store->get($iter,$_)) for C_NAME,C_FILTER;
			$store->remove($iter);
			$iter=$parent;
			$startpos='into-or-'.$startpos if $startpos;
		}
		elsif (!$startpos && !$store->iter_has_child($iter))
		{	$iter=$parent;
		}
	}
	else { $store->clear }

	my $firstnewpath;
	my $createrowsub=sub
	 {	my $iter=shift;
		if ($startpos)
		{	my @args= $startpos=~m/^into/ ? ($iter,undef) : (undef,$iter);
			$iter=	($startpos=~m/^into/ xor $startpos=~m/after$/)
				? $store->insert_after(@args) : $store->insert_before(@args);
			$startpos=undef;
		}
		else	{$iter=$store->append($iter);}
		$firstnewpath||=$store->get_path($iter);
		return $iter;
	 };

	for my $f (split /\x1D/,$filter)
	{	if ($f eq ')')
		{	$iter=$store->iter_parent($iter);
		}
		elsif ($f=~m/^\(/)	# '(|' or '(&'
		{	$iter= $createrowsub->($iter);
			my $ao= $f eq '(|' ? '|' : '&';
			_set_row($store, $iter, $ao);
		}
		else
		{	next if $f eq '';
			my $leaf= $createrowsub->($iter);
			$firstnewpath=$store->get_path($leaf) unless $firstnewpath;
			_set_row($store, $leaf, $f);
		}
	}
	unless ($store->get_iter_first)	#default filter if no/invalid filter
	{	_set_row($store, $store->append(undef), DEFAULT_FILTER);
	}

	$firstnewpath||=Gtk2::TreePath->new_first;
	my $path_string=$firstnewpath->to_string;
	if ($firstnewpath->get_depth>1)	{ $firstnewpath->up; $treeview->expand_row($firstnewpath,TRUE); }
	else	{ $treeview->expand_all }
	$treeview->set_cursor( Gtk2::TreePath->new($path_string) );
}

sub _set_row
{	my ($store,$iter,$content)=@_;
	my $desc=	$content eq '&' ? _"All of :" :
			$content eq '|' ? _"Any of :" :
			Filter::_explain_element($content) || _("Unknown filter :")." '$content'";
	$store->set($iter, C_NAME,$desc, C_FILTER,$content);
}

sub Result
{	my ($self,$startpath)=@_;
	my $store=$self->{treeview}->get_model;
	my $filter='';
	my $depth=0;
	my $next=$startpath? $store->get_iter($startpath) : $store->get_iter_first;
	while (my $iter=$next)
	{	my $elem=$store->get($iter,C_FILTER);
		if ( $next=$store->iter_children($iter) )
		{	$filter.="($elem\x1D" unless $store->iter_n_children($iter)<2;
			$depth++;
		}
		else
		{	$filter.= $elem."\x1D";
			last unless $depth;
			$next=$store->iter_next($iter);
		}
		until ($next)
		{	last unless $depth and $iter=$store->iter_parent($iter);
			$filter.=")\x1D"  unless $store->iter_n_children($iter)<2;
			$depth--;
			last unless $depth;
			$next=$store->iter_next($iter);
		}
	}
	warn "filter= $filter\n" if $::debug;
	return Filter->new($filter);
}

package GMB::Edit::Sort;
use base 'Gtk2::Box';
use constant { TRUE  => 1, FALSE => 0, SENSITIVE => 1, INSENSITIVE => 2, };
sub new
{	my ($class,$dialog,$init) = @_;
	$init=undef if $init=~m/^random:|^shuffle/;
	my $self = bless Gtk2::VBox->new, $class;

	$self->{store1}=	my $store1=Gtk2::ListStore->new(('Glib::String')x2);
	$self->{store2}=	my $store2=Gtk2::ListStore->new(('Glib::String')x4);
	$self->{treeview1}=	my $treeview1=Gtk2::TreeView->new($store1);
	$self->{treeview2}=	my $treeview2=Gtk2::TreeView->new($store2);
	$treeview2->set_reorderable(TRUE);
	my $order_column= Gtk2::TreeViewColumn->new_with_attributes( 'Order',Gtk2::CellRendererPixbuf->new,'stock-id',2 );
	$treeview2->append_column($order_column);
	my $butadd=	::NewIconButton('gtk-add',	_"Add",		sub {$self->Add_selected});
	my $butrm=	::NewIconButton('gtk-remove',	_"Remove",	sub {$self->Del_selected});
	my $butclear=	::NewIconButton('gtk-clear',	_"Clear",	sub { $self->Set(''); });
	my $butup=	::NewIconButton('gtk-go-up',	undef,		sub { $self->Move_Selected(1,0); });
	my $butdown=	::NewIconButton('gtk-go-down',	undef,		sub { $self->Move_Selected(0,0); });
	$self->{butadd}=$butadd;
	$self->{butrm}=$butrm;
	$self->{butup}=$butup;
	$self->{butdown}=$butdown;

	my $size_group=Gtk2::SizeGroup->new('horizontal');
	$size_group->add_widget($_) for $butadd,$butrm,$butclear;

	$treeview1->get_selection->signal_connect (changed => sub{$self->Buttons_update;});
	$treeview2->get_selection->signal_connect (changed => sub{$self->Buttons_update;});
	$treeview1->signal_connect (row_activated => sub {$self->Add_selected});
	$treeview2->signal_connect (row_activated => sub {$self->Del_selected});
	$treeview2->signal_connect (cursor_changed => \&cursor_changed2_cb,$self);

	my $table=Gtk2::Table->new (2, 4, FALSE);
	my $col=0;
	for ([_"Available",$treeview1,$butadd],[_"Sort order",$treeview2,$butrm,$butclear])
	{	my ($label,$tv,@buts)=@$_;
		my $lab=Gtk2::Label->new;
		$lab->set_markup_with_format('<b>%s</b>',$label);
		$tv->set_headers_visible(FALSE);
		$tv->append_column( Gtk2::TreeViewColumn->new_with_attributes($label,Gtk2::CellRendererText->new,'text',1) );
		my $sw = Gtk2::ScrolledWindow->new;
		$sw->set_shadow_type('etched-in');
		$sw->set_policy('never','automatic');
		$sw->set_size_request(30,200);
		$sw->add($tv);
		my $row=0;
		$table->attach($lab,$col,$col+1,$row++,$row,'fill','shrink',1,1);
		$table->attach($sw,$col,$col+1,$row++,$row,'fill','fill',1,1);
		$table->attach($_,$col,$col+1,$row++,$row,'expand','shrink',1,1) for @buts;
		$col++;
	}
	#my $case_column= Gtk2::TreeViewColumn->new_with_attributes('Case',Gtk2::CellRendererPixbuf->new,'stock-id',3);
	my $caserenderer=Gtk2::CellRendererPixbuf->new;
	my $case_column= Gtk2::TreeViewColumn->new_with_attributes('Case',$caserenderer);
	$treeview2->append_column($case_column);
	$case_column->set_cell_data_func($caserenderer,	sub
	 {	my ($column,$cell,$store2,$iter)=@_;
		my $i=$store2->get_value($iter,3);
		my $stock= !$i ? undef : $i==SENSITIVE ? 'gmb-case_sensitive' : 'gmb-case_insensitive';
		$cell->set(stock_id => $stock);
	 });
	if (*Gtk2::Widget::set_has_tooltip{CODE}) # since gtk+ 2.12, Gtk2 1.160
	{	$treeview2->set_has_tooltip(1);
		$treeview2->signal_connect(query_tooltip=> sub
		 {	my ($treeview2, $x, $y, $keyb, $tooltip)=@_;
			return 0 if $keyb;
			my ($path, $column)=$treeview2->get_path_at_pos($x,$y);
			return 0 unless $path && $column;
			my $store2=$treeview2->get_model;
			my $iter=$store2->get_iter($path);
			return 0 unless $iter;
			my $tip;
			if ($column==$case_column)
			{	my $i=$store2->get_value($iter,3);
				$tip= !$i ? undef : $i==SENSITIVE ? _"Case sensitive" : _"Case insensitive";
			}
			elsif ($column==$order_column)
			{	my $o=$store2->get_value($iter,2);
				$tip= $o eq 'gtk-sort-ascending' ? _"Ascending order" : _"Descending order";
			}
			return 0 unless defined $tip;
			$tooltip->set_text($tip);
			1;
		 });

	}

	my $vbox=Gtk2::VBox->new (FALSE, 4);
	$vbox->pack_start($_,FALSE,TRUE,1) for $butup,$butdown;
	$table->attach($vbox,$col,$col+1,1,2,'shrink','expand',1,1);
	$self->pack_start($table,TRUE,TRUE,1);

	$self->Set($init);
	return $self;
}

sub Set
{	my ($self,$list)=@_;
	$list='' unless defined $list;
	my $store2=$self->{store2};
	$store2->clear;
	$self->{nb2}=0;	#nb of rows in $store2;
	my %cols;
	for my $f (split / /,$list)
	{   my $o=($f=~s/^-//)? 'gtk-sort-descending' : 'gtk-sort-ascending';
	    my $i=($f=~s/:i$//)? INSENSITIVE : SENSITIVE;
	    $i=0 unless Songs::SortICase($f);
	    my $text= Songs::FieldName($f);
	    $store2->set($store2->append,0,$f,1,$text,2,$o,3,$i);
	    $self->{nb2}++;
	    $cols{$f}=1;
	}

	my $store1=$self->{store1};
	$store1->clear;
	for my $f (sort { Songs::FieldName($a) cmp Songs::FieldName($b) } Songs::SortKeys())
	{   next if $cols{$f};
	    $store1->set($store1->append,0,$f,1,Songs::FieldName($f));
	}
	$self->Buttons_update;
}

sub cursor_changed2_cb
{	my ($treeview2,$self)=@_;
	my ($path,$col)=$treeview2->get_cursor;
	return unless $path && $col;
	my $store2=$self->{store2};
	my $iter=$store2->get_iter($path);
	if ($col eq $treeview2->get_column(0))
	{	my $o=$store2->get_value($iter,2);
		$o=($o eq 'gtk-sort-ascending')? 'gtk-sort-descending' : 'gtk-sort-ascending';
		$store2->set($iter,2,$o);
	}
	elsif ($col eq $treeview2->get_column(2))
	{	my $i=$store2->get_value($iter,3);
		return unless $i;
		$i= $i==1? INSENSITIVE : SENSITIVE;
		$store2->set($iter,3,$i);
	}
}

sub Add_selected
{	my $self=shift;
	my $path=($self->{treeview1}->get_cursor)[0]||return;
	my $store1=$self->{store1};
	my $store2=$self->{store2};
	my $iter=$store1->get_iter($path);
	return unless $iter;
	my ($f,$v)=$store1->get_value($iter,0,1);
	$store1->remove($iter);
	my $i=( Songs::SortICase($f) )? INSENSITIVE : 0;	#default to case-insensitive
	$store2->set($store2->append,0,$f,1,$v,2,'gtk-sort-ascending',3,$i);
	$self->{nb2}++;
	$self->Buttons_update;
}
sub Del_selected
{	my $self=shift;
	my $path=($self->{treeview2}->get_cursor)[0]||return;
	my $store1=$self->{store1};
	my $store2=$self->{store2};
	my $iter=$store2->get_iter($path);
	my ($f,$v)=$store2->get_value($iter,0,1);
	$store2->remove($iter);
	$self->{nb2}--;
	$store1->set($store1->append,0,$f,1,$v);	#FIXME should be inserted in correct order
	$self->Buttons_update;
}
sub Move_Selected
{	my ($self,$up,$max)=@_;
	my $path=($self->{treeview2}->get_cursor)[0]||return;
	my $store2=$self->{store2};
	my $iter=$store2->get_iter($path);
	if ($max)
	{	if ($up) { $store2->move_after($iter,undef); }
		else	 { $store2->move_before($iter,undef);}
		return;
	}
	my $row=$path->to_string;
	if ($up) {$row--} else {$row++}
	my $iter2=$store2->get_iter_from_string($row)||return;
	$store2->swap($iter,$iter2);
	$self->Buttons_update;
};


sub Buttons_update	#update sensitive state of buttons
{	my $self=shift;
	$self->{butadd}->set_sensitive( $self->{treeview1}->get_selection->count_selected_rows );
	my ($sel)=$self->{treeview2}->get_selection->get_selected_rows;
	if ($sel)
	{	my $row=$sel->to_string;
		$self->{butup}	->set_sensitive($row>0);
		$self->{butdown}->set_sensitive($row<$self->{nb2}-1);
		$self->{butrm}	->set_sensitive(1);
	}
	else { $self->{$_}->set_sensitive(0) for qw/butrm butup butdown/; }
}

sub Result
{	my $self=shift;
	my $store=$self->{store2};
	my $order='';
	my $iter=$store->get_iter_first;
	while ($iter)
	{	my ($f,$o,$i)=$store->get($iter,0,2,3);
		$order.='-' if $o eq 'gtk-sort-descending';
		$order.=$f;
		$order.=':i' if $i==INSENSITIVE;
		$order.=' ' if $iter=$store->iter_next($iter);
	}
	return $order;
}

package GMB::Edit::WRandom;
use base 'Gtk2::Box';
use constant
{ TRUE  => 1, FALSE => 0,
  NBCOLS	=> 20,
  COLWIDTH	=> 15,
  HHEIGHT	=> 100,
  HWIDTH	=> 20*15,
};
sub new
{	my ($class,$dialog,$init) = @_;
	my $self = bless Gtk2::VBox->new, $class;

	my $table=Gtk2::Table->new (1, 4, FALSE);
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('never','automatic');
	$sw->add_with_viewport($table);
	$self->add($sw);

	my $addlist=TextCombo->new({map {$_ => $Random::ScoreTypes{$_}{desc}} keys %Random::ScoreTypes}, (keys %Random::ScoreTypes)[0] );
	my $addbut=::NewIconButton('gtk-add',_"Add");
	my $addhbox=Gtk2::HBox->new(FALSE, 8);
	$addhbox->pack_start($_,FALSE,FALSE,0) for Gtk2::Label->new(_"Add rule : "), $addlist, $addbut;

	my $histogram=Gtk2::DrawingArea->new;
	my $histoframe=Gtk2::Frame->new;
	my $histoAl=Gtk2::Alignment->new(.5,.5,0,0);
	$histoframe->add($histogram);
	$histoAl->add($histoframe);

	my $LabEx=$self->{example_label}=Gtk2::Label->new;
	$self->pack_start($_,FALSE,FALSE,2) for $addhbox,$histoAl,$LabEx;

	$histogram->size(HWIDTH,HHEIGHT);
	$histogram->signal_connect(expose_event => \&histogram_expose_cb);
	$histogram->set_tooltip_text('');
	$histogram->add_events([qw/enter-notify-mask leave-notify-mask/]);
	$histogram->signal_connect(enter_notify_event => sub
		{	$_[0]{timeout}=Glib::Timeout->add(500,\&UpdateTip_timeout,$histogram);0;
		});
	$histogram->signal_connect(leave_notify_event => sub { Glib::Source->remove( $_[0]{timeout} );0; });

	$addbut->signal_connect( clicked => sub
		{	my $type=$addlist->get_value;
			$self->AddRow( $Random::ScoreTypes{$type}{default} );
		});
	::Watch($self,	CurSong		=>\&UpdateID);
	::Watch($self,	SongsChanged	=>\&SongsChanged_cb);
	::Watch($self,	SongArray	=>\&SongArray_cb);
	$self->signal_connect( destroy => \&cleanup );

	$self->{histogram}=$histogram;
	$self->{table}=$table;
	$self->Set($init);

	return $self;
}

sub cleanup
{	my $self=shift;
	delete $self->{need_redraw};
}

sub Set
{	my ($self,$sort)=@_;
	$sort=~s/^random://;
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
	$self->{frames}=[];
	$self->{row}=0;
	return unless $sort;
	$self->AddRow($_) for split /\x1D/,$sort;
}

sub Redraw
{	my ($self,$queue)=@_;
	if ($queue)
	{	unless ($self->{need_redraw}++)
		{	Glib::Timeout->add(300, sub
			{	return 0 unless $self->{need_redraw}; # redraw not needed anymore
				return $self->{need_redraw}=1 if  --$self->{need_redraw};
				# draw now if no change since last timeout
				$self->Redraw;
				return 0;
			});
		}
		return;
	}
	delete $self->{need_redraw};
	my $histogram=$self->{histogram};
	$histogram->{col}=undef;
	my $r=$self->get_random;
	my ($tab)= ($histogram->{tab},$self->{sum})= $r->MakeTab(NBCOLS);
	$histogram->{max}= (sort { $b <=> $a } @$tab)[0] ||0;
	$histogram->queue_draw;

	$self->{depend_fields}=$r->fields;
	$self->UpdateID; #update examples

	0;
}
sub SongsChanged_cb
{	my ($self,$IDs,$fields)=@_;
	return if $self->{need_redraw};
	return unless ::OneInCommon($fields,$self->{depend_fields});
	return if $IDs && !@{ $ListPlay->AreIn($IDs) };
	$self->Redraw(1);
}
sub SongArray_cb
{	my ($self,$array,$action)=@_;
	return if $self->{need_redraw};
	return unless $array==$ListPlay;
	return if grep $action eq $_, qw/mode sort move up down/;
	$self->Redraw(1);
}

sub histogram_expose_cb
{	my ($histogram,$event)=@_;
	my $max= $histogram->{max};
	return 0 unless $max;
	#my $gc = $histogram->style->fg_gc($histogram->state);
	my @param=($histogram->window, 'selected', 'out', $event->area, $histogram, undef);
	for my $x (0..NBCOLS-1)
	{	my $y=int(HHEIGHT* ($histogram->{tab}[$x]||0)/$max );
		#$histogram->window->draw_rectangle($gc,TRUE,COLWIDTH*$x,HHEIGHT-$y,COLWIDTH,$y);
		$histogram->style->paint_box(@param, COLWIDTH*$x,HHEIGHT-$y,COLWIDTH,$y);
		#warn "histogram : $x $y\n";
	}
	1;
}

sub UpdateTip_timeout
{	my $histogram=$_[0];
	my ($x,$y)=$histogram->get_pointer;#warn "$x,$y\n";
	return 0 if $x<0;
	my $col=int($x/COLWIDTH);
	return 1 if $histogram->{col} && $histogram->{col}==$col;
	$histogram->{col}=$col;
	my $nb=$histogram->{tab}[$col]||0;
	my $range=sprintf '%.2f - %.2f',$col/NBCOLS,($col+1)/NBCOLS;
	#my $sum=$histogram->get_ancestor('Gtk2::VBox')->{sum};
	#my $prob='between '.join ' and ',map $_? '1 chance in '.sprintf('%.0f',$sum/$_) : 'no chance', $col/NBCOLS,($col+1)/NBCOLS;
	$histogram->set_tooltip_text( "$range : ".::__('%d song','%d songs',$nb) );
	1;
}

sub AddRow
{	my ($self,$params)=@_;
	my $table=$self->{table};
	my $row=$self->{row}++;
	my $deleted;
	my ($inverse,$weight,$type,$extra)=$params=~m/^(-?)(\d*\.?\d+)([a-zA-Z])(.*)$/;
	return unless $type;
	my $frame=Gtk2::Frame->new( $Random::ScoreTypes{$type}{desc} );
	$frame->{type}=$type;
	push @{$self->{frames}},$frame;
	$frame->{params}=$params;
	my $exlabel=$frame->{label}=Gtk2::Label->new;
	$frame->{unit}=$Random::ScoreTypes{$type}{unit};
	$frame->{round}=$Random::ScoreTypes{$type}{round};
	my $button=::NewIconButton('gtk-remove',undef,sub
		{ my $button=$_[0];
		  my $self=::find_ancestor($button,__PACKAGE__);
		  $frame->{params}=undef;
		  $_->parent->remove($_) for $button,$frame;
		  $self->Redraw(1);
		},'none');
	$button->set_tooltip_text(_"Remove this rule");
	$table->attach($button,0,1,$row,$row+1,'shrink','shrink',1,1);
	$table->attach($frame,1,2,$row,$row+1,['fill','expand'],'shrink',2,4);
	$frame->{adj}=my $adj=Gtk2::Adjustment->new ($weight, 0, 1, .01, .05, 0);
	my $scale=Gtk2::HScale->new($adj);
	$scale->set_digits(2);
	$frame->{check}=my $check=Gtk2::CheckButton->new(_"inverse");
	$check->set_active($inverse);
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_end($exlabel, FALSE, FALSE, 1);

	my $extrasub;
	my $check_tip;
	if ($type eq 'f')
	{	$check_tip=_"ON less probable if label is set\nOFF more probable if label is set";
		#my $labellist=TextCombo->new(::SortedLabels(),$extra,\&update_frame_cb);
		my $labellist= GMB::ListStore::Field::Combo->new('label',$extra,\&update_frame_cb);
		$extrasub=sub { $labellist->get_value; };
		#$extrasub=sub {'Bootleg' };
		$hbox->pack_start($labellist, FALSE, FALSE, 1);
	}
	elsif ($type eq 'g')
	{	$check_tip=_"ON less probable if genre is set\nOFF more probable if genre is set";
		#my $genrelist=TextCombo->new( ::GetGenresList ,$extra,\&update_frame_cb);
		my $genrelist= GMB::ListStore::Field::Combo->new('genre',$extra,\&update_frame_cb);
		$extrasub=sub { $genrelist->get_value; };
		$hbox->pack_start($genrelist, FALSE, FALSE, 1);
	}
	elsif ($type eq 'r')
	{	$exlabel->parent->remove($exlabel);	#remove example to place it in the table
		$check_tip=_"ON -> smaller means more probable\nOFF -> bigger means more probable";
		my @l=split /,/,$extra;
		@l=(0,.1,.2,.3,.4,.5,.6,.7,.8,.9,1) unless @l==11;
		my @adjs;
		my $table=Gtk2::Table->new(3,4,FALSE);
		my $col=0; my $row=0;
		for my $r (0..10)
		{	my $label=Gtk2::Label->new($r*10);
			my $adj=Gtk2::Adjustment->new($l[$r], 0, 1, .01, .1, 0);
			my $spin=Gtk2::SpinButton->new($adj, 2, 2);
			$table->attach_defaults($label,$col,$col+1,$row,$row+1);
			$table->attach_defaults($spin,$col+1,$col+2,$row,$row+1);
			$row++;
			if ($row>2) {$col+=2; $row=0;}
			push @adjs,$adj;
			$spin->signal_connect( value_changed => \&update_frame_cb );
		}
		$extrasub=sub { join ',',map $_->get_value, @adjs; };
		$exlabel->set_alignment(1,.5);
		$table->attach_defaults($exlabel,0,$col+2,$row+1,$row+2);
		$hbox->pack_start($table, TRUE, TRUE, 1);
	}
	else
	{	$check_tip=_"ON -> smaller means more probable\nOFF -> bigger means more probable";
		my $halflife=$extra;
		my $adj=Gtk2::Adjustment->new ($halflife, 0.1, 10000, 1, 10, 0);
		my $spin=Gtk2::SpinButton->new($adj, 5, 1);
		$hbox->pack_start($_, FALSE, FALSE, 0)
		  for	Gtk2::Label->new(_"half-life : "),$spin,
			Gtk2::Label->new( $frame->{unit}||'' );
		$extrasub=sub { $adj->get_value; };
		$spin->signal_connect( value_changed => \&update_frame_cb );
	}
	$frame->{extrasub}=$extrasub;
	$check->set_tooltip_text($check_tip);
	$frame->add( ::Vpack(
			'1',[	$check,
				Gtk2::VSeparator->new,
				Gtk2::Label->new(_"weight :"),
				'1_',$scale]
			,$hbox) );
	update_frame_cb($frame);
	$scale->signal_connect( value_changed => \&update_frame_cb );
	$check->signal_connect( toggled => \&update_frame_cb );
	$button->show_all;
	$frame->show_all;
	#warn "new $button $frame\n";
	#$_->signal_connect( destroy => sub {warn "destroy $_[0]\n"}) for $frame,$button;
	$_->signal_connect( parent_set => sub {$_[0]->destroy unless $_[0]->parent}) for $frame,$button; #make sure they don't leak
}

sub update_frame_cb
{	my $frame=::find_ancestor($_[0],'Gtk2::Frame');
	my $inverse=$frame->{check}->get_active;
	my $weight=$frame->{adj}->get_value;
	::setlocale(::LC_NUMERIC, 'C');
	my $extra= $frame->{extrasub}();
	$frame->{params}=($inverse? '-' : '').$weight.$frame->{type}.$extra;
	::setlocale(::LC_NUMERIC, '');
	_frame_example($frame);
	my $self=::find_ancestor($frame,__PACKAGE__);
	$self->Redraw(1);
}

sub _frame_example
{	my $frame=shift;
	my $p=$frame->{params};
	return unless $p;
	$frame->{label}->set_markup_with_format( '<small><i>%s %s</i></small>', _("ex :"), Random->MakeExample($p,$::SongID)) if defined $::SongID;
}

sub UpdateID
{	my $self=shift;
	for my $frame (@{$self->{frames}})
	{	_frame_example($frame);
	}
	my $r= $self->get_random;
	return unless defined $::SongID;
	my $s=$r->CalcScore($::SongID);
	my $v=sprintf '%.3f', $s;
	my $prob;
	if ($s)
	{ $prob=$self->{sum}/$s;
	  $prob= ::__x( _"1 chance in {probability}", probability => sprintf($prob>=10? '%.0f' : '%.1f', $prob) );
	}
	else {$prob=_"0 chance"}
	$self->{example_label}->set_markup_with_format( '<small><i>%s</i></small>', ::__x( _"example (selected song) : {score}  ({chances})", score =>$v, chances => $prob) );
}

sub get_string
{	join "\x1D",grep defined,map $_->{params}, @{$_[0]{frames}};
}
sub get_random
{	my $self=shift;
	my $string=$self->get_string;
	#return Random->new( $string );
	return $self->{randommode} if $self->{randommode} && $self->{randommode}{string} eq $string;
	return $self->{randommode}=Random->new( $string );
}

sub Result
{	my $self=shift;
	my $sort='random:'.$self->get_string;
	$sort=undef if $sort eq 'r';
	return $sort;
}

package GMB::FilterBox;
use base 'Gtk2::Box';

our (%ENTRYTYPE);

INIT
{ %ENTRYTYPE=
  (	substring=>'GMB::FilterEdit::String',
	string	=> 'GMB::FilterEdit::String',
	regexp	=> 'GMB::FilterEdit::String',
	number	=> 'GMB::FilterEdit::Number',
	value	=> 'GMB::FilterEdit::Number',
	date	=> 'GMB::FilterEdit::Date',
	ago	=> 'GMB::FilterEdit::Number',
	fuzzy	=> 'GMB::FilterEdit::Number',
	listname=> 'GMB::FilterEdit::SavedListCombo',
	filename=> 'GMB::FilterEdit::Filename',
	combostring=> 'GMB::FilterEdit::Combo',
	menustring=> 'GMB::FilterEdit::Menu',
  );
}

sub new
{	my ($class,$activatesub,$changesub,$filter,@menu_append)=@_;
	my $self = bless Gtk2::HBox->new, $class;
	$filter='' if $filter eq 'null';
	my ($field,$set)= split /:/,$filter,2;
	my %fieldhash; $fieldhash{$_}= Songs::FieldName($_) for Songs::Fields_with_filter;
	my @ordered_field_hash= map { $_,$fieldhash{$_} } ::sorted_keys(\%fieldhash);
	if (@menu_append)
	{	push @ordered_field_hash, '','';
		my $n=0;
		while (@menu_append)
		{	my ($text,$sub)= splice @menu_append,0,2;
			my $key= '@ACTION'.$n++;
			$self->{$key}= $sub;
			push @ordered_field_hash, $key,$text;
		}
	}
	#FIXME add unknown $field ?
	my $combo= TextCombo->new( \@ordered_field_hash, $field, \&field_changed_cb, ordered_hash=>1, separator=>1 );		#FIXME should be updated when fields_reset
	$self->{fieldcombo}= $combo;
	$self->pack_start($combo,0,0,0);
	$self->Set(set=>"$field:$set");
	$self->{activatesub}=$activatesub;
	$self->{changesub}=$changesub;
	return $self;
}

sub field_changed_cb
{	my $self= ::find_ancestor($_[0],__PACKAGE__);
	return if $self->{busy};
	my $field= $self->{fieldcombo}->get_value;
	if ($field=~m/^@/) #@ACTION
	{	$self->{$field}->();
		$self->{busy}=1;
		$self->{fieldcombo}->set_value($self->{field});
		delete $self->{busy};
		return
	}
	$self->Set(field=>$field);
}
sub cmd_changed_cb
{	my ($item,$cmd)=@_;
	my $self= ::find_ancestor($item,__PACKAGE__);
	$self->Set(cmd=>$cmd);
}

sub Set
{	my ($self,$action,$newvalue)=@_;
	my %previous;
	if (my $w=delete $self->{w_invert})
	{	$previous{inv}= $w->get_active;
	}
	if (my $w=delete $self->{w_pattern})
	{	if (ref $w)
		{	$previous{pattern}= [map $_->Get,@$w];
			$previous{editwidget}= [map ref, @$w];
		}
	}
	if (my $w=delete $self->{w_icase})
	{	$previous{icase}= $w->get_active;
	}
	$self->remove($_) for grep $_ != $self->{fieldcombo}, $self->get_children;
	my ($field,$cmd);
	if ($action eq 'field')
	{	$field=$newvalue;
		my $d1= Songs::Field_property($self->{field},'default_filter');
		my $d2= Songs::Field_property($field,'default_filter');
		$cmd= $d1 eq $d2 ? $self->{cmd} : $d2;
	}
	elsif ($action eq 'cmd')
	{	$cmd=$newvalue;
		$field=$self->{field};
	}
	elsif ($action eq 'set')
	{	%previous=();
		($field,$cmd)= split /:/,$newvalue,2;
	}
	else {return}

	my $filters= Songs::Field_filter_choices($field);
	my $menu= $self->{cmdmenu}=Gtk2::Menu->new;
	for my $f (::sorted_keys($filters))
	{	my $item= Gtk2::MenuItem->new( $filters->{$f} );
		$item->signal_connect( activate => \&cmd_changed_cb,$f);
		$menu->append($item);
	}

	($cmd,my $pattern)= split /:/,$cmd,2;
	$pattern='' unless defined $pattern;
	my ($basecmd,my $prop)= Songs::filter_properties($field,"$cmd:$pattern");
	if (!$prop)
	{	$cmd=  Songs::Field_property($field,'default_filter');
		($basecmd,$prop)= Songs::filter_properties($field,$cmd);
		if (!$prop)	# shouldn't happen
		{	warn "error: can't find default filter '$cmd' for field $field\n";
			$prop=['',undef,''];
			$basecmd=$cmd;
		}
	}
	my ($text,undef,$type,%opt)=@$prop;
	$opt{field}=$field;
	my @type=split / /,$type;
	my @pattern= split / /,$pattern,scalar @type;

	if (!$opt{noinv})
	{	my $button= $self->{w_invert}= Gtk2::ToggleButton->new;
		$button->add( Gtk2::Image->new_from_stock('gmb-invert','menu') );
		my $on= $cmd=~s/^-//;
		$on= $previous{inv} unless $action eq 'set';
		$button->set_active(1) if $on;
		$button->signal_connect(toggled=> \&changed);
		$button->set_tooltip_text(_"Invert filter");
		$button->set_relief('none');
		$self->pack_start($button,0,0,0);
	}

	my $i=0; my $textbutton=0;
	for my $part (split /\s*(%s)\s*/,$text)
	{	if ($part eq '%s')
		{	my $type= shift @type;
			my $opt2= Songs::Field_property($field,'filterpat:'.$type) || [];
			my %opt2= (%opt, @$opt2, value_index=>$i++);
			my $class= $ENTRYTYPE{$type};
			my $pattern= shift @pattern;
			next unless $class;
			if ($previous{pattern})
			{	my $p= shift @{$previous{pattern}};
				my $t= shift @{$previous{editwidget}} || '';
				$pattern=$p if $t eq $class;
			}
			$pattern='' unless defined $pattern;
			my $widget= $class->new($pattern, \%opt2);
			$self->pack_start($widget,0,0,0);
			push @{$self->{w_pattern}}, $widget;
			if ($opt2{icase} && !$self->{w_icase})
			{	my $button= $self->{w_icase}= Gtk2::ToggleButton->new;
				$button->add( Gtk2::Image->new_from_stock('gmb-case_sensitive','menu') );
				my $on= $cmd!~s/i$//;
				$on= $previous{icase} unless $action eq 'set';
				$button->set_active(1) if $on;
				$button->signal_connect(toggled=> \&changed);
				$button->set_tooltip_text(_"Case sensitive");
				$button->set_relief('none');
				$self->pack_start($button,0,0,0);
			}
		}
		elsif ($part ne '')
		{	my $button= Gtk2::Button->new($part);
			$button->set_relief('none') if $textbutton++;
			$button->signal_connect( button_press_event => \&popup_menu_cb);
			$button->signal_connect( clicked => \&popup_menu_cb);
			$self->pack_start($button,0,0,0);
		}
	}

	$self->{cmd}=$basecmd;
	$self->{field}=$field;
	$self->show_all;
	$self->changed;
}
sub Get
{	my $self=shift;
	my $cmd= $self->{cmd};
	if (my $w=$self->{w_invert})
	{	$cmd=~s/^-//;
		$cmd= '-'.$cmd if $w->get_active;
	}
	if (my $w=$self->{w_icase})
	{	$cmd=~s/i$//;
		$cmd.= 'i' unless $w->get_active;
	}
	::setlocale(::LC_NUMERIC, 'C');
	if (my $patterns= $self->{w_pattern})
	{	$cmd.= ':'. join(' ',map $_->Get, @$patterns);
	}
	::setlocale(::LC_NUMERIC, '');
	my $filter= $self->{field}.':'.$cmd;
	return $filter;
}

sub popup_menu_cb
{	my $button=shift;
	my $self=::find_ancestor($button,__PACKAGE__);
	my $menu= $self->{cmdmenu};
	::PopupMenu($menu);
	0;
}

sub changed
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	return unless $self->{changesub};
	$self->{changesub}( $self->Get );
}
sub activate
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	return unless $self->{activatesub};
	$self->{activatesub}( $self->Get );
}

package GMB::FilterEdit::String;
use base 'Gtk2::Entry';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless Gtk2::Entry->new, $class;
	$self->set_text($val);
	$self->signal_connect(changed=> \&GMB::FilterBox::changed);
	$self->signal_connect(activate=> \&GMB::FilterBox::activate);
	GMB::ListStore::Field::setcompletion($self,$opt->{field}) if $opt->{completion};
	return $self;
}
sub Get
{	$_[0]->get_text;
}

package GMB::FilterEdit::Combo;
use base 'GMB::ListStore::Field::Combo';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless GMB::ListStore::Field::Combo->new($opt->{field},$val,\&GMB::FilterBox::changed),$class;
	#$self->set_size_request(300,-1); #FIXME limit size
	return $self;
}
sub Get { $_[0]->get_value; }

package GMB::FilterEdit::Menu;	# alternative to GMB::FilterEdit::Combo that better handle long list of values, and works with album filters
use base 'Gtk2::Button';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless Gtk2::Button->new,$class;
	$self->{field}=$opt->{field};
	$self->{val}=$val;
	$self->signal_connect(button_press_event => sub
		{	my $self=$_[0];
			::PopupAA( $self->{field}, cb=> sub { $self->set_gid($_[0]{key}); }, noalt=>1 );
			1;
		});
	$self->set_label($val);
	return $self;
}
sub Get { $_[0]{val}; }
sub set_gid
{	my ($self,$gid)=@_;
	my $field= $self->{field};
	 #ugly way to get the sgid	#FIXME
	 my $val=Songs::MakeFilterFromGID($field,$gid);
	 $val=$val->{string};
	 $val=~s/^$field:~://;
	$self->{val}=$val;
	$self->set_label($val);
	GMB::FilterBox::changed($self);
	GMB::FilterBox::activate($self);
}

package GMB::FilterEdit::Filename;
use base 'Gtk2::Box';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless Gtk2::HBox->new(0,0),$class;
	my $entry= $self->{entry}= Gtk2::Entry->new;
	my $button= ::NewIconButton('gtk-open');
	$self->pack_start($entry,1,1,0);
	$self->pack_start($button,0,0,0);
	$self->Set($val);
	my $busy;
	$entry->signal_connect( changed => sub
	{	return if $busy;
		my $entry=shift;
		my $self=$entry->parent;
		$self->{value}= ::url_escape($entry->get_text);
		GMB::FilterBox::changed($self);
	});
	$entry->signal_connect(activate=> \&GMB::FilterBox::activate);
	$button->signal_connect( clicked => sub
	{	my $self=$_[0]->parent;
		my $folder= ::ChooseDir(_"Choose a folder", path=>$self->{value});
		return unless $folder;
		$busy=1;
		$self->Set( ::url_escape($folder) );
		$busy=0;
		GMB::FilterBox::changed($self);
		GMB::FilterBox::activate($self);
	});
	return $self;
}
sub Set
{	my ($self,$folder)= @_;
	$self->{entry}->set_text( ::filename_to_utf8displayname(::decode_url($folder)) );
	$self->{value}=$folder;
}
sub Get { $_[0]{value} }

package GMB::FilterEdit::SavedListCombo;
use base 'Gtk2::ComboBox';
our @ISA;
BEGIN {unshift @ISA,'TextCombo';}
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless TextCombo->new([keys %{$::Options{SavedLists}}],$val,\&GMB::FilterBox::changed),$class;
	::Watch($self,SavedLists=>\&fill);
	return $self;
}
sub fill { $_[0]->build_store( [keys %{$::Options{SavedLists}}] ); }
sub Get { $_[0]->get_value; }

package GMB::FilterEdit::Number;
use base 'Gtk2::Box';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless Gtk2::HBox->new, $class;

	my $max=  $opt->{max} || 999999;
	my $min=  $opt->{min} || $opt->{signed} ? -$max : 0;
	my $step= $opt->{step}|| 1;
	my $page= $opt->{page}|| $step*10;
	my $digits=$opt->{digits}|| 0;
	$val= $opt->{default_value}||0 if $val eq '';
	my $unit0;
	$unit0= $1 if $val=~s/([a-zA-Z]+)$//;
	::setlocale(::LC_NUMERIC, 'C');
	$val= $val+0;	#make sure "." is used as the decimal separator
	::setlocale(::LC_NUMERIC, '');
	my $spin= $self->{spin}= Gtk2::SpinButton->new( Gtk2::Adjustment->new($val, $min, $max, $step, $page, 0) ,1,$digits );
	$spin->set_numeric(1);
	$self->pack_start($spin,0,0,0);

	if (my $unit=$opt->{unit})
	{	my $extra;
		if (ref $unit eq 'HASH')
		{	$unit0 ||= $opt->{default_unit};
			my @ordered_hash= map { $_ => $unit->{$_}[1] } sort { $unit->{$a}[0] <=> $unit->{$b}[0] } keys %$unit;
			my $set_digits= sub { $spin->set_digits( $unit->{ $_[0]->get_value }[0]==1 ? 0 : 2 ) }; # no decimals for indivisible units, 2 for others
			$extra= $self->{units}= TextCombo->new(\@ordered_hash, $unit0, sub { $set_digits->($_[0]); &GMB::FilterBox::changed}, ordered_hash=>1);
			$set_digits->($extra);
			$spin->signal_connect(key_press_event => sub	#catch letter key-press to change unit
				{	my $key=Gtk2::Gdk->keyval_name($_[1]->keyval);
					if (exists $unit->{$key}) { $extra->set_value($key); return 1 }
					0;
				});
		}
		elsif (ref $unit eq 'CODE')
		{	my $init= $unit->($val||0, 1);
			$extra= Gtk2::Label->new($init);
			$self->{unit_code}=$unit;
			$spin->signal_connect(value_changed => sub
				{	my $self=::find_ancestor($_[0],__PACKAGE__);
					my $v= $_[0]->get_adjustment->get_value;
					$extra->set_text( $self->{unit_code}->($v,1) );
				});
		}
		elsif ($unit)	{ $extra= Gtk2::Label->new($unit); }
		$self->pack_start($extra,0,0,0) if $extra;
	}

	$spin->signal_connect(value_changed => \&GMB::FilterBox::changed);
	$spin->signal_connect(activate => \&GMB::FilterBox::activate);
	return $self;
}
sub Get
{	my $self=shift;
	my $value= $self->{spin}->get_adjustment->get_value;
	::setlocale(::LC_NUMERIC, 'C');
	$value="$value"; #make sure "." is used as the decimal separator
	::setlocale(::LC_NUMERIC, '');
	if (my $u=$self->{units})
	{	$value.= $u->get_value;
	}
	return $value;
}

package GMB::FilterEdit::Date;
use base 'Gtk2::Button';
sub new
{	my ($class,$val,$opt)=@_;
	my $self= bless Gtk2::Button->new;
	$self->{date}= $val || ::mktime( ( $opt->{value_index} ? (59,59,23) : (0,0,0) ), (localtime)[3,4,5]); # default to today 0:00 or today 23:59
	$self->set_label( ::strftime_utf8('%c',localtime($self->{date})) );
	$self->signal_connect (clicked => sub
	{	my $self=shift;
		if ($self->{popup}) { $self->destroy_calendar; return; }
		$self->popup_calendar;
	});
	return $self;
}
sub Get { $_[0]{date}; }

sub destroy_calendar
{	if (my $popup=delete $_[0]->{popup}) { $popup->destroy }
}
sub popup_calendar
{	my $self=$_[0];
	my $popup=Gtk2::Window->new();
	$popup->set_decorated(0);
	$popup->set_border_width(5);
	$self->{popup}=$popup;
	my $cal=Gtk2::Calendar->new;
	$popup->set_modal(::TRUE);
	$popup->set_type_hint('dialog');
	$popup->set_transient_for($self->get_toplevel);
	my @time=(0,0,0);
	if (my $date=$self->{date})
	{	my ($s,$m,$h,$d,$M,$y)= localtime($date);
		$cal->select_month($M,$y+1900);
		$cal->select_day($d);
		@time=($h,$m,$s)
	}
	$cal->signal_connect(day_selected_double_click => sub
		{	my ($y,$m,$d)=$_[0]->get_date;
			$y-=1900;
			my @time= map $_->get_value, reverse @{$_[0]{timeadjs}};
			$self->{date}= ::mktime(@time,$d,$m,$y);
			$self->set_label( ::strftime_utf8('%c',@time,$d,$m,$y) );
			$self->destroy_calendar;
			GMB::FilterBox::changed($self);
			GMB::FilterBox::activate($self);
		});
	my $vbox= Gtk2::VBox->new(0,0);
	my $hbox= Gtk2::HBox->new(0,0);
	$vbox->add($cal);
	$vbox->pack_end($hbox,0,0,0);
	my $arrow0= Gtk2::Button->new; $arrow0->add( Gtk2::Arrow->new('left','none') );
	my $arrow1= Gtk2::Button->new; $arrow1->add( Gtk2::Arrow->new('right','none') );
	$_->set_relief('none') for $arrow0,$arrow1;
	$hbox->pack_start($arrow0,0,0,2);
	my @timelabels= (_("Time :"),':',':');
	for my $i (0..2)
	{	my $adj= Gtk2::Adjustment->new($time[$i], 0, ($i? 59 : 23), 1, ($i? 15 : 8), 0);
		my $spin= Gtk2::SpinButton->new($adj,1,0);
		$spin->set_numeric(1);
		push @{ $cal->{timeadjs} }, $adj;
		$hbox->pack_start( Gtk2::Label->new($timelabels[$i]),0,0,2 );
		$hbox->pack_start($spin,0,0,2);
	}
	$arrow0->signal_connect(clicked=> sub { $_->set_value($_->lower) for @{ $cal->{timeadjs} }; });
	$arrow1->signal_connect(clicked=> sub { $_->set_value($_->upper) for @{ $cal->{timeadjs} }; });
	$hbox->pack_start($arrow1,0,0,2);
	my $frame=Gtk2::Frame->new;
	$frame->add($vbox);
	$frame->set_shadow_type('out');
	$popup->add($frame);

	$popup->child->show_all; #needed to calculate position
	$popup->child->realize;
	$popup->move(::windowpos($popup,$self));
	$popup->show_all;
	Gtk2::Gdk->pointer_grab($popup->window, 0, 'button-press-mask', undef, undef,0);
	$popup->signal_connect(button_press_event=> sub {unless ($_[1]->window->get_toplevel==$popup->window) {$self->{popup}=undef;$popup->destroy}});
	#$cal->grab_focus;
}


package GMB::Cache;
my %Cache; my $CacheSize;

INIT { $CacheSize=0; }

sub drop_file	#drop a file from the cache
{	my $file=shift;
	my $re=qr/^(?:\d+:)?\Q$file\E/;
	delete $Cache{$_} for grep m/$re/, keys %Cache;
}

sub trim
{	my @list= sort {$Cache{$a}{lastuse} <=> $Cache{$b}{lastuse}} keys %Cache;
	my $max= $::Options{PixCacheSize} *1000*1000 *.9;
	warn "Trimming cache\n" if $::debug;
	while ($CacheSize> $max)
	{	my $key=shift @list;
		$CacheSize-= (delete $Cache{$key})->{size};
	}
}

sub add_pb	#add pixbuf ref
{	my ($key,$pb)=@_;
	$pb->{size}= $pb->get_height * $pb->get_rowstride;
	add($key,$pb);
}
sub add
{	my ($key,$ref)=@_;
	$ref->{lastuse}=time;
	$CacheSize+= $ref->{size};
	::IdleDo('9_CachePurge',undef,\&trim) if $CacheSize > $::Options{PixCacheSize}*1000*1000;
	$Cache{$key}=$ref;
}
sub get
{	my $key=shift;
	my $ref= $Cache{$key};
	$ref->{lastuse}=time if $ref;
	return $ref;
}


package GMB::Picture;
our @ArraysOfFiles;	#array of filenames that needs updating in case a folder is renamed

my ($pdfinfo,$pdftocairo,$gs);
our $pdf_ok;
INIT
{	$pdfinfo= ::findcmd('pdfinfo');
	$pdftocairo= ::findcmd('pdftocairo');
	$pdf_ok= $pdfinfo && ($pdftocairo || ($gs=::findcmd('gs')));
}

sub pixbuf
{	my ($file,$size,$cacheonly,$anim_ok)=@_;
	my $key= defined $size ? $size.':'.$file : $file;
	my $pb= GMB::Cache::get($key);
	unless ($pb || $cacheonly)
	{	$pb=load($file,$size,$anim_ok);
		GMB::Cache::add_pb($key,$pb) if $pb && $pb->isa('Gtk2::Gdk::Pixbuf'); #don't bother caching animation
	}
	return $pb;
}

sub pdf_pages
{	my $file=quotemeta(shift);
	my $ref= GMB::Cache::get("$file:pagecount");
	return $ref->{pagecount} if $ref;
	my $count=0;
	for (qx/$pdfinfo $file/) { if (m/Pages:\s*(\d+)/) {$count=$1;last} }  # hiding the warnings messages could be nice
	GMB::Cache::add("$file:pagecount", {size=>10,pagecount=>$count} ); # using a ref to cache a number is a lot of overhead :(
	return $count;
}

sub load
{	my ($file,$size,$anim_ok)=@_;
	return unless $file;

	my $nb= $file=~s/:(\w+)$// ? $1 : undef;	#index number for embedded pictures
	unless (-e $file) {warn "$file not found\n"; return undef;}

	my $loader=Gtk2::Gdk::PixbufLoader->new;
	$loader->signal_connect(size_prepared => \&PixLoader_callback,$size) if $size;
	if ($file=~m/\.(?:mp3|flac|m4a|m4b|ogg|oga)$/i)
	{	my $data=FileTag::PixFromMusicFile($file,$nb);
		eval { $loader->write($data) } if defined $data;
	}
	elsif ($file=~m/\.pdf$/i && $pdf_ok)
	{	my $n= 1+($nb||0);
		my $fh;
		my $res= (!$size || $size>500) ? 300 : $size>100 ? 150 : 75; #default is usually 150, faster but lower quality # use faster/lower quality for thumbnails
		my $qfile=quotemeta $file;
		#if ($pdftocairo) {open $fh,'-|', "pdftocairo -svg -r 150 -f $n -l $n $qfile -";} # pdftocairo with svg, slower but no temp file
		if ($pdftocairo) # should be able to avoid temp file, but bug in pdftocairo (tries to open fd://0.jpg)
		{	my $tmp= $TempDir.'gmb_pdftocairo';
			#system("pdftocairo -jpeg -singlefile -r $res -f $n -l $n $qfile $tmp"); $tmp.='.jpg'; #with jpeg, seems slightly slower than tiff, and loss of quality
			system("$pdftocairo -tiff -singlefile -r $res -f $n -l $n $qfile ".quotemeta($tmp)); $tmp.='.tif';
			open $fh,'<',$tmp; binmode $fh;
			unlink $tmp;
		}
		elsif ($gs) # usually slower, lower quality, and accents missing in some pdf
		{	open $fh,'-|', "$gs -q -dQUIET -dSAFER -dBATCH -dNOPAUSE -dNOPROMPT -dMaxBitmap=500000000 -sDEVICE=jpeg -dJPEGQ=95 -r$res"."x$res -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dFirstPage=$n -dLastPage=$n -sOutputFile=- $qfile";
		}
		if ($fh)
		{	my $buf; eval {$loader->write($buf) while read $fh,$buf,1024*64;};
			close $fh;
		}
	}
	else	#eval{Gtk2::Gdk::Pixbuf->new_from_file(filename_to_unicode($file))};
		# work around Gtk2::Gdk::Pixbuf->new_from_file which wants utf8 filename
	{	open my$fh,'<',$file; binmode $fh;
		my $buf; eval {$loader->write($buf) while read $fh,$buf,1024*64;};
		close $fh;
	}
	eval {$loader->close;};
	return undef if $@;
	if ($anim_ok)
	{	my $anim=$loader->get_animation;
		return $anim if $anim && !$anim->is_static_image;
	}
	return $loader->get_pixbuf;
}

sub load_skinfile
{	my ($file,$crop,$resize,$now)=@_; #resize is resizeopt_w_h
	my $key= ':'.join ':',$file,$crop,$resize||''; #FIXME remove w or h in resize if not resized in this dimension
	my $pixbuf= GMB::Cache::get($key);
	unless ($pixbuf)
	{	return unless $now;
		$pixbuf=Skin::_load_skinfile($file,$crop);
		$pixbuf=Skin::_resize($pixbuf,split /_/,$resize) if $resize && $pixbuf;
		return unless $pixbuf;
		GMB::Cache::add_pb($key,$pixbuf);
	}
	return $pixbuf;
}

sub RenameFile
{	my ($dir,$old,$newutf8,$window)=@_;
	my $new= ::RenameFile($dir,$old,$newutf8,$window);
	return unless defined $new;
	$dir= ::pathslash($dir); #make sure the path ends with SLASH
	GMB::Cache::drop_file($dir.$old);
	$old=qr/^\Q$dir$old\E$/;
	for my $ref (@ArraysOfFiles) {s#$old#$dir$new# for grep $_, @$ref}
	return $new;
}

sub UpdatePixPath
{	my ($oldpath,$newpath)=@_;
	$_= pathslash($_) for $oldpath,$newpath; #make sure the path ends with SLASH
	$oldpath=qr/^\Q$oldpath\E/;
	for my $ref (@ArraysOfFiles) {s#$oldpath#$newpath# for grep $_, @$ref}
}

sub PixLoader_callback
{	my ($loader,$w,$h,$max)=@_;
	$loader->{w}=$w;
	$loader->{h}=$h;
	if ($max!~s/^-// or $w>$max or $h>$max)
	{	my $r=$w/$h;
		if ($r>1) {$h=int(($w=$max)/$r);}
		else	  {$w=int(($h=$max)*$r);}
		$loader->set_size($w,$h);
	}
}
sub LoadPixData
{	my $pixdata=$_[0]; my $size=$_[1];
	my $loader=Gtk2::Gdk::PixbufLoader->new;
	$loader->signal_connect(size_prepared => \&PixLoader_callback,$size) if $size;
	eval { $loader->write($pixdata); };
	eval { $loader->close; } unless $@;
	$loader=undef if $@;
	warn "$@\n" if $@ && $debug;
	return $loader;
}

sub Scale_with_ratio
{	my ($pix,$w,$h,$q)=@_;
	my $ratio0= $w/$h;
	my $ratio=$pix->get_width / $pix->get_height;
	if    ($ratio>$ratio0) {$h=int($w/$ratio);}
	elsif ($ratio<$ratio0) {$w=int($h*$ratio);}
	$q= $q ? 'bilinear' : 'nearest';
	return $pix->scale_simple($w, $h, $q);
}

sub ScaleImage
{	my ($img,$s,$file)=@_;
	$img->{pixbuf}=load($file) if $file;
	my $pix=$img->{pixbuf};
	if (!$pix || !$s || $s<16) { $img->set_from_pixbuf(undef); return; }
	$img->set_from_pixbuf( Scale_with_ratio($pix,$s,$s,1) );
}

sub pixbox_button_press_cb	# zoom picture when clicked
{	my ($eventbox,$event,$button)=@_;
	return 0 if $button && $event->button != $button;
	my $pixbuf;
	if ($eventbox->{pixdata})
	{	my $loader=LoadPixData($eventbox->{pixdata},350);
		$pixbuf=$loader->get_pixbuf if $loader;
	}
	elsif (my $pb=$eventbox->child->{pixbuf})	{ $pixbuf= Scale_with_ratio($pb,350,350,1); }
	elsif (my $file=$eventbox->child->{filename})	{ $pixbuf= pixbuf($file,350); }
	return 1 unless $pixbuf;
	my $image=Gtk2::Image->new_from_pixbuf($pixbuf);
	my $menu=Gtk2::Menu->new;
	my $item=Gtk2::MenuItem->new;
	$item->add($image);
	$menu->append($item);
	::PopupMenu($menu,event=>$event,nomenupos=>1);
	1;
}


package AAPicture;

my $watcher;

sub GetPicture
{	my ($field,$key)=@_;
	return Songs::Picture($key,$field,'get');
}
sub SetPicture
{	my ($field,$key,$file)=@_;
	GMB::Cache::drop_file($file); #make sure the cache is up-to-date
	Songs::Picture($key,$field,'set',$file);
}

my @imgqueue;
sub newimg
{	my ($field,$key,$size)=@_;
	my $pb= pixbuf($field,$key,$size);
	return Gtk2::Image->new_from_pixbuf($pb) if $pb;	# cached
	return undef unless defined $pb;			# no file
	# $pb=0 => file but not cached

	my $img=Gtk2::Image->new;
	$img->{params}=[$field,$key,$size];
	$img->set_size_request($size,$size);

	Glib::Idle->add(\&idle_loadimg_cb) unless @imgqueue;
	push @imgqueue,$img;
	::weaken($imgqueue[-1]);	#weaken ref so that it won't be loaded after img widget is destroyed
	return $img;
}
sub idle_loadimg_cb
{	my $img;
	for my $i (0..$#imgqueue) { next unless $imgqueue[$i] && $imgqueue[$i]->mapped; $img=splice @imgqueue,$i,1; last } #prioritize currently mapped images
	$img||=shift @imgqueue while @imgqueue && !$img;
	if ($img)
	{	my $pb=pixbuf( @{delete $img->{params}},1 );
		$img->set_from_pixbuf($pb) if $pb;
	}
	return scalar @imgqueue;	#return 0 when finished => disconnect idle cb
}

sub pixbuf
{	my ($field,$key,$size,$now)=@_;
	my $file= GetPicture($field,$key);
	return undef unless $file;
	my $pb=GMB::Picture::pixbuf($file,$size,!$now);
	return 0 unless $pb || $now;
	return $pb;
}

sub draw
{	my ($window,$x,$y,$field,$key,$size,$now,$gc)=@_;
	my $pixbuf=pixbuf($field,$key,$size,$now);
	if ($pixbuf)
	{	my $offy=int(($size-$pixbuf->get_height)/2);#center pic
		my $offx=int(($size-$pixbuf->get_width )/2);
		$gc||=Gtk2::Gdk::GC->new($window);
		$window->draw_pixbuf( $gc, $pixbuf,0,0,	$x+$offx, $y+$offy,-1,-1,'none',0,0);
		return 1;
	}
	return $pixbuf; # 0 if exist but not cached, undef if there is no picture for this key
}

package TextCombo;
use base 'Gtk2::ComboBox';

sub new
{	my ($class,$list,$init,$sub,%opt) = @_;
	my $self= bless Gtk2::ComboBox->new, $class;
	my $buildlist;
	if (ref $list eq 'CODE') { $buildlist=$list; $list= $buildlist->(); }
	my $store=$self->build_store($list,%opt);
	$self->set_model($store);
	my $renderer=Gtk2::CellRendererText->new;
	$self->pack_start($renderer,::TRUE);
	$self->add_attribute($renderer, text => 0);
	if ($opt{separator})	#rows with empty string in col 1 is separator
	{	$self->set_row_separator_func(sub { $_[0]->get($_[1],1) eq ''; });
	}
	$self->set_cell_data_func($renderer,sub { my (undef,$renderer,$store,$iter)=@_; $renderer->set(sensitive=> ! $store->iter_n_children($iter) );  })
		if $self->get_model->isa('Gtk2::TreeStore');	#hide title of submenus
	$self->set_value($init);
	$self->set_value(undef) unless $self->get_active_iter; #in case $init was not found
	$self->signal_connect( changed => sub { &$sub unless $_[0]{busy}; } ) if $sub;
	if ($buildlist && $opt{event})
	{	::Watch( $self, $_, sub { $_[0]->rebuild_store( $buildlist->() ); } ) for split / /,$opt{event};
	}
	return $self;
}

sub rebuild_store
{	my $self=shift;
	$self->{busy}=1;
	my $value= $self->get_value;
	$self->build_store(@_);
	$self->set_value($value) if defined $value;
	delete $self->{busy};
}

sub build_store
{	my ($self,$list,%opt)=@_;
	$self->{ordered_hash}=1 if $opt{ordered_hash};	#when called from rebuild_store, must use same options it got at init => save option
	my $store= $self->get_model || Gtk2::ListStore->new('Glib::String','Glib::String');
	$store->clear;
	my $names=$list;
	if (ref $list eq 'ARRAY' && $self->{ordered_hash})
	{	my $i=0;
		my $array=$list;
		$list=[]; $names=[];
		while ($i<$#$array)
		{	push @$list,$array->[$i++]; push @$names,$array->[$i++];
		}
	}
	elsif (ref $list eq 'HASH')
	{	my $h=$list;
		$list=[]; $names=[];
		for my $key (sort {::superlc($h->{$a}) cmp ::superlc($h->{$b})} keys %$h)
		{	push @$list,$key;
			push @$names,$h->{$key}
		}
	}
	for my $i (0..$#$list)
	{	my $iter= $store->append;
		$store->set($iter, 0,$names->[$i], 1,$list->[$i]);
	}
	return $store;
}

sub set_value
{	my ($self,$value)=@_;
	my $store=$self->get_model;
	$store->foreach( sub
	 {	my ($store,$path,$iter)=@_;
		return 0 if $store->iter_has_child($iter);
		if (!defined $value || ($store->get($iter,1) eq $value))
		{	$self->set_active_iter($iter); return 1;
		}
		return 0;
	 });
}
#sub set_value
#{	my ($self,$value)=@_;
#	my $store=$self->get_model;
#	my $iter=$store->get_iter_first;
#	while ($iter)
#	{	$self->set_active_iter($iter) if $store->get($iter,1) eq $value;
#		$iter=$store->iter_next($iter);
#	}
#}
sub get_value
{	my $self=shift;
	my $iter=$self->get_active_iter;
	return $iter ? $self->get_model->get($iter,1) : undef;
}
sub make_toolitem
{	my ($self,$desc,$menu_item_id,$widget)=@_;	#$self should be contained in $widget (or $widget=undef)
	$widget||=$self;
	$menu_item_id||="$self";
	my $titem=Gtk2::ToolItem->new;
	$titem->add($widget);
	$titem->set_tooltip_text($desc);
	my $item=Gtk2::MenuItem->new_with_label($desc);
	my $menu=Gtk2::Menu->new;
	$item->set_submenu($menu);
	$titem->set_proxy_menu_item($menu_item_id,$item);
	my $radioi;
	my $store=$self->get_model;
	my $iter=$store->get_iter_first;
	while ($iter)
	{	my ($name,$val)=$store->get($iter,0,1);
		$radioi=Gtk2::RadioMenuItem->new_with_label($radioi,$name);
		$radioi->{value}=$val;
		$menu->append($radioi);
		$radioi->signal_connect(activate => sub
			{	return if $_[0]->parent->{busy};
				$self->set_value( $_[0]{value} );
			});
		$iter=$store->iter_next($iter);
	}
	$self->signal_connect(changed => sub
	{	$menu->{busy}=1;
		my $value= $self->get_value;
		for my $item ($menu->get_children)
		{	$item->set_active( defined $value && $item->{value} eq $value );
		}
		delete $menu->{busy};
	});
	return $titem;
}

package TextCombo::Tree;
use base 'Gtk2::ComboBox';
our @ISA;
BEGIN {unshift @ISA,'TextCombo';}

sub build_store
{	my ($self,$list)=@_;			#$list is a list of label,value pairs, where value can be a sublist
	my $store= $self->get_model || Gtk2::TreeStore->new('Glib::String','Glib::String');
	$store->clear;
	my @todo=(undef,$list);
	while (@todo)
	{	my $parent=shift @todo;
		my $list= shift @todo;
		for my $i (sort {::superlc($list->[$a]) cmp ::superlc($list->[$b])} map 1+$_*2, 0..int($#$list/2))
		{	my $iter= $store->append($parent);
			my $key=$list->[$i-1];
			my $name=$list->[$i];
			if (ref $key) { push @todo,$iter,$key; $key=''; }
			$store->set($iter, 0,$name, 1,$key);
		}
	}
	return $store;
}

sub make_toolitem
{	warn "TextCombo::Tree : make_toolitem not implemented\n";	#FIXME not needed for now, but could be in the future
	return undef;
}

package FilterCombo;
use base 'Gtk2::ComboBox';

sub new
{	my ($class,$init,$sub) = @_;
	my $store= Gtk2::ListStore->new('Glib::String','Glib::Scalar','Glib::String');
	my $self= bless Gtk2::ComboBox->new($store), $class;
	$self->fill_store;

	my $renderer=Gtk2::CellRendererPixbuf->new;
	$renderer->set_fixed_size( Gtk2::IconSize->lookup('menu') );
	$self->pack_start($renderer,::FALSE);
	$self->add_attribute($renderer, 'stock-id' => 2);

	$renderer=Gtk2::CellRendererText->new;
	$self->pack_start($renderer,::TRUE);
	$self->add_attribute($renderer, text => 0);

	$self->signal_connect( changed => \&value_changed );
	$self->set_value($init);
	$self->{cb}=$sub;
	::Watch($self, 'SavedFilters', \&SavedFilters_changed);
	return $self;
}

sub value_changed
{	my $self=shift;
	my $iter=$self->get_active_iter;
	return unless $iter;
	my $value= $self->get_model->get($iter,1);
	if (!defined $value)	#edit... filter
	{	my $value=$self->{selected};
		$self->{busy}=1;
		$self->set_value($value);
		delete $self->{busy};
		::EditFilter($self->get_toplevel,$value,undef,sub { $self->set_value($_[0]) if $_[0]; });
		return;
	}
	$self->{selected}=$value;
	$self->set_tooltip_text( $value->explain );	#set tooltip to filter description
	$self->{cb}->($self,$value) if $self->{cb} && !$self->{busy};
}

sub SavedFilters_changed
{	my $self=shift;
	my $value= $self->get_value;
	$self->{busy}=1;
	$self->fill_store;
	$self->set_value($value);
	delete $self->{busy};
}

sub fill_store
{	my $self=shift;
	my $store= $self->get_model;
	$store->clear;
	$store->set($store->append, 0,_"All songs", 1,Filter->new, 2,'gmb-library');
	my $hash=$Options{SavedFilters};
	my @names= sort {::superlc($a) cmp ::superlc($b)} keys %$hash;
	$store->set($store->append, 0,$_, 1,$hash->{$_}) for @names;
	$store->set($store->append, 0,_"Edit...", 1,undef, 2,'gtk-preferences');
}

sub set_value
{	my ($self,$value)=@_;
	$value=Filter->new($value) unless ref $value;
	my $store=$self->get_model;
	my $founditer;
	my $iter=$store->get_iter_first;
	while ($iter)
	{	my $v=$store->get($iter,1);
		if ( defined $v && $value->are_equal($v) )
		{	$founditer=$iter; last;
		}
		$iter=$store->iter_next($iter);
	}
	unless ($founditer)
	{	$founditer= $store->prepend;
		$store->set($founditer, 0, _"Unnamed filter", 1,$value)
	}
	$self->{selected}=$value;
	$self->set_active_iter($founditer);
}
sub get_value
{	$_[0]{selected};
}


package Label::Preview;
use base 'Gtk2::Label';

sub new
{	my ($class,%args)=@_;
	my $self= bless Gtk2::Label->new, $class;
	$self->set_line_wrap(1), $self->set_line_wrap_mode('word-char') if $args{wrap};
	$self->{$_}=$args{$_} for qw/entry preview format empty noescape/;
	my ($event,$entry)=@args{qw/event entry/};
	$entry->signal_connect_swapped( changed => \&queue_update, $self) if $entry;
	if ($event) { ::Watch($self, $_ => \&queue_update) for split / /,$event; }
	$self->update;
	return $self;
}
sub queue_update
{	my $self=shift;
	$self->{queue_update}||= Glib::Idle->add(\&update,$self)
}
sub update
{	my $self=shift;
	my $arg= $self->{entry} ? $self->{entry}->get_text : undef;
	my $text=$self->{preview}->($arg);
	if (defined $text)
	{	my $f= $self->{format} || '%s';
		$text= ::PangoEsc($text) unless $self->{noescape};
		$text=sprintf $f, $text;
	}
	else
	{	$text= $self->{empty};
		$text='' unless defined $text;
	}
	$self->set_markup($text);
	return $self->{queue_update}=undef;
}

package GMB::JobIDQueue;
my %Presence;
my %Properties;
my @ArrayList;

::Watch(undef, SongsRemoved => \&SongsRemoved_cb);

sub new
{	my ($package,%properties)=@_;	#possible properties keys : title, details(optional)
	my $self= bless [],$_[0];
	push @ArrayList, $self;
	$Properties{$self}= \%properties;
	$Properties{$self}{end}=0;
	::weaken($ArrayList[-1]);
	return $self;
}

sub add
{	my $self=shift;
	my $IDs= ref $_[0] ? $_[0] : \@_;
	$Presence{$self}='' unless @$self;
	my @new= grep !vec($Presence{$self},$_,1), @$IDs; #ignore IDs that are already in the list
	vec($Presence{$self},$_,1)=1 for @new;
	$Properties{$self}{end}+= @new;
	push @$self, @new;
}

sub progress
{	my $self=shift;
	my $prop= $Properties{$self};
	return current=> ($prop->{end}-scalar(@$self)), %$prop;
}

sub next
{	my $self=shift;
	my $ID=shift @$self;
	vec($Presence{$self},$ID,1)=0;
	$self->abort unless @$self;
	return $ID;
}

sub abort
{	my $self=shift;
	@$self=();
	delete $Presence{$self};
	$Properties{$self}{end}=0;
}

sub SongsRemoved_cb
{	my $IDs=shift;
	my $remove='';
	vec($remove,$_,1)=1 for @$IDs;
	for my $self (@ArrayList)
	{	next unless @$self;
		@$self= grep !vec($remove,$_,1), @$self;
		vec($Presence{$self},$_,1)=0 for @$IDs;
		$self->abort unless @$self;
	}
}

package GMB::DropURI;

sub new #params : toplevel, cb, cb_end
{	my ($class,%params)=@_;
	my $self= bless \%params,$class;
	return $self;
}

sub Add_URI #params : is_move, destpath
{	my ($self,%params)=@_;
	my $uris= delete $params{uris};
	return if !$params{destpath} || !@$uris;
	push @{$self->{todo}}, $_,\%params for @$uris;
	$self->{total}+= @$uris;
	::Progress( 'DropURI_'.$self, add=>scalar(@$uris), abortcb=>sub{$self->Abort}, bartext=> _('file $current/$end')." :", title=>"",);
	Glib::Timeout->add(10,sub {$self->Next; 0});
}

sub Next
{	my $self=shift;
	return if $self->{current};
	my $todo= $self->{todo};
	unless (@$todo)
	{	$self->Abort;
		return;
	}
	my $uri=shift @$todo;
	my $params= shift @$todo;
	$self->{current}= { %$params, uri=>$uri };
	$self->{done}++;
	$self->{left}= @$todo/2;
	$uri=~s#^file://##;
	$self->{current}{display_uri}= ::filename_to_utf8displayname(::decode_url($uri));
	$self->Start;
}

sub Start
{	my $self=shift;
	my $params= $self->{current};
	my $uri= $params->{uri};
	my $display_uri= $params->{display_uri};
	my $destpath= $params->{destpath};
	my $progressid= 'DropURI_'.$self;
	if ($uri=~s#^file://##)
	{	my $srcfile= ::decode_url($uri);
		my $is_move= $params->{is_move};
		warn "".($is_move ? "Copying" : "Moving")." file '$display_uri' to '$destpath'\n" if $::debug;
		::Progress( $progressid, bartext_append=>$display_uri, title=>($is_move ? _"Moving" : _"Copying"));
		my ($srcpath,$basename)= ::splitpath($srcfile);
		my $new= ::catfile($destpath,$basename);
		if ($srcfile eq $new) { $self->Done; return } # ignore copying file on itself
		my ($sub,$errormsg,$abortmsg)=  $is_move ? (\&::move,_"Move failed",_"abort move")
							 : (\&::copy,_"Copy failed",_"abort copy") ;
		$errormsg.= sprintf " (%d/%d)",$self->{done},$self->{total} if $self->{total} >1;
		if (-f $new) #if file already exists
		{	my $ow= $self->{owrite_all};
			$ow||=::OverwriteDialog($self->{toplevel},$new,$self->{left}>0);
			$self->{owrite_all}=$ow if $ow=~m/all$/;
			if ($ow=~m/^no/) { $self->Skip; return }
			#overwriting
			GMB::Cache::drop_file($new); # mostly for picture files
		}
		until ($sub->($srcfile,$new))
		{	my $res= $self->{skip_all};
			my $details= ::__x(_"Destination: {folder}",	folder=> ::filename_to_utf8displayname($destpath))."\n"
				    .::__x(_"File: {file}",		file  => ::filename_to_utf8displayname($srcfile));
			$res ||= ::Retry_Dialog($!,$errormsg, details=>$details, window=>$self->{toplevel}, abortmsg=>$abortmsg, many=>$self->{left}>0);
			$self->{skip_all}=$res if $res eq 'skip_all';
			if ($res=~m/^skip/)	{ $self->Done; return }
			if ($res eq 'abort')	{ $self->Abort;return }
		}
		$self->{newfile}=$new;
		$self->Done;
	}
	else
	{	unless (eval {require $::HTTP_module}) {warn "Loading $::HTTP_module failed, can't download $display_uri\n"; $self->Done; return}
		warn "Downloading '$display_uri' to '$destpath'\n" if $::debug;
		::Progress( $progressid, bartext_append=>$display_uri, title=>_"Downloading");
		$self->{waiting}= Simple_http::get_with_cb(url => $uri, cache=>1, progress=>1, cb => sub { $self->Downloaded(@_); });
		$self->{track_progress} ||= Glib::Timeout->add(200,
		 sub {	if (my $w= $self->{waiting}) { my ($p,$s)=$w->progress; ::Progress( $progressid, partial=>$p ) if defined $p; }
			else { $self->{track_progress}=0 }
			return $self->{track_progress};
		     });
		return
	}
}

sub Downloaded
{	my ($self,$content,%content_prop)=@_;
	delete $self->{waiting};
	my $type=$content_prop{type};
	my $params= $self->{current};
	my $uri= $params->{uri};
	my $display_uri= $params->{display_uri};
	my $destpath= $params->{destpath};
	unless ($content)
	{	my $error= $content_prop{error}||'';
		my $res= $self->{skip_all};
		$res ||= ::Retry_Dialog($error,_"Download failed.", details=>_("url").': '.$display_uri, window=>$self->{toplevel}, abortmsg=>_"abort", many=>$self->{left});
		$self->{skip_all}=$res if $res eq 'skip_all';
		if    ($res eq 'abort')	{ $self->Abort; }
		elsif ($res eq 'retry')	{ $self->Start; }
		else			{ $self->Done;  } # skip or skip_all
		return
	}
	my ($file,$ext);
	$uri= ::decode_url($uri);
	$uri=~s/\?.*//;
	$file= $content_prop{filename};
	$file= '' unless defined $file;
	$file= $1 if $file eq '' && $uri=~m#([^/]+)$#;
	($file,$ext)= ::barename(::CleanupFileName($file));
	# if uri doesn't have a file name, try to find a good default name, currently mostly used for pictures, so doesn't try very hard for non-pictures
	my $is_pic= $type=~m#^image/(gif|jpeg|png|bmp)# ? $1 : 0;
	$ext='' if $is_pic && $ext!~m/^(?:gif|jpe?g|png|bmp)$/; #make sure common picture types have the correct extension
	if ($ext eq '')
	{	$ext=	$is_pic ? ($is_pic eq 'jpeg' ? 'jpg' : $is_pic) :
			$type=~m#^text/html# ? 'html' :
			$type=~m#^text/plain# ? 'txt' :
			$type=~m#^application/pdf# ? 'pdf' :
			'';
	}
	if ($file eq '')
	{	if ($is_pic) { $file= 'picture00' } #default file name for pictures #FIXME translate ?
		else #not a picture and no name, should maybe ask to confirm
		{	$file= $uri=~m#^w+://([\w.]+)/# ? $1.'00' : 'file00';
			$file=~s/\./_/g;
		}
		$file= ::CleanupFileName($file);
	}
	$ext= $ext eq '' ? '' : ".$ext";
	$file= ::catfile($destpath,$file);
	::IncSuffix($file) while -e $file.$ext; #could check if same file exist ?
	$file.=$ext;

	{	my $fh;
		open($fh,'>',$file) && (print $fh $content) && close $fh && last;
		my $res= $self->{skip_all};
		$res ||= ::Retry_Dialog($!,_"Error writing downloaded file", details=> ::__x( _"file: {filename}", filename=>$file)."\n". _("url").': '.$display_uri,
						window=>$self->{toplevel}, abortmsg=>_"abort", many=>$self->{left}>0 );
		$self->{skip_all}=$res if $res eq 'skip_all';
		if ($res=~m/^skip/)	{ $self->Done; return }
		if ($res eq 'abort')	{ $self->Abort;return }
		redo if $res eq 'retry';
	}
	$self->{newfile}= $file;
	$self->Done;
}
sub Done # file done, if no $self->{newfile} it means the file has been skipped
{	my $self=shift;
	my $current=delete $self->{current};
	::Progress( 'DropURI_'.$self, inc=>1 );

	if (my $newfile= delete $self->{newfile})
	{	warn "Dropped file : $newfile\n" if $::debug;
		$self->{cb}($newfile) if $self->{cb};
	}

	if (@{$self->{todo}}) { Glib::Timeout->add(10,sub {$self->Next; 0}); }
	else {$self->Abort}
}
sub Abort	# GMB::DropURI object must not be used after that
{	my $self=shift;
	$self->{waiting}->abort if $self->{waiting};
	Glib::Source->remove( $self->{track_progress} ) if $self->{track_progress};
	::Progress( 'DropURI_'.$self, abort=>1 );
	$self->{cb_end}() if $self->{cb_end};
	%$self=();	# content is emptied to prevent reference cycles (memory leak)
}
