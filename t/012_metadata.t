use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (14 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 14
            unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $wiki = CGI::Wiki->new( store => $store );
        isa_ok( $wiki, "CGI::Wiki" );

        $wiki->write_node( "Reun Thai", "A restaurant", undef,
            { postcode => "W6 9PL",
              category => [ "Thai Food", "Restaurant", "Hammersmith" ] } );
        my %node = $wiki->retrieve_node( "Reun Thai" );
        my $data = $node{metadata}{postcode};
        is( ref $data, "ARRAY", "arrayref always returned" );
        is( $node{metadata}{postcode}[0], "W6 9PL",
	    "...simple metadata retrieved" );
        my $cats = $node{metadata}{category};
        is_deeply( [ sort @{$cats||[]} ],
		   [ "Hammersmith", "Restaurant", "Thai Food" ],
		   "...more complex metadata too" );

        #### Test list_nodes_by_metadata.
        $wiki->write_node( "The Old Trout", "A pub", undef,
	    { category => [ "Pub", "Hammersmith" ] } );
	my @nodes = $wiki->list_nodes_by_metadata(
            metadata_type  => "category",
            metadata_value => "Hammersmith" );
        is_deeply( [ sort @nodes ], [ "Reun Thai", "The Old Trout" ],
		   "list_nodes_by_metadata returns everything it should" );
        $wiki->write_node( "The Three Cups", "Another pub", undef,
			   { category => "Pub" } );
        @nodes = $wiki->list_nodes_by_metadata( metadata_type  => "category",
                                    metadata_value => "Pub" );
        is_deeply( [ sort @nodes ], [ "The Old Trout", "The Three Cups" ],
		   "...and not things it shouldn't" );

        # Case insensitivity option.
        @nodes = $wiki->list_nodes_by_metadata(
            metadata_type  => "category",
            metadata_value => "hammersmith",
            ignore_case    => 1,
        );
        is_deeply( [ sort @nodes ], [ "Reun Thai", "The Old Trout" ],
                   "ignore_case => 1 ignores case of metadata_value" );
        @nodes = $wiki->list_nodes_by_metadata(
            metadata_type  => "Category",
            metadata_value => "Hammersmith",
            ignore_case    => 1,
        );
        is_deeply( [ sort @nodes ], [ "Reun Thai", "The Old Trout" ],
                   "...and case of metadata_type" );

        %node = $wiki->retrieve_node("The Three Cups");
        $wiki->write_node( "The Three Cups", "Not a pub any more",
			   $node{checksum} );
        @nodes = $wiki->list_nodes_by_metadata( metadata_type  => "category",
                                    metadata_value => "Pub" );
        is_deeply( [ sort @nodes ], [ "The Old Trout" ],
	   "removing metadata from a node stops it showing up in list_nodes_by_metadata" );

        $wiki->delete_node("Reun Thai");
        @nodes = $wiki->list_nodes_by_metadata( metadata_type  => "category",
                                    metadata_value => "Hammersmith" );
        is_deeply( [ sort @nodes ], [ "The Old Trout" ],
		   "...as does deleting a node" );

        # Test checksumming.
	%node = $wiki->retrieve_node("The Three Cups");
        ok( $wiki->write_node( "The Three Cups", "Not a pub any more",
			   $node{checksum}, { newdata => "foo" } ),
	    "writing node with metadata succeeds when checksum fresh" );
	ok( !$wiki->write_node( "The Three Cups", "Not a pub any more",
			   $node{checksum}, { newdata => "bar" } ),
	    "writing node with identical content but different metadata fails when checksum not updated" );

        # Test with duplicate metadata.
        $wiki->write_node( "Dupe Test", "test", undef,
			   { foo => [ "bar", "bar" ] } );
        %node = $wiki->retrieve_node( "Dupe Test" );
        is( scalar @{$node{metadata}{foo}}, 1,
	    "duplicate metadata only written once" );

        # Test version is updated when metadata is removed.
        $wiki->write_node( "Dupe Test", "test", $node{checksum} );
        %node = $wiki->retrieve_node( "Dupe Test" );
        is( $node{version}, 2, "version updated when metadata removed" );

        # Clean up
	foreach my $node ( "Reun Thai", "The Old Trout", "The Three Cups",
			   "Dupe Test" ) {
	    $wiki->delete_node($node) or die "Can't cleanup";
	}
    }
}
