use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME                => 'BadBoids',
    AUTHOR              => q{YOUR NAME <youremail@example.com>},
    VERSION_FROM        => 'lib/BadBoids.pm',
    ABSTRACT            => 'YOUR APPLICATION ABSTRACT',
    ($eumm_version >= 6.3001
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'Dancer'     => 1.3115,
	'Dancer::Template::Caribou' => 0,
	'Dancer::Plugin::Auth::Twitter' => 0,
	'Dancer::Plugin::Auth::Extensible' => 0,
	map { $_ => 0 } qw/
		DateTime::Duration::Fuzzy
		DateTime::Format::Human::Duration
		Dancer::Session::YAML
	/
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Twisters-*' },
);
