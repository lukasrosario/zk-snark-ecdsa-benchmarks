#!/bin/bash

# Exit on error
set -e

echo "🔍 Verifying proofs for all test cases..."

# Create directories for verification results and benchmark results
mkdir -p /out/verification
mkdir -p /out/benchmarks

# Discover test cases from tests directory
TEST_CASE_FILES=(./tests/test_case_*.json)
if [ ! -e "${TEST_CASE_FILES[0]}" ]; then
    echo "❌ No test case files found in tests directory!"
    echo "   Expected files like: test_case_1.json, test_case_2.json, etc."
    exit 1
fi

# Extract test case numbers and sort them
TEST_CASE_NUMBERS=()
for file in "${TEST_CASE_FILES[@]}"; do
    # Extract number from filename (e.g., test_case_3.json -> 3)
    if [[ $file =~ test_case_([0-9]+)\.json ]]; then
        TEST_CASE_NUMBERS+=(${BASH_REMATCH[1]})
    fi
done

# Sort the test case numbers
IFS=$'\n' TEST_CASE_NUMBERS=($(sort -n <<<"${TEST_CASE_NUMBERS[*]}"))
unset IFS

NUM_TEST_CASES=${#TEST_CASE_NUMBERS[@]}

echo "🔍 Discovered $NUM_TEST_CASES test cases: ${TEST_CASE_NUMBERS[*]}"

# Check if verification has already been completed
if [ -f "/out/benchmarks/all_verifications_benchmark.json" ]; then
    echo "✅ Proof verification already completed, skipping verification step."
    echo "   Found verification results for all test cases."
    echo "   To re-verify, delete the '/out/benchmarks/all_verifications_benchmark.json' file first."
    
    # Display existing benchmark results
    echo "📊 Displaying existing benchmark results:"
    if [ -f "/out/benchmarks/verifications_summary.md" ]; then
        cat /out/benchmarks/verifications_summary.md
    fi
    exit 0
fi

# Prepare test cases for verification
echo "📝 Preparing test cases for verification..."
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    echo "🧹 Cleaning files for test case ${test_case}..."
    
    # Clean public files
    if [ -f "/out/proofs/public_${test_case}.json" ]; then
        cat /out/proofs/public_${test_case}.json | tr -d "\0" | jq -c . | tr -d "\n" > /out/verification/public_${test_case}.json
    fi
    
    # Clean proof files
    if [ -f "/out/proofs/proof_${test_case}.json" ]; then
        cat /out/proofs/proof_${test_case}.json | tr -d "\0" | jq -c . | tr -d "\n" > /out/verification/proof_${test_case}.json
    fi
done

# Create comma-separated list of test cases for hyperfine
TEST_CASES=$(printf "%s," "${TEST_CASE_NUMBERS[@]}" | sed 's/,$//')

# Run hyperfine with parameter list for test cases
echo "📊 Running verification benchmarks for $NUM_TEST_CASES test cases..."

hyperfine --min-runs 1 --max-runs 1 \
    --show-output \
    -L test_case $TEST_CASES \
    --export-json /out/benchmarks/all_verifications_benchmark.json \
    --export-markdown /out/benchmarks/verifications_summary.md \
    'echo "Verifying {test_case}..."; snarkjs groth16 verify /out/setup/verification_key.json /out/verification/public_{test_case}.json /out/verification/proof_{test_case}.json'

echo "✅ All proofs verified successfully!"

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "/out/benchmarks/all_verifications_benchmark.json" ]; then
    echo "Error: Benchmark results file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate average time"
    exit 1
fi

if ! min_time=$(jq -r '[.results[].min | select(. != null)] | min' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate minimum time"
    exit 1
fi

if ! max_time=$(jq -r '[.results[].max | select(. != null)] | max' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate maximum time"  
    exit 1
fi

# Calculate standard deviation
if ! std_dev=$(jq -r '
    .results | 
    map(.mean) | 
    (add / length) as $mean |
    map(($mean - .) * ($mean - .)) |
    (add / length) | 
    sqrt
' /out/benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate standard deviation"
    exit 1
fi

# Only print if we have valid numbers
if [[ "$avg_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$min_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$max_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$std_dev" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    printf "Average Time: %.3f ± %.3f seconds\n" $avg_time $std_dev
    printf "Min Time: %.3f seconds\n" $min_time
    printf "Max Time: %.3f seconds\n" $max_time
else
    echo "Error: Invalid numerical values in benchmark results"
    exit 1
fi

echo "----------------------------------------"
