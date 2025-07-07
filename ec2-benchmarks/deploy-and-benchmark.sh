#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v terraform &> /dev/null; then
        missing_deps+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_deps+=("awscli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy EC2 instances and run ZK-SNARK ECDSA benchmarks

OPTIONS:
    -k, --key-name KEY      EC2 key pair name (required)
    -s, --subnet-id SUBNET  VPC subnet ID (required)  
    -v, --vpc-id VPC        VPC ID (required)
    -r, --region REGION     AWS region (default: us-east-1)
    -t, --test-cases NUM    Number of test cases to generate (default: 10)
    --skip-deploy           Skip infrastructure deployment (use existing instances)
    --skip-benchmarks       Skip benchmark execution (deploy only)
    --cleanup               Destroy infrastructure after benchmarks complete
    -h, --help              Show this help message

EXAMPLES:
    # Deploy and run benchmarks
    $0 -k my-key -s subnet-123456 -v vpc-123456
    
    # Use custom region and more test cases
    $0 -k my-key -s subnet-123456 -v vpc-123456 -r us-west-2 -t 20
    
    # Deploy only (no benchmarks)
    $0 -k my-key -s subnet-123456 -v vpc-123456 --skip-benchmarks
    
    # Run benchmarks on existing instances
    $0 --skip-deploy
    
    # Full cycle with cleanup
    $0 -k my-key -s subnet-123456 -v vpc-123456 --cleanup

EOF
}

# Default values
AWS_REGION="us-east-1"
TEST_CASES=10
SKIP_DEPLOY=false
SKIP_BENCHMARKS=false
CLEANUP=false
KEY_NAME=""
SUBNET_ID=""
VPC_ID=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key-name)
            KEY_NAME="$2"
            shift 2
            ;;
        -s|--subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        -v|--vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -t|--test-cases)
            TEST_CASES="$2"
            shift 2
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --skip-benchmarks)
            SKIP_BENCHMARKS=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters (only if not skipping deploy)
if [ "$SKIP_DEPLOY" = false ]; then
    if [ -z "$KEY_NAME" ] || [ -z "$SUBNET_ID" ] || [ -z "$VPC_ID" ]; then
        error "Required parameters missing"
        usage
        exit 1
    fi
fi

# Check if we're in the correct directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_ROOT/Cargo.toml" ]; then
    error "Please run this script from the ec2-benchmarks directory within the zk-snark-ecdsa-benchmarks project"
    exit 1
fi

log "Starting EC2 benchmark deployment..."
log "Project root: $PROJECT_ROOT"

# Check dependencies
check_dependencies

# Move to terraform directory
cd "$SCRIPT_DIR/terraform"

# Deploy infrastructure
if [ "$SKIP_DEPLOY" = false ]; then
    log "=== Deploying EC2 Infrastructure ==="
    
    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
aws_region = "$AWS_REGION"
key_name   = "$KEY_NAME"
subnet_id  = "$SUBNET_ID"
vpc_id     = "$VPC_ID"
EOF

    # Initialize and apply Terraform
    log "Initializing Terraform..."
    terraform init
    
    log "Planning infrastructure deployment..."
    terraform plan
    
    log "Applying infrastructure changes..."
    terraform apply -auto-approve
    
    # Get instance information
    log "Retrieving instance information..."
    terraform output -json > ../instance_outputs.json
    
    # Extract instance IPs
    T4G_IP=$(terraform output -json instance_info | jq -r '.t4g_medium.public_ip')
    C7G_IP=$(terraform output -json instance_info | jq -r '.c7g_xlarge.public_ip')
    C7I_2X_IP=$(terraform output -json instance_info | jq -r '.c7i_2xlarge.public_ip')
    C7I_4X_IP=$(terraform output -json instance_info | jq -r '.c7i_4xlarge.public_ip')
    
    log "Instances deployed:"
    log "  t4g.medium:   $T4G_IP"
    log "  c7g.xlarge:   $C7G_IP"
    log "  c7i.2xlarge:  $C7I_2X_IP"
    log "  c7i.4xlarge:  $C7I_4X_IP"
    
    # Wait for instances to be ready
    log "Waiting for instances to complete setup..."
    
    wait_for_instance() {
        local ip=$1
        local instance_name=$2
        local max_attempts=60
        local attempt=1
        
        log "Waiting for $instance_name ($ip) to be ready..."
        
        while [ $attempt -le $max_attempts ]; do
            if ssh -i ~/.ssh/$KEY_NAME.pem -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$ip "test -f /home/ubuntu/setup-complete" 2>/dev/null; then
                log "$instance_name is ready!"
                return 0
            fi
            
            log "Attempt $attempt/$max_attempts - $instance_name not ready yet..."
            sleep 30
            ((attempt++))
        done
        
        error "$instance_name failed to become ready after ${max_attempts} attempts"
        return 1
    }
    
    # Wait for all instances in parallel
    wait_for_instance "$T4G_IP" "t4g.medium" &
    wait_for_instance "$C7G_IP" "c7g.xlarge" &
    wait_for_instance "$C7I_2X_IP" "c7i.2xlarge" &
    wait_for_instance "$C7I_4X_IP" "c7i.4xlarge" &
    
    # Wait for all background jobs to complete
    wait
    
    log "All instances are ready!"
    
else
    log "Skipping infrastructure deployment"
    
    # Try to get existing instance information
    if [ -f "../instance_outputs.json" ]; then
        T4G_IP=$(jq -r '.instance_info.value.t4g_medium.public_ip' ../instance_outputs.json)
        C7G_IP=$(jq -r '.instance_info.value.c7g_xlarge.public_ip' ../instance_outputs.json)
        C7I_2X_IP=$(jq -r '.instance_info.value.c7i_2xlarge.public_ip' ../instance_outputs.json)
        C7I_4X_IP=$(jq -r '.instance_info.value.c7i_4xlarge.public_ip' ../instance_outputs.json)
        
        log "Using existing instances:"
        log "  t4g.medium:   $T4G_IP"
        log "  c7g.xlarge:   $C7G_IP"
        log "  c7i.2xlarge:  $C7I_2X_IP"
        log "  c7i.4xlarge:  $C7I_4X_IP"
    else
        error "No existing instance information found. Cannot skip deployment."
        exit 1
    fi
fi

# Run benchmarks
if [ "$SKIP_BENCHMARKS" = false ]; then
    log "=== Running Benchmarks ==="
    
    # Copy benchmark script to instances and run
    run_benchmark_on_instance() {
        local ip=$1
        local instance_type=$2
        
        log "Starting benchmarks on $instance_type ($ip)..."
        
        # Copy the benchmark script
        scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no \
            "$SCRIPT_DIR/scripts/run-all-benchmarks.sh" \
            ubuntu@$ip:/home/ubuntu/
        
        # Make it executable and run
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip \
            "chmod +x /home/ubuntu/run-all-benchmarks.sh && cd /home/ubuntu/zk-snark-ecdsa-benchmarks && /home/ubuntu/run-all-benchmarks.sh" \
            > "$SCRIPT_DIR/benchmark_${instance_type}.log" 2>&1 &
        
        log "Benchmark started on $instance_type (log: benchmark_${instance_type}.log)"
    }
    
    # Start benchmarks on all instances in parallel
    run_benchmark_on_instance "$T4G_IP" "t4g_medium"
    run_benchmark_on_instance "$C7G_IP" "c7g_xlarge"  
    run_benchmark_on_instance "$C7I_2X_IP" "c7i_2xlarge"
    run_benchmark_on_instance "$C7I_4X_IP" "c7i_4xlarge"
    
    log "All benchmarks started. Waiting for completion..."
    
    # Wait for all benchmark jobs to complete
    wait
    
    log "All benchmarks completed!"
    
    # Create results collection directory
    RESULTS_COLLECTION_DIR="$SCRIPT_DIR/collected_results_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$RESULTS_COLLECTION_DIR"
    
    # Collect results from all instances
    collect_results() {
        local ip=$1
        local instance_type=$2
        
        log "Collecting results from $instance_type..."
        
        # Get the latest results directory
        LATEST_RESULTS=$(ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip \
            "ls -t /mnt/benchmark-data/results_* | head -n1" 2>/dev/null || echo "")
        
        if [ -n "$LATEST_RESULTS" ]; then
            # Copy the entire results directory to avoid wildcard issues with mixed files/directories
            if scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no -r \
                ubuntu@$ip:"$LATEST_RESULTS" \
                "$RESULTS_COLLECTION_DIR/" 2>/dev/null; then
                
                # Get the directory name and rename it to match instance type
                RESULTS_DIR_NAME=$(basename "$LATEST_RESULTS")
                if [ -d "$RESULTS_COLLECTION_DIR/$RESULTS_DIR_NAME" ]; then
                    mv "$RESULTS_COLLECTION_DIR/$RESULTS_DIR_NAME" "$RESULTS_COLLECTION_DIR/$instance_type"
                    log "Results collected from $instance_type"
                else
                    warn "Results directory not found after copy for $instance_type"
                fi
            else
                warn "Failed to copy results from $instance_type"
            fi
        else
            warn "No results found on $instance_type"
        fi
    }
    
    # Collect results from all instances
    collect_results "$T4G_IP" "t4g_medium"
    collect_results "$C7G_IP" "c7g_xlarge"
    collect_results "$C7I_2X_IP" "c7i_2xlarge"
    collect_results "$C7I_4X_IP" "c7i_4xlarge"
    
    # Generate comparison report
    log "Generating cross-instance comparison report..."
    
    cat > "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md" << 'EOF'
# ZK-SNARK ECDSA Cross-Instance Benchmark Comparison

This report compares the performance of ZK-SNARK ECDSA implementations across different EC2 instance types.

## Instance Specifications

- **t4g.medium**: ARM Graviton2, 2 vCPUs, 4GB RAM
- **c7g.xlarge**: ARM Graviton3, 4 vCPUs, 8GB RAM  
- **c7i.2xlarge**: Intel, 8 vCPUs, 16GB RAM
- **c7i.4xlarge**: Intel, 16 vCPUs, 32GB RAM

## Performance Summary

EOF
    
    # Add performance data for each instance type
    for instance_type in t4g_medium c7g_xlarge c7i_2xlarge c7i_4xlarge; do
        if [ -f "$RESULTS_COLLECTION_DIR/$instance_type/summary.json" ]; then
            echo "### $instance_type" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            
            cpu_cores=$(jq -r '.cpu_cores' "$RESULTS_COLLECTION_DIR/$instance_type/summary.json")
            memory_gb=$(jq -r '.memory_gb' "$RESULTS_COLLECTION_DIR/$instance_type/summary.json")
            total_duration=$(jq -r '.total_duration_seconds' "$RESULTS_COLLECTION_DIR/$instance_type/summary.json")
            
            echo "- **CPU Cores**: $cpu_cores" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "- **Memory**: ${memory_gb}GB" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "- **Total Duration**: ${total_duration}s" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
        fi
    done
    
    log "Cross-instance comparison saved to: $RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
    log "All results collected in: $RESULTS_COLLECTION_DIR"
    
else
    log "Skipping benchmark execution"
fi

# Cleanup infrastructure if requested
if [ "$CLEANUP" = true ]; then
    log "=== Cleaning Up Infrastructure ==="
    
    if [ "$SKIP_DEPLOY" = false ]; then
        log "Destroying Terraform infrastructure..."
        cd "$SCRIPT_DIR/terraform"
        terraform destroy -auto-approve
        log "Infrastructure destroyed"
    else
        warn "Cannot cleanup infrastructure - deployment was skipped"
    fi
fi

log "=== Deployment Complete ==="

if [ "$SKIP_BENCHMARKS" = false ]; then
    echo
    log "Benchmark results are available in: $RESULTS_COLLECTION_DIR"
    log "View the cross-instance comparison at: $RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
fi

if [ "$CLEANUP" = false ] && [ "$SKIP_DEPLOY" = false ]; then
    echo
    warn "EC2 instances are still running. Don't forget to destroy them when done:"
    warn "cd $SCRIPT_DIR/terraform && terraform destroy"
fi 