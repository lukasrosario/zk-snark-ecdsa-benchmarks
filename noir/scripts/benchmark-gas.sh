#!/bin/bash

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Check for required commands
check_command() {
  local cmd=$1
  if ! command -v $cmd &> /dev/null; then
    print_message "$RED" "❌ Error: $cmd command not found"
    print_message "$CYAN" "Please install $cmd to continue"
    exit 1
  fi
}

# Check for required commands
check_command "od"
check_command "jq"
check_command "forge"

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
  exit 1
fi

print_message "$CYAN" "⛽ Starting gas usage benchmarking for Noir ECDSA proofs..."

# Create persistent output directories
mkdir -p /out/gas
mkdir -p /out/contracts
mkdir -p /out/test-contracts

# Circuit file path
CIRCUIT_FILE="/out/compilation/benchmarking.json"

# Check if circuit file exists
if [ ! -f "$CIRCUIT_FILE" ]; then
  print_message "$RED" "❌ Circuit file not found: $CIRCUIT_FILE"
  print_message "$RED" "   Please run the compilation step first."
  exit 1
fi

# Count total proof directories
TOTAL_PROOFS=$(find /out/proofs -name "test_case_*" -type d | wc -l)
if [ "$TOTAL_PROOFS" -eq 0 ]; then
    print_message "$RED" "❌ No proof directories found in /out/proofs"
    print_message "$RED" "   Please run the proof generation step first."
    exit 1
fi

print_message "$CYAN" "📊 Found $TOTAL_PROOFS test cases to benchmark"

# Check if gas benchmarking has already been completed
GAS_SUMMARY="/out/gas/gas_benchmark_summary.json"
if [ -f "$GAS_SUMMARY" ]; then
    COMPLETED_BENCHMARKS=$(jq -r '.results | length' "$GAS_SUMMARY" 2>/dev/null || echo "0")
    if [ "$COMPLETED_BENCHMARKS" -eq "$TOTAL_PROOFS" ]; then
        print_message "$GREEN" "✅ Gas benchmarking already completed, skipping gas benchmark step."
        print_message "$GREEN" "   Found: $GAS_SUMMARY with $COMPLETED_BENCHMARKS results"
        print_message "$GREEN" "   To re-benchmark, delete the '/out/gas' directory first."
        exit 0
    fi
fi

# Generate Solidity verifier (only if not already exists)
VERIFIER_FILE="/out/contracts/NoirVerifier.sol"
if [ ! -f "$VERIFIER_FILE" ]; then
    print_message "$CYAN" "🔨 Generating Solidity verifier..."
    
    # Generate the verification key with keccak hash for EVM compatibility
    bb write_vk -b "$CIRCUIT_FILE" -o "/out/contracts" --oracle_hash keccak
    
    # Generate the Solidity verifier from the verification key
    bb write_solidity_verifier -k "/out/contracts/vk" -o "/out/contracts/Verifier.sol"
    
    # Rename for clarity
    mv "/out/contracts/Verifier.sol" "$VERIFIER_FILE"
    
    print_message "$GREEN" "✅ Solidity verifier generated at $VERIFIER_FILE"
else
    print_message "$GREEN" "✅ Solidity verifier already exists, skipping generation."
fi

# Set up Foundry project (only if not already exists)
FOUNDRY_PROJECT="/out/gas/gas-benchmark"
if [ ! -d "$FOUNDRY_PROJECT" ]; then
    print_message "$CYAN" "📁 Creating Foundry project directory..."
    mkdir -p "$FOUNDRY_PROJECT"
    cd "$FOUNDRY_PROJECT"
    
    print_message "$CYAN" "🔧 Setting up Foundry..."
    forge init --no-git
    
    # Create foundry.toml to specify solc version that's compatible with the generated verifier
    print_message "$CYAN" "📝 Creating foundry.toml with compatible solc version..."
    cat > foundry.toml << EOF
[profile.default]
solc = "0.8.29"
EOF

    # Copy the verifier
    cp "$VERIFIER_FILE" src/NoirVerifier.sol
    
    print_message "$CYAN" "📝 Creating test contract..."
    cat > src/GasTest.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./NoirVerifier.sol";

contract GasTest {
    HonkVerifier verifier;

    constructor() {
        verifier = new HonkVerifier();
    }

    function verifyProof(bytes calldata _proof, bytes32[] calldata _publicInputs) public view returns (bool) {
        return verifier.verify(_proof, _publicInputs);
    }
}
EOF

    # Copy the GasTest contract to the persistent output directory
    print_message "$CYAN" "💾 Saving GasTest contract to /out/test-contracts/GasTest.sol"
    cp src/GasTest.sol "/out/test-contracts/GasTest.sol"

    forge build
    print_message "$GREEN" "✅ Foundry project set up successfully!"
else
    print_message "$GREEN" "✅ Foundry project already exists, skipping setup."
    cd "$FOUNDRY_PROJECT"
fi

print_message "$CYAN" "🧪 Running gas benchmarks for $TOTAL_PROOFS test cases..."

# Create gas reports directory
mkdir -p ./gas-reports

# Initialize JSON summary
cat > ./gas-reports/all_gas_data.json << EOF
{
  "results": []
}
EOF

CURRENT_TEST=0
GAS_RESULTS=()

# Process each proof directory
for proof_dir in /out/proofs/test_case_*; do
  if [ -d "$proof_dir" ]; then
    CURRENT_TEST=$((CURRENT_TEST + 1))
    BASENAME=$(basename "$proof_dir")
    TEST_NUMBER=${BASENAME#test_case_}
    
    print_message "$CYAN" "📊 [$CURRENT_TEST/$TOTAL_PROOFS] Benchmarking gas for $BASENAME..."
    
    PROOF_FILE="$proof_dir/proof"
    PROOF_FIELDS_FILE="$proof_dir/proof_fields.json"
    PUBLIC_INPUTS_FILE="$proof_dir/public_inputs_fields.json"
    
    # Check if required files exist
    if [ ! -f "$PROOF_FILE" ] || [ ! -f "$PROOF_FIELDS_FILE" ]; then
        print_message "$RED" "❌ Missing files for $BASENAME"
        print_message "$RED" "   Expected: $PROOF_FILE and $PROOF_FIELDS_FILE"
        exit 1
    fi
    
    # Format the proof for Solidity verification
    print_message "$CYAN" "   Formatting proof as hex string..."
    PROOF_HEX=$(echo -n "0x"; xxd -p "$PROOF_FILE" | tr -d '\n')
    
    # Get the public inputs as an array of hex values
    PUBLIC_INPUTS_COUNT=$(jq -r '. | length' "$PUBLIC_INPUTS_FILE")
    print_message "$CYAN" "   Found $PUBLIC_INPUTS_COUNT public inputs"

    # Extract all public input values dynamically
    PUBLIC_INPUTS_ARRAY=()
    for ((i=0; i<PUBLIC_INPUTS_COUNT; i++)); do
        PUBLIC_INPUT_VALUE=$(jq -r ".[$i]" "$PUBLIC_INPUTS_FILE")
        PUBLIC_INPUTS_ARRAY+=("$PUBLIC_INPUT_VALUE")
    done
    
    # Create a test file for this specific test case
    cat > test/GasTest.t.sol << EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/GasTest.sol";

contract GasTestTest is Test {
    GasTest gasTest;
    
    function setUp() public {
        gasTest = new GasTest();
    }
    
    function testVerifyProof${TEST_NUMBER}() public view {
        bytes memory proof = hex"${PROOF_HEX:2}";
        
        // Dynamic public inputs array with ${PUBLIC_INPUTS_COUNT} elements
        bytes32[] memory publicInputs = new bytes32[](${PUBLIC_INPUTS_COUNT});
$(for ((i=0; i<PUBLIC_INPUTS_COUNT; i++)); do
    echo "        publicInputs[$i] = bytes32(uint256(${PUBLIC_INPUTS_ARRAY[$i]}));"
done)
        
        gasTest.verifyProof(proof, publicInputs);
    }
}
EOF

    # Copy the test contract to the persistent output directory
    print_message "$CYAN" "   💾 Saving test contract to /out/test-contracts/${BASENAME}_Test.sol"
    cp test/GasTest.t.sol "/out/test-contracts/${BASENAME}_Test.sol"

    print_message "$CYAN" "   ⛽ Running gas report..."
    # Run the test and capture the gas report
    forge test --match-test testVerifyProof${TEST_NUMBER} --gas-report > ./gas-reports/${BASENAME}_gas_report.txt
    
    # Extract the gas usage from the report
    GAS_USAGE=$(grep -o "testVerifyProof${TEST_NUMBER}() (gas: [0-9]*)" ./gas-reports/${BASENAME}_gas_report.txt | sed -E 's/.*\(gas: ([0-9]*)\)/\1/')
    
    if [ -z "$GAS_USAGE" ]; then
        print_message "$RED" "❌ Could not extract gas usage from test result for $BASENAME"
        exit 1
    fi
    
    print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_PROOFS] Gas usage for $BASENAME: $GAS_USAGE gas"
    
    # Store result for summary
    GAS_RESULTS+=("{\"test_case\":\"$BASENAME\",\"gas_used\":$GAS_USAGE}")
  fi
done

# Generate gas usage summary
print_message "$CYAN" "📊 Generating gas usage summary..."

# Create JSON summary
cat > "$GAS_SUMMARY" << EOF
{
  "total_test_cases": $TOTAL_PROOFS,
  "timestamp": "$(date -u --iso-8601=seconds)",
  "results": [
    $(IFS=','; echo "${GAS_RESULTS[*]}")
  ]
}
EOF

# Calculate and display aggregate statistics
if [ ${#GAS_RESULTS[@]} -gt 0 ]; then
    print_message "$CYAN" "📈 Calculating aggregate statistics..."
    
    # Calculate average, min, max gas usage
    avg_gas=$(jq -r '[.results[].gas_used] | add / length' "$GAS_SUMMARY")
    min_gas=$(jq -r '[.results[].gas_used] | min' "$GAS_SUMMARY")
    max_gas=$(jq -r '[.results[].gas_used] | max' "$GAS_SUMMARY")
    std_dev=$(jq -r '
        .results | 
        map(.gas_used) | 
        (add / length) as $mean |
        map(($mean - .) * ($mean - .)) |
        (add / length) | 
        sqrt
    ' "$GAS_SUMMARY")
    
    # Update the summary with statistics
    jq ". + {\"average_gas_used\": $avg_gas, \"min_gas_used\": $min_gas, \"max_gas_used\": $max_gas, \"std_dev_gas_used\": $std_dev}" "$GAS_SUMMARY" > "$GAS_SUMMARY.tmp" && mv "$GAS_SUMMARY.tmp" "$GAS_SUMMARY"
    
    # Create text report
    cat > "/out/gas/gas_benchmark_report.txt" << EOF
Noir ECDSA Gas Usage Benchmark Report
=====================================

Total Test Cases: $TOTAL_PROOFS
All Tests: Successful

Gas Usage Statistics:
  Average: $(printf "%.0f" $avg_gas) gas
  Minimum: $(printf "%.0f" $min_gas) gas  
  Maximum: $(printf "%.0f" $max_gas) gas
  Std Dev: $(printf "%.0f" $std_dev) gas

Generated at: $(date -u --iso-8601=seconds)
EOF

    print_message "$GREEN" "✅ Gas benchmarking completed successfully!"
    print_message "$GREEN" "📁 Gas usage results: /out/gas/"
    print_message "$CYAN" "📈 Gas Usage Statistics:"
    echo "========================================"
    printf "Average Gas: %.0f ± %.0f gas\n" $avg_gas $std_dev
    printf "Min Gas: %.0f gas\n" $min_gas
    printf "Max Gas: %.0f gas\n" $max_gas
    echo "========================================"
else
    print_message "$RED" "❌ No gas usage results to summarize"
    exit 1
fi
