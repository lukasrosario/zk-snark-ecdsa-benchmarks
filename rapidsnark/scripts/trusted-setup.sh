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

echo "✅ Powers of tau file found, proceeding with setup."

# Detect available memory and set appropriate Node.js heap size (cross-platform)
if command -v free >/dev/null 2>&1; then
    # Linux (EC2 instances)
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ {print $2}')
elif command -v sysctl >/dev/null 2>&1; then
    # macOS
    TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "8589934592")
    TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
else
    # Fallback: assume 8GB
    TOTAL_MEM_MB=8192
    echo "⚠️  Could not detect memory, assuming 8GB"
fi

if [ "$TOTAL_MEM_MB" -ge 15000 ]; then
    # 16+ GB instances: use 12GB for Node.js
    NODE_MEMORY=12288
elif [ "$TOTAL_MEM_MB" -ge 7000 ]; then
    # 8GB instances: use 6GB for Node.js
    NODE_MEMORY=6144
else
    # 4GB instances: use 3GB for Node.js
    NODE_MEMORY=3072
fi

echo "📊 Detected ${TOTAL_MEM_MB}MB RAM, allocating ${NODE_MEMORY}MB to Node.js"

echo "📝 Generating proving key and verification key..."
NODE_OPTIONS=--max_old_space_size=$NODE_MEMORY snarkjs groth16 setup /out/setup/circuit.r1cs pot22_final.ptau /out/setup/circuit.zkey

# Export the verification key
echo "🔑 Exporting verification key..."
NODE_OPTIONS=--max_old_space_size=$NODE_MEMORY snarkjs zkey export verificationkey /out/setup/circuit.zkey /out/setup/verification_key.json

echo "✅ Proving key and verification key generated successfully!"

echo "✅ Trusted setup completed successfully!"
