#!/bin/bash
# Copyright (c) 2024-2025, LongQT-sea

# macOS Python3 Silent Installer
# Installs appropriate Python3 version based on macOS version
# Checks if installer exists in current directory first; if not, downloads from python.org
# Supports macOS 10.6 and later

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get macOS version
get_macos_version() {
    sw_vers -productVersion
}

# Determine Python version and download URL based on macOS version
determine_python_version() {
    local macos_version=$1
    local major=$(echo "$macos_version" | cut -d. -f1)
    local minor=$(echo "$macos_version" | cut -d. -f2)
    
    if [ "$major" -eq 10 ]; then
        if [ "$minor" -ge 15 ]; then
            # macOS 10.15
            PYTHON_VERSION="3.14.0"
            PYTHON_PKG="python-3.14.0-macos11.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.14.0/python-3.14.0-macos11.pkg"
        elif [ "$minor" -ge 13 ] && [ "$minor" -le 14 ]; then
            # macOS 10.13 to 10.14
            PYTHON_VERSION="3.13.9"
            PYTHON_PKG="python-3.13.9-macos11.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.13.9/python-3.13.9-macos11.pkg"
        elif [ "$minor" -ge 9 ] && [ "$minor" -le 12 ]; then
            # macOS 10.9 to 10.12
            PYTHON_VERSION="3.9.13"
            PYTHON_PKG="python-3.9.13-macosx10.9.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.9.13/python-3.9.13-macosx10.9.pkg"
        elif [ "$minor" -ge 6 ] && [ "$minor" -le 8 ]; then
            # macOS 10.6 to 10.8
            PYTHON_VERSION="3.6.6"
            PYTHON_PKG="python-3.6.6-macosx10.6.pkg"
            DOWNLOAD_URL="https://www.python.org/ftp/python/3.6.6/python-3.6.6-macosx10.6.pkg"
        else
            print_error "Unsupported macOS version: $macos_version"
            exit 1
        fi
    elif [ "$major" -ge 11 ]; then
        # macOS 11 (Big Sur) and later
        PYTHON_VERSION="3.14.0"
        PYTHON_PKG="python-3.14.0-macos11.pkg"
        DOWNLOAD_URL="https://www.python.org/ftp/python/3.14.0/python-3.14.0-macos11.pkg"
    else
        print_error "Unsupported macOS version: $macos_version"
        exit 1
    fi
}

# Check if installer exists in current directory
check_local_installer() {
    local pattern=$1
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    # Use ls and grep to find matching files (more compatible)
    local found_file=""
    
    # First, try to find exact match
    if [ -f "$script_dir/$PYTHON_PKG" ]; then
        echo "$script_dir/$PYTHON_PKG"
        return 0
    fi
    
    # Then try pattern matching with ls
    found_file=$(ls -1 "$script_dir" 2>/dev/null | grep -E "^python-${PYTHON_VERSION}.*\.pkg$" | head -n 1)
    
    if [ -n "$found_file" ]; then
        echo "$script_dir/$found_file"
        return 0
    fi
    
    # Also check current working directory if different from script dir
    local current_dir="$(pwd)"
    if [ "$current_dir" != "$script_dir" ]; then
        if [ -f "$current_dir/$PYTHON_PKG" ]; then
            echo "$current_dir/$PYTHON_PKG"
            return 0
        fi
        
        found_file=$(ls -1 "$current_dir" 2>/dev/null | grep -E "^python-${PYTHON_VERSION}.*\.pkg$" | head -n 1)
        
        if [ -n "$found_file" ]; then
            echo "$current_dir/$found_file"
            return 0
        fi
    fi
    
    return 1
}

# Download installer
download_installer() {
    local url=$1
    local output=$2
    
    print_info "Downloading Python installer from: $url"
    
    if command -v curl &> /dev/null; then
        if curl -L -o "$output" "$url" --connect-timeout 30 --max-time 600; then
            return 0
        else
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if wget -O "$output" "$url" --timeout=30; then
            return 0
        else
            return 1
        fi
    else
        print_error "Neither curl nor wget found. Cannot download installer."
        return 1
    fi
}

# Install Python silently
install_python() {
    local pkg_path=$1
    
    print_info "Installing Python from: $pkg_path"
    
    if [ ! -f "$pkg_path" ]; then
        print_error "Installer file not found: $pkg_path"
        exit 1
    fi
    
    # Silent installation using installer command
    if sudo installer -pkg "$pkg_path" -target / -verbose; then
        print_info "Python installed successfully!"
        return 0
    else
        print_error "Installation failed!"
        return 1
    fi
}

# Main installation process
main() {
    print_info "macOS Python Silent Installer"
    echo ""
    
    # Get macOS version
    MACOS_VERSION=$(get_macos_version)
    print_info "Detected macOS version: $MACOS_VERSION"
    
    # Determine appropriate Python version
    determine_python_version "$MACOS_VERSION"
    print_info "Target Python version: $PYTHON_VERSION"
    print_info "Installer package: $PYTHON_PKG"
    echo ""
    
    # Check if installer exists locally
    print_info "Checking for local installer..."
    print_info "Script directory: $(cd "$(dirname "$0")" && pwd)"
    print_info "Current directory: $(pwd)"
    
    LOCAL_PKG=""
    
    # Extract version pattern for search (e.g., "python-3.9.13*")
    VERSION_PATTERN="python-${PYTHON_VERSION}*"
    
    if LOCAL_PKG=$(check_local_installer "$VERSION_PATTERN"); then
        print_info "Found local installer: $LOCAL_PKG"
        INSTALLER_PATH="$LOCAL_PKG"
    else
        print_warning "Local installer not found. Attempting to download..."
        # Save to current user's Downloads folder
        DOWNLOADS_DIR="$HOME/Downloads"
        INSTALLER_PATH="$DOWNLOADS_DIR/$PYTHON_PKG"
        
        print_info "Will save installer to: $INSTALLER_PATH"
        
        if ! download_installer "$DOWNLOAD_URL" "$INSTALLER_PATH"; then
            print_error "Download failed!"
            echo ""
            print_warning "This may be due to outdated SSL/TLS support on older macOS versions."
            print_warning "Please try one of the following options:"
            echo "  1. Download the installer on a newer macOS system and transfer it here"
            echo "  2. Download manually from: $DOWNLOAD_URL"
            echo "  3. Place the installer in the same directory as this script and run again"
            echo ""
            print_info "Looking for: $PYTHON_PKG"
            exit 1
        fi
        
        print_info "Download completed successfully!"
    fi
    
    echo ""
    
    # Install Python
    if install_python "$INSTALLER_PATH"; then
        echo ""
        print_info "Installation complete!"
        
        # Verify installation
        if command -v python3 &> /dev/null; then
            INSTALLED_VERSION=$(python3 --version 2>&1)
            print_info "Installed: $INSTALLED_VERSION"
        fi
    else
        exit 1
    fi
}

# Run main function
main

exit 0