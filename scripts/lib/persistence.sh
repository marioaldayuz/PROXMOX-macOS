#!/bin/bash
#
# persistence.sh - User preferences and persistent configuration for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides functionality to store and retrieve user preferences
# across multiple script executions.
#

# Get the directory where this script is located
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Configuration file location
export PERSISTENCE_FILE="/etc/pve/qemu-server/.PROXMOX-macOS-config"

# Initialize persistence file if it doesn't exist
init_persistence() {
  if [[ ! -f "$PERSISTENCE_FILE" ]]; then
    mkdir -p "$(dirname "$PERSISTENCE_FILE")" 2>/dev/null || true
    cat > "$PERSISTENCE_FILE" << 'EOF'
# HACKINTOSHSTER-PROXMOX User Preferences
# This file stores user preferences and default configurations
# Edit with caution or use the interactive menu options

# Network preferences
DEFAULT_BRIDGE=""

# Profile preferences
DEFAULT_PROFILE=""
DEFAULT_STORAGE=""

# System preferences
IS_ENTERPRISE=""
EOF
    chmod 600 "$PERSISTENCE_FILE"
  fi
}

# Get a configuration value
# Parameters: $1 - Key name
# Returns: Value or empty string
get_config_value() {
  local key=$1
  init_persistence
  
  if [[ -f "$PERSISTENCE_FILE" ]]; then
    # Extract value, handling both quoted and unquoted values
    local value=$(grep "^${key}=" "$PERSISTENCE_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
    echo "$value"
  fi
}

# Set a configuration value
# Parameters: $1 - Key name, $2 - Value
# Returns: 0 on success, 1 on failure
set_config_value() {
  local key=$1
  local value=$2
  init_persistence
  
  # Escape special characters in value
  local escaped_value=$(echo "$value" | sed 's/[&/\]/\\&/g')
  
  if grep -q "^${key}=" "$PERSISTENCE_FILE"; then
    # Update existing key
    sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" "$PERSISTENCE_FILE"
  else
    # Add new key before EOF or at end
    echo "${key}=\"${escaped_value}\"" >> "$PERSISTENCE_FILE"
  fi
}

# Remove a configuration value
# Parameters: $1 - Key name
# Returns: 0 on success
remove_config_value() {
  local key=$1
  init_persistence
  
  if [[ -f "$PERSISTENCE_FILE" ]]; then
    sed -i "/^${key}=/d" "$PERSISTENCE_FILE"
  fi
}

# Check if enterprise repository is configured
# Returns: "true" if enterprise, "false" if community
detect_repository_type() {
  local is_enterprise="false"
  
  # Check if already cached
  local cached_value=$(get_config_value "IS_ENTERPRISE")
  if [[ -n "$cached_value" ]]; then
    echo "$cached_value"
    return 0
  fi
  
  # Check if subscription appears to be configured
  if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ] || [ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]; then
    # Enterprise repos exist - check if subscription is active
    if command -v pvesubscription &> /dev/null; then
      SUBSCRIPTION_STATUS=$(pvesubscription get 2>/dev/null | grep -i "status" | head -n1 || echo "")
      
      if echo "$SUBSCRIPTION_STATUS" | grep -qi "active"; then
        is_enterprise="true"
      fi
    fi
  fi
  
  # Cache the result
  set_config_value "IS_ENTERPRISE" "$is_enterprise"
  echo "$is_enterprise"
}

# Get default bridge (with fallback to vmbr0)
# Returns: Bridge name
get_default_bridge() {
  local bridge=$(get_config_value "DEFAULT_BRIDGE")
  if [[ -z "$bridge" ]]; then
    echo "vmbr0"
  else
    echo "$bridge"
  fi
}

# Set default bridge
# Parameters: $1 - Bridge name
set_default_bridge() {
  local bridge=$1
  set_config_value "DEFAULT_BRIDGE" "$bridge"
}

# Get default profile
# Returns: Profile name or empty
get_default_profile() {
  get_config_value "DEFAULT_PROFILE"
}

# Set default profile
# Parameters: $1 - Profile name
set_default_profile() {
  local profile=$1
  set_config_value "DEFAULT_PROFILE" "$profile"
}

# Get default storage
# Returns: Storage name or empty
get_default_storage() {
  get_config_value "DEFAULT_STORAGE"
}

# Set default storage
# Parameters: $1 - Storage name
set_default_storage() {
  local storage=$1
  set_config_value "DEFAULT_STORAGE" "$storage"
}

# Clear all defaults
clear_all_defaults() {
  remove_config_value "DEFAULT_BRIDGE"
  remove_config_value "DEFAULT_PROFILE"
  remove_config_value "DEFAULT_STORAGE"
}

# Export functions for use in other scripts
export -f init_persistence
export -f get_config_value
export -f set_config_value
export -f remove_config_value
export -f detect_repository_type
export -f get_default_bridge
export -f set_default_bridge
export -f get_default_profile
export -f set_default_profile
export -f get_default_storage
export -f set_default_storage
export -f clear_all_defaults

