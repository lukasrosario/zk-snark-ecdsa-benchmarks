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

print_message "$CYAN" "🔍 Verifying proofs for all test cases..."

# Ensure we're in the correct directory
cd /app

# Check if verifying key exists
if [ ! -f "data/verifying.key" ]; then
    print_message "$RED" "Verifying key not found. Please run compile-circuit.sh first."
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

# Check if verification already completed
if [ -f "/out/benchmarks/all_verifications_benchmark.json" ]; then
    print_message "$GREEN" "✅ Proof verification already completed, skipping verification step."
    print_message "$CYAN" "   Found verification results for all test cases."
    print_message "$CYAN" "   To re-verify, delete the '/out/benchmarks/all_verifications_benchmark.json' file first."
    
    # Display existing benchmark results
    if [ -f "/out/benchmarks/verifications_summary.md" ]; then
        print_message "$CYAN" "📊 Displaying existing benchmark results:"
        cat /out/benchmarks/verifications_summary.md
    fi
    exit 0
fi

# Check if proof files exist
missing_proofs=()
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    if [ ! -f "data/proof_${test_case}.groth16" ]; then
        missing_proofs+=($test_case)
    fi
done

if [ ${#missing_proofs[@]} -gt 0 ]; then
    print_message "$RED" "Missing proof files for test cases: ${missing_proofs[*]}"
    print_message "$RED" "Please run generate-proofs.sh first."
    exit 1
fi

# Create benchmark directories
mkdir -p /out/benchmarks

# Verify proofs with hyperfine benchmark  
print_message "$CYAN" "🔄 Verifying proofs..."
TEST_CASES_LIST=$(printf "%s," "${TEST_CASE_NUMBERS[@]}" | sed 's/,$//')

hyperfine --min-runs 1 --max-runs 1 \
    -L test_case $TEST_CASES_LIST \
    --show-output \
    --export-json /out/benchmarks/all_verifications_benchmark.json \
    --export-markdown /out/benchmarks/verifications_summary.md \
    'echo "Verifying {test_case}..."; go run main.go circuit.go verify tests/test_case_{test_case}.json'

print_message "$GREEN" "✅ All proofs verified successfully!"

# Display benchmark results
if [ -f "/out/benchmarks/verifications_summary.md" ]; then
    print_message "$CYAN" "📊 Displaying benchmark results:"
    cat /out/benchmarks/verifications_summary.md
fi

# Calculate and display aggregate statistics
print_message "$CYAN" ""
print_message "$CYAN" "📈 Aggregate Statistics:"
print_message "$CYAN" "----------------------------------------"

if [ -f "/out/benchmarks/all_verifications_benchmark.json" ]; then
    avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null)
    min_time=$(jq -r '[.results[].min | select(. != null)] | min' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null)
    max_time=$(jq -r '[.results[].max | select(. != null)] | max' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null)
    
    # Convert to milliseconds for display (like rapidsnark)
    avg_time_ms=$(echo "$avg_time * 1000" | bc -l)
    min_time_ms=$(echo "$min_time * 1000" | bc -l)
    max_time_ms=$(echo "$max_time * 1000" | bc -l)
    
    printf "Average Time: %.1f ms\n" $avg_time_ms
    printf "Min Time: %.1f ms\n" $min_time_ms
    printf "Max Time: %.1f ms\n" $max_time_ms
fi

print_message "$CYAN" "----------------------------------------" 