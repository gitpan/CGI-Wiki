use Test::More tests => 1;
use CGI::Wiki;
use CGI::Wiki::TestConfig;

# Note - this test will raise warnings about the test database not being
# open at cleanup.  This is a known problem which shouldn't affect normal use.

my $sii_configured = $CGI::Wiki::TestConfig::config{search_invertedindex};

# We can use any of the stores to *set up* the indexes, since it's indexed on
# node name, and the test data is the same in all test backends.
my ($no_store, %store_config);
if ($CGI::Wiki::TestConfig::config{MySQL}->{dbname}) {
    %store_config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    $store_config{store_class} = "CGI::Wiki::Store::MySQL";
} elsif ($CGI::Wiki::TestConfig::config{Pg}->{dbname}) {
    %store_config = %{$CGI::Wiki::TestConfig::config{Pg}};
    $store_config{store_class} = "CGI::Wiki::Store::Pg";
} elsif ($CGI::Wiki::TestConfig::config{SQLite}->{dbname}) {
    %store_config = %{$CGI::Wiki::TestConfig::config{SQLite}};
    $store_config{store_class} = "CGI::Wiki::Store::SQLite";
} else {
    $no_store = 1;
}

my $testing = $sii_configured && (!$no_store);

if ($testing) {
    require CGI::Wiki::Setup::SII;

    my $indexdb = Search::InvertedIndex::DB::DB_File_SplitHash->new(
                   -map_name  => 't/sii-db-file-test.db',
                   -lock_mode => 'EX' );

    my $store_class = $store_config{store_class};
    eval "require $store_class";
    my $store = $store_class->new( dbname => $store_config{dbname},
				   dbuser => $store_config{dbuser},
				   dbpass => $store_config{dbpass},
				   dbhost => $store_config{dbhost},
                                 );

    CGI::Wiki::Setup::SII::setup( indexdb => $indexdb, store => $store );
}

SKIP: {
    skip "Not testing Search::InvertedIndex/DB_File backend", 1 unless $testing;
    pass("Search::InvertedIndex/DB_File test backend set up successfully");
}

