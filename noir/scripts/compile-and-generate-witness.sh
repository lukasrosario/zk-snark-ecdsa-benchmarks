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

print_message "$CYAN" "Compiling Noir ECDSA circuit..."

if ! command -v nargo &> /dev/null; then
  print_message "$RED" "nargo could not be found. Please install Noir and nargo first."
  exit 1
fi

# Get the absolute path to the noir project directory (where Nargo.toml is located)
NOIR_DIR="$(dirname "$0")/.."
NOIR_DIR="$(cd "$NOIR_DIR" && pwd)"
TESTS_DIR="$NOIR_DIR/tests"
TARGET_DIR="$NOIR_DIR/target"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Change to the Noir project directory where Nargo.toml is located
cd "$NOIR_DIR"

print_message "$CYAN" "Working in directory: $(pwd)"
print_message "$CYAN" "Checking for Nargo.toml: $(ls -la Nargo.toml)"

# First compile the circuit
print_message "$CYAN" "Compiling the circuit..."
nargo compile || {
  print_message "$RED" "Failed to compile Noir circuit";
  exit 1;
}

# Process each test case
for testcase in "$TESTS_DIR"/test_case_*.toml; do
  if [ -f "$testcase" ]; then
    BASENAME=$(basename "$testcase" .toml)
    print_message "$CYAN" "Computing witness for $BASENAME..."
    
    # Create directory for this testcase
    TESTCASE_DIR="$TARGET_DIR/${BASENAME}"
    if [ -d "$TESTCASE_DIR" ]; then
      print_message "$CYAN" "Removing existing directory for $BASENAME..."
      rm -rf "$TESTCASE_DIR"
    fi
    mkdir -p "$TESTCASE_DIR"
    
    # Execute the Noir program, generating the witness
    nargo execute -p "$testcase" "${BASENAME}_witness" || {
      print_message "$RED" "Failed to compute witness for $BASENAME";
      exit 1;
    }
    
    # Move the witness file to the testcase directory
    mv "$TARGET_DIR/${BASENAME}_witness.gz" "$TESTCASE_DIR/" || {
      print_message "$RED" "Failed to move witness file for $BASENAME";
      exit 1;
    }
    
    print_message "$GREEN" "Witness for $BASENAME written to $TESTCASE_DIR/${BASENAME}_witness.gz"
  fi
done

print_message "$GREEN" "Noir circuit compiled successfully! Artifacts are in $TARGET_DIR." 