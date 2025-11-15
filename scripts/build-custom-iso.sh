#!/bin/bash
#
# build-custom-iso.sh - Build custom processor-specific OpenCore ISO
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script orchestrates the creation of a custom OpenCore ISO with:
# - Processor-specific EFI configuration
# - Populated SMBIOS values
# - Supporting Tools
# - macOS post-install setup script
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common functions
source "${SCRIPT_DIR}/scripts/lib/common-functions.sh"

# Set log file
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/logs/build-custom-iso.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Default values
EFI_SOURCE=""
SMBIOS_JSON=""
OUTPUT_DIR=""
TMPDIR_ARG=""
OUTPUT_NAME_FILE=""

#
# parse_arguments() - Parse command line arguments
#
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --efi-source)
                EFI_SOURCE="$2"
                shift 2
                ;;
            --processor)
                # Legacy support for --processor (deprecated)
                log_message "WARNING: --processor is deprecated, use --efi-source instead"
                EFI_SOURCE="Processor_EFIs/$2"
                shift 2
                ;;
            --smbios-json)
                SMBIOS_JSON="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --script-dir)
                SCRIPT_DIR="$2"
                shift 2
                ;;
            --tmpdir)
                TMPDIR_ARG="$2"
                shift 2
                ;;
            --output-name-file)
                OUTPUT_NAME_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 --efi-source <path> --smbios-json <path> --output-dir <path> --script-dir <path> [--tmpdir <path>] [--output-name-file <path>]"
                echo
                echo "Options:"
                echo "  --efi-source <path>     Path to EFI source directory (required)"
                echo "  --smbios-json <path>    Path to SMBIOS JSON file (required)"
                echo "  --output-dir <path>     Output directory for ISO (required)"
                echo "  --script-dir <path>     Hackintoshster root directory (required)"
                echo "  --tmpdir <path>         Temporary build directory (optional)"
                echo "  --output-name-file <path>  Write ISO filename to this file (optional)"
                echo "  --help                  Show this help message"
                exit 0
                ;;
            *)
                log_message "ERROR: Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$EFI_SOURCE" ]; then
        log_message "ERROR: --efi-source argument is required"
        exit 1
    fi
    
    if [ -z "$SMBIOS_JSON" ]; then
        log_message "ERROR: --smbios-json argument is required"
        exit 1
    fi
    
    if [ -z "$OUTPUT_DIR" ]; then
        log_message "ERROR: --output-dir argument is required"
        exit 1
    fi
    
    if [ -z "$SCRIPT_DIR" ]; then
        log_message "ERROR: --script-dir argument is required"
        exit 1
    fi
}

#
# validate_dependencies() - Check for required tools
#
validate_dependencies() {
    log_message "Checking dependencies..."
    
    local missing_deps=()
    
    if ! ensure_dependency "genisoimage" && ! ensure_dependency "mkisofs"; then
        missing_deps+=("genisoimage or mkisofs")
    fi
    
    if ! ensure_dependency "jq"; then
        missing_deps+=("jq")
    fi
    
    if ! ensure_dependency "rsync"; then
        missing_deps+=("rsync")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "ERROR: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log_message "All dependencies satisfied"
    return 0
}

#
# validate_inputs() - Validate input paths and files
#
validate_inputs() {
    log_message "Validating inputs..."
    
    # Check EFI source exists
    local efi_source="${SCRIPT_DIR}/${EFI_SOURCE}"
    if ! validate_path "$efi_source" "dir"; then
        log_message "ERROR: EFI source directory not found: $efi_source"
        exit 1
    fi
    
    # Check EFI_NEW directory exists in source
    if ! validate_path "${efi_source}/EFI_NEW" "dir"; then
        log_message "ERROR: EFI_NEW subdirectory not found: ${efi_source}/EFI_NEW"
        exit 1
    fi
    
    # Check config.plist exists
    if ! validate_path "${efi_source}/EFI_NEW/EFI/OC/config.plist" "file"; then
        log_message "ERROR: config.plist not found: ${efi_source}/EFI_NEW/EFI/OC/config.plist"
        exit 1
    fi
    
    # Check SMBIOS JSON file
    if ! validate_path "$SMBIOS_JSON" "file"; then
        exit 1
    fi
    
    if ! validate_json_file "$SMBIOS_JSON"; then
        exit 1
    fi
    
    # Check Supporting_Tools directory
    if ! validate_path "${SCRIPT_DIR}/Supporting_Tools" "dir"; then
        log_message "ERROR: Supporting_Tools directory not found: ${SCRIPT_DIR}/Supporting_Tools"
        exit 1
    fi
    
    # Check output directory exists or can be created
    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR" || {
            log_message "ERROR: Failed to create output directory: $OUTPUT_DIR"
            exit 1
        }
    fi
    
    log_message "Input validation successful"
    return 0
}

#
# create_build_directory() - Create temporary build directory structure
#
create_build_directory() {
    echo "→ Creating build directory..." >&2
    log_message "Creating build directory..."
    
    local build_dir
    if [ -n "$TMPDIR_ARG" ]; then
        build_dir="${TMPDIR_ARG}/oc-build-$$"
        mkdir -p "$build_dir" 2>>"$LOG_FILE"
    else
        build_dir=$(create_temp_dir "oc-build" 2>>"$LOG_FILE")
    fi
    
    if [ $? -ne 0 ] || [ ! -d "$build_dir" ]; then
        echo "  ERROR: Failed to create build directory" >&2
        log_message "ERROR: Failed to create build directory"
        exit 2
    fi
    
    echo "  ✓ Build directory: $build_dir" >&2
    log_message "Build directory created: $build_dir"
    
    # Output just the path to stdout for caller
    echo "$build_dir"
    return 0
}

#
# copy_base_efi() - Copy ALL files from PROXMOX-EFI to build directory
#
copy_base_efi() {
    local build_dir="$1"
    local efi_source="${SCRIPT_DIR}/${EFI_SOURCE}"
    
    echo "→ Copying all PROXMOX-EFI files..." >&2
    log_message "Copying all PROXMOX-EFI files to build directory..."
    log_message "  Source: $efi_source"
    log_message "  Destination: $build_dir"
    
    if ! validate_path "$efi_source" "dir"; then
        echo "  ERROR: Source directory not found: $efi_source" >&2
        log_message "ERROR: Source directory not found: $efi_source"
        return 1
    fi
    
    # Copy ALL files and directories from PROXMOX-EFI
    # This includes: BOOT.img, boot.catalog, EFI_NEW/, and any other helper files
    echo "  Copying all files..." >&2
    
    rsync -a --exclude='.git' --exclude='.gitignore' "${efi_source}/" "${build_dir}/" >> "$LOG_FILE" 2>&1
    local rsync_exit=$?
    
    if [ $rsync_exit -ne 0 ]; then
        echo "  ERROR: rsync failed with exit code $rsync_exit" >&2
        log_message "ERROR: rsync failed copying PROXMOX-EFI directory (exit $rsync_exit)"
        log_message "  Command: rsync -a ${efi_source}/ ${build_dir}/"
        echo "  Last 20 lines of log:" >&2
        tail -20 "$LOG_FILE" >&2
        return 1
    fi
    
    # Verify critical files were copied
    if [ ! -f "${build_dir}/EFI_NEW/EFI/OC/config.plist" ]; then
        echo "  ERROR: config.plist not found after copy" >&2
        log_message "ERROR: config.plist not found: ${build_dir}/EFI_NEW/EFI/OC/config.plist"
        return 1
    fi
    
    # Note: BOOT.img will be created later from EFI_NEW/EFI/ after SMBIOS injection
    # boot.catalog will be auto-generated by genisoimage during ISO creation
    
    local file_count=$(find "${build_dir}" -type f | wc -l)
    echo "  ✓ All PROXMOX-EFI files copied successfully ($file_count files total)" >&2
    log_message "All PROXMOX-EFI files copied successfully ($file_count files)"
    log_message "  Includes: EFI_NEW/, helper scripts, and utilities"
    return 0
}

#
# create_boot_image_from_efi() - Create BOOT.img from EFI_NEW/EFI directory
#
create_boot_image_from_efi() {
    local build_dir="$1"
    
    echo "→ Creating BOOT.img from EFI_NEW/EFI..." >&2
    log_message "Creating BOOT.img with SMBIOS-injected config.plist..."
    
    # The EFI directory to include in BOOT.img
    local efi_source="${build_dir}/EFI_NEW/EFI"
    
    if [ ! -d "$efi_source" ]; then
        echo "  ERROR: EFI source not found: $efi_source" >&2
        log_message "ERROR: EFI source not found: $efi_source"
        return 2
    fi
    
    # Call the create-boot-img.sh script with the EFI directory
    # It will create BOOT.img in the build directory
    if "${SCRIPT_DIR}/scripts/create-boot-img.sh" "$efi_source" "$LOG_FILE" "${build_dir}/BOOT.img"; then
        echo "  ✓ BOOT.img created with custom SMBIOS" >&2
        log_message "BOOT.img created successfully with injected serial"
        
        # Verify it was created
        if [ -f "${build_dir}/BOOT.img" ]; then
            local img_size=$(du -h "${build_dir}/BOOT.img" | awk '{print $1}')
            log_message "  BOOT.img size: $img_size"
        else
            echo "  ERROR: BOOT.img not found after creation" >&2
            return 2
        fi
        return 0
    else
        echo "  ERROR: Failed to create BOOT.img" >&2
        log_message "ERROR: Failed to create BOOT.img"
        return 2
    fi
}

#
# inject_smbios() - Inject SMBIOS values into config.plist
#
inject_smbios() {
    local build_dir="$1"
    local config_plist="${build_dir}/EFI_NEW/EFI/OC/config.plist"
    
    echo "→ Injecting SMBIOS values into config.plist..." >&2
    log_message "Injecting SMBIOS values into config.plist..."
    log_message "  Config: $config_plist"
    log_message "  JSON: $SMBIOS_JSON"
    
    # Verify config.plist exists
    if [ ! -f "$config_plist" ]; then
        echo "  ERROR: config.plist not found: $config_plist" >&2
        log_message "ERROR: config.plist not found: $config_plist"
        return 1
    fi
    
    # Call the inject-smbios script
    echo "  Running inject-smbios.sh..." >&2
    echo "    Config: $config_plist" >&2
    echo "    JSON: $SMBIOS_JSON" >&2
    
    # Run with full output visible
    "${SCRIPT_DIR}/scripts/inject-smbios.sh" \
        --config "$config_plist" \
        --json "$SMBIOS_JSON" \
        --backup 2>&1 | tee -a "$LOG_FILE" >&2
    
    local inject_exit=${PIPESTATUS[0]}
    
    if [ $inject_exit -ne 0 ]; then
        echo "  ERROR: inject-smbios.sh failed with exit code $inject_exit" >&2
        log_message "ERROR: Failed to inject SMBIOS values (exit $inject_exit)"
        echo "  Check logs at: ${SCRIPT_DIR}/logs/inject-smbios.log" >&2
        return 1
    fi
    
    echo "  ✓ SMBIOS values injected successfully" >&2
    log_message "SMBIOS values injected successfully"
    return 0
}

#
# copy_supporting_tools() - Copy Supporting_Tools directory to build
#
copy_supporting_tools() {
    local build_dir="$1"
    
    echo "→ Copying Supporting_Tools..." >&2
    log_message "Copying Supporting_Tools..."
    
    echo "  Copying files (this may take a moment)..." >&2
    rsync -a "${SCRIPT_DIR}/Supporting_Tools/" "${build_dir}/Supporting_Tools/" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to copy Supporting_Tools" >&2
        log_message "ERROR: Failed to copy Supporting_Tools"
        return 1
    fi
    
    echo "  ✓ Supporting_Tools copied successfully" >&2
    log_message "Supporting_Tools copied successfully"
    return 0
}

#
# copy_copyright() - Copy COPYRIGHT.md from EFI source to build
#
copy_copyright() {
    local build_dir="$1"
    local efi_source="${SCRIPT_DIR}/${EFI_SOURCE}"
    
    echo "→ Copying COPYRIGHT.md..." >&2
    log_message "Copying COPYRIGHT.md..."
    
    # Try to copy from EFI source first, fallback to project root
    if [ -f "${efi_source}/COPYRIGHT.md" ]; then
        if ! cp "${efi_source}/COPYRIGHT.md" "${build_dir}/COPYRIGHT.md"; then
            echo "  ERROR: Failed to copy COPYRIGHT.md from EFI source" >&2
            log_message "ERROR: Failed to copy COPYRIGHT.md from EFI source"
            return 1
        fi
        echo "  ✓ Copied from EFI source" >&2
    elif [ -f "${SCRIPT_DIR}/COPYRIGHT.md" ]; then
        if ! cp "${SCRIPT_DIR}/COPYRIGHT.md" "${build_dir}/COPYRIGHT.md"; then
            echo "  ERROR: Failed to copy COPYRIGHT.md from project root" >&2
            log_message "ERROR: Failed to copy COPYRIGHT.md from project root"
            return 1
        fi
        echo "  ✓ Copied from project root" >&2
    else
        echo "  ⚠ WARNING: COPYRIGHT.md not found, skipping" >&2
        log_message "WARNING: COPYRIGHT.md not found, skipping"
        return 0
    fi
    
    log_message "COPYRIGHT.md copied successfully"
    return 0
}

#
# generate_iso_readme() - Generate user-friendly README for the ISO
#
generate_iso_readme() {
    local build_dir="$1"
    
    echo "→ Generating ISO README..." >&2
    log_message "Generating ISO README..."
    
    # Extract SMBIOS information
    local serial=$(jq -r '.Serial // "Unknown"' "$SMBIOS_JSON")
    local mac_model=$(jq -r '.Type // "Unknown"' "$SMBIOS_JSON")
    local build_date=$(date '+%B %d, %Y at %H:%M:%S')
    
    # Generate README
    cat > "${build_dir}/README.md" << EOF
# Your Custom Hackintoshster OpenCore ISO

**Serial Number**: ${serial}  
**Mac Model**: ${mac_model}  
**Built**: ${build_date}  
**Configuration**: PROXMOX-EFI (Skylake-Client-v4 optimized)  
**OpenCore Version**: 1.0.6

---

## 📁 What's Inside This ISO

### EFI/
Pre-configured OpenCore bootloader with your unique SMBIOS values already populated. This folder contains:
- **BOOT/** - UEFI boot files
- **OC/** - OpenCore configuration, drivers, kexts, and ACPI tables
  - **config.plist** - Your personalized configuration
  - **Kexts/** - Kernel extensions (Lilu, VirtualSMC, WhateverGreen)
  - **Drivers/** - UEFI drivers for boot
  - **ACPI/** - ACPI tables for hardware compatibility

### Supporting_Tools/
Essential Hackintosh utilities and tools:
- **Core_Tools/** - Lilu and VMHide kernel extensions
- **Misc_Tools/** - ProperTree, GenSMBIOS, macrecovery, and more

### macOS-Setup.command
Automated post-installation script (double-click to run)

### COPYRIGHT.md
License and legal information

---

## 🚀 Quick Start Guide

### Step 1: Install macOS

1. Boot your VM with this ISO attached
2. Install macOS Sequoia or Tahoe following the on-screen installer
3. Complete the initial macOS setup

### Step 2: Run Post-Install Script

After logging into macOS for the first time:

1. Double-click this ISO in Finder to mount it
2. Double-click **macOS-Setup.command**
3. Enter your password when prompted
4. Wait for the script to complete

The script will automatically:
- Install Homebrew and Python 3
- Copy Supporting_Tools to your Desktop
- Install Lilu and VMHide kernel extensions
- Run system verification checks

### Step 3: Install OpenCore to Your Disk

1. Open **Supporting_Tools/Misc_Tools/MountEFI** (if available) or use Terminal:
   \`\`\`bash
   sudo diskutil mount disk0s1
   \`\`\`

2. Copy the **EFI** folder from this ISO to your mounted EFI partition:
   \`\`\`bash
   sudo cp -r /Volumes/OPENCORE/EFI/ /Volumes/EFI/
   \`\`\`

3. Unmount the EFI partition:
   \`\`\`bash
   sudo diskutil unmount /Volumes/EFI
   \`\`\`

### Step 4: Cleanup

1. In Proxmox: Remove this ISO from your VM's CD drive
2. On Proxmox host: Delete the ISO file to free space:
   \`\`\`bash
   rm /var/lib/vz/template/iso/OpenCore-${serial}.iso
   \`\`\`

---

## 🛠️ Your SMBIOS Information

**System Product Name**: ${mac_model}  
**Serial Number**: ${serial}  
**Source**: $(jq -r 'if .Serial then "API-Validated" else "GenSMBIOS" end' "$SMBIOS_JSON")

Keep this information private and secure. These identifiers make your Hackintosh unique and allow iServices (iCloud, iMessage) to function properly.

---

## 📦 Supporting Tools Overview

Located at **Supporting_Tools/** on your Desktop after running macOS-Setup.command:

### Core Tools
- **Lilu.kext** - Core patching framework (pre-installed by setup script)
- **VMHide.kext** - VM detection hiding (pre-installed by setup script)

### Misc Tools (Access from Desktop/Supporting_Tools/Misc_Tools/)
- **macrecovery** - Download macOS recovery images
- **GenSMBIOS** - Generate new SMBIOS if needed
- **ProperTree** - Edit config.plist files
- **ocvalidate** - Validate OpenCore configuration
- **MountEFI** - Mount EFI partitions easily
- And many more utilities...

---

## ⚙️ Technical Details

### VM Configuration
- **CPU Model**: Skylake-Client-v4 with CPUID model 165
- **Performance**: ~30-44% faster than host passthrough
- **Compatibility**: Works on both Intel and AMD Proxmox hosts

### Reference Documentation
- QEMU CPU Optimization Guide for macOS VMs
- OpenCore Documentation: Included in Supporting_Tools
- Dortania Guide: https://dortania.github.io/

---

## 🆘 Troubleshooting

### macOS Won't Boot
- Ensure your VM has proper TSC configuration
- Check that OVMF (UEFI) firmware is enabled
- Verify boot order in Proxmox (IDE0 should be first)

### iServices Not Working
- Verify your serial number is valid at https://checkcoverage.apple.com
- If "Purchase Date not validated", your serial is good for iServices
- If API-validated, it should work out of the box

### Need to Change SMBIOS?
Use GenSMBIOS from Supporting_Tools to generate a new serial, then update config.plist using ProperTree.

---

## 📬 Support

**Created by Mario Aldayuz (thenotoriousllama)**  
Website: [aldayuz.com](https://aldayuz.com)  
Email: [mario@aldayuz.com](mailto:mario@aldayuz.com)

---

**Built with ❤️ for the Hackintosh community**
EOF

    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to generate ISO README" >&2
        log_message "ERROR: Failed to generate ISO README"
        return 1
    fi
    
    echo "  ✓ README.md generated successfully" >&2
    log_message "ISO README generated successfully"
    return 0
}

#
# generate_build_info() - Generate BUILD_INFO.txt with metadata
#
generate_build_info() {
    local build_dir="$1"
    
    echo "→ Generating BUILD_INFO.txt..." >&2
    log_message "Generating BUILD_INFO.txt..."
    
    # Extract SMBIOS information
    local serial=$(jq -r '.Serial // "Unknown"' "$SMBIOS_JSON")
    local mac_model=$(jq -r '.Type // "Unknown"' "$SMBIOS_JSON")
    local board_serial=$(jq -r '."Board Serial" // "Unknown"' "$SMBIOS_JSON")
    local system_uuid=$(jq -r '.SmUUID // "Unknown"' "$SMBIOS_JSON")
    local rom=$(jq -r '.ROM // "Unknown"' "$SMBIOS_JSON")
    local build_date=$(date '+%Y-%m-%d %H:%M:%S')
    local build_timestamp=$(date '+%s')
    
    # Generate build info
    cat > "${build_dir}/BUILD_INFO.txt" << EOF
═══════════════════════════════════════════════════════════
  HACKINTOSHSTER CUSTOM OPENCORE ISO - BUILD INFORMATION
═══════════════════════════════════════════════════════════

BUILD METADATA
--------------
Build Date:       ${build_date}
Build Timestamp:  ${build_timestamp}
EFI Source:       ${EFI_SOURCE}
OpenCore Version: 1.0.6

SMBIOS INFORMATION
------------------
Mac Model:        ${mac_model}
Serial Number:    ${serial}
Board Serial:     ${board_serial}
System UUID:      ${system_uuid}
ROM Address:      ${rom}

VM CONFIGURATION
----------------
CPU Model:        Skylake-Client-v4
CPUID:            Model 165 (Comet Lake)
Platform:         Proxmox VE (Intel & AMD compatible)
Performance:      ~30-44% faster than host passthrough

INCLUDED COMPONENTS
-------------------
✓ EFI/                   Pre-configured bootloader
✓ Supporting_Tools/      Complete toolset
✓ macOS-Setup.command    Automated setup script
✓ README.md              User documentation
✓ COPYRIGHT.md           Legal information

REFERENCES
----------
- QEMU CPU Optimization Guide for macOS VMs
- OpenCore:   https://github.com/acidanthera/OpenCorePkg
- Project:    https://github.com/marioaldayuz/hackintoshster-main

═══════════════════════════════════════════════════════════
           Built by Hackintoshster v2025.11.23
═══════════════════════════════════════════════════════════
EOF

    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to generate BUILD_INFO.txt" >&2
        log_message "ERROR: Failed to generate BUILD_INFO.txt"
        return 1
    fi
    
    echo "  ✓ BUILD_INFO.txt generated successfully" >&2
    log_message "BUILD_INFO.txt generated successfully"
    return 0
}

#
# generate_setup_command() - Generate macOS setup .command script
#
generate_setup_command() {
    local build_dir="$1"
    local serial_number=$(jq -r '.Serial // empty' "$SMBIOS_JSON")
    
    echo "→ Generating macOS-Setup.command script..." >&2
    log_message "Generating macOS setup .command script..."
    
    # Call the generate script
    "${SCRIPT_DIR}/scripts/generate-macos-setup.sh" \
        --output "${build_dir}/macOS-Setup.command" \
        --serial "$serial_number"
    
    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to generate setup .command script" >&2
        log_message "ERROR: Failed to generate setup .command script"
        return 1
    fi
    
    echo "  ✓ macOS-Setup.command generated successfully" >&2
    log_message "macOS setup script generated successfully"
    return 0
}

#
# create_bootable_iso() - Create bootable ISO from build directory
#
create_bootable_iso() {
    local build_dir="$1"
    local serial_number=$(jq -r '.Serial // empty' "$SMBIOS_JSON")
    
    # Validate serial number was extracted
    if [ -z "$serial_number" ] || [ "$serial_number" == "null" ]; then
        echo "  ERROR: Failed to extract serial number from SMBIOS JSON" >&2
        log_message "ERROR: Serial number is empty or null"
        log_message "  SMBIOS_JSON path: $SMBIOS_JSON"
        log_message "  SMBIOS_JSON contents: $(cat "$SMBIOS_JSON" 2>&1)"
        return 2
    fi
    
    local iso_name="OpenCore-${serial_number}.iso"
    local iso_path="${OUTPUT_DIR}/${iso_name}"
    
    echo "→ Creating bootable ISO: $iso_name..." >&2
    log_message "Creating bootable ISO: $iso_name..."
    log_message "  Serial: $serial_number"
    
    # Determine which tool to use (genisoimage preferred, mkisofs fallback)
    local iso_cmd=""
    if command -v genisoimage &> /dev/null; then
        iso_cmd="genisoimage"
    elif command -v mkisofs &> /dev/null; then
        iso_cmd="mkisofs"
    else
        echo "  ERROR: Neither genisoimage nor mkisofs found" >&2
        log_message "ERROR: Neither genisoimage nor mkisofs found"
        return 2
    fi
    
    echo "  Using ISO creation tool: $iso_cmd" >&2
    log_message "Using ISO creation tool: $iso_cmd"
    log_message "  Build directory: $build_dir"
    log_message "  Output path: $iso_path"
    
    # Create the ISO with El Torito boot specification for UEFI
    # The -apple flag enables Apple extensions for better macOS compatibility
    # Boot from BOOT.img (FAT32 image containing EFI directory)
    echo "  Building ISO (this may take 30-60 seconds)..." >&2
    log_message "  ISO command: $iso_cmd -D -V OPENCORE -no-pad -r -apple -file-mode 0555 -dir-mode 0555 -eltorito-alt-boot -e BOOT.img -no-emul-boot -c boot.catalog -o $iso_path $build_dir"
    $iso_cmd \
        -D \
        -V "OPENCORE" \
        -no-pad \
        -r \
        -apple \
        -file-mode 0555 \
        -dir-mode 0555 \
        -eltorito-alt-boot \
        -e BOOT.img \
        -no-emul-boot \
        -c boot.catalog \
        -o "$iso_path" \
        "$build_dir" \
        >> "$LOG_FILE" 2>&1
    
    local iso_exit=$?
    
    if [ $iso_exit -ne 0 ]; then
        echo "  ERROR: ISO creation failed (exit code: $iso_exit)" >&2
        log_message "ERROR: ISO creation failed (exit code: $iso_exit)"
        log_message "  Last 20 lines of ISO creation output:"
        tail -20 "$LOG_FILE" >> "$LOG_FILE"
        return 2
    fi
    
    # Verify the ISO was created
    if [ ! -f "$iso_path" ]; then
        echo "  ERROR: ISO file was not created: $iso_path" >&2
        log_message "ERROR: ISO file was not created: $iso_path"
        return 2
    fi
    
    # Get ISO size
    local iso_size=$(du -h "$iso_path" | awk '{print $1}')
    
    # Check if ISO is empty (0 bytes)
    if [ "$iso_size" == "0B" ] || [ ! -s "$iso_path" ]; then
        echo "  ERROR: ISO file is empty (0 bytes)" >&2
        log_message "ERROR: ISO file is empty: $iso_path"
        log_message "  Build directory contents:"
        ls -laR "$build_dir" >> "$LOG_FILE" 2>&1
        return 2
    fi
    
    echo "  ✓ ISO created successfully ($iso_size)" >&2
    log_message "ISO created successfully: $iso_path ($iso_size)"
    
    # Return ISO name - either to file or stdout
    if [ -n "$OUTPUT_NAME_FILE" ]; then
        echo "$iso_name" > "$OUTPUT_NAME_FILE"
        log_message "ISO name written to: $OUTPUT_NAME_FILE"
    else
        echo "$iso_name"
    fi
    
    return 0
}

#
# cleanup_build_dir() - Remove temporary build directory
#
cleanup_build_dir() {
    local build_dir="$1"
    
    if [ -z "$build_dir" ]; then
        return 0
    fi
    
    echo "→ Cleaning up build directory..." >&2
    log_message "Cleaning up build directory: $build_dir"
    
    # Check if it's in /tmp or in TMPDIR (which might be /root/hackintoshster-main/tmp)
    if [[ "$build_dir" == /tmp/* ]] || [[ "$build_dir" == */hackintoshster-main/tmp/* ]]; then
        rm -rf "$build_dir" 2>/dev/null || {
            echo "  WARNING: Failed to cleanup build directory" >&2
            log_message "WARNING: Failed to cleanup build directory: $build_dir"
            return 3
        }
        echo "  ✓ Build directory cleaned up" >&2
        log_message "Build directory cleaned up"
    else
        echo "  WARNING: Build directory not in expected location, skipping cleanup" >&2
        log_message "WARNING: Build directory not in expected location: $build_dir"
    fi
    
    return 0
}

#
# main() - Main entry point
#
main() {
    log_message "═══════════════════════════════════════════════════════════"
    log_message "Starting Custom OpenCore ISO Build Process"
    log_message "═══════════════════════════════════════════════════════════"
    
    parse_arguments "$@"
    validate_dependencies
    validate_inputs
    
    local build_dir
    build_dir=$(create_build_directory)
    local build_exit=$?
    
    if [ $build_exit -ne 0 ]; then
        exit $build_exit
    fi
    
    # Track if we need cleanup
    local cleanup_needed=true
    local final_exit_code=0
    
    # Build process
    if ! copy_base_efi "$build_dir"; then
        final_exit_code=2
    elif ! inject_smbios "$build_dir"; then
        final_exit_code=2
    elif ! create_boot_image_from_efi "$build_dir"; then
        final_exit_code=2
    elif ! copy_supporting_tools "$build_dir"; then
        final_exit_code=2
    elif ! copy_copyright "$build_dir"; then
        final_exit_code=2
    elif ! generate_iso_readme "$build_dir"; then
        final_exit_code=2
    elif ! generate_build_info "$build_dir"; then
        final_exit_code=2
    elif ! generate_setup_command "$build_dir"; then
        final_exit_code=2
    else
        local iso_name
        iso_name=$(create_bootable_iso "$build_dir")
        local iso_exit=$?
        
        if [ $iso_exit -ne 0 ]; then
            final_exit_code=$iso_exit
        else
            echo >&2
            echo "═══════════════════════════════════════════════════════════" >&2
            echo "  Custom OpenCore ISO Build Complete!" >&2
            echo "  ISO File: ${OUTPUT_DIR}/${iso_name}" >&2
            echo "═══════════════════════════════════════════════════════════" >&2
            log_message "═══════════════════════════════════════════════════════════"
            log_message "Custom OpenCore ISO Build Complete!"
            log_message "ISO File: ${OUTPUT_DIR}/${iso_name}"
            log_message "═══════════════════════════════════════════════════════════"
        fi
    fi
    
    # Cleanup
    if [ "$cleanup_needed" = true ]; then
        cleanup_build_dir "$build_dir"
        # Don't change exit code based on cleanup failure (exit code 3)
        if [ $? -eq 3 ] && [ $final_exit_code -eq 0 ]; then
            final_exit_code=3
        fi
    fi
    
    exit $final_exit_code
}

# Run main function
main "$@"

