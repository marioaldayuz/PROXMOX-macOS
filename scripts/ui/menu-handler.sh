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
# Dynamically adjusts menu options based on enterprise vs community repository
main_menu() {
  # Detect repository type once per session
  local IS_ENTERPRISE=$(detect_repository_type)
  
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
    
    # Build dynamic menu based on repository type
    declare -A MENU_OPTIONS
    local option_num=3
    
    # Only show subscription-related options for non-enterprise users
    if [[ "$IS_ENTERPRISE" != "true" ]]; then
      echo " ${option_num} - Add Proxmox VE no-subscription repository"
      MENU_OPTIONS[$option_num]="add_no_subscription_repo"
      ((option_num++))
    fi
    
    echo " ${option_num} - Update default OpenCore ISO (legacy/fallback only)"
    MENU_OPTIONS[$option_num]="update_opencore_iso"
    ((option_num++))
    
    echo " ${option_num} - Clear all cached macOS recovery images"
    MENU_OPTIONS[$option_num]="clear_recovery_images"
    ((option_num++))
    
    # Only show subscription notice removal for non-enterprise users
    if [[ "$IS_ENTERPRISE" != "true" ]]; then
      echo " ${option_num} - Remove Proxmox subscription notice"
      MENU_OPTIONS[$option_num]="remove_subscription_notice"
      ((option_num++))
    fi
    
    echo " ${option_num} - Add new network bridge (macOS in cloud)"
    MENU_OPTIONS[$option_num]="configure_network_bridge"
    ((option_num++))
    
    echo " ${option_num} - Customize OpenCore config.plist"
    MENU_OPTIONS[$option_num]="customize_opencore_config"
    ((option_num++))
    
    echo " ${option_num} - Set default bridge"
    MENU_OPTIONS[$option_num]="set_default_bridge_interactive"
    ((option_num++))
    
    echo " ${option_num} - Configure default profile & preferences"
    MENU_OPTIONS[$option_num]="configure_default_preferences"
    ((option_num++))
    
    echo
    echo " 0   - Quit (or press ENTER)"
    echo
    
    # Show current defaults if set
    local default_bridge=$(get_default_bridge)
    local default_profile=$(get_default_profile)
    if [[ "$default_bridge" != "vmbr0" ]] || [[ -n "$default_profile" ]]; then
      echo "Current defaults:"
      [[ "$default_bridge" != "vmbr0" ]] && echo "  Bridge: $default_bridge"
      [[ -n "$default_profile" ]] && echo "  Profile: $default_profile"
      echo
    fi
    
    read -rp "Select Option: " OPT
    # Exit on empty input or explicit zero
    [[ -z "$OPT" || "$OPT" -eq 0 ]] && exit

    # Route numeric selections to VM configuration, text selections to utility functions
    if [[ ${MACOS_CONFIG[$OPT]} ]]; then
      configure_macos_vm "${MACOS_CONFIG[$OPT]}" "$NEXTID" "$OPT"
    elif [[ -n "${MENU_OPTIONS[$OPT]}" ]]; then
      ${MENU_OPTIONS[$OPT]}
    else
      echo "Invalid option"; read -n 1 -s
    fi
  done
}

# Export functions for use in other scripts
export -f init_dirs
export -f main_menu

