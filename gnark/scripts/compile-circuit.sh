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

# Check if compilation already done
if [ -f "/out/circuit.r1cs" ] && [ -f "/out/proving.key" ]; then
    print_message "$GREEN" "✅ Circuit already compiled. Skipping."
    exit 0
fi

# Compile the circuit and run setup
print_message "$CYAN" "Compiling ECDSA circuit..."
go run main.go circuit.go compile

# Check if circuit files were created
if [ ! -f "data/circuit.r1cs" ] || [ ! -f "data/proving.key" ] || [ ! -f "data/verifying.key" ]; then
    print_message "$RED" "❌ Circuit compilation failed. Files not found."
    exit 1
fi

print_message "$GREEN" "✅ Circuit compiled and setup complete."
print_message "$CYAN" "   Artifacts saved to /out/"

# Copy artifacts to /out directory
cp data/circuit.r1cs data/proving.key data/verifying.key /out/ 