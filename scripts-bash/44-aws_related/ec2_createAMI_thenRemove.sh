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

readonly AMI_WAIT_TIMEOUT="${AMI_WAIT_TIMEOUT:-3600}"
readonly AMI_WAIT_INTERVAL="${AMI_WAIT_INTERVAL:-30}"
readonly VOLUME_WAIT_TIMEOUT="${VOLUME_WAIT_TIMEOUT:-300}"
readonly VOLUME_WAIT_INTERVAL="${VOLUME_WAIT_INTERVAL:-10}"

# Defaults (overridden by parse_args)
INSTANCE_ID=""
AMI_NAME=""
REGION=""
LOG_FILE=""
YES=false

# Internal state
CLEANED_UP=false
FATAL_LOGGED=false

# -----------------------------------------------------------------------------
# Logging (google-glog format)
# -----------------------------------------------------------------------------

# emit: render and print one glog-format line to console and log file.
# Arguments: level, caller_file, caller_line, message...
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
    local plain_line="${level}${timestamp} ${thread_id} ${short_file}:${caller_line}] ${msg}"

    local color=""
    local output_fd=1
    case "$level" in
        I) color="${BLUE}";   output_fd=1 ;;
        W) color="${YELLOW}"; output_fd=2 ;;
        E) color="${RED}";    output_fd=2 ;;
        F) color="${RED}";    output_fd=2 ;;
    esac

    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t "$output_fd" ]]; then
        color=""
    fi

    printf '%b%s%b\n' "$color" "$plain_line" "$NC" >&"$output_fd"

    if [[ -n "${LOG_FILE:-}" && -w "${LOG_FILE}" ]]; then
        printf '%s\n' "$plain_line" >>"$LOG_FILE"
    fi

    if [[ "$level" == "F" ]]; then
        exit 1
    fi
}

log_info()    { emit "I" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_warn()    { emit "W" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_error()   { emit "E" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }
log_fatal()   { FATAL_LOGGED=true; emit "F" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$@"; }

# print_important: green start/end banner; plain when not a TTY or NO_COLOR set.
print_important() {
    local msg="$*"
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        printf '%s\n' "$msg"
    else
        printf '%b%s%b\n' "${GREEN}" "$msg" "${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Initialisation and utilities
# -----------------------------------------------------------------------------

# init_logging: create the log directory and log file if needed.
init_logging() {
    local timestamp
    timestamp="$(date '+%y%m%dt%H%M%S')"

    if [[ -z "$LOG_FILE" ]]; then
        local log_dir="${HOME}/.ec2-backup-logs"
        mkdir -p "$log_dir" || log_fatal "Failed to create log directory: $log_dir"
        LOG_FILE="${log_dir}/${LOG_BASE_NAME}${timestamp}.log"
    else
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" || log_fatal "Failed to create log directory: $log_dir"
        fi
    fi

    touch "$LOG_FILE" || log_fatal "Failed to create log file: $LOG_FILE"
    log_info "Logging initialised. Log file: $LOG_FILE"
}

# check_commands: verify external commands used by this script exist.
check_commands() {
    local cmds=("aws" "date" "mkdir" "touch" "dirname")
    local cmd
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_fatal "Required command not found: $cmd"
        fi
    done
}

# usage: print help text.
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

# parse_args: parse command-line options; exit 2 on usage errors.
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --instance-id)
                [[ $# -ge 2 ]] || { log_error "--instance-id requires a value"; usage; exit 2; }
                INSTANCE_ID="$2"; shift 2 ;;
            --ami-name)
                [[ $# -ge 2 ]] || { log_error "--ami-name requires a value"; usage; exit 2; }
                AMI_NAME="$2"; shift 2 ;;
            --region)
                [[ $# -ge 2 ]] || { log_error "--region requires a value"; usage; exit 2; }
                REGION="$2"; shift 2 ;;
            --log-file)
                [[ $# -ge 2 ]] || { log_error "--log-file requires a value"; usage; exit 2; }
                LOG_FILE="$2"; shift 2 ;;
            --yes)
                YES=true; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 2 ;;
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
# Workflow functions
# -----------------------------------------------------------------------------

# get_volume_ids: print volume IDs for an instance (text output).
get_volume_ids() {
    local instance_id="$1"
    aws_cmd ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' \
        --output text 2>>"$LOG_FILE"
}

# create_ami: register an AMI and print its ID to stdout.
# Note: --no-reboot yields a crash-consistent image, not application-consistent.
create_ami() {
    local ami_id
    if ! ami_id=$(aws_cmd ec2 create-image \
            --instance-id "$INSTANCE_ID" \
            --name "$AMI_NAME" \
            --no-reboot \
            --query 'ImageId' \
            --output text 2>>"$LOG_FILE"); then
        log_error "Failed to create AMI from instance $INSTANCE_ID"
        return 1
    fi
    if [[ -z "$ami_id" || "$ami_id" == "None" ]]; then
        log_error "AMI creation returned an empty ImageId"
        return 1
    fi
    printf '%s\n' "$ami_id"
}

# wait_for_ami: poll until the AMI is available, failing fast on 'failed'.
wait_for_ami() {
    local ami_id="$1"
    local waited=0
    local state="unknown"

    log_info "Waiting for AMI $ami_id to become available (timeout: ${AMI_WAIT_TIMEOUT}s)"
    while (( waited < AMI_WAIT_TIMEOUT )); do
        if ! state=$(aws_cmd ec2 describe-images \
                --image-ids "$ami_id" \
                --query 'Images[0].State' \
                --output text 2>>"$LOG_FILE"); then
            log_error "Failed to query state of AMI $ami_id"
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

# terminate_instance: terminate the instance and wait for 'terminated'.
terminate_instance() {
    local instance_id="$1"
    log_warn "Terminating instance $instance_id"
    if ! aws_cmd ec2 terminate-instances --instance-ids "$instance_id" 2>>"$LOG_FILE"; then
        log_error "Failed to terminate instance $instance_id"
        return 1
    fi
    log_info "Waiting for instance $instance_id to terminate"
    if ! aws_cmd ec2 wait instance-terminated --instance-ids "$instance_id" 2>>"$LOG_FILE"; then
        log_error "Instance $instance_id did not reach 'terminated' state"
        return 1
    fi
    log_info "Instance $instance_id terminated"
}

# delete_volume: wait for a volume to be deletable, then delete it.
# Handles DeleteOnTermination by treating deleting/deleted/NotFound as success.
delete_volume() {
    local vol_id="$1"
    local waited=0
    local state=""

    while (( waited < VOLUME_WAIT_TIMEOUT )); do
        if ! state=$(aws_cmd ec2 describe-volumes \
                --volume-ids "$vol_id" \
                --query 'Volumes[0].State' \
                --output text 2>>"$LOG_FILE"); then
            log_info "Volume $vol_id no longer exists (deleted by AWS on termination)"
            return 0
        fi
        case "$state" in
            deleted|deleting)
                log_info "Volume $vol_id is being deleted by AWS (DeleteOnTermination)"
                return 0 ;;
            available)
                log_warn "Deleting detached volume $vol_id"
                if ! aws_cmd ec2 delete-volume --volume-id "$vol_id" 2>>"$LOG_FILE"; then
                    log_error "Failed to delete volume $vol_id"
                    return 1
                fi
                log_info "Volume $vol_id deleted"
                return 0 ;;
            in-use)
                sleep "$VOLUME_WAIT_INTERVAL"
                waited=$((waited + VOLUME_WAIT_INTERVAL)) ;;
            *)
                log_warn "Volume $vol_id in state '$state'; waiting"
                sleep "$VOLUME_WAIT_INTERVAL"
                waited=$((waited + VOLUME_WAIT_INTERVAL)) ;;
        esac
    done
    log_error "Timed out waiting for volume $vol_id to become deletable (last state: $state)"
    return 1
}

# delete_volumes: delete every supplied volume ID, aggregating failures.
delete_volumes() {
    local -a volume_ids=("$@")
    if (( ${#volume_ids[@]} == 0 )); then
        log_info "No EBS volumes to delete"
        return 0
    fi

    local vol_id
    local failures=0
    for vol_id in "${volume_ids[@]}"; do
        if ! delete_volume "$vol_id"; then
            failures=$((failures + 1))
        fi
    done
    if (( failures > 0 )); then
        log_error "Failed to delete $failures volume(s)"
        return 1
    fi
}

# cleanup: trap handler; log unexpected exit once and propagate exit code.
cleanup() {
    local exit_code=$?
    if [[ "$CLEANED_UP" == true ]]; then
        return 0
    fi
    CLEANED_UP=true
    if (( exit_code != 0 )) && [[ "$FATAL_LOGGED" != true ]]; then
        log_error "Script exited with code $exit_code"
    fi
    exit "$exit_code"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    trap cleanup EXIT ERR INT TERM

    parse_args "$@"
    check_commands
    init_logging

    print_important "Starting AMI backup for instance $INSTANCE_ID"

    # Capture volume IDs before any destructive action.
    local vol_output
    if ! vol_output=$(get_volume_ids "$INSTANCE_ID"); then
        log_fatal "Failed to describe instance $INSTANCE_ID; verify the ID, region, and credentials"
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

    # Create the AMI and wait for it to become available.
    log_info "Creating AMI '$AMI_NAME' from instance $INSTANCE_ID"
    local ami_id
    if ! ami_id=$(create_ami); then
        log_fatal "AMI creation failed; aborting before any destructive action"
    fi
    log_info "AMI creation initiated. AMI ID: $ami_id"

    if ! wait_for_ami "$ami_id"; then
        log_fatal "AMI $ami_id did not become available; aborting before any destructive action"
    fi
    print_important "AMI $ami_id created successfully"

    # Optional destructive phase.
    if [[ "$YES" == true ]]; then
        terminate_instance "$INSTANCE_ID" || log_fatal "Instance termination failed"
        if (( ${#volume_ids[@]} > 0 )); then
            delete_volumes "${volume_ids[@]}" || log_fatal "One or more volumes could not be deleted"
        else
            log_info "No volumes to delete"
        fi
        print_important "Instance $INSTANCE_ID and its volumes have been removed"
    else
        log_warn "Instance and volumes were NOT removed; rerun with --yes to enable destructive actions"
    fi

    print_important "Script completed successfully"
}

main "$@"
