#!/usr/bin/perl

# Bombtter - What are you bombing?
# 2008/03/16 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Net::Twitter;
use Encode;
use Jcode;
use YAML;  # for YAML::Dump
use DateTime;

use lib './lib';
use Bombtter;
use Bombtter::Fetcher;
use Bombtter::Analyzer;

my $LOCKDIR = 'lock/';
my $LOCKFILE = 'lock';

my @source_name = ('Twitter search', 'IM', 'API');

my $conf = load_config or &error('load_config failed');
set_terminal_encoding($conf);

logger('main', '$Id$');

if(!defined($ARGV[0]))
{
	&error("usage: bombtter.pl [auto|fetch|post|both] [-1|0|1] [-1|0|1]\n");
}

my $dt_now = DateTime->now(time_zone => '+0000');
my $dt_local_now = $dt_now->clone->set_time_zone('+0900');

my $mode = $ARGV[0];

my $scrape_source = $ARGV[1] || 0;
my $post_source   = $ARGV[2] || -1;
if($scrape_source > $#source_name || $scrape_source < -1 ||
   $post_source > $#source_name || $post_source < -1)
{
	&error("invalid source\n");
}

if($mode eq 'auto')
{
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
		localtime(time);
	print $min . "\n";
	if($min % ($conf->{automode_search_interval} || 20) == 0)
	{
		$mode		   = 'both';
		$scrape_source = 0;      # search only
		$post_source   = -1;     # search + followers
	}
	elsif($min % ($conf->{automode_followers_interval} || 10) == 0)
	{
		$mode		   = 'both';
		$scrape_source = 1;      # IM only
		#$scrape_source = 2;      # API only
		$post_source   = -1;     # search + followers
	}
	else
	{
		$mode		   = 'post';
		$post_source   = 1;     # followers only
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

my $lfh = &bombtter_lock or &error('locked');

my $dbh = db_connect($conf) or &error('db_connect failed');

if($mode eq 'fetch' || $mode eq 'both')
{
	&bombtter_fetcher($conf, $dbh, $scrape_source);
	&bombtter_analyzer($conf, $dbh);
}
if($mode eq 'post' || $mode eq 'both')
{
	my @categories = (0, 1);
	foreach(@categories)
	{
		&bombtter_publisher($conf, $dbh, $post_source, $_);
	}
}

$dbh->disconnect;

&bombtter_unlock($lfh);
exit;


# Twitter 検索をスクレイピングしてデータベースに格納する
# 2008/03/17 naoh
sub bombtter_fetcher
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	my $source = shift || 0;

	logger('fetcher', 'running fetcher ' . $Bombtter::Fetcher::revision);
	logger('fetcher', 'source: ' . $source_name[$source]);

	my $ignore_name = $conf->{twitter}->{username};
	if(defined($conf->{ignore_name_expr}))
	{
		if($conf->{ignore_name_expr} ne '')
		{
			$ignore_name .= '|' . $conf->{ignore_name_expr};
		}
	}
	logger('fetcher', "ignore: $ignore_name");


	# ソースごとのローカル最新ステータス ID を取得
	my $hashref = $dbh->selectrow_hashref('SELECT status_id FROM statuses WHERE source = ' . $source . ' ORDER BY status_id DESC LIMIT 1');
	my $local_latest_status_id = $hashref->{'status_id'} || 0;
	logger('fetcher', "Latest status_id = $local_latest_status_id");


	my $try = 0;
	my $try_max = 5;
	my $remote_earliest_status_id = 99999999999;
	my $inserted = 0;

	# リモートの(1ページの)一番古い番号がローカルの一番新しい番号より大きければ
	# 未取得のデータがある
	my $sth = $dbh->prepare(
		'INSERT OR IGNORE INTO statuses (status_id, permalink, screen_name, name, status_text, source, is_protected)' .
		' VALUES (?, ?, ?, ?, ?, ?, ?)');
	while($remote_earliest_status_id >= $local_latest_status_id && $try < $try_max)
	{
		my $r = [];
		if($source == 0)
		{
			logger('fetcher', "sleeping 5 sec ...");
			sleep(5);

			$r = fetch_rss();
			#$r = fetch_html($try + 1);
			&error if(!defined($r));
	
			#$remote_earliest_status_id = $r->{earliest_status_id};
			$remote_earliest_status_id = -1;
		}
		elsif($source == 1)
		{
			#$r = fetch_im($conf->{db}->{im});
			$r = fetch_im($conf->{db}->{timeliner});
			&error if(!defined($r));

			# 強制的にリモートの最古 < ローカルの最新になるようにする
			$remote_earliest_status_id = -1;
		}
		elsif($source == 2)
		{
			$r = fetch_api($conf->{twitter}->{username},
						   $conf->{twitter}->{password});
			&error if(!defined($r));

			$remote_earliest_status_id = -1;
		}
		else
		{
			&error;
		}
		logger('fetcher', 'got ' . ($#{$r->{statuses}}+1) . ' status(es)');

		logger('fetcher', "remote: $remote_earliest_status_id / local: $local_latest_status_id");

		$dbh->begin_work; # commit するまで AutoCommit がオフになる
		foreach(@{$r->{statuses}})
		{
			if($_->{screen_name} =~ /^($ignore_name)$/)
			{
				next;
			}

			if($_->{status_id} > $local_latest_status_id)
			{
				# ローカルの最新より新しいデータ
				logger('fetcher', 'insert: ' .
					   $_->{status_id} . '|' .
					   $_->{screen_name} . '|' .
					   $_->{status_text});
				$sth->execute($_->{status_id},
							  $_->{permalink},
							  $_->{screen_name},
							  $_->{name},
							  $_->{status_text},
							  $source,
							  $_->{is_protected});
				$inserted++;
			}
			else
			{
#				logger('fetcher', 'ignore: ' .
#					   $_->{status_id} . '|' .
#					   $_->{screen_name} . '|' .
#					   $_->{status_text});
			}
		}
		$dbh->commit;

		$try++;
	}
	$sth->finish;

	logger('fetcher', "$inserted inserted.");

	return 1;
}


# 2008/03/17
sub bombtter_analyzer
{
	my $conf = shift || return undef;
	my $dbh = shift || return undef;

	logger('analyzer', 'running analyzer ' . $Bombtter::Analyzer::revision);

	my $ng_target_expr = join('|', @{$conf->{ng_target_expr}});
	#logger('analyzer', 'NG target: ' . $ng_target_expr);
	my $urgent_target_expr = join('|', @{$conf->{urgent_target_expr}});

	my $sth = $dbh->prepare('SELECT * FROM statuses WHERE analyzed IS NULL ORDER BY status_id DESC');
	$sth->execute();

	my @analyze_ok_ids = ();
	my @analyze_fail_ids = ();
	my @analyze_nobomb_ids = ();
	my @analyze_ng_ids = ();

	my $mecab_opts = '';
	if(defined($conf->{'mecab_userdic'}))
	{
		$mecab_opts .= '--userdic=' . $conf->{'mecab_userdic'};
	}

	my $sth_insert = $dbh->prepare(
		'INSERT OR IGNORE INTO bombs (status_id, target, target_normalized, source, urgency, category) VALUES (?, ?, ?, ?, ?, ?)');
	$dbh->begin_work;
	while(my $update = $sth->fetchrow_hashref)
	{
		my $status_id = $update->{status_id};
		my $target = $update->{status_text};
		my $source = $update->{source};

		logger('analyzer', "target: " . $target);

		# 爆発させないフラグ
		if($target =~ /爆発しろ.+-b/i || $target =~ /RT\s\@/)
		{
			push(@analyze_nobomb_ids, $status_id);
			logger('analyzer', "result: has no-bomb flag");
			next;
		}

		my $bombed;
		my $bombed_normalized;

		# april fool hack (2009/03/28)
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
			localtime(time);
		if(($mon+1 == 4 && $mday == 1) || $conf->{debug_aprilfool})
		{
			$bombed = $update->{screen_name};
		}
		else
		{
			$bombed = analyze($target, $mecab_opts);
		}

		$bombed_normalized = decode('utf8',
			Jcode->new(encode('utf8', $bombed))->h2z->utf8);
		$bombed_normalized =~ tr/Ａ-Ｚａ-ｚ０-９/A-Za-z0-9/;

		# 緊急度とカテゴリを決定
		my $urgency = 0;
		my $category = 0;

		if(length($bombed) >= 8)
		{
			$category = 1; # long
		}

		if($bombed_normalized =~ /$urgent_target_expr/i)
		{
			$urgency++;
		}

		#my $analyze_result;

		if(defined($bombed))
		{
			if($bombed =~ /$ng_target_expr/i)
			{
				# political through
				push(@analyze_ng_ids, $status_id);
				logger('analyzer', "result: NG");
			}
			else
			{
				push(@analyze_ok_ids, $status_id);
				$sth_insert->execute(
					$status_id,
					$bombed,
					$bombed_normalized,
					$source,
					$urgency,
					$category
				);
				logger('analyzer', "result: " . $bombed);
			}
		}
		else
		{
			push(@analyze_fail_ids, $status_id);
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
	foreach(@analyze_fail_ids)
	{
		$sth->execute(0, $_);
	}
	foreach(@analyze_nobomb_ids)
	{
		$sth->execute(-1, $_);
	}
	foreach(@analyze_ng_ids)
	{
		$sth->execute(-2, $_);
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
	my $category = shift || 0;

	logger('publisher', 'running publisher');
	if($limit_source >= 0)
	{
		logger('publisher', 'limit source: ' . $source_name[$limit_source]);
	}
	logger('publisher', 'category: ' . $category);

	my $ignore_target_expr = join('|', @{$conf->{ignore_target_expr}});
	#logger('publisher', 'IGNORE target: ' . $ignore_target_expr);

	my $count_target_expr = join('|', @{$conf->{count_target_expr}});
	#logger('publisher', 'COUNT target: ' . $count_target_expr);

	my $self_target_expr = join('|', @{$conf->{self_target_expr}});

	# FIXME
	my $enable_posting = $conf->{'twitter'}->{'enable'} || 0;
	my $limit = $conf->{'posts_at_once'} || 1;

	my $sql;

	# 時には自重する
	if($dt_local_now->month == 8 &&
	   ($dt_local_now->day == 6  || $dt_local_now->day == 9))
	{
		logger('publisher', 'take-care-of-myself mode activated');
		my $sth_takecare = $dbh->prepare(
			'UPDATE bombs SET result = -3, posted_at = CURRENT_TIMESTAMP ' .
			'WHERE posted_at IS NULL');
		$dbh->begin_work;
		$sth_takecare->execute;
		$dbh->commit;
		$sth_takecare->finish;
		undef $sth_takecare;
	}

	# 一定期間内にある回数以上要求しているユーザの投稿をスルー
	my $buzzterm = $dt_now->clone->subtract(hours => $conf->{buzzuser_term})->strftime('%Y-%m-%d %H:%M:%S');
	logger('publisher', 'checking buzz-users in ctime > ' . $buzzterm .
						' with thresh ' . $conf->{buzzuser_thresh});
	$sql =
		'UPDATE bombs SET result = -2, posted_at = CURRENT_TIMESTAMP ' .
		'WHERE status_id IN ' .
		'  (SELECT status_id FROM statuses WHERE screen_name IN ' .
		'    (SELECT screen_name FROM statuses ' .
		'       WHERE ctime > \'' . $buzzterm . '\' GROUP BY screen_name ' .
		'       HAVING COUNT(*) > ' . $conf->{buzzuser_thresh}. ')' .
		'  ) AND posted_at IS NULL';
	my $sth_buzzuser = $dbh->prepare($sql);
	$dbh->begin_work;
	$sth_buzzuser->execute;
	$dbh->commit;
	$sth_buzzuser->finish;
	undef $sth_buzzuser;

	# buzz ってるものをスルー
	# 2009/09/10: buzz ってるワードを含むものをスルーするよう変更
	#             TODO 形態素解析するなど要改善
	logger('publisher', 'checking buzz-words');

	# buzzword リスト取得
	my @buzzwordlist = ();
	$sql = 'SELECT LOWER(target) AS ltarget FROM buzz WHERE out_at IS NULL';
	my $sth_buzzword = $dbh->prepare($sql);
	$sth_buzzword->execute;
	while(my $buzzword = $sth_buzzword->fetchrow_hashref)
	{
		push(@buzzwordlist, $buzzword->{ltarget});
	}
	$sth_buzzword->finish; undef $sth_buzzword;

	$dbh->begin_work;
	foreach(@buzzwordlist)
	{
		next if(length($_) < 3);

		# FIXME
		my $target = $dbh->quote($_);
		if(!defined($target)) { $target = $_; }

		my $sth_word = $dbh->prepare(
			'UPDATE bombs SET result = -1, posted_at = CURRENT_TIMESTAMP ' .
			"WHERE LOWER(target) LIKE '%" . $_ . "%' AND posted_at IS NULL");
		$sth_word->execute;
		$sth_word->finish; undef $sth_word;
	}
	$dbh->commit;


	# ========================================================================
	# post target の選択

	my $multipostmode = 1;

	$sql = 'SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL';
	if($limit_source >= 0)
	{
		$sql .= ' AND source = ' . $limit_source;
	}

	my $hashref = $dbh->selectrow_hashref($sql);
	my $n_unposted = $hashref->{'count'};
	logger('publisher', "bombs in queue: $n_unposted");

	# post queue の数を見て limit を調節する
	if($n_unposted >= 10)
	{
		$limit = int($n_unposted/10)+1;
	}
	my $max_posts_at_once = $conf->{'max_posts_at_once'} || 1;
	if($limit > $max_posts_at_once)
	{
		$limit = $max_posts_at_once;
	}
 
	if($multipostmode == 1 && $category == 0)
	{
		$limit = 20;
	}

	my @posts = ();
	$sql =
		'SELECT rowid, status_id, target, category, '.
		'(SELECT s.permalink FROM statuses s ' .
		'WHERE s.status_id = b.status_id) AS permalink ' .
		'FROM bombs b WHERE posted_at IS NULL ';
	if($limit_source >= 0)
	{
		$sql .= 'AND source = ' . $limit_source . ' ';
	}
	$sql .= 'AND category = ' . $category . ' ';
	$sql .= 'ORDER BY urgency DESC, status_id ASC LIMIT ?';
	my $sth = $dbh->prepare($sql);

	$sth->execute($limit);
	while(my $update = $sth->fetchrow_hashref)
	{
		my $status_id = $update->{status_id};
		my $rowid = $update->{rowid};
		my $target = $update->{target};
		my $category = $update->{category};
		my $permalink = $update->{permalink};

		# post 内容の構築

		my $result;

		# ターゲットチェック
		my $selfbomb = 0;
		if($target =~ /$self_target_expr/i)
		{
			# 自爆

			$result = 'が自爆しました。';
			$selfbomb = 1;
		}
		else
		{
			$result = 'が爆発しました。';
		}

		my $bomb_result = 0;
		my $post;
		if($target =~ /$ignore_target_expr/i)
		{
			# 自重すべきもの
			$post = '昨今の社会情勢を鑑みて検討を行った結果、'
				  . $target . 'は爆発しませんでした。';
		}
		else
		{
			$post = $target . $result;
			$bomb_result = 1;
		}

		# 2008/11/15 (fix 2008/11/18)
		$post =~ s/^(\@[0-9a-zA-Z_]+)/$1 /g;
		$post =~ s/(.+?)(\@[0-9a-zA-Z_]+)/$1 $2 /g;
		$post =~ s/\s{2,}\@/ \@/g;
		$post =~ s/(\@[0-9a-zA-Z_]+)\s{2,}/$1 /g;

		# 仕様が変わったようなのでさらに置換しておく(2009/07/27)
		# raw に投げるほうは別途置換 (2009/09/20)
		$post =~ s/\@/＠/g;

		push(@posts, {
			target => $target,
			category => $category,
			id => $status_id,
			post => $post,
			rowid => $rowid,
			result => $bomb_result,
			permalink => $permalink,
			selfbomb => $selfbomb,
			proceeded => 0,
		});
		#print Dump($posts[$#posts]);
	}
	$sth->finish;


	my $twit = Net::Twitter->new(
			username => $conf->{twitter}->{username},
			password => $conf->{twitter}->{password});

	$sth = $dbh->prepare(
			'UPDATE bombs SET posted_at = CURRENT_TIMESTAMP, result = ? WHERE status_id = ?');
	my $n_posted = 0;

	# ========================================================================
	# まとめモード(nターゲット/1post)
	# カテゴリ 0 のターゲットのみ
	if($#posts >= 0 && $multipostmode == 1 && $category == 0)
	{
		# 前処理: 回数計算等
		my $bomb_type = 0;
		my %targets = ();
		foreach my $p (@posts)
		{
			if(defined($targets{$p->{target}}))
			{
				$targets{$p->{target}}->{count_now}++;
			}
			else
			{
				$targets{$p->{target}} = {
					data => $p,
					count_now => 1,		# この post での回数
					count_total => 0,	# 合計回数
					count_target => 0,
				};
			}

			# 自爆,result 0 のものがあるかチェック
			if($p->{result} == 0)
			{
				$bomb_type = 2;
			}
			if($p->{selfbomb} == 1)
			{
				$bomb_type = 1;
			}
		}

		foreach my $t (keys(%targets))
		{
			# カウント対象なら数えておく
			if($t =~ /$count_target_expr/i)
			{
				my $sql =
					'SELECT COUNT(*) AS count FROM bombs' .
					'  WHERE LOWER(target) = LOWER(?)' .
					'    AND posted_at IS NOT NULL AND result = 1';
				my $row = $dbh->selectrow_hashref($sql, undef, $t);

				printf "%s: %d + %d\n", $t, $row->{count}, $targets{$t}->{count_now};
				$targets{$t}->{count_total} =
					$row->{count} + $targets{$t}->{count_now};
				if($targets{$t}->{count_total} > 1)
				{
					$targets{$t}->{count_target} = 1;
				}
			}
		}
		#print Dump(%targets);

		my $post_prefix;
		my $post_suffix;

		# プレフィクス・サフィックスの決定
		if($bomb_type == 1)
		{
			$post_prefix = '';
			$post_suffix = 'が自爆しました。';
		}
		elsif($bomb_type == 2)
		{
			$post_prefix = '昨今の社会情勢を鑑みて検討を行った結果、';
			$post_suffix = 'は爆発しませんでした。';
		}
		else
		{
			$post_prefix = '';
			$post_suffix = 'が爆発しました。';
		}

		my $post_content = '';
		# 1 文字は連投対策の空白分
		my $post_length = $conf->{multipost}->{max_length} - 1;

		# 可変部分以外の文字数を引いておく
		$post_length -= (length($post_prefix) + length($post_suffix));

		foreach my $t (keys %targets)
		{
			my $p = $targets{$t}->{data};
			# result0 のものがあればそれだけ，無ければそれ以外を追加していく
			if($bomb_type == 1)
			{
				next if($p->{selfbomb} != 1);
			}
			elsif($bomb_type == 2)
			{
				next if($p->{result} != 0);
			}
			else
			{
				next if($p->{result} == 0);
				next if($p->{selfbomb} == 1);
			}

			my $add_content = '';
			if($post_content ne '')
			{
				$add_content .= '、';
			}
			$add_content .= $p->{target};

			# 回数表示
			if($targets{$t}->{count_now} > 1)
			{
				$add_content .= sprintf 'が%d発', $targets{$t}->{count_now};
			}
			if($targets{$t}->{count_target} == 1)
			{
				$add_content .= sprintf '(%d回目)',
					$targets{$t}->{count_total};
			}

			if($post_length - length($add_content) < 0)
			{
				# これ以上追加できない
				last;
			}

			$post_content .= $add_content;
			$post_length -= length($add_content);

			foreach(@posts)
			{
				if($_->{target} eq $t)
				{
					$_->{proceeded} = 1;
				}
			}
		}

		$post_content = $post_prefix . $post_content . $post_suffix;
		printf "%s (len=%d)\n", $post_content, length($post_content);

		foreach(@posts)
		{
			printf "%d %s\n", $_->{proceeded}, $_->{target};
		}

		# 投稿処理

		my $twit_post = Net::Twitter->new(
				username => $conf->{twitter}->{normal}->{username},
				password => $conf->{twitter}->{normal}->{password});

		logger('publisher', "post: $post_content");

		my $status = undef;
		if($conf->{twitter}->{normal}->{enable})
		{
			eval {
				$status = $twit_post->update(encode('utf8', $post_content));
			};

			logger('publisher', sprintf('update main: code %d %s',
				$twit_post->http_code, $twit_post->http_message));
			logger('publisher', Dump($status));

			if($twit_post->http_code == 200)
			{
				# post 成功: bombs を UPDATE する
				foreach(@posts)
				{
					if($_->{proceeded} == 1)
					{
						$sth->execute($_->{result}, $_->{id});
						$n_posted++;
					}
				}
			}
			else
			{
				&error('failed to update: ' . Dump($twit_post->get_error));
			}

# FIXME
#			if($conf->{twitter_raw}->{enable})
#			{
#				my $twit2 = Net::Twitter->new(
#					username => $conf->{twitter_raw}->{username},
#					password => $conf->{twitter_raw}->{password});
#				my $trigger = '-/0';
#				if($permalink =~ m{twitter\.com/([^/]+)/statuses/(\d+)})
#				{
#					$trigger = $1 . '/' . $2;
#				}
#				my $target_san = $target;
#				$target_san =~ s/\@/＠/g;
#				for(my $try = 0; $try < 3; $try++)
#				{
#					eval {
#						$status = $twit2->update(encode('utf8',
#							sprintf('%d,%d|%s|%s',
#								$bomb_result, $count, $trigger, $target_san)));
#					};
#					logger('publisher', 'update raw: code ' .
#							$twit2->http_code . ' ' . $twit2->http_message);
#					last if($twit2->http_code == 200);
#				}
#			}
		}
	}
	# ========================================================================
	else
{
	# 通常モード(1ターゲット/1post)
	foreach(@posts)
	{
		my $post = $_->{post};
		my $target = $_->{target};
		my $rowid = $_->{rowid};
		my $bomb_result = $_->{result};
		my $permalink = $_->{permalink};
		my $count = 1;

		# 負荷分散
		my $lb_target = 'normal';
		if($_->{category} == 1)
		{
			$lb_target = 'long';
		}

		logger('publish', sprintf('using account %s for %s target',
			$conf->{twitter}->{$lb_target}->{username}, $lb_target));

		my $twit_post = Net::Twitter->new(
				username => $conf->{twitter}->{$lb_target}->{username},
				password => $conf->{twitter}->{$lb_target}->{password});

		my $sql =
			'SELECT COUNT(*) AS count FROM bombs' .
			'  WHERE LOWER(target) = LOWER(?)' .
			'    AND posted_at IS NOT NULL AND result = 1';  # post されたものから数える
#			'  GROUP BY target';
		my $sth_count = $dbh->prepare($sql);

		$sth_count->execute($target);
		if(my $ary = $sth_count->fetchrow_hashref)
		{
			$count = $ary->{count}+1;
			if($target =~ /$count_target_expr/i && $count > 1)
			{
				$post .= '(' . $count . '回目)';
			}
		}

		# 連投対策
		if($rowid % 2 == 1)
		{
			$post .= '　'; # 全角スペース
		}

		logger('publisher', "post: $post");

		my $status = undef;
		if($enable_posting)
		{
			eval { $status = $twit_post->update(encode('utf8', $post)); };

			logger('publisher', 'update main: code ' .
								$twit_post->http_code . ' ' . $twit_post->http_message);
			logger('publisher', Dump($status));

			if($twit_post->http_code == 200)
			{
				# post 成功: bombs を UPDATE する
				$sth->execute($bomb_result, $_->{'id'});
				$n_posted++;
			}
			else
			{
				&error('failed to update: ' . Dump($twit_post->get_error));
			}

			if($conf->{twitter_raw}->{enable})
			{
				my $twit2 = Net::Twitter->new(
					username => $conf->{twitter_raw}->{username},
					password => $conf->{twitter_raw}->{password});
				my $trigger = '-/0';
				if($permalink =~ m{twitter\.com/([^/]+)/statuses/(\d+)})
				{
					$trigger = $1 . '/' . $2;
				}
				my $target_san = $target;
				$target_san =~ s/\@/＠/g;
				for(my $try = 0; $try < 3; $try++)
				{
					eval {
						$status = $twit2->update(encode('utf8',
							sprintf('%d,%d|%s|%s',
								$bomb_result, $count, $trigger, $target_san)));
					};
					logger('publisher', 'update raw: code ' .
							$twit2->http_code . ' ' . $twit2->http_message);
					last if($twit2->http_code == 200);
				}
			}
		}
	}
}
	$sth->finish;

#	my $profile_name = 'bombtter';
#	if($n_unposted >= 10)
#	{
#		$profile_name .= sprintf(' (忙しいLv%d)', int($n_unposted/10));
#	}
	#$twit->update_profile({name => encode('utf8', $profile_name)});
	#$twit->update_profile({name => $profile_name});

	logger('publisher', "posted $n_posted bombs, $n_unposted unposted.");

	my $ratelimit = $twit->rate_limit_status;
	logger('publisher', sprintf('Twitter API: %s/%s',
		$ratelimit->{remaining_hits}, $ratelimit->{hourly_limit}));

	if($conf->{twitter_status}->{enable})
	{
		my $twit2 = Net::Twitter->new(
			username => $conf->{twitter_status}->{username},
			password => $conf->{twitter_status}->{password});
		eval {
			if($n_unposted >= 10)
			{
				my $status = $twit2->update(encode('utf8',
					sprintf('【遅延】混雑度 %d',
						int($n_unposted/10))));
			}
		};
	}

	return 1;
}

sub bombtter_lock
{
	my %lfh = (dir => $LOCKDIR, basename => $LOCKFILE,
			   timeout => 120,  trytime => 5, @_);
	$lfh{path} = $lfh{dir} . $lfh{basename};

	for(my $i = 0; $i < $lfh{trytime}; $i++, sleep 1)
	{
		return \%lfh if(rename($lfh{path}, $lfh{current} = $lfh{path} . time));
	}

	opendir(LOCKDIR, $lfh{dir});
	my @filelist = readdir(LOCKDIR);
	closedir(LOCKDIR);
	foreach(@filelist)
	{
		if(/^$lfh{basename}(\d+)/)
		{
			return \%lfh if(time - $1 > $lfh{timeout} and
				rename($lfh{dir} . $_, $lfh{current} = $lfh{path} . time));
			last;
		}
	}

	return undef;
}

sub bombtter_unlock
{
	my $lfh = shift;
	rename($lfh->{current}, $lfh->{path});
}

sub error
{
	my $msg = shift || '';
	my $lfh = shift || undef;

	logger('error', $msg);
	&bombtter_unlock($lfh) if(defined($lfh));
	exit;
}

# vim: noexpandtab
