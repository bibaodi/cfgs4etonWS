#!/bin/bash
# Usage: ./copy_models.sh <ResultName>
# Copies:
#   - xinmy_multi.pt  →  ./<current_folder>.pt
#   - xinmy_multi.tflite → ./<current_folder>.tflite
# from /train/history_train/<ResultName>/... into the current directory.
# Then appends md5sum of both files to md5sum.txt.

_SDIR="${1:-nothing}"

if [ "$_SDIR" = "nothing" ]; then
    echo "Usage: $0 ResultName"
    echo "Example: $0 res_surpressFP_mul_thyNoduGlandv09.N13_20260515T1628_sz224"
    exit 1
fi

_SDIR="/train/history_train/${_SDIR}"

if [ ! -e "$_SDIR" ]; then
    echo "Error: Source directory '$_SDIR' does not exist."
    exit 1
fi

# Current folder name (without path)
CUR_NAME=$(basename "$PWD")

echo "Source base: $_SDIR"
echo "Current folder: $CUR_NAME"
echo "Target location: $PWD"

# Define the two model file names (edit if needed)
MODEL_PT="xinmy_multi.pt"
MODEL_TFLITE="xinmy_multi.tflite"

# Find and copy .pt file
SRC_PT=$(find "$_SDIR" -type f -name "$MODEL_PT" | head -n 1)
if [ -n "$SRC_PT" ]; then
    TARGET_PT="./${CUR_NAME}.pt"
    cp "$SRC_PT" "$TARGET_PT"
    echo "Copied: $SRC_PT -> $TARGET_PT"
else
    echo "Warning: $MODEL_PT not found in $_SDIR"
fi

# Find and copy .tflite file
SRC_TFLITE=$(find "$_SDIR" -type f -name "$MODEL_TFLITE" | head -n 1)
if [ -n "$SRC_TFLITE" ]; then
    TARGET_TFLITE="./${CUR_NAME}.tflite"
    cp "$SRC_TFLITE" "$TARGET_TFLITE"
    echo "Copied: $SRC_TFLITE -> $TARGET_TFLITE"
    md5sum ${SRC_TFLITE}
else
    echo "Warning: $MODEL_TFLITE not found in $_SDIR"
fi

# Generate md5sum for the two copied files (only if they exist)
MD5_FILE="md5sum.txt"
> "$MD5_FILE"   # Create/clear md5sum.txt (or append? Use >> to append as per user example)
if [ -f "${CUR_NAME}.pt" ]; then
    md5sum "${CUR_NAME}.pt" >> "$MD5_FILE"
fi
if [ -f "${CUR_NAME}.tflite" ]; then
    md5sum "${CUR_NAME}.tflite" >> "$MD5_FILE"
fi

echo "Done. Checksums saved in $MD5_FILE"

