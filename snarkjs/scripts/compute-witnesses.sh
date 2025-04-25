#!/bin/bash

# Exit on error
set -e

echo "🧮 Computing witnesses for all test cases..."

# Create a directory for benchmark results
mkdir -p ./benchmarks

# Run hyperfine with parameter list for test cases
echo "📊 Running benchmarks for all test cases..."
hyperfine --min-runs 1 --max-runs 1 \
    -L test_case 1,2,3,4,5,6,7,8,9,10 \
    --export-json ./benchmarks/all_witnesses_benchmark.json \
    --export-markdown ./benchmarks/summary.md \
    'node ./out/circuit_js/generate_witness.js ./out/circuit_js/circuit.wasm ./tests/test_case_{test_case}.json ./tests/witness_{test_case}.wtns'


echo "✅ All witnesses computed successfully!"

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "./benchmarks/all_witnesses_benchmark.json" ]; then
    echo "Error: Benchmark results file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' ./benchmarks/all_witnesses_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate average time"
    exit 1
fi

if ! min_time=$(jq -r '[.results[].min | select(. != null)] | min' ./benchmarks/all_witnesses_benchmark.json 2>/dev/null); then
    echo "Error: Could not calculate minimum time"
    exit 1
fi

if ! max_time=$(jq -r '[.results[].max | select(. != null)] | max' ./benchmarks/all_witnesses_benchmark.json 2>/dev/null); then
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
' ./benchmarks/all_witnesses_benchmark.json 2>/dev/null); then
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
