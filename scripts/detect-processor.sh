#!/bin/bash
#
# detect-processor.sh - Detect or manually select processor type for OpenCore EFI
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# ⚠️  DEPRECATED: This script is no longer used in the main workflow.
# The system now uses a single PROXMOX-EFI configuration optimized with
# Skylake-Client-v4 CPU model for all hardware, providing 30-44% better
# performance than host passthrough.
#
# Reference: QEMU CPU optimization for macOS guests
#
# This script is kept for backward compatibility only.
#
# This script detects the host CPU and maps it to the appropriate Processor_EFIs folder,
# or allows manual selection from available options.
#

set -e

# Display deprecation warning
echo "⚠️  WARNING: This script is deprecated and no longer used in the main workflow." >&2
echo "The system now uses PROXMOX-EFI (Skylake-Client-v4) for all configurations." >&2
echo "This provides ~30-44% better performance than processor-specific configurations." >&2
echo >&2

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common functions
source "${SCRIPT_DIR}/scripts/lib/common-functions.sh"

# Set log file
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/logs/detect-processor.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Processor EFIs directory
PROCESSOR_EFIS_DIR="${SCRIPT_DIR}/Processor_EFIs"

#
# detect_cpu_info() - Parse /proc/cpuinfo to extract CPU details
# Returns: vendor, model_name, family, model
#
detect_cpu_info() {
    local cpu_vendor=""
    local cpu_model_name=""
    local cpu_family=""
    local cpu_model=""
    
    if [ ! -f /proc/cpuinfo ]; then
        log_message "ERROR: /proc/cpuinfo not found"
        return 1
    fi
    
    cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F: '{print $2}' | tr -d ' ')
    cpu_model_name=$(grep -m1 "model name" /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    cpu_family=$(grep -m1 "cpu family" /proc/cpuinfo | awk -F: '{print $2}' | tr -d ' ')
    cpu_model=$(grep -m1 "^model" /proc/cpuinfo | awk -F: '{print $2}' | tr -d ' ')
    
    echo "VENDOR:$cpu_vendor"
    echo "MODEL_NAME:$cpu_model_name"
    echo "FAMILY:$cpu_family"
    echo "MODEL:$cpu_model"
    
    return 0
}

#
# map_intel_processor() - Map Intel CPU to Processor_EFIs folder
#
map_intel_processor() {
    local model_name="$1"
    local family="$2"
    
    log_message "Detecting Intel processor: $model_name"
    
    # Intel generation detection based on model name patterns
    if [[ "$model_name" =~ "Core(TM) Ultra" ]] || [[ "$model_name" =~ "Arrow Lake" ]]; then
        echo "Intel-Desktop-15thgen-Core-Ultra-200-Arrow-Lake"
    elif [[ "$model_name" =~ "14th Gen" ]] || [[ "$model_name" =~ "13th Gen" ]] || [[ "$model_name" =~ "Raptor Lake" ]]; then
        echo "Intel-Desktop-13thgen-14thgen-Raptor-Lake"
    elif [[ "$model_name" =~ "12th Gen" ]] || [[ "$model_name" =~ "Alder Lake" ]]; then
        echo "Intel-Desktop-12thgen-Alder-Lake"
    elif [[ "$model_name" =~ "11th Gen" ]] || [[ "$model_name" =~ "Rocket Lake" ]]; then
        echo "Intel-Desktop-11thgen-Rocket-Lake"
    elif [[ "$model_name" =~ "10th Gen" ]] || [[ "$model_name" =~ "Comet Lake" ]]; then
        echo "Intel-10thgen-Comet-Lake"
    elif [[ "$model_name" =~ "9th Gen" ]] || [[ "$model_name" =~ "i[3579]-9" ]]; then
        echo "Intel-9thgen-Coffee-Lake-Refresh"
    elif [[ "$model_name" =~ "8th Gen" ]] || [[ "$model_name" =~ "i[3579]-8" ]]; then
        echo "Intel-8thgen-Coffee-Lake"
    elif [[ "$model_name" =~ "7th Gen" ]] || [[ "$model_name" =~ "i[3579]-7" ]] || [[ "$model_name" =~ "Kaby Lake" ]]; then
        echo "Intel-7thgen-Kaby-Lake"
    elif [[ "$model_name" =~ "6th Gen" ]] || [[ "$model_name" =~ "i[3579]-6" ]] || [[ "$model_name" =~ "Skylake" ]]; then
        echo "Intel-6thgen-Skylake"
    elif [[ "$model_name" =~ "5th Gen" ]] || [[ "$model_name" =~ "i[3579]-5" ]] || [[ "$model_name" =~ "Broadwell" ]]; then
        echo "Intel-5thgen-Broadwell"
    elif [[ "$model_name" =~ "4th Gen" ]] || [[ "$model_name" =~ "i[3579]-4" ]] || [[ "$model_name" =~ "Haswell" ]]; then
        echo "Intel-4thgen-Haswell"
    elif [[ "$model_name" =~ "3rd Gen" ]] || [[ "$model_name" =~ "i[3579]-3" ]] || [[ "$model_name" =~ "Ivy Bridge" ]]; then
        echo "Intel-3rdgen-Ivy-Bridge"
    elif [[ "$model_name" =~ "2nd Gen" ]] || [[ "$model_name" =~ "i[3579]-2" ]] || [[ "$model_name" =~ "Sandy Bridge" ]]; then
        echo "Intel-2ndgen-Sandy-Brydge"
    elif [[ "$model_name" =~ "i[3579]-[78][0-9][0-9]" ]] || [[ "$model_name" =~ "Lynnfield\|Clarkdale" ]]; then
        echo "Intel-1stgen-Lynnfield-Clarkdale"
    # HEDT detection
    elif [[ "$model_name" =~ "X299" ]] || [[ "$model_name" =~ "i9-[79][0-9][0-9]9X" ]]; then
        if [[ "$model_name" =~ "Cascade Lake" ]]; then
            echo "Intel-HEDT-X299-Cascade-Lake-XW"
        else
            echo "Intel-HEDT-X299-Skylake-XW"
        fi
    elif [[ "$model_name" =~ "X99" ]] || [[ "$model_name" =~ "i7-[56]9[0-9][0-9]X" ]]; then
        if [[ "$model_name" =~ "Broadwell" ]]; then
            echo "Intel-HEDT-5thgen-X99-Broadwell-E"
        else
            echo "Intel-HEDT-4thgen-X99-Haswell-E"
        fi
    elif [[ "$model_name" =~ "X79" ]]; then
        if [[ "$model_name" =~ "Ivy Bridge" ]]; then
            echo "Intel-HEDT-3rdgen-X79-Ivy-Bridge-E"
        else
            echo "Intel-HEDT-2ndgen-X79-Sandy-Bridge-E"
        fi
    elif [[ "$model_name" =~ "X58" ]] || [[ "$model_name" =~ "X59" ]]; then
        if [[ "$model_name" =~ "Westmere" ]]; then
            echo "Intel-HEDT-1stgen-X59-Westmere"
        else
            echo "Intel-HEDT-1stgen-X59-Nehalem"
        fi
    else
        # Default to a modern generation if detection fails
        log_message "WARNING: Could not determine specific Intel generation"
        return 1
    fi
    
    return 0
}

#
# map_amd_processor() - Map AMD CPU to Processor_EFIs folder
#
map_amd_processor() {
    local model_name="$1"
    
    log_message "Detecting AMD processor: $model_name"
    
    # AMD detection based on model name patterns
    if [[ "$model_name" =~ "Ryzen" ]] || [[ "$model_name" =~ "Threadripper" ]] || [[ "$model_name" =~ "EPYC" ]]; then
        echo "AMD-Ryzen-Threadripper"
    elif [[ "$model_name" =~ "FX" ]] || [[ "$model_name" =~ "Bulldozer" ]]; then
        echo "AMD-Bulldozer-FX-Processors"
    else
        log_message "WARNING: Could not determine specific AMD processor type"
        return 1
    fi
    
    return 0
}

#
# auto_detect_processor() - Automatically detect processor and map to EFI folder
#
auto_detect_processor() {
    log_message "Attempting automatic processor detection..."
    
    local cpu_info
    cpu_info=$(detect_cpu_info)
    
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to detect CPU information"
        return 1
    fi
    
    local vendor=$(echo "$cpu_info" | grep "^VENDOR:" | cut -d: -f2)
    local model_name=$(echo "$cpu_info" | grep "^MODEL_NAME:" | cut -d: -f2)
    local family=$(echo "$cpu_info" | grep "^FAMILY:" | cut -d: -f2)
    
    local processor_folder=""
    
    case "$vendor" in
        GenuineIntel)
            processor_folder=$(map_intel_processor "$model_name" "$family")
            ;;
        AuthenticAMD)
            processor_folder=$(map_amd_processor "$model_name")
            ;;
        *)
            log_message "ERROR: Unknown CPU vendor: $vendor"
            return 1
            ;;
    esac
    
    if [ $? -ne 0 ] || [ -z "$processor_folder" ]; then
        log_message "ERROR: Failed to map processor to EFI folder"
        return 1
    fi
    
    # Validate that the folder exists
    if [ ! -d "${PROCESSOR_EFIS_DIR}/${processor_folder}" ]; then
        log_message "ERROR: Processor folder does not exist: $processor_folder"
        return 1
    fi
    
    log_message "Successfully detected: $processor_folder"
    echo "$processor_folder"
    return 0
}

#
# list_available_processors() - List all available processor EFI folders
#
list_available_processors() {
    if [ ! -d "$PROCESSOR_EFIS_DIR" ]; then
        log_message "ERROR: Processor_EFIs directory not found: $PROCESSOR_EFIS_DIR"
        return 1
    fi
    
    local folders=()
    while IFS= read -r -d '' folder; do
        local basename=$(basename "$folder")
        # Skip hidden folders and non-directories
        if [[ ! "$basename" =~ ^\. ]] && [ -d "$folder/EFI" ]; then
            folders+=("$basename")
        fi
    done < <(find "$PROCESSOR_EFIS_DIR" -maxdepth 1 -type d -print0 | sort -z)
    
    if [ ${#folders[@]} -eq 0 ]; then
        log_message "ERROR: No processor folders found in $PROCESSOR_EFIS_DIR"
        return 1
    fi
    
    # Print folders as array elements
    printf '%s\n' "${folders[@]}"
    return 0
}

#
# manual_processor_selection() - Display menu for manual processor selection
#
manual_processor_selection() {
    log_message "Starting manual processor selection..."
    
    local processors
    mapfile -t processors < <(list_available_processors)
    
    if [ $? -ne 0 ] || [ ${#processors[@]} -eq 0 ]; then
        log_message "ERROR: No processors available for selection"
        return 2
    fi
    
    echo "╔═══════════════════════════════════════════════════════════╗" >&2
    echo "║ Available Processor EFI Configurations                   ║" >&2
    echo "╚═══════════════════════════════════════════════════════════╝" >&2
    echo >&2
    
    for i in "${!processors[@]}"; do
        printf "%2d) %s\n" $((i + 1)) "${processors[$i]}" >&2
    done
    
    echo >&2
    read -rp "Select processor number [1-${#processors[@]}]: " selection >&2
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#processors[@]} ]; then
        log_message "ERROR: Invalid selection: $selection"
        return 2
    fi
    
    local selected_processor="${processors[$((selection - 1))]}"
    log_message "Manually selected: $selected_processor"
    echo "$selected_processor"
    return 0
}

#
# main() - Main entry point
#
main() {
    local mode="interactive"
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --auto)
                mode="auto"
                shift
                ;;
            --manual)
                mode="manual"
                shift
                ;;
            --interactive)
                mode="interactive"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--auto|--manual|--interactive]"
                echo
                echo "Options:"
                echo "  --auto         Auto-detect only (fail if detection fails)"
                echo "  --manual       Skip detection, show selection menu"
                echo "  --interactive  Try auto-detect, fallback to manual (default)"
                echo "  --help         Show this help message"
                exit 0
                ;;
            *)
                log_message "ERROR: Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
    
    local processor_folder=""
    
    case "$mode" in
        auto)
            processor_folder=$(auto_detect_processor)
            if [ $? -ne 0 ]; then
                log_message "ERROR: Auto-detection failed"
                exit 1
            fi
            ;;
        manual)
            processor_folder=$(manual_processor_selection)
            if [ $? -ne 0 ]; then
                log_message "ERROR: Manual selection failed"
                exit 2
            fi
            ;;
        interactive)
            processor_folder=$(auto_detect_processor 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$processor_folder" ]; then
                log_message "Auto-detection failed, falling back to manual selection..." >&2
                processor_folder=$(manual_processor_selection)
                if [ $? -ne 0 ]; then
                    log_message "ERROR: Manual selection failed"
                    exit 2
                fi
            else
                log_message "Auto-detected: $processor_folder" >&2
            fi
            ;;
    esac
    
    # Output the selected processor folder name to stdout
    echo "$processor_folder"
    exit 0
}

# Run main function
main "$@"

