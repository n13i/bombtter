#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use DateTime;
use Net::Twitter;
use Encode;

use lib './lib';
use Bombtter;


my $conf = load_config;
set_terminal_encoding($conf);

my $thresh = $ARGV[0] || 1;

my $dbh = db_connect($conf);

my $longterm_days = 7;
my $shortterm_hours = 3;

my $dt_now = DateTime->now(time_zone => '+0000');
#$dt_now->subtract(hours => 28);

my $twit = Net::Twitter->new(
		username => $conf->{twitter}->{username},
		password => $conf->{twitter}->{password});

# ---------------------------------------------------------------------------
# 短期
# ---------------------------------------------------------------------------
my $dt_from = $dt_now->clone->subtract(hours => $shortterm_hours)->strftime('%Y-%m-%d %H:%M:%S');
my $dt_to = $dt_now->clone->strftime('%Y-%m-%d %H:%M:%S');

my $sth = $dbh->prepare('SELECT COUNT(target) as count, LOWER(target) as target FROM bombs WHERE ctime > ? AND ctime <= ? GROUP BY target ORDER BY LOWER(count) DESC');
$sth->execute($dt_from, $dt_to);
my @shortterm = ();
while(my $row = $sth->fetchrow_hashref)
{
    push(@shortterm, $row);
}
$sth->finish;

# ---------------------------------------------------------------------------
# 長期
# ---------------------------------------------------------------------------
$dt_from = $dt_now->clone->subtract(days => $longterm_days)->strftime('%Y-%m-%d %H:%M:%S');
$dt_to = $dt_now->clone->subtract(hours => $shortterm_hours)->strftime('%Y-%m-%d %H:%M:%S');

$sth = $dbh->prepare('SELECT COUNT(target) as count, LOWER(target) as target FROM bombs WHERE ctime > ? AND ctime <= ? GROUP BY target ORDER BY LOWER(count) DESC');
$sth->execute($dt_from, $dt_to);
my @longterm = ();
while(my $row = $sth->fetchrow_hashref)
{
    push(@longterm, $row);
}
$sth->finish;

# ---------------------------------------------------------------------------
# buzz ってると思われるものを抽出
# ---------------------------------------------------------------------------
my @buzz = ();
foreach my $st (@shortterm)
{
    my $count_st = $st->{count};
    my $level_st = $count_st;
    my $count_lt = 0;
    my $level_lt = 0;

    foreach my $lt (@longterm)
    {
        if($st->{target} eq $lt->{target})
        {
            $count_lt = $lt->{count};
            # 最近一週間の 1 日平均
            $level_lt = $count_lt/$longterm_days * ($conf->{hotbomb_thresh} || 1.5);
            last;
        }
    }
    printf "L:%3d(%.4f)/S:%3d(%.4f)\t%s\n", $count_lt, $level_lt, $count_st, $level_st, $st->{target};
    #if($level_st > $level_lt && $count_st >= 3)
    if($count_st >= 3)
    {
        push(@buzz, $st);
    }
}

# ---------------------------------------------------------------------------
# DB 上の buzzing 情報を取得
# ---------------------------------------------------------------------------
logger('hot', 'buzzing on db:');
my @buzz_on_db = ();
$sth = $dbh->prepare('SELECT id, LOWER(target) as target FROM buzz WHERE out_at IS NULL');
$sth->execute;
while(my $row = $sth->fetchrow_hashref)
{
    push(@buzz_on_db, $row);
    logger('hot', '  ' . $row->{target});
}
$sth->finish;

# ---------------------------------------------------------------------------
# 新規 buzz word
# ---------------------------------------------------------------------------
logger('hot', 'buzz-in:');
$sth = $dbh->prepare('INSERT INTO buzz (target) VALUES (?)');
foreach my $b (@buzz)
{
    my $found = 0;
    foreach my $d (@buzz_on_db)
    {
        if($b->{target} eq $d->{target})
        {
            # 既に buzz ってる
            $found = 1;
            last;
        }
    }

    if($found == 0)
    {
        logger('hot', '  ' . $b->{target});
        if($conf->{enable_hotbomb})
        {
    		if($conf->{twitter}->{enable})
    		{
                my $status;
                eval {
    				$status = $twit->update(encode('utf8',
    					sprintf('HOT: %s', $b->{target})));
                };
				if($twit->http_code == 200)
				{
	        		$sth->execute($b->{target});
				}
				else
				{
					logger('hot', 'failed to update');
				}
			}
			else
			{
				$sth->execute($b->{target});
			}
		}
    }
}
$sth->finish;

# ---------------------------------------------------------------------------
# buzz 状態終了のお知らせ
# ---------------------------------------------------------------------------
logger('hot', 'buzz-out:');
$sth = $dbh->prepare('UPDATE buzz SET out_at = CURRENT_TIMESTAMP WHERE id = ?');
foreach my $b (@buzz_on_db)
{
    my $found = 0;
    foreach my $st (@shortterm)
    {
        if($b->{target} eq $st->{target})
        {
            # まだ短期間中に爆発要求されている
            $found = 1;
            last;
        }
    }

    if($found == 0)
    {
        $sth->execute($b->{id});
        logger('hot', '  ' . $b->{target});
    }
}
$sth->finish;

undef $sth;
$dbh->disconnect;

