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

my $sth = $dbh->prepare('SELECT status FROM updates WHERE analyzed = 0 ORDER BY status_id ASC');
$sth->execute();
while(my @row = $sth->fetchrow_array)
{
	print "@row\n";
}

$dbh->disconnect;
