use strict;
use CGI::Wiki;
use CGI::Wiki::Formatter::Default;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (3 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 3
            unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $formatter = CGI::Wiki::Formatter::Default->new(
            extended_links => 1
        );
        my $wiki = CGI::Wiki->new( formatter => $formatter, store => $store );

        $wiki->write_node( "018 Node 1", "[018 Nonexistent]" )
          or die "Couldn't write node";
        $wiki->write_node( "018 Node 2", "[018 Node 1]" )
          or die "Couldn't write node";
        $wiki->write_node( "018 Node 3", "[018 Nonexistent]" )
          or die "Couldn't write node";

        my @links = $wiki->list_dangling_links;
        my %dangling;
        foreach my $link (@links) {
            $dangling{$link}++;
        }
        ok( $dangling{"018 Nonexistent"},
            "dangling links returned by ->list_dangling_links" );
        ok( !$dangling{"018 Node 1"}, "...but not existing ones" );
        is( $dangling{"018 Nonexistent"}, 1,
            "...and each dangling link only returned once" );

    } # end of SKIP
}
