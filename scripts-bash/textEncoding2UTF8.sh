#!/bin/env bash
echo "iconv -f GBK -t UTF-8 /path/to/readme.txt"


function convert_v1(){
	for enc in gbk gb2312 gb18030 big5; do
		iconv -f $enc -t UTF-8 "$1" > "${1}.utf8" 2>/dev/null && mv "${1}.utf8" "$1" && exit 0
	done
	echo "Failed to convert $1"
}

function convert_to_utf8_v2(){
	FILE="$1"
	[[ -f "$FILE" ]] || { echo "Error: File not found"; exit 1; }
	file "$FILE" | grep -q "text" || { echo "Error: Not a text file"; exit 1; }
	for enc in gbk gb2312 gb18030 big5; do
		iconv -f $enc -t UTF-8 "$FILE" > "${FILE}.utf8" 2>/dev/null && mv "${FILE}.utf8" "$FILE" && exit 0
	done
	echo "Failed to convert $FILE"
}

convert_to_utf8_v2 $@ ;
