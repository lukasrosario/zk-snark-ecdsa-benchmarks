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

print_message "$CYAN" "Generating proofs for Noir ECDSA test cases..."

WITNESS_DIR="$(dirname "$0")/../target"
NARGO_TOML_PACKAGE_NAME="benchmarking"

# Find all testcase directories
for testcase_dir in "$WITNESS_DIR"/test_case_*; do
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

    # Generate proof
    bb prove -b "$CIRCUIT_FILE" -w "$WITNESS_FILE" -o ./|| {
      print_message "$RED" "Failed to generate proof for $BASENAME"
      exit 1
    }
    print_message "$GREEN" "Proof for $BASENAME written to $testcase_dir/${BASENAME}-proof"
    
    # Generate verification key
    bb write_vk -b $CIRCUIT_FILE -o ./ || {
      print_message "$RED" "Failed to generate verification key for $BASENAME"
      exit 1
    }
    print_message "$GREEN" "Verification key for $BASENAME written to $testcase_dir/${BASENAME}-vk"
    
    # Return to original directory
    cd - > /dev/null
  fi
done

print_message "$GREEN" "All proofs and verification keys generated successfully!"