#!/bin/bash
set -e

echo "Installing circom dependencies..."
./scripts/install-deps.sh

echo "Compiling circuit..."
./scripts/compile-circuit.sh

echo "Running trusted setup..."
./scripts/trusted-setup.sh

echo "Computing witnesses..."
./scripts/compute-witnesses.sh

echo "All done!" 