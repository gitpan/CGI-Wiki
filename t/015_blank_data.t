use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (7 * $CGI::Wiki::TestConfig::Utilities::num_combinations);

my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_name, $store, $search_name, $search, $configured ) =
        @testconfig{qw(store_name store search_name search configured)};

    SKIP: {
        skip "Store $store_name and search $search_name"
	   . " not configured for testing", 7 unless $configured;

        print "#####\n##### Test config: STORE: $store_name, SEARCH: "
	   . $search_name . "\n#####\n";

        my $wiki = CGI::Wiki->new( store  => $store,
                                   search => $search );

        # Test writing blank data.
        eval {
            $wiki->write_node( "015 Test 1", undef, undef );
        };
        ok( $@, "->write_node dies if undef content and metadata supplied" );

        eval {
            $wiki->write_node( "015 Test 2", "", undef );
        };
        is( $@, "", "...but not if blank content and undef metadata supplied");

        eval {
            $wiki->write_node( "015 Test 3", "foo", undef );
        };
        is( $@, "", "...and not if just content defined" );

        eval {
            $wiki->write_node( "015 Test 4", "", undef, { category => "Foo" });
        };
        is( $@, "", "...and not if just metadata defined" );

        # Test deleting nodes with blank data.
        eval {
            $wiki->delete_node( "015 Test 2");
        };
        is( $@, "", "->delete_node doesn't die when called on node with blank content and undef metadata" );
        eval {
            $wiki->delete_node( "015 Test 3");
        };
        is( $@, "", "...nor on node with only content defined" );
        eval {
            $wiki->delete_node( "015 Test 4");
        };
        is( $@, "", "...nor on node with only metadata defined" );
    }
}

