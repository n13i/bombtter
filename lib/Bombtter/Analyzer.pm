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

my $mecab_dic_encoding = 'euc-jp';

sub analyze
{
	my $target = shift || return undef;
	my $mecab_opts = shift || '';

#	my $seps = '。|．|\.\s|、|，|,\s|！|!|？|\?|…|･･|・|：|ｗ+|（|）|「|『|」|』|\s';
	# FIXME スペースを含む英単語が分割されてしまう件
	#my $seps = '。．、，！!？\?…‥・：ｗ（）「」『』\s';
	#my $seps_woparen = '。．、，！!？\?…‥・：ｗ（）\s';
	my $seps_woparen = '。．、，！!？\?…‥・：ｗ（）\s';
	my $seps = $seps_woparen . '「」『』';

	my $cadds = 'とりあえず|(?:ほんと|ホント|本当)に?|(?:マジ|まじ)で?|だったら';
	my $sadds = $cadds . "|うあー|あー|もう|あーもう|ちくしょー|思うと|つーことで|なんだ(?:ってー)?|やっぱり|くそー|そして|言う(?:が|けど)|(?:という|てな)わけで|どういうことだ(?!か)|速やかに|あるいは|もしくは|または|[$seps]のに|つまり";
	my $eadds = $cadds . '|ごと|みんな|皆|なんて|なんか|とか|がって|いったん|一旦|本気で';

	# 末尾の *Tw* とか [mb] とか _TL_ とかを除去
	$target =~ s/(\[.+?\]|\*.+?\*|_.+?_|\sもば)$//;

	#print 'target: ' . $target . "\n";

   	# スペースと,.を除く
	my $ascii = '\x{0000}-\x{001f}\x{0021}-\x{002c}\x{002d}\x{002f}-\x{007e}';

	# 英単語前後の空白を正規化
    # ex) 誤変換する IME 爆発しろ
	# FIXME 英単語間の空白の扱い
	#$target =~ s/([^$ascii])\s([$ascii]+)\s/$1$2/g;
	#$target =~ s/^([^\@][$ascii]+)\s([^$ascii])/$1$2/g;
	$target =~ s/([^$ascii])\s([$ascii]+)/$1$2/g;
	$target =~ s/([$ascii])\s([^$ascii]+)/$1$2/g;
	$target =~ s/^(\@[$ascii]+)\s?/$1 /g;

	my $name = '\x{0000}-\x{007f}';

	#$target =~ s/^([^\@][$ascii]+)\s([$ascii])/$1_$2/g;

	# 適当に解析
	# FIXME 文頭以外の「@hoge 爆発しろ」はスペースで分割される
	if($target =~ m{
		(?:
		  # -----------------------------------------------------------------
		  # ターゲット前の補足部分があれば喰っておく
		  (?:.*(?:$sadds))?
		  # ターゲット名
		  (
		    #([^(?:$seps)]{0,39}?[^(?:$seps)はがのをに])
		    [^(?:$seps)]+?
		  |
		    #([「『][^(?:$seps_woparen)]{1,20}[」』][^(?:$seps)]{1,40}?) # $2
		    [「『][^「『」』]+[」』][^(?:$seps)]+?
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
			  は(?!じめ)、?(?:[^(?:$seps)]+?[^(?:$seps)はがのをに])?
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
		大?爆発しろ
		#(?:(?:!+|！+)?(?:」|』)?(.{0,40}$)|(?:。|．|\.\s)())
		(?:(?:!+|！+)?(?:」|』)?|(?:。|．|\.\s))(.{0,40})$ # $3
		}omsx)
	{
		my $object = $1 || $2;
		my $outro  = $3;

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
			^(?:$cadds)$
			}x)
		{
			print "  skipped (due to object): $target\n";
			return undef;
		}

		if($outro =~ m{^(
				は|な|とか|とは|っは|って|よ[^$seps]|
				で[^す]|と(思|おも)(う|っ)|と(言|いう|いえ)|
				から|(しか|然)り
			)}ox)
		{
			print "  skipped (due to outro): $target\n";
			return undef;
		}

		# normalize target
		$object =~ s/(
#			とか(まじ|マジ)で?$|
#			^とりあえず|
#			^うあー|
#			^ちくしょー|
#			ごと$|
#			なんて$|
			(拗|抉|こじ)らせて$
#			^.+だったら
			)//x;
		#$object =~ s/^(\@.+)$/$1 /g;

		# 形態素解析テスト
		# 表層形と品詞を文末の単語から順に @sentence へ
		my @sentence = ();
		my $mecab = new MeCab::Tagger($mecab_opts);
		my $node = $mecab->parseToNode(encode($mecab_dic_encoding, $object));
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
		   $sentence[0]->{surface} !~ /^(だけ|まで)$/ &&
		   $sentence[0]->{feature} !~ /並立助詞/)
		{
			# 文末の単語が助詞だった
			print "  skipped (due to MA - end with particle): $target\n";
			return undef;
		}

		# 文末の単語が名詞になるまで
		while($#sentence >= 0 && $sentence[0]->{feature} !~ /^名詞/)
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
		my @out = ();
		foreach(@sentence)
		{
			push(@out, $_->{surface});
		}

		$object = join('', reverse(@out));

		print "  got [$object]: $target\n";
		return $object;
	}
	else
	{
		print "  unmatched: $target\n";
		return undef;
	}
}

1;
__END__
