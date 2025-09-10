#!/bin/bash
# Complete cleanup script for AgentVerse infrastructure

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/set_env.sh"

echo "🧹 Starting AgentVerse infrastructure cleanup..."
echo ""
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Function to safely delete resources
safe_delete() {
    local command="$1"
    local resource_name="$2"
    
    echo "Deleting $resource_name..."
    if eval "$command" 2>/dev/null; then
        echo "  ✅ $resource_name deleted"
    else
        echo "  ⚠️ $resource_name not found or already deleted"
    fi
}

echo "🛑 Phase 1: Deleting Cloud Run Services"
echo "----------------------------------------"

safe_delete "gcloud run services delete guardian-agent --region=${REGION} --quiet" "Guardian Agent"
safe_delete "gcloud run services delete gemma-ollama-baked-service --region=${REGION} --quiet" "Ollama Service"
safe_delete "gcloud run services delete gemma-vllm-fuse-service --region=${REGION} --quiet" "vLLM Service" 
safe_delete "gcloud run services delete agentverse-dungeon --region=${REGION} --quiet" "Dungeon Service"

echo ""
echo "🛡️ Phase 2: Deleting Security Components"
echo "----------------------------------------"

safe_delete "gcloud model-armor templates delete ${ARMOR_ID} --location=${REGION} --quiet" "Model Armor Template"
safe_delete "gcloud service-extensions lb-traffic-extensions delete chain-model-armor-unified --location=${REGION} --quiet" "Service Extension"

echo ""
echo "⚖️ Phase 3: Deleting Load Balancer Components"
echo "--------------------------------------------"

safe_delete "gcloud compute forwarding-rules delete agentverse-forwarding-rule --region=${REGION} --quiet" "Forwarding Rule"
safe_delete "gcloud compute target-https-proxies delete agentverse-https-proxy --region=${REGION} --quiet" "HTTPS Proxy"
safe_delete "gcloud compute url-maps delete agentverse-lb-url-map --region=${REGION} --quiet" "URL Map"
safe_delete "gcloud compute ssl-certificates delete agentverse-ssl-cert-self-signed --region=${REGION} --quiet" "SSL Certificate"
safe_delete "gcloud compute backend-services delete vllm-backend-service --region=${REGION} --quiet" "vLLM Backend Service"
safe_delete "gcloud compute backend-services delete ollama-backend-service --region=${REGION} --quiet" "Ollama Backend Service"
safe_delete "gcloud compute network-endpoint-groups delete serverless-vllm-neg --region=${REGION} --quiet" "vLLM NEG"
safe_delete "gcloud compute network-endpoint-groups delete serverless-ollama-neg --region=${REGION} --quiet" "Ollama NEG"
safe_delete "gcloud compute addresses delete agentverse-lb-ip --region=${REGION} --quiet" "Static IP Address"
safe_delete "gcloud compute networks subnets delete proxy-only-subnet --region=${REGION} --quiet" "Proxy Subnet"

echo ""
echo "📦 Phase 4: Deleting Storage and Secrets"
echo "---------------------------------------"

safe_delete "gcloud artifacts repositories delete ${REPO_NAME} --location=${REGION} --quiet" "Artifact Repository"
safe_delete "gcloud storage rm -r gs://${BUCKET_NAME}" "Storage Bucket"
safe_delete "gcloud secrets delete hf-secret --quiet" "Hugging Face Secret"
safe_delete "gcloud secrets delete vllm-monitor-config --quiet" "vLLM Monitor Config Secret"

echo ""
echo "🧽 Phase 5: Cleaning Local Files (Optional)"
echo "------------------------------------------"
echo "To clean up local files, run:"
echo "  rm -rf $(pwd)"
echo "  rm -rf ~/agentverse-dungeon"
echo "  rm -rf ~/a2a-inspector"
echo "  rm -f ~/project_id.txt"
echo ""

echo "✅ AgentVerse cleanup completed!"
echo ""
echo "Summary:"
echo "  - All Cloud Run services deleted"
echo "  - Model Armor and security components removed"
echo "  - Load balancer infrastructure dismantled"
echo "  - Storage and secrets cleaned up"
echo ""
echo "Your Google Cloud project is now clean and ready for new adventures! 🚀"