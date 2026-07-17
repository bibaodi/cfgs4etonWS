#!/usr/bin/env bash
# ssh2host.sh: A wrapper to handle mDNS (.local) resolution fallbacks for ssh
# Usage: 
#   ./ssh2host.sh eton@xyzp-Mac-Studio.local
#   ./ssh2host.sh eton@xyzp-Mac-Studio.local -X (extra args are passed to ssh)

set -euo pipefail

# --- Logging Helpers ---
log()  { printf '\033[1;34m[STEP]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }

# --- Function 1: Check current default DNS service ---
check_default_dns_service() {
    log "Step 1: Checking current default DNS/Name resolution service..."
    
    # Show what glibc uses for host resolution
    if [ -f /etc/nsswitch.conf ]; then
        echo "    -> NSS configuration (/etc/nsswitch.conf hosts line):"
        grep -E '^hosts:' /etc/nsswitch.conf | sed 's/^/       /'
    else
        warn "    -> /etc/nsswitch.conf not found."
    fi

    # Check if systemd-resolved is managing DNS
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        echo "    -> systemd-resolved is ACTIVE (acting as default DNS stub)."
        resolvectl status 2>/dev/null | grep -E 'Protocols|Link|mDNS' | head -n 5 | sed 's/^/       /'
    else
        echo "    -> systemd-resolved is not active. Using standard /etc/resolv.conf."
    fi
    echo ""
}

# --- Function 2: Check if name can be correctly resolved by default service ---
resolve_via_default() {
    local hostname="$1"
    log "Step 2: Checking if '$hostname' can be resolved by default service (getent hosts)..."
    
    local ip
    # getent uses the NSS stack (nsswitch.conf), which is what ssh uses internally
    if ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -n1); then
        if [[ -n "$ip" ]]; then
            ok "Default service successfully resolved '$hostname' -> $ip"
            echo "$ip"
            return 0
        fi
    fi
    
    warn "Default service FAILED to resolve '$hostname' (or returned empty)."
    return 1
}

# --- Function 3: Connect using SSH (Success Path) ---
connect_ssh() {
    local user="$1"
    local target="$2"
    shift 2
    local extra_args="$@"
    
    local ssh_target="$target"
    [[ -n "$user" ]] && ssh_target="${user}@${target}"
    
    log "Step 3: Default resolution succeeded. Connecting to $ssh_target..."
    exec ssh "$ssh_target" $extra_args
}

# --- Function 4: Fallback to avahi or other tools, then connect (Failure Path) ---
resolve_via_fallback_and_connect() {
    local user="$1"
    local hostname="$2"
    shift 2
    local extra_args="$@"
    
    log "Step 4: Default resolution failed. Attempting fallback tools (avahi-resolve)..."
    
    if ! command -v avahi-resolve &> /dev/null; then
        err "avahi-resolve command not found. Please install it: sudo apt install avahi-utils"
        exit 1
    fi

    local ip
    # avahi-resolve -n outputs: "hostname \t IP"
    if ip=$(avahi-resolve -n "$hostname" 2>/dev/null | awk '{print $2}'); then
        if [[ -n "$ip" ]]; then
            ok "Avahi successfully resolved '$hostname' -> $ip"
            
            local ssh_target="$ip"
            [[ -n "$user" ]] && ssh_target="${user}@${ip}"
            
            log "Step 4: Connecting to $ssh_target (using resolved IP)..."
            exec ssh "$ssh_target" $extra_args
        fi
    fi

    err "All resolution methods failed for '$hostname'. Cannot connect."
    exit 1
}

# --- Main Execution ---
main() {
    if [ $# -lt 1 ]; then
        err "Usage: $0 [user@]hostname [extra_ssh_args...]"
        err "Example: $0 eton@xyzp-Mac-Studio.local"
        exit 2
    fi

    local target="$1"
    shift
    
    # Parse user@host
    local user=""
    local host="$target"
    if [[ "$target" == *@* ]]; then
        user="${target%%@*}"
        host="${target#*@}"
    fi

    # Step 1
    check_default_dns_service

    # Step 2
    local resolved_ip
    if resolved_ip=$(resolve_via_default "$host"); then
        # Step 3: Success path
        connect_ssh "$user" "$resolved_ip" "$@"
    else
        # Step 4: Failure path
        resolve_via_fallback_and_connect "$user" "$host" "$@"
    fi
}

main "$@"

