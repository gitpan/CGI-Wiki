#!/usr/bin/perl -w

# Very simple Wiki to demonstrate use of CGI::Wiki.

use strict;
use warnings;
use CGI qw/:standard/;
use CGI::Wiki;
use CGI::Wiki::Store::MySQL;
use CGI::Wiki::Search::DBIxFTS;
use Template;

# Initialise
my %macros = (
    qr/\@RECENTCHANGES(\b|$)/ => qq(<a href="wiki.cgi?node=Recent%20Changes">Recent Changes</a>),
    qr/\@SEARCHBOX(\b|$)/ =>
        qq(<form action="wiki.cgi" method="get">
	   <input type="hidden" name="action" value="search">
	   <input type="text" size="20" name="terms">
	   <input type="submit" name="Search" value="Search"></form>) );

my $store = CGI::Wiki::Store::MySQL->new( dbname => "kakewiki",
                                          dbuser => "wiki",
                                          dbpass => "wiki" );
my $dbh = $store->dbh;
my $search = CGI::Wiki::Search::DBIxFTS->new( dbh => $dbh );
my %conf = ( store           => $store,
             search          => $search,
	     extended_links  => 1,
	     implicit_links  => 0,
	     allowed_tags    => [qw(p b i pre)],
             macros          => \%macros,
	     node_prefix     => 'wiki.cgi?node=' );

my ($wiki, $q);
eval {
    $wiki = CGI::Wiki->new(%conf);

    # Get CGI object, find out what to do.
    $q = CGI->new;
    my $node = $q->param('node') || "";
    my $action = $q->param('action') || 'display';
    my $commit = $q->param('commit') || 0;
    my $preview = $q->param('preview') || 0;

    if ($commit) {
        commit_node($node);
    } elsif ($preview) {
        preview_node($node);
    } elsif ($action eq 'edit') {
        edit_node($node);
    } elsif ($action eq 'search') {
        do_search($q->param('terms'));
    } elsif ($action eq 'index') {
        my @nodes = $wiki->list_all_nodes();
        process_template("site_index.tt", "index", { nodes => \@nodes });
    } else {
        display_node($node);
    }
};

if ($@) {
    my $error = $@;
    warn $error;
    print CGI::header;
    print qq(<html><head><title>ERROR</title></head><body>
             <p>Sorry!  Something went wrong.  Please contact the
             Wiki administrator at
             <a href="mailto:kake\@earth.li">kake\@earth.li</a> and quote
             the following error message:</p><blockquote>)
      . CGI::escapeHTML($error)
      . qq(</blockquote><p><a href="wiki.cgi">Return to the Wiki home page</a>
           </body></html>);
}
exit 0;

############################ subroutines ###################################

sub display_node {
    my $node = shift;
    $node ||= "Home";
    my $raw = $wiki->retrieve_node($node);
    my $content = $wiki->format($raw);

    my %tt_vars = ( content       => $content,
		    node_name     => CGI::escapeHTML($node),
		    node_param    => CGI::escape($node) );

    if ($node eq "Recent Changes") {
        my @recent = $wiki->list_recent_changes( days => 7 );
        @recent = map { {name          => CGI::escapeHTML($_->{name}),
                         last_modified => CGI::escapeHTML($_->{last_modified}),
                         comment       => CGI::escapeHTML($_->{comment}),
                         url           => "wiki.cgi?node="
                                          . CGI::escape($_->{name}) }
                       } @recent;
        $tt_vars{recent_changes} = \@recent;
        $tt_vars{days} = 7;
        process_template("recent_changes.tt", $node, \%tt_vars);
    } else {
        process_template("node.tt", $node, \%tt_vars);
    }
}

sub preview_node {
    my $node = shift;
    my $content    = $q->param('content');
    my $checksum   = $q->param('checksum');

    if ($wiki->verify_checksum($node, $checksum)) {
        my %tt_vars = ( content      => CGI::escapeHTML($content),
                          preview_html => $wiki->format($content),
                        checksum     => CGI::escapeHTML($checksum) );

        process_template("edit_form.tt", $node, \%tt_vars);
    } else {
        my %node_data = $wiki->retrieve_node($node);
        my ($stored, $checksum) = @node_data{ qw( content checksum ) };
        my %tt_vars = ( checksum    => CGI::escapeHTML($checksum),
                        new_content => CGI::escapeHTML($content),
                        stored      => CGI::escapeHTML($stored) );
        process_template("edit_conflict.tt", $node, \%tt_vars);
    }
}

sub edit_node {
    my $node = shift;
    my %node_data = $wiki->retrieve_node($node);
    my ($content, $checksum) = @node_data{ qw( content checksum ) };
    my %tt_vars = ( content  => CGI::escapeHTML($content),
                    checksum => CGI::escapeHTML($checksum)   );

    process_template("edit_form.tt", $node, \%tt_vars);
}


sub process_template {
    my ($template, $node, $vars, $conf) = @_;

    $vars ||= {};
    $conf ||= {};

    my %tt_vars = ( %$vars,
                    site_name     => "Kake Wiki",
                    cgi_url       => "wiki.cgi",
                    contact_email => "kake\@earth.li",
                    description   => "",
                    keywords      => "",
                    stylesheet    => "/~kake/wiki/styles.css",
                    home_link     => "wiki.cgi",
                    home_name     => "Home" );

    if ($node) {
        $tt_vars{node_name} = CGI::escapeHTML($node);
        $tt_vars{node_param} = CGI::escape($node);
    }

    my %tt_conf = ( %$conf,
                INCLUDE_PATH => "/home/kake/working/wiki/examples/templates" );

    # Create Template object, print CGI header, process template.
    my $tt = Template->new(\%tt_conf);
    print CGI::header;
    unless ($tt->process($template, \%tt_vars)) {
        print qq(<html><head><title>ERROR</title></head><body><p>
                 Failed to process template: )
          . $tt->error
          . qq(</p></body></html>);
    }
}


sub commit_node {
    my $node = shift;
    my $content  = $q->param('content');
    my $checksum = $q->param('checksum');

    my $written = $wiki->write_node($node, $content, $checksum);
    if ($written) {
        display_node($node);
    } else {
        my %node_data = $wiki->retrieve_node($node);
	my ($stored, $checksum) = @node_data{ qw( content checksum ) };
        my %tt_vars = ( checksum    => CGI::escapeHTML($checksum),
                        new_content => CGI::escapeHTML($content),
                        stored      => CGI::escapeHTML($stored) );
        process_template("edit_conflict.tt", $node, \%tt_vars);
    }
}


sub do_search {
    my $terms = shift;
    my %finds = $wiki->search_nodes($terms);
    my @sorted = sort { $finds{$a} cmp $finds{$b} } keys %finds;
    my @results = map { { url   => CGI::escape($_),
                          title => CGI::escapeHTML($_) } } @sorted;
    my %tt_vars = ( results => \@results );
    process_template("search_results.tt", "", \%tt_vars);
}
