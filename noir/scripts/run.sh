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

# Debug environment
print_message "$CYAN" "Current PATH: $PATH"
print_message "$CYAN" "Checking for bb command..."
if command -v bb &> /dev/null; then
  print_message "$GREEN" "bb command found at: $(which bb)"
  bb --version || print_message "$RED" "bb command found but failed to run"
else
  print_message "$RED" "bb command not found in PATH"
  # Try to find it
  find / -name "bb" 2>/dev/null | while read -r bb_path; do
    print_message "$CYAN" "Found bb at: $bb_path"
  done
fi

# Source Barretenberg environment if it exists
if [ -f "$HOME/.bb/env" ]; then
  print_message "$CYAN" "Sourcing Barretenberg environment"
  source "$HOME/.bb/env"
  print_message "$CYAN" "Updated PATH: $PATH"
fi

print_message "$CYAN" "Running all Noir ECDSA benchmark steps..."

SCRIPT_DIR="$(dirname "$0")"

print_message "$CYAN" "[2/4] Compiling circuit and generating witnesses..."
bash "$SCRIPT_DIR/compile-and-generate-witness.sh"

print_message "$CYAN" "[3/4] Generating proofs..."
bash "$SCRIPT_DIR/generate-proofs.sh"

print_message "$CYAN" "[5/5] Verifying proofs..."
bash "$SCRIPT_DIR/verify-proofs.sh"

print_message "$CYAN" "[6/6] Benchmarking gas usage..."
bash "$SCRIPT_DIR/benchmark-gas.sh"

print_message "$GREEN" "All Noir ECDSA benchmark steps completed successfully!" 