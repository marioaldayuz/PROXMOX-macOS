#!/bin/bash
#
# setup-prerequisites.sh - System initialization for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script performs first-run system configuration that prepares Proxmox host for macOS virtualization.
# Configures: locale, package repos, essential tools, GRUB bootloader, kernel modules, and VFIO passthrough.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Comprehensive first-run system configuration that prepares Proxmox host for macOS virtualization
# Executes only once (tracked via marker file) and requires reboot to activate kernel changes
# Configures: locale, package repos, essential tools, GRUB bootloader, kernel modules, and VFIO passthrough
# This function fundamentally alters system boot parameters and driver loading behavior
# Parameters:
#   $1 - CPU platform ("AMD" or "INTEL")
setup_prerequisites() {
  local OSX_PLATFORM=$1
  local logfile="${LOGDIR}/prerequisites-setup.log"
  
  # Note: OpenCore ISOs are now built on-demand during VM creation
  # No need to copy pre-built ISOs anymore
  
  # Create convenient shell alias for quick script access
  printf "alias mac='%s/setup'\n" "$SCRIPT_DIR" >> /root/.bashrc
  
  # Enforce UTF-8 locale to prevent character encoding issues
  printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/environment
  
  # Disable mouse integration in vim for better terminal compatibility
  printf "set mouse-=a\n" > ~/.vimrc
  
  # Remove enterprise repository that requires paid subscription
  rm -f /etc/apt/sources.list.d/pve-enterprise.list
  
  # Update package lists with fallback to main Debian mirror if local mirror fails
  apt-get update >>"$logfile" 2>&1 || {
    local country=$(curl -s https://ipinfo.io/country | tr '[:upper:]' '[:lower:]')
    sed -i "s/ftp.$country.debian.org/ftp.debian.org/g" /etc/apt/sources.list
    apt-get update >>"$logfile" 2>&1 || log_and_exit "Failed to update apt" "$logfile"
  }
  
  # Install essential utilities for system management, network configuration, and API communication
  apt-get install -y vim unzip zip sysstat parted wget curl iptraf git htop ipcalc coreutils vim-common xmlstarlet >>"$logfile" 2>&1 || log_and_exit "Failed to install packages" "$logfile"
  
  # Eliminate GRUB boot delay for faster system startup
  sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
  
  # Configure platform-specific IOMMU and virtualization settings
  local grub_cmd="quiet"
  if [[ $OSX_PLATFORM == "AMD" ]]; then
    # AMD-specific: Enable AMD IOMMU and disable framebuffer conflicts
    grub_cmd="quiet amd_iommu=on iommu=pt video=vesafb:off video=efifb:off"
    printf "options kvm-amd nested=1\n" > /etc/modprobe.d/kvm-amd.conf
  else
    # Intel-specific: Enable Intel VT-d and disable framebuffer conflicts
    grub_cmd="quiet intel_iommu=on iommu=pt video=vesafb:off video=efifb:off"
    printf "options kvm-intel nested=Y\n" > /etc/modprobe.d/kvm-intel.conf
  fi
  
  # Apply sysfb_init blacklist for specific Proxmox versions to prevent GPU conflicts
  pveversion | grep -qE "pve-manager/(7.[2-4]|8.[0-4]|9)" && grub_cmd="$grub_cmd initcall_blacklist=sysfb_init"
  sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$grub_cmd\"/g" /etc/default/grub
  
  # Load VFIO kernel modules required for PCI passthrough functionality
  printf "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd\n" >> /etc/modules
  
  # Blacklist GPU and audio drivers that interfere with macOS passthrough
  printf "blacklist nouveau\nblacklist nvidia\nblacklist snd_hda_codec_hdmi\nblacklist snd_hda_intel\nblacklist snd_hda_codec\nblacklist snd_hda_core\nblacklist radeon\nblacklist amdgpu\n" >> /etc/modprobe.d/pve-blacklist.conf
  
  # Suppress KVM MSR warnings that clutter logs during macOS operation
  printf "options kvm ignore_msrs=Y report_ignored_msrs=0\n" > /etc/modprobe.d/kvm.conf
  
  # Allow VFIO interrupt remapping for better device passthrough compatibility
  printf "options vfio_iommu_type1 allow_unsafe_interrupts=1\n" > /etc/modprobe.d/iommu_unsafe_interrupts.conf
  
  # Patch Proxmox web UI to remove subscription nag message
  [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  
  # Create marker file to prevent re-running prerequisites on subsequent executions
  touch /etc/pve/qemu-server/.PROXMOX-macOS
  
  # Regenerate GRUB configuration with new kernel parameters
  update-grub >>"$logfile" 2>&1 || log_and_exit "Failed to update GRUB" "$logfile"
  
  display_and_log "Prerequisites setup complete. A reboot is necessary to apply the required changes. Press enter to reboot or Ctrl+C if you intend to reboot later." "$logfile"
  read noop
  display_and_log "Enter pressed. Rebooting in 15 seconds..." "$logfile"
  sleep 15 && reboot
}

# Export functions for use in other scripts
export -f setup_prerequisites

