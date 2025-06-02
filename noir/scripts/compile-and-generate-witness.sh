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

TESTS_DIR="$(dirname "$0")/../tests"

for testcase in "$TESTS_DIR"/test_case_*.toml; do
  print_message "$CYAN" "Computing witness for $testcase..."
  if [ -f "$testcase" ]; then
    BASENAME=$(basename "$testcase" .toml)
    print_message "$CYAN" "Computing witness for $BASENAME..."
    
    # Create directory for this testcase
    TESTCASE_DIR="target/${BASENAME}"
    if [ -d "$TESTCASE_DIR" ]; then
      print_message "$CYAN" "Removing existing directory for $BASENAME..."
      rm -rf "$TESTCASE_DIR"
    fi
    mkdir -p "$TESTCASE_DIR"
    
    # Compiles and executes the Noir program, generating the witness
    nargo execute -p "$testcase" "${BASENAME}_witness" || {
      print_message "$RED" "Failed to compile or compute witness for $BASENAME";
      exit 1;
    }
    
    # Move the witness file to the testcase directory
    mv "target/${BASENAME}_witness.gz" "$TESTCASE_DIR/"
    print_message "$GREEN" "Witness for $BASENAME written to $TESTCASE_DIR/${BASENAME}_witness.gz"
  fi
done

print_message "$GREEN" "Noir circuit compiled successfully! Artifacts are in $BUILD_DIR." 