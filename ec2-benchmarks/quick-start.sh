#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}

info() {
    echo -e "${BLUE}$1${NC}"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              ZK-SNARK ECDSA EC2 Benchmarking                 ║${NC}"
echo -e "${BLUE}║                      Quick Start Guide                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

echo "This script will help you set up and run ZK-SNARK ECDSA benchmarks on EC2."
echo "The benchmarks will run on three instance types:"
echo "  • t4g.medium (ARM Graviton2, 2 vCPUs, 4GB RAM)"
echo "  • c7g.xlarge (ARM Graviton3, 4 vCPUs, 8GB RAM)"  
echo "  • c7i.2xlarge (Intel, 8 vCPUs, 16GB RAM)"
echo

# Step 1: Setup check
echo -e "${BLUE}Step 1: Checking your setup...${NC}"
echo

if ! ./setup-check.sh; then
    error "Setup check failed. Please fix the issues above and try again."
    exit 1
fi

echo
read -p "Press Enter to continue to configuration..."
echo

# Step 2: Interactive configuration
echo -e "${BLUE}Step 2: Configuration${NC}"
echo

# Get AWS region
REGION=$(aws configure get region || echo "")
if [ -z "$REGION" ]; then
    echo "Available AWS regions for EC2:"
    echo "  • us-east-1 (Virginia) - Generally lowest cost"
    echo "  • us-west-2 (Oregon)"
    echo "  • eu-west-1 (Ireland)"
    echo "  • ap-southeast-1 (Singapore)"
    echo
    read -p "Enter AWS region [us-east-1]: " REGION
    REGION=${REGION:-us-east-1}
    aws configure set region "$REGION"
fi

log "Using AWS region: $REGION"

# Get EC2 key pair
echo
echo "Available EC2 key pairs:"
KEY_PAIRS=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
if [ -n "$KEY_PAIRS" ]; then
    echo "$KEY_PAIRS" | tr '\t' '\n' | sed 's/^/  • /'
    echo
    read -p "Enter the name of your EC2 key pair: " KEY_NAME
else
    echo "  No key pairs found."
    echo
    read -p "Create a new key pair? Enter name [zk-benchmark-key]: " KEY_NAME
    KEY_NAME=${KEY_NAME:-zk-benchmark-key}
    
    echo "Creating key pair: $KEY_NAME"
    aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > ~/.ssh/${KEY_NAME}.pem
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    log "Key pair created and saved to ~/.ssh/${KEY_NAME}.pem"
fi

# Get VPC information
echo
echo "Finding your VPC and subnet..."
echo "Available VPCs:"
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,IsDefault,Tags[?Key==`Name`].Value|[0]]' --output table

echo
read -p "Enter VPC ID (vpc-xxxxxxxxx): " VPC_ID

echo
echo "Available subnets in $VPC_ID:"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table

echo
echo "Choose a PUBLIC subnet (MapPublicIpOnLaunch = True) for internet access."
read -p "Enter Subnet ID (subnet-xxxxxxxxx): " SUBNET_ID

# Get number of test cases
echo
read -p "Number of test cases to generate [10]: " TEST_CASES
TEST_CASES=${TEST_CASES:-10}

# Ask about cleanup
echo
read -p "Automatically destroy instances after benchmarks complete? [y/N]: " CLEANUP
CLEANUP=${CLEANUP:-n}

echo
echo -e "${BLUE}Step 3: Configuration Summary${NC}"
echo
echo "  AWS Region:     $REGION"
echo "  Key Pair:       $KEY_NAME"
echo "  VPC ID:         $VPC_ID"
echo "  Subnet ID:      $SUBNET_ID"
echo "  Test Cases:     $TEST_CASES"
echo "  Auto Cleanup:   $CLEANUP"

echo
echo "Estimated costs:"
echo "  • Instance costs: ~\$2-5 for 2-4 hour benchmark run"
echo "  • Storage costs: ~\$0.50/month for EBS volumes (if kept)"

echo
read -p "Proceed with deployment? [Y/n]: " PROCEED
PROCEED=${PROCEED:-y}

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Step 4: Generate test cases
echo
echo -e "${BLUE}Step 4: Generating test cases...${NC}"
cd ..

if [ ! -f "pot22_final.ptau" ]; then
    echo "Downloading powers of tau file (4.5GB)..."
    curl -L "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau" -o pot22_final.ptau
fi

echo "Generating $TEST_CASES test cases..."
cargo run --bin generate_test_cases -- --num-test-cases="$TEST_CASES"

cd ec2-benchmarks

# Step 5: Deploy and run benchmarks
echo
echo -e "${BLUE}Step 5: Deploying infrastructure and running benchmarks...${NC}"
echo

DEPLOY_ARGS="--key-name $KEY_NAME --subnet-id $SUBNET_ID --vpc-id $VPC_ID --region $REGION --test-cases $TEST_CASES"

if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
    DEPLOY_ARGS="$DEPLOY_ARGS --cleanup"
fi

echo "Running: ./deploy-and-benchmark.sh $DEPLOY_ARGS"
echo

# Show progress info
echo "This will take approximately 30-60 minutes:"
echo "  • Infrastructure deployment: ~5 minutes"
echo "  • Instance setup: ~10 minutes"
echo "  • Benchmark execution: ~30-60 minutes"
echo "  • Results collection: ~5 minutes"

echo
read -p "Start deployment? [Y/n]: " START
START=${START:-y}

if [[ ! "$START" =~ ^[Yy]$ ]]; then
    echo "You can run manually later with:"
    echo "./deploy-and-benchmark.sh $DEPLOY_ARGS"
    exit 0
fi

echo
log "Starting deployment..."
echo

# Record start time
START_TIME=$(date +%s)

# Run the deployment
./deploy-and-benchmark.sh $DEPLOY_ARGS

# Calculate total time
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
HOURS=$((TOTAL_TIME / 3600))
MINUTES=$(((TOTAL_TIME % 3600) / 60))

echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Benchmarks Complete!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

log "Total execution time: ${HOURS}h ${MINUTES}m"

# Find results directory
RESULTS_DIR=$(find . -name "collected_results_*" -type d | head -n1)
if [ -n "$RESULTS_DIR" ]; then
    echo
    log "Results available in: $RESULTS_DIR"
    echo
    echo "Key files:"
    echo "  • Cross-instance comparison: $RESULTS_DIR/cross_instance_comparison.md"
    echo "  • Individual results: $RESULTS_DIR/{t4g_medium,c7g_xlarge,c7i_2xlarge}/"
    
    if command -v open &> /dev/null; then
        read -p "Open results directory? [Y/n]: " OPEN_RESULTS
        OPEN_RESULTS=${OPEN_RESULTS:-y}
        if [[ "$OPEN_RESULTS" =~ ^[Yy]$ ]]; then
            open "$RESULTS_DIR"
        fi
    fi
fi

if [[ ! "$CLEANUP" =~ ^[Yy]$ ]]; then
    echo
    warn "Remember to destroy your EC2 instances when done:"
    warn "cd terraform && terraform destroy"
fi

echo
log "Benchmarking complete!" 