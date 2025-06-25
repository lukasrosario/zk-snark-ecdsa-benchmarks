#!/bin/bash

set -e

# Clean output directory for a fresh run
if [ -d "/out" ]; then
    rm -rf /out/*
else
    mkdir -p /out
fi

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
print_message "$CYAN" "🚀 Starting Noir ECDSA benchmark setup..."
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

SCRIPT_DIR="$(dirname "$0")"

# Step 1: Compile circuit and generate witnesses
print_message "$CYAN" "🔨 [1/4] Compiling circuit and generating witnesses..."
bash "$SCRIPT_DIR/compile-and-generate-witness.sh"

# Step 2: Generate proofs
print_message "$CYAN" "🔐 [2/4] Generating proofs..."
bash "$SCRIPT_DIR/generate-proofs.sh"

# Step 3: Verify proofs
print_message "$CYAN" "🔍 [3/4] Verifying proofs..."
bash "$SCRIPT_DIR/verify-proofs.sh"

# Step 4: Benchmark gas usage
print_message "$CYAN" "⛽ [4/4] Benchmarking gas usage..."
bash "$SCRIPT_DIR/benchmark-gas.sh"

print_message "$GREEN" "✅ All Noir ECDSA benchmark steps completed successfully!"
print_message "$GREEN" "📁 Check the /out directory for all artifacts and benchmarks." 