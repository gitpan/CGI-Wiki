use Test::More tests => 1;
use CGI::Wiki;
use CGI::Wiki::TestConfig;

# Note - this test will raise warnings about the test database not being
# open at cleanup.  This is a known problem which shouldn't affect normal use.

my $testing = $CGI::Wiki::TestConfig::config{search_invertedindex};

if ($testing) {
    require CGI::Wiki::Setup::SII;
    require CGI::Wiki::Store::MySQL;

    my %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    my ($dbname, $dbuser, $dbpass) = @config{qw(dbname dbuser dbpass)};
    my $indexdb = Search::InvertedIndex::DB::Mysql->new(
                   -db_name    => $dbname,
                   -username   => $dbuser,
                   -password   => $dbpass,
		   -hostname   => '',
                   -table_name => 'siindex',
                   -lock_mode  => 'EX' );

    my $store = CGI::Wiki::Store::MySQL->new( dbname => $dbname,
					      dbuser => $dbuser,
					      dbpass => $dbpass );

    CGI::Wiki::Setup::SII::setup( indexdb => $indexdb, store => $store );
}

SKIP: {
    skip "Not testing Search::InvertedIndex backend", 1 unless $testing;
    pass("Search::InvertedIndex test backend set up successfully");
}

