use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (2 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
	my $num_tests = 2;
	skip "$store_name storage backend not configured for testing",
	  $num_tests
	    unless $store;
	my $dbh = eval { $store->dbh; };
	skip "Test not implemented for non-database stores",
	  $num_tests
	    unless $dbh;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $wiki = CGI::Wiki->new( store => $store );
        isa_ok( $wiki, "CGI::Wiki" );

        $wiki->write_node( "Deletion Test", "foo", undef,
                           { metadata => 1 } );
        $wiki->delete_node( "Deletion Test" );

        # White box testing.
        my $sql = "SELECT metadata_type, metadata_value FROM metadata
                   WHERE node='Deletion Test'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        my ( $type, $value ) = $sth->fetchrow_array;
        is_deeply( [ $type, $value ], [undef, undef],
		   "deletion of a node removes the metadata too" );
    }
}

