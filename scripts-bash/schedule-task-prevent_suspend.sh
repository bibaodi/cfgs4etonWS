#!/bin/bash
#
# YOLO26 training wrapper.
#
# Responsibilities:
#   * Activate the conda environment.
#   * Wait for a GPU to be free of Python processes.
#   * Temporarily disable auto-suspend while training runs:
#       - Save GNOME power settings and set them to "never".
#       - Run training under `systemd-inhibit` (blocks sleep + idle).
#   * Restore the original GNOME power settings on exit (any reason).
#
# Usable interactively, or via `at` / cron.
# echo '/home/eton/00-srcs/ml_dl2linkNet/schedule-train-plaque320.v3.sh' | at 18:00 today -m


set -eo pipefail


# =========================================================================
# Global state
# =========================================================================

_SCRIPT_NAME="$(basename "$0")"

# -- Paths / inputs (filled in by define_paths)
_baseWeight=""
_ds=""

# -- Training
_GPU_INDEX=0
_TRAIN_LOG=""

# -- GNOME power management
_ORIG_GS=()          # entries: "schema|key|value"
_GNOME_SAVED=0       # 1 = originals saved and need restoring


# =========================================================================
# Logging
# =========================================================================

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }


# =========================================================================
# Environment
# =========================================================================

setup_environment() {
    # Make conda findable from `at`'s minimal PATH.
    export PATH="/mnt/datas/miniconda3/bin:$PATH"

    # Conda's (de)activation scripts are not `set -u` safe:
    # disable nounset while conda runs, then re-enable it.
    set +u
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate trainLinkNet18_env
    set -u

    log "Using python: $(command -v python)"
    python --version

    cd "$HOME/00-srcs/ml_dl2linkNet" || {
        log_err "cannot cd to project dir"
        exit 1
    }
}


# =========================================================================
# Paths & input validation
# =========================================================================

define_paths() {
    local basemodel_home="/mnt/datas/42workspace/34-pj_ML_data_models_UltrasoundIntelligence/44-ML.Models/32-carotidPlaque/26-trainWithV9.1-full/260812.model_segCAPlaque_22yl26_S256-v03/model_segCAPlaque_yolo26n-seg_260812T1116/weights"
    local basemodel_name="model_segCAPlaque_22yl26_S256-v03.pt"

    _baseWeight="${basemodel_home}/${basemodel_name}"
    _ds="/train/data/carotidplaque_yolo_v9.1full/dataset.yaml"
}

validate_inputs() {
    [[ -f "$_baseWeight" ]] || { log_err "weights not found: $_baseWeight"; exit 1; }
    [[ -f "$_ds" ]]         || { log_err "dataset yaml not found: $_ds";  exit 1; }
}


# =========================================================================
# GPU availability
# =========================================================================

wait_for_gpu() {
    command -v nvidia-smi >/dev/null || { log_err "nvidia-smi not found"; exit 1; }

    log "Waiting for GPU ${_GPU_INDEX} to be free of Python processes ..."
    # Conservative check: bail only when no Python process is on any GPU.
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

# Append current value of (schema, key) to _ORIG_GS.
# Silently ignores settings the running GNOME doesn't expose.
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
    [[ "$_GNOME_SAVED" -eq 1 ]]       || return 0
    [[ ${#_ORIG_GS[@]} -gt 0 ]]       || { _GNOME_SAVED=0; return 0; }

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
# Training
# =========================================================================

run_training() {
    _TRAIN_LOG="$HOME/yolo_train_$(date +%Y%m%d_%H%M%S).log"
    log "Training log: $_TRAIN_LOG"

    local train_cmd=(
        python yolo26_seg/train_yolo26.py
        --img_size 320
        --batch    50
        --epochs   100
        --data     "$_ds"
        --no_cache
        --patience 0
        --workers  4
        --device   "$_GPU_INDEX"
        --resume   "$_baseWeight"
        --finetune
    )

    # systemd-inhibit blocks sleep+idle while the command runs and
    # releases the lock automatically on exit.
    if command -v systemd-inhibit >/dev/null 2>&1; then
        log "Running training under systemd-inhibit (sleep+idle blocked) ..."
        systemd-inhibit \
            --what=sleep:idle \
            --who="YOLO training ($_SCRIPT_NAME)" \
            --why="Prevent auto-suspend during model training" \
            "${train_cmd[@]}" >"$_TRAIN_LOG" 2>&1
    else
        log "systemd-inhibit not found -- running training without inhibitor."
        "${train_cmd[@]}" >"$_TRAIN_LOG" 2>&1
    fi
}


# =========================================================================
# Cleanup / signal handling
# =========================================================================

_cleanup_exit() {
    local rc="$1"
    trap - EXIT INT TERM HUP            # prevent re-entry on signal storms
    restore_gnome_power_settings || true
    exit "$rc"
}


# =========================================================================
# Main
# =========================================================================

main() {
    log "==== START ${_SCRIPT_NAME} ===="

    trap '_cleanup_exit $?'  EXIT
    trap '_cleanup_exit 130' INT
    trap '_cleanup_exit 143' TERM
    trap '_cleanup_exit 129' HUP

    setup_environment
    define_paths
    validate_inputs
    wait_for_gpu
    disable_gnome_auto_suspend

    # NOTE: `set -e` is disabled inside run_training because it is called
    # in an `if` condition. This is intentional: we want to log the log
    # path and propagate the real exit code ourselves.
    if run_training; then
        log "Training finished successfully. Log: $_TRAIN_LOG"
    else
        local rc=$?
        log_err "Training failed (rc=$rc). Log: $_TRAIN_LOG"
        exit "$rc"
    fi

    log "==== END ${_SCRIPT_NAME} ===="
}

main "$@"
