#!/bin/bash
#
# logging.sh - Enhanced logging utilities for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides enhanced logging functionality with multiple log levels.
# Source this file: source "${SCRIPT_DIR}/scripts/lib/logging.sh"
#

# Source config to get MAIN_LOG and LOGDIR
if [[ -z "$SCRIPT_DIR" ]]; then
  SCRIPT_DIR="/root/PROXMOX-macOS"
fi
if [[ -z "$MAIN_LOG" ]]; then
  MAIN_LOG="${SCRIPT_DIR}/logs/main.log"
fi

# Unified output function that simultaneously displays messages to console and appends to log files
# Ensures all user-facing messages are captured with timestamps for troubleshooting
# Parameters:
#   $1 - The message text to display and log
#   $2 - Optional path to a specific log file for operation-specific logging
display_and_log() {
  local message="$1"
  local specific_logfile="$2"
  echo "$message"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$MAIN_LOG"
  if [[ -n "$specific_logfile" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$specific_logfile"
  fi
}

# Critical error handler that logs failure message and terminates script execution
# Provides consistent error reporting across all functions with proper log file routing
# Parameters:
#   $1 - Human-readable error message describing the failure
#   $2 - Path to specific log file for detailed error context
# Always exits with status code 1 to indicate failure to calling processes
log_and_exit() {
  local message=$1
  local logfile=$2
  display_and_log "$message" "$logfile"
  exit 1
}

# Log message with INFO level
log_info() {
  local message="$1"
  local logfile="${2:-$MAIN_LOG}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $message" >> "$logfile"
}

# Log message with WARNING level
log_warn() {
  local message="$1"
  local logfile="${2:-$MAIN_LOG}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $message" >> "$logfile"
}

# Log message with ERROR level
log_error() {
  local message="$1"
  local logfile="${2:-$MAIN_LOG}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $message" >> "$logfile"
}

# Export functions for use in other scripts
export -f display_and_log
export -f log_and_exit
export -f log_info
export -f log_warn
export -f log_error

