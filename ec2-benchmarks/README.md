# EC2 ZK-SNARK ECDSA Benchmarking Suite

This directory contains infrastructure-as-code and automation scripts to run your ZK-SNARK ECDSA benchmarks on various AWS EC2 instance types. The setup provisions EC2 instances, configures them for optimal performance, runs all benchmark suites in parallel, and collects results for analysis.

## Instance Types

The benchmarking suite targets five different EC2 instance types to compare performance across different CPU architectures and specifications:

- **t4g.medium**: ARM Graviton2, 2 vCPUs, 4GB RAM - Cost-effective ARM testing
- **c7g.xlarge**: ARM Graviton3, 4 vCPUs, 8GB RAM - High-performance ARM 
- **c7i.2xlarge**: Intel, 8 vCPUs, 16GB RAM - High-performance x86 (small)
- **c7i.4xlarge**: Intel, 16 vCPUs, 32GB RAM - High-performance x86 (medium)
- **c7i.8xlarge**: Intel, 32 vCPUs, 64GB RAM - High-performance x86 (large)

## Prerequisites

### 1. Install Dependencies

```bash
# Terraform (for infrastructure management)
# Install from: https://terraform.io/downloads

# AWS CLI (for AWS access)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# jq (for JSON processing)
sudo apt-get install jq  # Ubuntu/Debian
# or
brew install jq  # macOS
```

### 2. Configure AWS

```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

### 3. Set Up EC2 Key Pair

Create an EC2 key pair for SSH access:

```bash
# Create key pair in AWS Console or via CLI
aws ec2 create-key-pair --key-name zk-benchmark-key --query 'KeyMaterial' --output text > ~/.ssh/zk-benchmark-key.pem
chmod 400 ~/.ssh/zk-benchmark-key.pem
```

### 4. Network Information

You'll need the following AWS network information:
- VPC ID (where instances will be deployed)
- Subnet ID (public subnet for internet access)

Find these in the AWS Console or use CLI:

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,IsDefault]' --output table

# List subnets in a VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone]' --output table
```

## Quick Start

### 1. Basic Deployment and Benchmarking

```bash
# Navigate to ec2-benchmarks directory
cd ec2-benchmarks

# Deploy infrastructure and run benchmarks
./deploy-and-benchmark.sh \
  --key-name zk-benchmark-key \
  --subnet-id subnet-xxxxxxxxx \
  --vpc-id vpc-xxxxxxxxx
```

This will:
1. Deploy 5 EC2 instances with attached EBS volumes
2. Wait for instances to complete setup
3. Run all 4 benchmark suites (snarkjs, rapidsnark, noir, gnark) on each instance
4. Collect results from all instances
5. Generate comparison reports

### 2. Custom Configuration

```bash
# Use different region and more test cases
./deploy-and-benchmark.sh \
  --key-name my-key \
  --subnet-id subnet-123456 \
  --vpc-id vpc-123456 \
  --region us-west-2 \
  --test-cases 20
```

### 3. Deploy Only (No Benchmarks)

```bash
# Deploy infrastructure without running benchmarks
./deploy-and-benchmark.sh \
  --key-name my-key \
  --subnet-id subnet-123456 \
  --vpc-id vpc-123456 \
  --skip-benchmarks
```

### 4. Run Benchmarks on Existing Instances

```bash
# Run benchmarks on previously deployed instances
./deploy-and-benchmark.sh --skip-deploy
```

### 5. Full Cycle with Cleanup

```bash
# Deploy, benchmark, and cleanup automatically
./deploy-and-benchmark.sh \
  --key-name my-key \
  --subnet-id subnet-123456 \
  --vpc-id vpc-123456 \
  --cleanup
```

## Performance Optimizations

The setup includes several optimizations to maximize CPU and RAM utilization:

### Docker Configuration
- CPU allocation: Uses all available CPU cores (`--cpus=${CPU_CORES}`)
- Memory allocation: Adaptive based on instance RAM (leaves headroom for system)
- Shared memory: 1GB for cryptographic operations
- Memory swap: Configured to match memory limit

### System Tuning
- CPU governor set to "performance" mode
- VM swappiness reduced to minimize swap usage
- Memory overcommit enabled for large allocations
- Kernel scheduler migration cost optimized

### Instance-Specific Settings
- **t4g.medium (4GB RAM)**: Docker limited to 3GB, 2 CPU cores
- **c7g.xlarge (8GB RAM)**: Docker limited to 6GB, 4 CPU cores  
- **c7i.2xlarge (16GB RAM)**: Docker limited to 14GB, 8 CPU cores
- **c7i.4xlarge (32GB RAM)**: Docker limited to 28GB, 16 CPU cores
- **c7i.8xlarge (64GB RAM)**: Docker limited to 60GB, 32 CPU cores

## Directory Structure

```
ec2-benchmarks/
├── deploy-and-benchmark.sh          # Main orchestration script
├── terraform/                       # Infrastructure as code
│   ├── main.tf                     # EC2 instances, volumes, security
│   ├── user_data.sh                # Instance initialization script
│   └── terraform.tfvars.example    # Configuration template
├── scripts/
│   └── run-all-benchmarks.sh      # Benchmark execution script
└── README.md                       # This file
```

## Results Structure

After benchmarks complete, results are collected in timestamped directories:

```
collected_results_YYYYMMDD_HHMMSS/
├── cross_instance_comparison.md     # Performance comparison report
├── t4g_medium/                      # Results from t4g.medium instance
│   ├── performance_summary.md       # Overall benchmark summary
│   ├── performance_data.json        # Proving time / gas cost data from each of the suites
│   ├── proving_times.png            # Graph of proving times
│   ├── gas_consumption.png          # Graph of gas consumption
├── c7g_xlarge/                      # Results from c7g.xlarge instance
├── c7i_8xlarge/                     # Results from c7i.8xlarge instance
├── c7i_4xlarge/                     # Results from c7i.4xlarge instance
└── c7i_2xlarge/                     # Results from c7i.2xlarge instance
```

Each suite directory contains:
- Proof files and verification artifacts
- Timing measurements
- Gas cost estimates

## Monitoring Progress

### Real-time Logs

```bash
# Monitor deployment progress
tail -f ec2-benchmarks/terraform.log

# Monitor benchmark execution on specific instance
tail -f ec2-benchmarks/benchmark_t4g_medium.log
tail -f ec2-benchmarks/benchmark_c7g_xlarge.log
tail -f ec2-benchmarks/benchmark_c7i_8xlarge.log
tail -f ec2-benchmarks/benchmark_c7i_4xlarge.log
tail -f ec2-benchmarks/benchmark_c7i_2xlarge.log
```

### SSH into Instances

```bash
# Get instance IPs from terraform output
cd ec2-benchmarks/terraform
terraform output instance_info

# SSH into an instance
ssh -i ~/.ssh/zk-benchmark-key.pem ubuntu@<instance-ip>

# Check benchmark progress
sudo tail -f /var/log/user-data.log  # Setup progress
htop                                  # Resource usage
docker ps                           # Running containers
```

## Troubleshooting

### Common Issues

1. **SSH Connection Refused**
   ```bash
   # Check instance status
   aws ec2 describe-instances --instance-ids i-xxxxxxxxx
   
   # Verify security group allows SSH (port 22)
   aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
   ```

2. **Docker Build Failures**
   ```bash
   # SSH into instance and check Docker
   ssh -i ~/.ssh/key.pem ubuntu@instance-ip
   sudo docker ps
   sudo docker logs container-name
   ```

3. **Benchmark Timeout**
   ```bash
   # Increase test case timeout or reduce test cases
   ./deploy-and-benchmark.sh --test-cases 5
   ```

4. **Terraform Errors**
   ```bash
   # Check Terraform state
   cd terraform
   terraform state list
   terraform plan
   ```

### Recovery Commands

```bash
# Force cleanup stale Terraform state
cd terraform
terraform refresh
terraform destroy -auto-approve

# Manual instance termination
aws ec2 terminate-instances --instance-ids i-xxxxxxxxx

# Remove orphaned volumes
aws ec2 describe-volumes --filters "Name=status,Values=available"
aws ec2 delete-volume --volume-id vol-xxxxxxxxx
```

## Advanced Usage

### Custom Test Cases

```bash
# Generate more test cases before deployment
cd zk-snark-ecdsa-benchmarks
cargo run --bin generate_test_cases -- --num-test-cases 50

# Then deploy
cd ec2-benchmarks
./deploy-and-benchmark.sh --skip-deploy --test-cases 50
```

### Selective Benchmark Execution

Modify `scripts/run-all-benchmarks.sh` to run only specific suites:

```bash
# Comment out benchmarks you don't want to run
# run_benchmark "snarkjs" "SnarkJS (JavaScript) ECDSA Benchmarks"
run_benchmark "rapidsnark" "RapidSnark (C++) ECDSA Benchmarks" 
# run_benchmark "noir" "Noir (Rust) ECDSA Benchmarks"
# run_benchmark "gnark" "Gnark (Go) ECDSA Benchmarks"
```

### Extended Performance Analysis

```bash
# Profile CPU usage during benchmarks
ssh -i ~/.ssh/key.pem ubuntu@instance-ip
sudo apt-get install linux-perf
sudo perf top

# Monitor memory usage
watch -n 1 'free -h && docker stats --no-stream'
``` 