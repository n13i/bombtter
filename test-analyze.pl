#!/usr/bin/perl

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

my $verbose = 0;
if(($ARGV[0] || '') eq '-v')
{
    $verbose = 1;
    select(STDERR); $| = 1;
    select(STDOUT);
}

my $lines = 0;
#my $prompt = 'input> ';
#print STDERR $prompt;
#foreach(<STDIN>) # foreach だと全体を読み込んでからになる
while(<STDIN>)
{
	chomp;
    my $target = $_;

	print 'target: ' . $target . "\n";

	my $result = analyze($target, $mecab_opts);

	if(defined($result))
	{
		print 'result: ' . $result . "\n";
	}
	else
	{
		print 'failed: ' . $target . "\n";
	}
	print "--------\n";

    if($verbose)
    {
        printf STDERR "done %d status(es)\r", $lines;
    }
    $lines++;
	#print STDERR $prompt;
}
printf STDERR "\n" if($verbose);

