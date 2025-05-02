#!/bin/bash

# Exit on error
set -e

echo "🔐 Starting trusted setup..."

# Download powers of tau file if it doesn't exist
if [ ! -f "pot22_final.ptau" ]; then
    echo "📥 Downloading powers of tau file..."
    curl -L "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau" -o pot22_final.ptau
    echo "✅ Powers of tau file downloaded successfully!"
else
    echo "📂 Powers of tau file already exists, skipping download."
fi

# Generate the proving key and zkey
echo "📝 Generating proving key and verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs groth16 setup ./out/circuit.r1cs pot22_final.ptau circuit.zkey

# Export the verification key
echo "🔑 Exporting verification key..."
NODE_OPTIONS=--max_old_space_size=16384 snarkjs zkey export verificationkey circuit.zkey verification_key.json

echo "✅ Trusted setup completed successfully!"
