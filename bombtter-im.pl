#!/usr/bin/perl

# 2008/05/16
# 参考:
#  http://iyouneta.blog49.fc2.com/?no=306
#  http://dev.ariel-networks.com/column/tech/xmpp

use warnings;
use strict;
use utf8;

use Net::Jabber;
use YAML;
use XML::TreePP;
use DBI;
use Net::Twitter::Diff;

use lib './lib';
use Bombtter;

my $TWITTER_JID = 'twitter@twitter.com';

my $conf = load_config or &error('load_config failed');
set_terminal_encoding($conf);

*LOG = *STDERR;

my $mainloop = 1;

$SIG{HUP} = \&stop;
$SIG{KILL} = \&stop;
$SIG{TERM} = \&stop;
$SIG{INT} = \&stop;

# ---------------------------------------------------------------------------
my $dbh = DBI->connect(
    'dbi:SQLite:dbname=' . $conf->{db}->{im}, '', '', {unicode => 1});
$dbh->func(5000, 'busy_timeout');

my $jabber = Net::Jabber::Client->new(
#        debuglevel => 1,
#        debugfile  => "debug.log",
) or die "can't create Net::XMPP::Client instance.";

my $twitter = Net::Twitter::Diff->new(
        username => $conf->{twitter}->{username},
        password => $conf->{twitter}->{password},
);

my $next_autofollow_time = 0;

&debug('starting ...');
while($mainloop)
{
    my $r = &main;
    &debug('r = %s', $r);
    last if($r == 0);

    sleep(5);
}

&debug('exit');
$jabber->Disconnect;
$dbh->disconnect;
exit 0;
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
sub main
{
    &debug('Jabber: Connecting ...');
    $jabber->Connect(
            hostname => $conf->{jabber}->{hostname} || die,
            port => $conf->{jabber}->{port} || 5222,
            tls => $conf->{jabber}->{tls} || 0,
    ) or return -10;

    $jabber->SetCallBacks(
            message   => \&recv_message,
    );

    &debug('Jabber: Waiting for authenticated ...');
    my @result = $jabber->AuthSend(
            username => $conf->{jabber}->{username} || die("username"),
            password => $conf->{jabber}->{password} || die("password"),
            resource => $conf->{jabber}->{resource} || die("resource"),
            hostname => $conf->{jabber}->{hostname} || die("hostname"),
    ) or return -5;

    return -2 if($result[0] ne 'ok');

    &debug('Jabber: Connected.');

    $jabber->RosterGet;
    $jabber->PresenceSend;

    #&send_message('whois n13i');

    while(defined($jabber->Process(5)))
    {
        return 0 if(!$mainloop);

        if(($conf->{autofollow_interval} || 0) > 0 &&
           time >= $next_autofollow_time)
        {
            &autofollow;
            $next_autofollow_time = time + $conf->{autofollow_interval};
        }

        sleep(1);
    }

    &debug('Jabber: Status not ok.');
    return -1;
}

# ---------------------------------------------------------------------------
sub stop
{
    &debug('caught signal');
    $mainloop = 0;
}

# ---------------------------------------------------------------------------
sub recv_message
{
    my $sid = shift;
    my $message = shift;

    my $type = $message->GetType;
    my $from = $message->GetFrom;
    my $body = $message->GetBody;

    &debug('<< from %s, type %s : [%s]', $from, $type, $body);

    return if($from ne $TWITTER_JID);

    return if($body !~ /爆発しろ/);

    my $tpp = XML::TreePP->new;
    my $tree = $tpp->parse($message->GetXML);

    return if(!defined($tree->{message}->{entry}));

    my $screen_name = $tree->{message}->{entry}->{source}->{author}->{screen_name};
    if($tree->{message}->{entry}->{source}->{author}->{protected} eq 'true')
    {
        &debug('%s is protected, skip.', $screen_name);
        return;
    }

    my $status_text = $tree->{message}->{body};
    $status_text =~ s/^[^:]+\:\s+//;

    my $status_id = $tree->{message}->{entry}->{status_id};
    if(!defined($status_id))
    {
        # twitter_id だったりもする
        $status_id = $tree->{message}->{entry}->{twitter_id};
    }

    my $status = {
        status_id => $status_id,
        permalink => $tree->{message}->{entry}->{link}->{-href},
        name => $tree->{message}->{entry}->{source}->{author}->{name},
        screen_name => '@' . $screen_name,
        status_text => $status_text,
    };
    print Dump($status);
    print "===\n";

    my $sth = $dbh->prepare('INSERT INTO statuses ' .
        '(status_id, permalink, name, screen_name, status_text) ' .
        'VALUES (?, ?, ?, ?, ?)');
    $sth->execute(
        $status->{status_id},
        $status->{permalink},
        $status->{name},
        $status->{screen_name},
        $status->{status_text});
    $sth->finish;
}

# ---------------------------------------------------------------------------
sub send_message
{
    my $msg = shift || return undef;
    &debug('>> [%s]', $msg);
                                                                                    my $message = Net::Jabber::Message->new;
    $message->SetMessage(
            to   => $TWITTER_JID,
            type => 'chat',
            body => $msg);

    $jabber->Send($message);
}

# ---------------------------------------------------------------------------
# 自動 follow/remove 処理
sub autofollow
{
    &debug('Performing auto follow/remove process ...');

    my $diff = $twitter->diff();

    my $n = 0;
    foreach(@{$diff->{not_following}})
    {
        last if($n > 100);
        $n++;

        &debug('start following %s', $_);
        &send_message('on ' . $_);
    }

    $n = 0;
    foreach(@{$diff->{not_followed}})
    {
        last if($n > 10); # API 制限対策
        $n++;

        &debug('stop following %s', $_);
        $twitter->stop_following($_);
    }

    &debug('auto follow/remove done.');
}

# ---------------------------------------------------------------------------
sub debug
{
    my $fmtstr = shift;
    printf LOG "$fmtstr\n", @_;
}

