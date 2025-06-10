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

print_message "$CYAN" "Starting circuit compilation and setup..."

# Ensure we're in the correct directory
cd /app

# Create data directory if it doesn't exist
mkdir -p data
mkdir -p /out

# Compile the circuit and run setup
print_message "$CYAN" "Compiling ECDSA circuit..."
go run main.go circuit.go compile

# Check if circuit files were created
if [ ! -f "data/circuit.r1cs" ] || [ ! -f "data/proving.key" ] || [ ! -f "data/verifying.key" ]; then
    print_message "$RED" "Circuit compilation failed - missing required files!"
    exit 1
fi

# Copy circuit files to output directory for persistence
cp -r data/* /out/

print_message "$GREEN" "Circuit compilation and setup completed successfully!"
print_message "$CYAN" "Circuit files saved to data/ and /out/ directories." 