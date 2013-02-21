package Bombtter::Analyzer;
# vim: noexpandtab

# 爆発物検出
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
@EXPORT = qw(analyze);

use MeCab;
use Encode;

#my $mecab_dic_encoding = 'euc-jp';
my $mecab_dic_encoding = 'utf8';

sub analyze
{
	my $target = shift || return undef;
	my $mecab_opts = shift || '';

	# @name
	my $name = '\x{0000}-\x{001f}\x{0021}-\x{007e}';

	my $in_reply_to = undef;
	if($target =~ /^(\@[$name]+)/)
	{
		$in_reply_to = $1;
	}

	my $kyubotter_requested_by = undef;

	# @kyubotter 対策(1)
	# 「@someoneが世界に"○○爆発しろ"を、要求しています。」
	# ただ「爆発しろ」の場合はスルー
	if($target =~ /^告知 (.+?)が世界に(?:&quot;|")(.+?爆発しろ.*)/)
	{
		$kyubotter_requested_by = $1;
		$target = $2;
		print "  vs. \@kyubotter: replacing target with ($target), requested by ($kyubotter_requested_by)\n";
	}

#	my $seps = '。|．|\.\s|、|，|,\s|！|!|？|\?|…|･･|・|：|ｗ+|（|）|「|『|」|』|\s';
	# FIXME スペースを含む英単語が分割されてしまう件
	#my $seps = '。．、，！!？\?…‥・：ｗ（）「」『』\s';
	#my $seps_woparen = '。．、，！!？\?…‥・：ｗ（）\s';
	#my $seps_woparen = '。．、，！!？\?…‥・：ｗ（）\s';
	#my $seps_woparen = '。．、，！!？\?…‥・：ｗ\s';
	my $seps_woparen = '。．、，！!？\?…‥：ｗ\s';
	my $seps = $seps_woparen . '「」『』';
	#my $seps = $seps_woparen;

	my $cadds = 'とりあえず|取り[敢合あ]えず|(?:ほんと|ホント|本当)に?|(?:マジ(?!アカ|ック|コン)|まじ)で?|だったら|ついでに|＞＜';
	my $sadds = $cadds . "|うあー|あー|もう|あーもう|ちくしょー|思うと|つーことで|なんだ(?!かんだ|か)(?:ってー)?|やっぱり|くっ?そ(?:ー|ぅ|ぉ)?|そして|言う(?:が|けど)|(?:という|てな)わけで|どういうことだ(?!か)|速やかに|あるいは|もしくは|または|[$seps]のに|つまり|あれだ|ええい(?!ああ)|(?:何|なに)が|・{2,}|＼|ぐお{2,}|(?:まと|纏)めると|[あー]{3,}";
	my $eadds = $cadds . '|ごと|みんな|皆|なんて|なんか|とか|がって|いったん|一旦|本気で|(?:今|いま)すぐ|(?:まと|纏)めて|(?:(?:\d+|[１２３４５６７８９０一二三四五六七八九]+)?[十百千万億兆]?)+回|跡形もなく|粉々に|木っ端微塵に';

	# 末尾の *Tw* とか [mb] とか _TL_ とかを除去
	$target =~ s/(\[.+?\]|\*.+?\*|_.+?_|\sもば)$//;

	# ハッシュタグを除去
	$target =~ s/#//;

	# 半角記号をある程度処理
	$target =~ tr/｢｣/「」/;

	#print 'target: ' . $target . "\n";

   	# スペースと,.を除く
	my $ascii = '\x{0000}-\x{001f}\x{0021}-\x{002c}\x{002d}\x{002f}-\x{007e}';

	# 英単語前後の空白を正規化
    # ex) 誤変換する IME 爆発しろ
	my $target_name = '';
	if($target =~ /^(\@[$ascii]+\s*)(.+)$/)
	{
		$target_name = $1;
		$target = $2;
	}
	$target =~ s/([^$ascii])\s([$ascii]+)/$1$2/g;
	$target =~ s/([$ascii])\s([^$ascii]+)/$1$2/g;
	$target = $target_name . $target;

	# 適当に解析
	# FIXME 文頭以外の「@hoge 爆発しろ」はスペースで分割される
	if($target =~ m{
		(?:
		  # -----------------------------------------------------------------
		  # ターゲット前の補足部分があれば喰っておく
		  (?:.*(?:$sadds))*
		  # ターゲット名
		  (
		    #([^(?:$seps)]{0,39}?[^(?:$seps)はがのをに])
		    #[^(?:$seps)]+?
		    (?:[^(?:$seps)]|(?<=[$ascii])\s(?=[$ascii]))+?
		  |
			# 「〜〜」とか言う奴
			# 「〜〜」を「～～」とか言う奴
			#(?:(?:[^(?:$seps)]+?)?[「『][^「『」』]+[」』])*[^(?:$seps)]+?
			(?:(?:(?:[^(?:$seps)]|(?<=[$ascii])\s(?=[$ascii]))+?)?[「『][^「『」』]+[」』])*(?:[^(?:$seps)]|(?<=[$ascii])\s(?=[$ascii]))+?
		  |
			\@[$name]+\s?
		  ) # $1
		  # ターゲットに続く補足部分
		  (?:
		    (?:
			  # ○○、××爆発しろ
			  # ○○、爆発しろ
			  、(?:$eadds)?
			|
			  # ○○は爆発しろ
			  # ○○は～爆発しろ (～は2文字以上)
			  # FIXME 誤爆が多いので品詞チェックが必要
			  (?<!に)は(?!じめ|ず|てな)(?!.+?）)、?(?:[^(?:$seps)]+?[^(?:$seps)はがのをに])?
		    )
		  )?
		  # 補足2
		  (?:$eadds)?
		|
		  # -----------------------------------------------------------------
		  # ターゲットが @name の場合
		  # TODO そうでない場合について
		  ^(\@\S+\s)\s* # $2
		  (?:.*(?:$eadds))?
		)
		# FIXME 大爆発判定は要修正
		(?:(?<!東)大|核|(?=バス)ガス)?爆発しろ
		(?:(?:[!！おぉオォ]+)?(?:」|』)?|(?:。|．|\.\s))(.*)$ # $3
		}omsx)
	{
		my $object = $1 || $2;
		my $outro  = $3;

		if($object eq '')
		{
			print "  oops, I got empty object: $target\n";
			return undef;
		}

		print "  ($object)($outro)\n";

		# check target
		# post するだけのクオリティが得られていない場合
		if($object =~ m{
			爆発しろ|      # 無限ループって怖くね？
			とりあえず$|
			^大$|
			^もう$|
			^盛大に$|
			^は$|
			^(と|て)いうか$|
			^全力で$|
			^[＜＞]$|
			方法で$|
			#[てで]$|      # FIXME 文末の品詞を調べるべき
			[←・「＼]$|
			^[～○×]+$|
			^【急募】|    # @kyubotter 対策(2)
			^【速報】|    # @sokuhobot 対策
			^RT\s|
			^(?:$cadds)$
			}x)
		{
			print "  skipped (due to object): $target\n";
			return undef;
		}

		# TODO 品詞でチェックしたい
		if($outro =~ m{^(
				は|な(?!のよ)|と書|と言|とか|とは|っは|って|よ[^$seps]|
				で[^す]|と(思|おも)(う|っ)|と(言|いう|いえ)|
				から|(しか|然)り|タイム
			)}ox)
		{
			print "  skipped (due to outro): $target\n";
			return undef;
		}

		# normalize target
#		$object =~ s/(
##			とか(まじ|マジ)で?$|
##			^とりあえず|
##			^うあー|
##			^ちくしょー|
##			ごと$|
##			なんて$|
#			(拗|抉|こじ)らせて$
##			^.+だったら
#			)//x;
		#$object =~ s/^(\@.+)$/$1 /g;

		# 英単語間のスペースを MeCab にばらされないように
		#$object =~ s/\s/%%SPC%%/g;
		$object = &_escape_space($object);

		# 対 WAVE DASH 問題
		#$object =~ s/\x{ff5e}/\x{301c}/g;

		# 形態素解析テスト
		# 表層形と品詞を文末の単語から順に @sentence へ
		my @sentence = ();
		my $mecab = new MeCab::Tagger($mecab_opts);
		my $node = $mecab->parseToNode($object);
		$node = $node->{next};
		while($node->{next})
		{
			my $surface = decode($mecab_dic_encoding, $node->{surface});
			my $feature = decode($mecab_dic_encoding, $node->{feature});
			printf "  : %s\t%s\n", $surface, $feature; 

			unshift(@sentence, {
					surface => $surface,
					feature => $feature
			});

			$node = $node->{next};
		}

		if($sentence[0]->{feature} =~ /^助詞/ &&
		   $sentence[0]->{surface} !~ /^(だけ|まで|って)$/ &&
		   $sentence[0]->{feature} !~ /(並立|係)助詞/)
		{
			# 文末の単語が助詞だった
			print "  skipped (due to MA - end with particle): $target\n";
			return undef;
		}

		# 文末の単語が名詞または記号になるまで
		while($#sentence >= 0 && $sentence[0]->{feature} !~ /^(名詞|記号)/)
		{
			shift(@sentence);
		}

		if($#sentence == -1)
		{
			# 名詞が見つからなかった
			print "  skipped (due to MA - no noun): $target\n";
			return undef;
		}

		# 表層形のみの配列を作る
		# スカラーに戻す
		$object = '';
		foreach(reverse(@sentence))
		{
			$object .= $_->{surface};
		}

		# %%SPC%% を半角スペースに戻す
		#$object =~ s/%%SPC%%/ /g;
		$object = &_unescape_space($object);

		# 行末のスペースを取っぱらう
		$object =~ s/\s+$//;

		# 戻した結果が @hoge something なら something だけにする
		$object =~ s/^(?:\@[$name]+\s+)+(.+)$/$1/;

		# ex) @hoge のxxx爆発しろ！
		if(defined($in_reply_to) &&
		   ($sentence[$#sentence]->{feature} =~ /^助詞,(連体化|格助詞),/ ||
			$sentence[$#sentence]->{surface} eq "\x{2573}"))
		{
			$object = $in_reply_to . ' ' . $object;
		}

		# .@hoge を @hoge に
		$object =~ s/\.\@([$name]+)/\@$1/;

		# WAVE DASH を元に戻す
		#$object =~ s/\x{301c}/\x{ff5e}/g;

		# @kyubotter 対策(3)
		if($object =~ /(\@[$name]+)が世界に(?:&quot;|")$/)
		{
			$object = $1 . ' の要求により、世界';
		}
		if(defined($kyubotter_requested_by))
		{
			$object = $kyubotter_requested_by . ' の要求により、' . $object;
		}

		# 最後に長さをチェック
		if(length($object) > 80)
		{
			print "  skipped (due to length '$object'): $target\n";
			return undef;
		}


		print "  got [$object]: $target\n";
		return $object;
	}
	else
	{
		print "  unmatched: $target\n";
		return undef;
	}
}

sub _escape_space
{
	my $str = shift;
	$str =~ s/%/\\%/g;
	$str =~ s/ / % /g;
	return $str;
}

sub _unescape_space
{
	my $str = shift;
	$str =~ s/(?<!\\)%/ /g;
	$str =~ s/\\%/%/g;
	return $str;
}

1;
__END__
