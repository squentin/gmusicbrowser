#!/usr/bin/perl

# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
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


package main;
use Gtk2 '-init';
use Glib qw/filename_from_unicode filename_to_unicode/;
{no warnings 'redefine'; #some work arounds for old versions of perl-Gtk2 and/or gtk2
 *filename_to_utf8displayname=\&Glib::filename_display_name if *Glib::filename_display_name{CODE};
 *PangoEsc=\&Glib::Markup::escape_text if *Glib::Markup::escape_text{CODE}; #needs perl-Gtk2 version >=1.092
 *Gtk2::Notebook::set_tab_reorderable=	sub {} unless *Gtk2::Notebook::set_tab_reorderable{CODE};
 *Gtk2::AboutDialog::set_url_hook=	sub {} unless *Gtk2::AboutDialog::set_url_hook{CODE};	#for perl-Gtk2 version <1.080~1.083
 *Gtk2::Label::set_ellipsize=		sub {} unless *Gtk2::Label::set_ellipsize{CODE};	#for perl-Gtk2 version <1.080~1.083
 *Gtk2::Pango::Layout::set_height=	sub {} unless *Gtk2::Pango::Layout::set_height{CODE};	#for perl-Gtk2 version <1.180  pango <1.20
 my $set_clip_rectangle_orig=\&Gtk2::Gdk::GC::set_clip_rectangle;
 *Gtk2::Gdk::GC::set_clip_rectangle=sub { &$set_clip_rectangle_orig if $_[1]; } if $Gtk2::VERSION <1.102; #work-around $rect can't be undef in old bindings versions
}
use POSIX qw/setlocale LC_NUMERIC LC_MESSAGES strftime mktime/;
use List::Util qw/min max sum first/;
use File::Copy;
use File::Spec::Functions qw/file_name_is_absolute catfile rel2abs/;
use Fcntl qw/O_NONBLOCK O_WRONLY O_RDWR SEEK_SET/;
use Encode qw/_utf8_on _utf8_off/;
use Scalar::Util qw/blessed weaken refaddr/;
use Unicode::Normalize 'NFKD'; #for accent-insensitive sort and search, only used via superlc()

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
 VERSION => '1.1003',
 VERSIONSTRING => '1.1.3',
 PIXPATH => $DATADIR.SLASH.'pix'.SLASH,
 PROGRAM_NAME => 'gmusicbrowser',
# PERL510 => $^V ge 'v5.10',

 DRAG_STRING	=> 0, DRAG_USTRING	=> 1, DRAG_FILE		=> 2,
 DRAG_ID	=> 3, DRAG_ARTIST	=> 4, DRAG_ALBUM	=> 5,
 DRAG_FILTER	=> 6, DRAG_MARKUP	=> 7,

};

sub _ ($) {$_[0]}	#dummy translation functions
sub __ { sprintf( ($_[2]>1 ? $_[0] : $_[1]), $_[2]); }
sub __x { my ($s,%h)=@_; $s=~s/{(\w+)}/$h{$1}/g; $s; }
BEGIN
{no warnings 'redefine';
 eval {require Locale::gettext};
 if ($@) { warn "Locale::gettext not found -> no translations\n"; }
 elsif ($Locale::gettext::VERSION<1.04) { warn "Needs at least version 1.04 of Locale::gettext, v$Locale::gettext::VERSION found -> no translations\n" }
 else
 {	my $localedir=$DATADIR;
	$localedir= $FindBin::RealBin.SLASH.'..'.SLASH.'share' unless -d $localedir.SLASH.'locale';
	my $d= eval { Locale::gettext->domain('gmusicbrowser'); };
	if ($@) { warn "Locale::gettext error : $@\n -> no translations\n"; }
	else
	{	$d->dir( $localedir.SLASH.'locale' );
		*_=sub ($) { $d->get($_[0]); };
		*__=sub { sprintf $d->nget(@_),$_[2]; };
	}
 }
}
our %Alias_ext;	#define alternate file extensions (ie: .ogg files treated as .oga files)
INIT {%Alias_ext=(ogg=> 'oga', m4b=>'m4a');} #needs to be in a INIT block because used in a INIT block in gmusicbrowser_tags.pm

BEGIN{
require 'gmusicbrowser_songs.pm';
require 'gmusicbrowser_tags.pm';
require 'gmusicbrowser_layout.pm';
require 'gmusicbrowser_list.pm';
require 'simple_http.pm';
}

our $Gtk2TrayIcon;
BEGIN
{ eval { require Gtk2::TrayIcon; $Gtk2TrayIcon=1; };
  if ($@) { warn "Gtk2::TrayIcon not found -> tray icon won't be available\n"; }
}


our $debug;
our %CmdLine;
our ($HomeDir,$SaveFile,$FIFOFile);

our $QSLASH;	#quoted SLASH for use in regex
#FIXME use :		use constant QSLASH => quotemeta SLASH;
#  ???			and ${\QSLASH} instead of $QSLASH

########## cmdline
BEGIN
{ our $QSLASH=quotemeta SLASH;
  $HomeDir=Glib::get_user_config_dir.SLASH.PROGRAM_NAME.SLASH;
  unless (-d $HomeDir)
  {	my $old=Glib::get_home_dir.SLASH.'.'.PROGRAM_NAME.SLASH;
	if (-d $old)
	{	warn "Using folder $old for configuration, you could move it to $HomeDir to conform to the XDG Base Directory Specification\n";
		$HomeDir=$old;
	}
	else
	{	warn "Creating folder $HomeDir\n";
		my $current='';
		for my $dir (split /$QSLASH/o,$HomeDir)
		{	$current.=SLASH.$dir;
			next if -d $current;
			die "Can't create folder $HomeDir : $!\n" unless mkdir $current;
		}
	}
  }

  $SaveFile=(-d $HomeDir)
	?  $HomeDir.'gmbrc'
	: rel2abs('gmbrc');
  $FIFOFile=(-d $HomeDir && $^O ne 'MSWin32')
	?  $HomeDir.'gmusicbrowser.fifo'
	: undef;

my $help=PROGRAM_NAME.' v'.VERSIONSTRING." (c)2005-2009 Quentin Sculo
options :
-c	: don't check for updated/deleted songs on startup
-s	: don't scan folders for songs on startup
-demo	: don't check if current song has been updated/deleted
-ro	: prevent modifying/renaming/deleting song files
-rotags	: prevent modifying tags of music files
-play	: start playing on startup
-nodbus	: do not use DBus
-gst	: use gstreamer
-nogst  : do not use gstreamer
-server	: send playing song to connected icecast clent
-port N : listen for connection on port N in icecast server mode
-C FILE	: use FILE as configuration file (instead of $SaveFile)
-F FIFO : use FIFO as named pipe to receive commans (instead of $FIFOFile)
-nofifo : do not create/use named pipe $FIFOFile
-debug	: print lots of mostly useless informations
-layout NAME		: Use layout NAME for player window
+plugin NAME		: Enable plugin NAME
-plugin NAME		: Disable plugin NAME
-searchpath FOLDER	: Additional FOLDER to look for plugins and layouts
-use-gnome-session 	: Use gnome libraries to save tags/settings on session logout


Command options, all following arguments constitute CMD :
-cmd CMD...		: launch gmusicbrowser if not already running, and execute command CMD
-remotecmd CMD...	: execute command CMD in a running gmusicbrowser
-launch_or_cmd CMD...	: launch gmusicbrowser if not already running OR execute command CMD in a running gmusicbrowser
(-cmd, -remotecmd and -launch_or_cmd must be the last option, all following arguments are put in CMD)

Options to change what is done with files/folders passed as arguments (done in running gmusicbrowser if there is one) :
-playlist		: Set them as playlist (default)
-enqueue		: Enqueue them
-addplaylist		: Add them to the playlist
-insertplaylist		: Insert them in the playlist after current song
-add			: Add them to the library

-tagedit FOLDER_OR_FILE ... : Edittag mode
-listcmd	: list the available fifo commands and exit
-listlayout	: list the available layouts and exit
";
  unshift @ARGV,'-tagedit' if $0=~m/tagedit/;
  $CmdLine{gst}=0;
  my @files; my $filescmd;
   while (defined (my $arg=shift))
   {	if   ($arg eq '-c')		{$CmdLine{nocheck}=1}
	elsif($arg eq '-s')		{$CmdLine{noscan}=1}
	elsif($arg eq '-demo')		{$CmdLine{demo}=1}
#	elsif($arg eq '-empty')		{$CmdLine{empty}=1}
	elsif($arg eq '-play')		{$CmdLine{play}=1}
	elsif($arg eq '-hide')		{$CmdLine{hide}=1}
	elsif($arg eq '-server')	{$CmdLine{server}=1}
	elsif($arg eq '-nodbus')	{$CmdLine{noDBus}=1}
	elsif($arg eq '-nogst')		{$CmdLine{gst}=0}
	elsif($arg eq '-gst')		{$CmdLine{gst}=1}
	elsif($arg eq '-ro')		{$CmdLine{ro}=$CmdLine{rotags}=1}
	elsif($arg eq '-rotags')	{$CmdLine{rotags}=1}
	elsif($arg eq '-port')		{$CmdLine{port}=shift if $ARGV[0]}
	elsif($arg eq '-debug')		{$debug=1}
	elsif($arg eq '-nofifo')	{$FIFOFile=undef}
	elsif($arg eq '-C')		{$CmdLine{savefile}=1; $SaveFile=rel2abs(shift) if $ARGV[0]}
	elsif($arg eq '-F')		{$FIFOFile=rel2abs(shift) if $ARGV[0]}
	elsif($arg eq '-layout')	{$CmdLine{layout}=shift if $ARGV[0]}
	elsif($arg eq '-searchpath')	{ push @{ $CmdLine{searchpath} },shift if $ARGV[0]}
	elsif($arg=~m/^([+-])plugin$/)	{ $CmdLine{plugins}{shift @ARGV}=($1 eq '+') if $ARGV[0]}
	elsif($arg eq '-geometry')	{ $CmdLine{geometry}=shift if $ARGV[0]; }
	elsif($arg eq '-tagedit')	{ $CmdLine{tagedit}=1;last; }
	elsif($arg eq '-listcmd')	{ $CmdLine{cmdlist}=1;last; }
	elsif($arg eq '-listlayout')	{ $CmdLine{layoutlist}=1;last; }
	elsif($arg eq '-cmd')		{ RunRemoteCommand(@ARGV); $CmdLine{runcmd}="@ARGV"; last; }
	elsif($arg eq '-remotecmd')	{ RunRemoteCommand(@ARGV); exit; }
	elsif($arg eq '-launch_or_cmd')	{ RunRemoteCommand(@ARGV); last; }
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
  if (@files)
  {	for my $f (@files)
	{ unless ($f=~m#^http://#)
	  {	$f=rel2abs($f);
		$f=~s/([^A-Za-z0-9])/sprintf('%%%02X', ord($1))/seg; #FIXME use url_escapeall, but not yet defined
	  }
	}
	$filescmd ||= 'OpenFiles';
	my $cmd="$filescmd(@files)";
	RunRemoteCommand($cmd);
	$CmdLine{runcmd}=$cmd;
  }

  sub RunRemoteCommand
  {	warn "Sending command @_\n" if $debug;
	if (defined $FIFOFile && -p $FIFOFile)
	{	sysopen my$fifofh,$FIFOFile, O_NONBLOCK | O_WRONLY;
		print $fifofh "@_" and exit; #exit if ok
		close $fifofh;
		#exit;
	}
  }
  unless ($CmdLine{noDBus}) { eval {require 'gmusicbrowser_dbus.pm'} || warn "Error loading Net::DBus :\n$@ => controling gmusicbrowser through DBus won't be possible.\n\n"; }

}

##########

#our $re_spaces_unlessinbrackets=qr/([^( ]+(?:\(.*?\))?)(?: +|$)/; #breaks "widget1(options with spaces) widget2" in "widget1(options with spaces)" and "widget2" #replaced by ExtractNameAndOptions

our $re_artist; #regular expression used to split artist name into multiple artists, defined at init by the option ArtistSplit, may not be changed afterward because it is used with the /o option (faster)

my ($browsercmd,$opendircmd);

our %QActions=		#icon		#short		#long description
(	''	=> [ 0, undef,		_"normal",	_"normal play when queue empty"],
	autofill=> [ 1, 'gtk-refresh',	_"autofill",	_"autofill queue" ],
	'wait'	=> [ 2, 'gmb-wait',	_"wait for more",_"wait for more when queue empty"],
	stop	=> [ 3, 'gtk-media-stop',_"stop",	_"stop when queue empty"],
	quit	=> [ 4, 'gtk-quit',	_"quit",	_"quit when queue empty"],
	turnoff => [ 5, 'gmb-turnoff',	_"turn off",	_"turn off computer when queue empty"],
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
		  DRAG_STRING,	undef, #will use DRAG_USTRING
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
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('artists',$_),@_)->filter; SortList($l); @$l; },
		}],
	[Album  => {	DRAG_USTRING,	sub { (@_<10)? join("\n",@{Songs::Gid_to_Display('album',\@_)}) : __("%d album","%d albums",scalar@_) },
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map Songs::MakeFilterFromGID('album',$_),@_)->filter; SortList($l); @$l; },
		}],
	[Filter =>
		{	DRAG_USTRING,	sub {Filter->new($_[0])->explain},
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_ID,	sub { my $l=Filter->new($_[0])->filter; SortList($l); @$l; },
			#DRAG_FILE,	sub { my $l=Filter->new($_[0])->filter; Songs::Map('uri',$l); }, #good idea ?
		}
	],
);
our %DRAGTYPES;
$DRAGTYPES{$DRAGTYPES[$_][0]}=$_ for DRAG_FILE,DRAG_USTRING,DRAG_STRING,DRAG_ID,DRAG_ARTIST,DRAG_ALBUM,DRAG_FILTER,DRAG_MARKUP;

our @submenuRemove=
(	{ label => sub {$_[0]{mode} eq 'Q' ? _"Remove from queue" : $_[0]{mode} eq 'A' ? _"Remove from playlist" : _"Remove from list"},	code => sub { $_[0]{self}->RemoveSelected; }, mode => 'BLQA'},
	{ label => _"Remove from library",	code => sub { SongsRemove($_[0]{IDs}); }, },
	{ label => _"Remove from disk",		code => sub { DeleteFiles($_[0]{IDs}); },	test => sub {!$CmdLine{ro}},	stockicon => 'gtk-delete' },
);
#modes : S:Search, B:Browser, Q:Queue, L:List, P:Playing song in the player window, F:Filter Panels (submenu "x songs")
our @SongCMenu=
(	{ label => _"Song Properties",	code => sub { DialogSongProp (@{ $_[0]{IDs} }); },	onlyone => 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Songs Properties",	code => sub { DialogSongsProp(@{ $_[0]{IDs} }); },	onlymany=> 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Play Only Selected",code => sub { Select(song => 'first', play => 1, staticlist => $_[0]{IDs} ); },
		onlymany => 'IDs', 	stockicon => 'gtk-media-play'},
	{ label => _"Play Only Displayed",code => sub { Select(song => 'first', play => 1, staticlist => \@{$_[0]{listIDs}} ); },
		test => sub { @{$_[0]{IDs}}<2 }, notmode => 'A',	onlymany => 'listIDs',	stockicon => 'gtk-media-play' },
	{ label => _"Enqueue Selected",	code => sub { Enqueue(@{ $_[0]{IDs} }); },
		notempty => 'IDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Enqueue Displayed",	code => sub { Enqueue(@{ $_[0]{listIDs} }); },
		empty => 'IDs',	notempty=> 'listIDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Add to list",	submenu => \&AddToListMenu,	notempty => 'IDs' },
	{ label => _"Edit Labels",	submenu => \&LabelEditMenu,	notempty => 'IDs' },
	{ label => _"Edit Rating",	submenu => \&Stars::createmenu,	notempty => 'IDs' },
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
);
our @cMenuAA=
(	{ label => _"Lock",	code => sub { ToggleLock($_[0]{field}); }, check => sub { $::TogLock && $::TogLock eq $_[0]{field}}, mode => 'P' },
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

my %htmlelem= #FIXME maybe should use a module with a complete list
(	amp => '&', 'lt' => '<', 'gt' => '>', quot => '"', apos => "'",
	raquo => '»', copy => '©', middot => '·',
	acirc => 'à', eacute => 'é', egrave => 'è', ecirc => 'ê',
);
sub decode_html
{	local $_=$_[0];
	s/&#(\d{2,4});/chr($1)/eg;
	s/&([a-z]+);/$htmlelem{$1}||'?'/eg;
	return $_;
}

sub PangoEsc	# escape special chars for pango ( & < > ) #replaced by Glib::Markup::escape_text if available
{	local $_=$_[0];
	return '' unless defined;
	s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g;
	s/"/&quot;/g; s/'/&apos;/g; # doesn't seem to be needed
	return $_;
}

sub CleanupFileName
{	local $_=$_[0];
	s#[[:cntrl:]/:><\*\?\"\\]##g;
	s#^[- ]+##g;
	s/ +$//g;
	return $_;
}
sub CleanupDirName
{	local $_=$_[0];
	if ($^O eq 'MSWin32')	{ s#[[:cntrl:]/:><\*\?\"]##g; }
	else			{ s#[[:cntrl:]:><\*\?\"\\]##g; }
	s#^[- ]+##g;
	s/ +$//g;
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
	until ($nb==grep m/^$folder(?:$QSLASH|$)/, @folders)
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
	while (m#\G\s*([^= ]+)=#gc)
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
	$string=~s#\\n#\n#g;
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
sub MakeReplaceTable
{	my $fields=$_[0];
	my $table=Gtk2::Table->new (4, 2, FALSE);
	my $row=0; my $col=0;
	for my $tag (map '%'.$_, split //,$fields)
	{	for my $text ( $tag, Songs::FieldName($ReplaceFields{$tag}) )
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
{	my $fields=$_[0];
	my $text=join "\n",map '%'.$_.' : '.Songs::FieldName($ReplaceFields{'%'.$_}), split //,$fields;
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
sub ConvertTime	# convert date pattern into nb of seconds
{	my $pat=$_[0];
	if ($pat=~m/(\d\d\d\d)-(\d\d?)-(\d\d?)/) { $pat=mktime(0,0,0,$3,$2-1,$1-1900); }
	elsif ($pat=~m/(\d+(?:\.\d+)?)\s*([smhdwMy])/){ $pat=time-$1*$DATEUNITS{$2}[0];   }
	else {$pat=~m/(\d+)/; $pat=$1||0}
	return $pat;
}
sub ConvertSize
{	my $pat=$_[0];
	if ($pat=~m/^(\d+)([bkm])$/) { $pat=$1*$::SIZEUNITS{$2}[0] }
	return $pat;
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
our ($SongID,$Recent,$RecentPos,$Queue); our $QueueAction='';
our ($Position,$ChangedID,$ChangedPos,@NextSongs,$NextFileToPlay);
our ($MainWindow,$FullscreenWindow); my $OptionsDialog;
my $TrayIcon;
my %Editing; #used to keep track of opened song properties dialog and lyrics dialog
our $PlayTime;
our ($StartTime,$StartedAt,$PlayingID,$PlayedPartial);
our $CurrentDir=$ENV{PWD};
#$ENV{PULSE_PROP_media.role}='music'; # pulseaudio hint. could set other pulseaudio properties, FIXME doesn't seem to reach pulseaudio

our $LEvent;
our (%ToDo,%TimeOut);
my %EventWatchers;#for Save Vol Time Queue Lock Repeat Sort Filter Pos CurSong Playing SavedWRandoms SavedSorts SavedFilters SavedLists Icons Widgets connections
# also used for SearchText_ SelectedID_ followed by group id
# Picture_#mainfield#

my (%Watched,%WatchedFilt);
my ($IdleLoop,@ToCheck,@ToReRead,@ToAdd_Files,@ToAdd_IDsBuffer,@ToScan,%FollowedDirs,$CoverCandidates);
our ($LengthEstimated);
our %Progress; my $ProgressWindowComing;
my $Lengthcheck_max=0; my ($ScanProgress_cb,$CheckProgress_cb,$ProgressNBSongs,$ProgressNBFolders);
my %Plugins;
my $ScanRegex;

#Default values
our %Options=
(	Layout		=> 'Lists, Library & Context',
	LayoutT		=> 'info',
	LayoutB		=> 'Browser',
	LayoutF		=> 'default fullscreen',
	LayoutS		=> 'Search',
	IconTheme	=> '',
	MaxAutoFill	=> 5,
	Repeat		=> 1,
	Sort		=> 'shuffle',		#default sort order
	Sort_LastOrdered=> 'path file',
	Sort_LastSR	=> 'shuffle',
	WindowSizes	=>
	{	Rename		=> '300x180',
		MassRename	=> '650x550',
		MassTag		=> '520x560',
		AdvTag		=> '538x503',
		SongInfo	=> '420x482',
		EditSort	=> '600x320',
		EditFilter	=> '600x260',
		EditWRandom	=> '600x450',
	},
	Sessions	=> '',
	StartCheck	=> 0,	#check if songs have changed on startup
	StartScan	=> 0,	#scan @LibraryPath on startup for new songs
	Labels		=> [_("favorite"),_("bootleg"),_("broken"),_("bonus tracks"),_("interview"),_("another example")],
	FilenameSchema	=> ['%a - %l - %n - %t','%l - %n - %t','%n-%t','%d%n-%t'],
	FolderSchema	=> ['%A/%l','%A','%A/%Y-%l','%A - %l'],
	PlayedPercent	=> .85,	#percent of a song played to increase play count
	DefaultRating	=> 50,
#	Device		=> 'default',
#	amixerSMC	=> 'PCM',
#	gst_sink	=> 'alsa',
	gst_volume	=> 100,
	gst_use_equalizer=>0,
	gst_equalizer	=> '0:0:0:0:0:0:0:0:0:0',
	gst_rg_limiter	=> 1,
	gst_rg_preamp	=> 6,
	gst_rg_fallback	=> 0,
	gst_rg_songmenu => 1,
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
	TAG_auto_check_current	=> 1,
	Simplehttp_CacheSize	=> 200*1024,
	CustomKeyBindings	=> {},
	ArtistSplit		=> ' & |, |;',
	VolumeStep		=> 10,

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

our $GlobalKeyBindings='Insert OpenSearch c-q EnqueueSelected p PlayPause c OpenContext q OpenQueue ca-f ToggleFullscreenLayout';
%GlobalBoundKeys=%{ make_keybindingshash($GlobalKeyBindings) };


sub make_keybindingshash
{	my $keybindings=$_[0];
	my @list= ref $keybindings ? %$keybindings : ExtractNameAndOptions($keybindings);
	my %h;
	while (@list>1)
	{	my $key=shift @list;
		my $cmd=shift @list;
		my $mod='';
		$mod=$1 if $key=~s/^(c?a?w?s?-)//;
		my @keys=($key);
		@keys=(lc$key,uc$key) if $key=~m/^[A-Za-z]$/;
		$h{$mod.$_}=$cmd for @keys;
	}
	return \%h;
}
sub keybinding_longname
{	my $key=$_[0];
	return $key unless $key=~s/^(c?a?w?s?)-//;
	my $mod=$1;
	my %h=(c => _"Ctrl", a => _"Alt", w => _"Win", s => _"Shift");
	my $name=join '',map $h{$_}, split //,$mod;
	return $name.'-'.$key;
}

our ($NBVolIcons,$NBQueueIcons); my $TrayIconFile;
my $icon_factory;

my %IconsFallbacks=
(	'gmb-queue-window' => 'gmb-queue',
	'gmb-random-album' => 'gmb-random',
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
	{	my $dir= $HomeDir.SLASH.'icons'.SLASH.$theme;
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

	$TrayIconFile=delete $icons{trayicon} || PIXPATH.'trayicon.png';
	$TrayIcon->child->child->set_from_file($TrayIconFile) if $TrayIcon;
	Gtk2::Window->set_default_icon_from_file( delete $icons{gmusicbrowser} || PIXPATH.'gmusicbrowser.png' );

	$NBVolIcons=0;
	$NBVolIcons++ while $icons{'gmb-vol'.$NBVolIcons};
	$NBQueueIcons=0;
	$NBQueueIcons++ while $icons{'gmb-queue'.$NBQueueIcons};

	$icon_factory->remove_default if $icon_factory;
	$icon_factory=Gtk2::IconFactory->new;
	$icon_factory->add_default;
	for my $stock_id (keys %icons,keys %IconsFallbacks)
	{	my %h= ( stock_id => $stock_id );
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
		{	$icon_set=$icon_factory->lookup($fallback);
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
	NextArtist	=> [sub {NextDiff('artist_first')},	_"Next Artist",],
	NextSong	=> [\&NextSong,				_"Next Song"],
	PrevSong	=> [\&PrevSong,				_"Previous Song"],
	PlayPause	=> [\&PlayPause,			_"Play/Pause"],
	Forward		=> [\&Forward,				_"Forward",_"Number of seconds",qr/^\d+$/],
	Rewind		=> [\&Rewind,				_"Rewind",_"Number of seconds",qr/^\d+$/],
	Seek		=> [sub {SkipTo($_[1])},		_"Seek",_"Number of seconds",qr/^\d+$/],
	Stop		=> [\&Stop,				_"Stop"],
	Browser		=> [\&OpenBrowser,			_"Open Browser"],
	OpenQueue	=> [\&EditQueue,			_"Open Queue window"],
	OpenSearch	=> [sub { Layout::Window->new($Options{LayoutS}, uniqueid=>'Search'); },	_"Open Search window"],
	OpenContext	=> [\&ContextWindow,			_"Open Context window"],
	OpenCustom	=> [sub { Layout::Window->new($_[1]); },	_"Open Custom window",_"Name of layout", sub { TextCombo->new( Layout::get_layout_list() ); }],
	PopupCustom	=> [sub { PopupLayout($_[1],$_[0]); },		_"Popup Custom window",_"Name of layout", sub { TextCombo::Tree->new( Layout::get_layout_list() ); }],
	CloseWindow	=> [sub { $_[0]->get_toplevel->close_window if $_[0];}, _"Close Window"],
	SetPlayerLayout => [sub { SetOption(Layout=>$_[1]); CreateMainWindow(); },_"Set player window layout",_"Name of layout", sub {  TextCombo::Tree->new( Layout::get_layout_list('G') ); }, ],
	OpenPref	=> [\&PrefDialog,			_"Open Preference window"],
	OpenSongProp	=> [sub { DialogSongProp($SongID) if defined $SongID }, _"Edit Current Song Properties"],
	EditSelectedSongsProperties => [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DialogSongsProp(@IDs) if @IDs; },		_"Edit selected song properties"],
	ShowHide	=> [\&ShowHide,				_"Show/Hide"],
	Quit		=> [\&Quit,				_"Quit"],
	Save		=> [\&SaveTags,				_"Save Tags/Options"],
	ChangeDisplay	=> [\&ChangeDisplay,			_"Change Display",_"Display (:1 or host:0 for example)",qr/:\d/],
	GoToCurrentSong => [\&Layout::GoToCurrentSong,		_"Select current song"],
	DeleteSelected	=> [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DeleteFiles(\@IDs); },		_"Delete Selected Songs"],
	EnqueueSelected => [\&Layout::EnqueueSelected,		_"Enqueue Selected Songs"],
	EnqueueArtist	=> [sub {EnqueueSame('artist',$SongID)},_"Enqueue Songs from Current Artist"], # or use field 'artists' or 'first_artist' ?
	EnqueueAlbum	=> [sub {EnqueueSame('album',$SongID)},	_"Enqueue Songs from Current Album"],
	EnqueueAction	=> [sub {EnqueueAction($_[1])},		_"Enqueue Action", _"Queue mode" ,sub { TextCombo::Tree->new({map {$_ => $QActions{$_}[2]} sort keys %QActions}) }],
	ClearQueue	=> [\&::ClearQueue,			_"Clear queue"],
	IncVolume	=> [sub {ChangeVol('up')},		_"Increase Volume"],
	DecVolume	=> [sub {ChangeVol('down')},		_"Decrease Volume"],
	TogMute		=> [sub {ChangeVol('mute')},		_"Mute/Unmute"],
	RunSysCmd	=> [\&run_system_cmd,			_"Run system command",_"Shell command\n(some variables such as %f (current song filename) or %F (list of selected songs filenames) are available)",qr/./],
	RunPerlCode	=> [sub {eval $_[1]},			_"Run perl code",_"perl code",qr/./],
	TogArtistLock	=> [sub {ToggleLock('first_artist')},	_"Toggle Artist Lock"],
	TogAlbumLock	=> [sub {ToggleLock('album')},		_"Toggle Album Lock"],
	TogSongLock	=> [sub {ToggleLock('fullfilename')},	_"Toggle Song Lock"],
	SetSongRating	=> [sub {return unless defined $SongID && $_[1]=~m/^\d*$/; Songs::Set($SongID, rating=> $_[1]); },	_"Set Current Song Rating", _"Rating between 0 and 100, or empty for default", qr/^\d*$/],
	ToggleFullscreen=> [\&Layout::ToggleFullscreen,		_"Toggle fullscreen mode"],
	ToggleFullscreenLayout=> [\&ToggleFullscreenLayout, _"Toggle the fullscreen layout"],
	OpenFiles	=> [\&OpenFiles, _"Play a list of files", _"url-encoded list of files",0],
	AddFilesToPlaylist=> [sub { DoActionForList('addplay',Uris_to_IDs($_[1])); }, _"Add a list of files/folders to the playlist", _"url-encoded list of files/folders",0],
	InsertFilesInPlaylist=> [sub { DoActionForList('insertplay',Uris_to_IDs($_[1])); }, _"Insert a list of files/folders at the start of the playlist", _"url-encoded list of files/folders",0],
	EnqueueFiles	=> [sub { DoActionForList('queue',Uris_to_IDs($_[1])); }, _"Enqueue a list of files/folders", _"url-encoded list of files/folders",0],
	AddToLibrary	=> [sub { AddPath(1,split / /,$_[1]); }, _"Add files/folders to library", _"url-encoded list of files/folders",0],
	SetFocusOn	=> [sub { my ($w,$name)=@_;return unless $w; $w=find_ancestor($w,'Layout');$w->SetFocusOn($name) if $w;},_"Set focus on a layout widget", _"Widget name",0],
	ShowHideWidget	=> [sub { my ($w,$name)=@_;return unless $w; $w=find_ancestor($w,'Layout');$w->ShowHide(split / +/,$name,2) if $w;},_"Show/Hide layout widget(s)", _"|-separated list of widget names",0],
	PopupTrayTip	=> [sub {ShowTraytip($_[1])}, _"Popup Traytip",_"Number of milliseconds",qr/^\d*$/ ],
	SetSongLabel	=> [sub{ Songs::Set($SongID,'+label' => $_[1]); }, _"Add a label to the current song", _"Label",qr/./],
	UnsetSongLabel	=> [sub{ Songs::Set($SongID,'-label' => $_[1]); }, _"Remove a label from the current song", _"Label",qr/./],
	ToggleSongLabel	=> [sub{ ToggleLabel($_[1],$::SongID); }, _"Toggle a label of the current song", _"Label",qr/./],
	PlayListed	=> [sub{ my $songlist=GetSonglist($_[0]) or return; Select(song => 'first', play => 1, staticlist => $songlist->{array} ); }, _"Play listed songs"],
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

sub run_system_cmd
{	my $syscmd=$_[1];
	my @cmd= split_with_quotes($syscmd);
	return unless @cmd;
	if ($syscmd=~m/%F/)
	{	my @files;
		if ($_[0] and my $songlist=GetSonglist($_[0])) { @files=map Songs::GetFullFilename($_), $songlist->GetSelectedIDs; }
		unless (@files) { warn "Not executing '$syscmd' because no song is selected in the current window\n"; return }
		@cmd=map { $_ ne '%F' ? $_ : @files } @cmd ;
	}
	if (defined $SongID) { $_=ReplaceFields($SongID,$_) for @cmd; }
	forksystem(@cmd);
}

sub forksystem
{	use POSIX ':sys_wait_h';	#for WNOHANG in waitpid
	my $pid=fork;
	if ($pid==0) #child
	{	exec @_;
		exit;
	}
	#waitpid $pid,0 if $pid;# && kill(0,$pid);
	while (waitpid(-1, WNOHANG)>0) {}	#reap dead children
}


if ($CmdLine{cmdlist})
{	print "Available commands (for fifo or layouts) :\n";
	my ($max)= sort {$b<=>$a} map length, keys %Command;
	for my $cmd (sort keys %Command)
	{	my $tip=$Command{$cmd}[2] || '';
		if ($tip) { $tip=~s/\n.*//s; $tip=" (argument : $tip)"; }
		printf "%-${max}s : %s %s\n", $cmd, $Command{$cmd}[1], $tip;
	}
	exit;
}
my $fifofh;
if (defined $FIFOFile)
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
$PlayPacks{$_}= $_->init for keys %PlayPacks;

LoadPlugins();
ReadSavedTags();

%CustomBoundKeys= %{ make_keybindingshash($Options{CustomKeyBindings}) };

$Options{version}=VERSION;
LoadIcons();

{	my $pp=$Options{AudioOut};
	$pp= $Options{use_GST_for_server} ? 'Play_GST_server' : 'Play_Server' if $CmdLine{server};
	$pp='Play_GST' if $CmdLine{gst};
	for my $p ($Play_package, qw/Play_GST Play_123 Play_mplayer Play_GST_server Play_Server/)
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

our $Tooltips=Gtk2::Tooltips->new;
CreateMainWindow( $CmdLine{layout}||$Options{Layout} );
&ShowHide if $CmdLine{hide};
SkipTo($PlayTime) if $PlayTime; #done only now because of gstreamer

CreateTrayIcon();

run_command(undef,$CmdLine{runcmd}) if $CmdLine{runcmd};

#--------------------------------------------------------------
Gtk2->main;
exit;

sub Edittag_mode
{	my @dirs=@_;
	$_=rel2abs($_) for @dirs;
	IdleScan(@dirs);
	IdleDo('9_SkipLength',undef,sub {@$LengthEstimated=()});
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
	my $hbox= $vertical ? Gtk2::VBox->new : Gtk2::HBox->new;
	while (@list)
	{	my $w=shift @list;
		next unless defined $w;
		my $exp=FALSE;
		unless (ref $w)
		{	$exp=$w=~m/_/;
			$end=1 if $w=~m/-/;
			$pad=$1 if $w=~m/(\d+)/;
			$w=shift @list;
			next unless $w;
		}
		if (ref $w eq 'ARRAY')
		{	$w=HVpack(!$vertical,@$w);
		}
		if ($end)	{$hbox->pack_end  ($w,$exp,$exp,$pad);}
		else		{$hbox->pack_start($w,$exp,$exp,$pad);}
	}
	return $hbox;
}

sub Hpack { HVpack(0,@_); }
sub Vpack { HVpack(1,@_); }

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

sub GetGenresList	#FIXME inline it or rename it
{	return Songs::ListAll('genre');
}
sub SortedLabels	#FIXME inline it or rename it
{	return Songs::ListAll('label');
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
			if (--$sec) {$dialog->set_markup(::PangoEsc(_"About to turn off the computer in :"."\n".__("%d second","%d seconds",$sec)))}
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
	$Options{SavedPlayTime}= $PlayTime||0 if $Options{RememberPlayTime};
	&Stop if defined $TogPlay;
	@ToScan=@ToAdd_Files=();
	SaveTags();
	unlink $FIFOFile if defined $FIFOFile;
	Gtk2->main_quit;
	exec $Options{Shutdown_cmd} if $turnoff && $Options{Shutdown_cmd};
	exit;
}

sub CmdFromFIFO
{	while (my $cmd=<$fifofh>)
	{	chomp $cmd;
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
{	for my $w (Gtk2::Window->list_toplevels)
	{	return $w if $w->get_focus;
	}
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
		open my$fh,'<',$file or do {warn "error opening $file : $!\n";next};
		while (my $line=<$fh>)
		{	if ($line=~m/^=gmbplugin (\D\w+)/)
			{	my $id=$1;
				my @lines;
				while ($line=<$fh>)
				{	last if $line=~m/^=cut/;
					$line=~s/[\n\r]+$//;
					$line=_($line) if $line;
					push @lines,$line;
				}
				next unless @lines>1;
				my $name=shift @lines;
				my $longname=shift @lines;
				my $desc=join "\n",@lines;
				$found++;
				last if $Plugins{$id};
				warn "found plugin $id ($name)\n" if $::debug;
				$Plugins{$id}=
				{	file	=> $file,
					name	=> $name,
					longname=> $longname,
					desc	=> $desc,
				};
				last;
			}
			elsif ($line=~m/^\s*[^#\n\r]/) {last}
		}
		close $fh;
		warn "No plugin found in $file, maybe it uses an old format\n" unless $found;
	}
}
sub PluginsInit
{	my $p=delete $CmdLine{plugins};
	$Options{'PLUGIN_'.$_}=$p->{$_} for keys %$p;
	ActivatePlugin($_,'init') for grep $Options{'PLUGIN_'.$_}, sort keys %Plugins;
}
sub ActivatePlugin
{	my ($plugin,$startup)=@_;
	my $ref=$Plugins{$plugin};
	if ( $ref->{loaded} || do $ref->{file} )
	{	$ref->{loaded}=1;
		delete $ref->{error};
		my $package='GMB::Plugin::'.$plugin;
		if ($startup && $startup eq 'init')
		{	if ($package->can('Init'))
			{	$package->Init if $package->can('Init');
				warn "Plugin $plugin initialized.\n" if $debug;
			}
		}
		else
		{	$package->Start($startup) if $package->can('Start');
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
		_"Played Today"		=> 'lastplay:>:1d',
		_"Added Today"		=> 'added:>:1d',
		_"played>4"		=> 'playcount:>:4',
		_"not bootleg"		=> '-label:~:bootleg',
	};
	$_=Filter->new($_) for values %{ $Options{SavedFilters} };

	if (-r $DATADIR.SLASH.'gmbrc.default')
	{	open my($fh),'<:utf8', $DATADIR.SLASH.'gmbrc.default';
		my @lines=<$fh>;
		close $fh;
		chomp @lines;
		my $opt={};
		ReadRefFromLines(\@lines,$opt);
		%Options= ( %Options, %$opt );
	}

	$re_artist=qr/ & |, /;
	Post_Options_init();
}



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
	delete $Options{$_} for qw/Device 123options_mp3 123options_ogg 123options_flac test/; #cleanup old options
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
	$Options{Labels}=[ split "\x1D",$Options{Labels} ] unless ref $Options{Labels};	#for version <1.1.2
	$Options{ArtistSplit}||=' & |, |;';
	$re_artist=qr/$Options{ArtistSplit}/;

	Post_Options_init();

	my $oldID=-1;
	no warnings 'utf8'; # to prevent 'utf8 "\xE9" does not map to Unicode' type warnings about path and file which are stored as they are on the filesystem #FIXME find a better way to read lines containing both utf8 and unknown encoding
	my ($loadsong)=Songs::MakeLoadSub({},split / /,$Songs::OLD_FIELDS);
	my (%IDforAlbum,%IDforArtist);
	my @newIDs; SongArray::start_init();
	my @missing;
	while (<$fh>)
	{	chomp; last if $_ eq '';
		$oldID++;
		next if $_ eq ' ';	#deleted entry
		s#\\([n\\])#$1 eq "n" ? "\n" : "\\"#ge unless $oldversion<0.9603;
		my @song=split "\x1D",$_,-1;

		#FIXME PHASE1 do some checks
		#unless ($song[SONG_UPATH] && ($song[SONG_UFILE] || $song[SONG_UPATH]=~m#^http://#) && $song[SONG_ADDED])
		#{	warn "skipping invalid song entry : @song\n";
		#	next;
		#}
		my $album=$song[11]; my $artist=$song[10];
		$song[10]=~s/^<Unknown>$//;	#10=SONG_ARTIST
		$song[11]=~s/^<Unknown>.*//;	#11=SONG_ALBUM
		$song[12]=~s#/.*$##; 		##12=SONG_DISC
		#$song[13]=~s#/.*$##; 		##13=SONG_TRACK
		for ($song[0],$song[1]) { _utf8_off($_); $_=Songs::filename_escape($_) } # file and path
		my $ID= $newIDs[$oldID]= $loadsong->(@song);
		$IDforAlbum{$album}=$IDforArtist{$artist}=$ID;

		if (my $m=$song[24]) #FIXME PHASE1		#24=SONG_MISSINGSINCE
		{	if ($m=~m/^\d+$/) { push @missing,$ID;next}
			$song[24]=undef;
			if ($m eq 'l') {push @$LengthEstimated,$ID}
			elsif ($m eq 'R') {next}#push @Radio,$ID;next}
		}
		#elsif (!$song[2]) { push @ToAdd,$ID;next; } #FIXME PHASE1
		elsif (!$song[2]) { next; }	#2=SONG_MODIF

		push @$Library,$ID;
		#AA::Add($ID); #Fill %AA::Artist and %AA::Album
	}
	Songs::AddMissing(\@missing) if @missing;
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
			$Options{SavedFilters}{$key}=Filter->new($val);
		}
		elsif ($1 eq 'S')
		{	$Options{SavedSorts}{$key}=$val;
		}
		elsif ($1 eq 'R')
		{	$Options{SavedWRandoms}{$key}=$val;
		}
		elsif ($1 eq 'L')
		{	$Options{SavedLists}{$key}= SongArray->new_from_string($val);
		}
		elsif ($1 eq 'G')
		{	$Options{SavedSTGroupings}{$key}=$val;
		}
	}

	if (my $f=delete $Options{LastPlayFilter})
	{	if ($f=~s/^(filter|savedlist|list) //)
		{	$Options{LastPlayFilter}=
			$1 eq 'filter' ?	Filter->new($f) :
			$1 eq 'savedlist' ?	$f		:
			$1 eq 'list' ?		SongArray->new_from_string($f):
			undef;
		}
	}
	$Options{Labels}=delete $Options{Flags} if $oldversion<=0.9571;
	s/^r/random:/ || s/([0-9s]+)(i?)/($1 eq 's' ? 'shuffle' : Songs::FieldUpgrade($1)).($2 ? ':i' : '')/ge
		for values %{$Options{SavedSorts}},values %{$Options{SavedWRandoms}},$Options{Sort},$Options{AltSort};
	$Options{Sort_LastOrdered}=$Options{Sort_LastSR}= delete $Options{AltSort};
	if ($Options{Sort}=~m/random|shuffle/) { $Options{Sort_LastSR}=$Options{Sort} } else { $Options{Sort_LastOrdered}=$Options{Sort}||'path file'; }

	$Options{SongArray_Recent}= SongArray->new_from_string(delete $Options{RecentIDs});
	#FIXME PHASE1   Missing ?
	SongArray::updateIDs(\@newIDs);
	SongArray->new($Library);	#done after SongArray::updateIDs because doesn't use old IDs
	$Options{SongArray_Estimated}=SongArray->new($LengthEstimated);
}

sub ReadSavedTags	#load tags _and_ settings
{	if (-d $SaveFile) {$SaveFile.=SLASH.'gmbrc'}
	my $LoadFile=$SaveFile;
	if (!-e $LoadFile && !$CmdLine{savefile} && -r $HomeDir.'tags')
	{	$LoadFile=$HomeDir.'tags';	#import from v1.0.x
	}
	unless (-r $LoadFile)
	{	FirstTime();
		Post_ReadSavedTags();
		return;
	}
	setlocale(LC_NUMERIC, 'C');  # so that '.' is used as a decimal separator when converting numbers into strings
	warn "Reading saved tags in $LoadFile ...\n";
	open my($fh),'<:utf8',$LoadFile;

	# read first line to determine if old version, old version starts with a letter, new with blank or # (for comments) or [ (section name)
	my $firstline=<$fh>;
	seek $fh,0,SEEK_SET;
	if ($firstline=~m/^\w/) { ReadOldSavedTags($fh); }
	else
	{	my %lines;
		my $section;
		while (<$fh>)
		{	if (m/^\[([^]]+)\]/) {$section=$1; next}
			next unless $section;
			chomp;
			next unless length;
			push @{$lines{$section}},$_;
		}
		close $fh;
		# FIXME do someting clever if no [Options]
		SongArray::start_init(); #every SongArray read in Options will be updated to new IDs by SongArray::updateIDs later
		ReadRefFromLines($lines{Options},\%Options);
		my $oldversion=delete $Options{version} || VERSION;
		$Options{ArtistSplit}||=' & |, |;';
		$re_artist=qr/$Options{ArtistSplit}/;
		$Options{Labels}=[ split "\x1D",$Options{Labels} ] unless ref $Options{Labels};	#for version <1.1.2  #DELME in v1.1.3/4
		if ($oldversion<1.1003) { delete $Options{$_} for grep m/^Layout(?:LastSeen)?_/, keys %Options }	#for version <1.1.2  #DELME in v1.1.3/4
		if ($oldversion<1.1003) { $Options{WindowSizes}{$_}= join 'x',split / /,delete $Options{"WS$_"} for map m/^WS(.*)/, keys %Options; }	#for version <1.1.2  #DELME in v1.1.3/4

		Post_Options_init();

		if ($oldversion<1.1002) { for my $k (qw/Songs artist album/) {$lines{$k}[0]=~s/ /\t/g; s/\x1D/\t/g for @{$lines{$k}}; }}	#for version <1.1.2  #DELME in v1.1.3/4
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
				s#\\x([0-9a-fA-F]{2})#chr hex $1#eg for @vals;
				$sub->($key,@vals);
			}
		}
		SongArray::updateIDs(\@newIDs);
		my $filter=Filter->new('missing:e:0');
		$Library=[];	#dummy array to avoid a warning when filtering in the next line
		$Library= SongArray->new( $filter->filter([1..$Songs::LastID]) );
	}

	delete $Options{LastPlayFilter} unless $Options{RememberPlayFilter};
	@$Queue=() unless $Options{RememberQueue};
	if ($Options{RememberPlayFilter})
	{	$TogLock=$Options{Lock};
	}
	if ($Options{RememberPlaySong} && $Options{SavedSongID})
	 { $SongID= (delete $Options{SavedSongID})->[0]; }
	if ($Options{RememberPlaySong} && $Options{RememberPlayTime}) { $PlayTime=delete $Options{SavedPlayTime}; }
	$Options{LibraryPath}||=[];
	$Options{LibraryPath}= [ map url_escape($_), split "\x1D", $Options{LibraryPath}] unless ref $Options{LibraryPath}; #for versions <=1.1.1
	#&launchIdleLoop;

	setlocale(LC_NUMERIC, '');
	warn "Reading saved tags in $LoadFile ... done\n";
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
	$LengthEstimated=  $Options{SongArray_Estimated}	||= SongArray->new;
	$Options{LibraryPath}||=[];
}

sub SaveTags	#save tags _and_ settings
{	HasChanged('Save');
	warn "Writing tags in $SaveFile ...\n";
	setlocale(LC_NUMERIC, 'C');
	my $savedir=$SaveFile;
	$savedir=~s/([^$QSLASH]+)$//o;
	my $savefilename=$1;
	unless (-d $savedir) { warn "Creating folder $savedir\n"; mkdir $savedir or warn $!; }
	$Options{Lock}= $TogLock || '';
	$Options{SavedSongID}= SongArray->new([$SongID]) if $Options{RememberPlaySong} && defined $SongID;

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
		elsif	($lastseen->{$key}<$tooold)	{ delete $_->{$key} for $Options{Layout},$lastseen; }
	}

	my $error;
	open my($fh),'>:utf8',$SaveFile.'.new' or warn "Error opening '$SaveFile.new' for writing : $!";
	my $optionslines=SaveRefToLines(\%Options);
	print $fh "[Options]\n$$optionslines\n"  or $error||=$!;

	my ($savesub,$fields,$extrasub,$extra_subfields)=Songs::MakeSaveSub();
	print $fh "[Songs]\n".join("\t",@$fields)."\n"  or $error||=$!;
	for my $ID (@{ Songs::AllFilter('missing:<:'.($tooold||1)) })
	{	my @vals=$savesub->($ID);
		s#([\x00-\x1F\\])#sprintf "\\x%02x",ord $1#eg for @vals;
		my $line= join "\t", $ID, @vals;
		print $fh $line."\n"  or $error||=$!;
	}
	#save fields properties, like album pictures ...
	for my $field (sort keys %$extrasub)
	{	print $fh "\n[$field]\n$extra_subfields->{$field}\n"  or $error++;
		my $h= $extrasub->{$field}->();
		for my $key (sort keys %$h)
		{	my $vals= $h->{$key};
			s#([\x00-\x1F\\])#sprintf "\\x%02x",ord $1#eg for @$vals;
			my $line= join "\t", @$vals;
			next if $line=~m/^\t*$/;
			print $fh "$key\t$line\n"  or $error||=$!;
		}
	}
	close $fh  or $error||=$!;
	setlocale(LC_NUMERIC, '');
	if ($error)
	{	rename $SaveFile.'.new',$SaveFile.'.error';
		warn "Writing tags in $SaveFile ... error : $error\n";
		return;
	}
	if (-e $SaveFile) #keep some old files as backup
	{	{	last unless -e $SaveFile.'.bak';
			last unless (open my $file,'<',$SaveFile.'.bak');
			local $_; my $date;
			while (<$file>) { if (m/^SavedOn:\s*(\d+)/) {$date=$1;last} last if m/^\[(?!Options])/}
			close $file;
			last unless $date;
			$date=strftime('%Y%m%d',localtime($date));
			last if -e $SaveFile.'.bak.'.$date;
			rename $SaveFile.'.bak', $SaveFile.'.bak.'.$date;
			my @files=FileList(qr/^\Q$savefilename\E\.bak\.\d{8}$/, $savedir);
			last unless @files>5;
			splice @files,-5;	#keep the 5 newest versions
			unlink $_ for @files;
		}
		rename $SaveFile,$SaveFile.'.bak';
	}
	rename $SaveFile.'.new',$SaveFile;
	warn "Writing tags in $SaveFile ... done\n";
}

sub ReadRefFromLines	# convert a string written by SaveRefToLines to a hash/array # can only read a small subset of YAML
{	my ($lines,$return)=@_;
	my @todo;
	my ($ident,$ref)=(0,$return);
	my $parentval;
	for my $line (@$lines)
	{	next if $line=~m/^\s*(?:#|$)/;	#skip comment or empty line
		my ($d,$array,$key,$val)= $line=~m/^(\s*)(?:(-)|(?:(\S*|"[^"]*")\s*:))\s*(.*)$/;
		$d= length $d;
		if ($parentval)
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
		if ($val eq '')
		{	$parentval= $array ? \$ref->[@$ref] : \$ref->{$key};
		}
		else
		{	my $class;
			if ($val=~m/^!/)
			{	($class,$val)= $val=~m/^!([^ !]+)\s+(.*)$/;
				unless ($class) { warn "Unsupported value : '$val'\n"; next }
			}
			if ($val eq '~') {$val=undef}
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
	return @todo ? $todo[0] : $ref;
}


sub SaveRefToLines	#convert hash/array into a YAML string readable by ReadRefFromLines
{	my $ref=$_[0];
	my (@todo,$keylist);
	my $lines='';
	my $pre='';
	my $depth=0;
	if (ref $ref eq 'ARRAY'){ $keylist=0; }
	else			{ $keylist=[sort keys %$ref]; }
	while (1)
	{	my ($val,$next,$up);
		if (ref $ref eq 'ARRAY')
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
		{	if (ref $next ne 'ARRAY' && ref $next ne 'HASH')
			{	$val=$next->save_to_string;
				$lines.= ' !'.ref($next).' ';
			}
			else
			{	if (ref $next eq 'ARRAY' && !@$next)		{ $lines.=" []\n";next; }
				elsif (ref $next eq 'HASH' && !keys(%$next))	{ $lines.=" {}\n";next; }
				$lines.="\n";
				$depth++;
				$pre='  'x$depth;
				unshift @todo,$ref,$keylist;
				$ref=$next;
				if (ref $ref eq 'ARRAY'){ $keylist=0; }
				else			{ $keylist=[sort keys %$ref]; }
				next;
			}
		}
		elsif ($up)
		{	if ($depth)
			{	$depth--;
				$pre='  'x$depth;
				$ref=shift @todo;
				$keylist=shift @todo;
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
{	my ($win,$wkey)=@_;
	$win->set_role($wkey);
	$win->set_name($wkey);
	my $prevsize= $Options{WindowSizes}{$wkey};
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
	#return unless $sec=~m/^\d+(?:\.\d+)?$/;
	if (defined $PlayingID)
	{	$StartedAt=$sec unless (defined $PlayTime && $PlayingID==$SongID && $PlayedPartial && $sec<$PlayTime);	#don't re-set $::StartedAt if rewinding a song not fully(85%) played
		$Play_package->SkipTo($sec);
		my $wasplaying=$TogPlay;
		$TogPlay=1;
		HasChanged('Playing') unless $wasplaying;
	}
	else	{ Play($sec); }
}

sub PlayPause
{	if (defined $TogPlay)	{ Pause()}
	else			{ Play() }
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
{	my ($error,$critical)=@_;
	$error='Playing error : '.$error;
	warn $error."\n";
	return if $Options{IgnorePlayError} && !$critical;
	my $dialog = Gtk2::MessageDialog->new
		( undef, [qw/modal destroy-with-parent/],
		  'error','close','%s',
		  $error
		);
	if ($critical)
	{ my $button=Gtk2::Button->new('Save tag/settings now');
	  my $l=Gtk2::Label->new('Warning. This error may cause the program to crash, it could be a good time to save tags/settings now');
	  $l->set_line_wrap(1);
	  $button->signal_connect(clicked => sub
		  { $_[0]->hide;$l->set_text('tags/settings saved');SaveTags(); });
	  $dialog->vbox->pack_start($_,0,0,4) for $l,$button;
	}
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
	#$dialog->signal_connect( response => sub {$_[0]->destroy});
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
	&NextSong;
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

sub TimeString
{	return '--:--' unless defined $PlayTime;
	my $time=$PlayTime;
	my $l=Songs::Get($SongID,'length');
	my $f=($l<600)? '%01d:%02d' : '%02d:%02d';
	if ($_[0])
	{	$f='-'.$f;
		$time= $l-$time;
	}
	return sprintf $f,$time/60,$time%60;
}

sub ResetTime
{	undef $PlayTime;
	HasChanged('Time');
}

sub Played
{	return unless defined $PlayingID;
	HasChanged('Played');
	my $ID=$PlayingID;
	undef $PlayingID;
	warn "Played : $ID $StartTime $StartedAt $PlayTime\n" if $debug;
	#add song to recently played list
	unless (@$Recent && $Recent->[0]==$ID)
	{	$Recent->Unshift([$ID]);	#FIXME make sure it's not too slow, put in a idle ?
		$Recent->Pop if @$Recent>80;	#
	}

	return unless defined $PlayTime;
	$PlayedPartial=$PlayTime-$StartedAt < $Options{PlayedPercent} * Songs::Get($ID,'length');
	if ($PlayedPartial) #FIXME maybe only count as a skip if played less than ~20% ?
	{	my $nb= 1+Songs::Get($ID,'skipcount');
		Songs::Set($ID, skipcount=> $nb, lastskip=> $StartTime);
	}
	else
	{	my $nb= 1+Songs::Get($ID,'playcount');
		Songs::Set($ID, playcount=> $nb, lastplay=> $StartTime);
	}
}

sub Get_PPSQ_Icon	#for a given ID, returns the Play, Pause, Stop or Queue icon, or undef if none applies
{	my $ID=$_[0];
	my $playlist_row=$_[1]; # facultative
	my $currentsong=defined $playlist_row ?
				defined $Position && $Position==$playlist_row :
				defined $SongID && $ID==$SongID ;
	return
	 $currentsong ?
	 (	$TogPlay		? 'gtk-media-play' :
		defined $TogPlay	? 'gtk-media-pause':
		'gtk-media-stop'
	 ) :
	 @$Queue && $Queue->IsIn($ID) ?
	 do{	my $n;
		if ($NBQueueIcons)
		{	my $max= $#$Queue; $max=$NBQueueIcons if $NBQueueIcons < $max;
			$n= first { $Queue->[$_]==$ID } 0..$max;
		}
		$n ? "gmb-queue$n" : 'gmb-queue';
	 } : undef;
}

sub ClearQueue
{	$Queue->Replace();
	$QueueAction='';
	HasChanged('QueueAction');
}
sub ShuffleQueue
{	my @rand;
	push @rand,rand for 0..$#$Queue;
	$Queue->Replace([map $Queue->[$_], sort { $rand[$a] <=> $rand[$b] } 0..$#$Queue]);
}

sub EnqueueSame
{	my ($field,$ID)=@_;
	my $filter=Songs::MakeFilterFromID($field,$ID);
	EnqueueFilter($filter);
}
sub EnqueueFilter
{	my $l=$_[0]->filter;
	SortList($l) if @$l>1;
	Enqueue(@$l);
}
sub Enqueue
{	my @l=@_;
	SortList(\@l) if @l>1;
	@l=grep $_!=$SongID, @l  if @l>1 && defined $SongID;
	$Queue->Push(\@l);
	# ToggleLock($TogLock) if $TogLock;	#unset lock
}
sub ReplaceQueue
{	$Queue->Replace();
	&Enqueue; #keep @_
}
sub EnqueueAction
{	$QueueAction=shift;
	if ($QueueAction eq 'autofill')	{ QAutoFill(); }
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

sub GetNeighbourSongs
{	my $nb=shift;
	UpdateSort() if $ToDo{'8_updatesort'};
	my $pos=$Position||0;
	my $begin=$pos-$nb;
	my $end=$pos+$nb;
	$begin=0 if $begin<0;
	$end=$#$ListPlay if $end>$#$ListPlay;
	return @$ListPlay[$begin..$end];
}

sub PrevSongInPlaylist
{	UpdateSort() if $ToDo{'8_updatesort'};
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
{	UpdateSort() if $ToDo{'8_updatesort'};
	my $pos=$Position;
	if (!defined $pos) { $pos=0;  if ($RandomMode) {} }	#FIXME PHASE1 in case random
	if ($pos==$#$ListPlay)
	{	return unless $Options{Repeat};
		$pos=0;
	}
	else { $pos++ }
	SetPosition($pos);
}

sub GetNextSongs
{	my $nb=shift||1;
	my $list=($nb>1)? 1 : 0;
	my @IDs;
	{ if (@$Queue)
	  {	unless ($list) { my $ID=$Queue->Shift; return $ID; }
		push @IDs,_"Queue";
		if ($nb>@$Queue) { push @IDs,@$Queue; $nb-=@$Queue; }
		else { push @IDs,@$Queue[0..$nb-1]; last; }
	  }
	  if ($QueueAction)
	  {	push @IDs, $list ? $QActions{$QueueAction}[2] : $QueueAction;
		unless ($list || $QueueAction eq 'wait')
		 { $QueueAction=''; HasChanged('QueueAction'); }
		last;
	  }
	  if ($RandomMode)
	  {	push @IDs,_"Random" if $list;
		push @IDs,$RandomMode->Draw($nb,((defined $SongID && @$ListPlay>1)? [$SongID] : undef));
		last;
	  }
	  return unless @$ListPlay;
	  UpdateSort() if $ToDo{'8_updatesort'};
	  my $pos;
	  $pos=FindPositionSong( $IDs[-1],$ListPlay ) if @IDs;
	  $pos=$Position||0 unless defined $pos;
	  push @IDs,_"next" if $list;
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
	return $list ? @IDs : $IDs[0];
}

sub PrepNextSongs
{	if ($RandomMode) { @NextSongs=(); }
	else
	{	@NextSongs= grep /^\d+$/, GetNextSongs(5); # FIXME GetNextSongs needs some changes to return only IDs, and in the GetNextSongs(1) case
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
	if ($ID eq 'wait') { Stop(); return; }
	if ($ID eq 'stop') { Stop(); return; }
	if ($ID eq 'quit') { Quit(); }
	if ($ID eq 'turnoff') { Stop(); TurnOff(); return; }
	my $pos=$Position; $pos=-2 unless defined $pos;
	if ( $pos<$#$ListPlay && $ListPlay->[$pos+1]==$ID ) { SetPosition($pos+1); }
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
		SortList($playlist,$Options{Sort}) unless $RandomMode;
		$position=FindPositionSong($SongID,$playlist);
	}
	my $list;
	if ($RandomMode) { $list= $filter->filter($playlist); warn scalar @$playlist; }
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

sub DoActionForList
{	my ($action,$list)=@_;
	$action||='playlist';
	my @list=@$list;
	if	($action eq 'queue')		{ Enqueue(@list) }
	elsif	($action eq 'replacequeue')	{ ReplaceQueue(@list) }
	else
	{SortList(\@list) if @list>1; #Enqueue will sort it
	 if	($action eq 'playlist')		{ $ListPlay->Replace(\@list); }
	 elsif	($action eq 'addplay')		{ $ListPlay->Push(\@list); }
	 elsif	($action eq 'insertplay')	{ $ListPlay->InsertAtPosition(\@list); }
	}
}

sub SongArray_changed
{	my (undef,$songarray,$action,@extra)=@_;
	if ($songarray==$Queue)
	{	HasChanged('Queue',$action,@extra);
		if	($QueueAction eq 'wait')	{ IdleDo('1_QAuto',10,\&QWaitAutoPlay) if @$Queue && !$TogPlay; }
		elsif	($QueueAction eq 'autofill')	{ IdleDo('1_QAuto',10,\&QAutoFill); }
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
::callstack(@_);
	my ($filter,$sort,$song,$staticlist,$pos)=@args{qw/filter sort song staticlist position/};
	$SongID=undef if $song && $song eq 'first';
	$song=undef if $song && $song=~m/\D/;
	if (defined $sort) { $ListPlay->Sort($sort) }
	elsif (defined $filter) { $filter= Filter->new($filter) unless ref $filter; $ListPlay->SetFilter($filter) }
	elsif ($staticlist)
	{	if (defined $pos) { $Position=$pos; $SongID=$staticlist->[$pos]; $ChangedID=$ChangedPos=1; }
		$ListPlay->Replace($staticlist);
	}
	elsif (defined $song) { $ListPlay->SetID($song) }
	elsif (defined $pos) { warn $pos;SetPosition($pos) }
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
	{	HasChanged('CurSongID',$SongID);
		HasChanged('CurSong',$SongID);
		ShowTraytip($Options{TrayTipTimeLength}) if $TrayIcon && $Options{ShowTipOnSongChange} && !$FullscreenWindow;
		if (!defined $SongID || $RandomMode) { $Position=undef; }
		else
		{	IdleCheck($SongID) if $Options{TAG_auto_check_current};
			if (!defined $Position || $ListPlay->[$Position]!=$SongID)
			{	my $start=$Position;
				$start=-1 unless defined $start;
				$Position=undef;
				for my $i ($start+1..$#$ListPlay, 0..$start-1) {$Position=$i if $ListPlay->[$i]==$SongID}
			}
		}
		# FIXME if (defined $RecentPos && (!defined $SongID || $SongID!=$Recent->[$RecentPos-1])) { $RecentPos=undef }
		$ChangedPos=1;
	}
	if ($ChangedPos)
	{	HasChanged('Pos','song');
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
		SortList(\@l,$sort);
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

sub SortList	#sort @$listref according to $sort
{	my $time=times; #DEBUG
	warn "deprecated SortList @_\n"; #PHASE1 DELME
	my ($listref,$sort)=@_;
	$sort||=$Options{Sort};
	my $func; my $insensitive;
	if ($sort=~m/^random:/)
	{	@$listref=Random->OneTimeDraw($sort,$listref);
	}
	elsif ($sort ne '')		# generate custom sort function
	{	Songs::SortList($listref,$sort);
	}
	$time=times-$time; warn "sort ($sort) : $time s\n"; #DEBUG
}

sub ExplainSort
{	my $sort=$_[0];
	if ($sort eq '') {return 'no order'}
	elsif ($sort=~m/^random:/)
	{	for my $name (keys %{$Options{SavedWRandoms}})
		{	return "Weighted Random $name." if $Options{SavedWRandoms}{$name} eq $sort;
		}
		return _"unnamed random mode"; #describe ?
	}
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
{	if (@_) { push @ToReRead,@_; }
	else	{ unshift @ToReRead,@$Library; }
	&launchIdleLoop;
}
sub IdleCheck
{	if (@_) { push @ToCheck,@_; }
	else	{ unshift @ToCheck,@$Library; }
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
{	if (@ToCheck)
	{	unless ($CheckProgress_cb)
		{	Glib::Timeout->add(500, \&CheckProgress_cb,0);
			CheckProgress_cb(1);
		}
		Songs::ReReadFile(pop @ToCheck);
	}
	elsif (@ToReRead){Songs::ReReadFile(pop(@ToReRead),1); }	#FIXME should show progress
	elsif (@ToAdd_Files)  { SongAdd(shift @ToAdd_Files); }
#	elsif ($CoverCandidates) {CheckCover();}	#FIXME PHASE1
	elsif (@ToAdd_IDsBuffer>1000)	{ SongAdd_Real() }
	elsif (@ToScan) { $ProgressNBFolders++; ScanFolder(shift @ToScan); }
	elsif (@ToAdd_IDsBuffer)	{ SongAdd_Real() }
	elsif (%ToDo)	{ DoTask( (sort keys %ToDo)[0] ); }
	elsif (@$LengthEstimated)	 #to replace estimated length/bitrate by real one(for mp3s without VBR header)
	{	$Lengthcheck_max=@$LengthEstimated if @$LengthEstimated > $Lengthcheck_max;
		Songs::ReReadFile(shift(@$LengthEstimated),2);
		$Lengthcheck_max=0 unless @$LengthEstimated;
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
}

sub WEditList
{	my $name=$_[0];
	my ($window)=grep exists $_->{editing_listname} && $_->{editing_listname} eq $name, Gtk2::Window->list_toplevels;
	if ($window) { $window->present; return; }
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
	{	$h=($h)? $h.'h ' : '';
		return _"Queue empty" if $nb==0;
		my $format= $h? _"{hours}h{min}m{sec}s" : _"{min}m{sec}s";
		return __("%d song in queue","%d songs in queue",$nb) .' ('. __x($format, @values) . ')';
	}
	else
	{	my $format= $h? _"{hours}h {min}m {sec}s ({size}M)" : _"{min}m {sec}s ({size}M)";
		return __x($format, @values);
	}
}

# http://www.allmusic.com/cg/amg.dll?p=amg&opt1=1&sql=%s    artist search
# http://www.allmusic.com/cg/amg.dll?p=amg&opt1=2&sql=%s    album search
sub AMGLookup
{	my ($col,$key)=@_;
	my $opt1=	$col eq 'artist' ? 1 :
			$col eq 'album'  ? 2 :
			$col eq 'title'	 ? 3 : 0;
	return unless $opt1;
	my $url='http://www.allmusic.com/cg/amg.dll?p=amg&opt1='.$opt1.'&sql=';
	$key=superlc($key);	#can't figure how to pass accents, removing them works better
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
{	my $url=$_[0];
	if ($^O eq 'MSWin32') { system "start $url"; return }#FIXME quote the url
	else
	{	$browsercmd||=findcmd($Options{OpenUrl},qw/xdg-open gnome-open firefox epiphany konqueror galeon/);
		unless ($browsercmd) { ErrorMessage(_"No web browser found."); return }
	}
	$url=quotemeta $url;
	system "$browsercmd $url &"; #FIXME if xdg-open is used, don't launch with "&" and check error code
}
sub openfolder
{	my $dir=quotemeta $_[0];
	if ($^O eq 'MSWin32') { system "start $dir"; return }
	else
	{	$opendircmd||=findcmd($Options{OpenFolder},qw/xdg-open gnome-open nautilus konqueror thunar/);
		unless ($opendircmd) { ErrorMessage(_"No file browser found."); return }
	}
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
	SortList(\@list,'artist:i album:i');
	return ChooseSongs( __x( _"by {artist} from {album}", artist => "<b>%a</b>", album => "%l") ,@list);
}

sub ChooseSongsFromA	#FIXME limit the number of songs if HUGE number of songs (>100-200 ?)
{	my $album=$_[0];
	return unless defined $album;
	my $list= AA::GetIDs(album=>$album);
	SortList($list,'disc track file');
	if (Songs::Get($list->[0],'disc'))
	{	my $disc=''; my @list2;
		for my $ID (@$list)
		{	my $d=Songs::Get($ID,'disc');
			if ($d && $d ne $disc) {push @list2,__x(_"disc {disc}",disc =>$d); $disc=$d;}
			push @list2,$ID;
		}
		$list=\@list2;
	}
	my $menu = ChooseSongs('%n %S', @$list);
	$menu->show_all;
	if (1)
	{	my $h=$menu->size_request->height;
		my $picsize=$menu->size_request->width/$menu->{nbcols};
		$picsize=200 if $picsize<200;
		$picsize=$h if $picsize>$h;
		if ( my $img=NewScaledImageFromFile( AAPicture::GetPicture(album=>$album) ,$picsize) )
		{	my $item=Gtk2::MenuItem->new;
			$item->add($img);
			my $col=$menu->{nbcols};
			$menu->attach($item, $col, $col+1, 0, scalar @$list);
			$item->show_all;
		}
	}
	elsif (0) #TEST not used
	{	my $picsize=$menu->size_request->height;
		$picsize=220 if $picsize>220;
		if ( my $img=NewScaledImageFromFile( AAPicture::GetPicture(album=>$album) ,$picsize) )
		{	my $item=Gtk2::MenuItem->new;
			$item->add($img);
			my $col=$menu->{nbcols};
			#$menu->attach($item, $col, $col+1, 0, scalar @$list);
			$item->show_all;
	$menu->signal_connect(size_request => sub {my ($self,$req)=@_;warn $req->width;return if $self->{busy};$self->{busy}=1;my $rw=$self->get_toplevel->size_request->width;$self->get_toplevel->set_size_request($rw+$picsize,-1);$self->{busy}=undef;});
	my $sub=sub {my ($self,$alloc)=@_;warn $alloc->width;return if $self->{done};$alloc->width($alloc->width-$picsize/$col);$self->{done}=1;$self->size_allocate($alloc);};
	$_->signal_connect(size_allocate => $sub) for $menu->get_children;
		#		$item->signal_connect(size_allocate => sub  {my ($self,$alloc)=@_;warn $alloc->width;return if $self->{busy};$self->{busy}=1;my $w=$self->get_toplevel;$w->set_size_request($w->size_request->width-$alloc->width+$picsize+20,-1);$alloc->width($picsize+20);$self->size_allocate($alloc);});
		}
	}
	elsif ( my $pixbuf=PixBufFromFile(AAPicture::GetPicture(album=>$album)) ) #TEST not used
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
	if (defined wantarray)	{return $menu}
	$menu->popup(undef,undef,\&menupos,undef,$LEvent->button,$LEvent->time);
}

sub ChooseSongs
{	my ($format,@IDs)=@_;
	$format||= __x( _"{song} by {artist}", song => "<b>%t</b>", artist => "%a");
	my $menu = Gtk2::Menu->new;
	my $activate_callback=sub
	 {	return if $_[0]->get_submenu;
		if ($_[0]{middle}) { Enqueue($_[1]); }
		else { Select(song => $_[1]); }
	 };
	my $click_callback=sub
	 { if	($_[1]->button == 2) { $_[0]{middle}=1 }
	   elsif($_[1]->button == 3)
	   {	$LEvent=$_[1];
		my $submenu=PopupContextMenu(\@SongCMenu,{mode => '', IDs=> [$_[2]]});
		$submenu->show_all;
		$_[0]->set_submenu($submenu);
		#$submenu->signal_connect( selection_done => sub {$menu->popdown});
		#$submenu->show_all;
		#$submenu->popup(undef,undef,undef,undef,$LEvent->button,$LEvent->time);
		return 0; #return 0 so that the item receive the click and popup the submenu
	   }
	   return 0;
	 };

	my $cols= $menu->{nbcols}= (@IDs<40)? 1 : (@IDs<80)? 2 : 3;
	my $rows=int(@IDs/$cols);

	my $row=0; my $col=0;
	for my $ID (@IDs)
	{   my $label=Gtk2::Label->new;
	    my $item;
	    if ($ID=~m/^\d+$/) #songs
	    {	$item=Gtk2::ImageMenuItem->new;
		$label->set_alignment(0,.5); #left-aligned
		$label->set_markup( ReplaceFieldsAndEsc($ID,$format) );
		my $icon=Get_PPSQ_Icon($ID);
		$item->set_image(Gtk2::Image->new_from_stock($icon, 'menu')) if $icon;
		$item->signal_connect(activate => $activate_callback, $ID);
		$item->signal_connect(button_press_event => $click_callback, $ID);
		#set_drag($item, source => [::DRAG_ID,sub {::DRAG_ID,$ID}]);
	    }
	    else	# "title" items
	    {	$item=Gtk2::MenuItem->new;
		$label->set_markup("<b>".PangoEsc($ID)."</b>");
		$item->can_focus(0);
		$item->signal_connect(enter_notify_event=> sub {1});
	    }
	    $item->add($label);
	    #$menu->append($item);
	    $menu->attach($item, $col, $col+1, $row, $row+1); if (++$row>$rows) {$row=0;$col++;}
	}
	if (defined wantarray)	{return $menu}
	my $ev=$LEvent;
	$menu->show_all;
	$menu->popup(undef,undef,\&menupos,undef,$ev->button,$ev->time);
}

sub menupos	# function to position popupmenu below clicked widget
{	my $h=$_[0]->size_request->height;		# height of menu to position
	my $ymax=$LEvent->get_screen->get_height;	# height of the screen
	my ($x,$y)=$LEvent->window->get_origin;		# position of the clicked widget on the screen
	my $dy=($LEvent->window->get_size)[1];	# height of the clicked widget
	if ($dy+$y+$h > $ymax)  { $y-=$h; $y=0 if $y<0 }	# display above the widget
	else			{ $y+=$dy; }			# display below the widget
	return $x,$y;
}

sub PopupAA
{	my ($col,%args)=@_;
	my ($list,$from,$callback,$format,$widget,$nosort,$nominor)=@args{qw/list from cb format widget nosort nominor/};
	return undef unless @$Library;
	$format||="%a";

#### make list of albums/artists
	my @keys;
	if (defined $list) { @keys=@$list; }
	elsif (defined $from)
	{	if ($col eq 'album')
		{ my %alb;
		  $from=[$from] unless ref $from;
		  for my $artist (@$from)
		  {	push @{$alb{$_}},$artist for @{ AA::GetXRef(artist=>$artist) };  }
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
				$item->set_submenu(PopupAA('album', list=> $art_keys{$artist}));
				$menu->append($item);
			}
			$menu->show_all;
			if (defined wantarray) {return $menu}
			$menu->popup(undef,undef,\&menupos,undef,$LEvent->button,$LEvent->time);
			return;
		  }
		}
		else
		{ @keys= @{ AA::GetXRef(album=>$from) }; }
	}
	else { @keys=@{ AA::GetAAList($col) }; }

#### callbacks
	my $rmbcallback;
	unless ($callback)
	{  $callback=sub		#jump to first song
	   {	return if $_[0]->get_submenu;
		my $key=$_[1];
		my $ID=FindFirstInListPlay( AA::GetIDs($col,$key) );
		Select(song => $ID);
	   };
	   $rmbcallback=($col eq 'album')?
		sub	#Albums rmb cb
		{	(my$item,$LEvent,my$key)=@_;
			return 0 unless $LEvent->button==3;
			my $submenu=ChooseSongsFromA($key);
			$item->set_submenu($submenu);
			0; #return 0 so that the item receive the click and popup the submenu
		}:
		sub	#Arists rmb cb
		{	(my$item,$LEvent,my$key)=@_;
			return 0 unless $LEvent->button==3;
			my $submenu=PopupAA('album', from=>$key);
			$item->set_submenu($submenu);
			0;
		};
	}

	my $screen= $widget ? $widget->get_screen : $LEvent->get_screen;
	my $max=($screen->get_height)*.8;
	#my $minsize=Gtk2::ImageMenuItem->new('')->size_request->height;
	my @todo;	#hold images not yet loaded because not cached

	my $createAAMenu=sub
	{	my ($start,$end,$names,$keys)=@_;
		my $nb=$end-$start+1;
		my $size=32;	$size=64 if 64*$nb < $max;
		my $row=0; my $rows=($nb<21)? 1 : ($nb<50)? 2 : 3; $rows=int($nb/$rows); my $colnb=0;
	#	my $size=int($max/$rows);	#my $size=int($max/$nb);
	#	if ($size<$minsize) {$size=$minsize} elsif ($size>100) {$size=100}
		my $menu = Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $key=$keys->[$i];
			my $item=Gtk2::ImageMenuItem->new;
			my $label=Gtk2::Label->new;
			$label->set_line_wrap(TRUE);
			$label->set_alignment(0,.5);
			$label->set_markup( AA::ReplaceFields($key,$format,$col,1) );
			#$label->set_markup( AA::ReplaceFields($key,"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",$col,1) );
			$item->add($label);
			$item->signal_connect(activate => $callback,$key);
			$item->signal_connect(button_press_event => $rmbcallback,$key) if $rmbcallback;
			#$menu->append($item);
			$menu->attach($item, $colnb, $colnb+1, $row, $row+1); if (++$row>$rows) {$row=0;$colnb++;}
			if (my $f=AAPicture::GetPicture($col,$key))
			{	my $img=AAPicture::newimg($col,$key,$size,\@todo);
				$item->set_image($img);
				#push @todo,$item,$f,$size;
			}
		}
		return $menu;
	}; #end of createAAMenu

	my $min= ($col eq 'album')? $Options{AlbumMenu_min} : $Options{ArtistMenu_min};
	$min=0 if $nominor;
	my @keys_minor;
	if ($min)
	{	@keys= grep {  @{ AA::GetAAList($col,$_) }>$min or push @keys_minor,$_ and 0 } @keys;
		if (!@keys) {@keys=@keys_minor; undef @keys_minor;}
	}

	Songs::sort_gid_by_name($col,\@keys) unless $nosort;
	my @names=@{Songs::Gid_to_Display($col,\@keys)}; #convert @keys to list of names

	my $menu=Breakdown_List(\@names,5,20,35,$createAAMenu,\@keys);
	return undef unless $menu;
	if (@keys_minor)
	{	Songs::sort_gid_by_name($col,\@keys_minor) unless $nosort;
		my @names=@{Songs::Gid_to_Display($col,\@keys)};
		my $item=Gtk2::MenuItem->new('minor'); #FIXME
		my $submenu=Breakdown_List(\@names,5,20,35,$createAAMenu,\@keys_minor);
		$item->set_submenu($submenu);
		$menu->append($item);
	}
	$menu->show_all;

	if (@todo)
	{ Glib::Idle->add(sub
		{	my $img=shift @todo;
			return 0 unless $img;
			AAPicture::setimg($img);
			1;
		});
	  $menu->signal_connect(destroy => sub {undef @todo})
	}

	if (defined wantarray) {return $menu}
	$menu->popup(undef,undef,\&menupos,undef,$LEvent->button,$LEvent->time);
}

sub Breakdown_List
{	my ($keys,$min,$opt,$max,$makemenu,$gids)=@_;

	if ($#$keys<=$max) { return $makemenu ? &$makemenu(0,$#$keys,$keys,$gids) : [0,$#$keys] }

	my @bounds;
	for my $start (0..$#$keys)
	{	my $name1= $start==0 ?  '' : lc $keys->[$start-1];
		my $name2= lc $keys->[$start];
		my $name3= $start==$#$keys ?  '' : lc $keys->[$start+1];
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
				$toobig[$pos]=0 unless $chunk[$pos]>$max;
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
#	push @breakpoints,$#$keys+1; push @length,1;

	my $istart=0; my @list;
	while ($istart<$#breakpoints)
	{	my $best; my $bestpos;
		for (my $i=$istart+1; $i<=$#breakpoints; $i++)
		{	my $nb=$breakpoints[$i]-$breakpoints[$istart];
			my $nbafter=$#$keys-$breakpoints[$i]+1;
			next if $nb<$min && $i<$#breakpoints;
			my $score=$length[$i]*100+abs($nb-$opt)+ ($nbafter==0 ? -10 : $nbafter<8 ? 8-$nbafter : 0);
#warn "$istart-$i ($breakpoints[$istart]-$breakpoints[$i]): $nb  length=$length[$i]	score=$score  nbafter=$nbafter\n";	#DEBUG
			if (!defined $best || $best>$score)
			 {$best=$score; $bestpos=$i;}
			last if $nb>$max && $nbafter>$min;
		}
#warn " best: $istart-$bestpos ($breakpoints[$istart]-$breakpoints[$bestpos]): score=$best\n";	#DEBUG
		push @list,$breakpoints[$bestpos];
		$istart=$bestpos;
	}
#	for my $i (0..$#$keys)	#DEBUG
#	{	my $b=grep $i==$_, @breakpoints;
#		$b= $b? '->' : ' ';
#		my $b2=grep $i==$_, @list;
#		$b2= $b2? '=>' : ' ';
#		warn "$i\t$b\t$b2\t$bounds[$i][0]\t$bounds[$i][1]\t$keys->[$i]\n";
#	}
	@breakpoints=@list;

	my @menus; my $start=0;
	for my $end (@breakpoints)
	{	my $c1=$bounds[$start][0];
		my $c2=$bounds[$end-1][1];
		for my $i (0..length($c1)-1)
		{	my $c2i=substr $c2,$i,1;
			if ($c2i eq '') { $c2.=$c2i= substr $keys->[$end-1],$i,1; }
			last if substr($c1,$i,1) ne $c2i;
		}
		#warn "$c1-$c2\n";
		push @menus,[$start,$end-1,$c1,$c2];
		$start=$end;
	}

	return @menus unless $makemenu;
	my $menu;
	if (@menus>1)
	{	$menu=Gtk2::Menu->new;
		for my $ref (@menus)
		{	my ($start,$end,$c1,$c2)=@$ref;
			$c1=ucfirst$c1; $c2=ucfirst$c2;
			$c1.='-'.$c2 if $c2 ne $c1;
			my $item=Gtk2::MenuItem->new_with_label($c1);
			my $submenu= &$makemenu($start,$end,$keys,$gids);
			$item->set_submenu($submenu);
			$menu->append($item);
		}
	}
	elsif (@menus==1) { $menu= &$makemenu(0,$#$keys,$keys,$gids); }
	else {return undef}

	return $menu;
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
	$loader->signal_connect(size_prepared => \&::PixLoader_callback,$size) if $size;
	eval { $loader->write($pixdata); };
	eval { $loader->close; } unless $@;
	$loader=undef if $@;
	warn "$@\n" if $debug;
	return $loader;
}

sub PixBufFromFile
{	my $file=$_[0]; my $size=$_[1];
	return unless $file;
	unless (-r $file) {warn "$file not found\n" unless $_[1]; return undef;}

	my $loader=Gtk2::Gdk::PixbufLoader->new;
	$loader->signal_connect(size_prepared => \&PixLoader_callback,$size) if $size;
	if ($file=~m/\.(?:mp3|flac|m4a|m4b)$/i)
	{	my $data=FileTag::PixFromMusicFile($file);
		eval { $loader->write($data) } if defined $data;
	}
	else	#eval{Gtk2::Gdk::Pixbuf->new_from_file(filename_to_unicode($file))};
		# work around Gtk2::Gdk::Pixbuf->new_from_file which wants utf8 filename
	{	open my$fh,'<',$file; binmode $fh;
		my $buf; eval {$loader->write($buf) while read $fh,$buf,1024*64;};
		close $fh;
	}
	eval {$loader->close;};
	return $@ ? undef : $loader->get_pixbuf;
}

sub NewScaledImageFromFile
{	my ($pix,$w,$q)=@_;	# $pix=file or pixbuf , $w=size, $q true for HQ
	return undef unless $pix;
	my $h=$w;
	unless (ref $pix)
	{ $pix=PixBufFromFile($pix);
	  return undef unless $pix;
	}
	my $ratio=$pix->get_width / $pix->get_height;
	if    ($ratio>1) {$h=int($w/$ratio);}
	elsif ($ratio<1) {$w=int($h*$ratio);}
	$q=($q)? 'bilinear' : 'nearest';
	return Gtk2::Image->new_from_pixbuf( $pix->scale_simple($w, $h, $q) );
}

sub ScaleImageFromFile
{	my ($img,$w,$file,$nowarn)=@_;
	$img->{pixbuf}=PixBufFromFile($file,$nowarn);
	ScaleImage($img,$w);
}

sub ScaleImage
{	my ($img,$w)=@_;
	my $pix=$img->{pixbuf};
	if (!$pix || !$w || $w<16) { $img->set_from_pixbuf(undef); return; }
	my $h=$w;
	my $ratio=$pix->get_width / $pix->get_height;
	if    ($ratio>1) {$h=int($w/$ratio);}
	elsif ($ratio<1) {$w=int($h*$ratio);}
	$img->set_from_pixbuf( $pix->scale_simple($w, $h, 'bilinear') );
}

sub pixbox_button_press_cb	# zoom picture when clicked
{	my ($eventbox,$event,$button)=@_;
	return 0 if $button && $event->button != $button;
	my $image;
	if ($eventbox->{pixdata})
	{	my $loader=::LoadPixData($eventbox->{pixdata},350);
		$image=Gtk2::Image->new_from_pixbuf($loader->get_pixbuf) if $loader;
	}
	elsif (my $pixbuf=$eventbox->child->{pixbuf})
	 { $image=::NewScaledImageFromFile($pixbuf,350,1); }
	return 1 unless $image;
	my $menu=Gtk2::Menu->new;
	my $item=Gtk2::MenuItem->new;
	$item->add($image);
	$menu->append($item);
	$menu->show_all;
	$menu->popup(undef,undef,undef,undef,$event->button,$event->time);
	1;
}

sub PopupContextMenu	#FIXME rename to BuildContextMenu or BuildMenu
{	my ($mref,$args,$appendtomenu)=@_;
	my $menu= $appendtomenu || Gtk2::Menu->new;
	for my $m (@$mref)
	{	next if $m->{ignore};
		next if $m->{type}	&& index($args->{type},	$m->{type})==-1;
		next if $m->{mode}	&& index($m->{mode},	$args->{mode})==-1;
		next if $m->{notmode}	&& index($m->{notmode},	$args->{mode})!=-1;
		next if $m->{isdefined}	&& !defined $args->{ $m->{isdefined} };
		#next if $m->{notdefined}&& defined $args->{ $m->{notdefined} };
		next if $m->{istrue}	&&   !$args->{ $m->{istrue} };
		#next if $m->{notstrue}	&&    $args->{ $m->{nottrue} };
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
		elsif ($m->{stockicon})
		{	$item=Gtk2::ImageMenuItem->new($label);
			$item->set_image( Gtk2::Image->new_from_stock($m->{stockicon},'menu') );
		}
		elsif ( ($m->{check} || $m->{radio}) && !$m->{submenu})
		{	$item=Gtk2::CheckMenuItem->new($label);
			my $func= $m->{check} || $m->{radio};
			$item->set_active(1) if $func->($args);
			$item->set_draw_as_radio(1) if $m->{radio};
		}
		elsif ( my $include=$m->{include} ) #append items made by $include
		{	$include= $include->($args) if ref $include eq 'CODE';
			if (ref $include eq 'ARRAY') { PopupContextMenu($include,$args,$menu); }
			next;
		}
		elsif ( my $repeat=$m->{repeat} )
		{	my @menus= $repeat->($args);
			for my $submenu (@menus)
			{	my ($menuarray,@extra)=@$submenu;
				PopupContextMenu($menuarray,{%$args,@extra},$menu);
			}
			next;
		}
		else	{ $item=Gtk2::MenuItem->new($label); }

		if (my $i=$m->{sensitive}) { $item->set_sensitive(0) unless $i->($args) }

		if (my $submenu=$m->{submenu})
		{	$submenu=$submenu->($args) if ref $submenu eq 'CODE';
			if ($m->{code}) #list submenu
			{	my (@labels,@values);
				if ($m->{submenu_ordered_hash} || $m->{submenu_tree})
				{	my $i=0;
					while ($i<$#$submenu)
					 { push @labels,$submenu->[$i++];push @values,$submenu->[$i++]; }
				}
				elsif (ref $submenu eq 'ARRAY')	{@labels=@values=@$submenu}
				else				{@labels=keys %$submenu; @values=values %$submenu;}
				my $reverse= $m->{submenu_tree} || $m->{submenu_reverse};
				if ($reverse) { my @t=@values; @values=@labels; @labels=@t; }
				my @order= 0..$#labels;
				@order=sort {superlc($labels[$a]) cmp superlc($labels[$b])} @order if ref $submenu eq 'HASH' || $m->{submenu_tree};

				$submenu=Gtk2::Menu->new;
				my $smenu_callback=sub
				 {	my $sub=$_[1];
					$sub->( $args, $_[0]{selected} );
				 };
				my $check;
				$check= $m->{check}($args) if $m->{check};
				for my $i (@order)
				{	my $label=$labels[$i];
					my $value=$values[$i];
					if (ref $value && $m->{submenu_tree})
					{	PopupContextMenu([{%$m,label=>$label,submenu=>$value}],$args,$submenu);
						next;
					}
					my $item=Gtk2::MenuItem->new_with_label($label);
					if (defined $check)
					{	$item=Gtk2::CheckMenuItem->new_with_label($label);
						if (ref $check)	{ $item->set_active(1) if grep $_ eq $value, @$check; }
						else
						{	$item->set_draw_as_radio(1);
							$item->set_active(1) if $check eq $value;
						}
					}
					$item->{selected}= $value;
					$submenu->append($item);
					$item->signal_connect(activate => $smenu_callback, $m->{code} );
				}
				$submenu=undef unless @order; #empty submenu
			}
			elsif (ref $submenu eq 'ARRAY') { $submenu=PopupContextMenu($submenu,$args); }
			next unless $submenu;
			$item->set_submenu($submenu);
		}
		else
		{	$item->signal_connect (activate => sub { $m->{code}->($args); });
		}
		$menu->append($item);
	}
	return if $appendtomenu;
	if (defined wantarray) {return $menu}
	return unless $menu->get_children;
	$menu->show_all;
	my $posfunction= $args->{usemenupos} ? \&menupos : undef;
	$menu->popup(undef,undef,$posfunction,undef,$LEvent->button,$LEvent->time);
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
	my $pixmap = Gtk2::Gdk::Pixmap->new(undef,$w,$h, $self->window->get_depth);
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
	if ($data->length >=0 && $data->format==8)
	{	my @values=split "\x0d\x0a",$data->data;
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
{	my ($path,$win,$abortmsg)=@_;
	my $current='';
	for my $dir (split /$QSLASH/o,$path)
	{	$dir= CleanupFileName($dir);
		next if $dir eq '' || $dir eq '.';
		$current.=SLASH.$dir;
		next if -d $current;
		until (mkdir $current)
		{	#if (-f $current) { ErrorMessage("Can't create folder '$current' :\na file with that name exists"); return undef }
			my $ret=Retry_Dialog( __x( _"Can't create Folder '{path}' : \n{error}", path => $current, error=> $!) ,$win,$abortmsg);
			return $ret unless $ret eq 'yes';
		}
	}
	return 'ok';
}

sub CopyMoveFilesDialog
{	my ($IDs,$copy)=@_;
	my $msg=$copy	?	_"Choose directory to copy files to"
			:	_"Choose directory to move files to";
	my $newdir=ChooseDir($msg, Songs::Get($IDs->[0],'path').SLASH);
	CopyMoveFiles($IDs,$copy,$newdir) if defined $newdir;
}

#$fnformat=$1 if $dirformat=~s/$QSLASH([^$QSLASH]*%\w[^$QSLASH]*)//o;
sub CopyMoveFiles
{	my ($IDs,$copy,$basedir,$dirformat,$fnformat)=@_;
	#return unless defined $basedir || defined $dirformat;
	$basedir.=SLASH if defined $basedir && $basedir!~m/$QSLASH$/o;
	return if !$copy && $CmdLine{ro};
	my ($sub,$errormsg,$abortmsg)=  $copy	?	(\&copy,_"Copy failed",_"abort copy")
						:	(\&move,_"Move failed",_"abort move") ;
	$abortmsg=undef unless @$IDs>1;
	my $action=($copy) ?	__("Copying file","Copying %d files",scalar@$IDs) :
				__("Moving file", "Moving %d files", scalar@$IDs) ;

	my $win=Gtk2::Window->new('toplevel');
	$win->set_border_width(3);
	my $label=Gtk2::Label->new($action);
	my $progressbar=Gtk2::ProgressBar->new;
	my $Bcancel=Gtk2::Button->new_from_stock('gtk-cancel');
	my $cancel;
	my $cancelsub=sub {$cancel=1};
	$win->signal_connect( destroy => $cancelsub);
	$Bcancel->signal_connect( clicked => $cancelsub);
	my $vbox=Gtk2::VBox->new(FALSE, 2);
	$vbox->pack_start($_, FALSE, TRUE, 3) for $label,$progressbar,$Bcancel;
	$win->add($vbox);
	$win->show_all;
	my $done=0;

	my $owrite_all;
COPYNEXTID:for my $ID (@$IDs)
	{	$progressbar->set_fraction($done/@$IDs);
		Gtk2->main_iteration while Gtk2->events_pending;
		$done++;
		$abortmsg=undef if $done==@$IDs;
		my ($olddir,$oldfile)= Songs::Get($ID, qw/path file/);
		my $old=$olddir.SLASH.$oldfile;
		my $newfile=$oldfile;
		my $newdir=defined $basedir? $basedir : $olddir.SLASH;
		if ($dirformat)
		{	$newdir=pathfromformat($ID,$dirformat,$basedir);
			my $res=CreateDir($newdir,$win, $abortmsg );
			last if $res eq 'abort';
			next if $res eq 'no';
			$newdir=filename_from_unicode($newdir);
		}
		if ($fnformat)
		{	$newfile=filenamefromformat($ID,$fnformat,1);
			next unless defined $newfile;
			$newfile=filename_from_unicode($newfile);
		}
		my $new=$newdir.$newfile;
		next if $old eq $new;
		#warn "from $old\n to $new\n";
		if (-f $new) #if file already exists
		{	my $ow=$owrite_all;
			$ow||=OverwriteDialog($win,$new,$abortmsg);
			$owrite_all=$ow if $ow=~m/all$/;
			next if $ow=~m/^no/;
		}
		until ($sub->($old,$new))
		{	my $res=Retry_Dialog("$errormsg :\n'$old'\n -> '$new'\n$!",$win,$abortmsg);
			last COPYNEXTID if $res eq 'abort';
			last unless $res eq 'yes';
		}
		unless ($copy)
		{	$newdir=~s/$QSLASH+$//o;
			my @modif;
			push @modif, path => $newdir  if $olddir ne $newdir;
			push @modif, file => $newfile if $oldfile ne $newfile;
			Songs::Set($ID, @modif);
		}
		last if $cancel;
	}
	$win->destroy;
}

sub ChooseDir
{	my ($msg,$path,$extrawidget,$remember_key,$multiple) = @_;
	my $dialog=Gtk2::FileChooserDialog->new($msg,undef,'select-folder',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none',
					);
	if ($remember_key) { $path= decode_url($Options{$remember_key}); }
	_utf8_on($path) if $path; #FIXME not sure if it's the right thing to do
	$dialog->set_current_folder($path) if $path;
	$dialog->set_extra_widget($extrawidget) if $extrawidget;
	$dialog->set_select_multiple(1) if $multiple;

	my @paths;
	if ($dialog->run eq 'ok')
	{	@paths=$dialog->get_filenames;
		eval { $_=filename_from_unicode($_); } for @paths;
		_utf8_off($_) for @paths;# folder names that failed filename_from_unicode still have their uft8 flag on
		@paths= grep -d, @paths;
	}
	else {@paths=()}
	if ($remember_key) { $Options{$remember_key}= url_escape($dialog->get_current_folder); }
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

sub ChoosePix
{	my ($path,$text,$file,$remember_key)=@_;
	$text||=_"Choose Picture";
	my $dialog=Gtk2::FileChooserDialog->new($text,undef,'open',
					_"no picture" => 'reject',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none');

	for my $aref
	(	[_"Pictures and music files",'image/*','*.mp3 *.flac *.m4a *.m4b' ],
		[_"Pictures files",'image/*'],
		[_"All files",undef,'*'],
	)
	{	my $filter= Gtk2::FileFilter->new;
		#$filter->add_mime_type('image/'.$_) for qw/jpeg gif png bmp/;
		if ($aref->[1])	{ $filter->add_mime_type($_)	for split / /,$aref->[1]; }
		if ($aref->[2])	{ $filter->add_pattern($_)	for split / /,$aref->[2]; }
		$filter->set_name($aref->[0]);
		$dialog->add_filter($filter);
	}

	my $preview=Gtk2::VBox->new;
	my $label=Gtk2::Label->new;
	my $image=Gtk2::Image->new;
	my $eventbox=Gtk2::EventBox->new;
	$eventbox->add($image);
	$eventbox->signal_connect(button_press_event => \&pixbox_button_press_cb);
	$preview->pack_start($_,FALSE,FALSE,2) for $eventbox,$label;
	$dialog->set_preview_widget($preview);
	#$dialog->set_use_preview_label(FALSE);
	my $update_preview=sub
		{ my ($dialog,$file)=@_;
		  unless ($file)
		  {	$file= eval {$dialog->get_preview_filename};
			$file=$dialog->get_filename if $@; #for some reason get_preview_filename doesn't work with bad utf8 whereas get_filename works. don't know if there is any difference
		  }
		  return unless $file;
		  unless (-f $file) #not sure it's needed - test with broken filenames on other OS
		  {	eval{ $file=filename_from_unicode($file); };
		  	_utf8_off($file); #shouldn't be needed :(
		  }
		  ScaleImageFromFile($image,150,$file);
		  my $p=$image->{pixbuf};
		  if ($p) { $label->set_text($p->get_width.' x '.$p->get_height); }
		  #else { $label->set_text('no picture'); }
		  $dialog->set_preview_widget_active($p);
		};
	$dialog->signal_connect(update_preview => $update_preview);

	$preview->show_all;
	if ($remember_key) { $path= decode_url($Options{$remember_key}); }
	if ($file && -f $file)	{ $dialog->set_filename($file); $update_preview->($dialog,$file); }
	#elif ($path)		{ $dialog->set_current_folder($path); }
	elsif ($path)		{ $dialog->set_filename($path.SLASH.'*.jpg'); }

	my $response=$dialog->run;
	my $ret;
	if ($response eq 'ok')
	{	$ret=$dialog->get_filename;
		eval { $ret=filename_from_unicode($ret); };
		unless (-r $ret) { warn "can't read $ret\n"; $ret=undef; }
	}
	elsif ($response eq 'reject') {$ret='0'}
	else {$ret=undef}
	if ($remember_key) { $Options{$remember_key}= url_escape($dialog->get_current_folder); }
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
#	$eventbox->signal_connect(button_press_event => \&pixbox_button_press_cb);
#	$frame->set_size_request(155,155);
#	my $label=Gtk2::Label->new;
#	$PixSelector->set_filename(filename_to_utf8displayname($path.SLASH)) if $path &&  -d $path;
#	$previewbox->pack_start($_,FALSE,FALSE,2) for $frame,$label;
#	$PixSelector->selection_entry->signal_connect(changed => sub
#		{	my ($file)=$PixSelector->get_selections;
#			$file=filename_from_unicode($file);
#			ScaleImageFromFile($img,150,$file,'nowarn');
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

sub Retry_Dialog	#returns 'yes' 'no' or 'abort'
{	my ($err,$window,$abortmsg)=@_;
	my $dialog = Gtk2::MessageDialog->new
	( $window,
	  [qw/modal destroy-with-parent/],
	  'error','yes-no','%s',
	  "$err\n "._("retry ?")
	);
	$dialog->add_button($abortmsg, '1') if $abortmsg;
	$dialog->show_all;
	my $ret=$dialog->run;
	$dialog->destroy;
	$ret=	($ret eq '1')	? 'abort':
		($ret)		? $ret	  :
		'abort';
	return $ret;
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
	if (exists $Editing{'L'.$ID}) { $Editing{'L'.$ID}->present; return; }
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

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);
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
		( undef,
		  'modal',
		  'warning','ok-cancel','%s',
		  __x(_("About to delete {files}\nAre you sure ?"), files => $text)
		);
	$dialog->show_all;
	if ('ok' eq $dialog->run)
	{ my $abortmsg;
	  $abortmsg=_"Abort" if @$IDs>1;
	  for my $ID (@$IDs)
	  {	my $f= Songs::GetFullFilename($ID);
		unless (unlink $f)
		{	my $res=::Retry_Dialog(__x(_("Failed to delete '{file}' :\n{error}"), file => $f, error => $!),undef,$abortmsg);
			redo if $res eq 'yes';
			last if $res eq 'abort';
		}
		IdleCheck($ID);
	  }
	}
	$dialog->destroy;
}

sub filenamefromformat
{	my ($ID,$format,$ext)=@_;
	my $s= CleanupFileName( ReplaceFields($ID,$format) );
	$s.=( Songs::Get($ID,'file')=~m/(\.[^\.]+$)/ )[0] if $ext; #add extension
	return $s;
}
sub pathfromformat
{	my ($ID,$format,$basefolder,$icase)=@_;
	my $path= $basefolder ? $basefolder.SLASH : '';
	for my $f0 (split /$QSLASH+/o,$format)
	{	my $f= CleanupFileName( ReplaceFields($ID,$f0) );
		if ($f0 ne $f)
		{	$f=~s/^\.\.?$//;
			$f=ICasePathFile($path,$f) if $icase;
		}
		$path.=$f.SLASH;
	}
	return $path;
}
sub pathfilefromformat
{	my ($ID,$format,$ext,$icase)=@_;
	$format=~s#^~($QSLASH)#$ENV{HOME}$1#o;
	$format=~s#$QSLASH+\.?$QSLASH+#SLASH#goe;
	return undef unless $format=~m#^$QSLASH#o;
	my ($path,$file)= $format=~m/^(.*)$QSLASH([^$QSLASH]+)$/o;
	return undef unless $file;
	$path=pathfromformat($ID,$path,undef,$icase);
	$file=filenamefromformat($ID,$file,$ext);
	$file=ICasePathFile($path,$file) if $icase;
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

sub DialogMassRename
{	return if $CmdLine{ro};
	my @IDs= uniq(@_); #remove duplicates IDs in @_ => @IDs
	::SortList(\@IDs,'path album disc track file');
	my $dialog = Gtk2::Dialog->new
			(_"Mass Renaming", undef,
			 [qw/destroy-with-parent/],
			 'gtk-ok'	=> 'ok',
			 'gtk-cancel'	=> 'none',
			);
	$dialog->set_border_width(4);
	$dialog->set_default_response('ok');
	SetWSize($dialog,'MassRename');
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
		if ($folders) {$text=pathfromformat($ID,$comboFolder->get_active_text, $Options{BaseFolder}).$text; }
		$cell->set(text=>$text);
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
		my $sw=Gtk2::ScrolledWindow->new;
		$sw->set_shadow_type('etched-in');
		$sw->set_policy('automatic','automatic');
		$sw->add($tv);
		$notebook->append_page($sw,$title);
	}
	$treeview2->parent->set_vadjustment( $treeview1->parent->get_vadjustment ); #sync vertical scrollbars
	#sync selections :
	my $busy;
	my $syncsel=sub { return if $busy;$busy=1;my $path=$_[0]->get_selected_rows; $_[1]->get_selection->select_path($path);$busy=undef;};
	$treeview1->get_selection->signal_connect(changed => $syncsel,$treeview2);
	$treeview2->get_selection->signal_connect(changed => $syncsel,$treeview1);

	$store->set( $store->append,0, $_ ) for @IDs;

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
		  {	my $base= $Options{BaseFolder};
			unless ( defined $base ) { ErrorMessage(_("You must specify a base folder"),$dialog); return }
			until ( -d $base ) { last unless $base=~s/$QSLASH[^$QSLASH]*$//o && $base=~m/$QSLASH/o;  }
			unless ( -w $base ) { ErrorMessage(__x(_("Can't write in base folder '{folder}'."), folder => $Options{BaseFolder}),$dialog); return }
			$dialog->set_sensitive(FALSE);
			my $folderformat=$comboFolder->get_active_text;
			CopyMoveFiles(\@IDs,FALSE,$Options{BaseFolder},$folderformat,$format);
		  }
		  elsif ($format)
		  {	$dialog->set_sensitive(FALSE);
			CopyMoveFiles(\@IDs,FALSE,undef,undef,$format);
		  }
		}
		$dialog->destroy;
	 });
}

sub RenameFile
{	my ($ID,$newutf8,$window,$abortmsg)=@_;
	my $new=filename_from_unicode(CleanupFileName($newutf8));
	my ($dir,$old)= Songs::Get($ID,qw/path file/);
	{	last if $new eq '';
		last if $old eq $new;
		if (-f $dir.SLASH.$new)
		{	my $res=OverwriteDialog($window,$new); #FIXME support yesall noall ? but not needed because RenameFile is now only used for single file renaming
			return $res unless $res eq 'yes';
			redo;
		}
		elsif (!rename $dir.SLASH.$old, $dir.SLASH.$new)
		{	my $res=Retry_Dialog( __x( _"Renaming {oldname}\nto {newname}\nfailed : {error}", oldname => Songs::Display($ID,'file'), newname => $newutf8, error => $!),$window,$abortmsg);
			return $res unless $res eq 'yes';
			redo;
		}
	}
	Songs::Set($ID, file=> $new);
	return 1;
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
		$lab1->set_markup('<b>'.PangoEsc(Songs::FieldName($col)).' :</b>');
		$lab1->set_padding(5,0);
		$lab1->set_alignment(1,.5);
		$lab2->set_alignment(0,.5);
		$lab2->set_line_wrap(1);
		$lab2->set_selectable(TRUE);
		$table->attach_defaults($lab1,0,1,$row,$row+1);
		$table->attach_defaults($lab2,1,2,$row,$row+1);
		$row++;
	}
	my $entry=Gtk2::Entry->new;
	$entry->set_activates_default(TRUE);
	$entry->set_text(Songs::Display($ID,'file'));
	$dialog->vbox->add($table);
	$dialog->vbox->add($entry);
	SetWSize($dialog,'Rename');

	$dialog->show_all;
	$dialog->signal_connect( response => sub
	 {	my ($dialog,$response)=@_;
		if ($response eq 'ok')
		{	my $name=$entry->get_text;
			RenameFile($ID,$name,$dialog) if $name;
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
	my $menu=Breakdown_List(\@keys,5,20,35,$makemenu);
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
		if ($_[0]->get_active)	{ SetLabels($IDs,[$f],undef); }
		else			{ SetLabels($IDs,undef,[$f]); }
	 };
	MakeFlagToggleMenu($field,$hash,$menusub_toggled);
}

sub MakeFlagToggleMenu	#FIXME special case for no @keys, maybe a menu with a greyed-out item "no #none#"
{	my ($field,$hash,$callback)=@_;
	my @keys= @{Songs::ListAll($field)};
	my $makemenu=sub
	{	my ($start,$end,$keys)=@_;
		my $menu=Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $key=$keys->[$i];
			my $item=Gtk2::CheckMenuItem->new_with_label($key);
			my $state= $hash->{$key}||0;
			if ($state==1){ $item->set_active(1); }
			elsif ($state==2)  { $item->set_inconsistent(1); }
			$item->signal_connect(toggled => $callback,$key);
			$menu->append($item);
		}
		return $menu;
	};
	my $menu=Breakdown_List(\@keys,5,20,35,$makemenu);
	return $menu;
}

sub PopupAAContextMenu
{	my $args=$_[0];
	$args->{mainfield}= Songs::MainField($args->{field});
	$args->{aaname}= Songs::Gid_to_Get($args->{field},$args->{gid});
	PopupContextMenu(\@cMenuAA, $args);
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
	return undef if $nb==0;
	return __("%d Song","%d Songs",$nb);
}
sub SongsSubMenu
{	my %args=%{$_[0]};
	$args{mode}='S';
	$args{IDs}=\@{ AA::GetIDs($args{field},$args{gid}) };
	return PopupContextMenu(\@SongCMenu,\%args);
}

sub ArtistContextMenu
{	my ($artists,$params)=@_;
	$params->{field}='artists';
	if (@$artists==1) { PopupAAContextMenu({%$params,gid=>$artists->[0]}); return; }
	my $menu = Gtk2::Menu->new;
	for my $ar (@$artists)
	{	my $item=Gtk2::MenuItem->new_with_label($ar);
		my $submenu= PopupAAContextMenu({%$params,gid=>$ar});
		$item->set_submenu($submenu);
		$menu->append($item);
	}
	$menu->show_all;
	$menu->popup(undef,undef,undef,undef,$LEvent->button,$LEvent->time);
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
	$addlabel->($_) for @{SortedLabels()};
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
		SetLabels(\@IDs,\@toadd,\@toremove);
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
	#my $editlabels=EditLabels(@IDs);
	#my $rating=SongRating(@IDs);
	#$notebook->append_page( $edittag ,	Gtk2::Label->new(_"Tag"));
	#$notebook->append_page( $editlabels,	Gtk2::Label->new(_"Labels"));
	#$notebook->append_page( $rating,	Gtk2::Label->new(_"Rating"));

	SetWSize($dialog,'MassTag');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
		{	#warn "MassTagging response : @_\n" if $debug;
			my ($dialog,$response)=@_;
			if ($response eq 'ok')
			{ $dialog->action_area->set_sensitive(FALSE);
			  #$editlabels->{save}();
			  #$rating->{save}($rating);
			  $edittag->save( sub {$dialog->destroy;} ); #the closure will be called when tagging finished #FIXME not very nice
			}
			else { $dialog->destroy; }
			#delete $Editing{$ID};
		});
}

sub DialogSongProp
{	my $ID=$_[0];
	if (exists $Editing{$ID}) { $Editing{$ID}->present; return; }
	my $dialog = Gtk2::Dialog->new (_"Song Properties", undef, [],
				'gtk-save' => 'ok',
				'gtk-cancel' => 'none');
	$dialog->set_default_response ('ok');
	$Editing{$ID}=$dialog;
	my $notebook = Gtk2::Notebook->new;
	$notebook->set_tab_border(4);
	$dialog->vbox->add($notebook);

	my $edittag=EditTagSimple->new($dialog,$ID);
	#my $editlabels=EditLabels($ID);
	#my $rating=SongRating($ID);
	my $songinfo=SongInfo($ID);
	$notebook->append_page( $edittag,	Gtk2::Label->new(_"Tag"));
	#$notebook->append_page( $editlabels,	Gtk2::Label->new(_"Labels"));
	#$notebook->append_page( $rating,	Gtk2::Label->new(_"Rating"));
	$notebook->append_page( $songinfo,	Gtk2::Label->new(_"Info"));

	SetWSize($dialog,'SongInfo');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
	{	warn "EditTag response : @_\n" if $debug;
		my ($dialog,$response)=@_;
		$songinfo->destroy;
		if ($response eq 'ok')
		{	#$editlabels->{save}();
			#$rating->{save}($rating);
			$edittag->save;
			IdleCheck($ID);
		}
		delete $Editing{$ID};
		$dialog->destroy;
	});
}

sub SongInfo
{	my $ID = shift;
	my $table=Gtk2::Table->new(8,2);
	my $sw=Gtk2::ScrolledWindow->new;
	 $sw->set_shadow_type('etched-in');
	 $sw->set_policy('automatic','automatic');
	 $sw->add_with_viewport($table);
	$table->{ID}=$ID;
	my $row=0;
	my @fields=Songs::InfoFields;
	for my $col (@fields)
	{	my $lab1=Gtk2::Label->new;
		my $lab2=$table->{$col}=Gtk2::Label->new;
		#$lab1->set_markup('<b>'.PangoEsc(Songs::FieldName($col)).' :</b>');
		$lab1->set_text( Songs::FieldName($col).' :');
		$lab1->set_padding(5,0);
		$lab1->set_alignment(1,.5);
		$lab2->set_alignment(0,.5);
		$lab2->set_line_wrap(1);
		$lab2->set_selectable(TRUE);
		$table->attach_defaults($lab1,0,1,$row,$row+1);
		$table->attach_defaults($lab2,1,2,$row,$row+1);
		$row++;
	}
	my $fillsub=sub
	 {	my ($table,$IDs,$fields)=@_;
		my $ID=$table->{ID};
		return if $IDs && !(grep $_==$ID, @$IDs);
		#$table->{$_}->set_text(Songs::Display($ID,$_)) for @$fields;
		$table->{$_}->set_markup('<b>'.Songs::DisplayEsc($ID,$_).'</b>') for grep $table->{$_}, @$fields;
	 };
	Watch($table, SongsChanged=> $fillsub);
	$fillsub->($table,undef,\@fields);
	return $sw;
}

sub SongsChanged
{	warn "SongsChanged @_\n" if $debug;
	my ($IDs,$fields)=@_;
	$Filter::CachedList=undef;
	if (defined $SongID && (grep $SongID==$_,@$IDs)) # if current song is part of the changed songs
	{	$ListPlay->UpdateLock if $TogLock && OneInCommon([Songs::Depends($TogLock)],$fields);
		HasChanged('CurSong',$SongID);
	}
	for my $group (keys %SelID)
	{	HasChangedSelID($group,$SelID{$group}) if grep $SelID{$group}==$_, @$IDs;
	}
	HasChanged(SongsChanged=>$IDs,$fields);
	GMB::ListStore::Field::changed(@$fields);
}
sub SongAdd		#only called from IdleLoop
{	my $ID=Songs::New($_[0]);
	return unless defined $ID;
	push @ToAdd_IDsBuffer,$ID;
	$ProgressNBSongs++;
	#IdleDo('0_AddIDs',30000,\&SongAdd_Real);
}
sub SongAdd_Real
{	return unless @ToAdd_IDsBuffer;
	my @IDs=@ToAdd_IDsBuffer; #FIXME remove IDs already in Library	#FIXME check against master filter ?
	@ToAdd_IDsBuffer=();
	$Filter::CachedList=undef;
	AA::IDs_Changed();
	$Library->Push(\@IDs);
	HasChanged(SongsAdded=>\@IDs);
}
sub SongsRemove
{	my $IDs=$_[0];
	$Filter::CachedList=undef;
	for my $ID (@$IDs, map("L$_", @$IDs)) { $::Editing{$ID}->destroy if exists $::Editing{$ID};}
	AA::IDs_Changed();
	SongArray::RemoveIDsFromAll($IDs);
	$RecentPos-- while $RecentPos && $Recent->[$RecentPos-1]!=$SongID; #update RecentPos if needed

	HasChanged(SongsRemoved=>$IDs);
	Songs::AddMissing($IDs);
}

#FIXME check completely replaced then remove
=toremove
sub AddMissing #FIXME check completely replaced then remove
{	my $ID=$_[0];
	if ($_[1]) { my $ref=\$Songs[$ID][SONG_MISSINGSINCE]; if ($$ref && $$ref eq 'l') {$Songs[$ID][SONG_LENGTH]=''} $$ref=$DAYNB; }
	my $staat=join "\x1D", grep defined, map $Songs[$ID][$_],@STAAT;
	push @{ $MissingSTAAT{$staat} },$ID;
	$MissingCount++;
}
sub RemoveMissing #FIXME check completely replaced then remove
{	my $ID=$_[0];
	my $staat=join "\x1D", grep defined, map $Songs[$ID][$_],@STAAT;
	my $aref=$MissingSTAAT{$staat};
	if (!$aref)	{warn "unregistered missing song";return}
	elsif (@$aref>1){ @$aref=grep $_ != $ID, @$aref; }
	else		{ delete $MissingSTAAT{$staat}; }
	$Songs[$ID][SONG_MISSINGSINCE]=undef;
	$MissingCount--;
}
sub CheckMissing #FIXME check completely replaced then remove
{	my $songref=$_[0];
	my $staat=join "\x1D", grep defined, map $songref->[$_],@STAAT;
	my $IDs=$MissingSTAAT{$staat};
	return undef unless $IDs;
	for my $oldID (@$IDs)
	{	my $m;
		for my $f (SONG_FILE,SONG_PATH)
		{	$m++ if $songref->[$f] eq $Songs[$oldID][$f];
		}
		next unless $m;	#must have the same path or the same filename
		# Found -> remove old ID, copy non-written song fields to new ID
		my $olddir =$Songs[$oldID][SONG_PATH];
		my $oldfile=$Songs[$oldID][SONG_FILE];
		warn "Found missing song, formerly '".$olddir.SLASH.$oldfile."'\n";# if $debug;
		RemoveMissing($oldID);
		$songref->[$_]=$Songs[$oldID][$_] for SONG_ADDED,SONG_LASTPLAY,SONG_NBPLAY,SONG_LASTSKIP,SONG_NBSKIP,SONG_RATING,SONG_LABELS,SONG_LENGTH; #SONG_LENGTH is copied to avoid the need to check length for mp3 without VBR header
		if (keys %{ $GetIDFromFile{$olddir} } ==1)
		{	delete $GetIDFromFile{$olddir};
		}
		else { delete $GetIDFromFile{$olddir}{$oldfile} }
		$Songs[$oldID]=undef;
		return 1;
	}
	return undef;
}

sub AddRadio
{	my ($url,$name,$noradiolist)=@_;
	$name=$url unless defined $name;
	$url='http://'.$url unless $url=~m#^\w+://#;
	my ($path,$file)= $url=~m#^(\w+://[^/]+)/?(.*)$#;
	return unless $path;
	my @song;
	$song[SONG_TITLE]=$name;
	$song[SONG_FILE]=$song[SONG_UFILE]=$file;
	$song[SONG_PATH]=$song[SONG_UPATH]=$path;
	$song[SONG_LENGTH]=0;
	$song[SONG_ARTIST]="radio";
	$song[SONG_ALBUM]="radio";
	$song[SONG_ADDED]=time;
	$song[SONG_MISSINGSINCE]='R'; #could be better, identify track as a radio
	push @Songs,\@song;
	my $ID=$#Songs;
	if ($noradiolist) {$song[SONG_MISSINGSINCE].='T'}
	else
	{	push @Radio, $ID;
		HasChanged('RadioList');
	}
	return $ID;
}
=cut

sub OpenFiles
{	my @IDs;
	for my $f (split / /,$_[1])
	{	if ($f=~m#^http://#) { }#push @IDs,AddRadio($f,1); }
		else
		{	$f=decode_url($f);
			my $l=ScanFolder($f);
			push @IDs, @$l if ref $l;
		}
	}
	Select(song=>'first',play=>1,staticlist => \@IDs) if @IDs;
}

sub Uris_to_IDs
{	my @urls=split / +/,$_[0];
	$_=decode_url($_) for @urls;
	my @IDs=FolderToIDs(1,@urls);
	return \@IDs;
}

sub FolderToIDs
{	my ($recurse,@dirs)=@_;
	s#^file://## for @dirs;
	s/$QSLASH$//o for @dirs;
	s/$QSLASH{2,}/$QSLASH/go for @dirs;
	my @files;
	MakeScanRegex() unless $ScanRegex;
	while (defined(my $dir=shift @dirs))
	{	if (-d $dir)
		{	opendir my($DIRH),$dir or warn "Can't read folder $dir : $!\n";
			my @list= map $dir.SLASH.$_, grep !m#^\.#, readdir $DIRH;
			push @files, grep -f && m/$ScanRegex/, @list;
			push @dirs, grep -d, @list   if $recurse;
			closedir $DIRH;
		}
		elsif (-f $dir) { push @files,$dir; }
	}
	my @IDs;
	for my $file (@files)
	{	my $ID=Songs::FindID($file);# check if missing => check if modified
		unless (defined $ID)
		{	$ID=Songs::New($file);
		}
		push @IDs,$ID if defined $ID;
	}
	#my @IDs=grep defined map FindID($dir.SLASH.$_), @files;
	return @IDs;
}

sub MakeScanRegex	#FIXME
{	my $s;
	if ($Options{ScanPlayOnly})
	{	my %ext; $ext{$_}=1 for ($PlayNext_package||$Play_package)->supported_formats;
		$ext{$_}=1 for grep $ext{$Alias_ext{$_}}, keys %Alias_ext;
		$s=join '|',keys %ext;
	}
	else { $s='mp3|ogg|oga|flac|mpc|ape|wv|m4a|m4b'; } #FIXME find a better way
	$ScanRegex=qr/\.(?:$s)$/i;
}

sub ScanFolder
{	warn "ScanFolder(@_)\n";
	my $dir=$_[0];
	$dir=~s#^file://##;
	MakeScanRegex() unless $ScanRegex;
	Songs::Build_IDFromFile() unless $Songs::IDFromFile;
	$ScanProgress_cb ||= Glib::Timeout->add(500,\&ScanProgress_cb);
	my @files;
	if (-d $dir)
	{	opendir my($DIRH),$dir or warn "Can't read folder $dir : $!\n";
		@files=readdir $DIRH;
		closedir $DIRH;
	}
	elsif (-f $dir && $dir=~s/$QSLASH([^$QSLASH]+)$//o)
	{	@files=($1);
	}
	#my @toadd;
	for my $file (@files)
	{	next if $file=~m#^\.#;		# skip . .. and hidden files/folders
		my $path_file=$dir.SLASH.$file;
		#if (-d $path_file) { push @ToScan,$path_file; next; }
		if (-d $path_file)
		{	#next if $notrecursive;
			if (-l $path_file)
			{	my $real=readlink $path_file;
				next if exists $FollowedDirs{$real};
				$FollowedDirs{$real}=undef;
			}
			else
			{	next if exists $FollowedDirs{$path_file};
				$FollowedDirs{$path_file}=undef;
			}
			push @ToScan,$path_file;
			next;
		}
		#if ($file=~m/\.(?:jpeg|jpg|png|gif)$/i) { push @pictures,$file; next; }
		next unless $file=~$ScanRegex;
		#my $ID=Songs::FindID($path_file);
		my $ID=$Songs::IDFromFile->{$dir}{$file};
		if (defined $ID)
		{	next unless Songs::Get($ID,'missing');
			Songs::Set($ID,missing => 0);
			push @ToReRead,$ID;	#or @ToCheck ? 
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
}

sub CheckProgress_cb
{	my $init=$_[0];
	if (@ToCheck)
 	{	$CheckProgress_cb=@ToCheck if @ToCheck> ($CheckProgress_cb||0);
		my $max=$CheckProgress_cb;
 		my $checked=$max-@ToCheck;
		::Progress('check',	title	=> _"Checking songs",
					aborthint=>_"Stop checking",
					bartext	=> "$checked / $max",
					current	=> $checked, end=> $max,
					abortcb	=> sub { @ToCheck=(); },
			) unless $init;
		return 1;
 	}
	else
	{	::Progress('check', abort=>1);
		return $CheckProgress_cb=0;
	}
}
sub AbortScan
{	@ToScan=(); undef %FollowedDirs;
}
sub ScanProgress_cb
{	my ($title,$details,$bartext,$current,$total,$abortcb);
	if (@ToScan || @ToAdd_Files)
	{	$title=_"Scanning";
		$details=__("%d song added","%d songs added", $ProgressNBSongs);
		$bartext= __("%d folder","%d folders", $ProgressNBFolders);
		$current=$ProgressNBFolders;
		$total=@ToScan + $ProgressNBFolders;
		$abortcb= \&AbortScan;
	}
	elsif (@$LengthEstimated)
	{	$title=_"Checking length/bitrate";
		$details= _"for files without a VBR header";
		$Lengthcheck_max=@$LengthEstimated if @$LengthEstimated > $Lengthcheck_max;
		$current=$Lengthcheck_max-@$LengthEstimated;
		$total=$Lengthcheck_max;
		$bartext="$current / $total";
	}
	else
	{	::Progress('scan', abort=>1);
		return $ScanProgress_cb=0;
	}
	Progress('scan', title => $title, details=>$details, current=>$current, end=>$total, abortcb=>$abortcb, aborthint=> _"Stop scanning", bartext=>$bartext );
	return 1;
}

#FIXME check completely replaced then remove
=toremove
sub ScanFolder_old
{	my $notlibrary=$_[0];
	my $dir= $notlibrary || shift @ToScan;
	warn "Scanning $dir\n" if $debug;
	$ProgressNBFolders++ unless $notlibrary;
	my @pictures;
	unless ($ScanRegex)
	{	my @list= $Options{ScanPlayOnly}? ($PlayNext_package||$Play_package)->supported_formats
						: qw/mp3 ogg oga flac mpc ape wv/; #FIXME find a better way,  wvc
		my $s=join '|',@list;
		$ScanRegex=qr/\.(?:$s)$/i;
	}
	my @files;
	if (-d $dir)
	{	opendir my($DIRH),$dir or warn "Can't read folder $dir : $!\n";
		@files=readdir $DIRH;
		closedir $DIRH;
	}
	elsif (-f $dir && $dir=~s/$QSLASH([^$QSLASH]+)$//o)
	{	@files=($1);
	}
	my $utf8dir=filename_to_utf8displayname($dir);
	my @toadd;
	for my $file (@files)
	{	next if $file=~m/^\./;		# skip . .. and hidden files/folders
		my $path_file=$dir.SLASH.$file;
		#warn "slash is utf8\n" if utf8::is_utf8(SLASH);
		#if (-d $path_file) { push @ToScan,$path_file; next; }
		if (-d $path_file)
		{	next if $notlibrary;
			if (-l $path_file)
			{	my $real=readlink $path_file;
				next if exists $FollowedDirs{$real};
				$FollowedDirs{$real}=undef;
			}
			else
			{	next if exists $FollowedDirs{$path_file};
				$FollowedDirs{$path_file}=undef;
			}
			push @ToScan,$path_file;
			next;
		}
		if ($file=~m/\.(?:jpeg|jpg|png|gif)$/i) { push @pictures,$file; next; }
		next unless $file=~$ScanRegex;
		my $rID=\$GetIDFromFile{$dir}{$file};
		if (defined $$rID)
		{	next unless ($Songs[$$rID][SONG_MISSINGSINCE] && $Songs[$$rID][SONG_MISSINGSINCE]=~m/^\d/) || $notlibrary;
		}
		else
		{	my @song;#=('')xSONGLAST;	#FIXME only to avoid undef warnings
			#$song[SONG_NBPLAY]=0;
			@song[SONG_UFILE,SONG_UPATH,SONG_ADDED,SONG_FILE,SONG_PATH]=(filename_to_utf8displayname($file),$utf8dir,time,$file,$dir);
			#_utf8_on($song[SONG_FILE]); # lie to perl so it doesn't get upgraded
			#_utf8_on($song[SONG_PATH]); #  to utf8 when saving with '>:utf8'
			push @Songs,\@song;
			$$rID=$#Songs;
		}
		push @toadd,$$rID;
	}
	if ($notlibrary)
	{	$_->[SONG_MODIF] or $_->[SONG_MISSINGSINCE]=$DAYNB for @Songs[@toadd]; # init MISSING_SINCE for new songs
		@toadd= grep SongCheck($_), @toadd;
		return \@toadd;
	}
	push @ToAdd_Files,@toadd;
	undef %FollowedDirs unless @ToScan;
	$CoverCandidates=[$dir,\@pictures] if @pictures;
}

sub CheckCover
{	my ($dir,$pictures)=@$CoverCandidates; $CoverCandidates=undef;
	return unless exists $GetIDFromFile{$dir};
	my $h=$GetIDFromFile{$dir};
	my ($first,@songs)=grep !($_->[SONG_MISSINGSINCE] && $_->[SONG_MISSINGSINCE]=~m/^\d/), map $Songs[$_],values %$h;
	my $alb=$first->[SONG_ALBUM];
	return unless defined $alb;
	return if $alb=~m/^<Unknown>/;
	for my $song (@songs)
	{	my $alb2=$song->[SONG_ALBUM];
		return if !defined $alb2 || $alb2 ne $alb;
	}
	#FIXME could check if all the songs of the album are in this dir
	my $cover=AAPicture::GetPicture(album=>$alb);
	return if $cover || (defined $cover && $cover eq '0');

	my $match=$alb; $match=~s/[^0-9A-Za-z]+/ /g; $match=~tr/A-Z/a-z/;
	$match=undef if $match eq ' ';
	my (@words)= $alb=~m/([0-9A-Za-z]{4,})/g; tr/A-Z/a-z/ for @words;
	my $hiscore; my $best;
	for my $file (@$pictures)
	{	my $score=0;
		my $letters=$file; $letters=~s/\.[^.]+$//;
		$letters=~s/[^0-9A-Za-z]+/ /g; $letters=~tr/A-Z/a-z/;
		if (defined $match)
		{	if    ($letters eq $match)		{$score+=100}
			elsif ($letters=~m/\b\Q$match\E\b/)	{$score+=100}
			else { $letters=~m/\Q$_\E/ && $score++ for @words; }
		}
		$score+=2 if $letters=~m/\b(?:cover|front|folder|thumb|thumbnail)\b/;
		$score-- if $letters=~m/\b(?:back|cd|inside|booklet)\b/;
		#next unless defined $score;
		next if $hiscore && $hiscore>$score;
		$hiscore=$score; $best=$file;
	}
	return unless $best;
	AAPicture::SetPicture(album=>$alb, $dir.SLASH.$best);
	warn "found cover for $alb : $best)\n" if $debug;
}
=cut

sub AboutDialog
{	my $dialog=Gtk2::AboutDialog->new;
	$dialog->set_version(VERSIONSTRING);
	$dialog->set_copyright("Copyright © 2005-2009 Quentin Sculo");
	#$dialog->set_comments();
	$dialog->set_license("Released under the GNU General Public Licence version 3\n(http://www.gnu.org/copyleft/gpl.html)");
	$dialog->set_website('http://gmusicbrowser.sourceforge.net/');
	$dialog->set_authors('Quentin Sculo <squentin@free.fr>');
	$dialog->set_artists('tango icon theme : Jean-Philippe Guillemin');
	$dialog->set_translator_credits("French : Quentin Sculo and Jonathan Fretin\nHungarian : Zsombor\nSpanish : Martintxo, Juanjo and Elega\nGerman : vlad <donvla\@users.sourceforge.net> & staubi <staubi\@linuxmail.org>\nPolish : tizzilzol team\nSwedish : Olle Sandgren\nChinese : jk");
	$dialog->signal_connect( response => sub { $_[0]->destroy if $_[1] eq 'cancel'; }); #used to worked without this, see http://mail.gnome.org/archives/gtk-perl-list/2006-November/msg00035.html
	$dialog->show_all;
}

sub PrefDialog
{	if ($OptionsDialog) { $OptionsDialog->present; return; }
	$OptionsDialog=my $dialog = Gtk2::Dialog->new (_"Settings", undef,[],
				'gtk-about' => 1,
				'gtk-close' => 'close');
	$dialog->set_default_response ('close');
	#$dialog->action_area->pack_end(NewIconButton('gtk-about',_"about",\&AboutDialog),FALSE,FALSE,2);
	SetWSize($dialog,'Pref');

	my $notebook = Gtk2::Notebook->new;
	$notebook->append_page( PrefLibrary()	,Gtk2::Label->new(_"Library"));
	#$notebook->append_page( PrefLabels()	,Gtk2::Label->new(_"Labels"));
	$notebook->append_page( PrefAudio()	,Gtk2::Label->new(_"Audio"));
	$notebook->append_page( PrefLayouts()	,Gtk2::Label->new(_"Layouts"));
	$notebook->append_page( PrefMisc()	,Gtk2::Label->new(_"Misc."));
	$notebook->append_page( PrefPlugins()	,Gtk2::Label->new(_"Plugins"));
	$notebook->append_page( PrefKeys()	,Gtk2::Label->new(_"Keys"));
	$notebook->append_page( PrefTags()	,Gtk2::Label->new(_"Tags"));

	$dialog->vbox->pack_start($notebook,TRUE,TRUE,4);

	$dialog->signal_connect( response => sub
		{	if ($_[1] eq '1') {AboutDialog();return};
			$OptionsDialog=undef;
			$_[0]->destroy;
		});
	$dialog->show_all;
	#$dialog->set_position('center-always');
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
	$Tooltips->set_tip($key_entry,_"Press a key or a key combination");
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
		if (defined $keyname && !grep($_ eq $keyname,qw/Shift_L Control_L Alt_L Super_L ISO_Level3_Shift Multi_key Menu Control_R Shift_R/))
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
					grep !defined $Command{$_}[3] || ref $Command{$_}[3],
					keys %Command
				  });
	my $vsg=Gtk2::SizeGroup->new('vertical');
	$vsg->add_widget($_) for $key_entry,$combo;
	$combochanged=sub
	 {	my $cmd=$combo->get_value;
		my $child=$entry_extra->child;
		$entry_extra->remove($child) if $child;
		if ($Command{$cmd}[2])
		{	$Tooltips->set_tip($entry_extra,$Command{$cmd}[2]);
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
	my $plug_box;
	my $plugin;

	my $sub_update= sub
	 {	return unless $plugin;
		my $pref=$Plugins{$plugin};
		if ($plug_box && $plug_box->parent) { $plug_box->parent->remove($plug_box); }
		my $title='<b>'.PangoEsc( $pref->{longname}||$pref->{name} ).'</b>';
		$plugtitle->set_markup($title);
		$plugdesc->set_text( $pref->{desc} );
		if (my $error=$pref->{error})
		{	$plug_box=Gtk2::Label->new;
			$error=PangoEsc($error);
			$error=~s#(\(\@INC contains: .*)#<small>$1</small>#s;
			$plug_box->set_markup('<b>'._("Error :")."</b>\n$error");
			$plug_box->set_line_wrap(1);
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
	 {	#my ($cell, $path_str) = @_;
		my $path = Gtk2::TreePath->new($_[1]);
		my $iter = $store->get_iter($path);
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
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($treeview);
	return $sw;
}
sub SetDefaultOptions
{	my $prefix=shift;
	while (my ($key,$val)=splice @_,0,2)
	{	$Options{$prefix.$key}=$val unless defined $Options{$prefix.$key};
	}
}

sub PrefAudio
{	my $vbox=Gtk2::VBox->new(FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my ($radio_gst,$radio_123,$radio_mp,$radio_ice)=NewPrefRadio('AudioOut', sub
		{	my $p=$Options{AudioOut};
			return if $PlayPacks{$p}==$Play_package;
			$PlayNext_package=$PlayPacks{$p};
			SwitchPlayPackage() unless defined $PlayTime;
			$ScanRegex=undef;
		},
		gstreamer		=> 'Play_GST',
		'mpg123/ogg123/...' => 'Play_123',
		mplayer			=> 'Play_mplayer',
		_"icecast server"	=> sub {$Options{use_GST_for_server}? 'Play_GST_server' : 'Play_Server'},
		);

	#123
	my $vbox_123=Gtk2::VBox->new (FALSE, 2);
	#my $hbox1=NewPrefCombo(Device => [qw/default oss alsa esd arts sun/], text => _"output device :", sizeg1=>$sg1,sizeg2=> $sg2);
	my $adv1=PrefAudio_makeadv('Play_123','123');
	$vbox_123->pack_start($_,FALSE,FALSE,2) for $radio_123,$adv1;

	#gstreamer
	my $vbox_gst=Gtk2::VBox->new (FALSE, 2);
	if (exists $PlayPacks{Play_GST})
	{	my $hbox2=NewPrefCombo(gst_sink => Play_GST->supported_sinks, text => _"output device :", sizeg1=>$sg1, sizeg2=> $sg2);
		my $EQbut=Gtk2::Button->new(_"Open Equalizer");
		$EQbut->signal_connect(clicked => sub { OpenSpecialWindow('Equalizer'); });
		my $EQcheck=NewPrefCheckButton(gst_use_equalizer => _"Use Equalizer", sub { HasChanged('Equalizer'); });
		$sg1->add_widget($EQcheck);
		$sg2->add_widget($EQbut);
		my $EQbox=Hpack($EQcheck,$EQbut);
		$EQbox->set_sensitive(0) unless $PlayPacks{Play_GST} && $PlayPacks{Play_GST}{EQ};
		my $RGbox=Play_GST::RGA_PrefBox($sg1,$sg2);
		my $adv2=PrefAudio_makeadv('Play_GST','gstreamer');
		my $albox=Gtk2::Alignment->new(0,0,1,1);
		$albox->set_padding(0,0,15,0);
		$albox->add(Vpack($hbox2,$EQbox,$RGbox,$adv2));
		$vbox_gst->pack_start($_,FALSE,FALSE,2) for $radio_gst,$albox;
	}
	else
	{	$vbox_gst->pack_start($_,FALSE,FALSE,2) for $radio_gst,Gtk2::Label->new(_"GStreamer module not loaded.");
	}

	#icecast
	my $vbox_ice=Gtk2::VBox->new(FALSE, 2);
	$Options{use_GST_for_server}=0 unless $PlayPacks{Play_GST_server};
	my $usegst=NewPrefCheckButton(use_GST_for_server => _"Use gstreamer",sub {$radio_gst->signal_emit('toggled');},_"without gstreamer : one stream per file, one connection at a time\nwith gstreamer : one continuous stream, multiple connection possible");
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

	$vbox->pack_start($_,FALSE,FALSE,2) for
		$vbox_gst, Gtk2::HSeparator->new,
		$vbox_123, Gtk2::HSeparator->new,
		$vbox_mp,  Gtk2::HSeparator->new,
		$vbox_ice, Gtk2::HSeparator->new,
		NewPrefCheckButton(IgnorePlayError => _"Ignore playback errors",undef,_"Skip to next song if an error occurs");
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
				$_[0]->set_markup('<small>'._("supports : ").$list.'</small>') if $list;
			}) if $package;
		$hbox->pack_start($label,TRUE,TRUE,4);
	}
	if (1)
	{	my $label=Gtk2::Label->new;
		$label->set_markup('<small>'._('advanced options').'</small>');
		my $but=Gtk2::Button->new;
		$but->add($label);
		$but->set_relief('none');
		$hbox->pack_start($but,TRUE,TRUE,4);
		$but->signal_connect(clicked =>	sub #create dialog
		 {	my $but=$_[0];
			if ($but->{dialog} && !$but->{dialog}{destroyed}) { $but->{dialog}->present; return; }
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

sub PrefMisc
{	my $vbox=Gtk2::VBox->new (FALSE, 2);

	#Default rating
	my $DefRating=NewPrefSpinButton('DefaultRating',sub
		{ IdleDo('0_DefaultRating',500,\&Songs::UpdateDefaultRating);
		},10,0,0,100,10,20,_"Default rating :");

	my $checkR1=NewPrefCheckButton(RememberPlayFilter => _"Remember last Filter/Playlist between sessions");
	my $checkR3=NewPrefCheckButton( RememberPlayTime  => _"Remember playing position between sessions");
	my $checkR2=NewPrefCheckButton( RememberPlaySong  => _"Remember playing song between sessions",undef,undef,$checkR3);

	#Proxy
	my $ProxyCheck=NewPrefCheckButton(Simplehttp_Proxy => _"Connect through a proxy",undef,undef,
			Hpack(	NewPrefEntry(Simplehttp_ProxyHost => _"Proxy host :"),
				NewPrefEntry(Simplehttp_ProxyPort => _"port :"),
			)
		);

	#xdg-screensaver
	my $screensaver=NewPrefCheckButton(StopScreensaver => _"Disable screensaver when fullscreen and playing",undef,_"requires xdg-screensaver");
	$screensaver->set_sensitive(0) unless findcmd('xdg-screensaver');
	#Diacritic_sort
	my $diasort=NewPrefCheckButton(Diacritic_sort => _"Diacritic sort",undef,_"Makes case insensitive sort puts accented letters right after their unaccented version.\n(Significantly slower)");
	#shutdown
	my $shutentry=NewPrefEntry(Shutdown_cmd => _"Shutdown command :", tip => _"Command used when\n'turn off computer when queue empty'\nis selected");
	#artist splitting
	my %split=
	(	' & |, |;'	=> _"' & ' and ', ' and ';'",
		' & '		=> "' & '",
		' \\+ '		=> "' + '",
		'; *'		=> "';'",
		'$'		=> _"no splitting",
	);
	my $asplit=NewPrefCombo(ArtistSplit => \%split, text => _"Split artist names on (needs restart) :");


	#packing
	$vbox->pack_start($_,FALSE,FALSE,1) for $checkR1,$checkR2,$DefRating,$ProxyCheck,$diasort,$asplit,$screensaver,$shutentry;
	return $vbox;
}

sub PrefLayouts
{	my $vbox=Gtk2::VBox->new (FALSE, 2);

	#Tray
	my $traytiplength=NewPrefSpinButton('TrayTipTimeLength',undef,100,0,0,100000,100,1000,_"Display tray tip for",'ms');
	my $checkT2=NewPrefCheckButton(CloseToTray => _"Close to tray");
	my $checkT3=NewPrefCheckButton(ShowTipOnSongChange => _"Show tray tip on song change",undef,undef,$traytiplength);
	my $checkT4=NewPrefCheckButton(TrayTipDelay => _"Delay tray tip popup on mouse over",\&SetTrayTipDelay);
	my $checkT1=NewPrefCheckButton( UseTray => _"Show tray icon",
					sub { &CreateTrayIcon; },undef,
					Vpack($checkT2,$checkT4,$checkT3)
					);
	$checkT1->set_sensitive($Gtk2TrayIcon);

	#layouts
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $layoutT=NewPrefCombo(LayoutT=> Layout::get_layout_list('T'), text => _"Tray tip window layout :",	sizeg1=>$sg1,sizeg2=>$sg2, tree=>1);
	my $layout =NewPrefCombo(Layout => Layout::get_layout_list('G'), text =>_"Player window layout :", 	sizeg1=>$sg1,sizeg2=>$sg2, tree=>1, cb => sub {CreateMainWindow();}, );
	my $layoutB=NewPrefCombo(LayoutB=> Layout::get_layout_list('B'), text =>_"Browser window layout :",	sizeg1=>$sg1,sizeg2=>$sg2, tree=>1);
	my $layoutF=NewPrefCombo(LayoutF=> Layout::get_layout_list('F'), text =>_"Full screen layout :",	sizeg1=>$sg1,sizeg2=>$sg2, tree=>1);
	my $layoutS=NewPrefCombo(LayoutS=> Layout::get_layout_list('S'), text =>_"Search window layout :",	sizeg1=>$sg1,sizeg2=>$sg2, tree=>1);

	#fullscreen button
	my $fullbutton=NewPrefCheckButton(AddFullscreenButton => _"Add a fullscreen button", sub { Layout::WidgetChangedAutoAdd('Fullscreen'); },_"Add a fullscreen button to layouts that can accept extra buttons");


	my $icotheme=NewPrefCombo(IconTheme=> GetIconThemesList(), text =>_"Icon theme :", sizeg1=>$sg1,sizeg2=>$sg2, cb => \&LoadIcons);

	#packing
	$vbox->pack_start($_,FALSE,FALSE,1) for $layout,$layoutB,$layoutT,$layoutF,$layoutS,$checkT1,$fullbutton,$icotheme;
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
	$warning->set_markup('<b>'.PangoEsc(_"Warning : these are advanced options, don't change them unless you know what you are doing.").'</b>');
	$warning->set_line_wrap(1);
	my $checkv4=NewPrefCheckButton('TAG_write_id3v2.4',_"Write ID3v2.4 tags",undef,_"Use ID3v2.4 instead of ID3v2.3, ID3v2.3 are probably better supported by other softwares");
	my $checklatin1=NewPrefCheckButton(TAG_use_latin1_if_possible => _"Use latin1 encoding if possible in id3v2 tags",undef,_"the default is utf16 for ID3v2.3 and utf8 for ID3v2.4");
	my $check_unsync=NewPrefCheckButton(TAG_no_desync => _"Do not unsynchronise id3v2 tags",undef,_"itunes doesn't support unsynchronised tags last time I checked, mostly affect tags with pictures");
	my @Encodings=grep $_ ne 'null', Encode->encodings(':all');
	my $id3v1encoding=NewPrefCombo(TAG_id3v1_encoding => \@Encodings, text => _"Encoding used for id3v1 tags :");
	my $nowrite=NewPrefCheckButton('TAG_nowrite_mode',_"Do not write the tags",undef,_"Will not write the tags except with the advanced tag editing dialog. The changes will be kept in the library instead.\nWarning, the changes for a song will be lost if the tag is re-read.");
	my $autocheck=NewPrefCheckButton('TAG_auto_check_current',_"Auto-check current song for modification",undef,_"Automatically check if the file for the current song has changed. And remove songs not found from the library.");
	my $noid3v1=NewPrefCheckButton('TAG_id3v1_noautocreate',_"Do not create an id3v1 tag in mp3 files",undef,_"Only affect mp3 files that do not already have an id3v1 tag");

	$vbox->pack_start($_,FALSE,FALSE,1) for $warning,$checkv4,$checklatin1,$check_unsync,$id3v1encoding,$noid3v1,$nowrite,$autocheck;
	return $vbox;
}

sub AskRenameFolder
{	my $parent=shift; #parent is in utf8
	$parent=~s/([^$QSLASH]+)$//o;
	my $old=$1;
	my $dialog=Gtk2::Dialog->new(_"Rename folder", undef,
			[qw/modal destroy-with-parent/],
			'gtk-ok' => 'ok',
			'gtk-cancel' => 'none');
	$dialog->set_default_response('ok');
	$dialog->set_border_width(3);
	my $entry=Gtk2::Entry->new;
	$entry->set_activates_default(TRUE);
	$entry->set_text($old);
	$dialog->vbox->pack_start( Gtk2::Label->new(_"Rename this folder to :") ,FALSE,FALSE,1);
	$dialog->vbox->pack_start($entry,FALSE,FALSE,1);
	$dialog->show_all;
	{	last unless $dialog->run eq 'ok';
		my $new=$entry->get_text;
		last if $new eq '';
		last if $old eq $new;
		last if $new=~m/$QSLASH/o;	#FIXME allow moving folder
		$old=filename_from_unicode($parent.$old.SLASH);
		$new=filename_from_unicode($parent.$new.SLASH);
		-d $new and ErrorMessage(__x(_"{folder} already exists",folder=>$new)) and last; #FIXME use an error dialog
		rename $old,$new
			or ErrorMessage(__x(_"Renaming {oldname}\nto {newname}\nfailed : {error}",oldname=>$old,newname=>$new,error=>$!)) and last; #FIXME use an error dialog
		UpdateFolderNames($old,$new);
	}
	$dialog->destroy;
}

sub MoveFolder #FIXME implement
{	my $parent=shift;
	$parent=~s/([^$QSLASH]+)$//o;
	my $folder=$1;
	my $new=ChooseDir(_"Move folder to",$parent);
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
	s/$QSLASH+$//o for $oldpath,$newpath;
	my $pattern= "^\Q$oldpath\E(?:".SLASH.'|$)';
	my $renamed=Songs::FilterAll('path:m:'.$pattern);
	return unless @$renamed;

	$pattern=qr/^\Q$oldpath\E/;
	my @newpath;
	for my $ID (@$renamed)
	{	my $path= Songs::Get($ID,'path');
		$path=~s/$pattern/$newpath/;	#CHECKME check if works with broken filenames
		push @newpath,$path;
	}
	Songs::Set($renamed,'@path'=>\@newpath);

	AAPicture::UpdatePixPath($oldpath,$newpath);
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
	$selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$rmdbut->set_sensitive($sel);
		});
	$rmdbut->set_sensitive(FALSE);
	$rmdbut->signal_connect( clicked => sub
	{	my $iter=$selection->get_selected;
		return unless defined $iter;
		my $s= $store->get($iter,0);
		@{$Options{LibraryPath}}=grep $_ ne $s, @{$Options{LibraryPath}};
		HasChanged(options=>'LibraryPath');
	});

	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type ('etched-in');
	$sw->set_policy ('automatic', 'automatic');
	$sw->add($treeview);

	my $Cscanall=NewPrefCheckButton(ScanPlayOnly => _"Do not add songs that can't be played",sub {$ScanRegex=undef});
	my $CScan=NewPrefCheckButton(StartScan => _"Search for new songs on startup");
	my $CCheck=NewPrefCheckButton(StartCheck => _"Check for updated/deleted songs on startup");
	my $BScan= NewIconButton('gtk-refresh',_"scan now", sub { IdleScan();	});
	my $BCheck=NewIconButton('gtk-refresh',_"check now",sub { IdleCheck();	});
	my $label=Gtk2::Label->new(_"Folders to search for new songs");
	my $table=Gtk2::Table->new(2,2,FALSE);
	$table->attach_defaults($CScan, 0,1,1,2);
	$table->attach_defaults($BScan, 1,2,1,2);
	$table->attach_defaults($CCheck,0,1,0,1);
	$table->attach_defaults($BCheck,1,2,0,1);
	$table->attach_defaults($Cscanall, 0,2,2,3);

	my $reorg=Gtk2::Button->new(_"Reorganize files and folders");
	$reorg->signal_connect( clicked => sub
	{	return unless @$Library;
		DialogMassRename(@$Library);
	});

	my $vbox=Vpack( 1,$label,
			'_',$sw,
			[$addbut,$rmdbut,'-',$reorg],
			$table );
	return $vbox;
}
sub ChooseAddPath
{	my $addtolibrary=shift;
	my @dirs=ChooseDir(_"Choose folder to add",undef,undef,'LastFolder_Add',1);
	@dirs=map url_escape($_), @dirs;
	AddPath($addtolibrary,@dirs);
}
sub AddPath
{	my ($addtolibrary,@dirs)=@_;
	s#^file://## for @dirs;
	@dirs= grep !m#^\w+://#, @dirs;
	my $changed;
	for my $dir (@dirs)
	{	$dir=~s/$QSLASH$//o unless $dir eq SLASH || $dir=~m/^\w:.$/;
		my $d=decode_url($dir);
		if (!-d $d) { ScanFolder($d); next }
		IdleScan($d);
		next unless $addtolibrary;
		next if (grep $dir eq $_,@{$Options{LibraryPath}});
		push @{$Options{LibraryPath}},$dir;
		$changed=1;
	}
	HasChanged(options=>'LibraryPath') if $changed;
}

sub ToggleLabel #maybe do the toggle in SetLabels #FIXME
{	my ($label,$ID,$on)=@_;
	return unless defined $ID && defined $label;
	my $add=[]; my $rm=[];
	unless (defined $on)
	{	$on= !Songs::IsSet($ID,label => $label);
	}
	if ($on) { $add=[$label] }
	else	 { $rm =[$label] }
	SetLabels([$ID],$add,$rm);
}

sub SetLabels	#FIXME move to Songs::
{	my ($IDs,$toadd,$torm)=@_;
	my @args;
	push @args,'+label',$toadd if $toadd && @$toadd;
	push @args,'-label',$torm if $torm  && @$torm;
	Songs::Set($IDs,@args);
}

sub RemoveLabel		#FIXME ? label specific
{	my ($field,$gid)=@_;
	my $label= Songs::Gid_to_Display($field,$gid);
	#my $IDlist= Songs::AllFilter( MakeFilterFromGID('label',$gid) );
	my $IDlist= Songs::MakeFilterFromGID($field,$gid)->filter;
	if (my $nb=@$IDlist)
	{	my $dialog = Gtk2::MessageDialog->new
			( undef, #FIXME
			  [qw/modal destroy-with-parent/],
			  'warning','ok-cancel',
			  __("This label is set for %d song.","This label is set for %d songs.",$nb)."\n".
			  __x(_"Are you sure you want to delete the '{label}' label ?", label => $label)
			);
		$dialog->show_all;
		if ($dialog->run ne 'ok') {$dialog->destroy;return;}
		$dialog->destroy;
		SetLabels($IDlist,undef,[$label]);
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
		SetLabels($l,[$new],[$old]);
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
		for my $f (@{SortedLabels()})
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
					( undef, #FIXME
					  [qw/modal destroy-with-parent/],
					  'warning','ok-cancel','%s',
					  __("This label is set for %d song.","This label is set for %d songs.",$nb)."\n".
					  __x("Are you sure you want to delete the '{label}' label ?", label => $label)
					);
				$dialog->show_all;
				if ($dialog->run ne 'ok') {$dialog->destroy;return;}
				my $l= Songs::AllFilter( 'label:~:'.$label );
				SetLabels($l,undef,[$label]);
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
{	my ($key,$sub,@text_val)=@_;
	my $init=$Options{$key};
	$init='' unless defined $init;
	my $cb=sub
		{	return unless $_[0]->get_active;
			my $val=$_[1];
			$val=&$val if ref $val;
			SetOption($key,$val);
			&$sub if $sub;
		};
	my $radio; my @radios;
	while (defined (my $text=shift @text_val))
	{	my $val=shift @text_val;
		push @radios, $radio=Gtk2::RadioButton->new($radio,$text);
		$radio->signal_connect(toggled => $cb,$val);
		$val=&$val if ref $val;
		$radio->set_active(1) if $val eq $init;
	}
	return @radios;
}
sub NewPrefCheckButton
{	my ($key,$text,$sub,$tip,$widget,$toolitem,$horizontal,$sizeg)=@_;
	my $init= $Options{$key};
	my $check=Gtk2::CheckButton->new($text);
	$sizeg->add_widget($check) if $sizeg;
	$check->set_active(1) if $init;
	$check->signal_connect( toggled => sub
	{	my $val=($_[0]->get_active)? 1 : 0;
		SetOption($_[1],$val);
		$_[0]{albox}->set_sensitive( $_[0]->get_active )  if $_[0]{albox};
		&$sub if $sub;
	},$key);
	$Tooltips->set_tip($check,$tip) if defined $tip;
	my $return=$check;
	if ($widget)
	{	if ($horizontal)
		{	$return=Hpack($check,$widget);
		}
		else
		{	$check->{albox}=my $albox=Gtk2::Alignment->new(0,0,1,1);
			$albox->set_padding(0,0,15,0);
			$albox->add($widget);
			$widget=$albox;
			$return=Vpack($check,$albox);
		}
		$check->{child}=$widget;
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
	my ($cb,$sg1,$sg2,$tip,$hide,$expand)=@opt{qw/cb sizeg1 sizeg2 tip hide expand/};
	my $widget=my $entry=Gtk2::Entry->new;
	if (defined $text)
	{	$widget=Gtk2::HBox->new;
		my $label=Gtk2::Label->new($text);
		$label->set_alignment(0,.5);
		$widget->pack_start($label,FALSE,FALSE,2);
		$widget->pack_start($entry,$expand,$expand,2);
		$sg1->add_widget($label) if $sg1;
	}
	$sg2->add_widget($entry) if $sg2;

	$Tooltips->set_tip($entry, $tip) if defined $tip;
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
		$widget->append_text($_) for @$hist;
	}
	my $button=NewIconButton('gtk-open');
	my $hbox=Gtk2::HBox->new;
	my $hbox2=Gtk2::HBox->new(FALSE,0);
	$hbox2->pack_start($widget,TRUE,TRUE,0);
	$hbox2->pack_start($button,FALSE,FALSE,0);
	$hbox->pack_start($_,FALSE,FALSE,2)  for $label,$hbox2;
	$label->set_alignment(0,.5);

	if ($sg1) { $sg1->add_widget($label); $label->set_alignment(0,.5); }
	if ($sg2) { $sg2->add_widget($hbox2); }

	$Tooltips->set_tip($entry, $tip) if defined $tip;
	$entry->set_text(filename_to_utf8displayname($Options{$key})) if defined $Options{$key};

	my $busy;
	$entry->signal_connect( changed => sub
	{	return if $busy;
		SetOption( $key, filename_from_unicode( $_[0]->get_text ));
		&$cb if $cb;
	});
	$button->signal_connect( clicked => sub
	{	my $file= $folder? ChooseDir($text,$Options{$key}) : undef;
		return unless $file;
		# could simply $entry->set_text(), but wouldn't work with filenames with broken encoding
		SetOption( $key, $file);
		$busy=1; $entry->set_text(filename_to_utf8displayname($file)); $busy=undef;
		&$cb if $cb;
	});
	$entry->signal_connect( destroy => sub { PrefSaveHistory($key_history,$_[0]->get_text); } ) if $key_history;
	return $hbox;
}
sub NewPrefSpinButton
{	my ($key,$sub,$climb_rate,$digits,$min,$max,$stepinc,$pageinc,$text1,$text2,$sg1,$sg2,$tip,$wrap)=@_;
	$text1=Gtk2::Label->new($text1) if defined $text1;
	$text2=Gtk2::Label->new($text2) if defined $text2;
	my $adj=Gtk2::Adjustment->new($Options{$key}||=0,$min,$max,$stepinc,$pageinc,0);
	my $spin=Gtk2::SpinButton->new($adj,$climb_rate,$digits);
	$spin->set_wrap(1) if $wrap;
	$adj->signal_connect(value_changed => sub
	 {	SetOption( $_[1], $_[0]->get_value);
		&$sub if $sub;
	 },$key);
	$Tooltips->set_tip($spin, $tip) if defined $tip;
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
	my ($text,$cb0,$sg1,$sg2,$toolitem,$tree)=@opt{qw/text cb sizeg1 sizeg2 toolitem tree/};
	my $cb=sub
		{	SetOption($key,$_[0]->get_value);
			&$cb0 if $cb0;
		};
	my $class= $tree ? 'TextCombo::Tree' : 'TextCombo';
	my $combo= $class->new( $list, $Options{$key}, $cb );
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
	if (defined $toolitem)
	{	$widget= $combo->make_toolitem($toolitem,$key,$widget);
	}
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
	$Tooltips->set_tip($but,$tip) if defined $tip;
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
	if (defined $newname)	{$saved->{$newname}=delete $saved->{$name}; HasChanged('SavedLists',$name,'renamedto',$newname); $name=$newname; }
	elsif (defined $val)	{$saved->{$name}= SongArray->new($val);}
	else			{delete $saved->{$name}; HasChanged('SavedLists',$name,'remove'); return}
	HasChanged('SavedLists',$name);
}

sub Watch
{	my ($object,$key,$sub)=@_;
	unless ($object) { push @{$EventWatchers{$key}},$sub; return } #for permanent watch
	warn "watch $key $object\n" if $debug;
	if ($object->{'WatchUpdate_'.$key})
	{	warn "Warning : Object $object is already watching event $key => previous watch replaced\n";
	}
	else { push @{$EventWatchers{$key}},$object; weaken($EventWatchers{$key}[-1]); }
	$object->{'WatchUpdate_'.$key}=$sub;
	$object->signal_connect(destroy => \&UnWatch,$key) unless ref $object eq 'HASH' || !$object->isa('Gtk2::Object');
}
sub UnWatch
{	my ($object,$key)=@_;
	warn "unwatch $key $object\n" if $debug;
	@{$EventWatchers{$key}}=grep defined && $_ != $object, @{$EventWatchers{$key}};
	delete $object->{'WatchUpdate_'.$key};
}
sub UnWatch_all #for when destructing non-Gtk2::Object
{	my $object=shift;
	UnWatch($object,$_) for map m/^WatchUpdate_(.+)/, keys %$object;
}

sub HasChanged
{	my ($key,@args)=@_;
	return unless $EventWatchers{$key};
	my @list=@{$EventWatchers{$key}};
	warn "HasChanged $key -> updating @list\n" if $debug;
	for my $r ( @list )
	{	my ($sub,$o)= ref $r eq 'CODE' ? ($r) : ($r->{'WatchUpdate_'.$key},$r);
		$sub->($o,@args) if $sub;
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
		#$Filters{$group}[0]||=$Filters{$group}[1+1]||= Filter->none;#FIXME implement a "none" filter
		#$Filters{$group}[0]||=$Filters{$group}[1+1]||=Filter->new;
	}
	IdleDo('1_init_filter'.$group,0, \&InitFilter, $group);
	$object->signal_connect(destroy => \&UnWatchFilter,$group) unless ref $object eq 'HASH' || !$object->isa('Glib::Object');
}
sub UnWatchFilter
{	my ($object,$group)=@_;
	warn "unwatch filter $group $object\n" if $debug;
	if ($group=~m/:[\w.]+$/)
	{	unless (--$Related_FilterWatchers{$group})
		{	delete $Related_FilterWatchers{$group};
		}
	}
	delete $object->{'UpdateFilter'.$group};
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
	{	$Progress{$pid}=$self;
		$self->{end}+=delete $self->{add} if $self->{add};
	}
	else		#update existing
	{	$Progress{$pid}{$_}=$self->{$_} for keys %$self;
		$self= $Progress{$pid};
	}
	$self->{current}++ if delete $self->{inc};
	$self->{fraction}= ($self->{current}||=0) / ($self->{end}||1);

	if (my $w=$self->{widget}) { $w->set_fraction( $self->{fraction} ); }
	delete $Progress{$pid} if $self->{abort} or $self->{current}==$self->{end}; # finished
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
	$win->present;
	$win->set_skip_taskbar_hint(FALSE) unless $win->{skip_taskbar_hint};
}

sub PopupLayout
{	my ($layout,$widget)=@_;
	return if $widget && $widget->{PoppedUpWindow};
	my $popup=Layout::Window::Popup->new($layout,$widget);
}

sub CreateTrayIcon
{	if ($TrayIcon)
	{	return if $Options{UseTray};
		$TrayIcon->destroy;
		$TrayIcon=undef;
		return;
	}
	elsif (!$Options{UseTray} || !$Gtk2TrayIcon)
	 {return}
	if (0) {&CreateTrayIcon_StatusIcon}
	$TrayIcon= Gtk2::TrayIcon->new(PROGRAM_NAME);
	my $eventbox=Gtk2::EventBox->new;
	my $img=Gtk2::Image->new_from_file($TrayIconFile);

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
	$eventbox->signal_connect(scroll_event => \&::ChangeVol);
	$eventbox->signal_connect(button_press_event => sub
		{	$LEvent=$_[1];
			my $b=$LEvent->button;
			if	($b==3) { &TrayMenuPopup }
			elsif	($b==2) { &PlayPause}
			else		{ &ShowHide }
			1;
		});
	SetTrayTipDelay();
	Layout::Window::Popup::set_hover($eventbox);

	$TrayIcon->show_all;
	#Watch($eventbox,'CurSong', \&UpdateTrayTip);
	#&UpdateTrayTip($eventbox);
}
sub SetTrayTipDelay
{	return unless $TrayIcon;
	$TrayIcon->child->{hover_delay}= $Options{TrayTipDelay} ? 900 : 1;
}
sub TrayMenuPopup
{	my @TrayMenu=
 (	{ label=> _"Play", code => \&PlayPause,	test => sub {!defined $TogPlay},stockicon => 'gtk-media-play' },
	{ label=> _"Pause",code => \&PlayPause,	test => sub {defined $TogPlay},	stockicon => 'gtk-media-pause' },
	{ label=> _"Stop", code => \&Stop,	stockicon => 'gtk-media-stop' },
	{ label=> _"Next", code => \&NextSong,	stockicon => 'gtk-media-next' },
	{ label=> _"Recently played", submenu => sub { my $m=::ChooseSongs(undef,::GetPrevSongs(5)); }, stockicon => 'gtk-media-previous' },
	{ label=> sub {$TogLock && $TogLock eq 'first_artist'? _"Unlock Artist" : _"Lock Artist"},	code => sub {ToggleLock('first_artist');} },
	{ label=> sub {$TogLock && $TogLock eq 'album' ? _"Unlock Album"  : _"Lock Album"},	code => sub {ToggleLock('album');} },
	{ label=> _"Windows",	code => \&PresentWindow,	submenu_ordered_hash =>1,
		submenu => sub {  [map { $_->layout_name => $_ } grep $_->isa('Layout::Window'), Gtk2::Window->list_toplevels];  }, },
	{ label=> sub { IsWindowVisible($MainWindow) ? _"Hide": _"Show"}, code => \&ShowHide },
	{ label=> _"Fullscreen",	code => \&::ToggleFullscreenLayout,	stockicon => 'gtk-fullscreen' },
	{ label=> _"Settings",		code => \&PrefDialog,	stockicon => 'gtk-preferences' },
	{ label=> _"Quit",		code => \&Quit,		stockicon => 'gtk-quit' },
 );
	my $traytip=$TrayIcon->child->{PoppedUpWindow};
	$traytip->DestroyNow if $traytip;
	$TrayIcon->{NoTrayTip}=1;
	my $m=PopupContextMenu(\@TrayMenu,{});
	$m->signal_connect( selection_done => sub {$TrayIcon->{NoTrayTip}=undef});
	$m->show_all;
	$m->popup(undef,undef,\&::menupos,undef,$LEvent->button,$LEvent->time);
}
sub ShowTraytip
{	return 0 if !$TrayIcon || $TrayIcon->{NoTrayTip};
	Layout::Window::Popup::Popup($TrayIcon->child,$_[0]);
}

sub windowpos	# function to position window next to clicked widget ($event can be a widget)
{	my ($win,$event)=@_;
	return (0,0) unless $event;
	my $h=$win->size_request->height;		# height of window to position
	my $w=$win->size_request->width;		# width of window to position
	my $screen=$event->get_screen;
	my $monitor=$screen->get_monitor_at_window($event->window);
	my ($xmin,$ymin,$monitorwidth,$monitorheight)=$screen->get_monitor_geometry($monitor)->values;
	my $xmax=$xmin + $monitorwidth;
	my $ymax=$ymin + $monitorheight;

	my ($x,$y)=$event->window->get_origin;		# position of the clicked widget on the screen
	my ($dx,$dy)=$event->window->get_size;		# width,height of the clicked widget
	if ($event->isa('Gtk2::Widget') && $event->no_window)
	{	(my$x2,my$y2,$dx,$dy)=$event->allocation->values;
		$x+=$x2;$y+=$y2;
	}
	my $ycenter=0;
	if ($x+$dx/2+$w/2 < $xmax && $x+$dx/2-$w/2 >$xmin){ $x-=int($w/2-$dx/2); }	# centered
	elsif ($x+$dx+$w > $xmax)	{ $x=max($xmax-$w,$xmin) }		# right side
	else				{ $x=$xmin; }				# left side
	if ($ycenter && $y+$h/2 < $ymax && $y-$h/2 >$ymin){ $y-=int($h/2) }	# y center
	elsif ($dy+$y+$h > $ymax)	{ $y=max($y-$h,$ymin) }			# display above the widget
	else				{ $y+=$dy; }				# display below the widget
	return $x,$y;
}

#sub UpdateTrayTip #not used
#{	my ($song,$artist,$album)=Songs::Display($SongID,qw/title artist album/);
	#$Tooltips->set_tip($_[0], __x( _"{song}\nby {artist}\nfrom {album}", song => $song, artist => $artist, album => $album) );
#}

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
{	my (@windows)=grep $_->isa('Layout::Window') && $_->{showhide} && $_!=$MainWindow, Gtk2::Window->list_toplevels;
	if ( IsWindowVisible($MainWindow) )
	{	#hide
		#warn "hiding\n";
		for my $win ($MainWindow,@windows)
		{	next unless $win;
			$win->{saved_position}=join 'x',$win->get_position;
			$win->iconify;
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
		$MainWindow->present;
	}
}

package GMB::Edit;
use Gtk2;
use base 'Gtk2::Dialog';

my %refs;

INIT
{ %refs=
  (	Filter	=> [	_"Filter edition",		'SavedFilters',		_"saved filters",
			_"name of the new filter",	_"save filter as",	_"delete selected filter"	],
	Sort	=> [	_"Sort mode edition",		'SavedSorts',		_"saved sort modes",
			_"name of the new sort mode",	_"save sort mode as",	_"delete selected sort mode"	],
	WRandom	=> [	_"Random mode edition",		'SavedWRandoms',	_"saved random modes",
			_"name of the new random mode", _"save random mode as", _"delete selected random mode"],
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
		{	$name=0;
			$name++ while exists $self->{hash}{_"noname".$name};
			$name=_"noname".$name;
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
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type ('etched-in');
	$sw->set_policy ('automatic', 'automatic');
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
	$::Tooltips->set_tip($NameEntry,$typedata->[3] );
	$::Tooltips->set_tip($butsave,	$typedata->[4] );
	$::Tooltips->set_tip($butrm,	$typedata->[5]);

	$self->{entry}=$NameEntry;
	$self->{store}=$store;
	$self->{treeview}=$treeview;
	$self->Fill;
	my $package='GMB::Edit::'.$type;
	my $editobject=$package->new($self,$init);
	$sw->add($treeview);
	$self->vbox->add( ::Hpack( [[0,$NameEntry,$butsave],'_',$sw,$butrm], '_',$editobject) );
	if ($self->{save_name_entry}) { $editobject->pack_start(::Hpack(Gtk2::Label->new('Save as : '),$self->{save_name_entry}), ::FALSE,::FALSE, 2); $self->{save_name_entry}->set_text($name); }
	$self->{editobject}=$editobject;

	::SetWSize($self,'Edit'.$type);
	$self->show_all;

	$treeview->get_selection->unselect_all;
	$treeview->signal_connect(cursor_changed => \&cursor_changed_cb,$self);

	return $self;
}

sub name_edited_cb
{	my ($cell, $path_string, $newname,$self) = @_;
	my $store=$self->{store};
	my $iter=$store->get_iter( Gtk2::TreePath->new($path_string) );
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
use Gtk2;
use base 'Gtk2::VBox';
use constant
{  TRUE  => 1, FALSE => 0,
   C_NAME => 0,	C_POS => 1, C_VAL1 => 2, C_VAL2	=> 3,
};

sub new
{	my ($class,$dialog,$init) = @_;
	my $self = bless Gtk2::VBox->new, $class;

	my $store=Gtk2::TreeStore->new(('Glib::String')x4);
	$self->{treeview}=
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_reorderable(TRUE);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes(
		filters => Gtk2::CellRendererText->new,
		text => C_NAME) );
	my $sw = Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');

	my $butadd= ::NewIconButton('gtk-add',_"Add");
	my $butadd2=::NewIconButton('gtk-add',_"Add multiple condition");
	my $butrm=  ::NewIconButton('gtk-remove',_"Remove");
	$butadd->signal_connect( clicked => \&Add_cb,$self);
	$butadd2->signal_connect(clicked => \&Add_cb,$self);
	$butrm->signal_connect(  clicked => \&Rm_cb, $self);
	$butrm->set_sensitive(FALSE);
	$butadd->{filter}='title:s:';
	$butadd2->{filter}="(\x1Dtitle:s:\x1D)";

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

	$treeview->signal_connect(cursor_changed => \&cursor_changed_cb, $self);

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
{	my ($button,$self)=@_;
	my $path=($self->{treeview}->get_cursor)[0];
	$path||=Gtk2::TreePath->new_first;
	$self->Set( $button->{filter}, $path);
}
sub Rm_cb
{	my ($button,$self)=@_;
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
	$self->Set('title:s:') unless $store->get_iter_first;
	return $oldpath;
}

sub cursor_changed_cb
{	my ($treeview,$self)=@_;
	my $fbox=$self->{fbox};
	my $store=$treeview->get_model;
	my ($path,$co)=$_[0]->get_cursor;
	return unless $path;
	#warn "row : ",$path->to_string," / col : $co\n";
	$fbox->remove($fbox->child) if $fbox->child;
	my $iter=$store->get_iter($path);
	my $box;
	if ($store->iter_has_child($iter))
	{	$box=Gtk2::HBox->new;
		my $state=$store->get($iter,C_POS);
		my $group;
		for my $ao ('&','|')
		{	my $name=($ao eq '&')? _"All of :":_"Any of :";
			my $b=Gtk2::RadioButton->new($group,$name);
			$group=$b unless $group;
			$b->set_active(1) if $ao eq $state;
			$b->signal_connect( toggled => sub
			{	return unless $_[0]->get_active;
				$store->set($iter,C_NAME,$name,C_POS,$ao);
			});
			$box->add($b);
		}
	}
	else
	{	$box=FilterBox->new
		(	undef,
			sub
			{	warn "filter : @_\n" if $::debug;
				my ($pos,@vals)=@_;
				$store->set($iter,
					C_NAME,FilterBox::posval2desc($pos,@vals),
					C_POS,$pos,C_VAL1,$vals[0], C_VAL2,$vals[1]);
			},
			$store->get($iter,C_POS,C_VAL1,C_VAL2)
		);
	}
	$fbox->add($box);
	$fbox->show_all;
}

sub Set
{	my ($self,$filter,$startpath,$startpos)=@_;
	$filter=$filter->{string} if ref $filter;
	$filter='' unless defined $filter;
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;

	my $iter;
	if ($startpath)
	{	$iter=$store->get_iter($startpath);
		my $parent=$store->iter_parent($iter);
		if (!$parent && !$store->iter_has_child($iter)) #add a root
		{	$parent=$store->prepend(undef);
			$store->set($parent,C_NAME,_"All of :",C_POS,'&');
			my $new=$store->append($parent);
			$store->set($new,$_,$store->get($iter,$_)) for C_NAME,C_POS,C_VAL1,C_VAL2;
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
		{	$iter=&$createrowsub($iter);
			my ($ao,$text)=($f eq '(|')? ('|',_"Any of :") : ('&',_"All of :");
			$store->set($iter,C_NAME,$text,C_POS,$ao);
		}
		else
		{ next if $f eq '';
		  my ($pos,@vals)=FilterBox::filter2posval($f);
		  unless ($pos) { warn "Invalid filter : $f\n"; next; }
		  my $leaf=&$createrowsub($iter);
		  $firstnewpath=$store->get_path($leaf) unless $firstnewpath;
		  $store->set($leaf, C_NAME,FilterBox::posval2desc($pos,@vals),	C_POS,$pos, C_VAL1,$vals[0], C_VAL2,$vals[1]);
		}
	}
	unless ($store->get_iter_first)	#default filter if no/invalid filter
	{	my ($pos,@vals)=FilterBox::filter2posval('title:s:');
		$store->set($store->append(undef), C_NAME,FilterBox::posval2desc($pos,@vals),	C_POS,$pos, C_VAL1,$vals[0], C_VAL2,$vals[1]);
	}

	$firstnewpath||=Gtk2::TreePath->new_first;
	my $path_string=$firstnewpath->to_string;
	if ($firstnewpath->get_depth>1)	{ $firstnewpath->up; $treeview->expand_row($firstnewpath,TRUE); }
	else	{ $treeview->expand_all }
	$treeview->set_cursor( Gtk2::TreePath->new($path_string) );
}

sub Result
{	my ($self,$startpath)=@_;
	my $store=$self->{treeview}->get_model;
	my $filter='';
	my $depth=0;
	my $next=$startpath? $store->get_iter($startpath) : $store->get_iter_first;
	while (my $iter=$next)
	{	my ($pos,@vals)=$store->get($iter,C_POS,C_VAL1,C_VAL2);
		if ( $next=$store->iter_children($iter) )
		{	$filter.="($pos\x1D" unless $store->iter_n_children($iter)<2;
			$depth++;
		}
		else
		{	$filter.=FilterBox::posval2filter($pos,@vals)."\x1D";
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
use Gtk2;
use base 'Gtk2::VBox';
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
	$treeview2->append_column
		( Gtk2::TreeViewColumn->new_with_attributes
		  ('Order',Gtk2::CellRendererPixbuf->new,'stock-id',2)
		);
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
		$lab->set_markup('<b>'.::PangoEsc($label).'</b>');
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
			return 0 unless $path && $column && $column==$case_column;
			my $store2=$treeview2->get_model;
			my $iter=$store2->get_iter($path);
			return 0 unless $iter;
			my $i=$store2->get_value($iter,3);
			return 0 unless $i;
			my $tip= $i==SENSITIVE ? _"Case sensitive" : _"Case insensitive";
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
use Gtk2;
use base 'Gtk2::VBox';
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
	$::Tooltips->set_tip($histogram,'');
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

sub cleanup	#FIXME find a simpler way to do it
{	my $self=shift;
	delete $ToDo{'2_WRandom'.$self};
}

sub Set
{	my ($self,$sort)=@_; warn $sort;
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
	if ($queue) { ::IdleDo('2_WRandom'.$self,500,\&Redraw, $self); return }
	delete $::ToDo{'2_WRandom'.$self};
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
	return if $::ToDo{'2_WRandom'.$self};
	return unless ::OneInCommon($fields,$self->{depend_fields});
	return if $IDs && !@{ $ListPlay->AreIn($IDs) };
	$self->Redraw(1);
}
sub SongArray_cb
{	my ($self,$array,$action)=@_;
	return if $::ToDo{'2_WRandom'.$self};
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
	$::Tooltips->set_tip($histogram, "$range : ".::__('%d song','%d songs',$nb) );
	1;
}

sub AddRow
{	my ($self,$params)=@_;
	my $table=$self->{table};
	my $row=$self->{row}++;
	my $deleted;
	my ($inverse,$weight,$type,$extra)=$params=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)$/;
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
	$::Tooltips->set_tip($button,_"Remove this rule");
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
	$::Tooltips->set_tip($check,$check_tip);
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
	$frame->{label}->set_markup( '<small><i>'._("ex : ").::PangoEsc(Random->MakeExample($p,$::SongID)).'</i></small>' ) if defined $::SongID;
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
	$self->{example_label}->set_markup( '<small><i>'.::__x( _"example (selected song) : {score}  ({chances})", score =>$v, chances => $prob). "</i></small>" );
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

package FilterBox;
use Gtk2;
use base 'Gtk2::HBox';

my (@FLIST,%TYPEREGEX,%ENTRYTYPE);
my %PosRe;

INIT
{ %TYPEREGEX=
  (	s => '[^\x1D]*',
	r => '[^\x1D]*',
	n => '[0-9]*',
	d => '(?:\d+)|(?:\d\d\d\d-\d\d?-\d\d?)',
	a => '[-0-9]*[smhdwMy]',	#see %DATEUNITS
	b => '[-0-9]*[bkm]',		#see %SIZEUNITS
	l => '.+'
  );
  %ENTRYTYPE=
  (	s => 'FilterEntryString',
	r => 'FilterEntryString',
	n => 'FilterEntryNumber',
	d => 'FilterEntryDate',
	a => 'FilterEntryUnit',
	b => 'FilterEntryUnit',
	f => 'FilterEntryCombo',
	g => 'FilterEntryCombo',
	l => 'FilterEntryCombo',
  );
  @FLIST=
  (	_"Title",
	[	_"contains %s",		 'title:s:%s',
		_"doesn't contain %s",	'-title:s:%s',
		_"is %s",		 'title:~:%s',
		_"is not %s",		'-title:~:%s',
		_"match regexp %r",	 'title:m:%r',
		_"doesn't match regexp %r",'-title:m:%r',
	],
	_"Artist",
	[	_"contains %s",		 'artist:s:%s',
		_"doesn't contain %s",	'-artist:s:%s',
		_"is %s",		 'artist:~:%s',
		_"is not %s",		'-artist:~:%s',
		_"match regexp %r",	 'artist:m:%r',
		_"doesn't match regexp %r",'-artist:m:%r',
	],
	_"Album",
	[	_"contains %s",		 'album:s:%s',
		_"doesn't contain %s",	'-album:s:%s',
		_"is %s",		 'album:e:%s',
		_"is not %s",		'-album:e:%s',
		_"match regexp %r",	 'album:m:%r',
		_"doesn't match regexp %r",'-album:m:%r',
	],
	_"Year",
	[	_"is %n",	'year:e:%n',
		_"isn't %n",	'-year:e:%n',
		_"is before %n",'year:<:%n',
		_"is after %n",	'year:>:%n',
	],
	_"Track",
	[	_"is %n",		'track:e:%n',
		_"is not %n",		'-track:e:%n',
		_"is more than %n",	'track:>:%n',
		_"is less than %n",	'track:<:%n',
	],
	_"Disc",
	[	_"is %n",		'disc:e:%n',
		_"is not %n",		'-disc:e:%n',
		_"is more than %n",	'disc:>:%n',
		_"is less than %n",	'disc:<:%n',
	],
	_"Rating",
	[	_"is %n( %)",		'rating:e:%n',
		_"is not %n( %)",	'-rating:e:%n',
		_"is more than %n( %)",	'rating:>:%n',
		_"is less than %n( %)",	'rating:<:%n',
		_"is between %n( and )%n( %)",'rating:b:%n %n',
	],
	_"Length",
	[	_"is more than %n( s)",		'length:>:%n',
		_"is less than %n( s)",		'length:<:%n',
		_"is between %n( and )%n( s)",	'length:b:%n %n',
	],
	_"Size",
	[	_"is more than %b",		'size:>:%b',
		_"is less than %b",		'size:<:%b',
		_"is between %b( and )%b",	'size:b:%b %b',
	],
	_"played",
	[	_"more than %n( times)",	'playcount:>:%n',
		_"less than %n( times)",	'playcount:<:%n',
		_"exactly %n( times)",		'playcount:e:%n',
		_"exactly not %n( times)",	'-playcount:e:%n',
		_"between %n( and )%n",		'playcount:b:%n %n',
	],
	_"skipped",
	[	_"more than %n( times)",	'skipcount:>:%n',
		_"less than %n( times)",	'skipcount:<:%n',
		_"exactly %n( times)",		'skipcount:e:%n',
		_"exactly not %n( times)",	'-skipcount:e:%n',
		_"between %n( and )%n",		'skipcount:b:%n %n',
	],
	_"last played",
	[	_"less than %a( ago)",	'lastplay:>:%a',
		_"more than %a( ago)",	'lastplay:<:%a',
		_"before %d",		'lastplay:<:%d',
		_"after %d",		'lastplay:>:%d',
		_"between %d( and )%d",	'lastplay:b:%d %d',
		#_"on %d",		'lastplay:o:%d',
	],
	_"last skipped",
	[	_"less than %a( ago)",	'lastskip:>:%a',
		_"more than %a( ago)",	'lastskip:<:%a',
		_"before %d",		'lastskip:<:%d',
		_"after %d",		'lastskip:>:%d',
		_"between %d( and )%d",	'lastskip:b:%d %d',
		#_"on %d",		'lastskip:o:%d',
	],
	_"modified",
	[	_"less than %a( ago)",	'modif:>:%a',
		_"more than %a( ago)",	'modif:<:%a',
		_"before %d",		'modif:<:%d',
		_"after %d",		'modif:>:%d',
		_"between %d( and )%d",	'modif:b:%d %d',
		#_"on %d",		'modif:o:%d',
	],
	_"added",
	[	_"less than %a( ago)",	'added:>:%a',
		_"more than %a( ago)",	'added:<:%a',
		_"before %d",		'added:<:%d',
		_"after %d",		'added:>:%d',
		_"between %d( and )%d",	'added:b:%d %d',
		#_"on %d",		'added:o:%d',
	],
	_"The [most/less]",
	[	_"%n most played",	'playcount:h:%n',
		_"%n less played",	'playcount:t:%n',
		_"%n last played",	'lastplay:h:%n',
		_"%n not played for the longest time",	'lastplay:t:%n', #FIXME description
		_"%n most skipped",	'skipcount:h:%n',
		_"%n less skipped",	'skipcount:t:%n',
		_"%n last skipped",	'lastskip:h:%n',
		_"%n not skipped for the longest time",	'lastskip:t:%n',
		_"%n longest",		'length:h:%n',
		_"%n shortest",		'length:t:%n',
		_"%n last added",	'added:h:%n',
		_"%n first added",	'added:t:%n',
		_"All but the [most/less]%n",
		[	_"most played",		'-playcount:h:%n',
			_"less played",		'-playcount:t:%n',
			_"last played",		'-lastplay:h:%n',
			_"not played for the longest time",	'-lastplay:t:%n',
			_"most skipped",	'-skipcount:h:%n',
			_"less skipped",	'-skipcount:t:%n',
			_"last skipped",	'-lastskip:h:%n',
			_"not skipped for the longest time",	'-lastskip:t:%n',
			_"longest",		'-length:h:%n',
			_"shortest",		'-length:t:%n',
			_"last added",		'-added:h:%n',
			_"first added",		'-added:t:%n',
		],
	],
	_"Genre",
	[	_"is %g",		'genre:~:%s',
		_"isn't %g",		'-genre:~:%s',
		_"contains %s",		'genre:s:%s',
		_"doesn't contain %s",	'-genre:s:%s',
		_"(: )none",		'genre:e:',
		_"(: )has one",		'-genre:e:',
	],
	_"Label",
	[	_"%f is set",		 'label:~:%s',
		_"%f isn't set",	'-label:~:%s',
		_"contains %s",		 'label:s:%s',
		_"doesn't contain %s",	'-label:s:%s',
		_"(: )none",		'label:e:',
		_"(: )has one",		'-label:e:',
	],
	_"Filename",
	[	_"contains %s",		 'file:s:%s',
		_"doesn't contain %s",	'-file:s:%s',
		_"is %s",		 'file:e:%s',
		_"is not %s",		'-file:e:%s',
		_"match regexp %r",		 'file:m:%r',
		_"doesn't match regexp %r",	'-file:m:%r',
	],
	_"Folder",
	[	_"contains %s",		 'path:s:%s',
		_"doesn't contain %s",	'-path:s:%s',
		_"is %s",		 'path:e:%s',
		_"is not %s",		'-path:e:%s',
		_"is in %s",		 'path:i:%s',
		_"is not in %s",	'-path:i:%s',
		_"match regexp %r",		 'path:m:%r',
		_"doesn't match regexp %r",	'-path:m:%r',
	],
	_"Comment",
	[	_"contains %s",		 'comment:s:%s',
		_"doesn't contain %s",	'-comment:s:%s',
		_"is %s",		 'comment:e:%s',
		_"is not %s",		'-comment:e:%s',
		_"match regexp %r",		 'comment:m:%r',
		_"doesn't match regexp %r",	'-comment:m:%r',
	],
	_"Version",
	[	_"contains %s",		 'version:s:%s',
		_"doesn't contain %s",	'-version:s:%s',
		_"is %s",		 'version:e:%s',
		_"is not %s",		'-version:e:%s',
		_"match regexp %r",		 'version:m:%r',
		_"doesn't match regexp %r",	'-version:m:%r',
	],
	_"is in list %l",	 ':l:%l',
	_"is not in list %l",	'-:l:%l',
	_"file format",
	[	_"is",
		[	_"a mp3 file",		'filetype:m:^mp3',
			_"an ogg file",		'filetype:m:^ogg',
			_"a flac file",		'filetype:m:^flac',
			_"a musepack file",	'filetype:m:^mpc',
			_"a wavepack file",	'filetype:m:^wv',
			_"an ape file",		'filetype:m:^ape',
			_"mono",		'channel:e:1',
			_"stereo",		'channel:e:2',
		],
		_"is not",
		[	_"a mp3 file",		'-filetype:m:^mp3',
			_"an ogg file",		'-filetype:m:^ogg',
			_"a flac file",		'-filetype:m:^flac',
			_"a musepack file",	'-filetype:m:^mpc',
			_"a wavepack file",	'-filetype:m:^wv',
			_"an ape file",		'-filetype:m:^ape',
			_"mono",		'-channel:e:1',
			_"stereo",		'-channel:e:2',
		],
		_"bitrate",
		[	_"is %n(kbps)",		 'bitrate:e:%n',
			_"isn't %n(kbps)",	'-bitrate:e:%n',
			_"is more than %n(kbps)",'bitrate:>:%n',
			_"is less than %n(kbps)",'bitrate:<:%n',
		],
		_"sampling rate",
		[	_"is %n(Hz)",		 'samprate:e:%n',
			_"isn't %n(Hz)",	'-samprate:e:%n',
			_"is more than %n(Hz)",	 'samprate:>:%n',
			_"is less than %n(Hz)",	 'samprate:<:%n',
			_"is not 44.1kHz",	'-samprate:e:44100',
		],
	],
  );
  my @todo=(\@FLIST);
  my @todopos=('');
  while (my $ref=shift @todo)
  {	my $pos=shift @todopos;
	for (my $i=0; $ref->[$i]; $i+=2)
	{ if (ref $ref->[$i+1] eq 'ARRAY')
	  {	push @todo,$ref->[$i+1];
		push @todopos,$pos.$i.' ';
	  }
	  else	#put in %PosRe a regex to find the value(s) and pos
	  {	my $f=$ref->[$i+1];
		my ($colcmd,$val)=$f=~m/^(-?\w*:[A-Za-z<>!~]:)(.*)$/;
		$val=~s/(\W)/\\$1/g;
		$val=~s/\\%([a-z])/'('.$TYPEREGEX{$1}.')'/ge;
		push @{ $PosRe{$colcmd} }, [qr/^$val$/, $pos.$i.' '];
	  }
	}
  }
}

sub new
{	my ($class,$activatesub,$changesub,$pos,@vals)=@_;#$init,$ao)=@_;
	my $self = bless Gtk2::HBox->new, $class;
#	$self->{init}=shift @$init;
#	$self->{ao}=$ao;
#	$self->{more}=$init;
#	my $menu=$self->make_submenu(\@FLIST);
#	Selected_cb($self->{item},$self);

	#$self->makemenus;
#	my ($pos,@vals)=filter2posval(shift @$init);
	$self->Set($pos,@vals);
	$self->{activatesub}=$activatesub;
	$self->{changesub}=$changesub;
	return $self;
}

sub addtomainmenu
{	my ($self,$label,$sub)=@_;
	push @{$self->{append}},[$label,$sub];
}

sub filter2posval
{	my $f=shift;
	my ($colcmd,$val)=$f=~m/^(-?\w*:[A-Za-z<>!~]:)(.*)$/;
	my $aref=$PosRe{$colcmd};
	for my $aref (@{ $PosRe{$colcmd} })
	{	my ($re,$pos)=@$aref;
		if (my @vals=$val=~m/$re/)
		{	return $pos,@vals;
		}
	}
	return undef;	#not found
}

sub posval2filter
{	my ($pos,@vals)=@_;
	my $ref=\@FLIST;
	for my $i (split / /,$pos)
	{	$ref=$ref->[$i+1];
	}
	my $filter=$ref;
	$filter=~s/%[a-z]/shift @vals/ge;
	return $filter;
}

sub posval2desc
{	my ($pos,@vals)=@_;
	my $string;
	my $ref=\@FLIST;
	for my $i (split / /,$pos)
	{	$string.=$ref->[$i].' ';
		$ref=$ref->[$i+1];
	}
	chop $string;
	$string=~s/\[[^]]*\]//g;	#remove what is between []
	$string=~tr/()//d;		#keep what is between ()
	my $desc;
	for my $s (split /(%[a-z])/,$string)
	{	if ($s=~m/^%[a-z]/)
		{	my $v=shift @vals;
			if	($s eq '%a') { $v=~s/([smhdwMy])$/' '.$::DATEUNITS{$1}[1]/e }
			elsif	($s eq '%b') { $v=~s/([bkm])$/    ' '.$::SIZEUNITS{$1}[1]/e }
			elsif	($s eq '%d') { $v=localtime($v) if $v=~m/^\d+$/ }
			$desc.=$v;
		}
		else {$desc.=$s;}
	}
	#$string=~s/%[a-z]/shift @vals/ge;
	return $desc;
}

sub makemenu
{	my ($self,$pos)=@_;
	my $ref=\@FLIST; $pos=~s/^ //;
	$ref=$ref->[$_+1] for split / /,$pos;
	my $menu=Gtk2::Menu->new;
	for (my $i=0; $ref->[$i]; $i+=2)
	{	my $name=$ref->[$i];
		$name=~s/\([^)]*\)//g;	#remove what is between ()
		$name=~s/ ?%[a-z]//g; $name=~s/^ +//;
		$name=~tr/[]//d;	#keep what is between []
		my $item=Gtk2::MenuItem->new($name);
		$item->{'pos'}=$pos.$i.' ';
		$menu->append($item);
		if (ref $ref->[$i+1] eq 'ARRAY')
		{	my $submenu= $self->makemenu($pos.$i.' ');
			$item->set_submenu($submenu);
		}
		else
		{	$item->signal_connect(activate => \&Selected_cb,$self);
		}
	}
	if ($pos eq '') #main menu
	{	for my $aref (@{$self->{append}})
		{	my ($label,$sub)=@$aref;
			my $item=Gtk2::MenuItem->new($label);
			$item->signal_connect(activate => $sub,$self);
			$menu->append($item);
		}
	}
	return $menu;
}

sub Selected_cb
{	#my $self=my $item=$_[0];
	#until ($self->isa(__PACKAGE__))
	#{	if ($self->isa('Gtk2::Menu')) {$self=$self->get_attach_widget}
	#	else {$self=$self->parent}warn $self;
	#	return unless $self;
	#}
	my ($item,$self)=@_;
	$self->Set($item->{'pos'});
}

sub Get
{	my $self=shift;
	my @vals;
	push @vals,$_->Get for @{ $self->{entry} };
	return $self->{'pos'},@vals;
}

sub Set
{	my ($self,$pos,@vals)=@_;
	$self->{'pos'}=$pos;
	if ($self->{entry} && !@vals)
	{	for my $entry ( @{$self->{entry}} )
		{ push @vals,$entry->Get };
	}
	$self->{entry}=[];
	$self->remove($_) for $self->get_children;
	my $menu='';
	my $ref=\@FLIST;
	for my $i (split / /,$pos)
	{	my $string=$ref->[$i];
		$string=~s/\[[^]]*\]//g;
		$string=~tr/()//d;
		my $first=1;
		for my $s (split /(%[a-z])/,$string)
		{	my $widget;
			if ($s=~m/^%([a-z])$/)
			{	$widget=$ENTRYTYPE{$1}->new(\&activate,\&changed,(shift @vals),$1);
				push @{ $self->{entry} },$widget;
				#$widget->Set( shift @vals ) if @vals;
			}
			elsif ($first && $s ne '')
			{	$widget=Gtk2::Button->new($s);
				$widget->set_relief('none');
				$widget->signal_connect( button_press_event => \&button_press_cb,$menu);
				$first=undef;
			}
			else
			{	$widget=Gtk2::Label->new($s);
			}
			$self->pack_start($widget,::FALSE,::FALSE, 0);
		}
		$menu.=$i.' ';
		$ref=$ref->[$i+1];
	}
	$self->show_all;
	$self->changed;
}

sub button_press_cb
{	my ($button,$ev,$menu)=@_;
	my $self=::find_ancestor($button,__PACKAGE__);
	$menu=$self->makemenu($menu);
	$::LEvent=$ev;
	$menu->show_all;
	$menu->popup(undef, undef, \&::menupos, undef, $ev->button, $ev->time);
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


package FilterEntryString;
use Gtk2;
use base 'Gtk2::Entry';

sub new
{	my ($class,$activatesub,$changesub,$init) = @_;
	my $self = bless Gtk2::Entry->new, $class;
	$self->set_text($init) if defined $init;
	$self->signal_connect(changed => $changesub) if $changesub;
	$self->signal_connect(activate => $activatesub) if $activatesub;
	return $self;
}
sub Get { $_[0]->get_text; }
sub Set { $_[0]->set_text($_[1]); }

package FilterEntryNumber;
use Gtk2;
use base 'Gtk2::SpinButton';

sub new
{	my ($class,$activatesub,$changesub,$init) = @_;
	my $self = bless Gtk2::SpinButton->new( Gtk2::Adjustment->new($init||0, 0, 99999, 1, 10, 0) ,10,0  ), $class;
	$self->set_numeric(::TRUE);
	$self->signal_connect(value_changed => $changesub) if $changesub;
	$self->signal_connect(activate => $activatesub) if $activatesub;
	return $self;
}
sub Get { $_[0]->get_adjustment->get_value; }
sub Set { $_[0]->get_adjustment->set_value($_[1]) if $_[1]=~m/^\d+$/; }

package FilterEntryDate;
use Gtk2;
use base 'Gtk2::Button';

sub new
{	my ($class,$activatesub,$changesub,$init) = @_;
	my $self = bless Gtk2::Button->new(_"Choose Date"), $class;
	unless ($init && $init=~m/(\d\d\d\d)-(\d\d?)-(\d\d?)/)
	{	my $time=$init||'';
		$time=time unless $time=~m/^\d+$/;
		my ($y,$m,$d)=(localtime($time))[5,4,3]; $y+=1900; $m++;
		$init=sprintf '%04d-%02d-%02d',$y,$m,$d;
	}
	$self->{date}=$init;
	$self->set_label($init);
	$self->{activatesub}=$activatesub;
	$self->{changesub}=$changesub;
	$self->signal_connect (clicked => sub
	{	my $self=$_[0];
		if ($self->{popup}) { $self->{popup}->destroy; $self->{popup}=undef; return; }
		$self->popup_calendar;
	});
	return $self;
}

sub popup_calendar
{	my $self=$_[0];
	my $popup=Gtk2::Window->new();
	$popup->set_decorated(0);
	$popup->set_border_width(5);
	$self->{popup}=$popup;
	my $cal=Gtk2::Calendar->new;
	$popup->set_modal(::TRUE);
	if ($self->{date}=~m/(\d\d\d\d)-(\d\d?)-(\d\d?)/)
	{	$cal->select_month($2-1,$1);
		$cal->select_day($3);
	}
	$cal->signal_connect(day_selected_double_click => sub
		{	my ($y,$m,$d)=$_[0]->get_date;
			$m++;
			$self->{date}=sprintf '%04d-%02d-%02d',$y,$m,$d;
			$self->set_label($self->{date});
			$popup->destroy;
			$self->{popup}=undef;
			$self->{changesub}($self) if $self->{changesub};
			$self->{activatesub}($self) if $self->{activatesub};
		});
	my $frame=Gtk2::Frame->new;
	$frame->add($cal);
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

sub Get { $_[0]{date} }
sub Set { $_[0]{date}=$_[1]; $_[0]->set_label($_[1]); }

package FilterEntryUnit;
use Gtk2;
use base 'Gtk2::HBox';

my %units;
INIT
{%units=
 (	a => ['d',99999,\%::DATEUNITS],
	b => ['m',99999999,\%::SIZEUNITS],
 );
}

sub new
{	my ($class,$activatesub,$changesub,$init,$type) = @_;
	my $self = bless Gtk2::HBox->new, $class;
	my ($defunit,$max,$units)=@{$units{$type}};
	my $valid=join '',keys %$units;
	my ($val,$unit);
	($val,$unit)=($init=~m/^(.*)([$valid])$/) if $init;
	$val=1 unless defined $val;
	$unit=$defunit unless defined $unit;
	my $spin=Gtk2::SpinButton->new( Gtk2::Adjustment->new($val||0, 0, $max, 1, 10, 0) ,10,0  );
	$spin->set_numeric(::TRUE);
	my $combo=Gtk2::OptionMenu->new;
	$self->pack_start($spin, ::FALSE,::FALSE, 0);
	$self->pack_start($combo,::FALSE,::FALSE, 0);
	$spin->signal_connect(value_changed => $changesub) if $changesub;
	$spin->signal_connect(activate => $activatesub) if $activatesub;
	$self->{adj}=$spin->get_adjustment;
	my $menuCombo=Gtk2::Menu->new;
	$combo->signal_connect(changed => sub
		{	$_[0]->parent->{u}=$_[0]->get_menu->get_active->{val};
			&$changesub if $changesub;
		});
	my $h;my $n=0;
	for my $u (sort { $units->{$a}[0] <=> $units->{$b}[0] } keys %$units)
	{	$h=$n if ($unit eq $u);
		my $item=Gtk2::MenuItem->new( $units->{$u}[1] );
		$item->{val}=$u;
		$menuCombo->append($item);
		$n++;
	}
	$combo->set_menu($menuCombo);
	$combo->set_history($h);
	$self->{u}=$unit;
	return $self;
}
sub Get
{	my $self=shift;
	return ($self->{adj}->get_value) . $self->{u};
}
#sub Set { $_[0]->get_adjustment->set_value($_[1]) if $_[1]=~m/^\d+$/; }

package FilterEntryCombo;		#FIXME use GMB::ListStore::Field::Combo for genre/label
use Gtk2;
use base 'Gtk2::OptionMenu';

my %getlist;
INIT
{%getlist=
 (	l => sub {[::GetListOfSavedLists()]},
	g => \&::GetGenresList,
	f => \&::SortedLabels,
 );
}

sub new
{	my ($class,$activatesub,$changesub,$init,$type) = @_;
	my $self = bless Gtk2::OptionMenu->new, $class;
	my $menuCombo=Gtk2::Menu->new;
	$self->signal_connect(changed => sub
		{	$_[0]{val}=$_[0]->get_menu->get_active->{val};
			&$changesub if $changesub;
			#&$activatesub if $activatesub;
		});
	my %hash; my $n=0;
	my $list= $getlist{$type}();
	for my $f (sort @$list)
	{	$hash{$f}=$n;
		my $item=Gtk2::MenuItem->new_with_label($f);
		$item->{val}=$f;
		$menuCombo->append($item);
		$n++;
	}
	$self->set_menu($menuCombo);
	$self->set_history($hash{$init}) if defined $init && $init ne '';
	$self->{hash}=\%hash;
	$self->{val}=$init;
	return $self;
}
sub Get { $_[0]{val}; }
sub Set
{	my ($self,$val)=@_;
	return unless defined $val && defined $self->{hash}{$val};
	$self->set_history( $self->{hash}{$val} );
	$self->{val}=$val;
}

package AAPicture;

my %Cache;
my $watcher;
our @ArraysOfFiles;	#array of filenames that needs updating in case a folder is renamed
my %Field_id;

INIT
{	::Watch(undef, Picture_artist => \&AAPicture_Changed);	#FIXME PHASE1
	::Watch(undef, Picture_album  => \&AAPicture_Changed);	#FIXME PHASE1
}

sub GetPicture
{	my ($field,$key)=@_;
	return Songs::Picture($key,$field,'get');
}
sub SetPicture
{	my ($field,$key,$file)=@_;
	Songs::Picture($key,$field,'set',$file);
}
sub UpdatePixPath
{	my ($oldpath,$newpath)=@_;
	m/$::QSLASH$/o or $_.=::SLASH for $oldpath,$newpath; #make sure the path ends with SLASH
	$oldpath=qr/^\Q$oldpath\E/;
	s/$oldpath/$newpath/ for grep $_, map @$_, @ArraysOfFiles;
}

sub newimg
{	my ($field,$key,$size,$todoref)=@_;
	my $p= pixbuf($field,$key,$size, ($todoref ? 0 : 1));
	return Gtk2::Image->new_from_pixbuf($p) if $p;

	my $img=Gtk2::Image->new;
	push @$todoref,$img;
	$img->{params}=[$field,$key,$size];
	$img->set_size_request($size,$size);
	return $img;
}
sub setimg
{	my $img=$_[0];
	my $p=pixbuf( @{delete $img->{params}},1 );
	$img->set_from_pixbuf($p);
}

sub pixbuf
{	my ($field,$key,$size,$now)=@_;
	my $fid= $Field_id{$field} ||= Songs::Code($field,'pic_cache_id|field');
	my $file= GetPicture($field,$key);
	#unless ($file)
	#{	return undef unless $::Options{use_default_aapic};
	#	$file=$::Options{default_aapic};
		return undef unless $file;
	#}
	$key=$size.$fid.':'.$key;
	my $p=$Cache{$key};
	return 0 unless $p || $now;
	$p||=load($file,$size,$key);
	$p->{lastuse}=time if $p;
	return $p;
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

sub load
{	my ($file,$size,$key)=@_;
	my $pixbuf=::PixBufFromFile($file,$size);
	return undef unless $pixbuf;
#	my $ratio=$pixbuf->get_width / $pixbuf->get_height;
#	my $ph=my $pw=$s;
#	if    ($ratio>1) {$ph=int($pw/$ratio);}
#	elsif ($ratio<1) {$pw=int($ph*$ratio);}
#	$Cache{$key}=$pixbuf=$pixbuf->scale_simple($pw, $ph, 'bilinear');
	$Cache{$key}=$pixbuf;
	::IdleDo('9_AAPicPurge',undef,\&purge) if keys %Cache >120;
	return $pixbuf;
}

sub purge
{	my $nb= keys(%Cache)-100;# warn "purging $nb cached AApixbufs\n";
	delete $Cache{$_} for (sort {$Cache{$a}{lastuse} <=> $Cache{$b}{lastuse}} keys %Cache)[0..$nb];
}

sub AAPicture_Changed
{	my $key=$_[1];
	my $re=qr/^\d+\w+:\Q$key\E/;
	delete $Cache{$_} for grep m/$re/, keys %Cache;
}

sub load_file #use the same cache as the AAPictures, #FIXME create a different package for all picture cache functions
{	my ($file,$crop,$resize,$now)=@_; #resize is resizeopt_w_h
	my $key= ':'.join ':',$file,$crop,$resize||''; #FIXME remove w or h in resize if not resized in this dimension
	my $pixbuf=$Cache{$key};
	unless ($pixbuf)
	{	return unless $now;
		$pixbuf=Skin::_load_skinfile($file,$crop);
		$pixbuf=Skin::_resize($pixbuf,split /_/,$resize) if $resize && $pixbuf;
		return unless $pixbuf;
		$Cache{$key}=$pixbuf;
	}
	$pixbuf->{lastuse}=time;
	::IdleDo('9_AAPicPurge',undef,\&purge) if keys %Cache >120;
	return $pixbuf;
}


package TextCombo;
use base 'Gtk2::ComboBox';

sub new
{	my ($class,$list,$init,$sub) = @_;
	my $self= bless Gtk2::ComboBox->new, $class;
	$self->build_store($list);
	my $renderer=Gtk2::CellRendererText->new;
	$self->pack_start($renderer,::TRUE);
	$self->add_attribute($renderer, text => 0);
	$self->set_value($init);
	$self->set_value(undef) unless $self->get_active_iter; #in case $init was not found
	$self->signal_connect( changed => $sub ) if $sub;
	return $self;
}

sub build_store
{	my ($self,$list)=@_;
	my $store= Gtk2::ListStore->new('Glib::String','Glib::String');
	my $names=$list;
	if (ref $list eq 'HASH')
	{	my $h=$list;
		$list=[]; $names=[];
		for my $key (sort {::superlc($h->{$a}) cmp ::superlc($h->{$b})} keys %$h)
		{	push @$list,$key;
			push @$names,$h->{$key}
		}
	}
	my $found;
	for my $i (0..$#$list)
	{	my $iter= $store->append;
		$store->set($iter, 0,$names->[$i], 1,$list->[$i]);
	}
	$self->set_model($store);
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
	$titem->set_tooltip($::Tooltips,$desc,'');
	my $item=Gtk2::MenuItem->new_with_label($desc);
	my $menu=Gtk2::Menu->new;
	$item->set_submenu($menu);
	$titem->set_proxy_menu_item($menu_item_id,$item);
	my $radioi;
	my $store=$self->get_model;
	my $iter=$self->get_active_iter;
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
		{	$item->set_active( $item->{value} eq $value );
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
	my $store= Gtk2::TreeStore->new('Glib::String','Glib::String');
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
	$self->set_model($store);
	return $store;
}

sub make_toolitem
{	warn "TextCombo::Tree : make_toolitem not implemented\n";	#FIXME not needed for now, but could be in the future
	return undef;
}

package Label::Preview;
use base 'Gtk2::Label';

sub new
{	my ($class,$update,$event,$entry,$use_markup)=@_;
	my $self= bless Gtk2::Label->new, $class;
	$self->{entry}=$entry;
	$self->{update}=$update;
	$self->{use_markup}=$use_markup;
	#$entry->signal_connect( changed => sub { $self->update });
	$entry->signal_connect_swapped( changed => \&update, $self) if $entry;
	if ($event) { ::Watch($self, $_ => \&update) for split / /,$event; }
	$self->update;
	return $self;
}
sub update
{	my $self=shift;
	my $arg= $self->{entry} ? $self->{entry}->get_text : undef;
	my $text=$self->{update}->($arg);
	$self->{use_markup} ? $self->set_markup($text) : $self->set_text($text);
}

