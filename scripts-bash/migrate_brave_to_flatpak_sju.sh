#!/usr/bin/env bash
# ==============================================================================
# migrate_brave_to_flatpak.sh
#
# Migrate Brave browser from APT to Flatpak on Debian/Ubuntu:
#   1. Uninstall (purge) the APT brave-browser + brave-keyring packages
#   2. Install Flatpak if it is missing
#   3. Configure the Flathub remote against a China mirror (USTC by default),
#      with GPG signature verification ENABLED. If an existing flathub remote
#      is broken ("no-gpg-verify"), it is deleted and rebuilt with the
#      official GPG key instead of leaving verification disabled.
#   4. Install (or update) Brave from Flathub
#
# Usage:
#   sudo ./migrate_brave_to_flatpak.sh [OPTIONS]
#
# Options:
#   -y, --yes            Confirm the destructive APT purge step
#   -m, --mirror NAME    ustc (default) | sjtug | official
#   -g, --gpg-key FILE   Import Flathub's GPG key from a local file (offline fallback
#                        for when dl.flathub.org is unreachable)
#   -l, --log-file PATH  Custom log file path
#   -h, --help           Show help and exit
#
# Exit codes: 0 success, 1 runtime failure, 2 usage / confirmation error
# https://chat.mistral.ai/canvas/shared/57fea903-ba01-446e-b7dd-4597a23a6da9
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
readonly FLATHUB_REPO_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
readonly FLATHUB_OFFICIAL_URL="https://dl.flathub.org/repo"
readonly USTC_MIRROR_URL="https://mirrors.ustc.edu.cn/flathub"
readonly SJTUG_MIRROR_URL="https://mirror.sjtu.edu.cn/flathub"
readonly BRAVE_FLATPAK_ID="com.brave.Browser"
readonly BRAVE_APT_PACKAGES=("brave-browser" "brave-keyring")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIRM_YES="false"
MIRROR_NAME="ustc"
GPG_KEY_FILE=""
CUSTOM_LOG_FILE=""
LOG_FILE=""

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' \
             C_BLUE=$'\033[34m' C_RESET=$'\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi

_log() {
    local level="$1"
    shift
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*"
    case "$level" in
        INFO|OK)   printf '%s%s%s\n' "$C_BLUE" "$line" "$C_RESET" ;;
        WARN)      printf '%s%s%s\n' "$C_YELLOW" "$line" "$C_RESET" ;;
        ERROR|FATAL) printf '%s%s%s\n' "$C_RED" "$line" "$C_RESET" >&2 ;;
    esac
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$line" >> "$LOG_FILE"
    fi
}

log_info()  { _log INFO   "$@"; }
log_ok()    { _log OK     "$@"; }
log_warn()  { _log WARN   "$@"; }
log_error() { _log ERROR  "$@"; }
die()       { _log FATAL  "$@"; exit 1; }

on_exit() {
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        log_ok "Script finished successfully."
    else
        log_error "Script aborted with exit code ${rc}."
    fi
}

init_logging() {
    local timestamp
    timestamp="$(date +%Y%m%dT%H%M%S)"
    if [[ -n "$CUSTOM_LOG_FILE" ]]; then
        LOG_FILE="$CUSTOM_LOG_FILE"
    else
        LOG_FILE="${SCRIPT_DIR}/logs/brave_migration_${timestamp}.log"
    fi
    local log_parent
    log_parent="$(dirname "$LOG_FILE")"
    if [[ ! -d "$log_parent" ]]; then
        mkdir -p "$log_parent" || {
            printf 'Cannot create log directory: %s\n' "$log_parent" >&2
            exit 1
        }
    fi
    touch "$LOG_FILE" || {
        printf 'Cannot create log file: %s\n' "$LOG_FILE" >&2
        exit 1
    }
    log_info "Logging to: $LOG_FILE"
}

# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo $(basename "${BASH_SOURCE[0]}") [OPTIONS]

Migrate Brave from APT to Flatpak (Debian/Ubuntu):
purge the APT packages, ensure Flatpak is installed, point the Flathub
remote at a China mirror with GPG verification enabled, and install Brave.

Options:
  -y, --yes            Confirm the destructive APT purge step
  -m, --mirror NAME    Mirror to use: ustc (default) | sjtug | official
  -g, --gpg-key FILE   Import Flathub's GPG key from a local file
                       (offline fallback if dl.flathub.org is unreachable)
  -l, --log-file PATH  Custom log file path
  -h, --help           Show this help and exit

Examples:
  sudo $(basename "${BASH_SOURCE[0]}") --yes
  sudo $(basename "${BASH_SOURCE[0]}") --yes --mirror sjtug
  sudo $(basename "${BASH_SOURCE[0]}") --yes --gpg-key ./flathub.gpg
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -y|--yes)
                CONFIRM_YES="true"
                shift
                ;;
            -m|--mirror)
                if [[ -z "${2:-}" ]]; then
                    printf 'Error: --mirror requires a name (ustc|sjtug|official).\n' >&2
                    exit 2
                fi
                case "$2" in
                    ustc|sjtug|official) MIRROR_NAME="$2" ;;
                    *)
                        printf 'Error: unknown mirror "%s" (use ustc|sjtug|official).\n' "$2" >&2
                        exit 2
                        ;;
                esac
                shift 2
                ;;
            -g|--gpg-key)
                if [[ -z "${2:-}" ]]; then
                    printf 'Error: --gpg-key requires a path argument.\n' >&2
                    exit 2
                fi
                GPG_KEY_FILE="$2"
                shift 2
                ;;
            -l|--log-file)
                if [[ -z "${2:-}" ]]; then
                    printf 'Error: --log-file requires a path argument.\n' >&2
                    exit 2
                fi
                CUSTOM_LOG_FILE="$2"
                shift 2
                ;;
            *)
                printf 'Error: unknown option: %s\n' "$1" >&2
                usage
                exit 2
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        printf 'Error: this script must be run as root (use sudo).\n' >&2
        exit 2
    fi
}

check_dependencies() {
    local cmd
    for cmd in apt-get dpkg-query awk; do
        if ! command -v "$cmd" &>/dev/null; then
            die "Required command not found: $cmd (this script targets Debian/Ubuntu)."
        fi
    done
    log_info "All required system commands are available."
}

# ------------------------------------------------------------------------------
# Step 1: remove the APT Brave
# ------------------------------------------------------------------------------
apt_pkg_installed() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'
}

uninstall_apt_brave() {
    local pkgs=()
    local p
    for p in "${BRAVE_APT_PACKAGES[@]}"; do
        if apt_pkg_installed "$p"; then
            pkgs+=("$p")
        fi
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log_info "No APT installation of Brave found (nothing to purge)."
        return 0
    fi

    log_info "Detected APT packages: ${pkgs[*]}"
    if [[ "$CONFIRM_YES" != "true" ]]; then
        log_error "Purging APT Brave is destructive. Re-run with --yes to confirm."
        exit 2
    fi

    log_info "Purging APT packages: ${pkgs[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    local repo_file
    for repo_file in /etc/apt/sources.list.d/brave-browser*; do
        if [[ -f "$repo_file" ]]; then
            log_warn "Removing leftover Brave APT repo file: $repo_file"
            rm -f "$repo_file"
        fi
    done

    log_ok "APT Brave removed."
    log_warn "Old profile kept at ~/.config/BraveSoftware (not migrated)."
    log_warn "Flatpak Brave uses: ~/.var/app/com.brave.Browser/config/BraveSoftware"
}

# ------------------------------------------------------------------------------
# Step 2: ensure Flatpak is installed
# ------------------------------------------------------------------------------
ensure_flatpak_installed() {
    if command -v flatpak &>/dev/null; then
        log_info "Flatpak is already installed ($(flatpak --version))."
        return 0
    fi
    log_info "Flatpak not found. Installing via apt..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y flatpak
    command -v flatpak &>/dev/null || die "Flatpak installation failed."
    log_ok "Flatpak installed."
}

# ------------------------------------------------------------------------------
# Step 3a: check and repair the flathub GPG verification issue
# ------------------------------------------------------------------------------
# Prints the 'flatpak remotes' option text for the system flathub remote
# (e.g. "flathub system" or "flathub system,no-gpg-verify"); empty if absent.
flathub_remote_state() {
    flatpak remotes --system 2>/dev/null | awk '$1 == "flathub"'
}

# Detects and repairs the "no-gpg-verify" problem, then validates the result.
#   - remote missing           -> add it (imports the official GPG key)
#   - remote has no-gpg-verify -> delete and rebuild it with the GPG key
#   - remote already verified   -> nothing to do
# After any change, re-checks 'flatpak remotes' and fails loudly if the remote
# is STILL unverified (e.g. the key download silently failed).
ensure_gpg_verification() {
    local remote_line
    remote_line="$(flathub_remote_state)"

    if [[ -z "$remote_line" ]]; then
        log_info "No system flathub remote found; it will be added."
    elif [[ "$remote_line" != *"no-gpg-verify"* ]]; then
        log_info "Flathub remote exists and is GPG-verified."
        return 0
    else
        log_warn "Detected a broken flathub remote: GPG verification is DISABLED."
        log_warn "This usually comes from 'remote-add' with a bare URL, or from a"
        log_warn "migration script that fell back to --no-gpg-verify. Rebuilding it..."
        log_info "Installed Flatpak apps are kept and re-associate automatically."
        flatpak remote-delete --system --force flathub \
            || die "Failed to delete the broken flathub remote."
    fi

    if [[ -n "$GPG_KEY_FILE" ]]; then
        # Offline fallback: the user provides the Flathub GPG key file
        # (e.g. saved from flathub.flatpakrepo on another machine).
        [[ -f "$GPG_KEY_FILE" ]] || die "GPG key file not found: $GPG_KEY_FILE"
        log_info "Adding flathub remote and importing GPG key from: $GPG_KEY_FILE"
        flatpak remote-add --system --if-not-exists flathub "$FLATHUB_REPO_URL" \
            || die "Failed to add the Flathub remote."
        flatpak remote-modify --system flathub --gpg-import="$GPG_KEY_FILE" \
            || die "Failed to import the GPG key from $GPG_KEY_FILE."
        flatpak remote-modify --system flathub --gpg-verify \
            || die "Failed to enable GPG verification."
    else
        log_info "Adding Flathub remote (imports the official GPG key)..."
        flatpak remote-add --system --if-not-exists flathub "$FLATHUB_REPO_URL" \
            || die "Failed to add the Flathub remote: could not fetch" \
                   "$FLATHUB_REPO_URL. If dl.flathub.org is unreachable, save" \
                   "Flathub's GPG key to a file and re-run with --gpg-key <file>."
    fi

    # Post-fix validation: refuse to continue if still unverified.
    local after
    after="$(flathub_remote_state)"
    if [[ -z "$after" ]]; then
        die "flathub remote is missing after configuration; please investigate."
    elif [[ "$after" == *"no-gpg-verify"* ]]; then
        log_error "The flathub remote STILL has GPG verification disabled."
        log_error "Most likely $FLATHUB_REPO_URL was unreachable, so the GPG"
        log_error "key was never imported."
        log_error "Fix: obtain Flathub's GPG key (the GPG block inside"
        log_error "flathub.flatpakrepo), save it to a file, and re-run:"
        log_error "  sudo $0 --yes --gpg-key ./flathub.gpg"
        exit 1
    fi
    log_ok "Flathub remote is present and GPG-verified."
}

# ------------------------------------------------------------------------------
# Step 3b: configure the Flathub remote (mirror URL + metadata refresh)
# ------------------------------------------------------------------------------
configure_flathub_mirror() {
    local mirror_url
    case "$MIRROR_NAME" in
        ustc)     mirror_url="$USTC_MIRROR_URL" ;;
        sjtug)    mirror_url="$SJTUG_MIRROR_URL" ;;
        official) mirror_url="$FLATHUB_OFFICIAL_URL" ;;
        *)        die "Unknown mirror: $MIRROR_NAME" ;;
    esac

    ensure_gpg_verification

    log_info "Pointing flathub at the '$MIRROR_NAME' endpoint: $mirror_url"
    flatpak remote-modify --system flathub --url="$mirror_url" \
        || die "Failed to set the flathub URL."

    # Refresh metadata. NOTE: there is no 'flatpak remote-refresh' command in
    # flatpak; appstream refresh is done via 'flatpak update --appstream'.
    log_info "Refreshing appstream metadata from the remote..."
    if ! flatpak update --system --appstream flathub >/dev/null 2>&1; then
        log_warn "Appstream refresh failed; it will retry automatically during install."
    fi

    if [[ "$MIRROR_NAME" == "ustc" ]]; then
        log_warn "USTC mirror is a cache: on a cache miss flatpak is redirected"
        log_warn "to flathub.org origin servers, so basic connectivity is still needed."
    fi
    log_ok "Flathub configured (${MIRROR_NAME}: ${mirror_url})."
}

# ------------------------------------------------------------------------------
# Step 4: install or update Brave via Flatpak
# ------------------------------------------------------------------------------
flatpak_brave_installed() {
    flatpak list --system --app | grep -q "$BRAVE_FLATPAK_ID"
}

install_brave_flatpak() {
    if flatpak_brave_installed; then
        log_info "Brave is already installed via Flatpak. Updating..."
        flatpak update --system -y "$BRAVE_FLATPAK_ID" \
            || die "Failed to update Flatpak Brave."
    else
        log_info "Installing Brave ($BRAVE_FLATPAK_ID) from Flathub..."
        flatpak install --system -y flathub "$BRAVE_FLATPAK_ID" \
            || die "Failed to install Flatpak Brave."
    fi
    log_ok "Flatpak Brave is ready: run with 'flatpak run $BRAVE_FLATPAK_ID'."
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"
    init_logging
    trap on_exit EXIT
    require_root
    log_info "Brave migration started (APT -> Flatpak, mirror=${MIRROR_NAME})."
    check_dependencies
    uninstall_apt_brave
    ensure_flatpak_installed
    configure_flathub_mirror
    install_brave_flatpak
    log_ok "Migration complete."
}

main "$@"
