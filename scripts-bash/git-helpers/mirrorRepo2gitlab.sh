#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  mirrorRepo2gitlab.sh --from <source-remote> --to <target-remote>
  mirrorRepo2gitlab.sh
  mirrorRepo2gitlab.sh --help

With no remote options, the script suggests the current branch's upstream
remote as the source and the only other configured remote as the target.
Detected remotes must be confirmed. If that is ambiguous, the script prompts
for both remote names.

The script fetches source branches and tags, then mirrors them to the target.
Target-only branches and tags are deleted. Other ref namespaces are untouched.
Locally, source branches update remote-tracking refs and missing tags are added;
existing local tags are preserved.
EOF
}

error() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# Parse explicit remote names; with neither option, selection is interactive.
parse_options() {
    source_remote=
    target_remote=
    options_provided=false

    while (($#)); do
        case "$1" in
            --from)
                (($# >= 2)) || error "Option --from requires a remote name."
                [[ -z "$source_remote" ]] || error "Option --from may only be specified once."
                source_remote=$2
                options_provided=true
                shift 2
                ;;
            --to)
                (($# >= 2)) || error "Option --to requires a remote name."
                [[ -z "$target_remote" ]] || error "Option --to may only be specified once."
                target_remote=$2
                options_provided=true
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1 (use --help for usage)."
                ;;
        esac
    done

    if [[ "$options_provided" == true ]] && { [[ -z "$source_remote" ]] || [[ -z "$target_remote" ]]; }; then
        error "Specify both --from <source-remote> and --to <target-remote>."
    fi
}

require_repository() {
    git rev-parse --git-dir >/dev/null 2>&1 ||
        error "Run this script from inside a Git repository."

    mapfile -t remotes < <(git remote)
    ((${#remotes[@]} >= 2)) || error "At least two Git remotes must be configured."
}

has_remote() {
    local remote=$1
    local configured

    for configured in "${remotes[@]}"; do
        [[ "$configured" == "$remote" ]] && return 0
    done
    return 1
}

prompt_remote() {
    local label=$1
    local selected
    local configured

    while true; do
        printf '%s\n' "Configured remotes:"
        for configured in "${remotes[@]}"; do
            printf '  %s\n' "$configured"
        done
        read -r -p "$label remote: " selected || error "Could not read remote selection."
        if has_remote "$selected"; then
            REPLY=$selected
            return
        fi
        printf 'Error: Remote "%s" is not configured.\n' "$selected" >&2
    done
}

# Prefer the upstream and the one remaining remote, but always confirm a guess.
select_remotes() {
    local branch
    local upstream_remote
    local remote
    local confirmation
    local -a other_remotes=()

    if [[ "$options_provided" == true ]]; then
        return
    fi

    branch=$(git branch --show-current)
    if [[ -n "$branch" ]]; then
        upstream_remote=$(git config --get "branch.${branch}.remote" || true)
    else
        upstream_remote=
    fi

    if [[ -n "$upstream_remote" ]] && has_remote "$upstream_remote"; then
        for remote in "${remotes[@]}"; do
            [[ "$remote" == "$upstream_remote" ]] || other_remotes+=("$remote")
        done
    fi

    if [[ -n "$upstream_remote" ]] && has_remote "$upstream_remote" && ((${#other_remotes[@]} == 1)); then
        source_remote=$upstream_remote
        target_remote=${other_remotes[0]}
        printf 'Detected source remote: %s\nDetected target remote: %s\n' "$source_remote" "$target_remote"
        read -r -p "Mirror branches and tags from '$source_remote' to '$target_remote'? [y/N] " confirmation ||
            error "Could not read confirmation."
        case "$confirmation" in
            y|Y|yes|YES|Yes) ;;
            *) error "Sync cancelled." ;;
        esac
    else
        printf 'Could not unambiguously detect a source/target pair.\n'
        prompt_remote "Source"
        source_remote=$REPLY
        prompt_remote "Target"
        target_remote=$REPLY
    fi
}

validate_remotes() {
    has_remote "$source_remote" || error "Source remote '$source_remote' is not configured."
    has_remote "$target_remote" || error "Target remote '$target_remote' is not configured."
    [[ "$source_remote" != "$target_remote" ]] || error "Source and target remotes must be different."
}

# Fetch into private temporary refs so local branches and tags are not changed.
fetch_source_refs() {
    sync_ref_prefix="refs/mirror-sync-$$"
    printf "Fetching branches and tags from '%s'...\n" "$source_remote"
    git fetch --no-tags "$source_remote" \
        "+refs/heads/*:${sync_ref_prefix}/heads/*" \
        "+refs/tags/*:${sync_ref_prefix}/tags/*"
}

# Push the fetched source refs; pruning makes target branches/tags match the source.
push_target_refs() {
    printf "Mirroring branches and tags to '%s' (target-only branches and tags will be deleted)...\n" "$target_remote"
    git push --prune --force "$target_remote" \
        "+${sync_ref_prefix}/heads/*:refs/heads/*" \
        "+${sync_ref_prefix}/tags/*:refs/tags/*"
}

# Always remove temporary refs, including when a fetch or push fails.
cleanup_sync_refs() {
    local ref

    while IFS= read -r ref; do
        [[ -z "$ref" ]] || git update-ref -d "$ref" ||
            printf 'Warning: Could not remove temporary ref %s\n' "$ref" >&2
    done < <(git for-each-ref --format='%(refname)' "$sync_ref_prefix")
}

# Refresh this remote's local branch-tracking refs. Pruning removes tracking refs
# for source branches deleted upstream; local branches are never checked out or changed.
sync_local_repo() {
    local ref
    local tag
    local local_tag_ref
    local object

    printf "Updating local remote-tracking branches from '%s'...\n" "$source_remote"
    git fetch --no-tags --prune "$source_remote" \
        "+refs/heads/*:refs/remotes/${source_remote}/*"

    # Add only missing source tags, preserving local-only tags and name conflicts.
    printf "Adding missing local tags from '%s'...\n" "$source_remote"
    while IFS= read -r ref; do
        tag=${ref#"$sync_ref_prefix/tags/"}
        local_tag_ref="refs/tags/${tag}"
        if ! git show-ref --verify --quiet "$local_tag_ref"; then
            object=$(git rev-parse "$ref")
            git update-ref "$local_tag_ref" "$object"
        fi
    done < <(git for-each-ref --format='%(refname)' "${sync_ref_prefix}/tags")
}

main() {
    parse_options "$@"
    require_repository
    select_remotes
    validate_remotes

    trap cleanup_sync_refs EXIT
    fetch_source_refs
    sync_local_repo
    push_target_refs

    printf 'Sync from %s to %s completed successfully; local tracking branches and missing tags updated.\n' \
        "$source_remote" "$target_remote"
}

main "$@"
