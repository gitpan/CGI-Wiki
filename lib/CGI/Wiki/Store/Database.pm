package CGI::Wiki::Store::Database;

use strict;

use vars qw( $VERSION );
$VERSION = 0.02;

use DBI;
use Time::Piece;
use Time::Seconds;
use Carp qw(croak);

=head1 NAME

CGI::Wiki::Store::Database - parent class for database storage backends
for CGI::Wiki

=head1 REQUIRES

Time::Piece for making timestamps.

=head1 SYNOPSIS

Can't see yet why you'd want to use the backends directly, but:

  # See below for parameter details.
  my $backend = CGI::Wiki::Store::MySQL->new( %config );

=head1 METHODS

=over 4

=item B<new>

  my $store = CGI::Wiki::Store::MySQL->new( dbname => "wiki",
					    dbuser => "wiki",
					    dbpass => "wiki",
				   checksum_method => \&md5_hex );

dbname, dbuser and checksum_method parameters are mandatory. If you
want defaults done for you then get at it via CGI::Wiki instead. 
dbpass isn't mandatory, but you'll want to supply it unless your
authentication method doesn't require it.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    return $self->_init(@args);
}

sub _init {
    my ($self, %args) = @_;

    # Store parameters.
    foreach ( qw(dbname dbuser checksum_method) ) {
        $self->{"_$_"} = $args{$_} or die "Must supply a value for $_";
    }
    ref $self->{_checksum_method} eq "CODE"
        or die "Must supply a coderef for checksum_method";
    $self->{_dbpass} = $args{dbpass} || "";

    # Connect to database and store the database handle.
    my ($dbname, $dbuser, $dbpass) = @$self{qw(_dbname _dbuser _dbpass)};
    my $dsn = $self->_dsn($dbname)
       or croak "No data source string provided by class";
    $self->{_dbh} = DBI->connect($dsn, $dbuser, $dbpass,
				 { PrintError => 0, RaiseError => 1,
				   AutoCommit => 1 } )
        or croak "Can't connect to database $dbname: " . DBI->errstr;

    return $self;
}


=item B<retrieve_node>

  my $content = $backend->retrieve_node($node);

Returns the current (raw Wiki language) contents of the specified node.
The node parameter is mandatory.

=cut

sub retrieve_node {
    my ($self, $node) = @_;
    croak "No valid node name supplied" unless $node;
    my $dbh = $self->dbh;
    my $sql = "SELECT text FROM node WHERE name=" . $dbh->quote($node);
    my $arrayref = $dbh->selectcol_arrayref($sql)
        or die "Can't get content from database: " . DBI->errstr;
    return $arrayref->[0] || "";
}

=item B<verify_checksum>

  my $ok = $backend->verify_checksum($node, $checksum);

Sees whether your checksum is current for the given node. Returns true
if so, false if not.

B<NOTE:> Be aware that when called directly and without locking, this
might not be accurate, since there is a small window between the
checking and the returning where the node might be changed, so
B<don't> rely on it for safe commits; use C<write_node> for that. It
can however be useful when previewing edits, for example.

=cut

sub verify_checksum {
    my ($self, $node, $checksum) = @_;
    my $content = $self->retrieve_node($node);
    return ( $checksum eq $self->{_checksum_method}->($content) );
}

=item B<write_node_after_locking>

  $backend->write_node_after_locking($node, $content)
      or handle_error();

Writes the specified content into the specified node. Making sure that
locking/unlocking/transactions happen is left up to you (or your
chosen subclass). This method shouldn't really be used directly as it
might overwrite someone else's changes. Croaks on error but otherwise
returns true.

=cut

sub write_node_after_locking {
    my ($self, $node, $content) = @_;
    my $dbh = $self->dbh;

    my $timestamp = $self->_get_timestamp();
    my $comment = ""; # Not implemented yet.
    my $version;

    # Either inserting a new page or updating an old one.
    my $sql = "SELECT count(*) FROM node WHERE name=" . $dbh->quote($node);
    my $exists = @{ $dbh->selectcol_arrayref($sql) }[0] || 0;
    if ($exists) {
        $sql = "SELECT max(version) FROM content
                WHERE name=" . $dbh->quote($node);
        $version = @{ $dbh->selectcol_arrayref($sql) }[0] || 0;
        croak "Can't get version number" unless $version;
        $version++;
        $sql = "UPDATE node SET version=" . $dbh->quote($version)
	     . ", text=" . $dbh->quote($content)
	     . ", modified=" . $dbh->quote($timestamp)
	     . " WHERE name=" . $dbh->quote($node);
	$dbh->do($sql) or croak "Error updating database: " . DBI->errstr;
    } else {
        $version = 1;
        $sql = "INSERT INTO node (name, version, text, modified)
                VALUES ("
             . join(", ", map { $dbh->quote($_) }
		              ($node, $version, $content, $timestamp)
                   )
             . ")";
	$dbh->do($sql) or croak "Error updating database: " . DBI->errstr;
    }

    # In either case we need to add to the history.
    $sql = "INSERT INTO content (name, version, text, modified, comment)
            VALUES ("
         . join(", ", map { $dbh->quote($_) }
		          ($node, $version, $content, $timestamp, $comment)
               )
         . ")";
    $dbh->do($sql) or croak "Error updating database: " . DBI->errstr;

    return 1;
}

# Returns the timestamp of now, unless epoch is supplied.
sub _get_timestamp {
    my $self = shift;
    # I don't care about no steenkin' timezones (yet).
    my $time = shift || localtime; # Overloaded by Time::Piece.
    unless( ref $time ) {
	$time = localtime($time); # Make it into an object for strftime
    }
    return $time->strftime("%Y-%m-%d %H:%M:%S");
}

=item B<delete_node>

  $backend->delete_node($node);

Deletes the node (whether it exists or not), croaks on error. Again,
doesn't do any kind of locking. You probably don't want to let anyone
except Wiki admins call this. Removes all the node's history as well.

=cut

sub delete_node {
    my ($self, $node) = @_;
    my $dbh = $self->dbh;
    # Should start a transaction here.  FIXME.
    my $sql = "DELETE FROM node WHERE name=" . $dbh->quote($node);
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    $sql = "DELETE FROM content WHERE name=" . $dbh->quote($node);
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    # And finish it here.
    return 1;
}

=item B<list_recent_changes>

  # Changes in last 7 days.
  my @nodes = $backend->list_recent_changes( days => 7 );

  # Changes since a given time.
  my @nodes = $backend->list_recent_changes( since => 1036235131 );

  # Most recent change and its details.
  my @nodes = $backend->list_recent_changes( days => 1 );
  print "Node:          $nodes[0]{name}";
  print "Last modified: $nodes[0]{last_modified}";
  print "Comment:       $nodes[0]{comment}";


Returns results as an array, in reverse chronological order.  Each
element of the array is a reference to a hash with the following entries:

=over 4

=item * B<name>: the name of the node

=item * B<last_modified>: the timestamp of when it was last modified

=item * B<comment>: the comment (if any) that was attached to the node
last time it was modified

=back

Note that adding comments isn't implemented properly yet, so those
will always be the blank string at the moment.

=cut

sub list_recent_changes {
    my $self = shift;
    my %args = @_;
    if ($args{since}) {
        return $self->_list_changes_since($args{since});
    } elsif ($args{days}) {
        my $now = localtime;
	my $then = $now - ( ONE_DAY * $args{days} );
        return $self->_list_changes_since($then);
    } else {
	croak "Need to supply a parameter";
    }
}

sub _list_changes_since {
    my $self = shift;
    my $since = shift;
    my $timestamp = $self->_get_timestamp($since);
    my $dbh = $self->dbh;
    my $sql = "SELECT node.name, node.modified, content.comment
               FROM node, content WHERE node.modified >= "
            . $dbh->quote($timestamp)
            . " AND node.name=content.name AND node.version=content.version "
	    . " ORDER BY modified DESC";
    my $nodesref = $dbh->selectall_arrayref($sql);
    return map { { name          => $_->[0],
		   last_modified => $_->[1],
                   comment       => $_->[2] }
               } @$nodesref;
}

=item B<list_all_nodes>

  my @nodes = $backend->list_all_nodes();

Returns a list containing the name of every existing node.  The list
won't be in any kind of order; do any sorting in your calling script.

=cut

sub list_all_nodes {
    my $self = shift;
    my $dbh = $self->dbh;
    my $sql = "SELECT name FROM node;";
    my $nodes = $dbh->selectall_arrayref($sql); 
    return ( map { $_->[0] } (@$nodes) );
}

=item B<dbh>

  my $dbh = $store->dbh;

Returns the database handle belonging to this storage backend instance.

=cut

sub dbh {
    my $self = shift;
    return $self->{_dbh};
}

# Cleanup.
sub DESTROY {
    my $self = shift;
    my $dbh = $self->dbh;
    $dbh->disconnect if $dbh;
}

1;
