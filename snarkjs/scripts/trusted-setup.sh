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
NODE_OPTIONS=--max_old_space_size=$NODE_MEMORY snarkjs zkey new /out/setup/circuit.r1cs pot22_final.ptau /out/setup/circuit.zkey

echo "✅ Proving key and verification key generated successfully!"

echo "🔑 Exporting verification key..."
NODE_OPTIONS=--max_old_space_size=$NODE_MEMORY snarkjs zkey export verificationkey /out/setup/circuit.zkey /out/setup/verification_key.json

echo "✅ Trusted setup completed successfully!"
