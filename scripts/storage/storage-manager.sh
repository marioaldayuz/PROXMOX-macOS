#!/bin/bash
#
# storage-manager.sh - Storage detection and management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script manages storage operations including detection of available storages and ISO storage selection.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Discovers all Proxmox storage volumes capable of hosting VM disk images
# Queries pvesm for active storages with 'images' content type and calculates available space
# Automatically selects the storage with most free space as the default recommendation
# Output format: One line per storage as "name|bytes|GB", followed by default storage name
# Returns: Multi-line output suitable for parsing by calling functions
get_available_storages() {
  local logfile="${LOGDIR}/storage-detection.log"
  local storages=()
  local max_space=0
  local default_storage=""

  local storage_list
  storage_list=$(pvesm status --content images 2>>"$logfile") || log_and_exit "Failed to retrieve storage list" "$logfile"
  while IFS= read -r line; do
    # Skip header line from pvesm output
    [[ "$line" =~ ^Name.* ]] && continue
    read -r storage_name type status total used avail percent <<< "$line"
    # Filter out inactive storages and those with zero or invalid available space
    [[ "$status" != "active" || ! "$avail" =~ ^[0-9]+$ || "$avail" -eq 0 ]] && continue
    # Convert available space from KB to GB with two decimal precision
    local avail_space_gb=$(echo "scale=2; $avail / 1024 / 1024" | bc 2>/dev/null)
    storages+=("$storage_name|$avail|$avail_space_gb")
    # Track storage with maximum available space for default selection
    if [[ $(echo "$avail > $max_space" | bc -l) -eq 1 ]]; then
      max_space=$avail
      default_storage="$storage_name"
    fi
  done <<< "$storage_list"

  [[ ${#storages[@]} -eq 0 || -z "$default_storage" ]] && log_and_exit "No active storages found" "$logfile"
  for storage in "${storages[@]}"; do echo "$storage"; done
  echo "$default_storage"
}

# Enumerates Proxmox storage locations configured to store ISO image files
# Similar to get_available_storages but filters for 'iso' content type instead of 'images'
# Used during initialization to determine where OpenCore and recovery ISOs will be stored
# Output format: One line per storage as "name|bytes|GB", followed by default storage name
# Returns: Multi-line output with storage candidates and automatic default selection
get_available_iso_storages() {
  local logfile="${LOGDIR}/iso-storage-detection.log"
  local storages=()
  local max_space=0
  local default_storage=""

  local storage_list
  storage_list=$(pvesm status --content iso 2>>"$logfile") || log_and_exit "Failed to retrieve ISO storage list" "$logfile"
  while IFS= read -r line; do
    # Skip header line from pvesm status output
    [[ "$line" =~ ^Name.* ]] && continue
    read -r storage_name type status total used avail percent <<< "$line"
    # Only consider active storages with valid available space
    [[ "$status" != "active" || ! "$avail" =~ ^[0-9]+$ || "$avail" -eq 0 ]] && continue
    # Convert KB to human-readable GB format
    local avail_space_gb=$(echo "scale=2; $avail / 1024 / 1024" | bc 2>/dev/null)
    storages+=("$storage_name|$avail|$avail_space_gb")
    # Automatically prefer the storage with most available capacity
    if [[ $(echo "$avail > $max_space" | bc -l) -eq 1 ]]; then
      max_space=$avail
      default_storage="$storage_name"
    fi
  done <<< "$storage_list"

  [[ ${#storages[@]} -eq 0 || -z "$default_storage" ]] && log_and_exit "No active ISO storages found" "$logfile"
  for storage in "${storages[@]}"; do echo "$storage"; done
  echo "$default_storage"
}

# Interactive ISO storage selector that determines where bootloader and recovery images reside
# Presents available ISO-capable storages to user or auto-selects if only one exists
# Queries Proxmox API to resolve storage name to actual filesystem path
# Sets global ISODIR variable pointing to the template/iso subdirectory
# This function must run early in script execution as ISODIR is used throughout
set_isodir() {
  local logfile="${LOGDIR}/iso-storage-detection.log"
  
  # Ensure jq is available for JSON parsing
  if ! command -v jq >/dev/null 2>&1; then
    display_and_log "Installing jq..." "$logfile"
    apt-get update >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
    apt-get install -y jq >>"$logfile" 2>&1 || log_and_exit "Failed to install jq" "$logfile"
  fi
  
  local storage_output=$(get_available_iso_storages) || { display_and_log "Failed to retrieve ISO storages"; read -n 1 -s; return 1; }
  local storages=() default_storage=""
  # Parse multi-line output separating storage entries from default marker
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ -z "$default_storage" && ! "$line" =~ \| ]] && default_storage="$line" || storages+=("$line")
  done <<< "$storage_output"

  if ((${#storages[@]} == 0)); then
    log_and_exit "No ISO storages found" "$logfile"
  fi

  # Skip interactive prompt if only one storage is available
  if ((${#storages[@]} == 1)); then
    storage_iso="${storages[0]%%|*}"
    display_and_log "Using ISO storage: $storage_iso" "$logfile"
  else
    # Present menu of available storages with capacity information
    while true; do
      display_and_log "Available ISO storages:" "$logfile"
      for s in "${storages[@]}"; do
        storage_name="${s%%|*}"
        avail_space="${s##*|}"
        display_and_log "  - $storage_name ($avail_space GB)" "$logfile"
      done
      read -rp "ISO Storage [${default_storage}]: " storage_iso
      storage_iso=${storage_iso:-$default_storage}
      # Validate user input against available storage names
      local valid=false
      for s in "${storages[@]}"; do
        if [[ "$storage_iso" == "${s%%|*}" ]]; then
          valid=true
          break
        fi
      done
      if $valid; then
        display_and_log "Selected ISO storage: $storage_iso" "$logfile"
        break
      else
        display_and_log "Invalid ISO storage. Please try again." "$logfile"
      fi
    done
  fi

  # Resolve storage name to filesystem path via Proxmox API
  local storage_iso_path
  storage_iso_path=$(pvesh get /storage/"${storage_iso}" --output-format json | jq -r '.path') || log_and_exit "Failed to retrieve path for storage $storage_iso" "$logfile"
  [[ -z "$storage_iso_path" ]] && log_and_exit "Storage path for $storage_iso is empty" "$logfile"
  # Construct standard Proxmox ISO directory path
  export ISODIR="${storage_iso_path}/template/iso/"
  export storage_iso="${storage_iso}"
  mkdir -p "$ISODIR" || log_and_exit "Failed to create ISODIR: $ISODIR" "$logfile"
  display_and_log "ISODIR set to: $ISODIR" "$logfile"
}

# Export functions for use in other scripts
export -f get_available_storages
export -f get_available_iso_storages
export -f set_isodir

