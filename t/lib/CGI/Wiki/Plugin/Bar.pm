package CGI::Wiki::Plugin::Bar;
use vars qw( @ISA );
@ISA = qw( CGI::Wiki::Plugin );

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub on_register {
    my $self = shift;
    die unless $self->datastore;
}

1;
