#!/bin/bash

# Exit on error
set -e

# Default number of test cases
NUM_TEST_CASES=10

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --num-test-cases|-n)
      NUM_TEST_CASES="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "🔍 Verifying proofs for $NUM_TEST_CASES test cases..."

# Create a directory for benchmark results
mkdir -p ./benchmarks

# Generate test case list based on NUM_TEST_CASES
TEST_CASES=$(seq 1 $NUM_TEST_CASES | tr '\n' ',' | sed 's/,$//')

# Run hyperfine with parameter list for test cases
echo "📊 Running benchmarks for $NUM_TEST_CASES test cases..."

hyperfine --min-runs 1 --max-runs 1 \
    --show-output \
    -L test_case $TEST_CASES \
    --export-json ./benchmarks/all_verifications_benchmark.json \
    --export-markdown ./benchmarks/verifications_summary.md \
    '
    echo "Cleaning public_{test_case}.json..."; 
    cat ./tests/public_{test_case}.json | tr -d "\0" | jq -c . | tr -d "\n" > ./tests/public_{test_case}.json.clean && mv ./tests/public_{test_case}.json.clean ./tests/public_{test_case}.json; 
    echo "Cleaning proof_{test_case}.json..."; 
    cat ./tests/proof_{test_case}.json | tr -d "\0" | jq -c . | tr -d "\n" > ./tests/proof_{test_case}.json.clean && mv ./tests/proof_{test_case}.json.clean ./tests/proof_{test_case}.json; 
    echo "Verifying {test_case}..."; 
    snarkjs groth16 verify verification_key.json ./tests/public_{test_case}.json ./tests/proof_{test_case}.json
    '

echo "✅ All proofs verified successfully!"

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "./benchmarks/all_verifications_benchmark.json" ]; then
    echo "Error: Benchmark results file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' ./benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate average time"
    exit 1
fi

if ! min_time=$(jq -r '[.results[].min | select(. != null)] | min' ./benchmarks/all_verifications_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate minimum time"
    exit 1
fi

if ! max_time=$(jq -r '[.results[].max | select(. != null)] | max' ./benchmarks/all_verifications_benchmark.json 2>/dev/null); then
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
' ./benchmarks/all_verifications_benchmark.json 2>/dev/null); then
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
