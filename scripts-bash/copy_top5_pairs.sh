#!/bin/bash
src="$1"
if [ -z "$src" ]; then
    echo "Usage: $0 /path/to/source_A"
    exit 1
fi

for subdir in "$src"/*/; do
    [ -d "$subdir" ] || continue
    name=$(basename "$subdir")
    mkdir -p "$name"
    # Find images, sort, take first 5, copy both image and matching .json
    find "$subdir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | sort | head -5 | while read img; do
        base="${img%.*}"
        json="${base}.json"
        if [ -f "$json" ]; then
            cp "$img" "$name/"
            cp "$json" "$name/"
        fi
    done
done
