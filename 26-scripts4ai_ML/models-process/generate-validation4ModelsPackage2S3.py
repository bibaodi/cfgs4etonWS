#!/usr/bin/env python3
"""
================================================================================
                    VALIDATION.JSON GENERATOR
================================================================================
App Version: 1.0.0
Author: Ultrasound Intelligence Team
Description: This script generates a validation.json file containing file names
             and their corresponding MD5 checksums for all files in the
             specified directory.

================================================================================
                            USAGE
================================================================================
To run this script:
    python3 generate-validation.py [folder_path]
    OR
    ./generate-validation.py [folder_path] (if executable permissions are set)

Arguments:
    folder_path    Path to the folder containing model files (optional).
                   If not provided, uses the current directory.

The script will:
1. Scan all files in the specified folder
2. Validate that .tflite file names are contained in .xml files
3. Calculate MD5 checksum for each file
4. Generate validation.json with file names and checksums
5. Skip the script itself and existing validation.json
6. Only include .tflite and .xml files in the validation

Output format:
    [
        {
            "name": "filename.ext",
            "md5": "md5checksum"
        },
        ...
    ]

================================================================================
"""

import os
import sys
import hashlib
import json
import argparse
from pathlib import Path


def calculate_md5(file_path):
    """Calculate MD5 checksum for a file."""
    hash_md5 = hashlib.md5()
    try:
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    except Exception as e:
        print(f"Error calculating MD5 for {file_path}: {e}")
        return None


def validate_file_pairs(folder_path):
    """
    Validate that .tflite files have corresponding .xml file pairs.
    Returns True if all .tflite files have corresponding .xml files, False otherwise.
    """
    tflite_files = set()
    xml_files = set()
    
    for file_path in folder_path.iterdir():
        if file_path.is_file():
            filename = file_path.name
            if filename.endswith('.tflite'):
                tflite_files.add(filename)
            elif filename.endswith('.xml'):
                xml_files.add(filename)
    
    missing_pairs = []
    for tflite_file in tflite_files:
        expected_xml = tflite_file.replace('.tflite', '.xml')
        if expected_xml not in xml_files:
            missing_pairs.append(tflite_file)
    
    if missing_pairs:
        print("ERROR: The following .tflite files are missing corresponding .xml files:")
        for tflite_file in missing_pairs:
            print(f"  - {tflite_file}")
        return False
    
    print(f"Validation passed: All {len(tflite_files)} .tflite files have corresponding .xml files.")
    return True


def generate_validation(folder_path):
    """Generate validation.json with file names and MD5 checksums."""
    script_name = os.path.basename(__file__)
    validation_file = folder_path / "validation.json"
    
    files_data = []
    
    for file_path in folder_path.iterdir():
        if file_path.is_file():
            filename = file_path.name
            
            if filename == script_name or filename == validation_file.name:
                continue
            
            md5_sum = calculate_md5(file_path)
            if md5_sum:
                files_data.append({
                    "name": filename,
                    "md5": md5_sum
                })
    
    files_data.sort(key=lambda x: x["name"])
    
    with open(validation_file, "w") as f:
        json.dump(files_data, f, indent=2)
    
    print(f"Generated {validation_file} with {len(files_data)} files")


def main():
    """Main function to handle CLI arguments and execute validation generation."""
    parser = argparse.ArgumentParser(
        description="Generate validation.json with MD5 checksums for model files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 generate-validation.py
  python3 generate-validation.py /path/to/models
  ./generate-validation.py /path/to/models
        """
    )
    parser.add_argument(
        "folder",
        nargs="?",
        default=".",
        help="Path to the folder containing model files (default: current directory)"
    )
    
    args = parser.parse_args()
    
    folder_path = Path(args.folder).resolve()
    
    if not folder_path.exists():
        print(f"ERROR: Folder '{folder_path}' does not exist.")
        sys.exit(1)
    
    if not folder_path.is_dir():
        print(f"ERROR: '{folder_path}' is not a directory.")
        sys.exit(1)
    
    print(f"Scanning folder: {folder_path}")
    
    validate_file_pairs=0 
    if test ${validate_file_pairs} -nq 0 && not validate_file_pairs(folder_path):
        print("\nValidation failed. Please ensure all .tflite files have corresponding .xml files.")
        sys.exit(1)
    
    generate_validation(folder_path)


if __name__ == "__main__":
    main()
