#!/usr/bin/perl

use v5.10.1;
use strict;
use warnings;

use IO::Splice;
use IO::Select;
use IO::Socket::INET;

use Socket;

my $listen = IO::Socket::INET->new(
    Proto     => "tcp",
    LocalPort => shift // 5050,
    Listen    => 5,
    ReuseAddr => 1,
    Blocking  => 0,
);

sub handshake {
    my $fh = shift;
    my $buffer;

    $fh->sysread($buffer, 1024, 0);
    my ($version, $command, $port, $ip, $user, $rest) = unpack("CCnNZ*a*", $buffer);

    if ( $version == 0x04 && $command == 0x01 ) {
        socket(my $endpoint, PF_INET, SOCK_STREAM, getprotobyname("tcp")) or goto ERROR;
        connect($endpoint, sockaddr_in( $port, pack("N", $ip))) or goto ERROR;

        $fh->syswrite( pack("xcxxxxxx", 0x5a) );
        $endpoint->syswrite($rest);
        
        return $endpoint;
    }

    ERROR:
    $fh->syswrite( pack("xcxxxxxx", 0x5b) );
    return;
}

# Setup select loop
my $readers = IO::Select->new($listen);
my $writers = IO::Select->new();
my %splices;

while( my @ready = IO::Select->select( $readers, $writers, undef) ) {
    for my $fh (@{$ready[0]}) {
        if ($fh == $listen) {
            my $newfh = $listen->accept();

            my $endpoint = handshake( $newfh )
                or next;

            $splices{$newfh} = $splices{$endpoint} = IO::Splice->new(
                $newfh, $endpoint,
                will_write => sub { $writers->add( shift ) },
                wont_write => sub { $writers->remove( shift ) },
                close      => sub { close($_[0]); $readers->remove($_[0]) },
            );

            $readers->add( $newfh, $endpoint );
        } else {
            $splices{$fh}->read($fh);
        }
    }

    $splices{$_}->write( $_ ) for @{$ready[1]};
}


