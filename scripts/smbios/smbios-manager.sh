#!/bin/bash
#
# smbios-manager.sh - SMBIOS generation and management for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script manages SMBIOS data generation via API or macserial, and model selection.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source required libraries
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

# API-based validated SMBIOS fetcher
# Fetches pre-validated Apple serial numbers from API endpoint
# Returns validated serials that pass Apple's warranty lookup system
# Falls back gracefully to GenSMBIOS if API is unavailable or returns "None"
# Parameters: $1 - Output JSON file path for SMBIOS data
# Returns: 0 on success, 1 on failure (triggers GenSMBIOS fallback)
fetch_validated_smbios() {
  local output_json=$1
  local api_url="https://api.olliebot.ai/webhook/macos-serial-checker-4fcdf009-38eb-49c5-ba28-bfc42178536c"
  local logfile="${LOGDIR}/api-smbios-fetch.log"
  
  echo "→ Fetching validated serial number from API..." >&2
  display_and_log "Fetching validated serial number from API..." "$logfile"
  echo "  URL: $api_url" >&2
  display_and_log "  URL: $api_url" "$logfile"
  
  # Make API POST request with 10 second timeout
  # Try with system CA certificates first, fallback to insecure if needed
  echo "  Attempting connection..." >&2
  display_and_log "  Attempting POST request to API..." "$logfile"
  
  local response
  local curl_exit_code
  
  # First attempt with system CA certificates
  response=$(curl -s -m 10 -X POST --cacert /etc/ssl/certs/ca-certificates.crt "$api_url" 2>&1)
  curl_exit_code=$?
  
  # If that failed, try with -k (insecure)
  if [ $curl_exit_code -ne 0 ]; then
    echo "  First attempt failed (exit code: $curl_exit_code), trying without cert verification..." >&2
    display_and_log "  Certificate verification failed, retrying with -k flag..." "$logfile"
    response=$(curl -s -m 10 -X POST -k "$api_url" 2>&1)
    curl_exit_code=$?
  fi
  
  # Log the curl result
  if [ $curl_exit_code -ne 0 ]; then
    echo "  ERROR: curl failed with exit code $curl_exit_code" >&2
    display_and_log "  curl failed with exit code: $curl_exit_code" "$logfile"
    display_and_log "  Response: $response" "$logfile"
    display_and_log "API request failed. Will use GenSMBIOS instead." "$logfile"
    return 1
  fi
  
  echo "  Connection successful, parsing response..." >&2
  display_and_log "  API responded successfully" "$logfile"
  display_and_log "  Response: $response" "$logfile"
  
  # Check if response is "None" or empty
  if [[ -z "$response" || "$response" == "None" ]]; then
    echo "  API returned no available serials" >&2
    display_and_log "API returned no available serials. Will use GenSMBIOS instead." "$logfile"
    return 1
  fi
  
  # Parse and validate JSON response
  echo "  Parsing JSON response..." >&2
  local api_status=$(echo "$response" | jq -r '.status // empty' 2>>"$logfile")
  local api_type=$(echo "$response" | jq -r '.type // empty' 2>>"$logfile")
  local api_serial=$(echo "$response" | jq -r '.serial // empty' 2>>"$logfile")
  local api_boardserial=$(echo "$response" | jq -r '.boardserial // empty' 2>>"$logfile")
  local api_smuuid=$(echo "$response" | jq -r '.smuuid // empty' 2>>"$logfile")
  local api_applerom=$(echo "$response" | jq -r '.applerom // empty' 2>>"$logfile")
  
  # Note: API returns status:false when serial is available but not actively in use
  # This is actually what we want - an available serial that's not registered
  echo "  API Status: $api_status (false = available for use)" >&2
  
  # Validate all required fields are present
  if [[ -z "$api_type" || -z "$api_serial" || -z "$api_boardserial" || -z "$api_smuuid" || -z "$api_applerom" ]]; then
    echo "  ERROR: API response missing required fields" >&2
    display_and_log "API response missing required fields. Will use GenSMBIOS instead." "$logfile"
    display_and_log "  Response: $response" "$logfile"
    return 1
  fi
  
  # Convert response to GenSMBIOS format and save to JSON file
  echo "  Saving SMBIOS data..." >&2
  jq -n \
    --arg Type "$api_type" \
    --arg Serial "$api_serial" \
    --arg BoardSerial "$api_boardserial" \
    --arg SmUUID "$api_smuuid" \
    --arg ROM "$api_applerom" \
    '{Type: $Type, Serial: $Serial, "Board Serial": $BoardSerial, SmUUID: $SmUUID, ROM: $ROM}' > "$output_json"
  
  echo "  ✓ Success!" >&2
  display_and_log "✓ Validated serial fetched successfully: $api_serial ($api_type)" "$logfile"
  display_and_log "  Board Serial: $api_boardserial" "$logfile"
  display_and_log "  System UUID: $api_smuuid" "$logfile"
  display_and_log "  ROM Address: $api_applerom" "$logfile"
  return 0
}

# Present menu for selecting Mac model for SMBIOS generation
# Returns: Selected Mac model identifier (e.g., "iMac19,1")
# Default: iMac19,1 for maximum compatibility
select_mac_model() {
  echo >&2
  echo "╔════════════════════════════════════════════════════════════╗" >&2
  echo "║ Select Mac Model for SMBIOS Generation                    ║" >&2
  echo "╚════════════════════════════════════════════════════════════╝" >&2
  echo >&2
  echo " 1 - iMac19,1           27-inch iMac (2019)" >&2
  echo " 2 - iMac19,2           21.5-inch iMac (2019)" >&2
  echo " 3 - Macmini8,1         Mac mini (2018)" >&2
  echo " 4 - MacPro7,1          Mac Pro (2019)" >&2
  echo " 5 - MacBookPro15,1     15-inch MacBook Pro (2018-2019)" >&2
  echo " 6 - MacBookPro15,3     15-inch MacBook Pro (2019)" >&2
  echo " 7 - MacBookPro16,1     16-inch MacBook Pro (2019)" >&2
  echo >&2
  echo " Default: iMac19,1 (recommended for best compatibility)" >&2
  echo >&2
  
  local selected_key
  while true; do
    read -rp "Select Mac model [1-7, or ENTER for default]: " selected_key
    
    # Default to option 1 (iMac19,1) if empty
    if [[ -z "$selected_key" ]]; then
      selected_key=1
      break
    fi
    
    # Validate numeric input within range
    if [[ "$selected_key" =~ ^[1-7]$ ]]; then
      break
    else
      echo "Invalid selection. Please enter a number between 1-7." >&2
    fi
  done
  
  # Return the selected model identifier (to stdout for capture)
  case "$selected_key" in
    1) echo "iMac19,1" ;;
    2) echo "iMac19,2" ;;
    3) echo "Macmini8,1" ;;
    4) echo "MacPro7,1" ;;
    5) echo "MacBookPro15,1" ;;
    6) echo "MacBookPro15,3" ;;
    7) echo "MacBookPro16,1" ;;
  esac
}

# Generate SMBIOS using macserial binary directly
# Non-interactive alternative to GenSMBIOS.py menu-driven interface
# Parameters: $1 - Mac model (e.g., "iMac19,1"), $2 - Output JSON path
# Returns: 0 on success, 1 on failure
generate_smbios_with_macserial() {
  local mac_model="$1"
  local output_json="$2"
  local logfile="${LOGDIR}/macserial-generation.log"
  
  echo "→ Generating SMBIOS for $mac_model using macserial..." >&2
  display_and_log "Generating SMBIOS for $mac_model..." "$logfile"
  
  # Locate macserial binary (Linux binary for Proxmox)
  local macserial_bin="${SCRIPT_DIR}/Supporting_Tools/Misc_Tools/macserial/macserial"
  
  if [ ! -f "$macserial_bin" ]; then
    echo "  ERROR: macserial binary not found: $macserial_bin" >&2
    display_and_log "ERROR: macserial binary not found: $macserial_bin" "$logfile"
    return 1
  fi
  
  # Make sure it's executable
  chmod +x "$macserial_bin" 2>/dev/null
  
  # Generate SMBIOS (use -m for model, -n 1 for one result only)
  # NOTE: Do NOT use -a flag as it generates ALL models
  echo "  Calling macserial: -m $mac_model -n 1" >&2
  echo "  Binary: $macserial_bin" >&2
  
  local output
  output=$("$macserial_bin" -m "$mac_model" -n 1 2>&1)
  local macserial_exit=$?
  
  echo "  macserial exit code: $macserial_exit" >&2
  display_and_log "  macserial exit: $macserial_exit" "$logfile"
  
  if [ $macserial_exit -ne 0 ]; then
    echo "  ERROR: macserial failed with exit code $macserial_exit" >&2
    echo "  Output: $output" >&2
    display_and_log "ERROR: macserial generation failed (exit $macserial_exit)" "$logfile"
    display_and_log "  Output: $output" "$logfile"
    return 1
  fi
  
  if [ -z "$output" ]; then
    echo "  ERROR: macserial returned empty output" >&2
    display_and_log "ERROR: macserial returned empty output" "$logfile"
    return 1
  fi
  
  echo "  Raw output:" >&2
  echo "$output" >&2
  display_and_log "  macserial raw output: $output" "$logfile"
  
  echo "  Parsing macserial output..." >&2
  
  # macserial output format is just: "Serial | BoardSerial" (no model name in output)
  # May have warning line about arc4random - skip lines starting with "Warning"
  local data_line=$(echo "$output" | grep -v "^Warning" | grep "|" | head -1)
  
  if [ -z "$data_line" ]; then
    echo "  ERROR: Could not find valid data line with | separator" >&2
    echo "  Full output was: $output" >&2
    display_and_log "ERROR: No valid data line in macserial output" "$logfile"
    return 1
  fi
  
  echo "  Data line: $data_line" >&2
  
  # Parse: "Serial | BoardSerial"
  local serial=$(echo "$data_line" | awk -F'|' '{print $1}' | tr -d ' ')
  local board_serial=$(echo "$data_line" | awk -F'|' '{print $2}' | tr -d ' ')
  
  echo "    Parsed serial: '$serial'" >&2
  echo "    Parsed board serial: '$board_serial'" >&2
  
  if [ -z "$serial" ] || [ -z "$board_serial" ]; then
    echo "  ERROR: Failed to parse serial or board serial from output" >&2
    echo "  Raw output was: '$output'" >&2
    display_and_log "ERROR: Failed to parse macserial output" "$logfile"
    display_and_log "  Output: $output" "$logfile"
    return 1
  fi
  
  # Generate UUID using multiple fallback methods
  local sm_uuid=""
  
  # Try uuidgen first (if available)
  if command -v uuidgen &>/dev/null; then
    sm_uuid=$(uuidgen 2>/dev/null)
  fi
  
  # Fallback 1: Use Linux kernel random UUID
  if [ -z "$sm_uuid" ] && [ -f /proc/sys/kernel/random/uuid ]; then
    sm_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr 'a-z' 'A-Z')
  fi
  
  # Fallback 2: Generate UUID format manually
  if [ -z "$sm_uuid" ]; then
    sm_uuid=$(printf '%08X-%04X-%04X-%04X-%012X' $((RANDOM*32768+RANDOM)) $RANDOM $RANDOM $RANDOM $((RANDOM*32768+RANDOM)))
  fi
  
  echo "    UUID: $sm_uuid" >&2
  
  # Generate ROM (random MAC address format - 12 hex digits)
  local rom=$(printf '%02X%02X%02X%02X%02X%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
  echo "    ROM: $rom" >&2
  
  # Create JSON file in GenSMBIOS format
  echo "  Creating JSON file at: $output_json" >&2
  jq -n \
    --arg Type "$mac_model" \
    --arg Serial "$serial" \
    --arg BoardSerial "$board_serial" \
    --arg SmUUID "$sm_uuid" \
    --arg ROM "$rom" \
    '{Type: $Type, Serial: $Serial, "Board Serial": $BoardSerial, SmUUID: $SmUUID, ROM: $ROM}' > "$output_json" 2>&1
  
  local jq_exit=$?
  
  if [ $jq_exit -ne 0 ]; then
    echo "  ERROR: jq failed with exit code $jq_exit" >&2
    display_and_log "ERROR: jq command failed ($jq_exit)" "$logfile"
    return 1
  fi
  
  if [ ! -f "$output_json" ]; then
    echo "  ERROR: JSON file was not created" >&2
    display_and_log "ERROR: JSON file was not created at $output_json" "$logfile"
    return 1
  fi
  
  # Verify JSON contents
  echo "  Verifying JSON contents..." >&2
  local json_contents=$(cat "$output_json" 2>&1)
  echo "  JSON: $json_contents" >&2
  display_and_log "  Generated JSON: $json_contents" "$logfile"
  
  # Verify required fields exist in JSON
  local verify_serial=$(jq -r '.Serial // empty' "$output_json" 2>&1)
  if [ -z "$verify_serial" ]; then
    echo "  ERROR: JSON file missing Serial field" >&2
    display_and_log "ERROR: Generated JSON missing Serial field" "$logfile"
    return 1
  fi
  
  echo "  ✓ SMBIOS generated and validated successfully" >&2
  display_and_log "✓ SMBIOS generated successfully: $serial" "$logfile"
  return 0
}

# Export functions for use in other scripts
export -f fetch_validated_smbios
export -f select_mac_model
export -f generate_smbios_with_macserial

