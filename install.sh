#!/bin/bash

#########################################################################################################################
#
# Script: Installation tool for HACKINTOSHSTER-PROXMOX
# Purpose: One-time system setup for Hackintosh VM support on Proxmox VE
# Source: https://aldayuz.com
# Author: Mario Aldayuz (thenotoriousllama)
#
# This script configures your Proxmox host for macOS virtualization:
# - Installs required packages and dependencies
# - Configures GRUB with IOMMU settings
# - Sets up kernel modules for VFIO passthrough
# - Creates shell alias for easy access
# - Requires system reboot to apply changes
#
# Run this ONCE after cloning the repository.
#
#########################################################################################################################

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

# Get script directory (where this install.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define log file
LOG_FILE="${SCRIPT_DIR}/logs/install-hackintoshster-proxmox.log"
mkdir -p "${SCRIPT_DIR}/logs" 2>/dev/null || true

# Function to log messages
log_message() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Function to check command success
check_status() {
    if [ $? -ne 0 ]; then
        log_message "Error: $1"
        exit 1
    fi
}

# Clear screen
clear

echo "═══════════════════════════════════════════════════════════════"
echo "           H A C K I N T O S H S T E R   I N S T A L L E R"
echo "      Proxmox VE System Configuration for macOS Virtualization"
echo "═══════════════════════════════════════════════════════════════"
echo
log_message "Starting Hackintoshster installation from: $SCRIPT_DIR"

# Check if already installed
if [ -f /etc/pve/qemu-server/.hackintoshster-main ]; then
    log_message "⚠️  Hackintoshster appears to be already installed."
    log_message "Marker file exists: /etc/pve/qemu-server/.hackintoshster-main"
    echo
    read -p "Reinstall? This will reconfigure system settings. [y/N]: " reinstall
    if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
        log_message "Installation cancelled."
        echo
        echo "To create VMs, run: ./setup or mac"
        exit 0
    fi
    rm -f /etc/pve/qemu-server/.hackintoshster-main
fi

# Detect CPU platform (AMD vs Intel) for platform-specific configurations
log_message "Detecting CPU platform..."
if lscpu | grep -qi "Vendor ID.*AMD"; then
    OSX_PLATFORM="AMD"
else
    OSX_PLATFORM="INTEL"
fi
log_message "Detected platform: $OSX_PLATFORM"

# Clean up problematic repository files
log_message "Cleaning up existing repository configurations..."
[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ] && rm -f "/etc/apt/sources.list.d/pve-enterprise.list"
[ -f "/etc/apt/sources.list.d/ceph.list" ] && rm -f "/etc/apt/sources.list.d/ceph.list"
[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ] && rm -f "/etc/apt/sources.list.d/pve-enterprise.sources"
[ -f "/etc/apt/sources.list.d/ceph.sources" ] && rm -f "/etc/apt/sources.list.d/ceph.sources"

# Update package lists
log_message "Updating package lists..."
apt-get update >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "Initial apt-get update failed. Attempting to fix sources..."
    
    # Use main Debian mirror instead of country-specific
    sed -i 's/ftp\.[a-z]\{2\}\.debian\.org/ftp.debian.org/g' /etc/apt/sources.list
    
    log_message "Retrying apt-get update..."
    apt-get update >> "$LOG_FILE" 2>&1
    check_status "Failed to update package lists after source modification"
fi

# Install essential utilities
log_message "Installing essential packages..."
apt-get install -y vim unzip zip sysstat parted wget curl iptraf git htop ipcalc coreutils vim-common xmlstarlet jq bc >> "$LOG_FILE" 2>&1
check_status "Failed to install packages"

# Make setup script executable
chmod +x "${SCRIPT_DIR}/setup"

# Create convenient shell alias for quick script access
log_message "Creating 'mac' command alias..."
printf "alias mac='%s/setup'\n" "$SCRIPT_DIR" >> /root/.bashrc

# Enforce UTF-8 locale to prevent character encoding issues
log_message "Configuring UTF-8 locale..."
printf "LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n" > /etc/environment

# Disable mouse integration in vim for better terminal compatibility
printf "set mouse-=a\n" > ~/.vimrc

# Eliminate GRUB boot delay for faster system startup
log_message "Configuring GRUB boot settings..."
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub

# Configure platform-specific IOMMU and virtualization settings
log_message "Configuring IOMMU and virtualization settings for $OSX_PLATFORM..."
grub_cmd="quiet"
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
log_message "Configuring VFIO kernel modules..."
printf "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd\n" >> /etc/modules

# Blacklist GPU and audio drivers that interfere with macOS passthrough
log_message "Blacklisting conflicting drivers..."
printf "blacklist nouveau\nblacklist nvidia\nblacklist snd_hda_codec_hdmi\nblacklist snd_hda_intel\nblacklist snd_hda_codec\nblacklist snd_hda_core\nblacklist radeon\nblacklist amdgpu\n" >> /etc/modprobe.d/pve-blacklist.conf

# Suppress KVM MSR warnings that clutter logs during macOS operation
printf "options kvm ignore_msrs=Y report_ignored_msrs=0\n" > /etc/modprobe.d/kvm.conf

# Allow VFIO interrupt remapping for better device passthrough compatibility
printf "options vfio_iommu_type1 allow_unsafe_interrupts=1\n" > /etc/modprobe.d/iommu_unsafe_interrupts.conf

# Patch Proxmox web UI to remove subscription nag message
log_message "Patching Proxmox web UI..."
[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# Create marker file to prevent re-running prerequisites on subsequent executions
mkdir -p /etc/pve/qemu-server 2>/dev/null || true
touch /etc/pve/qemu-server/.hackintoshster-main

# Regenerate GRUB configuration with new kernel parameters
log_message "Updating GRUB configuration..."
update-grub >> "$LOG_FILE" 2>&1
check_status "Failed to update GRUB"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "           Installation Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo
log_message "✓ Packages installed"
log_message "✓ IOMMU configured for $OSX_PLATFORM"
log_message "✓ Kernel modules configured"
log_message "✓ GRUB updated"
log_message "✓ Command alias created: mac"
echo
log_message "⚠️  A SYSTEM REBOOT IS REQUIRED to apply kernel changes."
echo
read -p "Press Enter to reboot now, or Ctrl+C to reboot later: "
log_message "Rebooting in 15 seconds..."
echo "Rebooting in 15 seconds... (Ctrl+C to cancel)"
sleep 15
reboot