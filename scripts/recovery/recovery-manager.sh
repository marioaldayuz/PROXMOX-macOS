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
  local iso_path="${ISODIR}/${version_name,,}-installer.iso"

  # Skip creation if recovery image already exists in ISO directory
  [[ -e "$iso_path" ]] && { display_and_log "Recovery image for macOS $version_name already exists" "$logfile"; return; }
  display_and_log "Downloading macOS $version_name recovery image from Apple..." "$logfile"
  # Pre-allocate disk space for ISO file in temporary directory
  fallocate -x -l "$iso_size" "${TMPDIR}/${version_name,,}-installer.iso" >>"$logfile" 2>&1 || {
    display_and_log "❌ Error: Failed to allocate disk space for recovery image" "$logfile"
    display_and_log "   Required: $iso_size" "$logfile"
    display_and_log "   Check available space: df -h ${TMPDIR}" "$logfile"
    log_and_exit "Insufficient disk space" "$logfile"
  }
  
  # Format as FAT32 filesystem with uppercase volume label
  mkfs.msdos -F 32 "${TMPDIR}/${version_name,,}-installer.iso" -n "${version_name^^}" >>"$logfile" 2>&1 || {
    display_and_log "❌ Error: Failed to format recovery image as FAT32" "$logfile"
    display_and_log "   Ensure dosfstools is installed: apt-get install dosfstools" "$logfile"
    log_and_exit "FAT32 formatting failed" "$logfile"
  }
  
  # Attach ISO as loop device for mounting
  local loopdev=$(losetup -f --show "${TMPDIR}/${version_name,,}-installer.iso") || {
    display_and_log "❌ Error: Failed to set up loop device" "$logfile"
    display_and_log "   Check available loop devices: losetup -a" "$logfile"
    display_and_log "   You may need to increase max loop devices" "$logfile"
    log_and_exit "Loop device setup failed" "$logfile"
  }
  mkdir -p /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to create mount point" "$logfile"
  mount "$loopdev" /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to mount image" "$logfile"
  cd /mnt/APPLE
  # Construct macrecovery.py arguments with special handling for latest macOS versions
  local recovery_args="-b $board_id -m $model_id download"
  # Modern macOS versions (Sequoia/Tahoe) require the -os latest flag
  [[ "$version_name" =~ ^(Sequoia|Tahoe)$ ]] && recovery_args="$recovery_args -os latest"
  # Download recovery files directly into mounted ISO filesystem
  python3 "${SCRIPT_DIR}/Supporting_Tools/Misc_Tools/macrecovery/macrecovery.py" $recovery_args >>"$logfile" 2>&1 || {
    display_and_log "❌ Error: Failed to download macOS recovery files from Apple servers" "$logfile"
    display_and_log "   Possible causes:" "$logfile"
    display_and_log "   1. No internet connection (check: ping apple.com)" "$logfile"
    display_and_log "   2. Apple servers temporarily unavailable" "$logfile"
    display_and_log "   3. Firewall blocking outbound connections" "$logfile"
    display_and_log "   Board ID: $board_id | Model ID: $model_id" "$logfile"
    display_and_log "   Detailed log: $logfile" "$logfile"
    cd "$SCRIPT_DIR"
    umount /mnt/APPLE 2>/dev/null
    losetup -d "$loopdev" 2>/dev/null
    log_and_exit "Recovery download failed - check network connectivity" "$logfile"
  }
  cd "$SCRIPT_DIR"
  # Clean up mount and loop device
  umount /mnt/APPLE >>"$logfile" 2>&1 || log_and_exit "Failed to unmount image" "$logfile"
  losetup -d "$loopdev" >>"$logfile" 2>&1 || log_and_exit "Failed to detach loop device" "$logfile"
  # Move completed ISO from temp directory to final storage location
  mv "${TMPDIR}/${version_name,,}-installer.iso" "$iso_path" >>"$logfile" 2>&1 || log_and_exit "Failed to move image" "$logfile"
  display_and_log "Recovery image created successfully" "$logfile"
}

# Maintenance utility that removes all downloaded macOS recovery images and their logs
# Frees up disk space by deleting macOS recovery ISO files from ISO storage
# Useful when switching between macOS versions or cleaning up after testing
# Menu option: CRI - Clear all macOS recovery images
clear_recovery_images() {
  find "$ISODIR" -type f \( -name "sequoia-installer.iso" -o -name "tahoe-installer.iso" -o -name "sonoma-installer.iso" -o -name "ventura-installer.iso" \) -delete
  find "$LOGDIR" -type f -name "crt-recovery-*.log" -delete
  display_and_log "All recovery images cleared"
  read -n 1 -sp "Press any key to return to menu..."
}

# Check if installer ISO exists for a given macOS version
# Parameters: $1 - version name (e.g., "Sequoia", "Tahoe")
# Returns: 0 if exists, 1 if not
check_installer_iso_exists() {
  local version_name=$1
  local iso_path="${ISODIR}/${version_name,,}-installer.iso"
  [[ -f "$iso_path" ]]
}

# Download pre-built installer ISO from Hackintoshster CDN
# Parameters: $1 - version name (e.g., "Sequoia", "Tahoe")
# Returns: 0 on success, 1 on failure
download_installer_iso() {
  local version_name=$1
  local logfile="${LOGDIR}/download-installer-${version_name,,}.log"
  local iso_path="${ISODIR}/${version_name,,}-installer.iso"
  local temp_iso="${TMPDIR}/${version_name,,}-installer.iso.tmp"
  
  # Skip if already exists
  if [[ -f "$iso_path" ]]; then
    display_and_log "✓ Installer ISO for macOS $version_name already exists" "$logfile"
    return 0
  fi
  
  # Determine download URL based on version
  local download_url
  case "${version_name,,}" in
    sequoia)
      download_url="https://r2.hackintoshster.com/macos-assets/isos/sequoia-installer.iso"
      ;;
    tahoe)
      download_url="https://r2.hackintoshster.com/macos-assets/isos/tahoe-installer.iso"
      ;;
    *)
      display_and_log "❌ Error: Unknown macOS version: $version_name" "$logfile"
      return 1
      ;;
  esac
  
  display_and_log "Downloading macOS $version_name installer ISO from Hackintoshster CDN..." "$logfile"
  display_and_log "Source: $download_url" "$logfile"
  display_and_log "Target: $iso_path" "$logfile"
  echo
  
  # Download with progress bar using wget or curl
  if command -v wget &>/dev/null; then
    display_and_log "Using wget for download..." "$logfile"
    wget --progress=bar:force \
         --show-progress \
         --no-check-certificate \
         --output-document="$temp_iso" \
         "$download_url" 2>&1 | tee -a "$logfile"
    local download_status=${PIPESTATUS[0]}
  elif command -v curl &>/dev/null; then
    display_and_log "Using curl for download..." "$logfile"
    curl --progress-bar \
         --insecure \
         --location \
         --output "$temp_iso" \
         "$download_url" 2>&1 | tee -a "$logfile"
    local download_status=${PIPESTATUS[0]}
  else
    display_and_log "❌ Error: Neither wget nor curl is available" "$logfile"
    display_and_log "   Install wget: apt-get install wget" "$logfile"
    return 1
  fi
  
  # Check if download was successful
  if [[ $download_status -ne 0 ]]; then
    display_and_log "❌ Error: Download failed with exit code $download_status" "$logfile"
    display_and_log "   Possible causes:" "$logfile"
    display_and_log "   1. No internet connection" "$logfile"
    display_and_log "   2. CDN temporarily unavailable" "$logfile"
    display_and_log "   3. Firewall blocking HTTPS connections" "$logfile"
    display_and_log "   Detailed log: $logfile" "$logfile"
    rm -f "$temp_iso"
    return 1
  fi
  
  # Verify downloaded file is not empty
  if [[ ! -s "$temp_iso" ]]; then
    display_and_log "❌ Error: Downloaded file is empty" "$logfile"
    rm -f "$temp_iso"
    return 1
  fi
  
  # Move to final location
  mv "$temp_iso" "$iso_path" 2>&1 | tee -a "$logfile"
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    display_and_log "❌ Error: Failed to move ISO to final location" "$logfile"
    rm -f "$temp_iso"
    return 1
  fi
  
  # Get file size for display
  local file_size=$(du -h "$iso_path" | cut -f1)
  echo
  display_and_log "✓ Download complete: $file_size" "$logfile"
  display_and_log "✓ ISO saved to: $iso_path" "$logfile"
  
  return 0
}

# Interactive installer ISO download manager
# Checks for missing ISOs and offers to download them
# Menu option: Download macOS installer ISOs
download_installer_isos_interactive() {
  local logfile="${LOGDIR}/download-installers.log"
  
  clear
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║ DOWNLOAD macOS INSTALLER ISOs                            ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo
  echo "This will download pre-built macOS installer ISOs from"
  echo "Hackintoshster CDN. These ISOs contain the official Apple"
  echo "recovery images and are ready to use for VM installation."
  echo
  
  # Check which ISOs are missing
  local missing_isos=()
  local sequoia_exists=false
  local tahoe_exists=false
  
  if check_installer_iso_exists "Sequoia"; then
    sequoia_exists=true
    echo "✓ Sequoia installer ISO: Already downloaded"
  else
    echo "✗ Sequoia installer ISO: Not found"
    missing_isos+=("sequoia")
  fi
  
  if check_installer_iso_exists "Tahoe"; then
    tahoe_exists=true
    echo "✓ Tahoe installer ISO: Already downloaded"
  else
    echo "✗ Tahoe installer ISO: Not found"
    missing_isos+=("tahoe")
  fi
  
  echo
  
  # If all ISOs exist, no action needed
  if [[ ${#missing_isos[@]} -eq 0 ]]; then
    echo "All installer ISOs are already downloaded!"
    echo
    read -n 1 -sp "Press any key to return to menu..."
    return 0
  fi
  
  # Offer to download missing ISOs
  echo "Missing ISOs: ${missing_isos[*]}"
  echo
  echo "Download options:"
  echo "  1 - Download Sequoia only"
  echo "  2 - Download Tahoe only"
  echo "  3 - Download all missing ISOs"
  echo "  0 - Cancel"
  echo
  
  read -rp "Select option: " download_choice
  
  case $download_choice in
    1)
      if [[ "$sequoia_exists" == "true" ]]; then
        echo "Sequoia ISO already exists."
        sleep 2
      else
        echo
        if download_installer_iso "Sequoia"; then
          echo
          echo "✓ Sequoia installer ISO downloaded successfully!"
        else
          echo
          echo "✗ Failed to download Sequoia installer ISO."
          echo "  Check log: $logfile"
        fi
        echo
        read -n 1 -sp "Press any key to return to menu..."
      fi
      ;;
    2)
      if [[ "$tahoe_exists" == "true" ]]; then
        echo "Tahoe ISO already exists."
        sleep 2
      else
        echo
        if download_installer_iso "Tahoe"; then
          echo
          echo "✓ Tahoe installer ISO downloaded successfully!"
        else
          echo
          echo "✗ Failed to download Tahoe installer ISO."
          echo "  Check log: $logfile"
        fi
        echo
        read -n 1 -sp "Press any key to return to menu..."
      fi
      ;;
    3)
      echo
      local download_failed=false
      
      for version in "${missing_isos[@]}"; do
        local version_capitalized="$(tr '[:lower:]' '[:upper:]' <<< ${version:0:1})${version:1}"
        echo "═══════════════════════════════════════════════════════════════"
        echo "Downloading $version_capitalized..."
        echo "═══════════════════════════════════════════════════════════════"
        echo
        
        if download_installer_iso "$version_capitalized"; then
          echo
          echo "✓ $version_capitalized downloaded successfully!"
          echo
        else
          echo
          echo "✗ Failed to download $version_capitalized"
          download_failed=true
          echo
        fi
      done
      
      echo "═══════════════════════════════════════════════════════════════"
      if [[ "$download_failed" == "true" ]]; then
        echo "Some downloads failed. Check logs for details."
      else
        echo "All downloads completed successfully!"
      fi
      echo "═══════════════════════════════════════════════════════════════"
      echo
      read -n 1 -sp "Press any key to return to menu..."
      ;;
    0)
      echo "Cancelled."
      sleep 1
      return 0
      ;;
    *)
      echo "Invalid option."
      sleep 1
      ;;
  esac
}

# Check and offer to download installer ISO if missing (for VM creation workflow)
# Parameters: $1 - version name (e.g., "Sequoia", "Tahoe")
# Returns: 0 if ISO exists or was downloaded, 1 if user declined or download failed
check_and_offer_installer_download() {
  local version_name=$1
  
  # If ISO exists, we're good
  if check_installer_iso_exists "$version_name"; then
    return 0
  fi
  
  # ISO is missing, offer to download
  echo
  echo "═══════════════════════════════════════════════════════════════"
  echo "  macOS $version_name Installer ISO Not Found"
  echo "═══════════════════════════════════════════════════════════════"
  echo
  echo "The installer ISO for macOS $version_name is not available."
  echo
  echo "Options:"
  echo "  1. Download pre-built ISO from Hackintoshster CDN (recommended, fast)"
  echo "  2. Build from Apple recovery images (slower, requires download from Apple)"
  echo "  3. Cancel VM creation"
  echo
  
  read -rp "Select option [1]: " iso_choice
  iso_choice=${iso_choice:-1}
  
  case $iso_choice in
    1)
      echo
      if download_installer_iso "$version_name"; then
        echo
        echo "✓ Installer ISO downloaded successfully!"
        echo
        sleep 2
        return 0
      else
        echo
        echo "✗ Download failed. You can try building from Apple recovery images instead."
        echo
        read -rp "Build from Apple recovery images? (y/n) [n]: " build_choice
        if [[ "${build_choice,,}" == "y" ]]; then
          return 0  # Let the normal recovery download process handle it
        else
          return 1
        fi
      fi
      ;;
    2)
      # User wants to build from Apple recovery images
      echo "Will build installer from Apple recovery images..."
      sleep 1
      return 0
      ;;
    3)
      echo "VM creation cancelled."
      return 1
      ;;
    *)
      echo "Invalid option. VM creation cancelled."
      return 1
      ;;
  esac
}

# Export functions for use in other scripts
export -f download_recovery_image
export -f clear_recovery_images
export -f check_installer_iso_exists
export -f download_installer_iso
export -f download_installer_isos_interactive
export -f check_and_offer_installer_download

