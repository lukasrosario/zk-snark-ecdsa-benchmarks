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

# Source Barretenberg environment if it exists
if [ -f "$HOME/.bb/env" ]; then
  print_message "$CYAN" "Sourcing Barretenberg environment"
  source "$HOME/.bb/env"
fi

# Check if bb is available
if ! command -v bb &> /dev/null; then
  print_message "$RED" "❌ Error: bb command not found"
  print_message "$CYAN" "Make sure Barretenberg (bb) is installed and in your PATH"
  print_message "$CYAN" "You can install it with: curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash"
  print_message "$CYAN" "Then source the environment: source ~/.bb/env"
  print_message "$CYAN" "Current PATH: $PATH"
  exit 1
fi

print_message "$CYAN" "🔐 Starting proof generation for Noir ECDSA test cases..."

# Create persistent output directories
mkdir -p /out/proofs
mkdir -p /out/benchmarks

# Circuit file path
CIRCUIT_FILE="/out/compilation/benchmarking.json"

# Check if circuit file exists
if [ ! -f "$CIRCUIT_FILE" ]; then
    print_message "$RED" "❌ Circuit file not found: $CIRCUIT_FILE"
    print_message "$RED" "   Please run the compilation step first."
    exit 1
fi

# Discover test cases from witnesses directory
WITNESS_DIRS=(/out/witnesses/test_case_*)
if [ ! -d "${WITNESS_DIRS[0]}" ]; then
    print_message "$RED" "❌ No witness directories found in /out/witnesses"
    print_message "$RED" "   Please run the witness generation step first."
    exit 1
fi

TOTAL_WITNESSES=$(ls -1q /out/witnesses/test_case_* | wc -l)
print_message "$CYAN" "📊 Found $TOTAL_WITNESSES test cases to process"

TEST_CASE_NUMBERS=()
for testcase_dir in /out/witnesses/test_case_*; do
  if [ -d "$testcase_dir" ]; then
    BASENAME=$(basename "$testcase_dir")
    TEST_CASE_NUMBERS+=("${BASENAME#test_case_}")
  fi
done

# Create proof generation script for hyperfine
cat > /tmp/generate_single_proof.sh << 'EOF'
#!/bin/bash
set -e

TEST_CASE=$1
CIRCUIT_FILE="/out/compilation/benchmarking.json"
WITNESS_FILE="/out/witnesses/test_case_${TEST_CASE}/test_case_${TEST_CASE}_witness.gz"
PROOF_DIR="/out/proofs/test_case_${TEST_CASE}"

# Create proof directory
mkdir -p "$PROOF_DIR"

# Change to the proof directory for output
cd "$PROOF_DIR"

# Generate proof with keccak hash and bytes_and_fields format for EVM compatibility
bb prove -b "$CIRCUIT_FILE" -w "$WITNESS_FILE" -o ./ --oracle_hash keccak --output_format bytes_and_fields > /dev/null 2>&1

# Generate verification key with keccak hash for EVM compatibility
bb write_vk -b "$CIRCUIT_FILE" -o ./ --oracle_hash keccak > /dev/null 2>&1

echo "✓ Proof generated for test case $TEST_CASE"
EOF

chmod +x /tmp/generate_single_proof.sh

# Generate proofs with hyperfine benchmark
print_message "$CYAN" "🔄 Generating proofs..."
TEST_CASES_LIST=$(printf "%s," "${TEST_CASE_NUMBERS[@]}" | sed 's/,$//')

hyperfine --warmup 1 --min-runs 1 --max-runs 1 \
    -L test_case $TEST_CASES_LIST \
    --show-output \
    --export-json /out/benchmarks/all_proofs_benchmark.json \
    --export-markdown /out/benchmarks/proofs_summary.md \
    '/tmp/generate_single_proof.sh {test_case}'

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
print_message "$GREEN" "📁 Proof artifacts: /out/proofs/"
