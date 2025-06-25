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

print_message "$CYAN" "🔐 Generating proofs for all test cases..."

# Ensure we're in the correct directory
cd /app

# Check if circuit is compiled
if [ ! -f "/out/circuit.r1cs" ]; then
    print_message "$RED" "Circuit not found. Please run compile-circuit.sh first."
    exit 1
fi

# Discover test cases
TEST_CASE_FILES=(tests/test_case_*.json)
if [ ! -e "${TEST_CASE_FILES[0]}" ]; then
    print_message "$RED" "No test case files found in tests directory!"
    exit 1
fi

# Extract test case numbers and sort them
TEST_CASE_NUMBERS=()
for file in "${TEST_CASE_FILES[@]}"; do
    if [[ $file =~ test_case_([0-9]+)\.json ]]; then
        TEST_CASE_NUMBERS+=(${BASH_REMATCH[1]})
    fi
done

# Sort the test case numbers
IFS=$'\n' TEST_CASE_NUMBERS=($(sort -n <<<"${TEST_CASE_NUMBERS[*]}"))
unset IFS

NUM_TEST_CASES=${#TEST_CASE_NUMBERS[@]}
print_message "$CYAN" "🔍 Discovered $NUM_TEST_CASES test cases: ${TEST_CASE_NUMBERS[*]}"

# Create benchmark directories
mkdir -p /out/benchmarks

# Generate proofs with hyperfine benchmark
print_message "$CYAN" "🔄 Generating proofs..."
TEST_CASES_LIST=$(printf "%s," "${TEST_CASE_NUMBERS[@]}" | sed 's/,$//')

hyperfine --min-runs 1 --max-runs 1 \
    -L test_case $TEST_CASES_LIST \
    --show-output \
    --export-json /out/benchmarks/all_proofs_benchmark.json \
    --export-markdown /out/benchmarks/proofs_summary.md \
    'go run main.go circuit.go prove -d /out tests/test_case_{test_case}.json'

print_message "$GREEN" "✅ All proofs generated successfully!"

# Calculate and display aggregate statistics
print_message "$CYAN" ""
print_message "$CYAN" "📈 Aggregate Statistics:"
print_message "$CYAN" "----------------------------------------"

if [ -f "/out/benchmarks/all_proofs_benchmark.json" ]; then
    avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null)
    min_time=$(jq -r '[.results[].min | select(. != null)] | min' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null)
    max_time=$(jq -r '[.results[].max | select(. != null)] | max' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null)
    
    std_dev=$(jq -r '
        .results | 
        map(.mean) | 
        (add / length) as $mean |
        map(($mean - .) * ($mean - .)) |
        (add / length) | 
        sqrt
    ' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null)
    
    if [[ "$avg_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        printf "Average Time: %.3f ± %.3f seconds\n" $avg_time $std_dev
        printf "Min Time: %.3f seconds\n" $min_time
        printf "Max Time: %.3f seconds\n" $max_time
    fi
fi

print_message "$CYAN" "----------------------------------------" 