#!/bin/bash

# Exit on error
set -e

echo "🔐 [4/5] Generating proofs..."

# Create directories for proofs and benchmark results
mkdir -p /out/proofs

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

# Detect available memory and set appropriate Node.js heap size (cross-platform)
if [ -n "$NODE_MEMORY_MB" ]; then
    # Use pre-calculated Node.js memory allocation passed from host
    NODE_MEMORY=$NODE_MEMORY_MB
    echo "🎯 Using pre-calculated Node.js memory allocation: ${NODE_MEMORY}MB"
elif [ -n "$HOST_MEMORY_MB" ]; then
    # Use memory info passed from host and calculate Node.js allocation
    TOTAL_MEM_MB=$HOST_MEMORY_MB
    echo "📊 Using host memory info: ${TOTAL_MEM_MB}MB"
    
    if [ "$TOTAL_MEM_MB" -ge 15000 ]; then
        NODE_MEMORY=12288
    elif [ "$TOTAL_MEM_MB" -ge 7000 ]; then
        NODE_MEMORY=6144
    else
        NODE_MEMORY=3072
    fi
elif command -v free >/dev/null 2>&1; then
    # Linux (EC2 instances)
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2}')
    echo "📊 Detected memory using free command: ${TOTAL_MEM_MB}MB"
    
    if [ "$TOTAL_MEM_MB" -ge 15000 ]; then
        NODE_MEMORY=12288
    elif [ "$TOTAL_MEM_MB" -ge 7000 ]; then
        NODE_MEMORY=6144
    else
        NODE_MEMORY=3072
    fi
elif command -v sysctl >/dev/null 2>&1; then
    # macOS
    TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "8589934592")
    TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
    echo "📊 Detected memory using sysctl: ${TOTAL_MEM_MB}MB"
    
    if [ "$TOTAL_MEM_MB" -ge 15000 ]; then
        NODE_MEMORY=12288
    elif [ "$TOTAL_MEM_MB" -ge 7000 ]; then
        NODE_MEMORY=6144
    else
        NODE_MEMORY=3072
    fi
else
    # Fallback: assume 8GB
    TOTAL_MEM_MB=8192
    NODE_MEMORY=6144
    echo "⚠️  Could not detect memory, assuming 8GB with 6GB for Node.js"
fi

echo "📊 Detected ${TOTAL_MEM_MB}MB RAM, allocating ${NODE_MEMORY}MB to Node.js"

# Generate proofs with benchmark
echo "🔄 Generating proofs..."
TEST_CASES_LIST=$(printf "%s," "${TEST_CASE_NUMBERS[@]}" | sed 's/,$//')

hyperfine --min-runs 1 --max-runs 1 \
    -L test_case $TEST_CASES_LIST \
    --show-output \
    --export-json /out/benchmarks/all_proofs_benchmark.json \
    --export-markdown /out/benchmarks/proofs_summary.md \
    "NODE_OPTIONS=--max_old_space_size=$NODE_MEMORY snarkjs groth16 prove /out/setup/circuit.zkey /out/witnesses/witness_{test_case}.wtns /out/proofs/proof_{test_case}.json /out/proofs/public_{test_case}.json"

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
