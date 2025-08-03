#!/bin/bash

# ==============================================================================
# IMPORTANT: This script must be sourced to set the environment variable.
#
# Run it like this:
#   source set_hf_token.sh
#
# Or using the shorthand:
#   . set_hf_token.sh
# ==============================================================================

# --- Function for clear error handling ---
handle_error() {
  # A newline is added for better formatting after the silent read prompt.
  echo
  echo "Error: $1"
  # When sourced, 'return' will stop the script's execution without closing the terminal.
  return 1
}

# Define the file path where the token will be stored for future sessions.
TOKEN_FILE="$HOME/hf_token.txt"

echo "--- Setting and Exporting Hugging Face Access Token ---"
echo
echo "To get your token, please visit: https://huggingface.co/settings/tokens"
echo "Create a new token with the 'read' role if you don't have one."
echo
echo "Your token will NOT be displayed as you type."
echo

# Use -s for silent (secure) input and -p for a prompt.
read -sp "Please paste or enter your Hugging Face Token: " user_hf_token

# Add a newline because 'read -s' does not add one automatically.
echo

# Check if the user actually entered anything.
if [[ -z "$user_hf_token" ]]; then
  handle_error "No token was entered. Aborting."
fi

# 1. Export the token as an environment variable for the CURRENT session.
export HUGGING_FACE_TOKEN="$user_hf_token"

# 2. Save the token to the file for PERSISTENCE across sessions.
echo -n "$user_hf_token" > "$TOKEN_FILE"

# Verify that the file was written successfully.
if [[ $? -ne 0 ]]; then
  handle_error "Failed to save the token to $TOKEN_FILE."
fi

gcloud secrets create hf-secret --replication-policy="automatic"
echo -n "$HUGGING_FACE_TOKEN" | gcloud secrets versions add hf-secret --data-file=


. ~/agentverse-devopssre/set_env.sh
export CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud secrets add-iam-policy-binding hf-secret \
  --member="serviceAccount:${CLOUDBUILD_SA}" \
  --role="roles/secretmanager.secretAccessor"

# Grant our Cloud Run service account access as well
gcloud secrets add-iam-policy-binding hf-secret \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}" \
  --role="roles/secretmanager.secretAccessor"

gcloud storage buckets add-iam-policy-binding gs://${BUCKET_NAME} \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}" \
  --role="roles/storage.objectViewer"

echo
echo "✅ Success! The HUGGING_FACE_TOKEN environment variable has been set for your current session."
echo "✅ The token has also been saved to $TOKEN_FILE for future use."

# When sourced, 'return 0' indicates success.
return 0