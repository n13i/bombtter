#!/usr/bin/perl -w

# 2008/03/17
# $Id$

use strict;
use utf8;

use DBI;

use lib './lib';
use Bombtter;
use Bombtter::Analyzer;

my $conf = load_config;
set_terminal_encoding($conf);

my $mecab_opts = '';
if(defined($conf->{'mecab_userdic'}))
{
	$mecab_opts .= '--userdic=' . $conf->{'mecab_userdic'};
}

#my $prompt = 'input> ';
#print STDERR $prompt;
#foreach(<STDIN>) # foreach だと全体を読み込んでからになる
while(<STDIN>)
{
	chomp;

	print 'target: ' . $_ . "\n";

	my $result = analyze($_, $mecab_opts);

	if(defined($result))
	{
		print 'result: ' . $result . "\n";
	}
	else
	{
		print "result:\n";
	}
	print "--------\n";

	#print STDERR $prompt;
}
