#!/bin/bash
# -----------------------------------------------------------------------------
# Script: move_v_contents.sh
# Purpose: Recursively find directories whose names contain "-v". For each,
#          move *all contents* (including hidden files) to the current folder,
#          then remove the (now empty) source directory.
#
#          Interactive confirmation is provided, with options to:
#            y - move contents of this directory
#            n - skip this directory
#            a - move contents of this and all remaining directories
#            q - quit immediately
#
# Usage: ./move_v_contents.sh
# -----------------------------------------------------------------------------

set -o nounset
set -o pipefail
shopt -s nullglob dotglob

# -----------------------------------------------------------------------------
# Display an error message and exit.
# -----------------------------------------------------------------------------
die() {
    echo "Error: $*" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Prompt the user for a decision.
# Returns: 0 for "yes", 1 for "no"
# Sets the global variable ALL_CHOICE to "yes" if user chooses "all".
# Exits the script entirely if user chooses "quit".
# -----------------------------------------------------------------------------
prompt_user() {
    local dir="$1"
    local answer
    while true; do
        read -p "Move contents of '$dir' to current folder? [y]es / [n]o / [a]ll / [q]uit: " answer
        case "${answer,,}" in
            y|yes)  return 0 ;;
            n|no)   return 1 ;;
            a|all)  ALL_CHOICE="yes"; return 0 ;;
            q|quit) echo "Exiting."; exit 0 ;;
            *)      echo "Invalid input. Please enter y, n, a, or q." ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Move a single item (file or directory) from source to current directory.
# Handles name collisions by skipping with a warning.
# -----------------------------------------------------------------------------
move_item() {
    local src_item="$1"
    local base
    base="$(basename "$src_item")"
    local dest="./$base"

    if [[ -e "$dest" ]]; then
        echo "⚠️  Warning: '$dest' already exists. Skipping '$src_item'."
        return 1
    fi

    mv "$src_item" ./
    echo "   Moved '$src_item' → ./"
    return 0
}

# -----------------------------------------------------------------------------
# Process one source directory: move its entire contents, then try to remove it.
# -----------------------------------------------------------------------------
process_directory() {
    local src="$1"
    local any_failures=0

    # Move every item (including hidden files) inside the source directory
    for item in "$src"/*; do
        [[ -e "$item" ]] || continue
        move_item "$item" || any_failures=1
    done

    # Attempt to remove the source directory if it is now empty
    if rmdir "$src" 2>/dev/null; then
        echo "   Removed empty directory '$src'."
    else
        if [[ $any_failures -eq 0 ]]; then
            echo "⚠️  Warning: '$src' is not empty after moving all items; leaving it."
        else
            echo "   '$src' not empty (some items were skipped); left in place."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Find all directories (excluding the current one) whose names contain "-v".
# -----------------------------------------------------------------------------
find_directories() {
    local -n arr="$1"   # nameref to the caller's array
    mapfile -d '' arr < <(find . -mindepth 1 -type d -name "*-v*" -print0 2>/dev/null)
}

# -----------------------------------------------------------------------------
# Main script logic.
# -----------------------------------------------------------------------------
main() {
    local dirs=()
    find_directories dirs

    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "No directories containing '-v' found."
        exit 0
    fi

    echo "Found ${#dirs[@]} directorie(s) with '-v' in the name."
    echo "For each one, you will be asked whether to move its contents to the current folder."
    echo

    # Global variable that, when set to "yes", skips further prompting.
    ALL_CHOICE=""

    for src in "${dirs[@]}"; do
        # Remove leading "./" for a cleaner display
        display_src="${src#./}"

        # Determine action based on global choice or interactive prompt
        if [[ -z "$ALL_CHOICE" ]]; then
            if prompt_user "$display_src"; then
                action="yes"
            else
                action="no"
            fi
        elif [[ "$ALL_CHOICE" == "yes" ]]; then
            action="yes"
        else
            # This case should not occur, but handle defensively
            action="no"
        fi

        if [[ "$action" == "yes" ]]; then
            process_directory "$src"
        else
            echo "⏭️  Skipping '$display_src'."
        fi
        echo   # blank line for readability
    done

    echo "All done."
}

# -----------------------------------------------------------------------------
# Run the main function
# -----------------------------------------------------------------------------
main;

echo "$0 exit..."
