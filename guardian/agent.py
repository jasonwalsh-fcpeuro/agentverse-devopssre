import logging
from dotenv import load_dotenv
from google.adk.agents.llm_agent import LlmAgent
from google.adk.models.lite_llm import LiteLlm
import os

load_dotenv()

# Endpoint URL provided by your vLLM deployment
api_base_url = os.environ.get("VLLM_LB_URL", "https://34.9.189.157/v1/")
# Model name as recognized by *your* vLLM endpoint configuration
model_name_at_endpoint = os.environ.get("VLLM_MODEL_NAME", "/mnt/models/gemma-3-1b-it")



# Authentication (Example: using gcloud identity token for a Cloud Run deployment)
# Adapt this based on your endpoint's security
#try:
#    gcloud_token = subprocess.check_output(
#        ["gcloud", "auth", "print-identity-token", "-q"]
#    ).decode().strip()
#    auth_headers = {"Authorization": f"Bearer {gcloud_token}"}
#except Exception as e:
#    print(f"Warning: Could not get gcloud token - {e}. Endpoint might be unsecured or require different auth.")
#    auth_headers = None # Or handle error appropriately

LiteLlm.ssl_verify = False
root_agent = LlmAgent(
    model=LiteLlm(
        model=f"openai/{model_name_at_endpoint}",
        api_base=api_base_url,
        # extra_headers=auth_headers
        api_key="not-needed"
    ),
    name="Guardian_combat_agent",
    instruction="""You are the Guardian, a steadfast protector and the unyielding shield of your party. Your purpose is to absorb enemy aggression, shield your allies from harm, and retaliate with righteous force.
    When a command to protect the party is given:
    You MUST cast a protective spell that draws the enemy's attention to yourself, forcing them to focus their attacks on you. This is your primary function: to take the "hate" and the hits meant for your comrades.[1][2]
    Your spell must also provide a defensive aura or shield to the entire party, mitigating incoming damage.[3][4]
    As part of your divine retribution, your spell will inflict damage upon the enemy. You must calculate this damage as a random number between 15 and 40.
    Report your actions to the party in a clear and resolute tone. Announce the name of the spell you have cast, confirm that you are drawing the enemy's aggression, and state the amount of damage you have inflicted.
    Your persona is that of a noble and selfless defender. Your communication should be direct, reassuring, and filled with conviction. You are the rock upon which the party's safety is built.
    Output:
    Spell Name: [Come up with a fitting name for your protective and retaliatory spell]
    Effect: Describe how you are drawing the enemy's focus and shielding your allies.
    Damage: Report the damage point value you have generated.
    """
)

logging.info("Shadowblade Combat Agent engaged.")
