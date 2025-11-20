#!/bin/bash
#
# config.sh - Global configuration constants for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This file contains all global configuration variables and constants.
# Source this file at the beginning of other scripts: source "${SCRIPT_DIR}/scripts/lib/config.sh"
#

# Source persistence library for user preferences
PERSISTENCE_LIB="${SCRIPT_DIR}/scripts/lib/persistence.sh"
[[ -f "$PERSISTENCE_LIB" ]] && source "$PERSISTENCE_LIB"

# Global configuration constants defining paths, versions, and resource allocation defaults
export SCRIPT_DIR="${SCRIPT_DIR:-/root/PROXMOX-macOS}"  # Primary working directory for all script operations
export LOGDIR="${LOGDIR:-${SCRIPT_DIR}/logs}"           # Centralized location for all operation logs
export MAIN_LOG="${MAIN_LOG:-${LOGDIR}/main.log}"      # Master log file capturing all script activities
export TMPDIR="${TMPDIR:-${SCRIPT_DIR}/tmp}"           # Temporary storage for ISO building and loop mounts
export HACKOCVERSION="2025.11.23"                       # Current release version of this automation script
export OCVERSION="1.0.6"                                # OpenCore bootloader version bundled with ISOs
export DEFAULT_VM_PREFIX="macOS-"                       # Naming convention prefix for newly created VMs
export BASE_RAM_SIZE=4096                               # Minimum RAM allocation in MiB (4GB baseline)
export RAM_PER_CORE=1024                                # Additional RAM per CPU core in MiB (1GB per core for modern macOS)
export MAX_CORES=16                                     # Maximum CPU cores allowed per VM to prevent overallocation
export DHCP_CONF_DIR="/etc/dhcp/dhcpd.d"               # Directory containing per-bridge DHCP configuration files
export NETWORK_INTERFACES_FILE="/etc/network/interfaces"  # Debian network configuration file for bridge definitions
export DHCP_USER="dhcpd"                                # System user/group name for ISC DHCP server daemon
export OPENCORE_ISO="opencore-PROXMOX-macOS-vm.iso"    # Default OpenCore ISO filename

# Associative array mapping menu options to macOS version metadata
# Format: [option_number]="Display_Name|Version|Board_ID|Model_ID|Recovery_Size|Disk_Interface"
# Only supporting macOS 15+ (Sequoia and Tahoe)
declare -gA MACOS_CONFIG=(
  ["1"]="Sequoia|15|Mac-7BA5B2D9E42DDD94|00000000000000000|1450M|virtio0"
  ["2"]="Tahoe|26|Mac-7BA5B2D9E42DDD94|00000000000000000|1450M|virtio0"
)

