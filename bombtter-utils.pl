#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Net::Twitter;
use Encode;
use YAML;

use lib './lib';
use Bombtter;

my $conf = load_config or &error('load_config failed');
set_terminal_encoding($conf);

my $twitter = Net::Twitter->new(
	username => $conf->{twitter}->{username},
	password => $conf->{twitter}->{password},
);

my %func = (
	update_location => \&update_location,
	rate_limit_status => \&rate_limit_status,
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
	my $r = $twitter->update_profile({location => encode('utf8', $location)});
	print Dump($r);

	my $twit = Net::Twitter->new(
		username => $conf->{twitter_status}->{username},
		password => $conf->{twitter_status}->{password},
	);
	eval {
		$twit->update(encode('utf8', sprintf('【更新】%s', $location)));
	};
}

sub rate_limit_status
{
	my $r = $twitter->rate_limit_status;
	print Dump($r);
}

# vim: noexpandtab
