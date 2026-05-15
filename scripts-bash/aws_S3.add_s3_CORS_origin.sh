#!/usr/bin/env bash
# eton@260515 support add new origin ;
set -euo pipefail

_usage='usage:aws s3api get-bucket-cors --bucket yingling-s3test-storage --region cn-north-1'
# Default values (change if you like)
BUCKET="yingling-s3test-storage"
REGION="cn-north-1"
NEW_ORIGIN="https://test.medicalxy.com"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bucket) BUCKET="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        --origin) NEW_ORIGIN="$2"; shift 2 ;;
        *) echo -e "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$BUCKET" || -z "$REGION" || -z "$NEW_ORIGIN" ]]; then
    echo "Usage: $0 --bucket BUCKET --region REGION --origin ORIGIN"
    exit 1
fi

echo "Adding origin '$NEW_ORIGIN' to bucket '$BUCKET' in region '$REGION'"

# Get current CORS configuration (may fail if none exists)
CORS_JSON=$(aws s3api get-bucket-cors --bucket "$BUCKET" --region "$REGION" 2>/dev/null || echo "")

if [[ -z "$CORS_JSON" ]]; then
    echo "No existing CORS configuration found. Creating a new one."
    # Create a minimal CORS rule with the new origin
    NEW_CORS=$(jq -n \
        --arg origin "$NEW_ORIGIN" \
        '{
            CORSRules: [{
                AllowedHeaders: ["*"],
                AllowedMethods: ["GET", "HEAD"],
                AllowedOrigins: [$origin],
                ExposeHeaders: ["Content-Length", "Content-Range", "Accept-Ranges"],
                MaxAgeSeconds: 3600
            }]
        }')
else
    # Add the new origin to the first rule's AllowedOrigins list (modify all rules if needed)
    echo "Existing CORS found. Adding origin if not already present."
    NEW_CORS=$(echo "$CORS_JSON" | jq \
        --arg origin "$NEW_ORIGIN" \
        '.CORSRules[0].AllowedOrigins |= if index($origin) then . else . + [$origin] end')
fi

# Apply the updated CORS configuration
aws s3api put-bucket-cors --bucket "$BUCKET" --region "$REGION" --cors-configuration "$NEW_CORS"

echo "Successfully updated CORS for bucket '$BUCKET'"
