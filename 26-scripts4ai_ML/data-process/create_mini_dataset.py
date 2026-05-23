#!/usr/bin/env python3
import os
import shutil
import argparse
import random
from pathlib import Path

# Common image extensions in ML datasets
IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.bmp', '.dcm', '.tiff', '.tif'}

def sample_indices(total_count, n_samples, strategy):
    """Returns a list of selected indices based on the sampling strategy."""
    if total_count <= n_samples:
        return list(range(total_count))
        
    if strategy == 'top':
        return list(range(n_samples))
        
    elif strategy == 'bottom':
        return list(range(total_count - n_samples, total_count))
        
    elif strategy == 'random':
        # Return a sorted selection so files copy in relative order
        return sorted(random.sample(range(total_count), n_samples))
        
    elif strategy == 'even':
        # Generate exactly N indices distributed evenly across the population
        # Uses a float step to guarantee reaching the final index correctly
        if n_samples == 1:
            return [total_count // 2]
        return [int(round(i * (total_count - 1) / (n_samples - 1))) for i in range(n_samples)]
        
    else:
        raise ValueError(f"Unknown strategy: {strategy}")

def create_mini_dataset(src_dir, dst_dir, n_samples=5, strategy='even', seed=None):
    if seed is not None:
        random.seed(seed)

    src_base = Path(src_dir).resolve()
    dst_base = Path(dst_dir).resolve()
    
    print(f"Scanning source: {src_base}")
    print(f"Creating mini dataset at: {dst_base}")
    print(f"Strategy: '{strategy}' | Target samples per subfolder: {n_samples}\n")

    for root, dirs, files in os.walk(src_base):
        current_src_dir = Path(root)
        
        # Replicate subfolder structure
        rel_path = current_src_dir.relative_to(src_base)
        current_dst_dir = dst_base / rel_path
        
        # Group assets by base filename stem to preserve image/json pairings
        file_groups = {}
        for f in files:
            p = current_src_dir / f
            stem = p.stem
            ext = p.suffix.lower()
            
            if stem not in file_groups:
                file_groups[stem] = {'images': [], 'jsons': []}
                
            if ext == '.json':
                file_groups[stem]['jsons'].append(p)
            elif ext in IMAGE_EXTENSIONS:
                file_groups[stem]['images'].append(p)
                
        # We only care about stems that actually contain data
        valid_stems = [
            stem for stem, components in file_groups.items() 
            if components['images'] or components['jsons']
        ]
        
        if not valid_stems:
            continue
            
        # Ensure consistent ordering before sampling (crucial for even/top/bottom)
        valid_stems.sort()
        total_available = len(valid_stems)
        
        # Determine which items to pick
        indices = sample_indices(total_available, n_samples, strategy)
        selected_stems = [valid_stems[i] for i in indices]
        
        # Create output path and copy files
        current_dst_dir.mkdir(parents=True, exist_ok=True)
        print(f"Processing: {rel_path if rel_path != Path('.') else 'Root'} "
              f"({len(selected_stems)}/{total_available} samples selected)")
        
        for stem in selected_stems:
            components = file_groups[stem]
            for file_to_copy in components['images'] + components['jsons']:
                shutil.copy2(file_to_copy, current_dst_dir / file_to_copy.name)

    # Copy top-level readme if present
    readme_path = src_base / "readme.txt"
    if readme_path.exists():
        shutil.copy2(readme_path, dst_base / "readme.txt")
        print("\nCopied root readme.txt")

    print("\nDone! Mini dataset created successfully.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create a paired mini dataset with varied selection strategies.")
    parser.add_argument("--src", type=str, default="/mnt/datas/42workspace/34-project_ML_data_models_UltrasoundIntelligence/10-datas4ML/3-thyroid/001-thyroidTestSetV03", help="Source directory")
    parser.add_argument("--dst", type=str, default="mini-dataset", help="Destination directory")
    parser.add_argument("-n", type=int, default=5, help="Number of samples to keep per subfolder")
    parser.add_argument("--strategy", type=str, choices=['top', 'bottom', 'even', 'random'], default='even', 
                        help="Sampling strategy: top, bottom, even (default), or random")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility when using 'random' strategy")
    
    args = parser.parse_args()
    create_mini_dataset(args.src, args.dst, args.n, args.strategy, args.seed)
