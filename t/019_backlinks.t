use strict;
use CGI::Wiki;
use CGI::Wiki::Formatter::Default;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => (1 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 1
            unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $formatter = CGI::Wiki::Formatter::Default->new(
            extended_links => 1
        );
        my $wiki = CGI::Wiki->new( formatter => $formatter, store => $store );

        my $content = <<WIKITEXT;

[Cleanup]

[CleanUp]

WIKITEXT

        my @warnings;
        eval {
            local $SIG{__WARN__} = sub { push @warnings, $_[0]; };
            $wiki->write_node( "019 Node 1", $content );
        };
        is( $@, "", "->write_node doesn't die when content links to nodes differing only in case" );
        print "# ...but it does warn: " . join(" ", @warnings ) . "\n"
            if scalar @warnings;

    } # end of SKIP
}
