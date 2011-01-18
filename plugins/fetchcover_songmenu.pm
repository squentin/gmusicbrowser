=gmbplugin COVERSONGCMENU
name	Picture finder in song menu
title	Picture finder in song menu plugin
desc	Extends Picture finder plugin by adding menu entries to song context menu for fetching/setting album cover.
=cut

package GMB::Plugin::COVERSONGCMENU;
use strict;

my %menuitem=
(	label => _"Fetch cover",
	code => sub { my $gid=Songs::Get_gid($_[0]{IDs}[0],'album'); GMB::Plugin::FETCHCOVER::Fetch('album',$gid,$_[0]{IDs}[0]); },
	notmode => 'P',
	onlyone => 'IDs',
);
my %menuitem0=
(	label => _"Set cover",
	code => sub { my $gid=Songs::Get_gid($_[0]{IDs}[0],'album'); ::ChooseAAPicture($_[0]{IDs}[0],'album',$gid); },
	notmode => 'P',
	onlyone => 'IDs',
);
sub Start
{	push @::SongCMenu,( \%menuitem0, \%menuitem );
}
sub Stop
{	@::SongCMenu=  grep($_!=\%menuitem0, grep($_!=\%menuitem, @::SongCMenu));
}

sub prefbox {
}

1

