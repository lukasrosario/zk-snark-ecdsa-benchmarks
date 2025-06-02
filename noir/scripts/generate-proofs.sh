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

# Source Barretenberg environment if it exists
if [ -f "$HOME/.bb/env" ]; then
  print_message "$CYAN" "Sourcing Barretenberg environment"
  source "$HOME/.bb/env"
fi

# Check if bb is available
if ! command -v bb &> /dev/null; then
  print_message "$RED" "Error: bb command not found"
  print_message "$CYAN" "Make sure Barretenberg (bb) is installed and in your PATH"
  print_message "$CYAN" "You can install it with: curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash"
  print_message "$CYAN" "Then source the environment: source ~/.bb/env"
  print_message "$CYAN" "Current PATH: $PATH"
  exit 1
fi

print_message "$CYAN" "Generating proofs for Noir ECDSA test cases..."

# Get the absolute path to the noir project directory (where Nargo.toml is located)
NOIR_DIR="$(dirname "$0")/.."
NOIR_DIR="$(cd "$NOIR_DIR" && pwd)"
TARGET_DIR="$NOIR_DIR/target"
NARGO_TOML_PACKAGE_NAME="benchmarking"

# Find all testcase directories
for testcase_dir in "$TARGET_DIR"/test_case_*; do
  if [ -d "$testcase_dir" ]; then
    BASENAME=$(basename "$testcase_dir")
    print_message "$CYAN" "Processing $BASENAME..."
    
    # Change to the testcase directory
    cd "$testcase_dir"
    CIRCUIT_FILE="./../$NARGO_TOML_PACKAGE_NAME.json"
    
    # Get the witness file name (should be the only .gz file in the directory)
    WITNESS_FILE=$(find . -name "*.gz" -type f)
    if [ -z "$WITNESS_FILE" ]; then
      print_message "$RED" "No witness file found in $testcase_dir"
      exit 1
    fi

    # Generate proof with keccak hash and bytes_and_fields format for EVM compatibility
    bb prove -b "$CIRCUIT_FILE" -w "$WITNESS_FILE" -o ./ --oracle_hash keccak --output_format bytes_and_fields || {
      print_message "$RED" "Failed to generate proof for $BASENAME"
      exit 1
    }
    print_message "$GREEN" "Proof for $BASENAME written to $testcase_dir/proof"
    print_message "$GREEN" "Proof fields for $BASENAME written to $testcase_dir/proof_fields.json"
    
    # Generate verification key with keccak hash for EVM compatibility
    bb write_vk -b $CIRCUIT_FILE -o ./ --oracle_hash keccak || {
      print_message "$RED" "Failed to generate verification key for $BASENAME"
      exit 1
    }
    print_message "$GREEN" "Verification key for $BASENAME written to $testcase_dir/vk"
    
    # Return to original directory
    cd - > /dev/null
  fi
done

print_message "$GREEN" "All proofs and verification keys generated successfully!"