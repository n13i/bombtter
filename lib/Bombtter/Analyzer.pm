package Bombtter::Analyzer;

# 爆発物検出
# 2008/03/17 naoh
# $Id$

use warnings;
use strict;
use utf8;

use Exporter;

use vars qw(@ISA @EXPORT $VERSION);
$VERSION = "0.12";
@ISA = qw(Exporter);
@EXPORT = qw(analyze);


sub analyze
{
	my $target = shift || return undef;

	my $seps = '。|．|\.\s|、|，|,\s|！|!|？|\?|…|･･|・|：|ｗ+|（|）|「|『|」|』|\s';

	$target =~ s/(\[.+\]|\*.+\*)$//;

	print 'target: ' . $target . "\n";

	if($target =~ m{
		^(.*(?:$seps)+|)               # skip preface
		([^(?:$seps)]{1,40}?|^\@\S+)   # bombing target object
		(?:、|は|\s+)?
		大?爆発しろ
		(?:!+|！+|。|．|\.\s)?(.{0,40}$)
		}msx)
	{
		my $intro  = $1;
		my $object = $2;
		my $outro  = $3;

		print "[intro:$intro][object:$object][outro:$outro]\n";

		# check target
		if($object =~ m{
			爆発しろ|      # 無限ループって怖くね？
			とりあえず$|
			^大$|
			^もう$|
			^盛大に$|
			^は$|
			^(と|て)いうか$
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
			^うあー
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
