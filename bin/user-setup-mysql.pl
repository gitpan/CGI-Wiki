#!/usr/bin/perl -w

use strict;
use DBI;
use Carp;

my ($dbname, $dbuser, $dbpass) = ("kakewiki", "wiki", "wiki");

my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
		       { PrintError => 1, RaiseError => 1, AutoCommit => 1 } )
    or croak DBI::errstr;

# Drop tables if they already exist.
my $sql;
$sql = "DROP TABLE IF EXISTS node, content";
$dbh->do($sql) or croak $dbh->errstr;

# Set up tables.
$sql = "CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   int(10) NOT NULL default 0,
  text      mediumtext NOT NULL default '',
  modified  datetime default NULL,
  PRIMARY KEY (name)
)";
$dbh->do($sql) or croak $dbh->errstr;

$sql = "CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   int(10) NOT NULL default 0,
  text      mediumtext NOT NULL default '',
  modified  datetime default NULL,
  comment   mediumtext NOT NULL default '',
  PRIMARY KEY  (name, version)
)";
$dbh->do($sql) or croak $dbh->errstr;

# Clean up.
$dbh->disconnect;
