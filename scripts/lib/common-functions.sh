#!/bin/bash
#
# common-functions.sh - Shared utility functions for Hackintoshster scripts
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides common functionality for logging, validation, and dependency checks
# Source this file in other scripts: source "$(dirname "$0")/lib/common-functions.sh"
#

# Global log file path (will be set by calling script)
# Default to /tmp if not set, but scripts should set this explicitly
LOG_FILE="${LOG_FILE:-/tmp/hackintoshster-$$.log}"

#
# log_message() - Log a message with timestamp to log file only
# Usage: log_message "Your message here"
# Note: Does NOT echo to console - use echo separately for user-facing messages
#
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true
}

#
# check_status() - Check the exit status of the last command
# Usage: command_here
#        check_status "Error message if command failed"
#
check_status() {
    local exit_code=$?
    local error_message="$1"
    
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR: $error_message (exit code: $exit_code)"
        return $exit_code
    fi
    return 0
}

#
# validate_path() - Check if a file or directory exists
# Usage: validate_path "/path/to/check" "file|dir|any"
# Returns: 0 if valid, 1 if not found or wrong type
#
validate_path() {
    local path="$1"
    local type="${2:-any}"  # file, dir, or any
    
    if [ -z "$path" ]; then
        log_message "ERROR: Path validation called with empty path"
        return 1
    fi
    
    case "$type" in
        file)
            if [ ! -f "$path" ]; then
                log_message "ERROR: File not found: $path"
                return 1
            fi
            ;;
        dir)
            if [ ! -d "$path" ]; then
                log_message "ERROR: Directory not found: $path"
                return 1
            fi
            ;;
        any)
            if [ ! -e "$path" ]; then
                log_message "ERROR: Path not found: $path"
                return 1
            fi
            ;;
        *)
            log_message "ERROR: Invalid validation type: $type"
            return 1
            ;;
    esac
    
    return 0
}

#
# ensure_dependency() - Check if a command or package is available
# Usage: ensure_dependency "command_name" "package_name"
# If package_name is omitted, uses command_name for both
#
ensure_dependency() {
    local command_name="$1"
    local package_name="${2:-$1}"
    
    if ! command -v "$command_name" &> /dev/null; then
        log_message "WARNING: Required command '$command_name' not found"
        return 1
    fi
    
    return 0
}

#
# ensure_root() - Check if script is running as root
# Usage: ensure_root
#
ensure_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR: This script must be run as root"
        return 1
    fi
    return 0
}

#
# create_temp_dir() - Create a temporary directory and return its path
# Usage: temp_dir=$(create_temp_dir "prefix")
#
create_temp_dir() {
    local prefix="${1:-hackintosh}"
    local temp_dir
    
    temp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXXXXXX")
    
    if [ $? -ne 0 ] || [ ! -d "$temp_dir" ]; then
        log_message "ERROR: Failed to create temporary directory"
        return 1
    fi
    
    echo "$temp_dir"
    return 0
}

#
# cleanup_temp_dir() - Remove a temporary directory
# Usage: cleanup_temp_dir "$temp_dir_path"
#
cleanup_temp_dir() {
    local temp_dir="$1"
    
    if [ -z "$temp_dir" ]; then
        log_message "WARNING: cleanup_temp_dir called with empty path"
        return 1
    fi
    
    # Safety check: only delete directories under /tmp
    if [[ "$temp_dir" == /tmp/* ]] && [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir" 2>/dev/null
        return $?
    else
        log_message "WARNING: Refusing to delete directory outside /tmp: $temp_dir"
        return 1
    fi
}

#
# validate_json_file() - Check if a file is valid JSON
# Usage: validate_json_file "/path/to/file.json"
#
validate_json_file() {
    local json_file="$1"
    
    validate_path "$json_file" "file" || return 1
    
    if ! ensure_dependency "jq"; then
        log_message "ERROR: jq is required for JSON validation"
        return 1
    fi
    
    if ! jq empty "$json_file" 2>/dev/null; then
        log_message "ERROR: Invalid JSON file: $json_file"
        return 1
    fi
    
    return 0
}

#
# validate_plist_file() - Check if a file is a valid plist
# Usage: validate_plist_file "/path/to/config.plist"
#
validate_plist_file() {
    local plist_file="$1"
    
    validate_path "$plist_file" "file" || return 1
    
    if ! ensure_dependency "xmlstarlet"; then
        log_message "ERROR: xmlstarlet is required for plist validation"
        return 1
    fi
    
    # Validate XML structure
    local validation_output=$(xmlstarlet val "$plist_file" 2>&1)
    local validation_exit=$?
    
    if [ $validation_exit -ne 0 ]; then
        log_message "ERROR: Invalid plist file: $plist_file"
        log_message "  xmlstarlet validation output: $validation_output"
        echo "  xmlstarlet validation error:" >&2
        echo "$validation_output" | head -5 >&2
        return 1
    fi
    
    return 0
}

# Export functions for use in other scripts
export -f log_message
export -f check_status
export -f validate_path
export -f ensure_dependency
export -f ensure_root
export -f create_temp_dir
export -f cleanup_temp_dir
export -f validate_json_file
export -f validate_plist_file

