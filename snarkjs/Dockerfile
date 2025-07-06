# Use Node.js LTS version as base image
FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    curl \
    wget \
    jq \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install yarn
RUN corepack enable && corepack prepare yarn@stable --activate

# Install circom
RUN git clone https://github.com/iden3/circom.git && \
    cd circom && \
    cargo build --release && \
    cargo install --path circom && \
    cd .. && \
    rm -rf circom

# Install snarkjs
RUN npm install -g snarkjs

# Install hyperfine (detect architecture dynamically)
RUN ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/sharkdp/hyperfine/releases/download/v1.19.0/hyperfine_1.19.0_${ARCH}.deb && \
    dpkg -i hyperfine_1.19.0_${ARCH}.deb && \
    rm hyperfine_1.19.0_${ARCH}.deb

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
RUN /root/.foundry/bin/foundryup -C d484a00089d789a19e2e43e63bbb3f1500eb2cbf

# Add Foundry binaries to PATH
ENV PATH="/root/.foundry/bin:${PATH}"

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

# Copy test cases
COPY tests/*.json /app/tests/

# Copy scripts
COPY scripts /app/scripts

# Default command to run setup and compilation
ENTRYPOINT ["/app/scripts/run.sh"]