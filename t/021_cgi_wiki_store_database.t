#!/usr/bin/perl -w

use strict;
use Test::More tests => 18;
use CGI::Wiki::TestConfig;

my @databases;
push @databases, "MySQL"  if $CGI::Wiki::TestConfig::config{MySQL}{dbname};
push @databases, "Pg"     if $CGI::Wiki::TestConfig::config{Pg}{dbname};
push @databases, "SQLite" if $CGI::Wiki::TestConfig::config{SQLite}{dbname};

SKIP: {
    skip "No databases configured for testing", 18 unless @databases;

    foreach my $db (qw(MySQL Pg SQLite)) {
        my %config = %{$CGI::Wiki::TestConfig::config{$db}};
        SKIP: {
	    skip "$db backend not configured for testing", 6
	        unless $config{dbname};
	    my $class = "CGI::Wiki::Store::$db";
	    use_ok( $class );

	    eval { $class->new; };
	    ok( $@, "Failed creation dies" );

	    my ($dbname, $dbuser, $dbpass) = @config{qw(dbname dbuser dbpass)};
	    my $store = eval { $class->new( dbname => $dbname,
					    dbuser => $dbuser,
					    dbpass => $dbpass );
			     };
	    is( $@, "", "Creation succeeds" );
	    isa_ok( $store, $class );
	    ok( $store->dbh, "...and has set up a database handle" );
	    ok( $store->retrieve_node("Home"),
		"...and we can retrieve a node" );
	}
    }
}
