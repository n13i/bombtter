package Bombtter::Fetcher;
# vim: noexpandtab

# Twitter 検索をスクレイピングする
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION);
$VERSION = "0.13";
@ISA = qw(Exporter);
@EXPORT = qw(get_uri fetch_html read_html scrape_html_regexp scrape_html);

use LWP::UserAgent;
use Encode;
use Web::Scraper;
use URI;


sub get_uri
{
	my $offset = shift || 1;

	my $offset_max = 5;

	if($offset > $offset_max)
	{
		return undef;
	}

	print "Twitter search (offset=$offset) ...\n";

	my $search_keyword = '%E7%88%86%E7%99%BA%E3%81%97%E3%82%8D';

	return 'http://twitter.1x1.jp/search/?keyword='
		   . $search_keyword
		   . '&lang=&text=1ja&offset=' . $offset . '&source=';
}

sub fetch_html
{
	my $offset = shift || 1;

	my $uri = get_uri($offset);

	if(!defined($uri))
	{
		return undef;
	}

	my $ua = LWP::UserAgent->new();
	$ua->timeout(60);
	my $res = $ua->get($uri);

	print 'Result: ' . $res->code . ' ' . $res->message . "\n";

	if(!$res->is_success || $res->code != 200)
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

sub scrape_html_regexp
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

				# @ リンクの除去
				$status =~ s/<a\shref=\"http:\/\/twitter\.1x1\.jp[^>]+>(.+?)<\/a>/$1/g;
				# <a href="~"> の除去
				$status =~ s/<a\s+(?:.+?)?href=\"([^\"]+)\"[^>]*>.+?<\/a>/$1/g;

				#print "$name $screen_name $twiturl $status_id\n";
				#print "$status\n---\n";

				# FIXME name と screen_name が Twitter API と逆
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

sub scrape_html
{
	my $html = shift || return undef;

	my $earliest_status_id = 99999999999;

	my $trimmed_text = [ 'TEXT', sub { s/^\s*(.+?)\s*$/$1/ } ];
	my $list = scraper {
		process 'table.list tbody tr',
				'updates[]' => scraper {
					process 'td:nth-child(1) a',
					'twiturl_home' => '@href';
					process 'td:nth-child(1) a img',
							'iconurl' => '@src',
							'profile' => '@alt';

					process 'td:nth-child(2)',
							'screen_name' => [ 'TEXT', sub { s/^\s*(.+?)\s+\@[^@]+$/$1/ } ];
					process 'td:nth-child(2) a',
							'name' => $trimmed_text;

					process 'td:nth-child(3)',
							'status' => $trimmed_text;

					process 'td:nth-child(4) a',
							'web' => '@href';

					process 'td:nth-child(5) a',
							'twiturl' => '@href',
							'status_id' => [ '@href', sub { s/^.+?\/statuses\/(\d+)$/$1/ } ];

					process 'td:nth-child(6)',
							'from' => 'HTML';

					process 'td:nth-child(7)',
							'timestamp' => $trimmed_text;

					result 'twiturl_home', 'iconurl', 'profile',
						   'screen_name', 'name',
						   'status',
						   'web',
						   'twiturl', 'status_id',
						   'from',
						   'timestamp';
				};

		result 'updates';
	};

	my $r_updates = $list->scrape($html);
	#use YAML;
	#print Dump($r_updates);

	if($#$r_updates == -1)	
	{
		print "empty list: maybe scraping error?\n";
		return undef;
	}

	foreach(@$r_updates)
	{
		if($_->{'status_id'} < $earliest_status_id)
		{
			$earliest_status_id = $_->{'status_id'};
		}
	}

	return {
		'earliest_status_id' => $earliest_status_id,
		'updates' => $r_updates,
	};
}

1;
__END__

