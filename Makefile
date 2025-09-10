# Makefile for Agentverse DevOps/SRE
SHELL := /bin/bash

.PHONY: help setup validate audit deploy clean test-local

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Python environment
PYTHON := python3.11
UV := uv
VENV := .venv
VENV_PYTHON := $(VENV)/bin/python
VENV_SENTINEL := $(VENV)/.sentinel
DEPS_SENTINEL := $(VENV)/.deps_installed

# Default target
help:
	@echo "$(GREEN)AgentVerse DevOps/SRE Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Setup & Configuration:$(NC)"
	@echo "  make setup          - Complete setup (auth, repo, docker)"
	@echo "  make setup-keys     - Secure API key configuration"
	@echo "  make env            - Source environment variables"
	@echo "  make setup-repo     - Create Artifact Registry repository"
	@echo "  make configure-docker - Configure Docker for Artifact Registry"
	@echo ""
	@echo "$(YELLOW)Validation & Audit:$(NC)"
	@echo "  make validate       - Run all validation checks"
	@echo "  make audit          - Perform security and config audit"
	@echo "  make check-auth     - Check gcloud authentication"
	@echo "  make check-apis     - Verify required APIs are enabled"
	@echo "  make check-permissions - Verify IAM permissions"
	@echo ""
	@echo "$(YELLOW)Build & Deploy:$(NC)"
	@echo "  make build          - Build container images"
	@echo "  make deploy         - Deploy all services to Cloud Run"
	@echo "  make deploy-ollama  - Deploy Ollama service only"
	@echo "  make deploy-vllm    - Deploy vLLM service only"
	@echo "  make setup-vllm     - Setup vLLM environment"
	@echo "  make warmup         - Run cache warming"
	@echo "  make validate-deploy - Validate deployment"
	@echo ""
	@echo "$(YELLOW)Monitoring & Logs:$(NC)"
	@echo "  make logs           - Show recent Cloud Run logs"
	@echo "  make status         - Show service status"
	@echo "  make builds         - List recent builds"
	@echo ""
	@echo "$(YELLOW)Development:$(NC)"
	@echo "  make venv           - Create Python virtual environment"
	@echo "  make install        - Install all dependencies"
	@echo "  make install-dev    - Install with dev dependencies"
	@echo "  make guardian       - Run Guardian agent"
	@echo "  make test-local     - Run local tests"
	@echo "  make test-ollama    - Test Ollama service"
	@echo "  make test-vllm      - Test vLLM service"
	@echo "  make show-env       - Display current environment"
	@echo "  make clean          - Clean up resources"
	@echo "  make clean-venv     - Remove virtual environment"

# Generate README.md from README.org (requires Emacs)
README.md: README.org
	@echo "$(YELLOW)Generating README.md from README.org...$(NC)"
	@emacs README.org --batch -f org-md-export-to-markdown --kill 2>/dev/null || \
		(echo "$(RED)Error: Emacs not available. Install with: brew install emacs$(NC)" && exit 1)
	@echo "$(GREEN)✓ README.md generated$(NC)"

# Complete setup
setup: check-auth setup-repo configure-docker validate
	@echo "$(GREEN)✓ Setup complete$(NC)"

# Setup API keys securely
setup-keys:
	@echo "$(YELLOW)Setting up API keys securely...$(NC)"
	@./setup_keys.sh

# Source environment variables
env:
	@echo "$(YELLOW)Sourcing environment variables...$(NC)"
	@. ./set_env.sh && env | grep -E "(PROJECT_ID|OLLAMA_URL|REGION|REPO_NAME)"

# Check gcloud authentication
check-auth:
	@echo "$(YELLOW)Checking gcloud authentication...$(NC)"
	@if gcloud auth print-access-token > /dev/null 2>&1; then \
		echo "$(GREEN)✓ Authenticated$(NC)"; \
		echo "  Account: $$(gcloud config get-value account 2>/dev/null)"; \
		echo "  Project: $$(gcloud config get-value project 2>/dev/null)"; \
	else \
		echo "$(RED)✗ Not authenticated$(NC)"; \
		echo "  Run: gcloud auth login"; \
		exit 1; \
	fi

# Create Artifact Registry repository
setup-repo: check-auth
	@echo "$(YELLOW)Creating Artifact Registry repository...$(NC)"
	@. ./set_env.sh && \
	if gcloud artifacts repositories describe $$REPO_NAME \
		--location=$$REGION --format="value(name)" 2>/dev/null; then \
		echo "$(GREEN)✓ Repository '$$REPO_NAME' already exists$(NC)"; \
	else \
		gcloud artifacts repositories create $$REPO_NAME \
			--repository-format=docker \
			--location=$$REGION \
			--description="Repository for Agentverse agents" \
			--quiet && \
		echo "$(GREEN)✓ Repository '$$REPO_NAME' created$(NC)"; \
	fi

# Configure Docker for Artifact Registry
configure-docker: check-auth
	@echo "$(YELLOW)Configuring Docker for Artifact Registry...$(NC)"
	@. ./set_env.sh && \
	gcloud auth configure-docker $$REGION-docker.pkg.dev --quiet && \
	echo "$(GREEN)✓ Docker configured for $$REGION-docker.pkg.dev$(NC)"

# Run all validation checks
validate: check-auth check-apis check-ollama check-network check-storage
	@echo ""
	@echo "$(GREEN)════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ All validation checks passed$(NC)"
	@echo "$(GREEN)════════════════════════════════════$(NC)"

# Check required APIs
check-apis:
	@echo "$(YELLOW)Checking required APIs...$(NC)"
	@. ./set_env.sh && \
	for api in compute.googleapis.com \
		run.googleapis.com \
		cloudbuild.googleapis.com \
		artifactregistry.googleapis.com \
		aiplatform.googleapis.com \
		storage.googleapis.com; do \
		if gcloud services list --enabled --filter="name:$$api" --format="value(name)" | grep -q $$api; then \
			echo "$(GREEN)  ✓ $$api$(NC)"; \
		else \
			echo "$(RED)  ✗ $$api - enabling...$(NC)"; \
			gcloud services enable $$api --quiet; \
		fi; \
	done

# Check Ollama connectivity
check-ollama:
	@echo "$(YELLOW)Checking Ollama connectivity...$(NC)"
	@. ./set_env.sh && \
	if [ -n "$$OLLAMA_URL" ]; then \
		if curl -s $$OLLAMA_URL/api/tags > /dev/null 2>&1; then \
			echo "$(GREEN)  ✓ Ollama available at $$OLLAMA_URL$(NC)"; \
			echo "    Models: $$(ollama list 2>/dev/null | tail -n +2 | cut -d' ' -f1 | tr '\n' ' ')"; \
		else \
			echo "$(YELLOW)  ⚠ Ollama URL set but not responding$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)  ⚠ Ollama URL not configured$(NC)"; \
	fi

# Check network configuration
check-network:
	@echo "$(YELLOW)Checking network configuration...$(NC)"
	@. ./set_env.sh && \
	if gcloud compute networks describe $$VPC_NETWORK --format="value(name)" 2>/dev/null; then \
		echo "$(GREEN)  ✓ VPC network: $$VPC_NETWORK$(NC)"; \
	else \
		echo "$(RED)  ✗ VPC network not found$(NC)"; \
	fi

# Check storage bucket
check-storage:
	@echo "$(YELLOW)Checking storage configuration...$(NC)"
	@. ./set_env.sh && \
	if gsutil ls -b gs://$$BUCKET_NAME 2>/dev/null; then \
		echo "$(GREEN)  ✓ Storage bucket: $$BUCKET_NAME$(NC)"; \
	else \
		echo "$(YELLOW)  ⚠ Storage bucket does not exist (will be created if needed)$(NC)"; \
	fi

# Check IAM permissions
check-permissions:
	@echo "$(YELLOW)Checking IAM permissions...$(NC)"
	@. ./set_env.sh && \
	SA=$$(gcloud config get-value account) && \
	echo "  Checking permissions for: $$SA" && \
	for role in roles/cloudbuild.builds.editor \
		roles/artifactregistry.admin \
		roles/run.admin \
		roles/storage.admin; do \
		if gcloud projects get-iam-policy $$PROJECT_ID \
			--flatten="bindings[].members" \
			--format="table(bindings.role)" \
			--filter="bindings.members:$$SA AND bindings.role:$$role" | grep -q $$role; then \
			echo "$(GREEN)  ✓ $$role$(NC)"; \
		else \
			echo "$(YELLOW)  ⚠ Missing $$role$(NC)"; \
		fi; \
	done

# Check for exposed secrets
check-secrets:
	@echo "$(YELLOW)Checking for exposed secrets...$(NC)"
	@if [ -f ".env" ]; then \
		echo "$(GREEN)  ✓ .env file exists$(NC)"; \
		if [ "$$(stat -c '%a' .env 2>/dev/null || stat -f '%A' .env 2>/dev/null)" = "600" ]; then \
			echo "$(GREEN)  ✓ .env has secure permissions (600)$(NC)"; \
		else \
			echo "$(YELLOW)  ⚠ .env permissions should be 600$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)  ⚠ No .env file found - run 'make setup-keys'$(NC)"; \
	fi && \
	if grep -q "^\.env$$" .gitignore 2>/dev/null; then \
		echo "$(GREEN)  ✓ .env properly ignored by git$(NC)"; \
	else \
		echo "$(RED)  ✗ .env not in .gitignore - SECURITY RISK$(NC)"; \
	fi && \
	echo "$(YELLOW)Scanning for accidentally committed secrets...$(NC)" && \
	if git log --all --full-history --grep="token" --grep="password" --grep="secret" --grep="api_key" --grep="API_KEY" 2>/dev/null | head -1 | grep -q .; then \
		echo "$(RED)  ⚠ Potential secrets found in commit messages$(NC)"; \
		echo "    Run: git log --all --grep='token' --grep='password' --grep='secret'"; \
	else \
		echo "$(GREEN)  ✓ No obvious secrets in commit messages$(NC)"; \
	fi && \
	if git log --all --full-history --name-only -- "*.env" "*_token" "*_key" "*_secret" "*_password" | head -1 | grep -q .; then \
		echo "$(RED)  ⚠ Potential secret files in git history$(NC)"; \
		echo "    Run: git log --all --name-only -- '*.env' '*_token' '*_key'"; \
	else \
		echo "$(GREEN)  ✓ No secret files in git history$(NC)"; \
	fi

# Security and configuration audit
audit: check-permissions check-secrets
	@echo ""
	@echo "$(YELLOW)Running security audit...$(NC)"
	@. ./set_env.sh && \
	echo "$(YELLOW)API Security:$(NC)" && \
	if gcloud services list --enabled --filter="name:iamcredentials.googleapis.com" --format="value(name)" | grep -q iamcredentials; then \
		echo "$(GREEN)  ✓ IAM credentials API enabled$(NC)"; \
	else \
		echo "$(YELLOW)  ⚠ IAM credentials API not enabled$(NC)"; \
	fi && \
	echo "$(YELLOW)Container Security:$(NC)" && \
	if gcloud container images list --repository=$$REGION-docker.pkg.dev/$$PROJECT_ID/$$REPO_NAME 2>/dev/null; then \
		echo "$(GREEN)  ✓ Container registry accessible$(NC)"; \
	else \
		echo "$(YELLOW)  ⚠ No images in registry yet$(NC)"; \
	fi && \
	echo "$(YELLOW)Network Security:$(NC)" && \
	if gcloud compute firewall-rules list --format="table(name,direction,sourceRanges)" 2>/dev/null | grep -q INGRESS; then \
		echo "$(GREEN)  ✓ Firewall rules configured$(NC)"; \
	else \
		echo "$(YELLOW)  ⚠ Review firewall rules$(NC)"; \
	fi

# Build container images
build:
	@echo "$(YELLOW)Building container images...$(NC)"
	@. ./set_env.sh && \
	gcloud builds submit --config cloudbuild-cache-warmup.yaml \
		--substitutions=_REGION=$$REGION \
		--project=$$PROJECT_ID

# Deploy services
deploy: deploy-ollama deploy-vllm

# Deploy Ollama with baked models
deploy-ollama:
	@echo "$(YELLOW)Deploying Ollama with baked models to Cloud Run...$(NC)"
	@cd ollama && ./deploy-ollama-baked.sh

# Deploy Ollama (simple version with single model)
deploy-ollama-simple:
	@echo "$(YELLOW)Deploying Ollama (simple) to Cloud Run...$(NC)"
	@cd ollama && ./deploy-ollama-baked.sh --simple

# Test Ollama service
test-ollama:
	@echo "$(YELLOW)Testing Ollama service...$(NC)"
	@. ./set_env.sh && \
	if [ -n "$$OLLAMA_URL" ]; then \
		echo "Testing $$OLLAMA_URL..." && \
		curl -s -X POST "$$OLLAMA_URL/api/generate" \
			-H "Content-Type: application/json" \
			-d '{"model": "gemma:2b", "prompt": "Hello, Guardian!", "stream": false}' | \
			jq -r '.response' 2>/dev/null || echo "$(RED)Service not responding$(NC)"; \
	else \
		echo "$(YELLOW)Ollama URL not configured$(NC)"; \
	fi

# Deploy vLLM service
deploy-vllm: setup-vllm
	@echo "$(YELLOW)Deploying vLLM service to Cloud Run...$(NC)"
	@cd vllm && gcloud builds submit \
		--config cloudbuild-vllm-deploy.yaml \
		--project="$$(cd .. && source set_env.sh > /dev/null 2>&1 && echo $$PROJECT_ID)" \
		.

# Setup vLLM environment (HF token, secrets)
setup-vllm:
	@echo "$(YELLOW)Setting up vLLM environment...$(NC)"
	@cd vllm && ./setup-vllm.sh

# Test vLLM service
test-vllm:
	@echo "$(YELLOW)Testing vLLM service...$(NC)"
	@. ./set_env.sh && \
	if [ -n "$$VLLM_URL" ]; then \
		echo "Testing $$VLLM_URL..." && \
		curl -s "$$VLLM_URL/v1/models" | jq '.data[].id' 2>/dev/null || \
		curl -s "$$VLLM_URL/health" || echo "$(RED)Service not responding$(NC)"; \
	else \
		echo "$(YELLOW)vLLM URL not configured$(NC)"; \
	fi

# Run cache warming
warmup:
	@echo "$(YELLOW)Running cache warming...$(NC)"
	@./warmup.sh

# Validate deployment
validate-deploy:
	@echo "$(YELLOW)Validating deployment...$(NC)"
	@. ./set_env.sh && \
	if [ -n "$$VLLM_URL" ]; then \
		if curl -s $$VLLM_URL/health > /dev/null 2>&1; then \
			echo "$(GREEN)  ✓ VLLM service responding$(NC)"; \
		else \
			echo "$(RED)  ✗ VLLM service not responding$(NC)"; \
		fi; \
	fi && \
	if [ -n "$$PUBLIC_URL" ]; then \
		if curl -s $$PUBLIC_URL > /dev/null 2>&1; then \
			echo "$(GREEN)  ✓ Public endpoint responding$(NC)"; \
		else \
			echo "$(YELLOW)  ⚠ Public endpoint not responding$(NC)"; \
		fi; \
	fi

# Show recent Cloud Run logs
logs:
	@echo "$(YELLOW)Recent Cloud Run logs:$(NC)"
	@gcloud logging read "resource.type=cloud_run_revision" \
		--limit=20 \
		--format="table(timestamp,severity,textPayload)"

# Show service status
status:
	@echo "$(YELLOW)Cloud Run services:$(NC)"
	@. ./set_env.sh && \
	gcloud run services list --region=$$REGION \
		--format="table(SERVICE,REGION,URL,LAST_DEPLOYED_BY,LAST_DEPLOYED_AT)"

# List recent builds
builds:
	@echo "$(YELLOW)Recent builds:$(NC)"
	@. ./set_env.sh && \
	gcloud builds list --limit=5 \
		--format="table(id,status,createTime.date(),duration)"

# Run local tests
test-local:
	@echo "$(YELLOW)Running local tests...$(NC)"
	@. ./set_env.sh && \
	if [ -n "$$OLLAMA_URL" ]; then \
		echo "Testing Ollama endpoint..." && \
		curl -s $$OLLAMA_URL/api/tags > /dev/null && \
		echo "$(GREEN)  ✓ Ollama test passed$(NC)"; \
	else \
		echo "$(YELLOW)  ⚠ Ollama not configured$(NC)"; \
	fi

# Show current environment
show-env:
	@. ./set_env.sh > /dev/null 2>&1 && \
	echo "$(YELLOW)Current Environment:$(NC)" && \
	echo "  $(GREEN)PROJECT_ID:$(NC) $$PROJECT_ID" && \
	echo "  $(GREEN)REGION:$(NC) $$REGION" && \
	echo "  $(GREEN)REPO_NAME:$(NC) $$REPO_NAME" && \
	echo "  $(GREEN)OLLAMA_URL:$(NC) $$OLLAMA_URL" && \
	echo "  $(GREEN)VLLM_URL:$(NC) $$VLLM_URL" && \
	echo "  $(GREEN)PUBLIC_URL:$(NC) $$PUBLIC_URL" && \
	echo "  $(GREEN)MODEL_ID:$(NC) $$MODEL_ID"

# Python Virtual Environment Management
# Create virtual environment with sentinel
$(VENV_SENTINEL): pyproject.toml
	@echo "$(YELLOW)Creating Python virtual environment...$(NC)"
	@$(UV) venv --python $(PYTHON)
	@touch $(VENV_SENTINEL)
	@echo "$(GREEN)✓ Virtual environment created$(NC)"

# Alias for creating venv
venv: $(VENV_SENTINEL)

# Install dependencies with sentinel
$(DEPS_SENTINEL): $(VENV_SENTINEL) pyproject.toml
	@echo "$(YELLOW)Installing dependencies with uv...$(NC)"
	@$(UV) pip sync pyproject.toml
	@touch $(DEPS_SENTINEL)
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

# Install all dependencies
install: $(DEPS_SENTINEL)

# Install with dev dependencies
install-dev: $(VENV_SENTINEL)
	@echo "$(YELLOW)Installing with dev dependencies...$(NC)"
	@$(UV) pip install -e ".[dev,guardian]"
	@touch $(DEPS_SENTINEL)
	@echo "$(GREEN)✓ All dependencies installed$(NC)"

# Install Guardian dependencies specifically
install-guardian: $(VENV_SENTINEL)
	@echo "$(YELLOW)Installing Guardian dependencies...$(NC)"
	@$(UV) pip install -e ".[guardian]"
	@echo "$(GREEN)✓ Guardian dependencies installed$(NC)"

# Run Guardian agent
guardian: $(DEPS_SENTINEL)
	@echo "$(YELLOW)Starting Guardian agent...$(NC)"
	@. ./set_env.sh && \
	$(VENV_PYTHON) guardian/guardian.py

# Python tests
test-python: $(DEPS_SENTINEL)
	@echo "$(YELLOW)Running Python tests...$(NC)"
	@$(VENV_PYTHON) -m pytest tests/ -v

# Format code
format: $(VENV_SENTINEL)
	@echo "$(YELLOW)Formatting code...$(NC)"
	@$(UV) run black guardian/ tests/
	@$(UV) run ruff check --fix guardian/ tests/

# Clean Python artifacts
clean-python:
	@echo "$(YELLOW)Cleaning Python artifacts...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Python artifacts cleaned$(NC)"

# Clean virtual environment
clean-venv:
	@echo "$(YELLOW)Removing virtual environment...$(NC)"
	@rm -rf $(VENV)
	@echo "$(GREEN)✓ Virtual environment removed$(NC)"

# Scale down services to save costs
clean-services:
	@echo "$(YELLOW)Scaling down Cloud Run services to save costs...$(NC)"
	@. ./set_env.sh && \
	gcloud run services update gemma-ollama-baked-service --min-instances 0 --region $$REGION 2>/dev/null || echo "Ollama service not found" && \
	gcloud run services update gemma-vllm-fuse-service --min-instances 0 --region $$REGION 2>/dev/null || echo "vLLM service not found" && \
	gcloud run services update guardian-agent --min-instances 0 --region $$REGION 2>/dev/null || echo "Guardian agent not found"
	@echo "$(GREEN)✓ Services scaled down$(NC)"

# Complete infrastructure cleanup (DESTRUCTIVE)
clean-all:
	@echo "$(RED)⚠️  WARNING: This will DELETE ALL AgentVerse infrastructure!$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to cancel, or Enter to continue...$(NC)"
	@read
	@./cleanup-agentverse.sh

# Clean up resources
clean: clean-python
	@echo "$(YELLOW)Cleaning up resources...$(NC)"
	@echo "$(RED)Warning: This will delete resources. Press Ctrl+C to cancel.$(NC)"
	@sleep 3
	@. ./set_env.sh && \
	echo "Cleaning build artifacts..." && \
	gsutil -m rm -r gs://$$PROJECT_ID_cloudbuild/** 2>/dev/null || true && \
	echo "$(GREEN)✓ Cleanup complete$(NC)"

# Full clean (including venv)
clean-all: clean clean-venv
	@echo "$(GREEN)✓ Full cleanup complete$(NC)"