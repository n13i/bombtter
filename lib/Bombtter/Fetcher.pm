package Bombtter::Fetcher;
# vim: noexpandtab

# Twitter 検索をスクレイピングする
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
@EXPORT = qw(get_uri fetch_html read_html scrape_html_regexp scrape_html fetch_followers);

use LWP::UserAgent;
use Encode;
use Web::Scraper;
use URI;
use Net::Twitter;


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

		my $r_statuses = [];
		my $earliest_status_id = 99999999999;

		foreach($table =~ m{<tr>(.+?)</tr>}gmsx)
		{
			my ($name, $screen_name, $status_text, $permalink, $status_id);

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
				$name = $1;
				$screen_name = $2;
				$status_text = $3;
				$permalink = $4;
				($status_id) = $permalink =~ /statuses\/(\d+)/;

				$status_text = &_normalize_status_text($status_text);

				#print "$name $screen_name $twiturl $status_id\n";
				#print "$status\n---\n";

				push(@$r_statuses, {
					'status_id'   => $status_id,
					'permalink'   => $permalink,
					'name'        => $name,
					'screen_name' => $screen_name,
					'status_text' => $status_text,
				});

				if($status_id < $earliest_status_id)
				{
					$earliest_status_id = $status_id;
				}
			}
		}

		return {
			'earliest_status_id' => $earliest_status_id,
			'statuses' => $r_statuses,
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
				'statuses[]' => scraper {
					process 'td:nth-child(1) a',
					'twiturl_home' => '@href';
					process 'td:nth-child(1) a img',
							'profile_image_url' => '@src',
							'description' => '@alt';

					process 'td:nth-child(2)',
							'name' => [ 'TEXT', sub { s/^\s*(.+?)\s+\@[^@]+$/$1/ } ];
					process 'td:nth-child(2) a',
							'screen_name' => $trimmed_text;

					# FIXME リンク除去等の処理が必要
					process 'td:nth-child(3)',
							'status_text' => $trimmed_text;

					process 'td:nth-child(4) a',
							'url' => '@href';

					process 'td:nth-child(5) a',
							'twiturl' => '@href',
							'status_id' => [ '@href', sub { s/^.+?\/statuses\/(\d+)$/$1/ } ];

					process 'td:nth-child(6)',
							'from' => 'HTML';

					process 'td:nth-child(7)',
							'timestamp' => $trimmed_text;

					result 'twiturl_home', 'profile_image_url', 'description',
						   'name', 'screen_name',
						   'status_text',
						   'url',
						   'permalink', 'status_id',
						   'from',
						   'timestamp';
				};

		result 'statuses';
	};

	my $r_statuses = $list->scrape($html);
	#use YAML;
	#print Dump($r_statuses);

	if($#$r_statuses == -1)	
	{
		print "empty list: maybe scraping error?\n";
		return undef;
	}

	foreach(@$r_statuses)
	{
		if($_->{'status_id'} < $earliest_status_id)
		{
			$earliest_status_id = $_->{'status_id'};
		}
	}

	return {
		'earliest_status_id' => $earliest_status_id,
		'statuses' => $r_statuses,
	};
}

sub fetch_followers
{
	my $username = shift || return undef;
	my $password = shift || return undef;

	my $target_str = '爆発しろ';

	my $twit = Net::Twitter->new(username => $username, password => $password);
	my $followers = $twit->followers();
	#use YAML;
	#my $followers = YAML::LoadFile('test/followers.yaml');
	#utf8::decode($followers);
	if(!defined($followers))
	{
		print "can't get followers\n";
		return undef;
	}

	my $r_statuses = [];
	my $earliest_status_id = 99999999999;

	foreach(@$followers)
	{
		if($_->{protected})
		{
			print $_->{screen_name} . " is protected; skip.\n";
			next;
		}

		if($_->{status}->{text} !~ /$target_str/)
		{
			next;
		}

		my $status_id   = $_->{status}->{id};
		my $screen_name = '@' . $_->{screen_name};
		my $name        = $_->{name};
		my $permalink   = 'http://twitter.com/' . $_->{screen_name} . '/statuses/' . $status_id;
		my $status_text = $_->{status}->{text};

		#$status_text = decode('utf8', $status_text);
		#$status_text = Dump($status_text);
		#use JSON::Any;
		#$status_text = JSON::Any->decode($status_text);
		#$status_text = &_normalize_status_text($status_text);

		#print $status_text . "\n";

		push(@$r_statuses, {
			'status_id'   => $status_id,
			'permalink'   => $permalink,
			'name'        => $name,
			'screen_name' => $screen_name,
			'status_text' => $status_text,
		});

		if($_->{status}->{id} < $earliest_status_id)
		{
			$earliest_status_id = $_->{status}->{id};
		}
	}

	return {
		'earliest_status_id' => $earliest_status_id,
		'statuses' => $r_statuses,
	};
}

sub _normalize_status_text
{
	my $s = shift || '';

	# @ リンクの除去
	$s =~ s/<a\shref=\"http:\/\/twitter\.1x1\.jp[^>]+>(.+?)<\/a>/$1/g;

	# <a href="~"> の除去
	$s =~ s/<a\s+(?:.+?)?href=\"([^\"]+)\"[^>]*>.+?<\/a>/$1/g;

	return $s;
}

1;
__END__

