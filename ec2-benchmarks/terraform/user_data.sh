#!/bin/bash
set -e

# Update system
apt-get update -y
apt-get upgrade -y

# Install dependencies
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    htop \
    git \
    unzip \
    jq \
    awscli

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install Rust and Cargo for test case generation
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source /home/ubuntu/.cargo/env

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Configure Docker for performance - increase memory and use all CPU cores
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "memlock": {
      "Hard": -1,
      "Name": "memlock",
      "Soft": -1
    },
    "nofile": {
      "Hard": 1048576,
      "Name": "nofile",
      "Soft": 1048576
    }
  }
}
EOF

# Restart Docker with new configuration
systemctl restart docker

# Wait for EBS volume to be available
sleep 30

# Find the attached EBS volume
DEVICE=""
for dev in /dev/nvme[1-9]n1 /dev/xvdf /dev/sdf; do
    if [ -b "$dev" ]; then
        DEVICE="$dev"
        break
    fi
done

if [ -z "$DEVICE" ]; then
    echo "No attached EBS volume found"
    exit 1
fi

# Format and mount the EBS volume
mkfs.ext4 -F $DEVICE
mkdir -p /mnt/benchmark-data
mount $DEVICE /mnt/benchmark-data

# Add to fstab for persistent mounting
echo "$DEVICE /mnt/benchmark-data ext4 defaults 0 0" >> /etc/fstab

# Set ownership to ubuntu user
chown -R ubuntu:ubuntu /mnt/benchmark-data

# Performance tuning
echo 'vm.swappiness=1' >> /etc/sysctl.conf
echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
echo 'kernel.sched_migration_cost_ns=5000000' >> /etc/sysctl.conf

# Apply sysctl settings
sysctl -p

# Set CPU governor to performance
echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Create benchmark user environment
sudo -u ubuntu bash << 'EOF'
cd /home/ubuntu

# Clone the benchmark repository
git clone https://github.com/lukasrosario/zk-snark-ecdsa-benchmarks.git
cd zk-snark-ecdsa-benchmarks

# Download powers of tau file
curl -L "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau" -o pot22_final.ptau

# Create data directories for each benchmark suite
mkdir -p snarkjs/data
mkdir -p rapidsnark/data
mkdir -p noir/data
mkdir -p gnark/data

# Link data directories to the mounted volume
ln -sf /mnt/benchmark-data/snarkjs /home/ubuntu/zk-snark-ecdsa-benchmarks/snarkjs/data-volume
ln -sf /mnt/benchmark-data/rapidsnark /home/ubuntu/zk-snark-ecdsa-benchmarks/rapidsnark/data-volume
ln -sf /mnt/benchmark-data/noir /home/ubuntu/zk-snark-ecdsa-benchmarks/noir/data-volume
ln -sf /mnt/benchmark-data/gnark /home/ubuntu/zk-snark-ecdsa-benchmarks/gnark/data-volume

# Create directories on the volume
mkdir -p /mnt/benchmark-data/snarkjs
mkdir -p /mnt/benchmark-data/rapidsnark
mkdir -p /mnt/benchmark-data/noir
mkdir -p /mnt/benchmark-data/gnark

# Set up Rust environment
source /home/ubuntu/.cargo/env

# Build test case generator
cargo build --release

# Generate test cases for benchmarking
cargo run --bin generate_test_cases -- --num-test-cases=10
EOF

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Create instance info file
cat > /home/ubuntu/instance-info.json << EOF
{
  "instance_id": "$INSTANCE_ID",
  "instance_type": "$INSTANCE_TYPE",
  "availability_zone": "$AZ",
  "cpu_cores": $(nproc),
  "memory_gb": $(free -g | awk '/^Mem:/{print $2}'),
  "setup_completed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chown ubuntu:ubuntu /home/ubuntu/instance-info.json

# Mark setup as complete
touch /home/ubuntu/setup-complete

echo "Instance setup completed successfully" | tee /var/log/user-data.log 