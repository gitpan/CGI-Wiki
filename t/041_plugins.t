use strict;
use CGI::Wiki;
use CGI::Wiki::TestConfig::Utilities;
use Test::MockObject;
use Test::More tests => (9 * $CGI::Wiki::TestConfig::Utilities::num_stores);

my %stores = CGI::Wiki::TestConfig::Utilities->stores;

my ($store_name, $store);
while ( ($store_name, $store) = each %stores ) {
    SKIP: {
            skip "$store_name storage backend not configured for testing", 9
                unless $store;

        print "#####\n##### Test config: STORE: $store_name\n#####\n";

        my $wiki = CGI::Wiki->new( store => $store );

        my $null_plugin = Test::MockObject->new;

        my $plugin = Test::MockObject->new;
        $plugin->mock( "on_register",
                       sub {
                           my $self = shift;
                           $self->{__registered} = 1;
                           $self->{__seen_nodes} = [ ];
                           }
                      );
        eval { $wiki->register_plugin; };
        ok( $@, "->register_plugin dies if no plugin supplied" );
        eval { $wiki->register_plugin( plugin => $null_plugin ); };
        is( $@, "",
     "->register_plugin doesn't die if plugin which can't on_register supplied"
          );
        eval { $wiki->register_plugin( plugin => $plugin ); };
        is( $@, "",
       "->register_plugin doesn't die if plugin which can on_register supplied"
          );
        ok( $plugin->{__registered}, "->on_register method called" );

        my @registered = $wiki->get_registered_plugins;
        is( scalar @registered, 2,
            "->get_registered_plugins returns right number" );
        ok( ref $registered[0], "...and they're objects" );

        my $regref = $wiki->get_registered_plugins;
        is( ref $regref, "ARRAY", "...returns arrayref in scalar context" );

        $plugin->mock( "post_write",
                       sub {
            my ($self, %args) = @_;
            push @{ $self->{__seen_nodes} },
                { name     => $args{node},
                  version  => $args{version},
                  content  => $args{content},
                  metadata => $args{metadata}
                };
                           }
         );

         $wiki->write_node( "041 Test Node 1", "foo", undef, {bar => "baz"} )
             or die "Can't write node";
         ok( $plugin->called("post_write"), "->post_write method called" );

         my @seen = @{ $plugin->{__seen_nodes} };
         is_deeply( $seen[0], { name => "041 Test Node 1",
                                version => 1,
                                content => "foo",
                                metadata => { bar => "baz" } },
                    "...with the right arguments" );

    }
}
