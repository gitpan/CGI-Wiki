use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig;
use Test::More tests => 2;

my ($skip, %config);
if ($CGI::Wiki::TestConfig::config{MySQL}->{dbname}) {
    %config = %{$CGI::Wiki::TestConfig::config{MySQL}};
    $config{backend} = "mysql";
} elsif ($CGI::Wiki::TestConfig::config{Pg}->{dbname}) {
    %config = %{$CGI::Wiki::TestConfig::config{Pg}};
    $config{backend} = "postgres";
} else {
    $skip = 1;
}

SKIP: {
    skip "No backends configured for testing", 2 if $skip;

    # Test that the implicit_links flag gets passed through right.
    my $raw = "This paragraph has StudlyCaps in.";
    my ($wiki, $cooked);
    $wiki = CGI::Wiki->new( backend        => $config{backend},
			    dbname         => $config{dbname},
			    dbuser         => $config{dbuser},
			    dbpass         => $config{dbpass},
			    implicit_links => 1,
			    node_prefix    => "wiki.cgi?node=" );

    $cooked = $wiki->format($raw);
    like( $cooked, qr!StudlyCaps</a>!,
	  "StudlyCaps turned into link when we specify implicit_links=1" );

    $wiki = CGI::Wiki->new( backend        => $config{backend},
			    dbname         => $config{dbname},
			    dbuser         => $config{dbuser},
			    dbpass         => $config{dbpass},
			    implicit_links => 0,
			    node_prefix    => "wiki.cgi?node=" );

    $cooked = $wiki->format($raw);
    unlike( $cooked, qr!StudlyCaps</a>!,
	    "...but not when we specify implicit_links=0" );
}
