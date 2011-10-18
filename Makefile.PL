use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'IO::Splice',
    AUTHOR              => q{Peter Makholm <peter@makholm.net>},
    VERSION_FROM        => 'lib/IO/Splice.pm',
    ABSTRACT_FROM       => 'lib/IO/Splice.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'IO-Splice-*' },
);
