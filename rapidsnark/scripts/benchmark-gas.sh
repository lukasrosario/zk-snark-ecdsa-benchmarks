#!/bin/bash

# Exit on error
set -e

echo "⛽ Benchmarking gas usage for all test cases..."

# Create gas benchmark output directory
mkdir -p /out/gas-reports

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

# Check if gas benchmarking has already been completed
if [ -f "/out/gas-reports/all_gas_data.json" ] && [ -f "/out/gas-reports/summary.txt" ]; then
    echo "✅ Gas benchmarking already completed, skipping gas benchmark step."
    echo "   Found gas reports for all test cases."
    echo "   To re-run gas benchmarks, delete the '/out/gas-reports' directory first."
    
    # Display existing results
    echo "📊 Displaying existing gas benchmark results:"
    if [ -f "/out/gas-reports/summary.txt" ]; then
        cat /out/gas-reports/summary.txt
    fi
    exit 0
fi

echo "🔨 Generating Solidity verifier..."
snarkjs zkey export solidityverifier /out/setup/circuit.zkey /out/gas-reports/verifier.sol

# Create a new directory for the Foundry project
echo "📁 Creating Foundry project directory..."
mkdir -p /out/gas-reports/gas-benchmark
cd /out/gas-reports/gas-benchmark

echo "🔧 Setting up Foundry..."
forge init --no-git

# Create foundry.toml to specify solc version
echo "📝 Creating foundry.toml to use solc 0.8.20..."
cat > foundry.toml << EOF
[profile.default]
solc = "0.8.20"
EOF

# Copy and rename the verifier to match the contract name
cp ../verifier.sol src/Groth16Verifier.sol

echo "📝 Creating test contract..."
cat > src/GasTest.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Groth16Verifier.sol";

contract GasTest {
    Groth16Verifier verifier;

    constructor() {
        verifier = new Groth16Verifier();
    }

    function verifyProof(uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[31] memory input) public view returns (bool) {
        return verifier.verifyProof(a, b, c, input);
    }
}
EOF

forge build

echo "🧪 Running gas benchmarks for $NUM_TEST_CASES test cases..."

# Create a summary file for all gas reports
echo "Gas Usage Summary" > ../summary.txt
echo "=================" >> ../summary.txt
echo "" >> ../summary.txt

# Create a JSON file to store all gas data for statistics
echo "{" > ../all_gas_data.json
echo "  \"results\": [" >> ../all_gas_data.json

# Run gas report for each test case
for i in "${TEST_CASE_NUMBERS[@]}"; do
    echo "📊 Generating calldata for test case $i..."
    CALLDATA=$(cd /app && snarkjs generatecall /out/verification/public_${i}.json /out/verification/proof_${i}.json)
    
    # Format the calldata as proper JSON
    FORMATTED_CALLDATA="[$CALLDATA]"
    
    # Extract values using jq
    A1=$(echo "$FORMATTED_CALLDATA" | jq -r '.[0][0]')
    A2=$(echo "$FORMATTED_CALLDATA" | jq -r '.[0][1]')
    
    B11=$(echo "$FORMATTED_CALLDATA" | jq -r '.[1][0][0]')
    B12=$(echo "$FORMATTED_CALLDATA" | jq -r '.[1][0][1]')
    B21=$(echo "$FORMATTED_CALLDATA" | jq -r '.[1][1][0]')
    B22=$(echo "$FORMATTED_CALLDATA" | jq -r '.[1][1][1]')
    
    C1=$(echo "$FORMATTED_CALLDATA" | jq -r '.[2][0]')
    C2=$(echo "$FORMATTED_CALLDATA" | jq -r '.[2][1]')
    
    # Extract input values and format them individually
    INPUT_VALUES=$(echo "$FORMATTED_CALLDATA" | jq -r '.[3][]')
    INPUT_ARRAY=""
    while IFS= read -r value; do
        if [ -z "$INPUT_ARRAY" ]; then
            INPUT_ARRAY="uint256($value)"
        else
            INPUT_ARRAY="$INPUT_ARRAY, uint256($value)"
        fi
    done <<< "$INPUT_VALUES"
    
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
        uint[2] memory a = [uint256($A1), uint256($A2)];
        uint[2][2] memory b = [[uint256($B11), uint256($B12)], [uint256($B21), uint256($B22)]];
        uint[2] memory c = [uint256($C1), uint256($C2)];
        uint[31] memory input = [$INPUT_ARRAY];
        gasTest.verifyProof(a, b, c, input);
    }
}
EOF

    echo "⛽ Running gas report for test case $i..."
    # Run the test and capture the gas report
    forge test --match-test testVerifyProof${i} --gas-report > ../test_case_${i}_gas_report.txt
    
    # Extract the gas usage from the report and add it to the summary
    echo "Test Case $i:" >> ../summary.txt
    
    # Save the full gas report to the summary file
    cat ../test_case_${i}_gas_report.txt >> ../summary.txt
    echo "" >> ../summary.txt
    
    # Extract the actual gas usage from the test result line
    # The format is: [PASS] testVerifyProof1() (gas: 411848)
    GAS_USAGE=$(grep -o "testVerifyProof${i}() (gas: [0-9]*)" ../test_case_${i}_gas_report.txt | sed -E 's/.*\(gas: ([0-9]*)\)/\1/')
    
    if [ -z "$GAS_USAGE" ]; then
        echo "Error: Could not extract gas usage from test result for test case $i"
        exit 1
    fi
    
    # Add to JSON file
    if [ "$i" = "${TEST_CASE_NUMBERS[0]}" ]; then
        echo "    {" >> ../all_gas_data.json
    else
        echo "    ,{" >> ../all_gas_data.json
    fi
    echo "      \"test_case\": $i," >> ../all_gas_data.json
    echo "      \"mean\": $GAS_USAGE," >> ../all_gas_data.json
    echo "      \"min\": $GAS_USAGE," >> ../all_gas_data.json
    echo "      \"max\": $GAS_USAGE" >> ../all_gas_data.json
    echo "    }" >> ../all_gas_data.json
    
    # Display a concise gas report for this test case
    echo "Gas Report for Test Case $i:"
    echo "  Test Gas Usage: $GAS_USAGE gas"
    echo "----------------------------------------"
done

# Close the JSON file
echo "  ]" >> ../all_gas_data.json
echo "}" >> ../all_gas_data.json

# Move back to the original directory
cd /app

echo "✅ Gas benchmarking complete! Check the /out/gas-reports directory for results."
echo "📊 Summary of gas usage:"
cat /out/gas-reports/summary.txt

# Calculate and display aggregate statistics
echo ""
echo "📈 Aggregate Statistics:"
echo "----------------------------------------"

# Check if the JSON file exists and is valid
if [ ! -f "/out/gas-reports/all_gas_data.json" ]; then
    echo "Error: Gas data file not found"
    exit 1
fi

# Calculate statistics with error handling
if ! avg_gas=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' /out/gas-reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate average gas usage"
    exit 1
fi

if ! min_gas=$(jq -r '[.results[].min | select(. != null)] | min' /out/gas-reports/all_gas_data.json 2>/dev/null); then
    echo "Error: Could not calculate minimum gas usage"
    exit 1
fi

if ! max_gas=$(jq -r '[.results[].max | select(. != null)] | max' /out/gas-reports/all_gas_data.json 2>/dev/null); then
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
' /out/gas-reports/all_gas_data.json 2>/dev/null); then
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