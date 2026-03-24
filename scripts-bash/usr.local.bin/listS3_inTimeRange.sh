# Calculate the date from 24 hours ago (works on Linux/macOS)
TWENTY_FOUR_HOURS_AGO=$(date -u -d '24 hours ago' +'%Y-%m-%dT%H:%M:%SZ')
Bucket="dev-studyupload"
Bucket="yingling-s3test"

echo "s3://${Bucket}/"
# List objects modified after that date

aws s3api list-objects-v2 \
    --bucket "${Bucket}" \
    --query "Contents[?LastModified>=\`$TWENTY_FOUR_HOURS_AGO\`].[Key, LastModified, Size]" \
    --output json #table
