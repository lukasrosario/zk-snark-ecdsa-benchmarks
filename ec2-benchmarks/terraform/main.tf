terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instances"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group"
  type        = string
}

variable "test_cases" {
  description = "Number of test cases to generate"
  type        = number
  default     = 10
}

# Security group for benchmark instances
resource "aws_security_group" "benchmark_sg" {
  name_prefix = "zk-benchmark-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zk-benchmark-sg"
  }
}

# EBS volumes for persistent storage
resource "aws_ebs_volume" "benchmark_volumes" {
  count             = 4
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = 50
  type              = "gp3"
  iops              = 3000
  throughput        = 125

  tags = {
    Name = "zk-benchmark-volume-${count.index + 1}"
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

# Get the latest Ubuntu 22.04 LTS AMI (x86_64)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Get ARM-based Ubuntu AMI for ARM instances
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script for instance setup
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    volume_device_name = "/dev/nvme1n1"
    test_cases = var.test_cases
  }))
}

# t4g.medium - ARM Graviton2, 2 vCPUs, 4GB RAM
resource "aws_instance" "t4g_medium" {
  ami                     = data.aws_ami.ubuntu_arm.id
  instance_type          = "t4g.medium"
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.benchmark_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "zk-benchmark-t4g-medium"
    Type = "benchmark"
    InstanceType = "t4g.medium"
  }
}

# c7g.xlarge - ARM Graviton3, 4 vCPUs, 8GB RAM
resource "aws_instance" "c7g_xlarge" {
  ami                     = data.aws_ami.ubuntu_arm.id
  instance_type          = "c7g.xlarge"
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.benchmark_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "zk-benchmark-c7g-xlarge"
    Type = "benchmark"
    InstanceType = "c7g.xlarge"
  }
}

# c7i.2xlarge - Intel, 8 vCPUs, 16GB RAM
resource "aws_instance" "c7i_2xlarge" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type          = "c7i.2xlarge"
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.benchmark_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "zk-benchmark-c7i-2xlarge"
    Type = "benchmark"
    InstanceType = "c7i.2xlarge"
  }
}

# c7i.4xlarge - Intel, 16 vCPUs, 32GB RAM
resource "aws_instance" "c7i_4xlarge" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type          = "c7i.4xlarge"
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.benchmark_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "zk-benchmark-c7i-4xlarge"
    Type = "benchmark"
    InstanceType = "c7i.4xlarge"
  }
}

# Attach volumes to instances
resource "aws_volume_attachment" "benchmark_attachments" {
  count       = 4
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.benchmark_volumes[count.index].id
  instance_id = [
    aws_instance.t4g_medium.id,
    aws_instance.c7g_xlarge.id,
    aws_instance.c7i_2xlarge.id,
    aws_instance.c7i_4xlarge.id
  ][count.index]
}

# Outputs
output "instance_info" {
  value = {
    t4g_medium = {
      id         = aws_instance.t4g_medium.id
      public_ip  = aws_instance.t4g_medium.public_ip
      private_ip = aws_instance.t4g_medium.private_ip
    }
    c7g_xlarge = {
      id         = aws_instance.c7g_xlarge.id
      public_ip  = aws_instance.c7g_xlarge.public_ip
      private_ip = aws_instance.c7g_xlarge.private_ip
    }
    c7i_2xlarge = {
      id         = aws_instance.c7i_2xlarge.id
      public_ip  = aws_instance.c7i_2xlarge.public_ip
      private_ip = aws_instance.c7i_2xlarge.private_ip
    }
    c7i_4xlarge = {
      id         = aws_instance.c7i_4xlarge.id
      public_ip  = aws_instance.c7i_4xlarge.public_ip
      private_ip = aws_instance.c7i_4xlarge.private_ip
    }
  }
}

output "volume_ids" {
  value = aws_ebs_volume.benchmark_volumes[*].id
}