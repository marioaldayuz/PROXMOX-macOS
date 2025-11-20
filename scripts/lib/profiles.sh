#!/bin/bash
#
# profiles.sh - VM profile management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides predefined VM configuration profiles and custom profile support.
# Source this file: source "${SCRIPT_DIR}/scripts/lib/profiles.sh"
#

# Get the directory where this script is located
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/validation.sh"

# Profile definitions
# Each profile contains: cores|ram|disk_size
declare -gA VM_PROFILES=(
  ["minimal"]="4|8192|80|Minimal (4 cores, 8GB RAM, 80GB disk) - Basic macOS usage"
  ["balanced"]="8|16384|120|Balanced (8 cores, 16GB RAM, 120GB disk) - Recommended for most users"
  ["performance"]="12|24576|200|Performance (12 cores, 24GB RAM, 200GB disk) - Development & content creation"
  ["maximum"]="16|32768|300|Maximum (16 cores, 32GB RAM, 300GB disk) - Heavy workloads & compilation"
)

# Display available profiles with descriptions
# Returns: Nothing (displays to terminal)
display_profiles() {
  # Output to /dev/tty to ensure display even when called in command substitution
  {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ VM CONFIGURATION PROFILES                                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo
    
    local profile_num=1
    for profile in minimal balanced performance maximum; do
      IFS='|' read -r cores ram disk desc <<< "${VM_PROFILES[$profile]}"
      printf " %d - %s\n" "$profile_num" "$desc"
      ((profile_num++))
    done
    
    echo " 5 - Custom (specify your own values)"
    echo
  } >&2
}

# Get profile by number (1-5)
# Parameters: $1 - Profile number
# Returns: Profile name (minimal, balanced, performance, maximum, custom)
get_profile_by_number() {
  local num=$1
  case $num in
    1) echo "minimal" ;;
    2) echo "balanced" ;;
    3) echo "performance" ;;
    4) echo "maximum" ;;
    5) echo "custom" ;;
    *) return 1 ;;
  esac
}

# Get profile configuration values
# Parameters: $1 - Profile name (minimal, balanced, performance, maximum)
# Returns: cores|ram|disk_size (separated by pipes)
get_profile_values() {
  local profile=$1
  
  if [[ -z "${VM_PROFILES[$profile]}" ]]; then
    return 1
  fi
  
  IFS='|' read -r cores ram disk _ <<< "${VM_PROFILES[$profile]}"
  echo "$cores|$ram|$disk"
}

# Interactive profile selection with validation
# Returns: Selected profile name to stdout
select_profile_interactive() {
  local logfile="${LOGDIR}/profile-selection.log"
  
  while true; do
    display_profiles
    read -rp "Select profile (1-5): " profile_choice </dev/tty
    
    local profile_name=$(get_profile_by_number "$profile_choice")
    if [[ $? -eq 0 && -n "$profile_name" ]]; then
      if [[ "$profile_name" == "custom" ]]; then
        echo "custom"
        return 0
      else
        IFS='|' read -r cores ram disk desc <<< "${VM_PROFILES[$profile_name]}"
        {
          echo
          echo "Selected: $desc"
          echo "  CPU Cores: $cores"
          echo "  RAM: $((ram / 1024))GB"
          echo "  Disk: ${disk}GB"
          echo
        } >&2
        read -rp "Confirm selection? (y/n): " confirm </dev/tty
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          echo "$profile_name"
          return 0
        fi
      fi
    else
      {
        echo "Invalid selection. Please enter 1-5."
      } >&2
      sleep 1
    fi
  done
}

# Get custom configuration values interactively
# Returns: cores|ram|disk_size (separated by pipes)
get_custom_config_interactive() {
  local cores ram disk
  
  {
    echo
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ CUSTOM VM CONFIGURATION                                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo
  } >&2
  
  # Get CPU cores
  while true; do
    read -rp "CPU cores (2-${MAX_CORES}, recommended power of 2): " cores </dev/tty
    if validate_cpu_cores "$cores" && (( cores >= 2 && cores <= MAX_CORES )); then
      # Check if power of 2
      if (( (cores & (cores - 1)) != 0 )); then
        echo "⚠️  Warning: $cores is not a power of 2. macOS may not detect all cores correctly." >&2
        read -rp "Continue anyway? (y/n): " continue_choice </dev/tty
        [[ "$continue_choice" =~ ^[Yy]$ ]] && break
      else
        break
      fi
    else
      echo "❌ Invalid input. Enter a number between 2 and ${MAX_CORES}." >&2
    fi
  done
  
  # Get RAM
  while true; do
    read -rp "RAM in GB (4-256): " ram_gb </dev/tty
    if [[ "$ram_gb" =~ ^[0-9]+$ ]] && (( ram_gb >= 4 && ram_gb <= 256 )); then
      ram=$((ram_gb * 1024))
      break
    else
      echo "❌ Invalid input. Enter a number between 4 and 256." >&2
    fi
  done
  
  # Get disk size
  while true; do
    read -rp "Disk size in GB (60-2000): " disk </dev/tty
    if validate_disk_size "$disk" && (( disk >= 60 && disk <= 2000 )); then
      break
    else
      echo "❌ Invalid input. Enter a number between 60 and 2000." >&2
    fi
  done
  
  {
    echo
    echo "Custom configuration:"
    echo "  CPU Cores: $cores"
    echo "  RAM: ${ram_gb}GB"
    echo "  Disk: ${disk}GB"
    echo
  } >&2
  
  echo "$cores|$ram|$disk"
}

# Validate profile name from CLI
# Parameters: $1 - Profile name
# Returns: 0 if valid, 1 if invalid
validate_profile_name() {
  local profile=$1
  [[ "$profile" =~ ^(minimal|balanced|performance|maximum|custom)$ ]]
}

# Export functions for use in other scripts
export -f display_profiles
export -f get_profile_by_number
export -f get_profile_values
export -f select_profile_interactive
export -f get_custom_config_interactive
export -f validate_profile_name


