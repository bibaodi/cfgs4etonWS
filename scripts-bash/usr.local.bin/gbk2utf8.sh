#!/bin/env bash

detect_encoding() {
    local file="$1"
    if ! command -v uchardet &> /dev/null; then
        echo "Installing uchardet..."
        sudo apt update && sudo apt install -y uchardet
    fi
    uchardet "$file" | tr 'A-Z' 'a-z'
}

gbk_to_utf8() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: gbk_to_utf8 <input_file>"
        return 1
    fi

    local input_file="$1"
    local tmp_file="/tmp/$(basename "$input_file").utf8.tmp"

    if [ ! -f "$input_file" ]; then
        echo "Error: File '$input_file' not found."
        return 1
    fi

    local encoding
    encoding=$(detect_encoding "$input_file")
    if [[ "$encoding" != *"gbk"* && "$encoding" != *"gb18030"* ]]; then
        echo "File is not GBK/GB18030 encoded. Skipping conversion."
        return 0
    fi
    echo "File is GBK/GB18030 encoded. Converting to UTF-8..."

    iconv -f GBK -t UTF-8 "$input_file" > "$tmp_file"

    if [ $? -ne 0 ]; then
        echo "Error: Conversion failed."
        return 1
    fi

    read -p "Do you want to overwrite '$input_file' with the converted UTF-8 file? [y/N] " answer
    case "$answer" in
        [yY])
            mv "$tmp_file" "$input_file"
            echo "File '$input_file' has been converted to UTF-8."
            ;;
        *)
            echo "Conversion aborted. The converted file is saved as '$tmp_file'."
            ;;
    esac
}


_ifile=${1:-nofile}
_ofile=${_ifile}
test ! -f "${_ifile}" && echo "file not found" && exit 0
gbk_to_utf8 "${_ifile}"
