#!/bin/env bash
# - eton@260424 v0.0.1 first edition;
# - eton@260424 v0.0.2 auto get all remote names;


# Function: get all remote names as an array
get_all_origins() {
    # Check if inside a Git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not inside a Git repository." >&2
        return 1
    fi
    # Print each remote on a separate line; caller will turn lines into array
    git remote
}

# Retry function: tries a command up to N times
retry_push() {
    local remote="$1"
    local max_retries=10
    local attempt=1
    local delay=2  # seconds between retries

    while [ $attempt -le $max_retries ]; do
        echo "Attempt $attempt/$max_retries: git push $remote"
        if git push "$remote"; then
            echo "Success: git push $remote"
            return 0
        else
            echo "Failed: git push $remote (attempt $attempt)"
            if [ $attempt -lt $max_retries ]; then
                echo "Retrying in $delay seconds..."
                sleep $delay
            fi
        fi
        ((attempt++))
    done

    echo "Error: git push $remote failed after $max_retries attempts."
    return 1
}

_allOrigins=("origin" "ori-gh" "ori-xin1")

# Capture remotes into an array (one element per line)
# Using mapfile (or readarray) is the cleanest way:
mapfile -t _allOrigins < <(get_all_origins)

##############################
# --this can replace mapfile;
#_allOrigins=()
#while IFS= read -r remote; do
#    _allOrigins+=("$remote")
#done < <(get_all_origins)
#############################

# If you prefer POSIX compatibility (but bash can use mapfile), fallback:
# IFS=$'\n' read -r -d '' -a _allOrigins < <(get_all_origins && printf '\0')
for ior in ${_allOrigins[@]}; do
    CMD="git push ${ior}"
    echo "$CMD"
    retry_push "$ior"
    # Optional: exit script if a push fails after retries (uncomment next line)
    # if [ $? -ne 0 ]; then exit 1; fi
done
