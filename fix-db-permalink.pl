#!/usr/bin/perl -w

# 2008/04/20

use strict;
use utf8;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

my $sth = $dbh->prepare('SELECT status_id, permalink FROM statuses');
$sth->execute();

my @updates = ();
while(my $update = $sth->fetchrow_hashref)
{
	my $status_id = $update->{'status_id'};
	my $permalink = $update->{'permalink'};

	#print $permalink . "\n";

    if($permalink =~ /com\/\@/)
    {
        $permalink =~ s/(com\/)\@/$1/;
        push(@updates, { status_id => $status_id, permalink => $permalink });
    }
}
$sth->finish;

my $sth = $dbh->prepare('UPDATE statuses SET permalink = ? WHERE status_id = ?');
foreach(@updates)
{
    print $_->{permalink} . "\n";
    $sth->execute($_->{permalink}, $_->{status_id});
}
$sth->finish;

$dbh->disconnect;
