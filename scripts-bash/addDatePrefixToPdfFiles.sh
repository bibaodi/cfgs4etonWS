#!/bin/bash
# add_date_prefix.sh – Prefix PDF files with their modification date (yymmdd)
# Usage: ./add_date_prefix.sh [directory]

set -euo pipefail

target_dir="${1:-.}"
cd "$target_dir" || { echo "Error: Cannot enter directory '$target_dir'"; exit 1; }

shopt -s nocaseglob
for file in *.pdf; do
    # Skip if no PDF files are present
    [ -e "$file" ] || continue

    # Skip files that already have a yymmdd- prefix
    if [[ "$file" =~ ^[0-9]{6}-.*\.pdf$ ]]; then
        echo "Skipping (already prefixed): $file"
        continue
    fi

    # Get file's modification date in yymmdd format (e.g., 260615)
    mod_date=$(date -r "$file" +%y%m%d 2>/dev/null) || {
        echo "Warning: Could not read modification date of '$file' – skipping"
        continue
    }
    birth_date=$(date -d "@$(stat -c %W "${file}" )" +%y%m%d)
    #echo "birth=[${birth_date}]"

    new_name="${mod_date}-${file}"

    # Avoid overwriting existing files
    if [ -e "$new_name" ]; then
        echo "Warning: '$new_name' already exists – skipping '$file'"
        continue
    fi

    mv -- "$file" "$new_name"
    echo "Renamed: '$file' -> '$new_name'"
done
