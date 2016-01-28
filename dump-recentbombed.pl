#!/usr/bin/perl -w

use strict;
use utf8;

use lib './lib';
use Bombtter;
use YAML;

my $conf = load_config;
set_terminal_encoding($conf);

my $count = $ARGV[0] || 20;

my $dbh = db_connect($conf);

my @posts = ();
my $sql = 'SELECT posted_at, screen_name, target, category, urgency ' .
    'FROM bombs LEFT JOIN statuses ON statuses.status_id = bombs.status_id ' .
    'WHERE posted_at IS NOT NULL AND result = 1 ' .
    'ORDER BY posted_at DESC LIMIT ?';
#printf "%s\n", $sql;
my $sth = $dbh->prepare($sql);
$sth->execute($count);
while(my $post = $sth->fetchrow_hashref)
{
    printf "%s\tCat:%d\tUrg:%d\t%s\t\t%s\n",
        $post->{posted_at},
        $post->{category},
        $post->{urgency},
        $post->{screen_name},
        $post->{target};
}
$sth->finish; undef $sth;

$dbh->disconnect;
