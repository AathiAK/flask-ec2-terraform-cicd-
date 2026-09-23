# Testing Guide

## Overview

This document describes the testing strategy for the Flask EC2 deployment project.

## Test Levels

### 1. Local Development Testing

#### Flask Application
```bash
# Test locally before deployment
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run the app
python app.py

# In another terminal, test endpoints
curl http://localhost:5000/
curl http://localhost:5000/health
curl http://localhost:5000/api/info
```

#### Terraform Configuration
```bash
cd terraform

# Format check
terraform fmt -check -recursive

# Validation
terraform validate

# Plan (dry run)
terraform plan
```

### 2. Integration Testing

#### End-to-End Test Script
The `scripts/test-e2e.sh` script performs comprehensive tests:

```bash
# Usage
bash scripts/test-e2e.sh <EC2_IP>

# Or using Make
make test-e2e EC2_IP=<EC2_IP>
```

**Tests performed:**
1. Home endpoint (/)
2. Health check (/health)
3. Info endpoint (/api/info)
4. Data GET endpoint (/api/data)
5. Data POST endpoint (/api/data)
6. 404 handling (/invalid-endpoint)

#### Manual Integration Tests

```bash
EC2_IP="<your-ec2-ip>"

# 1. Test basic connectivity
curl -v http://$EC2_IP/

# 2. Test health endpoint
curl http://$EC2_IP/health | jq

# 3. Test application info
curl http://$EC2_IP/api/info | jq

# 4. Test data retrieval
curl http://$EC2_IP/api/data | jq

# 5. Test data storage
curl -X POST http://$EC2_IP/api/data \
  -H "Content-Type: application/json" \
  -d '{
    "test_id": "001",
    "message": "Test data",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }' | jq

# 6. Test error handling
curl http://$EC2_IP/nonexistent

# 7. Load test (basic)
for i in {1..100}; do
  curl -s http://$EC2_IP/ > /dev/null &
done
wait
echo "Load test complete"
```

### 3. Infrastructure Testing

#### Verify AWS Resources

```bash
# Get Terraform outputs
cd terraform
terraform output

# Verify EC2 instance
EC2_ID=$(terraform output -raw ec2_instance_id)
aws ec2 describe-instances --instance-ids $EC2_ID

# Verify S3 bucket
S3_BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 ls s3://$S3_BUCKET/

# Verify security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=flask-app"

# Verify IAM role
aws iam get-role --role-name flask-app-ec2-role-dev
```

#### SSH and Service Checks

```bash
# SSH into instance
ssh -i your-key.pem ubuntu@$EC2_IP

# Once connected:

# Check Flask service
sudo systemctl status flask-app

# Check Nginx
sudo systemctl status nginx
sudo nginx -t

# Check logs
sudo journalctl -u flask-app -n 50
sudo tail -f /var/log/nginx/access.log

# Check processes
ps aux | grep gunicorn
ps aux | grep nginx

# Check ports
sudo netstat -tlnp | grep -E ':(80|5000)'
sudo ss -tlnp | grep -E ':(80|5000)'

# Test local Flask app
curl http://localhost:5000/health

# Test Nginx proxy
curl http://localhost/health

# Check disk space
df -h

# Check memory
free -h
```

### 4. Performance Testing

#### Basic Load Test with Apache Bench
```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Run load test (100 requests, 10 concurrent)
ab -n 100 -c 10 http://$EC2_IP/

# More intensive test (1000 requests, 50 concurrent)
ab -n 1000 -c 50 http://$EC2_IP/api/info
```

#### Load Test with wrk
```bash
# Install wrk
sudo apt-get install wrk

# Run 30 second test with 10 connections
wrk -t10 -c10 -d30s http://$EC2_IP/

# POST request test
wrk -t10 -c10 -d30s -s post.lua http://$EC2_IP/api/data
```

**post.lua:**
```lua
wrk.method = "POST"
wrk.body   = '{"test": "data"}'
wrk.headers["Content-Type"] = "application/json"
```

### 5. Security Testing

#### SSL/TLS Check (if HTTPS enabled)
```bash
# Check SSL certificate
openssl s_client -connect $EC2_IP:443 -servername yourdomain.com

# Use SSL Labs (online)
# https://www.ssllabs.com/ssltest/
```

#### Security Group Audit
```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(cd terraform && terraform output -raw web_security_group_id)

# Verify only necessary ports are open
# Expected: 22 (SSH), 80 (HTTP), 443 (HTTPS)
```

#### Vulnerability Scanning
```bash
# SSH into EC2
ssh -i your-key.pem ubuntu@$EC2_IP

# Update system
sudo apt-get update

# Check for vulnerabilities
sudo apt-get upgrade -s | grep -i security
```

### 6. CI/CD Testing

#### GitHub Actions Workflow
The workflow automatically runs on:
- Push to any branch (plan only)
- Push to main (plan + apply + deploy + test)
- Pull requests (plan + comment)

**Verify workflow:**
1. Make a change
2. Create a pull request
3. Check that plan is posted as comment
4. Merge to main
5. Verify deployment succeeds
6. Check deployment summary

#### Manual Workflow Trigger
```bash
# Via GitHub CLI
gh workflow run deploy.yml

# Check status
gh run list --workflow=deploy.yml
```

### 7. Monitoring and Alerting Tests

#### Application Metrics
```bash
# Check response times
time curl http://$EC2_IP/

# Check memory usage
ssh -i your-key.pem ubuntu@$EC2_IP "free -h"

# Check CPU usage
ssh -i your-key.pem ubuntu@$EC2_IP "top -bn1 | head -20"

# Check disk I/O
ssh -i your-key.pem ubuntu@$EC2_IP "iostat -x 1 5"
```

#### Log Analysis
```bash
# Check error rates
ssh -i your-key.pem ubuntu@$EC2_IP \
  "sudo journalctl -u flask-app --since '1 hour ago' | grep -i error | wc -l"

# Check request counts
ssh -i your-key.pem ubuntu@$EC2_IP \
  "sudo tail -1000 /var/log/flask-app/access.log | wc -l"

# Check response codes
ssh -i your-key.pem ubuntu@$EC2_IP \
  "sudo tail -1000 /var/log/nginx/access.log | awk '{print \$9}' | sort | uniq -c"
```

## Test Automation

### Pre-commit Hooks
Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash

echo "Running pre-commit checks..."

# Terraform format
cd terraform
if ! terraform fmt -check -recursive; then
    echo "Error: Terraform files not formatted"
    echo "Run: terraform fmt -recursive"
    exit 1
fi

# Terraform validate
if ! terraform validate; then
    echo "Error: Terraform validation failed"
    exit 1
fi

echo "Pre-commit checks passed!"
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

### Continuous Monitoring Script
```bash
#!/bin/bash
# monitor.sh - Continuous health monitoring

EC2_IP=$1
INTERVAL=60  # Check every 60 seconds

if [ -z "$EC2_IP" ]; then
    echo "Usage: $0 <ec2_ip>"
    exit 1
fi

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    if curl -sf http://$EC2_IP/health > /dev/null; then
        echo "[$TIMESTAMP] ✓ Health check passed"
    else
        echo "[$TIMESTAMP] ✗ Health check failed"
        # Send alert (email, Slack, etc.)
    fi
    
    sleep $INTERVAL
done
```

## Test Checklist

### Before Deployment
- [ ] Terraform configuration formatted
- [ ] Terraform validation passes
- [ ] Terraform plan reviewed
- [ ] Flask app runs locally
- [ ] All dependencies in requirements.txt
- [ ] GitHub secrets configured
- [ ] SSH key pair exists in AWS

### After Deployment
- [ ] EC2 instance running
- [ ] Security groups configured correctly
- [ ] EIP attached
- [ ] IAM roles and policies applied
- [ ] S3 bucket created and accessible
- [ ] Flask app service active
- [ ] Nginx configured and running
- [ ] All endpoints responding
- [ ] Health check passing
- [ ] Logs accessible
- [ ] E2E tests passing

### Before Production
- [ ] HTTPS configured (SSL/TLS)
- [ ] CloudWatch monitoring enabled
- [ ] Backups configured
- [ ] Auto Scaling tested (if applicable)
- [ ] Load balancer configured (if applicable)
- [ ] Database backups working (if applicable)
- [ ] Disaster recovery plan in place
- [ ] Security audit completed
- [ ] Performance benchmarks met
- [ ] Documentation updated

## Common Test Failures

### 1. Connection Timeout
**Cause:** Security group not allowing traffic
**Solution:** 
```bash
# Check security group
cd terraform
terraform output web_security_group_id

# Verify rules allow port 80
```

### 2. 502 Bad Gateway
**Cause:** Flask app not running
**Solution:**
```bash
ssh -i key.pem ubuntu@$EC2_IP
sudo systemctl status flask-app
sudo journalctl -u flask-app -n 50
```

### 3. 404 Not Found
**Cause:** Nginx misconfiguration
**Solution:**
```bash
ssh -i key.pem ubuntu@$EC2_IP
sudo nginx -t
sudo systemctl restart nginx
```

### 4. S3 Access Denied
**Cause:** IAM permissions missing
**Solution:**
Check IAM role has S3 permissions:
```bash
cd terraform
terraform output ec2_role_arn
aws iam get-role-policy --role-name flask-app-ec2-role-dev
```

## Continuous Improvement

1. **Add more tests** as application grows
2. **Automate load testing** in CI/CD
3. **Set up CloudWatch alarms** for metrics
4. **Implement canary deployments** for safer updates
5. **Add synthetic monitoring** for 24/7 checks
6. **Create runbooks** for common issues
7. **Document incident responses**

## Resources

- [Flask Testing Documentation](https://flask.palletsprojects.com/en/latest/testing/)
- [Terraform Testing Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/part3.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
