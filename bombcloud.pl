#!/usr/bin/perl -w

# 2008/03/18
# $Id: dump-wordranking.pl 40 2008-03-24 19:54:45Z naoh $

use strict;
use utf8;

use HTML::TagCloud;
use MIME::Base64;
use Digest::MD5 qw(md5_base64);
use Encode;

use lib './lib';
use Bombtter;

my $conf = load_config;
set_terminal_encoding($conf);
#binmode STDOUT, ':encoding(utf8)';

my $thresh = $ARGV[0] || 1;

my $cloud = HTML::TagCloud->new;

my $dbh = db_connect($conf);

my @posts = ();
#my $sth = $dbh->prepare('SELECT COUNT(*) as count, target FROM bombs GROUP BY target HAVING count >= ? ORDER BY count DESC');
my $sth = $dbh->prepare('SELECT COUNT(*) as count, target FROM bombs WHERE posted_at IS NOT NULL GROUP BY LOWER(target) HAVING count >= ' . $thresh . ' ORDER BY count DESC, target');
#$sth->execute($thresh);
$sth->execute();
while(my $update = $sth->fetchrow_hashref)
{
	my $count = $update->{'count'};
	my $target = $update->{'target'};

    print "$target ($count)\n";

    my $target_enc = $target;
#    $target_enc =~ s/([^0-9A-Za-z_ ])/'%'.unpack('H2',$1)/ge;
#    $target_enc =~ s/\s/+/g;
    #$target_enc = encode_base64(encode('utf8', $target));
    $target_enc = md5_base64(encode('utf8', $target));
    $target_enc =~ s/\n//g;
    $target_enc =~ tr/\+\/=/!_\-/;

	#print $count . "\t\t" . $target . "\n";
    my $filename = $target_enc . '.php';

    $cloud->add($target, 'details/' . $filename, $count);

    open(FH, '>:encoding(utf8)', 'www/bombcloud/details/' . $filename) or die;
    print FH <<"EOM";
<?php
\$title = '$target'; \$bombcount = $count;
\$list = array(
EOM

    my $sth_stats = $dbh->prepare('SELECT b.target AS target, b.posted_at AS posted_at, s.status_text AS status_text, s.permalink AS permalink, s.name AS name, s.screen_name AS screen_name FROM statuses s, bombs b WHERE s.status_id = b.status_id AND b.posted_at IS NOT NULL AND LOWER(b.target) = LOWER(?) ORDER BY s.status_id DESC');
    $sth_stats->execute($target);
    while(my $stats = $sth_stats->fetchrow_hashref)
    {
        #print FH $stats->{permalink} . "\n";
        print FH "array('permalink' => '$stats->{permalink}', 'screen_name' => '$stats->{screen_name}', 'name' => '$stats->{name}', 'status_text' => '$stats->{status_text}', 'posted_at' => '$stats->{posted_at}'),\n";
    }
    $sth_stats->finish;

    print FH <<"EOM";
);
include('../detail_template.php');
?>
EOM
    close(FH);
}
$sth->finish;

$dbh->disconnect;



open(FH, '>:encoding(utf8)', 'www/bombcloud/index.php') or die;
print FH <<EOM;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
  <meta http-equiv="content-type" content="text/html; charset=UTF-8"/>
  <meta http-equiv="content-style-type" content="text/css"/>
  <title>bombtter - bombcloud :: labs.m2hq.net</title>
  <link rel="stylesheet" type="text/css" href="http://labs.m2hq.net/css/default.css"/>
</head>

<body>

  <div id="navi">
    <ul>
      <li><a href="/">HOME</a></li>
      <li>/ <a href="/bombtter/">bombtter</a></li>
    </ul>
  </div>
 
  <div id="contents">
    <div style="float: right;">
      <img src="http://labs.m2hq.net/bombtter/img/bombtter.png" width="75" height="75" alt="bombtter"/>
    </div>
    <h1>bombcloud</h1>
    <p>
      $thresh 回以上爆発したものを表示しています。
    </p>
    <div class="entry">
EOM
print FH $cloud->html_and_css;
print FH <<EOM;
    </div>
  </div>

  <div id="footer">
    <address>
      Generated at <?=strftime('%Y/%m/%d %H:%M:%S %z', filemtime(\$_ENV['SCRIPT_FILENAME']))?>
    </address>
  </div>

  </div>

</body>

</html>
EOM

