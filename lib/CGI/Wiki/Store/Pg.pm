package CGI::Wiki::Store::Pg;

use strict;

use vars qw( @ISA $VERSION );

use CGI::Wiki::Store::Database;
use Carp qw/carp croak/;

@ISA = qw( CGI::Wiki::Store::Database );
$VERSION = 0.01;

=head1 NAME

CGI::Wiki::Store::Pg - Postgres storage backend for CGI::Wiki

=head1 REQUIRES

Subclasses CGI::Wiki::Store::Database.

=head1 SYNOPSIS

See CGI::Wiki::Store::Database

=cut

# Internal method to return the data source string required by DBI.
sub _dsn {
    my ($self, $dbname) = @_;
    return "dbi:Pg:dbname=$dbname";
}

=head1 METHODS

=over 4

=item B<check_and_write_node>

  $store->check_and_write_node( node     => $node,
				content  => $content,
				checksum => $checksum ) or return 0;

Locks the node, verifies the checksum and writes the content to the
node, unlocks the node.  Returns 1 on success, 0 if checksum doesn't
match, croaks on error.

=cut

sub check_and_write_node {
    my ($self, %args) = @_;
    my ($node, $content, $checksum) = @args{qw(node content checksum)};

    my $dbh = $self->{_dbh};
    $dbh->{AutoCommit} = 0;

    my $ok = eval {
        $dbh->do("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
        $self->verify_checksum($node, $checksum) or return 0;
        $self->write_node_after_locking($node, $content);
    };
    if ($@) {
        my $error = $@;
        $dbh->rollback;
	$dbh->{AutoCommit} = 1;
	if ($error =~ /Can't serialize access due to concurrent update/) {
            return 0;
        } else {
            croak $error;
        }
    } else {
        $dbh->commit;
	$dbh->{AutoCommit} = 1;
	return $ok;
    }
}


1;
