#!/usr/bin/perl -w

# 2009/11/18

use strict;
use utf8;

use lib './lib';
use Bombtter;

use Jcode;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

my $sth = $dbh->prepare('SELECT status_id, target FROM bombs WHERE target_normalized IS NULL');
$sth->execute();

my @updates = ();
while(my $update = $sth->fetchrow_hashref)
{
	my $status_id = $update->{'status_id'};
	my $target = $update->{'target'};

    my $ntarget = decode('utf8',
        Jcode->new(encode('utf8', $target))->h2z->utf8);
    $ntarget =~ tr/Ａ-Ｚａ-ｚ０-９/A-Za-z0-9/;

    if($target ne $ntarget)
    {
        printf "[%s] -> [%s]\n", $target, $ntarget;
        push(@updates, { status_id => $status_id, ntarget => $ntarget });
    }
}
$sth->finish;

$sth = $dbh->prepare('UPDATE bombs SET target_normalized = ? WHERE status_id = ?');
foreach(@updates)
{
    print $_->{ntarget} . "\n";
    $sth->execute($_->{ntarget}, $_->{status_id});
}
$sth->finish;

$dbh->disconnect;
