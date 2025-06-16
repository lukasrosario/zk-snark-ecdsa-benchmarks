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
if [ ! -f "data/circuit.r1cs" ]; then
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

# Check if all proof files already exist
missing_proofs=()
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    if [ ! -f "data/proof_${test_case}.groth16" ]; then
        missing_proofs+=($test_case)
    fi
done

if [ ${#missing_proofs[@]} -eq 0 ]; then
    print_message "$GREEN" "✅ All proof files already exist, skipping proof generation."
    print_message "$CYAN" "   Found all proof files for test cases: ${TEST_CASE_NUMBERS[*]}"
    print_message "$CYAN" "   To regenerate proofs, delete the proof files first."
    
    # Still display existing benchmark results
    if [ -f "/out/benchmarks/all_proofs_benchmark.json" ]; then
        print_message "$CYAN" "📊 Displaying existing benchmark results:"
        if [ -f "/out/benchmarks/proofs_summary.md" ]; then
            cat /out/benchmarks/proofs_summary.md
        fi
    fi
    exit 0
fi

print_message "$CYAN" "📝 Found ${#missing_proofs[@]} missing proof files out of $NUM_TEST_CASES total."
print_message "$CYAN" "💡 Missing proofs: ${missing_proofs[*]}"

# Create benchmark directories
mkdir -p /out/benchmarks

# Generate missing proofs with hyperfine benchmark
print_message "$CYAN" "🔄 Generating missing proofs..."
MISSING_TEST_CASES=$(printf "%s," "${missing_proofs[@]}" | sed 's/,$//')

hyperfine --min-runs 1 --max-runs 1 \
    -L test_case $MISSING_TEST_CASES \
    --show-output \
    --export-json /out/benchmarks/all_proofs_benchmark.json \
    --export-markdown /out/benchmarks/proofs_summary.md \
    'go run main.go circuit.go prove tests/test_case_{test_case}.json'

print_message "$GREEN" "✅ All proofs generated successfully!"

# Display benchmark results
if [ -f "/out/benchmarks/proofs_summary.md" ]; then
    print_message "$CYAN" "📊 Displaying benchmark results:"
    cat /out/benchmarks/proofs_summary.md
fi

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