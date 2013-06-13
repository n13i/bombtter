#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use YAML;

use lib './lib';
use Bombtter;
use Bombtter::Fetcher;

my $conf = load_config or die('load_config failed');
set_terminal_encoding($conf);

my $key = $ARGV[0] || die;

my $r = fetch_api(
	$conf->{twitter}->{consumer_key},
	$conf->{twitter}->{consumer_secret},
	$conf->{twitter}->{normal}->{access_token},
	$conf->{twitter}->{normal}->{access_token_secret},
);

print Dump($r);

# vim: noexpandtab
