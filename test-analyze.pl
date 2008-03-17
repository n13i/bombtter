#!/usr/bin/perl -w

# 2008/03/17
# $Id$

use strict;
use utf8;

use DBI;
use YAML;

use lib './lib';
use Bombtter::Analyzer;

my $conffile = 'bombtter.conf';
my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");

binmode STDIN, ":encoding($conf->{'terminal_encoding'})";
binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";

#foreach(<STDIN>) # foreach だと全体を読み込んでからになる
while(<STDIN>)
{
	chomp;

	print "--------\n";
	my $result = analyze($_);

	if(defined($result))
	{
		print 'result: ' . $result . "\n\n";
	}
}
