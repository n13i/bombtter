#!/usr/bin/perl -w
# vim: noexpandtab

# Bombtter - What are you bombing?
# 2008/03/16 naoh
# $Id$

use strict;
use utf8;

use Net::Twitter;
use Encode;
use YAML;  # for YAML::Dump

use lib './lib';
use Bombtter;
use Bombtter::Fetcher;
use Bombtter::Analyzer;

my $conf = load_config;
set_terminal_encoding($conf);

logger('$Id$');

if(!defined($ARGV[0]))
{
	die("usage: bombtter.pl [fetch|post|both]\n");
}


my $dbh = db_connect($conf);

if($ARGV[0] eq 'fetch' || $ARGV[0] eq 'both')
{
	&bombtter_scraper($conf, $dbh);
	&bombtter_analyzer($conf, $dbh);
}
if($ARGV[0] eq 'post' || $ARGV[0] eq 'both')
{
	&bombtter_publisher($conf, $dbh);
}

$dbh->disconnect;
exit;


# Twitter 検索をスクレイピングしてデータベースに格納する
# 2008/03/17 naoh
sub bombtter_scraper
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	logger('running scraper');

	my $ignore_name = $conf->{'twitter_username'};
	logger("ignore: $ignore_name");

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

		#my $r = scrape_html($buf);
		my $r = scrape_html_regexp($buf);
		die if(!defined($r));

		#my $uri = get_uri($try + 1);
		#die if(!defined($uri));
		#
		#my $r = scrape_html(new URI($uri));
		#die if(!defined($r));

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
				logger($_->{'name'} . ' ' .
					   $_->{'status_id'} . ' ' . $_->{'status'});
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

	return 1;
}


# 2008/03/17
sub bombtter_analyzer
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	logger('running analyzer');

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
		#push(@targets, $update->{'status'});
		my $status_id = $update->{'status_id'};
		my $target = $update->{'status'};

		logger("target: " . $target);

		my $bombed = analyze($target);

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

	return 1;
}

sub bombtter_publisher
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	logger('running publisher');

	my $enable_posting = $conf->{'enable_posting'} || 0;
	my $limit = $conf->{'posts_at_once'} || 1;

	my $hashref = $dbh->selectrow_hashref('SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL');
	my $n_unposted = $hashref->{'count'};
logger("Unposted bombs: $n_unposted");

	my @posts = ();
	#my $sth = $dbh->prepare('SELECT * FROM bombs WHERE posted_at IS NULL ORDER BY status_id ASC LIMIT ?');
	my $sth = $dbh->prepare(
		'SELECT *, (' .
		' SELECT COUNT(*) FROM bombs co ' .
		'  WHERE co.target = li.target' .
		'    AND co.posted_at IS NOT NULL' .  # post されたものから数える
		'  GROUP BY co.target) AS count ' .
		'FROM bombs li WHERE posted_at IS NULL ORDER BY status_id ASC LIMIT ?');
	# FIXME 複数個を一度に post する場合は count の計算をちゃんとしないとない
	#       (全部 post した後で posted_at が更新されるため)
	$sth->execute($limit);
	while(my $update = $sth->fetchrow_hashref)
	{
		my $status_id = $update->{'status_id'};
		my $target = $update->{'target'};
		my $count = $update->{'count'} || 0;

		my $extra = '';
		if(int(rand(100)) < 10)
		{
			my @extras = ('盛大に', 'ひっそりと', '派手に');
			#$extra = $extras[int(rand($#extras+1))];
		}

		my $result = 'が' . $extra . '爆発しました。';

		if($count > 1)
		{
			#$extra = 'また';
			#$result = 'は今日も爆発しました。';
		}

		if(int(rand(100)) < 5)
		{
			#$result = 'は爆発しませんでした。';
		}

		if($target =~ /^\@$conf->{'twitter_username'}\s*/)
		{
			# 身代わりに何か適当なものを爆発させる
			my $hashref = $dbh->selectrow_hashref('SELECT target FROM bombs WHERE posted_at IS NOT NULL ORDER BY RANDOM() LIMIT 1');
			my $subst = $hashref->{'target'};

			if(!defined($subst))
			{
				logger("WARNING: subst is undef");
			}

			if(int(rand(100)) < 30 || !defined($subst))
			{
				$result = 'が自爆しました。';
			}
			else
			{
				$result = 'の身代わりとして' . $subst . 'が爆発しました。';
			}
		}

		#my $post = '●~* ' . $target . $result;
		#my $post = '[●~] ' . $target . $result;
		my $post = '●~＊ ' . $target . $result;

		push(@posts, { 'id' => $status_id, 'post' => $post });
	}
	$sth->finish;



	my $twit = Net::Twitter->new(
			username => $conf->{'twitter_username'},
			password => $conf->{'twitter_password'});

	$sth = $dbh->prepare(
			'UPDATE bombs SET posted_at = CURRENT_TIMESTAMP WHERE status_id = ?');
	my $n_posted = 0;
	foreach(@posts)
	{
		my $post = $_->{'post'};

		logger("post: $post");

		my $status = undef;
		if($enable_posting)
		{
			$status = $twit->update(encode('utf8', $post));

			logger('update: code ' . $twit->http_code . ' ' . $twit->http_message);
			logger(Dump($status));

			if($twit->http_code == 200)
			{
				$sth->execute($_->{'id'});
				$n_posted++;
			}
			else
			{
				die('failed to update');
			}
		}
	}
	$sth->finish;

	logger("posted $n_posted bombs.");

	return 1;
}

