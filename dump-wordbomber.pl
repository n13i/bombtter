#!/usr/bin/perl -w

# 2008/03/18
# $Id: dump-wordranking.pl 198 2008-11-17 08:28:24Z naoh $

use strict;
use utf8;

use lib './lib';
use Bombtter;
use YAML;

my $conf = load_config;
set_terminal_encoding($conf);

my $keyword = $ARGV[0] or die;

my $dbh = db_connect($conf);

my @posts = ();
my $sql = 'SELECT COUNT(*) as count, target, screen_name ' .
    'FROM bombs LEFT JOIN statuses ON statuses.status_id = bombs.status_id ' .
    'WHERE posted_at IS NOT NULL AND result = 1 ' .
    'AND target LIKE \'%' . $keyword . '%\' ' .
    'GROUP BY screen_name ORDER BY count DESC';
printf "%s\n", $sql;
my $sth = $dbh->prepare($sql);
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
    printf "%s\t\t%d\t%s\n",
        $update->{screen_name},
        $update->{count},
        $update->{target};
}
$sth->finish; undef $sth;

$dbh->disconnect;
