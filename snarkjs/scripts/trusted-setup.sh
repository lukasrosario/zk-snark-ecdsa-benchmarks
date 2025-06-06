#!/bin/bash

# Exit on error
set -e

echo "🔐 Starting trusted setup..."

# Create the setup output directory
mkdir -p /out/setup

# Check if trusted setup is already completed
if [ -f "/out/setup/circuit.zkey" ] && [ -f "/out/setup/verification_key.json" ]; then
    echo "✅ Trusted setup already completed, skipping setup step."
    echo "   Found: /out/setup/circuit.zkey and /out/setup/verification_key.json"
    echo "   To redo setup, delete these files first."
    exit 0
fi

# Check if powers of tau file is mounted/available
if [ ! -f "pot22_final.ptau" ]; then
    echo "❌ Powers of tau file not found!"
    echo "📝 Please mount the powers of tau file as a volume:"
    echo "   docker run -v /path/to/your/pot22_final.ptau:/app/pot22_final.ptau ..."
    echo ""
    echo "💡 You can download the file from:"
    echo "   https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau"
    echo ""
    echo "🚨 Exiting - powers of tau file is required for trusted setup."
    exit 1
else
    echo "✅ Powers of tau file found, proceeding with setup."
fi

# Check if we need to generate the proving key
if [ ! -f "/out/setup/circuit.zkey" ]; then
    echo "📝 Generating proving key and verification key..."
    NODE_OPTIONS=--max_old_space_size=16384 snarkjs groth16 setup /out/compilation/circuit.r1cs pot22_final.ptau /out/setup/circuit.zkey
else
    echo "✅ Proving key already exists, skipping generation."
fi

# Check if we need to export the verification key
if [ ! -f "/out/setup/verification_key.json" ]; then
    echo "🔑 Exporting verification key..."
    NODE_OPTIONS=--max_old_space_size=16384 snarkjs zkey export verificationkey /out/setup/circuit.zkey /out/setup/verification_key.json
else
    echo "✅ Verification key already exists, skipping export."
fi

echo "✅ Trusted setup completed successfully!"
