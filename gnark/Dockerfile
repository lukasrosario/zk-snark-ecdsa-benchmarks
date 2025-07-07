# Use golang base image with all necessary tools
FROM golang:1.22-bullseye

# Install system dependencies including curl, bc, jq, and hyperfine for benchmarking
RUN n=1; \
    max=5; \
    delay=5; \
    while true; do \
        (apt-get update && apt-get install -y --fix-missing \
            curl \
            bc \
            jq \
            git \
            ca-certificates \
            && rm -rf /var/lib/apt/lists/*) && break || { \
                if [ $n -lt $max ]; then \
                    n=$((n+1)); \
                    echo "Command failed. Attempt $n/$max:"; \
                    sleep $delay; \
                else \
                    echo "The command has failed after $n attempts."; \
                    exit 1; \
                fi; \
            }; \
    done

# Install hyperfine for benchmarking (detect architecture dynamically)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -LO https://github.com/sharkdp/hyperfine/releases/download/v1.18.0/hyperfine_1.18.0_${ARCH}.deb && \
    dpkg -i hyperfine_1.18.0_${ARCH}.deb && \
    rm hyperfine_1.18.0_${ARCH}.deb

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
RUN /root/.foundry/bin/foundryup -C d484a00089d789a19e2e43e63bbb3f1500eb2cbf

# Add Foundry binaries to PATH
ENV PATH="/root/.foundry/bin:${PATH}"

# Verify forge installation
RUN forge --version

# Set the working directory
WORKDIR /app

# Copy Go modules files first for better caching
COPY go.mod go.sum ./

# Download and tidy Go modules  
RUN go mod tidy && go mod download

# Copy source code
COPY . .

# Copy scripts and make them executable
RUN chmod +x scripts/*.sh

# Create necessary directories
RUN mkdir -p data tests

# Set script entrypoint
ENTRYPOINT ["/app/scripts/run.sh"] 