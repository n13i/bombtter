package Bombtter::Fetcher;

# Twitter 検索をスクレイピングする
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION);
$VERSION = "0.01";
@ISA = qw(Exporter);
@EXPORT = qw(fetch_html read_html scrape_html);

use LWP::UserAgent;
use Encode;


sub fetch_html
{
	my $offset = shift || 1;

	my $offset_max = 5;

	if($offset > $offset_max)
	{
		return undef;
	}

	print "Searching Twitter search (offset=$offset) ... ";

	my $search_keyword = '%E7%88%86%E7%99%BA%E3%81%97%E3%82%8D';

	my $ua = LWP::UserAgent->new();
	my $res = $ua->get('http://twitter.1x1.jp/search/?keyword='
					   . $search_keyword
					   . '&lang=&text=1ja&offset=' . $offset . '&source=');

	print $res->code . "\n";

	if($res->code != 200)
	{
		return undef;
	}

	return decode('utf8', $res->content);
}

sub read_html
{
	my $filename = shift || return undef;

	# for debug
	open FH, $filename;
	binmode FH, ':encoding(utf8)';
	my $buf = join('', <FH>);
	close(FH);

	return $buf;
}

sub scrape_html
{
	my $buf = shift || return undef;

	if($buf =~ m{
		<table\sclass="list"[^>]*>\s<tbody>\s(.+?)</tbody>\s+</table>
		}msx)
	{
		my $table = $1;

		my $r_updates = [];
		my $earliest_status_id = 99999999999;

		foreach($table =~ m{<tr>(.+?)</tr>}gmsx)
		{
			my ($name, $screen_name, $status, $twiturl, $status_id);

			if(m{
				<td\swidth="10%">.+?</td>\s+
				<td\swidth="10%">\s+(.+?)<br\s/>\s+
				<a[^>]+?>\s+(\@.+?)\s+</a>\s+
				</td>\s+
				<td\swidth="45%"[^>]+>\s+(.+?)\s+</td>\s+
				<td\swidth="5%">.+?</td>\s+
				<td\swidth="5%">\s+<a\shref=\"([^\"]+?)\"[^>]*?>.+?</td>\s+
				}msx)
			{
				$screen_name = $1;
				$name = $2;
				$status = $3;
				$twiturl = $4;
				($status_id) = $twiturl =~ /statuses\/(\d+)/;

				$status =~ s/<a\shref=\"http:\/\/twitter\.1x1\.jp[^>]+>(.+?)<\/a>/$1/g;

				#print "$name $screen_name $twiturl $status_id\n";
				#print "$status\n---\n";

				push(@$r_updates, {
					'status_id'   => $status_id,
					'twiturl'     => $twiturl,
					'name'        => $name,
					'screen_name' => $screen_name,
					'status'      => $status,
				});

				if($status_id < $earliest_status_id)
				{
					$earliest_status_id = $status_id;
				}
			}
		}

		return {
			'earliest_status_id' => $earliest_status_id,
			'updates' => $r_updates,
		};
	}
	else
	{
		print "Scrape error: can't find table\n";
		return undef;
	}
}

1;
__END__
