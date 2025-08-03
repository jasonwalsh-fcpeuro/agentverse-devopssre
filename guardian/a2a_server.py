from a2a.server.apps import A2AStarletteApplication
from a2a.types import AgentCard, AgentCapabilities, AgentSkill
from a2a.server.tasks import InMemoryTaskStore
from a2a.server.request_handlers import DefaultRequestHandler
from google.adk.agents.llm_agent import LlmAgent
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.adk.artifacts import InMemoryArtifactService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
import os
import logging
from dotenv import load_dotenv
from guardian.agent_executor import GuardianAgentExecutor
import uvicorn
from guardian import agent



load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

host=os.environ.get("A2A_HOST", "localhost")
port=int(os.environ.get("A2A_PORT",10003))
PUBLIC_URL=os.environ.get("PUBLIC_URL")




class GuardianAgent:
    """An agent representing the Shadowblade character in a game, responding to battlefield commands."""
    SUPPORTED_CONTENT_TYPES = ["text", "text/plain"]

    def __init__(self):
        self._agent = self._build_agent()
        self.runner = Runner(
            app_name=self._agent.name,
            agent=self._agent,
            artifact_service=InMemoryArtifactService(),
            session_service=InMemorySessionService(),
            memory_service=InMemoryMemoryService(),
        )
        capabilities = AgentCapabilities(streaming=True)
        skill = AgentSkill(
            id="protective_stance",
            name="Guardian Agent",
            description="""
            This skill enables the Guardian to draw enemy aggression, providing a protective aura
            to the party and retaliating with a divine force. It's the Guardian's primary combat
            ability to shield allies and inflict damage upon foes.
            """,
            tags=["game", "tank", "security", "modelarmor", "observibility"],
            examples=[
                "Dogma: The Zealot of Stubborn Conventions strikes, Weakness: Revolutionary Rewrite, protect us!",
            ],
        )
        self.agent_card = AgentCard(
            name="Guardian",
            description="""
            A steadfast protector and the unyielding shield of your party. The Guardian absorbs
            enemy aggression, shields allies from harm, and retaliates with righteous force.
            They are the rock upon which the party's safety is built.
            """,
            url=f"{PUBLIC_URL}",
            version="1.0.0",
            defaultInputModes=GuardianAgent.SUPPORTED_CONTENT_TYPES,
            defaultOutputModes=GuardianAgent.SUPPORTED_CONTENT_TYPES,
            capabilities=capabilities,
            skills=[skill],
        )

    def get_processing_message(self) -> str:
        return "Processing the planning request..."

    def _build_agent(self) -> LlmAgent:
        """Builds the LLM agent for the night out planning agent."""
        return agent.root_agent


if __name__ == '__main__':
    try:
        GuardianAgent = GuardianAgent()

        request_handler = DefaultRequestHandler(
            agent_executor=GuardianAgentExecutor(GuardianAgent.runner,GuardianAgent.agent_card),
            task_store=InMemoryTaskStore(),
        )

        server = A2AStarletteApplication(
            agent_card=GuardianAgent.agent_card,
            http_handler=request_handler,
        )
        logger.info(f"Attempting to start server with Agent Card: {GuardianAgent.agent_card.name}")
        logger.info(f"Server object created: {server}")

        uvicorn.run(server.build(), host='0.0.0.0', port=port)
    except Exception as e:
        logger.error(f"An error occurred during server startup: {e}")
        exit(1)
