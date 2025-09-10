#!/bin/bash
# Configure IAM permissions for Model Armor

set -e

# Source environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../set_env.sh"

echo "Configuring IAM permissions for Model Armor..."

# Service account for Model Armor
SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-dep.iam.gserviceaccount.com"

echo "Service Account: $SERVICE_ACCOUNT"
echo ""

# Define IAM roles needed
declare -a ROLES=(
    "roles/container.admin"
    "roles/modelarmor.calloutUser"
    "roles/serviceusage.serviceUsageConsumer"
    "roles/modelarmor.user"
    "roles/logging.logWriter"
    "roles/monitoring.metricWriter"
)

# Grant IAM roles (idempotent)
for ROLE in "${ROLES[@]}"; do
    echo "Granting $ROLE..."
    
    # Check if binding already exists
    if gcloud projects get-iam-policy $PROJECT_ID \
        --flatten="bindings[].members" \
        --filter="bindings.role=$ROLE AND bindings.members=serviceAccount:$SERVICE_ACCOUNT" \
        --format="value(bindings.role)" | grep -q "$ROLE"; then
        echo "  ✓ Already has $ROLE"
    else
        gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SERVICE_ACCOUNT" \
            --role="$ROLE" \
            --quiet
        echo "  ✓ Granted $ROLE"
    fi
done

echo ""
echo "IAM configuration complete!"
echo ""
echo "Service Account: $SERVICE_ACCOUNT"
echo "Roles Granted:"
for ROLE in "${ROLES[@]}"; do
    echo "  ✓ $ROLE"
done