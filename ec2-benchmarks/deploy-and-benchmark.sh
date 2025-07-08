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
    --skip-reports          Skip report generation (just collect raw data)
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
    
    # Run benchmarks without generating reports
    $0 -k my-key -s subnet-123456 -v vpc-123456 --skip-reports
    
    # Full cycle with cleanup
    $0 -k my-key -s subnet-123456 -v vpc-123456 --cleanup

EOF
}

# Default values
AWS_REGION="us-east-1"
TEST_CASES=10
SKIP_DEPLOY=false
SKIP_BENCHMARKS=false
SKIP_REPORTS=false
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
        --skip-reports)
            SKIP_REPORTS=true
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
    C7I_8X_IP=$(terraform output -json instance_info | jq -r '.c7i_8xlarge.public_ip')
    
    log "Instances deployed:"
    log "  t4g.medium:   $T4G_IP"
    log "  c7g.xlarge:   $C7G_IP"
    log "  c7i.2xlarge:  $C7I_2X_IP"
    log "  c7i.4xlarge:  $C7I_4X_IP"
    log "  c7i.8xlarge:  $C7I_8X_IP"
    
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
    wait_for_instance "$C7I_8X_IP" "c7i.8xlarge" &
    
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
        C7I_8X_IP=$(jq -r '.instance_info.value.c7i_8xlarge.public_ip' ../instance_outputs.json)
        
        log "Using existing instances:"
        log "  t4g.medium:   $T4G_IP"
        log "  c7g.xlarge:   $C7G_IP"
        log "  c7i.2xlarge:  $C7I_2X_IP"
        log "  c7i.4xlarge:  $C7I_4X_IP"
        log "  c7i.8xlarge:  $C7I_8X_IP"
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
    run_benchmark_on_instance "$C7I_8X_IP" "c7i_8xlarge"
    run_benchmark_on_instance "$C7I_4X_IP" "c7i_4xlarge"
    run_benchmark_on_instance "$C7I_2X_IP" "c7i_2xlarge"
    
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
        
        log "Generating summary and collecting results from $instance_type..."
        
        # Create instance-specific directory
        mkdir -p "$RESULTS_COLLECTION_DIR/$instance_type"
        
        # Create a comprehensive summary generation script on the instance
        ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip << 'REMOTE_SCRIPT'
            LATEST_RESULTS=$(find /mnt/benchmark-data -name 'results_*' -type d | sort -r | head -n1)
            if [ -z "$LATEST_RESULTS" ]; then echo "No results found"; exit 1; fi
            
            SUMMARY_DIR="/tmp/benchmark_final_summary"
            rm -rf "$SUMMARY_DIR" && mkdir -p "$SUMMARY_DIR"
            
            INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
            CPU_CORES=$(nproc)
            MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
            
            # --- Start JSON generation ---
            echo "{" > "$SUMMARY_DIR/performance_data.json"
            echo "  \"instance_type\": \"$INSTANCE_TYPE\"," >> "$SUMMARY_DIR/performance_data.json"
            echo "  \"cpu_cores\": $CPU_CORES," >> "$SUMMARY_DIR/performance_data.json"
            echo "  \"memory_gb\": $MEMORY_GB," >> "$SUMMARY_DIR/performance_data.json"
            echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$SUMMARY_DIR/performance_data.json"
            
            # --- Proving Times ---
            echo "  \"proving_times\": {" >> "$SUMMARY_DIR/performance_data.json"
            temp_entries_proving=$(mktemp)
            for suite in snarkjs rapidsnark noir gnark; do
                if [ -f "$LATEST_RESULTS/$suite/benchmarks/all_proofs_benchmark.json" ]; then
                    avg_time=$(jq -r '[.results[].mean] | add / length' "$LATEST_RESULTS/$suite/benchmarks/all_proofs_benchmark.json" 2>/dev/null)
                    if [ -n "$avg_time" ] && [ "$avg_time" != "null" ]; then
                        echo "    \"$suite\": $avg_time" >> "$temp_entries_proving"
                    fi
                fi
            done
            if [ -s "$temp_entries_proving" ]; then
                sed '$!s/$/,/' "$temp_entries_proving" >> "$SUMMARY_DIR/performance_data.json"
            fi
            rm "$temp_entries_proving"
            echo "  }," >> "$SUMMARY_DIR/performance_data.json"

            # --- Gas Costs ---
            echo "  \"gas_costs\": {" >> "$SUMMARY_DIR/performance_data.json"
            temp_entries_gas=$(mktemp)
            for suite in snarkjs rapidsnark noir gnark; do
                 gas_file_snarkjs_rapidsnark="$LATEST_RESULTS/$suite/gas-reports/reports/all_gas_data.json"
                 gas_file_noir="$LATEST_RESULTS/$suite/gas/gas_benchmark_summary.json"
                 avg_gas=""
                 if [ -f "$gas_file_snarkjs_rapidsnark" ]; then
                    avg_gas=$(jq -r '[.results[].mean] | add / length' "$gas_file_snarkjs_rapidsnark" 2>/dev/null)
                 elif [ -f "$gas_file_noir" ]; then
                    avg_gas=$(jq -r '[.results[].gas_used] | add / length' "$gas_file_noir" 2>/dev/null)
                 fi
                 if [ -n "$avg_gas" ] && [ "$avg_gas" != "null" ]; then
                    echo "    \"$suite\": $avg_gas" >> "$temp_entries_gas"
                 fi
            done
            if [ -s "$temp_entries_gas" ]; then
                sed '$!s/$/,/' "$temp_entries_gas" >> "$SUMMARY_DIR/performance_data.json"
            fi
            rm "$temp_entries_gas"
            echo "  }," >> "$SUMMARY_DIR/performance_data.json"

            # --- Raw Data ---
            echo "  \"raw_data\": {" >> "$SUMMARY_DIR/performance_data.json"
            temp_raw_entries=$(mktemp)
            for suite in snarkjs rapidsnark noir gnark; do
                if [ -d "$LATEST_RESULTS/$suite" ]; then
                    echo "    \"$suite\": {" >> "$temp_raw_entries"
                    
                    # Raw proving times
                    proving_times_raw=$(jq -r '[.results[].mean] | map(select(. != null)) | join(",")' "$LATEST_RESULTS/$suite/benchmarks/all_proofs_benchmark.json" 2>/dev/null || echo "")
                    echo "      \"proving_times\": [$proving_times_raw]," >> "$temp_raw_entries"

                    # Raw gas costs
                    gas_file_snarkjs_rapidsnark="$LATEST_RESULTS/$suite/gas-reports/reports/all_gas_data.json"
                    gas_file_noir="$LATEST_RESULTS/$suite/gas/gas_benchmark_summary.json"
                    gas_costs_raw=""
                    if [ -f "$gas_file_snarkjs_rapidsnark" ]; then
                        gas_costs_raw=$(jq -r '[.results[].mean] | map(select(. != null)) | join(",")' "$gas_file_snarkjs_rapidsnark" 2>/dev/null || echo "")
                    elif [ -f "$gas_file_noir" ]; then
                        gas_costs_raw=$(jq -r '[.results[].gas_used] | map(select(. != null)) | join(",")' "$gas_file_noir" 2>/dev/null || echo "")
                    fi
                    echo "      \"gas_costs\": [$gas_costs_raw]" >> "$temp_raw_entries"

                    echo "    }" >> "$temp_raw_entries"
                fi
            done
            if [ -s "$temp_raw_entries" ]; then
                sed '$!s/^\(    }\)$/\1,/' "$temp_raw_entries" >> "$SUMMARY_DIR/performance_data.json"
            fi
            rm "$temp_raw_entries"
            echo "  }" >> "$SUMMARY_DIR/performance_data.json"
            
            echo "}" >> "$SUMMARY_DIR/performance_data.json"
            # --- End JSON generation ---
REMOTE_SCRIPT
        
        # Generate reports on the VM if not skipping reports
        if [ "$SKIP_REPORTS" = false ]; then
            log "Generating reports on $instance_type..."
            
            # Copy the generate_reports.py script to the VM and run it
            scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no \
                "$SCRIPT_DIR/generate_reports.py" \
                ubuntu@$ip:/tmp/
            
            # Run the report generation on the VM
            ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$ip \
                "cd /tmp && python3 generate_reports.py benchmark_final_summary/performance_data.json"
        fi
        
        # Copy the generated summary files and reports
        scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no -r \
            ubuntu@$ip:"/tmp/benchmark_final_summary/*" \
            "$RESULTS_COLLECTION_DIR/$instance_type/"
        
        # Copy any generated PNG files if reports were created
        if [ "$SKIP_REPORTS" = false ]; then
            scp -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no \
                ubuntu@$ip:"/tmp/*.png" \
                "$RESULTS_COLLECTION_DIR/$instance_type/" 2>/dev/null || true
        fi
        
        log "Results and summary collected from $instance_type"
    }

    # Collect results from all instances
    for instance_info in $(jq -c '.instance_info.value | to_entries[]' ../instance_outputs.json); do
        instance_type=$(echo "$instance_info" | jq -r '.key')
        ip=$(echo "$instance_info" | jq -r '.value.public_ip')
        collect_results "$ip" "$instance_type"
    done
    
    log "All results collected and processed!"
    
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
    
    if [ "$SKIP_REPORTS" = false ]; then
        log ""
        log "Each instance directory contains:"
        log "  - performance_summary.md (detailed report)"
        log "  - performance_data.json (raw data)"
        log "  - proving_times.png (performance plots)"
        log "  - verification_times.png (performance plots)"
        log "  - gas_consumption.png (performance plots)"
    else
        log ""
        log "Raw data collected. Each instance directory contains:"
        log "  - performance_data.json (raw benchmark data)"
        log ""
        log "To generate reports later, you can run on any VM or locally:"
        log "  python3 $SCRIPT_DIR/generate_reports.py <path_to_performance_data.json>"
    fi
fi

if [ "$CLEANUP" = false ] && [ "$SKIP_DEPLOY" = false ]; then
    echo
    warn "EC2 instances are still running. Don't forget to destroy them when done:"
    warn "cd $SCRIPT_DIR/terraform && terraform destroy"
fi 