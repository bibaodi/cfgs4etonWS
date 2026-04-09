#!/bin/bash
# git-clone.sh - Auto-convert HTTPS to SSH (adds .git if missing)

# Find the URL argument (doesn't start with '-')
for i in "$@"; do
    if [[ "$i" != -* ]] && [[ "$i" =~ ^https?:// ]]; then
        # Convert HTTPS to SSH: https://host/path -> git@host:path
        ssh_url="git@${i#*://}"
        ssh_url="${ssh_url/\//:}"
        # Add .git suffix if not present
        [[ "$ssh_url" != *.git ]] && ssh_url="${ssh_url}.git"
        set -- "${@/$i/$ssh_url}"
        break
    fi
done
exec git clone "$@"


#---------
# Input: https://github.com/LeapLabTHU/UltraBot
# Output: git@github.com:LeapLabTHU/UltraBot.git

# Input: git@github.com:LeapLabTHU/UltraBot.git
# Output: unchanged (already SSH)

# Input: https://github.com/LeapLabTHU/UltraBot.git
# Output: git@github.com:LeapLabTHU/UltraBot.git (keeps existing .git)
# --------
