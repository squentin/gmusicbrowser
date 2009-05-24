# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin Export
Export
Export plugin
Adds menu entries to song contextual menu
=cut

package GMB::Plugin::Export;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_Export_',
};

my $ON;
my %menuentry=
(topath =>
 {	label => _"Copy to portable player",	#label of the menu entry
	code => \&Copy,				#when menu entry selected
	test => sub {my $p=$::Options{OPT.'path'}; $p && (-d $p || $p=~m/%/);},	#the menu entry is displayed if returns true
	notempty => 'IDs',			#display only if at least one song
 },
 tom3u =>
 {	label => _"Export to .m3u file",
	code => \&ToM3U,
	notempty => 'IDs',
 },
 toCSV =>
 {	label => _"Export song properties to a .csv file",
	code => \&ToCSV,
	notempty => 'IDs',
 },
 tocmd =>
 {	label => sub { ($::Options{OPT.'tocmd_label'} || _"Unamed custom command") },
	code => \&RunCommand,
	test => sub {my $c=$::Options{OPT.'tocmd_cmd'}; defined $c && $c ne '';},
	notempty => 'IDs',
 }
);

my %FLmenuentry=
(topath =>
 {	label => _"Copy to portable player",
	code => \&Copy,
	test => sub {my $p=$::Options{OPT.'path'}; $p && (-d $p || $p=~m/%/);},
	isdefined => 'filter',
 },
 tom3u =>
 {	label => _"Export to .m3u file",
	code => \&ToM3U,
	isdefined => 'filter',
 },
);

sub Start
{	$ON=1;
	updatemenu();
}
sub Stop
{	$ON=0;
	updatemenu();
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');

	my $entry1=::NewPrefFileEntry(OPT.'path',_"Player mounted on :",folder=>1, sizeg1=>$sg1,sizeg2=>$sg2);
	my $entry2=::NewPrefEntry(OPT.'folderformat',_"Folder format :", sizeg1=>$sg1,sizeg2=>$sg2, tip =>_("These fields can be used :")."\n".::MakeReplaceText('talydnAY'));
	my $entry3=::NewPrefEntry(OPT.'filenameformat',_"Filename format :", sizeg1=>$sg1,sizeg2=>$sg2, tip =>_("These fields can be used :")."\n".::MakeReplaceText('talydnAYo'));
	my $check1=::NewPrefCheckButton(OPT.'topath',_"Copy to mounted portable player", \&updatemenu, undef, ::Vpack($entry1,$entry2,$entry3) );

	my $entry4=::NewPrefEntry(OPT.'tocmd_label',_"Menu entry name", sizeg1=> $sg1,sizeg2=>$sg2, tip => _("Name under which the command will appear in the menu"));
	my $entry5=::NewPrefEntry(OPT.'tocmd_cmd',_"System command :", sizeg1=> $sg1,sizeg2=>$sg2,
		tip =>  _("These fields can be used :")."\n".::MakeReplaceText('ftalydnAY')."\n".
			_("In this case one command by file will be run\n\n".
			'Or you can use the field $files which will be replaced by the list of files, and only one command will be run'));
	my $check2=::NewPrefCheckButton(OPT.'tocmd',_"Execute custom command on selected files", \&updatemenu ,undef, ::Vpack($entry4,$entry5) );

	my $check3=::NewPrefCheckButton(OPT.'tom3u',_"Export to .m3u file", \&updatemenu);
	my $check4=::NewPrefCheckButton(OPT.'toCSV',_"Export song properties to a .csv file", \&updatemenu);
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $check1,$check2,$check3,$check4;
	return $vbox;
}

sub updatemenu
{	my $removeall=!$ON;
	for my $eid (keys %menuentry)
	{	my $menu=\@::SongCMenu;
		my $entry=$menuentry{$eid};
		if (!$removeall && $::Options{OPT.$eid})
		{	push @$menu,$entry unless (grep $_==$entry, @$menu);
		}
		else
		{	@$menu =grep $_!=$entry, @$menu;
		}
	}
	for my $eid (keys %FLmenuentry)
	{	my $menu=\@FilterList::FLcMenu;
		my $entry=$FLmenuentry{$eid};
		if (!$removeall && $::Options{OPT.$eid})
		{	push @$menu,$entry unless (grep $_==$entry, @$menu);
		}
		else
		{	@$menu =grep $_!=$entry, @$menu;
		}
	}
}

sub Copy
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	::CopyMoveFiles($IDs,::TRUE,$::Options{OPT.'path'},$::Options{OPT.'folderformat'},$::Options{OPT.'filenameformat'});
}

sub ToM3U
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $file=::ChooseSaveFile(undef,_"Write filenames to ...", Songs::Get($IDs->[0],'path'), 'list.m3u');
	return unless defined $file;
	open my$fh,'>',$file;
	for my $ID (@$IDs)
	 { print $fh Songs::GetFullFilename($ID)."\n"; }
	close $fh;
}

sub ToCSV
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my $check=::NewPrefCheckButton(OPT.'toCSV_notitlerow',_"Do not add a title row");
	my $file=::ChooseSaveFile(undef,_"Write filenames to ...",undef,'songs.csv',$check);
	return unless defined $file;
	my @fields=qw/file path title artist album year comment track disc length size rating modif added lastplay playcount lastskip skipcount bitrate filetype channel samprate genre label/; #FIXME PHASE1 use a dynamic list of fields
	open my$fh,'>:utf8',$file;
	unless ($::Options{OPT.'toCSV_notitlerow'}) #print a title row
	{	print $fh join(',',map Songs::FieldName($_), @fields)."\n";
	}
	no warnings 'uninitialized';
	for my $ID (@$IDs)
	{	my @val;
		push @val, Songs::Get($ID,@fields);
		s/\x00/\t/g for @val; #for genres and labels
		s/"/""/g for @val;
		::_utf8_on($val[0]); # for file and path, so it doesn't get converted in utf8
		::_utf8_on($val[1]); # FIXME find a cleaner way to do that
		#print STDERR join(',',@val)."\n";
		print $fh join(',',map '"'.$_.'"', @val)."\n";
	}
	close $fh;

}

sub RunCommand
{	my $IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	my @cmd=split / /,$::Options{OPT.'tocmd_cmd'};
	return unless @cmd;
	if (grep $_ eq '$files', @cmd)
	{	my @files=map ::ReplaceFields($_,'%f'), @$IDs;
		@cmd=map { $_ ne '$files' ?  $_ :  @files } @cmd;
		::forksystem(@cmd);
	}
	else
	{	for my $ID (@$IDs)
		{	my @c=@cmd;
			$_=::ReplaceFields($ID,$_) for @c;
			system @c;
		}
	}
}

1
