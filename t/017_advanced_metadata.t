use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (7 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 7
            unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $wiki = CGI::Wiki->new( store => $store );
        isa_ok( $wiki, "CGI::Wiki" );

        $wiki->write_node( "Hammersmith Station", "a station", undef,
                           { tube_data =>
                             { line => "Piccadilly",
                               direction => "Eastbound",
                               next_station => "Baron's Court Station"
                             }
                           }
                        );

        my %node_data = $wiki->retrieve_node( "Hammersmith Station" );
        my %metadata  = %{ $node_data{metadata} || {} };
        ok( !defined $metadata{tube_data},
            "hashref metadata not stored directly" );
        ok( defined $metadata{__tube_data__checksum},
            "checksum stored instead" );

        ok( $wiki->write_node( "Hammersmith Station", "a station",
                               $node_data{checksum},
                               { tube_data => [
                                 { line => "Piccadilly",
                                   direction => "Eastbound",
                                   next_station => "Baron's Court Station"
                                 },
                                 { line => "Piccadilly",
                                   direction => "Westbound",
                                   next_station => "Acton Town Station"
                                 }
                                            ]
                              }
                            ),
            "writing node with metadata succeeds when node checksum fresh" );

        ok( !$wiki->write_node( "Hammersmith Station", "a station",
                               $node_data{checksum},
                               { tube_data => [
                                 { line => "Piccadilly",
                                   direction => "Eastbound",
                                   next_station => "Baron's Court Station"
                                 },
                                 { line => "Piccadilly",
                                   direction => "Westbound",
                                   next_station => "Acton Town Station"
                                 }
                                               ]
                                 }
                               ),
           "...but fails when node checksum old and hashref metadata changed");

        # Make sure that order doesn't matter in the arrayrefs.
        %node_data = $wiki->retrieve_node( "Hammersmith Station" );
        $wiki->write_node( "Hammersmith Station", "a station",
                           $node_data{checksum},
                           { tube_data => [
                             { line => "Piccadilly",
                               direction => "Westbound",
                               next_station => "Acton Town Station"
                             },
                             { line => "Piccadilly",
                               direction => "Eastbound",
                               next_station => "Baron's Court Station"
                             },
                                           ]
                            }
                          ) or die "Couldn't write node";
        ok( $wiki->verify_checksum("Hammersmith Station",$node_data{checksum}),
            "order within arrayrefs doesn't affect checksum" );

        my %node_data_check = $wiki->retrieve_node( "Hammersmith Station" );
        my %metadata_check  = %{ $node_data_check{metadata} || {} };
        is( scalar @{ $metadata_check{__tube_data__checksum} }, 1,
            "metadata checksum only written once even if multiple entries" );

        # Clean up
	foreach my $node ( "Hammersmith Station" ) {
	    $wiki->delete_node($node) or die "Can't cleanup";
	}
    }
}