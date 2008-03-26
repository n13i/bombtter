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

my $LOCKDIR = '.bombtter_lock';

my @source_name = ('Twitter search', 'followers');

my $conf = load_config;
set_terminal_encoding($conf);

logger('main', '$Id$');

if(!defined($ARGV[0]))
{
	die("usage: bombtter.pl [auto|fetch|post|both] [-1|0|1] [-1|0|1]\n");
}

my $mode = $ARGV[0];

my $scrape_source = $ARGV[1] || 0;
my $post_source   = $ARGV[2] || -1;
if($scrape_source > $#source_name || $scrape_source < -1 ||
   $post_source > $#source_name || $post_source < -1)
{
	die("invalid source\n");
}

if($mode eq 'auto')
{
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
		localtime(time);
	print $min . "\n";
	if(($min+10) % 20 == 0)
	{
		$mode          = 'both';
		$scrape_source = 0;      # search only
		$post_source   = -1;     # search + followers
	}
	elsif($min % 10 == 0)
	{
		$mode          = 'both';
		$scrape_source = 1;      # followers only
		$post_source   = -1;     # search + followers
	}
	else
	{
		$mode          = 'both';
		$scrape_source = 1;      # followers only
		$post_source   = 1;      # followers only
	}
}

logger('main', 'mode: ' . $mode);
logger('main', 'source for scrape: ' . $source_name[$scrape_source]);
if($post_source == -1)
{
	logger('main', 'source for post: all');
}
else
{
	logger('main', 'source for post: ' . $source_name[$post_source]);
}

&bombtter_lock;

my $dbh = db_connect($conf);

if($mode eq 'fetch' || $mode eq 'both')
{
	&bombtter_scraper($conf, $dbh, $scrape_source);
	&bombtter_analyzer($conf, $dbh);
}
if($mode eq 'post' || $mode eq 'both')
{
	&bombtter_publisher($conf, $dbh, $post_source);
}

$dbh->disconnect;

&bombtter_unlock;
exit;


# Twitter 検索をスクレイピングしてデータベースに格納する
# 2008/03/17 naoh
sub bombtter_scraper
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	my $source = shift || 0;

	logger('scraper', 'running scraper ' . $Bombtter::Fetcher::revision);
	logger('scraper', 'source: ' . $source_name[$source]);

	my $ignore_name = $conf->{'twitter_username'};
	logger('scraper', "ignore: $ignore_name");

	$dbh->do('CREATE TABLE statuses (status_id INTEGER UNIQUE, permalink TEXT, screen_name TEXT, name TEXT, status_text TEXT, ctime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, source INTEGER, analyzed INTEGER)');

	# ソースごとのローカル最新ステータス ID を取得
	my $hashref = $dbh->selectrow_hashref('SELECT status_id FROM statuses WHERE source = ' . $source . ' ORDER BY status_id DESC LIMIT 1');
	my $local_latest_status_id = $hashref->{'status_id'} || 0;
	logger('scraper', "Latest status_id = $local_latest_status_id");


	my $try = 0;
	my $try_max = 5;
	my $remote_earliest_status_id = 99999999999;
	my $inserted = 0;

	# リモートの(1ページの)一番古い番号がローカルの一番新しい番号より大きければ
	# 未取得のデータがある
	my $sth = $dbh->prepare(
		'INSERT OR IGNORE INTO statuses (status_id, permalink, screen_name, name, status_text, source)' .
		' VALUES (?, ?, ?, ?, ?, ?)');
	while($remote_earliest_status_id >= $local_latest_status_id && $try < $try_max)
	{
		my $r = [];
		if($source == 0)
		{
			logger('scraper', "sleeping 5 sec ...");
			sleep(5);
	
			my $buf = fetch_html($try + 1);
			#my $buf = read_html('targets/twsearch.html');
			die if(!defined($buf));
	
			#$r = scrape_html($buf);
			$r = scrape_html_regexp($buf);
			die if(!defined($r));
	
			#my $uri = get_uri($try + 1);
			#die if(!defined($uri));
			#
			#$r = scrape_html(new URI($uri));
			#die if(!defined($r));

			$remote_earliest_status_id = $r->{'earliest_status_id'};
		}
		elsif($source == 1)
		{
			$r = fetch_followers($conf->{'twitter_username'},
								 $conf->{'twitter_password'});
			die if(!defined($r));

			# 強制的にリモートの最古 < ローカルの最新になるようにする
			$remote_earliest_status_id = -1;
		}
		else
		{
			die;
		}


		logger('scraper', "remote: $remote_earliest_status_id / local: $local_latest_status_id");

		$dbh->begin_work; # commit するまで AutoCommit がオフになる
		foreach(@{$r->{'statuses'}})
		{
			if($_->{'screen_name'} =~ /^$ignore_name$/)
			{
				next;
			}

			if($_->{'status_id'} > $local_latest_status_id)
			{
				# ローカルの最新より新しいデータ
				logger('scraper',
					   $_->{'screen_name'} . ' ' .
					   $_->{'status_id'} . ' ' . $_->{'status_text'});
				$sth->execute($_->{'status_id'},
							  $_->{'permalink'},
							  $_->{'screen_name'},
							  $_->{'name'},
							  $_->{'status_text'},
							  $source);
				$inserted++;
			}
		}
		$dbh->commit;

		$try++;
	}
	$sth->finish;

	logger('scraper', "$inserted inserted.");

	return 1;
}


# 2008/03/17
sub bombtter_analyzer
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	logger('analyzer', 'running analyzer ' . $Bombtter::Analyzer::revision);

	$dbh->do('CREATE TABLE bombs (status_id INTEGER UNIQUE, target TEXT, ctime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, source INTEGER, posted_at TIMESTAMP)');

	my $sth = $dbh->prepare('SELECT * FROM statuses WHERE analyzed IS NULL ORDER BY status_id DESC');
	$sth->execute();

	my @analyze_ok_ids = ();
	my @analyze_ng_ids = ();

	my $mecab_opts = '';
	if(defined($conf->{'mecab_userdic'}))
	{
		$mecab_opts .= '--userdic=' . $conf->{'mecab_userdic'};
	}

	my $sth_insert = $dbh->prepare(
		'INSERT OR IGNORE INTO bombs (status_id, target, source) VALUES (?, ?, ?)');
	$dbh->begin_work;
	while(my $update = $sth->fetchrow_hashref)
	{
		#push(@targets, $update->{'status'});
		my $status_id = $update->{'status_id'};
		my $target = $update->{'status_text'};
		my $source = $update->{'source'};

		logger('analyzer', "target: " . $target);

		my $bombed = analyze($target, $mecab_opts);

		my $analyze_result;

		if(defined($bombed))
		{
			push(@analyze_ok_ids, $status_id);
			$sth_insert->execute($status_id, $bombed, $source);
			logger('analyzer', "result: " . $bombed);
		}
		else
		{
			push(@analyze_ng_ids, $status_id);
			logger('analyzer', "result:");
		}

		# fetchrow 中のテーブルを update しようとすると怒られる(2008/03/17)
		#my $sth_update = $dbh->prepare(
		#	'UPDATE statuses SET analyzed = ? WHERE status_id = ?');
		#$sth_update->execute($analyze_result, $status_id);
	}
	$dbh->commit;
	$sth_insert->finish;
	$sth->finish;

	$sth = $dbh->prepare(
		'UPDATE statuses SET analyzed = ? WHERE status_id = ?');
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

	my $limit_source = shift || -1;

	logger('publisher', 'running publisher');
	if($limit_source >= 0)
	{
		logger('publisher', 'limit source: ' . $source_name[$limit_source]);
	}

	my $enable_posting = $conf->{'enable_posting'} || 0;
	my $limit = $conf->{'posts_at_once'} || 1;

	my $sql;

	$sql = 'SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL';
	if($limit_source >= 0)
	{
		$sql .= ' AND source = ' . $limit_source;
	}
	my $hashref = $dbh->selectrow_hashref($sql);
	my $n_unposted = $hashref->{'count'};
	logger('publisher', "bombs in queue: $n_unposted");

	my @posts = ();
	#my $sth = $dbh->prepare('SELECT * FROM bombs WHERE posted_at IS NULL ORDER BY status_id ASC LIMIT ?');
	$sql =
		'SELECT *, (' .
		' SELECT COUNT(*) FROM bombs co ' .
		'  WHERE co.target = li.target' .
		'    AND co.posted_at IS NOT NULL' .  # post されたものから数える
		'  GROUP BY co.target) AS count ' .
		'FROM bombs li WHERE posted_at IS NULL ';
	if($limit_source >= 0)
	{
		$sql .= 'AND source = ' . $limit_source . ' ';
	}
	$sql .= 'ORDER BY status_id ASC LIMIT ?';
	my $sth = $dbh->prepare($sql);

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

		if($count > 1)
		{
			#$extra = 'また';
			#$result = 'は今日も爆発しました。';
		}

		my $result = 'が' . $extra . '爆発しました。';

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
				logger('publisher', "WARNING: subst is undef");
			}

			if(int(rand(100)) < 70 || !defined($subst))
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
		#my $post = '●~＊ ' . $target . $result;
		my $post = $target . $result;

		# reply してしまわないように
		if($target =~ /^\s*\@/)
		{
			$post = '. ' . $post;
		}

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

		logger('publisher', "post: $post");

		my $status = undef;
		if($enable_posting)
		{
			$status = $twit->update(encode('utf8', $post));

			logger('publisher', 'update: code ' .
								$twit->http_code . ' ' . $twit->http_message);
			logger('publisher', Dump($status));

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

	logger('publisher', "posted $n_posted bombs.");

	return 1;
}

sub bombtter_lock
{
	my $retry = 5;
	while(!mkdir($LOCKDIR, 0755))
	{
		if(--$retry <= 0)
		{
			logger('lock', 'lock timeout');
			die;
		}
	}
}

sub bombtter_unlock
{
	rmdir($LOCKDIR);
}

