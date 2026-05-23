#!/usr/bin/env python3
"""
Replace label "Thyroid" with "ThyGland" in all JSON files.
Usage: python rename_label.py [directory] [--backup]
"""

import os
import json
import argparse
import shutil
from pathlib import Path

def process_json_file(filepath, backup=False):
    """Read JSON file, replace label, write back."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"❌ Error reading {filepath}: {e}")
        return False

    modified = False
    # Check if "shapes" list exists and iterate
    if 'shapes' in data and isinstance(data['shapes'], list):
        for shape in data['shapes']:
            if shape.get('label') == 'Thyroid':
                shape['label'] = 'ThyGland'
                modified = True

    if not modified:
        return False

    # Create backup if requested
    if backup:
        backup_path = filepath.with_suffix(filepath.suffix + '.bak')
        shutil.copy2(filepath, backup_path)
        print(f"📁 Backup created: {backup_path}")

    # Write back the modified data
    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"✅ Updated: {filepath}")
        return True
    except OSError as e:
        print(f"❌ Error writing {filepath}: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Replace "Thyroid" label with "ThyGland" in JSON files.'
    )
    parser.add_argument(
        'directory', nargs='?', default='.',
        help='Directory containing JSON files (default: current directory)'
    )
    parser.add_argument(
        '--backup', action='store_true',
        help='Create .bak backup files before modifying'
    )
    parser.add_argument(
        '--pattern', default='*.json',
        help='Glob pattern for JSON files (default: *.json)'
    )
    args = parser.parse_args()

    root_dir = Path(args.directory)
    if not root_dir.is_dir():
        print(f"❌ Error: '{root_dir}' is not a valid directory.")
        return

    json_files = list(root_dir.glob(f"**/{args.pattern}"))
    if not json_files:
        print(f"No files matching '{args.pattern}' found in '{root_dir}'.")
        return

    print(f"Found {len(json_files)} JSON file(s). Processing...")
    updated = 0
    for filepath in json_files:
        if process_json_file(filepath, args.backup):
            updated += 1

    print(f"\nDone. Updated {updated} file(s).")

if __name__ == '__main__':
    main()
