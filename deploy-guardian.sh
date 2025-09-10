#!/bin/bash
# Deploy Guardian Agent using Cloud Build

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/set_env.sh"

echo "Starting Guardian Agent deployment pipeline..."
echo ""
echo "Configuration:"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Repository: $REPO_NAME"
echo "  vLLM URL: https://$LB_IP/v1"
echo ""

# Get load balancer IP if not set
if [ -z "$LB_IP" ]; then
    echo "Retrieving Load Balancer IP..."
    LB_IP=$(gcloud compute addresses describe agentverse-lb-ip --region=$REGION --format="value(address)" 2>/dev/null || echo "")
    if [ -z "$LB_IP" ]; then
        echo "Warning: Load Balancer IP not found. Agent may not connect to vLLM."
    else
        export LB_IP
        echo "Load Balancer IP: $LB_IP"
    fi
fi

# Set vLLM LB URL
export VLLM_LB_URL="https://$LB_IP/v1"

# Trigger Cloud Build
echo "Triggering Cloud Build pipeline..."
gcloud builds submit . \
    --config=cloudbuild.yaml \
    --project="${PROJECT_ID}" \
    --substitutions="_VLLM_LB_URL=${VLLM_LB_URL},VLLM_URL=${VLLM_URL},VLLM_MODEL_NAME=${VLLM_MODEL_NAME},PROJECT_ID=${PROJECT_ID},REGION=${REGION},REPO_NAME=${REPO_NAME},PUBLIC_URL=${PUBLIC_URL}"

echo ""
echo "Build submitted successfully!"
echo ""

# Wait for deployment to complete
echo "Waiting for deployment to complete..."
sleep 30

# Get the deployed service URL
AGENT_URL=$(gcloud run services describe guardian-agent --platform managed --region $REGION --format 'value(status.url)' 2>/dev/null || echo "")

if [ -n "$AGENT_URL" ]; then
    echo ""
    echo "Guardian Agent deployed successfully!"
    echo "Agent URL: $AGENT_URL"
    echo ""
    echo "You can test the agent using:"
    echo "  1. A2A Inspector (recommended)"
    echo "  2. Direct API calls"
    echo ""
    echo "To wake up the vLLM service (if cold):"
    echo "  curl -k -X POST \"https://$LB_IP/v1/completions\" \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"model\": \"/mnt/models/gemma-3-1b-it\", \"prompt\": \"Hello\", \"max_tokens\": 10}'"
else
    echo "Warning: Could not retrieve agent URL. Check Cloud Run console for status."
fi