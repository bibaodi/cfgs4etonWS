#!/usr/bin/env python3
"""
Clear 'imageData' fields from LabelMe-style JSON files.

Usage:
    python clear_imagedata.py /path/to/json/folder
    python clear_imagedata.py /path/to/json/folder -r
    python clear_imagedata.py /path/to/json/folder --dry-run
    python clear_imagedata.py /path/to/json/folder --output /path/to/output
"""

import json
import os
import sys
import argparse
import pathlib  # Changed from glob to pathlib for better recursive support


def find_json_files(directory, pattern="*.json", recursive=False):
    """Find all JSON files matching the pattern in the directory."""
    base_path = pathlib.Path(directory)
    
    if recursive:
        # rglob automatically searches all subfolders
        files = [str(p) for p in base_path.rglob(pattern)]
    else:
        # glob only searches the current folder
        files = [str(p) for p in base_path.glob(pattern)]
        
    return sorted(files)


def format_size(size_bytes):
    """Format a byte count into human-readable string."""
    if size_bytes < 0:
        return "0 B"
    size = float(size_bytes)
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def get_file_size(filepath):
    """Get human-readable file size from a file path."""
    return format_size(os.path.getsize(filepath))


def estimate_saving(filepath):
    """Estimate how much space will be saved by clearing imageData."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)

        original_size = os.path.getsize(filepath)

        # Calculate imageData size
        image_data_size = 0
        if 'imageData' in data and data['imageData']:
            image_data_size = len(data['imageData'].encode('utf-8'))

        for shape in data.get('shapes', []):
            if 'imageData' in shape and shape['imageData']:
                image_data_size += len(shape['imageData'].encode('utf-8'))

        has_image_data = image_data_size > 0
        return has_image_data, original_size, image_data_size

    except (json.JSONDecodeError, UnicodeDecodeError):
        return False, 0, 0


def clear_image_data(filepath, output_path=None):
    """
    Parse a JSON file, set 'imageData' to null, and save.
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Clear imageData at root level (set to null)
    if 'imageData' in data:
        data['imageData'] = None

    # Clear imageData in shapes (if any)
    if 'shapes' in data:
        for shape in data['shapes']:
            if 'imageData' in shape:
                shape['imageData'] = None

    if output_path is None:
        output_path = filepath

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def confirm_action(files, directory):
    """Display file list and ask user for confirmation."""
    print(f"\n{'='*60}")
    print(f"  Folder     : {directory}")
    print(f"  Files found: {len(files)}")
    print(f"{'='*60}")

    total_original = 0
    total_saving = 0
    has_data_count = 0

    print(f"\n{'#':<5} {'File':<45} {'Size':<10} {'ImageData':<10} {'Saving':<10}")
    print(f"{'-'*5} {'-'*45} {'-'*10} {'-'*10} {'-'*10}")

    for i, filepath in enumerate(files, 1):
        # Show relative path so you can see which subfolder it came from
        filename = os.path.relpath(filepath, directory)
        has_data, original_size, data_size = estimate_saving(filepath)

        total_original += original_size
        total_saving += data_size
        if has_data:
            has_data_count += 1

        status = "Yes" if has_data else "No"
        saving = format_size(data_size) if has_data else "-"

        print(f"{i:<5} {filename:<45} {get_file_size(filepath):<10} {status:<10} {saving:<10}")

    print(f"{'-'*80}")
    print(f"  Total files      : {len(files)}")
    print(f"  With imageData   : {has_data_count}")
    print(f"  Without imageData: {len(files) - has_data_count}")
    print(f"  Estimated saving : {format_size(total_saving)}")
    print(f"{'='*60}")

    if has_data_count == 0:
        print("\n⚠  No files contain imageData. Nothing to do.")
        return False

    # Confirmation prompt
    while True:
        answer = input(f"\n▶ Proceed to clear imageData in {has_data_count} file(s)? [y/N]: ").strip().lower()
        if answer in ('y', 'yes'):
            return True
        elif answer in ('n', 'no', ''):
            return False
        else:
            print("  Please enter 'y' or 'n'.")


def main():
    parser = argparse.ArgumentParser(
        description="Clear 'imageData' fields from JSON files in a folder.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/json/folder
  %(prog)s /path/to/json/folder -r             (search subfolders)
  %(prog)s /path/to/json/folder --dry-run
  %(prog)s /path/to/json/folder --output /path/to/output
        """
    )

    parser.add_argument(
        'folder',
        help="Path to the folder containing JSON files"
    )
    parser.add_argument(
        '--recursive', '-r',
        action='store_true',
        help="Search for JSON files recursively in subfolders."
    )
    parser.add_argument(
        '--pattern', '-p',
        default="*.json",
        help="Glob pattern to match JSON files (default: *.json)"
    )
    parser.add_argument(
        '--output', '-o',
        default=None,
        help="Output folder. If not set, files are modified in-place."
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Only show what would be done, don't modify any files."
    )

    args = parser.parse_args()

    # ──────────────────────────────────────────────
    # 1. Check if folder exists
    # ──────────────────────────────────────────────
    folder = os.path.abspath(args.folder)

    if not os.path.exists(folder):
        print(f"✗ Error: Path does not exist: {folder}")
        sys.exit(1)

    if not os.path.isdir(folder):
        print(f"✗ Error: Path is not a folder: {folder}")
        sys.exit(1)

    # ──────────────────────────────────────────────
    # 2. Find JSON files
    # ──────────────────────────────────────────────
    files = find_json_files(folder, args.pattern, args.recursive)

    if not files:
        print(f"✗ No files matching '{args.pattern}' found in: {folder}")
        if not args.recursive:
            print("  Hint: Use the -r flag to search in subfolders.")
        sys.exit(1)

    # ──────────────────────────────────────────────
    # 3. Check output folder (if specified)
    # ──────────────────────────────────────────────
    if args.output:
        output_folder = os.path.abspath(args.output)
        if not os.path.exists(output_folder):
            print(f"⚠  Output folder does not exist: {output_folder}")
            while True:
                answer = input(f"▶ Create output folder? [y/N]: ").strip().lower()
                if answer in ('y', 'yes'):
                    os.makedirs(output_folder, exist_ok=True)
                    print(f"✓ Created: {output_folder}")
                    break
                elif answer in ('n', 'no', ''):
                    print("✗ Cancelled.")
                    sys.exit(0)
                else:
                    print("  Please enter 'y' or 'n'.")

    # ──────────────────────────────────────────────
    # 4. Show summary and ask confirmation
    # ──────────────────────────────────────────────
    if not confirm_action(files, folder):
        print("\n✗ Cancelled by user.")
        sys.exit(0)

    # ──────────────────────────────────────────────
    # 5. Dry run
    # ──────────────────────────────────────────────
    if args.dry_run:
        print("\n⚠  Dry run mode — no files were modified.")
        sys.exit(0)

    # ──────────────────────────────────────────────
    # 6. Process files
    # ──────────────────────────────────────────────
    success_count = 0
    error_count = 0

    print("\nProcessing...")
    for filepath in files:
        try:
            out = None
            if args.output:
                # Preserve subfolder structure in output directory
                rel_path = os.path.relpath(filepath, folder)
                out = os.path.join(os.path.abspath(args.output), rel_path)
                
                # Create sub-directories in output if they don't exist
                os.makedirs(os.path.dirname(out), exist_ok=True)

            clear_image_data(filepath, output_path=out)
            success_count += 1
            print(f"  ✓ {os.path.relpath(filepath, folder)}")
        except Exception as e:
            error_count += 1
            print(f"  ✗ {os.path.relpath(filepath, folder)}: {e}")

    # ──────────────────────────────────────────────
    # 7. Summary
    # ──────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  Done!")
    print(f"  Success : {success_count}")
    print(f"  Errors  : {error_count}")
    if args.output:
        print(f"  Output  : {os.path.abspath(args.output)}")
    else:
        print(f"  Mode    : In-place overwrite")
    print(f"{'='*60}")


if __name__ == '__main__':
    main()

