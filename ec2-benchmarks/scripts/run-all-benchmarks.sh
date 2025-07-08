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
if [ "$MEMORY_GB" -ge 30 ]; then
    # 30+ GB instances: Node.js gets 24GB, Docker gets 28GB (leaves 4GB for system + container overhead)
    NODE_MEMORY_MB=24576
    DOCKER_MEMORY_LIMIT="28g"
elif [ "$MEMORY_GB" -ge 15 ]; then
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
    
    # Clean up container and image to free disk space
    docker rm "zk-ecdsa-$suite-benchmark-$TIMESTAMP" 2>/dev/null || true
    docker rmi "zk-ecdsa-$suite" 2>/dev/null || true
    
    log "$description completed in ${duration}s"
    log "Cleaned up Docker container and image for $suite"
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

# Define memory requirements for each suite (in MB)
SNARKJS_MIN_MEMORY=15000
RAPIDSNARK_MIN_MEMORY=15000
NOIR_MIN_MEMORY=2000
GNARK_MIN_MEMORY=2000

# Convert GB to MB for comparison
MEMORY_MB=$((MEMORY_GB * 1024))

# Run benchmark suites based on available memory
benchmark_start=$(date +%s)
COMPLETED_SUITES=()
SKIPPED_SUITES=()

# Check and run SnarkJS
if [ "$MEMORY_MB" -ge "$SNARKJS_MIN_MEMORY" ]; then
    log "Memory sufficient for SnarkJS (${MEMORY_MB}MB >= ${SNARKJS_MIN_MEMORY}MB)"
    run_benchmark "snarkjs" "SnarkJS (JavaScript) ECDSA Benchmarks"
    COMPLETED_SUITES+=("snarkjs")
else
    warn "Skipping SnarkJS - insufficient memory (${MEMORY_MB}MB < ${SNARKJS_MIN_MEMORY}MB)"
    SKIPPED_SUITES+=("snarkjs")
fi

# Check and run RapidSnark
if [ "$MEMORY_MB" -ge "$RAPIDSNARK_MIN_MEMORY" ]; then
    log "Memory sufficient for RapidSnark (${MEMORY_MB}MB >= ${RAPIDSNARK_MIN_MEMORY}MB)"
    run_benchmark "rapidsnark" "RapidSnark (C++) ECDSA Benchmarks"
    COMPLETED_SUITES+=("rapidsnark")
else
    warn "Skipping RapidSnark - insufficient memory (${MEMORY_MB}MB < ${RAPIDSNARK_MIN_MEMORY}MB)"
    SKIPPED_SUITES+=("rapidsnark")
fi

# Check and run Noir
if [ "$MEMORY_MB" -ge "$NOIR_MIN_MEMORY" ]; then
    log "Memory sufficient for Noir (${MEMORY_MB}MB >= ${NOIR_MIN_MEMORY}MB)"
    run_benchmark "noir" "Noir (Rust) ECDSA Benchmarks"
    COMPLETED_SUITES+=("noir")
else
    warn "Skipping Noir - insufficient memory (${MEMORY_MB}MB < ${NOIR_MIN_MEMORY}MB)"
    SKIPPED_SUITES+=("noir")
fi

# Check and run Gnark
if [ "$MEMORY_MB" -ge "$GNARK_MIN_MEMORY" ]; then
    log "Memory sufficient for Gnark (${MEMORY_MB}MB >= ${GNARK_MIN_MEMORY}MB)"
    run_benchmark "gnark" "Gnark (Go) ECDSA Benchmarks"
    COMPLETED_SUITES+=("gnark")
else
    warn "Skipping Gnark - insufficient memory (${MEMORY_MB}MB < ${GNARK_MIN_MEMORY}MB)"
    SKIPPED_SUITES+=("gnark")
fi

benchmark_end=$(date +%s)
total_duration=$((benchmark_end - benchmark_start))

# Create summary report
cat > "$RESULTS_DIR/summary.json" << EOF
{
  "instance_type": "$INSTANCE_TYPE",
  "cpu_cores": $CPU_CORES,
  "memory_gb": $MEMORY_GB,
  "memory_mb": $MEMORY_MB,
  "total_duration_seconds": $total_duration,
  "docker_memory_limit": "$DOCKER_MEMORY_LIMIT",
  "started_at": "$(date -d @$benchmark_start -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "suites_completed": [$(printf '"%s",' "${COMPLETED_SUITES[@]}" | sed 's/,$//')]$([ ${#COMPLETED_SUITES[@]} -eq 0 ] && echo ''),
  "suites_skipped": [$(printf '"%s",' "${SKIPPED_SUITES[@]}" | sed 's/,$//')]$([ ${#SKIPPED_SUITES[@]} -eq 0 ] && echo ''),
  "memory_requirements": {
    "snarkjs_min_mb": $SNARKJS_MIN_MEMORY,
    "rapidsnark_min_mb": $RAPIDSNARK_MIN_MEMORY,
    "noir_min_mb": $NOIR_MIN_MEMORY,
    "gnark_min_mb": $GNARK_MIN_MEMORY
  }
}
EOF

log "=== Benchmark execution completed in ${total_duration}s ==="
log "Completed suites: ${COMPLETED_SUITES[*]}"
log "Skipped suites: ${SKIPPED_SUITES[*]}"
log "Results saved to: $RESULTS_DIR"
log "Summary available at: $RESULTS_DIR/summary.json"

# Display disk usage
du -sh "$RESULTS_DIR"

# Create a performance comparison for completed suites
if [ ${#COMPLETED_SUITES[@]} -gt 0 ]; then
    log "Generating performance comparison..."
    
    cat > "$RESULTS_DIR/performance_comparison.md" << EOF
# ZK-SNARK ECDSA Benchmark Results

**Instance Type:** $INSTANCE_TYPE  
**CPU Cores:** $CPU_CORES  
**Memory:** ${MEMORY_GB}GB (${MEMORY_MB}MB)  
**Date:** $(date)

## Execution Times

EOF
    
    for suite in "${COMPLETED_SUITES[@]}"; do
        if [ -f "$RESULTS_DIR/$suite/benchmark_info.json" ]; then
            duration=$(jq -r '.duration_seconds' "$RESULTS_DIR/$suite/benchmark_info.json")
            echo "- **$suite**: ${duration}s" >> "$RESULTS_DIR/performance_comparison.md"
        fi
    done
    
    if [ ${#SKIPPED_SUITES[@]} -gt 0 ]; then
        cat >> "$RESULTS_DIR/performance_comparison.md" << EOF

## Skipped Suites

The following suites were skipped due to insufficient memory:

EOF
        for suite in "${SKIPPED_SUITES[@]}"; do
            case $suite in
                "snarkjs") echo "- **$suite**: Requires ${SNARKJS_MIN_MEMORY}MB memory (15GB system)" >> "$RESULTS_DIR/performance_comparison.md" ;;
                "rapidsnark") echo "- **$suite**: Requires ${RAPIDSNARK_MIN_MEMORY}MB memory (15GB system)" >> "$RESULTS_DIR/performance_comparison.md" ;;
                "noir") echo "- **$suite**: Requires ${NOIR_MIN_MEMORY}MB memory (2GB system)" >> "$RESULTS_DIR/performance_comparison.md" ;;
                "gnark") echo "- **$suite**: Requires ${GNARK_MIN_MEMORY}MB memory (2GB system)" >> "$RESULTS_DIR/performance_comparison.md" ;;
            esac
        done
    fi
    
    cat >> "$RESULTS_DIR/performance_comparison.md" << EOF

## Results Location

All detailed results, proofs, and artifacts are stored in:
\`$RESULTS_DIR\`

Each completed suite has its own subdirectory with complete benchmark outputs.
EOF

    log "Performance comparison saved to: $RESULTS_DIR/performance_comparison.md"
else
    warn "No suites completed successfully - no performance comparison generated"
fi

# Final cleanup to free disk space
log "Performing final Docker cleanup..."
docker system prune -f 2>/dev/null || true

log "Benchmark suite execution completed successfully!" 