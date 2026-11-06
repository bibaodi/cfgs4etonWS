#!/bin/bash
#
# runner.sh — reusable wrapper for long-running GPU jobs.
#
# Usage:
#   ./runner.sh jobs/<name>.sh
#
# A job file defines:
#   JOB_NAME        (required)  short label for logs
#   JOB_LOG_PREFIX  (required)  log basename, e.g. "yolo_train"
#   JOB_CONDA_ENV   (optional)  conda env to activate; "" to skip
#   JOB_WORKDIR     (optional)  directory to cd into;    "" to skip
#   JOB_GPU_INDEX   (optional)  GPU to wait for;         "" to skip wait
#   JOB_COMMAND     (required)  array: command to run under inhibitor
#   JOB_PRE()       (optional)  runs after setup, before inhibitor
#   JOB_POST()      (optional)  runs after inhibitor, before cleanup
#
# Guarantees:
#   * Timestamped log lines on stdout (visible via `at`/cron mail).
#   * GNOME auto-suspend disabled on entry, restored on ANY exit.
#   * systemd-inhibit blocks sleep+idle while JOB_COMMAND runs.
#   * INT/TERM/HUP reuse the same cleanup path as normal exit.

set -eo pipefail


# =========================================================================
# Logging
# =========================================================================

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }


# =========================================================================
# Job contract (defaults; job file overrides)
# =========================================================================

_SCRIPT_NAME="$(basename "$0")"

JOB_NAME=""
JOB_LOG_PREFIX=""
JOB_CONDA_ENV=""
JOB_WORKDIR=""
JOB_GPU_INDEX=""
declare -a JOB_COMMAND=()

# Runtime state
_JOB_LOG=""
_ORIG_GS=()
_GNOME_SAVED=0


# =========================================================================
# The missing function — wrap any command under systemd-inhibit
# =========================================================================

run_inhibited() {
    if command -v systemd-inhibit >/dev/null 2>&1; then
        systemd-inhibit \
            --what=sleep:idle \
            --who="${JOB_NAME:-$_SCRIPT_NAME}" \
            --why="Prevent auto-suspend during long-running job" \
            "$@"
    else
        log "systemd-inhibit not found -- running without it." >&2
        "$@"
    fi
}


# =========================================================================
# Environment
# =========================================================================

setup_environment() {
    if [[ -n "$JOB_CONDA_ENV" ]]; then
        export PATH="/mnt/datas/miniconda3/bin:$PATH"
        set +u
        source "$(conda info --base)/etc/profile.d/conda.sh"
        conda activate "$JOB_CONDA_ENV"
        set -u
        log "Using python: $(command -v python)"
        python --version
    fi

    if [[ -n "$JOB_WORKDIR" ]]; then
        cd "$JOB_WORKDIR" || { log_err "cannot cd to $JOB_WORKDIR"; exit 1; }
    fi
}


# =========================================================================
# GPU wait
# =========================================================================

wait_for_gpu() {
    [[ -n "$JOB_GPU_INDEX" ]] || return 0
    command -v nvidia-smi >/dev/null || { log_err "nvidia-smi not found"; exit 1; }

    log "Waiting for GPU ${JOB_GPU_INDEX} to be free of Python processes ..."
    while nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null \
          | grep -q "python"; do
        sleep 30
    done
    log "GPU is free."
}


# =========================================================================
# GNOME power management (best effort; needs an active session bus)
# =========================================================================

gnome_power_available() {
    command -v gsettings >/dev/null 2>&1 \
        && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]
}

_save_gnome_setting() {
    local schema="$1" key="$2" val
    val=$(gsettings get "$schema" "$key" 2>/dev/null) || return 0
    [[ -n "$val" ]] && _ORIG_GS+=("${schema}|${key}|${val}")
    return 0
}

disable_gnome_auto_suspend() {
    if ! gnome_power_available; then
        log "gsettings/DBus unavailable -- skipping GNOME power tweaks."
        log "   (systemd-inhibit will still block auto-suspend.)"
        return 0
    fi

    local gs_power="org.gnome.settings-daemon.plugins.power"
    local gs_session="org.gnome.desktop.session"

    log "Saving current GNOME power settings ..."
    _save_gnome_setting "$gs_power"   sleep-inactive-ac-timeout
    _save_gnome_setting "$gs_power"   sleep-inactive-ac-type
    _save_gnome_setting "$gs_power"   sleep-inactive-battery-timeout
    _save_gnome_setting "$gs_power"   sleep-inactive-battery-type
    _save_gnome_setting "$gs_session" idle-delay
    _GNOME_SAVED=1

    log "Disabling GNOME auto-suspend ..."
    gsettings set "$gs_power"   sleep-inactive-ac-type      'nothing' 2>/dev/null || true
    gsettings set "$gs_power"   sleep-inactive-ac-timeout   0         2>/dev/null || true
    gsettings set "$gs_power"   sleep-inactive-battery-type 'nothing' 2>/dev/null || true
    gsettings set "$gs_power"   sleep-inactive-battery-timeout 0      2>/dev/null || true
    gsettings set "$gs_session" idle-delay                  0         2>/dev/null || true
}

restore_gnome_power_settings() {
    [[ "$_GNOME_SAVED" -eq 1 ]]   || return 0
    [[ ${#_ORIG_GS[@]} -gt 0 ]]   || { _GNOME_SAVED=0; return 0; }

    log "Restoring original GNOME power settings ..."
    local entry schema key val
    for entry in "${_ORIG_GS[@]}"; do
        IFS='|' read -r schema key val <<< "$entry"
        gsettings set "$schema" "$key" "$val" 2>/dev/null || true
    done
    _GNOME_SAVED=0
    _ORIG_GS=()
}


# =========================================================================
# Job execution
# =========================================================================

run_job() {
    _JOB_LOG="$HOME/${JOB_LOG_PREFIX}_$(date +%Y%m%d_%H%M%S).log"
    log "Job log: $_JOB_LOG"

    if declare -F JOB_PRE >/dev/null; then
        log "Running JOB_PRE ..."
        JOB_PRE
    fi

    log "Running JOB_COMMAND under systemd-inhibit ..."
    local rc=0
    run_inhibited "${JOB_COMMAND[@]}" >"$_JOB_LOG" 2>&1 || rc=$?

    if declare -F JOB_POST >/dev/null; then
        log "Running JOB_POST ..."
        JOB_POST
    fi

    if [[ $rc -ne 0 ]]; then
        log_err "Job failed (rc=$rc). Log: $_JOB_LOG"
        return "$rc"
    fi

    log "Job finished successfully. Log: $_JOB_LOG"
    return 0
}


# =========================================================================
# Cleanup / signal handling
# =========================================================================

_cleanup_exit() {
    local rc="$1"
    trap - EXIT INT TERM HUP
    restore_gnome_power_settings || true
    exit "$rc"
}


# =========================================================================
# Validation
# =========================================================================

_validate_job_contract() {
    local missing=()
    [[ -n "$JOB_NAME"              ]] || missing+=("JOB_NAME")
    [[ -n "$JOB_LOG_PREFIX"        ]] || missing+=("JOB_LOG_PREFIX")
    [[ ${#JOB_COMMAND[@]} -gt 0    ]] || missing+=("JOB_COMMAND (non-empty array)")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err "job file missing required fields: ${missing[*]}"
        exit 2
    fi
}


# =========================================================================
# Main
# =========================================================================

main() {
    trap '_cleanup_exit $?'  EXIT
    trap '_cleanup_exit 130' INT
    trap '_cleanup_exit 143' TERM
    trap '_cleanup_exit 129' HUP

    local job_file="${1:-}"
    [[ -n "$job_file" ]] || { log_err "usage: $0 <job-file>"; exit 2; }
    [[ -f "$job_file" ]] || { log_err "job file not found: $job_file"; exit 2; }

    # shellcheck source=/dev/null
    source "$job_file"

    _validate_job_contract
    log "==== START ${JOB_NAME} ===="

    setup_environment
    wait_for_gpu
    disable_gnome_auto_suspend

    local rc=0
    run_job || rc=$?

    if [[ $rc -ne 0 ]]; then
        exit "$rc"
    fi
    log "==== END ${JOB_NAME} ===="
}

main "$@"
