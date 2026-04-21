#!/usr/bin/env python3
import os
import shutil
import sys
from pathlib import Path

IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff'}

def get_top5_pairs(folder):
    pairs = []
    for f in os.listdir(folder):
        path = os.path.join(folder, f)
        if not os.path.isfile(path):
            continue
        name, ext = os.path.splitext(f)
        if ext.lower() in IMAGE_EXTS:
            json_path = os.path.join(folder, name + '.json')
            if os.path.isfile(json_path):
                pairs.append((path, json_path))
    pairs.sort(key=lambda x: os.path.basename(x[0]))  # sort by image name
    return pairs[:5]  # top 5

def main():
    if len(sys.argv) != 2:
        print("Usage: python copy_top5_pairs.py /path/to/source_A")
        sys.exit(1)
    src = Path(sys.argv[1])
    dest = Path.cwd()  # B is current directory

    if not src.is_dir():
        print(f"Error: {src} is not a directory")
        sys.exit(1)

    for subdir in src.iterdir():
        if not subdir.is_dir():
            continue
        pairs = get_top5_pairs(subdir)
        if not pairs:
            print(f"No pairs found in {subdir.name}")
            continue

        # Create same subfolder inside destination
        dest_sub = dest / subdir.name
        dest_sub.mkdir(exist_ok=True)

        print(f"Copying {len(pairs)} pairs from {subdir.name} -> {dest_sub}")
        for img, jsonf in pairs:
            shutil.copy2(img, dest_sub / os.path.basename(img))
            shutil.copy2(jsonf, dest_sub / os.path.basename(jsonf))

if __name__ == "__main__":
    main()
