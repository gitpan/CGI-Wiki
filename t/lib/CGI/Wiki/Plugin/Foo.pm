package CGI::Wiki::Plugin::Foo;
use vars qw( @ISA );
@ISA = qw( CGI::Wiki::Plugin );

sub new {
    my $class = shift;
    return bless {}, $class;
}

1;
