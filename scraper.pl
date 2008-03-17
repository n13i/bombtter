#!/usr/bin/perl -w

# Twitter 検索をスクレイピングしてデータベースに格納する
# 2008/03/17 naoh
# $Id$

use strict;
use utf8;

use DBI;
use YAML;

use lib './lib';
use Bombtter::Fetcher;


my $conffile = 'bombtter.conf';
my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");

binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";


my $ignore_name = $conf->{'twitter_username'};
print "ignore: $ignore_name\n";


my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{'dbfile'}, '', '', {unicode => 1});
$dbh->do('CREATE TABLE updates (status_id INTEGER UNIQUE, twiturl TEXT, name TEXT, screen_name TEXT, status TEXT, ctime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, analyzed INTEGER)');


my $hashref = $dbh->selectrow_hashref('SELECT status_id FROM updates ORDER BY status_id DESC LIMIT 1');
my $local_latest_status_id = $hashref->{'status_id'} || 0;
print "Latest status_id = $local_latest_status_id\n";


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
	print "sleeping 5 sec ...\n";
	sleep(5);

	my $buf = fetch_html($try + 1);
	#my $buf = read_html('targets/twsearch.html');
	die if(!defined($buf));

	my $r = scrape_html($buf);
	die if(!defined($r));

	$remote_earliest_status_id = $r->{'earliest_status_id'};

	print "remote: $remote_earliest_status_id / local: $local_latest_status_id\n";

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
			print $_->{'status_id'} . ' ' . $_->{'status'} . "\n";
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

print "$inserted inserted.\n";

$dbh->disconnect;
