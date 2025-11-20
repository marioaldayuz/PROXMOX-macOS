#!/bin/bash
#
# menu-handler.sh - Main menu interface for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script provides the interactive menu system for VM creation and system utilities.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"
source "${SCRIPT_DIR}/scripts/vm/vm-configurator.sh"
source "${SCRIPT_DIR}/scripts/utilities/system-utilities.sh"
source "${SCRIPT_DIR}/scripts/network/bridge-manager.sh"
source "${SCRIPT_DIR}/scripts/recovery/recovery-manager.sh"
source "${SCRIPT_DIR}/scripts/opencore/opencore-manager.sh"

# Bootstrap function that creates essential directory structure for script operations
# Establishes log directory for operation tracking and temp directory for ISO manipulation
# Must execute before any logging or file operations occur
# Creates main log file to prevent append errors during initial operations
init_dirs() {
  mkdir -p "$LOGDIR" "$TMPDIR" || log_and_exit "Failed to create directories" "${LOGDIR}/init-dirs.log"
  touch "$MAIN_LOG"  # Initialize main log file to prevent "file not found" errors
}

# Primary user interface presenting macOS version selection and maintenance utilities
# Displays banner with version info, dynamically sorted macOS options, and utility commands
# Loops indefinitely until user exits, routing selections to appropriate handler functions
# Queries Proxmox for next available VM ID on each iteration
main_menu() {
  while true; do
    clear
    # Fetch next available VM ID from Proxmox cluster
    NEXTID=$(pvesh get /cluster/nextid)
    echo "═══════════════════════════════════════════════════════════════"
    echo "           H A C K I N T O S H S T E R   -   M O D E R N"
    echo "        macOS 15+ (Sequoia/Tahoe) VM Deployment System"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  by Mario Aldayuz (thenotoriousllama) | https://aldayuz.com"
    echo "  Version: ${HACKOCVERSION} | OpenCore: ${OCVERSION}"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "Next VM ID: ${NEXTID}"
    echo
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ CREATE macOS VM                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    # Dynamically display macOS versions sorted by version number
    for i in $(for key in "${!MACOS_CONFIG[@]}"; do
      IFS='|' read -r _ version _ _ _ _ <<< "${MACOS_CONFIG[$key]}"
      echo "$version|$key"
    done | sort -t'|' -k1,1V | cut -d'|' -f2); do
      IFS='|' read -r name version _ _ _ _ <<< "${MACOS_CONFIG[$i]}"
      printf " %s - macOS %-10s (Version %s)\n" "$i" "$name" "$version"
    done
    echo
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ SYSTEM UTILITIES                                          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo " 3 - Add Proxmox VE no-subscription repository"
    echo " 4 - Update default OpenCore ISO (legacy/fallback only)"
    echo " 5 - Clear all cached macOS recovery images"
    echo " 6 - Remove Proxmox subscription notice"
    echo " 7 - Add new network bridge (macOS in cloud)"
    echo " 8 - Customize OpenCore config.plist"
    echo
    echo " 0   - Quit (or press ENTER)"
    echo
    read -rp "Select Option: " OPT
    # Exit on empty input or explicit zero
    [[ -z "$OPT" || "$OPT" -eq 0 ]] && exit

    # Route numeric selections to VM configuration, text selections to utility functions
    if [[ ${MACOS_CONFIG[$OPT]} ]]; then
      configure_macos_vm "${MACOS_CONFIG[$OPT]}" "$NEXTID" "$OPT"
    else
      case $OPT in
        3) add_no_subscription_repo ;;
        4) update_opencore_iso ;;
        5) clear_recovery_images ;;
        6) remove_subscription_notice ;;
        7) configure_network_bridge ;;
        8) customize_opencore_config ;;
        *) echo "Invalid option"; read -n 1 -s ;;
      esac
    fi
  done
}

# Export functions for use in other scripts
export -f init_dirs
export -f main_menu

