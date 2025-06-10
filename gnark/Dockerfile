# Use golang base image with all necessary tools
FROM golang:1.22-bullseye

# Install system dependencies including curl, bc, jq, and hyperfine for benchmarking
RUN apt-get update && apt-get install -y \
    curl \
    bc \
    jq \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install hyperfine for benchmarking (detect architecture dynamically)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -LO https://github.com/sharkdp/hyperfine/releases/download/v1.18.0/hyperfine_1.18.0_${ARCH}.deb && \
    dpkg -i hyperfine_1.18.0_${ARCH}.deb && \
    rm hyperfine_1.18.0_${ARCH}.deb

# Install Foundry for gas benchmarking
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN bash -c "source ~/.bashrc && foundryup"

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