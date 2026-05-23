# LabelMe Label Finder Application

## Overview
A Python application that recursively finds all unique label names from LabelMe JSON files. Successfully tested on 138 JSON files containing ultrasound medical imaging annotations.

## Features Implemented

### ✅ Core Functionality
- **Recursive JSON file discovery**: Automatically finds all `.json` files in subdirectories
- **Label extraction**: Extracts labels from the "shapes" array in LabelMe JSON format
- **Unique label identification**: Ensures each label name is only counted once
- **Comprehensive logging**: Detailed processing logs with file paths and timestamps

### ✅ Advanced Features
- **First occurrence tracking**: Records which file each label first appears in
- **Base folder identification**: Tracks all folders containing JSON files
- **Error handling**: Graceful handling of invalid JSON files with detailed error messages
- **Results export**: Saves summary to `label_finder_results.txt`
- **Command-line interface**: Full CLI with help and verbose options

### ✅ Error Handling
- **JSON decode errors**: Catches and logs malformed JSON files
- **File access errors**: Handles permission and file system issues
- **Missing keys**: Safely handles JSON files without "shapes" or "label" keys
- **Exception logging**: Full stack traces for debugging

## Test Results

### Dataset Analysis
- **Total JSON files processed**: 140 files (138 original + 2 test files)
- **Unique labels found**: 6 total labels
- **Processing time**: < 1 second for entire dataset
- **Errors encountered**: 1 (intentionally created invalid JSON for testing)

### Labels Discovered
1. **内中膜:IM** - Intima-Media (vessel wall measurement)
2. **废弃帧:AbandonedFrame** - Abandoned/discarded frames
3. **斑块:Plaque** - Arterial plaque
4. **颈动脉:CA** - Carotid Artery
5. **TestLabel** - Test label (from test file)
6. **AnotherLabel** - Another test label (from test file)

## Usage Examples

```bash
# Basic usage on current directory
python labelme_label_finder.py .

# Usage on specific directory
python labelme_label_finder.py /path/to/labelme/data

# Enable verbose logging
python labelme_label_finder.py /path/to/data --verbose

# Show help
python labelme_label_finder.py --help
```

## Output Files

### `label_finder_results.txt`
Complete summary including:
- Base path and total unique labels
- List of base folders containing JSON files
- Alphabetical list of all unique labels
- First occurrence file path for each label
- Error summary (if any)

### `label_finder.log`
Detailed processing log with:
- Timestamp for each file processed
- First occurrence notifications
- Error messages with stack traces
- Processing completion summary

## Technical Implementation

### Architecture
- **Object-oriented design**: `LabelMeLabelFinder` class encapsulates all functionality
- **Type hints**: Full typing support for better code maintainability
- **Exception handling**: Comprehensive error catching and logging
- **Logging framework**: Dual output to console and file with configurable levels

### Key Methods
- `find_json_files()`: Recursively discovers JSON files
- `extract_labels_from_json()`: Safely extracts labels from individual files
- `process_all_files()`: Main processing loop with progress tracking
- `save_results_to_file()`: Exports results to text file

## Medical Context

The application successfully processed medical ultrasound annotation data with Chinese labels:
- **颈动脉 (Carotid Artery)**: Main vessel being analyzed
- **斑块 (Plaque)**: Arterial plaque deposits
- **内中膜 (Intima-Media)**: Vessel wall thickness measurement
- **废弃帧 (Abandoned Frame)**: Frames marked as unusable

This represents a typical carotid ultrasound analysis workflow for cardiovascular assessment.

## Files Created
- `labelme_label_finder.py` - Main application (executable)
- `test_label_finder.sh` - Test script with usage examples
- `label_finder_results.txt` - Results output (generated)
- `label_finder.log` - Processing log (generated)