package CGI::Wiki::Setup::DBIxFTSMySQL;

use strict;

use DBI;
use DBIx::FullTextSearch;
use Carp;

=head1 NAME

CGI::Wiki::Setup::DBIxFTSMySQL - set up fulltext indexes for CGI::Wiki

=head1 SYNOPSIS

  use CGI::Wiki::Setup::DBIxFTSMySQL;
  CGI::Wiki::Setup::DBIxFTSMySQL::setup($dbname, $dbuse, $dbpass);

=head1 DESCRIPTION

Set up DBIx::FullTextSearch indexes for use with CGI::Wiki. Has only
one function, C<setup>, which takes as arguments the database name,
the username and the password. The username must be able to create and
drop tables in the database.

=cut

sub setup
{
  my ($dbname, $dbuser, $dbpass) = (@_);

  my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
			 { PrintError => 1, RaiseError => 1, AutoCommit => 1 } )
    or croak DBI::errstr;

  # Drop FTS indexes if they already exist.
  my $fts = DBIx::FullTextSearch->open($dbh, "_content_and_title_fts");
  $fts->drop if $fts;
  $fts = DBIx::FullTextSearch->open($dbh, "_title_fts");
  $fts->drop if $fts;

  # Set up FullText indexes and index anything already extant.
  my $fts_all = DBIx::FullTextSearch->create($dbh, "_content_and_title_fts",
					     frontend       => "table",
					     backend        => "phrase",
					     table_name     => "node",
					     column_name    => ["name","text"],
					     column_id_name => "name",
					     stemmer        => "en-uk");

  my $fts_title = DBIx::FullTextSearch->create($dbh, "_title_fts",
					       frontend       => "table",
					       backend        => "phrase",
					       table_name     => "node",
					       column_name    => "name",
					       column_id_name => "name",
					       stemmer        => "en-uk");

  my $sql = "SELECT name FROM node";
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  while (my ($name, $version) = $sth->fetchrow_array) {
    $fts_title->index_document($name);
    $fts_all->index_document($name);
  }
  $sth->finish;
}

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<CGI::Wiki>, L<CGI::Wiki::Setup::MySQL>, L<DBIx::FullTextSearch>

=cut

1;
