#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use CGI::Wiki::Setup::Pg;

my ($dbname, $dbuser, $dbpass, $help, $preclear);
GetOptions( "name=s"         => \$dbname,
            "user=s"         => \$dbuser,
            "pass=s"         => \$dbpass,
            "help"           => \$help,
            "force-preclear" => \$preclear
           );

unless (defined($dbname)) {
    print "You must supply a database name with the --name option\n";
    print "further help can be found by typing 'perldoc $0'\n";
    exit 1;
}

if ($help) {
    print "Help can be found by typing 'perldoc $0'\n";
    exit 0;
}

if ($preclear) {
    CGI::Wiki::Setup::Pg::cleardb($dbname, $dbuser, $dbpass);
}

CGI::Wiki::Setup::Pg::setup($dbname, $dbuser, $dbpass);

=head1 NAME

user-setup-postgres - set up a Postgres storage backend for CGI::Wiki

=head1 SYNOPSIS

# Set up or update the storage backend, leaving any existing data intact.
# Useful for upgrading from old versions of CGI::Wiki to newer ones with
# more backend features.

  user-setup-postgres --name mywiki \
                      --user wiki  \
                      --pass wiki

# Clear out any existing data and set up a fresh backend from scratch.

  user-setup-postgres --name mywiki \
                      --user wiki  \
                      --pass wiki  \
                      --force-preclear

=head1 DESCRIPTION

Takes three mandatory arguments:

=over 4

=item name

The database name.

=item user

The user that connects to the database. It must have permission
to create and drop tables in the database.

=item pass

The user's database password.

=back

and one optional flag:

=over 4

=item force-preclear

By default, this script will leave any existing data alone.  To force
that to be cleared out first, pass the C<--force-preclear> flag.

=back

=head1 AUTHOR

Kake Pugh (kake@earth.li).

=head1 COPYRIGHT

     Copyright (C) 2002 Kake Pugh.  All Rights Reserved.

This code is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<CGI::Wiki>, L<CGI::Wiki::Setup::Pg>

=cut

1;
