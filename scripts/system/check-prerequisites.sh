#!/bin/bash
#
# check-prerequisites.sh - System prerequisite checks for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script validates Proxmox version compatibility and detects CPU platform.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Proxmox VE version compatibility validator
# Ensures host is running a supported major version (7.x, 8.x, or 9.x)
# Proxmox 9 support is marked as preliminary with explicit user warning
# Exits script if running on unsupported versions to prevent configuration issues
check_proxmox_version() {
  local log_file="${LOGDIR}/proxmox-version.log"

  # Extract major version number from pveversion output
  local version=$(pveversion | grep -oE "pve-manager/[0-9.]+")
  if [[ "$version" != pve-manager/[7-9].* ]]; then
    log_and_exit "Unsupported Proxmox version. Use 7.x, 8.x, or 9.x" "$log_file"
  fi

  # Display cautionary message for Proxmox 9 early adopters
  if [[ "$version" == pve-manager/9.* ]]; then
    display_and_log "It is in Apple's DNA that technology alone is not enough—it's technology married with liberal arts, married with the humanities, that yields us the results that make our hearts sing." "$log_file"
    sleep 5
  fi
}

# Hardware platform detection for CPU-specific virtualization optimizations
# Identifies AMD vs Intel processors to apply appropriate IOMMU and CPU arguments
# Returns: "AMD" or "INTEL" string used throughout script for conditional logic
detect_cpu_platform() {
  lscpu | grep -qi "Vendor ID.*AMD" && echo "AMD" || echo "INTEL"
}

# Check if system has been initialized
check_system_initialized() {
  if [[ ! -e /etc/pve/qemu-server/.PROXMOX-macOS ]]; then
    echo
    echo "⚠️  System not initialized!"
    echo
    echo "Please run the install script first:"
    echo "  cd /root/PROXMOX-macOS && ./install.sh"
    echo
    echo "This will configure your Proxmox host and reboot the system."
    return 1
  fi
  return 0
}

# Export functions for use in other scripts
export -f check_proxmox_version
export -f detect_cpu_platform
export -f check_system_initialized

