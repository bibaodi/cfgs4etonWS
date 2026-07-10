#!/bin/bash
# ==============================================================================
# README: Flatten Scans to Set 
# - v03.260710 by eton
#
# Objective:
#   This script flattens the file hierarchy by gathering images from multiple 
#   scan directories and consolidating them into a single, flat dataset folder.
#   After processing, it cleans up the original directories by removing them 
#   if they are left empty.
#
# Description:
#   It scans for directories matching the pattern "03_ScanEmpty_*_frms". 
#   Instead of keeping the images inside their respective sub-folders, it 
#   extracts all image files, renames them by prepending a prefix based on 
#   their original parent folder's number (e.g., an image from 
#   "03_ScanEmpty_17_frms" gets the prefix "03_ScanEmpty_17_"), and moves them 
#   into a unified destination folder named "03_SE_set".
#
# Usage:
#   1. Place this script in the parent directory containing your 
#      "03_ScanEmpty_*_frms" folders.
#   2. Make it executable: chmod +x flatten_scans_to_set.sh
#   3. Run it: ./flatten_scans_to_set.sh
#
# Notes:
#   - The destination folder "03_SE_set" will be created automatically.
#   - Files will not be overwritten if a file with the same name already exists 
#     in the destination folder (uses `mv -n`).
#   - Source folders are only deleted if ALL their files were successfully moved.
# ==============================================================================

# Global variables
DEST_DIR="03_SE_set"
DIR_REGEX="^03_ScanEmpty_([0-9]+)_frms$"
COUNT=0
LOG_FILE="flatten_operations.log"

# ------------------------------------------------------------------------------
# Function: cleanup_empty_dir
# Purpose: Tests if a directory is empty. If it is, it removes it.
# Arguments: 
#   $1 - The path to the directory to check and clean up.
# ------------------------------------------------------------------------------
cleanup_empty_dir() {
    local target_dir="$1"
    
    if [ -d "$target_dir" ]; then
        # find returns true if it finds any files/subdirectories
        if [ -z "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            echo "  -> Cleanup: Folder is empty. Removing '$target_dir'."   # Stdout
            rmdir "$target_dir"
        else
            echo "  -> Cleanup: Folder '$target_dir' is NOT empty. Skipping removal." # Stdout
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: flatten_directory
# Purpose: Processes a single source directory. Renames images and moves them 
#          to the destination folder.
# Arguments: 
#   $1 - The source directory to process.
# ------------------------------------------------------------------------------
flatten_directory() {
    local src_dir="$1"
    local clean_dir="${src_dir%/}"
    
    if [[ "$clean_dir" =~ $DIR_REGEX ]]; then
        local number="${BASH_REMATCH[1]}"
        local prefix="03_ScanEmpty_${number}_"
        
        echo "Processing folder: $clean_dir"  # Stdout
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Processing $clean_dir (Prefix: $prefix)" >> "$LOG_FILE"
        
        while read -r file; do
            [ -z "$file" ] && continue
            
            local filename=$(basename "$file")
            local new_name=""
            
            if [[ "$filename" == "$prefix"* ]]; then
                new_name="$filename"
            else
                new_name="${prefix}${filename}"
            fi
            
            if mv -n "$file" "$DEST_DIR/$new_name"; then
                # File-level log goes to log file, not stdout
                echo "  -> Moved: $filename  =>  $DEST_DIR/$new_name" >> "$LOG_FILE"
                ((COUNT++))
            else
                echo "  -> Skipped (already exists or failed): $filename" >> "$LOG_FILE"
            fi
            
        done < <(find "$clean_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.bmp" \))
        
        cleanup_empty_dir "$clean_dir"
    fi
}

# ==============================================================================
# Main Execution Block
# ==============================================================================

set -e
trap 'echo -e "\nScript interrupted by user. Exiting."; exit 1' INT

# Initialize clean log file for this run
echo "--------------------------------------------------"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script started."|tee -a "$LOG_FILE"

mkdir -p "$DEST_DIR"

echo "Flattening scan directories into '$DEST_DIR'..."
echo "Detailed file operations will be logged to: $LOG_FILE"
echo "--------------------------------------------------"

for dir in */; do
    flatten_directory "$dir"
done

echo "--------------------------------------------------"
echo "Done! Successfully flattened $COUNT files into '$DEST_DIR'."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script ended."|tee -a "$LOG_FILE"

