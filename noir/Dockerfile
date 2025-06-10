FROM ubuntu:24.04 AS builder

# Install system dependencies for building
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libgmp-dev \
    libsodium-dev \
    curl \
    wget \
    jq \
    vim-common \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
RUN foundryup

# Install hyperfine for benchmarking
RUN ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/sharkdp/hyperfine/releases/download/v1.19.0/hyperfine_1.19.0_${ARCH}.deb && \
    dpkg -i hyperfine_1.19.0_${ARCH}.deb && \
    rm hyperfine_1.19.0_${ARCH}.deb

# Install noirup and nargo
# TODO: always pin in build!
RUN curl -L https://raw.githubusercontent.com/noir-lang/noirup/refs/heads/main/install | bash -s -- -y
ENV PATH="/root/.nargo/bin:${PATH}"
RUN echo 'export PATH="$HOME/.nargo/bin:$PATH"' >> ~/.bashrc
# Verify nargo is installed correctly and in PATH
RUN noirup -v 1.0.0-beta.4

# Install bbup and bb (Barretenberg)
RUN curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/master/barretenberg/bbup/install | bash
ENV PATH="/root/.bb:${PATH}"
RUN echo 'export PATH="$HOME/.bb:$PATH"' >> ~/.bashrc
RUN bbup

# FROM here is the final image
FROM ubuntu:24.04

# Install only the runtime dependencies
RUN apt-get update && apt-get install -y \
    libgmp-dev \
    libsodium-dev \
    git \
    curl \
    jq \
    xxd \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Copy necessary binaries and directories from builder
COPY --from=builder /root/.cargo/bin/ /root/.cargo/bin/
COPY --from=builder /root/.nargo/ /root/.nargo/
COPY --from=builder /root/.bb/ /root/.bb/
COPY --from=builder /usr/bin/hyperfine /usr/bin/
COPY --from=builder /root/.foundry/ /root/.foundry/

# Set environment variables
ENV PATH="/root/.cargo/bin:/root/.nargo/bin:/root/.bb:/root/.foundry/bin:${PATH}"

# Set working directory
WORKDIR /app

# Copy Noir project files
COPY . /app

# Create persistent data directory
RUN mkdir -p /out

# Default command to run setup and benchmarks
ENTRYPOINT ["/app/scripts/run.sh"] 