#!/bin/bash
#
# vm-configurator.sh - VM configuration interface for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script handles user interaction for VM configuration (interactive and CLI modes).
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"
source "${SCRIPT_DIR}/scripts/lib/validation.sh"
source "${SCRIPT_DIR}/scripts/lib/math-utils.sh"
source "${SCRIPT_DIR}/scripts/lib/profiles.sh"
source "${SCRIPT_DIR}/scripts/storage/storage-manager.sh"
source "${SCRIPT_DIR}/scripts/network/bridge-manager.sh"
source "${SCRIPT_DIR}/scripts/recovery/recovery-manager.sh"
source "${SCRIPT_DIR}/scripts/opencore/opencore-manager.sh"
source "${SCRIPT_DIR}/scripts/vm/vm-creator.sh"

# Non-interactive VM creation using CLI arguments
create_vm_noninteractive() {
  local logfile="${LOGDIR}/cli-vm-creation.log"
  
  # Validate version
  local macos_option=""
  case "${CLI_VERSION,,}" in
    sequoia) macos_option="1" ;;
    tahoe) macos_option="2" ;;
    *)
      display_and_log "❌ Error: Invalid macOS version: $CLI_VERSION" "$logfile"
      display_and_log "   Valid options: 'sequoia' or 'tahoe'" "$logfile"
      log_and_exit "Invalid version specified" "$logfile"
      ;;
  esac
  
  local macopt="${MACOS_CONFIG[$macos_option]}"
  local version_name version board_id model_id iso_size disk_type
  IFS='|' read -r version_name version board_id model_id iso_size disk_type <<< "$macopt"
  
  # Set VM ID (use next available if not specified)
  local vm_id="${CLI_VM_ID:-$(pvesh get /cluster/nextid)}"
  
  # Validate VM ID doesn't exist
  if [[ -e "/etc/pve/qemu-server/$vm_id.conf" ]]; then
    display_and_log "❌ Error: VM ID $vm_id already exists" "$logfile"
    display_and_log "   Try a different ID or use --vmid to specify another" "$logfile"
    display_and_log "   List existing VMs: qm list" "$logfile"
    log_and_exit "VM ID conflict" "$logfile"
  fi
  
  # Set VM name (use default if not specified)
  local vm_name="${CLI_VM_NAME:-${DEFAULT_VM_PREFIX}$(echo "$version_name" | tr -s ' ' | sed 's/^[ ]*//;s/[ ]*$//;s/[ ]/-/g' | tr '[:lower:]' '[:upper:]' | sed 's/-*$//')}"
  
  if ! validate_vm_name "$vm_name"; then
    display_and_log "❌ Error: Invalid VM name: $vm_name" "$logfile"
    display_and_log "   VM names must use alphanumeric characters, -, _, . only (no spaces)" "$logfile"
    log_and_exit "Invalid VM name" "$logfile"
  fi
  
  # Handle profile or individual settings
  local disk_size cores ram
  
  if [[ -n "$CLI_PROFILE" ]]; then
    # Use profile
    if ! validate_profile_name "$CLI_PROFILE"; then
      display_and_log "❌ Error: Invalid profile: $CLI_PROFILE" "$logfile"
      display_and_log "   Valid profiles: minimal, balanced, performance, maximum" "$logfile"
      log_and_exit "Invalid profile specified" "$logfile"
    fi
    
    IFS='|' read -r cores ram disk_size <<< "$(get_profile_values "$CLI_PROFILE")"
    display_and_log "Using profile: $CLI_PROFILE" "$logfile"
    display_and_log "  CPU Cores: $cores" "$logfile"
    display_and_log "  RAM: $((ram / 1024))GB" "$logfile"
    display_and_log "  Disk: ${disk_size}GB" "$logfile"
  else
    # Use individual settings or defaults
    disk_size="${CLI_DISK_SIZE:-80}"
    cores="${CLI_CORES:-4}"
    
    # Adjust cores to power of 2 if needed
    if ! is_power_of_2 "$cores"; then
      cores=$(next_power_of_2 "$cores")
      display_and_log "Adjusted cores to power of 2: $cores" "$logfile"
    fi
    ((cores > MAX_CORES)) && cores=$MAX_CORES
    
    # Set RAM (auto-calculate if not specified)
    ram="${CLI_RAM:-$((BASE_RAM_SIZE + cores * RAM_PER_CORE))}"
  fi
  
  # Get storage
  local storage="${CLI_STORAGE}"
  if [[ -z "$storage" ]]; then
    local storage_output=$(get_available_storages) || {
      display_and_log "❌ Error: Failed to retrieve available storages" "$logfile"
      display_and_log "   Check Proxmox storage configuration" "$logfile"
      log_and_exit "Storage detection failed" "$logfile"
    }
    local default_storage=$(echo "$storage_output" | tail -1)
    storage="$default_storage"
  fi
  
  # Get bridge
  local bridge="${CLI_BRIDGE:-vmbr0}"
  if [[ ! -d "/sys/class/net/$bridge" ]]; then
    display_and_log "❌ Error: Network bridge '$bridge' does not exist" "$logfile"
    display_and_log "   Available bridges: $(ls -1 /sys/class/net/ | grep vmbr | tr '\n' ' ')" "$logfile"
    log_and_exit "Bridge not found" "$logfile"
  fi
  
  # Download recovery image if requested
  if [[ "${CLI_DOWNLOAD_RECOVERY}" == "yes" ]]; then
    download_recovery_image "$version_name" "$board_id" "$model_id" "$iso_size"
  fi
  
  # Create VM
  display_and_log "Creating VM with following configuration:" "$logfile"
  display_and_log "  Version: macOS $version_name ($version)" "$logfile"
  display_and_log "  VM ID: $vm_id" "$logfile"
  display_and_log "  VM Name: $vm_name" "$logfile"
  display_and_log "  Disk: ${disk_size}GB" "$logfile"
  display_and_log "  Storage: $storage" "$logfile"
  display_and_log "  Bridge: $bridge" "$logfile"
  display_and_log "  Cores: $cores" "$logfile"
  display_and_log "  RAM: ${ram}MiB" "$logfile"
  
  create_vm "$version_name" "$vm_id" "$vm_name" "$disk_size" "$storage" "$cores" "$ram" "$iso_size" "$disk_type" "$bridge"
  
  display_and_log "VM created successfully!" "$logfile"
  display_and_log "Start VM: qm start $vm_id" "$logfile"
  display_and_log "View console: Open Proxmox web UI and navigate to VM $vm_id" "$logfile"
}
# Interactive VM configuration wizard for modern macOS (15+)
# Collects: VM ID, name, disk size (default 80GB), storage, bridge, cores, RAM
# All VMs use VirtIO storage/networking, Skylake-Client-v4 CPU, XHCI USB
# Validates inputs and prevents conflicts with existing VMs
# Called from main menu when user selects macOS Sequoia or Tahoe
configure_macos_vm() {
  local macopt=$1
  local nextid=$2
  local version_name version board_id model_id iso_size disk_type opt=$3
  # Parse macOS configuration string from MACOS_CONFIG array
  IFS='|' read -r version_name version board_id model_id iso_size disk_type <<< "$macopt"
  # Generate default VM name from version (e.g., "macOS-SEQUOIA" or "macOS-TAHOE")
  local default_vm_name="${DEFAULT_VM_PREFIX}$(echo "$version_name" | tr -s ' ' | sed 's/^[ ]*//;s/[ ]*$//;s/[ ]/-/g' | tr '[:lower:]' '[:upper:]' | sed 's/-*$//')"
  validate_vm_name "$default_vm_name" || log_and_exit "Invalid default VM name: $default_vm_name" "${LOGDIR}/main-menu.log"
  clear
  display_and_log "══════════════════════════════════════════════════"
  display_and_log "  Configuring macOS $version_name VM"
  display_and_log "══════════════════════════════════════════════════"

  # Prompt for unique VM ID with validation against existing configurations
  while true; do
    read -rp "VM ID [${nextid}]: " VM_ID
    VM_ID=${VM_ID:-$nextid}
    if [[ "$VM_ID" =~ ^[0-9]+$ && ! -e "/etc/pve/qemu-server/$VM_ID.conf" ]]; then
      break
    else
      display_and_log "Invalid or existing VM ID. Please try again."
    fi
  done

  # Prompt for VM name with character validation
  while true; do
    read -rp "VM Name [${default_vm_name}]: " VM_NAME
    VM_NAME=${VM_NAME:-$default_vm_name}
    if validate_vm_name "$VM_NAME"; then
      break
    else
      display_and_log "Invalid VM name. Please use alphanumeric characters, -, _, .; no spaces."
    fi
  done

  echo
  echo "══════════════════════════════════════════════════"
  echo "  VM Configuration Profile"
  echo "══════════════════════════════════════════════════"
  echo
  
  # Profile selection
  local selected_profile=$(select_profile_interactive)
  local SIZEDISK PROC_COUNT RAM_SIZE
  
  if [[ "$selected_profile" == "custom" ]]; then
    # Custom configuration - will prompt for each value individually later
    USE_CUSTOM_CONFIG=true
  else
    # Use profile values
    IFS='|' read -r PROC_COUNT RAM_SIZE SIZEDISK <<< "$(get_profile_values "$selected_profile")"
    USE_CUSTOM_CONFIG=false
    
    echo
    echo "Profile configuration applied:"
    echo "  CPU Cores: $PROC_COUNT"
    echo "  RAM: $((RAM_SIZE / 1024))GB ($RAM_SIZE MiB)"
    echo "  Disk: ${SIZEDISK}GB"
    echo
    read -rp "Continue with these settings? (y/n): " confirm_profile
    if [[ ! "$confirm_profile" =~ ^[Yy]$ ]]; then
      display_and_log "Configuration cancelled. Returning to menu..."
      read -n 1 -sp "Press any key to continue..."
      return 1
    fi
  fi

  echo
  echo "══════════════════════════════════════════════════"
  echo "  Building Custom OpenCore ISO"
  echo "══════════════════════════════════════════════════"
  echo
  
  # Build custom OpenCore ISO with PROXMOX-EFI base
  local CUSTOM_ISO_NAME
  local temp_output="${TMPDIR}/.iso-output-$$"
  
  # Run the builder, show output to user, and capture to file
  build_custom_opencore_iso | tee "$temp_output"
  local build_result=${PIPESTATUS[0]}
  
  # Extract only the ISO filename (last line that ends with .iso)
  if [ $build_result -eq 0 ]; then
    CUSTOM_ISO_NAME=$(grep '\.iso$' "$temp_output" | tail -1)
  fi
  rm -f "$temp_output"
  
  if [ $build_result -ne 0 ] || [ -z "$CUSTOM_ISO_NAME" ]; then
    display_and_log "Failed to build custom ISO. Cannot proceed with VM creation."
    read -n 1 -sp "Press any key to return to menu..."
    return 1
  fi
  
  display_and_log "Custom ISO ready for VM creation: $CUSTOM_ISO_NAME"
  read -n 1 -sp "Press any key to continue with VM configuration..."
  echo
  echo

  # Modern macOS 15+ requires more disk space - default to 80GB
  # Only prompt if using custom config (profile already set this)
  if [[ "$USE_CUSTOM_CONFIG" == "true" ]]; then
    local default_disk_size=80
    while true; do
      read -rp "Disk size (GB) [default: $default_disk_size]: " SIZEDISK
      SIZEDISK=${SIZEDISK:-$default_disk_size}
      if [[ "$SIZEDISK" =~ ^[0-9]+$ ]]; then
        break
      else
        display_and_log "Disk size must be an integer. Please try again."
      fi
    done
  fi

  # Storage Selection
  local storage_output=$(get_available_storages) || { display_and_log "Failed to retrieve storages"; read -n 1 -s; return 1; }
  local storages=() default_storage=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ -z "$default_storage" && ! "$line" =~ \| ]] && default_storage="$line" || storages+=("$line")
  done <<< "$storage_output"
  if ((${#storages[@]} == 0)); then
    display_and_log "No storages found"; read -n 1 -s; return 1
  fi
  if ((${#storages[@]} == 1)); then
    STORAGECRTVM="${storages[0]%%|*}"
    display_and_log "Using storage: $STORAGECRTVM"
  else
    while true; do
      display_and_log "Available storages:"
      for s in "${storages[@]}"; do
        storage_name="${s%%|*}"
        avail_space="${s##*|}"
        display_and_log "  - $storage_name ($avail_space GB)"
      done
      read -rp "Storage [${default_storage}]: " STORAGECRTVM
      STORAGECRTVM=${STORAGECRTVM:-$default_storage}
      local valid=false
      for s in "${storages[@]}"; do
        if [[ "$STORAGECRTVM" == "${s%%|*}" ]]; then
          valid=true
          break
        fi
      done
      if $valid; then
        display_and_log "Selected storage: $STORAGECRTVM"
        break
      else
        display_and_log "Invalid storage. Please try again."
      fi
    done
  fi

  # Bridge Selection
  local bridge_output=$(get_available_bridges) || { display_and_log "Failed to retrieve bridges"; read -n 1 -s; return 1; }
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
    display_and_log "No bridges found"; read -n 1 -s; return 1
  fi

  declare -A bridge_info
  for b in "${bridges[@]}"; do
    IFS='|' read -r bridge_name ip_addr <<< "$b"
    bridge_info["$bridge_name"]="IP address: ${ip_addr:-unknown}"
  done

  mapfile -t sorted_names < <(printf '%s\n' "${!bridge_info[@]}" | sort -V)

  local default_bridge_num=${default_bridge#vmbr}
  if ((${#bridges[@]} == 1)); then
    name="${sorted_names[0]}"
    ip_info="${bridge_info[$name]}"
    BRIDGECRTVM="$name"
    display_and_log "Using bridge: $BRIDGECRTVM ($ip_info)"
  else
    while true; do
      display_and_log "Available bridges:"
      for name in "${sorted_names[@]}"; do
        bridge_num=${name#vmbr}
        ip_info="${bridge_info[$name]}"
        display_and_log "  - $bridge_num ($name, $ip_info)"
      done
      read -rp "Bridge number [${default_bridge_num}]: " BRIDGE_NUM
      BRIDGE_NUM=${BRIDGE_NUM:-$default_bridge_num}
      if [[ "$BRIDGE_NUM" =~ ^[0-9]+$ ]]; then
        BRIDGECRTVM="vmbr$BRIDGE_NUM"
        if [[ -n "${bridge_info[$BRIDGECRTVM]}" ]]; then
          display_and_log "Selected bridge: $BRIDGECRTVM"
          break
        else
          display_and_log "Invalid bridge number. Please try again."
        fi
      else
        display_and_log "Bridge number must be an integer. Please try again."
      fi
    done
  fi

  # CPU Cores and RAM (only prompt if using custom config)
  if [[ "$USE_CUSTOM_CONFIG" == "true" ]]; then
    # CPU Cores (power of 2 recommended for macOS: 1, 2, 4, 8, 16)
    while true; do
      display_and_log "\nRecommended CPU cores (power of 2): 1, 2, 4, 8, 16"
      read -rp "CPU cores [4]: " PROC_COUNT
      PROC_COUNT=${PROC_COUNT:-4}
      if [[ "$PROC_COUNT" =~ ^[0-9]+$ ]]; then
        if ! is_power_of_2 "$PROC_COUNT"; then
          PROC_COUNT=$(next_power_of_2 "$PROC_COUNT")
          display_and_log "→ Adjusted to next power of 2: $PROC_COUNT"
        fi
        break
      else
        display_and_log "→ CPU cores must be an integer. Please try again."
      fi
    done
    ((PROC_COUNT > MAX_CORES)) && PROC_COUNT=$MAX_CORES

    # RAM (modern macOS 15+ benefits from more RAM)
    while true; do
      default_ram=$((BASE_RAM_SIZE + PROC_COUNT * RAM_PER_CORE))
      display_and_log "\nRecommended RAM: ${default_ram} MiB (minimum 4GB for macOS 15+)"
      read -rp "RAM in MiB [$default_ram]: " RAM_SIZE
      RAM_SIZE=${RAM_SIZE:-$default_ram}
      if [[ "$RAM_SIZE" =~ ^[0-9]+$ ]]; then
        break
      else
        display_and_log "→ RAM must be an integer. Please try again."
      fi
    done
  fi

  # Recovery image download (downloads macOS installer from Apple servers)
  echo
  display_and_log "Download macOS recovery image from Apple?"
  display_and_log "(Required for first-time installation, can skip if already downloaded)"
  read -rp "Download recovery image? [Y/n]: " CRTRECODISK
  [[ "${CRTRECODISK:-Y}" =~ ^[Yy]$ ]] && download_recovery_image "$version_name" "$board_id" "$model_id" "$iso_size"
  # Execute VM creation with all collected parameters (including custom ISO)
  create_vm "$version_name" "$VM_ID" "$VM_NAME" "$SIZEDISK" "$STORAGECRTVM" "$PROC_COUNT" "$RAM_SIZE" "$iso_size" "$disk_type" "$BRIDGECRTVM" "$CUSTOM_ISO_NAME"
  
  # Post-creation information about custom ISO
  echo
  display_and_log "╔═══════════════════════════════════════════════════════════╗"
  display_and_log "║ VM Creation Complete                                      ║"
  display_and_log "╚═══════════════════════════════════════════════════════════╝"
  display_and_log "Your VM has been created with a custom OpenCore ISO:"
  display_and_log "  ISO: $CUSTOM_ISO_NAME"
  display_and_log "  Location: $ISODIR"
  echo
  display_and_log "After successful macOS installation and setup, you can:"
  display_and_log "  1. Remove the custom ISO from your VM's CD drive in Proxmox"
  display_and_log "  2. Delete the ISO file to free up space:"
  display_and_log "     rm ${ISODIR}/${CUSTOM_ISO_NAME}"
  echo
  read -n 1 -sp "Press any key to return to menu..."
}

# Export functions for use in other scripts
export -f create_vm_noninteractive
export -f configure_macos_vm
