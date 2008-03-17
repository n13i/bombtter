#!/usr/bin/perl -w

use strict;
use utf8;

use DBI;
use YAML;

my $conffile = 'bombtter.conf';
my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");

binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";


my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{'dbfile'}, '', '', {unicode => 1});

my $hashref = $dbh->selectrow_hashref('SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL');
my $n_unposted = $hashref->{'count'};
print "Unposted bombs: $n_unposted\n";

my @posts = ();
my $sth = $dbh->prepare('SELECT * FROM bombs WHERE posted_at IS NULL ORDER BY status_id ASC');
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	my $status_id = $update->{'status_id'};
	my $target = $update->{'target'};

	print $target . "\n";
}
$sth->finish;

$dbh->disconnect;
