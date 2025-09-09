#!/bin/bash

# This script starts the Cloud Build cache warming process in the background.
# It assumes you have already sourced a script like 'set_gcp_env.sh'
# to set the required environment variables.

echo "--- Starting GCS FUSE Cache Warming Build ---"

# 1. Prerequisite Check: Ensure necessary variables are set
# This makes the script safer and prevents errors.
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$REPO_NAME" ]; then
  echo "Error: One or more required environment variables are not set." >&2
  echo "Please ensure PROJECT_ID, REGION, and REPO_NAME are exported." >&2
  echo "You may need to run 'source ./set_env.sh' first." >&2
  exit 1
fi

# 2. Define the config file name
CONFIG_FILE="cloudbuild-cache-warmup.yaml"

# 3. Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Cloud Build config file not found at: $CONFIG_FILE" >&2
  exit 1
fi

echo "Submitting build from '$CONFIG_FILE' to project '$PROJECT_ID'..."
echo "This job will run in the background. The Build ID and Log URL will appear below."

# 4. Submit the build to Google Cloud Build in the background
# The '&' at the end runs the command as a background job.
# We redirect stdout and stderr to a log file to keep the terminal clean,
# and we print the PID (Process ID) of the background job.
gcloud builds submit --config "$CONFIG_FILE" --substitutions=_REGION="${REGION}",_REPO_NAME="${REPO_NAME}" > warmup_build.log 2>&1 &
BG_PID=$!

# 5. Provide follow-up instructions
echo ""
echo "Cache warming build submitted as a background job with PID: $BG_PID"
echo "You can view live output in 'warmup_build.log' by running:"
echo "tail -f warmup_build.log"
echo ""
echo "To check the status of all builds, run:"
echo "gcloud builds list --project=$PROJECT_ID --region=global"
echo ""
echo "--- Script Finished ---"