#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# 1. Check if we are inside a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: You are not inside a Git repository."
    exit 1
fi

# 2. Check if 'origin' remote exists
if ! git remote | grep -wq "origin"; then
    echo "Error: Remote 'origin' does not exist."
    exit 1
fi

# 3. Check if 'ori-x1' remote exists
if ! git remote | grep -wq "ori-x1"; then
    echo "Error: Remote 'ori-x1' does not exist."
    echo "Please add it first using: git remote add ori-x1 <your-gitlab-url>"
    exit 1
fi

echo "Fetching and pulling from 'origin' (Gitea)..."
# Fetch all branches and tags from origin
git fetch origin

# Pull changes for the current branch
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

echo "Pushing all branches and tags to 'ori-x1' (GitLab)..."
# Push all branches
git push ori-x1 --all
# Push all tags
git push ori-x1 --tags

echo "Sync completed successfully!"

