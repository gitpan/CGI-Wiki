package CGI::Wiki::Store::MySQL;

use strict;

use vars qw( @ISA $VERSION );

use CGI::Wiki::Store::Database;
use Carp qw/carp croak/;

@ISA = qw( CGI::Wiki::Store::Database );
$VERSION = 0.01;

=head1 NAME

CGI::Wiki::Store::MySQL - MySQL storage backend for CGI::Wiki

=head1 REQUIRES

Subclasses CGI::Wiki::Store::Database.

=head1 SYNOPSIS

See CGI::Wiki::Store::Database

=cut

# Internal method to return the data source string required by DBI.
sub _dsn {
    my ($self, $dbname) = @_;
    return "dbi:mysql:$dbname";
}

=head1 METHODS

=over 4

=item B<check_and_write_node>

  $store->check_and_write_node( node     => $node,
				content  => $content,
				checksum => $checksum,
                                links_to => \@links_to ) or return 0;

Locks the node, verifies the checksum and writes the content to the
node, unlocks the node. Returns 1 on successful writing, 0 if checksum
doesn't match, croaks on error.

The C<links_to> parameter is optional, but if you do supply it then
this node will be returned when calling C<list_backlinks> on the nodes
in C<@links_to>. B<Note> that if you don't supply the ref then the store
will assume that this node doesn't link to any others, and update
itself accordingly.

Note:  Uses MySQL's user level locking, so any locks are released when
the database handle disconnects.  Doing it like this because I can't seem
to get it to work properly with transactions.

=cut

sub check_and_write_node {
    my ($self, %args) = @_;
    my ($node, $content, $checksum, $links_to) =
                                     @args{qw(node content checksum links_to)};

    $self->_lock_node($node) or croak "Can't lock node";
    my $ok = $self->verify_checksum($node, $checksum);
    unless ($ok) {
        $self->_unlock_node($node) or carp "Can't unlock node";
	return 0;
    }
    $self->write_node_after_locking($node, $content, $links_to);
    $self->_unlock_node($node) or carp "Can't unlock node";
    return 1;
}

# Returns 1 if we can get a lock, 0 if we can't, croaks on error.
sub _lock_node {
    my ($self, $node) = @_;
    my $dbh = $self->{_dbh};
    $node = $dbh->quote($node);
    my $sql = "SELECT GET_LOCK($node, 10)";
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my $locked = $sth->fetchrow_array;
    $sth->finish;
    return $locked;
}

# Returns 1 if we can unlock, 0 if we can't, croaks on error.
sub _unlock_node {
    my ($self, $node) = @_;
    my $dbh = $self->{_dbh};
    $node = $dbh->quote($node);
    my $sql = "SELECT RELEASE_LOCK($node)";
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my $unlocked = $sth->fetchrow_array;
    $sth->finish;
    return $unlocked;
}


1;
