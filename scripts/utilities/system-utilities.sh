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

# Export functions for use in other scripts
export -f add_no_subscription_repo
export -f remove_subscription_notice

