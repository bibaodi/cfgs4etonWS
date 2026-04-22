_wkpl=${1:-nothing}

test "nothing" == ${_wkpl} && exit 0
test ! -d ${_wkpl} && exit 0

cd ${_wkpl}

for d in */;do for f in "$d"*;do [[ -f "$f" && "$f" =~ \.(png|jpg|jpeg|gif|bmp|tiff)$ ]]&&mv "$f" "./${d%/}$(basename "$f")";done;done
