#!/bin/bash

# Exit on error
set -e

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function for better output
log() {
    local type=$1
    local message=$2
    
    case $type in
        "info")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            echo "debian"
        else
            echo "unsupported"
        fi
    else
        echo "unsupported"
    fi
}

# Function to install dependencies on MacOS
install_macos_deps() {
    log "info" "Installing dependencies using Homebrew..."
    
    # Check if Homebrew is installed
    if ! command_exists brew; then
        log "error" "Homebrew is not installed. Please install it first: https://brew.sh/"
        exit 1
    fi
    
    # Update Homebrew
    brew update || { log "error" "Failed to update Homebrew"; exit 1; }
    
    # Install dependencies
    packages=(
        "git"
        "cmake"
        "gmp"
        "libsodium"
        "nasm"
        "m4"
        "wget"
        "jq"
    )
    
    for pkg in "${packages[@]}"; do
        log "info" "Installing $pkg..."
        brew install "$pkg" || { log "error" "Failed to install $pkg"; exit 1; }
    done
    
    log "success" "Successfully installed MacOS dependencies"
}

# Function to install dependencies on Debian/Ubuntu
install_debian_deps() {
    log "info" "Installing dependencies using apt..."
    
    # Update package lists
    sudo apt-get update || { log "error" "Failed to update apt package lists"; exit 1; }
    
    # Install dependencies
    packages=(
        "git"
        "build-essential"
        "cmake"
        "libgmp-dev"
        "libsodium-dev"
        "nasm"
        "curl"
        "m4"
        "wget"
        "jq"
        "vim-common"
    )
    
    log "info" "Installing packages: ${packages[*]}"
    sudo apt-get install -y "${packages[@]}" || { 
        log "error" "Failed to install dependencies"; 
        exit 1; 
    }
    
    log "success" "Successfully installed Debian/Ubuntu dependencies"
}

# Function to initialize and update git submodules
init_submodules() {
    log "info" "Initializing and updating git submodules..."
    
    git submodule init || { 
        log "error" "Failed to initialize git submodules"; 
        exit 1; 
    }
    
    git submodule update || { 
        log "error" "Failed to update git submodules"; 
        exit 1; 
    }
    
    log "success" "Successfully initialized and updated git submodules"
}

# Function to build GMP and rapidsnark
build_rapidsnark() {
    log "info" "Building GMP..."
    
    # Check if build_gmp.sh exists
    if [[ ! -f "build_gmp.sh" ]]; then
        log "error" "build_gmp.sh not found in current directory"
        exit 1
    fi
    
    # Make build_gmp.sh executable if it's not already
    chmod +x build_gmp.sh
    
    # Build GMP
    ./build_gmp.sh host_noasm || {
        log "error" "Failed to build GMP"
        exit 1
    }
    
    log "success" "Successfully built GMP"
    
    # Clean any existing build artifacts
    log "info" "Cleaning existing build artifacts..."
    rm -rf build_prover
    
    # Build rapidsnark
    log "info" "Building rapidsnark..."
    make host_noasm || {
        log "error" "Failed to build rapidsnark"
        exit 1
    }
    
    log "success" "Successfully built rapidsnark"
    
    # Verify the build
    if [[ -f "./package_noasm/bin/prover" ]]; then
        log "success" "Build verification: prover binary found at ./package_noasm/bin/prover"
    else
        log "error" "Build verification failed: prover binary not found"
        exit 1
    fi
}

# Main function
main() {
    log "info" "Starting setup dependencies for rapidsnark..."
    
    # Detect OS
    OS=$(detect_os)
    log "info" "Detected OS: $OS"
    
    # Install dependencies based on OS
    case $OS in
        "macos")
            install_macos_deps
            ;;
        "debian")
            install_debian_deps
            ;;
        *)
            log "error" "Unsupported OS. This script supports MacOS and Debian/Ubuntu."
            exit 1
            ;;
    esac
    
    # Initialize and update git submodules
    init_submodules
    
    # Build GMP and rapidsnark
    build_rapidsnark
    
    log "success" "Rapidsnark setup completed successfully!"
}

# Run main function
main

