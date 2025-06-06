#!/bin/bash

# Exit on error
set -e

echo "🔐 Starting trusted setup..."

# Create setup output directory
mkdir -p /out/setup

# Check if trusted setup is already completed
if [ -f "/out/setup/circuit.zkey" ] && [ -f "/out/setup/verification_key.json" ]; then
    echo "✅ Trusted setup already completed, skipping setup step."
    echo "   Found: /out/setup/circuit.zkey and /out/setup/verification_key.json"
    echo "   To redo setup, delete the '/out/setup' directory first."
    exit 0
fi

# Check if powers of tau file exists (mounted from host)
if [ ! -f "pot22_final.ptau" ]; then
    echo "❌ Error: Powers of tau file not found!"
    echo "Please ensure pot22_final.ptau is mounted into the container."
    echo "Download it with: curl -L 'https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau' -o pot22_final.ptau"
    exit 1
fi

# Generate the proving key and zkey
echo "📝 Generating proving key and verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs groth16 setup /out/compilation/circuit.r1cs pot22_final.ptau /out/setup/circuit.zkey

# Export the verification key
echo "🔑 Exporting verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs zkey export verificationkey /out/setup/circuit.zkey /out/setup/verification_key.json

echo "✅ Trusted setup completed successfully!"
