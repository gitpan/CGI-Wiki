use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (5 * $CGI::Wiki::TestConfig::Utilities::num_combinations);

my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_name, $store, $search_name, $search, $configured ) =
        @testconfig{qw(store_name store search_name search configured)};

    SKIP: {
        my $num_tests = 5;
        skip "Store $store_name and search $search_name"
	   . " not configured for testing", $num_tests unless $configured;

        skip "No search backend in this combination",
           $num_tests
             unless $search;

        skip "Search backend $search_name doesn't support fuzzy searching",
           $num_tests
             unless $search->can("fuzzy_title_match");

        print "#####\n##### Test config: STORE: $store_name, SEARCH: "
	   . $search_name . "\n#####\n";

        my $wiki = CGI::Wiki->new( store  => $store,
                                   search => $search );

        # Fuzzy match with differing punctuation.
        $wiki->write_node( "King's Cross St Pancras", "station" )
          or die "Can't write node";

        my %finds = $search->fuzzy_title_match("Kings Cross St. Pancras");
        is_deeply( [ keys %finds ], [ "King's Cross St Pancras" ],
                   "fuzzy_title_match works when punctuation differs" );

        # Fuzzy match when we actually got the string right.
        $wiki->write_node( "Potato", "A delicious vegetable" )
          or die "Can't write node";
        $wiki->write_node( "Patty", "A kind of burger type thing" )
          or die "Can't write node";
        %finds = $search->fuzzy_title_match("Potato");
        is_deeply( [ sort keys %finds ], [ "Patty", "Potato" ],
                   "...returns all things found" );
        ok( $finds{Potato} > $finds{Patty},
            "...and exact match has highest relevance score" );

        # Now try matching indirectly, through the wiki object.
        %finds = eval {
            $wiki->fuzzy_title_match("kings cross st pancras");
        };
        is( $@, "", "fuzzy_title_match works when called on wiki object" ); 
        is_deeply( [ keys %finds ], [ "King's Cross St Pancras" ],
                   "...and returns the right thing" );

        # Cleanup
        foreach my $node ( "King's Cross St Pancras", "Potato",
                           "Patty" ) {
            $wiki->delete_node( $node ) or die "Couldn't cleanup $node";
        }
    }
}

