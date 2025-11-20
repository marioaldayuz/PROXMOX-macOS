#!/bin/bash
#
# dependency-installer.sh - Package dependency management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script manages installation of required packages and dependencies.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Dependency installer for jq JSON processor required for parsing Proxmox API responses
# Checks if jq is already available in PATH before attempting installation
# Used extensively for extracting storage paths and parsing SMBIOS JSON files
# Automatically updates apt cache if installation is needed
ensure_jq_dependency() {
  local logfile="${LOGDIR}/jq-dependency.log"
  if ! command -v jq >/dev/null 2>&1; then
    display_and_log "Installing jq..." "$logfile"
    apt-get update >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
    apt-get install -y jq >>"$logfile" 2>&1 || log_and_exit "Failed to install jq" "$logfile"
  fi
}

# Dependency installer for xmlstarlet XML manipulation toolkit
# Required for reading and modifying OpenCore config.plist files programmatically
# Enables XPath-based queries and updates to nested plist dictionary structures
# Only installs if not already present in the system
ensure_xmlstarlet_dependency() {
  local logfile="${LOGDIR}/xmlstarlet-dependency.log"
  if ! command -v xmlstarlet >/dev/null 2>&1; then
    display_and_log "Installing xmlstarlet..." "$logfile"
    apt-get update >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
    apt-get install -y xmlstarlet >>"$logfile" 2>&1 || log_and_exit "Failed to install xmlstarlet" "$logfile"
  fi
}

# Dependency installer for binary encoding utilities needed for ROM address manipulation
# base64: Encodes/decodes binary data for plist storage compatibility
# xxd: Converts between hexadecimal and binary representations
# These tools are essential for properly formatting MAC addresses in OpenCore config
# Falls back gracefully if installation fails, allowing base64-only operation
ensure_base64_xxd_dependency() {
  local logfile="${LOGDIR}/base64-xxd-dependency.log"
  if ! command -v base64 >/dev/null || ! command -v xxd >/dev/null; then
    display_and_log "Installing base64 and xxd..." "$logfile"
    apt-get update >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
    apt-get install -y coreutils xxd vim-common >>"$logfile" 2>&1 || display_and_log "Failed to install base64 and xxd. Editing ROM in base64 format." "$logfile"
  fi
}

# Install all required dependencies at once
# This is a convenience function that can be called during initialization
ensure_all_dependencies() {
  ensure_jq_dependency
  ensure_xmlstarlet_dependency
  ensure_base64_xxd_dependency
}

# Export functions for use in other scripts
export -f ensure_jq_dependency
export -f ensure_xmlstarlet_dependency
export -f ensure_base64_xxd_dependency
export -f ensure_all_dependencies

