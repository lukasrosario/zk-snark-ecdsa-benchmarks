#!/bin/bash

# Exit on error
set -e

echo "🔨 Starting circuit compilation..."

# Compile the circuit
echo "📝 Compiling circuit.circom..."

# Check if out directory exists and remove it if it does
if [ -d "out" ]; then
    echo "📂 Removing existing out directory..."
    rm -rf out
fi

# Create a fresh out directory
mkdir out
circom circuit.circom --r1cs --wasm -o ./out

echo "✅ Circuit compilation completed successfully!" 