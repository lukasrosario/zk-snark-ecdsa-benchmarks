#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "pot22_final.ptau" ]; then
    error "Not in the correct directory. Please run from the zk-snark-ecdsa-benchmarks root directory."
    exit 1
fi

# Get system information
CPU_CORES=$(nproc)
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "local")

log "Starting benchmarks on $INSTANCE_TYPE with $CPU_CORES CPU cores and ${MEMORY_GB}GB RAM"

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="/mnt/benchmark-data/results_${INSTANCE_TYPE}_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# Save system info
cat > "$RESULTS_DIR/system_info.json" << EOF
{
  "instance_type": "$INSTANCE_TYPE",
  "cpu_cores": $CPU_CORES,
  "memory_gb": $MEMORY_GB,
  "timestamp": "$TIMESTAMP",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Coordinated Memory Allocation Strategy:
# - Docker containers get enough memory to run Node.js processes plus overhead
# - Node.js heap size is pre-calculated and passed to containers via environment variables
# - This ensures no memory conflicts and optimal performance
# Calculate memory allocation strategy based on available resources
if [ "$MEMORY_GB" -ge 15 ]; then
    # 16+ GB instances: Node.js gets 12GB, Docker gets 14GB (leaves 2GB for system + container overhead)
    NODE_MEMORY_MB=12288
    DOCKER_MEMORY_LIMIT="14g"
elif [ "$MEMORY_GB" -ge 7 ]; then
    # 8GB instances: Node.js gets 6GB, Docker gets 7GB (leaves 1GB for system + container overhead)
    NODE_MEMORY_MB=6144
    DOCKER_MEMORY_LIMIT="7g"
elif [ "$MEMORY_GB" -ge 4 ]; then
    # 4GB instances: Node.js gets 3GB, Docker gets 3.5GB (leaves 0.5GB for system + container overhead)
    NODE_MEMORY_MB=3072
    DOCKER_MEMORY_LIMIT="3584m"  # 3.5GB in MB
else
    # Less than 4GB: Node.js gets 2GB, Docker gets 2.5GB
    NODE_MEMORY_MB=2048
    DOCKER_MEMORY_LIMIT="2560m"  # 2.5GB in MB
fi

# Common Docker flags for performance optimization
DOCKER_FLAGS="--cpus=${CPU_CORES} --memory=${DOCKER_MEMORY_LIMIT} --memory-swap=${DOCKER_MEMORY_LIMIT} --shm-size=1g"

# Calculate memory in MB for passing to containers
MEMORY_MB=$((MEMORY_GB * 1024))

# Environment variables to pass to containers (including the calculated Node.js memory)
DOCKER_ENV="-e HOST_MEMORY_MB=$MEMORY_MB -e HOST_MEMORY_GB=$MEMORY_GB -e NODE_MEMORY_MB=$NODE_MEMORY_MB"

log "Using Docker flags: $DOCKER_FLAGS"
log "Memory allocation: Host=${MEMORY_GB}GB, Docker=${DOCKER_MEMORY_LIMIT}, Node.js=${NODE_MEMORY_MB}MB"

# Function to run a benchmark suite
run_benchmark() {
    local suite=$1
    local description=$2
    
    log "=== Starting $description ==="
    local start_time=$(date +%s)
    
    cd "$suite"
    
    # Build the Docker image
    log "Building Docker image for $suite"
    docker build -t "zk-ecdsa-$suite" .
    
    # Create suite-specific results directory
    local suite_results="$RESULTS_DIR/$suite"
    mkdir -p "$suite_results"
    
    # Run the benchmark with performance optimizations
    log "Running $suite benchmark with optimized settings"
    
    case $suite in
        "snarkjs")
            docker run $DOCKER_FLAGS $DOCKER_ENV \
                -v "$(pwd)/../pot22_final.ptau:/app/pot22_final.ptau:ro" \
                -v "$suite_results:/out" \
                --name "zk-ecdsa-$suite-benchmark-$TIMESTAMP" \
                "zk-ecdsa-$suite"
            ;;
        "rapidsnark")
            docker run $DOCKER_FLAGS $DOCKER_ENV \
                -v "$(pwd)/../pot22_final.ptau:/app/pot22_final.ptau:ro" \
                -v "$(pwd)/tests:/app/tests:ro" \
                -v "$suite_results:/out" \
                --name "zk-ecdsa-$suite-benchmark-$TIMESTAMP" \
                "zk-ecdsa-$suite"
            ;;
        "noir")
            docker run $DOCKER_FLAGS $DOCKER_ENV \
                -v "$(pwd)/tests:/app/tests:ro" \
                -v "$suite_results:/out" \
                --name "zk-ecdsa-$suite-benchmark-$TIMESTAMP" \
                "zk-ecdsa-$suite"
            ;;
        "gnark")
            docker run $DOCKER_FLAGS $DOCKER_ENV \
                -v "$(pwd)/tests:/app/tests:ro" \
                -v "$suite_results:/out" \
                --name "zk-ecdsa-$suite-benchmark-$TIMESTAMP" \
                "zk-ecdsa-$suite"
            ;;
    esac
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Save benchmark metadata
    cat > "$suite_results/benchmark_info.json" << EOF
{
  "suite": "$suite",
  "description": "$description",
  "start_time": $start_time,
  "end_time": $end_time,
  "duration_seconds": $duration,
  "docker_flags": "$DOCKER_FLAGS",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    # Clean up container
    docker rm "zk-ecdsa-$suite-benchmark-$TIMESTAMP" 2>/dev/null || true
    
    log "$description completed in ${duration}s"
    cd ..
}

# Check if Docker is running
if ! docker ps >/dev/null 2>&1; then
    error "Docker is not running. Please start Docker first."
    exit 1
fi

# Ensure Docker has enough memory allocated
log "Configuring Docker for optimal performance"
sudo systemctl restart docker
sleep 5

# Set CPU frequency governor to performance
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    log "Setting CPU governor to performance mode"
    sudo sh -c 'echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor' 2>/dev/null || warn "Could not set CPU governor"
fi

# Run all benchmark suites
benchmark_start=$(date +%s)

run_benchmark "snarkjs" "SnarkJS (JavaScript) ECDSA Benchmarks"
run_benchmark "rapidsnark" "RapidSnark (C++) ECDSA Benchmarks" 
run_benchmark "noir" "Noir (Rust) ECDSA Benchmarks"
run_benchmark "gnark" "Gnark (Go) ECDSA Benchmarks"

benchmark_end=$(date +%s)
total_duration=$((benchmark_end - benchmark_start))

# Create summary report
cat > "$RESULTS_DIR/summary.json" << EOF
{
  "instance_type": "$INSTANCE_TYPE",
  "cpu_cores": $CPU_CORES,
  "memory_gb": $MEMORY_GB,
  "total_duration_seconds": $total_duration,
  "docker_memory_limit": "$DOCKER_MEMORY_LIMIT",
  "started_at": "$(date -d @$benchmark_start -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "suites_completed": ["snarkjs", "rapidsnark", "noir", "gnark"]
}
EOF

log "=== All benchmarks completed in ${total_duration}s ==="
log "Results saved to: $RESULTS_DIR"
log "Summary available at: $RESULTS_DIR/summary.json"

# Display disk usage
du -sh "$RESULTS_DIR"

# Create a quick comparison if all suites completed
if [ -d "$RESULTS_DIR/snarkjs" ] && [ -d "$RESULTS_DIR/rapidsnark" ] && [ -d "$RESULTS_DIR/noir" ] && [ -d "$RESULTS_DIR/gnark" ]; then
    log "Generating performance comparison..."
    
    cat > "$RESULTS_DIR/performance_comparison.md" << EOF
# ZK-SNARK ECDSA Benchmark Results

**Instance Type:** $INSTANCE_TYPE  
**CPU Cores:** $CPU_CORES  
**Memory:** ${MEMORY_GB}GB  
**Date:** $(date)

## Execution Times

EOF
    
    for suite in snarkjs rapidsnark noir gnark; do
        if [ -f "$RESULTS_DIR/$suite/benchmark_info.json" ]; then
            duration=$(jq -r '.duration_seconds' "$RESULTS_DIR/$suite/benchmark_info.json")
            echo "- **$suite**: ${duration}s" >> "$RESULTS_DIR/performance_comparison.md"
        fi
    done
    
    cat >> "$RESULTS_DIR/performance_comparison.md" << EOF

## Results Location

All detailed results, proofs, and artifacts are stored in:
\`$RESULTS_DIR\`

Each suite has its own subdirectory with complete benchmark outputs.
EOF

    log "Performance comparison saved to: $RESULTS_DIR/performance_comparison.md"
fi

log "Benchmark suite execution completed successfully!" 