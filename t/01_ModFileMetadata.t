# Copyright (C) 2020 Daniel Hursh <dan@hursh.org>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

use Test::More;
use File::Fetch;
use Digest::MD5 qw(md5_hex);

########################################
# Define the test set.
our @SampleFiles;
BEGIN {
    @SampleFiles = (
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=172378#onslaugh.it',
            md5   => '5211667c9883d3fc25bce9735d9a9cd6',
            size  => 398680,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/onslaugh.it',
            filename => 'onslaugh.it',
            type     => 'IT',
            longType => 'Impulse Tracker',

            # ModFileMetadata::*
            title       => 'Onslaught',
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=55696#pod.s3m',
            md5   => '437efc7f1acbaf67102b2753e1aafa62',
            size  => 443136,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/pod.s3m',
            filename => 'pod.s3m',
            type     => 'S3M',
            longType => 'Scream Tracker 3',

            # ModFileMetadata::*
            title       => '"Point of Departure"',
        },
        {
            # Test data

            url   => 'https://api.modarchive.org/downloads.php?moduleid=34580#CASTAWAY.XM',
            md5   => 'f00d0a2411bdad9d4bc54bbe5a7caeb0',
            size  => 962228,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/CASTAWAY.XM',
            filename => 'CASTAWAY.XM',
            type     => 'XM',
            longType => 'Faster Tracker 2',

            # ModFileMetadata::*
            title       => 'castaway',
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=59903#WPROMISE.XM',
            md5   => 'a828fc578a9bdc20b24210cd717f1d8d',
            size  => 887397,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/HOPE-8.XM',
            filename => 'HOPE-8.XM',
            type     => 'XM',
            longType => 'Faster Tracker 2',

            # ModFileMetadata::*
            title  => 'Western Promise',
            artist => 'Astradyne',
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=39993#crystals.669',
            md5   => '0bfbfe214139cfef08f7223cf8c3ba3f',
            size  => 26618,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/crystals.669',
            filename => 'crystals.669',
            type     => '669',
            longType => 'Composer 669',

            # ModFileMetadata::*
            title   => 'Crystals...',
            message => " Crystals...                        \n".
                       "                                    \n".
                       "    by Tran of Renaissance...       ",
        },
        # This file contains a non-unicode character that must be sanitized..
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=184466#xypher.669',
            md5   => '95b13aa9f5b639531777b5cfa7c157aa',
            size  => 161653,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/xypher.669',
            filename => 'xypher.669',
            type     => '669',
            longType => 'Composer 669',

            # ModFileMetadata::*
            title   => 'Xyphêr...',
            message => " Xyphêr...                          \n".
                       "                                    \n".
                       "    by Tran of Renaissance...       ",
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=44355#HERE-KLF.MTM',
            md5   => 'dd6436f15332a46105ab1c7a77a4a386',
            size  => 333170,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/HERE-KLF.MTM',
            filename => 'HERE-KLF.MTM',
            type     => 'MTM',
            longType => 'MultiTracker',

            # ModFileMetadata::*
            title       => 'Here It Is -KLF-',
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=180108#lig-rave.dmf',
            md5   => 'a7e3355db847754da0a5b86e0d78ba56',
            size  => 264214,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/lig-rave.dmf',
            filename => 'lig-rave.dmf',
            type     => 'DMF',
            longType => 'D-lusion',

            # ModFileMetadata::*
            title  => 'RaVeStOrM  (Synth-MIX)',
            artist => 'LightsTONE',
        },
        {
            # Test data
            url   => 'https://api.modarchive.org/downloads.php?moduleid=126990#aftertouch.mod',
            md5   => 'c779f1698467b5d64d9b0ace890f6228',
            size  => 478790,
            valid => 1,

            # ModFileMetadata
            path     => 't/samples/aftertouch.mod',
            filename => 'aftertouch.mod',
            type     => 'MOD',
            longType => 'Protracker',

            # ModFileMetadata::*
            title => 'aftertouch',
        },
    );

}

########################################
# Calculate the plan.
BEGIN {
    # Test 'use'ing the library
    my $test_count = 1;

    # Test happy path constructors for ModFileMetadata on valid @SampleFiles
    $test_count += scalar grep { $_->{valid} } @SampleFiles;

    # Declare the plan
    plan tests => $test_count;
}


########################################
# Load the library.
BEGIN { use_ok('ModFileMetadata') }


########################################
# Declare helpers

# Calculate the MD5 of a file.
sub file_md5{
    my($path) = shift;
    open my $fh, '<', $path or die "Failed to open \"$path\".";
    local $/ = undef;
    my $md5 = md5_hex(<$fh>);
    close $fh;
    return $md5;
}

sub fetch_sample{
    my $file = shift;
    my $path = $file->{path};

    # Short circuit if we have it.
    return 1
      if (-f $path)
      && (-s $path) == $file->{size}
      && ( uc(file_md5($path)) eq uc($file->{md5}) );

    # Delete it if it exists.
    unlink($path) if -f $path;

    # Download it.
    my $ff = File::Fetch->new(uri => $file->{url});
    note("Fetching ",$file->{url}, " : ", defined($ff) );
    $ff->fetch( to => 't/samples' ) or die $ff->error;
    if($ff->output_file ne $file->{filename}){
        rename('t/samples/'.$ff->output_file, $path)
          or die("Failed to rename \"", $ff->output_file,
                 "\" to \"$file->{filename}\"");
    }

    # Validate it.
    die("Failed to fetch \"$path\".")    unless -f $path;
    die("Incorrect size for \"$path\".") unless (-s $path) == $file->{size};
    die("Incorrect MD5 for \"$path\".")
      unless file_md5($path) eq $file->{md5};
    return 1;
}

sub test_happy{
    my $want = shift;
    my $got = ModFileMetadata->new($want->{path});

    subtest "Happy path test for '$want->{path}'", => sub {
        plan tests => 11;
        ok(defined $got,                                   'object');
        is($got->path,               $want->{path},        'path');
        is($got->filename,           $want->{filename},    'filename');
        ok($got->isValidModFile,                       'Valid file');
        is($got->type,               $want->{type},        'type');
        is($got->typeVerbose,        $want->{longType},    'typeVerbose');
        is($got->title,              $want->{title},       'title');
        is($got->artist,             $want->{artist},      'artist');
        is($got->message,            $want->{message},     'message');
        is_deeply($got->samples,     $want->{samples},     'samples');
        is_deeply($got->instruments, $want->{instruments}, 'instruments');
    };
}

########################################
# Fetch test data
fetch_sample($_) foreach @SampleFiles;


########################################
# Validate happy path constructors
foreach my $sample (@SampleFiles){
    test_happy($sample) if $sample->{valid};
}

########################################
# Validate unhappy path constructors
