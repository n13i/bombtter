package Bombtter;

# もろもろ
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION $revision);
$VERSION = '0.20';
$revision = '$Rev$';
@ISA = qw(Exporter);
@EXPORT = qw(load_config set_terminal_encoding db_connect logger);

use DateTime;
use YAML;
use DBI;

sub load_config
{
	my $conffile = shift || 'conf/bombtter.conf';
	my $conf = YAML::LoadFile($conffile) or return undef;
	return $conf;
}

sub set_terminal_encoding
{
	my $conf = shift || return;
	binmode STDIN, ":encoding($conf->{charset})";
	binmode STDOUT, ":encoding($conf->{charset})";
	binmode STDERR, ":encoding($conf->{charset})";
}

sub db_connect
{
	my $conf = shift || return undef;
	my $dbh = DBI->connect('dbi:SQLite:dbname=' . $conf->{db}->{main}, '', '', {unicode => 1});
	return $dbh;
}

sub logger
{
	my $domain = shift || '';
	my $msg = shift || '';
	my $dt = DateTime->now(time_zone => '+0900'); # fixme
	print '[' . $dt->ymd . ' ' . $dt->hms . '] ' . $domain . ': ' . $msg . "\n";
}

1;
__END__
