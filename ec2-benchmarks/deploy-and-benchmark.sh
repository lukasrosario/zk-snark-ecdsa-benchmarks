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
    
    # Generate summary and collect only lightweight files from instances
    collect_results() {
        local ip=$1
        local instance_type=$2
        
        log "Generating summary and collecting lightweight results from $instance_type..."
        
        # Create instance-specific directory
        mkdir -p "$RESULTS_COLLECTION_DIR/$instance_type"
        
        # Create a summary generation script on the instance
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip << 'REMOTE_SCRIPT'
            # Find the latest results directory
            LATEST_RESULTS=$(find /mnt/benchmark-data -name 'results_*' -type d | sort -r | head -n1)
            
            if [ -n "$LATEST_RESULTS" ]; then
                echo "Found results: $LATEST_RESULTS"
                
                # Copy key summary files to a lightweight collection directory
                SUMMARY_DIR="/tmp/benchmark_summary"
                mkdir -p "$SUMMARY_DIR"
                
                # Copy essential files
                cp "$LATEST_RESULTS/summary.json" "$SUMMARY_DIR/" 2>/dev/null || echo "No summary.json"
                cp "$LATEST_RESULTS/system_info.json" "$SUMMARY_DIR/" 2>/dev/null || echo "No system_info.json"
                cp "$LATEST_RESULTS/performance_comparison.md" "$SUMMARY_DIR/" 2>/dev/null || echo "No performance_comparison.md"
                
                # Extract key benchmark metrics from each suite
                for suite in snarkjs rapidsnark noir gnark; do
                    if [ -d "$LATEST_RESULTS/$suite" ]; then
                        mkdir -p "$SUMMARY_DIR/$suite"
                        
                        # Copy benchmark summary files (small JSON files with timing data)
                        find "$LATEST_RESULTS/$suite" -name "*benchmark*.json" -size -1M -exec cp {} "$SUMMARY_DIR/$suite/" \; 2>/dev/null
                        
                        # Copy gas reports (typically small)
                        if [ -d "$LATEST_RESULTS/$suite/gas-reports/reports" ]; then
                            mkdir -p "$SUMMARY_DIR/$suite/gas-reports"
                            cp -r "$LATEST_RESULTS/$suite/gas-reports/reports" "$SUMMARY_DIR/$suite/gas-reports/" 2>/dev/null
                        fi
                        
                        echo "Collected $suite summaries"
                    fi
                done
                
                echo "Summary collection complete"
            else
                echo "No results directory found"
            fi
REMOTE_SCRIPT
        
        # Copy the lightweight summary files
        if scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no -r \
            ubuntu@$ip:"/tmp/benchmark_summary/*" \
            "$RESULTS_COLLECTION_DIR/$instance_type/" 2>/dev/null; then
            log "Lightweight results collected from $instance_type"
        else
            warn "Failed to collect summary from $instance_type"
        fi
        
        # Clean up remote temporary directory
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip \
            "rm -rf /tmp/benchmark_summary" 2>/dev/null || true
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
        # Check both the expected location and debug what's actually there
        SUMMARY_FILE="$RESULTS_COLLECTION_DIR/$instance_type/summary.json"
        
        if [ -f "$SUMMARY_FILE" ]; then
            echo "### $instance_type" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            
            cpu_cores=$(jq -r '.cpu_cores' "$SUMMARY_FILE" 2>/dev/null || echo "unknown")
            memory_gb=$(jq -r '.memory_gb' "$SUMMARY_FILE" 2>/dev/null || echo "unknown")
            total_duration=$(jq -r '.total_duration_seconds' "$SUMMARY_FILE" 2>/dev/null || echo "unknown")
            completed_suites=$(jq -r '.suites_completed[]?' "$SUMMARY_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            skipped_suites=$(jq -r '.suites_skipped[]?' "$SUMMARY_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            
            echo "- **CPU Cores**: $cpu_cores" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "- **Memory**: ${memory_gb}GB" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "- **Total Duration**: ${total_duration}s" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            [ -n "$completed_suites" ] && echo "- **Completed Suites**: $completed_suites" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            [ -n "$skipped_suites" ] && echo "- **Skipped Suites**: $skipped_suites" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
        else
            # Debug: show what's actually in the directory
            echo "### $instance_type" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            echo "⚠️ **Summary file not found at**: \`$SUMMARY_FILE\`" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            
            if [ -d "$RESULTS_COLLECTION_DIR/$instance_type" ]; then
                echo "**Available files:**" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
                ls -la "$RESULTS_COLLECTION_DIR/$instance_type/" | sed 's/^/- /' >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            else
                echo "**Directory not found**: \`$RESULTS_COLLECTION_DIR/$instance_type\`" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
            fi
            echo "" >> "$RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
        fi
    done
    
    log "Cross-instance comparison saved to: $RESULTS_COLLECTION_DIR/cross_instance_comparison.md"
    log "All results collected in: $RESULTS_COLLECTION_DIR"
    
    # Generate performance plots (optional - won't break if it fails)
    log "Attempting to generate performance plots..."
    generate_plots() {
        # Check if Python and required libraries are available
        if ! command -v python3 &> /dev/null; then
            warn "Python3 not found - skipping plot generation"
            return 1
        fi
        
        # Create a Python script for plotting
        cat > "$RESULTS_COLLECTION_DIR/generate_plots.py" << 'PLOT_SCRIPT'
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

try:
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError:
    print("matplotlib not available - skipping plots")
    sys.exit(1)

# Set up matplotlib for headless operation
plt.switch_backend('Agg')

def extract_proving_times(results_dir):
    """Extract proving times from benchmark results."""
    proving_times = {}
    
    for instance_dir in Path(results_dir).iterdir():
        if not instance_dir.is_dir():
            continue
            
        instance_name = instance_dir.name
        proving_times[instance_name] = {}
        
        # Look for benchmark files in each suite
        for suite in ['snarkjs', 'rapidsnark', 'noir', 'gnark']:
            suite_dir = instance_dir / suite / 'benchmarks'
            if suite_dir.exists():
                # Look for proof benchmark files
                for benchmark_file in suite_dir.glob('*proof*benchmark*.json'):
                    try:
                        with open(benchmark_file) as f:
                            data = json.load(f)
                            if 'results' in data:
                                # Extract timing data
                                times = []
                                for result in data['results']:
                                    if 'times' in result:
                                        times.extend(result['times'])
                                    elif 'time' in result:
                                        times.append(result['time'])
                                    elif 'elapsed' in result:
                                        times.append(result['elapsed'])
                                
                                if times:
                                    proving_times[instance_name][suite] = {
                                        'mean': np.mean(times),
                                        'median': np.median(times),
                                        'times': times
                                    }
                    except Exception as e:
                        print(f"Error reading {benchmark_file}: {e}")
    
    return proving_times

def extract_gas_consumption(results_dir):
    """Extract gas consumption from gas reports."""
    gas_data = {}
    
    for instance_dir in Path(results_dir).iterdir():
        if not instance_dir.is_dir():
            continue
            
        instance_name = instance_dir.name
        gas_data[instance_name] = {}
        
        # Look for gas reports in each suite
        for suite in ['snarkjs', 'rapidsnark', 'noir', 'gnark']:
            gas_reports_dir = instance_dir / suite / 'gas-reports' / 'reports'
            if gas_reports_dir.exists():
                for report_file in gas_reports_dir.glob('*.json'):
                    try:
                        with open(report_file) as f:
                            data = json.load(f)
                            
                            # Extract gas usage data
                            if 'verification_gas' in data:
                                gas_data[instance_name][suite] = data['verification_gas']
                            elif 'gas_used' in data:
                                gas_data[instance_name][suite] = data['gas_used']
                            elif isinstance(data, dict) and 'gasUsed' in str(data):
                                # Try to find gas usage in nested structure
                                for key, value in data.items():
                                    if isinstance(value, dict) and 'gasUsed' in value:
                                        gas_data[instance_name][suite] = value['gasUsed']
                                        break
                    except Exception as e:
                        print(f"Error reading {report_file}: {e}")
    
    return gas_data

def plot_proving_times(proving_times, output_dir):
    """Generate proving time comparison plots."""
    if not proving_times:
        print("No proving time data found")
        return
    
    # Collect data for plotting
    instances = list(proving_times.keys())
    suites = set()
    for instance_data in proving_times.values():
        suites.update(instance_data.keys())
    suites = sorted(list(suites))
    
    if not suites:
        print("No suite data found for proving times")
        return
    
    # Create bar plot
    fig, ax = plt.subplots(figsize=(12, 8))
    
    x = np.arange(len(instances))
    width = 0.8 / len(suites)
    
    for i, suite in enumerate(suites):
        times = []
        for instance in instances:
            if suite in proving_times[instance]:
                times.append(proving_times[instance][suite]['mean'])
            else:
                times.append(0)
        
        ax.bar(x + i * width, times, width, label=suite, alpha=0.8)
    
    ax.set_xlabel('Instance Type')
    ax.set_ylabel('Proving Time (seconds)')
    ax.set_title('ZK-SNARK Proving Time Comparison Across Instances')
    ax.set_xticks(x + width * (len(suites) - 1) / 2)
    ax.set_xticklabels(instances, rotation=45)
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'proving_times_comparison.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"Proving times plot saved to {output_dir / 'proving_times_comparison.png'}")

def plot_gas_consumption(gas_data, output_dir):
    """Generate gas consumption comparison plots."""
    if not gas_data:
        print("No gas consumption data found")
        return
    
    # Collect data for plotting
    instances = list(gas_data.keys())
    suites = set()
    for instance_data in gas_data.values():
        suites.update(instance_data.keys())
    suites = sorted(list(suites))
    
    if not suites:
        print("No suite data found for gas consumption")
        return
    
    # Create bar plot
    fig, ax = plt.subplots(figsize=(12, 8))
    
    x = np.arange(len(instances))
    width = 0.8 / len(suites)
    
    for i, suite in enumerate(suites):
        gas_values = []
        for instance in instances:
            if suite in gas_data[instance]:
                gas_values.append(gas_data[instance][suite])
            else:
                gas_values.append(0)
        
        ax.bar(x + i * width, gas_values, width, label=suite, alpha=0.8)
    
    ax.set_xlabel('Instance Type')
    ax.set_ylabel('Gas Consumption')
    ax.set_title('ZK-SNARK Verification Gas Consumption Across Instances')
    ax.set_xticks(x + width * (len(suites) - 1) / 2)
    ax.set_xticklabels(instances, rotation=45)
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    # Format y-axis for large numbers
    ax.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))
    
    plt.tight_layout()
    plt.savefig(output_dir / 'gas_consumption_comparison.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"Gas consumption plot saved to {output_dir / 'gas_consumption_comparison.png'}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 generate_plots.py <results_directory>")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    
    print("Extracting proving times...")
    proving_times = extract_proving_times(results_dir)
    
    print("Extracting gas consumption data...")
    gas_data = extract_gas_consumption(results_dir)
    
    print("Generating plots...")
    plot_proving_times(proving_times, results_dir)
    plot_gas_consumption(gas_data, results_dir)
    
    print("Plot generation completed!")

if __name__ == "__main__":
    main()
PLOT_SCRIPT
        
        # Run the plotting script
        if python3 "$RESULTS_COLLECTION_DIR/generate_plots.py" "$RESULTS_COLLECTION_DIR" 2>/dev/null; then
            log "Performance plots generated successfully!"
            log "  - Proving times: $RESULTS_COLLECTION_DIR/proving_times_comparison.png"
            log "  - Gas consumption: $RESULTS_COLLECTION_DIR/gas_consumption_comparison.png"
        else
            warn "Plot generation failed - continuing without plots"
        fi
        
        # Clean up the script
        rm -f "$RESULTS_COLLECTION_DIR/generate_plots.py"
    }
    
    # Try to generate plots (non-blocking)
    generate_plots || warn "Plot generation skipped"
    
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