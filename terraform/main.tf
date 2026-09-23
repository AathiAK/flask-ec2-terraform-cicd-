terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure in terraform.tfvars or via CLI
    # bucket = "your-terraform-state-bucket"
    # key    = "flask-app/terraform.tfstate"
    # region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script for EC2 initialization
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    apt-get update
    ##apt-get upgrade -y
    
    # Install required packages
    ###apt-get install -y python3-pip python3-venv python3-dev build-essential nginx git
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      python3-pip \
      python3-venv \
      python3-dev \
      build-essential \
      nginx \
      git
	
    # Upgrade system
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    # Create app directory
    mkdir -p /opt/flask-app
    chown -R ubuntu:ubuntu /opt/flask-app
    
    # Create log directory
    mkdir -p /var/log/flask-app
    chown -R ubuntu:ubuntu /var/log/flask-app
    
    echo "EC2 instance initialized successfully"
  EOF
}

# Modules
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "s3" {
  source = "./modules/s3"

  bucket_name        = var.s3_bucket_name
  project_name       = var.project_name
  environment        = var.environment
  versioning_enabled = true
}

module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  s3_bucket_arn  = module.s3.bucket_arn
}

module "ec2" {
  source = "./modules/ec2"

  project_name         = var.project_name
  environment          = var.environment
  instance_type        = var.instance_type
  ami_id               = data.aws_ami.ubuntu.id
  subnet_id            = module.vpc.public_subnet_ids[0]
  security_group_ids   = [module.vpc.web_security_group_id]
  iam_instance_profile = module.iam.ec2_instance_profile_name
  key_name             = var.ssh_key_name
  user_data            = local.user_data
}
