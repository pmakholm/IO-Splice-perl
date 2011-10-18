#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'IO::Splice' ) || print "Bail out!\n";
}

diag( "Testing IO::Splice $IO::Splice::VERSION, Perl $], $^X" );
