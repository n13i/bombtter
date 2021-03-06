#!/usr/bin/perl -w

# 2008/03/18
# $Id$

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

#my $hashref = $dbh->selectrow_hashref('SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL');
#my $n_unposted = $hashref->{'count'};
#print "Unposted bombs: $n_unposted\n";

my @posts = ();
my $sth = $dbh->prepare('SELECT * FROM bombs WHERE posted_at IS NULL ORDER BY status_id ASC');
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	printf "C:%d U:%d [%s] %s\n",
        $update->{category}, $update->{urgency},
        $update->{status_id}, $update->{target};
}
$sth->finish;
undef $sth;

$sth = $dbh->prepare(
    'SELECT category, COUNT(*) as count FROM bombs WHERE posted_at IS NULL ' .
    'GROUP BY category'
);
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	printf "category %d: %d unposted\n", $update->{category}, $update->{count};
}
$sth->finish;
undef $sth;


$dbh->disconnect;
