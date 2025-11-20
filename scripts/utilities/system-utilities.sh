#!/bin/bash
#
# system-utilities.sh - System utility functions for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script provides system maintenance utilities for Proxmox.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Proxmox repository configurator that enables free community updates without subscription
# Adds version-specific no-subscription repo (Bullseye for PVE 7, Bookworm for 8, Trixie for 9)
# Proxmox 9 uses new DEB822 format (.sources) instead of traditional one-line format (.list)
# Allows system updates and package installations without enterprise subscription
# Menu option: NVE - Add Proxmox VE no-subscription repo
add_no_subscription_repo() {
  local logfile="${LOGDIR}/add-repo-pve-no-subscription.log"
  # Proxmox VE 7.x uses Debian Bullseye repositories
  if pveversion | grep -q "pve-manager/[7]"; then
    printf "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription\n" > /etc/apt/sources.list.d/pve-no-sub.list
  # Proxmox VE 8.x uses Debian Bookworm repositories
  elif pveversion | grep -q "pve-manager/[8]"; then
    printf "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription\n" > /etc/apt/sources.list.d/pve-no-sub.list
  # Proxmox VE 9.x uses Debian Trixie with new DEB822 source format
  elif pveversion | grep -q "pve-manager/[9]"; then
    printf "Types: deb\nURIs: http://download.proxmox.com/debian/pve\nSuites: trixie\nComponents: pve-no-subscription\nSigned-By: /usr/share/keyrings/proxmox-archive-keyring.gpg\n" > /etc/apt/sources.list.d/pve-no-sub.sources
  else
    log_and_exit "Unsupported Proxmox version" "$logfile"
  fi
  # Refresh package index to incorporate new repository
  apt update -y >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
  display_and_log "Repository added successfully" "$logfile"
  read -n 1 -sp "Press any key to return to menu..."
}

# Proxmox web UI subscription nag removal tool
# Installs apt hook that automatically patches proxmoxlib.js after package updates
# Prevents subscription warning from reappearing after Proxmox upgrades
# Reinstalls widget toolkit to immediately apply patch without waiting for next update
# Menu option: RPS - Remove Proxmox subscription notice
remove_subscription_notice() {
  echo "DPkg::Post-Invoke { \"if [ -s /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && ! grep -q -F 'NoMoreNagging' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then echo 'Removing subscription nag from UI...'; sed -i '/data\.status/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi\" };" >/etc/apt/apt.conf.d/no-nag-script
  apt --reinstall install proxmox-widget-toolkit &>/dev/null
  display_and_log "Subscription notice removed"
  read -n 1 -sp "Press any key to return to menu..."
}

# Interactive bridge default setter
# Allows user to set a default bridge that will be pre-selected for VM creation
# Menu option: Set default bridge
set_default_bridge_interactive() {
  local logfile="${LOGDIR}/set-default-bridge.log"
  
  clear
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║ SET DEFAULT NETWORK BRIDGE                                ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo
  
  # Get available bridges
  local bridge_output=$(get_available_bridges) || { 
    display_and_log "Failed to retrieve bridges" "$logfile"
    read -n 1 -sp "Press any key to return to menu..."
    return 1
  }
  
  local bridges=() default_bridge=""
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ \| ]]; then
      default_bridge="$line"
    else
      bridges+=("$line")
    fi
  done <<< "$bridge_output"
  
  if ((${#bridges[@]} == 0)); then
    display_and_log "No bridges found" "$logfile"
    read -n 1 -sp "Press any key to return to menu..."
    return 1
  fi
  
  # Display available bridges
  declare -A bridge_info
  for b in "${bridges[@]}"; do
    IFS='|' read -r bridge_name ip_addr <<< "$b"
    bridge_info["$bridge_name"]="IP address: ${ip_addr:-unknown}"
  done
  
  mapfile -t sorted_names < <(printf '%s\n' "${!bridge_info[@]}" | sort -V)
  
  local current_default=$(get_default_bridge)
  echo "Current default bridge: $current_default"
  echo
  echo "Available bridges:"
  for name in "${sorted_names[@]}"; do
    bridge_num=${name#vmbr}
    ip_info="${bridge_info[$name]}"
    echo "  ${bridge_num}. $name ($ip_info)"
  done
  echo
  echo "  C - Clear default (reset to vmbr0)"
  echo "  0 - Cancel"
  echo
  
  read -rp "Select bridge number [current: ${current_default#vmbr}]: " choice
  
  if [[ -z "$choice" || "$choice" == "0" ]]; then
    echo "Cancelled."
    read -n 1 -sp "Press any key to return to menu..."
    return 0
  fi
  
  if [[ "${choice^^}" == "C" ]]; then
    remove_config_value "DEFAULT_BRIDGE"
    display_and_log "Default bridge cleared (reset to vmbr0)" "$logfile"
    read -n 1 -sp "Press any key to return to menu..."
    return 0
  fi
  
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local selected_bridge="vmbr$choice"
    if [[ -n "${bridge_info[$selected_bridge]}" ]]; then
      set_default_bridge "$selected_bridge"
      display_and_log "Default bridge set to: $selected_bridge" "$logfile"
    else
      display_and_log "Invalid bridge number" "$logfile"
    fi
  else
    display_and_log "Invalid selection" "$logfile"
  fi
  
  read -n 1 -sp "Press any key to return to menu..."
}

# Interactive default preferences configurator
# Allows user to set default profile, storage, and other preferences for quick VM creation
# Menu option: Configure default profile & preferences
configure_default_preferences() {
  local logfile="${LOGDIR}/configure-preferences.log"
  
  while true; do
    clear
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ CONFIGURE DEFAULT PREFERENCES                             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo
    echo "Set default values for quick VM creation. When defaults are"
    echo "configured, you'll be able to create VMs with minimal prompts."
    echo
    
    # Show current settings
    local current_profile=$(get_default_profile)
    local current_storage=$(get_default_storage)
    local current_bridge=$(get_default_bridge)
    
    echo "Current defaults:"
    echo "  1. Profile:  ${current_profile:-<not set>}"
    echo "  2. Storage:  ${current_storage:-<not set>}"
    echo "  3. Bridge:   ${current_bridge:-vmbr0 (system default)}"
    echo
    echo "Options:"
    echo "  1 - Set default profile"
    echo "  2 - Set default storage"
    echo "  3 - Set default bridge"
    echo "  C - Clear all defaults"
    echo "  0 - Return to main menu"
    echo
    
    read -rp "Select option: " pref_choice
    
    case "${pref_choice^^}" in
      1)
        # Set default profile
        clear
        display_profiles
        echo
        read -rp "Select default profile (1-5, 0=none): " profile_num
        
        if [[ "$profile_num" == "0" ]]; then
          remove_config_value "DEFAULT_PROFILE"
          echo "Default profile cleared."
          sleep 1
        elif [[ "$profile_num" =~ ^[1-5]$ ]]; then
          local profile_name=$(get_profile_by_number "$profile_num")
          if [[ $? -eq 0 && -n "$profile_name" ]]; then
            if [[ "$profile_name" == "custom" ]]; then
              echo "Cannot set 'custom' as default profile."
              sleep 2
            else
              set_default_profile "$profile_name"
              echo "Default profile set to: $profile_name"
              sleep 1
            fi
          fi
        else
          echo "Invalid selection."
          sleep 1
        fi
        ;;
        
      2)
        # Set default storage
        clear
        echo "Available storages:"
        local storage_output=$(get_available_storages)
        if [[ $? -ne 0 ]]; then
          echo "Failed to retrieve storages."
          read -n 1 -sp "Press any key to continue..."
          continue
        fi
        
        local storages=()
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          [[ "$line" =~ \| ]] && storages+=("$line")
        done <<< "$storage_output"
        
        if ((${#storages[@]} == 0)); then
          echo "No storages found."
          read -n 1 -sp "Press any key to continue..."
          continue
        fi
        
        local idx=1
        for s in "${storages[@]}"; do
          storage_name="${s%%|*}"
          avail_space="${s##*|}"
          echo "  ${idx}. $storage_name ($avail_space GB)"
          ((idx++))
        done
        echo
        echo "  0. Clear default storage"
        echo
        
        read -rp "Select storage: " storage_choice
        
        if [[ "$storage_choice" == "0" ]]; then
          remove_config_value "DEFAULT_STORAGE"
          echo "Default storage cleared."
          sleep 1
        elif [[ "$storage_choice" =~ ^[0-9]+$ ]] && ((storage_choice > 0 && storage_choice <= ${#storages[@]})); then
          local selected_storage="${storages[$((storage_choice-1))]%%|*}"
          set_default_storage "$selected_storage"
          echo "Default storage set to: $selected_storage"
          sleep 1
        else
          echo "Invalid selection."
          sleep 1
        fi
        ;;
        
      3)
        # Set default bridge (redirect to dedicated function)
        set_default_bridge_interactive
        ;;
        
      C)
        # Clear all defaults
        clear
        echo "Are you sure you want to clear all default preferences?"
        read -rp "(y/n): " confirm
        if [[ "${confirm,,}" == "y" ]]; then
          clear_all_defaults
          echo "All defaults cleared."
          sleep 1
        fi
        ;;
        
      0)
        return 0
        ;;
        
      *)
        echo "Invalid option."
        sleep 1
        ;;
    esac
  done
}

# Export functions for use in other scripts
export -f add_no_subscription_repo
export -f remove_subscription_notice
export -f set_default_bridge_interactive
export -f configure_default_preferences

