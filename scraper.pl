#!/usr/bin/perl -w

# Twitter 検索をスクレイピングしてデータベースに格納する
# 2008/03/17 naoh
# $Id$

use strict;
use utf8;

use DBI;
use YAML;

use lib './lib';
use Bombtter;
use Bombtter::Fetcher;

my $conf = load_config;
set_terminal_encoding($conf);

logger('running scraper');

my $ignore_name = $conf->{'twitter_username'};
logger("ignore: $ignore_name");

my $dbh = db_connect($conf);

$dbh->do('CREATE TABLE updates (status_id INTEGER UNIQUE, twiturl TEXT, name TEXT, screen_name TEXT, status TEXT, ctime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, analyzed INTEGER)');


my $hashref = $dbh->selectrow_hashref('SELECT status_id FROM updates ORDER BY status_id DESC LIMIT 1');
my $local_latest_status_id = $hashref->{'status_id'} || 0;
logger("Latest status_id = $local_latest_status_id");


my $try = 0;
my $try_max = 5;
my $remote_earliest_status_id = 99999999999;
my $inserted = 0;

# リモートの(1ページの)一番古い番号がローカルの一番新しい番号より大きければ
# 未取得のデータがある
my $sth = $dbh->prepare(
	'INSERT INTO updates (status_id, twiturl, name, screen_name, status)' .
	' VALUES (?, ?, ?, ?, ?)');
while($remote_earliest_status_id >= $local_latest_status_id && $try < $try_max)
{
	logger("sleeping 5 sec ...");
	sleep(5);

	my $buf = fetch_html($try + 1);
	#my $buf = read_html('targets/twsearch.html');
	die if(!defined($buf));

	my $r = scrape_html($buf);
	die if(!defined($r));

	$remote_earliest_status_id = $r->{'earliest_status_id'};

	logger("remote: $remote_earliest_status_id / local: $local_latest_status_id");

	$dbh->begin_work; # commit するまで AutoCommit がオフになる
	foreach(@{$r->{'updates'}})
	{
		if($_->{'name'} =~ /^$ignore_name$/)
		{
			next;
		}

		if($_->{'status_id'} > $local_latest_status_id)
		{
			# ローカルの最新より新しいデータ
			logger($_->{'name'} . ' ' . $_->{'status_id'} . ' ' . $_->{'status'});
			$sth->execute($_->{'status_id'},
							 $_->{'twiturl'},
							 $_->{'name'},
							 $_->{'screen_name'},
							 $_->{'status'});
			$inserted++;
		}
	}
	$dbh->commit;

	$try++;
}
$sth->finish;

logger("$inserted inserted.");

$dbh->disconnect;
