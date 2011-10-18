#!/usr/bin/perl

use v5.10.1;
use strict;
use warnings;

use IO::Splice;
use IO::Select;

# Find a socket pair to splice.
my $fh1 = \*STDIN;
my $fh2 = \*STDOUT;

# Setup select loop
my $readers = IO::Select->new($fh1, $fh2);
my $writers = IO::Select->new();

# Setup splicing
my $splicing = IO::Splice->new(
    $fh1, $fh2, 
    will_write => sub { $writers->add( shift ) },
    wont_write => sub { $writers->remove( shift ) },
    block_size => 512,
);

# Select loop
while( my @ready = IO::Select->select( $readers, $writers, undef) ) {
    $splicing->read( $_ )  for @{$ready[0]};
    $splicing->write( $_ ) for @{$ready[1]};
}

