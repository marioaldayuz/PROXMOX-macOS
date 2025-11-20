#!/bin/bash
#
# vm-creator.sh - Virtual machine creation for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script handles actual VM creation using qm commands with proper macOS configurations.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"
source "${SCRIPT_DIR}/scripts/lib/math-utils.sh"
source "${SCRIPT_DIR}/scripts/opencore/opencore-manager.sh"

# Modern macOS VM creator for Sequoia (15) and Tahoe (26)
# Creates VMs with VirtIO storage/networking, Skylake-Client-v4 CPU, and XHCI USB
# Automatically configures QEMU Guest Agent, disables ballooning, and applies hotplug fixes
# Post-creation: patches config to treat ISOs as disks (required for macOS boot)
# Parameters: version_name, vm_id, vm_name, disk_size, storage, core_count, ram_size, iso_size, disk_type, bridge, custom_iso_name
create_vm() {
  local iso_file version_name=$1 vm_id=$2 vm_name=$3 disk_size=$4 storage=$5 core_count=$6 ram_size=$7 iso_size=$8 disk_type=$9 bridge=${10} custom_iso_name=${11}
  local logfile="${LOGDIR}/crt-vm-${OSX_PLATFORM,,}-${version_name,,}.log"
  
  # Use custom ISO if provided, otherwise use default OpenCore ISO
  if [ -n "$custom_iso_name" ]; then
    iso_file="$custom_iso_name"
    display_and_log "Using custom OpenCore ISO: $iso_file" "$logfile"
  else
    iso_file="${OPENCORE_ISO}"
    # Ensure default OpenCore ISO exists, download if missing
    if [ ! -f "${ISODIR}/$iso_file" ]; then
      update_opencore_iso
    fi
  fi
  # Validate bridge exists in kernel before attempting VM creation
  [[ ! -d "/sys/class/net/$bridge" ]] && log_and_exit "Bridge $bridge does not exist" "$logfile"

  # Build QEMU device arguments starting with Apple SMC emulation (required for macOS boot)
  local cpu_args device_args='-device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" -smbios type=2'
  # Modern macOS 15+ requires XHCI USB controller
  device_args="$device_args -device qemu-xhci -device usb-kbd -device usb-tablet -global nec-usb-xhci.msi=off"
  
  # CPU emulation per QEMU best practices for macOS
  # Using Skylake-Client-v4 with CPUID model=165 (Comet Lake Mac compatibility)
  # Reference: QEMU CPU optimization for macOS guests
  # This provides ~30-44% better performance than host passthrough
  if [[ "$OSX_PLATFORM" == "AMD" ]]; then
    # AMD: Skylake-Client-v4 with Comet Lake CPUID for Mac compatibility
    cpu_args="-cpu Skylake-Client-v4,vendor=GenuineIntel,model=165,+invtsc,-pcid,-spec-ctrl,kvm=on"
  else
    # Intel: Skylake-Client-v4 with Comet Lake CPUID for optimal performance
    cpu_args="-cpu Skylake-Client-v4,vendor=GenuineIntel,model=165,+invtsc,+kvm_pv_unhalt,+kvm_pv_eoi,kvm=on"
  fi

  # Apply QEMU 6.1+ hotplug workaround to prevent boot hangs
  local qemu_version=$(qemu-system-x86_64 --version | awk '/version/ {print $4}' | cut -d'(' -f1)
  version_compare "$qemu_version" "6.1" && device_args="$device_args -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off"

  # Debug: log the actual values being used
  display_and_log "DEBUG: storage_iso='$storage_iso', iso_file='$iso_file'" "$logfile"
  display_and_log "DEBUG: ide0 parameter: ${storage_iso}:iso/${iso_file},media=cdrom,cache=unsafe,size=96M" "$logfile"
  
  # Execute Proxmox qm command with comprehensive VM configuration
  # macOS 15+ uses VirtIO network adapter per NEW-GUIDE.md
  qm create "$vm_id" \
    --agent 1 --args "$device_args $cpu_args" --autostart 0 \
    --balloon 0 --bios ovmf --boot "order=ide0;virtio0" \
    --cores "$core_count" --description "Hackintosh VM - macOS $version_name" \
    --efidisk0 "${storage}:4" --machine q35 --memory "$ram_size" \
    --name "$vm_name" --net0 "virtio,bridge=$bridge" --numa 0 \
    --onboot 0 --ostype other --sockets 1 --start 0 --tablet 1 \
    --vga vmware --vmgenid 1 --scsihw virtio-scsi-pci \
    --virtio0 "${storage}:${disk_size},cache=none,discard=on" \
    --ide0 "${storage_iso}:iso/${iso_file},media=cdrom,cache=unsafe,size=96M" \
    --ide2 "${storage_iso}:iso/${version_name,,}.iso,media=cdrom,cache=unsafe,size=${iso_size}" >>"$logfile" 2>&1 || log_and_exit "Failed to create VM" "$logfile"
  # Critical post-creation patch: Change ISO media type from cdrom to disk (macOS requirement)
  sed -i 's/media=cdrom/media=disk/' "/etc/pve/qemu-server/$vm_id.conf" >>"$logfile" 2>&1 || log_and_exit "Failed to update VM config" "$logfile"

  display_and_log "VM ($vm_name) created successfully" "$logfile"
  
  # Extract bridge IP for displaying web panel access URL
  local bridge_ip=$(ip -4 addr show "$bridge" | awk '/inet/ {print $2}' | cut -d'/' -f1 || echo "unknown")
  
  # Display macOS 26 (Tahoe) cursor freeze fix if applicable
  if [[ "$version_name" == "Tahoe" ]]; then
    display_and_log "\n=== macOS 26 (Tahoe) Cursor Freeze Fix ===" "$logfile"
    display_and_log "To fix cursor freezing issues, run this command in Proxmox shell:" "$logfile"
    display_and_log "  qm set $vm_id -args \"\$(qm config $vm_id --current | grep ^args: | cut -d' ' -f2-) -device virtio-tablet\"" "$logfile"
    display_and_log "Then disable 'Use tablet for pointer' in VM Options tab.\n" "$logfile"
  fi
  
  display_and_log "Access Proxmox Web Panel: https://$bridge_ip:8006" "$logfile"
}

# Export functions for use in other scripts
export -f create_vm

