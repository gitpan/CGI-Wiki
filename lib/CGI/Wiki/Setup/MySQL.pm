package CGI::Wiki::Setup::MySQL;

use strict;

use DBI;
use Carp;

=head1 NAME

CGI::Wiki::Setup::MySQL - set up tables for CGI::Wiki in a MySQL database.

=head1 SYNOPSIS

  use CGI::Wiki::Setup::MySQL;
  CGI::Wiki::Setup::MySQL::setup($dbname, $dbuser, $dbpass);

=head1 DESCRIPTION

Set up a MySQL database for use with CGI::Wiki. Has only one function,
C<setup>, which takes as arguments the database name, the username and
the password. The username must be able to create and drop tables in
the database.

=cut

sub setup {
    my ($dbname, $dbuser, $dbpass) = (@_);

    my $dbh = DBI->connect("dbi:mysql:$dbname", $dbuser, $dbpass,
			   { PrintError => 1, RaiseError => 1,
			     AutoCommit => 1 } )
     or croak DBI::errstr;

    # Drop tables if they already exist; then set them up.
    {
      local $/ = "\n\n";
      while (my $sql = <DATA>) {
          $dbh->do($sql) or croak $dbh->errstr;
      }
    }

    # Clean up.
    $dbh->disconnect;
}

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002 Kake Pugh.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<CGI::Wiki>, L<CGI::Wiki::Setup::DBIxMySQL>, L<CGI::Wiki::Setup::Pg>

=cut

1;

__DATA__
DROP TABLE IF EXISTS node, content

CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  PRIMARY KEY (name)
)

CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   int(10)      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  comment   mediumtext   NOT NULL default '',
  PRIMARY KEY (name, version)
)

