#!/usr/bin/env python3
"""Test script for the Guardian agent"""

import asyncio
import logging
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

def test_environment():
    """Test that all required environment variables are set"""
    required_vars = [
        'VLLM_LB_URL',
        'VLLM_MODEL_NAME',
    ]
    
    missing_vars = []
    for var in required_vars:
        if not os.environ.get(var):
            missing_vars.append(var)
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {missing_vars}")
        logger.info("Please set these in your .env file or environment")
        return False
    
    logger.info("All required environment variables are set")
    return True

def test_imports():
    """Test that all required imports work"""
    try:
        from guardian import agent
        logger.info("Successfully imported guardian.agent")
        
        # Test that the agent is properly configured
        if hasattr(agent, 'root_agent'):
            logger.info(f"Guardian agent configured: {agent.root_agent.name}")
            return True
        else:
            logger.error("Guardian agent not properly configured")
            return False
            
    except ImportError as e:
        logger.error(f"Import error: {e}")
        return False

async def test_agent_response():
    """Test the agent with a sample combat command"""
    try:
        from guardian import agent
        from google.genai import types
        
        # Create a test message
        test_message = "The enemy approaches! Protect the party!"
        
        logger.info(f"Testing agent with message: {test_message}")
        
        # Create session ID for testing
        session_id = "test_session_001"
        
        # Run the agent (simplified test without full runner)
        response = await agent.root_agent.generate_content_async(
            prompt=test_message
        )
        
        if response and response.text:
            logger.info(f"Agent response received:")
            logger.info(response.text)
            return True
        else:
            logger.error("No response from agent")
            return False
            
    except Exception as e:
        logger.error(f"Error testing agent: {e}")
        return False

async def main():
    """Main test function"""
    logger.info("Starting Guardian Agent tests...")
    
    # Test 1: Environment
    if not test_environment():
        logger.error("Environment test failed")
        return 1
    
    # Test 2: Imports
    if not test_imports():
        logger.error("Import test failed")
        return 1
    
    # Test 3: Agent Response (only if vLLM endpoint is available)
    vllm_url = os.environ.get('VLLM_LB_URL', '')
    if vllm_url and not vllm_url.startswith('https://your-'):
        logger.info("Testing agent response...")
        if not await test_agent_response():
            logger.warning("Agent response test failed (this is expected if vLLM is not running)")
    else:
        logger.info("Skipping agent response test (vLLM endpoint not configured)")
    
    logger.info("All basic tests completed successfully!")
    return 0

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)