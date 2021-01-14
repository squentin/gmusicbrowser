# Copyright (C) 2020 Daniel Hursh <dan@hursh.org>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# TODOS
# - [X] interface
# - [X] scaffold testcase  (prove -I. t / perl -I. t)
# - [X] test data / fetcher (each format)
# - [ ] fetch from internet
# - [ ] POD
# - [ ] For each format
#   - [X] new
#   - [X] validate (We are trusting *.mod.  This should be "improved".
#   - [X] title
# - [ ] For each format, add other fields as appropriate
# - [ ] new formats Add ULT, PTM & MDL.  Investigate PLM.


package ModFileMetadata;
# A class for reading metadata from (support) mod/tracker files.

use strict;
use warnings;
use File::Basename;
use Encode;

my $decode = sub { map { Encode::decode('cp437', $_) } @_ };

# Reference
# https://www.loc.gov/preservation/digital/formats/fdd/fdd000126.shtml


# Determine the Mod File type based on the file name and
# call the type specific constructor to …
# - Read and store any necessary data from file.
# - Do basic parsing and verification based on filename.
# - This is a factory that will return something that @ISA ModFileMetadata.
sub new;  # Defined below

# Return the path given to new(),
sub path { return $_[0]{path} }

# Return the filename given to new(),
sub filename { return $_[0]{filename} }

# Confirm the file is valid.
sub isValidModFile { return undef }

# Return a string of the modfile type.  ("s3m", "it", "mod", etc)
sub type { return undef }

# Return a string of the verbose modfile type.
#   ("Scream Tracker 3", "Impulse Tracker", "ProTracker", etc)
sub typeVerbose { return undef }

# Return the Title from the file (Based on the format)
# (Returns undef if blank, not supported or invalid)
# (Trailing and leading whitespace is removed)
sub title { return undef }

# Return the Artist from the file (Based on the format (DMF has a composer))
# (Returns undef if blank, not supported or invalid)
# (Trailing and leading whitespace is removed)
sub artist { return undef }

# Return the Message from the file
#   (Based on the format (Message, Comment, etc. Not Samples or Instruments))
# (Returns undef if blank, not supported or invalid)
sub message { return undef }

# Return an array_ref of sample names from the file
# (Returns undef if blank, not supported or invalid)
sub samples { return undef }

# Return an array_ref of instrument names from the file
# (Returns undef if blank, not supported or invalid)
sub instruments { return undef }

# Implement the factory constructor
sub new {
    my($class) = shift;
    my($path) = shift;
    my($self) = bless {
	path => $path,
	filename => basename($path)
    };

    my $fh = IO::File->new($self->{path}, 'r');
    if($fh){
        $fh->binmode;

        # Big if block to determine which constructor to call.
        if(ModFileMetadata::IT::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::IT->new($self, $fh)
        }
        elsif(ModFileMetadata::S3M::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::S3M->new($self, $fh)
        }
        elsif(ModFileMetadata::XM::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::XM->new($self, $fh)
        }
        elsif(ModFileMetadata::MTM::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::MTM->new($self, $fh)
        }
        elsif(ModFileMetadata::DMF::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::DMF->new($self, $fh)
        }
        elsif(ModFileMetadata::669::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::669->new($self, $fh)
        }
        elsif(ModFileMetadata::MOD::checkTypeByName($self->{filename})){
            $self = ModFileMetadata::MOD->new($self, $fh)
        }
        $fh->close;
    }

    return $self;
}


######################################################################

package ModFileMetadata::IT;
use parent 'ModFileMetadata';

# IT (Impulse Tracker)
# https://github.com/schismtracker/schismtracker/wiki/ITTECH.TXT

# Base IT header format
my $itHeaderLength = 0x40;
my $itHeaderFormat =
    'A[4]'.  # "IMPM"  (Eye catcher)
    'A[26]'. # <Title> (26 bytes with a null terminator)
    'x[8]'.  # 8 16bit fields (We don't care about these)
    'b[16]'. # 16 bit field (We care about the first bit)
    'x[6]'.  # 6 byte fields (We don't care about these)
    'v'.     # 16 bit Message length
    'V'.     # 32 bit absolute file offest to Message
    'x[4]';  # 32 bit reserved field (We don't care about it)

# Subroutine (not method)
sub checkTypeByName($)  { return scalar($_[0] =~ m/\.it$/i) }

# This modfile type.
sub type { return 'IT' }
sub typeVerbose { return 'Impulse Tracker' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $itHeaderLength) == $itHeaderLength or die;
        my($ec, $title, $bits, $mlength, $moffset) =
            unpack($itHeaderFormat, $header);
        ($title) = $decode->($title);

        # Do basic validation
        die unless $ec eq "IMPM";

        # Store data
        $self->{it}{valid}  = 1;
        ($self->{it}{title} = $title) =~ s/^\s+|\s+$//g;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{it}{valid} }
sub title { return $_[0]->{it}{title} }


######################################################################

package ModFileMetadata::S3M;
use parent 'ModFileMetadata';

# S3m (Scream Tracker 3)
# http://www.shikadi.net/moddingwiki/S3M_Format
# https://wiki.multimedia.cx/index.php?title=Scream_Tracker_3_Module
# http://www.textfiles.com/programming/FORMATS/s3m-form.txt
# ftp://ftp.modland.com/pub/documents/format_documentation/FireLight%20S3M%20Player%20Tutorial.txt
# ftp://ftp.modland.com/pub/documents/format_documentation/FireLight%20MOD%20Player%20Tutorial.txt

# Base S3M header format
my $s3mHeaderLength = 0x48;
my $s3mHeaderFormat =
    'A[28]'. # <Title> (28 bytes with a null terminator)
    'C'.     # byte 0x1A (Eye catcher)
    'C'.     # byte 0x10 (Eye catcher)
    'v'.     # 16bit 0x0 (reserved, always zero (aka an eye catcher))
    'x[12]'. # 6 16bit fields (We don't care about these)
    'A[4]';  # "SCRM" (Eye catcher)

# Subroutine (not method)
sub checkTypeByName($) { return scalar($_[0] =~ m/\.s3m$/i) }

# This modfile type.
sub type { return 'S3M' }
sub typeVerbose { return 'Scream Tracker 3' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $s3mHeaderLength) == $s3mHeaderLength or die;
        my($title, $ec1, $ec2, $ec3, $ec4) = unpack($s3mHeaderFormat, $header);
        ($title) = $decode->($title);

        # Do basic validation
        die unless ($ec1 == 0x1A) && ($ec2 == 0x10)
            && ($ec3 eq 0x00) && ($ec4 eq "SCRM");

        # Store data
        $self->{s3m}{valid}  = 1;
        ($self->{s3m}{title} = $title) =~ s/^\s+|\s+$//g;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{s3m}{valid} }
sub title { return $_[0]->{s3m}{title} }


######################################################################

package ModFileMetadata::XM;
use parent 'ModFileMetadata';

# XM (Faster Tracker 2)
# http://jss.sourceforge.net/moddoc/xm-form.txt
# http://ftp.modland.com/pub/documents/format_documentation/FastTracker%202%20v2.04%20%28.xm%29.html
# http://fileformats.archiveteam.org/wiki/Extended_Module

# Base XM header format
my $xmHeaderLength = 0x3C;
my $xmHeaderFormat =
    'a[17]'. # "Extended Module: " (Eye catcher)
    'A[20]'. # <Title> (20 bytes with a null terminator)
    'C'.     # 0x1A (Eye catcher)
    'A[20]'. # Possible Artist (See fileformats.archiveteam.org wiki)
    'v';     # Version (Expect 0x104.  Not valid if lower.)

# Subroutine (not method)
sub checkTypeByName($) { return scalar($_[0] =~ m/\.xm$/i) }

# This modfile type.
sub type { return 'XM' }
sub typeVerbose { return 'Faster Tracker 2' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $xmHeaderLength) == $xmHeaderLength or die;
        my($ec1, $title, $ec2, $tracker, $version) =
            unpack($xmHeaderFormat, $header);
        ($title, $tracker) = $decode->($title, $tracker);

        # Do basic validation
        die unless ($ec1 eq 'Extended Module: ')
            && ($ec2 == 0x1A)
            && ($version >= 0x0104);

        # Store data
        $self->{xm}{valid}   = 1;
        ($self->{xm}{title}  = $title) =~ s/^\s+|\s+$//g;
        ($self->{xm}{artist} = $tracker) =~ s/^\s+|\s+$//g
            unless $tracker =~ /^ ( FastTracker | DigiBooster Pro        |
                                    AmigaMML    | MilkyTracker           |
                                    MED2XM      | ModPlug Tracker        |
                                    MOD2XM      | \*Converted \S+-File\* |
                                    OpenMPT     | Velvet Studio          |
                                    XMLiTE      | $                      ) /x;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{xm}{valid} }
sub title { return $_[0]->{xm}{title} }
sub artist { return $_[0]->{xm}{artist} }


######################################################################

package ModFileMetadata::669;
use parent 'ModFileMetadata';

# 669
# ftp://ftp.modland.com/pub/documents/format_documentation/Composer%20669,%20Unis%20669%20(.669).txt
# https://www.fileformat.info/format/669/corion.htm
# https://battleofthebits.org/lyceum/View/669+Format/

# Base 669 header format
my $c669HeaderLength = 0X6F;
my $c669HeaderFormat =
    'A[2]'.   # "if" or "JN" (Eye catcher)
    'a[36]'.  # <Message> (seems to be 3 lines of 36 characters each)
    'a[36]'.  # I'm going to ready three 36 blocks and insert newlines
    'a[36]';  # Instead of one 108 byte block.

# Subroutine (not method)
sub checkTypeByName($) { return scalar($_[0] =~ m/\.669$/i) }

# This modfile type.
sub type { return '669' }
sub typeVerbose { return 'Composer 669' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $c669HeaderLength) == $c669HeaderLength or die;
        my($ec, $mesg1, $mesg2, $mesg3) = unpack($c669HeaderFormat, $header);
        ($mesg1, $mesg2, $mesg3) = $decode->($mesg1, $mesg2, $mesg3);

        # Do basic validation
        die unless ($ec eq 'if') || ($ec eq 'JN');

        # Store data
        $self->{669}{valid}   = 1;
        ($self->{669}{title}  = $mesg1) =~ s/^\s+|\s+$//g;
        $self->{669}{message} = "$mesg1\n$mesg2\n$mesg3";
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{669}{valid} }
sub title { return $_[0]->{669}{title} }
sub message { return $_[0]->{669}{message} }


######################################################################

package ModFileMetadata::MTM;
use parent 'ModFileMetadata';

# MTM (MultiTracker Music)
# http://www.textfiles.com/programming/FORMATS/mtm-form.txt

# Base MTM header format
my $mtmHeaderLength = 0x40;
my $mtmHeaderFormat =
    'A[3]'.  # "MTM"  (Eye catcher)
    'x'.     # verion number (We don't care about this)
    'A[20]'; # <Title> (20 bytes)

# Subroutine (not method) 
sub checkTypeByName($) { return scalar($_[0] =~ m/\.mtm$/i) }

# This modfile type.
sub type { return 'MTM' }
sub typeVerbose { return 'MultiTracker' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $mtmHeaderLength) == $mtmHeaderLength or die;
        my($ec, $title) = unpack($mtmHeaderFormat, $header);
        ($title) = $decode->($title);

        # Do basic validation
        die unless $ec eq "MTM";

        # Store data
        $self->{mtm}{valid}  = 1;
        ($self->{mtm}{title} = $title) =~ s/^\s+|\s+$//g;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{mtm}{valid} }
sub title { return $_[0]->{mtm}{title} }


######################################################################

package ModFileMetadata::DMF;
use parent 'ModFileMetadata';

# DMF (D-Lusion XTracker)
# https://www.fileformat.info/format/dmf/corion.htm
# https://github.com/OpenMPT/openmpt/blob/master/soundlib/Load_dmf.cpp

# Base DMF header format
my $dmfHeaderLength = 0x42;
my $dmfHeaderFormat =
    'A[4]'.  # "DDMF"  (Eye catcher)
    'x'.     # verion number (We don't care about this)
    'x[8]'.  # <Tracker> (We don't really care about this)
    'A[30]'. # <Title>
    'A[20]'. # <Composer>
    'x[3]';  # <creationDay><month><year> (Maybe we should care?)

# Subroutine (not method)
sub checkTypeByName($) { return scalar($_[0] =~ m/\.dmf$/i) }

# This modfile type.
sub type { return 'DMF' }
sub typeVerbose { return 'D-lusion' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $dmfHeaderLength) == $dmfHeaderLength or die;
        my($ec, $title, $artist) = unpack($dmfHeaderFormat, $header);
        ($title, $artist) = $decode->($title, $artist);

        # Do basic validation
        die unless $ec eq "DDMF";

        # Store data
        $self->{dmf}{valid}   = 1;
        ($self->{dmf}{title}  = $title)  =~ s/^\s+|\s+$//g;
        ($self->{dmf}{artist} = $artist) =~ s/^\s+|\s+$//g;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{dmf}{valid} }
sub title { return $_[0]->{dmf}{title} }
sub artist { return $_[0]->{dmf}{artist} }


######################################################################

package ModFileMetadata::MOD;
use parent 'ModFileMetadata';

# MOD (ProTracker)
# https://wiki.multimedia.cx/index.php/Protracker_Module
# https://www.fileformat.info/format/mod/spec/3bc11a4842e342498a6230e60187b463/view.htm
# https://github.com/OpenMPT/openmpt/blob/master/soundlib/Load_mod.cpp

# Base MOD header format (Sorta. Not really.)
my $modHeaderLength = 0x14;
my $modHeaderFormat =
    'A[20]'; # <Title> (We assume it is a mod file, because the position of
             #          the only eye catcher and it's value isn't fixed.  I
             #          may try more when I come back for messages.)

# Subroutine (not method)
sub checkTypeByName($) {
    return scalar($_[0] =~ m/\.mod$/i)
	|| scalar($_[0] =~ m/^mod\./i); # Is this is an Amiga convention?
}

# This modfile type.
sub type { return 'MOD' }
sub typeVerbose { return 'Protracker' }

# Read and store any necessary data from file.
# Do basic parsing and verification based on filename.
# Return the blessed object.
sub new {
    my($class, $self, $fh) = @_;
    my $header;

    eval {
        # Read the header
        $fh->seek(0,0) or die;
        $fh->read($header, $modHeaderLength) == $modHeaderLength or die;
        my($title) = unpack($modHeaderFormat, $header);
        ($title) = $decode->($title);

        # Do basic validation
        # die unless $ec eq "???";  # This is really a lie.

        # Store data
        $self->{mod}{valid}  = 1;
        ($self->{mod}{title} = $title)  =~ s/^\s+|\s+$//g;
    };

    return bless $self;
}

# Simple interface functions
sub isValidModFile { return $_[0]->{mod}{valid} }
sub title { return $_[0]->{mod}{title} }


1;
