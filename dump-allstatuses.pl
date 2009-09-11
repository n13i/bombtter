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

my $sql = 'SELECT status_text FROM statuses ORDER BY status_id DESC';
if($#ARGV == 0)
{
    if($ARGV[0] =~ /^\d+$/)
    {
        $sql .= ' LIMIT ' . $ARGV[0];
    }
}

my $sth = $dbh->prepare($sql);
$sth->execute();
while(my @row = $sth->fetchrow_array)
{
	print "@row\n";
}
$sth->finish; undef $sth;

$dbh->disconnect;
