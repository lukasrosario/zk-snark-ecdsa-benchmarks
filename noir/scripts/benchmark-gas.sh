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
    print_message "$RED" "Error: $cmd command not found"
    print_message "$CYAN" "Please install $cmd to continue"
    exit 1
  fi
}

# Check for required commands
check_command "od"
check_command "jq"

# Default number of test cases
NUM_TEST_CASES=${NUM_TEST_CASES:-1}

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

# Get the package name from Nargo.toml
NOIR_DIR="$(dirname "$0")/.."
NOIR_DIR="$(cd "$NOIR_DIR" && pwd)"
TARGET_DIR="$NOIR_DIR/target"
TESTS_DIR="$NOIR_DIR/tests"
NARGO_TOML_PACKAGE_NAME=$(grep -m 1 "name" "$NOIR_DIR/Nargo.toml" | cut -d '"' -f 2)

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Create contract directory if it doesn't exist
CONTRACT_DIR="$NOIR_DIR/contract"
mkdir -p "$CONTRACT_DIR"

print_message "$CYAN" "🔨 Generating Solidity verifier..."
# First make sure the circuit is compiled
cd "$NOIR_DIR"
nargo compile

# Generate the verification key with keccak hash for EVM compatibility
bb write_vk -b "$TARGET_DIR/$NARGO_TOML_PACKAGE_NAME.json" -o "$TARGET_DIR" --oracle_hash keccak

# Generate the Solidity verifier from the verification key
bb write_solidity_verifier -k "$TARGET_DIR/vk" -o "$TARGET_DIR/Verifier.sol"

# Ensure we're using relative paths
print_message "$CYAN" "📁 Creating Foundry project directory..."
mkdir -p gas-benchmark
cd gas-benchmark

print_message "$CYAN" "🔧 Setting up Foundry..."
forge init --no-git

# Create foundry.toml to specify solc version that's compatible with the generated verifier
print_message "$CYAN" "📝 Creating foundry.toml with compatible solc version..."
cat > foundry.toml << EOF
[profile.default]
solc = "0.8.29"
EOF

# Copy and rename the verifier to match the contract name
cp ../target/Verifier.sol src/NoirVerifier.sol

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

forge build

print_message "$CYAN" "🧪 Running gas benchmarks for $NUM_TEST_CASES test cases..."

# Create a directory for gas reports
mkdir -p ./gas-reports

# Create a summary file for all gas reports
echo "Gas Usage Summary" > ./gas-reports/summary.txt
echo "=================" >> ./gas-reports/summary.txt
echo "" >> ./gas-reports/summary.txt

# Create a JSON file to store all gas data for statistics
echo "{" > ./gas-reports/all_gas_data.json
echo "  \"results\": [" >> ./gas-reports/all_gas_data.json

# Run gas report for each test case
for i in $(seq 1 $NUM_TEST_CASES); do
    print_message "$CYAN" "📊 Preparing test data for test case $i..."
    
    # Get the test case directory path
    TEST_CASE_DIR="$TARGET_DIR/test_case_${i}"
    
    # Check if the directory exists
    if [ ! -d "$TEST_CASE_DIR" ]; then
        print_message "$YELLOW" "Error: Test case directory not found at $TEST_CASE_DIR"
        exit 1
    fi
  
    # Format the proof for Solidity verification
    # Note: Proofs should be generated with the --output_format bytes_and_fields flag
    # Example: bb prove -b ./target/<circuit-name>.json -w ./target/<witness-name> -o ./target --oracle_hash keccak --output_format bytes_and_fields
    print_message "$CYAN" "Formatting proof as hex string..."
    PROOF_HEX=$(echo -n "0x"; xxd -p "$TEST_CASE_DIR/proof" | tr -d '\n')
    
    # Read public inputs from proof_fields.json
    # This file is created when using --output_format bytes_and_fields with bb prove
    print_message "$CYAN" "Reading public inputs from JSON file..."
    
    # Check for both potential filenames - bb may create public_inputs_fields.json or proof_fields.json
    if [ -f "$TEST_CASE_DIR/public_inputs_fields.json" ]; then
        PROOF_FIELDS_FILE="$TEST_CASE_DIR/public_inputs_fields.json"
    elif [ -f "$TEST_CASE_DIR/proof_fields.json" ]; then
        PROOF_FIELDS_FILE="$TEST_CASE_DIR/proof_fields.json"
    else
        print_message "$YELLOW" "Error: Public inputs file not found at $TEST_CASE_DIR/public_inputs_fields.json or $TEST_CASE_DIR/proof_fields.json"
        print_message "$CYAN" "Make sure proofs are generated with: bb prove -b ./target/<circuit-name>.json -w ./target/<witness-name> -o ./target --oracle_hash keccak --output_format bytes_and_fields"
        exit 1
    fi
    
    # Get the public inputs as an array of hex values - the fields json file contains a direct array
    PUBLIC_INPUTS=$(jq -r '. | join(",")' "$PROOF_FIELDS_FILE")
    
    print_message "$CYAN" "Creating Solidity test with data from public inputs file"
    
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
    
    function testVerifyProof${i}() public view {
        bytes memory proof = hex"${PROOF_HEX:2}";
        bytes32[] memory publicInputs = new bytes32[]($(jq '. | length' "$PROOF_FIELDS_FILE"));
        
        // Set all public inputs from the JSON file
EOF
    
    # Add each public input separately
    jq -r 'to_entries | .[] | "        publicInputs[" + (.key | tostring) + "] = bytes32(" + .value + ");  // Public input " + (.key | tostring)' "$PROOF_FIELDS_FILE" >> test/GasTest.t.sol
    
    # Finish the test file
    cat >> test/GasTest.t.sol << EOF
        
        gasTest.verifyProof(proof, publicInputs);
    }
}
EOF
    # cat test/GasTest.t.sol

    print_message "$CYAN" "⛽ Running gas report for test case $i..."
    # Run the test and capture the gas report
    forge test --match-test testVerifyProof${i} --gas-report > ./gas-reports/test_case_${i}_gas_report.txt
    
    # Extract the gas usage from the report and add it to the summary
    echo "Test Case $i:" >> ./gas-reports/summary.txt
    
    # Save the full gas report to the summary file
    cat ./gas-reports/test_case_${i}_gas_report.txt >> ./gas-reports/summary.txt
    echo "" >> ./gas-reports/summary.txt
    
    # Extract the actual gas usage from the test result line
    # The format is: [PASS] testVerifyProof1() (gas: 411848)
    GAS_USAGE=$(grep -o "testVerifyProof${i}() (gas: [0-9]*)" ./gas-reports/test_case_${i}_gas_report.txt | sed -E 's/.*\(gas: ([0-9]*)\)/\1/')
    
    if [ -z "$GAS_USAGE" ]; then
        print_message "$YELLOW" "Error: Could not extract gas usage from test result for test case $i"
        exit 1
    fi
    
    # Add to JSON file
    if [ $i -eq 1 ]; then
        echo "    {" >> ./gas-reports/all_gas_data.json
    else
        echo "    ,{" >> ./gas-reports/all_gas_data.json
    fi
    echo "      \"test_case\": $i," >> ./gas-reports/all_gas_data.json
    echo "      \"mean\": $GAS_USAGE," >> ./gas-reports/all_gas_data.json
    echo "      \"min\": $GAS_USAGE," >> ./gas-reports/all_gas_data.json
    echo "      \"max\": $GAS_USAGE" >> ./gas-reports/all_gas_data.json
    echo "    }" >> ./gas-reports/all_gas_data.json
    
    # Display a concise gas report for this test case
    print_message "$GREEN" "Gas Report for Test Case $i:"
    echo "  Test Gas Usage: $GAS_USAGE gas"
    echo "----------------------------------------"
done

# Close the JSON file
echo "  ]" >> ./gas-reports/all_gas_data.json
echo "}" >> ./gas-reports/all_gas_data.json

# Move back to the original directory
cd ..

print_message "$GREEN" "✅ Gas benchmarking complete! Check the gas-benchmark/gas-reports directory for results."
print_message "$GREEN" "📊 Summary of gas usage:"
cat ./gas-benchmark/gas-reports/summary.txt

# Calculate and display aggregate statistics
echo ""
print_message "$GREEN" "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "./gas-benchmark/gas-reports/all_gas_data.json" ]; then
    print_message "$YELLOW" "Error: Gas data file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_gas=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' ./gas-benchmark/gas-reports/all_gas_data.json 2>/dev/null); then
    print_message "$YELLOW" "Error: Could not calculate average gas usage"
    exit 1
fi

if ! min_gas=$(jq -r '[.results[].min | select(. != null)] | min' ./gas-benchmark/gas-reports/all_gas_data.json 2>/dev/null); then
    print_message "$YELLOW" "Error: Could not calculate minimum gas usage"
    exit 1
fi

if ! max_gas=$(jq -r '[.results[].max | select(. != null)] | max' ./gas-benchmark/gas-reports/all_gas_data.json 2>/dev/null); then
    print_message "$YELLOW" "Error: Could not calculate maximum gas usage"
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
' ./gas-benchmark/gas-reports/all_gas_data.json 2>/dev/null); then
    print_message "$YELLOW" "Error: Could not calculate standard deviation"
    exit 1
fi

# Only print if we have valid numbers
if [[ "$avg_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$min_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$max_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$std_dev" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    printf "Average Gas: %.0f ± %.0f\n" $avg_gas $std_dev
    printf "Min Gas: %.0f\n" $min_gas
    printf "Max Gas: %.0f\n" $max_gas
else
    print_message "$YELLOW" "Error: Invalid numerical values in gas data"
    exit 1
fi

echo "----------------------------------------"
