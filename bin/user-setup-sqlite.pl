#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use CGI::Wiki::Setup::SQLite;

my ($dbname, $help, $preclear);
GetOptions( "name=s"         => \$dbname,
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
    CGI::Wiki::Setup::SQLite::cleardb($dbname);
}

CGI::Wiki::Setup::SQLite::setup($dbname);

=head1 NAME

user-setup-sqlite - set up a SQLite storage backend for CGI::Wiki

=head1 SYNOPSIS

# Set up or update the storage backend, leaving any existing data intact.
# Useful for upgrading from old versions of CGI::Wiki to newer ones with
# more backend features.

  user-setup-sqlite --name mywiki

# Clear out any existing data and set up a fresh backend from scratch.

  user-setup-sqlite --name mywiki \
                    --force-preclear

=head1 DESCRIPTION

Takes one mandatory argument:

=over 4

=item name

The name of the file to store the SQLite database in.  It will be
created if it doesn't already exist.

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

L<CGI::Wiki>, L<CGI::Wiki::Setup::SQLite>

=cut

1;
