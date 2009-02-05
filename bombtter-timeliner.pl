#!/usr/bin/perl
# 2008/06/15
# Twitter のタイムラインをスクレイピングする

use warnings;
use strict;
use utf8;

use LWP::UserAgent;
use HTTP::Cookies;
use DBI;
use Encode;
use HTML::Entities;
use Net::Twitter::Diff;

use lib './lib';
use Bombtter;

my $conf = load_config or &error('load_config failed');
set_terminal_encoding($conf);

select(STDERR); $| = 1; select(STDOUT);
*LOG = *STDERR;

# login to twitter
my $ua = LWP::UserAgent->new();
my $cookie_jar = HTTP::Cookies->new(file => 'cookies.txt', autosave => 1);
$ua->cookie_jar($cookie_jar);
my $r = &login($ua, $conf->{twitter}->{username}, $conf->{twitter}->{password});
if(!defined($r))
{
    die "login failed\n";
}
my $html = decode('utf8', $r->content);


my $dbh = DBI->connect(
    'dbi:SQLite:dbname=' . $conf->{db}->{timeliner}, '', '', {unicode => 1});
$dbh->func(5000, 'busy_timeout');

my $twitter = Net::Twitter::Diff->new(
	username => $conf->{twitter}->{username},
	password => $conf->{twitter}->{password},
);

my $mainloop = 1;

$SIG{HUP} = \&stop;
$SIG{KILL} = \&stop;
$SIG{TERM} = \&stop;
$SIG{INT} = \&stop;

my $local_latest_id = 0;

my $next_autofollow_time = time + $conf->{autofollow_interval};
my $fetch_interval = $conf->{timeliner}->{fetch_interval} || 120;
my $traceback_limit = $conf->{timeliner}->{traceback_limit} || 5;

while($mainloop)
{
	print "===> fetching ...\n";
	&fetch_timeline;
	printf "===> done. wait %d seconds ...\n", $fetch_interval;
	sleep $fetch_interval;

	if(($conf->{autofollow_interval} || 0) > 0 &&
	   time >= $next_autofollow_time)
	{
		&autofollow;
		$next_autofollow_time = time + $conf->{autofollow_interval};
	}
}
$dbh->disconnect;
exit;

sub fetch_timeline
{
#	# DB 内の最新 status_id を取得
#	my $tmp = $dbh->selectrow_hashref('SELECT status_id FROM statuses ORDER BY status_id DESC LIMIT 1');
#	my $local_latest_id = $tmp->{status_id} || 0;

	my @statuses = ();
	for(my $i = 0; $i < $traceback_limit; $i++)
	{
		my $remote_oldest_id = 10000000000;
		if(!defined($html))
		{
			my $page = $i+1;
			printf "fetching timeline page %d\n", $page;
		    my $res = $ua->get('https://twitter.com/home?page=' . $page);
		    if($res->code != 200)
		    {
				printf "error %d\n", $res->code;
				$html = undef;
				last;
		    }
			$html = decode('utf8', $res->content);
		}

#		my @entries = $html =~ m{(<tr id="status_\d+" class="hentry.+?</tr>)}sg;
#		my @entries = $html =~ m{(<tr\s.*?id="status_\d+".+?</tr>)}sg;
		my @entries = $html =~ m{(<li\s.*?id="status_\d+".+?</li>)}sg;
		printf "entries: %d\n", $#entries+1;

		foreach my $entry (@entries)
		{
			my $s = &parse_entry($entry);
			if(defined($s))
			{
				#use YAML;
				#print Dump($s);
				printf "[%d] (%d) %s / %s: %s\n",
					$s->{status_id}, $s->{is_protected},
					$s->{screen_name}, $s->{name}, $s->{status_text};
				if($s->{status_id} < $remote_oldest_id)
				{
					$remote_oldest_id = $s->{status_id};
				}
				push(@statuses, $s);
			}
		}

		printf "remote: %d / local: %d\n", $remote_oldest_id, $local_latest_id;
		last if($remote_oldest_id <= $local_latest_id);

		$html = undef;
	}
	if(!defined($html))
	{
		print "maybe lost some status\n";
	}
	printf "statuses: %d\n", $#statuses+1;
	
	my $sth = $dbh->prepare('INSERT OR IGNORE INTO statuses ' .
	    '(status_id, permalink, screen_name, name, status_text, is_protected) ' .
	    'VALUES (?, ?, ?, ?, ?, ?)');
	$dbh->begin_work;
	foreach(@statuses)
	{
		if($_->{status_id} > $local_latest_id)
		{
			$local_latest_id = $_->{status_id};
		}

		next if($_->{status_text} !~ /爆発しろ/);
		next if($_->{is_protected} && $_->{status_text} !~ /^\@$conf->{twitter}->{username}/);

		# FIXME
		if(defined($_->{status_id}) && $_->{status_text} =~ /<img/)
		{
			# アイコン対策
			my $status = $twitter->show_status($_->{status_id});
	        $_->{status_text} = &_normalize_status_text($status->{text});
		}

		use YAML;
		print Dump($_);

		$sth->execute(
		    $_->{status_id},
		    $_->{permalink},
		    $_->{screen_name},
		    $_->{name},
		    $_->{status_text},
		    $_->{is_protected});
	}
	$dbh->commit;
	$sth->finish;
	undef $sth;

	$html = undef;
}

sub parse_entry
{
	my $entry = shift || return undef;

    my $s = {
        status_id => undef,
        permalink => undef, 
        screen_name => undef,
        name => undef,
        status_text => undef,
        is_protected => undef,
    };

	if($entry =~ m{<span class="status-body"><strong><a href="https?://twitter.com/[^"]+" title="([^"]+)">}s)
    {
        $s->{name} = &_normalize_status_text($1);
    }

    $s->{is_protected} = 1;
    if($entry !~ m{<img alt="Icon_red_lock"}s)
    {
        $s->{is_protected} = 0;
    }

    if($entry =~ m{<span class="entry-content">\s*(.+?)\s*</span>}s)
    {
        $s->{status_text} = &_normalize_status_text($1);
    }

    if($entry =~ m{<span class="meta entry-meta">\s*<a href="https?://twitter\.com/([^/]+)/status(?:es)?/(\d+)" class="entry-date"}s)
    {
        $s->{status_id} = $2;
        $s->{permalink} = 'http://twitter.com/' . $1 . '/statuses/' . $2;
        $s->{screen_name} = '@' . $1;
    }

	if(defined($s->{status_id}) && defined($s->{permalink}) &&
	   defined($s->{screen_name}) && defined($s->{name}) &&
	   defined($s->{status_text}) && defined($s->{is_protected}))
	{
		return $s;
	}

	return undef;
}

sub login
{
    my $ua = shift || return undef;
    my $username = shift || return undef;
    my $password = shift || return undef;

	$ua->max_redirect(0);
    my $res = $ua->get('https://twitter.com/home');
	if($res->code == 200 && !$res->is_redirect)
	{
		return $res;
	}

    $res = $ua->get('https://twitter.com/login');
	my $auth_token = '';
	if($res->content =~ m{name="authenticity_token"\s+type="hidden"\s+value="(\w{40})"})
	{
		$auth_token = $1;
	}
	else
	{
    	print "Login: can't get authenticity token\n";
		return undef;
	}
    print "Login: as $username\n";
    $res = $ua->post('https://twitter.com/sessions' => {
        'session[username_or_email]' => $username,
        'session[password]' => $password,
		authenticity_token => $auth_token,
        remember_me => 1,
    });
    my $n_redirect = 0;
    while($res->is_redirect)
    {
        my $url = $res->header('Location');
        print "Login: redirect to $url ...\n";
        $res = $ua->get($url);
        $n_redirect++;
        last if($n_redirect > 5);
    }
    if($res->code != 200)
    {
        printf "Login: failed (code = %d)\n", $res->code;
        return undef;
    }

    return $res;
}

sub _normalize_status_text
{
    my $s = shift || '';

	decode_entities($s);

    # @ リンクの除去
    $s =~ s#\@<a href="/[^"]+">(.+?)</a>#\@$1#g;

    # <a href="~"> の除去
    $s =~ s#<a\s+(?:.+?)?href="([^"]+)"[^>]*>.+?</a>#$1#g;

    return $s;
}

sub stop
{
	$mainloop = 0;
}

# ---------------------------------------------------------------------------
# 自動 follow/remove 処理
sub autofollow
{
    &debug('Performing auto follow/remove process ...');

    eval {
        my $diff = $twitter->diff();
    
        my $n = 0;
        foreach(@{$diff->{not_following}})
        {
            #last if($n > 20);
            last if($n > 5);
            $n++;
    
            &debug('start following %s', $_);
            #&send_message('on ' . $_);
            $twitter->create_friend($_);
        }
    
        $n = 0;
        foreach(@{$diff->{not_followed}})
        {
            last if($n > 5); # API 制限対策
            $n++;
    
            &debug('stop following %s', $_);
            $twitter->destroy_friend($_);
        }
    };
    warn $@ if $@;

    &debug('auto follow/remove done.');
}

# ---------------------------------------------------------------------------
sub debug
{
    my $fmtstr = shift;
    printf LOG "$fmtstr\n", @_;
}

# vim: noexpandtab
