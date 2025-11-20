#!/bin/bash
#
# bridge-manager.sh - Network bridge management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script manages network bridge detection, creation, and DHCP configuration.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# Network bridge discovery function that scans system for configured virtual bridges
# Parses /etc/network/interfaces for vmbr* definitions and validates they exist in kernel
# Extracts IP addresses assigned to each bridge for display purposes
# Output format: One line per bridge as "vmbr#|IP_address", followed by default bridge name
# Returns: Multi-line output with bridge candidates, defaults to vmbr0 if none found
get_available_bridges() {
  local bridges=()
  local default_bridge="vmbr0"

  # Extract all bridge interface definitions from network config
  local bridge_lines=$(grep -E '^iface vmbr[0-9]+' "$NETWORK_INTERFACES_FILE")
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^iface\ (vmbr[0-9]+) ]]; then
      local bridge_name="${BASH_REMATCH[1]}"
      # Verify bridge actually exists in kernel networking stack
      [[ ! -d "/sys/class/net/$bridge_name" ]] && continue
      # Extract IP address from bridge configuration, stripping CIDR notation
      local address=$(awk "/^iface $bridge_name/{p=1} p&&/^[[:space:]]*address/{print \$2; exit}" "$NETWORK_INTERFACES_FILE" | sed 's|/.*||' | tr -d '\r')
      # Validate extracted address is a proper IPv4 format
      if [[ -n "$address" && "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        bridges+=("$bridge_name|$address")
      else
        bridges+=("$bridge_name|unknown")
      fi
    fi
  done <<< "$bridge_lines"

  # Fallback to vmbr0 if no bridges were discovered
  [[ ${#bridges[@]} -eq 0 ]] && bridges+=("$default_bridge|unknown")
  printf '%s\n' "${bridges[@]}"
  echo "$default_bridge"
}

# Comprehensive network bridge provisioning system for isolated macOS VM networks
# Creates NAT-enabled virtual bridges with optional DHCP server configuration
# Implements automatic rollback on failure to prevent network configuration corruption
# Calculates subnet parameters, validates against existing networks, and configures iptables masquerading
# Menu option: NBR - Add new bridge (macOS in cloud)
configure_network_bridge() {
  local logfile="${LOGDIR}/configure-network-bridge.log"

  # Local error handler that logs and terminates function execution
  die() {
    display_and_log "ERROR: $*" "$logfile"
    return 1
  }

  # Local warning handler for non-fatal issues
  warn() {
    display_and_log "WARNING: $*" "$logfile"
  }

  # Local info handler for progress messages
  info() {
    display_and_log "INFO: $*" "$logfile"
  }

  # Network configuration rollback mechanism to prevent system instability
  # Restores /etc/network/interfaces from timestamped backup if bridge activation fails
  restore_backup() {
    local backup_file="$1"
    info "Restoring network configuration from backup..."
    if [[ -f "$backup_file" ]]; then
      if ! cp "$backup_file" "$NETWORK_INTERFACES_FILE"; then
        die "CRITICAL: Failed to restore network configuration from backup! System may be in unstable state."
      fi
      info "Network configuration successfully restored from backup"
      return 0
    else
      die "CRITICAL: Backup file not found! Network configuration may be corrupted."
    fi
  }

  # DHCP server group provisioning for proper daemon permissions
  ensure_dhcp_group() {
    if ! getent group "$DHCP_USER" >/dev/null; then
      info "Creating DHCP server group '$DHCP_USER'..."
      groupadd "$DHCP_USER" || die "Failed to create group '$DHCP_USER'"
    fi
  }

  # Package dependency installer for network utilities and DHCP server
  # Installs ipcalc for subnet calculations and isc-dhcp-server for IP address management
  ensure_dependencies() {
    local deps=("ipcalc")
    local missing=()

    # Check if ISC DHCP server package is installed
    if ! dpkg -l isc-dhcp-server &>/dev/null; then
      deps+=("isc-dhcp-server")
    fi

    for dep in "${deps[@]}"; do
      if ! command -v "$dep" &>/dev/null && ! dpkg -l "$dep" &>/dev/null; then
        missing+=("$dep")
      fi
    done

    if (( ${#missing[@]} > 0 )); then
      info "Installing missing dependencies: ${missing[*]}"
      apt-get update && apt-get install -y "${missing[@]}" >>"$logfile" 2>&1 || die "Failed to install dependencies"
    fi

    # Create DHCP configuration directory with secure permissions
    mkdir -p "$DHCP_CONF_DIR"
    chown root:root "$DHCP_CONF_DIR"
    chmod 755 "$DHCP_CONF_DIR"
  }

  # Subnet parameter calculator using ipcalc to derive network details from CIDR notation
  # Populates global network_info associative array with network, netmask, broadcast, gateway, and DHCP range
  # Reserves first 50 IPs for static assignments, uses remaining addresses for DHCP pool
  calculate_network() {
    local subnet=$1
    declare -gA network_info

    # Validate CIDR format (e.g., 10.27.1.0/24)
    if [[ ! "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      warn "Invalid subnet format: $subnet"
      return 1
    fi

    # Execute ipcalc to compute network parameters
    if ! ipcalc_output=$(ipcalc -nb "$subnet"); then
      warn "ipcalc failed to process subnet: $subnet"
      return 1
    fi

    # Extract key network values from ipcalc output
    network_info["network"]=$(echo "$ipcalc_output" | awk '/^Network:/ {print $2}' | cut -d'/' -f1)
    network_info["netmask"]=$(echo "$ipcalc_output" | awk '/^Netmask:/ {print $2}')
    network_info["broadcast"]=$(echo "$ipcalc_output" | awk '/^Broadcast:/ {print $2}')
    network_info["hostmin"]=$(echo "$ipcalc_output" | awk '/^HostMin:/ {print $2}')
    network_info["hostmax"]=$(echo "$ipcalc_output" | awk '/^HostMax:/ {print $2}')

    # Reserve .1-.50 for static IPs, use .51-end for DHCP pool
    IFS='.' read -r i1 i2 i3 i4 <<< "${network_info[hostmin]}"
    network_info["range_start"]="$i1.$i2.$i3.$((i4 + 50))"
    network_info["range_end"]="${network_info[hostmax]}"
    # Gateway conventionally uses .1 address
    network_info["gateway"]="${network_info[network]%.*}.1"

    # Verify all required parameters were successfully calculated
    local required=("network" "netmask" "broadcast" "range_start" "range_end" "gateway")
    for key in "${required[@]}"; do
      if [[ -z "${network_info[$key]}" ]]; then
        warn "Failed to calculate network $key for subnet $subnet"
        return 1
      fi
    done
  }

  # Bridge validation
  validate_bridge() {
    local bridge_num=$1
    [[ "$bridge_num" =~ ^[0-9]+$ ]] || { warn "Bridge number must be a positive integer"; return 1; }

    if [[ -d "/sys/class/net/vmbr$bridge_num" || \
          -n $(grep -h "^iface vmbr$bridge_num" "$NETWORK_INTERFACES_FILE" 2>/dev/null) ]]; then
      return 1  # Bridge exists
    fi
    return 0  # Bridge doesn't exist
  }

  # Find next available bridge
  find_next_bridge() {
    local bridge_num=0
    while ! validate_bridge "$bridge_num"; do
      ((bridge_num++))
    done
    echo "$bridge_num"
  }

  # Subnet validation
  validate_subnet() {
    local subnet=$1
    [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || { warn "Invalid CIDR format"; return 1; }

    IFS='./' read -r ip1 ip2 ip3 ip4 mask <<< "$subnet"
    (( ip1 <= 255 && ip2 <= 255 && ip3 <= 255 && ip4 <= 255 && mask <= 32 )) || { warn "Invalid IP/Netmask"; return 1; }

    # Check for conflicts
    while read -r existing; do
      if [[ -n "$existing" ]]; then
        if ipcalc -n "$subnet" | grep -q "$(ipcalc -n "$existing" | awk -F= '/NETWORK/ {print $2}')"; then
          warn "Subnet conflict detected with $existing"
          return 1
        fi
      fi
    done < <(get_existing_subnets)

    return 0
  }

  get_existing_subnets() {
    grep -h '^iface' "$NETWORK_INTERFACES_FILE" 2>/dev/null | \
    grep -v '^iface lo' | while read -r line; do
      if [[ $line =~ address[[:space:]]+([0-9.]+) ]]; then
        address=${BASH_REMATCH[1]}
        netmask_line=$(grep -A5 "^$line" "$NETWORK_INTERFACES_FILE" 2>/dev/null | grep -m1 'netmask')
        [[ $netmask_line =~ netmask[[:space:]]+([0-9.]+) ]] || continue
        netmask=${BASH_REMATCH[1]}
        cidr=$(ipcalc -p "$address" "$netmask" | awk -F= '/PREFIX/ {print $2}')
        echo "${address}/${cidr}"
      fi
    done
  }

  # Regenerate main dhcpd.conf
  regenerate_dhcpd_conf() {
    # Start with base configuration
    printf "# DHCP Server Configuration\n# Global DHCP options\noption domain-name \"local\";\noption domain-name-servers 8.8.8.8, 8.8.4.4;\n\ndefault-lease-time 604800;\nmax-lease-time 1209600;\n\nauthoritative;\nlog-facility local7;\n" > /etc/dhcp/dhcpd.conf

    # Add includes for all bridge configs
    printf "\n# Bridge configurations\n" >> /etc/dhcp/dhcpd.conf
    for conf in "$DHCP_CONF_DIR"/*.conf; do
      [[ -f "$conf" ]] && printf "include \"%s\";\n" "$conf" >> /etc/dhcp/dhcpd.conf
    done
  }

  # Update DHCP interfaces list
  update_dhcp_interfaces() {
    # Collect all bridge interfaces with DHCP configs
    local interfaces=()
    for conf in "$DHCP_CONF_DIR"/*.conf; do
      [[ -f "$conf" ]] && interfaces+=("$(basename "${conf%.conf}")")
    done

    # Update interfaces list
    printf "INTERFACESv4=\"%s\"\n" "${interfaces[*]}" > /etc/default/isc-dhcp-server
  }

  # DHCP configuration
  configure_dhcp() {
    local bridge_name=$1
    local subnet=$2

    if ! calculate_network "$subnet"; then
      warn "Failed to calculate network parameters for $subnet"
      return 1
    fi

    # Create bridge-specific config
    printf "subnet %s netmask %s {\n" "${network_info[network]}" "${network_info[netmask]}" > "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    range %s %s;\n" "${network_info[range_start]}" "${network_info[range_end]}" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    option routers %s;\n" "${network_info[gateway]}" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    option broadcast-address %s;\n" "${network_info[broadcast]}" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    option subnet-mask %s;\n" "${network_info[netmask]}" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    default-lease-time 604800;\n" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "    max-lease-time 1209600;\n" >> "$DHCP_CONF_DIR/$bridge_name.conf"
    printf "}\n" >> "$DHCP_CONF_DIR/$bridge_name.conf"

    # Set permissions
    chown root:root "$DHCP_CONF_DIR/$bridge_name.conf"
    chmod 644 "$DHCP_CONF_DIR/$bridge_name.conf"

    # Regenerate main config
    regenerate_dhcpd_conf

    # Update interfaces list
    update_dhcp_interfaces

    # Validate config
    if ! dhcpd -t -cf /etc/dhcp/dhcpd.conf >>"$logfile" 2>&1; then
      warn "DHCP configuration validation failed"
      return 1
    fi

    # Restart service
    systemctl restart isc-dhcp-server >>"$logfile" 2>&1 || warn "Failed to restart isc-dhcp-server"
    systemctl enable isc-dhcp-server >>"$logfile" 2>&1
  }

  # Network configuration with rollback support
  configure_network() {
    local bridge_num=$1
    local subnet=$2

    info "Calculating network parameters for $subnet..."
    if ! calculate_network "$subnet"; then
      die "Failed to calculate network parameters for $subnet"
    fi

    local gw_iface=$(ip route | awk '/^default/ {print $5}')
    [[ -z "$gw_iface" ]] && die "No default gateway found"

    # Create backup of interfaces file
    local backup_file="${NETWORK_INTERFACES_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
    info "Creating backup of network interfaces: $backup_file"
    cp "$NETWORK_INTERFACES_FILE" "$backup_file" || die "Failed to create backup of $NETWORK_INTERFACES_FILE"

    # Add bridge configuration
    printf "\n" >> "$NETWORK_INTERFACES_FILE"
    printf "auto vmbr%s\n" "$bridge_num" >> "$NETWORK_INTERFACES_FILE"
    printf "iface vmbr%s inet static\n" "$bridge_num" >> "$NETWORK_INTERFACES_FILE"
    printf "\t# Subnet %s using %s for gateway\n" "$subnet" "$gw_iface" >> "$NETWORK_INTERFACES_FILE"
    printf "\taddress %s\n" "${network_info[gateway]}" >> "$NETWORK_INTERFACES_FILE"
    printf "\tnetmask %s\n" "${network_info[netmask]}" >> "$NETWORK_INTERFACES_FILE"
    printf "\tbridge_ports none\n" >> "$NETWORK_INTERFACES_FILE"
    printf "\tbridge_stp off\n" >> "$NETWORK_INTERFACES_FILE"
    printf "\tbridge_fd 0\n" >> "$NETWORK_INTERFACES_FILE"
    printf "\tpost-up echo 1 > /proc/sys/net/ipv4/ip_forward\n" >> "$NETWORK_INTERFACES_FILE"
    printf "\tpost-up iptables -t nat -A POSTROUTING -s '%s' -o %s -j MASQUERADE\n" "$subnet" "$gw_iface" >> "$NETWORK_INTERFACES_FILE"
    printf "\tpost-down iptables -t nat -D POSTROUTING -s '%s' -o %s -j MASQUERADE\n" "$subnet" "$gw_iface" >> "$NETWORK_INTERFACES_FILE"

    # Verify the config was added correctly
    if ! grep -q "iface vmbr$bridge_num inet static" "$NETWORK_INTERFACES_FILE"; then
      warn "Failed to add bridge configuration"
      restore_backup "$backup_file"
      die "Network configuration failed"
    fi

    # Bring up bridge with rollback on failure
    info "Bringing up bridge vmbr$bridge_num..."
    if ! ifup "vmbr$bridge_num" >>"$logfile" 2>&1; then
      warn "Failed to activate bridge"
      restore_backup "$backup_file"
      die "Bridge activation failed - configuration rolled back"
    fi

    # Clean up backup if successful
    rm -f "$backup_file"
  }

  # Prompt with validation
  prompt_with_validation() {
    local prompt=$1
    local default=$2
    local validation_func=$3
    local value

    while true; do
      read -rp "$prompt [$default]: " value
      value=${value:-$default}
      if $validation_func "$value"; then
        echo "$value"
        return
      fi
      display_and_log "Press any key to return to the main menu..."
      read -n 1 -s
      return 1
    done
  }

  # Main execution
  info "Configuring network bridge for macOS in Cloud..."

  # Check root
  (( EUID == 0 )) || die "This function must be run as root"

  ensure_dependencies
  ensure_dhcp_group

  # Get bridge number
  local next_bridge=$(find_next_bridge)
  info "Next available bridge: vmbr$next_bridge"
  local bridge_num
  bridge_num=$(prompt_with_validation "Enter bridge number" "$next_bridge" validate_bridge) || return

  # Get subnet
  local default_subnet="10.27.$bridge_num.0/24"
  local subnet
  subnet=$(prompt_with_validation "Enter subnet for VM bridge in CIDR notation" "$default_subnet" validate_subnet) || return

  # Configure network
  info "Configuring network..."
  configure_network "$bridge_num" "$subnet"

  # Configure DHCP
  read -rp "Configure DHCP server for vmbr$bridge_num? [Y/n]: " answer
  if [[ "${answer,,}" =~ ^(y|)$ ]]; then
    info "Configuring DHCP server..."
    configure_dhcp "vmbr$bridge_num" "$subnet" || {
      warn "DHCP configuration failed. Network bridge configured, but DHCP not enabled."
    }
  fi

  info "Configuration completed:"
  info "Bridge: vmbr$bridge_num"
  info "Subnet: $subnet"
  info "Gateway: ${network_info[gateway]}"
  [[ "${answer,,}" =~ ^(y|)$ ]] && info "DHCP Range: ${network_info[range_start]} - ${network_info[range_end]}"
  info "Network config: $NETWORK_INTERFACES_FILE"
  [[ "${answer,,}" =~ ^(y|)$ ]] && info "DHCP config: $DHCP_CONF_DIR/vmbr$bridge_num.conf"
  display_and_log "Press any key to return to the main menu..."
  read -n 1 -s
}

# Export functions for use in other scripts
export -f get_available_bridges
export -f configure_network_bridge

