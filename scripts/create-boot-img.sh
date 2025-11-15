#!/bin/bash
#
# create-boot-img.sh - Create BOOT.img FAT32 image containing EFI directory
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script creates a bootable BOOT.img file containing the EFI directory
# for proper UEFI booting from ISO. The image is RAW FAT16 filesystem (no partition table),
# sized based on EFI directory contents plus 20% overhead.
#
# Usage:
#   create-boot-img.sh <efi_dir> <log_file> <output_path>
#
# Arguments:
#   efi_dir     - Path to EFI directory to include in BOOT.img
#   log_file    - Path to log file for detailed output
#   output_path - Where to create BOOT.img
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - Dependency missing or operation failed
#

set -e

# Validate arguments
if [ $# -lt 3 ]; then
    echo "ERROR: Invalid arguments" >&2
    echo "Usage: $0 <efi_dir> <log_file> <output_path>" >&2
    exit 1
fi

EFI_DIR="$1"
LOG_FILE="$2"
BOOT_IMG="$3"

# Log helper function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_and_echo() {
    echo "$1" >&2
    log_message "$1"
}

#
# validate_dependencies() - Check for required tools
#
validate_dependencies() {
    log_and_echo "→ Checking BOOT.img creation dependencies..."
    
    local missing_deps=()
    
    # Check for dd
    if command -v dd >/dev/null 2>&1; then
        local dd_path=$(which dd)
        log_and_echo "  ✓ dd: $dd_path"
    else
        missing_deps+=("dd")
        log_and_echo "  ✗ dd: NOT FOUND"
    fi
    
    # Check for mkfs.vfat (from dosfstools package)
    if command -v mkfs.vfat >/dev/null 2>&1; then
        local mkfs_path=$(which mkfs.vfat)
        local mkfs_version=$(mkfs.vfat 2>&1 | head -1 || echo "unknown")
        log_and_echo "  ✓ mkfs.vfat: $mkfs_path"
        log_message "    Version: $mkfs_version"
    else
        missing_deps+=("mkfs.vfat")
        log_and_echo "  ✗ mkfs.vfat: NOT FOUND"
    fi
    
    # Check for fdisk (for creating MBR partition table)
    if command -v fdisk >/dev/null 2>&1; then
        local fdisk_path=$(which fdisk)
        log_and_echo "  ✓ fdisk: $fdisk_path"
    else
        missing_deps+=("fdisk")
        log_and_echo "  ✗ fdisk: NOT FOUND"
    fi
    
    # Check for sfdisk (for automated partitioning)
    if command -v sfdisk >/dev/null 2>&1; then
        local sfdisk_path=$(which sfdisk)
        log_and_echo "  ✓ sfdisk: $sfdisk_path"
    else
        missing_deps+=("sfdisk")
        log_and_echo "  ✗ sfdisk: NOT FOUND"
    fi
    
    # Check for partprobe (for updating partition table)
    if command -v partprobe >/dev/null 2>&1; then
        local partprobe_path=$(which partprobe)
        log_and_echo "  ✓ partprobe: $partprobe_path"
    else
        # partprobe is optional, just warn
        log_and_echo "  ⚠ partprobe: NOT FOUND (optional, from parted package)"
    fi
    
    # Check for losetup
    if command -v losetup >/dev/null 2>&1; then
        local losetup_path=$(which losetup)
        log_and_echo "  ✓ losetup: $losetup_path"
    else
        missing_deps+=("losetup")
        log_and_echo "  ✗ losetup: NOT FOUND"
    fi
    
    # Check for mount
    if command -v mount >/dev/null 2>&1; then
        local mount_path=$(which mount)
        log_and_echo "  ✓ mount: $mount_path"
    else
        missing_deps+=("mount")
        log_and_echo "  ✗ mount: NOT FOUND"
    fi
    
    # Check for umount
    if command -v umount >/dev/null 2>&1; then
        local umount_path=$(which umount)
        log_and_echo "  ✓ umount: $umount_path"
    else
        missing_deps+=("umount")
        log_and_echo "  ✗ umount: NOT FOUND"
    fi
    
    # Check for du
    if command -v du >/dev/null 2>&1; then
        local du_path=$(which du)
        log_and_echo "  ✓ du: $du_path"
    else
        missing_deps+=("du")
        log_and_echo "  ✗ du: NOT FOUND"
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_and_echo "  ERROR: Missing required dependencies: ${missing_deps[*]}"
        log_and_echo "  Install missing packages with:"
        if [[ " ${missing_deps[@]} " =~ " mkfs.vfat " ]]; then
            log_and_echo "    apt install dosfstools"
        fi
        if [[ " ${missing_deps[@]} " =~ " fdisk " ]] || [[ " ${missing_deps[@]} " =~ " sfdisk " ]]; then
            log_and_echo "    apt install util-linux"
        fi
        exit 2
    fi
    
    log_and_echo "  ✓ All dependencies found"
    return 0
}

#
# calculate_image_size() - Calculate size needed for BOOT.img
#
calculate_image_size() {
    local efi_dir="$1"
    
    log_and_echo "→ Calculating BOOT.img size..."
    log_message "  EFI directory: $efi_dir"
    
    # Get EFI directory size in KB
    local efi_size_kb=$(du -sk "$efi_dir" | awk '{print $1}')
    log_and_echo "  EFI directory size: ${efi_size_kb} KB"
    
    # Add 20% overhead for filesystem metadata and safety margin
    local overhead_kb=$((efi_size_kb * 20 / 100))
    local total_size_kb=$((efi_size_kb + overhead_kb))
    
    log_and_echo "  Overhead (20%): ${overhead_kb} KB"
    log_and_echo "  Total calculated size: ${total_size_kb} KB"
    
    # Convert to MB (round up)
    local total_size_mb=$(( (total_size_kb + 1023) / 1024 ))
    
    # Ensure minimum size of 10MB for FAT32 filesystem requirements
    if [ $total_size_mb -lt 10 ]; then
        log_and_echo "  Adjusting to minimum size: 10 MB (required for FAT32)"
        total_size_mb=10
    else
        log_and_echo "  Final size: ${total_size_mb} MB"
    fi
    
    echo "$total_size_mb"
}

#
# create_boot_image() - Main function to create BOOT.img
#
create_boot_image() {
    local mount_point="/tmp/boot_img_mount_$$"
    
    log_and_echo "═══════════════════════════════════════════════════════════"
    log_and_echo "Creating BOOT.img"
    log_and_echo "═══════════════════════════════════════════════════════════"
    
    # Validate EFI directory exists
    if [ ! -d "$EFI_DIR" ]; then
        log_and_echo "ERROR: EFI directory not found: $EFI_DIR"
        exit 2
    fi
    
    log_message "  EFI directory: $EFI_DIR"
    log_message "  Output image: $BOOT_IMG"
    
    # Calculate required size
    local size_mb=$(calculate_image_size "$EFI_DIR")
    log_and_echo ""
    
    # Step 1: Create empty image file
    log_and_echo "→ Creating empty ${size_mb}MB image file..."
    log_message "  Command: dd if=/dev/zero of=$BOOT_IMG bs=1M count=$size_mb"
    
    if dd if=/dev/zero of="$BOOT_IMG" bs=1M count=$size_mb >> "$LOG_FILE" 2>&1; then
        local img_size=$(ls -lh "$BOOT_IMG" | awk '{print $5}')
        log_and_echo "  ✓ Image file created: $img_size"
    else
        log_and_echo "  ERROR: Failed to create image file with dd"
        exit 2
    fi
    
    # Step 2: Format entire image as raw FAT16 filesystem (NO partition table!)
    # Standard UEFI boot image format:
    # - Raw filesystem (no MBR, no partition table)
    # - FAT16 (not FAT32)
    # - Entire image is the filesystem
    log_and_echo ""
    log_and_echo "→ Formatting image as raw FAT16 filesystem..."
    log_message "  Creating raw FAT16 filesystem (no partition table)"
    log_message "  Using standard UEFI boot image format"
    
    # Use mkfs.vfat to format the ENTIRE image as FAT16
    # -F 16 = FAT16 (working images use FAT16, not FAT32)
    # -n = volume label
    # -S 512 = 512 byte sectors
    log_message "  Command: mkfs.vfat -F 16 -n OPENCORE -S 512 $BOOT_IMG"
    
    if mkfs.vfat -F 16 -n "OPENCORE" -S 512 "$BOOT_IMG" >> "$LOG_FILE" 2>&1; then
        log_and_echo "  ✓ Image formatted as raw FAT16 filesystem"
        log_message "    Format: RAW FAT16 (no partition table)"
        log_message "    Sector size: 512 bytes"
        log_message "    Volume label: OPENCORE"
    else
        log_and_echo "  ERROR: Failed to format image with mkfs.vfat"
        rm -f "$BOOT_IMG"
        exit 2
    fi
    
    # Step 3: Mount the image directly (no partition, mount the whole thing)
    log_and_echo ""
    log_and_echo "→ Mounting filesystem..."
    log_message "  Creating mount point: $mount_point"
    
    mkdir -p "$mount_point" 2>> "$LOG_FILE"
    if [ $? -ne 0 ]; then
        log_and_echo "  ERROR: Failed to create mount point"
        rm -f "$BOOT_IMG"
        exit 2
    fi
    
    # Mount the image directly using loop (no partition number needed)
    log_message "  Command: mount -o loop $BOOT_IMG $mount_point"
    if mount -o loop "$BOOT_IMG" "$mount_point" >> "$LOG_FILE" 2>&1; then
        log_and_echo "  ✓ Filesystem mounted at: $mount_point"
    else
        log_and_echo "  ERROR: Failed to mount filesystem"
        rmdir "$mount_point" 2>/dev/null
        rm -f "$BOOT_IMG"
        exit 2
    fi
    
    # Step 4: Copy EFI directory into mounted filesystem
    log_and_echo ""
    log_and_echo "→ Copying EFI directory into image..."
    log_message "  Source: $EFI_DIR"
    log_message "  Destination: $mount_point/"
    log_message "  Command: cp -r $EFI_DIR $mount_point/"
    
    if cp -r "$EFI_DIR" "$mount_point/" >> "$LOG_FILE" 2>&1; then
        # Verify the copy was successful
        if [ -d "$mount_point/EFI" ] && [ -f "$mount_point/EFI/OC/config.plist" ]; then
            log_and_echo "  ✓ EFI directory copied successfully"
            
            # Log directory structure for verification
            log_message "  Verifying image contents:"
            ls -laR "$mount_point" >> "$LOG_FILE" 2>&1
            
            # Show file count
            local file_count=$(find "$mount_point/EFI" -type f | wc -l)
            log_and_echo "  Files copied: $file_count"
        else
            log_and_echo "  ERROR: EFI directory verification failed"
            umount "$mount_point" >> "$LOG_FILE" 2>&1
            rmdir "$mount_point" 2>/dev/null
            rm -f "$BOOT_IMG"
            exit 2
        fi
    else
        log_and_echo "  ERROR: Failed to copy EFI directory"
        umount "$mount_point" >> "$LOG_FILE" 2>&1
        rmdir "$mount_point" 2>/dev/null
        rm -f "$BOOT_IMG"
        exit 2
    fi
    
    # Step 4: Sync and unmount
    log_and_echo ""
    log_and_echo "→ Finalizing image..."
    log_message "  Syncing filesystem..."
    sync
    
    log_message "  Command: umount $mount_point"
    if umount "$mount_point" >> "$LOG_FILE" 2>&1; then
        log_and_echo "  ✓ Filesystem unmounted successfully"
    else
        log_and_echo "  WARNING: Failed to unmount cleanly (image may still be valid)"
        # Try to force unmount
        umount -f "$mount_point" >> "$LOG_FILE" 2>&1 || true
    fi
    
    # Cleanup mount point
    rmdir "$mount_point" 2>/dev/null || true
    
    # Step 5: Verify final image
    log_and_echo ""
    log_and_echo "→ Verifying BOOT.img..."
    
    if [ ! -f "$BOOT_IMG" ]; then
        log_and_echo "  ERROR: BOOT.img file not found after creation"
        exit 2
    fi
    
    local final_size=$(ls -lh "$BOOT_IMG" | awk '{print $5}')
    local final_size_bytes=$(stat -c%s "$BOOT_IMG" 2>/dev/null || stat -f%z "$BOOT_IMG" 2>/dev/null || echo "0")
    
    if [ "$final_size_bytes" -eq 0 ]; then
        log_and_echo "  ERROR: BOOT.img is empty (0 bytes)"
        rm -f "$BOOT_IMG"
        exit 2
    fi
    
    log_and_echo "  ✓ BOOT.img verified"
    log_and_echo "  Size: $final_size (${final_size_bytes} bytes)"
    log_message "  Path: $BOOT_IMG"
    
    log_and_echo ""
    log_and_echo "═══════════════════════════════════════════════════════════"
    log_and_echo "✓ BOOT.img created successfully"
    log_and_echo "═══════════════════════════════════════════════════════════"
    
    return 0
}

#
# Main execution
#
main() {
    # Validate dependencies first
    validate_dependencies
    
    echo "" >&2
    
    # Create the boot image
    create_boot_image
    
    exit 0
}

# Run main function
main

