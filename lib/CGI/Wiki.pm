package CGI::Wiki;

use strict;

use vars qw( $VERSION );
$VERSION = 0.03;

use CGI ":standard";
use Carp qw(croak carp);
use Text::WikiFormat as => 'wikiformat';
use HTML::PullParser;
use Digest::MD5 "md5_hex";
use Class::Delegation
    send => ['retrieve_node', 'verify_checksum', 'list_all_nodes',
	     'list_recent_changes'],
    to   => '_store',
    send => 'delete_node',
    to   => ['_store', '_search'],
    send => 'search_nodes',
    to   => '_search',
    ;

=head1 NAME

CGI::Wiki - A toolkit for building Wikis.

=head1 REQUIRES

Uses Text::WikiFormat and HTML::PullParser to do the HTML translation,
Digest::MD5 to make checksums, and Class::Delegation to avoid ugliness.

=head1 DESCRIPTION

Helps you develop Wikis quickly by taking care of the boring bits for
you. The aim is to allow different types of backend storage and search
without you having to worry about the details.

=head1 SYNOPSIS

  my $wiki   = CGI::Wiki->new(%config); # See below for parameter details
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

 my %config = ( storage_backend => 'mysql',
		dbname          => 'wiki',
		dbuser          => 'wiki',
		dbpass          => 'wiki',
                search_backend  => 'dbixfts', # defaults to undef
                extended_links  => 0,
                implicit_links  => 1,
                allowed_tags    => [qw(b i)], # defaults to none
                macros          => {},
	        node_prefix     => 'wiki.cgi?node=' );


  my $wiki = CGI::Wiki->new(%config);

Currently the only storage backends supported are C<mysql> and
C<postgres>, and the only search backend supported (other than no
search at all) is C<dbixfts>, which uses the DBIx::FullTextSearch
module, and so can only be used with MySQL.

The parameters will default to the values shown above (apart from
C<allowed_tags>, which defaults to allowing no tags, and
C<search_backend>, which defaults to not providing any search
methods). (If you're using a method of database authentication that
doesn't require a password, then leave out C<dbpass> or just put any
old junk in there.)

=over 4

=item * macros - be aware that macros are processed I<after> filtering
out disallowed HTML tags.  Currently macros are just strings, maybe later
we can add in subs if we think it might be useful.

=back

Macro example:

  macros => { qr/(^|\b)\@SEARCHBOX(\b|$)/ =>
 	        qq(<form action="wiki.cgi" method="get">
                   <input type="hidden" name="action" value="search">
                   <input type="text" size="20" name="terms">
                   <input type="submit"></form>) }

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

    # Store the optional scalar parameters or their defaults.
    my %defs = ( storage_backend => 'mysql',
		 dbname          => 'wiki',
		 dbuser          => 'wiki',
		 dbpass          => 'wiki',
		 search_backend  => undef,
	         extended_links  => 0,
	         implicit_links  => 1,
		 allowed_tags    => [],
		 macros          => {},
	         node_prefix     => 'wiki.cgi?node=',
	       );

    my %collated = (%defs, %args);
    foreach my $k (keys %defs) {
        $self->{"_".$k} = $collated{$k};
    }

    # Make sure that the storage backend is one we support, and
    # connect to it if so. *BACKEND*
    my $store_type = $self->{_storage_backend};
    if ($store_type eq "mysql") {
        require CGI::Wiki::Store::MySQL;
        eval { $self->{_store} = CGI::Wiki::Store::MySQL->new(
                   dbname => $self->{_dbname},
	           dbuser => $self->{_dbuser},
                   dbpass => $self->{_dbpass},
		   checksum_method => \&md5_hex           )
            };
        croak "Failed to connect to storage backend $store_type: $@" if $@;
    } elsif ($store_type eq "postgres") {
        require CGI::Wiki::Store::Pg;
        eval { $self->{_store} = CGI::Wiki::Store::Pg->new(
                   dbname => $self->{_dbname},
		   dbuser => $self->{_dbuser},
		   dbpass => $self->{_dbpass},
		   checksum_method => \&md5_hex        )
            };
        croak "Failed to connect to storage backend $store_type: $@" if $@;
    } else {
        croak "Storage backend '$store_type' is not currently supported";
    }

    # Make sure that the search backend is one we support, and set it up.
    my $search_type = $self->{_search_backend};
    if (defined $search_type) {
        if ($search_type eq 'dbixfts') {
            require CGI::Wiki::Search::DBIxFTS;
	    my $store_dbh = $self->{_store}->dbh;
            eval {
                $self->{_search} = CGI::Wiki::Search::DBIxFTS->new(
                    dbh => $store_dbh );
            };
            croak "Couldn't set up search object: $@" if $@;
        } else {
            croak "Search backend '$search_type' is not supported";
        }
    }

    return $self;
}

=item B<retrieve_node_and_checksum>

  my ($content, $cksum) = $wiki->retrieve_node_and_checksum($node);

Works just like retrieve_node, but also gives you a checksum that
you must send back when you want to commit changes, so you can check that
no other changes have been committed while you were editing.  Currently
it's just the md5sum of the node content.

=cut

sub retrieve_node_and_checksum {
    my ($self, $node) = @_;
    my $content = $self->retrieve_node($node);
    my $checksum = md5_hex($content);
    return ($content, $checksum);
}

=item B<format>

  my $html = $wiki->format($submitted_content);

Escapes any tags which weren't specified as allowed on creation, then
interpolates any macros, then calls Text::WikiFormat::format (with the
config set up when B<new> was called) to translate the raw Wiki
language supplied into HTML.

=cut

sub format {
    my ($self, $raw) = @_;
    my $safe = "";

    my %allowed = map {lc($_) => 1, "/".lc($_) => 1} @{$self->{_allowed_tags}};

    if (scalar keys %allowed) {
        # If we are allowing some HTML, parse and get rid of the nasties.
	my $parser = HTML::PullParser->new(doc   => $raw,
					   start => '"TAG", tag, text',
					   end   => '"TAG", tag, text',
					   text  => '"TEXT", tag, text');
	while (my $token = $parser->get_token) {
            my ($flag, $tag, $text) = @$token;
	    if ($flag eq "TAG" and !defined $allowed{lc($tag)}) {
	        $safe .= CGI::escapeHTML($text);
	    } else {
                $safe .= $text;
            }
        }
    } else {
        # Else just escape everything.
        $safe = CGI::escapeHTML($raw);
    }

    # Now process any macros.
    my %macros = %{$self->{_macros}};
    foreach my $regexp (keys %macros) {
        $safe =~ s/$regexp/$macros{$regexp}/g;
    }

    return wikiformat($safe, {},
		      { extended       => $self->{_extended_links},
			prefix         => $self->{_node_prefix},
			implicit_links => $self->{_implicit_links} } );
}

=item B<write_node>

  my $written = $wiki->write_node($node, $content, $checksum);
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

All parameters are mandatory.  Returns 1 on success, 0 on conflict,
croaks on error.

=cut

sub write_node {
    my ($self, $node, $content, $checksum) = @_;
    croak "No valid node name supplied for writing" unless $node;
    croak "No content parameter supplied for writing" unless defined $content;
    $checksum = md5_hex("") unless defined $checksum;

    my $store = $self->{_store};
    $store->check_and_write_node( node     => $node,
				  content  => $content,
				  checksum => $checksum ) or return 0;

    my $search = $self->{_search};
    if ($search) {
        $search->index_node($node);
    }
    return 1;
}


# Now for the things that are provided by the various plugins.

=item B<Methods provided by storage backend>

See the docs for your chosen storage backend to see how these work.

=over 4

=item * delete_node (also calls the delete_node method in the search
backend, if any)

=item * list_all_nodes

=item * list_recent_changes

=item * retrieve_node

=item * verify_checksum

=back

=item B<Methods provided by search backend>

See the docs for your chosen search backend to see how these work.

=over 4

=item * search_nodes

=back

=back

=head1 SEE ALSO

  CGI::Wiki::Store::MySQL
  CGI::Wiki::Store::Pg
  CGI::Wiki::Store::Database
  CGI::Wiki::Search::DBIxFTS
  Text::WikiFormat

Other ways to implement Wikis in Perl include:

=over 4

=item * CGI::pWiki

=item * AxKit::XSP::Wiki

=item * UseModWiki

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FEEDBACK

Please send me mail and tell me what you think of this.  It's my first
CPAN module, so stuff probably sucks.  Tell me what sucks, send me
patches, send me tests.  Or if it doesn't suck, tell me that too.  I
love getting mail, even if all it says is "I used your thing and I
like it", or "I didn't use your thing because of X".

I will buy beer or cider (two pints, litres, or similarly-sized bottles
of, not exchangeable for lager or other girly drinks, will probably
need to be claimed in person in whichever city I'm in at the time) for
the first three people to send me such mail.

=head1 CREDITS

Various London.pm types helped out with code review, encouragement,
JFDI, style advice, code snippets, module recommendations, and so on;
far too many to name individually, but particularly Richard Clamp,
Tony Fisher, Mark Fowler, and Chris Ball.

And never forget to say thanks to those who wrote the stuff that your
module depends on. Come claim beer or home-made cakes[0] at the next
YAPC, people.

[0] cakes require pre-booking

=head1 GRATUITOUS PLUG

I'm only obsessed with Wikis because of the Open-Source Guide to
London -- http://grault.net/grubstreet/

=cut

1;
