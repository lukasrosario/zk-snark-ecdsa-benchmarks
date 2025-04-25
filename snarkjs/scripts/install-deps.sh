#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting dependency installation..."

# Install npm dependencies in circom-ecdsa-p256
echo "📦 Installing npm dependencies in circom-ecdsa-p256..."
cd lib/circom-ecdsa-p256
npm install

# Install yarn dependencies (assuming there's a package.json in the parent directory)
echo "🧶 Installing yarn dependencies in circom-pairing..."
cd circuits/circom-pairing
yarn install

echo "✅ All dependencies installed successfully!" 