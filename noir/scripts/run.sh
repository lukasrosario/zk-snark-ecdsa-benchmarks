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

print_message "$CYAN" "Running all Noir ECDSA benchmark steps..."

SCRIPT_DIR="$(dirname "$0")"

print_message "$CYAN" "[1/4] Installing dependencies..."
bash "$SCRIPT_DIR/install-deps.sh"

print_message "$CYAN" "[2/4] Compiling circuit and generating witnesses..."
bash "$SCRIPT_DIR/compile-and-generate-witness.sh"

print_message "$CYAN" "[3/4] Generating proofs..."
bash "$SCRIPT_DIR/generate-proofs.sh"

print_message "$CYAN" "[5/5] Verifying proofs..."
bash "$SCRIPT_DIR/verify-proofs.sh"

print_message "$GREEN" "All Noir ECDSA benchmark steps completed successfully!" 