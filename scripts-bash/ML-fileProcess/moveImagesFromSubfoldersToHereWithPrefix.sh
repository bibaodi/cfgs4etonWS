#!/bin/env bash
# ============================================
# INPUT BEFORE SCRIPT:
# /parent/
# ├── sub1/
# │   ├── photo.png
# │   └── doc.txt
# └── sub2/
#     └── pic.jpg
# 
# OUTPUT AFTER SCRIPT:
# /parent/
# ├── sub1/
# │   └── doc.txt
# ├── sub2/
# │   (empty)
# ├── sub1photo.png
# └── sub2pic.jpg
# ============================================

_usage="This script moves image files from immediate subdirectories into the parent directory, \
	renaming them by prefixing the subdirectory name."

echo ${_usage}
read -p "[y/n]run?" ans

test 'y' != ${ans} && exit 0

_wkpl=${1:-nothing}

test "nothing" == ${_wkpl} && exit 0
test ! -d ${_wkpl} && exit 0

cd ${_wkpl}

echo "working..."
for d in */;do 
	# Skip if not a directory (safety)
	[[ -d "$d" ]] || continue
	
	for f in "$d"*; do 
		#[[ -f "$f" && "$f" =~ \.(png|jpg|jpeg|gif|bmp|tiff)$ ]]&&mv "$f" "./${d%/}$(basename "$f")";
		if [[ "$f" =~ \.(png|jpg|jpeg|gif|bmp|tiff)$ ]]; then
			target="./${d%/}$(basename "$f")"
			# Optional: check for overwrite
			if [[ -e "$target" ]]; then
				echo "Warning: $target already exists, skipping $f"
			else
				mv "$f" "$target"
			fi
		fi
	done;
done
