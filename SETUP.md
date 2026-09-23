# Quick Setup Guide

## 1. Prerequisites Setup

### Install Required Tools
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installations
aws --version
terraform --version

### Configure AWS CLI
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (e.g., us-east-1)
# - Default output format (json)

## 2. Create AWS SSH Key Pair

# Option 1: Create via AWS CLI
aws ec2 create-key-pair \
  --key-name flask-app-key \
  --query 'KeyMaterial' \
  --output text > flask-app-key.pem

chmod 400 flask-app-key.pem

# Option 2: Use AWS Console
# Go to EC2 → Key Pairs → Create Key Pair
# Download and save the .pem file

## 3. Create S3 Buckets

# For Terraform state
aws s3 mb s3://flask-terraform-statefiles --region us-east-1
aws s3api put-bucket-versioning \
  --bucket flask-terraform-statefiles \
  --versioning-configuration Status=Enabled

# For application data
aws s3 mb s3://flask-app-data-1 --region us-east-1

## 4. Configure Terraform

cd terraform

# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars

#terraform.tfvars:
aws_region      = "us-east-1"
project_name    = "flask-app"
environment     = "dev"
instance_type   = "t2.micro"
ssh_key_name    = "flask-app-key"  # Your key name
s3_bucket_name  = "flask-app-data-1"  # Must be unique

## 5. Test Terraform Locally

# Initialize
terraform init -backend-config="bucket=flask-terraform-statefiles" -backend-config="key=flask-app/terraform.tfstate" -backend-config="region=us-east-1"

# Validate
terraform validate

# Plan
terraform plan

# Apply (optional - GitHub Actions will do this)
terraform apply -auto-approve

# Destroy partial resources created while "terraform apply" results failed 
terraform destroy -auto-approve

## 6. Configure GitHub Repository

### Create Repository
# Initialize git
git init
git add .
git commit -m "Initial commit"

# Create repo on GitHub, then:
git remote add origin https://github.com/yourusername/flask-ec2-deployment.git
git branch -M main
git push -u origin main

### Add GitHub Secrets

Go to: Repository → Settings → Secrets and variables → Actions → New repository secret

Add these secrets:

1. AWS_ACCESS_KEY_ID
   # Your AWS access key

2. AWS_SECRET_ACCESS_KEY
   # Your AWS secret key

3. SSH_KEY_NAME
   flask-app-key

4. SSH_PRIVATE_KEY
   # Content of your .pem file
   cat flask-app-key.pem

5. S3_BUCKET_NAME
   flask-app-data-agl-190

6. TF_STATE_BUCKET
   flask-terraform-statefiles

## 7. Deploy


# Make a change and push
git add .
git commit -m "Trigger deployment"
git push origin main


## 8. Verify Deployment

### Check GitHub Actions
1. Go to your repository on GitHub
2. Click "Actions" tab
3. Watch the workflow run

### Test Application

# Get EC2 IP from Terraform output or GitHub Actions logs
EC2_IP="<your-ec2-ip>"

# Test endpoints
curl http://$EC2_IP/
curl http://$EC2_IP/health
curl http://$EC2_IP/api/info

# Run full E2E tests
 scripts/test-e2e.sh $EC2_IP


## 9. SSH into EC2 (if needed)
ssh -i flask-app-key.pem ubuntu@<EC2_IP>

# Check application
sudo systemctl status flask-app
sudo journalctl -u flask-app -f


## 10. Cleanup (when done)
cd terraform

# Destroy all resources
terraform destroy -auto-approve

# Delete S3 buckets
aws s3 rb s3://my-terraform-state-bucket-12345 --force
aws s3 rb s3://flask-app-data-12345 --force


## Troubleshooting

### Error: Key pair does not exist
- Create key pair in AWS Console or via CLI
- Ensure the name matches `ssh_key_name` in terraform.tfvars

### Error: S3 bucket already exists
- S3 bucket names are globally unique
- Choose a different name in terraform.tfvars

### Error: Insufficient permissions
- Ensure your AWS IAM user has appropriate permissions:
  - EC2 full access
  - S3 full access
  - IAM role creation
  - VPC management

### Application not accessible
- Wait 2-3 minutes after deployment
- Check security group allows port 80
- Verify EC2 instance is running
- Check logs: `sudo journalctl -u flask-app -n 50`

### Terraform state locked

terraform force-unlock <LOCK_ID>

