#!/bin/bash

# Exit on error
set -e

echo "🔐 Generating proofs for all test cases..."

# Create directories for proofs and benchmark results
mkdir -p /out/proofs
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

# Check if all proof files already exist
missing_proofs=()
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    if [ ! -f "/out/proofs/proof_${test_case}.json" ] || [ ! -f "/out/proofs/public_${test_case}.json" ]; then
        missing_proofs+=($test_case)
    fi
done

if [ ${#missing_proofs[@]} -eq 0 ]; then
    echo "✅ All proof files already exist, skipping proof generation."
    echo "   Found all proof files for test cases: ${TEST_CASE_NUMBERS[*]}"
    echo "   To regenerate proofs, delete the proof files first."
    
    # Still check if we have benchmark results
    if [ -f "/out/benchmarks/all_proofs_benchmark.json" ]; then
        echo "📊 Displaying existing benchmark results:"
        if [ -f "/out/benchmarks/proofs_summary.md" ]; then
            cat /out/benchmarks/proofs_summary.md
        fi
    fi
    exit 0
fi

echo "📝 Found ${#missing_proofs[@]} missing proof files out of $NUM_TEST_CASES total."
echo "💡 Missing proofs: ${missing_proofs[*]}"

# Generate missing proofs with benchmark
echo "🔄 Generating missing proofs..."
# Create comma-separated list of missing test cases for hyperfine
MISSING_TEST_CASES=$(printf "%s," "${missing_proofs[@]}" | sed 's/,$//')
echo "🔄 Running benchmark for missing test cases: $MISSING_TEST_CASES"

hyperfine --min-runs 1 --max-runs 1 \
    -L test_case $MISSING_TEST_CASES \
    --show-output \
    --export-json /out/benchmarks/all_proofs_benchmark.json \
    --export-markdown /out/benchmarks/proofs_summary.md \
    'NODE_OPTIONS=--max_old_space_size=16384 snarkjs groth16 prove /out/setup/circuit.zkey /out/witnesses/witness_{test_case}.wtns /out/proofs/proof_{test_case}.json /out/proofs/public_{test_case}.json'

echo "✅ All proofs generated successfully!"

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "/out/benchmarks/all_proofs_benchmark.json" ]; then
    echo "Error: Benchmark results file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate average time"
    exit 1
fi

if ! min_time=$(jq -r '[.results[].min | select(. != null)] | min' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate minimum time"
    exit 1
fi

if ! max_time=$(jq -r '[.results[].max | select(. != null)] | max' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null); then
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
' /out/benchmarks/all_proofs_benchmark.json 2>/dev/null); then
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
