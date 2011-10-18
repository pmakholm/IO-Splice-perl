package IO::Splice;

use v5.10.0;
use strict;
use warnings;

use Carp;
use IO::Handle;
use Errno qw(EAGAIN EINTR);

our $VERSION = '0.01';

=head1 NAME

IO::Splice - pass data between two IO handles

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use IO::Splice;

    my $readers  = IO::Select->new($fh1, $fh2);
    my $writers  = IO::Select->new();
    my $splicing = IO::Splice->new(
        $fh1, $fh2, 
        will_write => sub { $writers->add( shift ) },
        wont_write => sub { $writers->remove( shift ) },
    );

    while( my @read = IO::Select->select( $readers, $writers, undef) ) {
        # Either just pump...
        $splicing->pump();

        # Or explicitly call read and write
        $splicing->read( $_ )  for @$ready[0];
        $splicing->write( $_ ) for @$ready[1];

    }

=head1 CONSTRUCTOR

=over 4

=item new( HANDLE, HANDLE, [ ARGS ] )

The constructor takes two IO handles as parameters followed by a number of
optional named parameters:

=over 4

=item block_size => <integer>

Block size of read and write calls. Default is to use 4K blocks

=item buffer_size => <interger>

The maximal size of buffers used, this should be at least twice the buffer
size. Note that a splicing needs two buffers, one for each direction. Default
it to use an unlimited buffer size.

=item will_write => <callback>

Callback used when the splicing needs to write to a IO handle. Will be called
with the handle as the first parameter.

=item wont_write => <callback>

Callback used when the splicing is done writing to a IO handle. Will be called
with the handle as the first parameter.

=item will_read => <callback>

Callback used when the splicing needs to read from a IO handle. Will be called
with the handle as the first parameter. This is never called unless the buffer
size is limited.

=item wont_read => <callback>

Callback used when the splicing is done reading from a IO handle. Will be called
with the handle as the first parameter. This is never called unless the buffer
size is limited.

=item shutdown => <callback>

Callback used to notify that the splicing is closing in one direction. Will be
called with two arguments: The first is a IO handle and the second is the direction.

Roughly equivalent to L<shutdown>. Default to call shutdown() on the handle.

=item close => <callback>

Callbac to notify user that the splicing is closing in both directions. Will
be called with the socket as only argument.

Default is to call close() on the socekt.

=back

=back

=cut

sub new {
    my ($class, $fh1, $fh2, %args) = @_;
    
    croak( "back splicing is not supported" ) if $fh1 == $fh2;

    my $self = {
        fh1 => $fh1,
        fh2 => $fh2,
        forward  => "", # Buffer going $fh1 => $fh2 
        backward => "", # Buffer going $fh1 <= $fh2

        will_write => $args{will_write} // sub { },
        wont_write => $args{wont_write} // sub { },
        will_read  => $args{will_read}  // sub { },
        wont_read  => $args{wont_read}  // sub { },

        shutdown   => $args{shutdown} // sub { shutdown( shift, shift ) },
        close      => $args{close}    // sub { close( shift ) },

        block_size  => $args{block_size}  // 4096,
        buffer_size => $args{buffer_size},

        state       => { $fh1 => "open", $fh2 => "open" },
    };

    croak( "buffer_size should be at least twice the block_size" ) if defined( $self->{buffer_size} )
                                                                   && $self->{buffer_size} <= 2 * $self->{block_size};


    # For the actual buffer size management we use it as soft limit always allowing one extra block
    $self->{buffer_size} -= $self->{block_size} if defined( $self->{buffer_size} );

    bless $self, $class;
}

=head1 METHODS

=over 4

=item pump() 

Moves all available data

=cut

sub pump {
    my ($self) = @_;


}

=item read( HANDLE )

Reads data from handle into buffer

=cut

sub read {
    my ($self, $fh) = @_;
    croak( "Unknown handle" ) unless $fh == $self->{fh1} || $fh == $self->{fh2};

    croak( "Reading from read closed handle" ) if $self->{state}->{$fh} eq "closed"
                                               || $self->{state}->{$fh} eq "read closed";

    my $endpoint = ( $fh == $self->{fh1} ? $self->{fh2} : $self->{fh1} );
    my $buffer   = ( $fh == $self->{fh1} ? \$self->{forward} : \$self->{backward} );
    my $buflen   = length( $$buffer );
    my $bytes    = $fh->sysread( $$buffer, $self->{block_size}, $buflen );


    $self->{will_write}->($endpoint) if $buflen == 0
                                     && $bytes > 0;

    $self->{wont_read}->($fh) if defined( $self->{buffer_size} )
                              && length( $$buffer ) > $self->{buffer_size};


    if (defined($bytes) && $bytes == 0) {
        $self->{wont_read}->($fh);
        $self->{shutdown}->($fh, 0);
        $self->{state}->{$fh} = ( $self->{state}->{$fh} eq "open" ? "read closed" : "closed" );

        $self->{close}->($fh) if $self->{state}->{$fh} eq "closed";
    }

    return $bytes; 
}

=item write( HANDLE )

Writes data from buffer to handle

=cut

sub write {
    my ($self, $fh) = @_;
    croak( "Unknown handle" ) unless $fh == $self->{fh1} || $fh == $self->{fh2};

    croak( "Writing to write closed handle" ) if $self->{state}->{$fh} eq "closed"
                                              || $self->{state}->{$fh} eq "write closed";

    my $endpoint = ( $fh == $self->{fh1} ? $self->{fh2} : $self->{fh1} );
    my $buffer   = ( $fh == $self->{fh1} ? \$self->{backward} : \$self->{forward} );
    my $bytes    = $fh->syswrite( $$buffer, $self->{block_size} );

    # Handle write errors
    my $errno = $!;
    if (!defined($bytes) && $errno != EAGAIN && $errno != EINTR) {
        # Stop reading more data:
        $self->{wont_read}->($fh);
        $self->{shutdown}->($endpoint, 0);
        $self->{state}->{$endpoint} = ( $self->{endpoint}->{$fh} eq "open" ? "read closed" : "closed" );
                
        $self->{close}->($endpoint) if $self->{state}->{$endpoint} eq "closed";

        # Stop writing more data:
        $$buffer = "";
        $self->{wont_write}->($fh);
        $self->{shutdown}->($fh, 1);
        $self->{state}->{$fh} = ( $self->{state}->{$fh} eq "open" ? "write closed" : "closed" );
        
        $self->{close}->($fh) if $self->{state}->{$fh} eq "closed";
    }

    # Remove written bytes from buffer
    substr($$buffer, 0, $bytes, ""); 

    my $buflen = length( $$buffer );

    $self->{wont_write}->($fh) if $buflen == 0;

    $self->{will_read}->($endpoint) if defined( $self->{buffer_size} )
                                    && $buflen < $self->{buffer_size};

    if ( $buflen == 0 && $self->{state}->{$endpoint} eq "read closed"
                      || $self->{state}->{$endpoint} eq "closed" ) {

        $self->{wont_write}->($fh);
        $self->{shutdown}->($fh, 1);
        $self->{state}->{$fh} = ( $self->{state}->{$fh} eq "open" ? "write closed" : "closed" );
        
        $self->{close}->($fh) if $self->{state}->{$fh} eq "closed";
    }


    $! = $errno;
    return $bytes; 
}


=head1 AUTHOR

Peter Makholm, C<< <peter at makholm.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-io-splice at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IO-Splice>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IO::Splice


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IO-Splice>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IO-Splice>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IO-Splice>

=item * Search CPAN

L<http://search.cpan.org/dist/IO-Splice/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Peter Makholm.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of IO::Splice
