use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (22*$CGI::Wiki::TestConfig::Utilities::num_combinations);

# Test for each configured pair: $store, $search.
my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_name, $store, $search_name, $search, $configured ) =
        @testconfig{qw(store_name store search_name search configured)};
    SKIP: {
        skip "Store $store_name and search $search_name"
	   . " not configured for testing", 22 unless $configured;

        print "#####\n##### Test config: STORE: $store_name, SEARCH: "
	   . $search_name . "\n#####\n";

        my $wiki = CGI::Wiki->new( store          => $store,
				   search         => $search,
				   extended_links => 1 );

	##### Test recent_changes.

        # Test by "in last n days".
	my $slept = sleep(2);
	warn "Slept for less than a second, 'in last n days' test may fail"
	  unless $slept >= 1;
        foreach my $node ("Node1", "Everyone's Favourite Hobby",
			  "Another Node") { # note the order
            my %node_data = $wiki->retrieve_node($node);
            $wiki->write_node($node, @node_data{ qw(content checksum) },
			      { comment => "Test" }
			     );
            my $slept = sleep(2);
            warn "Slept for less than a second, 'right order' test may fail"
              unless $slept >= 1;
	}

        my @nodes = $wiki->list_recent_changes( days => 1 );
        my @nodenames = map { $_->{name} } @nodes;
        my %unique = map { $_ => 1 } @nodenames;
        is_deeply( [sort keys %unique],
		   ["Another Node", "Everyone's Favourite Hobby", "Node1"],
		   "recent_changes for last 1 day gets the right results" );

        is( scalar @nodenames, 3,
            "...only once per node however many times changed" );

        is_deeply( \@nodenames,
		   ["Another Node", "Everyone's Favourite Hobby", "Node1"],
		   "...in the right order" ); # returns in reverse chron. order

        foreach my $node ( @nodes ) {
            is( ref $node->{metadata}{comment}, "ARRAY",
		"...metadata is returned as a hash of array refs" );
            my @comments = @{$node->{metadata}{comment}};
            is( $comments[0], "Test", "...correct metadata is returned" );
	}

        # Test by "last n nodes changed".
        @nodes = $wiki->list_recent_changes( last_n_changes => 2 );
        @nodenames = map { $_->{name} } @nodes;
        print "# Found nodes: " . join(" ", @nodenames) . "\n";
        is_deeply( \@nodenames,
		   ["Another Node", "Everyone's Favourite Hobby"],
                   "recent_changes 'last_n_changes' works" );
        eval { $wiki->list_recent_changes( last_n_changes => "foo" ); };
        ok( $@, "...and croaks on bad input" );

        # Test by "since time T".
        my $time = time;
	$slept = sleep(2);
	warn "Slept for less than a second, 'since' test may fail"
	  unless $slept >= 1;
        my %node_data = $wiki->retrieve_node("Node1");
	$wiki->write_node("Node1", @node_data{qw( content checksum )});
        @nodes = $wiki->list_recent_changes( since => $time );
	@nodenames = map { $_->{name} } @nodes;
        is_deeply( \@nodenames, ["Node1"],
		   "recent_changes 'since' returns the right results" );
        ok( $nodes[0]{last_modified},
	    "...and a plausible (not undef or empty) last_modified timestamp");

        # Test selecting by metadata.
	$slept = sleep(2);
	warn "Slept for less than a second, 'recent by metadata' test may fail"
	  unless $slept >= 1;
        %node_data = $wiki->retrieve_node("Node1");
	$wiki->write_node("Node1", @node_data{qw( content checksum )},
			  { username  => "Kake",
                            edit_type => "Minor tidying" } )
          or die "Couldn't write node";

        %node_data = $wiki->retrieve_node("Another Node");
	$wiki->write_node("Another Node", @node_data{qw( content checksum )},
			  { username => "nou" } )
          or die "Couldn't write node";

        # Test metadata_is. (We only actually expect a single result.)
        @nodes = $wiki->list_recent_changes(
            last_n_changes => 2,
	    metadata_is    => { username => "Kake" }
        );
        is( scalar @nodes, 1, "metadata_is does constrain the search" );
        is( $nodes[0]{name}, "Node1", "...correctly" );

        # Test metadata_isnt.
        @nodes = $wiki->list_recent_changes(
            last_n_changes => 1,
	    metadata_isnt  => { username => "Kake" }
        );
        is( scalar @nodes, 1, "metadata_isnt, too" );
        is( $nodes[0]{name}, "Another Node", "...correctly" );
        print "# " . join(" ", map { $_->{name} } @nodes) . "\n";

        @nodes = $wiki->list_recent_changes(
            last_n_changes => 1,
	    metadata_isnt  => { edit_type => "Minor tidying" }
        );
        is( scalar @nodes, 1,
           "metadata_isnt includes nodes where this metadata type isn't set" );
        is( $nodes[0]{name}, "Another Node", "...correctly" );

        eval { @nodes = $wiki->list_recent_changes(
                   last_n_changes => 1,
	           metadata_isnt  => { arthropod => "millipede" }
               );
        };
        is( $@, "",
  "list_recent_changes doesn't die when metadata_isnt doesn't omit anything" );

      SKIP: {
        skip "TODO", 2;

        # Test by "last n nodes added".
        foreach my $node ("Temp Node 1", "Temp Node 2", "Temp Node 3") {
            $wiki->write_node($node, "foo");
            my $slept = sleep(2);
            warn "Slept for less than a second, 'last n added' test may fail"
              unless $slept >= 1;
	}
        @nodes = $wiki->list_recent_changes( last_n_added => 2 );
	@nodenames = map { $_->{name} } @nodes;
        is_deeply( \@nodenames, ["Temp Node 3", "Temp Node 2"],
                   "last_n_added works" );
        my $slept = sleep(2);
            warn "Slept for less than a second, 'last n added' test may fail"
              unless $slept >= 1;
        my %node_data = $wiki->retrieve_node("Temp Node 1");
	$wiki->write_node("Temp Node1", @node_data{qw( content checksum )});
        @nodes = $wiki->list_recent_changes( last_n_added => 2 );
	@nodenames = map { $_->{name} } @nodes;
        is_deeply( \@nodenames, ["Temp Node 3", "Temp Node 2"],
                   "...still works when we've written to an older node" );

        foreach my $node ("Temp Node 1", "Temp Node 2", "Temp Node 3") {
            $wiki->delete_node($node) or die "Couldn't clean up";
        }
      }
    }
}

