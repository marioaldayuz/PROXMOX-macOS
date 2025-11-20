#!/bin/bash
#
# recovery-manager.sh - macOS recovery image management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script manages downloading and clearing macOS recovery images.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# macOS recovery image builder for modern macOS (15+)
# Downloads official Apple recovery media and packages into bootable ISO
# Creates FAT32-formatted ISO with BaseSystem.dmg and BaseSystem.chunklist
# Uses macrecovery.py to fetch files via Apple's board/model identifiers
# Skips if recovery image already exists (saves bandwidth and time)
# Parameters: version_name, board_id, model_id, iso_size (e.g., "Sequoia", "Mac-7BA5B2D9E42DDD94", "000...", "1450M")
download_recovery_image() {
  local version_name=$1 board_id=$2 model_id=$3 iso_size=$4
  local logfile="${LOGDIR}/crt-recovery-${version_name,,}.log"
  local iso_path="${ISODIR}/${version_name,,}.iso"

  # Skip creation if recovery image already exists in ISO directory
  [[ -e "$iso_path" ]] && { display_and_log "Recovery image for macOS $version_name already exists" "$logfile"; return; }
  display_and_log "Downloading macOS $version_name recovery image from Apple..." "$logfile"
  # Pre-allocate disk space for ISO file in temporary directory
  fallocate -x -l "$iso_size" "${TMPDIR}/${version_name,,}.iso" >>"$logfile" 2>&1 || log_and_exit "Failed to allocate image" "$logfile"
  # Format as FAT32 filesystem with uppercase volume label
  mkfs.msdos -F 32 "${TMPDIR}/${version_name,,}.iso" -n "${version_name^^}" >>"$logfile" 2>&1 || log_and_exit "Failed to format image" "$logfile"
  # Attach ISO as loop device for mounting
  local loopdev=$(losetup -f --show "${TMPDIR}/${version_name,,}.iso") || log_and_exit "Failed to set up loop device" "$logfile"
  mkdir -p /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to create mount point" "$logfile"
  mount "$loopdev" /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to mount image" "$logfile"
  cd /mnt/APPLE
  # Construct macrecovery.py arguments with special handling for latest macOS versions
  local recovery_args="-b $board_id -m $model_id download"
  # Modern macOS versions (Sequoia/Tahoe) require the -os latest flag
  [[ "$version_name" =~ ^(Sequoia|Tahoe)$ ]] && recovery_args="$recovery_args -os latest"
  # Download recovery files directly into mounted ISO filesystem
  python3 "${SCRIPT_DIR}/Supporting_Tools/Misc_Tools/macrecovery/macrecovery.py" $recovery_args >>"$logfile" 2>&1 || log_and_exit "Failed to download recovery" "$logfile"
  cd "$SCRIPT_DIR"
  # Clean up mount and loop device
  umount /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to unmount image" "$logfile"
  losetup -d "$loopdev" >>"$logfile" 2>&1 || log_and_exit "Failed to detach loop device" "$logfile"
  # Move completed ISO from temp directory to final storage location
  mv "${TMPDIR}/${version_name,,}.iso" "$iso_path" >>"$logfile" 2>&1 || log_and_exit "Failed to move image" "$logfile"
  display_and_log "Recovery image created successfully" "$logfile"
}

# Maintenance utility that removes all downloaded macOS recovery images and their logs
# Frees up disk space by deleting macOS recovery ISO files from ISO storage
# Useful when switching between macOS versions or cleaning up after testing
# Menu option: CRI - Clear all macOS recovery images
clear_recovery_images() {
  find "$ISODIR" -type f \( -name "sequoia.iso" -o -name "tahoe.iso" -o -name "sonoma.iso" -o -name "ventura.iso" \) -delete
  find "$LOGDIR" -type f -name "crt-recovery-*.log" -delete
  display_and_log "All recovery images cleared"
  read -n 1 -sp "Press any key to return to menu..."
}

# Export functions for use in other scripts
export -f download_recovery_image
export -f clear_recovery_images

