#!/bin/bash

# Exit on error
set -e

echo "🔐 Starting trusted setup..."

# Create the setup output directory
mkdir -p /out/setup

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
fi

echo "✅ Powers of tau file found, proceeding with setup."
echo "📝 Generating proving key and verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs zkey new /out/setup/circuit.r1cs pot22_final.ptau /out/setup/circuit.zkey

echo "✅ Proving key and verification key generated successfully!"

echo "🔑 Exporting verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs zkey export verificationkey /out/setup/circuit.zkey /out/setup/verification_key.json

echo "✅ Trusted setup completed successfully!"
