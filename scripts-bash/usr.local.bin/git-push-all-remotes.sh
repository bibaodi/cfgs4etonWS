#!/bin/env bash
# - eton@260424 v0.0.1 first edition;
# - eton@250805 v0.0.2 add --set-upstream fallback, push tags, shorten;

get_remotes() {
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repo" >&2; return 1; }
    git remote
}

push_with_retry() {
    local remote="$1"
    local branch; branch=$(git rev-parse --abbrev-ref HEAD)
    local max=5 delay=3

    for i in $(seq 1 $max); do
        echo "  [$i/$max] git push $remote"
        local err; err=$(git push "$remote" 2>&1)
        [ $? -eq 0 ] && return 0

        # Fallback: set upstream on origin, then retry
        if echo "$err" | grep -qi "no upstream"; then
            echo "  → upstream not set, running: git push --set-upstream origin $branch"
            git push --set-upstream origin "$branch" 2>&1 && continue || return 1
        fi

        [ $i -lt $max ] && { echo "  retry in ${delay}s..."; sleep "$delay"; }
    done
    echo "  FAILED after $max attempts: $remote" >&2
    return 1
}

push_tags() {
    local remote="$1"
    echo "  git push $remote --tags"
    git push "$remote" --tags 2>&1 | tail -1
}

# ---- main ----
mapfile -t remotes < <(get_remotes)
for r in "${remotes[@]}"; do
    echo "=== $r ==="
    push_with_retry "$r"
    push_tags "$r"
done
echo "Done."
