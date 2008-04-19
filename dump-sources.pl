#!/usr/bin/perl -w

# 2008/03/18
# $Id: dump-postqueue.pl 38 2008-03-24 19:41:29Z naoh $

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

my $hashref = $dbh->selectrow_hashref('SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL');
my $n_unposted = $hashref->{'count'};
print "Unposted bombs: $n_unposted\n";

my @posts = ();
my $sth = $dbh->prepare('SELECT *, (SELECT permalink FROM statuses s WHERE s.status_id = b.status_id) AS permalink FROM bombs b WHERE b.posted_at IS NULL ORDER BY b.status_id ASC');
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	my $target = $update->{'target'};
	my $permalink = $update->{'permalink'};

	print $target . "\n";
	print $permalink . "\n";
}
$sth->finish;

$dbh->disconnect;
