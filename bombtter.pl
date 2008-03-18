#!/usr/bin/perl -w

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

#print $Bombtter::VERSION;
#exit;

my $conf = load_config;
set_terminal_encoding($conf);

my $enable_posting = $conf->{'enable_posting'} || 0;
my $limit = $conf->{'posts_at_once'} || 1;

my $dbh = db_connect($conf);

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

	if($target eq '@' . $conf->{'twitter_username'} . ' ')
	{
		# 身代わりに何か適当なものを爆発させる
		my $hashref = $dbh->selectrow_hashref('SELECT target FROM bombs WHERE posted_at IS NOT NULL ORDER BY RANDOM() LIMIT 1');
		my $subst = $hashref->{'target'};

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

$dbh->disconnect;
