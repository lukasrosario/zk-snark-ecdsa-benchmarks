#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

echo -e "${BLUE}=== ZK-SNARK ECDSA Benchmarking Setup Check ===${NC}"
echo

# Check dependencies
echo "Checking dependencies..."

check_command() {
    if command -v "$1" &> /dev/null; then
        log "$1 is installed"
        return 0
    else
        error "$1 is not installed"
        return 1
    fi
}

DEPS_OK=true

check_command "terraform" || DEPS_OK=false
check_command "aws" || DEPS_OK=false
check_command "jq" || DEPS_OK=false
check_command "ssh" || DEPS_OK=false

if [ "$DEPS_OK" = false ]; then
    echo
    error "Missing required dependencies. Please install them first:"
    echo "  - Terraform: https://terraform.io/downloads"
    echo "  - AWS CLI: https://aws.amazon.com/cli/"
    echo "  - jq: sudo apt-get install jq (or brew install jq)"
    exit 1
fi

echo
echo "Checking AWS configuration..."

# Check AWS credentials
if aws sts get-caller-identity &> /dev/null; then
    log "AWS credentials are configured"
    
    # Display current AWS identity
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    USER=$(aws sts get-caller-identity --query Arn --output text)
    info "AWS Account: $ACCOUNT"
    info "AWS User: $USER"
else
    error "AWS credentials not configured or invalid"
    echo "Run 'aws configure' to set up your credentials"
    exit 1
fi

# Check AWS region
REGION=$(aws configure get region)
if [ -n "$REGION" ]; then
    log "AWS region configured: $REGION"
else
    warn "No default AWS region configured"
    echo "You can set it with 'aws configure set region us-east-1'"
fi

echo
echo "Checking AWS permissions..."

# Test EC2 permissions
if aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
    log "EC2 permissions are working"
else
    error "Insufficient EC2 permissions"
    echo "Ensure your AWS user/role has EC2 access"
    exit 1
fi

echo
echo "Finding your AWS network information..."

# List VPCs
echo "Available VPCs:"
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,IsDefault,Tags[?Key==`Name`].Value|[0]]' --output table

echo
echo "Example command for listing subnets in a VPC:"
echo "aws ec2 describe-subnets --filters \"Name=vpc-id,Values=vpc-xxxxxxxxx\" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table"

echo
echo "Checking for existing EC2 key pairs..."

# List key pairs
KEY_PAIRS=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text)
if [ -n "$KEY_PAIRS" ]; then
    log "Available EC2 key pairs:"
    echo "$KEY_PAIRS" | tr '\t' '\n' | sed 's/^/  - /'
else
    warn "No EC2 key pairs found"
    echo "Create one with: aws ec2 create-key-pair --key-name zk-benchmark-key --query 'KeyMaterial' --output text > ~/.ssh/zk-benchmark-key.pem"
fi

echo
echo "Checking project structure..."

# Check if we're in the right place
if [ -f "../Cargo.toml" ]; then
    log "Project structure looks correct"
else
    error "Please run this script from the ec2-benchmarks directory"
    exit 1
fi

# Check if powers of tau file exists
if [ -f "../pot22_final.ptau" ]; then
    log "Powers of tau file found"
else
    warn "Powers of tau file not found"
    echo "Download it with: curl -L \"https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau\" -o pot22_final.ptau"
fi

echo
echo -e "${GREEN}=== Setup Check Complete ===${NC}"
echo

if [ "$DEPS_OK" = true ]; then
    echo -e "${GREEN}✓ All dependencies are installed${NC}"
    echo -e "${GREEN}✓ AWS configuration is working${NC}"
    echo
    echo "You're ready to run benchmarks! Example usage:"
    echo
    echo -e "${BLUE}./deploy-and-benchmark.sh \\${NC}"
    echo -e "${BLUE}  --key-name YOUR_KEY_NAME \\${NC}"
    echo -e "${BLUE}  --subnet-id subnet-xxxxxxxxx \\${NC}"
    echo -e "${BLUE}  --vpc-id vpc-xxxxxxxxx${NC}"
    echo
    echo "Replace YOUR_KEY_NAME, subnet-xxxxxxxxx, and vpc-xxxxxxxxx with your actual values."
    echo
    echo "For help: ./deploy-and-benchmark.sh --help"
else
    echo -e "${RED}Please fix the issues above before proceeding.${NC}"
fi 