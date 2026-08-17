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
import re
import argparse
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
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


def _collect_ai_keys(folder_path):
    """Parse all model .xml files and return a set of AiModel/@key values.

    Skips presets.xml (special preset file, not a model description).
    """
    keys = set()
    for xml_path in sorted(folder_path.iterdir()):
        if not xml_path.is_file() or xml_path.suffix != ".xml":
            continue
        if xml_path.name == "presets.xml":
            continue
        try:
            root = ET.parse(xml_path).getroot()
            k = root.get("key", "")
            if k:
                keys.add(k)
        except ET.ParseError:
            pass
    return keys


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
            elif filename.endswith('.xml') and filename != "presets.xml":
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


def validate_xml_locator_references(folder_path):
    """Validate that every <Locator file="..."> in XMLs points to an existing .tflite file.

    Also checks:
      - <AiModel key="..."> values are unique across all XMLs (no duplicate keys).
      - Every .tflite file referenced by an XML exists on disk.
      - Reports .tflite files that are NOT referenced by any XML (orphans).

    Returns True if all checks pass.
    """
    tflite_on_disk = {
        f.name for f in folder_path.iterdir()
        if f.is_file() and f.suffix == ".tflite"
    }
    xml_files = sorted(
        f for f in folder_path.iterdir()
        if f.is_file() and f.suffix == ".xml" and f.name != "presets.xml"
    )

    if not xml_files:
        print("WARNING: No .xml files found in folder.")
        return True

    ai_keys = []
    locator_refs = {}  # xml_filename -> referenced_tflite_file
    errors = []

    for xml_path in xml_files:
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
        except ET.ParseError as e:
            errors.append(f"{xml_path.name}: XML parse error — {e}")
            continue

        key = root.get("key", "")
        ai_keys.append(key)

        locator = root.find("Locator")
        if locator is None:
            errors.append(f"{xml_path.name}: missing <Locator> element")
            continue

        ref_file = locator.get("file", "").strip()
        locator_refs[xml_path.name] = ref_file

        if not ref_file:
            errors.append(f"{xml_path.name}: <Locator> missing 'file' attribute")
        elif ref_file not in tflite_on_disk:
            errors.append(
                f"{xml_path.name}: <Locator file=\"{ref_file}\"> "
                f"— file NOT FOUND in folder"
            )

    # --- duplicate AiModel keys ---
    key_counts = Counter(ai_keys)
    dup_keys = {k: c for k, c in key_counts.items() if c > 1}
    if dup_keys:
        for k, c in dup_keys.items():
            errors.append(
                f"Duplicate AiModel key=\"{k}\" found in {c} XML files"
            )

    # --- .tflite files not referenced by any XML ---
    referenced_tflites = set(locator_refs.values())
    orphan_tflites = tflite_on_disk - referenced_tflites
    if orphan_tflites and tflite_on_disk:
        for tf in sorted(orphan_tflites):
            print(f"  WARNING: {tf} — not referenced by any XML <Locator>")

    # --- report ---
    if errors:
        print(f"\nERROR: {len(errors)} XML locator reference issue(s):")
        for e in errors:
            print(f"  - {e}")
        return False

    print(
        f"XML locator validation passed: {len(xml_files)} XML(s), "
        f"{len(ai_keys)} AiModel key(s), "
        f"{len(referenced_tflites)} referenced .tflite file(s) "
        f"(all exist on disk, keys are unique)."
    )
    return True


def validate_presets_xml(folder_path):
    """Validate that every model=... in presets.xml matches an AiModel/@key.

    presets.xml maps app names to model keys:
      <presets>
        <preset application="app_thyroid" model="thyroid_yolo26V03"/>

    Each model= value must reference an existing AiModel/@key in a model .xml file.
    Returns True if all presets have valid model references.
    """
    presets_path = folder_path / "presets.xml"
    if not presets_path.is_file():
        return True  # no presets file to validate

    ai_keys = _collect_ai_keys(folder_path)
    if not ai_keys:
        print("WARNING: presets.xml exists but no model .xml files with AiModel/@key found.")
        return True

    try:
        tree = ET.parse(presets_path)
    except ET.ParseError as e:
        print(f"ERROR: presets.xml parse error — {e}")
        return False

    errors = []
    presets_seen = []
    for preset in tree.getroot().findall("preset"):
        model_key = preset.get("model", "").strip()
        app = preset.get("application", "")
        presets_seen.append(model_key)
        if not model_key:
            errors.append(f"presets.xml: <preset> missing 'model' attribute (app={app or '?'})")
        elif model_key not in ai_keys:
            errors.append(
                f"presets.xml: model=\"{model_key}\" (app={app or '?'}) "
                f"— no <AiModel key=\"{model_key}\"> found in any .xml"
            )

    if errors:
        print(f"\nERROR: {len(errors)} presets.xml reference issue(s):")
        for e in errors:
            print(f"  - {e}")
        return False

    print(
        f"presets.xml validation passed: {len(presets_seen)} preset(s), "
        f"all model= keys found in AiModel/@key."
    )
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


def create_zip_package(folder_path):
    """Zip all files in folder_path into <folder_name>.zip in the parent folder.

    Files are stored at the archive root (no wrapping folder), mirroring:
        zip ../<folder_name>.zip -r ./
    """
    zip_path = folder_path.parent / (folder_path.name + ".zip")

    if zip_path.exists():
        answer = input(f"{zip_path.name} already exists. Delete it? [y/N]: ").strip().lower()
        if answer not in ("y", "yes"):
            print("Skipped creating zip package.")
            return None
        try:
            zip_path.unlink()
            print(f"Deleted existing {zip_path.name}.")
        except Exception as e:
            print(f"ERROR: Failed to delete {zip_path}: {e}")
            sys.exit(1)

    files = [p for p in folder_path.rglob("*") if p.is_file()]

    try:
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_path in files:
                zf.write(file_path, file_path.relative_to(folder_path))
    except Exception as e:
        print(f"ERROR: Failed to create zip package: {e}")
        sys.exit(1)

    print(f"Created {zip_path} with {len(files)} files")
    return zip_path


class ModelsInfoBuilder:
    """Build a model-package entry and append it to models_infomations.json.

    Reads the most up-to-date cumulative list (the latest
    models_infomations.json-for* snapshot, or the base file), appends an entry
    for a newly created .zip package, and writes a versioned snapshot
    models_infomations.json-for<version_code>.
    """

    BASE_URL = "https://yingling-s3test.s3.cn-north-1.amazonaws.com.cn/Models/"

    def __init__(self, info_filename="models_infomations.json",
                 model_xml_version="2.3", schema=2.0):
        self.info_filename = info_filename
        self.model_xml_version = model_xml_version
        self.schema = schema

    @staticmethod
    def parse_version(name):
        """Return (version, version_code) parsed from a zip filename like 'modelsV2.9.2.zip'.

        version_code is the three version numbers concatenated, e.g. "2.9.2" -> 292.
        """
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", name)
        if not match:
            raise ValueError(f"Cannot parse version from '{name}'")
        major, minor, patch = match.groups()
        version = f"{int(major)}.{int(minor)}.{int(patch)}"
        version_code = int(f"{major}{minor}{patch}")
        return version, version_code

    def _load_entries(self, package_dir):
        """Load the fullest cumulative entry list from package_dir.

        Prefers the snapshot whose newest version_code is highest; falls back
        to the base file if no snapshot exists.
        """
        candidates = [package_dir / self.info_filename]
        candidates += list(package_dir.glob(f"{self.info_filename}-for*"))

        best_entries = []
        best_code = -1
        for path in candidates:
            if not path.is_file():
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(data, list):
                continue
            code = max(
                (e.get("version_code", -1) for e in data if isinstance(e, dict)),
                default=-1,
            )
            if code > best_code:
                best_entries, best_code = data, code
        return best_entries

    def build_entry(self, zip_path, update=""):
        """Build the dict entry for a zip package, computing md5sum from the file."""
        name = zip_path.name
        version, version_code = self.parse_version(name)
        md5 = calculate_md5(zip_path)
        if not md5:
            raise RuntimeError(f"Failed to compute MD5 for {name}")
        return {
            "name": name,
            "version": version,
            "version_code": version_code,
            "model_xml_version": self.model_xml_version,
            "schema": self.schema,
            "md5sum": md5,
            "url": self.BASE_URL + name,
            "update": update,
        }

    def add_package(self, folder_path, zip_path, update=""):
        """Append an entry for zip_path and write models_infomations.json-for<version_code>.

        The info json and zip live in folder_path.parent. Returns (output_path, entry).
        """
        package_dir = folder_path.parent
        entry = self.build_entry(zip_path, update)

        entries = self._load_entries(package_dir)
        entries = [
            e for e in entries
            if isinstance(e, dict) and e.get("version_code") != entry["version_code"]
        ]
        entries.append(entry)

        out_path = package_dir / f"{self.info_filename}-for{entry['version_code']}"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(entries, f, indent=2, ensure_ascii=False)
        return out_path, entry


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
    
    if not validate_file_pairs(folder_path):
        print("\nValidation failed. Please ensure all .tflite files have corresponding .xml files.")
        sys.exit(1)

    if not validate_xml_locator_references(folder_path):
        print("\nValidation failed. Please fix XML <Locator file=\"...\"> references.")
        sys.exit(1)

    if not validate_presets_xml(folder_path):
        print("\nValidation failed. Please fix presets.xml model references.")
        sys.exit(1)

    generate_validation(folder_path)

    answer = input("\nCreate zip package? [y/N]: ").strip().lower()
    if answer in ("y", "yes"):
        zip_path = create_zip_package(folder_path)
        if zip_path:
            info_answer = input("\nAppend entry to models_infomations.json? [y/N]: ").strip().lower()
            if info_answer in ("y", "yes"):
                update = input("Update notes (changelog): ").strip()
                builder = ModelsInfoBuilder()
                out_path, entry = builder.add_package(folder_path, zip_path, update)
                print(f"Wrote {out_path} (version_code={entry['version_code']})")


if __name__ == "__main__":
    main()
