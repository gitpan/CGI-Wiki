package CGI::Wiki::Store::Database;

use strict;

use vars qw( $VERSION $timestamp_fmt );
$timestamp_fmt = "%Y-%m-%d %H:%M:%S";

use DBI;
use Time::Piece;
use Time::Seconds;
use Carp qw(croak);
use Digest::MD5 qw( md5_hex );

$VERSION = '0.06';

=head1 NAME

CGI::Wiki::Store::Database - parent class for database storage backends
for CGI::Wiki

=head1 SYNOPSIS

Can't see yet why you'd want to use the backends directly, but:

  # See below for parameter details.
  my $store = CGI::Wiki::Store::MySQL->new( %config );

=head1 METHODS

=over 4

=item B<new>

  my $store = CGI::Wiki::Store::MySQL->new( dbname => "wiki",
					    dbuser => "wiki",
					    dbpass => "wiki" );

dbname and dbuser parameters are mandatory. If you want defaults done
for you then get at it via CGI::Wiki instead. dbpass isn't mandatory,
but you'll want to supply it unless your authentication method doesn't
require it. If your authentication method doesn't need a database
username, just put any old junk in there.

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
    foreach ( qw(dbname dbuser) ) {
        die "Must supply a value for $_" unless defined $args{$_};
        $self->{"_$_"} = $args{$_};
    }
    $self->{_dbpass} = $args{dbpass} || "";
    $self->{_checksum_method} = \&md5_hex;

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

  my $content = $store->retrieve_node($node);

  # Or get additional meta-data too.
  my %node = $store->retrieve_node("HomePage");
  print "Current Version: " . $node{version};

  # Or get an earlier version:
  my %node = $store->retrieve_node(name    => "HomePage",
			             version => 2 );
  print $node{content};

In scalar context, returns the current (raw Wiki language) contents of
the specified node. In list context, returns a hash containing the
contents of the node plus metadata: last_modified, version, checksum.

The node parameter is mandatory. The version parameter is optional and
defaults to the newest version. If the node hasn't been created yet,
it is considered to exist but be empty (this behaviour might change).

=cut

sub retrieve_node {
    my $self = shift;
    my %args = scalar @_ == 1 ? ( name => $_[0] ) : @_;
    croak "No valid node name supplied" unless $args{name};
    my $dbh = $self->dbh;
    my $sql;
    if ( $args{version} ) {
        $sql = "SELECT text, version, modified FROM content"
             . " WHERE  name=" . $dbh->quote($args{name})
             . " AND version=" . $dbh->quote($args{version});
    } else {
        $sql = "SELECT text, version, modified FROM node
                WHERE name=" . $dbh->quote($args{name});
    }
    my @results = $dbh->selectrow_array($sql);
    @results = ("", 0, "") unless scalar @results;
    my %data;
    @data{ qw( content version last_modified ) } = @results;
    $data{checksum} = md5_hex($data{content});
    return wantarray ? %data : $data{content};
}

=item B<retrieve_node_and_checksum>

  my ($content, $cksum) = $store->retrieve_node_and_checksum($node);

Works just like retrieve_node would in scalar context, but also gives you
a checksum that you must send back when you want to commit changes, so
you can check that no other changes have been committed while you were
editing.

B<NOTE:> This is a convenience method supplied for backwards
compatibility with 0.03, and will probably disappear at some point.
Use C<retrieve_node> in list context, instead.

=cut

sub retrieve_node_and_checksum {
    my ($self, $node) = @_;
    my %data = $self->retrieve_node($node) or return ();
    return @data{ qw( content checksum ) };
}

=item B<node_exists>

  if ( $store->node_exists( "Wombat Defenestration" ) {
      # do something about the weird people infesting your wiki
  } else {
      # ah, safe, no weirdos here
  }

Returns true if the node has ever been created (even if it is
currently empty), and false otherwise.

=cut

sub node_exists {
    my ( $self, $node ) = @_;
    my %data = $self->retrieve_node($node) or return ();
    return $data{version}; # will be 0 if node doesn't exist, >=1 otherwise
}

=item B<verify_checksum>

  my $ok = $store->verify_checksum($node, $checksum);

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
    return ( $checksum eq md5_hex($content) );
}

=item B<write_node_after_locking>

  $store->write_node_after_locking($node, $content)
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
    return $time->strftime($timestamp_fmt); # global
}

=item B<delete_node>

  $store->delete_node($node);

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
  my @nodes = $store->list_recent_changes( days => 7 );

  # Changes since a given time.
  my @nodes = $store->list_recent_changes( since => 1036235131 );

  # Most recent change and its details.
  my @nodes = $store->list_recent_changes( last_n_changes => 1 );
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
        return $self->_find_recent_changes_by_criteria(since => $args{since});
    } elsif ( $args{days} ) {
        my $now = localtime;
	my $then = $now - ( ONE_DAY * $args{days} );
        return $self->_find_recent_changes_by_criteria(since => $then );
    } elsif ( $args{last_n_changes} ) {
        return $self->_find_recent_changes_by_criteria(
            limit => $args{last_n_changes}
        );
    } else {
	croak "Need to supply a parameter";
    }
}

sub _find_recent_changes_by_criteria {
    my ($self, %args) = @_;
    my ( $since, $limit ) = @args{ qw( since limit ) };
    my $dbh = $self->dbh;

    my @where = ( "node.name=content.name", "node.version=content.version" );
    if ( $since ) {
        my $timestamp = $self->_get_timestamp( $since );
        push @where, "node.modified >= " . $dbh->quote($timestamp);
    }

    my $sql = "SELECT node.name, node.modified, content.comment
               FROM node, content WHERE " . join(" AND ", @where)
            . " ORDER BY node.modified DESC";
    if ( $limit ) {
        croak "Bad argument $limit" unless $limit =~ /^\d+$/;
        $sql .= " LIMIT $limit";
    }

    my $nodesref = $dbh->selectall_arrayref($sql);
    return map { { name          => $_->[0],
		   last_modified => $_->[1],
                   comment       => $_->[2] }
               } @$nodesref;
}

=item B<list_all_nodes>

  my @nodes = $store->list_all_nodes();

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

=item B<dbname>

  my $dbname = $store->dbname;

Returns the name of the database used for backend storage.

=cut

sub dbname {
    my $self = shift;
    return $self->{_dbname};
}

=item B<dbh>

  my $dbuser = $store->dbuser;

Returns the username used to connect to the database used for backend storage.

=cut

sub dbuser {
    my $self = shift;
    return $self->{_dbuser};
}

=item B<dbpass>

  my $dbpass = $store->dbpass;

Returns the password used to connect to the database used for backend storage.

=cut

sub dbpass {
    my $self = shift;
    return $self->{_dbpass};
}

# Cleanup.
sub DESTROY {
    my $self = shift;
    my $dbh = $self->dbh;
    $dbh->disconnect if $dbh;
}

1;
