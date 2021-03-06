package Bombtter::Fetcher;

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
@EXPORT = qw(fetch_rss fetch_html read_html fetch_api fetch_im);

use LWP::UserAgent;
use Encode;
use Web::Scraper;
use URI;
use YAML;
use HTML::Entities;
use Net::Twitter::Lite::WithAPIv1_1;

my $OFFSET_MAX = 5;
my $SEARCH_KEYWORD = '爆発しろ';

sub _urlencode
{
	my $str = shift;

	$str = encode('utf8', $str);
	$str =~ s/([^?w])/'%'.unpack('H2', $1)/ego;
	$str =~ tr/ a-z/+A-Z/;
	$str = decode('utf8', $str);

	return $str;
}

sub fetch_rss
{
	my $service = shift || 'pcod';
	my $query = shift || die;
	my $filter = shift || die;

	if($service eq '1x1')
	{
		return &_fetch_rss_1x1($query, $filter);
	}
	elsif($service eq 'pcod')
	{
		return &_fetch_rss_pcod($query, $filter);
	}

	return &_fetch_rss_official($query, $filter);
}

sub _fetch_rss_1x1
{
	my $query = shift || die;
	my $filter = shift || die;

	my $uri = 'http://twitter.1x1.jp/rss/search/?keyword='
			  . &_urlencode($query)
			  . '&text=1';

	print "Twitter search RSS (1x1) ...\n";

	my $content = &_fetch_uri($uri);
	if(!defined($content))
	{
		return undef;
	}

	$content = decode('utf8', $content);

	return &_parse_rss_1x1($content, $filter);
}

sub _fetch_rss_pcod
{
	my $query = shift || die;
	my $filter = shift || die;

	my $uri = 'http://pcod.no-ip.org/yats/search?query='
			  . &_urlencode($query)
			  . '&rss&fast';

	print "Twitter search RSS (pcod) ...\n";

	my $content = &_fetch_uri($uri);
	if(!defined($content))
	{
		return undef;
	}

	$content = decode('utf8', $content);

	return &_parse_rss_pcod($content, $filter);
}

sub _fetch_rss_official
{
	my $query = shift || die;
	my $filter = shift || die;

	my $r = undef;
	my $tmp = [];

	# FIXME 3ページ固定
	for(my $i = 1; $i <= 1; $i++)
	{
		my $uri = 'http://search.twitter.com/search.atom?q='
				  . &_urlencode($query)
				  . '&page=' . $i;

		printf "Twitter search RSS (official:%d) ...\n", $i;

		my $content = &_fetch_uri($uri);
		if(!defined($content))
		{
			last;
		}

		$content = decode('utf8', $content);

		$r = &_parse_rss_official($content, $tmp, $filter);
		$tmp = $r->{statuses};
	}

	return $r;
}


sub fetch_html
{
	my $offset = shift || 1;

	if($offset > $OFFSET_MAX)
	{
		return undef;
	}

	my $uri = 'http://twitter.1x1.jp/search/?keyword='
			  . &_urlencode($SEARCH_KEYWORD)
			  . '&lang=&text=1ja&offset=' . $offset . '&source=';

	print "Twitter search HTML (offset=$offset) ...\n";

	my $content = &_fetch_uri($uri);
	if(!defined($content))
	{
		return undef;
	}

	$content = decode('utf8', $content);

	return &_scrape_html_regexp($content);
}

sub _fetch_uri
{
	my $uri = shift || return undef;

	my $ua = LWP::UserAgent->new();
	$ua->timeout(60);
	my $res = $ua->get($uri);

	print 'Result: ' . $res->code . ' ' . $res->message . "\n";

	if(!$res->is_success || $res->code != 200)
	{
		return undef;
	}

	return $res->content;
}

sub read_html
{
	my $filename = shift || return undef;

	# for debug
	open FH, $filename;
	binmode FH, ':encoding(utf8)';
	my $buf = join('', <FH>);
	close(FH);

	return &_scrape_html_regexp($buf);
}

sub _parse_rss_1x1
{
	my $buf = shift || return undef;
	my $filter = shift || return undef;

	if($buf =~ m{<channel>(.+?)</channel>}msx)
	{
		my $channel = $1;

		my $r_statuses = [];
		my $earliest_status_id = 99999999999;

		foreach($channel =~ m{<item>(.+?)</item>}gmsx)
		{
			my ($name, $screen_name, $status_text, $permalink, $status_id);

			if(m{
				<title>(\@.+?)\s+&lt;(.+?)&gt;</title>\s+
				<description>(.+?)</description>\s+
				<link>.+?\?id=(\d+)</link>\s+
				}msx)
			{
				$screen_name = $1;
				$name = $2;
				$status_text = $3;
				$status_id = $4;

				my $screen_name_noat = $screen_name;
				$screen_name_noat =~ s/^\@//;
				$permalink = 'http://twitter.com/' . $screen_name_noat . '/statuses/' . $status_id;

				$status_text = &_normalize_status_text($status_text);
				next if($status_text !~ /$filter/);

				push(@$r_statuses, {
					status_id    => $status_id,
					permalink    => $permalink,
					name         => $name,
					screen_name  => $screen_name,
					status_text  => $status_text,
					is_protected => 0,  # public rss
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
		print "RSS error: can't find channel\n";
		return undef;
	}
}

sub _parse_rss_official
{
	my $buf = shift || return undef;
	my $r_statuses = shift || [];
	my $filter = shift || return undef;

	if($buf =~ m{<feed(.+?)</feed>}msx)
	{
		my $feed = $1;

		#my $r_statuses = [];
		my $earliest_status_id = 9223372036854775807;

		foreach($feed =~ m{<entry>(.+?)</entry>}gmsx)
		{
			my ($name, $screen_name, $status_text, $permalink, $status_id, $source);

			$_ = decode_entities($_);
			#print;
# <entry>
#   <id>tag:search.twitter.com,2005:5282870124</id>
#   <published>2009-10-30T08:50:06Z</published>
#   <link type="text/html" href="http://twitter.com/yuuna/statuses/5282870124" rel="alternate"/>
#   <title>DJ&#12477;&#12523;&#12488;&#29190;&#30330;&#12375;&#12429;</title>
#   <content type="html">DJ&#12477;&#12523;&#12488;&#29190;&#30330;&#12375;&#12429;</content>
#   <updated>2009-10-30T08:50:06Z</updated>
#   <link type="image/png" href="http://a3.twimg.com/profile_images/424187279/tw_re_normal.jpg" rel="image"/>
#   <twitter:geo>
#   </twitter:geo>
#   <twitter:source>&lt;a href=&quot;http://d.hatena.ne.jp/lynmock/20071107/p2&quot; rel=&quot;nofollow&quot;&gt;P3:PeraPeraPrv&lt;/a&gt;</twitter:source>
#   <twitter:lang>ja</twitter:lang>
#   <author>
#     <name>yuuna (&#22805;&#33756;)</name>
#     <uri>http://twitter.com/yuuna</uri>
#   </author>
# </entry>

			if(m{
				<link\stype="text/html"\shref="http\://twitter\.com/[^/]+/status(?:es)?/(\d+)"[^>]*>.+?
				<content\stype="html">(.+?)</content>.+?
				<twitter\:source>(.+?)</twitter\:source>.+?
				<author>.*<name>(.+?)</name>.*
				<uri>http\://twitter\.com\/([^<]+)</uri>.*</author>
				}msx)
			{
				$status_id = $1;
				$status_text = $2;
				$source = $3;
				$name = $4;
				$screen_name = $5;

				my $screen_name_noat = $screen_name;
				$screen_name = '@' . $screen_name;
				$permalink = 'http://twitter.com/' . $screen_name_noat . '/statuses/' . $status_id;

				$status_text = &_normalize_status_text($status_text);
				$status_text =~ s/<\/?em>//g;
				next if($status_text !~ /$filter/);
				$status_text =~ s/<b>($filter)<\/b>/$1/g;

				push(@$r_statuses, {
					status_id    => $status_id,
					permalink    => $permalink,
					name         => $name,
					screen_name  => $screen_name,
					status_text  => $status_text,
					is_protected => 0,  # public RSS
					source       => $source,
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
		print "RSS error: can't find feed\n";
		return undef;
	}
}

sub _parse_rss_pcod
{
	my $buf = shift || return undef;
	my $filter = shift || return undef;

	if($buf =~ m{<feed(.+?)</feed>}msx)
	{
		my $feed = $1;

		my $r_statuses = [];
		my $earliest_status_id = 99999999999;

		foreach($feed =~ m{<entry>(.+?)</entry>}gmsx)
		{
			my ($name, $screen_name, $status_text, $permalink, $status_id);

# <entry>
#   <title>irca</title>
#   <link href="http://twitter.com/irca/status/1009393256" rel="alternate"></link>
#   <updated>2008-11-17T10:48:20Z</updated>
#   <author><name>irca</name></author>
#   <id>tag:twitter.com,2008-11-17:/irca/status/1009393256</id>
#   <summary type="html">@irca : 黒執事の展示会をなめ回すように眺めるなどする</summary>
# </entry>

			if(m{
				<link\shref="http\://twitter\.com/[^/]+/status(?:es)?/(\d+)"[^>]*></link>.+?
				<author><name>(.+?)</name></author>.+?
				<summary\stype="html">(\@.+?)\s\:\s(.+?)</summary>
				}msx)
			{
				$status_id = $1;
				$name = $2;
				$screen_name = $3;
				$status_text = $4;

				my $screen_name_noat = $screen_name;
				$screen_name_noat =~ s/^\@//;
				$permalink = 'http://twitter.com/' . $screen_name_noat . '/statuses/' . $status_id;

				$status_text = &_normalize_status_text($status_text);
				next if($status_text !~ /$filter/);

				push(@$r_statuses, {
					status_id    => $status_id,
					permalink    => $permalink,
					name         => $name,
					screen_name  => $screen_name,
					status_text  => $status_text,
					is_protected => 0,  # public RSS
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
		print "RSS error: can't find feed\n";
		return undef;
	}
}

sub _scrape_html_regexp
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
					status_id    => $status_id,
					permalink    => $permalink,
					name         => $name,
					screen_name  => $screen_name,
					status_text  => $status_text,
					is_protected => 0,  # public html
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

sub fetch_api
{
	my $consumer_key = shift || return undef;
	my $consumer_secret = shift || return undef;
	my $access_token = shift || return undef;
	my $access_token_secret = shift || return undef;

	my $r_statuses = [];
	my $earliest_status_id = 9223372036854775807;

	my $twit = Net::Twitter::Lite::WithAPIv1_1->new(
		consumer_key => $consumer_key,
		consumer_secret => $consumer_secret,
		ssl => 1,
	);
	$twit->access_token($access_token);
	$twit->access_token_secret($access_token_secret);

	my $r = undef;
	eval {
		$r = $twit->search({
			q => &_urlencode($SEARCH_KEYWORD),
			locale => 'ja',
			count => 100,
			result_type => 'recent',
		});
		if(!defined($r))
		{
			printf "can't get search results: code %d %s\n",
				$twit->http_code, $twit->http_message;
			print Dump($twit->get_error);
			return undef;
		}
		printf "got %d results\n", $#{$r->{statuses}}+1;
	};
	if($@)
	{
	    printf "can't get search results\n";
		return undef;
	}

	foreach(@{$r->{statuses}})
	{
		last if(ref($_) ne 'HASH');

		my $is_protected = 0;
		if($_->{user}->{protected})
		{
			#print $_->{user}->{screen_name} . " is protected; skip.\n";
			#next;
			$is_protected = 1;
		}

		# premature user check (2013/09/15)
		if($_->{user}->{statuses_count} < 30 ||
		   $_->{user}->{followers_count} < 20)
		{
			printf "user %s seems premature, skip.\n",
				$_->{user}->{screen_name};
			next;
		}

		if($_->{text} !~ /$SEARCH_KEYWORD/)
		{
			next;
		}

		my $status_id   = $_->{id};
		my $screen_name = '@' . $_->{user}->{screen_name};
		my $name        = $_->{user}->{name};
		my $permalink   = 'http://twitter.com/' . $_->{user}->{screen_name} . '/status/' . $status_id;
		my $status_text = $_->{text};
		my $source      = $_->{source};

		$status_text = &_normalize_status_text($status_text);

		push(@$r_statuses, {
			status_id    => $status_id,
			permalink    => $permalink,
			name         => $name,
			screen_name  => $screen_name,
			status_text  => $status_text,
			is_protected => $is_protected,
			source       => $source,
		});
	}

	foreach(@$r_statuses)
	{
		if($_->{status_id} < $earliest_status_id)
		{
			$earliest_status_id = $_->{status_id};
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
	$s =~ s/<a\s+(?:.+?)?href=\"[^\"]+\"[^>]*>(.+?)<\/a>/$1/g;

	return $s;
}

1;
__END__

# vim: noexpandtab
