use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (4 * $CGI::Wiki::TestConfig::Utilities::num_combinations);

my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_name, $store, $search_name, $search, $configured ) =
        @testconfig{qw(store_name store search_name search configured)};

    SKIP: {
        skip "Store $store_name and search $search_name"
	   . " not configured for testing", 4 unless $configured;

        print "#####\n##### Test config: STORE: $store_name, SEARCH: "
	   . $search_name . "\n#####\n";

        my $wiki = CGI::Wiki->new( store  => $store,
                                   search => $search );

        eval {
            $wiki->write_node( "015 Test 1", undef, undef );
        };
        ok( $@, "->write_node dies if undef content and metadata supplied" );

        eval {
            $wiki->write_node( "015 Test 1", "", undef );
        };
        is( $@, "", "...but not if blank content and undef metadata supplied");

        eval {
            $wiki->write_node( "015 Test 2", "foo", undef );
        };
        is( $@, "", "...and not if just content defined" );

        eval {
            $wiki->write_node( "015 Test 3", "", undef, { category => "Foo" });
        };
        is( $@, "", "...and not if just metadata defined" );

        # Cleanup
        $wiki->delete_node( "015 Test 1" ) or die "couldn't cleanup";
        $wiki->delete_node( "015 Test 2" ) or die "couldn't cleanup";
        $wiki->delete_node( "015 Test 3" ) or die "couldn't cleanup";
    }
}

