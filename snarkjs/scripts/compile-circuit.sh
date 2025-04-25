#!/bin/bash

# Exit on error
set -e

echo "🔨 Starting circuit compilation..."

# Compile the circuit
echo "📝 Compiling circuit.circom..."
rm -rf ./out
mkdir out
circom circuit.circom --r1cs --wasm -o ./out

echo "✅ Circuit compilation completed successfully!" 