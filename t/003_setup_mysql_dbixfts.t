use Test::More tests => 1;
use CGI::Wiki::TestConfig;
use DBI;

my $testing = $CGI::Wiki::TestConfig::config{dbixfts};

if ($testing) {
    require DBIx::FullTextSearch;
    my %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    my ($dbname, $dbuser, $dbpass) = @config{qw(dbname dbuser dbpass)};
    my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
                       { PrintError => 1, RaiseError => 1, AutoCommit => 1 } )
        or die "Couldn't connect to database: " . DBI->errstr;

    # Drop FTS indexes if they already exist.
    my $fts = DBIx::FullTextSearch->open($dbh, "_content_and_title_fts");
    $fts->drop if $fts;
    $fts = DBIx::FullTextSearch->open($dbh, "_title_fts");
    $fts->drop if $fts;

    # Set up FullText indexes and index anything already extant.
    my $fts_all = DBIx::FullTextSearch->create($dbh, "_content_and_title_fts",
    					   frontend       => "table",
    					   backend        => "phrase",
    					   table_name     => "node",
    					   column_name    => ["name","text"],
    					   column_id_name => "name",
    					   stemmer        => "en-uk");

    my $fts_title = DBIx::FullTextSearch->create($dbh, "_title_fts",
    					      frontend       => "table",
    					      backend        => "phrase",
    					      table_name     => "node",
    					      column_name    => "name",
    					      column_id_name => "name",
    					      stemmer        => "en-uk");

    my $sql = "SELECT name FROM node";
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    while (my ($name, $version) = $sth->fetchrow_array) {
        $fts_title->index_document($name);
        $fts_all->index_document($name);
    }
    $sth->finish;
    $dbh->disconnect;
}

SKIP: {
    skip "Not testing DBIx::FTS backend", 1 unless $testing;
    pass("DBIx::FTS test backend set up successfully");
}

