local $^W = 1;
use strict;
use Test::More tests => 36;
use CGI::Wiki;
use CGI::Wiki::TestConfig;

# Test for each configured storage backend.
my %config = %CGI::Wiki::TestConfig::config;
# This way of doing it is probably really ugly, but better that than
# sitting here agonising for ever.
my @tests;
push @tests, { store  => "CGI::Wiki::Store::MySQL",
	       config => $config{MySQL},
	       do     => ( $config{MySQL}{dbname} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::Pg",
	       config => $config{Pg},
	       do     => ( $config{Pg}{dbname} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::SQLite",
	       config => $config{SQLite},
	       do     => ( $config{SQLite}{dbname} ? 1 : 0 ) };

foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my $store_class = $testconfig{store};
    SKIP: {
        skip "Store $store_class"
	   . " not configured for testing", 12 unless $testconfig{do};

        print "#####\n##### Test config: STORE: $store_class\n#####\n";

	##### Grab working db/user/pass.
	my $dbname = $testconfig{config}{dbname};
	my $dbuser = $testconfig{config}{dbuser};
	my $dbpass = $testconfig{config}{dbpass};

	eval "require $store_class";
	my $store = $store_class->new( dbname => $dbname,
				       dbuser => $dbuser,
				       dbpass => $dbpass )
	  or die "Couldn't set up test store";

        my $wiki = CGI::Wiki->new( store => $store );
        isa_ok( $wiki, "CGI::Wiki" );

        ####  Here's the start of the real tests.
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
        $wiki->write_node( "The Old Trout", "A pub", undef,
	    { category => [ "Pub", "Hammersmith" ] } );
	my @nodes = $wiki->list_nodes_by_metadata( metadata_type  => "category",
                                       metadata_value => "Hammersmith" );
        is_deeply( [ sort @nodes ], [ "Reun Thai", "The Old Trout" ],
		   "list_nodes_by_metadata returns everything it should" );
        $wiki->write_node( "The Three Cups", "Another pub", undef,
			   { category => "Pub" } );
        @nodes = $wiki->list_nodes_by_metadata( metadata_type  => "category",
                                    metadata_value => "Pub" );
        is_deeply( [ sort @nodes ], [ "The Old Trout", "The Three Cups" ],
		   "...and not things it shouldn't" );

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

    }
}
