package Bombtter;

# ‚à‚ë‚à‚ë
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION);
$VERSION = "0.13";
@ISA = qw(Exporter);
@EXPORT = qw(load_config set_terminal_encoding db_connect logger);

use DateTime;
use YAML;
use DBI;

sub load_config
{
	my $conffile = shift || 'bombtter.conf';
	my $conf = YAML::LoadFile($conffile) or die("$conffile:$!");
	return $conf;
}

sub set_terminal_encoding
{
	my $conf = shift || die;
	binmode STDIN, ":encoding($conf->{'terminal_encoding'})";
	binmode STDOUT, ":encoding($conf->{'terminal_encoding'})";
}

sub db_connect
{
	my $conf = shift || die;
	my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{'dbfile'}, '', '', {unicode => 1});
	return $dbh;
}

sub logger
{
	my $msg = shift || '';
	my $dt = DateTime->now(time_zone => '+0900'); # fixme
	print '[' . $dt->ymd . ' ' . $dt->hms . '] ' . $msg . "\n";
}

1;
__END__
