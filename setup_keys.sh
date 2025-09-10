#!/bin/bash

# Secure API Key Setup Script for AgentVerse
# This script helps you securely configure API keys and tokens

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    AgentVerse API Key Setup                                  ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to securely prompt for input
secure_read() {
    local prompt="$1"
    local var_name="$2"
    echo -n -e "${YELLOW}$prompt${NC}"
    read -s value
    echo ""
    eval "$var_name='$value'"
}

# Function to prompt for regular input
regular_read() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    echo -n -e "${YELLOW}$prompt${NC}"
    if [ -n "$default" ]; then
        echo -n " [default: $default]: "
    else
        echo -n ": "
    fi
    read value
    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    eval "$var_name='$value'"
}

# Check if .env already exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env file already exists${NC}"
    echo -n "Do you want to overwrite it? [y/N]: "
    read overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "Exiting without changes."
        exit 0
    fi
    echo ""
fi

echo -e "${GREEN}Setting up your API keys securely...${NC}"
echo ""

# Hugging Face Token
echo -e "${BLUE}📚 Hugging Face Setup${NC}"
echo "Get your token from: https://huggingface.co/settings/tokens"
secure_read "Enter your Hugging Face token (hidden): " HF_TOKEN
echo ""

# Google Gemini API Key
echo -e "${BLUE}🤖 Google Gemini Setup${NC}"
echo "Get your API key from: https://aistudio.google.com/app/apikey"
secure_read "Enter your Gemini API key (hidden): " GEMINI_API_KEY
echo ""

# Project Configuration
echo -e "${BLUE}☁️  Google Cloud Configuration${NC}"
regular_read "Enter your Google Cloud Project ID" GOOGLE_CLOUD_PROJECT
regular_read "Path to service account key (optional)" GOOGLE_APPLICATION_CREDENTIALS
echo ""

# Optional API Keys
echo -e "${BLUE}🔧 Optional API Keys${NC}"
echo "Leave blank to skip these:"
secure_read "OpenAI API Key (optional, hidden): " OPENAI_API_KEY
echo ""
secure_read "Anthropic API Key (optional, hidden): " ANTHROPIC_API_KEY
echo ""

# Model Configuration
echo -e "${BLUE}⚙️  Model Configuration${NC}"
regular_read "Ollama Base URL" OLLAMA_BASE_URL "http://localhost:11434"
regular_read "Ollama Parallel Requests" OLLAMA_NUM_PARALLEL "4"
regular_read "Default Model Temperature" MODEL_TEMPERATURE "0.7"
regular_read "Default Max Tokens" MODEL_MAX_TOKENS "512"
echo ""

# Create .env file
echo -e "${YELLOW}Creating .env file...${NC}"

cat > .env << EOF
# AgentVerse Environment Variables
# Generated on $(date)
# NEVER commit this file to version control

# Hugging Face API Token
HF_TOKEN=$HF_TOKEN

# Google Gemini API Key  
GEMINI_API_KEY=$GEMINI_API_KEY

# Google Cloud Project Configuration
GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS

# OpenAI API Key
OPENAI_API_KEY=$OPENAI_API_KEY

# Anthropic API Key
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY

# Ollama Configuration
OLLAMA_BASE_URL=$OLLAMA_BASE_URL
OLLAMA_NUM_PARALLEL=$OLLAMA_NUM_PARALLEL

# vLLM Configuration
VLLM_MODEL_NAME=google/gemma-2-2b-it
VLLM_MAX_MODEL_LEN=4096

# Model specific settings
MODEL_TEMPERATURE=$MODEL_TEMPERATURE
MODEL_MAX_TOKENS=$MODEL_MAX_TOKENS
EOF

# Set secure permissions
chmod 600 .env

echo -e "${GREEN}✓ .env file created successfully!${NC}"
echo -e "${GREEN}✓ File permissions set to 600 (owner read/write only)${NC}"
echo ""

# Verify .env is ignored
if grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo -e "${GREEN}✓ .env is properly ignored by git${NC}"
else
    echo -e "${YELLOW}⚠️  Adding .env to .gitignore for safety${NC}"
    echo ".env" >> .gitignore
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Source the environment: source .env"
echo "2. Test your configuration: make validate"
echo "3. Deploy services: make deploy"
echo ""
echo -e "${RED}IMPORTANT SECURITY REMINDERS:${NC}"
echo -e "${RED}• Never commit .env files to version control${NC}"
echo -e "${RED}• Never share API keys in chat or documentation${NC}"
echo -e "${RED}• Regularly rotate your API keys${NC}"
echo -e "${RED}• Use least-privilege access when possible${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"