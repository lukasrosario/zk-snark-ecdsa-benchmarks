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

print_message "$CYAN" "⛽ Benchmarking gas usage for all test cases..."

# Create the main gas benchmarking directory and cd into it
mkdir -p /out/gas-reports/foundry
cd /out/gas-reports/foundry

# Discover test cases from tests directory
TEST_CASE_FILES=(/app/tests/test_case_*.json)
if [ ! -e "${TEST_CASE_FILES[0]}" ]; then
    echo "❌ No test case files found in /app/tests directory!"
    echo "   Expected files like: test_case_1.json, test_case_2.json, etc."
    exit 1
fi

# Extract test case numbers and sort them
TEST_CASE_NUMBERS=()
for file in "${TEST_CASE_FILES[@]}"; do
    if [[ $file =~ test_case_([0-9]+)\.json ]]; then
        TEST_CASE_NUMBERS+=(${BASH_REMATCH[1]})
    fi
done

# Sort the test case numbers
IFS=$'\n' TEST_CASE_NUMBERS=($(sort -n <<<"${TEST_CASE_NUMBERS[*]}"))
unset IFS

NUM_TEST_CASES=${#TEST_CASE_NUMBERS[@]}
echo "🔍 Discovered $NUM_TEST_CASES test cases: ${TEST_CASE_NUMBERS[*]}"

echo "🔧 Setting up Foundry..."
forge init --no-git

echo "🔨 Generating Solidity verifier..."
# Run the Go command from the /app directory where go.mod is located
# The generate_verifier command creates the file directly, so no redirection needed
(cd /app && go run cmd/generate_verifier/main.go > /dev/null 2>&1)

# Copy the generated verifier to the Foundry src directory
cp /app/src/Groth16Verifier.sol src/

# Create foundry.toml to specify solc version
echo "📝 Creating foundry.toml to use solc 0.8.20..."
cat > foundry.toml << EOF
[profile.default]
solc = "0.8.20"
EOF

echo "📝 Creating test contract..."
cat > src/GasTest.sol << EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Groth16Verifier.sol";

contract GasTest {
    Verifier verifier;

    constructor() {
        verifier = new Verifier();
    }

    function verifyProof(
        uint256[8] calldata proof,
        uint256[2] calldata commitments,
        uint256[2] calldata commitmentPok,
        uint256[4] calldata input
    ) public view {
        verifier.verifyProof(proof, commitments, commitmentPok, input);
    }
}
EOF

forge build

echo "🧪 Running gas benchmarks for $NUM_TEST_CASES test cases..."

# Create a directory for gas reports
mkdir -p ../reports

# Create a summary file for all gas reports
echo "Gas Usage Summary" > ../reports/summary.txt
echo "=================" >> ../reports/summary.txt
echo "" >> ../reports/summary.txt

# Create a JSON file to store all gas data for statistics
echo "{" > ../reports/all_gas_data.json
echo "  \"results\": [" >> ../reports/all_gas_data.json

# Run gas report for each test case
for idx in "${!TEST_CASE_NUMBERS[@]}"; do
    test_case=${TEST_CASE_NUMBERS[$idx]}
    print_message "$CYAN" "⛽ Benchmarking gas usage for test case $test_case..."
    
    # Generate proof data and insert into a temporary test file
    (cd /app && go run cmd/generate_test_data/main.go "$test_case" "/app/tests/test_case_${test_case}.json" "/out/proof_${test_case}.groth16" > /tmp/test_data_${test_case}.sol)
    
    # Copy the generated test file to the test directory
    cp /tmp/test_data_${test_case}.sol test/GasTest.t.sol
    
    # Run gas benchmark for this test case
    print_message "$CYAN" "🧪 Running gas benchmark for test case $test_case..."
    
    # Run the test and capture gas usage
    GAS_REPORT_FILE="../reports/gas_report_${test_case}.txt"
    forge test --match-test "testVerifyProof${test_case}" --gas-report > "$GAS_REPORT_FILE"
    
    # Extract the gas usage from the report
    GAS_USAGE=$(grep -o "testVerifyProof${test_case}() (gas: [0-9]*)" "$GAS_REPORT_FILE" | sed -E 's/.*\(gas: ([0-9]*)\)/\1/')
    
    if [ -z "$GAS_USAGE" ]; then
        echo "Error: Could not extract gas usage from test result for test case $test_case"
        exit 1
    fi
    
    print_message "$GREEN" "✅ Gas usage for test case $test_case: $GAS_USAGE gas"
    
    # Add to summary
    echo "Test Case $test_case:" >> ../reports/summary.txt
    cat "$GAS_REPORT_FILE" >> ../reports/summary.txt
    echo "" >> ../reports/summary.txt
    
    # Add to JSON file
    if [ "$test_case" = "${TEST_CASE_NUMBERS[0]}" ]; then
        echo "    {" >> ../reports/all_gas_data.json
    else
        echo "    ,{" >> ../reports/all_gas_data.json
    fi
    echo "      \"test_case\": $test_case," >> ../reports/all_gas_data.json
    echo "      \"mean\": $GAS_USAGE," >> ../reports/all_gas_data.json
    echo "      \"min\": $GAS_USAGE," >> ../reports/all_gas_data.json
    echo "      \"max\": $GAS_USAGE" >> ../reports/all_gas_data.json
    echo "    }" >> ../reports/all_gas_data.json
    
    # Display a concise gas report for this test case
    echo "Gas Report for Test Case $test_case:"
    echo "  Test Gas Usage: $GAS_USAGE gas"
    echo "----------------------------------------"
done

# Close the JSON file
echo "  ]" >> ../reports/all_gas_data.json
echo "}" >> ../reports/all_gas_data.json

echo "✅ Gas benchmarking complete! Check the /out/gas-reports directory for results."
echo "📊 Summary of gas usage:"
cat /out/gas-reports/reports/summary.txt

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "/out/gas-reports/reports/all_gas_data.json" ]; then
    echo "Error: Gas data file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_gas=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/gas-reports/reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate average gas usage"
    exit 1
fi

if ! min_gas=$(jq -r '[.results[].min | select(. != null)] | min' /out/gas-reports/reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate minimum gas usage"
    exit 1
fi

if ! max_gas=$(jq -r '[.results[].max | select(. != null)] | max' /out/gas-reports/reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate maximum gas usage"
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
' /out/gas-reports/reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate standard deviation"
    exit 1
fi

# Only print if we have valid numbers
if [[ "$avg_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$min_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$max_gas" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$std_dev" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    printf "Average Gas: %.0f ± %.0f\n" $avg_gas $std_dev
    printf "Min Gas: %.0f\n" $min_gas
    printf "Max Gas: %.0f\n" $max_gas
else
    echo "Error: Invalid numerical values in gas data"
    exit 1
fi

echo "----------------------------------------" 