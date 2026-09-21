#!/usr/bin/env bash

# Check if a file argument was provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <markdown_file>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' not found."
    exit 1
fi

# Run python script to perform regex replacements:
# 1. Block math:   \[...\]   ->  ```math \n ... \n ```
# 2. Inline math:  \(...\)   ->  `$ ... $`
python3 - "$FILE" << 'EOF'
import sys
import re

file_path = sys.argv[1]

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace block math: \[...\] to ```math ... ```
# re.DOTALL (re.S) allows matching across multiple lines
content = re.sub(
    r'\\\[\s*\n?(.*?)\n?\s*\\\]',
    r'```math\n\1\n```',
    content,
    flags=re.DOTALL
)

# Replace inline math: \(...\) to `$ ... $`
content = re.sub(
    r'\\\((.*?)\\\)',
    r'`$\1$`',
    content
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"Successfully converted math syntax in '{file_path}'.")
EOF
