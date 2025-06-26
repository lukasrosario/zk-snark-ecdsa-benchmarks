# Use Ubuntu as base image for better build support
FROM ubuntu:22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libgmp-dev \
    libsodium-dev \
    nasm \
    curl \
    m4 \
    wget \
    jq \
    bc \
    vim-common \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install yarn
RUN npm install -g yarn

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install circom
RUN git clone https://github.com/iden3/circom.git && \
    cd circom && \
    cargo build --release && \
    cargo install --path circom && \
    cd .. && \
    rm -rf circom

# Install snarkjs
RUN npm install -g snarkjs

# Install hyperfine
RUN wget https://github.com/sharkdp/hyperfine/releases/download/v1.19.0/hyperfine_1.19.0_arm64.deb && \
    dpkg -i hyperfine_1.19.0_arm64.deb && \
    rm hyperfine_1.19.0_arm64.deb

RUN mkdir -p /app

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
RUN /root/.foundry/bin/foundryup -C d484a00089d789a19e2e43e63bbb3f1500eb2cbf

# Add Foundry binaries to PATH
ENV PATH="/root/.foundry/bin:${PATH}"

# Clone rapidsnark FIRST
RUN git clone https://github.com/iden3/rapidsnark.git

# Build rapidsnark and run tests
RUN cd rapidsnark && \
    # Initialize and update submodules
    git submodule init && \
    git submodule update && \
    # Clean any existing build artifacts
    rm -rf build_prover && \
    # Build GMP first
    chmod +x build_gmp.sh && \
    ./build_gmp.sh host_noasm && \
    # Build rapidsnark
    make host_noasm && \
    ls && \
    # Test rapidsnark with provided test files
    ./package_noasm/bin/prover testdata/circuit_final.zkey testdata/witness.wtns testdata/proof.json testdata/public.json && \
    echo "✅ rapidsnark build and test successful!"

# Set working directory
WORKDIR /app

# Configure Git to use HTTPS for submodules
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# Clone circom-ecdsa-p256 with specific commit hash and its submodules
RUN mkdir -p lib && \
    cd lib && \
    git clone --recursive https://github.com/privacy-scaling-explorations/circom-ecdsa-p256.git && \
    cd circom-ecdsa-p256 && \
    git checkout 5b916ea5241d07c5b5953dd5724d7fb771ad76d8 && \
    git submodule update --init --recursive

# Install npm dependencies in circom-ecdsa-p256
RUN cd lib/circom-ecdsa-p256 && npm install

# Install yarn dependencies in circom-pairing (if it exists)
RUN cd lib/circom-ecdsa-p256 && \
    if [ -d "circuits/circom-pairing" ]; then \
        cd circuits/circom-pairing && yarn install; \
    fi

# Create tests directory
RUN mkdir -p /app/tests

# Copy circuit file
COPY circuit.circom /app/
# Copy scripts
COPY scripts /app/scripts

# Default command to run setup and compilation
ENTRYPOINT ["/app/scripts/run.sh"]