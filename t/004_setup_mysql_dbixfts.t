use Test::More tests => 1;
use CGI::Wiki::TestConfig;
use DBI;

my $testing = $CGI::Wiki::TestConfig::config{dbixfts};

if ($testing) {
    require CGI::Wiki::Setup::DBIxFTSMySQL;
    my %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    my ($dbname, $dbuser, $dbpass, $dbhost) =
                                     @config{qw(dbname dbuser dbpass dbhost)};
    CGI::Wiki::Setup::DBIxFTSMySQL::setup($dbname, $dbuser, $dbpass, $dbhost);
}

SKIP: {
    skip "Not testing DBIx::FTS backend", 1 unless $testing;
    pass("DBIx::FTS test backend set up successfully");
}

