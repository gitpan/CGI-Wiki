package CGI::Wiki::TestConfig::Utilities;

use strict;

use CGI::Wiki::TestConfig;

use vars qw( $num_stores $num_combinations $VERSION );
$VERSION = '0.02';

=head1 NAME

CGI::Wiki::TestConfig::Utilities - Utilities for testing CGI::Wiki things.

=head1 DESCRIPTION

When 'perl Makefile.PL' is run on a CGI::Wiki distribution,
information will be gathered about test databases etc that can be used
for running tests. CGI::Wiki::TestConfig::Utilities gives you
convenient access to this information, so you can easily write and run
tests for your own CGI::Wiki plugins.

=head1 SYNOPSIS

  # Reinitialise every configured storage backend.
  use strict;
  use CGI::Wiki;
  use CGI::Wiki::TestConfig::Utilities;

  CGI::Wiki::TestConfig::Utilities->reinitialise_stores;


  # Run all our tests for every possible storage backend.

  use strict;
  use CGI::Wiki;
  use CGI::Wiki::TestConfig::Utilities;
  use Test::More tests =>
                   (8 * $CGI::Wiki::TestConfig::Utilities::num_stores);

  my %stores = CGI::Wiki::TestConfig::Utilities->stores;

  my ($store_name, $store);
  while ( ($store_name, $store) = each %stores ) {
      SKIP: {
        skip "$store_name storage backend not configured for testing", 8
            unless $store;

        # PUT YOUR TESTS HERE
      }
  }


  # Or maybe we want to run tests for every combination of store
  # and search.

  use strict;
  use CGI::Wiki::TestConfig::Utilities;
  use Test::More tests =>
         (1 + 11 * $CGI::Wiki::TestConfig::Utilities::num_combinations);

  use_ok( "CGI::Wiki::Plugin::Location" );

  # Test for each configured pair: $store, $search.
  my @tests = CGI::Wiki::TestConfig::Utilities->combinations;
  foreach my $configref (@tests) {
      my %testconfig = %$configref;
      my ( $store_name, $store, $search_name, $search, $configured ) =
         @testconfig{qw(store_name store search_name search configured)};
      SKIP: {
        skip "Store $store_name and search $search_name"
	     . " not configured for testing", 11 unless $configured;

        # PUT YOUR TESTS HERE
      }
  }

=cut

my %stores;

foreach my $dbtype (qw( MySQL Pg SQLite )) {
    if ($CGI::Wiki::TestConfig::config{$dbtype}->{dbname}) {
        my %config = %{$CGI::Wiki::TestConfig::config{$dbtype}};
	my $store_class = "CGI::Wiki::Store::$dbtype";
	eval "require $store_class";
	my $store = $store_class->new( dbname => $config{dbname},
				       dbuser => $config{dbuser},
				       dbpass => $config{dbpass} );
	$stores{$dbtype} = $store;
    } else {
	$stores{$dbtype} = undef;
    }
}

$num_stores = scalar keys %stores;

my %searches;

# DBIxFTS only works with MySQL.
if ( $CGI::Wiki::TestConfig::config{dbixfts} && $stores{MySQL} ) {
    require CGI::Wiki::Search::DBIxFTS;
    my $dbh = $stores{MySQL}->dbh;
    $searches{DBIxFTSMySQL} = CGI::Wiki::Search::DBIxFTS->new( dbh => $dbh );
} else {
    $searches{DBIxFTSMySQL} = undef;
}

# Test the MySQL SII backend, if we can.
if ( $CGI::Wiki::TestConfig::config{search_invertedindex} && $stores{MySQL} ) {
    require Search::InvertedIndex::DB::Mysql;
    require CGI::Wiki::Search::SII;
    my %dbconfig = %{$CGI::Wiki::TestConfig::config{MySQL}};
    my $indexdb = Search::InvertedIndex::DB::Mysql->new(
                       -db_name    => $dbconfig{dbname},
                       -username   => $dbconfig{dbuser},
                       -password   => $dbconfig{dbpass},
	   	       -hostname   => '',
                       -table_name => 'siindex',
                       -lock_mode  => 'EX' );
    $searches{SIIMySQL} = CGI::Wiki::Search::SII->new( indexdb => $indexdb );
} else {
    $searches{SIIMySQL} = undef;
}

# Also test the default DB_File backend, if we have S::II installed at all.
if ( $CGI::Wiki::TestConfig::config{search_invertedindex} ) {
    require Search::InvertedIndex;
    require CGI::Wiki::Search::SII;
    my $indexdb = Search::InvertedIndex::DB::DB_File_SplitHash->new(
                       -map_name  => 't/sii-db-file-test.db',
                       -lock_mode  => 'EX' );
    $searches{SII} = CGI::Wiki::Search::SII->new( indexdb => $indexdb );
} else {
    $searches{SII} = undef;
}

my @combinations; # which searches work with which stores.
push @combinations, { store_name  => "MySQL",
		      store       => $stores{MySQL},
		      search_name => "DBIxFTSMySQL",
		      search      => $searches{DBIxFTSMySQL} };
push @combinations, { store_name  => "MySQL",
		      store       => $stores{MySQL},
		      search_name => "SIIMySQL",
		      search      => $searches{SIIMySQL} };

# All stores are compatible with the default S::II search, and with no search.
foreach my $store_name ( keys %stores ) {
    push @combinations, { store_name  => $store_name,
			  store       => $stores{$store_name},
			  search_name => "SII",
			  search      => $searches{SII} };
    push @combinations, { store_name  => $store_name,
			  store       => $stores{$store_name},
			  search_name => "undef",
			  search      => undef };
}

foreach my $comb ( @combinations ) {
    # There must be a store configured for us to test, but a search is optional
    $comb->{configured} = $comb->{store} ? 1 : 0;
}

$num_combinations = scalar @combinations;

=head1 METHODS

=over 4

=item B<reinitialise_stores>

  # Reinitialise every configured storage backend.
  use strict;
  use CGI::Wiki;
  use CGI::Wiki::TestConfig::Utilities;

  CGI::Wiki::TestConfig::Utilities->reinitialise_stores;

Clears out all of the configured storage backends.

=cut

sub reinitialise_stores {
    my $class = shift;
    my %stores = $class->stores;

    my ($store_name, $store);
    while ( ($store_name, $store) = each %stores ) {
        next unless $store;

        my $dbname = $store->dbname;
        my $dbuser = $store->dbuser;
        my $dbpass = $store->dbpass;

        # Clear out the test database, then set up tables afresh.
        my $setup_class = "CGI::Wiki::Setup::$store_name";
        eval "require $setup_class";
        {
          no strict "refs";
          &{"$setup_class\:\:cleardb"}($dbname, $dbuser, $dbpass);
          &{"$setup_class\:\:setup"}($dbname, $dbuser, $dbpass);
        }
    }
}

=item B<stores>

  my %stores = CGI::Wiki::TestConfig::Utilities->stores;

Returns a hash whose keys are the names of all possible storage
backends (eg, C<MySQL>, C<Pg>, C<SQLite>) and whose values are either
a corresponding CGI::Wiki::Store::* object, if one has been
configured, or C<undef>, if no corresponding store has been
configured.

You can find out at BEGIN time how many of these to expect; it's stored in
C<$CGI::Wiki::TestConfig::Utilities::num_stores>

=cut  

sub stores {
    return %stores;
}

=item B<combinations>

  my @combs = CGI::Wiki::TestConfig::Utilities->combinations;

Returns an array of references to hashes, one each for every possible
combination of storage and search backends.

The hash entries are as follows:

=over 4

=item B<store_name> - eg C<MySQL>, C<Pg>, C<SQLite>

=item B<store> - a CGI::Wiki::Store::* object corresponding to
C<store_name>, if one has been configured, or C<undef>, if no
corresponding store has been configured.

=item B<search_name> - eg C<DBIxFTSMySQL>, C<SIIMySQL>, C<SII>

=item B<search> - a CGI::Wiki::Search::* object corresponding to
C<search_name>, if one has been configured, or C<undef>, if no
corresponding search has been configured.

=item B<configured> - true if this combination has been sufficiently
configured to run tests on, false otherwise.


=back

You can find out at BEGIN time how many of these to expect; it's stored in
C<$CGI::Wiki::TestConfig::Utilities::num_combinations>

=cut  

sub combinations {
    return @combinations;
}

=back

=head1 SEE ALSO

L<CGI::Wiki>

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2003 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 CAVEATS

If you have the L<Search::InvertedIndex> backend configured (see
L<CGI::Wiki::Search::SII>) then your tests will raise warnings like

  (in cleanup) Search::InvertedIndex::DB::Mysql::lock() -
    testdb is not open. Can't lock.
  at /usr/local/share/perl/5.6.1/Search/InvertedIndex.pm line 1348

or

  (in cleanup) Can't call method "sync" on an undefined value
    at /usr/local/share/perl/5.6.1/Tie/DB_File/SplitHash.pm line 331
    during global destruction.

in unexpected places. I don't know whether this is a bug in me or in
L<Search::InvertedIndex>.

=cut

1;
