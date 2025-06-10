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

print_message "$CYAN" "Running comprehensive performance benchmarks..."

# Ensure we're in the correct directory
cd /app

# Create output directory
mkdir -p /out

# Run compilation benchmark
print_message "$CYAN" "Benchmarking circuit compilation..."
hyperfine --warmup 1 --runs 3 --export-json /out/gnark_compilation_times.json \
    --prepare 'rm -rf data/*' \
    'go run main.go circuit.go compile'

# Run end-to-end benchmark (compilation + proving + verification)
print_message "$CYAN" "Benchmarking end-to-end performance..."
hyperfine --warmup 1 --runs 3 --export-json /out/gnark_end_to_end_times.json \
    --prepare 'rm -rf data/*' \
    'go run main.go circuit.go compile && go run main.go circuit.go prove && go run main.go circuit.go verify'

# Count test cases and collect stats
TEST_CASE_COUNT=$(ls tests/test_case_*.json 2>/dev/null | wc -l)
print_message "$CYAN" "Collecting benchmark statistics..."

# Create a summary report
cat > /out/gnark_benchmark_summary.txt << EOF
gnark ECDSA Benchmark Summary
============================

Test Cases Processed: $TEST_CASE_COUNT

Circuit Information:
- Curve: P-256 (secp256r1)
- Proving System: Groth16
- Backend: BN254

Files Generated:
- Circuit compilation times: gnark_compilation_times.json
- Proof generation times: gnark_proving_times.json  
- Proof verification times: gnark_verification_times.json
- End-to-end times: gnark_end_to_end_times.json

Generated at: $(date)
EOF

print_message "$GREEN" "Performance benchmarking completed successfully!"
print_message "$CYAN" "Results saved to /out/ directory" 