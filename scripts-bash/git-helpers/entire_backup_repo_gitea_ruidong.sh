#!/bin/bash
##entire_backup_repo.sh 
## eton@260301
export PS4='+ [${LINENO}] '   # Show line number in prompt
set -x

# Configuration
_token="${_ruidongToken_}"
_url="https://code.effectlib.com:8083/"
_user="bibaodi"
_repo="webUSIS26"

# Timestamp for issue/comment files
_timestamp=$(date +"%Y%m%d_%H%M%S")

cd /home/xin1u/backup-gitea-webusis/backups/


# 1. Mirror clone the repository (full backup)
if [ -d "${_repo}.git" ]; then
  echo "Mirror repository already exists. Fetching latest changes..."
  cd "${_repo}.git"
  git fetch --all
  cd ..
else
  git clone --mirror "https://${_user}:${_token}@code.effectlib.com:8083/${_user}/${_repo}.git"
fi



# 2. Fetch all issues
mkdir -p 02issues
cd ./02issues

issues_dir="issues_${_timestamp}"
mkdir -p "$issues_dir"
cd "${issues_dir}"

issues_file="issues_${_repo}_${_timestamp}.json"
#issues_file="${issues_dir}/issues_${_repo}_${_timestamp}.json"
curl -s -H "Authorization: token ${_token}" \
     "${_url}/api/v1/repos/${_user}/${_repo}/issues?state=all" \
     -o "$issues_file"

# Format issues for readability
jq '.' "$issues_file" > "formatted_issues_${_repo}_${_timestamp}.json"

# 3. Fetch and save comments for each issue, with padded issue numbers
for issue in $(jq -r '.[].number' "$issues_file"); do
  padded_issue=$(printf "%03d" "$issue")  # Pad with leading zeros
  comments_file="raw_comments_issue_${padded_issue}_${_repo}_${_timestamp}.json"
  #comments_file="${issues_dir}/comments_issue_${padded_issue}_${_repo}_${_timestamp}.json"
  curl -s -H "Authorization: token ${_token}" \
       "${_url}/api/v1/repos/${_user}/${_repo}/issues/$issue/comments" \
       -o "$comments_file"
  jq '.' "$comments_file" > "comments_issue_${padded_issue}_${_repo}_${_timestamp}.json"
  rm "$comments_file"
done

echo "Backup completed. Mirror repository, issues, and comments saved with timestamp: ${_timestamp}"

