#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use DateTime;
use Net::Twitter::Lite::WithAPIv1_1;
use Encode;
use YAML;

use lib './lib';
use Bombtter;


my $conf = load_config;
set_terminal_encoding($conf);

my $dry_run = $ARGV[0] || 0;

my $dbh = db_connect($conf);

my $longterm_days = 7;
my $shortterm_hours = $conf->{hotbomb_shortterm_hours};

my $dt_now = DateTime->now(time_zone => '+0000');
#$dt_now->subtract(hours => 28);

my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key => $conf->{twitter}->{consumer_key},
    consumer_secret => $conf->{twitter}->{consumer_secret},
    ssl => 1,
);
$twit->access_token(
    $conf->{twitter}->{normal}->{access_token});
$twit->access_token_secret(
    $conf->{twitter}->{normal}->{access_token_secret});

# ---------------------------------------------------------------------------
# 最新の処理済み post の日時を取得
# ---------------------------------------------------------------------------
my $latest_bombed = $dbh->selectrow_hashref(
    'SELECT ctime FROM bombs WHERE posted_at IS NOT NULL '.
    'ORDER BY ctime DESC LIMIT 1'
);
if($latest_bombed->{ctime} =~ /(\d{4})\-(\d{2})\-(\d{2})\s(\d{2})\:(\d{2})\:(\d{2})/)
{
    $dt_now = DateTime->new(
        year => $1,
        month => $2,
        day => $3,
        hour => $4,
        minute => $5,
        second => $6,
        time_zone => '+0000',
    );
}

# ---------------------------------------------------------------------------
# 短期
# ---------------------------------------------------------------------------
my $dt_from = $dt_now->clone->subtract(hours => $shortterm_hours)->strftime('%Y-%m-%d %H:%M:%S');
my $dt_to = $dt_now->clone->add(hours => $shortterm_hours)->strftime('%Y-%m-%d %H:%M:%S');

my $sth = $dbh->prepare('SELECT COUNT(LOWER(target_normalized)) as count, target_normalized as target FROM bombs WHERE result >= 0 AND ctime > ? AND ctime <= ? GROUP BY LOWER(target_normalized) ORDER BY count DESC');
$sth->execute($dt_from, $dt_to);
my @shortterm = ();
while(my $row = $sth->fetchrow_hashref)
{
    if($dry_run == 1)
    {
        printf "hot: short-term count=%3d %s\n", $row->{count}, $row->{target};
    }
    push(@shortterm, $row);
}
$sth->finish;

# ---------------------------------------------------------------------------
# 長期
# ---------------------------------------------------------------------------
$dt_from = $dt_now->clone->subtract(days => $longterm_days)->strftime('%Y-%m-%d %H:%M:%S');
$dt_to = $dt_now->clone->subtract(hours => $shortterm_hours)->strftime('%Y-%m-%d %H:%M:%S');

$sth = $dbh->prepare('SELECT COUNT(LOWER(target_normalized)) as count, target_normalized as target FROM bombs WHERE result >= 0 AND ctime > ? AND ctime <= ? GROUP BY LOWER(target_normalized) ORDER BY count DESC');
$sth->execute($dt_from, $dt_to);
my @longterm = ();
while(my $row = $sth->fetchrow_hashref)
{
    next if(!defined($row->{target}));

    if($dry_run == 1)
    {
        printf "hot: long-term  count=%3d %s\n", $row->{count}, $row->{target};
    }
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
        next if(!defined($st->{target}) || !defined($lt->{target}));

        if(lc($st->{target}) eq lc($lt->{target}))
        {
            $count_lt = $lt->{count};
            # 最近一週間の 1 日平均
            $level_lt = $count_lt/$longterm_days * ($conf->{hotbomb_thresh} || 1.5);
            last;
        }
    }
    my $chk_level = ($level_st > $level_lt) ? 1 : 0;
    my $chk_count = ($count_st >= 3) ? 1 : 0;
    my $chk_impulse = (($level_st / $shortterm_hours) > $conf->{hotbomb_impulse_level}) ? 1 : 0;
    #printf "L:%3d(%.4f)/S:%3d(%.4f)\t%s\n", $count_lt, $level_lt, $count_st, $level_st, $st->{target};
    printf "hot: chk_impulse=%d level_st=%.4f %s level_lt=%.4f / count_st=%3d %s 3 / count_lt=%3d :\t%s\n",
        $chk_impulse, $level_st, (($chk_level == 1) ? '> ' : '<='), $level_lt, $count_st, (($chk_count == 1) ? '>=' : '< '), $count_lt, $st->{target};
    #if($count_st >= 3)
    if(($chk_level == 1 && $chk_count == 1) || $chk_impulse == 1)
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
        if(lc($b->{target}) eq lc($d->{target}))
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
    		if($conf->{twitter}->{normal}->{enable})
    		{
                my $status;
                eval {
                    if($dry_run == 0)
                    {
                        $status = $twit->update(
                                sprintf('HOT: %s', $b->{target}));
                    }
                };
				if(!$@)
				{
                    if($dry_run == 0)
                    {
	        		    $sth->execute($b->{target});
                    }
				}
				else
				{
					logger('hot', 'failed to update');
				}
			}
			else
			{
                if($dry_run == 0)
                {
                    $sth->execute($b->{target});
                }
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
        if(lc($b->{target}) eq lc($st->{target}))
        {
            # まだ短期間中に爆発要求されている
            $found = 1;
            last;
        }
    }

    if($found == 0)
    {
        if($dry_run == 0)
        {
            $sth->execute($b->{id});
        }
        logger('hot', '  ' . $b->{target});
    }
}
$sth->finish;

undef $sth;
$dbh->disconnect;

