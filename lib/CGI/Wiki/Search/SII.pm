package CGI::Wiki::Search::SII;

use strict;
use Search::InvertedIndex;
use Carp "croak";

use vars qw( @ISA $VERSION );

$VERSION = 0.04;

=head1 NAME

CGI::Wiki::Search::SII - Search::InvertedIndex search plugin for CGI::Wiki

=head1 SYNOPSIS

  my $indexdb = Search::InvertedIndex::DB::Mysql->new( ... );
  my $search = CGI::Wiki::Search::SII->new( indexdb => $indexdb );
  my %wombat_nodes = $search->search_nodes("wombat");

Provides search-related methods for CGI::Wiki

=cut

=head1 METHODS

=over 4

=item B<new>

  my $indexdb = Search::InvertedIndex::DB::Mysql->new(
                   -db_name    => $dbname,
                   -username   => $dbuser,
                   -password   => $dbpass,
		   -hostname   => '',
                   -table_name => 'siindex',
                   -lock_mode  => 'EX' );
  my $search = CGI::Wiki::Search::SII->new( indexdb => $indexdb );

Takes only one parameter, which is mandatory. C<indexdb> must be a
C<Search::InvertedIndex::DB::*> object.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    return $self->_init(@args);
}

sub _init {
    my ($self, %args) = @_;
    my $indexdb = $args{indexdb};

    my $map = Search::InvertedIndex->new( -database => $indexdb )
      or croak "Couldn't set up Search::InvertedIndex map";
    $map->add_group( -group => "nodes" );

    $self->{_map}  = $map;

    return $self;
}

=item B<search_nodes>

  # Find all the nodes which contain the word 'expert'.
  my %results = $search->search_nodes('expert');

Returns a (possibly empty) hash whose keys are the node names and
whose values are the scores in some kind of relevance-scoring system I
haven't entirely come up with yet. For OR searches, this could
initially be the number of terms that appear in the node, perhaps.

Defaults to AND searches (if $and_or is not supplied, or is anything
other than C<OR> or C<or>).

Searches are case-insensitive.

=cut

sub search_nodes {
    my ($self, $termstr, $and_or) = @_;

    $and_or = lc($and_or);
    unless ( defined $and_or and $and_or eq "or" ) {
        $and_or = "and";
    }

    # Extract individual search terms.
    my @terms = grep { length > 1            # ignore single characters
                      and ! /^\W*$/ }        # and things composed entirely
                                             #   of non-word characters
               split( /\b/,                  # split at word boundaries
                            lc($termstr)     # be case-insensitive
                    );

    # Create a leaf for each search term.
    my @leaves;
    foreach my $term ( @terms ) {
        my $leaf = Search::InvertedIndex::Query::Leaf->new(-key   => $term,
                                                           -group => "nodes" );
        push @leaves, $leaf;
    }

    # Collate the leaves.
    my $query = Search::InvertedIndex::Query->new( -logic => $and_or,
                                                   -leafs => \@leaves );

    # Perform the search and extract the results.
    my $result = $self->{_map}->search( -query => $query );

    my $num_results = $result->number_of_index_entries || 0;
    my %results;
    for my $i ( 1 .. $num_results ) {
        my ($index, $data, $ranking) = $result->entry( -number => $i - 1 );
	$results{$index} = $ranking;
    }
    return %results;
}

=item B<index_node>

  $search->index_node($node);

Indexes or reindexes the given node in the Search::InvertedIndex
indexes.

=cut

sub index_node {
    my ($self, $node, $content) = @_;
    croak "Must supply a node name" unless $node;
    croak "Must supply node content" unless $content;

    my @keys = grep { length > 1                 # ignore single characters
                      and ! /^\W*$/ }            # and things composed entirely
                                                 #   of non-word characters
               split( /\b/,                      # split at word boundaries
                            lc(                  # be case-insensitive
                                "$content $node" # index content and title
                              )
                    );

    my $update = Search::InvertedIndex::Update->new(
        -group => "nodes",
        -index => $node,
        -data  => $content,
        -keys => { map { $_ => 1 } @keys }
    );
    $self->{_map}->update( -update => $update );
}

=item B<delete_node>

  $search->delete_node($node);

Removes the given node from the search indexes.  NOTE: It's up to you to
make sure the node is removed from the backend store.  Croaks on error.

=cut

sub delete_node {
    my ($self, $node) = @_;
    croak "Must supply a node name" unless $node;

    my $update = Search::InvertedIndex::Update->new(
        -group => "nodes",
        -index => $node,
    );
    $self->{_map}->update( -update => $update );
}

=item B<supports_phrase_searches>

  if ( $search->supports_phrase_searches ) {
      return $search->search_nodes( '"fox in socks"' );
  }

Returns true if this search backend supports phrase searching, and
false otherwise.

=cut

sub supports_phrase_searches {
    return 0;
}

=back

=head1 SEE ALSO

L<CGI::Wiki>

=cut

1;
