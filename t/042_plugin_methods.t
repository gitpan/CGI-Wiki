use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::More tests => 1 +
                          (6 * $CGI::Wiki::TestConfig::Utilities::num_stores);

use_ok( "CGI::Wiki::Plugin" );
use lib "t/lib";
use CGI::Wiki::Plugin::Foo;
use CGI::Wiki::Plugin::Bar;

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 6
                unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $wiki = CGI::Wiki->new( store => $store );
        my $plugin = CGI::Wiki::Plugin::Foo->new;
        isa_ok( $plugin, "CGI::Wiki::Plugin::Foo" );
        isa_ok( $plugin, "CGI::Wiki::Plugin" );
        can_ok( $plugin, qw( datastore indexer formatter ) );

        $wiki->register_plugin( plugin => $plugin );
        ok( ref $plugin->datastore,
            "->datastore seems to return an object after registration" );
        is_deeply( $plugin->datastore, $store, "...the right one" );

        # Check that the datastore etc attrs are set up before on_register
        # is called.
        my $plugin_2 = CGI::Wiki::Plugin::Bar->new;
        eval { $wiki->register_plugin( plugin => $plugin_2 ); };
        is( $@, "", "->on_register can access datastore" );

    } # end of SKIP
}
