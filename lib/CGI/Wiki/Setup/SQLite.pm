package CGI::Wiki::Setup::SQLite;

use strict;

use DBI;
use Carp;

=head1 NAME

CGI::Wiki::Setup::SQLite - set up tables for CGI::Wiki in a SQLite database.

=head1 SYNOPSIS

  use CGI::Wiki::Setup::SQLite;
  CGI::Wiki::Setup::MySQLite::setup($dbfile);

=head1 DESCRIPTION

Set up a SQLite database for use with CGI::Wiki. Has only one function,
C<setup>, which takes as an argument the name of the file to use to store
the database in.

B<Note:> the SQLite database will be dropped and recreated, so you will
lose any extra tables you may have created in it.  I don't think this is
likely to be a problem; tell me if it is.

=cut

sub setup {
    my $dbfile = shift;

    # Drop database entirely before we start.
    unlink $dbfile;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "",
			   { PrintError => 1, RaiseError => 1,
			     AutoCommit => 1 } )
     or croak DBI::errstr;

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

L<CGI::Wiki>, L<CGI::Wiki::Setup::MySQL>, L<CGI::Wiki::Setup::Pg>

=cut

1;

__DATA__
CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   integer      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  PRIMARY KEY (name)
)

CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   integer      NOT NULL default 0,
  text      mediumtext   NOT NULL default '',
  modified  datetime     default NULL,
  comment   mediumtext   NOT NULL default '',
  PRIMARY KEY (name, version)
)

