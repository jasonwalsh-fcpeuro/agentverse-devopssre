#!/usr/bin/env python3
"""Test script for Guardian Agent local testing"""

import os
import sys
import json
import asyncio
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

# Set environment variables before imports
os.environ["SSL_VERIFY"] = "False"

import logging
from guardian import agent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def test_guardian_combat():
    """Test the Guardian agent with a combat scenario"""
    
    # Test prompts
    test_scenarios = [
        {
            "name": "Procrastination Attack",
            "prompt": "We've been trapped by 'Procrastination'. Its weakness is 'Elegant Sufficiency'. Break us out!",
            "expected": "combat response"
        },
        {
            "name": "Perfectionism Spectre",
            "prompt": "A chilling wave of scrutiny washes over the Citadel.... The Spectre of Perfectionism is attacking!",
            "expected": "combat response"
        },
        {
            "name": "Standard Protection",
            "prompt": "The enemy approaches! Protect the party!",
            "expected": "protection spell"
        }
    ]
    
    logger.info("Testing Guardian Agent locally...")
    logger.info(f"Agent Name: {agent.root_agent.name}")
    
    for scenario in test_scenarios:
        logger.info(f"\n{'='*60}")
        logger.info(f"Testing: {scenario['name']}")
        logger.info(f"Prompt: {scenario['prompt']}")
        logger.info(f"{'='*60}")
        
        try:
            # Generate response from agent
            response = await agent.root_agent.generate_content_async(
                prompt=scenario['prompt']
            )
            
            if response and response.text:
                logger.info(f"Guardian Response:")
                logger.info(response.text)
                logger.info(f"\n✅ Test passed: {scenario['name']}")
            else:
                logger.error(f"❌ No response for: {scenario['name']}")
                
        except Exception as e:
            logger.error(f"❌ Test failed: {scenario['name']}")
            logger.error(f"Error: {e}")
    
    logger.info("\n" + "="*60)
    logger.info("Local testing complete!")


if __name__ == "__main__":
    # Check if vLLM URL is set
    vllm_url = os.environ.get("VLLM_LB_URL")
    if not vllm_url or vllm_url == "/v1":
        logger.warning("VLLM_LB_URL not properly set. Agent may not connect to vLLM.")
        logger.info("Set it with: export VLLM_LB_URL='https://<LB_IP>/v1'")
    else:
        logger.info(f"Using vLLM endpoint: {vllm_url}")
    
    # Run tests
    asyncio.run(test_guardian_combat())