#!/usr/bin/perl -w

# Bombtter - What are you bombing?
# 2008/03/16 naoh
# $Id$

use strict;
use utf8;

use DBI;
use Net::Twitter;
use Encode;
use YAML;

#use lib './lib';
#use Bombtter;


my $conffile = 'bombtter.conf';
my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");

binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";

my $enable_posting = $conf->{'enable_posting'} || 0;
my $limit = $conf->{'posts_at_once'} || 1;


my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{'dbfile'}, '', '', {unicode => 1});

my $hashref = $dbh->selectrow_hashref('SELECT COUNT(*) AS count FROM bombs WHERE posted_at IS NULL');
my $n_unposted = $hashref->{'count'};
print "Unposted bombs: $n_unposted\n";

my @posts = ();
my $sth = $dbh->prepare('SELECT * FROM bombs WHERE posted_at IS NULL ORDER BY status_id ASC LIMIT ?');
$sth->execute($limit);
while(my $update = $sth->fetchrow_hashref)
{
	my $status_id = $update->{'status_id'};
	my $target = $update->{'target'};

	my $extra = '';
	if(int(rand(100)) < 10)
	{
		my @extras = ('盛大に', 'ひっそりと', '派手に');
		#$extra = $extras[int(rand($#extras+1))];
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

	print "$post\n";

	my $status = undef;
	if($enable_posting)
	{
		$status = $twit->update(encode('utf8', $post));
		print Dump($status);
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

print "posted $n_posted bombs.\n";

$dbh->disconnect;
