use strict;
use CGI::Wiki;
use CGI::Wiki::Store::Pg;
use CGI::Wiki::TestConfig;
BEGIN {
    require Test::More;
    Test::More->import(
        skip_all => "No Postgres database configured for testing" )
      unless $CGI::Wiki::TestConfig::config{Pg}{dbname};
}
use Test::More tests => 7;
use Hook::LexWrap;
use Test::MockObject;

my $class;
BEGIN {
    $class = "CGI::Wiki::Store::Pg";
    use_ok($class);
}

eval { $class->new; };
ok( $@, "Failed creation dies" );

my %config = %{$CGI::Wiki::TestConfig::config{Pg}};
my ($dbname, $dbuser, $dbpass) = @config{qw(dbname dbuser dbpass)};

my $store = eval { $class->new( dbname => $dbname,
                                dbuser => $dbuser,
                                dbpass => $dbpass,
                                checksum_method => \&md5_hex );

                 };
is( $@, "", "Creation succeeds" );
isa_ok( $store, $class );
ok( $store->dbh, "...and has set up a database handle" );

my $wiki = CGI::Wiki->new( dbname => $dbname,
                           dbuser => $dbuser,
                           dbpass => $dbpass,
                           storage_backend => "postgres" );

# White box testing - override verify_node_checksum to first verify the
# checksum and then if it's OK set up a new wiki object that sneakily
# writes to the node before letting us have control back.

my $temp;
$temp = wrap CGI::Wiki::Store::Database::verify_checksum,
    post => sub {
        undef $temp; # Don't want to wrap our sneaking-in
        my $node = $_[1];
        my $evil_wiki = CGI::Wiki->new( dbname => $dbname,
                                        dbuser => $dbuser,
                                        dbpass => $dbpass,
                                        storage_backend => "postgres" );
        my ($content, $checksum) =
            $evil_wiki->retrieve_node_and_checksum($node);
        $evil_wiki->write_node($node, "foo", $checksum)
            or die "Evil wiki got conflict on writing";
    };

# Now try to write to a node -- it should fail.
my ($content, $checksum) = $wiki->retrieve_node_and_checksum("Home");
ok( ! $wiki->write_node("Home", "bar", $checksum),
    "write_node handles overlapping write attempts correctly" );

# Cleanup
($content, $checksum) = $wiki->retrieve_node_and_checksum("Home");
$wiki->write_node("Home", "This is the home node.", $checksum)
    or die "Couldn't cleanup";

# Check actual real database errors croak rather than flagging conflict.
($content, $checksum) = $wiki->retrieve_node_and_checksum("Node1");
my $dbh = $store->dbh;
$dbh->disconnect;
# Mock a database handle.  Need to mock rollback() and disconnect()
# as well to avoid warnings that an unmocked method has been called
# (we don't actually care).
my $fake_dbh = Test::MockObject->new();
$fake_dbh->mock("do", sub { die "Dave told us to"; });
$fake_dbh->set_true("rollback");
$fake_dbh->set_true("disconnect");
$store->{_dbh} = $fake_dbh;
eval {
    $store->check_and_write_node( node     => "Node1",
				  content  => "This is Node1.",
				  checksum => $checksum );
};
ok( $@ =~ /Dave told us to/, "...and croaks on database error" );

