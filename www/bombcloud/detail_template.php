<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<?php
define('TWEETS_PER_PAGE', 20);
?>
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
  <meta http-equiv="content-type" content="text/html; charset=UTF-8"/>
  <meta http-equiv="content-style-type" content="text/css"/>
  <meta name="robots" content="noindex,nofollow,noarchive"/>
  <title>bombtter - bombcloud '<?php echo $title; ?>' :: labs.m2hq.net</title>
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
    <div id="bomb">
      <div id="bomb_count"><?php echo $bombcount; ?></div>
    </div>
    <h1><?php echo $title; ?></h1>
    <p>
      <?php echo $bombcount; ?> 回爆発しています。<br />
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
    <div class="entry autopagerize_page_element">
      <ol class="bombcloud">
<?php
$page = $_GET['page'];
if($page <= 0) { $page = 1; }

$page_last = ceil($bombcount / TWEETS_PER_PAGE);

$start = ($page-1)*TWEETS_PER_PAGE;
for($i = 0; $i < TWEETS_PER_PAGE; $i++)
{
    if($start + $i >= $bombcount)
    {
        break;
    }

    $item = $list[$start + $i];
    $n = $bombcount - $start - $i;

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
}
?>
      </ol>
    </div>
    <div class="pagenav">
<?php
if($page > 1)
{
?>
      <a rel="prev" href="?page=<?php echo ($page-1); ?>">Prev</a>
<?php
}
else
{
?>
      <span>Prev</span>
<?php
}
?>
      <?php echo $page; ?> / <?php echo $page_last; ?>
<?php
if($page < $page_last)
{
?>
      <a rel="next" href="?page=<?php echo ($page+1); ?>">Next</a>
<?php
}
else
{
?>
      <span>Next</span>
<?php
}
?>
    </div>
  </div>

  <div id="footer">
    <address>
      Generated at <?php echo strftime('%Y/%m/%d %H:%M:%S %z', filemtime($_ENV['SCRIPT_FILENAME'])); ?>
    </address>
  </div>

</body>

</html>
