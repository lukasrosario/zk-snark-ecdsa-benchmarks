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

print_message "$CYAN" "🔨 Starting Noir circuit compilation and witness generation..."

if ! command -v nargo &> /dev/null; then
  print_message "$RED" "❌ nargo could not be found. Please install Noir and nargo first."
  exit 1
fi

# Get the absolute path to the noir project directory (where Nargo.toml is located)
NOIR_DIR="$(dirname "$0")/.."
NOIR_DIR="$(cd "$NOIR_DIR" && pwd)"
TESTS_DIR="$NOIR_DIR/tests"

# Create persistent output directories
mkdir -p /out/compilation
mkdir -p /out/witnesses

# Change to the Noir project directory where Nargo.toml is located
cd "$NOIR_DIR"

print_message "$CYAN" "Working in directory: $(pwd)"
print_message "$CYAN" "Checking for Nargo.toml: $(ls -la Nargo.toml)"

# Step 1: Compile the circuit
print_message "$CYAN" "📝 Compiling the Noir circuit..."

# Check if circuit is already compiled
if [ -f "/out/compilation/benchmarking.json" ] && [ -f "target/benchmarking.json" ]; then
    print_message "$GREEN" "✅ Circuit already compiled, skipping compilation step."
    print_message "$GREEN" "   Found: /out/compilation/benchmarking.json"
    print_message "$GREEN" "   To recompile, delete the '/out/compilation' directory first."
else
    # Compile the circuit
    nargo compile || {
      print_message "$RED" "❌ Failed to compile Noir circuit";
      exit 1;
    }
    
    # Copy compiled circuit to persistent location
    cp target/benchmarking.json /out/compilation/
    print_message "$GREEN" "✅ Circuit compiled and saved to /out/compilation/benchmarking.json"
fi

# Step 2: Generate witnesses for all test cases
print_message "$CYAN" "🧮 Generating witnesses for test cases..."

# Count total test cases
TOTAL_TESTS=$(find "$TESTS_DIR" -name "test_case_*.toml" | wc -l)
if [ "$TOTAL_TESTS" -eq 0 ]; then
    print_message "$RED" "❌ No test cases found in $TESTS_DIR"
    print_message "$RED" "   Please generate test cases first using: bun run tests:generate"
    exit 1
fi

print_message "$CYAN" "📊 Found $TOTAL_TESTS test cases to process"

CURRENT_TEST=0
# Process each test case
for testcase in "$TESTS_DIR"/test_case_*.toml; do
  if [ -f "$testcase" ]; then
    CURRENT_TEST=$((CURRENT_TEST + 1))
    BASENAME=$(basename "$testcase" .toml)
    
    # Create directory for this testcase
    TESTCASE_DIR="/out/witnesses/${BASENAME}"
    WITNESS_FILE="$TESTCASE_DIR/${BASENAME}_witness.gz"
    
    # Check if witness already exists
    if [ -f "$WITNESS_FILE" ]; then
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_TESTS] Witness for $BASENAME already exists, skipping."
        print_message "$GREEN" "   Found: $WITNESS_FILE"
        continue
    fi
    
    print_message "$CYAN" "🧮 [$CURRENT_TEST/$TOTAL_TESTS] Computing witness for $BASENAME..."
    
    # Create directory for this testcase
    if [ -d "$TESTCASE_DIR" ]; then
      print_message "$CYAN" "📂 Removing existing directory for $BASENAME..."
      rm -rf "$TESTCASE_DIR"
    fi
    mkdir -p "$TESTCASE_DIR"
    
    # Execute the Noir program, generating the witness
    nargo execute -p "$testcase" "${BASENAME}_witness" || {
      print_message "$RED" "❌ Failed to compute witness for $BASENAME";
      exit 1;
    }
    
    # Move the witness file to the persistent testcase directory
    mv "target/${BASENAME}_witness.gz" "$TESTCASE_DIR/" || {
      print_message "$RED" "❌ Failed to move witness file for $BASENAME";
      exit 1;
    }
    
    print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_TESTS] Witness for $BASENAME written to $WITNESS_FILE"
  fi
done

print_message "$GREEN" "✅ Circuit compilation and witness generation completed successfully!"
print_message "$GREEN" "📁 Circuit artifacts: /out/compilation/"
print_message "$GREEN" "📁 Witness artifacts: /out/witnesses/" 