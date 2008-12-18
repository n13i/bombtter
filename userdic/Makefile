# vim: noexpandtab

all: user.dic
user.dic: user.csv
	/usr/local/libexec/mecab/mecab-dict-index -d/usr/local/lib/mecab/dic/ipadic -u $@ -f utf-8 -t utf-8 $>

