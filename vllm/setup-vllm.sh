#!/bin/bash

# Clean vLLM Setup Script for AgentVerse
# Uses our secure API key management system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    vLLM Setup for AgentVerse                                 ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Check if we're in the right directory
cd "$(dirname "$0")/.."

# Source environment variables
echo -e "${YELLOW}Loading environment configuration...${NC}"
source ./set_env.sh > /dev/null 2>&1

# Validate required environment variables
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$SERVICE_ACCOUNT_NAME" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo "Please ensure PROJECT_ID, REGION, and SERVICE_ACCOUNT_NAME are configured"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  PROJECT_ID: $PROJECT_ID"
echo "  REGION: $REGION"
echo "  SERVICE_ACCOUNT: $SERVICE_ACCOUNT_NAME"
echo "  BUCKET: $BUCKET_NAME"
echo ""

# Check if .env file exists with HF_TOKEN
if [ -f ".env" ] && grep -q "HF_TOKEN=" .env 2>/dev/null; then
    echo -e "${GREEN}✓ Hugging Face token found in .env file${NC}"
    source .env
    export HUGGING_FACE_TOKEN="$HF_TOKEN"
elif [ -n "$HF_TOKEN" ]; then
    echo -e "${GREEN}✓ Hugging Face token found in environment${NC}"
    export HUGGING_FACE_TOKEN="$HF_TOKEN"
else
    echo -e "${YELLOW}⚠️  No Hugging Face token found${NC}"
    echo "Please run: make setup-keys"
    exit 1
fi

# Create or update secret in Secret Manager
echo -e "${YELLOW}Setting up Secret Manager...${NC}"

# Check if secret exists
if gcloud secrets describe hf-secret --project="$PROJECT_ID" &>/dev/null; then
    echo "Updating existing hf-secret..."
    echo -n "$HUGGING_FACE_TOKEN" | gcloud secrets versions add hf-secret \
        --data-file=- \
        --project="$PROJECT_ID"
else
    echo "Creating new hf-secret..."
    gcloud secrets create hf-secret \
        --replication-policy="automatic" \
        --project="$PROJECT_ID"
    
    echo -n "$HUGGING_FACE_TOKEN" | gcloud secrets versions add hf-secret \
        --data-file=- \
        --project="$PROJECT_ID"
fi

# Set IAM permissions for Cloud Build and Cloud Run
echo -e "${YELLOW}Setting up IAM permissions...${NC}"

CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Grant Cloud Build access to secrets
gcloud secrets add-iam-policy-binding hf-secret \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID"

# Grant Cloud Run service account access  
gcloud secrets add-iam-policy-binding hf-secret \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID"

echo ""
echo -e "${GREEN}✓ vLLM environment setup complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Deploy vLLM: make deploy-vllm"
echo "2. Test deployment: make test-vllm"
echo "3. View logs: make logs"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"