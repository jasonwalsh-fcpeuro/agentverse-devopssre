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

# Check if the secret exists and delete it if it does.
if gcloud secrets describe hf-secret &>/dev/null; then
  echo "Secret 'hf-secret' already exists. Deleting it."
  gcloud secrets delete hf-secret --quiet
fi

gcloud secrets create hf-secret --replication-policy="automatic"
echo -n "$HUGGING_FACE_TOKEN" | gcloud secrets versions add hf-secret --data-file=-

# Source environment variables from the set_env.sh file.
# Make sure this file exists and is executable.
if [ -f ~/agentverse-devopssre/set_env.sh ]; then
  . ~/agentverse-devopssre/set_env.sh
else
  handle_error "Environment setup file not found: ~/agentverse-devopssre/set_env.sh"
fi


export CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# --- Add validation checks for required variables ---
if [[ -z "$PROJECT_NUMBER" || -z "$SERVICE_ACCOUNT_NAME" || -z "$BUCKET_NAME" ]]; then
  handle_error "One or more required environment variables (PROJECT_NUMBER, SERVICE_ACCOUNT_NAME, BUCKET_NAME) are not set. Please check set_env.sh."
fi


gcloud secrets add-iam-policy-binding hf-secret \
  --member="serviceAccount:${CLOUDBUILD_SA}" \
  --role="roles/secretmanager.secretAccessor"

# Grant our Cloud Run service account access as well
gcloud secrets add-iam-policy-binding hf-secret \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}" \
  --role="roles/secretmanager.secretAccessor"


echo
echo "✅ Success! The HUGGING_FACE_TOKEN environment variable has been set for your current session."
echo "✅ The token has also been saved to $TOKEN_FILE for future use."
echo "✅ IAM policies for Secret Manager and Storage Bucket have been updated."

# When sourced, 'return 0' indicates success.
return 0