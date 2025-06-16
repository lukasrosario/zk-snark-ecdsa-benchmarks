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

# Circuit file path
CIRCUIT_FILE="/out/compilation/benchmarking.json"

# Check if circuit file exists
if [ ! -f "$CIRCUIT_FILE" ]; then
  print_message "$RED" "❌ Circuit file not found: $CIRCUIT_FILE"
  print_message "$RED" "   Please run the compilation step first."
  exit 1
fi

# Count total test cases
TOTAL_WITNESSES=$(find /out/witnesses -name "test_case_*" -type d | wc -l)
if [ "$TOTAL_WITNESSES" -eq 0 ]; then
    print_message "$RED" "❌ No witness directories found in /out/witnesses"
    print_message "$RED" "   Please run the witness generation step first."
    exit 1
fi

print_message "$CYAN" "📊 Found $TOTAL_WITNESSES test cases to process"

CURRENT_TEST=0
# Find all testcase directories in persistent storage
for testcase_dir in /out/witnesses/test_case_*; do
  if [ -d "$testcase_dir" ]; then
    CURRENT_TEST=$((CURRENT_TEST + 1))
    BASENAME=$(basename "$testcase_dir")
    
    # Create proof output directory
    PROOF_DIR="/out/proofs/${BASENAME}"
    PROOF_FILE="$PROOF_DIR/proof"
    PROOF_FIELDS_FILE="$PROOF_DIR/proof_fields.json"
    VK_FILE="$PROOF_DIR/vk"
    
    # Check if proof already exists
    if [ -f "$PROOF_FILE" ] && [ -f "$PROOF_FIELDS_FILE" ] && [ -f "$VK_FILE" ]; then
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_WITNESSES] Proof for $BASENAME already exists, skipping."
        print_message "$GREEN" "   Found: $PROOF_FILE, $PROOF_FIELDS_FILE, $VK_FILE"
        continue
    fi
    
    print_message "$CYAN" "🔐 [$CURRENT_TEST/$TOTAL_WITNESSES] Generating proof for $BASENAME..."
    
    # Create proof directory
    mkdir -p "$PROOF_DIR"
    
    # Get the witness file name (should be the only .gz file in the directory)
    WITNESS_FILE=$(find "$testcase_dir" -name "*.gz" -type f)
    if [ -z "$WITNESS_FILE" ]; then
      print_message "$RED" "❌ No witness file found in $testcase_dir"
      exit 1
    fi

    # Change to the proof directory for output
    cd "$PROOF_DIR"
    
    # Generate proof with keccak hash and bytes_and_fields format for EVM compatibility
    if [ ! -f "$PROOF_FILE" ] || [ ! -f "$PROOF_FIELDS_FILE" ]; then
        bb prove -b "$CIRCUIT_FILE" -w "$WITNESS_FILE" -o ./ --oracle_hash keccak --output_format bytes_and_fields || {
          print_message "$RED" "❌ Failed to generate proof for $BASENAME"
          exit 1
        }
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_WITNESSES] Proof for $BASENAME written to $PROOF_FILE"
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_WITNESSES] Proof fields for $BASENAME written to $PROOF_FIELDS_FILE"
    fi
    
    # Generate verification key with keccak hash for EVM compatibility
    if [ ! -f "$VK_FILE" ]; then
        bb write_vk -b "$CIRCUIT_FILE" -o ./ --oracle_hash keccak || {
          print_message "$RED" "❌ Failed to generate verification key for $BASENAME"
          exit 1
        }
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_WITNESSES] Verification key for $BASENAME written to $VK_FILE"
    fi
    
    # Return to root directory
    cd /app
  fi
done

# --- BENCHMARKING ---
print_message "$CYAN" "📊 Benchmarking proof generation time..."

# Discover test cases for benchmarking
TEST_CASE_DIRS=($(find /out/witnesses -name "test_case_*" -type d | sort))
COMMANDS=()
for testcase_dir in "${TEST_CASE_DIRS[@]}"; do
    BASENAME=$(basename "$testcase_dir")
    PROOF_DIR="/out/proofs/${BASENAME}"
    CIRCUIT_FILE="/out/compilation/benchmarking.json"
    WITNESS_FILE=$(find "$testcase_dir" -name "*.gz" -type f)
    
    # Construct the command for hyperfine
    COMMANDS+=("cd ${PROOF_DIR} && bb prove -b ${CIRCUIT_FILE} -w ${WITNESS_FILE} -o ./ --oracle_hash keccak --output_format bytes_and_fields > /dev/null 2>&1")
done

# Run hyperfine with a single run per command
hyperfine --min-runs 1 --max-runs 1 \
    --show-output \
    --export-json "/out/proofs/proof_generation_benchmark.json" \
    --export-markdown "/out/proofs/proof_generation_summary.md" \
    --command-name "generate_proof" \
    "${COMMANDS[@]}"

# --- SUMMARY ---
print_message "$GREEN" "✅ All proofs and verification keys generated successfully!"
print_message "$GREEN" "📁 Proof artifacts: /out/proofs/"

if [ -f "/out/proofs/proof_generation_summary.md" ]; then
    print_message "$CYAN" "📊 Displaying benchmark results:"
    cat "/out/proofs/proof_generation_summary.md"
fi

if [ -f "/out/proofs/proof_generation_benchmark.json" ]; then
    print_message "$CYAN" "📈 Aggregate Statistics:"
    print_message "$CYAN" "----------------------------------------"
    
    avg_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/proofs/proof_generation_benchmark.json 2>/dev/null)
    min_time=$(jq -r '[.results[].min | select(. != null)] | min' /out/proofs/proof_generation_benchmark.json 2>/dev/null)
    max_time=$(jq -r '[.results[].max | select(. != null)] | max' /out/proofs/proof_generation_benchmark.json 2>/dev/null)
    
    std_dev=$(jq -r '
        .results | 
        map(.mean) | 
        (add / length) as $mean |
        map(($mean - .) * ($mean - .)) |
        (add / length) | 
        sqrt
    ' /out/proofs/proof_generation_benchmark.json 2>/dev/null)
    
    if [[ "$avg_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        printf "Average Time: %.3f ± %.3f seconds\n" "$avg_time" "$std_dev"
        printf "Min Time: %.3f seconds\n" "$min_time"
        printf "Max Time: %.3f seconds\n" "$max_time"
    fi
    
    print_message "$CYAN" "----------------------------------------"
fi