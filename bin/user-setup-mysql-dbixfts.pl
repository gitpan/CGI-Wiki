#!/usr/bin/perl -w

use strict;
use DBI;
use DBIx::FullTextSearch;
use Carp;

my ($dbname, $dbuser, $dbpass) = ("kakewiki", "wiki", "wiki");

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
