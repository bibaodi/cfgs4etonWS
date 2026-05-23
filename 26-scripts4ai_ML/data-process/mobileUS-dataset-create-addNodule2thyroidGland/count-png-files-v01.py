#!/usr/bin/env python3
"""
Count PNG files in subfolders of a given directory.
Usage: python count_png.py <home_path> [--recursive]
"""

import sys
from pathlib import Path

def count_png(folder, recursive=False):
    """Return the number of PNG files in folder."""
    if recursive:
        # Recursive: all .png files under folder
        return len(list(folder.rglob("*.png")))
    else:
        # Non‑recursive: only .png files directly in folder
        return len(list(folder.glob("*.png")))

def main():
    if len(sys.argv) < 2:
        print("Usage: python count_png.py <home_path> [--recursive]")
        sys.exit(1)

    home = sys.argv[1]
    recursive = False
    if len(sys.argv) > 2 and sys.argv[2] == "--recursive":
        recursive = True

    base = Path(home)
    if not base.is_dir():
        print(f"Error: '{home}' is not a valid directory.")
        sys.exit(1)

    # Loop through each item directly under base
    for item in base.iterdir():
        if item.is_dir():
            count = count_png(item, recursive)
            print(f"{item.name}: {count}")

if __name__ == "__main__":
    main()
