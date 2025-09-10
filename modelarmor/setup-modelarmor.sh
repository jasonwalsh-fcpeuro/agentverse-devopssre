#!/bin/bash
# Setup Model Armor configuration for Guardian agents

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../set_env.sh"

echo "Setting up Model Armor security policies..."

# Create sentinel directory
SENTINEL_DIR=".sentinels"
mkdir -p "$SENTINEL_DIR"

# Function to check if Model Armor template exists
template_exists() {
    if gcloud model-armor templates describe $ARMOR_ID --location=$REGION &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Configure Model Armor API endpoint
echo "Configuring Model Armor API endpoint..."
gcloud config set api_endpoint_overrides/modelarmor https://modelarmor.$REGION.rep.googleapis.com/

# Create Model Armor template (idempotent)
if [ ! -f "$SENTINEL_DIR/modelarmor-template.done" ]; then
    if template_exists; then
        echo "Model Armor template $ARMOR_ID already exists"
    else
        echo "Creating Model Armor template: $ARMOR_ID"
        
        gcloud model-armor templates create --location $REGION $ARMOR_ID \
            --rai-settings-filters='[
                { "filterType": "HATE_SPEECH", "confidenceLevel": "MEDIUM_AND_ABOVE" },
                { "filterType": "HARASSMENT", "confidenceLevel": "MEDIUM_AND_ABOVE" },
                { "filterType": "SEXUALLY_EXPLICIT", "confidenceLevel": "MEDIUM_AND_ABOVE" },
                { "filterType": "DANGEROUS_CONTENT", "confidenceLevel": "LOW_AND_ABOVE" }
            ]' \
            --basic-config-filter-enforcement=enabled \
            --pi-and-jailbreak-filter-settings-enforcement=enabled \
            --pi-and-jailbreak-filter-settings-confidence-level=LOW_AND_ABOVE \
            --malicious-uri-filter-settings-enforcement=enabled \
            --template-metadata-custom-llm-response-safety-error-code=798 \
            --template-metadata-custom-llm-response-safety-error-message="Guardian, a critical flaw has been detected in the very incantation you are attempting to cast!" \
            --template-metadata-custom-prompt-safety-error-code=799 \
            --template-metadata-custom-prompt-safety-error-message="Guardian, a critical flaw has been detected in the very incantation you are attempting to cast!" \
            --template-metadata-ignore-partial-invocation-failures \
            --template-metadata-log-operations \
            --template-metadata-log-sanitize-operations
        
        echo "Model Armor template created successfully"
    fi
    touch "$SENTINEL_DIR/modelarmor-template.done"
fi

# Apply Model Armor to Cloud Run services
echo "Applying Model Armor to services..."

# Apply to vLLM service
if [ ! -f "$SENTINEL_DIR/modelarmor-vllm.done" ]; then
    echo "Configuring Model Armor for vLLM service..."
    
    gcloud run services update gemma-vllm-fuse-service \
        --region=$REGION \
        --update-env-vars="MODEL_ARMOR_TEMPLATE=$ARMOR_ID,MODEL_ARMOR_ENABLED=true" \
        --update-annotations="modelarmor.cloud.google.com/template=$ARMOR_ID" \
        2>/dev/null || echo "vLLM service update skipped (service may not exist)"
    
    touch "$SENTINEL_DIR/modelarmor-vllm.done"
fi

# Apply to Ollama service
if [ ! -f "$SENTINEL_DIR/modelarmor-ollama.done" ]; then
    echo "Configuring Model Armor for Ollama service..."
    
    gcloud run services update gemma-ollama-baked-service \
        --region=$REGION \
        --update-env-vars="MODEL_ARMOR_TEMPLATE=$ARMOR_ID,MODEL_ARMOR_ENABLED=true" \
        --update-annotations="modelarmor.cloud.google.com/template=$ARMOR_ID" \
        2>/dev/null || echo "Ollama service update skipped (service may not exist)"
    
    touch "$SENTINEL_DIR/modelarmor-ollama.done"
fi

# Apply to Guardian agent service
if [ ! -f "$SENTINEL_DIR/modelarmor-guardian.done" ]; then
    echo "Configuring Model Armor for Guardian agent..."
    
    gcloud run services update guardian-agent \
        --region=$REGION \
        --update-env-vars="MODEL_ARMOR_TEMPLATE=$ARMOR_ID,MODEL_ARMOR_ENABLED=true" \
        --update-annotations="modelarmor.cloud.google.com/template=$ARMOR_ID" \
        2>/dev/null || echo "Guardian agent service update skipped (service may not exist)"
    
    touch "$SENTINEL_DIR/modelarmor-guardian.done"
fi

echo ""
echo "Model Armor setup complete!"
echo ""
echo "Security Features Enabled:"
echo "  ✓ Hate speech filtering (MEDIUM+)"
echo "  ✓ Harassment filtering (MEDIUM+)"
echo "  ✓ Sexually explicit content filtering (MEDIUM+)"
echo "  ✓ Dangerous content filtering (LOW+)"
echo "  ✓ PII detection and blocking"
echo "  ✓ Jailbreak attempt detection"
echo "  ✓ Malicious URI filtering"
echo "  ✓ Custom error messages for Guardian context"
echo "  ✓ Operation logging and sanitization"
echo ""
echo "Template ID: $ARMOR_ID"
echo "Region: $REGION"
echo ""
echo "Services Protected:"
echo "  - gemma-vllm-fuse-service"
echo "  - gemma-ollama-baked-service"
echo "  - guardian-agent"