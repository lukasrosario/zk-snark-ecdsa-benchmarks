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

# Ensure we're in the correct directory
cd /app

print_message "$CYAN" "🔨 [1/4] Compiling circuit..."

# Compile the circuit and run setup
print_message "$CYAN" "Compiling ECDSA circuit..."
go run main.go circuit.go compile -d /out

# Check if circuit files were created
if [ ! -f "/out/circuit.r1cs" ] || [ ! -f "/out/proving.key" ] || [ ! -f "/out/verifying.key" ]; then
    print_message "$RED" "Circuit compilation failed - missing required files!"
    exit 1
fi

print_message "$GREEN" "Circuit compilation and setup completed successfully!"
print_message "$CYAN" "Circuit files saved to /out/ directory." 