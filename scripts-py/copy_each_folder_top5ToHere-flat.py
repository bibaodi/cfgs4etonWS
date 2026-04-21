#!/usr/bin/env python3
import os
import shutil
import sys
from pathlib import Path

# Supported image extensions (add more if needed)
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff'}

def get_image_json_pairs(folder):
    """Return list of (image_path, json_path) pairs in folder."""
    pairs = []
    for f in os.listdir(folder):
        file_path = os.path.join(folder, f)
        if not os.path.isfile(file_path):
            continue
        name, ext = os.path.splitext(f)
        if ext.lower() in IMAGE_EXTS:
            json_file = os.path.join(folder, name + '.json')
            if os.path.isfile(json_file):
                pairs.append((file_path, json_file))
    # Sort by image filename to get deterministic "top 5"
    pairs.sort(key=lambda x: os.path.basename(x[0]))
    return pairs[:5]  # top 5

def main():
    # Source directory (A) – first argument, or current directory if not given
    if len(sys.argv) > 1:
        src = Path(sys.argv[1])
    else:
        src = Path.cwd()
    
    if not src.is_dir():
        print(f"Error: '{src}' is not a valid directory.")
        sys.exit(1)

    # Destination is current working directory (B)
    dest = Path.cwd()

    # Find all immediate subdirectories inside src
    subdirs = [d for d in src.iterdir() if d.is_dir()]

    if not subdirs:
        print(f"No subfolders found in {src}")
        return

    for subdir in subdirs:
        pairs = get_image_json_pairs(subdir)
        if not pairs:
            print(f"No valid image+json pairs in {subdir.name}")
            continue

        print(f"Copying top {len(pairs)} pairs from {subdir.name}:")
        for img_path, json_path in pairs:
            img_name = os.path.basename(img_path)
            json_name = os.path.basename(json_path)
            # Prefix with subfolder name to avoid overwriting
            new_img = dest / f"{subdir.name}_{img_name}"
            new_json = dest / f"{subdir.name}_{json_name}"
            shutil.copy2(img_path, new_img)
            shutil.copy2(json_path, new_json)
            print(f"  -> {new_img.name}, {new_json.name}")

if __name__ == "__main__":
    main()
