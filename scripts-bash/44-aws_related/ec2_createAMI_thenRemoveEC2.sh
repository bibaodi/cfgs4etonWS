#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script: ec2_ami_backup.sh
# Description: Create an AMI from an EC2 instance, wait for it to become
#              available, then optionally terminate the instance and delete
#              its EBS volumes. Destructive actions require --yes.
# Usage: ec2_ami_backup.sh --instance-id ID --ami-name NAME [options]
# Author: Senior Bash Developer
# Date: 2026-11-09
# =============================================================================
_history='bash ./ec2_createAMI_thenRemoveEC2.sh --instance-id i-06617d68551404163 --ami-name "webusis.ub18-bkup-$(date +%y%m%dt%H%M%S)" --region cn-north-1 --yes'
echo "eton run history:${_history}"
# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly LOG_BASE_NAME="ec2_ami_backup"
readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly AMI_WAIT_TIMEOUT="${AMI_WAIT_TIMEOUT:-3600}"
readonly AMI_WAIT_INTERVAL="${AMI_WAIT_INTERVAL:-30}"
readonly VOLUME_WAIT_TIMEOUT="${VOLUME_WAIT_TIMEOUT:-300}"
readonly VOLUME_WAIT_INTERVAL="${VOLUME_WAIT_INTERVAL:-10}"

# Runtime defaults
INSTANCE_ID=""
AMI_NAME=""
REGION=""
LOG_FILE=""
YES=false

# Internal state
CLEANED_UP=false
FATAL_LOGGED=false
LOG_TTY=0
LOG_COLOURED=0
[[ -t 2 ]] && LOG_TTY=1
[[ "$LOG_TTY" -eq 1 && -z "${NO_COLOR:-}" ]] && LOG_COLOURED=1

# -----------------------------------------------------------------------------
# Logging (google-glog format). Log output goes to stderr; stdout is data.
# -----------------------------------------------------------------------------

# emit: render one glog-format line to stderr (tee'd to the log file).
# Caller file/line are passed explicitly by the log_* wrappers below.
emit() {
    local level="$1"
    local caller_file="$2"
    local caller_line="$3"
    shift 3
    local msg="$*"

    local timestamp
    timestamp="$(date '+%m%d %H:%M:%S.%6N')"
    local thread_id="$$"
    local short_file="${caller_file##*/}"
    local line="${level}${timestamp} ${thread_id} ${short_file}:${caller_line}] ${msg}"

    local colour=""
    case "$level" in
        I) colour="$BLUE" ;;
        W) colour="$YELLOW" ;;
        E|F) colour="$RED" ;;
    esac
    [[ "$LOG_COLOURED" -eq 0 ]] && colour=""

    printf '%b%s%b\n' "$colour" "$line" "$NC" >&2

    if [[ "$level" == "F" ]]; then
        exit 1
    fi
}

log_info()    { emit "I" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_warn()    { emit "W" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_error()   { emit "E" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_fatal()   { FATAL_LOGGED=true; emit "F" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }

# print_important: green banner on stdout for start/end; also logged as [IMPORTANT].
print_important() {
    local msg="$*"
    if [[ "$LOG_COLOURED" -eq 0 ]] || [[ ! -t 1 ]]; then
        printf '==> %s\n' "$msg"
    else
        printf '%b==> %s%b\n' "$GREEN" "$msg" "$NC"
    fi
    log_info "[IMPORTANT] $msg"
}

# -----------------------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------------------

# init_logging: create the log file, then tee all stderr (ours and the AWS CLI's
# own error output) into it. Colour codes are stripped when they would be
# present, so the file stays clean ASCII for interactive runs too.
init_logging() {
    local ts
    ts="$(date '+%y%m%dt%H%M%S')"

    if [[ -z "$LOG_FILE" ]]; then
        local log_dir="${HOME}/.ec2-backup-logs"
        mkdir -p "$log_dir" || log_fatal "Failed to create log directory: $log_dir"
        LOG_FILE="${log_dir}/${LOG_BASE_NAME}${ts}.log"
    else
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir" \
            || log_fatal "Failed to create log directory: $log_dir"
    fi

    touch "$LOG_FILE" || log_fatal "Failed to create log file: $LOG_FILE"

    if [[ "$LOG_COLOURED" -eq 1 ]]; then
        local esc=$'\x1b'
        exec 2> >(tee >(sed -u "s/${esc}\\[[0-9;]*m//g" >> "$LOG_FILE") >&2)
    else
        exec 2> >(tee -a "$LOG_FILE" >&2)
    fi
}

# check_commands: verify external commands used by this script exist.
check_commands() {
    local cmds=("aws" "date" "mkdir" "touch" "dirname" "tee")
    [[ "$LOG_COLOURED" -eq 1 ]] && cmds+=("sed")

    local cmd
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_fatal "Required command not found: $cmd"
        fi
    done
}

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

# usage: print help text to stdout.
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Create an AMI from an EC2 instance, wait for it to become available, then
optionally terminate the instance and delete its EBS volumes. Destructive
actions require --yes.

Options:
  --instance-id ID      EC2 instance ID (required)
  --ami-name NAME       Name for the new AMI (required)
  --region REGION       AWS region (default: from AWS config)
  --log-file PATH       Log file path (default: auto-generated under ~/.ec2-backup-logs)
  --yes                 Confirm destructive actions (terminate instance,
                        delete volumes)
  -h, --help            Show this help message

Example:
  $SCRIPT_NAME --instance-id i-06617d68551404163 \\
               --ami-name "debian13-backup-\$(date +%y%m%d)" --yes
EOF
}

# parse_args: parse command-line options. Exit 2 on usage error.
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --instance-id)
                [[ -z "${2:-}" || "$2" == -* ]] \
                    && { log_error "--instance-id requires a value"; usage; exit 2; }
                INSTANCE_ID="$2"; shift 2 ;;
            --ami-name)
                [[ -z "${2:-}" || "$2" == -* ]] \
                    && { log_error "--ami-name requires a value"; usage; exit 2; }
                AMI_NAME="$2"; shift 2 ;;
            --region)
                [[ -z "${2:-}" || "$2" == -* ]] \
                    && { log_error "--region requires a value"; usage; exit 2; }
                REGION="$2"; shift 2 ;;
            --log-file)
                [[ -z "${2:-}" || "$2" == -* ]] \
                    && { log_error "--log-file requires a value"; usage; exit 2; }
                LOG_FILE="$2"; shift 2 ;;
            --yes) YES=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; usage; exit 2 ;;
        esac
    done

    if [[ -z "$INSTANCE_ID" ]]; then
        log_error "--instance-id is required"
        usage
        exit 2
    fi
    if [[ -z "$AMI_NAME" ]]; then
        log_error "--ami-name is required"
        usage
        exit 2
    fi
}

# aws_cmd: invoke aws with an optional --region prefix.
aws_cmd() {
    if [[ -n "$REGION" ]]; then
        aws --region "$REGION" "$@"
    else
        aws "$@"
    fi
}

# -----------------------------------------------------------------------------
# Workflow
# -----------------------------------------------------------------------------

# get_volume_ids: print volume IDs for an instance (text output, may be "None").
get_volume_ids() {
    local instance_id="$1"
    aws_cmd ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' \
        --output text
}

# create_ami: register an AMI and print only its ID to stdout.
# --no-reboot yields a crash-consistent image; stop the instance first if you
# need application consistency.
create_ami() {
    local ami_id=""
    if ! ami_id=$(aws_cmd ec2 create-image \
            --instance-id "$INSTANCE_ID" \
            --name "$AMI_NAME" \
            --no-reboot \
            --query 'ImageId' \
            --output text 2>&1); then
        log_error "Failed to create AMI from $INSTANCE_ID: $ami_id"
        return 1
    fi
    if [[ -z "$ami_id" || "$ami_id" == "None" ]]; then
        log_error "AMI creation returned an empty ImageId"
        return 1
    fi
    printf '%s\n' "$ami_id"
}

# wait_for_ami: poll until available; fail fast on 'failed'/'error'.
wait_for_ami() {
    local ami_id="$1"
    local waited=0
    local state=""

    log_info "Waiting for AMI $ami_id to become available (timeout: ${AMI_WAIT_TIMEOUT}s)"
    while (( waited < AMI_WAIT_TIMEOUT )); do
        if ! state=$(aws_cmd ec2 describe-images \
                --image-ids "$ami_id" \
                --query 'Images[0].State' \
                --output text 2>&1); then
            log_error "Failed to query state of AMI $ami_id: $state"
            return 1
        fi
        case "$state" in
            available)
                log_info "AMI $ami_id is now available"
                return 0 ;;
            failed|error)
                log_error "AMI $ami_id entered '$state' state"
                return 1 ;;
            *)
                sleep "$AMI_WAIT_INTERVAL"
                waited=$((waited + AMI_WAIT_INTERVAL))
                log_info "AMI $ami_id state: $state (waited ${waited}s)" ;;
        esac
    done
    log_error "Timed out waiting for AMI $ami_id (last state: $state)"
    return 1
}

# terminate_instance: terminate and wait for the 'terminated' state.
terminate_instance() {
    local instance_id="$1"
    log_warn "Terminating instance $instance_id"
    if ! aws_cmd ec2 terminate-instances --instance-ids "$instance_id"; then
        log_error "Failed to terminate instance $instance_id"
        return 1
    fi
    log_info "Waiting for instance $instance_id to terminate"
    if ! aws_cmd ec2 wait instance-terminated --instance-ids "$instance_id"; then
        log_error "Instance $instance_id did not reach 'terminated' state"
        return 1
    fi
    log_info "Instance $instance_id terminated"
}

# delete_volume: wait until deletable, then delete. Treats AWS DeleteOnTermination
# (deleting/deleted/InvalidVolume.NotFound) as success. Discriminates real errors.
delete_volume() {
    local vol_id="$1"
    local waited=0
    local state=""

    while (( waited < VOLUME_WAIT_TIMEOUT )); do
        if ! state=$(aws_cmd ec2 describe-volumes \
                --volume-ids "$vol_id" \
                --query 'Volumes[0].State' \
                --output text 2>&1); then
            if [[ "$state" == *"InvalidVolume.NotFound"* ]]; then
                log_info "Volume $vol_id no longer exists (already deleted by AWS)"
                return 0
            fi
            log_error "Failed to describe volume $vol_id: $state"
            return 1
        fi
        case "$state" in
            deleted|deleting)
                log_info "Volume $vol_id is being deleted by AWS (DeleteOnTermination)"
                return 0 ;;
            available)
                log_warn "Deleting detached volume $vol_id"
                if ! aws_cmd ec2 delete-volume --volume-id "$vol_id"; then
                    log_error "Failed to delete volume $vol_id"
                    return 1
                fi
                log_info "Volume $vol_id deleted"
                return 0 ;;
            in-use)
                sleep "$VOLUME_WAIT_INTERVAL"
                waited=$((waited + VOLUME_WAIT_INTERVAL)) ;;
            *)
                log_warn "Volume $vol_id state '$state'; waiting"
                sleep "$VOLUME_WAIT_INTERVAL"
                waited=$((waited + VOLUME_WAIT_INTERVAL)) ;;
        esac
    done
    log_error "Timed out waiting for volume $vol_id to become deletable (last state: $state)"
    return 1
}

# delete_volumes: delete a list of volumes, aggregating failures.
delete_volumes() {
    local -a volume_ids=("$@")
    if (( ${#volume_ids[@]} == 0 )); then
        log_info "No EBS volumes to delete"
        return 0
    fi
    local vol_id failures=0
    for vol_id in "${volume_ids[@]}"; do
        delete_volume "$vol_id" || failures=$((failures + 1))
    done
    if (( failures > 0 )); then
        log_error "Failed to delete $failures volume(s)"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Teardown
# -----------------------------------------------------------------------------

# cleanup: EXIT trap. Guards against double fire, suppresses the duplicate
# "Script exited" line when log_fatal already emitted the cause, and drains
# the tee/sed cascade by closing fd 2 and waiting for the orphans.
cleanup() {
    local exit_code=$?
    if [[ "$CLEANED_UP" == true ]]; then
        exit "$exit_code"
    fi
    CLEANED_UP=true

    if (( exit_code != 0 )) && [[ "$FATAL_LOGGED" != true ]]; then
        log_error "Script exited with code $exit_code"
    fi

    exec 2>&-      # EOF to tee -> sed flushes -> exits
    wait           # drain the process-substitution children before exit
    exit "$exit_code"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    trap cleanup EXIT

    parse_args "$@"
    check_commands
    init_logging

    print_important "Starting AMI backup for instance $INSTANCE_ID"

    # 1. Resolve volume IDs BEFORE any destructive action.
    local vol_output
    if ! vol_output=$(get_volume_ids "$INSTANCE_ID"); then
        log_fatal "Failed to describe instance $INSTANCE_ID (check ID, region, credentials)"
    fi

    local -a volume_ids=()
    if [[ -n "$vol_output" && "$vol_output" != "None" ]]; then
        IFS=$' \t\n' read -r -d '' -a volume_ids <<< "$vol_output" || true
    fi
    if (( ${#volume_ids[@]} > 0 )); then
        log_info "Associated EBS volumes: ${volume_ids[*]}"
    else
        log_info "Associated EBS volumes: none"
    fi

    # 2. Create the AMI and wait for it to be available.
    local ami_id
    if ! ami_id=$(create_ami); then
        log_fatal "AMI creation failed; aborting before any destructive action"
    fi
    log_info "AMI creation initiated. AMI ID: $ami_id"

    if ! wait_for_ami "$ami_id"; then
        log_fatal "AMI $ami_id did not become available; aborting before any destructive action"
    fi
    print_important "AMI $ami_id created successfully"

    # 3. Optional destructive phase.
    if [[ "$YES" == true ]]; then
        terminate_instance "$INSTANCE_ID" \
            || log_fatal "Instance termination failed"
        delete_volumes "${volume_ids[@]}" \
            || log_fatal "One or more volumes could not be deleted"
        print_important "Instance $INSTANCE_ID and its volumes have been removed"
    else
        log_warn "Instance and volumes were NOT removed; rerun with --yes to enable destructive actions"
    fi

    printf 'AMI_ID=%s\n' "$ami_id" >&2
    print_important "Script completed successfully"
}

main "$@"
