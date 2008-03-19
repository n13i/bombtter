package Bombtter::Analyzer;

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

sub analyze
{
	my $target = shift || return undef;

#	my $seps = '。|．|\.\s|、|，|,\s|！|!|？|\?|…|･･|・|：|ｗ+|（|）|「|『|」|』|\s';
	my $seps = '。．、，！!？\?…‥・：ｗ（）「『」』\s';
	my $cadds = 'とりあえず|(?:ほんと|ホント|本当)に?|(?:マジ|まじ)で?|だったら';
	my $sadds = $cadds . '|うあー|あー|もう|あーもう|ちくしょー';
	my $eadds = $cadds . '|ごと|みんな|皆|なんて|なんか';

	$target =~ s/(\[.+\]|\*.+\*)$//;

	print 'target: ' . $target . "\n";

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
			  は(?:[^(?:$seps)]+?[^(?:$seps)はがのをに])?
		    )
		  )?
		  # 補足2
		  (?:$eadds)?
		  |
		  # ターゲットが @name の場合
		  # TODO そうでない場合について
		  ^(\@\S+\s)\s*
		)
		大?爆発しろ
		(?:(?:!+|！+)?(.{0,40}$)|(?:。|．|\.\s)())
		}omsx)
	{
		my $object = $1 || $2;
		my $outro  = $3;

		print "[object:$object][outro:$outro]\n";

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
			^(?:$cadds)$
			}x ||
		   $outro =~ m{
			^(は|な|とか|っは|って|よ[^。]|では|でも|と思う|とおもう)
			}ox)
		{
			print "> skipped.\n";
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

		print "> $object\n";
		return $object;
	}
	else
	{
		print '> unmatched.' . "\n";
		return undef;
	}
}

1;
__END__
