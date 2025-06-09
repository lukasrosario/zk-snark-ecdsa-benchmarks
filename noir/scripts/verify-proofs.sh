#!/bin/bash

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Default number of test cases (will be determined automatically)
NUM_TEST_CASES=0

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

print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Source Barretenberg environment if it exists
if [ -f "$HOME/.bb/env" ]; then
  print_message "$CYAN" "Sourcing Barretenberg environment"
  source "$HOME/.bb/env"
fi

# Check if bb is available
if ! command -v bb &> /dev/null; then
  print_message "$RED" "Error: bb command not found"
  print_message "$CYAN" "Make sure Barretenberg (bb) is installed and in your PATH"
  print_message "$CYAN" "You can install it with: curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash"
  print_message "$CYAN" "Then source the environment: source ~/.bb/env"
  exit 1
fi

print_message "$CYAN" "Verifying proofs for Noir ECDSA test cases..."

# Get the absolute path to the noir project directory (where Nargo.toml is located)
NOIR_DIR="$(dirname "$0")/.."
NOIR_DIR="$(cd "$NOIR_DIR" && pwd)"
TESTS_DIR="$NOIR_DIR/tests"
TARGET_DIR="$NOIR_DIR/target"
BENCHMARK_DIR="$NOIR_DIR/benchmarks"

# Create a directory for benchmark results
mkdir -p "$BENCHMARK_DIR"

# Find all testcase directories and create a list for hyperfine
TEST_CASE_DIRS=()
for testcase_dir in "$TARGET_DIR"/test_case_*; do
  if [ -d "$testcase_dir" ]; then
    BASENAME=$(basename "$testcase_dir")
    TEST_CASE_DIRS+=("$BASENAME")
  fi
done

# If NUM_TEST_CASES is specified, limit the number of test cases
if [ "$NUM_TEST_CASES" -gt 0 ]; then
  TEST_CASE_DIRS=("${TEST_CASE_DIRS[@]:0:$NUM_TEST_CASES}")
fi

# Count actual test cases
ACTUAL_NUM_CASES=${#TEST_CASE_DIRS[@]}
print_message "$CYAN" "Found $ACTUAL_NUM_CASES test cases to verify"

# Create comma-separated list for hyperfine
TEST_CASES=$(printf ",%s" "${TEST_CASE_DIRS[@]}")
TEST_CASES=${TEST_CASES:1} # Remove leading comma

print_message "$CYAN" "📊 Running benchmarks for verification..."

# Run hyperfine for benchmarking
hyperfine --show-output --min-runs 1 --max-runs 1 \
    -L test_case $TEST_CASES \
    --export-json "$BENCHMARK_DIR/noir_verifications_benchmark.json" \
    --export-markdown "$BENCHMARK_DIR/noir_verifications_summary.md" \
    "cd $TARGET_DIR/{test_case} && bb verify -k vk -p proof -i public_inputs --oracle_hash keccak"

print_message "$GREEN" "✅ All proofs verified successfully!"

# Calculate and display aggregate statistics
echo ""
print_message "$CYAN" "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "$BENCHMARK_DIR/noir_verifications_benchmark.json" ]; then
    print_message "$RED" "Error: Benchmark results file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' "$BENCHMARK_DIR/noir_verifications_benchmark.json" 2>/dev/null); then
    print_message "$RED" "Error: Could not calculate average time"
    exit 1
fi

if ! min_time=$(jq -r '[.results[].min | select(. != null)] | min' "$BENCHMARK_DIR/noir_verifications_benchmark.json" 2>/dev/null); then
    print_message "$RED" "Error: Could not calculate minimum time"
    exit 1
fi

if ! max_time=$(jq -r '[.results[].max | select(. != null)] | max' "$BENCHMARK_DIR/noir_verifications_benchmark.json" 2>/dev/null); then
    print_message "$RED" "Error: Could not calculate maximum time"
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
' "$BENCHMARK_DIR/noir_verifications_benchmark.json" 2>/dev/null); then
    print_message "$RED" "Error: Could not calculate standard deviation"
    exit 1
fi

# Only print if we have valid numbers
if [[ "$avg_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$min_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$max_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$std_dev" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    printf "Average Time: %.3f ± %.3f seconds\n" $avg_time $std_dev
    printf "Min Time: %.3f seconds\n" $min_time
    printf "Max Time: %.3f seconds\n" $max_time
else
    print_message "$RED" "Error: Invalid numerical values in benchmark results"
    exit 1
fi

echo "----------------------------------------"