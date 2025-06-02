#!/bin/bash

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

print_message "$CYAN" "Installing Noir and dependencies..."

# Check for Rust
if ! command -v cargo &> /dev/null; then
  print_message "$RED" "Rust is not installed. Please install Rust from https://rustup.rs/ and re-run this script."
  exit 1
fi

# Install nargo using noirup
print_message "$CYAN" "Checking for nargo..."
if ! command nargo --version &> /dev/null; then
  print_message "$CYAN" "Installing noirup..."
  curl -L https://raw.githubusercontent.com/noir-lang/noirup/refs/heads/main/install | bash
  print_message "$GREEN" "noirup installed successfully!"
else
  print_message "$GREEN" "nargo is already installed"
fi

print_message "$CYAN" "Running noirup to ensure latest version..."
noirup

# Install bb using bbup
print_message "$CYAN" "Checking for bb..."
if ! command -v bb &> /dev/null; then
  print_message "$CYAN" "Installing bbup..."
  curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/master/barretenberg/bbup/install | bash
  print_message "$GREEN" "bbup installed successfully!"
else
  print_message "$GREEN" "bb is already installed"
fi

print_message "$CYAN" "Running bbup to ensure latest version..."
bbup

print_message "$GREEN" "Noir (nargo) and Barretenberg (bb) installed successfully!" 