package CGI::Wiki::Setup::MySQL;

use strict;

use vars qw( $VERSION );
$VERSION = '0.02';

use DBI;
use Carp;

my %create_sql = (
    node => "
CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  PRIMARY KEY (name)
)
",

    content => "
CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  comment   mediumtext   NOT NULL default '',
  PRIMARY KEY (name, version)
)
",
    internal_links => "
CREATE TABLE internal_links (
  link_from varchar(200) NOT NULL default '',
  link_to   varchar(200) NOT NULL default '',
  PRIMARY KEY (link_from, link_to)
)
"
);

=head1 NAME

CGI::Wiki::Setup::MySQL - Set up tables for a CGI::Wiki store in a MySQL database.

=head1 SYNOPSIS

  use CGI::Wiki::Setup::MySQL;
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass);

=head1 DESCRIPTION

Set up a MySQL database for use as a CGI::Wiki store.

=head1 FUNCIONS

=over 4

=item B<setup>

  use CGI::Wiki::Setup::MySQL;
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass);

Takes three arguments -- the database name, the username and the
password. The username must be able to create and drop tables in the
database.

B<NOTE:> If a table that the module wants to create already exists,
C<setup> will leave it alone. This means that you can safely run this
on an existing L<CGI::Wiki> database to bring the schema up to date
with the current L<CGI::Wiki> version. If you wish to completely start
again with a fresh database, run C<cleardb> first.

=cut

sub setup {
    my ($dbname, $dbuser, $dbpass) = (@_);

    my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
			   { PrintError => 1, RaiseError => 1,
			     AutoCommit => 1 } )
      or croak DBI::errstr;

    # Check whether tables exist, set them up if not.
    my $sth = $dbh->prepare("SHOW TABLES") or croak $dbh->errstr;
    $sth->execute;
    my %tables;
    while ( my $table = $sth->fetchrow_array ) {
        $tables{$table} = 1;
    }

    foreach my $required ( keys %create_sql ) {
        if ( $tables{$required} ) {
            print "Table $required already exists... skipping...\n";
        } else {
            print "Creating table $required... done\n";
            $dbh->do($create_sql{$required}) or croak $dbh->errstr;
        }
    }

    # Clean up.
    $dbh->disconnect;
}

=item B<cleardb>

  use CGI::Wiki::Setup::MySQL;

  # Clear out the old database completely, then set up tables afresh.
  CGI::Wiki::Setup::MySQL::cleardb($dbname, $dbuser, $dbpass);
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass);

Takes three arguments -- the database name, the username and the
password. The username must be able to drop tables in the database.

Clears out all L<CGI::Wiki> store tables from the database. B<NOTE>
that this will lose all your data; you probably only want to use this
for testing purposes or if you really screwed up somewhere. Note also
that it doesn't touch any L<CGI::Wiki> search backend tables; if you
have any of those in the same or a different database see either
L<CGI::Wiki::Setup::DBIxFTS> or L<CGI::Wiki::Setup::SII>, depending on
which search backend you're using.

=cut

sub cleardb {
    my ($dbname, $dbuser, $dbpass) = (@_);

    my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
			   { PrintError => 1, RaiseError => 1,
			     AutoCommit => 1 } )
      or croak DBI::errstr;

    print "Dropping tables... ";
    $dbh->do("DROP TABLE IF EXISTS " . join( ",", keys %create_sql ) )
      or croak $dbh->errstr;
    print "done\n";

    # Clean up.
    $dbh->disconnect;
}

=back

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<CGI::Wiki>, L<CGI::Wiki::Setup::DBIxMySQL>, L<CGI::Wiki::Setup::SII>

=cut

1;

