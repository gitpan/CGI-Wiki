package CGI::Wiki;

use strict;

use vars qw( $VERSION );
$VERSION = '0.20';

use CGI ":standard";
use Carp qw(croak carp);
use Digest::MD5 "md5_hex";
use Class::Delegation
    send => ['retrieve_node', 'retrieve_node_and_checksum', 'verify_checksum',
             'list_all_nodes', 'list_recent_changes', 'node_exists',
             'list_backlinks', 'list_nodes_by_metadata'],
    to   => '_store',
    send => 'delete_node',
    to   => ['_store', '_search'],
    send => ['search_nodes', 'supports_phrase_searches'],
    to   => '_search',
    ;

=head1 NAME

CGI::Wiki - A toolkit for building Wikis.

=head1 DESCRIPTION

Helps you develop Wikis quickly by taking care of the boring bits for
you. The aim is to allow different types of backend storage and search
without you having to worry about the details.

=head1 IMPORTANT NOTE WHEN UPGRADING FROM PRE-0.20 VERSIONS

The database schema changed between versions 0.14 and 0.15, and again
between versions 0.16 and 0.20 - see the 'Changes' file for details. 
This is really kinda important, please do check this out or your code
will die when it tries to use any existing databases.

=head1 NOTE WHEN UPGRADING FROM PRE-0.10 VERSIONS

There was a small interface change between versions 0.05 and 0.10 -
see the 'Changes' file for details.

=head1 SYNOPSIS

  # Set up a wiki object with an SQLite storage backend, and an
  # inverted index/DB_File search backend.  This store/search
  # combination can be used on systems with no access to an actual
  # database server.

  my $store     = CGI::Wiki::Store::SQLite->new(
      dbname => "/home/wiki/store.db" );
  my $indexdb   = Search::InvertedIndex::DB::DB_File_SplitHash->new(
      -map_name  => "/home/wiki/indexes.db",
      -lock_mode => "EX" );
  my $search    = CGI::Wiki::Search::SII->new(
      indexdb => $indexdb );

  my $wiki      = CGI::Wiki->new( store     => $store,
                                  search    => $search );

  # Do all the CGI stuff.
  my $q      = CGI->new;
  my $action = $q->param("action");
  my $node   = $q->param("node");

  if ($action eq 'display') {
      my $raw    = $wiki->retrieve_node($node);
      my $cooked = $wiki->format($raw);
      print_page(node    => $node,
		 content => $cooked);
  } elsif ($action eq 'preview') {
      my $submitted_content = $q->param("content");
      my $preview_html      = $wiki->format($submitted_content);
      print_editform(node    => $node,
	             content => $submitted_content,
	             preview => $preview_html);
  } elsif ($action eq 'commit') {
      my $submitted_content = $q->param("content");
      my $cksum = $q->param("checksum");
      my $written = $wiki->write_node($node, $submitted_content, $cksum);
      if ($written) {
          print_success($node);
      } else {
          handle_conflict($node, $submitted_content);
      }
  }

=head1 METHODS

=over 4

=item B<new>

  # Set up store, search and formatter objects.
  my $store     = CGI::Wiki::Store::SQLite->new(
      dbname => "/home/wiki/store.db" );
  my $indexdb   = Search::InvertedIndex::DB::DB_File_SplitHash->new(
      -map_name  => "/home/wiki/indexes.db",
      -lock_mode => "EX" );
  my $search    = CGI::Wiki::Search::SII->new(
      indexdb => $indexdb );
  my $formatter = My::HomeMade::Formatter->new;

  my $wiki = CGI::Wiki->new(
      store     => $store,     # mandatory
      search    => $search,    # defaults to undef
      formatter => $formatter  # defaults to something suitable
  );

C<store> must be an object of type C<CGI::Wiki::Store::*> and
C<search> if supplied must be of type C<CGI::Wiki::Search::*> (though
this isn't checked yet - FIXME). If C<formatter> isn't supplied, it
defaults to an object of class L<CGI::Wiki::Formatter::Default>.

You can get a searchable Wiki up and running on a system without an
actual database server by using the SQLite storage backend with the
SII/DB_File search backend - cut and paste the lines above for a quick
start, and see L<CGI::Wiki::Store::SQLite>, L<CGI::Wiki::Search::SII>,
and L<Search::InvertedIndex::DB::DB_File_SplitHash> when you want to
learn the details.

C<formatter> can be any object that behaves in the right way; this
essentially means that it needs to provide a C<format> method which
takes in raw text and returns the formatted version. See
L<CGI::Wiki::Formatter::Default> for an example. Note that you can
create a suitable object from a sub very quickly by using
L<Test::MockObject> like so:

  my $formatter = Test::MockObject->new();
  $formatter->mock( 'format', sub { my ($self, $raw) = @_;
                                    return uc( $raw );
                                  } );

I'm not sure whether to put this in the module or not - it'd let you
just supply a sub instead of an object as the formatter, but it feels
wrong to be using a Test::* module in actual code.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    $self->_init(@args) or return undef;
    return $self;
}

sub _init {
    my ($self, %args) = @_;

    # Check for scripts written with old versions of CGI::Wiki
    foreach my $obsolete_param ( qw( storage_backend search_backend ) ) {
        carp "You seem to be using a script written for a pre-0.10 version "
           . "of CGI::Wiki - the $obsolete_param parameter is no longer used. "
           . "Please read the documentation with 'perldoc CGI::Wiki'"
          if $args{$obsolete_param};
    }

    croak "No store supplied" unless $args{store};

    foreach my $k ( qw( store search formatter ) ) {
        $self->{"_".$k} = $args{$k};
    }

    # Make a default formatter object if none was actually supplied.
    unless ( $args{formatter} ) {
        require CGI::Wiki::Formatter::Default;
        # Ensure backwards compatibility - versions prior to 0.11 allowed the
        # following options to alter the default behaviour of Text::WikiFormat.
        my %config;
        foreach ( qw( extended_links implicit_links allowed_tags
		    macros node_prefix ) ) {
            $config{$_} = $args{$_} if defined $args{$_};
	}
        $self->{_formatter} = CGI::Wiki::Formatter::Default->new( %config );
    }

    return $self;
}

=item B<write_node>

  my $written = $wiki->write_node($node, $content, $checksum, \%metadata);
  if ($written) {
      display_node($node);
  } else {
      handle_conflict();
  }

Writes the specified content into the specified node in the backend
storage, and indexes/reindexes the node in the search indexes, if a
search is set up. Note that you can blank out a node without deleting
it by passing the empty string as $content, if you want to.

If you expect the node to already exist, you must supply a checksum,
and the node is write-locked until either your checksum has been
proved old, or your checksum has been accepted and your change
committed.  If no checksum is supplied, and the node is found to
already exist and be nonempty, a conflict will be raised.

The first three parameters are mandatory. The metadata hashref is
optional, but if it is supplied then each of its keys must be either a
scalar or a reference to an array of scalars.

(If you want to supply metadata but have no checksum (for a
newly-created node), supply a checksum of C<undef>.)

Returns 1 on success, 0 on conflict, croaks on error.

=cut

sub write_node {
    my ($self, $node, $content, $checksum, $metadata) = @_;
    croak "No valid node name supplied for writing" unless $node;
    croak "No content parameter supplied for writing" unless defined $content;
    $checksum = md5_hex("") unless defined $checksum;

    my $formatter = $self->{_formatter};
    my @links_to;
    if ( $formatter->can( "find_internal_links" ) ) {
        my @all_links_to = $formatter->find_internal_links( $content );
        my %unique = map { $_ => 1 } @all_links_to;
        @links_to = keys %unique;
    }

    my %data = ( node     => $node,
		 content  => $content,
		 checksum => $checksum,
                 metadata => $metadata );
    $data{links_to} = \@links_to if scalar @links_to;

    my $store = $self->store;
    $store->check_and_write_node( %data ) or return 0;

    my $search = $self->{_search};
    if ($search) {
        $search->index_node($node, $content);
    }
    return 1;
}

=item B<format>

  my $cooked = $wiki->format($raw);

Passed straight through to your chosen formatter object.

=cut

sub format {
    my ( $self, $raw ) = @_;
    my $formatter = $self->{_formatter};
    # Add on $self to the call so the formatter can access things like whether
    # a linked-to node exists, etc.
    return $formatter->format( $raw, $self );
}

=item B<store>

  my $store  = $wiki->store;
  my $dbname = eval { $wiki->store->dbname; }
    or warn "Not a DB backend";

Returns the storage backend object.

=cut

sub store {
    my $self = shift;
    return $self->{_store};
}

=item B<search_obj>

  my $search_obj = $wiki->search_obj;

Returns the search backend object.

=cut

sub search_obj {
    my $self = shift;
    return $self->{_search};
}

# Now for the things that are provided by the various plugins.

=item B<Methods provided by storage backend>

See the docs for your chosen storage backend to see how these work.

=over 4

=item * delete_node (also calls the delete_node method in the search
backend, if any)

=item * list_all_nodes

=item * list_backlinks

=item * list_nodes_by_metadata

=item * list_recent_changes

=item * node_exists

=item * retrieve_node

=item * retrieve_node_and_checksum (deprecated)

=item * verify_checksum

=back

=item B<Methods provided by search backend>

See the docs for your chosen search backend to see how these work.

=over 4

=item * search_nodes

=item * supports_phrase_searches

=back

=item B<Methods provided by formatter backend>

See the docs for your chosen formatter backend to see how these work.

=over 4

=item * format

=back

=back

=head1 SEE ALSO

=over 4

=item * L<CGI::Wiki::Formatter::Default>

=item * L<CGI::Wiki::Store::MySQL>

=item * L<CGI::Wiki::Store::Pg>

=item * L<CGI::Wiki::Store::SQLite>

=item * L<CGI::Wiki::Store::Database>

=item * L<CGI::Wiki::Search::DBIxFTS>

=item * L<CGI::Wiki::Search::SII>

=item * L<DBIx::FullTextSearch>

=item * L<Search::InvertedIndex>

=item * L<Text::WikiFormat>

=back

Other ways to implement Wikis in Perl include:

=over 4

=item * L<CGI::pWiki>

=item * L<AxKit::XSP::Wiki>

=item * L<Apache::MiniWiki>

=item * UseModWiki

=back

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002-2003 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FEEDBACK

Please send me mail and tell me what you think of this.  It's my first
CPAN module, so stuff probably sucks.  Tell me what sucks, send me
patches, send me tests.  Or if it doesn't suck, tell me that too.  I
love getting mail, even if all it says is "I used your thing and I
like it", or "I didn't use your thing because of X".

blair christensen, Clint Moore and Max Maischein won the beer.

=head1 CREDITS

Various London.pm types helped out with code review, encouragement,
JFDI, style advice, code snippets, module recommendations, and so on;
far too many to name individually, but particularly Richard Clamp,
Tony Fisher, Mark Fowler, and Chris Ball.

blair christensen sent patches and gave me some good ideas.  chromatic
patiently applied my patches to L<Text::WikiFormat>.

And never forget to say thanks to those who wrote the stuff that your
module depends on. Come claim beer or home-made cakes[0] at the next
YAPC, people.

[0] cakes require pre-booking

=head1 CGI::WIKI IN ACTION!

Max Maischein has set up a CGI::Wiki-based wiki describing various
file formats, at L<http://www.corion.net/cgi-bin/wiki.cgi>

I've set up a clone of grubstreet, a usemod wiki, at
L<http://the.earth.li/~kake/cgi-bin/cgi-wiki/wiki.cgi> -- it's not yet
feature complete, and it uses a custom formatter module based on
L<CGI::Wiki::Formatter::Default>, but other than the formatter (which
will be released if/when my latest patches go into L<Text::WikiFormat>
:) ) it's pure CGI::Wiki. Code is at
L<http://the.earth.li/~kake/code/cgi-wiki-usemod-emulator/>

=head1 GRATUITOUS PLUG

I'm only obsessed with Wikis because of the Open-Source Guide to
London -- http://grault.net/grubstreet/

=cut

1;
