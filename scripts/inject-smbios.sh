#!/bin/bash
#
# inject-smbios.sh - Inject SMBIOS values into OpenCore config.plist
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This script takes a config.plist and a SMBIOS JSON file, and injects
# the hardware identifiers into the PlatformInfo section.
#

# Note: NOT using 'set -e' to allow verbose error reporting
# Errors are handled explicitly at each step

echo "[inject-smbios] Script started" >&2

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[inject-smbios] SCRIPT_DIR: $SCRIPT_DIR" >&2

# Source common functions
echo "[inject-smbios] Sourcing common functions..." >&2
if [ ! -f "${SCRIPT_DIR}/scripts/lib/common-functions.sh" ]; then
    echo "[inject-smbios] ERROR: common-functions.sh not found at ${SCRIPT_DIR}/scripts/lib/common-functions.sh" >&2
    exit 1
fi
source "${SCRIPT_DIR}/scripts/lib/common-functions.sh"
echo "[inject-smbios] Common functions sourced successfully" >&2

# Set log file to main logs directory
LOG_FILE="${SCRIPT_DIR}/logs/inject-smbios.log"

# Create log directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/logs" 2>/dev/null || {
    echo "[inject-smbios] ERROR: Cannot create logs directory" >&2
    exit 1
}

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "[inject-smbios] ERROR: Cannot create log file: $LOG_FILE" >&2
    exit 1
}

echo "[inject-smbios] LOG_FILE: $LOG_FILE" >&2

# Default values
CONFIG_FILE=""
JSON_FILE=""
CREATE_BACKUP=false

echo "[inject-smbios] Initializing..." >&2

#
# parse_arguments() - Parse command line arguments
#
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --json)
                JSON_FILE="$2"
                shift 2
                ;;
            --backup)
                CREATE_BACKUP=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 --config <config.plist> --json <smbios.json> [--backup]"
                echo
                echo "Options:"
                echo "  --config <path>   Path to config.plist file (required)"
                echo "  --json <path>     Path to SMBIOS JSON file (required)"
                echo "  --backup          Create backup before modifying (optional)"
                echo "  --help            Show this help message"
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
    if [ -z "$CONFIG_FILE" ]; then
        log_message "ERROR: --config argument is required"
        exit 1
    fi
    
    if [ -z "$JSON_FILE" ]; then
        log_message "ERROR: --json argument is required"
        exit 1
    fi
}

#
# validate_dependencies() - Check for required tools
#
validate_dependencies() {
    echo "  Checking dependencies..." >&2
    local missing_deps=()
    
    # Check for essential tools (no longer need xmlstarlet)
    for tool in jq sed grep xxd base64; do
        if command -v "$tool" >/dev/null 2>&1; then
            local tool_path=$(which "$tool")
            echo "    ✓ $tool: $tool_path" >&2
        else
            missing_deps+=("$tool")
            echo "    ✗ $tool: NOT FOUND" >&2
        fi
    done
    
    # xmlstarlet is optional now (we use sed instead)
    if command -v xmlstarlet >/dev/null 2>&1; then
        echo "    ✓ xmlstarlet: available (optional)" >&2
    else
        echo "    ℹ xmlstarlet: not found (optional, using sed instead)" >&2
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "  ERROR: Missing required dependencies: ${missing_deps[*]}" >&2
        log_message "ERROR: Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    echo "  ✓ All dependencies found" >&2
    return 0
}

#
# validate_files() - Validate input files exist and are valid
#
validate_files() {
    echo "  Validating input files..." >&2
    log_message "Validating input files..."
    
    # Check config.plist
    if ! validate_path "$CONFIG_FILE" "file"; then
        echo "  ERROR: Config file not found: $CONFIG_FILE" >&2
        log_message "ERROR: Config file not found: $CONFIG_FILE"
        exit 2
    fi
    
    # Validate plist with detailed error output
    echo "  Validating config.plist structure..." >&2
    log_message "Validating config.plist: $CONFIG_FILE"
    
    # Basic validation: check if it's a valid plist file without using xmlstarlet
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "  ERROR: Config file not found: $CONFIG_FILE" >&2
        log_message "ERROR: Config file not found: $CONFIG_FILE"
        exit 2
    fi
    
    if ! grep -q "<?xml version" "$CONFIG_FILE" 2>/dev/null; then
        echo "  ERROR: File doesn't appear to be XML: $CONFIG_FILE" >&2
        log_message "ERROR: Not a valid XML file: $CONFIG_FILE"
        exit 2
    fi
    
    if ! grep -q "<plist version" "$CONFIG_FILE" 2>/dev/null; then
        echo "  ERROR: File doesn't appear to be a plist: $CONFIG_FILE" >&2
        log_message "ERROR: Not a valid plist file: $CONFIG_FILE"
        exit 2
    fi
    
    if ! grep -q "</plist>" "$CONFIG_FILE" 2>/dev/null; then
        echo "  ERROR: Plist file appears to be incomplete (missing </plist>)" >&2
        log_message "ERROR: Incomplete plist file: $CONFIG_FILE"
        exit 2
    fi
    
    echo "  ✓ Config.plist basic structure validated" >&2
    
    # Check JSON file
    if ! validate_path "$JSON_FILE" "file"; then
        echo "  ERROR: JSON file not found: $JSON_FILE" >&2
        log_message "ERROR: JSON file not found: $JSON_FILE"
        exit 2
    fi
    
    if ! validate_json_file "$JSON_FILE"; then
        echo "  ERROR: Invalid JSON file: $JSON_FILE" >&2
        log_message "ERROR: Invalid JSON file: $JSON_FILE"
        exit 2
    fi
    
    echo "  ✓ File validation successful" >&2
    log_message "File validation successful"
    return 0
}

#
# create_backup() - Create backup of config.plist
#
create_backup() {
    if [ "$CREATE_BACKUP" = true ]; then
        local backup_file="${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
        log_message "Creating backup: $backup_file"
        
        if ! cp "$CONFIG_FILE" "$backup_file"; then
            log_message "ERROR: Failed to create backup"
            exit 2
        fi
        
        log_message "Backup created successfully"
    fi
}

#
# read_plist_value() - Read a value from plist using XPath
#
read_plist_value() {
    local plist_file="$1"
    local xpath="$2"
    local key="$3"
    
    local value=$(xmlstarlet sel -t -v "${xpath}/key[text()='${key}']/following-sibling::*[1]" "$plist_file" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "    DEBUG: Failed to read $key: $value" >&2
        return 1
    fi
    
    echo "$value"
    return 0
}

#
# update_plist_value() - Update a value in plist using XPath
#
update_plist_value() {
    local plist_file="$1"
    local xpath="$2"
    local key="$3"
    local value="$4"
    
    echo "    DEBUG: Updating $key to: $value" >&2
    
    # For multi-line patterns, we need to handle newlines
    # Use sed with N command to join lines
    case "$key" in
        "SystemProductName"|"SystemSerialNumber"|"MLB"|"SystemUUID")
            # These are all string values
            # Pattern: <key>KeyName</key> followed by newline and <string>value</string>
            # We'll use a simpler approach: just replace the value line after finding the key
            
            # Find the line number of the key
            local key_line=$(grep -n "<key>$key</key>" "$plist_file" | cut -d: -f1)
            if [ -z "$key_line" ]; then
                echo "    ERROR: Key $key not found in plist" >&2
                return 1
            fi
            
            # The value should be on the next line
            local value_line=$((key_line + 1))
            
            # Replace just the value line
            sed -i.bak "${value_line}s|<string>[^<]*</string>|<string>$value</string>|" "$plist_file" 2>/dev/null
            local sed_exit=$?
            ;;
        "ROM")
            # ROM is base64 data
            local key_line=$(grep -n "<key>ROM</key>" "$plist_file" | cut -d: -f1)
            if [ -z "$key_line" ]; then
                echo "    ERROR: Key ROM not found in plist" >&2
                return 1
            fi
            
            local value_line=$((key_line + 1))
            sed -i.bak "${value_line}s|<data>[^<]*</data>|<data>$value</data>|" "$plist_file" 2>/dev/null
            local sed_exit=$?
            ;;
        *)
            echo "    ERROR: Unknown key: $key" >&2
            return 1
            ;;
    esac
    
    echo "    DEBUG: sed exit code: $sed_exit" >&2
    
    if [ $sed_exit -eq 0 ]; then
        # Verify the update worked - simply check if the value exists
        if grep -q "$value" "$plist_file" 2>/dev/null; then
            echo "    ✓ Successfully updated $key" >&2
            rm -f "${plist_file}.bak"
            return 0
        else
            echo "    WARNING: Value not found after replacement" >&2
            # Show what's actually there
            echo "    DEBUG: Current $key value:" >&2
            grep -A1 "<key>$key</key>" "$plist_file" | tail -1 >&2
            # Restore backup
            mv "${plist_file}.bak" "$plist_file" 2>/dev/null
            return 1
        fi
    else
        echo "    ERROR: sed command failed with exit code $sed_exit" >&2
        # Show what's actually there for debugging
        echo "    DEBUG: Current $key line:" >&2
        grep -A1 "<key>$key</key>" "$plist_file" | head -2 >&2
        return 1
    fi
}

#
# verify_plist_structure() - Verify the plist has the required structure
#
verify_plist_structure() {
    local plist_file="$1"
    
    echo "  Verifying plist structure..." >&2
    
    # Use grep instead of xmlstarlet to avoid XML parsing issues
    # Check if PlatformInfo exists
    if ! grep -q "<key>PlatformInfo</key>" "$plist_file" 2>/dev/null; then
        echo "    ERROR: PlatformInfo section not found in plist" >&2
        return 1
    fi
    
    # Check if Generic subsection exists (should be shortly after PlatformInfo)
    if ! grep -A 10 "<key>PlatformInfo</key>" "$plist_file" | grep -q "<key>Generic</key>" 2>/dev/null; then
        echo "    ERROR: PlatformInfo->Generic section not found in plist" >&2
        return 1
    fi
    
    # Check for required SMBIOS keys
    local required_keys=("SystemProductName" "SystemSerialNumber" "MLB" "SystemUUID" "ROM")
    for key in "${required_keys[@]}"; do
        if ! grep -q "<key>$key</key>" "$plist_file" 2>/dev/null; then
            echo "    WARNING: $key not found in plist (will be added if missing)" >&2
        fi
    done
    
    echo "    ✓ Plist structure verified" >&2
    return 0
}

#
# inject_smbios_values() - Main injection logic
#
inject_smbios_values() {
    echo "  Starting SMBIOS injection..." >&2
    log_message "Starting SMBIOS injection..."
    
    # XPath for PlatformInfo section
    local platform_generic_xpath="//key[text()='PlatformInfo']/following-sibling::dict/key[text()='Generic']/following-sibling::dict"
    
    # Read SMBIOS values from JSON
    echo "  Reading SMBIOS values from JSON..." >&2
    local system_product_name=$(jq -r '.Type // empty' "$JSON_FILE" 2>>"$LOG_FILE")
    local system_serial_number=$(jq -r '.Serial // empty' "$JSON_FILE" 2>>"$LOG_FILE")
    local mlb=$(jq -r '."Board Serial" // empty' "$JSON_FILE" 2>>"$LOG_FILE")
    local system_uuid=$(jq -r '.SmUUID // empty' "$JSON_FILE" 2>>"$LOG_FILE")
    local rom_hex=$(jq -r '.ROM // empty' "$JSON_FILE" 2>>"$LOG_FILE")
    
    echo "    Type: $system_product_name" >&2
    echo "    Serial: $system_serial_number" >&2
    echo "    MLB: $mlb" >&2
    
    # Validate that we got values
    if [ -z "$system_product_name" ] || [ -z "$system_serial_number" ] || [ -z "$mlb" ] || [ -z "$system_uuid" ]; then
        echo "  ERROR: Missing required SMBIOS values in JSON file" >&2
        log_message "ERROR: Missing required SMBIOS values in JSON file"
        log_message "  JSON file: $JSON_FILE"
        log_message "  JSON contents: $(cat "$JSON_FILE" 2>&1)"
        exit 2
    fi
    
    # Verify plist structure before proceeding
    if ! verify_plist_structure "$CONFIG_FILE"; then
        echo "  ERROR: Invalid plist structure" >&2
        log_message "ERROR: Invalid plist structure in $CONFIG_FILE"
        exit 2
    fi
    
    # Create temporary working file
    local temp_file="${CONFIG_FILE}.tmp"
    echo "  Creating temporary file..." >&2
    cp "$CONFIG_FILE" "$temp_file" 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "  ERROR: Failed to create temporary config file" >&2
        log_message "ERROR: Failed to copy config to temp file"
        exit 2
    fi
    
    # Update SystemProductName
    echo "  Injecting SystemProductName: $system_product_name" >&2
    log_message "Injecting SystemProductName: $system_product_name"
    if ! update_plist_value "$temp_file" "$platform_generic_xpath" "SystemProductName" "$system_product_name"; then
        echo "  ERROR: Failed to update SystemProductName" >&2
        log_message "ERROR: Failed to update SystemProductName"
        rm -f "$temp_file"
        exit 3
    fi
    
    # Update SystemSerialNumber
    echo "  Injecting SystemSerialNumber: $system_serial_number" >&2
    log_message "Injecting SystemSerialNumber: $system_serial_number"
    if ! update_plist_value "$temp_file" "$platform_generic_xpath" "SystemSerialNumber" "$system_serial_number"; then
        echo "  ERROR: Failed to update SystemSerialNumber" >&2
        log_message "ERROR: Failed to update SystemSerialNumber"
        rm -f "$temp_file"
        exit 3
    fi
    
    # Update MLB (Board Serial)
    echo "  Injecting MLB: $mlb" >&2
    log_message "Injecting MLB: $mlb"
    if ! update_plist_value "$temp_file" "$platform_generic_xpath" "MLB" "$mlb"; then
        echo "  ERROR: Failed to update MLB" >&2
        log_message "ERROR: Failed to update MLB"
        rm -f "$temp_file"
        exit 3
    fi
    
    # Update SystemUUID
    echo "  Injecting SystemUUID: $system_uuid" >&2
    log_message "Injecting SystemUUID: $system_uuid"
    if ! update_plist_value "$temp_file" "$platform_generic_xpath" "SystemUUID" "$system_uuid"; then
        echo "  ERROR: Failed to update SystemUUID" >&2
        log_message "ERROR: Failed to update SystemUUID"
        rm -f "$temp_file"
        exit 3
    fi
    
    # Update ROM (convert hex to base64)
    if [ -n "$rom_hex" ]; then
        echo "  Injecting ROM: $rom_hex" >&2
        log_message "Injecting ROM: $rom_hex"
        
        # Convert hex to base64
        local rom_base64=$(echo -n "$rom_hex" | xxd -r -p | base64 2>>"$LOG_FILE")
        
        if [ -z "$rom_base64" ]; then
            echo "  ERROR: Failed to convert ROM hex to base64" >&2
            log_message "ERROR: Failed to convert ROM hex to base64"
            rm -f "$temp_file"
            exit 3
        fi
        
        if ! update_plist_value "$temp_file" "$platform_generic_xpath" "ROM" "$rom_base64"; then
            echo "  ERROR: Failed to update ROM" >&2
            log_message "ERROR: Failed to update ROM"
            rm -f "$temp_file"
            exit 3
        fi
    else
        echo "  WARNING: ROM value not found in JSON, skipping" >&2
        log_message "WARNING: ROM value not found in JSON, skipping"
    fi
    
    # Validate the modified plist
    echo "  Validating modified plist..." >&2
    if ! grep -q "</plist>" "$temp_file" 2>/dev/null; then
        echo "  ERROR: Modified plist is invalid (structure corrupted)" >&2
        log_message "ERROR: Modified plist is invalid"
        echo "  Check log for details: $LOG_FILE" >&2
        rm -f "$temp_file"
        exit 3
    fi
    
    # Replace original file with modified version
    echo "  Replacing original config file..." >&2
    if ! mv "$temp_file" "$CONFIG_FILE" 2>>"$LOG_FILE"; then
        echo "  ERROR: Failed to replace original config file" >&2
        log_message "ERROR: Failed to replace original config file"
        rm -f "$temp_file"
        exit 3
    fi
    
    echo "  ✓ SMBIOS injection completed successfully" >&2
    log_message "SMBIOS injection completed successfully"
    return 0
}

#
# update_boot_args() - Update boot-args based on SystemProductName
#
update_boot_args() {
    echo "  Checking boot-args configuration..." >&2
    log_message "Checking boot-args configuration..."
    
    local nvram_xpath="//key[text()='NVRAM']/following-sibling::dict/key[text()='Add']/following-sibling::dict/key[text()='7C436110-AB2A-4BBB-A880-FE41995C9F82']/following-sibling::dict"
    local platform_generic_xpath="//key[text()='PlatformInfo']/following-sibling::dict/key[text()='Generic']/following-sibling::dict"
    
    local system_product_name=$(read_plist_value "$CONFIG_FILE" "$platform_generic_xpath" "SystemProductName")
    local boot_args=$(read_plist_value "$CONFIG_FILE" "$nvram_xpath" "boot-args")
    local flag=" -nehalem_error_disable"
    
    # Add flag if using MacPro5,1 SMBIOS
    if [ "$system_product_name" = "MacPro5,1" ]; then
        if [[ ! "$boot_args" =~ $flag ]]; then
            local new_boot_args="${boot_args}${flag}"
            update_plist_value "$CONFIG_FILE" "$nvram_xpath" "boot-args" "$new_boot_args"
            log_message "Added '$flag' to boot-args for MacPro5,1"
        fi
    else
        # Remove flag if not using MacPro5,1
        if [[ "$boot_args" =~ $flag ]]; then
            local new_boot_args="${boot_args//$flag/}"
            update_plist_value "$CONFIG_FILE" "$nvram_xpath" "boot-args" "$new_boot_args"
            log_message "Removed '$flag' from boot-args (not MacPro5,1)"
        fi
    fi
}

#
# main() - Main entry point
#
main() {
    echo "[inject-smbios] Main function started with $# arguments" >&2
    echo "[inject-smbios] Arguments: $@" >&2
    
    echo "[inject-smbios] Parsing arguments..." >&2
    parse_arguments "$@"
    echo "[inject-smbios] Arguments parsed. Config: $CONFIG_FILE, JSON: $JSON_FILE" >&2
    
    echo "[inject-smbios] Validating dependencies..." >&2
    validate_dependencies || exit $?
    
    echo "[inject-smbios] Validating files..." >&2
    validate_files || exit $?
    
    echo "[inject-smbios] Creating backup..." >&2
    create_backup || exit $?
    
    echo "[inject-smbios] Injecting SMBIOS values..." >&2
    inject_smbios_values || exit $?
    
    echo "[inject-smbios] Updating boot args..." >&2
    update_boot_args || exit $?
    
    echo "[inject-smbios] ✓ Complete!" >&2
    log_message "SMBIOS injection completed successfully for: $CONFIG_FILE"
    exit 0
}

# Run main function
echo "[inject-smbios] Starting main with args: $@" >&2
main "$@"

