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
	my $adds = '(?:(?:ほんと|ホント|本当)に?|(?:マジ|まじ)で?)';

	$target =~ s/(\[.+\]|\*.+\*)$//;

	print 'target: ' . $target . "\n";

	# 適当に解析
	if($target =~ m{
		(?:
		  # ターゲット名
		  (?:$adds)?
		  ([^(?:$seps)]{0,39}?[^(?:$seps)はがのをに])
		  # ターゲットに続く補足部分
		  (?:
		    (?:
			  # ○○、××爆発しろ
			  # ○○、爆発しろ
			  、(?:$adds)?
			  |
			  # ○○は爆発しろ
			  # ○○は～爆発しろ (～は2文字以上)
			  は(?:[^(?:$seps)]+?[^(?:$seps)はがのをに])?
		    )
		  )?
		  |
		  # ターゲットが @name の場合
		  # TODO そうでない場合について
		  ^(\@\S+\s)\s*
		)
		大?爆発しろ
		(?:!+|！+|。|．|\.\s)?(.{0,40}$)
		}omsx)
	{
		my $object = $1 || $2;
		my $outro  = $3;

		print "[object:$object][outro:$outro]\n";

		# check target
		if($object =~ m{
			爆発しろ|      # 無限ループって怖くね？
			とりあえず$|
			^大$|
			^もう$|
			^盛大に$|
			^は$|
			^(と|て)いうか$|
			^全力で$
			}x ||
		   $outro =~ m{
			^(は|な|とか|っは|って|よ[^。]|でも|と思う|とおもう)
			}x)
		{
			print "> skipped.\n";
			return undef;
		}

		# normalize target
		$object =~ s/(
			とか(まじ|マジ)$|
			は(みんな|皆)$|
			^とりあえず|
			^うあー|
			^ちくしょー
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
