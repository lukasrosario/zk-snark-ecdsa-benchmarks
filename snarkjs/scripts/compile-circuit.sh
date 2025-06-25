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

# Compile the circuit
echo "📝 Compiling circuit.circom..."

# Create the compilation output directory
mkdir -p /out/setup
mkdir -p /out/benchmarks

# Check if compilation directory exists and remove it if it does
if [ -d "/out/setup" ] && [ "$(ls -A /out/setup)" ]; then
    echo "📂 Removing existing compilation directory contents..."
    rm -rf /out/setup/*
fi

circom circuit.circom --r1cs --wasm -o /out/setup

echo "✅ Circuit compilation completed successfully!" 