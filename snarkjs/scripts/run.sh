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

# Install dependencies
echo "📦 Installing dependencies..."
if [ "$LOCAL_DEV" = true ]; then
  echo "🔧 Local development environment detected, using setup-dependencies.sh..."
  ./scripts/setup-dependencies.sh
fi

# Install dependencies
echo "📦 Installing dependencies..."
./scripts/install-deps.sh

# Compile circuit
echo "🔨 Compiling circuit..."
./scripts/compile-circuit.sh

# Run trusted setup
echo "🔑 Running trusted setup..."
./scripts/trusted-setup.sh

# Compute witnesses
echo "🧮 Computing witnesses..."
./scripts/compute-witnesses.sh --num-test-cases $NUM_TEST_CASES

# Generate proofs
echo "🔐 Generating proofs..."
./scripts/generate-proofs.sh --num-test-cases $NUM_TEST_CASES

# Verify proofs
echo "🔍 Verifying proofs..."
./scripts/verify-proofs.sh --num-test-cases $NUM_TEST_CASES

# Benchmark gas usage
echo "⛽ Benchmarking gas usage..."
./scripts/benchmark-gas.sh --num-test-cases $NUM_TEST_CASES

echo "✅ All done! Check the benchmarks and gas-reports directories for results." 