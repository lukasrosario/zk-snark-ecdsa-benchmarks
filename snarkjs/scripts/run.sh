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