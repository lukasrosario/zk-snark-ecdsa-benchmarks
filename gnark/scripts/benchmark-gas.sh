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

# Ensure we're in the correct directory
cd /app

# Check if verifying key exists
if [ ! -f "data/verifying.key" ]; then
    print_message "$RED" "Verifying key not found. Please run compile-circuit.sh first."
    exit 1
fi

# Discover test cases
TEST_CASE_FILES=(tests/test_case_*.json)
if [ ! -e "${TEST_CASE_FILES[0]}" ]; then
    print_message "$RED" "No test case files found in tests directory!"
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
print_message "$CYAN" "🔍 Discovered $NUM_TEST_CASES test cases: ${TEST_CASE_NUMBERS[*]}"

# Check if gas benchmarking already completed
if [ -d "/out/gas-reports" ] && [ -f "/out/gas-reports/gas_benchmark_summary.json" ]; then
    COMPLETED_BENCHMARKS=$(jq -r '.results | length' "/out/gas-reports/gas_benchmark_summary.json" 2>/dev/null || echo "0")
    if [ "$COMPLETED_BENCHMARKS" -eq "$NUM_TEST_CASES" ]; then
        print_message "$GREEN" "✅ Gas benchmarking already completed, skipping gas benchmark step."
        print_message "$CYAN" "   Found gas reports for all test cases."
        print_message "$CYAN" "   To re-run gas benchmarks, delete the '/out/gas-reports' directory first."
        
        # Display existing gas benchmark results
        print_message "$CYAN" "📊 Displaying existing gas benchmark results:"
        echo ""
        echo "Gas Usage Summary"
        echo "================="
        echo ""
        
        for test_case in "${TEST_CASE_NUMBERS[@]}"; do
            if [ -f "/out/gas-reports/gas_report_${test_case}.txt" ]; then
                echo "Test Case ${test_case}:"
                cat "/out/gas-reports/gas_report_${test_case}.txt"
                echo ""
            fi
        done
        exit 0
    fi
fi

# Check if proof files exist
missing_proofs=()
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    if [ ! -f "data/proof_${test_case}.groth16" ]; then
        missing_proofs+=($test_case)
    fi
done

if [ ${#missing_proofs[@]} -gt 0 ]; then
    print_message "$RED" "Missing proof files for test cases: ${missing_proofs[*]}"
    print_message "$RED" "Please run generate-proofs.sh first."
    exit 1
fi

# Create gas benchmarking directories
mkdir -p /out/gas-reports
mkdir -p gas-bench

# Create Foundry project structure
cd gas-bench
if [ ! -f "foundry.toml" ]; then
    print_message "$CYAN" "🔨 Setting up Foundry project..."
    
    # Create basic directory structure
    mkdir -p src test lib out
    
    # Create foundry.toml
    cat > foundry.toml << 'FOUNDRY_EOF'
[profile.default]
src = "src"
out = "out" 
libs = ["lib"]
solc = "0.8.20"
remappings = ["forge-std/=lib/forge-std/src/"]
FOUNDRY_EOF

    # Install forge-std
    print_message "$CYAN" "📦 Setting up forge-std dependencies..."
    if command -v git &> /dev/null; then
        git init . 2>/dev/null || true
        forge install foundry-rs/forge-std --no-commit 2>/dev/null || {
            print_message "$CYAN" "📦 Manual forge-std setup..."
            mkdir -p lib/forge-std/src
            cat > lib/forge-std/src/Test.sol << 'TEST_EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Test {
    function assertTrue(bool condition, string memory message) public pure {
        require(condition, message);
    }
    
    function assertTrue(bool condition) public pure {
        require(condition, "Assertion failed");
    }
}
TEST_EOF
        }
    else
        mkdir -p lib/forge-std/src
        cat > lib/forge-std/src/Test.sol << 'TEST_EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Test {
    function assertTrue(bool condition, string memory message) public pure {
        require(condition, message);
    }
    
    function assertTrue(bool condition) public pure {
        require(condition, "Assertion failed");
    }
}
TEST_EOF
    fi
fi

# Ensure test directory exists
mkdir -p test

# Generate Solidity verifier from gnark verification key
print_message "$CYAN" "🔧 Generating Solidity verifier..."
go run ../cmd/generate_verifier/main.go

print_message "$CYAN" "🧪 Running gas benchmarks for $NUM_TEST_CASES test cases..."

# Initialize results array
GAS_RESULTS=()

# Create gas test contract for each test case
for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    print_message "$CYAN" "⛽ Benchmarking gas usage for test case $test_case..."
    
    # Generate test contract (simplified without forge-std dependency)
    cat > "test/GasTest${test_case}.t.sol" <<EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../src/Groth16Verifier.sol";

contract GasTest${test_case} is Test {
    Verifier verifier = new Verifier();

    function testVerifyProof${test_case}() public view {
        // >>> Go will paste fully-expanded proof, commitments, commitmentPok, input here
        PROOF_DATA_PLACEHOLDER_${test_case}

        verifier.verifyProof(proof, commitments, commitmentPok, input);
        assertTrue(true);
    }
}
EOF

    # Generate proof data and insert into contract
    print_message "$CYAN" "🔄 Generating test data for test case $test_case..."
    go run ../cmd/generate_test_data/main.go "$test_case" "../tests/test_case_${test_case}.json" "../data/proof_${test_case}.groth16"
    
    # Run gas benchmark for this test case
    print_message "$CYAN" "🧪 Running gas benchmark for test case $test_case..."
    
    print_message "$CYAN" "🔍 Building contracts..."
    if ! forge build 2>&1; then
        print_message "$RED" "Error: Failed to build contracts for test case $test_case"
        continue
    fi
    
    print_message "$CYAN" "🚀 Running forge test for test case $test_case..."
    # Run the test and capture gas usage with timeout
    if timeout 60 forge test --match-test "testVerifyProof${test_case}" --gas-report > "/out/gas-reports/gas_report_${test_case}.txt" 2>&1; then
        print_message "$GREEN" "✅ Test completed for test case $test_case"
    else
        print_message "$RED" "❌ Test failed or timed out for test case $test_case"
    fi
    
    GAS_USAGE=$(grep -o "testVerifyProof${test_case}() (gas: [0-9]*)" "/out/gas-reports/gas_report_${test_case}.txt" | sed -E 's/.*\(gas: ([0-9]*)\)/\1/' | head -1 || echo "")

    if [ -z "$GAS_USAGE" ]; then
        print_message "$RED" "❌ Could not extract gas usage from test result for $BASENAME"
        exit 1
    fi
    
    print_message "$GREEN" "✅ Gas usage for test case $test_case: $GAS_USAGE"
    echo "$GAS_USAGE gas"
    
    # Store result for summary
    GAS_RESULTS+=("{\"test_case\":\"test_case_$test_case\",\"gas_used\":$GAS_USAGE}")
    
    echo "Test Case ${test_case} gas benchmark completed."
done

cd ..

print_message "$GREEN" "✅ All gas benchmarks completed!"

# Generate comprehensive gas usage summary
print_message "$CYAN" "📊 Generating gas usage summary..."

# Create JSON summary
cat > "/out/gas-reports/gas_benchmark_summary.json" << EOF
{
  "total_test_cases": $NUM_TEST_CASES,
  "timestamp": "$(date -u --iso-8601=seconds)",
  "results": [
    $(IFS=','; echo "${GAS_RESULTS[*]}")
  ]
}
EOF

# Calculate statistics
if [ ${#GAS_RESULTS[@]} -gt 0 ]; then
    avg_gas=$(jq -r '[.results[].gas_used] | add / length' "/out/gas-reports/gas_benchmark_summary.json")
    min_gas=$(jq -r '[.results[].gas_used] | min' "/out/gas-reports/gas_benchmark_summary.json")
    max_gas=$(jq -r '[.results[].gas_used] | max' "/out/gas-reports/gas_benchmark_summary.json")
    std_dev=$(jq -r '
        .results | 
        map(.gas_used) | 
        (add / length) as $mean |
        map(($mean - .) * ($mean - .)) |
        (add / length) | 
        sqrt
    ' "/out/gas-reports/gas_benchmark_summary.json")
    
    # Update summary with statistics
    jq ". + {\"average_gas_used\": $avg_gas, \"min_gas_used\": $min_gas, \"max_gas_used\": $max_gas, \"std_dev_gas_used\": $std_dev}" "/out/gas-reports/gas_benchmark_summary.json" > "/out/gas-reports/gas_benchmark_summary.json.tmp" && mv "/out/gas-reports/gas_benchmark_summary.json.tmp" "/out/gas-reports/gas_benchmark_summary.json"
fi

# Display summary
print_message "$CYAN" "📊 Displaying gas benchmark results:"
echo ""
echo "Gas Usage Summary"
echo "================="
echo ""

for test_case in "${TEST_CASE_NUMBERS[@]}"; do
    echo "Test Case ${test_case}:"
    cat "/out/gas-reports/gas_report_${test_case}.txt"
    echo ""
done

if [ ${#GAS_RESULTS[@]} -gt 0 ]; then
    print_message "$CYAN" "📈 Gas Usage Statistics:"
    echo "========================================"
    printf "Average Gas: %.0f ± %.0f gas\n" $avg_gas $std_dev
    printf "Min Gas: %.0f gas\n" $min_gas
    printf "Max Gas: %.0f gas\n" $max_gas
    echo "========================================"
fi 