#!/usr/bin/perl -w

# Bombtter - What are you bombing?
# 2008/03/16 naoh
# $Id$

use strict;
use utf8;

use Net::Twitter;
use Encode;

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

	if($count > 1)
	{
		#$extra = 'また';
	}

	my $result = 'が' . $extra . '爆発しました。';
	if(int(rand(100)) < 5)
	{
		#$result = 'は爆発しませんでした。';
	}

	#my $post = '●~* ' . $target . $result;
	my $post = '[●~] ' . $target . $result;

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
		# FIXME $twit->http_code のチェック
		logger(Dump($status));
		if(defined($status))
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
