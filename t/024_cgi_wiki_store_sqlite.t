use strict;
use CGI::Wiki;
use CGI::Wiki::Store::SQLite;
use CGI::Wiki::TestConfig;
BEGIN {
    require Test::More;
    Test::More->import(
        skip_all => "No SQLite database available for testing" )
      unless $CGI::Wiki::TestConfig::config{SQLite}{dbname};
}
use Test::More tests => 9;
use Hook::LexWrap;
use Test::MockObject;

my $class;
BEGIN {
    $class = "CGI::Wiki::Store::SQLite";
    use_ok($class);
}

eval { $class->new; };
ok( $@, "Failed creation dies" );

my %config = %{$CGI::Wiki::TestConfig::config{SQLite}};
my $dbname = $config{dbname};
my $store = eval { $class->new( dbname => $dbname );
                 };
is( $@, "", "Creation succeeds" );
isa_ok( $store, $class );
ok( $store->dbh, "...and has set up a database handle" );
ok( $store->can( "retrieve_node" ), "...the object can 'retrieve_node'" );
ok( defined $store->retrieve_node("Home"),
    "...and we can call 'retrieve_node' with a parameter" );

my $wiki = CGI::Wiki->new( store => $store );
die "Couldn't create wiki object" unless $wiki->isa( "CGI::Wiki" );

# White box testing - override verify_node_checksum to first verify the
# checksum and then if it's OK set up a new wiki object that sneakily
# writes to the node before letting us have control back.

my $temp;
$temp = wrap CGI::Wiki::Store::Database::verify_checksum,
    post => sub {
        undef $temp; # Don't want to wrap our sneaking-in
        my $node = $_[1];
        my $evil_store = $class->new( dbname => $dbname );
        my $evil_wiki = CGI::Wiki->new( store => $evil_store );
        my %node_data =
            $evil_wiki->retrieve_node($node);
        $evil_wiki->write_node($node, "foo", $node_data{checksum})
            or die "Evil wiki got conflict on writing";
    };

# Now try to write to a node -- it should fail.
my %node_data = $wiki->retrieve_node("Home");
ok( ! $wiki->write_node("Home", "bar", $node_data{checksum}),
    "write_node handles overlapping write attempts correctly" );

# Cleanup
%node_data = $wiki->retrieve_node("Home");
$wiki->write_node("Home", "This is the home node.", $node_data{checksum})
    or die "Couldn't cleanup";

# Check actual real database errors croak rather than flagging conflict.
%node_data = $wiki->retrieve_node("Node1");
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
				  checksum => $node_data{checksum} );
};
ok( $@ =~ /Dave told us to/, "...and croaks on database error" );
