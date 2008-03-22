package Bombtter::Analyzer;
# vim: noexpandtab

# 爆発物検出
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION);
$VERSION = "0.13";
@ISA = qw(Exporter);
@EXPORT = qw(analyze);

#use Bombtter;
use MeCab;
use Encode;

my $mecab_dic_encoding = 'euc-jp';

sub analyze
{
	my $target = shift || return undef;

#	my $seps = '。|．|\.\s|、|，|,\s|！|!|？|\?|…|･･|・|：|ｗ+|（|）|「|『|」|』|\s';
	my $seps = '。．、，！!？\?…‥・：ｗ（）「『」』\s';
	my $cadds = 'とりあえず|(?:ほんと|ホント|本当)に?|(?:マジ|まじ)で?|だったら';
	my $sadds = $cadds . '|うあー|あー|もう|あーもう|ちくしょー|思うと|つーことで|なんだ|やっぱり';
	my $eadds = $cadds . '|ごと|みんな|皆|なんて|なんか|とか|がって|いったん|一旦|本気で';

	$target =~ s/(\[.+\]|\*.+\*)$//;

	#print 'target: ' . $target . "\n";

    # 英単語前後の空白を正規化
    # ex) 誤変換する IME 爆発しろ
	my $ascii = '\x{0000}-\x{007f}';
	$target =~ s/([^$ascii])\s([$ascii]+)\s/$1$2/g;
	$target =~ s/^([^\@][$ascii]+)\s([^$ascii])/$1$2/g;

	# 適当に解析
	if($target =~ m{
		(?:
		  # ターゲット前の補足部分があれば喰っておく
		  (?:.*(?:$sadds))?
		  # ターゲット名
		  ([^(?:$seps)]{0,39}?[^(?:$seps)はがのをに])
		  # ターゲットに続く補足部分
		  (?:
		    (?:
			  # ○○、××爆発しろ
			  # ○○、爆発しろ
			  、(?:$eadds)?
			  |
			  # ○○は爆発しろ
			  # ○○は～爆発しろ (～は2文字以上)
			  は、?(?:[^(?:$seps)]+?[^(?:$seps)はがのをに])?
		    )
		  )?
		  # 補足2
		  (?:$eadds)?
		  |
		  # ターゲットが @name の場合
		  # TODO そうでない場合について
		  ^(\@\S+\s)\s*
		  (?:.*(?:$eadds))?
		)
		大?爆発しろ
		#(?:(?:!+|！+)?(?:」|』)?(.{0,40}$)|(?:。|．|\.\s)())
		(?:(?:!+|！+)?(?:」|』)?|(?:。|．|\.\s))(.{0,40}$)
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
			[てで]$|      # FIXME 文末の品詞を調べるべき
			^(?:$cadds)$
			}x)
		{
			print "  skipped (due to object): $target\n";
			return undef;
		}

		if($outro =~ m{
			^(は|な|とか|とは|っは|って|よ[^。]|では|でも|と(思|おも)(う|っ))
			}ox)
		{
			print "  skipped (due to outro): $target\n";
			return undef;
		}

		# normalize target
		$object =~ s/(
#			とか(まじ|マジ)で?$|
#			は(みんな|皆)$|
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
		my @sentence = ();
		my $mecab = new MeCab::Tagger('');
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

		# 先頭が名詞になるまで
		while($#sentence >= 0 && $sentence[0]->{feature} !~ /^名詞/)
		{
			shift(@sentence);
		}

		if($#sentence == -1)
		{
			print "  skipped (due to morphological analysis): $target\n";
			return undef;
		}

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
