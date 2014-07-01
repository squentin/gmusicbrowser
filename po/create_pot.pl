#!/usr/bin/perl
use strict;
use warnings;

my $verbose=1;
m/-q|--quiet/ and $verbose=0 for @ARGV;
use FindBin;
my $path=$FindBin::Bin;
$path=~s#/[^/]*/?$##; #up one dir
my @files=( "$path/gmusicbrowser.pl", glob("$path/*.pm"), glob("$path/plugins/*.pm"), glob("$path/layouts/*.layout") );

my (%msgid,%msgid_p);
my (%comments,%comments_p);
my $version;

my @formats=
(	'',
	"#, perl-format\n",
	"#, perl-brace-format\n",
	"#, perl-format, perl-brace-format\n",
);

while (my $file=shift @files)
{
 warn "reading $file\n" if $verbose;
 open my$fh,$file  or die $!;
 $file=~s#^$path/##;
 while (<$fh>)
 {	next if m/^\s*#/;
	if (!$version && m/VERSION *=> '([0-9]\.[0-9]+)'/) {$version=$1}

	my $com='';
	if (s/#(xgettext:no-perl-brace-format)//){$com.="$1\n"}
	if (s/#(xgettext:no-perl-format)//)	{$com.="$1\n"}
	if (m/#TRANSLATION:\s*(.*)/)		{$com.="#. $1\n"}

	while (m/\b_"([^"]+)"/g)	{ $msgid{''}{$1}.=" $file:$."; $comments{''}{$1}.=$com; }

	while (m/\b(_|_p) \(\s* ("[^"]+"|'[^']+') \s* (?:,\s* ("[^"]+"|'[^']+') )? \)/gx)
	{	my ($ctx,$str)=remove_quotes( $1 eq '_p' ? ($2,$3) : ('',$2) );
		$msgid{$ctx}{$str}   .= " $file:$.";
		$comments{$ctx}{$str}.= $com;
	}
	while (m/\b(__|__p) \(\s* ("[^"]+"|'[^']+') \s*,\s* ("[^"]+"|'[^']+') \s*,\s* (?:,\s* ("[^"]+"|'[^']+') )?/gx)
	{	my ($ctx,$str1,$str2)=remove_quotes( $1 eq '__p' ? ($2,$3,$4) : ('',$2,$3) );
		$msgid_p{$ctx}{$str1}{$str2}  .= " $file:$.";
		$comments_p{$ctx}{$str1}{$str2}.= $com;
	}

	if (m/^=(?:begin |for )?gmbplugin/)
	{	while (<$fh>)
		{	s/\s*[\n\r]+$//;
			last if $_ eq '=cut' || $_ eq '=end gmbplugin';
			$msgid{''}{$1}.= " $file:$." if m/^\s*(?:name|title|desc)\s+(.+)/;
		}
	}
 }
 close $fh;
}

$version||="VERSION";
my $date=`date --iso-8601=minutes`; $date=~s/T/ /; chomp $date;

my $potfile= $FindBin::Bin.'/gmusicbrowser.pot';
open my$fh,'>',$potfile or die $!;
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

my (%count,$count_simple,$count_plural);
my @count_format=(0,0,0,0);

for my $context (sort keys %msgid)
{	my $msgctxt= $context eq '' ? '' : qq(msgctxt "$context"\n);
	for my $msg (sort keys %{ $msgid{$context} })
	{	my $com= create_comments( $comments{$context}{$msg}, $msg);
		print $fh "#:$msgid{$context}{$msg}\n". $com.$msgctxt. qq(msgid "$msg"\nmsgstr ""\n\n);
		$count{$context}++;
		$count_simple++;
	}
}

for my $context (sort keys %msgid_p)
{	my $msgctxt= $context eq '' ? '' : qq(msgctxt "$context"\n);
	for my $msg (sort keys %{ $msgid_p{$context} })
	{	for my $msgp (sort keys %{ $msgid_p{$context}{$msg} })
		{	my $com= create_comments( $comments{$context}{$msg}{$msgp}, $msg.$msgp);
			print $fh "#:$msgid_p{$context}{$msg}{$msgp}\n". $com.$msgctxt. qq(msgid "$msg"\nmsgid_plural "$msgp"\nmsgstr[0] ""\nmsgstr[1] ""\n\n);
			$count{$context}++;
			$count_plural++;
		}
	}
}

close $fh;

if ($verbose)
{	warn "".($count_simple+$count_plural)." strings, including:\n";
	warn " $count_plural plural strings\n";
	for my $c (sort keys %count)
	{	warn " $count{$c} with ".($c? "context $c" : "default context")."\n";
	}
	warn " ".($count_format[1]+$count_format[3])." with perl-format flag\n";
	warn " ".($count_format[2]+$count_format[3])." with perl-format-brace flag\n";
	warn "wrote $potfile\n";
	warn "to update fr.po, run :  msgmerge -s -U fr.po gmusicbrowser.pot\n";
}
exit 0;

sub remove_quotes
{	my @ret=@_;
	for (@ret)
	{	next unless $_;
		s/['"]$//;
		s/^(['"])//;
		s/"/\\"/g if $1 eq "'"; #escape " if string was using single quotes
	}
	return @ret;
}

sub create_comments
{	my ($com,$msg)=@_;
	$com||='';
	my $format=0;
	if ($msg=~m/%/)    { $format|=1 unless $com=~s/xgettext:no-perl-format\n//g; }
	if ($msg=~m/{\w+}/){ $format|=2 unless $com=~s/xgettext:no-perl-brace-format\n//g; }
	$count_format[$format]++;
	$com.=$formats[$format];
	return $com;
}

