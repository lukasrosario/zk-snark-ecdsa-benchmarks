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
log "Test cases to generate: $TEST_CASES"

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
test_cases = $TEST_CASES
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
    log "Each EC2 instance will use $TEST_CASES test cases (generated during instance setup)"
    
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
    
    # Generate summary and collect only lightweight files from instances
    collect_results() {
        local ip=$1
        local instance_type=$2
        
        log "Generating summary and collecting lightweight results from $instance_type..."
        
        # Create instance-specific directory
        mkdir -p "$RESULTS_COLLECTION_DIR/$instance_type"
        
        # Create a comprehensive summary generation script on the instance
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip << 'REMOTE_SCRIPT'
            # Find the latest results directory
            LATEST_RESULTS=$(find /mnt/benchmark-data -name 'results_*' -type d | sort -r | head -n1)
            
            if [ -n "$LATEST_RESULTS" ]; then
                echo "Found results: $LATEST_RESULTS"
                
                # Create final summary directory
                SUMMARY_DIR="/tmp/benchmark_final_summary"
                rm -rf "$SUMMARY_DIR"
                mkdir -p "$SUMMARY_DIR"
                
                # Get instance info
                INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
                CPU_CORES=$(nproc)
                MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
                
                # Initialize summary data
                declare -A PROVING_TIMES
                declare -A VERIFICATION_TIMES  
                declare -A GAS_COSTS
                COMPLETED_SUITES=()
                
                echo "Processing benchmark data for each suite..."
                
                # Process each suite's results
                for suite in snarkjs rapidsnark noir gnark; do
                    if [ -d "$LATEST_RESULTS/$suite" ]; then
                        echo "Processing $suite results..."
                        
                        # Extract proving times from hyperfine JSON
                        if [ -f "$LATEST_RESULTS/$suite/benchmarks/all_proofs_benchmark.json" ]; then
                            proving_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' "$LATEST_RESULTS/$suite/benchmarks/all_proofs_benchmark.json" 2>/dev/null)
                            if [ -n "$proving_time" ] && [ "$proving_time" != "null" ]; then
                                PROVING_TIMES[$suite]=$proving_time
                                echo "  Proving time: ${proving_time}s"
                            fi
                        fi
                        
                        # Extract verification times from hyperfine JSON
                        if [ -f "$LATEST_RESULTS/$suite/benchmarks/all_verifications_benchmark.json" ]; then
                            verification_time=$(jq -r '([.results[].mean | select(. != null)] | add) / ([.results[].mean | select(. != null)] | length)' "$LATEST_RESULTS/$suite/benchmarks/all_verifications_benchmark.json" 2>/dev/null)
                            if [ -n "$verification_time" ] && [ "$verification_time" != "null" ]; then
                                VERIFICATION_TIMES[$suite]=$verification_time
                                echo "  Verification time: ${verification_time}s"
                            fi
                        fi
                        
                        # Extract gas costs
                        gas_cost=""
                        if [ "$suite" = "noir" ] && [ -f "$LATEST_RESULTS/$suite/gas/gas_benchmark_summary.json" ]; then
                            gas_cost=$(jq -r '[.results[].gas_used] | add / length' "$LATEST_RESULTS/$suite/gas/gas_benchmark_summary.json" 2>/dev/null)
                        elif [ -f "$LATEST_RESULTS/$suite/gas-reports/reports/all_gas_data.json" ]; then
                            gas_cost=$(jq -r '[.results[].mean] | add / length' "$LATEST_RESULTS/$suite/gas-reports/reports/all_gas_data.json" 2>/dev/null)
                        fi
                        
                        if [ -n "$gas_cost" ] && [ "$gas_cost" != "null" ]; then
                            GAS_COSTS[$suite]=$gas_cost
                            echo "  Gas cost: ${gas_cost} gas"
                        fi
                        
                        COMPLETED_SUITES+=($suite)
                    fi
                done
                
                echo "Generating comprehensive summary report..."
                
                # Generate comprehensive markdown report
                cat > "$SUMMARY_DIR/performance_summary.md" << EOF
# ZK-SNARK ECDSA Benchmark Results

**Instance:** $INSTANCE_TYPE  
**CPU Cores:** $CPU_CORES  
**Memory:** ${MEMORY_GB}GB  
**Date:** $(date)

## Performance Summary

EOF
                
                for suite in "${COMPLETED_SUITES[@]}"; do
                    echo "### $suite" >> "$SUMMARY_DIR/performance_summary.md"
                    echo "" >> "$SUMMARY_DIR/performance_summary.md"
                    
                    if [ -n "${PROVING_TIMES[$suite]}" ]; then
                        printf "- **Proving Time:** %.3fs\n" "${PROVING_TIMES[$suite]}" >> "$SUMMARY_DIR/performance_summary.md"
                    fi
                    
                    if [ -n "${VERIFICATION_TIMES[$suite]}" ]; then
                        printf "- **Verification Time:** %.3fs\n" "${VERIFICATION_TIMES[$suite]}" >> "$SUMMARY_DIR/performance_summary.md"
                    fi
                    
                    if [ -n "${GAS_COSTS[$suite]}" ]; then
                        printf "- **Gas Cost:** %.0f gas\n" "${GAS_COSTS[$suite]}" >> "$SUMMARY_DIR/performance_summary.md"
                    fi
                    
                    echo "" >> "$SUMMARY_DIR/performance_summary.md"
                done
                
                # Generate JSON summary for plotting
                cat > "$SUMMARY_DIR/performance_data.json" << EOF
{
  "instance_type": "$INSTANCE_TYPE",
  "cpu_cores": $CPU_CORES,
  "memory_gb": $MEMORY_GB,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "proving_times": {
EOF
                
                first=true
                for suite in "${COMPLETED_SUITES[@]}"; do
                    if [ -n "${PROVING_TIMES[$suite]}" ]; then
                        if [ "$first" = false ]; then
                            echo "," >> "$SUMMARY_DIR/performance_data.json"
                        fi
                        printf "    \"%s\": %.3f" "$suite" "${PROVING_TIMES[$suite]}" >> "$SUMMARY_DIR/performance_data.json"
                        first=false
                    fi
                done
                
                cat >> "$SUMMARY_DIR/performance_data.json" << EOF

  },
  "verification_times": {
EOF
                
                first=true
                for suite in "${COMPLETED_SUITES[@]}"; do
                    if [ -n "${VERIFICATION_TIMES[$suite]}" ]; then
                        if [ "$first" = false ]; then
                            echo "," >> "$SUMMARY_DIR/performance_data.json"
                        fi
                        printf "    \"%s\": %.3f" "$suite" "${VERIFICATION_TIMES[$suite]}" >> "$SUMMARY_DIR/performance_data.json"
                        first=false
                    fi
                done
                
                cat >> "$SUMMARY_DIR/performance_data.json" << EOF

  },
  "gas_costs": {
EOF
                
                first=true
                for suite in "${COMPLETED_SUITES[@]}"; do
                    if [ -n "${GAS_COSTS[$suite]}" ]; then
                        if [ "$first" = false ]; then
                            echo "," >> "$SUMMARY_DIR/performance_data.json"
                        fi
                        printf "    \"%s\": %.0f" "$suite" "${GAS_COSTS[$suite]}" >> "$SUMMARY_DIR/performance_data.json"
                        first=false
                    fi
                done
                
                cat >> "$SUMMARY_DIR/performance_data.json" << EOF

  }
}
EOF
                
                # Generate plots if Python is available
                if command -v python3 &> /dev/null; then
                    echo "Generating performance plots..."
                    
                    cat > "$SUMMARY_DIR/generate_plots.py" << 'PLOT_EOF'
#!/usr/bin/env python3
import json
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Set up matplotlib for headless operation
plt.switch_backend('Agg')

# Load performance data
with open('performance_data.json') as f:
    data = json.load(f)

instance_type = data['instance_type']
proving_times = data['proving_times']
verification_times = data['verification_times']
gas_costs = data['gas_costs']

# Generate proving times plot
if proving_times:
    suites = list(proving_times.keys())
    times = list(proving_times.values())
    
    plt.figure(figsize=(10, 6))
    bars = plt.bar(suites, times, alpha=0.8, color=['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728'])
    plt.xlabel('ZK-SNARK Suite')
    plt.ylabel('Proving Time (seconds)')
    plt.title(f'ZK-SNARK Proving Times - {instance_type}')
    plt.xticks(rotation=45)
    plt.grid(True, alpha=0.3)
    
    # Add value labels on bars
    for bar, time in zip(bars, times):
        plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(times)*0.01,
                f'{time:.3f}s', ha='center', va='bottom')
    
    plt.tight_layout()
    plt.savefig('proving_times.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated proving_times.png")

# Generate verification times plot
if verification_times:
    suites = list(verification_times.keys())
    times = list(verification_times.values())
    
    plt.figure(figsize=(10, 6))
    bars = plt.bar(suites, times, alpha=0.8, color=['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728'])
    plt.xlabel('ZK-SNARK Suite')
    plt.ylabel('Verification Time (seconds)')
    plt.title(f'ZK-SNARK Verification Times - {instance_type}')
    plt.xticks(rotation=45)
    plt.grid(True, alpha=0.3)
    
    # Add value labels on bars
    for bar, time in zip(bars, times):
        plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(times)*0.01,
                f'{time:.3f}s', ha='center', va='bottom')
    
    plt.tight_layout()
    plt.savefig('verification_times.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated verification_times.png")

# Generate gas costs plot
if gas_costs:
    suites = list(gas_costs.keys())
    costs = list(gas_costs.values())
    
    plt.figure(figsize=(10, 6))
    bars = plt.bar(suites, costs, alpha=0.8, color=['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728'])
    plt.xlabel('ZK-SNARK Suite')
    plt.ylabel('Gas Consumption')
    plt.title(f'ZK-SNARK Gas Consumption - {instance_type}')
    plt.xticks(rotation=45)
    plt.grid(True, alpha=0.3)
    plt.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))
    
    # Add value labels on bars
    for bar, cost in zip(bars, costs):
        plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(costs)*0.01,
                f'{cost:.0f}', ha='center', va='bottom')
    
    plt.tight_layout()
    plt.savefig('gas_consumption.png', dpi=300, bbox_inches='tight')
    plt.close()
    print("Generated gas_consumption.png")

print("Plot generation completed!")
PLOT_EOF
                    
                    cd "$SUMMARY_DIR"
                    if python3 generate_plots.py 2>/dev/null; then
                        echo "Performance plots generated successfully!"
                        rm generate_plots.py  # Clean up
                    else
                        echo "Plot generation failed - continuing without plots"
                    fi
                    cd -
                else
                    echo "Python3 not available - skipping plot generation"
                fi
                
                echo "Final summary generation complete"
                echo "Generated files:"
                ls -la "$SUMMARY_DIR/"
                
            else
                echo "No results directory found"
            fi
REMOTE_SCRIPT
        
        # Copy only the final summary files
        if scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no -r \
            ubuntu@$ip:"/tmp/benchmark_final_summary/*" \
            "$RESULTS_COLLECTION_DIR/$instance_type/" 2>/dev/null; then
            log "Final summary and plots collected from $instance_type"
        else
            warn "Failed to collect summary from $instance_type"
        fi
        
        # Clean up remote temporary directory
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip \
            "rm -rf /tmp/benchmark_final_summary" 2>/dev/null || true
    }
    
    # Collect results from all instances
    collect_results "$T4G_IP" "t4g_medium"
    collect_results "$C7G_IP" "c7g_xlarge"
    collect_results "$C7I_2X_IP" "c7i_2xlarge"
    collect_results "$C7I_4X_IP" "c7i_4xlarge"
    
    # Create a simple index of all collected results
    log "Creating results index..."
    
    cat > "$RESULTS_COLLECTION_DIR/README.md" << 'EOF'
# ZK-SNARK ECDSA Benchmark Results

This directory contains comprehensive benchmark results from multiple EC2 instance types.

## Instance Types Tested

- **t4g.medium**: ARM Graviton2, 2 vCPUs, 4GB RAM
- **c7g.xlarge**: ARM Graviton3, 4 vCPUs, 8GB RAM  
- **c7i.2xlarge**: Intel, 8 vCPUs, 16GB RAM
- **c7i.4xlarge**: Intel, 16 vCPUs, 32GB RAM

## Results Structure

Each instance directory contains:
- `performance_summary.md` - Detailed performance report
- `performance_data.json` - Raw performance data in JSON format
- `proving_times.png` - Proving times visualization
- `verification_times.png` - Verification times visualization
- `gas_consumption.png` - Gas consumption visualization

## Instance Results

EOF
    
    # Add links to each instance's results
    for instance_type in t4g_medium c7g_xlarge c7i_2xlarge c7i_4xlarge; do
        if [ -d "$RESULTS_COLLECTION_DIR/$instance_type" ]; then
            echo "### [$instance_type](./$instance_type/)" >> "$RESULTS_COLLECTION_DIR/README.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/README.md"
            
            if [ -f "$RESULTS_COLLECTION_DIR/$instance_type/performance_summary.md" ]; then
                echo "- [Performance Summary](./$instance_type/performance_summary.md)" >> "$RESULTS_COLLECTION_DIR/README.md"
            fi
            
            if [ -f "$RESULTS_COLLECTION_DIR/$instance_type/performance_data.json" ]; then
                echo "- [Raw Data](./$instance_type/performance_data.json)" >> "$RESULTS_COLLECTION_DIR/README.md"
            fi
            
            # List available plots
            for plot in proving_times.png verification_times.png gas_consumption.png; do
                if [ -f "$RESULTS_COLLECTION_DIR/$instance_type/$plot" ]; then
                    echo "- [$(echo $plot | sed 's/_/ /g' | sed 's/.png//')](./$instance_type/$plot)" >> "$RESULTS_COLLECTION_DIR/README.md"
                fi
            done
            
            echo "" >> "$RESULTS_COLLECTION_DIR/README.md"
        fi
    done
    
    echo "Generated at: $(date)" >> "$RESULTS_COLLECTION_DIR/README.md"
    
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
    log "View the results index at: $RESULTS_COLLECTION_DIR/README.md"
    log ""
    log "Each instance directory contains:"
    log "  - performance_summary.md (detailed report)"
    log "  - performance_data.json (raw data)"
    log "  - proving_times.png (performance plots)"
    log "  - verification_times.png (performance plots)"
    log "  - gas_consumption.png (performance plots)"
fi

if [ "$CLEANUP" = false ] && [ "$SKIP_DEPLOY" = false ]; then
    echo
    warn "EC2 instances are still running. Don't forget to destroy them when done:"
    warn "cd $SCRIPT_DIR/terraform && terraform destroy"
fi 