#!/usr/bin/perl -w

use strict;
use DBI;
use Carp;

my ($dbname, $dbuser, $dbpass) = ("cgi_wiki_test", "wiki", "wiki");

my $dbh = DBI->connect("dbi:Pg:dbname=$dbname", $dbuser, $dbpass,
		       { PrintError => 1, RaiseError => 1, AutoCommit => 1 } )
    or croak DBI::errstr;

# Drop tables if they already exist.
my $sql = "SELECT tablename FROM pg_tables
           WHERE tablename in ('node', 'content')";
foreach my $tableref (@{$dbh->selectall_arrayref($sql)}) {
    $dbh->do("DROP TABLE $tableref->[0]") or croak $dbh->errstr;
}

# Set up tables.
$sql = "CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   integer NOT NULL default 0,
  text      text NOT NULL default '',
  modified  datetime default NULL,
  PRIMARY KEY (name)
)";
$dbh->do($sql) or croak $dbh->errstr;

$sql = "CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   integer NOT NULL default 0,
  text      text NOT NULL default '',
  modified  datetime default NULL,
  comment   text NOT NULL default '',
  PRIMARY KEY  (name, version)
)";
$dbh->do($sql) or croak $dbh->errstr;

# Clean up.
$dbh->disconnect;
