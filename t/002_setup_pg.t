use Test::More tests => 1;
use CGI::Wiki::TestConfig;
use CGI::Wiki::Setup::Pg;
use DBI;

my %config = %{$CGI::Wiki::TestConfig::config{Pg}};
my $testing = $config{dbname};

if ($testing) {
    my ($dbname, $dbuser, $dbpass) = @config{qw(dbname dbuser dbpass)};

    # Set up the tables in the test database.
    CGI::Wiki::Setup::Pg::setup($dbname, $dbuser, $dbpass);

    # Put in the test data.
    my $dbh = DBI->connect("dbi:Pg:dbname=$dbname", $dbuser, $dbpass,
                       { PrintError => 1, RaiseError => 1, AutoCommit => 1 } )
        or die "Couldn't connect to database: " . DBI->errstr;
    while (my $sql = <DATA>) {
        $dbh->do($sql) or die $dbh->errstr;
    }
    $dbh->disconnect;
}

SKIP: {
    skip "Not testing Postgres backend", 1 unless $testing;
    pass("Postgres test backend set up successfully");
}

__DATA__
INSERT INTO node VALUES ('Home',1,'This is the home node.','2002-10-22 10:54:17')
INSERT INTO node VALUES ('Node1',1,'This is Node1.','2001-07-09 15:13:22')
INSERT INTO node VALUES ('Another Node',1,'This node exists solely to contain the word \"home\".','2002-10-22 10:56:05')
INSERT INTO node VALUES ('Everyone\'s Favourite Hobby',1,'Performing expert wombat defenestration.','1999-11-05 06:06:06')
INSERT INTO node VALUES ('001 Defenestration',1,'Expert advice for all your defenestration needs!','2002-03-25 10:16:23')
INSERT INTO content VALUES ('Home',1,'This is the home node.','2002-10-22 10:54:17','')
INSERT INTO content VALUES ('Node1',1,'This is Node1.','2001-07-09 15:13:22','')
INSERT INTO content VALUES ('Another Node',1,'This node exists solely to contain the word \"home\".','2002-10-22 10:56:05','')
INSERT INTO content VALUES ('Everyone\'s Favourite Hobby',1,'Performing expert wombat defenestration.','1999-11-05 06:06:06','')
INSERT INTO content VALUES ('001 Defenestration',1,'Expert advice for all your defenestration needs!','2002-03-25 10:16:23','')
