use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig;
use Test::More tests => 2;

my ($skip, %config);
if ($CGI::Wiki::TestConfig::config{MySQL}->{dbname}) {
    %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    $config{store_class} = "CGI::Wiki::Store::MySQL";
} elsif ($CGI::Wiki::TestConfig::config{Pg}->{dbname}) {
    %config = %{$CGI::Wiki::TestConfig::config{Pg}};
    $config{store_class} = "CGI::Wiki::Store::Pg";
} elsif ($CGI::Wiki::TestConfig::config{SQLite}->{dbname}) {
    %config = %{$CGI::Wiki::TestConfig::config{SQLite}};
    $config{store_class} = "CGI::Wiki::Store::SQLite";
} else {
    $skip = 1;
}

SKIP: {
    skip "No storage backends configured for testing", 2 if $skip;

    # Test that the implicit_links flag gets passed through right.
    my $raw = "This paragraph has StudlyCaps in.";
    my ($wiki, $cooked);
    my $store_class = $config{store_class};
    eval "require $store_class";
    my $store = $store_class->new( dbname => $config{dbname},
				   dbuser => $config{dbuser},
				   dbpass => $config{dbpass} );
    $wiki = CGI::Wiki->new( store           => $store,
			    implicit_links  => 1,
			    node_prefix     => "wiki.cgi?node=" );

    $cooked = $wiki->format($raw);
    like( $cooked, qr!StudlyCaps</a>!,
	  "StudlyCaps turned into link when we specify implicit_links=1" );

    $wiki = CGI::Wiki->new( store           => $store,
			    implicit_links  => 0,
			    node_prefix     => "wiki.cgi?node=" );

    $cooked = $wiki->format($raw);
    unlike( $cooked, qr!StudlyCaps</a>!,
	    "...but not when we specify implicit_links=0" );
}
