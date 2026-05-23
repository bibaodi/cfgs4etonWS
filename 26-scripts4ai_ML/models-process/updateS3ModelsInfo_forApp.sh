#!/bin/bash
set -e  # exit on error

#!/bin/env bash
# eton@v1.0-260312


# Configuration
S3_DEST="s3://yingling-s3test/Models/models_infomations.json"
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

    if confirm "$src" "$S3_DEST"; then
        upload_file "$src" "$S3_DEST"
        echo "Upload completed. ACL set to public-read."
        # Optionally print public URL
        echo "Public URL: https://yingling-s3test.s3.amazonaws.com/Models/models_infomations.json"
    else
        echo "Aborted."
        exit 0
    fi
}

# Run main
main "$@"
