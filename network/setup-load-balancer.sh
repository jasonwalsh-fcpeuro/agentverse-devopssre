#!/bin/bash
# Idempotent script to set up load balancer resources for Model Armor

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../set_env.sh"

echo "Setting up Network Endpoint Groups (NEGs) and Load Balancer resources..."

# Create sentinel directory for tracking
SENTINEL_DIR=".sentinels"
mkdir -p "$SENTINEL_DIR"

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local region_flag=${3:---region=$REGION}
    
    if gcloud compute $resource_type describe $resource_name $region_flag &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 1. Create NEGs (idempotent)
echo "Creating Network Endpoint Groups..."

if [ ! -f "$SENTINEL_DIR/neg-vllm.done" ]; then
    if resource_exists network-endpoint-groups serverless-vllm-neg; then
        echo "NEG serverless-vllm-neg already exists"
    else
        gcloud compute network-endpoint-groups create serverless-vllm-neg \
            --region=$REGION \
            --network-endpoint-type=serverless \
            --cloud-run-service=gemma-vllm-fuse-service
    fi
    touch "$SENTINEL_DIR/neg-vllm.done"
fi

if [ ! -f "$SENTINEL_DIR/neg-ollama.done" ]; then
    if resource_exists network-endpoint-groups serverless-ollama-neg; then
        echo "NEG serverless-ollama-neg already exists"
    else
        gcloud compute network-endpoint-groups create serverless-ollama-neg \
            --region=$REGION \
            --network-endpoint-type=serverless \
            --cloud-run-service=gemma-ollama-baked-service
    fi
    touch "$SENTINEL_DIR/neg-ollama.done"
fi

# 2. Create Backend Services (idempotent)
echo "Creating Backend Services..."

if [ ! -f "$SENTINEL_DIR/backend-vllm.done" ]; then
    if resource_exists backend-services vllm-backend-service; then
        echo "Backend service vllm-backend-service already exists"
    else
        gcloud compute backend-services create vllm-backend-service \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --protocol=HTTPS \
            --region=$REGION
        
        # Add backend to service
        gcloud compute backend-services add-backend vllm-backend-service \
            --network-endpoint-group=serverless-vllm-neg \
            --network-endpoint-group-region=$REGION \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/backend-vllm.done"
fi

if [ ! -f "$SENTINEL_DIR/backend-ollama.done" ]; then
    if resource_exists backend-services ollama-backend-service; then
        echo "Backend service ollama-backend-service already exists"
    else
        gcloud compute backend-services create ollama-backend-service \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --protocol=HTTPS \
            --region=$REGION
        
        # Add backend to service
        gcloud compute backend-services add-backend ollama-backend-service \
            --network-endpoint-group=serverless-ollama-neg \
            --network-endpoint-group-region=$REGION \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/backend-ollama.done"
fi

# 3. Create SSL Certificate (idempotent)
echo "Creating SSL Certificate..."

if [ ! -f "$SENTINEL_DIR/ssl-cert.done" ]; then
    # Check if certificate files exist
    if [ ! -f "agentverse.key" ] || [ ! -f "agentverse.crt" ]; then
        echo "Generating self-signed certificate..."
        
        # Generate private key
        openssl genrsa -out agentverse.key 2048
        
        # Create certificate
        openssl req -new -x509 -key agentverse.key -out agentverse.crt -days 365 \
            -subj "/C=US/ST=CA/L=MTV/O=Agentverse/OU=Guardians/CN=internal.agentverse"
    fi
    
    if resource_exists ssl-certificates agentverse-ssl-cert-self-signed; then
        echo "SSL certificate agentverse-ssl-cert-self-signed already exists"
    else
        gcloud compute ssl-certificates create agentverse-ssl-cert-self-signed \
            --certificate=agentverse.crt \
            --private-key=agentverse.key \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/ssl-cert.done"
fi

# 4. Create Proxy-Only Subnet (idempotent)
echo "Creating Proxy-Only Subnet..."

if [ ! -f "$SENTINEL_DIR/proxy-subnet.done" ]; then
    if gcloud compute networks subnets describe proxy-only-subnet --region=$REGION &>/dev/null; then
        echo "Proxy-only subnet already exists"
    else
        gcloud compute networks subnets create proxy-only-subnet \
            --purpose=REGIONAL_MANAGED_PROXY \
            --role=ACTIVE \
            --region=$REGION \
            --network=default \
            --range=192.168.0.0/26
    fi
    touch "$SENTINEL_DIR/proxy-subnet.done"
fi

# 5. Create URL Map (idempotent)
echo "Creating URL Map..."

if [ ! -f "$SENTINEL_DIR/url-map.done" ]; then
    if resource_exists url-maps agentverse-lb-url-map; then
        echo "URL map agentverse-lb-url-map already exists"
    else
        # Create the URL map
        gcloud compute url-maps create agentverse-lb-url-map \
            --default-service vllm-backend-service \
            --region=$REGION
        
        # Add path matcher
        gcloud compute url-maps add-path-matcher agentverse-lb-url-map \
            --default-service vllm-backend-service \
            --path-matcher-name=api-path-matcher \
            --path-rules='/api/*=ollama-backend-service' \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/url-map.done"
fi

# 6. Create Target HTTPS Proxy (idempotent)
echo "Creating Target HTTPS Proxy..."

if [ ! -f "$SENTINEL_DIR/https-proxy.done" ]; then
    if resource_exists target-https-proxies agentverse-lb-proxy; then
        echo "Target HTTPS proxy agentverse-lb-proxy already exists"
    else
        gcloud compute target-https-proxies create agentverse-lb-proxy \
            --url-map=agentverse-lb-url-map \
            --ssl-certificates=agentverse-ssl-cert-self-signed \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/https-proxy.done"
fi

# 7. Reserve Static IP (idempotent)
echo "Reserving Static IP..."

if [ ! -f "$SENTINEL_DIR/static-ip.done" ]; then
    if resource_exists addresses agentverse-lb-ip; then
        echo "Static IP agentverse-lb-ip already exists"
        LB_IP=$(gcloud compute addresses describe agentverse-lb-ip --region=$REGION --format="value(address)")
    else
        gcloud compute addresses create agentverse-lb-ip \
            --region=$REGION \
            --network-tier=STANDARD
        LB_IP=$(gcloud compute addresses describe agentverse-lb-ip --region=$REGION --format="value(address)")
    fi
    export LB_IP
    echo "Load Balancer IP: $LB_IP"
    touch "$SENTINEL_DIR/static-ip.done"
fi

# 8. Create Forwarding Rule (idempotent)
echo "Creating Forwarding Rule..."

if [ ! -f "$SENTINEL_DIR/forwarding-rule.done" ]; then
    if resource_exists forwarding-rules agentverse-lb-forwarding-rule; then
        echo "Forwarding rule agentverse-lb-forwarding-rule already exists"
    else
        gcloud compute forwarding-rules create agentverse-lb-forwarding-rule \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --network-tier=STANDARD \
            --target-https-proxy=agentverse-lb-proxy \
            --address=agentverse-lb-ip \
            --ports=443 \
            --region=$REGION
    fi
    touch "$SENTINEL_DIR/forwarding-rule.done"
fi

echo "Load balancer setup complete!"
echo ""
echo "Resources created:"
echo "  - NEGs: serverless-vllm-neg, serverless-ollama-neg"
echo "  - Backend Services: vllm-backend-service, ollama-backend-service"
echo "  - SSL Certificate: agentverse-ssl-cert-self-signed"
echo "  - Proxy Subnet: proxy-only-subnet"
echo "  - URL Map: agentverse-lb-url-map"
echo "  - HTTPS Proxy: agentverse-lb-proxy"
echo "  - Static IP: agentverse-lb-ip ($LB_IP)"
echo "  - Forwarding Rule: agentverse-lb-forwarding-rule"
echo ""
echo "Sentinel files stored in: $SENTINEL_DIR/"
echo ""
echo "Load Balancer URL: https://$LB_IP/"
echo "  - Default route (/) → vLLM service"
echo "  - /api/* → Ollama service"