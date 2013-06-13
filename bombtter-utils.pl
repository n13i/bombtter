#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Net::Twitter::Lite::WithAPIv1_1;
use Encode;
use YAML;

use lib './lib';
use Bombtter;

my $conf = load_config or &error('load_config failed');
set_terminal_encoding($conf);

my $twitter = Net::Twitter::Lite::WithAPIv1_1->new(
	consumer_key => $conf->{twitter}->{consumer_key},
	consumer_secret => $conf->{twitter}->{consumer_secret},
);

my %func = (
	update_location => \&update_location,
	rate_limit_status => \&rate_limit_status,
	replies => \&replies,
	oauth => \&oauth,
);

my $do = shift @ARGV || &usage;
my $f = $func{$do};
if(defined($f))
{
	printf "call %s\n", $do;
	&$f(@ARGV);
}

sub usage
{
	printf "usage: bombtter-utils.pl [%s] [args...]\n", join('|', keys(%func));
	exit;
}

sub update_location
{
	my $location = shift || die;

	&_do_auth('normal');

	my $r = $twitter->update_profile({location => $location});
	print Dump($r);

	&_do_auth('status');
	eval {
		my $s = $twitter->update(
			sprintf('【更新】%s', $location));
		print Dump($s);
	};
	if($@)
	{
		print "$@\n";
	}
}

sub rate_limit_status
{
	my $account = shift || 'normal';

	&_do_auth($account);
	my $r = $twitter->rate_limit_status;
	print Dump($r);
}

sub replies
{
	my $account = shift || 'normal';

	&_do_auth($account);
	my $r = $twitter->replies;
	print Dump($r);
}

sub oauth
{
    printf "Authorization URL: %s\n", $twitter->get_authorization_url;
    my $pin = <STDIN>;
    chomp $pin;

    print Dump($twitter->request_access_token(verifier => $pin));
}

sub _do_auth
{
	my $account = shift || die;

	$twitter->access_token(
		$conf->{twitter}->{$account}->{access_token});
	$twitter->access_token_secret(
		$conf->{twitter}->{$account}->{access_token_secret});
}

# vim: noexpandtab
