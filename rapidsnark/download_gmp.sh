#!/bin/bash

# Download GMP archive for rapidsnark build
# This avoids network connectivity issues during Docker build

set -e

GMP_VERSION="6.2.1"
GMP_ARCHIVE="gmp-${GMP_VERSION}.tar.xz"
GMP_URL="https://ftp.gnu.org/gnu/gmp/${GMP_ARCHIVE}"

echo "Downloading GMP ${GMP_VERSION} archive..."

if [ -f "${GMP_ARCHIVE}" ]; then
    echo "✓ ${GMP_ARCHIVE} already exists, skipping download"
    exit 0
fi

# Try multiple download methods
if command -v curl >/dev/null 2>&1; then
    echo "Using curl to download..."
    curl -L -o "${GMP_ARCHIVE}" "${GMP_URL}"
elif command -v wget >/dev/null 2>&1; then
    echo "Using wget to download..."
    wget -O "${GMP_ARCHIVE}" "${GMP_URL}"
else
    echo "Error: Neither curl nor wget is available"
    exit 1
fi

if [ -f "${GMP_ARCHIVE}" ]; then
    echo "✓ Successfully downloaded ${GMP_ARCHIVE}"
    echo "✓ File size: $(du -h "${GMP_ARCHIVE}" | cut -f1)"
else
    echo "✗ Failed to download ${GMP_ARCHIVE}"
    exit 1
fi 