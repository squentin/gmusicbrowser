#!/usr/bin/perl

# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
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
 *Gtk2::Gdk::GC::set_clip_rectangle=sub { goto $set_clip_rectangle_orig if $_[1]; } if $Gtk2::VERSION <1.102; #work-around $rect can't be undef in old bindings versions
}
use POSIX qw/setlocale LC_NUMERIC LC_MESSAGES strftime mktime/;
use File::Copy;
use Fcntl qw/O_NONBLOCK O_WRONLY O_RDWR/;
use Encode qw/_utf8_on _utf8_off/;
use Unicode::Normalize 'NFKD'; #for accent-insensitive sort

#use constant SLASH => ($^O  eq 'MSWin32')? '\\' : '/';
use constant SLASH => '/'; #gtk file chooser use '/' in win32 and perl accepts both '/' and '\'

# Find dir containing other files (*.pm & pix/) -> $DATADIR
use FindBin;
our $DATADIR;
BEGIN
{ my @dirs=(	$FindBin::RealBin,
		$FindBin::RealBin.SLASH.'..'.SLASH.'share'.SLASH.'gmusicbrowser' #FIXME add Glib::get_system_data_dirs to the list ?
	   );
  ($DATADIR)=grep -e $_.SLASH.'gmusicbrowser_player.pm', @dirs;
  die "Can't find folder containing data files, looked in @dirs\n" unless $DATADIR;
}
use lib $DATADIR;

use constant
{
 TRUE  => 1,
 FALSE => 0,
 VERSION => '1.02',	#used for easy numeric comparison
 VERSIONSTRING => '1.0.2',
 PIXPATH => $DATADIR.SLASH.'pix'.SLASH,
 PROGRAM_NAME => 'gmusicbrowser',

 #fields of @{$Songs[$ID]} :
 SONG_UFILE	=> 0,	SONG_UPATH	=> 1,	SONG_MODIF	=> 2,
 SONG_LENGTH	=> 3,	SONG_SIZE	=> 4,	SONG_BITRATE	=> 5,
 SONG_FORMAT	=> 6,	SONG_CHANNELS	=> 7,	SONG_SAMPRATE	=> 8,
 SONG_TITLE	=> 9,	SONG_ARTIST	=> 10,	SONG_ALBUM	=> 11,
 SONG_DISC	=> 12,	SONG_TRACK	=> 13,	SONG_DATE	=> 14,
 SONG_VERSION	=> 15,	SONG_GENRE	=> 16,	SONG_COMMENT	=> 17,
 SONG_AUTHOR	=> 18,
 SONG_ADDED	=> 19,	SONG_LASTPLAY	=> 20,	SONG_NBPLAY	=> 21,
 SONG_RATING	=> 22,	SONG_LABELS	=> 23,
 SONG_MISSINGSINCE => 24,
 SONG_LASTSKIP	=> 25,	SONG_NBSKIP	=> 26,
 SONGLASTSAVED	=> 26,
 SONG_FILE	=> 27,	SONG_PATH	=> 28,
 SONGLAST	=> 28,	# nb of last field
 # LYRICS ?

 DRAG_STRING	=> 0, DRAG_USTRING	=> 1, DRAG_FILE		=> 2,
 DRAG_ID	=> 3, DRAG_ARTIST	=> 4, DRAG_ALBUM	=> 5,
 DRAG_FILTER	=> 6, DRAG_MARKUP	=> 7,

 #contents of @{$Artist{$artist}} and @{$Album{$album}} :
 AALIST => 0, AAXREF => 1, AALENGTH => 2, AAYEAR => 3, AAPIXLIST => 4,

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

BEGIN{
require 'gmusicbrowser_tags.pm';
require 'gmusicbrowser_player.pm';
require 'gmusicbrowser_list.pm';
require 'simple_http.pm';
}

our $Gtk2TrayIcon;
BEGIN
{ if (grep -f $_."/Gtk2/TrayIcon.pm",@INC)  { require Gtk2::TrayIcon; $Gtk2TrayIcon=1; }
  else { warn "Gtk2::TrayIcon not found -> tray icon won't be available\n"; }
}


our $debug;
our %CmdLine;
our (@Songs,@Shuffle);
our (%Artist,%Album);
our ($HomeDir,$SaveFile,$FIFOFile);

our $QSLASH;	#quoted SLASH for use in regex
sub file_name_is_absolute
{	($^O ne 'MSWin32') ? $_[0]=~m#^$QSLASH#o : $_[0]=~m#^[a-z]:[/\\]#io;
}

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
		mkdir $HomeDir or warn "Error creating $HomeDir : $!\n";
	}
  }

  $SaveFile=(-d $HomeDir)
	?  $HomeDir.'tags'
	: 'gmusicbrowser.tags';
  $FIFOFile=(-d $HomeDir && $^O ne 'MSWin32')
	?  $HomeDir.'gmusicbrowser.fifo'
	: undef;

my $help=PROGRAM_NAME.' v'.VERSIONSTRING." (c)2005-2008 Quentin Sculo
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
-layout NAME		: use layout NAME for player window
-load FILE		: Load FILE as a plugin
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
-listcmd : list the available fifo commands and exit
";
  unshift @ARGV,'-tagedit' if $0=~m/tagedit/;
  $CmdLine{gst}=0;
  my @files; my $filescmd;
   while (defined (my $arg=shift))
   {	if   ($arg eq '-c')	{$CmdLine{nocheck}=1}
	elsif($arg eq '-s')	{$CmdLine{noscan}=1}
	elsif($arg eq '-demo')	{$CmdLine{demo}=1}
#	elsif($arg eq '-empty')	{$CmdLine{empty}=1}
	elsif($arg eq '-play')	{$CmdLine{play}=1}
	elsif($arg eq '-hide')	{$CmdLine{hide}=1}
	elsif($arg eq '-server'){$CmdLine{server}=1}
	elsif($arg eq '-nodbus'){$CmdLine{noDBus}=1}
	elsif($arg eq '-nogst')	{$CmdLine{gst}=0}
	elsif($arg eq '-gst')	{$CmdLine{gst}=1}
	elsif($arg eq '-ro')	{$CmdLine{ro}=$CmdLine{rotags}=1}
	elsif($arg eq '-rotags'){$CmdLine{rotags}=1}
	elsif($arg eq '-port')	{$CmdLine{port}=shift if $ARGV[0]}
	elsif($arg eq '-debug')	{$debug=1}
	elsif($arg eq '-nofifo'){$FIFOFile=undef}
	elsif($arg eq '-C')	{$SaveFile=shift if $ARGV[0]}
	elsif($arg eq '-F')	{$FIFOFile=shift if $ARGV[0]}
	elsif($arg eq '-layout'){$CmdLine{layout}=shift if $ARGV[0]}
	elsif($arg eq '-load')	{ push @{$CmdLine{plugins}},shift if $ARGV[0]}
	elsif($arg eq '-geometry'){$CmdLine{geometry}=shift if $ARGV[0]; }
	elsif($arg eq '-use-gnome-session'){ $CmdLine{UseGnomeSession}=1; }
	elsif($arg eq '-tagedit'){$CmdLine{tagedit}=1;last; }
	elsif($arg eq '-listcmd'){$CmdLine{cmdlist}=1;last; }
	elsif($arg eq '-cmd')   { RunRemoteCommand(@ARGV); $CmdLine{runcmd}="@ARGV"; last; }
	elsif($arg eq '-remotecmd'){ RunRemoteCommand(@ARGV); exit; }
	elsif($arg eq '-launch_or_cmd'){ RunRemoteCommand(@ARGV); last; }
	elsif($arg eq '-add')		{ $filescmd='AddToLibrary'; }
	elsif($arg eq '-playlist')	{ $filescmd='OpenFiles'; }
	elsif($arg eq '-enqueue')	{ $filescmd='EnqueueFiles'; }
	elsif($arg eq '-addplaylist')	{ $filescmd='AddFilesToPlaylist'; }
	elsif($arg eq '-insertplaylist'){ $filescmd='InsertFilesInPlaylist'; }
	elsif($arg=~m#^http://# || -e $arg) { push @files,$arg }
	else
	{	warn "unknown option '$arg'\n" unless $arg=~/^--?h(elp)?$/;
		print $help;
		exit;
	}
   }
  if (@files)
  {	for (@files)
	{ unless (m#^http://#)
	  {	$_=$ENV{PWD}.SLASH.$_ unless file_name_is_absolute($_);
		s/([^A-Za-z0-9])/sprintf('%%%02X', ord($1))/seg; #FIXME use url_escapeall, but not yet defined
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

our $ILLEGALCHAR=qr#[/:><\*\?\"\\]#;	# regex that matches characters that shouldn't be used in filenames
our $ILLEGALCHARDIR=qr#[:><\*\?\"\\]#;	# regex that matches characters that shouldn't be used in pathnames
$ILLEGALCHARDIR=qr#[/:><\*\?\"]#  if $^O eq 'MSWin32';

#our $re_spaces_unlessinbrackets=qr/([^( ]+(?:\(.*?\))?)(?: +|$)/; #breaks "widget1(options with spaces) widget2" in "widget1(options with spaces)" and "widget2" #replaced by ExtractNameAndOptions

our $re_artist; #regular expression used to split artist name into multiple artists, defined at init by the option ArtistSplit, may not be changed afterward because it is used with the /o option (faster)

my ($browsercmd,$opendircmd);

our %TagIndex;
our @TagProp;	# TagProp[columnnumber]=[name,id,data_type,width]
# data_type :	d : date in seconds since epoch (01-01-1970)
#		s : string
#		n : number
#		l : length in seconds
#		f : genres & labels (list of \x00 terminated strings)
BEGIN #FIXME, shouldn't be a BEGIN block but needs to be executed before gmusibrowser_list.pm
{ my @names=
  (	ufile	=>	_"Filename"	, SONG_UFILE,	's',400,
	upath	=>	_"Folder"	, SONG_UPATH,	's',200,
	modif	=>	_"Modification"	, SONG_MODIF,	'd',160,
	title	=>	_"Title"	, SONG_TITLE,	's',275,
	artist	=>	_"Artist"	, SONG_ARTIST,	's',200,
	date	=>	_"Date"		, SONG_DATE,	's',40,
	album	=>	_"Album"	, SONG_ALBUM,	's',200,
	comment	=>	_"Comment"	, SONG_COMMENT,	's',200,
	track	=>	_"Track"	, SONG_TRACK,	'n',22,
	genre	=>	_"Genres"	, SONG_GENRE,	'f',200,
	length	=>	_"Length"	, SONG_LENGTH,	'l',50,
	size	=>	_"Size"		, SONG_SIZE,	'n',80,
	disc	=>	_"Disc"		, SONG_DISC,	'n',50,
	version	=>	_"Version"	, SONG_VERSION,	's',150,
	rating	=>	_"Rating"	, SONG_RATING,	'n',80,
	added	=>	_"Added"	, SONG_ADDED,	'd',100,
	lastplay=>	_"Last played"	, SONG_LASTPLAY,'d',100,
	lastskip=>	_"Last skipped"	, SONG_LASTSKIP,'d',100,
	playcount=>	_"Play count"	, SONG_NBPLAY,	'n',100,
	skipcount=>	_"Skip count"	, SONG_NBSKIP,	'n',100,
	label	=>	_"Labels"	, SONG_LABELS,	'f',100,
	bitrate	=>	_"Bitrate"	, SONG_BITRATE,	'n',70,
	filetype=>	_"Type"		, SONG_FORMAT,	's',80,
	channel	=>	_"Channels"	, SONG_CHANNELS,'n',50,
	samprate=>	_"Sampling Rate", SONG_SAMPRATE,'n',60,
	author	=>	undef,		, SONG_AUTHOR,	's',100,
    );
    while (@names)
    {	my ($id,$name,$n,$type,$colwidth)=splice @names,0,5;
	$TagProp[$n]=[ $name,$id,$type,$colwidth ];
	$TagIndex{$id}=$n;
    }
}

our %QActions=		#icon		#short		#long description
(	''	=> [ 0, 'gmb-empty',	_"normal",	_"normal play when queue empty"],
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
		{ DRAG_FILE,	sub { map 'file://'.url_escape($Songs[$_][SONG_PATH].SLASH.$Songs[$_][SONG_FILE]), @_;},
#		  DRAG_ARTIST,	sub { keys %{ &{$FilterList::hashsub[SONG_ARTIST]}(\@_) } },
#		  DRAG_ALBUM,	sub { keys %{ &{$FilterList::hashsub[SONG_ALBUM]}(\@_) } },
		  DRAG_ARTIST,	sub { my %h; $h{ $Songs[$_][SONG_ARTIST] }=undef for @_; sort keys %h; },
		  DRAG_ALBUM,	sub { my %h; $h{ $Songs[$_][SONG_ALBUM ] }=undef for @_; sort keys %h; },
		  DRAG_USTRING,	sub { (@_==1)? $Songs[$_[0]][SONG_TITLE] : __("%d song","%d songs",scalar@_) },
		  DRAG_STRING,	undef, #will use DRAG_USTRING
		  DRAG_FILTER,	sub {Filter->newadd(FALSE,map SONG_TITLE.'~'.$Songs[$_][SONG_TITLE],@_)->{string}},
		  DRAG_MARKUP,	sub { (@_==1)	? ReplaceFieldsAndEsc($_[0],_"<b>%t</b>\n<small><small>by</small> %a\n<small>from</small> %l</small>")
						: __x(	_("{songs} by {artists}") . "\n<small>{length}</small>",
							songs => __("%d song","%d songs",scalar@_),
							artists => do {my %h; $h{$Songs[$_][SONG_ARTIST]}=undef for @_; (keys %h ==1)? ::PangoEsc($Songs[$_[0]][SONG_ARTIST]) : __("%d artist","%d artists",scalar(keys %h)) },
							'length' => CalcListLength(\@_,'length')
							)},
		}],
	[Artist => {	DRAG_USTRING,	sub { (@_<10)? join("\n",@_) : __("%d artist","%d artists",scalar@_) },
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map SONG_ARTIST.'~'.$_,@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map SONG_ARTIST.'~'.$_,@_)->filter; SortList($l); @$l; },
		}],
	[Album  => {	DRAG_USTRING,	sub { (@_<10)? join("\n",@_) : __("%d album","%d albums",scalar@_) },
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_FILTER,	sub {   Filter->newadd(FALSE,map SONG_ALBUM.'e'.$_,@_)->{string} },
			DRAG_ID,	sub { my $l=Filter->newadd(FALSE,map SONG_ALBUM.'e'.$_,@_)->filter; SortList($l); @$l; },
		}],
	[Filter =>
		{	DRAG_USTRING,	sub {Filter->new($_[0])->explain},
		  	DRAG_STRING,	undef, #will use DRAG_USTRING
			DRAG_ID,	sub { my $l=Filter->new($_[0])->filter; SortList($l); @$l; },
		}
	],
);
our %DRAGTYPES;
$DRAGTYPES{$DRAGTYPES[$_][0]}=$_ for DRAG_FILE,DRAG_USTRING,DRAG_STRING,DRAG_ID,DRAG_ARTIST,DRAG_ALBUM,DRAG_FILTER,DRAG_MARKUP;

our @submenuRemove=
(	{ label => _"Remove from list",	code => sub { $_[0]{self}->RemoveSelected; }, mode => 'BLQ'},
#(	{ label => _"Remove from list',	code => sub { $_[0]{self}->RemoveID(@{ $_[0]{IDs} }); }, mode => 'B'},
	{ label => _"Remove from library",	code => sub { SongsRemove($_[0]{IDs}); }, },
	{ label => _"Remove from disk",		code => sub { DeleteFiles($_[0]{IDs}); },	test => sub {!$CmdLine{ro}},	stockicon => 'gtk-delete' },
);
#modes : S:Search, B:Browser, Q:Queue, L:List, P:Playing song in the player window
our @SongCMenu=
(	{ label => _"Song Properties",	code => sub { DialogSongProp (@{ $_[0]{IDs} }); },	onlyone => 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Songs Properties",	code => sub { DialogSongsProp(@{ $_[0]{IDs} }); },	onlymany=> 'IDs', stockicon => 'gtk-edit' },
	{ label => _"Play Only Selected",code => sub { Select(song => 'first', play => 1, staticlist => $_[0]{IDs} ); },
		onlymany => 'IDs',	stockicon => 'gtk-media-play'},
	{ label => _"Play Only Displayed",code => sub { Select(song => 'first', play => 1, staticlist => \@{$_[0]{listIDs}} ); },
		test => sub { @{$_[0]{IDs}}<2 },	onlymany => 'listIDs',	stockicon => 'gtk-media-play' },
	{ label => _"Enqueue Selected",	code => sub { Enqueue(@{ $_[0]{IDs} }); },
		notempty => 'IDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Enqueue Displayed",	code => sub { Enqueue(@{ $_[0]{listIDs} }); },
		empty => 'IDs',	notempty=> 'listIDs', notmode => 'QP', stockicon => 'gmb-queue' },
	{ label => _"Add to list",	submenu => \&AddToListMenu,	notempty => 'IDs' },
	{ label => _"Edit Labels",	submenu => \&LabelEditMenu,	notempty => 'IDs' },
	{ label => _"Edit Rating",	submenu => \&Stars::createmenu,	notempty => 'IDs' },
	{ label => _"Find songs with the same names", code => sub { SearchSame(SONG_TITLE,$_[0]) },	mode => 'B',	notempty => 'IDs' },
	{ label => _"Find songs with same artists", code => sub { SearchSame(SONG_ARTIST,$_[0]) },	mode => 'B',	notempty => 'IDs' },
	{ label => _"Find songs in same albums", code => sub { SearchSame(SONG_ALBUM,$_[0]) },	mode => 'B',	notempty => 'IDs' },
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
	{ label => _"Open containing folder",	code => sub { openfolder( $Songs[ $_[0]{IDs}[0] ][SONG_PATH] ); },	onlyone => 'IDs' },
);
our @cMenuAA=
(	{ label => _"Lock",	code => sub { ToggleLock($_[0]{col}); }, check => sub {defined $::TogLock && $::TogLock==$_[0]{col}}, mode => 'P' },
	{ label => _"Lookup in AMG",	code => sub { ::AMGLookup( $_[0]{col},$_[0]{key} ); }, },
	{ label => _"Filter",		code => \&filterAA,	stockicon => 'gmb-filter', mode => 'P' },
	{ label => \&SongsSubMenuTitle,		submenu => \&SongsSubMenu, },
	{ label => sub {$_[0]{mode} eq 'P' ? _"Display Songs" : _"Filter"},	code => \&FilterOnAA,
		test => sub { GetSonglist( $_[0]{self} ) }, },
	{ label => _"Set Picture",	code => sub { ChooseAAPicture($_[0]{ID},$_[0]{col},$_[0]{key}); },
		stockicon => 'gmb-picture' },
);

sub url_escapeall
{	local $_=$_[0];
	_utf8_off($_); # or "use bytes" ?
	s#([^A-Za-z0-9])#sprintf('%%%02X', ord($1))#seg;
	return $_;
}
sub url_escape
{	local $_=$_[0];
	_utf8_off($_);
	s#([^/\$_.+!*'(),A-Za-z0-9-])#sprintf('%%%02X',ord($1))#seg;
	return $_;
}
sub decode_url
{	local $_=$_[0];
	_utf8_off($_);
	s#%([0-9A-F]{2})#chr(hex $1)#ieg;
	return $_;
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

our %ReplaceFields=		# for each field : [sub returning the formated value, field name, depends on these fields]
(	'%' => [sub {'%'},'%'],
	t => [sub { $Songs[$_[0]][SONG_TITLE]	}, $TagProp[SONG_TITLE][0],	[SONG_TITLE]],
	a => [sub { $Songs[$_[0]][SONG_ARTIST]	}, $TagProp[SONG_ARTIST][0],	[SONG_ARTIST]],
	l => [sub { $Songs[$_[0]][SONG_ALBUM]	}, $TagProp[SONG_ALBUM][0],	[SONG_ALBUM]],
	d => [sub { $Songs[$_[0]][SONG_DISC]	}, $TagProp[SONG_DISC][0],	[SONG_DISC]],
	n => [sub { $Songs[$_[0]][SONG_TRACK]	}, $TagProp[SONG_TRACK][0],	[SONG_TRACK]],
	y => [sub { $Songs[$_[0]][SONG_DATE]	}, $TagProp[SONG_DATE][0],	[SONG_DATE]],
	C => [sub { $Songs[$_[0]][SONG_COMMENT]	}, $TagProp[SONG_COMMENT][0],	[SONG_COMMENT]],
	p => [sub { $Songs[$_[0]][SONG_NBPLAY]||0},$TagProp[SONG_NBPLAY][0],	[SONG_NBPLAY]],
	P => [sub { my $v=$Songs[$_[0]][SONG_LASTPLAY]; $v ? scalar localtime $v : _('never')},$TagProp[SONG_LASTPLAY][0],	[SONG_LASTPLAY]],
	k => [sub { $Songs[$_[0]][SONG_NBSKIP]||0},$TagProp[SONG_NBSKIP][0],	[SONG_NBSKIP]],
	K => [sub { my $v=$Songs[$_[0]][SONG_LASTSKIP]; $v ? scalar localtime $v : _('never')},$TagProp[SONG_LASTSKIP][0],	[SONG_LASTSKIP]],
	m => [sub { my $v=$Songs[$_[0]][SONG_LENGTH];sprintf "%d:%02d",$v/60,$v%60;}, $TagProp[SONG_LENGTH][0],	[SONG_LENGTH]],
	g => [sub { join ', ',split /\x00/,$Songs[$_[0]][SONG_GENRE]||'' }, $TagProp[SONG_GENRE][0], [SONG_GENRE]],
	L => [sub { join ', ',split /\x00/,$Songs[$_[0]][SONG_LABELS]||'' },$TagProp[SONG_LABELS][0],[SONG_LABELS]],
	F => [sub { $Songs[$_[0]][SONG_PATH]; }, _"Folder",[SONG_PATH]],
	o => [sub { my$s=$Songs[$_[0]][SONG_UFILE]; $s=~s/\.[^\.]+$//; $s; },_"old filename",[SONG_UFILE]],
	f => [sub { $Songs[$_[0]][SONG_PATH].SLASH.$Songs[$_[0]][SONG_FILE]; }, _"File",[SONG_PATH,SONG_FILE]],
	u => [sub { $Songs[$_[0]][SONG_UPATH].SLASH.$Songs[$_[0]][SONG_UFILE]; }, _"File",[SONG_UPATH,SONG_UFILE]],
	S => [sub { my $s=$Songs[$_[0]][SONG_TITLE]; $s=$Songs[$_[0]][SONG_UFILE] if !defined $s || $s eq ''; $s;},undef,[SONG_TITLE,SONG_UFILE]],
	V => [sub { my $v=$Songs[$_[0]][SONG_VERSION]; return (!defined $v || $v eq '') ? '' : " ($v)" },undef,[SONG_VERSION]],
	c => [sub { my $alb=$Songs[$_[0]][SONG_ALBUM]; $alb=$Album{$alb}[AAPIXLIST]; $alb='' unless $alb; return $alb; }, _"Cover",[SONG_ALBUM]],
	Y => [sub { my $alb=$Songs[$_[0]][SONG_ALBUM]; return $Album{$alb}[AAYEAR]; }, _"Album year(s)",[SONG_DATE,SONG_ALBUM]],	#FIXME depends on SONG_DATE from all songs of SONG_ALBUM
	A => [sub #guess album artist
	{	my $alb=$Songs[$_[0]][SONG_ALBUM];
		my %h; $h{ $Songs[$_][SONG_ARTIST] }=undef for @{$Album{$alb}[AALIST]};
		my $nb=keys %h;
		return $Songs[$_[0]][SONG_ARTIST] if $nb==1;
		my @l=map split(/$re_artist/o), keys %h;
		my %h2; $h2{$_}++ for @l;
		my @common;
		for (@l) { if ($h2{$_}>=$nb) { push @common,$_; $h2{$_}=0; } }
		return @common ? join ' & ',@common : _"Various artists";
	},
		_"Album artist",[SONG_ARTIST,SONG_ALBUM]],	#FIXME depends on SONG_ARTIST from all songs of SONG_ALBUM
);

sub UsedFields
{	my $s=$_[0];
	return map @{ $ReplaceFields{$_}[2] || [] }, $s=~m/%([YACSVumtalydnfFcopPkKgL%])/g;
}
sub ReplaceFields
{	my ($ID,$s)=($_[0],$_[1]);
	no warnings 'uninitialized';
	$s=~s#\\n#\n#g;
	$s=~s/%([YACSVumtalydnfFcopPkKgL%])/&{$ReplaceFields{$1}[0]}($ID)/ge;
	return $s;
}
sub ReplaceFieldsAndEsc
{	my ($ID,$s)=($_[0],$_[1]);
	no warnings 'uninitialized';
	$s=~s#\\n#\n#g;
	$s=~s/%([YACSVumtalydnfFcopPkKgL%])/PangoEsc(&{$ReplaceFields{$1}[0]}($ID))/ge;
	return $s;
}
sub MakeReplaceTable
{	my $fields=$_[0];
	my $table=Gtk2::Table->new (4, 2, FALSE);
	my $row=0; my $col=0;
	for my $tag (split //,$fields)
	{	for my $text ( '%'.$tag, $ReplaceFields{$tag}[1] )
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
	my $text=join "\n",map '%'.$_.' : '.$ReplaceFields{$_}[1], split //,$fields;
	return $text;
}

our %ReplaceAAFields=
(	'%'	=>	sub {'%'},
	a	=>	sub { $_[0] },
	l	=>	sub { my $l=$_[1]->[AALENGTH]; $l=__x( ($l>=3600 ? _"{hours}h{min}m{sec}s" : _"{min}m{sec}s"), hours => (int $l/3600), min => ($l>=3600 ? sprintf('%02d',$l/60%60) : $l/60%60), sec => sprintf('%02d',$l%60)); },
	L	=>	sub { CalcListLength( $_[1]->[AALIST],'length' ); },
	y	=>	sub { $_[1]->[AAYEAR] || ''; },
	Y	=>	sub { my $y=$_[1]->[AAYEAR]; return $y? " ($y)" : '' },
	s	=>	sub { __('%d song','%d songs',$_[1]->[AALIST] ? scalar@{$_[1]->[AALIST]} : 0) },
	x	=>	sub { my $nb=keys %{$_[1]->[::AAXREF]}; return $_[2]==SONG_ARTIST ? __("%d Album","%d Albums",$nb) : __("%d Artist","%d Artists",$nb);  },
	X	=>	sub { my $nb=keys %{$_[1]->[::AAXREF]}; return $_[2]==SONG_ARTIST ? __("%d Album","%d Albums",$nb) : $nb>1 ? __("%d Artist","%d Artists",$nb) : '';  },
	b	=>	sub { my %h; $h{ $Songs[$_][::SONG_ARTIST] }=undef for @{$_[1]->[AALIST]}; return keys(%h)==1 ? (keys(%h))[0] : __("%d artist","%d artists", scalar keys(%h));  },
);
sub ReplaceAAFields
{	my ($aa,$format,$col,$esc)=@_;
	my $ref= $col == SONG_ARTIST ? \%Artist : \%Album;
	$ref=$ref->{$aa};
	return '' unless ref $ref;
	if($esc){ $format=~s/%([alLyYsxXb%r])/PangoEsc(&{$ReplaceAAFields{$1}}($aa,$ref,$col))/ge; }
	else	{ $format=~s/%([alLyYsxXb%r])/&{$ReplaceAAFields{$1}}($aa,$ref,$col)/ge; }
	return $format;
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
	my ($d1,$d2)=$pat=~m/^(\S+)\s?(.*)$/;
	for ($d1,$d2)
	{	if (m/^\d+$/) {}
		elsif (m/^(\d\d\d\d)-(\d\d?)-(\d\d?)/) { $_=mktime(0,0,0,$3,$2-1,$1-1900); }
		elsif (m/^(\d+\.?\d*)([smhdwMy])$/){ $_=time-$1*$DATEUNITS{$2}[0];   }
	}
	return ( (defined $d2 && $d2 ne '')?  join(' ',sort { $a <=> $b } $d1,$d2) : $d1 );
}


#---------------------------------------------------------------
our @TAGSREADFROMTAGS=(SONG_TITLE,SONG_ARTIST,SONG_DATE,SONG_ALBUM,SONG_COMMENT,SONG_TRACK,SONG_GENRE,SONG_DISC,SONG_VERSION);
our @TAGSELECTION=(SONG_TITLE,SONG_ARTIST,SONG_ALBUM,SONG_DATE,SONG_TRACK,SONG_DISC,SONG_VERSION,SONG_GENRE,SONG_RATING,SONG_LABELS,SONG_NBPLAY,SONG_LASTPLAY,SONG_NBSKIP,SONG_LASTSKIP,SONG_ADDED,SONG_MODIF,SONG_COMMENT,SONG_UFILE,SONG_UPATH,SONG_LENGTH,SONG_SIZE,SONG_BITRATE,SONG_FORMAT,SONG_CHANNELS,SONG_SAMPRATE);
my @SAVEDFIELDS=(0..SONGLASTSAVED); $SAVEDFIELDS[SONG_UFILE]=SONG_FILE; $SAVEDFIELDS[SONG_UPATH]=SONG_PATH;
my $DAYNB=int(time/86400)-12417;#number of days since 01 jan 2004

our (@LibraryPath,@Library,$PlaySource,@Radio);
our (%GlobalBoundKeys,%CustomBoundKeys);
#our (@Songs,@Shuffle);
#our (%Artist,%Album);
our %Labels;
my (%GetIDFromFile,%MissingSTAAT,$MissingCount);
my @STAAT=(SONG_SIZE,SONG_TITLE,SONG_ALBUM,SONG_ARTIST,SONG_TRACK); #Fields used to check if same song
our %SavedFilters; our ($SelectedFilter,$PlayFilter); our (%Filters,%Filters_nb,%FilterWatchers);
our (%SavedSorts,%SavedWRandoms);
our %SavedLists; my $SavedListsWatcher;
our @ListPlay;
our ($TogPlay,$TogLock);
my $VolInc=10;
our ($RandomMode,$SortFields,$ListMode);
our ($SongID,@Recent,$RecentPos,@Queue); our $QueueAction=''; our $Position=0;
our ($MainWindow,$BrowserWindow,$ContextWindow,$FullscreenWindow); my $OptionsDialog;
our $QueueWindow; my $TrayIcon;
my %Editing;
our $PlayTime;
our ($StartTime,$StartedAt,$PlayingID,$PlayedPartial); my $About_to_NextSong;
our $CurrentDir=$ENV{PWD};

our $LEvent;
our (%ToDo,%TimeOut);
my %EventWatchers;#for Save Vol Time Queue Lock Repeat Sort Filter Pos SongID Playing SavedWRandoms SavedSorts SavedFilters SavedLists AAPicture Icons ExtraWidgets Context connections
# also used for SearchText_ SelectedID_ followed by group id

my @SongsWatchers;
my $SFWatch=AddWatcher();
my (@Watched,@WatchedFilt);
$Watched[$_]=[] for 0..SONGLAST;
$WatchedFilt[$_]=[] for 0..SONGLAST;
my ($IdleLoop,@ToCheck,@ToScan,%FollowedDirs,@ToAdd,@LengthEstimated,$CoverCandidates,%ToUpdateYAr,%ToUpdateYAl);
my ($ProgressWin,$ProgressNBSongs,$ProgressNBFolders);
my %Plugins;
my $ScanRegex;

#Default values
our %Options=
(	Layout		=> 'default player layout',
	LayoutT		=> 'info',
	LayoutB		=> 'Browser',
	LayoutF		=> 'default fullscreen',
	LayoutS		=> 'Search',
	IconTheme	=> '',
	MaxAutoFill	=> 5,
	Repeat		=> 1,
	Sort		=> 's',		#default sort order
	AltSort		=> SONG_UPATH.' '.SONG_UFILE,
	WSRename	=> '300 180',
	WSMassRename	=> '650 550',
	WSMassTag	=> '520 560',
	WSAdvTag	=> '538 503',
	WSSongInfo	=> '420 482',
	WSEditSort	=> '600 320',
	WSEditFilter	=> '600 260',
	WSEditWRandom	=> '600 450',
	Sessions	=> '',
	StartCheck	=> 0,	#check if songs have changed on startup
	StartScan	=> 0,	#scan @LibraryPath on startup for new songs
	#Path		=> '',	#contains join "\x1D",@LibraryPath
	Labels => join("\x1D",_("favorite"),_("bootleg"),_("broken"),_("bonus tracks"),_("interview"),_("another example")),
	FilenameSchema	=> join("\x1D",'%a - %l - %n - %t','%l - %n - %t','%n-%t','%d%n-%t'),
	FolderSchema	=> join("\x1D",'%A/%l','%A','%A/%Y-%l','%A - %l'),
	PlayedPercent	=> .85,	#percent of a song played to increase play count
	DefaultRating	=> 50,
	Device		=> 'default',
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
	ShowTipOnSongChange => 0,
	TrayTipTimeLength => 3000, #in ms
	TAG_use_latin1_if_possible => 1,
	TAG_no_desync	=> 1,
	TAG_keep_id3v2_ver  => 0,
	'TAG_write_id3v2.4' => 0,
	TAG_id3v1_encoding => 'iso-8859-1',
	TAG_auto_check_current => 1,
	Simplehttp_CacheSize => 200*1024,
	CustomKeyBindings => '',
	ArtistSplit	=> ' & |, ',
);

our $GlobalKeyBindings='Insert OpenSearch c-q EnqueueSelected p PlayPause c OpenContext q OpenQueue ca-f ToggleFullscreenLayout';
%GlobalBoundKeys=%{ make_keybindingshash($GlobalKeyBindings) };


sub make_keybindingshash
{	my $string=$_[0];
	my @list= ExtractNameAndOptions($string);
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

our $NBVolIcons; my $TrayIconFile;
my $icon_factory;

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
			$icons{$name}=$dir.SLASH.$file;
		}
		closedir $dh;
	}

	my @dirs=($HomeDir.'icons');
	if (my $theme=$Options{IconTheme})
	{	my $dir=$HomeDir.'icons'.SLASH.$theme;
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
			$icons{$name}=$dir.SLASH.$file;
		}
		closedir $dh;
	}

	$TrayIconFile=delete $icons{trayicon} || PIXPATH.'trayicon.png';
	$TrayIcon->child->child->set_from_file($TrayIconFile) if $TrayIcon;
	Gtk2::Window->set_default_icon_from_file( delete $icons{gmusicbrowser} || PIXPATH.'gmusicbrowser.png' );

	$NBVolIcons=0;
	$NBVolIcons++ while $icons{'gmb-vol'.$NBVolIcons};

	$icon_factory->remove_default if $icon_factory;
	$icon_factory=Gtk2::IconFactory->new;
	$icon_factory->add_default;
	while (my ($stock_id,$file)=each %icons)
	{	next unless $file;
		my %h= ( stock_id => $stock_id );
			#label    => $$ref[1],
			#modifier => [],
			#keyval   => $Gtk2::Gdk::Keysyms{L},
			#translation_domain => 'gtk2-perl-example',
		if (exists $StockLabel{$stock_id}) { $h{label}=$StockLabel{$stock_id}; }
		Gtk2::Stock->add(\%h) unless Gtk2::Stock->lookup($stock_id);
		my $icon_set= eval {Gtk2::IconSet->new_from_pixbuf( Gtk2::Gdk::Pixbuf->new_from_file($file) )};
		warn $@ if $@;
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

sub FindID
{	local $_=$_[0];
	if (m/\D/)
	{	s/($QSLASH)$QSLASH+/$1/og;
		if (s/$QSLASH([^$QSLASH]+)$//o && $GetIDFromFile{$_})
		{	return $GetIDFromFile{$_}{$1};
		}
		return undef;
	}
	$_=undef unless defined && $Songs[$_];
	return $_;
}
sub GetTagValue
{	my ($ID,$field)=@_;
	warn "GetTagValue : $ID,$field\n" if $debug;
	my $fieldnb=$TagIndex{$field};
	unless (defined $fieldnb) { warn "GetTagValue : invalid field\n"; return undef }
	$ID=FindID($ID);
	unless (defined $ID) { warn "GetTagValue : song not found\n"; return undef }
	my $value=$Songs[$ID][$fieldnb];
	if ($TagProp[$fieldnb][2] eq 'f') {$value=~s/\00/\t/g}
	return $value;
}
sub SetTagValue
{	my ($ID,$field,$value)=@_;
	warn "SetTagValue : $ID,$field,$value\n" if $debug;
	my $fieldnb=$TagIndex{$field}; #FIXME some fields should not be editable
	unless (defined $fieldnb) { warn "SetTagValue : invalid field\n"; return FALSE }
	$ID=FindID($ID);
	unless (defined $ID) { warn "SetTagValue : song not found\n"; return FALSE }
	if ($TagProp[$fieldnb][2]=~m/[ndl]/) {return FALSE unless $value=~m/^\d+$/}
	elsif ($TagProp[$fieldnb][2] eq 'f') {$value=~s/\t/\x00/g}
	$Songs[$ID][$fieldnb]=$value;
	SongChanged($ID,$fieldnb);
	return TRUE;
}


our %Command=		#contains sub,description,argument_tip, argument_regex or code returning a widget, or '0' to hide it from the GUI edit dialog
(	NextSongInPlaylist=> [\&NextSongInPlaylist,		_"Next Song In Playlist"],
	PrevSongInPlaylist=> [\&PrevSongInPlaylist,		_"Previous Song In Playlist"],
	NextSong	=> [\&NextSong,				_"Next Song"],
	PrevSong	=> [\&PrevSong,				_"Previous Song"],
	PlayPause	=> [\&PlayPause,			_"Play/Pause"],
	Forward		=> [\&Forward,				_"Forward",_"Number of seconds",qr/^\d+$/],
	Rewind		=> [\&Rewind,				_"Rewind",_"Number of seconds",qr/^\d+$/],
	Seek		=> [sub {SkipTo($_[1])},		_"Seek",_"Number of seconds",qr/^\d+$/],
	Stop		=> [\&Stop,				_"Stop"],
	Browser		=> [\&Playlist,				_"Open Browser"],
	OpenQueue	=> [\&EditQueue,			_"Open Queue window"],
	OpenSearch	=> [sub { Layout::Window->new($Options{LayoutS}); },	_"Open Search window"],
	OpenContext	=> [sub { Layout::Window->new('Context');},	_"Open Context window"],
	OpenCustom	=> [sub { Layout::Window->new($_[1]); },	_"Open Custom window",_"Name of layout", sub { TextCombo->new( Layout::get_layout_list() ); }],
	PopupCustom	=> [sub { PopupLayout($_[1],$_[0]); },		_"Popup Custom window",_"Name of layout", sub { TextCombo->new( Layout::get_layout_list() ); }],
	CloseWindow	=> [sub { $_[0]->get_toplevel->close_window if $_[0];}, _"Close Window"],
	SetPlayerLayout => [sub { $Options{Layout}=$_[1]; set_layout(); },_"Set player window layout",_"Name of layout", sub {  TextCombo->new( Layout::get_layout_list('G') ); }, ],
	OpenPref	=> [\&PrefDialog,			_"Open Preference window"],
	OpenSongProp	=> [sub { DialogSongProp($SongID) if defined $SongID }, _"Edit Current Song Properties"],
	EditSelectedSongsProperties => [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DialogSongsProp(@IDs) if @IDs; },		_"Edit selected song properties"],
	ShowHide	=> [\&ShowHide,				_"Show/Hide"],
	Quit		=> [\&Quit,				_"Quit"],
	Save		=> [\&SaveTags,				_"Save Tags/Options"],
	ChangeDisplay	=> [\&ChangeDisplay,			_"Change Display",_"Display (:1 or host:0 for example)",qr/:\d/],
	GoToCurrentSong => [\&Layout::GoToCurrentSong,		_"Select current song"],
	EnqueueSelected => [\&Layout::EnqueueSelected,		_"Enqueue Selected Songs"],
	DeleteSelected => [sub { my $songlist=GetSonglist($_[0]) or return; my @IDs=$songlist->GetSelectedIDs; DeleteFiles(\@IDs); },		_"Delete Selected Songs"],
	EnqueueArtist	=> [sub {EnqueueArtist($SongID)},	_"Enqueue Songs from Current Artist"],
	EnqueueAlbum	=> [sub {EnqueueAlbum($SongID)},	_"Enqueue Songs from Current Album"],
	EnqueueAction	=> [sub {EnqueueAction($_[1])},		_"Enqueue Action", _"Queue mode" ,sub { TextCombo->new({map {$_ => $QActions{$_}[2]} sort keys %QActions}) }],
	ClearQueue	=> [\&::ClearQueue,			_"Clear queue"],
	IncVolume	=> [sub {ChangeVol('up')},		_"Increase Volume"],
	DecVolume	=> [sub {ChangeVol('down')},		_"Decrease Volume"],
	TogMute		=> [sub {ChangeVol('mute')},		_"Mute/Unmute"],
	RunSysCmd	=> [\&run_system_cmd,			_"Run system command",_"Shell command",qr/./],
	RunPerlCode	=> [sub {eval $_[1]},			_"Run perl code",_"perl code",qr/./],
	TogArtistLock	=> [sub {ToggleLock(SONG_ARTIST)},	_"Toggle Artist Lock"],
	TogAlbumLock	=> [sub {ToggleLock(SONG_ALBUM)},	_"Toggle Album Lock"],
	SetSongRating	=> [sub {return unless defined $SongID && $_[1]=~m/^\d*$/; $Songs[$SongID][SONG_RATING]=$_[1]; SongChanged($SongID,SONG_RATING); },				_"Set Current Song Rating", _"Rating between 0 and 100, or empty for default", qr/^\d*$/],
	ToggleFullscreen=> 	[\&Layout::ToggleFullscreen,	_"Toggle fullscreen mode"],
	ToggleFullscreenLayout=>[\&ToggleFullscreenLayout,	_"Toggle the fullscreen layout"],
	OpenFiles	=> [sub { DoActionForList('playlist',Url_to_IDs($_[1])); }, _"Play a list of files/folders", _"url-encoded list of files/folders",0],
	AddFilesToPlaylist=> [sub { DoActionForList('addplay',Url_to_IDs($_[1])); }, _"Add a list of files/folders to the playlist", _"url-encoded list of files/folders",0],
	InsertFilesInPlaylist=> [sub { DoActionForList('insertplay',Url_to_IDs($_[1])); }, _"Insert a list of files/folders at the start of the playlist", _"url-encoded list of files/folders",0],
	EnqueueFiles	=> [sub { DoActionForList('queue',Url_to_IDs($_[1])); }, _"Enqueue a list of files/folders", _"url-encoded list of files/folders",0],
	AddToLibrary	=> [sub { AddToLibrary(split / /,$_[1]); }, _"Add files/folders to library", _"url-encoded list of files/folders",0],
	SetFocusOn	=> [sub { my ($w,$name)=@_;return unless $w; $w=find_ancestor($w,'Layout');$w->SetFocusOn($name) if $w;},_"Set focus on a layout widget", _"Widget name",0],
	ShowHideWidget	=> [sub { my ($w,$name)=@_;return unless $w; $w=find_ancestor($w,'Layout');$w->ShowHide(split / +/,$name,2) if $w;},_"Show/Hide layout widget(s)", _"|-separated list of widget names",0],
	PopupTrayTip	=> [sub {ShowTraytip($_[1])}, _"Popup Traytip",_"Number of milliseconds",qr/^\d*$/ ],
	SetSongLabel	=> [sub{ ToggleLabel($_[1],$::SongID,1); }, _"Add a label to the current song", _"Label",qr/./],
	UnsetSongLabel	=> [sub{ ToggleLabel($_[1],$::SongID,0); }, _"Remove a label from the current song", _"Label",qr/./],
	ToggleSongLabel	=> [sub{ ToggleLabel($_[1],$::SongID); }, _"Toggle a label of the current song", _"Label",qr/./],
);

sub run_command
{	my ($self,$cmd)=@_; #self must be a widget or undef
	$cmd="$1($2)" if $cmd=~m/^(\w+) (.*)/;
	($cmd, my$arg)= $cmd=~m/^(\w+)(?:\((.*)\))?$/;
	warn "executing $cmd($arg) (with self=$self)" if $::debug;
	$Command{$cmd}[0]->($self,$arg) if $Command{$cmd};
}

sub run_system_cmd
{	my $syscmd=$_[1];
	#my @cmd=split / /,$syscmd;
	#system @cmd;
	my @cmd=grep defined, $syscmd=~m/(?:(?:"(.*[^\\])")|([^ ]*[^ \\]))(?: |$)/g;
	return unless @cmd;
	if ($syscmd=~m/%F/)
	{	my @files;
		if ($_[0] and my $songlist=GetSonglist($_[0])) { @files=map $Songs[$_][SONG_PATH].SLASH.$Songs[$_][SONG_FILE], $songlist->GetSelectedIDs; }
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
	for my $cmd (sort keys %Command)
	{	my $print="$cmd : $Command{$cmd}[1]";
		$print.="  (argument : $Command{$cmd}[2])" if $Command{$cmd}[2];
		print "$print\n"
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
our ($Play_package,%Packs); my $PlayNext_package;
require 'gmusicbrowser_mplayer.pm';
require 'gmusicbrowser_123.pm';
eval {require 'gmusicbrowser_gstreamer-0.10.pm';} || warn $@;
#require 'gmusicbrowser_win32.pm';
require 'gmusicbrowser_server.pm';
for my $p (qw/Play_Server Play_GST Play_123 Play_mplayer Play_GST_server/) { $Packs{$p}=$p->init; }


&ReadSavedTags;
$Options{version}=VERSION;
LoadIcons();

$Play_package=$Options{AudioOut};
$Play_package= $Options{use_GST_for_server} ? 'Play_GST_server' : 'Play_Server' if $CmdLine{server};
$Play_package='Play_GST' if $CmdLine{gst};
for my $p ($Play_package, qw/Play_GST Play_123 Play_mplayer Play_Server/)
{	next unless $p && $Packs{$p};
	$Options{AudioOut}||=$p;
	$Play_package=$p;
	last;
}
$Play_package=$Packs{$Play_package};

IdleCheck() if $Options{StartCheck} && !$CmdLine{nocheck};
IdleScan()  if $Options{StartScan}  && !$CmdLine{noscan};
$Options{Icecast_port}=$CmdLine{port} if $CmdLine{port};

#$ListMode=[] if $CmdLine{empty};

Select(	filter => ($SelectedFilter ? $SelectedFilter : ''),
	'sort' => $Options{Sort},
	song => (defined $SongID ? 'keep' : 'first'),
	play => ( ($CmdLine{play} && !$PlayTime)? 1 : undef),
	staticlist => $ListMode
      );
#SkipTo($PlayTime) if $PlayTime; #gstreamer (how I use it) needs the mainloop running to skip, so this is done after the main window is created

Layout::InitLayouts;
LoadPlugins();
for my $p (keys %Plugins)
{	ActivatePlugin($p,'startup') if $Options{'PLUGIN_'.$p};
}

our $Tooltips=Gtk2::Tooltips->new;
$MainWindow=Layout::Window->new($CmdLine{layout}||$Options{Layout});
&ShowHide if $CmdLine{hide};
SkipTo($PlayTime) if $PlayTime; #done only now because of gstreamer

CreateTrayIcon();

run_command(undef,$CmdLine{runcmd}) if $CmdLine{runcmd};

#--------------------------------------------------------------
Gtk2->main;
exit;

sub Edittag_mode
{	my @dirs=@_;
	#make path absolute
	file_name_is_absolute($_) or $_=$CurrentDir.SLASH.$_ for @dirs;
	$re_artist=qr/$/;
	IdleScan(@dirs);
	IdleDo('9_SkipLength',undef,sub {undef @LengthEstimated});
	Gtk2->main_iteration while Gtk2->events_pending;

	my $dialog = Gtk2::Dialog->new( _"Editing tags", undef,'modal',
				'gtk-save' => 'ok',
				'gtk-cancel' => 'none');
	$dialog->signal_connect(destroy => sub {exit});
	$dialog->set_default_size(500, 600);
	my $edittag;
	if (@Library==1)
	{	$edittag=EditTagSimple->new($dialog,$Library[0]);
		$dialog->signal_connect( response => sub
		 {	my ($dialog,$response)=@_;
			$edittag->save if $response eq 'ok';
			exit;
		 });
	}
	elsif (@Library>1)
	{	$edittag=MassTag->new($dialog,@Library);
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
		last unless $widget;
	}
	return $widget;
}
sub Hpack
{	my @list=@_;
	my $pad=2;
	my $end=FALSE;
	my $hbox=Gtk2::HBox->new;
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
		{	$w=Vpack(@$w);
		}
		if ($end)	{$hbox->pack_end  ($w,$exp,$exp,$pad);}
		else		{$hbox->pack_start($w,$exp,$exp,$pad);}
	}
	return $hbox;
}
sub Vpack
{	my @list=@_;
	my $pad=2;
	my $end=FALSE;
	my $vbox=Gtk2::VBox->new;
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
		{	$w=Hpack(@$w);
		}
		if ($end)	{$vbox->pack_end  ($w,$exp,$exp,$pad);}
		else		{$vbox->pack_start($w,$exp,$exp,$pad);}
	}
	return $vbox;
}

sub GetGenresList
{	no warnings 'uninitialized';
	my %h;
	$h{$_}=undef for map split(/\x00/, $::Songs[$_][::SONG_GENRE]), @::Library;
	return [sort keys %h];
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
	@ToScan=@ToAdd=();
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
		if (exists $Command{$cmd}) { Glib::Timeout->add(0, sub {&{$Command{$cmd}[0]}($_[0],$arg); 0;},GetActiveWindow()); warn "fifo:received $cmd\n" if $debug; }
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

sub LoadPlugins
{	my @list;
	for my $dirname ($DATADIR.SLASH.'plugins', $HomeDir.'plugins')
	{	next unless -d $dirname;
		opendir my($dir),$dirname;
		while (my $file=readdir $dir)
		{	next unless $file=~m/\.p[lm]$/;
			push @list,$dirname.SLASH.$file;
		}
		close $dir;
	}
	push @list,@{$CmdLine{plugins}} if $CmdLine{plugins};

	my %loaded; $loaded{$_}= $_->{file} for grep $_->{loaded}, values %Plugins;
	for my $file (grep !$loaded{$_}, @list)
	{	warn "Reading plugin $file\n" if $::debug;
		my ($found,$id);
		open my$fh,'<',$file;
		while (my $line=<$fh>)
		{	if ($line=~m/^=gmbplugin (\D\w+)/)
			{	my $id=$1;
				my @lines;
				while ($line=<$fh>)
				{	last if $line=~m/^=cut/;
					chomp $line;
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
			elsif ($line=~m/^\s*[^#\n]/) {last}
		}
		close $fh;
		warn "No plugin found in $file, maybe it uses an old format\n" unless $found;
	}
}
sub ActivatePlugin
{	my ($plugin,$startup)=@_;
	my $ref=$Plugins{$plugin};
	if ( $ref->{loaded} || do $ref->{file} )
	{	$ref->{loaded}=1;
		my $package='GMB::Plugin::'.$plugin;
		$package->Start($startup);
		warn "loaded plugin $plugin : OK\n" if $debug;
		$Options{'PLUGIN_'.$plugin}=1;
	}
	else
	{	warn "plugin $ref->{file} failed : $@\n";
		$ref->{error}=$@;
	}
}
sub DeactivatePlugin
{	my $plugin=$_[0];
	my $package='GMB::Plugin::'.$plugin;
	delete $Options{'PLUGIN_'.$plugin};
	$package->Stop if $Plugins{$plugin}{loaded};
}

sub ChangeVol
{	my $cmd;
	if ($_[0] eq 'mute')
	{	$cmd=$Play_package->GetMute? 'unmute':'mute' ;
	}
	else
	{	$cmd=(ref $_[0])? $_[1]->direction : $_[0];
		if	($Play_package->GetMute)	{$cmd='unmute'}
		elsif	($cmd eq 'up')	{$cmd="+$VolInc"}
		elsif	($cmd eq 'down'){$cmd="-$VolInc"}
	}
	warn "volume $cmd ...\n" if $debug;
	UpdateVol($cmd);
	warn "volume $cmd" if $debug;
}

sub UpdateVol
{	$Play_package->SetVolume($_[0]);
}
sub GetVol
{	$Play_package->GetVolume;
}
sub GetMute
{	$Play_package->GetMute;
}

sub makeVolSlider
{	my $opt1=$_[0];
	my $vol=$Play_package->GetVolume;
	my $adj=Gtk2::Adjustment->new($vol, 0, 100, 1, 10, 0);
	my $slider=$opt1->{horizontal}? 'Gtk2::HScale' : 'Gtk2::VScale';
	$slider=$slider->new($adj);
	$slider->set_draw_value(FALSE) if $opt1->{hide};
	$slider->set_digits(0);
	$slider->set_inverted(TRUE) unless $opt1->{horizontal};
	$slider->signal_connect(value_changed => sub { UpdateVol($_[0]->get_value); 1; });
	return $slider
}

sub PopupVol
{	if ($Play_package->GetVolume <0) { ErrorMessage($Play_package->GetVolumeError); return }
	my $slider=makeVolSlider();
	$slider->set_size_request(-1, 100);
	my $popup=Gtk2::Window->new('popup');
	$popup->signal_connect(leave_notify_event => sub { $popup->destroy if $_[1]->detail ne 'inferior';0; });
	my $frame=Gtk2::Frame->new;
	my $vbox=Gtk2::VBox->new;
	$popup->add($frame);
	$frame->add($vbox);
	$vbox->add($slider);
	$frame->set_shadow_type('out');
	$vbox->set_border_width(5);
	#$popup->set_modal(TRUE);
	$popup->set_position('mouse');
	$popup->show_all;
	return 0;
}

sub FirstTime
{ %SavedSorts=
  (	_"Path,File"	=> SONG_UPATH.' '.SONG_UFILE,
	_"Date"		=> SONG_DATE,
	_"Title"	=> SONG_TITLE,
	_"Last played"	=> SONG_LASTPLAY,
	_"Artist,Album,Disc,Track"	=> join(' ',SONG_ARTIST,SONG_ALBUM,SONG_DISC,SONG_TRACK),
	_"Artist,Date,Album,Disc,Track"	=> join(' ',SONG_ARTIST,SONG_DATE,SONG_ALBUM,SONG_DISC,SONG_TRACK),
	_"Path,Album,Disc,Track,File"	=> join(' ',SONG_UPATH,SONG_ALBUM,SONG_DISC,SONG_TRACK,SONG_UFILE),
  );

  %SavedWRandoms=
  (	_"by rating"	=> 'r1r0,.1,.2,.3,.4,.5,.6,.7,.8,.9,1',
	_"by play count"=> 'r-1n5',
	_"by lastplay"	=> 'r1l10',
	_"by added"	=> 'r-1a50',
	_"by lastplay & play count"	=> 'r1l10'."\x1D".'-1n5',
	_"by lastplay & bootleg"	=> 'r1l10'."\x1D".'-.5fbootleg',
  );

  #Default filters
  %SavedFilters=
  (	_"never played"		=> SONG_NBPLAY.'<1',
	_"50 Most Played"	=> SONG_NBPLAY.'h50',
	_"50 Last Played"	=> SONG_LASTPLAY.'h50',
	_"50 Last Added"	=> SONG_ADDED.'h50',
	_"Played Today"		=> SONG_LASTPLAY.'>1d',
	_"Added Today"		=> SONG_ADDED.'>1d',
	_"played>4"		=> SONG_NBPLAY.'>4',
	_"not bootleg"		=> '-'.SONG_LABELS.'fbootleg',
  );

  %SongTree::Groupings= #FIXME
  (	_"None"			=> '',
	_"Artist & album"	=> 'artist|simple|album|pic',
	_"Album with picture"	=> 'album|pic',
	_"Album"		=> 'album|simple',
	_"Folder"		=> 'folder|artistalbum',
  );

  if (-r $DATADIR.SLASH.'gmbrc')
  {	open SAVETAG,'<:utf8', $DATADIR.SLASH.'gmbrc';
	while (my $line=<SAVETAG>)
	{	chomp $line;
		$Options{$1}=$2 if $line=~m/^\s*([^#=][^=]*?)\s*=\s*(.+)\s*$/;
	}
	close SAVETAG;
  }

  $_=Filter->new($_) for values %SavedFilters;
  $Labels{$_}=undef for split "\x1D",$Options{Labels};
  $re_artist=qr/ & |, /;
}


sub ReadSavedTags	#load tags _and_ settings
{	if (-d $SaveFile) {$SaveFile.=SLASH.'tags'}
	unless (-r $SaveFile)
	{	FirstTime(); return;
	}
	setlocale(LC_NUMERIC, 'C');
	warn "Reading saved tags in $SaveFile ...\n";
	open SAVETAG,'<:utf8',$SaveFile;
	while (<SAVETAG>)
	{	chomp; last if $_ eq '';
		$Options{$1}=$2 if m/^([^=]+)=(.*)$/;
	}
	my $oldversion=delete $Options{version} || VERSION;
	if ($oldversion<0.9464) {delete $Options{$_} for qw/BrowserTotalMode FilterPane0Page FilterPane0min FilterPane1Page FilterPane1min LCols LSort PlayerWinPos SCols Sticky WSBrowser WSEditQueue paned StickyFilters/} #cleanup old options
	if ($oldversion<0.9540)
	{	$Options{Layout}='default player layout' if $Options{Layout} eq 'default';
		$Options{'Layout_default player layout'}=delete $Options{Layout_default};
	}
	if ($oldversion<=1.0)
	{	for my $key (grep m/^PLUGIN_MozEmbed/,keys %Options)
		{	my $old=$key;
			$key=~s/^PLUGIN_MozEmbed/PLUGIN_WebContext/;
			$Options{$key}=delete $Options{$old};
		}
	}
	#@Library=();
	$Options{ArtistSplit}||=' & |, ';
	$re_artist=qr/$Options{ArtistSplit}/;
	my $ID=my $oldID=-1; my @newIDs;
	no warnings 'utf8'; # to prevent 'utf8 "\xE9" does not map to Unicode' type warnings about SONG_PATH and SONG_FILE which are stored as they are on the filesystem #FIXME find a better way to read lines containing both utf8 and unknown encoding
	while (<SAVETAG>)
	{	chomp; last if $_ eq '';
		$oldID++;
		next if $_ eq ' ';	#deleted entry
		s#\\([n\\])#$1 eq "n" ? "\n" : "\\"#ge unless $oldversion<0.9603;
		my @song=split "\x1D";
		unless ($song[SONG_UPATH] && ($song[SONG_UFILE] || $song[SONG_UPATH]=~m#^http://#) && $song[SONG_ADDED])
		{	warn "skipping invalid song entry : @song\n";
			next;
		}
		$ID++;
		push @Songs,\@song;
		$newIDs[$oldID]=$ID;
		$song[SONG_PATH]=$song[SONG_UPATH];
		$song[SONG_FILE]=$song[SONG_UFILE];
		_utf8_off($song[SONG_PATH]);
		_utf8_off($song[SONG_FILE]);
		$song[SONG_UPATH]=filename_to_utf8displayname($song[SONG_PATH]);
		$song[SONG_UFILE]=filename_to_utf8displayname($song[SONG_FILE]);
		$GetIDFromFile{ $song[SONG_PATH] }{ $song[SONG_FILE] }=$ID;
		if (my $m=$song[SONG_MISSINGSINCE])
		{	if ($m=~m/^\d+$/) {AddMissing($ID);next}
			elsif ($m eq 'l') {push @LengthEstimated,$ID}
			elsif ($m eq 'r') {push @ToCheck,$ID}
			elsif ($m eq 'R') {push @Radio,$ID;next}
		}
		elsif (!$song[SONG_MODIF]) { push @ToAdd,$ID;next; }
		push @Library,$ID;
		#warn $song[SONG_PATH].SLASH.$song[SONG_FILE].' not found' unless -f $song[SONG_PATH].SLASH.$song[SONG_FILE];
		AddAA($ID); #Fill %Artist and %Album
	}
	if ($oldversion<0.9581)	#fix duplicated entries caused by a trailing slash in the folder name after a move
	{	for my $ID (@Library)
		{	my $ref=$Songs[$ID];
			next unless $ref->[SONG_PATH]=~m/$QSLASH$/o;
			my $path=$ref->[SONG_PATH];
			my $file=$ref->[SONG_FILE];
			my $cpath=$path; $cpath=~s/$QSLASH+$//o;
			my $dupID=$GetIDFromFile{ $cpath }{ $file };
			if (defined $dupID)
			{	if ($Songs[$dupID][SONG_MISSINGSINCE] && $Songs[$dupID][SONG_MISSINGSINCE]=~m/^\d+$/)
				{	RemoveMissing($dupID);
					$Songs[$dupID]=undef;
				}
				else
				{	RemoveAA($ID,$Songs[$ID]);
					delete $GetIDFromFile{$path}{$file};
					$Songs[$ID]=undef;
					next;
				}
			}
			$ref->[SONG_PATH]=$cpath;
			$ref->[SONG_UPATH]=filename_to_utf8displayname($cpath);
			$GetIDFromFile{$cpath}{$file}=delete $GetIDFromFile{$path}{$file};
		}
		@Library= grep $Songs[$_], @Library;
		for my $p (keys %GetIDFromFile) { delete $GetIDFromFile{$p} unless keys %{ $GetIDFromFile{$p} }; }
		for (@newIDs) { $newIDs[$_]=undef unless $Songs[ $newIDs[$_] ]; }
	}
	while (<SAVETAG>)
	{	chomp; last if $_ eq '';
		my ($key,$p)=split "\x1D";
		next if $p eq '';
		_utf8_off($p);
		$Artist{$key}[AAPIXLIST]=$p if exists $Artist{$key};
	}
	while (<SAVETAG>)
	{	chomp; last if $_ eq '';
		my ($key,$p)=split "\x1D";
		next if $p eq '';
		_utf8_off($p);
		#warn $p.' not found' unless -f $p;
		$Album{$key}[AAPIXLIST]=$p if exists $Album{$key};
	}
	%SavedFilters=();
	%SavedSorts=();
	%SavedWRandoms=();
	%SavedLists=();
	%SongTree::Groupings=();
	while (<SAVETAG>)
	{	chomp;# last if $_ eq '';
		my ($key,$val)=split "\x1D",$_,2;
		$key=~s/^(.)//;
		if ($1 eq 'F')
		{	$SavedFilters{$key}=Filter->new($val);
		}
		elsif ($1 eq 'S')
		{	$SavedSorts{$key}=$val;
		}
		elsif ($1 eq 'R')
		{	$SavedWRandoms{$key}=$val;
		}
		elsif ($1 eq 'L')
		{	$SavedLists{$key}=[grep defined,map $newIDs[$_],split / /,$val];
		}
		elsif ($1 eq 'G')
		{	$SongTree::Groupings{$key}=$val;
		}
	}
	close SAVETAG;

	@Recent= grep defined,map $newIDs[$_],split / /,delete $Options{RecentIDs} if exists $Options{RecentIDs};
	if (my $f=delete $Options{LastPlayFilter})
	{	if ($Options{RememberPlayFilter} && $f=~s/^(filter|savedlist|list) //)
		{	if ($1 eq 'filter') {$SelectedFilter=Filter->new($f)}
			elsif ($1 eq 'savedlist') {$ListMode=$f}
			elsif ($1 eq 'list') {$ListMode=[grep defined,map $newIDs[$_],split / /,$f]}
		}
	}
	if ($Options{RememberPlayFilter})
	{	$TogLock=$Options{Lock};
	}
	if ($Options{RememberPlaySong} && exists $Options{SavedSongID})
	 { $SongID=$newIDs[delete $Options{SavedSongID}]; }
	if ($Options{RememberPlaySong} && $Options{RememberPlayTime}) { $PlayTime=delete $Options{SavedPlayTime}; }
	_utf8_off($Options{Path});
	$Options{Path}||='';
	@LibraryPath=	split "\x1D",$Options{Path};
	s/\x00+$// for @LibraryPath; #FIXME ugly fix for paths ending with special char and not encoded in utf8, some \x00 are added when read with :utf8
	$Options{Labels}=delete $Options{Flags} if $oldversion<=0.9571;
	$Labels{$_}=undef for split "\x1D",$Options{Labels};
	%CustomBoundKeys=%{ make_keybindingshash($Options{CustomKeyBindings}) };
	setlocale(LC_NUMERIC, '');
	&launchIdleLoop unless defined $IdleLoop;
	UpdateAAYear();
	AddFullscreenButton() if $Options{AddFullscreenButton};
	warn "Reading saved tags in $SaveFile ... done\n";
}
sub SaveTags	#save tags _and_ settings
{	HasChanged('Save');
	warn "Writing tags in $SaveFile ...\n";
	setlocale(LC_NUMERIC, 'C');
	my $savedir=$SaveFile;
	$savedir=~s/([^$QSLASH]+)$//o;
	my $savefilename=$1;
	mkdir $savedir if $savedir ne '' && !-d $savedir;
	$Options{Lock}= $TogLock || '';
	if ($ListMode)	{ $Options{LastPlayFilter}=ref $ListMode? 'list '.join(' ',@$ListMode)
								: 'savedlist '.$ListMode;
			}
	elsif ($SelectedFilter) { $Options{LastPlayFilter}='filter '.$SelectedFilter->{string}; }
	$Options{Labels}=join "\x1D",sort keys %Labels;
	$Options{Path}  =join "\x1D",@LibraryPath;
	_utf8_on($Options{Path});
	$Options{RecentIDs}=join ' ',@Recent;
	$Options{SavedSongID}=$SongID if $Options{RememberPlaySong} && defined $SongID;

	$Options{SavedOn}= time;

	my $tooold=0;
	my @sessions=split ' ',$Options{Sessions};
	unless (@sessions && $DAYNB==$sessions[0])
	{	unshift @sessions,$DAYNB;
		$tooold=pop @sessions if @sessions>20;
		$Options{Sessions}=join ' ',@sessions;
	}
	for my $key (grep m/^Layout_/, keys %Options) #cleanup options for layout that haven't been seen for a while
	{	$key=~s/^Layout_//;
		my $key2='LayoutLastSeen_'.$key;
		if (exists $Layout::Layouts{$key}) { delete $Options{$key2}; }
		elsif (!$Options{$key2})	{ $Options{$key2}=$DAYNB; }
		elsif ($Options{$key2}<$tooold)	{ delete $Options{$_} for $key,$key2; }
	}

	my $error;
	open SAVETAG,'>:utf8',$SaveFile.'.new' or warn "Error opening '$SaveFile.new' for writing : $!";
	for my $key (sort keys %Options)
	{	print SAVETAG $key.'='.$Options{$key}."\n"  or $error++;
	}
	print SAVETAG "\n"  or $error++;
	no warnings 'uninitialized';
	for my $song (@Songs)
	{	if (!$song || ($$song[SONG_MISSINGSINCE] && ($$song[SONG_MISSINGSINCE]=~m/^\d/ && $$song[SONG_MISSINGSINCE]<$tooold) || $$song[SONG_MISSINGSINCE]=~m/T/ ))
		{ print SAVETAG " \n"  or $error++;next; }
		_utf8_on($$song[SONG_PATH]);
		_utf8_on($$song[SONG_FILE]);
		my $line=join "\x1D",@$song[@SAVEDFIELDS];
		_utf8_off($$song[SONG_PATH]); #FIXME ugly
		_utf8_off($$song[SONG_FILE]); #FIXME
		$line=~s#\\#\\\\#g; $line=~s#\n#\\n#g;
		if ($line eq '') {warn "trying to save empty Song entry" if $debug;next}
		print SAVETAG $line."\n"  or $error++;
	}
	print SAVETAG "\n"  or $error++;
	while ( my ($a,$ref)=each %Artist )
	{	my $p=$ref->[AAPIXLIST];
		next unless defined $p;
		_utf8_on($p);
		next unless @$ref[AALIST];
		print SAVETAG join("\x1D",$a,$p)."\n"  or $error++;
	}
	print SAVETAG "\n"  or $error++;
	while ( my ($a,$ref)=each %Album )
	{	my $p=$ref->[AAPIXLIST];
		next unless defined $p;
		_utf8_on($p);
		next unless @$ref[AALIST];
		print SAVETAG join("\x1D",$a,$p)."\n"  or $error++;
	}
	use warnings 'uninitialized';
	print SAVETAG "\n"  or $error++;
	for my $name (sort keys %SavedFilters)
	{	my $val=$SavedFilters{$name}; next unless defined $val;
		print SAVETAG "F$name\x1D".$val->{string}."\n"  or $error++;
	}
	for my $name (sort keys %SavedSorts)
	{	my $val=$SavedSorts{$name}; next unless defined $val;
		print SAVETAG "S$name\x1D$val\n"  or $error++;
	}
	for my $name (sort keys %SavedWRandoms)
	{	my $val=$SavedWRandoms{$name}; next unless defined $val;
		print SAVETAG "R$name\x1D$val\n"  or $error++;
	}
	for my $name (sort keys %SavedLists)
	{	my $val=$SavedLists{$name}; next unless defined $val;
		print SAVETAG "L$name\x1D".join(' ',@$val)."\n"  or $error++;
	}
	for my $name (sort keys %SongTree::Groupings)
	{	my $val=$SongTree::Groupings{$name}; next unless defined $val;
		print SAVETAG "G$name\x1D$val\n"  or $error++;
	}
	close SAVETAG  or $error++;
	setlocale(LC_NUMERIC, '');
	if ($error)
	{	rename $SaveFile.'.new',$SaveFile.'.error';
		warn "Writing tags in $SaveFile ... error\n";
		return;
	}
	if (-e $SaveFile)
	{	{	last unless -e $SaveFile.'.bak';
			last unless (open my $file,'<',$SaveFile.'.bak');
			local $_; my $date;
			while (<$file>) { if (m/^SavedOn=(\d+)/) {$date=$1;last} last unless m/=/}
			close $file;
			last unless $date;
			last unless $date>20100000; #for version 0.9623, used a different SavedOn format #DELME
			my ($day,$month,$year)=(localtime($date))[3,4,5];
			$date= sprintf '%04d%02d%02d',$year+1900,$month+1,$day;
			last if -e $SaveFile.'.bak.'.$date;
			rename $SaveFile.'.bak', $SaveFile.'.bak.'.$date;
			opendir my($dh), $savedir;
			my @files=sort grep m/^\Q$savefilename\E\.bak\.\d{8}$/, readdir $dh;
			closedir $dh;
			last unless @files>5;
			splice @files,-5;	#keep the 5 newest versions
			unlink $savedir.SLASH.$_ for @files;
		}
		rename $SaveFile,$SaveFile.'.bak';
	}
	rename $SaveFile.'.new',$SaveFile;
	warn "Writing tags in $SaveFile ... done\n";
}

sub SetWSize
{	my ($win,$wkey)=@_;
	$wkey='WS'.$wkey;
	$win->resize(split ' ',$Options{$wkey},2) if $Options{$wkey};
	$win->signal_connect(unrealize => sub
		{ $::Options{$_[1]}=join ' ',$_[0]->get_size; }
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
		$TogPlay=1;
		HasChanged('Playing');
	}
	else
	{	Play($sec);
	}
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
	if (defined $PlayingID)
	{	if ($PlayNext_package) {Stop();}
		else { $Play_package->Stop(1); }
		&Played;
	}
	$StartedAt=$sec||0;
	$StartTime=time;
	$PlayingID=$SongID;
	my $f=$Songs[$SongID][SONG_PATH].SLASH.$Songs[$SongID][SONG_FILE];
	$Play_package->Play($f,$sec);
	$TogPlay=1;
	UpdateTime(0);
	HasChanged('Playing');
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
{	UpdateTime($Songs[$SongID][SONG_LENGTH]);
	end_of_file();
}

sub end_of_file
{	SwitchPlayPackage() if $PlayNext_package;
	$About_to_NextSong=1;
	&Played;
	return unless $About_to_NextSong;	#with a playfilter based on playcount, the NextSong can happen in &Played
	$About_to_NextSong=undef;
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
{	$Play_package->Close;
	$Play_package=$PlayNext_package;
	#$Play_package->reinit; #FIXME
	$PlayNext_package=undef;
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
	my $f=($Songs[$SongID][SONG_LENGTH]<600)? '%01d:%02d' : '%02d:%02d';
	if ($_[0])
	{	$f='-'.$f;
		$time= $Songs[$SongID][SONG_LENGTH]-$time;
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
	unless (@Recent && $Recent[0]==$ID)
	{	unshift @Recent,$ID;
		pop @Recent if @Recent>80;
	}

	return unless defined $PlayTime;
	$PlayedPartial= $PlayTime-$StartedAt < $Options{PlayedPercent}*$Songs[$ID][SONG_LENGTH];
	if ($PlayedPartial) #FIXME maybe only count as a skip if played less than ~20% ?
	{	$Songs[$ID][SONG_NBSKIP]++;
		$Songs[$ID][SONG_LASTSKIP]=$StartTime;
		SongChanged($ID,SONG_NBPLAY,SONG_LASTSKIP);
	}
	else
	{	$Songs[$ID][SONG_NBPLAY]++;
		$Songs[$ID][SONG_LASTPLAY]=$StartTime;
		SongChanged($ID,SONG_NBPLAY,SONG_LASTPLAY);
	}
}

sub Get_PPSQ_Icon
{	my ($ID,$not)=($_[0],$_[1]);
	return
	 defined $::SongID && !$not && $ID==$::SongID ?
	 (	$::TogPlay		? 'gtk-media-play' :
		defined $::TogPlay	? 'gtk-media-pause':
		'gtk-media-stop'
	 ) :
	 (@::Queue && grep $ID==$_, @::Queue) ? 'gmb-queue' : undef;
}

sub ClearQueue
{	@Queue=();
	$QueueAction='';
	HasChanged('Queue');
}
sub ShuffleQueue
{	my @rand;
	push @rand,rand for 0..$#Queue;
	@Queue=map $Queue[$_], sort { $rand[$a] <=> $rand[$b] } 0..$#Queue;
	HasChanged('Queue');
}

sub EnqueueAlbum
{	my $key=$Songs[shift][SONG_ALBUM];
	Enqueue( @{$Album{$key}[AALIST]} );
}
sub EnqueueArtist
{	my @l=split /$re_artist/o, $Songs[shift][SONG_ARTIST];
	my %h; $h{$_}=undef for map @{$Artist{$_}[AALIST]}, @l;
	Enqueue( keys %h );
}
sub EnqueueFilter
{	my $l=$_[0]->filter;
	Enqueue(@$l);
}
sub Enqueue
{	my @l=@_;
	SortList(\@l) if @l>1;
	@l=grep $_!=$SongID, @l  if @l>1 && defined $SongID;
	push @Queue,@l;
	# ToggleLock($TogLock) if $TogLock;	#unset lock
	HasChanged(Queue=>'push');
	IdleDo('1_QAuto',10,\&QWaitAutoPlay) if $QueueAction eq 'wait' && !$TogPlay;
}
sub ReplaceQueue
{	@Queue=();
	HasChanged('Queue');
	&Enqueue; #keep @_
}
sub QWaitAutoPlay
{	return if $TogPlay || !@Queue;
	Select(song => (shift @Queue), play=>1);
	HasChanged(Queue => 'shift');
}
sub EnqueueAction
{	$QueueAction=shift;
	if ($QueueAction eq 'autofill')	{ Watch({},'Queue',sub { IdleDo('1_QAuto',10,\&QAutoFill,$_[0]); }); }
	HasChanged(Queue=>'action');
}
sub QAutoFill
{	my $hash=shift;
	if ($hash && ($QueueAction ne 'autofill')) { UnWatch($hash,'Queue'); return }
	my $nb=$Options{MaxAutoFill}-@Queue;
	return unless $nb>0;
	my $mode=$RandomMode? $Options{Sort} : 'r';
	my $r=Random->new($mode);
	$r->MakeRandomList(\@ListPlay);
	my @IDs=$r->Draw($nb,\@Queue);
	return unless @IDs;
	push @Queue,@IDs;
	HasChanged(Queue=>'push');
}

sub GetNeighbourSongs
{	my $nb=shift;
	UpdateSort() if $ToDo{'8_updatesort'};
	my $begin=$Position-$nb;
	my $end=$Position+$nb;
	$begin=0 if $begin<0;
	$end=$#ListPlay if $end>$#ListPlay;
	return @ListPlay[$begin..$end];
}

sub PrevSongInPlaylist
{	UpdateSort() if $ToDo{'8_updatesort'};
	if ($Position==0)
	{	return unless $Options{Repeat};
		$Position=$#ListPlay;
	}
	else { $Position-- }
	UpdateSongID();
}
sub NextSongInPlaylist
{	UpdateSort() if $ToDo{'8_updatesort'};
	if ($Position==$#ListPlay)
	{	return unless $Options{Repeat};
		$Position=0;
	}
	else { $Position++ }
	UpdateSongID();
}

sub GetNextSongs
{	my $nb=shift||1;
	my $list=($nb>1)? 1 : 0;
	my @IDs;
	{ if (@Queue)
	  {	unless ($list) { my $ID=shift @Queue; HasChanged('Queue','shift'); return $ID; }
		push @IDs,_"Queue";
		if ($nb>@Queue) { push @IDs,@Queue; $nb-=@Queue; }
		else { push @IDs,@Queue[0..$nb-1]; last; }
	  }
	  if ($QueueAction)
	  {	push @IDs, $list ? $QActions{$QueueAction}[2] : $QueueAction;
		unless ($list || $QueueAction eq 'wait')
		 { $QueueAction=''; HasChanged('Queue','action'); }
		last;
	  }
	  if ($RandomMode)
	  {	push @IDs,_"Random" if $list;
		push @IDs,$RandomMode->Draw($nb,(defined $SongID? [$SongID] : undef));
		last;
	  }
	  return undef unless @ListPlay;
	  UpdateSort() if $ToDo{'8_updatesort'};
	  my $pos;
	  $pos=FindPositionSong( $IDs[-1] ) if @IDs;
	  $pos=$Position unless defined $pos;
	  push @IDs,_"next" if $list;
	  while ($nb)
	  {	if ( $pos+$nb > $#ListPlay )
		{	push @IDs,@ListPlay[$pos+1..$#ListPlay];
			last unless $Options{Repeat}; #FIXME repeatlock modes
			$nb-=$#ListPlay-$pos;
			$pos=-1;
		}
		else { push @IDs,@ListPlay[$pos+1..$pos+$nb]; last; }
	  }
	}
	return $list ? @IDs : $IDs[0];
}

sub GetPrevSongs
{	my $nb=shift||1;
	my $list=($nb>1)? 1 : 0;
	my @IDs;
	push @IDs,_"Recently played" if $list;
	if ($nb>@Recent) { push @IDs,@Recent; }
	else { push @IDs,@Recent[0..$nb-1]; }
	return $list ? @IDs : $IDs[0];
}

sub PrevSong
{	#my $ID=GetPrevSongs();
	return if @Recent==0;
	$RecentPos||=0;
	if ($SongID==$Recent[$RecentPos]) {$RecentPos++}
	my $ID=$Recent[$RecentPos];
	return unless defined $ID;
	$RecentPos++;
	Select(song => $ID);
}
sub NextSong
{	$About_to_NextSong=undef;
	my $ID=GetNextSongs();
	if (!defined $ID)  { Stop(); return; }
	if ($ID eq 'wait') { Stop(); return; }
	if ($ID eq 'stop') { Stop(); return; }
	if ($ID eq 'quit') { Quit(); }
	if ($ID eq 'turnoff') { Stop(); TurnOff(); return; }
	if ( $Position<$#ListPlay && $ListPlay[$Position+1]==$ID ) { $Position++; UpdateSongID(); }
	else { Select(song => $ID); }
}

sub UpdateLock
{	if (defined $ListMode) { Select(staticlist => $ListMode); }
	else { Select(filter => $SelectedFilter); }
}

sub ToggleLock
{	my ($col,$set)=@_;
	if ($set || !$TogLock || $TogLock!=$col)
	{	$TogLock=$col;
		#&ClearQueue;
	}
	else {undef $TogLock}
	&UpdateLock;
	HasChanged('Lock');
}

sub SetRepeat
{	$::Options{Repeat}=$_[0]||0;
	::HasChanged('Repeat');
}

sub ToggleSort
{	Select('sort' => $Options{AltSort});
}

sub SongListActivate
{	my ($self,$row,$button)=@_; #self is SongList or SongTree
	my $ID=$self->{array}[$row];
	my $activate=$self->{'activate'.$button} || $self->{activate};
	$activate='queue' if $button==2 && !$activate;
	$activate= ($self->{mode} eq 'list' ? (defined $self->{listname} ? 'playlist' : 'play_and_unqueue' ) : 'play') unless $activate;
	my $aftercmd;
	$aftercmd=$1 if $activate=~s/&(.*)$//;
	if	($activate eq 'play_and_unqueue')
	{	splice @Queue,$row,1;
		HasChanged('Queue');
		$activate='play';
	}
	#if	($activate eq 'play')	{ Select(song=>$ID,play=>1,source=>$self->{filter}{source}); }
	if	($activate eq 'play')	{ Select(song=>$ID,play=>1); }
	elsif	($activate eq 'queue')	{ Enqueue($ID); }
	elsif	($activate eq 'playlist')
	{	if ($self->{listname})	{ Select(song=>$ID,play=>1,staticlist=>$self->{listname}); } #FIXME specify position in case the list contains ID multiple times
		elsif ($self->{filter})	{ Select(filter=>$self->{filter},song=>$ID,play=>1); }
		else { Select(song=>$ID,play=>1); } #FIXME check if it can happen and if it's the correct thing to do in this case
	}
	elsif	($activate eq 'addplay' || $activate eq 'insertplay'){ DoActionForList($activate,[$ID]); }
	run_command($self,$aftercmd) if $aftercmd;
}

sub DoActionForList
{	my ($action,$list)=@_;
	$action||='playlist';
	my @list=@$list;
	return unless @list;
	SortList(\@list) if @list>1 && $action!~/queue/; #Enqueue will sort it
	if ($action eq 'playlist') { Select( song=>'trykeep', staticlist => \@list ); }
	elsif ($action eq 'addplay') { $list=[@::ListPlay,@list]; Select( song=>'trykeep', staticlist => $list ); }
	elsif ($action eq 'insertplay')
	{	my $pos=defined $Position? $Position : -1;
		$list=[@ListPlay[0..$pos],@list,@ListPlay[$pos+1..$#ListPlay]];
		Select( song=>'trykeep', staticlist => $list );
	}
	elsif ($action eq 'queue') { Enqueue(@list) }
	elsif ($action eq 'replacequeue') { ReplaceQueue(@list) }
}

sub Select_sort {Select('sort' => $_[0])}
sub Select	#Set filter, sort order, selected song, playing state, staticlist, source
{	if (@_%2 || !$_[0]) {@_=(filter=>$_[0],'sort'=>$_[1],song=>$_[2],play=>$_[3],staticlist=>$_[4])} #for old plugins
	my %args=@_; #keys can be : filter sort song play staticlist source
	warn "Select : @_\n" if $debug;
	my ($filt,$sort,$song)=@args{qw/filter sort song/};
	if ($args{source})			{ $PlaySource=$args{source} }
	elsif (defined $song && $song=~m/^\d+$/){ $PlaySource=\@Library }
	$TogPlay=1 if $args{play};
	if ($args{staticlist})
	{ $filt=undef;
	  $ListMode=$args{staticlist};
	  if (!$SavedListsWatcher && !ref $ListMode)	#FIXME should be done in $SFWatch
	  { Watch($SavedListsWatcher={},'SavedLists',sub
		{ return unless $_[1] eq $ListMode;
		  if ($_[2] && $_[2] eq 'push') { my $l=$SavedLists{$ListMode};AddSongToPlaylist($$l[-1]); }
		  else { Select(staticlist => $ListMode); }
		});
	  }
	  @ListPlay=@{ ref $ListMode ? $ListMode : $SavedLists{$ListMode} || [] };
	  $SelectedFilter=undef;
	  HasChanged('Filter');
	}
	elsif (defined $filt)
	{	UnWatch($SavedListsWatcher,'SavedLists') if $SavedListsWatcher;
		$ListMode=$SavedListsWatcher=undef;
		if (!defined $sort)
		{	if    ($Options{Sort}    eq '')	{$sort=$Options{SavedSort}}
			elsif ($Options{AltSort} eq '') {$Options{AltSort}=$Options{SavedSort}}
		}
	}
	if (defined $sort)
	{	my $old=$Options{Sort};
		$Options{Sort}=$sort;
		if ($sort eq '')
		{	if ($old=~m/[sr]/) {$Options{SavedSort}=$Options{AltSort}}
			elsif ($old ne '') {$Options{SavedSort}=$old}
		}
		if ($sort=~m/^[sr]/ xor $old=~m/^[sr]/)
		{ $Options{AltSort}=$old; }	#save sort mode for quick toggle random/non-random
		if ($sort!~m/^r/)
		{	$RandomMode=undef;
			$SortFields=[map /^-?([0-9]+)/,split / /,$sort];
		}
		else
		{	$RandomMode=Random->new($sort);
			$SortFields=$RandomMode->fields;
		}
		$sort=1;
	}
	#starting here, $sort TRUE means "resort needed", $sort defined means "has been resorted"
	if    (!defined $song)		{ $song='trykeep';		}
	elsif ( $song=~m/^\d+$/ )	{ $SongID=$song; $song='keep';	}
	if (defined $filt)
	{	$filt=Filter->new($filt) unless ref $filt eq 'Filter';
		$SelectedFilter=$filt;
		@ListPlay=@{ $filt->filter };
		$sort=1;
		delete $ToDo{'7_updatefilter'};
	}
	elsif ($::ToDo{'8_updatesort'}) { $sort=1;delete $ToDo{'8_updatesort'}; }
	if ( $song eq 'keep' && !defined FindPositionSong($SongID) )
	{	if (grep $SongID==$_,@$PlaySource)
		{	$filt=$SelectedFilter=Filter->new;
			$sort=1; $ListMode=undef;
			warn "reset filter\n" if $debug;
			@ListPlay=@$PlaySource;
		}
		else
		{	DoActionForList('addplay',[$SongID]);
			return;
		}
	}
	elsif ( $song eq 'trykeep' && !defined FindPositionSong($SongID) )
	{	$song='first';
		if ($TogLock)	# try to
		{	my $pat=$Songs[$SongID][$TogLock];
			($SongID)=grep $Songs[$_][$TogLock] eq $pat, @ListPlay;
			$song='' if defined $SongID;
		}
	}
	if ($song eq 'first') #select the first song in the list according to sort order
	{	if ($RandomMode) { $RandomMode->MakeRandomList(\@ListPlay); ($SongID)=$RandomMode->Draw(1); }
		else { SortList(\@ListPlay); $SongID=$ListPlay[0]; } #$song='keep';
		$sort=0;
	}
	if ($TogLock && defined $SongID)
	{	my $pat=$Songs[$SongID][$TogLock];
		@ListPlay=grep $Songs[$_][$TogLock] eq $pat, @ListPlay;
		#@ListPlay=$FilterSubs{'~'}($TogLock,$Songs[$SongID][$TogLock],\@ListPlay);
		#$sort=1	# grep conserve order -> shouldn't be needed
		$PlayFilter=$filt=Filter->newadd( TRUE,$SelectedFilter, $TogLock.'e'.$Songs[$SongID][$TogLock] ) unless defined $ListMode;
	}
	else {$PlayFilter=$SelectedFilter}
	if ($sort)
	{	delete $ToDo{'8_updatesort'};
		if ($RandomMode) { $RandomMode->MakeRandomList(\@ListPlay); }
		else		 { SortList(\@ListPlay); }
	}
	$Position=FindPositionSong($SongID);
	if (defined $sort) { HasChanged('Sort');	}
	if (defined $filt) { HasChanged('Filter');	}
	ChangeWatcher($SFWatch, \@ListPlay, $SortFields,
		sub {	if ($RandomMode) { $RandomMode->UpdateIDs(@_); }
			elsif (!$ToDo{'8_updatesort'}) {IdleDo('8_updatesort',5*@ListPlay,\&UpdateSort);}
		    }, #re-sort
		\&RemoveSongFromPlaylist,	#remove song
		\&AddSongToPlaylist,		#add song
		$PlayFilter,
		sub { IdleDo('7_updatefilter',9000,\&UpdatePlayFilter); }, #re-filter
		);
	&UpdateSongID;
}

sub AddSongToPlaylist
{	push @ListPlay,@_;
	if (@ListPlay==@_) {$Position=0;&UpdateSongID;}
	if ($RandomMode) { $RandomMode->AddIDs(@_); IdleDo('8_updatesort',1000,sub {HasChanged('Pos','add');}); }
	elsif (!$ToDo{'8_updatesort'}) { IdleDo('8_updatesort',5*@ListPlay,\&UpdateSort); }
}
sub RemoveSongFromPlaylist
{	if ($RandomMode) { $RandomMode->RmIDs(@_); }
	my %h;
	$h{$_}=undef for @_;
	my $iscurrentsong= exists $h{$SongID};
	#@ListPlay=grep !exists $h{$_}, @ListPlay;
	my $i=@ListPlay;
	while ($i--)
	{	if (exists $h{ $ListPlay[$i] })
		{	splice @ListPlay,$i,1;
			$Position-- if $Position >= $i;
			#delete $h{ $ListPlay[$i] };
			#last unless keys %h;
		}
	}
	if (@ListPlay==0) { UpdateSongID(); }
	elsif ($iscurrentsong)
	{	#$Position=0 if $Position==-1;
		NextSong();
	}
	else { HasChanged('Pos','remove'); }
}

sub UpdateSort
{	delete $ToDo{'8_updatesort'};
	SortList(\@ListPlay);
	$Position=FindPositionSong($SongID);
	HasChanged('Pos','re-sort');
}

sub UpdatePlayFilter
{	my $m=(defined $SongID)? 'keep':'first';
	Select( filter => $SelectedFilter, song => $m );
}

sub Shuffle
{	if ($Options{Sort} eq 's')
	{	@Shuffle=();
		push @Shuffle,rand for 0..$#Songs;	#re-randomize @Shuffle
	}
	Select('sort' => 's'); #sort according to @Shuffle
}

sub SortList	#sort @$listref according to $sort
{	#my $time=times; #DEBUG
	my ($listref,$sort)=@_;
	($sort,$listref)=@_ if !ref $listref; #DELME for version <0.9496
	$sort=$Options{Sort} unless defined $sort;
	my $func; my $insensitive;
	if ($sort=~m/^r/)
	{	my $r=Random->new($sort);
		$r->MakeRandomList($listref);
		@$listref=$r->Draw;
	}
	elsif ($sort ne '')		# generate custom sort function
	{  if ($sort=~m/s/) { push @Shuffle,rand for (@Shuffle..$#Songs); }
	   my @expr;
	   for my $col ( split / +/,$sort )
	   {	my ($a,$b)=( $col=~s/^-// )? ('b','a') : ('a','b');
		my $i= $col=~s/i$//; #case-insensitive
		my ($pre,$post,$op);
		if ($col eq 's') { $pre='$Shuffle[$'; $post=']'; $op='<=>'; }
		else
		{ $post="][$col]";
		  my $type=$TagProp[$col][2];
		  if	($type eq 's')	  { $pre='$Songs[$'; $op='cmp'; }
		  elsif ($type=~m/[ndl]/) { $pre='$Songs[$'; $op='<=>'; }
		  #elsif ($type eq 'f')	  { $pre='join " ",sort split /\x00/,$Songs[$';   $op='cmp'; }
		  elsif ($type eq 'f')	  { $pre='$Songs[$'; $op='cmp'; }	#FIXME multiple labels/genres should be sorted
		  else	{ warn "Don't know how to sort $col\n"; next; }
		  if ($i)
		  {	$pre='lc'.$pre; $insensitive++;
			if ($Options{Diacritic_sort})
			{	$pre='NFKD('.$pre; $post.=')';
			}
		  }
		}
		push @expr, $pre.$a.$post.' '.$op.' '.$pre.$b.$post;
		#example:  $Songs[$ a ][$col]  <=>   $Songs[$ b ][$col]
	   }
	   warn "sort function for '$sort' :\n".'sub {'.join(' || ',@expr).'}'."\n" if $debug;
	   $func=eval 'no warnings;sub {' . join(' || ',@expr) . '}';
	   warn $@ if $@;
	}
	if ($insensitive) { my $sort0=$sort; $sort0=~s/i//g; SortList($listref,$sort0); } #do a case-sensitive sort first (faster)
	@$listref=sort $func @$listref if $func;
	#$time=times-$time; warn "sort ($sort) : $time s\n"; #DEBUG
}

sub ExplainSort
{	my $sort=$_[0];
	if ($sort eq '') {return 'no order'}
	elsif ($sort=~m/^r/)
	{	for my $name (keys %SavedWRandoms)
		{	return "Weighted Random $name." if $SavedWRandoms{$name} eq $sort;
		}
		return _"unnamed random mode"; #describe ?
	}
	my @text;
	for (split / /,$sort)
	{	my $field=s/^-// ? '-' : '';
		my $i=s/i$//;
		$field.=($_ eq 's')? _("Shuffle") : $TagProp[$_][0];
		$field.=_"(case insensitive)" if $i;
		push @text,$field;
	}
	return join ', ',@text;
}

sub ReReadTags
{	$Songs[$_][SONG_MISSINGSINCE] ||='r' for @_;
	&IdleCheck; #keep @_
}
sub IdleCheck
{	if (@_) { push @ToCheck,@_; }
	else	{ unshift @ToCheck,@Library; }
	&launchIdleLoop unless defined $IdleLoop;
}
sub IdleScan
{	@_=@LibraryPath unless @_;
	push @ToScan,@_;
	CreateProgressWindow() if @ToScan && !$ProgressWin;
	&launchIdleLoop unless defined $IdleLoop;
}

sub IdleDo
{	my $task_id=shift;
	my $timeout=shift;
	$ToDo{$task_id}=\@_;
	if ($timeout && !defined $TimeOut{$task_id})
	{ $TimeOut{$task_id}=Glib::Timeout->add($timeout,\&DoTask,$task_id); }
	&launchIdleLoop unless defined $IdleLoop;
}
sub DoTask
{	my $task_id=shift;
	delete $TimeOut{$task_id};
	my $aref=delete $ToDo{$task_id};
	if ($aref)
	{ my $sub=shift @$aref;
	  &$sub(@$aref);
	}
	0;
}

sub launchIdleLoop
{	$IdleLoop=Glib::Idle->add(\&IdleLoop);
}

sub IdleLoop
{	if    (@ToCheck){ SongCheck(pop @ToCheck); }
	elsif (@ToAdd)  { SongAdd(); }
	elsif ($CoverCandidates) {CheckCover();}
	elsif (@ToScan) { ScanFolder(); }
	elsif (%ToDo)	{ DoTask( (sort keys %ToDo)[0] ); }
	elsif (@LengthEstimated) { SongCheck(shift(@LengthEstimated)); } #to replace estimated length/bitrate by real one(for mp3s without VBR header)
	else
	{	warn "IdleLoop End\n" if $debug;
		undef $IdleLoop;
	}
	return $IdleLoop;
}

sub UpdateSongID
{	warn "pos : $Position\n" if $debug;
	if (@ListPlay==0) { $Position=$SongID=undef; Stop(); }
	else
	{	$SongID=$ListPlay[$Position];
		IdleCheck($SongID) if $Options{TAG_auto_check_current};
	}
	if ($RecentPos && $SongID!=$Recent[$RecentPos-1]) { $RecentPos=undef }
	HasChanged('SongID');
	HasChanged('Pos','song');
	ShowTraytip($Options{TrayTipTimeLength}) if $TrayIcon && $Options{ShowTipOnSongChange} && !$FullscreenWindow;
	if ( defined $SongID && !(defined $PlayingID && $PlayingID==$SongID) )
	{	if	($TogPlay)		{Play()}
		elsif	(defined $TogPlay)	{Stop()}
	}
}

sub FindPositionSong
{	my $ID=shift;
	return undef unless defined $ID;
	for (0..$#ListPlay) {return $_ if $ListPlay[$_]==$ID}
	return undef;	#not found
}
sub FindFirstInListPlay		#Choose a song in @$lref based on sort order, if possible in the current playlist. In sorted order, choose a song after current song
{	my $lref=shift;
	my $sort=$Options{Sort};
	my $ID;
	my %h;
	$h{$_}=undef for @$lref;
	my @l=grep exists $h{$_}, @ListPlay;
	if ($sort=~m/^r/)
	{	$lref=\@l if @l;
		my $r=Random->new($sort);
		$r->MakeRandomList($lref);
		($ID)=$r->Draw(1);
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

sub Playlist
{	if ($BrowserWindow)
	{	if ($_[0]{toggle})	{$BrowserWindow->close_window}
		else			{$BrowserWindow->present}
	}
	else
	{	$BrowserWindow=Layout::Window->new($Options{LayoutB});
		$BrowserWindow->signal_connect(destroy => sub { $BrowserWindow=undef; });
	}
}
sub ContextWindow
{	if ($ContextWindow)
	{	if ($_[0]{toggle})	{$ContextWindow->close_window}
		else			{$ContextWindow->present}
	}
	else
	{	$ContextWindow=Layout::Window->new('Context');
		$ContextWindow->signal_connect(destroy => sub { $ContextWindow=undef; });
	}
}
sub ToggleFullscreenLayout
{	if ($FullscreenWindow)
	{	$FullscreenWindow->close_window;
	}
	else
	{	$FullscreenWindow=Layout::Window->new($Options{LayoutF},undef,'UseDefaultState');
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

sub EditQueue
{	if ($QueueWindow)
	{	if ($_[0]{toggle})	{$QueueWindow->close_window}
		else			{$QueueWindow->present}
	}
	else
	{	$QueueWindow=Layout::Window->new('Queue');
		$QueueWindow->signal_connect(destroy => sub { $QueueWindow=undef; });
	}
}

sub WEditList
{	my $name=$_[0];
	my $window=Layout::Window->new('EditList',undef,'UseDefaultState,KeepSize');
	$window->{widgets}{SongList}->SetList($name);
	Watch($window, SavedLists => sub	#close window if the list is deleted, update title if renamed
		{	my ($window,$name,$info)=@_;
			return unless $info;
			my $songlist=$window->{widgets}{SongList};
			if ($info eq 'renamedto') { $window->set_title( _("Editing list : ").$songlist->{listname} ); return } #assumes the songlist received the rename event first
			return unless $songlist->{type} eq 'L' && $songlist->{listname} eq $name;
			$window->close_window if $info eq 'remove';
		});
	$window->set_title( _("Editing list : ").$name );
}

sub CalcListLength	#if $return, return formated string (0h00m00s)
{	my ($listref,$return)=@_;
	my $size=0; my $sec=0;
	for my $ID (@$listref)
	{	my $ref=$Songs[$ID];
		next unless $ref;
		$size+=$$ref[SONG_SIZE];
		#next unless $$_[SONG_LENGTH];
		$sec+=$$ref[SONG_LENGTH];
	}
	warn 'ListLength: '.scalar @$listref." Songs, $sec sec, $size bytes\n" if $debug;
	if ($return)	#return formated string (0h00m00s)
	{  $size=sprintf '%.0f',$size/1048576; #1024*1024
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
		return __("%d Song","%d Songs",$nb) .', '. __x($format, @values);
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
	else { return ($sec,$size); } #return numbers
}

# http://www.allmusic.com/cg/amg.dll?p=amg&opt1=1&sql=%s    artist search
# http://www.allmusic.com/cg/amg.dll?p=amg&opt1=2&sql=%s    album search
sub AMGLookup
{	my ($col,$key)=@_;
	my $opt1=	$col==SONG_ARTIST ? 1 :
			$col==SONG_ALBUM  ? 2 : 3;
	my $url='http://www.allmusic.com/cg/amg.dll?p=amg&opt1='.$opt1.'&sql=';
	$key=~s/ /|/g;
	$key=~s/([][\\@;?\/\$&="'<>~:#+,`])/sprintf '%%%x',ord$1/ge;
	if ($^O eq 'MSWin32') {system 'start',$url.$key;return}
	$url=quotemeta $url.$key;
	openurl($url);
}

sub Google
{	my $ID=shift;
	my $lang='';
	$lang="hl=$1&" if setlocale(LC_MESSAGES)=~m/^([a-z]{2})(?:_|$)/;
	my $url='http://google.com/search?'.$lang."q=";
	my @q;
	push @q,$Songs[$ID][$_] for SONG_TITLE,SONG_ARTIST,SONG_ALBUM;
	$q[1]='' if $q[1] eq '<Unknown>';
	$q[2]='' if $q[2]=~m/^<Unknown>/;
	@q=grep $_ ne '', @q;
	s/([][\\@;?\/\$&="'<>~: #+,`])/sprintf '%%%x',ord$1/ge for @q;
	if ($^O eq 'MSWin32') {system 'start',$url.join('+',@q);return}
	$url=quotemeta $url.join('+',@q);
	openurl($url);
}
sub openurl
{	my $url=$_[0];
	if ($^O eq 'MSWin32') { system "start $url"; return }
	else
	{	$browsercmd||=findcmd($Options{OpenUrl},qw/xdg-open gnome-open firefox epiphany konqueror galeon/);
		unless ($browsercmd) { ErrorMessage(_"No web browser found."); return }
	}
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
	my $AAref=($col==SONG_ARTIST)? \%Artist : \%Album;
	my $file;
	if (defined $ID) { $file=$::Songs[$ID][SONG_PATH]; }
	else { my %h; $h{$_}++ for map $::Songs[$_][SONG_PATH],@{ $AAref->{$key}[AALIST] }; ($file)=sort { $h{$b} <=> $h{$a} } keys %h; }	#FIXME should try to find common parent folder
	$file=ChoosePix($file,_"Choose picture for ".$key,$AAref->{$key}[AAPIXLIST]);
	return unless defined $file;
	$AAref->{$key}[AAPIXLIST]=$file;
	HasChanged('AAPicture',$key);
}

sub ChooseSongsTitle		#Songs with the same title
{	my $ID=$_[0];
	my $title=$Songs[$ID][SONG_TITLE];
	return 0 if $title eq '';
	my @list=@{ Filter->new(SONG_TITLE.'~'.$Songs[$ID][SONG_TITLE])->filter; };
	return 0 if @list<2 || @list>100;	#probably a problem if it finds >100 matching songs, and making a menu with a huge number of items is slow
	@list=grep $_!=$ID,@list;
	SortList(\@list,SONG_ARTIST.'i '.SONG_ALBUM.'i');
	return ChooseSongs( __x( _"by {artist} from {album}", artist => "<b>%a</b>", album => "%l") ,@list);
}

sub ChooseSongsFromA_current
{	return unless defined $SongID;
	return if $Songs[$SongID][SONG_MISSINGSINCE] && $Songs[$SongID][SONG_MISSINGSINCE]=~m/R/;
	my $album= $Songs[$SongID][SONG_ALBUM];
	ChooseSongsFromA($album);
}
sub ChooseSongsFromA
{	my $album=$_[0];
	return unless defined $album || exists $Album{ $album };
	my $list=$Album{ $album }[AALIST];
	SortList($list,SONG_DISC.' '.SONG_TRACK.' '.SONG_UFILE);
	if ($Songs[$list->[0]][SONG_DISC])
	{	my $disc=''; my @list2;
		for my $ID (@$list)
		{	my $d=$Songs[$ID][SONG_DISC];
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
		if ( my $img=NewScaledImageFromFile($Album{ $album }[AAPIXLIST],$picsize) )
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
		if ( my $img=NewScaledImageFromFile($Album{ $album }[AAPIXLIST],$picsize) )
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
	elsif ( my $pixbuf=PixBufFromFile($Album{ $album }[AAPIXLIST]) ) #TEST not used
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
		my $submenu=PopupContextMenu(\@SongCMenu,{IDs=> [$_[2]]});
		$submenu->show_all;
		$_[0]->set_submenu($submenu);
		#$submenu->signal_connect( selection_done => sub {$menu->popdown});
		#$submenu->show_all;
		#$submenu->popup(undef,undef,undef,undef,$LEvent->button,$LEvent->time);
		return 1;
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
		#set_drag($item, source => [::DRAG_ID,sub {$ID}]);
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
{	my ($col,$key,$callback,$format)=@_;
	return undef unless @Library;
	$format||="%a";
	my $href=($col==SONG_ARTIST)? \%Artist : \%Album;

####make list of albums/artists
	my @keys;
	if (defined $key)
	{	if (ref $key) {@keys=@$key;}
		elsif ($col==SONG_ALBUM)
		{ my %alb;
		  for my $artist (split /$re_artist/o,$key)
		  {	push @{$alb{$_}},$artist for keys %{ $Artist{$artist}[AAXREF] };  }
		  #{	$alb{$_}=undef for keys %{ $Artist{$artist}[AAXREF] };  }
		  #@keys=keys %alb;
		  my %art_keys;
		  while (my($album,$list)=each %alb)
		  {	my $artist=join ' & ',@$list;
			push @{$art_keys{$artist}},$album;
		  }
		  if (1==keys %art_keys)
		  {	@keys=@{ $art_keys{ (keys %art_keys)[0] } };
		  }
		  else	#multiple artists -> create a submenu for each artist
		  {	my $menu=Gtk2::Menu->new;
			for my $artist (keys %art_keys)
			{	my $item=Gtk2::MenuItem->new($artist);
				$item->set_submenu(PopupAA(SONG_ALBUM,$art_keys{$artist}));
				$menu->append($item);
			}
			$menu->show_all;
			if (defined wantarray) {return $menu}
			$menu->popup(undef,undef,\&menupos,undef,$LEvent->button,$LEvent->time);
			return;
		  }
		}
		else
		{ @keys=keys %{$Album{$key}[AAXREF]}; }
	}
	else { @keys=grep $href->{$_} && $href->{$_}[AALIST], keys %$href; }

#### callbacks
	my $rmbcallback;
	unless ($callback)
	{  $callback=sub		#jump to first song
	   {	return if $_[0]->get_submenu;
		my $key=$_[1];
		my $ID=FindFirstInListPlay( $href->{$key}[AALIST] );
		Select(song => $ID);
	   };
	   $rmbcallback=($col==SONG_ARTIST)?
		sub	#Arists rmb cb
		{	(my$item,$LEvent,my$key)=@_;
			return 0 unless $LEvent->button==3;
			my $submenu=PopupAA(SONG_ALBUM,$key);
			$item->set_submenu($submenu);
			0;
		}:
		sub	#Albums rmb cb
		{	(my$item,$LEvent,my$key)=@_;
			return 0 unless $LEvent->button==3;
			my $submenu=ChooseSongsFromA($key);
			$item->set_submenu($submenu);
			0;
		};
	}


	my $max=($LEvent->get_screen->get_height)*.8;
	#my $minsize=Gtk2::ImageMenuItem->new('')->size_request->height;
	my @todo;	#hold images not yet loaded because not cached

	my $createAAMenu=sub
	{	my ($start,$end,$keys)=@_;
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
			$label->set_markup( ReplaceAAFields($key,$format,$col,1) );
			#$label->set_markup( ReplaceAAFields($key,"<b>%a</b>%Y\n<small>%s <small>%l</small></small>",$col,1) );
			$item->add($label);
			$item->signal_connect(activate => $callback,$key);
			$item->signal_connect(button_press_event => $rmbcallback,$key) if $rmbcallback;
			#$menu->append($item);
			$menu->attach($item, $colnb, $colnb+1, $row, $row+1); if (++$row>$rows) {$row=0;$colnb++;}
			if (my $f=$$href{$key}[AAPIXLIST])
			{	my $img=AAPicture::newimg($col,$key,$size,\@todo);
				$item->set_image($img);
				#push @todo,$item,$f,$size;
			}
		}
		return $menu;
	}; #end of createAAMenu

	my $min= ($col==SONG_ARTIST)? $Options{ArtistMenu_min} : $Options{AlbumMenu_min};
	my @keys_minor;
	if ($min)
	{	@keys= grep { @{$href->{$_}[AALIST]}>$min or push @keys_minor,$_ and 0 } @keys;
		if (!@keys) {@keys=@keys_minor; undef @keys_minor;}
	}

	@keys=sort { NFKD(uc$a) cmp NFKD(uc$b) } @keys;

	my $menu=Breakdown_List(\@keys,5,20,35,$createAAMenu);
	return undef unless $menu;
	if (@keys_minor)
	{	@keys_minor=sort { NFKD(uc$a) cmp NFKD(uc$b) } @keys_minor;
		my $item=Gtk2::MenuItem->new('minor'); #FIXME
		my $submenu=Breakdown_List(\@keys_minor,5,20,35,$createAAMenu);
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
{	my ($keys,$min,$opt,$max,$makemenu)=@_;

	if ($#$keys<=$max) { return $makemenu ? &$makemenu(0,$#$keys,$keys) : [0,$#$keys] }

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
			my $item=Gtk2::MenuItem->new($c1);
			my $submenu= &$makemenu($start,$end,$keys);
			$item->set_submenu($submenu);
			$menu->append($item);
		}
	}
	elsif (@menus==1) { $menu= &$makemenu(0,$#$keys,$keys); }
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
{	my ($pixdata,$size)=($_[0],$_[1]);
	my $loader=Gtk2::Gdk::PixbufLoader->new;
	$loader->signal_connect(size_prepared => \&::PixLoader_callback,$size) if $size;
	eval { $loader->write($pixdata); };
	eval { $loader->close; } unless $@;
	$loader=undef if $@;
	warn "$@\n" if $debug;
	return $loader;
}

sub PixBufFromFile
{	my ($file,$size)=($_[0],$_[1]);
	return unless $file;
	unless (-r $file) {warn "$file not found\n" unless $_[1]; return undef;}

	my $loader=Gtk2::Gdk::PixbufLoader->new;
	$loader->signal_connect(size_prepared => \&PixLoader_callback,$size) if $size;
	if ($file=~m/\.(?:mp3|flac)$/i)
	{	my $data=ReadTag::PixFromMusicFile($file);
		eval { $loader->write($data) } if defined $data;
	}
	else	#eval{Gtk2::Gdk::Pixbuf->new_from_file(filename_to_unicode($file))};
		# work around Gtk2::Gdk::Pixbuf->new_from_file which wants utf8 filename
	{	open my$fh,'<',$file; binmode $fh;
		my $buf; eval {$loader->write($buf) while read $fh,$buf,1024*50;};
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

sub PopupContextMenu
{	my ($mref,$args)=@_;
	my $menu_callback=sub
		 {	my $sub=$_[1];
			&$sub( $args );
		 };
	my $mode=$args->{mode} || '^$';
	$mode=qr/$mode/;
	my $count;
	my $menu=Gtk2::Menu->new;
	for my $m (@$mref)
	{	next if $m->{ignore};
		next if $m->{isdefined}	&& !defined $args->{ $m->{isdefined} };
		next if $m->{istrue}	&& !$args->{ $m->{istrue} };
		next if $m->{mode}	&& $m->{mode}	!~m/$mode/;
		next if $m->{notmode}	&& $m->{notmode}=~m/$mode/;;
		next if $m->{empty}	&& (  $args->{ $m->{empty} }	&& @{ $args->{ $m->{empty}   } }!=0 );
		next if $m->{notempty}	&& ( !$args->{ $m->{notempty} }	|| @{ $args->{ $m->{notempty}} }==0 );
		next if $m->{onlyone}	&& ( !$args->{ $m->{onlyone}  }	|| @{ $args->{ $m->{onlyone} } }!=1 );
		next if $m->{onlymany}	&& ( !$args->{ $m->{onlymany} }	|| @{ $args->{ $m->{onlymany}} }<2  );
		next if $m->{test}	&& !&{ $m->{test} }($args);

		my $label=$m->{label};
		$label=&$label($args) if ref $label;
		my $item;
		if (!defined $label)
		{	next unless $m->{separator};
			$item=Gtk2::SeparatorMenuItem->new;
		}
		elsif ($m->{stockicon})
		{	$item=Gtk2::ImageMenuItem->new($label);
			$item->set_image( Gtk2::Image->new_from_stock($m->{stockicon},'menu') );
		}
		elsif ( ($m->{check} || $m->{radio}) && !$m->{submenu})
		{	$item=Gtk2::CheckMenuItem->new($label);
			my $func= $m->{check} || $m->{radio};
			$item->set_active(1) if &$func($args);
			$item->set_draw_as_radio(1) if $m->{radio};
		}
		else	{ $item=Gtk2::MenuItem->new($label); }
		if (my $submenu=$m->{submenu})
		{	$submenu=&$submenu($args) if ref $submenu eq 'CODE';
			if ($m->{code}) #list submenu
			{	my (@labels,@values);
				if ($m->{submenu_ordered_hash})
				{	my $i=0; while ($i<$#$submenu)
					{push @labels,$submenu->[$i++];push @values,$submenu->[$i++]; }
				}
				elsif (ref $submenu eq 'ARRAY')	{@labels=@values=@$submenu}
				elsif ($m->{submenu_reverse})	{@values=keys %$submenu; @labels=values %$submenu;}
				else				{@labels=keys %$submenu; @values=values %$submenu;}
				my @order= 0..$#labels;
				@order=sort {lc$labels[$a] cmp lc$labels[$b]} @order if ref $submenu eq 'HASH';

				$submenu=Gtk2::Menu->new;
				my $smenu_callback=sub
				 {	my $sub=$_[1];
					&$sub( $args, $_[0]{selected} );
				 };
				my $check;
				$check=&{ $m->{check} }($args) if $m->{check};
				for my $i (@order)
				{	my $label=$labels[$i];
					my $value=$values[$i];
					my $item=Gtk2::MenuItem->new($label);
					if (defined $check)
					{	$item=Gtk2::CheckMenuItem->new($label);
						$item->set_draw_as_radio(1);
						$item->set_active(1) if $check eq $value;
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
		{	$item->signal_connect (activate => $menu_callback, $m->{code} );
		}
		$count++;
		$menu->append($item);
	}
	if (defined wantarray) {return $menu}
	return unless $count;
	$menu->show_all;
	$menu->popup(undef,undef,undef,undef,$LEvent->button,$LEvent->time);
}

sub set_drag
{	my ($widget,%params)=@_;
	if (my $dragsrc=$params{source})
	{	my $n=$dragsrc->[0];
		$widget->drag_source_set(
			['button1-mask'],['copy','move'],
			map [ $DRAGTYPES[$_][0], [] , $_ ], $n,
				keys %{$DRAGTYPES[$n][1]} );
		$widget->{dragsrc}=$dragsrc;
		$widget->signal_connect(drag_data_get => \&drag_data_get_cb);
		$widget->signal_connect(drag_begin => \&drag_begin_cb);
		$widget->signal_connect(drag_end => \&drag_end_cb);
	}
	if (my $dragdest=$params{dest})
	{	$widget->drag_dest_set(
			'all',['copy','move'],
			map [ $DRAGTYPES[$_][0], ($_==DRAG_ID ? 'same-app' : []) , $_ ],
				@$dragdest[0..$#$dragdest-1] );
		$widget->{dragdest}=$dragdest->[-1];
		$widget->signal_connect(drag_data_received => \&drag_data_received_cb);
		$widget->signal_connect(drag_leave => \&drag_leave_cb);
		$widget->signal_connect(drag_motion => $params{motion}) if $params{motion}; $widget->{drag_motion_cb}=$params{motion};
	}
}

sub drag_begin_cb	#create drag icon
{	my ($self,$context)=@_;# warn "drag_begin_cb @_";
	$self->signal_stop_emission_by_name('drag_begin');
	$self->{drag_is_source}=1;
	my ($srcinfo,$sub)=@{ $self->{dragsrc} };
	my @values=&$sub($self);
	unless (@values) { $context->abort($context->start_time); return; } #FIXME no data -> should abort the drag
	$context->{data}=\@values;
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
	my ($srcinfo,$sub)=@{ $self->{dragsrc} };
	return unless $context->{data};
	my @values=@{ $context->{data} };#my @values=&$sub($self); return unless @values;
	if ($destinfo != $srcinfo)
	{	my $convsub=$DRAGTYPES[$srcinfo][1]{$destinfo};
		if ($destinfo==DRAG_STRING) { my $sub=$DRAGTYPES[$srcinfo][1]{DRAG_USTRING()}; $convsub||=sub { map Encode::encode('iso-8859-1',$_), &$sub }; } #not sure of the encoding I should use, it's for app that don't accept 'text/plain;charset=UTF-8', only found/tested with gnome-terminal
		@values=$convsub?  &$convsub(@values)  :  ();
	}
	$data->set($data->target,8, join("\x0d\x0a",@values) ) if @values;
}
sub drag_data_received_cb
{	my ($self,$context,$x,$y,$data,$info,$time)=@_;# warn "drag_data_received_cb @_";
	my $sub=$self->{dragdest};
	my $ret=my$del=0;
	if ($data->length >=0 && $data->format==8)
	{	my @values=split "\x0d\x0a",$data->data;
		_utf8_on($_) for @values;
		unshift @values,$context->{dest} if $context->{dest} && $context->{dest}[0]==$self;
		$sub->($self, $::DRAGTYPES{$data->target->name} , @values);
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
		$self->{drag_motion_cb}->($self,$self->{context}, ($self->window->get_pointer)[1,2], 0 ) if $self->{drag_motion_cb};
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
	{	$dir=~s/$ILLEGALCHAR//g;
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
	my $newdir=ChooseDir($msg,$Songs[$IDs->[0]][SONG_PATH].SLASH);
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
		my $aref=$Songs[$ID];
		my $oldfile=$$aref[SONG_FILE];
		my $olddir= $$aref[SONG_PATH];
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
		until (&$sub($old,$new))
		{	my $res=Retry_Dialog("$errormsg :\n'$old'\n -> '$new'\n$!",$win,$abortmsg);
			last COPYNEXTID if $res eq 'abort';
			last unless $res eq 'yes';
		}
		unless ($copy)
		{	my @diff;
			$newdir=~s/$QSLASH+$//o;
			if ($$aref[SONG_PATH] ne $newdir)
			{	$$aref[SONG_PATH]=$newdir;
				$$aref[SONG_UPATH]=filename_to_utf8displayname($newdir);
				@diff=(SONG_PATH,SONG_UPATH);
			}
			if ($$aref[SONG_FILE] ne $newfile)
			{	$$aref[SONG_FILE]=$newfile;
				$$aref[SONG_UFILE]=filename_to_utf8displayname($newfile);
				push @diff,SONG_FILE,SONG_UFILE;
			}
			SongChanged($ID,@diff);
			$GetIDFromFile{$newdir}{$newfile} = delete $GetIDFromFile{$olddir}{$oldfile};
			delete $GetIDFromFile{$olddir} unless keys %{ $GetIDFromFile{$olddir} };
		}
		last if $cancel;
	}
	$win->destroy;
}

sub CopyFields
{	my ($srcfile,$dstfile)=@_;
	my $IDsrc=FindID($srcfile);
	my $IDdst=FindID($dstfile);
	unless (defined $IDsrc) { warn "CopyFields : can't find $srcfile in the library\n";return 1 }
	unless (defined $IDdst) { warn "CopyFields : can't find $dstfile in the library\n";return 2 }
	warn "Copying stats from $srcfile to $dstfile\n" if $::debug;
	my @fields=(SONG_ADDED,SONG_LASTPLAY,SONG_NBPLAY,SONG_LASTSKIP,SONG_NBSKIP,SONG_RATING,SONG_LABELS);
	$Songs[$IDdst][$_]=$Songs[$IDsrc][$_] for @fields;
	SongChanged($IDdst,@fields);
	return 0;
}

sub ChooseDir
{	my ($msg,$path,$extrawidget,$multiple) = @_;
	my $dialog=Gtk2::FileChooserDialog->new($msg,undef,'select-folder',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none',
					);
	_utf8_on($path) if $path; #FIXME not sure if it's the right thing to do
	$dialog->set_current_folder($path) if $path;
	$dialog->set_extra_widget($extrawidget) if $extrawidget;
	$dialog->set_select_multiple(1) if $multiple;

	my @paths;
	if ($dialog->run eq 'ok')
	{   @paths=$dialog->get_filenames;
	    eval { $_=filename_from_unicode($_); } for @paths;
	    _utf8_off($_) for @paths; # folder names that failed filename_from_unicode still have their uft8 flag on
	    @paths= grep -d, @paths;
	}
	else {@paths=()}
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
{	my ($path,$text,$file)=@_;
	$text||=_"Choose Picture";
	my $dialog=Gtk2::FileChooserDialog->new($text,undef,'open',
					_"no picture" => 'reject',
					'gtk-ok' => 'ok',
					'gtk-cancel' => 'none');

	my $filter = Gtk2::FileFilter->new;
	#$filter->add_mime_type('image/'.$_) for qw/jpeg gif png bmp/;
	$filter->add_mime_type('image/*');
	$filter->add_pattern('*.mp3');
	$filter->add_pattern('*.flac');
	$filter->set_name(_"Pictures, mp3 & flac files");
	$dialog->add_filter($filter);
	$filter = Gtk2::FileFilter->new;
	$filter->add_mime_type('image/*');
	$filter->set_name(_"Pictures files");
	$dialog->add_filter($filter);
	$filter = Gtk2::FileFilter->new;
	#$filter->add_mime_type('*');
	$filter->add_pattern('*');
	$filter->set_name(_"All files");
	$dialog->add_filter($filter);

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
		  eval{ $file=filename_from_unicode($file); };
		  ScaleImageFromFile($image,150,$file);
		  my $p=$image->{pixbuf};
		  if ($p) { $label->set_text($p->get_width.' x '.$p->get_height); }
		  #else { $label->set_text('no picture'); }
		  $dialog->set_preview_widget_active($p);
		};
	$dialog->signal_connect(selection_changed => $update_preview);

	$preview->show_all;
	if ($file && -f $file)	{ $dialog->set_filename($file); &$update_preview($dialog,$file); }
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
	  'warning','yes-no', '%s',
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
	  'error','yes-no', '%s',
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
	  'error','close',
	  '%s', $err
	);
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
}

sub EditLyrics
{	my $ID=$_[0];
	if (exists $Editing{'L'.$ID}) { $Editing{'L'.$ID}->present; return; }
	my $lyrics=ReadTag::GetLyrics($ID);
	$lyrics='' unless defined $lyrics;
	$Editing{'L'.$ID}=
	  EditLyricsDialog(undef,$lyrics,_("Lyrics for ").$Songs[$ID][SONG_UPATH].SLASH.$Songs[$ID][SONG_UFILE],sub
	   {	delete $Editing{'L'.$ID};
		ReadTag::WriteLyrics($ID,$_[0]) if defined $_[0];
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
			&$sub($lyrics) if $sub;
		},$sub);
	return $dialog;
}

sub DeleteFiles
{	return if $CmdLine{ro};
	my $IDs=$_[0];
	return unless @$IDs;
	my $text=(@$IDs==1)? "'".$Songs[$IDs->[0]][SONG_UFILE]."'" : __("%d file","%d files",scalar @$IDs);
	my $dialog = Gtk2::MessageDialog->new
		( undef,
		  'modal',
		  'warning','ok-cancel', '%s',
		  __x(_("About to delete {files}\nAre you sure ?"), files => $text)
		);
	$dialog->show_all;
	if ('ok' eq $dialog->run)
	{ my $abortmsg;
	  $abortmsg=_"Abort" if @$IDs>1;
	  for my $ID (@$IDs)
	  {	my $f=$Songs[$ID][SONG_PATH].SLASH.$Songs[$ID][SONG_FILE];
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
	my $s=ReplaceFields( $ID, $format );
	$s=~s/$ILLEGALCHAR//g;
	$s=~s/ +$//;
	$s.=( $Songs[$ID][SONG_UFILE]=~m/(\.[^\.]+$)/ )[0] if $ext; #add extension
	return $s;
}
sub pathfromformat
{	my ($ID,$format,$basefolder)=@_;
	#my $s=ReplaceFields( $ID, $format );
	my $s=	join ::SLASH,	map { my $noclean= $_ eq '%F'; $_=ReplaceFields( $ID, $_ ); s/$QSLASH//go, s/$ILLEGALCHARDIR//go unless $noclean; $_ }	split /$QSLASH+/o, $format;
	#$s=~s/$ILLEGALCHARDIR//go;
	$s.=SLASH;
	$s=~s#$QSLASH\.\.?$QSLASH#::SLASH#goe;
	$s=$basefolder.SLASH.$s if $basefolder;
	$s=~s#$QSLASH{2,}#::SLASH#goe;
	$s=~s/ +$//;
	return $s;
}
sub pathfilefromformat
{	my ($ID,$format,$ext)=@_;
	$format=~s#^~($QSLASH)#$ENV{HOME}$1#o;
	return undef unless $format=~s#$QSLASH([^$QSLASH]+)$##o;
	#return undef unless $format=~m#^$QSLASH#o && $format=~s#$QSLASH([^$QSLASH]+)$##o;
	my $file=$1;
	$file=filenamefromformat($ID,$file,$ext);
	my $path=pathfromformat($ID,$format);
	return wantarray ? ($path,$file) : $path.::SLASH.$file;
}

sub DialogMassRename
{	return if $CmdLine{ro};
	my @IDs=do {my %h; grep !$h{$_}++, @_ }; #remove duplicates IDs in @_ => @IDs
	::SortList(\@IDs,::SONG_UPATH.' '.::SONG_UFILE);
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
	my $combo=Gtk2::ComboBoxEntry->new_text;
	$combo->child->set_activates_default(TRUE);
	my $comboFolder=Gtk2::ComboBoxEntry->new_text;
	my $folders=0;
	###
	my $notebook=Gtk2::Notebook->new;
	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview1=Gtk2::TreeView->new($store);
	my $treeview2=Gtk2::TreeView->new($store);
	my $func1=sub { my (undef,$cell,$store,$iter)= @_; my $ID=$store->get($iter,0); my $t=$Songs[$ID][SONG_UFILE]; $cell->set(text=> ($folders? $Songs[$ID][SONG_UPATH].SLASH.$t : $t)); };
	my $func2=sub { my (undef,$cell,$store,$iter)= @_; my $ID=$store->get($iter,0); my $t=filenamefromformat($ID,$combo->child->get_text,1); if ($folders) {$t=pathfromformat($ID,$comboFolder->child->get_text, $Options{BaseFolder}).$t; } $cell->set(text=>$t) };
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
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entrybase=NewPrefFileEntry('BaseFolder',_("Base Folder :"),'folder', $refresh,undef,$sg1,$sg2);
	my $labelfolder=Gtk2::Label->new(_"Folder pattern :");

	$combo->signal_connect(changed => $refresh);
	$combo->append_text($_) for split "\x1D",$Options{FilenameSchema};
	$combo->set_active(0);

	$comboFolder->signal_connect(changed => $refresh);
	$comboFolder->append_text($_) for split "\x1D",$Options{FolderSchema};
	$comboFolder->set_active(0);

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
		{ my $format=$combo->child->get_text;
			#save filename schema
		  my @list= grep $_ ne $format,split "\x1D",$Options{FilenameSchema};
		  $#list=10 if $#list>10;
		  $Options{FilenameSchema}=join "\x1D",$format,@list;
			#
		  if ($folders)
		  {	my $base= $Options{BaseFolder};
			unless ( defined $base ) { ErrorMessage(_("You must specify a base folder"),$dialog); return }
			until ( -d $base ) { last unless $base=~s/$QSLASH[^$QSLASH]*$//o && $base=~m/$QSLASH/o;  }
			unless ( -w $base ) { ErrorMessage(__x(_("Can't write in base folder '{folder}'."), folder => $Options{BaseFolder}),$dialog); return }
			$dialog->set_sensitive(FALSE);
			my $folderformat=$comboFolder->child->get_text;
			 #save foldername schema
			my @list= grep $_ ne $folderformat,split "\x1D",$Options{FolderSchema};
			$#list=10 if $#list>10;
			$Options{FolderSchema}=join "\x1D",$folderformat,@list;
			 #
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
	$newutf8=~s/$ILLEGALCHAR//g;
	my $new=filename_from_unicode($newutf8);
	my $old=$Songs[$ID][SONG_FILE];
	my $dir=$Songs[$ID][SONG_PATH];
	{	last if $new eq '';
		last if $old eq $new;
		if (-f $dir.SLASH.$new)
		{	my $res=OverwriteDialog($window,$new); #FIXME support yesall noall ? but not needed because RenameFile is now only used for single file renaming
			return $res unless $res eq 'yes';
			redo;
		}
		elsif (!rename $dir.SLASH.$old, $dir.SLASH.$new)
		{	my $res=Retry_Dialog( __x( _"Renaming {oldname}\nto {newname}\nfailed : {error}", oldname => $Songs[$ID][SONG_UFILE], newname => $newutf8, error => $!),$window,$abortmsg);
			return $res unless $res eq 'yes';
			redo;
		}
	}
	$Songs[$ID][SONG_FILE]=$new;
	$Songs[$ID][SONG_UFILE]=$newutf8;
	$GetIDFromFile{$dir}{$new}=delete $GetIDFromFile{$dir}{$old};
	SongChanged($ID,SONG_UFILE,SONG_FILE);
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
	for my $col (SONG_TITLE,SONG_ARTIST,SONG_ALBUM,SONG_DISC,SONG_TRACK)
	{	next if ($col==SONG_DISC || $col==SONG_TRACK) && !$Songs[$ID][$col];
		my $lab1=Gtk2::Label->new;
		my $lab2=Gtk2::Label->new($Songs[$ID][$col]);
		$lab1->set_markup('<b>'.$TagProp[$col][0].' :</b>');
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
	$entry->set_text($Songs[$ID][SONG_UFILE]);
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

sub AddToListMenu
{	return undef unless keys %SavedLists;
	my $IDs=$_[0]{IDs};
	my $menusub=sub {my $key=$_[1]; push @{$SavedLists{$key}},@$IDs; HasChanged('SavedLists',$key,'push'); };

	my @keys=sort { NFKD(uc$a) cmp NFKD(uc$b) } keys %SavedLists;
	my $makemenu=sub
	{	my ($start,$end,$keys)=@_;
		my $menu=Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $l=$keys->[$i];
			my $item=Gtk2::MenuItem->new($l);
			$item->signal_connect(activate => $menusub,$l);
			$menu->append($item);
		}
		return $menu;
	};
	my $menu=Breakdown_List(\@keys,5,20,35,$makemenu);
	return $menu;
}

sub LabelEditMenu
{	return undef unless keys %Labels;
	my $IDs=$_[0]{IDs};
	my $menusub_toggled=sub
	 {	my $f=$_[1];
		if ($_[0]->get_active)	{ SetLabels($IDs,[$f],undef); }
		else			{ SetLabels($IDs,undef,[$f]); }
	 };
	my @keys=sort { NFKD(uc$a) cmp NFKD(uc$b) } keys %Labels;
	my $makemenu=sub
	{	no warnings 'uninitialized';
		my ($start,$end,$keys)=@_;
		my $menu=Gtk2::Menu->new;
		for my $i ($start..$end)
		{	my $f=$keys->[$i];
			my $item=Gtk2::CheckMenuItem->new_with_label($f);
			my $state=grep $Songs[$_][SONG_LABELS]=~m/(?:^|\x00)\Q$f\E(?:$|\x00)/ , @$IDs;
			if ($state==@$IDs){ $item->set_active($state==@$IDs); }
			elsif ($state>0)  { $item->set_inconsistent(1); }
			$item->signal_connect(toggled => $menusub_toggled,$f);
			$menu->append($item);
		}
		return $menu;
	};
	my $menu=Breakdown_List(\@keys,5,20,35,$makemenu);
	return $menu;
}

sub filterAA
{	my ($col,$key)=@{$_[0]}{qw/col key/};
	my $cmd=($col==SONG_ARTIST)? '~' : 'e';
	Select(filter => $col.$cmd.$key);
}
sub FilterOnAA
{	my ($widget,$col,$key,$filternb)=@{$_[0]}{qw/self col key filternb/};
	$filternb=1 unless defined $filternb;
	my $cmd=($col==SONG_ARTIST)? '~' : 'e';
	::SetFilter($widget,$col.$cmd.$key,$filternb);
}
sub SearchSame
{	my $col=$_[0];
	my ($widget,$IDs,$filternb)=@{$_[1]}{qw/self IDs filternb/};
	$filternb=1 unless defined $filternb;
	my $cmd= ($col==SONG_TITLE || $col==SONG_ARTIST)? '~' : 'e';
	my $filter=Filter->newadd(FALSE,map($col.$cmd.$Songs[$_][$col], @$IDs));
	::SetFilter($widget,$filter,$filternb);
}

sub SongsSubMenuTitle
{	my $aaref= ($_[0]{col}==SONG_ARTIST)? \%Artist : \%Album;
	return undef unless $aaref->{$_[0]{key}};
	my $nb=@{ $aaref->{$_[0]{key}}[AALIST] };
	return __("%d Song","%d Songs",$nb);
}
sub SongsSubMenu
{	my %args=%{$_[0]};
	$args{mode}='S';
	my $aaref= ($args{col}==SONG_ARTIST)? \%Artist : \%Album;
	$args{IDs}=\@{ $aaref->{$args{key}}[AALIST] };
	return PopupContextMenu(\@SongCMenu,\%args);
}

sub ArtistContextMenu
{	my ($artist,$params)=@_;
	$params->{col}=SONG_ARTIST;
	my @l=split /$re_artist/o,$artist;
	if (@l==1) { PopupContextMenu(\@cMenuAA,{%$params,key=>$artist}); return; }
	my $menu = Gtk2::Menu->new;
	for my $ar (@l)
	{	my $item=Gtk2::MenuItem->new($ar);
		my $submenu=::PopupContextMenu(\@cMenuAA,{%$params,key=>$ar});
		$item->set_submenu($submenu);
		$menu->append($item);
	}
	$menu->show_all;
	$menu->popup(undef,undef,undef,undef,$LEvent->button,$LEvent->time);
}

sub EditLabels
{	my @IDs=@_;
	my $vbox=Gtk2::VBox->new;
	my $table=Gtk2::Table->new(int((keys %Labels)/3),3,FALSE);
	my %checks;
	my $changed;
	my $row=0; my $col=0;
	no warnings 'uninitialized';
	my $addlabel=sub
	 {	my $label=$_[0];
		my $check=Gtk2::CheckButton->new_with_label($label);
		my $state=grep $Songs[$_][SONG_LABELS]=~m/(?:^|\x00)\Q$label\E(?:$|\x00)/ , @IDs;
		if ($state==@IDs) { $check->set_active(1); }
		elsif ($state>0)  { $check->set_inconsistent(1); }
		$check->signal_connect( toggled => sub	{  $_[0]->set_inconsistent(0); $changed=1 });
		$checks{$label}=$check;
		if ($col==3) {$col=0; $row++;}
		$table->attach($check,$col,$col+1,$row,$row+1,['fill','expand'],'shrink',1,1);
		$col++;
	 };
	for my $label (sort { NFKD(uc$a) cmp NFKD(uc$b) } keys %Labels)
	{	&$addlabel($label);
	}
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
		&$addlabel($label) unless exists $checks{$label};
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

sub DialogSongsProp
{	my @IDs=@_;
	my $dialog = Gtk2::Dialog->new (_"Edit Multiple Songs Properties", undef,
				'destroy-with-parent',
				'gtk-save' => 'ok',
				'gtk-cancel' => 'none');
	$dialog->set_default_response ('ok');
	my $notebook = Gtk2::Notebook->new;
	$notebook->set_tab_border(4);
	$dialog->vbox->add($notebook);

	my $edittag=MassTag->new($dialog,@IDs);
	my $editlabels=EditLabels(@IDs);
	my $rating=SongRating(@IDs);
	$notebook->append_page( $edittag ,	Gtk2::Label->new(_"Tag"));
	$notebook->append_page( $editlabels,	Gtk2::Label->new(_"Labels"));
	$notebook->append_page( $rating,	Gtk2::Label->new(_"Rating"));

	SetWSize($dialog,'MassTag');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
		{	#warn "MassTagging response : @_\n" if $debug;
			my ($dialog,$response)=@_;
			if ($response eq 'ok')
			{ $dialog->action_area->set_sensitive(FALSE);
			  &{ $editlabels->{save} };
			  &{ $rating->{save} }($rating);
			  $edittag->save( sub {$dialog->destroy;} ); #the closure will be called when tagging finished #FIXME not clean
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
	my $editlabels=EditLabels($ID);
	my $rating=SongRating($ID);
	my $songinfo=SongInfo($ID);
	$notebook->append_page( $edittag,	Gtk2::Label->new(_"Tag"));
	$notebook->append_page( $editlabels,	Gtk2::Label->new(_"Labels"));
	$notebook->append_page( $rating,	Gtk2::Label->new(_"Rating"));
	$notebook->append_page( $songinfo,	Gtk2::Label->new(_"Info"));

	SetWSize($dialog,'SongInfo');
	$dialog->show_all;

	$dialog->signal_connect( response => sub
	{	warn "EditTag response : @_\n" if $debug;
		my ($dialog,$response)=@_;
		$songinfo->destroy;
		if ($response eq 'ok')
		{	&{ $editlabels->{save} };
			&{ $rating->{save} }($rating);
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
	my $row=0;
	for my $col (@TAGSELECTION)
	{	my $lab1=Gtk2::Label->new;
		my $lab2=$table->{$col}=Gtk2::Label->new;
		$lab1->set_markup('<b>'.$TagProp[$col][0].' :</b>');
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
	{ for my $col (@TAGSELECTION)
	  {	my $t=$TagProp[$col][2];
		my $val=$Songs[$ID][$col];
		if    ($t eq 'd') { $val=$val ? scalar localtime $val : 'never' }
		elsif ($t eq 'l') { $val=sprintf '%d:%02d',$val/60,$val%60 }
		elsif ($t eq 'f') { $val='' unless defined $val; $val=~s/\x00$//;$val=~s/\x00/, /g; }
		$table->{$col}->set_text($val);
	  }
	};
	my $watcher=AddWatcher([$ID],\@TAGSELECTION,$fillsub);
	$table->signal_connect( destroy => sub {RemoveWatcher($watcher);} );
	&$fillsub();
	return $table;
}

sub SongRating
{	my @IDs=@_;
	no warnings 'uninitialized';
	my %h; $h{ $Songs[$_][SONG_RATING] }++ for @IDs;
	my $val=(sort { $h{$b} <=> $h{$a} } keys %h)[0];

	my $updatesub=sub
	{	my ($self,$v)=@_;
		$self=$self->parent until $self->{stars};
		return if $self->{busy};
		$self->{busy}=1;
		$v='' unless defined $v;
		$self->{modif}=1 if exists $self->{val};
		$self->{val}=$v;
		$self->{check}->set_active($v eq '');
		$self->{stars}->set($v);
		$v=$Options{DefaultRating} if $v eq '';
		$self->{adj}->set_value($v);
		$self->{busy}=0;
	};
	my $adj=Gtk2::Adjustment->new(0,0,100,10,20,0);
	my $spin=Gtk2::SpinButton->new($adj,10,0);
	my $check=Gtk2::CheckButton->new(_"use default");
	my $stars=Stars->new($val,$updatesub);

	my $self=Vpack( $check,[$spin,$stars] );
	$self->{IDs}=\@IDs;
	$self->{stars}=$stars;
	$self->{check}=$check;
	$self->{adj}=$adj;

	&$updatesub($self,$val);
	$adj->signal_connect(value_changed => sub{ &$updatesub($self,$_[0]->get_value) });
	$check->signal_connect(toggled	   => sub{ &$updatesub($_[0], ($_[0]->get_active ? '' : $Options{DefaultRating}) ) });

	$self->{save}=sub
	{	my $self=$_[0];
		return unless $self->{modif}; #do nothing if rating not modified
		my $val=$self->{val};
		$Songs[$_][SONG_RATING]=$val for @{$self->{IDs}};
		SongsChanged(SONG_RATING,$self->{IDs});
	};

	return $self;
}

sub UpdateDefaultRating
{	my @l=grep $Songs[$_] && (!defined $Songs[$_][SONG_RATING] || $Songs[$_][SONG_RATING] eq ''), 0..$#Songs;
	SongsChanged(SONG_RATING,\@l);
}

sub AddWatcher
{	my $n=0;
	$n++ while defined $SongsWatchers[$n];
	if (@_) { ChangeWatcher($n,@_); }
	else { $SongsWatchers[$n]=0; }
	return $n;
}
sub ChangeWatcher
{	warn "ChangeWatcher @_\n" if $debug;
	my $n=shift;
	#Remove watcher if it exist
	for my $aref (grep defined,@Watched,@WatchedFilt)
	{	@$aref=grep $_!=$n,@$aref;
	}
	unless (@_) { $SongsWatchers[$n]=0; return; }
	my ($listref,$cols,$update,$remove,$add,$filter,$fqueue)=@_;
	#Add watcher with new properties
	push @{$Watched[$_]},$n for ( ref$cols ? @$cols : $cols );
	if ($filter)
	{	my ($greponly,@fields)=$filter->info;
		push @{ $WatchedFilt[$_] },$n for @fields;
		warn "filter fields : '@fields'\n" if $debug;
		$fqueue=undef if $greponly;
		$filter=undef if $filter->is_empty;
	}
	$SongsWatchers[$n]=[$listref,$update,$remove,$add,$filter,$fqueue];
}
sub RemoveWatcher
{	warn "RemoveWatcher @_\n" if $debug;
	my $n=$_[0];
	ChangeWatcher($n);
	delete $SongsWatchers[$n];
}

# old watchers notes :
	#watchers:
	#	one field			#labels/dir lists, filterpane, queue
	#	few/many fields			#AABox, Random, listview, add/removeAA, skin
	#
	#	incremental sub with old value	#removeAA, AABox, labels/dir lists, filterpane
	#	incremental sub			#addAA, listview
	#	big sub	(with sort)		#SF
	#	short sub multi-IDs		#queue
	#
	#	all IDs				#random, add/removeAA, filterpane
	#	list of IDs with filter		#listview, AABox, SF, filterpane
	#	list of IDs			#queue
	#	one ID				#skin, (listview->AAbox) ??
	#changes:
	#	one field, all IDs		#remove label
	#	one field, many IDs		#rename file/folder, edit labels/rating
	#	few/many fields, few/one IDs	#checksong, played
	#	all fields, few/one IDs		#add/delete/remove song
	#-------------------------------------------------------------------------------------
	#listref :	undef : all
	#		ref : [@IDs]
	#filter :	undef : none/don't watch
	#		defined : extract cols to watch
	#			  extract cmd -> determine incremental/not
	#cols :		[@cols]
	#$sub_chg,$sub_rmv,$sub_add : undef -> don't care
	#				incremental / not
	#
	#
	#
sub SongsChanged	# ($field,@IDs)
{	warn "SongsChanged @_\n" if $debug;
	my ($col,$IDs)=@_;
	$Filter::CachedList=undef;
	if ($TogLock && $TogLock==$col && grep($SongID==$_,@$IDs)) {&UpdateLock}	#update lock
	my @wake;
	$wake[$_]=1 for @{$Watched[$col]};
	$wake[$_]|=2 for @{$WatchedFilt[$col]};

	for my $n (grep $wake[$_],0..$#wake)
	{	my %ID;
		$ID{$_}=0 for @$IDs;
		my ($listref,$update,$remove,$add,$filter,$fqueue)=@{ $SongsWatchers[$n] };
		if ($fqueue && $wake[$n]&2) {&$fqueue(keys %ID); next; }
		if ($listref)
		{	for (@$listref) { $ID{$_}=1 if exists $ID{$_}; }
		}
		else { $_=1 for values %ID; }		#$listref is undef -> every song is in the list
		if ($wake[$n]==1) { &$update( grep $ID{$_},keys %ID ); next }
		$ID{$_}|=2 for @{ &{$filter->{'sub'}}([keys %ID]) };
		my @f;
		while (my($ID,$f)=each %ID) { push @{$f[ $f ]},$ID; }
		&$update( @{$f[3]} ) if $f[3] && $wake[$n]&1 && $update;
		&$remove( @{$f[1]} ) if $f[1] && $remove;
		&$add   ( @{$f[2]} ) if $f[2] && $add;
	}
}
sub SongChanged		# ($ID,@fields)
{	warn "SongChanged @_\n" if $debug;# my $time=times;		#DEBUG
	$Filter::CachedList=undef;
	my $ID=shift;
	if (defined $SongID && $ID==$SongID && $TogLock && grep($TogLock==$_,@_)) {&UpdateLock}	#update lock
	my @wake; #warn "@$_" for @Watched;
	$wake[$_]=1 for map @{$Watched[$_]},@_;
	$wake[$_]|=2 for map @{$WatchedFilt[$_]},@_;
	for my $n (grep $wake[$_],0..$#wake)
	{	#warn "SongChanged $n $wake[$n] @{$SongsWatchers[$n]}\n";
		my ($listref,$update,$remove,$add,$filter,$fqueue)=@{ $SongsWatchers[$n] };
		if ($fqueue && $wake[$n]&2) {&$fqueue($ID) if $fqueue; warn "$n -> queue\n" if $debug; next; }
		my $found=0;
		if ($listref)
		{	for (@$listref) {next unless $_==$ID;$found=1;last}
		}
		else {$found=1;}		#$listref is undef -> every song is in the list
		if ($wake[$n]==1) {&$update($ID) if $found && $update; warn "$n -> update\n" if ($found && $debug);next;}
		$found|=2 if @{ &{$filter->{'sub'}}([$ID]) }>0;
		if    ($found==3) { &$update($ID) if $wake[$n]&1 && $update; warn "$n -> update\n" if $debug; }
		elsif ($found==1) { &$remove($ID) if $remove; warn "$n -> remove\n" if $debug; }
		elsif ($found==2) { &$add($ID)    if $add; warn "$n -> add\n" if $debug; }
	}
	#$time=times-$time; warn "song changed : $time s\n" if $debug;	#DEBUG
}
sub SongAdd		#only called from IdleLoop
{	#my $time=times;		#DEBUG
	$Filter::CachedList=undef;
	my $ID=shift @ToAdd;
	my $aref=$Songs[$ID];
	RemoveMissing($ID) if $$aref[SONG_MISSINGSINCE] && $$aref[SONG_MISSINGSINCE]=~m/^\d/;
	my $file=$$aref[SONG_PATH].SLASH.$$aref[SONG_FILE];
	my ($size,$timestamp)=(stat $file)[7,9];
	unless ($$aref[SONG_MODIF] && $$aref[SONG_MODIF]==$timestamp && $$aref[SONG_LENGTH])
		#don't read tag if song already known and not modified
	{	my $checkmissing= !$$aref[SONG_MODIF] && $MissingCount;
		$$aref[SONG_MODIF]=$timestamp;
		$$aref[SONG_SIZE]=$size;
		warn "Reading Tag for [$ID] $file\n";
		my $read_result=ReadTag::Read($aref,$file,1);
		unless ($read_result) {$Songs[$ID]=undef;return}
		if ($checkmissing && CheckMissing($aref) && $$aref[SONG_LENGTH]) #check if new song is a missing song
		 {$read_result=1} #No need to check length if found missing song because the length was copied from old record
		if ($read_result==2) { push @LengthEstimated,$ID; $Songs[$ID][SONG_MISSINGSINCE]='l'; }
	}
	push @Library,$ID;
	AddAA($ID);
	for my $watcher (@SongsWatchers)
	{	next unless $watcher;
		my ($listref,undef,undef,$add,$filter,$fqueue)=@$watcher;
		next unless $add;
		#my @ret=@{ &{$filter->{'sub'}}([$ID]) } if $filter;	#DEBUG
		#warn "Addind $ID (".$::Songs[$ID][::SONG_ALBUM].") ".($filter->explain)." [@ret] =".scalar(@ret) if $filter;	#DEBUG
		if ($filter)
		{	if ($fqueue) { &$fqueue($ID); next; }
			elsif ( @{ &{$filter->{'sub'}}([$ID]) }==0 ) {next}
		}
		warn "$watcher -> add\n" if $debug;
		&$add($ID);
	}
	$ProgressNBSongs++;
	#$time=times-$time; warn "song add : $time s\n" if $debug;	#DEBUG
}
sub SongsRemove
{	my $IDs=$_[0];
	$Filter::CachedList=undef;
	my %ID;
	$ID{$_}=undef for @$IDs;
	for my $watcher (@SongsWatchers)
	{	next unless $watcher;
		my ($listref,undef,$remove,undef,$filter)=@$watcher;
		next unless $remove;
		if ($listref)
		{	&$remove( grep(exists $ID{$_},@$listref) );
		}
		else { &$remove(@$IDs); }	#$listref is undef -> every song is in the list
	}
	for my $ID (@$IDs) { RemoveAA($ID, $Songs[$ID] ) }
	my $qsize=@Queue;
	@$_=grep !exists $ID{$_},@$_ for \@Library,\@Queue,\@Recent,values %SavedLists;
	HasChanged('Queue') if $qsize!=@Queue;
	$RecentPos-- while $RecentPos && $Recent[$RecentPos-1]!=$SongID; #update RecentPos if needed

	for my $ID (@$IDs)
	{ AddMissing($ID,1);
	}
}
sub SongRemove
{	#my $time=times;		#DEBUG
	$Filter::CachedList=undef;
	my $ID=shift;
	for my $watcher (@SongsWatchers)
	{	next unless $watcher;
		my ($listref,undef,$remove,undef,$filter)=@$watcher;	#remove unused
		next unless $remove;
		my $found;
		if ($listref)
		{	for (@$listref) {next unless $_==$ID;$found=1;last}
			next unless $found;
		}
		&$remove($ID);
	}
	RemoveAA($ID, $Songs[$ID] );
	my $qsize=@Queue;
	@$_=grep $ID!=$_, @$_ for \@Library,\@Queue,\@Recent,values %SavedLists;
	HasChanged('Queue') if $qsize!=@Queue;
	$RecentPos-- while $RecentPos && $Recent[$RecentPos-1]!=$SongID; #update RecentPos if needed

	AddMissing($ID,1);
	#$Songs[$ID]=undef;
	#$time=times-$time; warn "song remove : $time s\n" if $debug;	#DEBUG
}
sub SongCheck
{	return if $CmdLine{demo};
	my ($ID,$forcefullscan)=@_;
	my $aref=$Songs[$ID];
	return 0 unless $aref;
	return 1 if $aref->[SONG_PATH]=~m#^http://#;
	$forcefullscan=2 if $aref->[SONG_MISSINGSINCE];
	my $file=$$aref[SONG_PATH].SLASH.$$aref[SONG_FILE];
	if (-r $file)
	{	my ($size,$timestamp)=(stat $file)[7,9];
		return 1 if !$forcefullscan && $$aref[SONG_MODIF]==$timestamp;
		my $checklength=$forcefullscan || ( $$aref[SONG_SIZE]!=$size );
		my @old=@$aref;
		$$aref[SONG_MODIF]=$timestamp;
		$$aref[SONG_SIZE]=$size;
		warn "Reading Tag for [$ID] $file\n";
		my $read_result=ReadTag::Read($aref,$file,$checklength);
		if ($aref->[SONG_MISSINGSINCE] && $aref->[SONG_MISSINGSINCE]=~m/^\d/) {$aref->[SONG_MISSINGSINCE]=$DAYNB;return 1} #for songs not in library
		elsif ($checklength && $read_result==2) { push @LengthEstimated,$ID; $aref->[SONG_MISSINGSINCE]='l'; }
		else {$aref->[SONG_MISSINGSINCE]=undef}
		no warnings 'uninitialized';
		my @changed=grep $$aref[$_] ne $old[$_],0..SONGLAST;
		for my $field (@changed)
		{	next unless $field==SONG_ALBUM || $field==SONG_ARTIST || $field==SONG_LENGTH || $field==SONG_DATE;
			RemoveAA($ID,\@old);
			AddAA($ID);
			last;
		}
		SongChanged($ID, @changed );
		return 1;
	}
	else	#file not found/readable
	{	warn "can't read file '$file'\n";

		for ($ID,"L$ID") { $Editing{$_}->destroy if exists $Editing{$_};}
		SongRemove($ID);
		#$Songs[$ID]=undef;
		#delete $GetIDFromFile{$file};
		#AddMissing($ID,1);
		return 0;
	}
}

sub AddAA
{	my $ID=$_[0];
	my ($album,$artist,$l,$y)=@{ $Songs[$ID] }[SONG_ALBUM,SONG_ARTIST,SONG_LENGTH,SONG_DATE];
	#warn "adding $ID to $album $artist\n" if $debug;
	push @{$Album{$album}[AALIST]},$ID;
	for my $art (split /$re_artist/o,$artist)
	{	push @{$Artist{$art}[AALIST]},$ID;
		$Artist{$art}[AALENGTH]+=$l;
		$Artist{$art}[AAXREF]{$album}++;
		$Album{$album}[AAXREF]{$art}++;
		$ToUpdateYAr{$art}=undef if $y;
	}
	$Album{$album}[AALENGTH]+=$l;
	if ($y)
	{	$ToUpdateYAl{$album}=undef;
		::IdleDo('2_UAAYear',500, \&UpdateAAYear);
	}
	#if (!$Album{$album}[AAPIXLIST] && $Album{$album}[AAPIXLIST] ne '0')
	#{	my $f=$Songs[$ID][SONG_PATH].SLASH.'cover.jpg';
	#	if (-r $f)
	#	{ $Album{$album}[AAPIXLIST]=$f; HasChanged('AAPicture',$album); }
	#}
}

sub RemoveAA
{	my ($ID,$oldref)=($_[0],$_[1]);
	my ($album,$artist,$l,$y)=@$oldref[SONG_ALBUM,SONG_ARTIST,SONG_LENGTH,SONG_DATE];
	warn "removing $ID from $album $artist\n" if $debug;
	my @listrefs=( \@{$Album{$album}[AALIST]} );
	$Album{$album}[AALENGTH]-=$l;
	for my $art (split /$re_artist/o,$artist)
	{	$Artist{$art}[AALENGTH]-=$l;
		push @listrefs,\@{$Artist{$art}[AALIST]};
		unless (--$Artist{$art}[AAXREF]{$album}) {delete $Artist{$art}[AAXREF]{$album};}
		unless (--$Album{$album}[AAXREF]{$art})  {delete $Album{$album}[AAXREF]{$art};}
		$ToUpdateYAr{$art}=undef if $y;
	}
	if ($y)
	{	$ToUpdateYAl{$album}=undef;
		::IdleDo('2_UAAYear',500, \&UpdateAAYear);
	}
	for my $l (@listrefs) { @$l=grep $_!=$ID,@$l; }
}

sub UpdateAAYear
{	for my $refs ([\%Artist,\%ToUpdateYAr],[\%Album,\%ToUpdateYAl])
	{	my ($href,$lref)=@$refs;
		for my $aa (keys %$lref)
		{	my @y=sort { $a <=> $b } grep $_,map $Songs[$_][SONG_DATE], @{ $href->{$aa}[AALIST] };
			my $year='';
			if (@y)
			{	$year=$y[0];
				my $max=pop @y;
				$year.=' - '.$max if $year!=$max; #add last year if !=
			}
			$href->{$aa}[AAYEAR]=$year;
		}
		%$lref=();
	}
}

sub AddMissing
{	my $ID=$_[0];
	if ($_[1]) { my $ref=\$Songs[$ID][SONG_MISSINGSINCE]; if ($$ref && $$ref eq 'l') {$Songs[$ID][SONG_LENGTH]=''} $$ref=$DAYNB; }
	my $staat=join "\x1D", grep defined, map $Songs[$ID][$_],@STAAT;
	push @{ $MissingSTAAT{$staat} },$ID;
	$MissingCount++;
}
sub RemoveMissing
{	my $ID=$_[0];
	my $staat=join "\x1D", grep defined, map $Songs[$ID][$_],@STAAT;
	my $aref=$MissingSTAAT{$staat};
	if (!$aref)	{warn "unregistered missing song";return}
	elsif (@$aref>1){ @$aref=grep $_ != $ID, @$aref; }
	else		{ delete $MissingSTAAT{$staat}; }
	$Songs[$ID][SONG_MISSINGSINCE]=undef;
	$MissingCount--;
}
sub CheckMissing
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

sub Url_to_IDs
{	my @IDs;
	for my $f (split / /,$_[0])
	{	if ($f=~m#^http://#) { push @IDs,AddRadio($f,1); }
		else
		{	$f=decode_url($f);
			my $l=ScanFolder($f);
			push @IDs, @$l if ref $l;
		}
	}
	return \@IDs;
}

sub AddToLibrary
{	my @list=map decode_url($_), @_;
	IdleScan(@list);
}

sub ScanFolder
{	my $notlibrary=$_[0];
	my $dir= $notlibrary || shift @ToScan;
	$dir=~s#^file://##; $dir=~s/$QSLASH+$//o;
	warn "Scanning $dir\n" if $debug;
	$ProgressNBFolders++ unless $notlibrary;
	my @pictures;
	unless ($ScanRegex)
	{	my @list= $Options{ScanPlayOnly}? ($PlayNext_package||$Play_package)->supported_formats
						: qw/mp3 ogg flac mpc ape wv/; #FIXME find a better way,  wvc
		my $s=join '|',@list;
		$ScanRegex=qr/\.(?:$s)$/i;
	}
	my @files;
	if (-d $dir)
	{	opendir my($DIRH),$dir or warn "Can't read folder $dir : $!\n";
		@files=readdir $DIRH;
		closedir $DIRH;
	}
	elsif (-f $dir && $dir=~s/$QSLASH([^$QSLASH]+)$//)
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
	push @ToAdd,@toadd;
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
	my $cover=$Album{$alb}[AAPIXLIST];
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
	$Album{$alb}[AAPIXLIST]=$dir.SLASH.$best;
	warn "found cover for $alb : $best)\n" if $debug;
	HasChanged('AAPicture',$alb);
}

sub AboutDialog
{	my $dialog=Gtk2::AboutDialog->new;
	$dialog->set_version(VERSIONSTRING);
	$dialog->set_copyright("Copyright © 2005-2008 Quentin Sculo");
	#$dialog->set_comments();
	$dialog->set_license("Released under the GNU General Public Licence version 3\n(http://www.gnu.org/copyleft/gpl.html)");
	$dialog->set_website('http://gmusicbrowser.sourceforge.net/');
	$dialog->set_authors('Quentin Sculo <squentin@free.fr>');
	$dialog->set_artists("tango icon theme : Jean-Philippe Guillemin\n tray icon for the tango theme by Piotr");
	$dialog->set_translator_credits("French : Quentin Sculo and Jonathan Fretin\nHungarian : Zsombor\nSpanish : Martintxo and Juanjo\nGerman : vlad <donvla\@users.sourceforge.net> & staubi <staubi\@linuxmail.org>\nPolish : tizzilzol team\nSwedish : Olle Sandgren\nChinese : jk");
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
	$notebook->append_page( PrefLabels()	,Gtk2::Label->new(_"Labels"));
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
		my %list= ExtractNameAndOptions($Options{CustomKeyBindings});
		for my $key (sort keys %list)
		{	my ($cmd,$arg)=  $list{$key}=~m/^(\w+)(?:\((.*)\))?$/;
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
			$child= (ref $Command{$cmd}[3] eq 'CODE')? &{ $Command{$cmd}[3] }  : Gtk2::Entry->new;
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
		my %list= ExtractNameAndOptions($Options{CustomKeyBindings});
		$list{$key}=$cmd;
		$Options{CustomKeyBindings}=join ' ',%list;
		&$refresh_sub;
	 });
	my $butrm=  ::NewIconButton('gtk-remove',_"Remove",sub
	 {	my $iter=$treeview->get_selection->get_selected;
		my $key=$store->get($iter,2);
		my %list= ExtractNameAndOptions($Options{CustomKeyBindings});
		delete $list{$key};
		$Options{CustomKeyBindings}=join ' ',%list;
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
	my $vbox=Gtk2::VBox->new;
	unless (keys %Plugins) {my $label=Gtk2::Label->new(_"no plugins found"); $vbox->add($label);return $vbox}
	my $store=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::Boolean');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(FALSE);
	my $renderer = Gtk2::CellRendererToggle->new;
	my $hbox=Gtk2::HBox->new;
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
	$vbox->add($hbox);
	return $vbox;
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
			return if $Packs{$p}==$Play_package;
			$PlayNext_package=$Packs{$p};
			SwitchPlayPackage() unless defined $PlayTime;
			$ScanRegex=undef;
		},
		gstreamer		=> 'Play_GST',
		'mpg321/ogg123/flac123' => 'Play_123',
		mplayer			=> 'Play_mplayer',
		_"icecast server"	=> sub {$Options{use_GST_for_server}? 'Play_GST_server' : 'Play_Server'},
		);

	#123
	my $vbox_123=Gtk2::VBox->new (FALSE, 2);
	my $hbox1=NewPrefCombo(Device => [qw/default oss alsa esd arts sun/],_"output device :",undef,$sg1,$sg2);
	my $adv1=PrefAudio_makeadv('Play_123','123');
	$vbox_123->pack_start($_,FALSE,FALSE,2) for $radio_123,$hbox1,$adv1;

	#gstreamer
	my $vbox_gst=Gtk2::VBox->new (FALSE, 2);
	my $hbox2=NewPrefCombo(gst_sink => Play_GST->supported_sinks,_"output device :",undef,$sg1,$sg2);
	my $EQbut=Gtk2::Button->new(_"Open Equalizer");
	$EQbut->signal_connect(clicked => sub {Layout::Window->new('Equalizer');});
	my $EQcheck=NewPrefCheckButton(gst_use_equalizer => _"Use Equalizer", sub { HasChanged('Equalizer'); });
	$sg1->add_widget($EQcheck);
	my $EQbox=Hpack($EQcheck,$EQbut);
	$EQbox->set_sensitive(0) unless $Packs{Play_GST} && $Packs{Play_GST}{EQ};
	my $RGbox=Play_GST::RGA_PrefBox($sg1);
	my $adv2=PrefAudio_makeadv('Play_GST','gstreamer');
	$vbox_gst->pack_start($_,FALSE,FALSE,2) for $radio_gst,$hbox2,$EQbox,$RGbox,$adv2;

	#icecast
	my $vbox_ice=Gtk2::VBox->new(FALSE, 2);
	$Options{use_GST_for_server}=0 unless $Packs{Play_GST_server};
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

	$vbox_123->set_sensitive($Packs{Play_123});
	$vbox_gst->set_sensitive($Packs{Play_GST});
	$vbox_ice->set_sensitive($Packs{Play_Server});
	$vbox_mp ->set_sensitive($Packs{Play_mplayer});
	$usegst->set_sensitive($Packs{Play_GST_server});

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
	$package=$Packs{$package};
	my $hbox=Gtk2::HBox->new(FALSE, 2);
	if (1)
	{	my $label=Gtk2::Label->new;
		$label->signal_connect(realize => sub	#delay finding supported formats because mplayer is slow
			{	my $list=join ' ',sort $package->supported_formats;
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
		{ IdleDo('0_DefaultRating',500,\&UpdateDefaultRating);
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
	my $shutentry=NewPrefEntry(Shutdown_cmd => _"Shutdown command :",undef,undef,undef,undef,_"Command used when\n'turn off computer when queue empty'\nis selected");
	#artist splitting
	my %split=
	(	' & |, '	=> _"' & ' and ', '",
		' & '		=> "' & '",
		' \\+ '		=> "' + '",
		'$'		=> _"no splitting",
	);
	my $asplit=NewPrefCombo(ArtistSplit => \%split,_"Split artist names on (needs restart) :");


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
	my $layoutT=NewPrefCombo(LayoutT=> Layout::get_layout_list('T'),_"Tray tip window layout :",undef,$sg1,$sg2);
	my $layout =NewPrefCombo(Layout => Layout::get_layout_list('G'),_"Player window layout :",\&set_layout,$sg1,$sg2);
	my $layoutB=NewPrefCombo(LayoutB=> Layout::get_layout_list('B'),_"Browser window layout :",undef,$sg1,$sg2);
	my $layoutF=NewPrefCombo(LayoutF=> Layout::get_layout_list('F'),_"Full screen layout :",undef,$sg1,$sg2);
	my $layoutS=NewPrefCombo(LayoutS=> Layout::get_layout_list('S'),_"Search window layout :",undef,$sg1,$sg2);

	#fullscreen button
	my $fullbutton=NewPrefCheckButton(AddFullscreenButton => _"Add a fullscreen button",\&AddFullscreenButton,_"Add a fullscreen button to layouts that can accept extra buttons");


	my $icotheme=NewPrefCombo(IconTheme=> GetIconThemesList(),_"Icon theme :", \&LoadIcons,$sg1,$sg2);

	#packing
	$vbox->pack_start($_,FALSE,FALSE,1) for $layout,$layoutB,$layoutT,$layoutF,$layoutS,$checkT1,$fullbutton,$icotheme;
	return $vbox;
}

sub AddFullscreenButton #FIXME put this sub somewhere else
{	if ($Options{AddFullscreenButton}) {ExtraWidgets::AddWidget('fullscreen_button','button',sub{$_[0]->NewObject('Fullscreen')});}
	else { ExtraWidgets::RemoveWidget('fullscreen_button'); }
}

sub set_layout
{	my $old=$MainWindow;
	$old->SaveOptions;
	$MainWindow=Layout::Window->new( $Options{Layout} );
	$old->destroy;
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
	my $id3v1encoding=NewPrefCombo(TAG_id3v1_encoding => \@Encodings,_"Encoding used for id3v1 tags :");
	my $nowrite=NewPrefCheckButton('TAG_nowrite_mode',_"Do not write the tags",undef,_"Will not write the tags except with the advanced tag editing dialog. The changes will be kept in the library instead.\nWarning, the changes for a song will be lost if the tag is re-read.");
	my $autocheck=NewPrefCheckButton('TAG_auto_check_current',_"Auto-check current song for modification",undef,_"Automatically check if the file for the current song has changed. And remove songs not found from the library.");

	$vbox->pack_start($_,FALSE,FALSE,1) for $warning,$checkv4,$checklatin1,$check_unsync,$id3v1encoding,$nowrite,$autocheck;
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
		last if $new=~m/$QSLASH/;	#FIXME allow moving folder
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
	my @renamed;
	$oldpath=qr/^\Q$oldpath\E/;
	for my $ID (0..$#Songs)
	{	my $aref=$Songs[$ID];
		next unless defined $aref;
		my $old=$$aref[SONG_PATH];
		my $new=$old.SLASH;
		#_utf8_off($new);
		next unless $new=~s/$oldpath/$newpath/;
		my $file=$$aref[SONG_FILE];
		chop $new; #remove SLASH
		#_utf8_on($new);
		$GetIDFromFile{$new}{$file}=delete $GetIDFromFile{$old}{$file};
		delete $GetIDFromFile{$old} unless keys %{ $GetIDFromFile{$old} };
		$$aref[SONG_PATH]=$new;
		$$aref[SONG_UPATH]=filename_to_utf8displayname($new);
		push @renamed,$ID;
	}

	#rename pic files in %Artist %Album
	for my $ref (values %Artist, values %Album)
	{	#_utf8_off($$ref[AAPIXLIST]);
		$$ref[AAPIXLIST]=~s/$oldpath/$newpath/ if exists $$ref[AAPIXLIST];
		#_utf8_on($$ref[AAPIXLIST]);
	}
	SongsChanged(SONG_PATH,\@renamed);
	SongsChanged(SONG_UPATH,\@renamed);
}

sub PrefLibrary
{	my $store=Gtk2::ListStore->new('Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	$treeview->set_headers_visible(FALSE);
	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		( _"Folders to search for new songs",Gtk2::CellRendererText->new,'text',0)
		);
	$store->set($store->append,0,filename_to_utf8displayname($_)) for @LibraryPath;
	::set_drag($treeview, dest => [::DRAG_FILE,sub
		{	my ($treeview,$type,@list)=@_;
			@list=map ::decode_url($_), grep s#^file://##, @list;
			for my $dir (grep -d, @list)
			{	next if (grep $dir eq $_,@LibraryPath);
				$dir=~s/$QSLASH$//o unless $dir eq SLASH || $dir=~m/^\w:.$/;
				$store->set($treeview->get_model->append,0,filename_to_utf8displayname($dir));
				push @LibraryPath,$dir;
				IdleScan($dir);
			}
		}]);

	my $addbut=NewIconButton('gtk-add',_"Add folder");
	my $rmdbut=NewIconButton('gtk-remove',_"Remove");

	my $selection=$treeview->get_selection;
	$selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$rmdbut->set_sensitive($sel);
		});
	$rmdbut->set_sensitive(FALSE);

	$addbut->signal_connect( clicked => sub
	{	my @dirs=ChooseDir(_"Choose folder to add",$CurrentDir.SLASH,undef,1);
		return unless @dirs;
		for my $dir (@dirs)
		{	next if (grep $dir eq $_,@LibraryPath);
			$dir=~s/$QSLASH$//o unless $dir eq SLASH || $dir=~m/^\w:.$/;
			$store->set($store->append,0,filename_to_utf8displayname($dir));
			push @LibraryPath,$dir;
			IdleScan($dir);
		}
	});
	$rmdbut->signal_connect( clicked => sub
	{	my $iter=$selection->get_selected;
		return unless defined $iter;
		my $i=$store->get_path($iter)->to_string;
		$store->remove($iter);
		splice @LibraryPath,$i,1;
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
	{	return unless @Library;
		DialogMassRename(@Library);
	});

	my $vbox=Vpack( 1,$label,
			'_',$sw,
			[$addbut,$rmdbut,'-',$reorg],
			$table );
	return $vbox;
}

sub ToggleLabel
{	my ($label,$ID,$on)=@_;
	return unless defined $ID && defined $label;
	my $add=[]; my $rm=[];
	unless (defined $on)
	{	$on= $::Songs[$ID][::SONG_LABELS]!~m/(?:^|\x00)\Q$label\E(?:$|\x00)/; #on=1 if not set
	}
	if ($on) { $add=[$label] }
	else	 { $rm =[$label] }
	SetLabels([$ID],$add,$rm);
}

sub SetLabels
{	my ($IDs,$toadd,$torm)=@_;
	my $nb=keys %Labels;
	$Labels{$_}=undef for @$toadd;
	HasChanged('LabelList') if (keys %Labels)-$nb;
	no warnings;
	for my $ID (@$IDs)
	{	my %h;
		$h{$_}=undef for @$toadd,split /\x00/,$Songs[$ID][SONG_LABELS];
		delete $h{$_} for @$torm;
		$Songs[$ID][SONG_LABELS]=join "\x00",sort keys %h;
	}
	SongsChanged(SONG_LABELS,$IDs);
}

sub PrefLabels
{	my $vbox=Gtk2::VBox->new(FALSE,2);
	my $store=Gtk2::ListStore->new('Glib::String','Glib::Int','Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	my $renderer=Gtk2::CellRendererText->new;
	$renderer->set(editable => TRUE);
	$renderer->signal_connect(edited => sub
	    {	my ($cell,$pathstr,$new)=@_;
		$new=~s/\x00//g;
		return if ($new eq '') || exists $Labels{$new};
		my $iter=$store->get_iter_from_string($pathstr);
		my ($old,$nb)=$store->get_value($iter);
		return if $new eq $old;
		$store->set($iter,0,$new,2,'label-'.$new);
		$Labels{$new}=delete $Labels{$old};
		#FIXME maybe should rename the icon file if it exist
		HasChanged('LabelList');
		return unless $nb;
		my $pat=qr/(?:^|\x00)\Q$old\E(?:$|\x00)/;
		my @l=grep $Songs[$_][SONG_LABELS]=~m/$pat/, 0..$#Songs;
		SetLabels(\@l,[$new],[$old]);
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
		my %set; no warnings;
		for my $ref (@Songs)
		{	$set{$_}++ for split /\x00/,$$ref[SONG_LABELS];
		}
		for my $f (sort keys %Labels)
		{	$store->set($store->append, 0,$f, 1,$set{$f}||0, 2,'label-'.$f);
		}
	    };
	my $watcher;
	$vbox->signal_connect(realize => sub
		{  #warn "realize @_\n" if $debug;
		   my $sub=sub { IdleDo('9_Labels',3000,$fillsub); };
		   $watcher=AddWatcher(undef,SONG_LABELS,$sub);
		   &$fillsub;
		 });
	$vbox->signal_connect(unrealize => sub
		{  #warn "unrealize @_\n" if $debug;
		   delete $ToDo{'9_Labels'};
		   RemoveWatcher($watcher);
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
				my $pat=qr/(?:^|\x00)\Q$label\E(?:$|\x00)/;
				my @l=grep $Songs[$_][SONG_LABELS]=~m/$pat/, 0..$#Songs;
				SetLabels(\@l,undef,[$label]);
				$dialog->destroy;
			}
			$store->remove($iter);
			delete $Labels{$label};
		});
	my $addbut=NewIconButton('gtk-add',_"Add label",sub
		{	my $iter=$store->append;
			$store->set($iter,0,'',1,0);
			$treeview->set_cursor($store->get_path($iter), $treeview->get_column(1), TRUE);
		});
	my $iconbut=NewIconButton('gmb-picture',_"Set icon",sub
		{	my ($row)=$treeview->get_selection->get_selected_rows;
			return unless defined $row;
			my $iter=$store->get_iter($row);
			my ($label)=$store->get_value($iter);
			my $file=ChoosePix($CurrentDir.SLASH,__x("Choose icon for label {label}",label => $label));
			return unless defined $file;
			my $dir=$::HomeDir.'icons';
			unless (-d $dir)
			{	warn "Creating $dir\n";
				unless (mkdir $dir)
				{ ErrorMessage(__x(_"Error creating {folder} :\n{error}",folder=>$dir,error=>$!));
				  return;
				}
			}
			my $destfile=$::HomeDir.'icons'.SLASH.'label-'.url_escape($label);
			unlink $destfile.'.svg',$destfile.'.png';
			if ($file eq '0') {}	#unset icon
			elsif ($file=~m/\.svg/i)
			{	$destfile.='.svg';
				copy($file,$destfile.'.svg');
			}
			else
			{	$destfile.='.png';
				my $pixbuf=PixBufFromFile($file,48);
				return unless $pixbuf;
				$pixbuf->save($destfile,'png');
			}
			LoadIcons();
			$treeview->queue_draw;
		});

	$delbut->set_sensitive(FALSE);
	$iconbut->set_sensitive(FALSE);
	$treeview->get_selection->signal_connect( changed => sub
		{	my $s=$_[0]->count_selected_rows;
			$delbut->set_sensitive($s);
			$iconbut->set_sensitive($s);
		});

	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never','automatic');
	$sw->add($treeview);
	$vbox->add($sw);
	$vbox->pack_start( Hpack($addbut,$delbut,$iconbut) ,FALSE,FALSE,2);

	return $vbox;
}

sub NewPrefRadio
{	my ($key,$sub,@text_val)=@_;
	my $init=$Options{$key};
	$init='' unless defined $init;
	my $cb=sub
		{	return unless $_[0]->get_active;
			my $val=$_[1];
			$val=&$val if ref $val;
			$Options{$key}=$val;
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
{	my ($key,$text,$sub,$tip,$widget,undef,$horizontal,$sizeg)=@_;
	my $check=Gtk2::CheckButton->new($text);
	$check->set_active(1) if $Options{$key};
	$sizeg->add_widget($check) if $sizeg;
	$check->signal_connect( toggled => sub
	{	$Options{ $_[1] }=($_[0]->get_active)? 1 : 0;
		$_[0]{child}->set_sensitive( $_[0]->get_active )  if $_[0]{child};
		&$sub if $sub;
	},$key);
	$Tooltips->set_tip($check,$tip) if defined $tip;
	my $return=$check;
	if ($widget)
	{	if ($horizontal)
		{	$return=Hpack($check,$widget);
		}
		else
		{	my $albox=Gtk2::Alignment->new(0,0,1,1);
			$albox->set_padding(0,0,15,0);
			$albox->add($widget);
			$widget=$albox;
			$return=Vpack($check,$albox);
		}
		$check->{child}=$widget;
		$widget->set_sensitive(0) unless $Options{$key};
	}
	return $return;
}
sub NewPrefEntry
{	my ($key,$text,$sub,$sizeg1,$sizeg2,$hide,$tip)=@_;
	my $label=Gtk2::Label->new($text);
	my $entry=Gtk2::Entry->new;
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_start($label,FALSE,FALSE,2);
	$hbox->pack_start($entry,0,FALSE,2);
	$sizeg1->add_widget($label) if $sizeg1;
	$sizeg2->add_widget($entry) if $sizeg2;
	$label->set_alignment(0,.5);

	$Tooltips->set_tip($entry, $tip) if defined $tip;
	$entry->set_visibility(0) if $hide;
	$entry->set_text($Options{$key}) if defined $Options{$key};
	$entry->signal_connect( changed => sub
	{	$Options{ $_[1] }=$_[0]->get_text;
		&$sub if $sub;
	},$key);
	return $hbox;
}
sub NewPrefFileEntry
{	my ($key,$text,$folder,$sub,$tip,$sg1,$sg2)=@_;
	my $label=Gtk2::Label->new($text);
	my $entry=Gtk2::Entry->new;
	my $button=NewIconButton('gtk-open');
	my $hbox=Gtk2::HBox->new;
	my $hbox2=Gtk2::HBox->new(FALSE,0);
	$hbox2->pack_start($entry,TRUE,TRUE,0);
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
		$Options{ $_[1] }=filename_from_unicode( $_[0]->get_text );
		&$sub if $sub;
	},$key);
	$button->signal_connect( clicked => sub
	{	my $file= $folder? ChooseDir($text,$Options{$key}) : undef;
		return unless $file;
		$Options{$key}=$file;
		$busy=1; $entry->set_text(filename_to_utf8displayname($file)); $busy=undef;
		&$sub if $sub;
	});
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
	 {	$::Options{ $_[1] }=$_[0]->get_value;
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
{	my ($key,$list,$text,$sub,$sizeg1,$sizeg2)=@_;
	my $combo=Gtk2::ComboBox->new_text;
	my $names=$list;
	if (ref $list eq 'HASH')
	{	my $h=$list;
		$list=[]; $names=[];
		for my $key (sort {uc($h->{$a}) cmp uc($h->{$b})} keys %$h)
		{	push @$list,$key;
			push @$names,$h->{$key}
		}
	}
	my $found;
	for my $i (0..$#$list)
	{	$combo->append_text( $names->[$i] );
		$found=$i if defined $Options{$key} && $list->[$i] eq $Options{$key};
	}
	$combo->set_active($found) if defined $found;
	$combo->signal_connect(changed => sub
		{	$Options{$key}= $list->[ $_[0]->get_active ];
			&$sub if $sub;
		});
	return $combo unless defined $text;
	my $label=Gtk2::Label->new($text);
	my $hbox=Gtk2::HBox->new;
	$hbox->pack_start($_,FALSE,FALSE,2) for $label,$combo;
	$sizeg1->add_widget($label) if $sizeg1;
	$sizeg2->add_widget($combo) if $sizeg2;
	$label->set_alignment(0,.5);
	return $hbox;
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
		$box->pack_start($_, FALSE, FALSE, 2)
			for $widget,Gtk2::Label->new($text);
		$widget=$box;
	}
	$but->add($widget);
	$but->signal_connect(clicked => $coderef) if $coderef;
	$Tooltips->set_tip($but,$tip) if defined $tip;
	return $but;
}

sub EditWeightedRandom
{	my ($widget,$sort,$name,$sub)=@_;
	my $dialog=EditSFR->new($widget,'WRandom',$sort,$name);
	return $dialog->Result($sub);
}
sub EditSortOrder
{	my ($widget,$sort,$name,$sub)=@_;
	my $dialog=EditSFR->new($widget,'Sort',$sort,$name);
	return $dialog->Result($sub);
}
sub EditFilter
{	my ($widget,$filter,$name,$sub)=@_;
	my $dialog=EditSFR->new($widget,'Filter',$filter,$name);
	$sub||='' unless wantarray;#FIXME
	return $dialog->Result($sub);
}
sub EditSTGroupings
{	my ($widget,$filter,$name,$sub)=@_;
	my $dialog=EditSFR->new($widget,'STGroupings',$filter,$name);
	return $dialog->Result($sub);
}

sub SaveWRandom
{	my ($name,$val,$newname)=@_;
	if (defined $newname)	{$SavedWRandoms{$newname}=delete $SavedWRandoms{$name};}
	elsif (defined $val)	{$SavedWRandoms{$name}=$val;}
	else			{delete $SavedWRandoms{$name};}
	HasChanged('SavedWRandoms');
}
sub SaveSort
{	my ($name,$val,$newname)=@_;
	if (defined $newname)	{$SavedSorts{$newname}=delete $SavedSorts{$name};}
	elsif (defined $val)	{$SavedSorts{$name}=$val;}
	else			{delete $SavedSorts{$name};}
	HasChanged('SavedSorts');
}
sub SaveFilter
{	my ($name,$val,$newname)=@_;
	if (defined $newname)	{$SavedFilters{$newname}=delete $SavedFilters{$name};}
	elsif (defined $val)	{$SavedFilters{$name}=$val;}
	else			{delete $SavedFilters{$name};}
	HasChanged('SavedFilters');
}
sub SaveSTGroupings
{	my ($name,$val,$newname)=@_;
	if (defined $newname)	{$SongTree::Groupings{$newname}=delete $SongTree::Groupings{$name};}
	elsif (defined $val)	{$SongTree::Groupings{$name}=$val;}
	else			{delete $SongTree::Groupings{$name};}
	HasChanged('SavedSTGroupings');
}
sub SaveList
{	my ($name,$val,$newname)=@_;
	if (defined $newname)	{$SavedLists{$newname}=delete $SavedLists{$name}; HasChanged('SavedLists',$name,'renamedto',$newname); $name=$newname; }
	elsif (defined $val)	{$SavedLists{$name}=$val;}
	else			{delete $SavedLists{$name}; HasChanged('SavedLists',$name,'remove'); return}
	HasChanged('SavedLists',$name);
}

sub Watch
{	my ($object,$key,$sub)=@_;
	warn "watch $key $object\n" if $debug;
	push @{$EventWatchers{$key}},$object;
	$object->{'WatchUpdate_'.$key}=$sub;
	$object->signal_connect(destroy => \&UnWatch,$key) unless ref $object eq 'HASH' || !$object->isa('Gtk2::Object');
}
sub UnWatch
{	my ($object,$key)=@_;
	warn "unwatch $key $object\n" if $debug;
	@{$EventWatchers{$key}}=grep $_ ne $object, @{$EventWatchers{$key}};
	delete $object->{'WatchUpdate_'.$key};
}

sub HasChanged
{	my ($key,@args)=@_;
	return unless $EventWatchers{$key};
	my @list=@{$EventWatchers{$key}};
	warn "HasChanged $key -> updating @list\n" if $debug;
	for my $r ( @list ) { my $sub=$r->{'WatchUpdate_'.$key}; &$sub($r,@args) if $sub; };
}

sub SetFilter
{	my ($object,$filter,$nb,$group)=@_;
	$nb=1 unless defined $nb;
	$filter=Filter->new($filter) unless defined $filter && ref $filter eq 'Filter';
	$group=$object->{group} unless defined $group;
	$group=get_layout_widget($object)->{group} unless defined $group;
	$Filters_nb{$group}[$nb]=$filter;
	$Filters_nb{$group}[$_]=undef for ($nb+1)..9;
	$Filters{$group}=Filter->newadd(TRUE, map($Filters_nb{$group}[$_],0..9) );
	for my $r ( @{$FilterWatchers{$group}} ) { &{$r->{'UpdateFilter_'.$group}}($r,$Filters{$group},$group,$nb) };
}
sub RefreshFilters
{	my ($object,$group)=@_;
	$group=$object->{group} unless defined $group;
	$group=get_layout_widget($object)->{group} unless defined $group;
	for my $r ( @{$FilterWatchers{$group}} ) { &{$r->{'UpdateFilter_'.$group}}($r,$Filters{$group},$group) };
}
sub GetFilter
{	my ($object,$nb)=@_;
	my $group=$object->{group};
	$group=get_layout_widget($object)->{group} unless defined $group;
	return defined $nb ? $Filters_nb{$group}[$nb] : $Filters{$group};
}
sub GetSonglist
{	my $object=$_[0];
	my $layw=get_layout_widget($object);
	my $group=$object->{group};
	$group=$layw->{group} unless defined $group;
	return $layw->{'songlist'.$group};
}
sub WatchFilter
{	my ($object,$group,$sub)=@_;
	warn "watch filter $group $object\n" if $debug;
	push @{$FilterWatchers{$group}},$object;
	$object->{'UpdateFilter_'.$group}=$sub;
	$object->signal_connect(destroy => \&UnWatchFilter,$group) unless ref $object eq 'HASH' || !$object->isa('Glib::Object');
	IdleDo('1_init_filter'.$group,0,sub {SetFilter($object,undef,0) unless $Filters{$group}; });
}
sub UnWatchFilter
{	my ($object,$group)=@_;
	warn "unwatch filter $group $object\n" if $debug;
	delete $object->{'UpdateFilter'.$group};
	my $ref=$FilterWatchers{$group};
	@$ref=grep $_ ne $object, @$ref;
	unless (@$ref)
	{	delete $_->{$group} for \%Filters,\%Filters_nb,\%FilterWatchers;
	}
}

sub CreateProgressWindow
{	$ProgressWin = Gtk2::Window->new('toplevel');
	#$ProgressWin->set_title(PROGRAM_NAME);
	$ProgressWin->set_border_width(3);

	$ProgressNBSongs=$ProgressNBFolders=0;
	my $lengthcheck_max=0;

	my $check_max=0;
	my $Checklabel=Gtk2::Label->new(_"Checking existing songs ...");
	my $CheckProgress=Gtk2::ProgressBar->new;
	my $Checkstop=NewIconButton('gtk-stop',_"Stop checking",sub { @ToCheck=(); });
	my $CheckVB=Vpack($Checklabel,$CheckProgress,$Checkstop);
	$CheckVB->set_no_show_all(1);

	my $label1=Gtk2::Label->new(_"Scanning ...");
	my $label2=Gtk2::Label->new;
	my $label3=Gtk2::Label->new;
	my $Bstop=NewIconButton('gtk-stop',_"Stop scanning",sub { @ToScan=();undef %FollowedDirs; });
	my $progressbar=Gtk2::ProgressBar->new;
	my $handle=Glib::Timeout->add(500,sub
		{	if (@ToCheck>1)
			{	unless ($check_max)
				{	$CheckVB->set_no_show_all(0);
					$CheckVB->show_all;
				}
				$check_max=@ToCheck if @ToCheck>$check_max;
				my $checked=$check_max-@ToCheck;
				$CheckProgress->set_fraction( $checked/$check_max );
				$CheckProgress->set_text( "$checked / $check_max" );
			}
			elsif ($check_max) { $CheckVB->hide; $check_max=0; $ProgressWin->resize(1,1); }

			my $fraction;
			if (@ToScan || @ToAdd || @LengthEstimated)
			{	$label2->set_label( __("Scanned %d folder, ","Scanned %d folders, ", $ProgressNBFolders)
							.__("%d song added.","%d songs added.", $ProgressNBSongs)  );
			}
			if (@ToScan || @ToAdd)
			{	$label3->set_label( __("%d folder left","%d folders left", scalar@ToScan) );
				#$progressbar->set_text(@ToScan.' folders '.@ToAdd.' songs');
				$fraction=@ToScan + $ProgressNBFolders;
				$fraction=$fraction?	$ProgressNBFolders/$fraction : 1;
				#$progressbar->pulse;
				if ($lengthcheck_max)
				{	$Bstop->show;
					$lengthcheck_max=0;
				}
			}
			elsif (@LengthEstimated)
			{	if (@LengthEstimated > $lengthcheck_max)
				{	$lengthcheck_max=@LengthEstimated;
					$Bstop->hide;
					$label3->set_label( __("Checking length/bitrate of %d mp3 file without VBR header...", "Checking length/bitrate of %d mp3 files without VBR header...", $lengthcheck_max)  );
				}
				$fraction=($lengthcheck_max-@LengthEstimated)/$lengthcheck_max;
			}
			else
			{	$ProgressWin->destroy;
				undef $ProgressWin;
				return 0;
			}
			$progressbar->set_fraction($fraction);
			return 1;
		});
	$ProgressWin->signal_connect (delete_event => sub
		{	Glib::Source->remove($handle);
			$ProgressWin->destroy;
			$ProgressWin=undef;
		});

	my $vbox = Gtk2::VBox->new(FALSE, 2);
	$ProgressWin->add($vbox);
	$vbox->pack_start($_, FALSE, TRUE, 3) for $CheckVB,$label1,$label2,$label3,$progressbar,$Bstop;
	$ProgressWin->show_all;
}

sub PresentWindow
{	my $win=$_[1];
	$win->present;
	$win->set_skip_taskbar_hint(FALSE);
}

sub PopupLayout
{	my ($layout,$widget)=@_;
	return if $widget && Layout::Window::Popup::find_window($widget);
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
	#Watch($eventbox,'SongID', \&UpdateTrayTip);
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
	{ label=> sub {$TogLock && $TogLock==SONG_ARTIST? _"Unlock Artist" : _"Lock Artist"}, code => sub {ToggleLock(SONG_ARTIST);} },
	{ label=> sub {$TogLock && $TogLock==SONG_ALBUM? _"Unlock Album" : _"Lock Album"}, code => sub {ToggleLock(SONG_ALBUM);} },
	{ label=> _"Windows",	code => \&PresentWindow,
		submenu => sub { scalar {map {_( $_->{layout} ),$_} grep exists $_->{layout}, Gtk2::Window->list_toplevels}; }, },
	{ label=> sub { IsWindowVisible($MainWindow) ? _"Hide": _"Show"}, code => \&ShowHide },
	{ label=> _"Fullscreen",	code => \&::ToggleFullscreenLayout,	stockicon => 'gtk-fullscreen' },
	{ label=> _"Settings",		code => \&PrefDialog,	stockicon => 'gtk-preferences' },
	{ label=> _"Quit",		code => \&Quit,		stockicon => 'gtk-quit' },
 );
	my $traytip=Layout::Window::Popup::find_window($TrayIcon->child,$_[0]);
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
	elsif ($x+$dx+$w > $xmax)	{ $x=$xmax-$w; $x=$xmin if $x<$xmin }	# right side
	else				{ $x=$xmin; }				# left side
	if ($ycenter && $y+$h/2 < $ymax && $y-$h/2 >$ymin){ $y-=int($h/2) }	# y center
	elsif ($dy+$y+$h > $ymax)  { $y-=$h; $y=$ymin if $y<$ymin }	# display above the widget
	else			   { $y+=$dy; }				# display below the widget
	return $x,$y;
}

#sub UpdateTrayTip #not used
#{	$Tooltips->set_tip($_[0], __x( _"{song}\nby {artist}\nfrom {album}", song => $Songs[$SongID][SONG_TITLE], artist => $Songs[$SongID][SONG_ARTIST], album => $Songs[$SongID][SONG_ALBUM]) );
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
{	if ( IsWindowVisible($MainWindow) )
	{	#hide
		#warn "hiding\n";
		for my $win ($MainWindow,$BrowserWindow,$ContextWindow)
		{	next unless $win;
			my ($x,$y)=$win->get_position;
			#warn "hiding($x,$y)\n";
			$win->{saved_position}=[$x,$y];
			$win->iconify;
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
		for my $win ($ContextWindow,$BrowserWindow,$MainWindow)
		{	next unless $win;
			my ($x,$y)= $win->{saved_position} ? @{delete $win->{saved_position}} : $win->get_position;
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
			$win->set_skip_taskbar_hint(FALSE);
		}
		$MainWindow->present;
	}
}

package EditSFR;
use Gtk2;
use base 'Gtk2::Dialog';

my %refs;

INIT
{ %refs=
  (	Filter	=> [_"Filter edition",	\%::SavedFilters,	'SavedFilters',	\&::SaveFilter,	_"saved filters",
	  _"name of the new filter",	_"save filter as",	_"delete selected filter"	],
	Sort	=> [_"Sort mode edition",  \%::SavedSorts,		'SavedSorts',	\&::SaveSort,	_"saved sort modes",
	  _"name of the new sort mode",	_"save sort mode as",	_"delete selected sort mode"	],
	WRandom	=> [_"Random mode edition",\%::SavedWRandoms,	'SavedWRandoms',\&::SaveWRandom,_"saved random modes",
	  _"name of the new random mode", _"save random mode as", _"delete selected random mode"],
	STGroupings => [_"SongTree groupings edition",\%SongTree::Groupings,	'SavedSTGroupings',\&::SaveSTGroupings,_"saved groupings",
	  _"name of the new grouping", _"save grouping as", _"delete selected grouping"],
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

	@$self{qw/hash update save/}=@$typedata[1,2,3];
	::Watch($self,$self->{update},\&Fill);

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
		( $typedata->[4],$renderer,'text',0)
		);
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type ('etched-in');
	$sw->set_policy ('automatic', 'automatic');
	my $butrm=::NewIconButton('gtk-remove',_"Remove");
	$treeview->get_selection->signal_connect( changed => sub
		{	my $sel=$_[0]->count_selected_rows;
			$butrm->set_sensitive($sel);
		});
	$butrm->set_sensitive(::FALSE);
	$butrm->signal_connect(clicked => \&Remove_cb,$self);
	my $butsave=::NewIconButton('gtk-save');
	my $NameEntry=Gtk2::Entry->new;
	$NameEntry->signal_connect(changed => sub { $butsave->set_sensitive(length $_[0]->get_text); });
	$butsave->signal_connect(  clicked  => sub {$self->Save});
	$NameEntry->signal_connect(activate => sub {$self->Save});
	$butsave->set_sensitive(0);
	$NameEntry->set_text($name) if defined $name;
	$::Tooltips->set_tip($NameEntry,$typedata->[5] );
	$::Tooltips->set_tip($butsave,	$typedata->[6] );
	$::Tooltips->set_tip($butrm,	$typedata->[7]);

	$self->{entry}=$NameEntry;
	$self->{store}=$store;
	$self->{treeview}=$treeview;
	$self->Fill;
	my $package='Edit'.$type;
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
	&{ $self->{save} }($name,undef,$newname);
	#$self->{busy}=undef;
	#$store->set($iter, 0, $newname);
}

sub Remove_cb
{	my $self=$_[1];
	my $path=($self->{treeview}->get_cursor)[0]||return;
	my $store=$self->{store};
	my $name=$store->get( $store->get_iter($path) ,0);
	&{ $self->{save} }($name,undef);
}

sub Save
{	my $self=shift;
	my $name=$self->{entry}->get_text;
	return unless $name;
	my $result=$self->{editobject}->Result;
	&{ $self->{save} }($name, $result);
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
				&{ $self->{save} }($self->{save_name}, $result) if $ans eq 'ok' && defined $self->{save_name} && $self->{save_name} ne '';
				&$sub($result) if $sub;
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


package EditFilter;
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
	$butadd->{filter}=::SONG_TITLE.'s';
	$butadd2->{filter}="(\x1D".::SONG_TITLE."s\x1D)";

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
			return $f->{string} if $f;
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
		{	my ($treeview,$context,$x,$y,$time)=@_; #warn "drag_motion_cb @_";
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
	$self->Set(::SONG_TITLE.'s') unless $store->get_iter_first;
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
	{	$iter=$store->get_iter($startpath); #warn "set filter $filter at path=".$startpath->to_string;
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
	{	my ($pos,@vals)=FilterBox::filter2posval(::SONG_TITLE.'s');
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

package EditSort;
use Gtk2;
use base 'Gtk2::VBox';
use constant { TRUE  => 1, FALSE => 0, STOCK_SENSITIVE => 'gmb-case_sensitive', STOCK_INSENSITIVE => 'gmb-case_insensitive', };
sub new
{	my ($class,$dialog,$init) = @_;
	$init=undef if $init=~m/^[rs]/;
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
	{	my ($text,$tv,@buts)=@$_;
		my $lab=Gtk2::Label->new;
		$lab->set_markup("<b>$text</b>");
		$tv->set_headers_visible(FALSE);
		$tv->append_column( Gtk2::TreeViewColumn->new_with_attributes($text,Gtk2::CellRendererText->new,'text',1) );
		my $sw = Gtk2::ScrolledWindow->new;
		$sw->set_shadow_type('etched-in');
		$sw->set_policy('never','automatic');
		$sw->set_size_request(-1,200);
		$sw->add($tv);
		my $row=0;
		$table->attach($lab,$col,$col+1,$row++,$row,'fill','shrink',1,1);
		$table->attach($sw,$col,$col+1,$row++,$row,'fill','fill',1,1);
		$table->attach($_,$col,$col+1,$row++,$row,'expand','shrink',1,1) for @buts;
		$col++;
	}
	$treeview2->append_column
		( Gtk2::TreeViewColumn->new_with_attributes
		  ('Case',Gtk2::CellRendererPixbuf->new,'stock-id',3)
		);

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
	for my $n (split ' ',$list)
	{   my $o=($n=~s/^-//)? 'gtk-sort-descending' : 'gtk-sort-ascending';
	    my $i=($n=~s/i$//)? STOCK_INSENSITIVE : STOCK_SENSITIVE;
	    $i='' unless $TagProp[$n][2] eq 's';
	    my $text=($n eq 's')? _"Shuffle" : $TagProp[$n][0];
	    $store2->set($store2->append,0,$n,1,$text,2,$o,3,$i);
	    $self->{nb2}++;
	    $cols{$n}=1;
	}

	my $store1=$self->{store1};
	$store1->clear;
	$store1->set($store1->append,0,'s',1,_"Shuffle");
	for my $n (grep $TagProp[$_][0] && $TagProp[$_][2]=~m/[dnsl]/, 0..$#TagProp)
	{   next if $cols{$n};
	    $store1->set($store1->append,0,$n,1,$TagProp[$n][0]);
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
		$i=($i eq STOCK_SENSITIVE)? STOCK_INSENSITIVE : STOCK_SENSITIVE;
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
	my ($n,$v)=$store1->get_value($iter,0,1);
	$store1->remove($iter);
	my $i=($n=~m/^\d+$/ && $TagProp[$n][2] eq 's')? STOCK_SENSITIVE : '';
	$store2->set($store2->append,0,$n,1,$v,2,'gtk-sort-ascending',3,$i);
	$self->{nb2}++;
	$self->Buttons_update;
}
sub Del_selected
{	my $self=shift;
	my $path=($self->{treeview2}->get_cursor)[0]||return;
	my $store1=$self->{store1};
	my $store2=$self->{store2};
	my $iter=$store2->get_iter($path);
	my ($n,$v)=$store2->get_value($iter,0,1);
	$store2->remove($iter);
	$self->{nb2}--;
	$store1->set($store1->append,0,$n,1,$v);	#FIXME should be inserted in correct order
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
	$store2->swap ($iter,$iter2);
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
	{	my ($n,$o,$i)=$store->get($iter,0,2,3);
		$order.='-' if $o eq 'gtk-sort-descending';
		$order.=$n;
		$order.='i' if $i && $i eq STOCK_INSENSITIVE;
		$order.=' ' if $iter=$store->iter_next($iter);
	}
	return $order;
}

package EditWRandom;
use Gtk2;
use base 'Gtk2::VBox';
use constant
{ TRUE  => 1, FALSE => 0,
  NBCOLS	=> 20,
  COLWIDTH	=> 15,
  HHEIGHT	=> 100,
  HWIDTH	=> 20*15,

  SCORE_FIELDS	=> 0, SCORE_DESCR	=> 1, SCORE_UNIT	=> 2,
  SCORE_ROUND	=> 3, SCORE_DEFAULT	=> 4, SCORE_VALUE	=> 5,
};
sub new
{	my ($class,$dialog,$init) = @_;
	my $self = bless Gtk2::VBox->new, $class;

	my $table=Gtk2::Table->new (1, 4, FALSE);
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_policy('never','automatic');
	$sw->add_with_viewport($table);
	$self->add($sw);

	my $addlist=TextCombo->new({map {$_ => $Random::ScoreTypes{$_}[SCORE_DESCR]} keys %Random::ScoreTypes}, (keys %Random::ScoreTypes)[0] );
	my $addbut=::NewIconButton('gtk-add',_"Add");
	my $addhbox=Gtk2::HBox->new(FALSE, 8);
	$addhbox->pack_start($_,FALSE,FALSE,0) for Gtk2::Label->new(_"Add rule : "), $addlist, $addbut;

	my $histogram=Gtk2::Image->new;
	my $eventbox=Gtk2::EventBox->new;
	my $histoframe=Gtk2::Frame->new;
	my $histoAl=Gtk2::Alignment->new(.5,.5,0,0);
	$eventbox->add($histogram);
	$histoframe->add($eventbox);
	$histoAl->add($histoframe);

	my $LabEx=$self->{example_label}=Gtk2::Label->new;
	$self->pack_start($_,FALSE,FALSE,2) for $addhbox,$histoAl,$LabEx;

	$::Tooltips->set_tip($eventbox,'');
	$eventbox->signal_connect(enter_notify_event => sub
		{	$_[0]{timeout}=Glib::Timeout->add(500,\&UpdateTip_timeout,$histogram);0;
		});
	$eventbox->signal_connect(leave_notify_event => sub { Glib::Source->remove( $_[0]{timeout} );0; });

	$addbut->signal_connect( clicked => sub
		{	my $type=$addlist->get_value;
			$self->AddRow( $Random::ScoreTypes{$type}[SCORE_DEFAULT] );
		});
	::Watch($self,'SongID',\&UpdateID);
	::Watch($self,'Filter',\&UpdateFilter);
	$self->{watcher}=::AddWatcher();
	$self->signal_connect( destroy => \&RemoveWatchers );

	$histogram->{eventbox}=$eventbox;
	$self->{histogram}=$histogram;
	$self->{table}=$table;
	$self->Set($init);

	return $self;
}

sub RemoveWatchers
{	my $self=shift;
	return unless defined $self->{watcher};
	delete $ToDo{'2_WRandom'.$self};
	::RemoveWatcher($self->{watcher});
	$self->{watcher}=undef;
}

sub Set
{	my ($self,$sort)=@_;
	$sort=~s/^r//;
	my $table=$self->{table};
	$table->remove($_) for $table->get_children;
	$self->{frames}=[];
	$self->{row}=0;
	return unless $sort;
	$self->AddRow($_) for split /\x1D/,$sort;
}

sub Redraw
{	my $self=shift;
	my $histogram=$self->{histogram};
	$histogram->{col}=undef;
	my $r=Random->new( $self->get_string );
	my ($tab)=($histogram->{tab},$self->{sum})=$r->MakeTab(NBCOLS);
	my $pixmap=Gtk2::Gdk::Pixmap->new ($histogram->window,HWIDTH,HHEIGHT,-1);
	$pixmap->draw_rectangle ($histogram->style->bg_gc($histogram->state),TRUE,0,0,HWIDTH,HHEIGHT);
	my $max=(sort { $b <=> $a } @$tab)[0] ||10;
	my $gc = $histogram->style->fg_gc($histogram->state);
	for my $x (0..NBCOLS-1)
	{	my $y=int(HHEIGHT*( $$tab[$x]||0 )/$max);
		warn "$x : $y\n" if $debug;
		$pixmap->draw_rectangle($gc,TRUE,COLWIDTH*$x,HHEIGHT-$y,COLWIDTH,$y);
	}
	$histogram->set_from_pixmap ($pixmap,undef);
	$histogram->show_all;

	my $sub=sub { ::IdleDo('2_WRandom'.$self,500,\&Redraw, $self); };
	::ChangeWatcher( $self->{watcher}, undef, $r->fields, $sub, $sub, $sub, $PlayFilter, $sub);
	$self->UpdateID; #update examples

	0;
}

sub UpdateTip_timeout
{	my $histogram=shift;
	my ($x,$y)=$histogram->get_pointer;#warn "$x,$y\n";
	return 0 if $x<0;
	my $col=int($x/COLWIDTH);
	return 1 if $histogram->{col} && $histogram->{col}==$col;
	$histogram->{col}=$col;
	my $nb=$histogram->{tab}[$col]||0;
	my $range=sprintf '%.2f - %.2f',$col/NBCOLS,($col+1)/NBCOLS;
	#my $sum=$histogram->get_ancestor('Gtk2::VBox')->{sum};
	#my $prob='between '.join ' and ',map $_? '1 chance in '.sprintf('%.0f',$sum/$_) : 'no chance', $col/NBCOLS,($col+1)/NBCOLS;
	$::Tooltips->set_tip($histogram->{eventbox}, "$range : ".::__('%d song','%d songs',$nb) );
	1;
}

sub AddRow
{	my ($self,$params)=@_;
	my $table=$self->{table};
	my $row=$self->{row}++;
	my $deleted;
	my ($inverse,$weight,$type,$extra)=$params=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)$/;
	return unless $type;
	my $frame=Gtk2::Frame->new( $Random::ScoreTypes{$type}[SCORE_DESCR] );
	$frame->{type}=$type;
	push @{$self->{frames}},$frame;
	$frame->{params}=$params;
	my $exlabel=$frame->{label}=Gtk2::Label->new;
	$frame->{unit}=$Random::ScoreTypes{$type}[SCORE_UNIT];
	$frame->{round}=$Random::ScoreTypes{$type}[SCORE_ROUND];
	my $button=::NewIconButton('gtk-remove',undef,sub
		{ my $button=$_[0];
		  my $self=::find_ancestor($button,__PACKAGE__);
		  $frame->{params}=undef;
		  $_->parent->remove($_) for $button,$frame;
		  ::IdleDo('2_WRandom'.$self,500,\&Redraw, $self);
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
		my $labellist=TextCombo->new([sort keys %Labels],$extra,\&update_frame_cb);
		$extrasub=sub { $labellist->get_value; };
		#$extrasub=sub {'Bootleg' };
		$hbox->pack_start($labellist, FALSE, FALSE, 1);
	}
	elsif ($type eq 'g')
	{	$check_tip=_"ON less probable if genre is set\nOFF more probable if genre is set";
		my $genrelist=TextCombo->new( ::GetGenresList ,$extra,\&update_frame_cb);
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
			Gtk2::Label->new($frame->{unit});
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
	my $extra=&{$frame->{extrasub}};
	$frame->{params}=($inverse? '-' : '').$weight.$frame->{type}.$extra;
	::setlocale(::LC_NUMERIC, '');
	_frame_example($frame);
	my $self=::find_ancestor($frame,__PACKAGE__);
	::IdleDo('2_WRandom'.$self,500, \&Redraw, $self);
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
	my $r=Random->new( $self->get_string );
	return unless defined $::SongID;
	my $s= $r->CalcScore($::SongID) || 0;
	my $v=sprintf '%.3f', $s;
	my $prob;
	if ($s)
	{ $prob=$self->{sum}/$s;
	  $prob= ::__x( _"1 chance in {probability}", probability => sprintf($prob>=10? '%.0f' : '%.1f', $prob) );
	}
	else {$prob=_"0 chance"}
	$self->{example_label}->set_markup( '<small><i>'.::__x( _"example (selected song) : {score}  ({chances})", score =>$v, chances => $prob). "</i></small>" );
}

sub UpdateFilter
{	my $self=shift;
	::IdleDo('2_WRandom'.$self,500,\&Redraw, $self);
}

sub get_string
{	join "\x1D",grep defined,map $_->{params}, @{$_[0]{frames}};
}

sub Result
{	my $self=shift;
	my $sort='r'.$self->get_string;
	$sort=undef if $sort eq 'r';
	return $sort;
}

package Stars;
use Gtk2;
use base 'Gtk2::EventBox';

my (@pixbufs,$width);
use constant NBSTARS => 5;

INIT
{	@pixbufs=map Gtk2::Gdk::Pixbuf->new_from_file(::PIXPATH.'stars'.$_.'.png'), 0..NBSTARS;
	$width=$pixbufs[0]->get_width/NBSTARS;
}

sub new
{	my ($class,$nb,$sub) = @_;
	my $self = bless Gtk2::EventBox->new, $class;
	$self->{callback}=$sub;
	my $image=$self->{image}=Gtk2::Image->new;
	$self->add($image);
	$self->set($nb);
	$self->signal_connect(button_press_event => \&click);
	return $self;
}

sub callback
{	my ($self,$value)=@_;
	if (my $sub=$self->{callback}) {&$sub($self,$value);}
	else {$self->set($value)}
}
sub set
{	my ($self,$nb)=@_;
	$self->{nb}=$nb;
	$nb=$Options{DefaultRating} if !defined $nb || $nb eq '';
	$::Tooltips->set_tip($self,_("song rating")." : $nb %");
	$self->{image}->set_from_pixbuf( get_pixbuf($nb) );
}
sub get { shift->{nb}; }

sub click
{	my ($self,$event)=@_;
	goto \&popup if $event->button == 3;
	my ($x)=$event->coords;
	my $nb=1+int($x/$width);
	$nb*=100/NBSTARS;
	$self->callback($nb);
	return 1;
}

sub popup
{	(my $self,$::LEvent)=@_;
	my $menu=Gtk2::Menu->new;
	my $set=$self->{nb}; $set='' unless defined $set;
	my $sub=sub { $self->callback($_[1]); };
	for my $nb (0,10,20,30,40,50,60,70,80,90,100,'')
	{	my $item=Gtk2::CheckMenuItem->new( ($nb eq '' ? _"default" : $nb) );
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $set eq $nb;
		$item->signal_connect(activate => $sub, $nb);
		$menu->append($item);
	}
	$menu->show_all;
	$menu->popup(undef, undef, \&::menupos, undef, $::LEvent->button, $::LEvent->time);
}

sub createmenu
{	my $IDs=$_[0]{IDs};
	my %set;
	no warnings 'uninitialized';
	$set{$::Songs[$_][::SONG_RATING]}++ for @$IDs;
	my $set= (keys %set ==1) ? each %set : 'undef';
	my $cb=sub	{	$::Songs[$_][::SONG_RATING]=$_[1] for @$IDs;
				::SongsChanged(::SONG_RATING,$IDs);
			};
	my $menu=Gtk2::Menu->new;
	for my $nb ('',0..NBSTARS)
	{	my $item=Gtk2::CheckMenuItem->new;
		my ($child,$rating)= $nb eq ''	? (Gtk2::Label->new(_"default"),'')
						: (Gtk2::Image->new_from_pixbuf($pixbufs[$nb]),$nb*100/NBSTARS);
		$item->add($child);
		$item->set_draw_as_radio(1);
		$item->set_active(1) if $set eq $rating;
		$item->signal_connect(activate => $cb, $rating);
		$menu->append($item);
	}
	return $menu;
}

sub get_pixbuf
{	my ($r,$def)=($_[0],$_[1]);
	if (!defined $r || $r eq '')
	{	return undef unless $def;
		$r=$::Options{DefaultRating};
	}
	$r=sprintf '%d',$r*NBSTARS/100;
	return $pixbufs[$r];
}

package FilterBox;
use Gtk2;
use base 'Gtk2::HBox';
use strict;
use warnings;

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
	[	_"contains %s",		::SONG_TITLE.'s%s',
		_"doesn't contain %s",	'-'.::SONG_TITLE.'s%s',
		_"is %s",		::SONG_TITLE.'~%s',
		_"is not %s",		'-'.::SONG_TITLE.'~%s',
		_"match regexp %r",	::SONG_TITLE.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_TITLE.'m%r',
	],
	_"Artist",
	[	_"contains %s",		::SONG_ARTIST.'s%s',
		_"doesn't contain %s",	'-'.::SONG_ARTIST.'s%s',
		_"is %s",		::SONG_ARTIST.'~%s',
		_"is not %s",		'-'.::SONG_ARTIST.'~%s',
		_"match regexp %r",	::SONG_ARTIST.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_ARTIST.'m%r',
	],
	_"Album",
	[	_"contains %s",		::SONG_ALBUM.'s%s',
		_"doesn't contain %s",	'-'.::SONG_ALBUM.'s%s',
		_"is %s",		::SONG_ALBUM.'e%s',
		_"is not %s",		'-'.::SONG_ALBUM.'e%s',
		_"match regexp %r",	::SONG_ALBUM.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_ALBUM.'m%r',
	],
	_"Year",
	[	_"is %n",	::SONG_DATE.'e%n',
		_"isn't %n",	'-'.::SONG_DATE.'e%n',
		_"is before %n",::SONG_DATE.'<%n',
		_"is after %n",	::SONG_DATE.'>%n',
	],
	_"Track",
	[	_"is %n",		::SONG_TRACK.'e%n',
		_"is not %n",		'-'.::SONG_TRACK.'e%n',
		_"is more than %n",	::SONG_TRACK.'>%n',
		_"is less than %n",	::SONG_TRACK.'<%n',
	],
	_"Disc",
	[	_"is %n",		::SONG_DISC.'e%n',
		_"is not %n",		'-'.::SONG_DISC.'e%n',
		_"is more than %n",	::SONG_DISC.'>%n',
		_"is less than %n",	::SONG_DISC.'<%n',
	],
	_"Rating",
	[	_"is %n( %)",		::SONG_RATING.'e%n',
		_"is not %n( %)",	'-'.::SONG_RATING.'e%n',
		_"is more than %n( %)",	::SONG_RATING.'>%n',
		_"is less than %n( %)",	::SONG_RATING.'<%n',
		_"is between %n( and )%n( %)",::SONG_RATING.'b%n %n',
	],
	_"Length",
	[	_"is more than %n( s)",		::SONG_LENGTH.'>%n',
		_"is less than %n( s)",		::SONG_LENGTH.'<%n',
		_"is between %n( and )%n( s)",	::SONG_LENGTH.'b%n %n',
	],
	_"Size",
	[	_"is more than %b",		::SONG_SIZE.'>%b',
		_"is less than %b",		::SONG_SIZE.'<%b',
		_"is between %b( and )%b",	::SONG_SIZE.'b%b %b',
	],
	_"played",
	[	_"more than %n( times)",	::SONG_NBPLAY.'>%n',
		_"less than %n( times)",	::SONG_NBPLAY.'<%n',
		_"exactly %n( times)",		::SONG_NBPLAY.'e%n',
		_"exactly not %n( times)",	'-'.::SONG_NBPLAY.'e%n',
		_"between %n( and )%n",		::SONG_NBPLAY.'b%n %n',
	],
	_"skipped",
	[	_"more than %n( times)",	::SONG_NBSKIP.'>%n',
		_"less than %n( times)",	::SONG_NBSKIP.'<%n',
		_"exactly %n( times)",		::SONG_NBSKIP.'e%n',
		_"exactly not %n( times)",	'-'.::SONG_NBSKIP.'e%n',
		_"between %n( and )%n",		::SONG_NBSKIP.'b%n %n',
	],
	_"last played",
	[	_"less than %a( ago)",	::SONG_LASTPLAY.'>%a',
		_"more than %a( ago)",	::SONG_LASTPLAY.'<%a',
		_"before %d",		::SONG_LASTPLAY.'<%d',
		_"after %d",		::SONG_LASTPLAY.'>%d',
		_"between %d( and )%d",	::SONG_LASTPLAY.'b%d %d',
		#_"on %d",		::SONG_LASTPLAY.'o%d',
	],
	_"last skipped",
	[	_"less than %a( ago)",	::SONG_LASTSKIP.'>%a',
		_"more than %a( ago)",	::SONG_LASTSKIP.'<%a',
		_"before %d",		::SONG_LASTSKIP.'<%d',
		_"after %d",		::SONG_LASTSKIP.'>%d',
		_"between %d( and )%d",	::SONG_LASTSKIP.'b%d %d',
		#_"on %d",		::SONG_LASTSKIP.'o%d',
	],
	_"modified",
	[	_"less than %a( ago)",	::SONG_MODIF.'>%a',
		_"more than %a( ago)",	::SONG_MODIF.'<%a',
		_"before %d",		::SONG_MODIF.'<%d',
		_"after %d",		::SONG_MODIF.'>%d',
		_"between %d( and )%d",	::SONG_MODIF.'b%d %d',
		#_"on %d",		::SONG_MODIF.'o%d',
	],
	_"added",
	[	_"less than %a( ago)",	::SONG_ADDED.'>%a',
		_"more than %a( ago)",	::SONG_ADDED.'<%a',
		_"before %d",		::SONG_ADDED.'<%d',
		_"after %d",		::SONG_ADDED.'>%d',
		_"between %d( and )%d",	::SONG_ADDED.'b%d %d',
		#_"on %d",		::SONG_ADDED.'o%d',
	],
	_"The [most/less]",
	[	_"%n most played",	::SONG_NBPLAY.'h%n',
		_"%n less played",	::SONG_NBPLAY.'t%n',
		_"%n last played",	::SONG_LASTPLAY.'h%n',
		_"%n not played for the longest time",	::SONG_LASTPLAY.'t%n', #FIXME description
		_"%n most skipped",	::SONG_NBSKIP.'h%n',
		_"%n less skipped",	::SONG_NBSKIP.'t%n',
		_"%n last skipped",	::SONG_LASTSKIP.'h%n',
		_"%n not skipped for the longest time",	::SONG_LASTSKIP.'t%n',
		_"%n longest",		::SONG_LENGTH.'h%n',
		_"%n shortest",		::SONG_LENGTH.'t%n',
		_"%n last added",	::SONG_ADDED.'h%n',
		_"%n first added",	::SONG_ADDED.'t%n',
		_"All but the [most/less]%n",
		[	_"most played",		'-'.::SONG_NBPLAY.'h%n',
			_"less played",		'-'.::SONG_NBPLAY.'t%n',
			_"last played",		'-'.::SONG_LASTPLAY.'h%n',
			_"not played for the longest time",	'-'.::SONG_LASTPLAY.'t%n',
			_"most skipped",	'-'.::SONG_NBSKIP.'h%n',
			_"less skipped",	'-'.::SONG_NBSKIP.'t%n',
			_"last skipped",	'-'.::SONG_LASTSKIP.'h%n',
			_"not skipped for the longest time",	'-'.::SONG_LASTSKIP.'t%n',
			_"longest",		'-'.::SONG_LENGTH.'h%n',
			_"shortest",		'-'.::SONG_LENGTH.'t%n',
			_"last added",		'-'.::SONG_ADDED.'h%n',
			_"first added",		'-'.::SONG_ADDED.'t%n',
		],
	],
	_"Genre",
	[	_"is %g",		::SONG_GENRE.'f%s',
		_"isn't %g",		'-'.::SONG_GENRE.'f%s',
		_"contains %s",		::SONG_GENRE.'s%s',
		_"doesn't contain %s",	'-'.::SONG_GENRE.'s%s',
		_"(: )none",		::SONG_GENRE.'e',
		_"(: )has one",		'-'.::SONG_GENRE.'e',
	],
	_"Label",
	[	_"%f is set",		::SONG_LABELS.'f%s',
		_"%f isn't set",	'-'.::SONG_LABELS.'f%s',
		_"contains %s",		::SONG_LABELS.'s%s',
		_"doesn't contain %s",	'-'.::SONG_LABELS.'s%s',
		_"(: )none",		::SONG_LABELS.'e',
		_"(: )has one",		'-'.::SONG_LABELS.'e',
	],
	_"Filename",
	[	_"contains %s",		::SONG_UFILE.'s%s',
		_"doesn't contain %s",	'-'.::SONG_UFILE.'s%s',
		_"is %s",		::SONG_UFILE.'e%s',
		_"is not %s",		'-'.::SONG_UFILE.'e%s',
		_"match regexp %r",	::SONG_UFILE.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_UFILE.'m%r',
	],
	_"Folder",
	[	_"contains %s",		::SONG_UPATH.'s%s',
		_"doesn't contain %s",	'-'.::SONG_UPATH.'s%s',
		_"is %s",		::SONG_UPATH.'e%s',
		_"is not %s",		'-'.::SONG_UPATH.'e%s',
		_"is in %s",		::SONG_UPATH.'i%s',
		_"is not in %s",	'-'.::SONG_UPATH.'i%s',
		_"match regexp %r",	::SONG_UPATH.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_UPATH.'m%r',
	],
	_"Comment",
	[	_"contains %s",		::SONG_COMMENT.'s%s',
		_"doesn't contain %s",	'-'.::SONG_COMMENT.'s%s',
		_"is %s",		::SONG_COMMENT.'e%s',
		_"is not %s",		'-'.::SONG_COMMENT.'e%s',
		_"match regexp %r",	::SONG_COMMENT.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_COMMENT.'m%r',
	],
	_"Version",
	[	_"contains %s",		::SONG_VERSION.'s%s',
		_"doesn't contain %s",	'-'.::SONG_VERSION.'s%s',
		_"is %s",		::SONG_VERSION.'e%s',
		_"is not %s",		'-'.::SONG_VERSION.'e%s',
		_"match regexp %r",	::SONG_VERSION.'m%r',
		_"doesn't match regexp %r",'-'.::SONG_VERSION.'m%r',
	],
	_"is in list %l",	'l%l',
	_"is not in list %l",	'-l%l',
	_"file format",
	[	_"is",
		[	_"a mp3 file",	::SONG_FORMAT.'m^mp3',
			_"an ogg file",	::SONG_FORMAT.'m^ogg',
			_"a flac file",	::SONG_FORMAT.'m^flac',
			_"a musepack file",::SONG_FORMAT.'m^mpc',
			_"a wavepack file",::SONG_FORMAT.'m^wv',
			_"an ape file",	::SONG_FORMAT.'m^ape',
			_"mono",	::SONG_CHANNELS.'e1',
			_"stereo",	::SONG_CHANNELS.'e2',
		],
		_"is not",
		[	_"a mp3 file",	'-'.::SONG_FORMAT.'m^mp3',
			_"an ogg file",	'-'.::SONG_FORMAT.'m^ogg',
			_"a flac file",	'-'.::SONG_FORMAT.'m^flac',
			_"a musepack file",'-'.::SONG_FORMAT.'m^mpc',
			_"a wavepack file",'-'.::SONG_FORMAT.'m^wv',
			_"an ape file",	'-'.::SONG_FORMAT.'m^ape',
			_"mono",	'-'.::SONG_CHANNELS.'e1',
			_"stereo",	'-'.::SONG_CHANNELS.'e2',
		],
		_"bitrate",
		[	_"is %n(kbps)",		::SONG_BITRATE.'e%n',
			_"isn't %n(kbps)",	'-'.::SONG_BITRATE.'e%n',
			_"is more than %n(kbps)",::SONG_BITRATE.'>%n',
			_"is less than %n(kbps)",::SONG_BITRATE.'<%n',
		],
		_"sampling rate",
		[	_"is %n(Hz)",		::SONG_SAMPRATE.'e%n',
			_"isn't %n(Hz)",	'-'.::SONG_SAMPRATE.'e%n',
			_"is more than %n(Hz)",	::SONG_SAMPRATE.'>%n',
			_"is less than %n(Hz)",	::SONG_SAMPRATE.'<%n',
			_"is not 44.1kHz",	'-'.::SONG_SAMPRATE.'e44100',
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
		my ($colcmd,$val)=$f=~m/^(-?\d*[A-Za-z<>!~])(.*)$/;
		$val=~s/(\W)/\\$1/g;
		$val=~s/\\%([a-z])/'('.$TYPEREGEX{$1}.')'/ge;
		push @{ $PosRe{$colcmd} }, [qr/^$val$/, $pos.$i.' '];
	  }
	}
  }
}

sub new
{	my ($class,$activatesub,$changesub,$pos,@vals)=@_;
	my $self = bless Gtk2::HBox->new, $class;

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
	my ($colcmd,$val)=$f=~m/^(-?\d*[A-Za-z<>!~])(.*)$/;
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
	&{ $self->{changesub} } ( $self->Get );
}
sub activate
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	return unless $self->{activatesub};
	&{ $self->{activatesub} } ( $self->Get );
}


package FilterEntryString;
use strict;
use warnings;
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
			&{$self->{changesub}}($self) if $self->{changesub};
			&{$self->{activatesub}}($self) if $self->{activatesub};
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

package FilterEntryCombo;
use Gtk2;
use base 'Gtk2::OptionMenu';

my %getlist;
INIT
{%getlist=
 (	l => sub {[keys %SavedLists]},
	g => \&::GetGenresList,
	f => sub {[keys %Labels]},
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
	my $list=&{$getlist{$type}};
	for my $f (sort @$list)
	{	$hash{$f}=$n;
		my $item=Gtk2::MenuItem->new;
		$item->add(Gtk2::Label->new($f));
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

package Filter;

my %GrepSubs;
my %NGrepSubs;

my $CachedString; our $CachedList;

INIT
{
  %GrepSubs=
  ( m => sub	#regex
	{ my ($n,$pat,$inv)=@_;
	  $pat=~s#"#\\"#g;
	  $pat=~s#^((?:.*[^\\])?(?:\\\\)*\\)$#$1\\#g; #escape trailing '\' in impair number
	  $inv=$inv ? '!' : '=';
	  return '$::Songs[$_]'."[$n]$inv~m\"$pat\"";
	},
    i => sub	#is in folder or sub-folders
	{ my ($n,$pat,$inv)=@_;
	  $inv=$inv ? '!' : '=';
	  return '$::Songs[$_]'."[$n]$inv~m/^\Q$pat\E".'(?:\\'.::SLASH.'|$)/';
	},
#  w => sub	# word
#	{ my ($n,$pat)=@_;
#	  $pat=quotemeta $pat;
#	  return '$::Songs[$_]['.$n.']=~m/\b'.$pat.'\b/';
#	},
  f => sub	# label is set
	{ my ($n,$pat,$inv)=@_;
	  $pat=quotemeta $pat;
	  $inv=$inv ? '!' : '=';
	  return '$::Songs[$_]['.$n.']'.$inv.'~m/(?:^|\x00)'.$pat.'(?:$|\x00)/';
	},
  s => sub	# substring
	{ my ($n,$pat,$inv)=@_;
	  $pat=lc quotemeta$pat;
	  $inv=$inv ? '=' : '!';
	  return "index (lc\$::Songs[\$_][$n],\"$pat\")$inv=-1";
	},
  e => sub	# equal
	{ my ($n,$pat,$inv)=@_; $pat=quotemeta $pat;
	  $inv=$inv ? 'ne' : 'eq';
	  return '$::Songs[$_]['.$n."] $inv \"$pat\"";
	},
  '~' => sub	    #smart equal
	{ my ($n,$pat,$inv)=@_;
	  $pat=quotemeta $pat;
	  $inv=$inv ? '!' : '=';
	  if ($n==::SONG_TITLE)
	  { #$pat=~s/[eéèê]/[eéèê]/g;	#FIXME, probably too slow anyway
	    #$pat=~s/[aà]/[aà]/g;
	    #$pat=~s/[oöô]/[oöô]/g;
	    $pat=~s#\\'# ?. ?#g;		#for 's == is ...
	    $pat=~s#\Bing\b#in[g']#g;
	    $pat=~s#\\ is\b#(?:'s|\\ is)#ig;
	    $pat=~s#\\ (?:and|\\&|et)\\ #\\ (?:and|\\&|et)\\ #ig;
	    $pat=~s#\\[-,.]#.?#g;
	    $pat=~s# ?\\\?# ?\\?#g;
	    return '' if $pat eq '';
	    $pat='m#(?:^|/) *'.$pat.' *(?:[/\(\[]|$)#i';
	  }
	  elsif ($n==::SONG_ARTIST)
	  {	$pat='m/(?:^|$::re_artist)'.$pat.'(?:$::re_artist|$)/o';
	  }
	  else { $pat='m/^'.$pat.'$/i'; }	#FIXME use index() ?
	  return '$::Songs[$_]['.$n.']'.$inv.'~'.$pat;
	},
  '<' => sub
	{ my ($n,$pat,$inv)=@_;
	  $inv=$inv ? '>=' : '<';
	  if ($TagProp[$n][2] eq 'd') { $pat=::ConvertTime($pat); }
	  elsif ($n==::SONG_SIZE && $pat=~m/^(\d+)([bkm])$/) { $pat=$1*$::SIZEUNITS{$2}[0] }
	  return '$::Songs[$_]['.$n.'] '.$inv.' '.$pat;
	},
  '>' => sub
	{ my ($n,$pat,$inv)=@_;
	  $inv=$inv ? '<=' : '>';
	  if ($TagProp[$n][2] eq 'd') { $pat=::ConvertTime($pat); }
	  elsif ($n==::SONG_SIZE && $pat=~m/^(\d+)([bkm])$/) { $pat=$1*$::SIZEUNITS{$2}[0] }
	  return '$::Songs[$_]['.$n.'] '.$inv.' '.$pat;
	},
  b => sub
	{ my ($n,$pat,$inv)=@_;
	  my $inv1=$inv ? '<' : '>=';
	  my $inv2=$inv ? '>' : '<=';
	  my $inv3=$inv ? '||' : '&&';
	  if ($TagProp[$n][2] eq 'd') { $pat=::ConvertTime($pat); }
	  elsif ($n==::SONG_SIZE && $pat=~m/^(\d+)([bkm]) (\d+)([bkm])$/) { $pat=$1*$::SIZEUNITS{$2}[0].' '.$3*$::SIZEUNITS{$4}[0] }
	  my ($start,$end)= $pat=~m/(\d+)\D+(\d+)/;
	  return '$::Songs[$_]['.$n.'] '.$inv1.' '.$start.' '.$inv3.' $::Songs[$_]['.$n.'] '.$inv2.' '.$end;
	},
  c => sub {$_[1]}, #used for optimizations
  );
  %NGrepSubs=
  (	t => sub
	     {	my ($n,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref;::SortList(\$tmp,$n);$assign @\$tmp[$inv];";
	     },
	h => sub
	     {	my ($n,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? "$pat..(($pat>@\$tmp)? 0 : \$#\$tmp)"
			  :    "0..(($pat>@\$tmp)? \$#\$tmp : ".($pat-1).')';
		return "\$tmp=$lref;::SortList(\$tmp,-$n);$assign @\$tmp[$inv];";
	     },
	a => sub #should probably use 'e' for albums and '~' for artists
	     {	my ($n,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? '!' : '';
		my $r;
		if    ($n==::SONG_ARTIST){ $r='$::Artist'; }
		elsif ($n==::SONG_ALBUM) { $r='$::Album'; }
		$pat=~s#'#\\'#g;
		return '$tmp={}; $$tmp{$_}=undef for @{'.$r."{\"\Q$pat\E\"}[".::AALIST.']};'
			.$assign.'grep '.$inv.'exists $$tmp{$_},@{'.$lref.'};';
	     },
	l => sub	#is in a saved lists
	     {	my ($n,$pat,$lref,$assign,$inv)=@_;
		$inv=$inv ? '!' : '';
		return '$tmp={}; $$tmp{$_}=undef for @{$::SavedLists{"'."\Q$pat\E".'"}};'
			.$assign.'grep '.$inv.'exists $$tmp{$_},@{'.$lref.'};';
	     },
  );
}

#Filter object contains :
# - string :	string notation of the filter
# - sub    :	ref to a sub which takes a ref to an array of IDs as argument and returns a ref to the filtered array
# - greponly :	set to 1 if the sub dosn't need to filter the whole list each times -> ID can be tested individualy
# - fields :	ref to a list of the columns used by the filter

sub new
{	my ($class,$string,$source) = @_;
	my $self=bless {}, $class;
	if	(!defined $string)	  {$string='';}
	elsif	($string=~m/^-?[0-9]+~/) { ($string)=_smart_simplify($string); }
	$self->{string}=$string;
	$self->{source}=$source;
	return $self;
}

sub newadd
{	my ($class,$and,@filters)=@_;
	my $self=bless {}, $class;
	my %sel;

	my ($ao,$re)=$and? ( '&', qr/^\(\&\x1D(.*)\)\x1D$/)
			 : ( '|', qr/^\(\|\x1D(.*)\)\x1D$/);
	my @strings;
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
		{	push @strings,( ($string=~m/^-?[0-9]+~/)
					? _smart_simplify($string,!$and)
					: $string
				      );
		}
	}
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
	return $self;
}

sub are_equal #FIXME could try harder
{	my ($f1,$f2)=($_[0],$_[1]);
	($f1,my$s1)=defined $f1 ? ref $f1 ? ($f1->{string},$f1->{source}) : $f1 : '';
	($f2,my$s2)=defined $f2 ? ref $f2 ? ($f2->{string},$f2->{source}) : $f2 : '';
	return ($f1 eq $f2) && ((!$s1 && !$s2) || $s1 eq $s2);
}

sub _smart_simplify
{	(local $_,my $returnlist)=($_[0],$_[1]);
	return $_ unless s/^(-)?([0-9]+)~//;
	my $inv=$1||''; my $col=$2;
	my @pats;
	if ($col==::SONG_TITLE)	# for medleys (songs separated by '/')
	{   s#(?<=.) *[\(\[].*##;	#remove '(...' unless '(' is at the begining of the string
	    @pats=grep m/\S/, split / *\/+ */,$_;
	}
	elsif ($col==::SONG_ARTIST) # for multiple artists (separated by '&' or ',')
	{   @pats=split /$::re_artist/o,$_;
	}
	else {@pats=($_)}
	if ($returnlist || @pats==1)
	{	return map $inv.$col.'~'.$_ , @pats;
	}
	else
	{	return "(|\x1D".join('',map($inv.$col.'~'.$_."\x1D", @pats)).")\x1D";
	}
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
}

sub filter
{	my $self=shift;
	#my $time=times;								#DEBUG
	my $sub=$self->{'sub'} || $self->makesub;
	my $listref= $self->{source} || \@Library;
	if ($CachedList && $CachedString eq $self->{string} && !$self->{source}) {return $CachedList} #else {warn "not cached : ".$self->{string}."\n"}
	my $r=&$sub($listref);
	#$time=times-$time; warn "filter $time s ( ".$self->{string}." )\n" if $debug;	#DEBUG
	if ($listref == \@Library) { $CachedString=$self->{string}; $CachedList=$r }
	return $r;
}

sub info
{	my $self=shift;
	$self->makesub unless $self->{'sub'};
	return $self->{greponly},@{ $self->{fields} };
}

sub makesub
{	my $self=shift;
	my $filter=$self->{string};
	warn "makesub filter=$filter\n" if $::debug;
	$self->{fields}=[];
	if ($filter eq '') { return $self->{'sub'}=sub {$_[0]}; }
	#$filter="(\x1D$filter)\x1D" if $filter=~m/^[|&]/;
	my @filter=split /\x1D/,$filter;
	#warn "$_\n" for @filter;

	###########	# optimization for some special cases
	my @hashes;
	if (@filter>4)
	{ my $d=0; my (@or,@val,@ilist);
	    for my $i (0..$#filter)
	    {	local $_=$filter[$i];
		if    (m/^\(/)	  { $d++; $or[$d]=($_ eq '(|')? 1 : 0; }
		elsif ($_ eq ')')
		{	my $vd=delete $val[$d];
			my $ilist=delete $ilist[$d];
			while (my ($icc,$h)=each %$vd)
			{	next unless (keys %$h)>2;
				my ($inv,$col,$cmd)=$icc=~m/^(-?)(\d+)([ef~])$/;
				next if $cmd eq '~' && $col!=::SONG_ARTIST;
				my $l=$ilist->{$icc};
				my $first=$l->[0]; my $last=$l->[-1];
				if ( $last-$first==$#$l
					&& $filter[$first-1] && $filter[$first-1]=~m/^\(/
					&& $filter[$last+1] eq ')'
				   )
				 {push @$l,$first-1,$last+1}
				$filter[$_]=undef for @$l;
				push @hashes,$h;
				my $code;
				if ($cmd eq 'e')
				{ $code=($inv ? '!':'').'exists $hashes['.$#hashes.']{$Songs[$_]['.$col.']}'; }
				elsif ($cmd eq 'f' || $cmd eq '~')
				{ my $sep=($cmd eq '~')? '$::re_artist' : '\x00';
				  $code='do { my $r;exists($hashes['.$#hashes.']{$_}) and $r=1 and last for split /'.$sep.'/,$Songs[$_]['.$col.'];'.$inv.'$r;}';
				}
				$filter[$first]=$col.'c'.$code;
			}
			$d--;
		}
		elsif (($or[$d] && m/^(\d+[ef~])(.*)$/) || (!$or[$d]&& m/^(-\d+[ef~])(.*)$/))
		{ $val[$d]{$1}{$2}=undef; push @{$ilist[$d]{$1}},$i; }
	    }
	    @filter=grep defined,@filter if @hashes; #warn "$_\n" for @filter;
	}
	###########

	my $func;
	if ( ! grep m/^-?\d*[tThHaAlL]/, @filter)
	{	############################### grep filter
		$self->{greponly}=1;
		$func='';
		my $op=' && ';
		my @ops;
		my $first=1;
		for (@filter)
		{  if (m/^\(/)
		   {	$func.=$op unless $first;
			$func.='(';
			push @ops,$op;
			$op=($_ eq '(|')? ' || ' : ' && ';
			$first=1;
		   }
		   elsif ($_ eq ')') { $func.=')'; $op=pop @ops; }
		   else
		   {	my ($inv,$col,$cmd,$pat)=m/^(-?)(\d*)([A-Za-z<>!~])(.*)$/;
			push @{ $self->{fields} },$col unless $col eq '';
			$func.=$op unless $first;
			$func.=&{$GrepSubs{$cmd}}($col,$pat,$inv);
			$first=0;
		   }
		}
		$func='[ grep {'.$func.'} @{$_[0]} ];';
	}
	else
	{	############################### non-grep filter
	  { my $d=0; my $c=0;
	    for (@filter)
	    {	if    (m/^\(/)	  {$d++}
		elsif ($_ eq ')') {$d--}
		elsif ($d==0)	  {$c++}
	    }
	    @filter=('(',@filter,')') if $c;
	  }
	  my $d=0;
	  $func='my @hash; my @list=($_[0]); my $tmp;';
	  my @out=('@{$_[0]}'); my @in; my @outref;
	  my $listref='$_[0]';
	  for my $f (@filter)
	  {	if ($f=~m/^[\(\)]/)
		{	if ($f ne ')') #$f begins with '('
			{  $d++;
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
		{	my ($inv,$col,$cmd,$pat)=$f=~m/^(-?)(\d*)([A-Za-z<>!~])(.*)$/;
			push @{ $self->{fields} },$col unless $col eq '';
			unless ($cmd) { warn "Invalid filter : $col $cmd $pat\n"; next; }
			$func.= (exists $GrepSubs{$cmd})
				? $in[$d].'grep '.&{$GrepSubs{$cmd}}($col,$pat,$inv).',@{'.$listref.'};'
				: &{$NGrepSubs{$cmd}}($col,$pat,$listref,$in[$d],$inv);
		}
	  }
	}
	warn "filter=$filter \$sub=eval sub{ $func }\n" if $::debug;
	my $sub=eval "no warnings; sub {$func}";
	if ($@) { warn "filter error : $@"; $sub=sub {$_[0]}; }; #return empty filter if compilation error
	return $self->{'sub'}=$sub;
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
		next unless $pos;
		$text.='  'x$depth;
		$text.=FilterBox::posval2desc($pos,@vals)."\n";
	    }
	}
	chomp $text;	#remove last "\n"
	return $self->{desc}=$text;
}

package Random;

use constant
{ SCORE_FIELDS	=> 0, SCORE_DESCR	=> 1, SCORE_UNIT	=> 2,
  SCORE_ROUND	=> 3, SCORE_DEFAULT	=> 4, SCORE_VALUE	=> 5,
};
our %ScoreTypes;


INIT
{
  %ScoreTypes=
 (	f => [::SONG_LABELS,_"Label is set", '','%s','.5f',sub {'($ref->['.::SONG_LABELS.']=~m/(?:^|\x00)'.quotemeta($_[0]).'(?:$|\x00)/)? 1 : 0'}],
	g => [::SONG_GENRE,_"Genre is set",'','%s','.5g',  sub {'($ref->['.::SONG_GENRE.']=~m/(?:^|\x00)'.quotemeta($_[0]).'(?:$|\x00)/)? 1 : 0'}],
	l => [::SONG_LASTPLAY,_"Number of days since last played",_"days",'%.1f','-1l10',
		'do { my $t=(time-( $ref->['.::SONG_LASTPLAY.'] ||0 ))/86400; ($t<0)? 0 : $t}'],
		#'(time-( $ref->['.::SONG_LASTPLAY.'] ||0 ))/86400'
	L => [::SONG_LASTSKIP,_"Number of days since last skipped",_"days",'%.1f','1L10',
		'do { my $t=(time-( $ref->['.::SONG_LASTSKIP.'] ||0 ))/86400; ($t<0)? 0 : $t}'],
	a => [::SONG_ADDED,_"Number of days since added",_"days",'%.1f','1a50',
		'do { my $t=(time-( $ref->['.::SONG_ADDED.'] ||0 ))/86400; ($t<0)? 0 : $t}'],
	n => [::SONG_NBPLAY,_"Number of times played",_"times",'%d','1n5',
		'($ref->['.::SONG_NBPLAY.'] ||0)'],
	N => [::SONG_NBSKIP,_"Number of times skipped",_"times",'%d','-1N5',
		'($ref->['.::SONG_NBSKIP.'] ||0)'],
	r => [::SONG_RATING,_"Rating",'%%','%d','1r0_.1_.2_.3_.4_.5_.6_.7_.8_.9_1',
		'do {my $v=$ref->['.::SONG_RATING.']; (defined $v && $v ne "")? $v : $Options{DefaultRating} }'
	     ],
 );
}

sub new
{	my ($class,$string)=@_;
	my $self=bless {}, $class;
	$string=~s/^r//;
	$self->{string}=$string;
	return $self;
}

sub fields
{	my $self=shift;
	my %fields;
	for my $s ( split /\x1D/, $self->{string} )
	{	my ($type)=$s=~m/^-?[0-9.]+([a-zA-Z])/;
		next unless $type;
		$fields{ $ScoreTypes{$type}[SCORE_FIELDS] }=undef;
	}
	return [keys %fields];
}

sub make
{	my $self=shift;
	return $self->{score} if $self->{score};
	my @scores;
	::setlocale(::LC_NUMERIC, 'C');
	for my $s ( split /\x1D/, $self->{string} )
	{	my ($inverse,$weight,$type,$extra)=$s=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)/;
		next unless $type;
		my $score=$ScoreTypes{$type}[SCORE_VALUE];
		if ($type eq 'f' || $type eq 'g')
		{	$score=&$score($extra);
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
	$self->{score}='('.join(')*(',@scores).')';
	::setlocale(::LC_NUMERIC, '');
	return $self->{score}
}

sub MakeRandomList
{	my ($self,$lref)=@_;
	$self->{lref}=$lref;
	if ($self->{AddToList})
	{	${ $self->{Sum} }=0;
		@{ $self->{Slist} }=();
	}
	else
	{	my $Sum=0; my @Score;
		$self->{Sum}=\$Sum;
		$self->{Slist}=\@Score;
		my $score=$self->make;
		my $func='no warnings;sub { for my $ID (@{$_[0]}) { my $ref=$::Songs[$ID]; $Sum+=$Score[$ID]='.$score.';} }';
		my $sub=eval $func;
		if ($@) { warn "Error in eval '$func' :\n$@"; }
		$self->{AddToList}= $sub || sub { $Sum+=@{$_[0]}; $Score[$_]=1 for @{$_[0]}; };
		$self->{RmFromList}=sub { for my $ID (@{$_[0]}) { $Sum-=$Score[$ID]; $Score[$ID]=undef; } };
	}
	&{$self->{AddToList}}($lref);
}
sub AddIDs
{	my $self=shift;
	&{ $self->{AddToList} }(\@_);
}
sub RmIDs
{	my $self=shift;
	&{ $self->{RmFromList} }(\@_);
}
sub UpdateIDs
{	my $self=shift;
	&{ $self->{RmFromList} }(\@_);
	&{ $self->{AddToList} }(\@_);
}
sub Draw_old	#FIXME too slow if drawing a LOT of songs
{	my ($self,$nb,$no_list)=@_;
	$no_list||=[];
	my $sum=${ $self->{Sum} };
	my @scores=@{ $self->{Slist} };
	my $lref=$self->{lref};
	unless ($nb)
	{	if (defined $nb) {return ()}
		else { $nb=@$lref; }
	}
	#@$no_list may contains duplicates IDs -> hash,
	#and IDs may not be in @$lref -> check if $scores[$ID] defined to know if in @$lref
	{ my %no;
	  for (grep defined $scores[$_],@$no_list)
		{$sum-=$scores[$_];$scores[$_]=0;$no{$_}=undef;}
	  my $nb_no=keys %no;
	  $nb=@$lref-$nb_no if $nb>@$lref-$nb_no;
	}
	my @drawn;
	NEXTDRAW:while ($nb>0)
	{	last unless $sum>0;
		my $r=rand $sum;
		($r-=$scores[$_])>0 or do { $nb--; push @drawn,$_;$sum-=$scores[$_];$scores[$_]=0; next NEXTDRAW; } for @$lref;
#		for my $i (@$lref)
#		{	next if ($r-=$scores[$i])>0;
#			$nb--;
#			push @drawn,$i;
#			$sum-=$scores[$i];
#			$scores[$i]=0;
#			next NEXTDRAW;
#		}
		last;
	}

	if ($nb)	#if still need more -> select at random (no weights) FIXME too complex
	{	my %drawn; $drawn{$_}=undef for @drawn,@$no_list;
		my @undrawn=grep !exists $drawn{$_},@$lref;
		my @rand; push @rand,rand for @undrawn;
		push @drawn,map( $undrawn[$_], (sort { $rand[$a] <=> $rand[$b] } 0..$#undrawn)[0..$nb-1] );
	}
	return @drawn;
}

sub Draw
{	my ($self,$nb,$no_list)=@_;
	$no_list||=[];
	my $sum=${ $self->{Sum} };
	my @scores=@{ $self->{Slist} };
	my $lref=$self->{lref};
	unless ($nb)
	{	if (defined $nb) {return ()}
		else { $nb=@$lref; }
	}
	#@$no_list may contains duplicates IDs -> hash,
	#and IDs may not be in @$lref -> check if $scores[$ID] defined to know if in @$lref
	{ my %no;
	  for (grep defined $scores[$_],@$no_list)
		{$sum-=$scores[$_];$scores[$_]=0;$no{$_}=undef;}
	  my $nb_no=keys %no;
	  $nb=@$lref-$nb_no if $nb>@$lref-$nb_no;
	}
	my @drawn;
	my $time=times;
	my (@chunknb,@chunksum);
	if ($nb>1)
	{	my $chunk=0; my $count;
		my $size=int(@$lref/60); $size=15 if $size<15;
		for my $id (@$lref)
		{	$chunksum[$chunk]+=$scores[$id];
			$chunknb[$chunk]++;
			$count||=$size;
			$chunk++ unless --$count;
		}
	}
	else { $chunksum[0]=$sum; $chunknb[0]=@$lref; }
	warn "\@chunknb=@chunknb\n" if $::debug;
	warn "\@chunksum=@chunksum\n" if $::debug;
	NEXTDRAW:while ($nb>0)
	{	last unless $sum>0;
		my $r=rand $sum; my $savedr=$r;
		my $chunk=0;
		my $start=0;
		until ($chunksum[$chunk]>$r)
		{	$start+=$chunknb[$chunk];
			$r-=$chunksum[$chunk++];
			#warn "no more chunks : savedr=$savedr r=$r chunk=$chunk" if $chunk>$#chunksum;
			last NEXTDRAW if $chunk>$#chunksum;#FIXME rounding error
		}
		for my $i ($start..$start+$chunknb[$chunk]-1)
		{	next if ($r-=$scores[$lref->[$i]])>0;
			$nb--;
			my $id=$lref->[$i];
			push @drawn,$id;
			$sum-=$scores[$id];
			$chunksum[$chunk]-=$scores[$id];
			$scores[$id]=0;
			next NEXTDRAW;
		}
		#warn $r; warn $nb;
		last;
	}
	warn "drawing took ".(times-$time)." s\n" if $::debug;

	if ($nb)	#if still need more -> select at random (no weights) FIXME too complex
	{	my %drawn; $drawn{$_}=undef for @drawn,@$no_list;
		my @undrawn=grep !exists $drawn{$_},@$lref;
		my @rand; push @rand,rand for @undrawn;
		push @drawn,map( $undrawn[$_], (sort { $rand[$a] <=> $rand[$b] } 0..$#undrawn)[0..$nb-1] );
	}
	return @drawn;
}

sub MakeTab
{	my ($self,$nbcols)=@_;
	my $score=$self->make;
	my $func='no warnings;my $sum;my @tab=(0)x'.$nbcols.'; for my $ID (@::ListPlay) { my $ref=$::Songs[$ID]; $sum+=my $s='.$score.'; $tab[int(.5+'.($nbcols-1).'*$s)]++;}; return \@tab,$sum;';
	my ($tab,$sum)=eval $func;
	if ($@)
	{	warn "Error in eval '$func' :\n$@";
		$tab=[(0)x$nbcols]; $sum=@::ListPlay;
	}
	return $tab,$sum;
}

sub CalcScore
{	my ($self,$ID)=@_;
	my $score=$self->make;
	eval 'no warnings; my $ref=$::Songs[$ID]; '.$score;
}

sub MakeExample
{	my ($class,$string,$ID)=@_;
	::setlocale(::LC_NUMERIC, 'C');
	my ($inverse,$weight,$type,$extra)=$string=~m/^(-?)([0-9.]+)([a-zA-Z])(.*)/;
	return 'error' unless $type;
	my $round=$ScoreTypes{$type}[SCORE_ROUND];
	my $unit= $ScoreTypes{$type}[SCORE_UNIT];
	my $value=$ScoreTypes{$type}[SCORE_VALUE];
	my $score;
	if ($type eq 'f' || $type eq 'g')
	{	$score=&$value($extra);
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
	my $func='no warnings;my $ref=$::Songs[$ID]; return (('.$value.'),('.$score.'));';
	my ($v,$s)=eval $func;
	return 'error' if $@;
	return sprintf("$round $unit -> %.2f",$v,$s);
}


package AAPicture;

my %Cache;
my $watcher;

INIT
{	$watcher={};
	::Watch($watcher, AAPicture => \&AAPicture_Changed);
}

sub newimg
{	my ($col,$key,$size,$todoref)=@_;
	my $p= pixbuf($col,$key,$size, ($todoref ? 0 : 1));
	return Gtk2::Image->new_from_pixbuf($p) if $p;

	my $img=Gtk2::Image->new;
	push @$todoref,$img;
	$img->{params}=[$col,$key,$size];
	$img->set_size_request($size,$size);
	return $img;
}
sub setimg
{	my $img=$_[0];
	my $p=pixbuf( @{delete $img->{params}},1 );
	$img->set_from_pixbuf($p);
}

sub pixbuf
{	my ($col,$key,$size,$now)=@_;
	my ($href,$aa)= $col==::SONG_ARTIST ? (\%::Artist,'a') : (\%::Album,'b');
	my $file= $href->{$key}[::AAPIXLIST];
	#unless ($file)
	#{	return undef unless $::Options{use_default_aapic};
	#	$file=$::Options{default_aapic};
		return undef unless $file;
	#}
	$key=$size.$aa.$key;
	if (exists $Cache{$key})
	{	my $p=$Cache{$key};
		$p->{lastuse}=time;
		return $p;
	}
	return 0 unless $now;
	return load($file,$size,$key);
}

sub draw
{	my ($window,$x,$y,$col,$key,$size,$now,$gc)=@_;
	my $pixbuf=pixbuf($col,$key,$size,$now);
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
	$pixbuf->{lastuse}=time;
	::IdleDo('9_AAPicPurge',undef,\&purge) if keys %Cache >120;
	return $pixbuf;
}

sub purge
{	my $nb= keys(%Cache)-100;# warn "purging $nb cached AApixbufs\n";
	delete $Cache{$_} for (sort {$Cache{$a}{lastuse} <=> $Cache{$b}{lastuse}} keys %Cache)[0..$nb];
}

sub AAPicture_Changed
{	my $key=$_[1];
	my $re=qr/^\d+[ab]\Q$key\E/;
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
	my $self = bless Gtk2::ComboBox->new_text, $class;
	my $names=$list;
	if (ref $list eq 'HASH')
	{	my $h=$list;
		$list=[]; $names=[];
		for my $key (sort {uc($h->{$a}) cmp uc($h->{$b})} keys %$h)
		{	push @$list,$key;
			push @$names,$h->{$key}
		}
	}
	my $found;
	for my $i (0..$#$list)
	{	$self->append_text( $names->[$i] );
		$found=$i if defined $init && $list->[$i] eq $init;
	}
	$found=0 unless defined $found;
	$self->set_active($found);
	$self->{list}=$list;
	$self->signal_connect( changed => $sub ) if $sub;
	return $self;
}

sub get_value
{	my $self=shift;
	return $self->{list}[ $self->get_active ];
}

