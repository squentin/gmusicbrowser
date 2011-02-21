#!/usr/bin/perl
use strict;
use warnings;

my $verbose=1;
m/-q|--quiet/ and $verbose=0 for @ARGV;
use FindBin;
my $path=$FindBin::Bin;
$path=~s#/[^/]*/?$##; #up one dir
my @files=( "$path/gmusicbrowser.pl", glob("$path/*.pm"), glob("$path/plugins/*.pm"), glob("$path/layouts/*.layout") );

my %msgid;
my %msgid_p;
my $version;

while (my $file=shift @files)
{
 warn "reading $file\n" if $verbose;
 open my$fh,$file  or die $!;
 $file=~s#^$path/##;
 my ($layout_id,$layout_loc);
 while (<$fh>)
 {	if (!$version && m/VERSION *=> '([0-9]\.[0-9]+)'/) {$version=$1}

	while (m/_"([^"]+)"/g)		{ $msgid{$1}.=" $file:$."; }
	while (m/_\("([^"]+)"\)/g)	{ $msgid{$1}.=" $file:$."; }
	while (m/_\('([^']+)'\)/g)	{ $msgid{$1}.=" $file:$."; }

	while (m/__\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,/g)	{ $msgid_p{$1}{$2}.=" $file:$."; }
	while (m/__\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,/g)	{ $msgid_p{$1}{$2}.=" $file:$."; }
	while (m/__\(\s*'([^']+)'\s*,\s*"([^"]+)"\s*,/g)	{ $msgid_p{$1}{$2}.=" $file:$."; }
	while (m/__\(\s*"([^"]+)"\s*,\s*'([^']+)'\s*,/g)	{ $msgid_p{$1}{$2}.=" $file:$."; }

	if (m/^=gmbplugin \D\w+/)
	{	while (<$fh>)
		{	last if m/^=cut/;
			$msgid{$1}.= " $file:$." if m/^\s*(?:name|title|desc)\s+(.+)/;
		}
	}
	if ($file=~m/\.layout$/) #id of layouts is used as default layout name => may need translation
	{	if (m/^\[([^]]+)\]/)
		{	$msgid{ $layout_id }.= $layout_loc if defined $layout_id;
			$layout_id=$1;
			$layout_loc=" $file:$.";
		}
		elsif (m/^\s*Name\s*=/) { $layout_id=undef } #layout has a name => no need to translate the id
	}
 }
 close $fh;
 $msgid{ $layout_id }.= $layout_loc if defined $layout_id; #for last layout
}

$version||="VERSION";
my $date=`date --iso-8601=minutes`; $date=~s/T/ /; chomp $date;

open my$fh,'>',$FindBin::Bin.'/gmusicbrowser.pot'  or die $!;
print $fh '
msgid ""
msgstr ""
"Project-Id-Version: gmusicbrowser '.$version.'\n"
"Report-Msgid-Bugs-To: squentin@free.fr\n"
"POT-Creation-Date: '.$date.'\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\n"
"Language-Team: LANGUAGE\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=2; plural=n != 1;\n"
';

for my $msg (sort keys %msgid)
{	print $fh qq(#:$msgid{$msg}\nmsgid "$msg"\nmsgstr ""\n\n);
}

for my $msg (sort keys %msgid_p)
{	for my $msgp (sort keys %{ $msgid_p{$msg} })
	{ print $fh qq(#:$msgid_p{$msg}{$msgp}\nmsgid "$msg"\nmsgid_plural "$msgp"\nmsgstr[0] ""\nmsgstr[1] ""\n\n);
	}
}

close $fh;

warn "wrote gmusicbrowser.pot\n" if $verbose;
warn "to update fr.po, run :  msgmerge -s -U fr.po gmusicbrowser.pot\n" if $verbose;
