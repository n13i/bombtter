#!/usr/bin/perl -w

# 2008/03/18
# $Id$

use strict;
use utf8;

use DBI;
use YAML;

my $conffile = 'bombtter.conf';
my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");

binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";

my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{'dbfile'}, '', '', {unicode => 1});

my $sth = $dbh->prepare('SELECT status FROM updates');
$sth->execute();
while(my @row = $sth->fetchrow_array)
{
	print "@row\n";
}

$dbh->disconnect;
