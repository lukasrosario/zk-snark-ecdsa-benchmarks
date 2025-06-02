#!/bin/bash

# Exit on error
set -e

# Parse command line arguments
LOCAL_DEV=false
for arg in "$@"; do
  case $arg in
    --local)
      LOCAL_DEV=true
      shift # Remove --local from processing
      ;;
    *)
      # Unknown option
      ;;
  esac
done

TESTS_DIR="$(dirname "$0")/../tests"

# Count the number of test case files in the tests directory
NUM_TEST_CASES=$(ls -1  $TESTS_DIR/test_case_*.json 2>/dev/null | wc -l)
if [ "$NUM_TEST_CASES" -eq 0 ]; then
  echo "⚠️  Warning: No test case files found in tests/ directory"
  NUM_TEST_CASES=0  # Default fallback
else
  echo "📊 Found $NUM_TEST_CASES test case files in tests/ directory"
fi


echo "🚀 Starting ECDSA SNARK benchmark setup..."
# Compile circuit
echo "🔨 Compiling circuit..."
./scripts/compile-circuit.sh

# Run trusted setup
echo "🔑 Running trusted setup..."
./scripts/trusted-setup.sh

# Compute witnesses
echo "🧮 Computing witnesses..."
./scripts/compute-witnesses.sh

# Generate proofs
echo "🔐 Generating proofs..."
./scripts/generate-proofs.sh

# Verify proofs
echo "🔍 Verifying proofs..."
./scripts/verify-proofs.sh

# Benchmark gas usage
echo "⛽ Benchmarking gas usage..."
./scripts/benchmark-gas.sh

echo "✅ All done! Check the benchmarks and gas-reports directories for results." 