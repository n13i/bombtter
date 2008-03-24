#!/usr/bin/perl -w

# 2008/03/18
# $Id$

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $thresh = 3;

my $dbh = db_connect($conf);

my @posts = ();
my $sth = $dbh->prepare('SELECT target, (SELECT COUNT(*) FROM bombs b WHERE b.target = a.target) as count FROM bombs a WHERE posted_at IS NOT NULL AND count >= ? GROUP BY target ORDER BY count DESC');
$sth->execute($thresh);
while(my $update = $sth->fetchrow_hashref)
{
	my $count = $update->{'count'};
	my $target = $update->{'target'};

	print $count . "\t" . $target . "\n";
}
$sth->finish;

$dbh->disconnect;
