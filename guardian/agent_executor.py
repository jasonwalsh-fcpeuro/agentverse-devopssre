import logging
from typing import TYPE_CHECKING
from datetime import datetime, timezone

from a2a.server.agent_execution import AgentExecutor
from a2a.server.agent_execution.context import RequestContext
from a2a.server.events.event_queue import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import (
    AgentCard,
    FilePart,
    FileWithBytes,
    FileWithUri,
    Part,
    TaskState,
    TextPart,
    UnsupportedOperationError,
)
from a2a.utils.errors import ServerError
from google.adk import Runner
from google.genai import types
from exceptiongroup import ExceptionGroup
from opentelemetry import trace
from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
from opentelemetry.sdk.trace import export
from opentelemetry.sdk.trace import TracerProvider
import os

if TYPE_CHECKING:
    from google.adk.sessions.session import Session


logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Observerability 
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
provider = TracerProvider()
processor = export.BatchSpanProcessor(
    CloudTraceSpanExporter(project_id=PROJECT_ID)
)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)


if TYPE_CHECKING:
    from google.adk.sessions.session import Session

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Constants
DEFAULT_USER_ID = 'self'
MAX_RETRIES = 1

class GuardianAgentExecutor(AgentExecutor):
    def __init__(self, runner: Runner, card: AgentCard):
        self.runner = runner
        self._card = card
        self._active_sessions: set[str] = set()

    async def _process_request(
        self,
        new_message: types.Content,
        session_id: str,
        task_updater: TaskUpdater,
        retry_count: int = 0,
    ) -> None:
        try:
            # STEP 1: Always ensure the session exists. This is the non-negotiable
            # fix for the "Session not found" error.
            await self._upsert_session(session_id)

            if retry_count == 0:
                self._active_sessions.add(session_id)

            # STEP 2: Now that we know the session exists, call the runner.
            async for event in self.runner.run_async(
                session_id=session_id,
                user_id=DEFAULT_USER_ID,
                new_message=new_message,
            ):
                if event.is_final_response():
                    parts = [ convert_genai_part_to_a2a(part) for part in event.content.parts if (part.text or part.file_data or part.inline_data) ]
                    await task_updater.add_artifact(parts)
                    await task_updater.update_status(TaskState.completed, final=True)
                    self._active_sessions.discard(session_id.split('_error_')[0])
                    break
                if not event.get_function_calls():
                     await task_updater.update_status( TaskState.working, message=task_updater.new_agent_message( [ convert_genai_part_to_a2a(part) for part in event.content.parts if part.text ],),)

        except Exception as e:
            # STEP 3: Handle any other errors (like BadRequestError) with the robust
            # "Orphan and Retry" strategy.
            logger.error(f"An exception occurred in session '{session_id}' (attempt {retry_count + 1}): {e}", exc_info=True)
            original_session_id = session_id.split('_error_')[0]

            if retry_count < MAX_RETRIES:
                timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
                new_session_id = f"{original_session_id}_error_{timestamp}"
                logger.warning(
                    f"Orphaning session '{session_id}' and retrying with new session '{new_session_id}'."
                )
                # The recursive call will begin with Step 1, correctly creating the new session.
                await self._process_request(
                    new_message, new_session_id, task_updater, retry_count + 1
                )
            else:
                logger.error(f"Maximum retries exceeded for original session '{original_session_id}'. Failing task.")
                await task_updater.add_artifact([TextPart(text="This is no quest to test a Guardian. Share only what is needed, and keep your words kind — for the road remembers more than you think..")])
                await task_updater.update_status(TaskState.failed, final=True)
                self._active_sessions.discard(original_session_id)

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ):
        updater = TaskUpdater(event_queue, context.task_id, context.context_id)
        if not context.current_task:
            await updater.update_status(TaskState.submitted)
        await updater.update_status(TaskState.working)

        await self._process_request(
            types.UserContent(
                parts=[convert_a2a_part_to_genai(part) for part in context.message.parts],
            ),
            context.context_id,
            updater,
            retry_count=0,
        )
        logger.debug('[GuardianAgentExecutor] execute exiting')

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        session_id = context.context_id
        if session_id in self._active_sessions:
            logger.info(
                f'Cancellation requested for active session: {session_id}'
            )
            self._active_sessions.discard(session_id)
        else:
            logger.debug(
                f'Cancellation requested for inactive session: {session_id}'
            )
        raise ServerError(error=UnsupportedOperationError())

    async def _upsert_session(self, session_id: str) -> 'Session':
        """Retrieves a session if it exists, otherwise creates a new one."""
        session = await self.runner.session_service.get_session(
            app_name=self.runner.app_name,
            user_id=DEFAULT_USER_ID,
            session_id=session_id,
        )
        if session is None:
            logger.debug(f"Session '{session_id}' not found. Creating a new one.")
            session = await self.runner.session_service.create_session(
                app_name=self.runner.app_name,
                user_id=DEFAULT_USER_ID,
                session_id=session_id,
            )
        return session

def convert_a2a_part_to_genai(part: Part) -> types.Part:
    """Convert a single A2A Part type into a Google Gen AI Part type.

    Args:
        part: The A2A Part to convert

    Returns:
        The equivalent Google Gen AI Part

    Raises:
        ValueError: If the part type is not supported
    """
    part = part.root
    if isinstance(part, TextPart):
        return types.Part(text=part.text)
    raise ValueError(f'Unsupported part type: {type(part)}')


def convert_genai_part_to_a2a(part: types.Part) -> Part:
        """Convert a single Google Gen AI Part type into an A2A Part type.

        Args:
            part: The Google Gen AI Part to convert

        Returns:
            The equivalent A2A Part

        Raises:
            ValueError: If the part type is not supported
        """
        if part.text:
            return TextPart(text=part.text)
        if part.inline_data:
            return Part(
                root=FilePart(
                    file=FileWithBytes(
                        bytes=part.inline_data.data,
                        mime_type=part.inline_data.mime_type,
                    )
                )
            )
        raise ValueError(f'Unsupported part type: {part}')