package CGI::Wiki::Setup::Pg;

use strict;

use DBI;
use Carp;

=head1 NAME

CGI::Wiki::Setup::Pg - set up tables for CGI::Wiki in a Postgres database.

=head1 SYNOPSIS

  use CGI::Wiki::Setup::Pg;
  CGI::Wiki::Setup::Pg::setup($dbname, $dbuser, $dbpass);

=head1 DESCRIPTION

Set up a Postgres database for use with CGI::Wiki. Has only one function,
C<setup>, which takes as arguments the database name, the username and
the password. The username must be able to create and drop tables in
the database.

=cut

sub setup {
    my ($dbname, $dbuser, $dbpass) = (@_);

    my $dbh = DBI->connect("dbi:Pg:dbname=$dbname", $dbuser, $dbpass,
                           { PrintError => 1, RaiseError => 1,
                             AutoCommit => 1 } )
      or croak DBI::errstr;

    # Drop tables if they already exist.
    my $sql = "SELECT tablename FROM pg_tables
               WHERE tablename in ('node', 'content')";
    foreach my $tableref (@{$dbh->selectall_arrayref($sql)}) {
        $dbh->do("DROP TABLE $tableref->[0]") or croak $dbh->errstr;
    }

    # Now set them up.
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

L<CGI::Wiki>, L<CGI::Wiki::Setup::MySQL>

=cut

1;

__DATA__
CREATE TABLE node (
  name      varchar(200) NOT NULL DEFAULT '',
  version   integer      NOT NULL default 0,
  text      text         NOT NULL default '',
  modified  datetime     default NULL
)

CREATE UNIQUE INDEX node_pkey ON node (name)

CREATE TABLE content (
  name      varchar(200) NOT NULL default '',
  version   integer      NOT NULL default 0,
  text      text         NOT NULL default '',
  modified  datetime     default NULL,
  comment   text         NOT NULL default ''
)

CREATE UNIQUE INDEX content_pkey ON content (name, version)
