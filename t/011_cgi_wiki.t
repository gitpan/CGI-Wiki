local $^W = 1;
use strict;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (2 + 48*$CGI::Wiki::TestConfig::Utilities::num_combinations);

BEGIN {
    use_ok( "CGI::Wiki" );
};

# Note - the Search::InvertedIndex test will raise warnings about the
# test database not being open at cleanup. This is a known problem
# which shouldn't affect normal use.

##### Test failed creation.  Note this has a few tests missing.
eval { CGI::Wiki->new;
     };
ok( $@, "Creation dies if no store supplied" );

# Test for each configured pair: $store, $search.
my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_name, $store, $search_name, $search, $configured ) =
        @testconfig{qw(store_name store search_name search configured)};
    SKIP: {
        skip "Store $store_name and search $search_name"
	   . " not configured for testing", 48 unless $configured;

        print "#####\n##### Test config: STORE: $store_name, SEARCH: "
	   . $search_name . "\n#####\n";

        ##### Test succesful creation.
        my $wiki = CGI::Wiki->new( store          => $store,
				   search         => $search,
				   extended_links => 1 );
        isa_ok( $wiki, "CGI::Wiki" );
        ok( $wiki->retrieve_node("Home"), "...and we can talk to the store" );

        ##### Test whether we can see if a node exists.
        ok( $wiki->node_exists("Home"),
            "node_exists returns true for an existing node" );
	ok( ! $wiki->node_exists("This Is A Nonexistent Node"),
	    "...and false for a nonexistent one" );

        ##### Test retrieval of a node.
        is( $wiki->retrieve_node("Node1"), "This is Node1.",
            "retrieve_node can retrieve a node correctly" );
        eval { $wiki->retrieve_node; };
        ok( $@, "...and dies if we don't tell it a node parameter" );
        is( $wiki->retrieve_node(name => "Node1"), "This is Node1.",
            "...still works if we supply params as a hash" );
        is( $wiki->retrieve_node(name => "Node1", version => 1),
	    "This is Node1.",
            "...still works if we supply a version param" );

        ##### Test retrieving a node with meta-data.
        my %node_data = $wiki->retrieve_node("Node1");
        is( $node_data{content}, "This is Node1.",
	    "...still works if we request a hash" );
        foreach (qw( last_modified version checksum )) {
            ok( defined $node_data{$_}, "...and $_ is defined" );
	}

        ##### Test writing to a new node.
        ok( $wiki->write_node("New Node", "New Node content."),
            "write_node can create nodes" );
        is( $wiki->retrieve_node("New Node"), "New Node content.",
            "...correctly" );

        ##### Test deleting a node.
        eval { $wiki->delete_node("Node1") };
        is( $@, "", "delete_node doesn't die when deleting an existing node" );
        is( $wiki->retrieve_node("Node1"), "",
	    "...and retrieving a deleted node returns the empty string" );
        eval { $wiki->delete_node("idonotexist") };
        is( $@, "",
	    "delete_node doesn't die when deleting a non-existent node" );

        # Cleanup.
        $wiki->write_node("Node1", "This is Node1.") or die "Couldn't cleanup";
        $wiki->delete_node("New Node") or die "Couldn't cleanup";

        ##### Test indexing.
        my @all_nodes = $wiki->list_all_nodes;
        is( scalar @all_nodes, 5,
    	"list_all_nodes returns the right number of nodes" );
        is_deeply( [sort @all_nodes],
                   ["001 Defenestration", "Another Node",
    		"Everyone's Favourite Hobby", "Home", "Node1" ],
        	   "...and the right ones, too" );

        ##### Test searching.
        SKIP: {
            skip "Not testing search for this configuration", 13
	        unless $search;
            my %results = eval {
                local $SIG{__WARN__} = sub { die $_[0] };
                $wiki->search_nodes('home');
            };
            is( $@, "", "search_nodes doesn't throw warning" );

            isnt( scalar keys %results, 0, "...and can find a single word" );
            is( scalar keys %results, 2, "...the right number of times" );
            is_deeply( [sort keys %results], ["Another Node", "Home"],
                       "...and the hash returned has node names as keys" );

            %results = $wiki->search_nodes('expert defenestration');
            isnt( scalar keys %results, 0,
    	      "...and can find two words on an AND search" );

            %results = $wiki->search_nodes('wombat home', 'OR');
	    my %and_results = $wiki->search_nodes('wombat home', 'AND');
            die "Erroneous wombat home in test data"
	        if scalar keys %and_results;
            isnt( scalar keys %results, 0,
    	      "...and the OR search seems to work" );

            SKIP: {
                skip "Search backend $search_name doesn't support"
		   . " phrase searches", 2
	            unless $wiki->supports_phrase_searches;

                %results=$wiki->search_nodes('expert "wombat defenestration"');
		isnt( scalar keys %results, 0, "...and can find a phrase" );
		ok( ! defined $results{"001 Defenestration"},
		    "...and ignores nodes that only have part of the phrase" );
	    }

            # Test case-insensitivity.
            %results = $wiki->search_nodes('performing');
            ok( defined $results{"Everyone's Favourite Hobby"},
                "a lower-case search finds things defined in mixed case" );

            %results = $wiki->search_nodes('WoMbAt');
            ok( defined $results{"Everyone's Favourite Hobby"},
                "a mixed-case search finds things defined in lower case" );

            # Check that titles are searched.
            %results = $wiki->search_nodes('Another');
            ok( defined $results{"Another Node"},
                "titles are searched" );

	    ##### Test that newly-created nodes come up in searches, and that
	    ##### once deleted they don't come up any more.
	    %results = $wiki->search_nodes('Sunnydale');
            unless ( scalar keys %results == 0 ) {
	        die "'Sunnydale' already in indexes -- rerun init script";
	    }
            unless ( ! defined $results{"New Searching Node"} ) {
                die "'New Node' already in indexes -- rerun init script";
	    }
            $wiki->write_node("New Searching Node", "Sunnydale")
                or die "Can't write 'New Searching Node'";
                # will die if node already exists
	    %results = $wiki->search_nodes('Sunnydale');
	    ok( defined $results{"New Searching Node"},
		"new nodes are correctly indexed for searching" );
            $wiki->delete_node("New Searching Node")
                or die "Can't delete 'New Searching Node'";
	    %results = $wiki->search_nodes('Sunnydale');
	    ok( ! defined $results{"New Searching Node"},
		"...and removed from the indexes on deletion" );
	}

        ##### Test writing to existing nodes.
        %node_data = $wiki->retrieve_node("Everyone's Favourite Hobby");
	my $slept = sleep(2);
	warn "Slept for less than a second, 'lastmod' test may fail"
	  unless $slept >= 1;

        ok( $wiki->write_node("Everyone's Favourite Hobby",
			      "xx", $node_data{checksum}),
	    "write_node succeeds when node matches checksum" );
        ok( ! $wiki->write_node("Everyone's Favourite Hobby",
				"foo", $node_data{checksum}),
	    "...and flags when it doesn't" );
        my %new_node_data = $wiki->retrieve_node("Everyone's Favourite Hobby");
        print "# version now: [$new_node_data{version}]\n";
        is( $new_node_data{version}, $node_data{version} + 1,
	    "...and the version number is updated on successful writing" );
        my $lastmod = Time::Piece->strptime($new_node_data{last_modified},
			           $CGI::Wiki::Store::Database::timestamp_fmt);
	my $prev_lastmod = Time::Piece->strptime($node_data{last_modified},
 				   $CGI::Wiki::Store::Database::timestamp_fmt);
        print "# [$lastmod] [$prev_lastmod]\n";
 	ok( $lastmod > $prev_lastmod, "...as is last_modified" );
        my $old_content = $wiki->retrieve_node(
	    name    => "Everyone's Favourite Hobby",
	    version => 2 );
        is( $old_content, "xx", "...and old versions are still available" );

        # Cleanup for next test run.
        $wiki->write_node("Everyone's Favourite Hobby",
        		  "Performing expert wombat defenestration.",
                          $new_node_data{checksum})
            or die "Couldn't cleanup";

        ##### Test retrieving with checksums.
        %node_data = $wiki->retrieve_node("Another Node");
        ok( $node_data{checksum}, "retrieve_node does return a checksum" );
        is( $node_data{content}, $wiki->retrieve_node("Another Node"),
            "...and the same content as when called in scalar context" );
        ok( $wiki->verify_checksum("Another Node", $node_data{checksum}),
            "...and verify_checksum is happy with the checksum" );

        $wiki->write_node("Another Node",
                         'This node exists solely to contain the word "home".',
			  $node_data{checksum}) or die "Couldn't cleanup";
        ok( $wiki->verify_checksum("Another Node", $node_data{checksum}),
           "...still happy when we write node again with exact same content" );

        $wiki->write_node("Another Node", "foo bar wibble",
			  $node_data{checksum});
        ok( ! $wiki->verify_checksum("Another Node", $node_data{checksum}),
            "...but not once we've changed the node content" );

        # Cleanup for next test run.
        $wiki->delete_node("Another Node") or die "Couldn't cleanup";
        $wiki->write_node("Another Node",
                         'This node exists solely to contain the word "home".')
            or die "Couldn't cleanup";

        ##### Test backlinks.
        $wiki->write_node("Backlink Test One",
             "This is some text.  It contains a link to [Backlink Test Two].");
        $wiki->write_node("Backlink Test Two",
             # don't break this line to pretty-indent it or the formatter will
             # think the second line is code and not pick up the link.
             "This is some text.  It contains a link to [Backlink Test Three] and one to [Backlink Test One].");
        $wiki->write_node("Backlink Test Three",
             "This is some text.  It contains a link to [Backlink Test One].");

        my @links = $wiki->list_backlinks( node => "Backlink Test Two" );
        is_deeply( \@links, [ "Backlink Test One" ],
                   "backlinks work on nodes linked to once" );
        @links = $wiki->list_backlinks( node => "Backlink Test One" );
        is_deeply( [ sort @links],
                   [ "Backlink Test Three", "Backlink Test Two" ],
                   "...and nodes linked to twice" );
        @links = $wiki->list_backlinks( node => "idonotexist" );
        is_deeply( \@links, [],
                  "...returns empty list for nonexistent node not linked to" );
        @links = $wiki->list_backlinks( node => "001 Defenestration" );
        is_deeply( \@links, [],
                  "...returns empty list for existing node not linked to" );

        $wiki->delete_node("Backlink Test One")   or die "Couldn't cleanup";
        $wiki->delete_node("Backlink Test Two")   or die "Couldn't cleanup";
        $wiki->delete_node("Backlink Test Three") or die "Couldn't cleanup";

        @links = $wiki->list_backlinks( node => "Backlink Test Two" );
        is_deeply( \@links, [],
                   "...returns empty list when the only node linking to this one has been deleted" );

        eval { $wiki->write_node("Multiple Backlink Test", "This links to [[Node One]] and again to [[Node One]]"); };
        is( $@, "", "doesn't die when writing a node that links to the same place twice" );

        $wiki->delete_node("Multiple Backlink Test") or die "Couldn't cleanup";

    }
}
