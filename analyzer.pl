#!/usr/bin/perl -w

# 2008/03/17
# $Id$

use strict;
use utf8;

use lib './lib';
use Bombtter;
use Bombtter::Analyzer;

my $conf = load_config;
set_terminal_encoding($conf);

my $dbh = db_connect($conf);

$dbh->do('CREATE TABLE bombs (status_id INTEGER UNIQUE, target TEXT, ctime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, posted_at TIMESTAMP)');

my $sth = $dbh->prepare('SELECT * FROM updates WHERE analyzed IS NULL ORDER BY status_id DESC');
$sth->execute();

my @analyze_ok_ids = ();
my @analyze_ng_ids = ();

my $sth_insert = $dbh->prepare(
	'INSERT INTO bombs (status_id, target) VALUES (?, ?)');
$dbh->begin_work;
while(my $update = $sth->fetchrow_hashref)
{
#	push(@targets, $update->{'status'});
	my $status_id = $update->{'status_id'};
	my $bombed = analyze($update->{'status'});

	logger("target: " . $update->{'status'});

	my $analyze_result;

	if(defined($bombed))
	{
		push(@analyze_ok_ids, $status_id);
		$sth_insert->execute($status_id, $bombed);
		logger("result: " . $bombed);
	}
	else
	{
		push(@analyze_ng_ids, $status_id);
		logger("result:");
	}

	# fetchrow 中のテーブルを update しようとすると怒られる(2008/03/17)
	#my $sth_update = $dbh->prepare(
	#	'UPDATE updates SET analyzed = ? WHERE status_id = ?');
	#$sth_update->execute($analyze_result, $status_id);
}
$dbh->commit;
$sth_insert->finish;
$sth->finish;

$sth = $dbh->prepare(
	'UPDATE updates SET analyzed = ? WHERE status_id = ?');
$dbh->begin_work;
foreach(@analyze_ok_ids)
{
	$sth->execute(1, $_);
}
foreach(@analyze_ng_ids)
{
	$sth->execute(0, $_);
}
$dbh->commit;
$sth->finish;

$dbh->disconnect;
