use ExtUtils::MakeMaker;
use DBI;
use Data::Dumper;
use strict;

# Large chunks of this were inspired by the Makefile.PL supplied with
# DBIx::FullTextSearch -- thanks!

# See if we already have some config variables set.
use lib "lib";
eval "use CGI::Wiki::TestConfig";

# Even if we do have a previous configuration saved, we can over-ride and
# be asked all the questions again by specifying the -s flag.
if ($CGI::Wiki::TestConfig::configured
    and not (@ARGV and $ARGV[0] eq '-s')
   ) {
    print "\nFor the test suite, we use the database and user info\n"
        . "specified during the previous run.  If you want to change\n"
        . "some or all of the values, run 'perl Makefile.PL -s'.\n\n";
} else {
    # Collect up all the info.
    print "\nYou should supply at least one set of options for testing,\n"
        . "preferably relevant to the backend(s) you intend to use live.\n"
        . "Running the tests under every possible backend combination is\n"
	. "recommended.  To enter an undefined value, accept the empty\n"
        . "string or explicitly enter 'undef'.\n";

    my %config;
    if ($CGI::Wiki::TestConfig::configured) {
        %config = %CGI::Wiki::TestConfig::config;
    }

    # Ask for options for each possible database store, and check them.
    my %dsn_prefix = ( MySQL => "dbi:mysql:",
		       Pg    => "dbi:Pg:dbname=" );
    my %driver = ( MySQL => "DBD::mysql",
	           Pg    => "DBD::Pg" );
    foreach my $store_type (qw(MySQL Pg)) {
        # See whether we have the driver installed.
        eval "require " . $driver{$store_type};
        if ($@) {
            print "\n$driver{$store_type} not installed... skipping...\n";
	    $config{$store_type}{dbname} = undef;
	    next;
	}

        # Prompt for the options.
        my ($dbname, $dbuser, $dbpass);
        $dbname = prompt "\nDatabase name for $store_type: ",
	                 $config{$store_type}{dbname};
        undef $dbname unless ($dbname and $dbname ne "undef");
        if ($dbname and $dbname ne "undef") {
	    $dbuser = prompt "          Database user: ",
	                     $config{$store_type}{dbuser};
            undef $dbname unless ($dbname and $dbname ne "undef");
	    $dbpass = prompt "      Database password: ",
	                     $config{$store_type}{dbpass};
            undef $dbname unless ($dbname and $dbname ne "undef");

            # Check that these connection parameters actually work.
            my $dbh = eval { DBI->connect($dsn_prefix{$store_type}.$dbname,
 				          $dbuser, $dbpass, {PrintError => 0})
			         or die DBI->errstr;
			   };
            die "\nCan't connect to $store_type with those parameters:"
		     . "\n" . $@ . "\n\n"
		     . "Please re-run 'perl Makefile.PL' and supply correct "
		     . "parameters.\n\n" if $@;
            $dbh->disconnect;

            # Save them if they do.
            $config{$store_type}{dbname} = $dbname;
            $config{$store_type}{dbuser} = $dbuser;
            $config{$store_type}{dbpass} = $dbpass;
	} else {
            print "\nNo database name supplied... skipping...\n";
	    $config{$store_type}{dbname} = undef;
	}
    }

    # If we have a MySQL store configured, see if they want to use the
    # DBIx::FullTextSearch search backend.
    eval { require DBIx::FullTextSearch; };
    my $fts_inst = $@ ? 0 : 1;
    if ($config{MySQL}{dbname} and $fts_inst) {
        my $test = prompt "\nThe MySQL storage backend is compatible with "
	         . "the\nDBIx::FullTextSearch search backend.\n"
		 . "Enter 'y' or 'Y' to test this, anything else to not: ",
                      $config{dbixfts} ? "y" : "n";
        if (lc($test) eq "y") {
            $config{dbixfts} = 1;
	} else {
            $config{dbixfts} = undef;
        }
    } else {
        $config{dbixfts} = undef;
    }

    print "\n";

    # Copy the config hash to the right namespace.
    %CGI::Wiki::TestConfig::config = %config;

    # Write out the config for next run.
    open OUT, ">lib/CGI/Wiki/TestConfig.pm"
       or die "Couldn't open lib/CGI/Wiki/TestConfig.pm for writing: $!";
    # warning - blind copy and paste follows.  FIXME.
    print OUT Data::Dumper->new([ \%CGI::Wiki::TestConfig::config ],
                                [ '*CGI::Wiki::TestConfig::config' ]
                               )->Dump,
        "\$CGI::Wiki::TestConfig::configured = 1;\n1;\n";
    close OUT;
}

# Some modules are only prerequisites if we intend to test a
# particular backend.
my %config = %CGI::Wiki::TestConfig::config;
my %extras;
if ( $config{MySQL}{dbname} ) {
    $extras{'DBD::mysql'} = 0;
}
if ( $config{Pg}{dbname} ) {
    $extras{'DBD::Pg'} = 0;
    $extras{'Test::MockObject'} = '0.07'; # earlier ones don't have mock()
    $extras{'Hook::LexWrap'} = 0;
}
if ( $config{dbixfts} ) {
    $extras{'DBIx::FullTextSearch'} = '0.71'; # earlier ones buggy
}

# Write the Makefile.
WriteMakefile( NAME         => "CGI::Wiki",
	       VERSION_FROM => "lib/CGI/Wiki.pm",
	       PREREQ_PM    => { 'Text::WikiFormat' => '0.45', #earlier's buggy
				 'HTML::PullParser' => 0,
				 'Digest::MD5' => 0,
			         'Test::More' => 0,
			         'Test::Warn' => 0,
			         'Class::Delegation' => 0,
			         'Time::Piece' => 0,
			         %extras },
	       clean => { FILES => "Config lib/CGI/Wiki/TestConfig.pm" }
	     );

sub MY::postamble {
    my $module = "lib/CGI/Wiki.pm";
    return <<EOF
    README: $module
\tpod2text $module > README
EOF
}
