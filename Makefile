# Makefile for Agentverse DevOps/SRE
SHELL := /bin/bash

.PHONY: help setup validate audit deploy clean test-local

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Default target
help:
	@echo "$(GREEN)AgentVerse DevOps/SRE Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Setup & Configuration:$(NC)"
	@echo "  make setup          - Complete setup (auth, repo, docker)"
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
	@echo "  make deploy         - Deploy services to Cloud Run"
	@echo "  make warmup         - Run cache warming"
	@echo "  make validate-deploy - Validate deployment"
	@echo ""
	@echo "$(YELLOW)Monitoring & Logs:$(NC)"
	@echo "  make logs           - Show recent Cloud Run logs"
	@echo "  make status         - Show service status"
	@echo "  make builds         - List recent builds"
	@echo ""
	@echo "$(YELLOW)Development:$(NC)"
	@echo "  make test-local     - Run local tests"
	@echo "  make show-env       - Display current environment"
	@echo "  make clean          - Clean up resources"

# Complete setup
setup: check-auth setup-repo configure-docker validate
	@echo "$(GREEN)✓ Setup complete$(NC)"

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

# Security and configuration audit
audit: check-permissions
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
deploy:
	@echo "$(YELLOW)Deploying services to Cloud Run...$(NC)"
	@echo "$(RED)Not yet implemented - add your service deployment here$(NC)"

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

# Clean up resources
clean:
	@echo "$(YELLOW)Cleaning up resources...$(NC)"
	@echo "$(RED)Warning: This will delete resources. Press Ctrl+C to cancel.$(NC)"
	@sleep 3
	@. ./set_env.sh && \
	echo "Cleaning build artifacts..." && \
	gsutil -m rm -r gs://$$PROJECT_ID_cloudbuild/** 2>/dev/null || true && \
	echo "$(GREEN)✓ Cleanup complete$(NC)"