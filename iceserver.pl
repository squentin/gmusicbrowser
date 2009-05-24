#!/usr/bin/perl
# Copyright (C) 2005-2006 Quentin Sculo <squentin@free.fr>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;
use Socket;
use constant { EOL => "\015\012" };
my ($file,$sec,$title);
my $port=8000;
while (my $arg=shift)
{	if    ($arg eq '-p') {$port=shift||8000}
	elsif ($arg eq '-b') {shift}
	elsif ($arg eq '-K') {$sec='-k '.shift}
	elsif ($arg eq '-title') {$title=shift}
	elsif (-f $arg) {$file=$arg}
}

$title||=$file;
my $mime='audio/x-unknown';  #FIXME
if	($file=~m/mp3$/i) { $mime='audio/mpeg'; }
elsif	($file=~m/ogg$|oga$/i) { $mime='application/ogg'; }
elsif	($file=~m/flac$/i) { $mime='audio/x-flac'; }
elsif	($file=~m/mpc$/i) { $mime='audio/x-musepack'; }

sub logmsg { print "$0 $$: @_ at ", scalar localtime, "\n" }

my $proto = getprotobyname('tcp');
($port) = $port =~ /^(\d+)$/			or die "invalid port";
socket(Server, PF_INET, SOCK_STREAM, $proto)	|| die "socket: $!";
setsockopt(Server, SOL_SOCKET, SO_REUSEADDR,
				pack('l', 1))	|| die "setsockopt: $!";
bind(Server, sockaddr_in($port, INADDR_ANY))	|| die "bind: $!";
listen(Server,SOMAXCONN)			|| die "listen: $!";
logmsg "server started on port $port";

my $paddr = accept(Client,Server);
my($port2,$iaddr) = sockaddr_in($paddr);
#my $name = gethostbyaddr($iaddr,AF_INET);
logmsg 'connection from ',inet_ntoa($iaddr), " at port $port2";

#shoutcast and icecast protocol :
# http://sander.vanzoest.com/talks/2002/audio_and_apache/
while (<Client>)
{	#warn $_;
	last if $_ eq EOL;
}
my $answer=
	'HTTP/1.0 200 OK'.EOL.
	'Server: iceserver/0.2'.EOL.
	"Content-Type: $mime".EOL.
	"x-audiocast-name: $title".EOL.
	'x-audiocast-public: 0'.EOL;
send Client,$answer.EOL,0;
#warn $answer;
open FILE,$file;
while (read FILE,$_,16384)
{	send Client,$_,0;
}
close Client;
exit;


