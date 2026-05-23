#!/bin/bash
set -e  # exit on error

# Configuration
S3_FOLDER="s3://yingling-s3test/guidance/"
AUTHOR="${USER:-unknown}"
VERSION="1.0"

# Functions
usage() {
    echo "Usage: $0 <local-file>"
    exit 1
}

confirm() {
    read -r -p "Upload '$1' to '$2'? (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

upload_file() {
    local src="$1"
    local dst="$2"
    echo "Uploading $src to $dst ..."
    aws s3 cp "$src" "$dst" --metadata "author=$AUTHOR,version=$VERSION" --acl public-read
}

# Main
main() {
    if [ $# -ne 1 ]; then
        usage
    fi

    local src="$1"
    if [ ! -f "$src" ]; then
        echo "Error: File '$src' not found."
        exit 1
    fi

    local filename
    filename=$(basename "$src")
    local dst="${S3_FOLDER}${filename}"

    if confirm "$src" "$dst"; then
        upload_file "$src" "$dst"
        echo "Upload completed. ACL set to public-read."

        # Extract bucket name and key for public URL
        # Assumes S3_FOLDER format: s3://bucket-name/path/
        local bucket
        local key_prefix
        bucket=$(echo "$S3_FOLDER" | sed -E 's|^s3://([^/]+)/.*|\1|')
        key_prefix=$(echo "$S3_FOLDER" | sed -E 's|^s3://[^/]+/||')
        echo "Public URL:"# "https://$bucket.s3.amazonaws.com/${key_prefix}${filename}"
	echo "https://${bucket}.s3.cn-north-1.amazonaws.com.cn/${key_prefix}${filename}"
    else
        echo "Aborted."
        exit 0
    fi
}

# Run main
main "$@"
