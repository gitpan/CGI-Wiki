use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig;
use Test::More tests => 8;
use Test::MockObject;

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
    skip "No storage backends configured for testing", 8 if $skip;

    # Set up a store to test with.
    my $store_class = $config{store_class};
    eval "require $store_class";
    my $store = $store_class->new( dbname => $config{dbname},
				   dbuser => $config{dbuser},
				   dbpass => $config{dbpass} );

    my ($wiki, $cooked);

    # Test that a Wiki object created without an explicit formatter sets
    # defaults sensibly in its default formatter.
    $wiki = CGI::Wiki->new( store => $store );
    # White box testing.
    foreach my $want_defined ( qw ( extended_links implicit_links
				    allowed_tags macros node_prefix ) ) {
        ok( defined $wiki->{_formatter}{"_".$want_defined},
	    "...default set for $want_defined" );
    }

    # Test that the implicit_links flag gets passed through right.
    my $raw = "This paragraph has StudlyCaps in.";
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

    # Test that we can use an alternative formatter.
    my $mock = Test::MockObject->new();
    $mock->mock( 'format', sub { my ($self, $raw) = @_; return uc( $raw ); } );
    $wiki = CGI::Wiki->new( store     => $store,
                            formatter => $mock );
    $cooked = $wiki->format( "in the [future] there will be <b>robots</b>" );
    is( $cooked, "IN THE [FUTURE] THERE WILL BE <B>ROBOTS</B>",
        "can use an alternative formatter" );

}
