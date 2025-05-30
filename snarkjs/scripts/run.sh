#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting ECDSA SNARK benchmark setup..."

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
./scripts/compute-witnesses.sh --num-test-cases ${NUM_TEST_CASES:-10}

# Generate proofs
echo "🔐 Generating proofs..."
./scripts/generate-proofs.sh --num-test-cases ${NUM_TEST_CASES:-10}

# Verify proofs
echo "🔍 Verifying proofs..."
./scripts/verify-proofs.sh --num-test-cases ${NUM_TEST_CASES:-10}

# Benchmark gas usage
echo "⛽ Benchmarking gas usage..."
./scripts/benchmark-gas.sh --num-test-cases ${NUM_TEST_CASES:-10}

echo "✅ All done! Check the benchmarks and gas-reports directories for results." 