#!/bin/bash
#
# validation.sh - Validation utilities for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides validation functions for user inputs and system state.
# Source this file: source "${SCRIPT_DIR}/scripts/lib/validation.sh"
#

# Input validator for VM naming conventions enforced by Proxmox
# Ensures names start/end with alphanumeric characters and contain only safe characters
# Prevents whitespace which can cause issues in shell scripts and Proxmox API calls
# Parameters: $1 - Proposed VM name string
# Returns: 0 if valid, 1 if invalid (contains spaces or invalid characters)
validate_vm_name() {
  local vm_name=$1
  [[ "$vm_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*[a-zA-Z0-9]$ && ! "$vm_name" =~ [[:space:]] ]]
}

# Validate if a bridge number is available (doesn't exist yet)
# Parameters: $1 - Bridge number
# Returns: 0 if available, 1 if already exists
validate_bridge_available() {
  local bridge_num=$1
  [[ "$bridge_num" =~ ^[0-9]+$ ]] || return 1
  
  if [[ -d "/sys/class/net/vmbr$bridge_num" || \
        -n $(grep -h "^iface vmbr$bridge_num" "$NETWORK_INTERFACES_FILE" 2>/dev/null) ]]; then
    return 1  # Bridge exists
  fi
  return 0  # Bridge doesn't exist
}

# Validate subnet in CIDR notation
# Parameters: $1 - Subnet (e.g., "10.27.1.0/24")
# Returns: 0 if valid, 1 if invalid
validate_subnet() {
  local subnet=$1
  [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  
  IFS='./' read -r ip1 ip2 ip3 ip4 mask <<< "$subnet"
  (( ip1 <= 255 && ip2 <= 255 && ip3 <= 255 && ip4 <= 255 && mask <= 32 )) || return 1
  
  return 0
}

# Validate that a VM ID is numeric and doesn't already exist
# Parameters: $1 - VM ID
# Returns: 0 if valid and available, 1 otherwise
validate_vm_id() {
  local vm_id=$1
  [[ "$vm_id" =~ ^[0-9]+$ ]] || return 1
  [[ -e "/etc/pve/qemu-server/$vm_id.conf" ]] && return 1
  return 0
}

# Validate disk size is a positive integer
# Parameters: $1 - Disk size
# Returns: 0 if valid, 1 otherwise
validate_disk_size() {
  local size=$1
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  (( size > 0 )) || return 1
  return 0
}

# Validate CPU core count is a positive integer
# Parameters: $1 - Core count
# Returns: 0 if valid, 1 otherwise
validate_cpu_cores() {
  local cores=$1
  [[ "$cores" =~ ^[0-9]+$ ]] || return 1
  (( cores > 0 )) || return 1
  return 0
}

# Validate RAM size is a positive integer
# Parameters: $1 - RAM size in MiB
# Returns: 0 if valid, 1 otherwise
validate_ram_size() {
  local ram=$1
  [[ "$ram" =~ ^[0-9]+$ ]] || return 1
  (( ram > 0 )) || return 1
  return 0
}

# Export functions for use in other scripts
export -f validate_vm_name
export -f validate_bridge_available
export -f validate_subnet
export -f validate_vm_id
export -f validate_disk_size
export -f validate_cpu_cores
export -f validate_ram_size

