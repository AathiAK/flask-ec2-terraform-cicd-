.PHONY: help init plan apply destroy test clean ssh logs

# Variables
TF_DIR := terraform
APP_DIR := app
SCRIPTS_DIR := scripts

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo "$(GREEN)Initializing Terraform...$(NC)"
	cd $(TF_DIR) && terraform init

validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating Terraform configuration...$(NC)"
	cd $(TF_DIR) && terraform fmt -check -recursive
	cd $(TF_DIR) && terraform validate

plan: ## Run Terraform plan
	@echo "$(GREEN)Running Terraform plan...$(NC)"
	cd $(TF_DIR) && terraform plan

apply: ## Apply Terraform changes
	@echo "$(GREEN)Applying Terraform changes...$(NC)"
	cd $(TF_DIR) && terraform apply

apply-auto: ## Apply Terraform changes without confirmation
	@echo "$(GREEN)Auto-applying Terraform changes...$(NC)"
	cd $(TF_DIR) && terraform apply -auto-approve

destroy: ## Destroy all resources
	@echo "$(RED)Destroying all resources...$(NC)"
	cd $(TF_DIR) && terraform destroy

destroy-auto: ## Destroy all resources without confirmation
	@echo "$(RED)Auto-destroying all resources...$(NC)"
	cd $(TF_DIR) && terraform destroy -auto-approve

output: ## Show Terraform outputs
	@echo "$(GREEN)Terraform outputs:$(NC)"
	cd $(TF_DIR) && terraform output

test-local: ## Test Flask app locally
	@echo "$(GREEN)Testing Flask app locally...$(NC)"
	cd $(APP_DIR) && python3 -m venv venv && \
		. venv/bin/activate && \
		pip install -r requirements.txt && \
		python app.py

test-e2e: ## Run end-to-end tests (requires EC2_IP)
	@if [ -z "$(EC2_IP)" ]; then \
		echo "$(RED)Error: EC2_IP not set. Use: make test-e2e EC2_IP=x.x.x.x$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Running E2E tests on $(EC2_IP)...$(NC)"
	bash $(SCRIPTS_DIR)/test-e2e.sh $(EC2_IP)

ssh: ## SSH into EC2 instance (requires EC2_IP and SSH_KEY)
	@if [ -z "$(EC2_IP)" ]; then \
		echo "$(RED)Error: EC2_IP not set. Use: make ssh EC2_IP=x.x.x.x SSH_KEY=path/to/key.pem$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SSH_KEY)" ]; then \
		echo "$(RED)Error: SSH_KEY not set. Use: make ssh EC2_IP=x.x.x.x SSH_KEY=path/to/key.pem$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Connecting to EC2...$(NC)"
	ssh -i $(SSH_KEY) ubuntu@$(EC2_IP)

logs: ## View application logs (requires EC2_IP and SSH_KEY)
	@if [ -z "$(EC2_IP)" ]; then \
		echo "$(RED)Error: EC2_IP not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SSH_KEY)" ]; then \
		echo "$(RED)Error: SSH_KEY not set$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Viewing application logs...$(NC)"
	ssh -i $(SSH_KEY) ubuntu@$(EC2_IP) "sudo journalctl -u flask-app -f"

deploy: ## Deploy application to EC2 (requires EC2_IP, SSH_KEY, S3_BUCKET_NAME)
	@if [ -z "$(EC2_IP)" ] || [ -z "$(SSH_KEY)" ] || [ -z "$(S3_BUCKET_NAME)" ]; then \
		echo "$(RED)Error: Required variables not set$(NC)"; \
		echo "Usage: make deploy EC2_IP=x.x.x.x SSH_KEY=key.pem S3_BUCKET_NAME=bucket"; \
		exit 1; \
	fi
	@echo "$(GREEN)Deploying application...$(NC)"
	tar czf flask-app.tar.gz $(APP_DIR)/ $(SCRIPTS_DIR)/
	scp -i $(SSH_KEY) flask-app.tar.gz ubuntu@$(EC2_IP):/tmp/
	ssh -i $(SSH_KEY) ubuntu@$(EC2_IP) "\
		cd /tmp && \
		tar xzf flask-app.tar.gz && \
		export S3_BUCKET_NAME=$(S3_BUCKET_NAME) && \
		export ENVIRONMENT=production && \
		sudo -E bash /tmp/$(SCRIPTS_DIR)/deploy.sh"
	rm -f flask-app.tar.gz
	@echo "$(GREEN)Deployment complete!$(NC)"

clean: ## Clean temporary files
	@echo "$(GREEN)Cleaning temporary files...$(NC)"
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	find . -type d -name "*.egg-info" -delete
	rm -rf $(APP_DIR)/venv
	rm -f flask-app.tar.gz
	cd $(TF_DIR) && rm -f tfplan
	@echo "$(GREEN)Clean complete!$(NC)"

format: ## Format Terraform files
	@echo "$(GREEN)Formatting Terraform files...$(NC)"
	cd $(TF_DIR) && terraform fmt -recursive

setup-backend: ## Setup S3 backend for Terraform state (requires BACKEND_BUCKET)
	@if [ -z "$(BACKEND_BUCKET)" ]; then \
		echo "$(RED)Error: BACKEND_BUCKET not set$(NC)"; \
		echo "Usage: make setup-backend BACKEND_BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "$(GREEN)Creating S3 bucket for Terraform state...$(NC)"
	aws s3 mb s3://$(BACKEND_BUCKET) --region us-east-1
	aws s3api put-bucket-versioning \
		--bucket $(BACKEND_BUCKET) \
		--versioning-configuration Status=Enabled
	@echo "$(GREEN)Backend bucket created: $(BACKEND_BUCKET)$(NC)"

get-ip: ## Get EC2 public IP
	@echo "$(GREEN)EC2 Public IP:$(NC)"
	@cd $(TF_DIR) && terraform output -raw ec2_public_ip

health-check: ## Check application health (requires EC2_IP)
	@if [ -z "$(EC2_IP)" ]; then \
		EC2_IP=$$(cd $(TF_DIR) && terraform output -raw ec2_public_ip); \
	fi
	@echo "$(GREEN)Checking application health at $$EC2_IP...$(NC)"
	@curl -s http://$$EC2_IP/health | python3 -m json.tool

status: ## Show deployment status
	@echo "$(GREEN)=== Deployment Status ===$(NC)"
	@echo ""
	@echo "$(YELLOW)Terraform State:$(NC)"
	@cd $(TF_DIR) && terraform output 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(YELLOW)Application Health:$(NC)"
	@EC2_IP=$$(cd $(TF_DIR) && terraform output -raw ec2_public_ip 2>/dev/null); \
	if [ -n "$$EC2_IP" ]; then \
		curl -sf http://$$EC2_IP/health > /dev/null && echo "  $(GREEN)✓ Healthy$(NC)" || echo "  $(RED)✗ Unhealthy$(NC)"; \
	else \
		echo "  Not deployed"; \
	fi

.DEFAULT_GOAL := help
