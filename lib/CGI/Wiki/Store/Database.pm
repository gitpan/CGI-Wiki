package CGI::Wiki::Store::Database;

use strict;

use vars qw( $VERSION $timestamp_fmt );
$timestamp_fmt = "%Y-%m-%d %H:%M:%S";

use DBI;
use Time::Piece;
use Time::Seconds;
use Carp qw( carp croak );
use Digest::MD5 qw( md5_hex );

$VERSION = '0.10';

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

C<dbname> is mandatory. C<dbpass> and C<dbuser> are optional, but
you'll want to supply them unless your database's authentication
method doesn't require it.

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
    foreach ( qw(dbname) ) {
        die "Must supply a value for $_" unless defined $args{$_};
        $self->{"_$_"} = $args{$_};
    }
    $self->{_dbuser} = $args{dbuser} || "";
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

  my $content = $store->retrieve_node($node);

  # Or get additional meta-data too.
  my %node = $store->retrieve_node("HomePage");
  print "Current Version: " . $node{version};

  # Maybe we stored some metadata too.
  my $categories = $node{metadata}{category};
  print "Categories: " . join(", ", @$categories);
  print "Postcode: $node{metadata}{postcode}[0]";

  # Or get an earlier version:
  my %node = $store->retrieve_node(name    => "HomePage",
			             version => 2 );
  print $node{content};


In scalar context, returns the current (raw Wiki language) contents of
the specified node. In list context, returns a hash containing the
contents of the node plus additional data:

=over 4

=item B<last_modified>

=item B<version>

=item B<checksum>

=item B<metadata> - a reference to a hash containing any caller-supplied
metadata sent along the last time the node was written

The node parameter is mandatory. The version parameter is optional and
defaults to the newest version. If the node hasn't been created yet,
it is considered to exist but be empty (this behaviour might change).

B<Note> on metadata - each hash value is an array ref, even if that
type of metadata only has one value.

=cut

sub retrieve_node {
    my $self = shift;
    my %args = scalar @_ == 1 ? ( name => $_[0] ) : @_;
    # Note _retrieve_node_data is sensitive to calling context.
    return $self->_retrieve_node_data( %args ) unless wantarray;
    my %data = $self->_retrieve_node_data( %args );
    $data{checksum} = $self->_checksum(%data);
    return %data;
}

# Returns hash or scalar depending on calling context.
sub _retrieve_node_data {
    my ($self, %args) = @_;
    my %data = $self->_retrieve_node_content( %args );
    return $data{content} unless wantarray;

    # If we want additional data then get it.  Note that $data{version}
    # will already have been set by C<_retrieve_node_content>, if it wasn't
    # specified in the call.
    my $dbh = $self->dbh;
    my $sql = "SELECT metadata_type, metadata_value FROM metadata WHERE "
         . "node=" . $dbh->quote($args{name}) . " AND "
         . "version=" . $dbh->quote($data{version});
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my %metadata;
    while ( my ($type, $val) = $sth->fetchrow_array ) {
        if ( defined $metadata{$type} ) {
	    push @{$metadata{$type}}, $val;
	} else {
            $metadata{$type} = [ $val ];
        }
    }
    $data{metadata} = \%metadata;
    return %data;
}

# $store->_retrieve_node_content( name    => $node_name,
#                                 version => $node_version );
# Params: 'name' is compulsory, 'version' is optional and defaults to latest.
# Returns a hash of data for C<retrieve_node> - content, version, last modified
sub _retrieve_node_content {
    my ($self, %args) = @_;
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
    return %data;
}

sub _checksum {
    my ($self, %node_data) = @_;
    my $string = $node_data{content};
    my %metadata = %{ $node_data{metadata} || {} };
    foreach my $key ( sort keys %metadata ) {
        $string .= "\0\0\0" . $key . "\0\0"
                 . join("\0", sort @{$metadata{$key}} );
    }
    return md5_hex($string);
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
    carp "retrieve_node_and_checksum is deprecated; please use retrieve_node in list context, instead";
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
    my %node_data = $self->_retrieve_node_data( name => $node );
    return ( $checksum eq $self->_checksum( %node_data ) );
}

=item B<list_backlinks>

  # List all nodes that link to the Home Page.
  my @links = $store->list_backlinks( node => "Home Page" );

=cut

sub list_backlinks {
    my ( $self, %args ) = @_;
    my $node = $args{node};
    croak "Must supply a node name" unless $node;
    my $dbh = $self->dbh;
    my $sql = "SELECT link_from FROM internal_links WHERE link_to="
            . $dbh->quote($node);
    my $sth = $dbh->prepare($sql);
    $sth->execute or croak $dbh->errstr;
    my @backlinks;
    while ( my $backlink = $sth->fetchrow_array ) {
        push @backlinks, $backlink;
    }
    return @backlinks;
}

=item B<write_node_after_locking>

Deprecated, use C<write_node_post_locking> instead. This is still here
for now as a wrapper but it will go away soon.

=cut

sub write_node_after_locking {
    carp "write_node_after_locking is deprecated; please use write_node_post_locking instead";
    my ($self, $node, $content, $links_to_ref) = @_;
    return $self->write_node_post_locking( node     => $node,
                                           content  => $content,
                                           links_to => $links_to_ref );
}

=item B<write_node_post_locking>

  $store->write_node_post_locking( node     => $node,
                                   content  => $content,
                                   links_to => \@links_to,
                                   metadata => \%metadata  )
      or handle_error();

Writes the specified content into the specified node. Making sure that
locking/unlocking/transactions happen is left up to you (or your
chosen subclass). This method shouldn't really be used directly as it
might overwrite someone else's changes. Croaks on error but otherwise
returns true.

Supplying a ref to an array of nodes that this ones links to is
optional, but if you do supply it then this node will be returned when
calling C<list_backlinks> on the nodes in C<@links_to>. B<Note> that
if you don't supply the ref then the store will assume that this node
doesn't link to any others, and update itself accordingly.

The metadata hashref is also optional, but if it is supplied then each
of its keys must be either a scalar or a reference to an array of scalars.

=cut

sub write_node_post_locking {
    my ($self, %args) = @_;
    my ($node, $content, $links_to_ref, $metadata_ref) =
                                @args{ qw( node content links_to metadata) };
    my $dbh = $self->dbh;

    my $timestamp = $self->_get_timestamp();
    my @links_to = @{ $links_to_ref || [] }; # default to empty array
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

    # And to the backlinks.
    $dbh->do("DELETE FROM internal_links WHERE link_from="
             . $dbh->quote($node) ) or croak $dbh->errstr;
    foreach my $links_to ( @links_to ) {
        $sql = "INSERT INTO internal_links (link_from, link_to) VALUES ("
             . join(", ", map { $dbh->quote($_) } ( $node, $links_to ) ) . ")";
        $dbh->do($sql) or croak $dbh->errstr;
    }

    # And also store any metadata.  Note that any entries already in the
    # metadata table refer to old versions, so we don't need to delete them.
    my %metadata = %{ $metadata_ref || {} }; # default to no metadata
    foreach my $type ( keys %metadata ) {
        my $val = $metadata{$type};
        my @values = ref $val ? @$val : ( $val );
        my %unique = map { $_ => 1 } @values;
        @values = keys %unique;
        foreach my $value ( @values ) {
            my $sql = "INSERT INTO metadata "
                    . "(node, version, metadata_type, metadata_value) VALUES ("
                   . join(", ", map { $dbh->quote($_) }
                                    ( $node, $version, $type, $value ) ) . ")";
	    $dbh->do($sql) or croak $dbh->errstr;
	}
    }

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
    my $name = $dbh->quote($node);
    # Should start a transaction here.  FIXME.
    my $sql = "DELETE FROM node WHERE name=$name";
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    $sql = "DELETE FROM content WHERE name=$name";
    $dbh->do($sql) or croak "Deletion failed: " . DBI->errstr;
    $sql = "DELETE FROM internal_links WHERE link_from=$name";
    $dbh->do($sql) or croak $dbh->errstr;
    $sql = "DELETE FROM metadata WHERE node=$name";
    $dbh->do($sql) or croak $dbh->errstr;
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
  print "Comment:       $nodes[0]{metadata}{comment}";


Returns results as an array, in reverse chronological order.  Each
element of the array is a reference to a hash with the following entries:

=over 4

=item * B<name>: the name of the node

=item * B<version>: the latest version number

=item * B<last_modified>: the timestamp of when it was last modified

=item * B<metadata>: a ref to a hash containing any metadata attached
to the current version of the node

=back

Each node will only be returned once, regardless of how many times it
has been changed recently.

B<Note:> interface change between L<CGI::Wiki> 0.23 and 0.24 - this
method used to pretend to return a comment, which was always the blank
string. It now returns the metadata hashref, so you can put your
comments in that.

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

    my @where;
    if ( $since ) {
        my $timestamp = $self->_get_timestamp( $since );
        push @where, "node.modified >= " . $dbh->quote($timestamp);
    }

    my $sql = "SELECT node.name, node.version, node.modified
               FROM node " . ( scalar @where ? " WHERE " . join(" AND ",@where)
			                     : "" )
            . " ORDER BY node.modified DESC";
    if ( $limit ) {
        croak "Bad argument $limit" unless $limit =~ /^\d+$/;
        $sql .= " LIMIT $limit";
    }

    my $nodesref = $dbh->selectall_arrayref($sql);
    my @finds = map { { name          => $_->[0],
			version       => $_->[1],
			last_modified => $_->[2] }
		    } @$nodesref;
    foreach my $find ( @finds ) {
        my %metadata;
        my $sth = $dbh->prepare( "SELECT metadata_type, metadata_value
                                  FROM metadata WHERE node=? AND version=?" );
        $sth->execute( $find->{name}, $find->{version} );
        while ( my ($type, $value) = $sth->fetchrow_array ) {
	    if ( defined $metadata{$type} ) {
                push @{$metadata{$type}}, $value;
	    } else {
                $metadata{$type} = [ $value ];
            }
	}
        $find->{metadata} = \%metadata;
    }
    return @finds;
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

=item B<list_nodes_by_metadata>

  # All nodes that Kake's watching.
  my @nodes = $store->list_nodes_by_metadata(
      metadata_type  => "watched_by",
      metadata_value => "Kake"              );

  # All pubs in Hammersmith.
  my @pubs = $store->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value => "Pub"              );
  my @hsm  = $store->list_nodes_by_metadata(
      metadata_type  => "category",
      metadata_value  => "Hammersmith"     );
  my @results = my_l33t_method_for_ANDing_arrays( \@pubs, \@hsm );

Returns a list containing the name of every node whose caller-supplied
metadata matches the criteria given in the parameters.

If you don't supply any criteria then you'll get an empty list.

This is a really really really simple way of finding things; if you
want to be more complicated then you'll need to call the method
multiple times and combine the results yourself. Or write a plugin,
when I get around to adding support for that.

=cut

sub list_nodes_by_metadata {
    my ($self, %args) = @_;
    my ( $type, $value ) = @args{ qw( metadata_type metadata_value ) };
    return () unless $type;
    my $dbh = $self->dbh;
    my $sql = "SELECT node.name FROM node, metadata"
            . " WHERE node.name=metadata.node"
            . " AND node.version=metadata.version"
            . " AND metadata.metadata_type = " . $dbh->quote($type)
            . " AND metadata.metadata_value = " . $dbh->quote($value);
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

=item B<dbuser>

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
