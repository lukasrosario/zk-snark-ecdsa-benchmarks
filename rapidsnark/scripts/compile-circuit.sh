#!/bin/bash

# Exit on error
set -e

echo "🔨 [1/5] Compiling circuit..."

# Create directories for setup and benchmarks
mkdir -p /out/setup
mkdir -p /out/benchmarks

# Compile the circuit
circom circuit.circom --r1cs --wasm --sym -o /out/setup

echo "✅ Circuit compiled successfully!"
echo "   Artifacts saved to /out/setup/" 