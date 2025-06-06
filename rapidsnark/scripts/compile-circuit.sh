#!/bin/bash

# Exit on error
set -e

# Check if circom is installed
if ! command -v circom &> /dev/null; then
    echo "❌ Error: circom command not found!"
    echo "Please install circom using Cargo (Rust's package manager):"
    echo "1. Install Rust if not already installed: https://www.rust-lang.org/tools/install"
    echo "2. Run: cargo install circom"
    echo "For more information, visit: https://github.com/iden3/circom"
    exit 1
fi

echo "🔨 Starting circuit compilation..."

# Check if circuit is already compiled
if [ -f "/out/compilation/circuit.r1cs" ] && [ -f "/out/compilation/circuit_js/circuit.wasm" ]; then
    echo "✅ Circuit already compiled, skipping compilation step."
    echo "   Found: /out/compilation/circuit.r1cs and /out/compilation/circuit_js/circuit.wasm"
    echo "   To recompile, delete the '/out/compilation' directory first."
    exit 0
fi

# Compile the circuit
echo "📝 Compiling circuit.circom..."

# Create the compilation output directory
mkdir -p /out/compilation

# Check if compilation directory exists and remove it if it does
if [ -d "/out/compilation" ] && [ "$(ls -A /out/compilation)" ]; then
    echo "📂 Removing existing compilation directory contents..."
    rm -rf /out/compilation/*
fi

circom circuit.circom --r1cs --wasm -o /out/compilation

echo "✅ Circuit compilation completed successfully!" 