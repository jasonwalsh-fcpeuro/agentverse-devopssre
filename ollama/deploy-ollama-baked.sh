#!/bin/bash

# Deploy Ollama with Baked-in Gemma Model to Cloud Run
# This script builds and deploys an Ollama container with pre-loaded models

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}    Ollama Baked Model Deployment Script                      ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"

# Source environment variables
echo -e "${YELLOW}Loading environment configuration...${NC}"
source ../set_env.sh

# Validate required environment variables
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$REPO_NAME" ]; then
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo "Please ensure PROJECT_ID, REGION, and REPO_NAME are configured"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  PROJECT_ID: $PROJECT_ID"
echo "  REGION: $REGION"
echo "  REPO_NAME: $REPO_NAME"
echo ""

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found${NC}"
    echo "Please run this script from the ollama directory"
    exit 1
fi

# Option to use simple or advanced Dockerfile
if [ "$1" == "--simple" ]; then
    echo -e "${YELLOW}Using simple Dockerfile (gemma:2b only)...${NC}"
    cat << 'EOF' > Dockerfile.simple
FROM ollama/ollama

RUN (ollama serve &) && sleep 5 && ollama pull gemma:2b
EOF
    DOCKERFILE="Dockerfile.simple"
    BUILD_CONFIG="cloudbuild-simple.yaml"
else
    echo -e "${YELLOW}Using advanced Dockerfile (multiple models)...${NC}"
    DOCKERFILE="Dockerfile"
    BUILD_CONFIG="cloudbuild-ollama-deploy.yaml"
fi

# Generate the cloudbuild configuration with environment variables
echo -e "${YELLOW}Generating Cloud Build configuration...${NC}"
cat << EOF > cloudbuild-generated.yaml
# Auto-generated Cloud Build configuration for Ollama deployment
substitutions:
  _REGION: "$REGION"
  _REPO_NAME: "$REPO_NAME"
  _SERVICE_NAME: "gemma-ollama-baked-service"

steps:
  # Build the Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: 
      - 'build'
      - '-f'
      - '$DOCKERFILE'
      - '-t'
      - '\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPO_NAME}/\${_SERVICE_NAME}:latest'
      - '.'

  # Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: 
      - 'push'
      - '\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPO_NAME}/\${_SERVICE_NAME}:latest'

  # Deploy to Cloud Run with GPU
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - '\${_SERVICE_NAME}'
      - '--image=\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPO_NAME}/\${_SERVICE_NAME}:latest'
      - '--region=\${_REGION}'
      - '--platform=managed'
      - '--cpu=4'
      - '--memory=16Gi'
      - '--gpu=1'
      - '--gpu-type=nvidia-l4'
      - '--no-gpu-zonal-redundancy'
      - '--port=11434'
      - '--timeout=3600'
      - '--concurrency=4'
      - '--max-instances=2'
      - '--min-instances=1'
      - '--set-env-vars=OLLAMA_NUM_PARALLEL=4,OLLAMA_KEEP_ALIVE=24h'
      - '--no-cpu-throttling'
      - '--labels=project=agentverse,service=ollama'
      - '--allow-unauthenticated'

images:
  - '\${_REGION}-docker.pkg.dev/\${PROJECT_ID}/\${_REPO_NAME}/\${_SERVICE_NAME}:latest'

timeout: 1800s
EOF

# Submit the build
echo -e "${YELLOW}Submitting build to Cloud Build...${NC}"
echo -e "${YELLOW}This process will take 5-10 minutes...${NC}"

gcloud builds submit \
    --config cloudbuild-generated.yaml \
    --project="$PROJECT_ID" \
    .

# Check if build was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build and deployment completed successfully!${NC}"
    
    # Get the service URL
    echo -e "${YELLOW}Retrieving service URL...${NC}"
    OLLAMA_URL=$(gcloud run services describe gemma-ollama-baked-service \
        --platform=managed \
        --region=$REGION \
        --format='value(status.url)')
    
    echo -e "${GREEN}Ollama Service URL: $OLLAMA_URL${NC}"
    
    # Update set_env.sh with the new URL
    echo -e "${YELLOW}Updating environment configuration...${NC}"
    sed -i.bak "s|export OLLAMA_URL=.*|export OLLAMA_URL=\"$OLLAMA_URL\"|g" ../set_env.sh
    
    # Test the service
    echo -e "${YELLOW}Testing the service...${NC}"
    sleep 10  # Give the service a moment to fully initialize
    
    curl -s -X POST "$OLLAMA_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gemma:2b",
            "prompt": "As a Guardian of the Agentverse, what is my primary duty?",
            "stream": false
        }' | jq '.response' || echo -e "${YELLOW}Service may still be initializing. Try again in a moment.${NC}"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}Service URL: $OLLAMA_URL${NC}"
    echo -e "${GREEN}Test with: curl -X POST $OLLAMA_URL/api/generate ...${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}✗ Build failed. Check the logs above for details.${NC}"
    exit 1
fi

# Clean up temporary files
rm -f cloudbuild-generated.yaml Dockerfile.simple