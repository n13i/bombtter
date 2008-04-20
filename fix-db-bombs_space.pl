#!/usr/bin/perl -w

# 2008/04/20

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

my $sth = $dbh->prepare('SELECT status_id, target FROM bombs');
$sth->execute();

my @updates = ();
while(my $update = $sth->fetchrow_hashref)
{
	my $status_id = $update->{'status_id'};
	my $target = $update->{'target'};

    if($target =~ /\s+$/)
    {
    	print "[" . $target . "]\n";
        $target =~ s/\s+$//;
        push(@updates, { status_id => $status_id, target => $target });
    }
}
$sth->finish;

$sth = $dbh->prepare('UPDATE bombs SET target = ? WHERE status_id = ?');
foreach(@updates)
{
    print $_->{target} . "\n";
    $sth->execute($_->{target}, $_->{status_id});
}
$sth->finish;

$dbh->disconnect;
