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

print_message "$CYAN" "🚀 Starting ECDSA SNARK benchmark setup..."

# Phase 1: Compile circuit
print_message "$CYAN" "🔨 Compiling circuit..."
./scripts/compile-circuit.sh

# Phase 2: Generate proofs
print_message "$CYAN" "🔐 Generating proofs..."
./scripts/generate-proofs.sh

# Phase 3: Verify proofs  
print_message "$CYAN" "🔍 Verifying proofs..."
./scripts/verify-proofs.sh

# Phase 4: Benchmark gas usage
print_message "$CYAN" "⛽ Benchmarking gas usage..."
./scripts/benchmark-gas.sh

print_message "$GREEN" "✅ All done! Check the benchmarks and gas-reports directories for results." 