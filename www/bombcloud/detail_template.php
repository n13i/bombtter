<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
  <meta http-equiv="content-type" content="text/html; charset=UTF-8"/>
  <meta http-equiv="content-style-type" content="text/css"/>
  <meta name="robots" content="noindex,nofollow,noarchive"/>
  <title>bombtter - bombcloud '<?=$title?>' :: labs.m2hq.net</title>
  <link rel="stylesheet" type="text/css" href="http://labs.m2hq.net/css/default.css"/>
</head>

<body>

  <div id="navi">
    <div id="navi-inner">
      <div id="sitelogo">
        labs.m2hq.net
      </div>
      <ul>
        <li><a href="/">HOME</a></li>
        <li>/ <a href="/bombtter/">bombtter</a></li>
        <li>/ <a href="/bombtter/bombcloud/">bombcloud</a></li>
      </ul>
    </div>
  </div>
 
  <div id="contents">
    <div style="float: right;">
      <img src="http://labs.m2hq.net/bombtter/img/bombtter.png" width="75" height="75" alt="bombtter"/>
    </div>
    <h1><?=$title?></h1>
    <p>
      <?=$bombcount?> 回爆発しています。<br />
<?php
for($i = 0; $i < 5; $i++)
{
    if($i >= count($requested_by)) { break; }
    $request = $requested_by[$i];
    $screen_name = str_replace('@', '', $request['screen_name']);
    printf('<a href="http://twitter.com/%s">@%s</a>(%d) ',
        $screen_name, $screen_name, $request['count']);
}
?>
    </p>
    <div class="entry">
      <ol class="bombcloud">
<?php
$n = $bombcount;
foreach($list as $item)
{
    $screen_name = str_replace('@', '', $item['screen_name']);
    $url_profile = 'http://twitter.com/' . $screen_name;
    $status_text = preg_replace('/@(\w+)/', '<a href="http://twitter.com/$1">@$1</a>', $item['status_text']);
    $status_text = html_entity_decode($status_text);
    $username = $item['name'];
    if($username != $screen_name)
    {
        $username = $screen_name . ' / ' . $username;
    }

    print '<li value="' . $n . '"><span class="status">' . $status_text . '</span><br />';
    print '<div style="text-align:right;font-size:90%">';
    print '<a href="' . $item['permalink'] . '">Requested</a> by <a href="' . $url_profile . '">' . $username . '</a>, bombed at ' . strftime('%Y/%m/%d %H:%M:%S %z', strtotime($item['posted_at']) + 9 * 3600);
    print '</div>';
    print '</li>';
    $n--;
}
?>
      </ol>
    </div>
  </div>

  <div id="footer">
    <address>
      Generated at <?=strftime('%Y/%m/%d %H:%M:%S %z', filemtime($_ENV['SCRIPT_FILENAME']))?>
    </address>
  </div>

</body>

</html>
