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
# be asked all the questions again by specifying the -s flag or setting
# the appropriate environment variable.
if ($CGI::Wiki::TestConfig::configured
    and not (@ARGV and $ARGV[0] eq '-s')
    and not $ENV{CGI_WIKI_RERUN_CONFIG}
   ) {
    print "\nFor the test suite, we use the database and user info\n"
        . "specified during the previous run.  If you want to change\n"
        . "some or all of the values, run 'perl Makefile.PL -s'.\n\n";
} else {
    print "\nYou should supply at least one set of options for testing,\n"
        . "preferably relevant to the backend(s) you intend to use live.\n"
        . "Running the tests under every possible backend combination is\n"
	. "recommended.  To enter an undefined value, accept the empty\n"
        . "string or explicitly enter 'undef'.\n";

    my %config;

    # Grab information from previous runs.
    if ($CGI::Wiki::TestConfig::configured) {
        %config = %CGI::Wiki::TestConfig::config;
    }

    # Grab information from environment variables.
    foreach my $store (qw(MySQL Pg)) {
        my $dbname = $ENV{"CGI_WIKI_".uc($store)."_DBNAME"};
	if ($dbname and $dbname ne "undef") {
	    $config{$store}{dbname} = $dbname;
            foreach my $var (qw(dbuser dbpass)) {
                my $value = $ENV{"CGI_WIKI_".uc($store)."_".uc($var)};
		if ($value and $value ne "undef") {
  	            $config{$store}{$var} = $value;
		} elsif ($value eq "undef") {
		    $config{$store}{$var} = undef;
		}
	    }
	} elsif ($dbname eq "undef") {
	    $config{$store}{dbname} = undef;
	}
    }

    my $dbixfts = $ENV{CGI_WIKI_DBIXFTS_MYSQL};
    if ($dbixfts and $dbixfts ne "undef") {
        $config{dbixfts} = 1;
    } elsif ($dbixfts eq "undef") {
        $config{dbixfts} = 0;
    }

    # Finally ask questions; then check the settings work.
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
}

# We can test the SQLite backend without asking questions, if it's installed.
eval { require DBD::SQLite; };
if ($@) {
    print "DBD::SQLite not installed... so won't test that...\n\n";
    $CGI::Wiki::TestConfig::config{SQLite} = { dbname => undef };
} else {
    print "You have DBD::SQLite... configuring test SQLite database...\n\n";
    $CGI::Wiki::TestConfig::config{SQLite} = { dbname => "t/sqlite-test.db" };
}

# Write out the config for next run.
open OUT, ">lib/CGI/Wiki/TestConfig.pm"
  or die "Couldn't open lib/CGI/Wiki/TestConfig.pm for writing: $!";
# warning - blind copy and paste follows.  FIXME.
print OUT Data::Dumper->new([ \%CGI::Wiki::TestConfig::config ],
			    [ '*CGI::Wiki::TestConfig::config' ]
			   )->Dump,
  "\$CGI::Wiki::TestConfig::configured = 1;\n1;\n";
close OUT;

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
if ( $config{sqlite} ) {
    $extras{'DBD::SQLite'} = 0;
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
	       clean => { FILES => "Config lib/CGI/Wiki/TestConfig.pm "
			         . "t/sqlite-test.db" }
	     );

