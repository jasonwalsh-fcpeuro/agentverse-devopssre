#!/bin/bash
# Create service extension for Model Armor integration with load balancer

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../set_env.sh"

echo "Creating Model Armor service extension configuration..."

# Create service extension YAML
cat > service_extension.yaml <<EOF
name: model-armor-unified-ext
loadBalancingScheme: EXTERNAL_MANAGED
forwardingRules:
- https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/regions/${REGION}/forwardingRules/agentverse-forwarding-rule
extensionChains:
- name: "chain-model-armor-unified"
  matchCondition:
    celExpression: 'request.path.startsWith("/v1/") || request.path.startsWith("/api/")'
  extensions:
  - name: model-armor-interceptor
    service: modelarmor.${REGION}.rep.googleapis.com
    failOpen: true
    supportedEvents:
    - REQUEST_HEADERS
    - REQUEST_BODY
    - RESPONSE_BODY
    - REQUEST_TRAILERS
    - RESPONSE_TRAILERS
    timeout: 10s
    metadata:
      model_armor_settings: |
        [
          {
            "model": "/mnt/models/gemma-3-1b-it",
            "model_response_template_id": "projects/${PROJECT_ID}/locations/${REGION}/templates/${ARMOR_ID}",
            "user_prompt_template_id": "projects/${PROJECT_ID}/locations/${REGION}/templates/${ARMOR_ID}"
          },
          {
            "model": "gemma:2b",
            "model_response_template_id": "projects/${PROJECT_ID}/locations/${REGION}/templates/${ARMOR_ID}",
            "user_prompt_template_id": "projects/${PROJECT_ID}/locations/${REGION}/templates/${ARMOR_ID}"
          }
        ]
EOF

echo "Service extension configuration created: service_extension.yaml"

# Import the service extension
echo "Importing service extension to load balancer..."

if gcloud service-extensions lb-traffic-extensions describe chain-model-armor-unified \
    --location=$REGION &>/dev/null; then
    echo "Service extension chain-model-armor-unified already exists, updating..."
    gcloud service-extensions lb-traffic-extensions import chain-model-armor-unified \
        --source=service_extension.yaml \
        --location=$REGION \
        --force
else
    echo "Creating new service extension chain-model-armor-unified..."
    gcloud service-extensions lb-traffic-extensions import chain-model-armor-unified \
        --source=service_extension.yaml \
        --location=$REGION
fi

echo ""
echo "Model Armor service extension configured successfully!"
echo ""
echo "Extension Details:"
echo "  Name: model-armor-unified-ext"
echo "  Chain: chain-model-armor-unified"
echo "  Match: /v1/* and /api/* paths"
echo "  Service: modelarmor.${REGION}.rep.googleapis.com"
echo "  Models Protected:"
echo "    - /mnt/models/gemma-3-1b-it (vLLM)"
echo "    - gemma:2b (Ollama)"
echo ""
echo "The Model Armor interceptor will now:"
echo "  ✓ Validate all incoming prompts"
echo "  ✓ Filter harmful content"
echo "  ✓ Detect PII and jailbreak attempts"
echo "  ✓ Log security events"
echo "  ✓ Apply custom Guardian-themed error messages"