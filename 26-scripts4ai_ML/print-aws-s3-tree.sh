#!/bin/bash
# Usage: ./s3tree.sh bucket-name > output.txt

BUCKET=${1:-ftp-huaxia-200420}
#aws s3 ls "s3://$BUCKET/" --recursive | awk '{print $4}' | sed -e 's/[^-][^\/]*\// |/g' -e 's/| / |—/g' > s3-file-tree.txt
DATE=$(date +%y%m%d)
FILENAME="s3-tree${DATE}.txt"

echo "Generating tree for s3://$BUCKET... saving to $FILENAME"

# Generate the tree and redirect output to the dynamic filename
aws s3 ls "s3://$BUCKET/" --recursive | \
awk '{print $4}' | \
sed -e 's/[^-][^\/]*\// |/g' -e 's/| / |—/g' > "$FILENAME"

echo "Done."
