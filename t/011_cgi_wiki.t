local $^W = 1;
use strict;
use Test::More tests => 320;
use Test::Warn;
use CGI::Wiki::TestConfig;

##### Test whether we can be 'use'd with no warnings.
BEGIN {
  warnings_are { use_ok('CGI::Wiki') } [], "CGI::Wiki raised no warnings";
};

# Note - the Search::InvertedIndex test will raise warnings about the
# test database not being open at cleanup. This is a known problem
# which shouldn't affect normal use.

##### Test that calling with deprecated options warns.
foreach my $obsolete_param ( qw( storage_backend search_backend ) ) {
    warning_like { CGI::Wiki->new( storage_backend => "foo",
				   store => "foo" ) }
                 qr/parameter is no longer used/,
                 "warnings raised on obsolete parameter $obsolete_param";
}

##### Test failed creation.  Note this has a few tests missing.
eval { CGI::Wiki->new;
     };
ok( $@, "Creation dies if no store supplied" );

# Test for each configured pair: $store, $search.
my %config = %CGI::Wiki::TestConfig::config;
# This way of doing it is probably really ugly, but better that than
# sitting here agonising for ever.
my @tests;
push @tests, { store  => "CGI::Wiki::Store::MySQL",
	       search => undef,
	       config => $config{MySQL},
	       do     => ( $config{MySQL}{dbname} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::MySQL",
	       search => "CGI::Wiki::Search::DBIxFTS",
	       config => $config{MySQL},
	       do     => ( $config{MySQL}{dbname}
                           and $config{dbixfts} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::MySQL",
	       search => "CGI::Wiki::Search::SII",
	       config => $config{MySQL},
	       do     => ( $config{MySQL}{dbname}
                           and $config{search_invertedindex} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::Pg",
	       search => undef,
	       config => $config{Pg},
	       do     => ( $config{Pg}{dbname} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::Pg",
	       search => "CGI::Wiki::Search::SII",
	       config => $config{Pg},
	       do     => ( $config{Pg}{dbname}
                           and $config{search_invertedindex} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::SQLite",
	       search => undef,
	       config => $config{SQLite},
	       do     => ( $config{SQLite}{dbname} ? 1 : 0 ) };
push @tests, { store  => "CGI::Wiki::Store::SQLite",
	       search => "CGI::Wiki::Search::SII",
	       config => $config{SQLite},
	       do     => ( $config{SQLite}{dbname}
                           and $config{search_invertedindex} ? 1 : 0 ) };

foreach my $configref (@tests) {
    my %testconfig = %$configref;
    my ( $store_class, $search_class ) = @testconfig{qw(store search)};
    SKIP: {
        skip "Store $store_class and search "
	   . ( defined $search_class ? $search_class : "undef" )
	   . " not configured for testing", 45 unless $testconfig{do};

        print "#####\n##### Test config: STORE: $store_class, SEARCH: "
	   . ( defined $search_class ? $search_class : "undef" ) . "\n#####\n";

	##### Grab working db/user/pass.
	my $dbname = $testconfig{config}{dbname};
	my $dbuser = $testconfig{config}{dbuser};
	my $dbpass = $testconfig{config}{dbpass};

	eval "require $store_class";
	my $store = $store_class->new( dbname => $dbname,
				       dbuser => $dbuser,
				       dbpass => $dbpass )
	  or die "Couldn't set up test store";
	my $search;
	if ( $search_class ) {
	    eval "require $search_class";
	    my %search_config;
	    if ( $search_class eq "CGI::Wiki::Search::DBIxFTS" ) {
	        # DBIxFTS only works with MySQL.
	        require DBI;
	        my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass);
		%search_config = ( dbh => $dbh );
	    } elsif ( $search_class eq "CGI::Wiki::Search::SII" ) {
  	        if ( $store_class eq "CGI::Wiki::Store::MySQL" ) {
                    # If we can test the MySQL SII backend, do so.
                    my $indexdb = Search::InvertedIndex::DB::Mysql->new(
                       -db_name    => $dbname,
                       -username   => $dbuser,
                       -password   => $dbpass,
	   	       -hostname   => '',
                       -table_name => 'siindex',
                       -lock_mode  => 'EX' );
		    %search_config = ( indexdb => $indexdb );
		} else {
                    # Otherwise just test the default DB_File backend.
                    my $indexdb = Search::InvertedIndex::DB::DB_File_SplitHash->new(
                       -map_name  => 't/sii-db-file-test.db',
                       -lock_mode  => 'EX' );
		    %search_config = ( indexdb => $indexdb );
                }
	    } else {
	        die "Whoops, don't know how to set up a $search_class";
            }
	    $search = $search_class->new( %search_config )
	      or die "Couldn't set up test search";
	}

        ##### Test succesful creation.
        my $wiki = CGI::Wiki->new( store  => $store,
				   search => $search );
        isa_ok( $wiki, "CGI::Wiki" );
        ok( $wiki->retrieve_node("Home"), "...and we can talk to the store" );

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
                skip "Search backend $search_class doesn't support"
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

	##### Test recent_changes (must do this as the last in each batch
        ##### of tests since some tests involve writing, and some configs
        ##### re-use the same database (eg mysql-nosearch, mysql-dbixfts)
        # The tests in this file will write to the following nodes:
        #   Another Node, Everyone's Favourite Hobby, Node1
        foreach my $node ("Node1", "Everyone's Favourite Hobby",
			  "Another Node") { # note the order
            %node_data = $wiki->retrieve_node($node);
            $wiki->write_node($node, @node_data{ qw(content checksum) });
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

        my $time = time;
	my $slept = sleep(2);
	warn "Slept for less than a second, 'since' test may fail"
	  unless $slept >= 1;
        %node_data = $wiki->retrieve_node("Node1");
	$wiki->write_node("Node1", @node_data{qw( content checksum )});
        @nodes = $wiki->list_recent_changes( since => $time );
	@nodenames = map { $_->{name} } @nodes;
        is_deeply( \@nodenames, ["Node1"],
		   "recent_changes 'since' returns the right results" );
        ok( $nodes[0]{last_modified},
	    "...and a plausible (not undef or empty) last_modified timestamp");

    }
}
