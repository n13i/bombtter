#!/usr/bin/perl -w

# 2008/03/18
# $Id$

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $thresh = $ARGV[0] || 1;

my $dbh = db_connect($conf);

my @posts = ();
#my $sth = $dbh->prepare('SELECT COUNT(*) as count, target FROM bombs GROUP BY target HAVING count >= ? ORDER BY count DESC');
my $sth = $dbh->prepare('SELECT COUNT(*) as count, target FROM bombs WHERE posted_at IS NOT NULL GROUP BY target HAVING count >= ' . $thresh . ' ORDER BY count DESC');
#$sth->execute($thresh);
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	my $count = $update->{'count'};
	my $target = $update->{'target'};

	print $count . "\t\t" . $target . "\n";
}
$sth->finish;

$dbh->disconnect;
