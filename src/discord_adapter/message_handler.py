"""
Purpose
-------
Handle mention-based Discord messages for the general orchestration workflow.

Key behaviors
-------------
- Accept raw discord.py message events and translate them into normalized
  internal request contexts.
- Route normalized message requests through the shared Discord router.
- Return no-op, rejection, planner, or direct-execution outcomes in a uniform
  way.
- Keep Discord transport concerns separate from planner logic and tool
  execution logic.
- Send consistent user-facing responses for message-based workflows.

Conventions
-----------
- This module handles only message-based workflows.
- Slash-command workflows belong in the slash-command layer.
- This module does not call the planner directly and does not execute tools
  directly; it delegates those responsibilities through injected callables.
- This module only processes messages that survive context-building and routing
  policy.
- Message-based workflows cannot produce true ephemeral replies and therefore
  always degrade to public replies when necessary.

Downstream usage
----------------
Instantiate `MessageHandler` with the loaded Discord config plus planner and
tool-execution callables. Call `handle_message()` from the bot's `on_message`
event after filtering obvious bot-originated traffic.
"""

from __future__ import annotations

from dataclasses import dataclass
import logging
from typing import Awaitable, Callable, TypeAlias

import discord

from discord_adapter.discord_config import DiscordConfig
from discord_adapter.discord_context import build_context_from_message
from discord_adapter.discord_router import route_request_with_attachment_hint
from discord_adapter.response_utils import (
    build_clarification_response_plan,
    build_noop_response_plan,
    build_simple_response_plan,
    build_unauthorized_response_plan,
    send_error_response_for_message,
    send_response_plan_for_message,
)
from discord_adapter.discord_types import (
    DiscordRequestContext,
    DiscordResponsePlan,
    ExecutionResult,
    PlannerOutput,
    ResponseVisibility,
    RouteDecision,
    RouteKind,
)


LOGGER = logging.getLogger(__name__)


PlannerCallable: TypeAlias = Callable[
    [DiscordRequestContext, RouteDecision],
    Awaitable[PlannerOutput],
]

DirectExecutionCallable: TypeAlias = Callable[
    [DiscordRequestContext, RouteDecision],
    Awaitable[ExecutionResult],
]

PlannerExecutionCallable: TypeAlias = Callable[
    [DiscordRequestContext, PlannerOutput],
    Awaitable[ExecutionResult],
]


@dataclass(frozen=True)
class MessageHandlingResult:
    """
    Purpose
    -------
    Represent the high-level outcome of handling one Discord message event.

    Key behaviors
    -------------
    - Capture whether the message was ignored, rejected, planner-routed, or
      executed directly.
    - Preserve the normalized context and route decision for logging or later
      instrumentation.
    - Provide a stable return type for the Discord main orchestrator.

    Parameters
    ----------
    handled : bool
        Whether the message resulted in any orchestration action.
    route_kind : str
        High-level route kind string for logging and metrics.
    context : DiscordRequestContext | None
        Normalized request context if message processing reached that stage.
    route_decision : RouteDecision | None
        Route decision produced by the shared router, if any.
    response_plan : DiscordResponsePlan | None
        Final response plan sent or chosen for the message, if any.

    Attributes
    ----------
    handled : bool
        Whether the message resulted in any orchestration action.
    route_kind : str
        High-level route kind string.
    context : DiscordRequestContext | None
        Normalized request context.
    route_decision : RouteDecision | None
        Shared router decision.
    response_plan : DiscordResponsePlan | None
        Final response plan.

    Notes
    -----
    - `handled=False` usually means the message was ignored early.
    - `response_plan` may be present even when nothing was sent, such as for
      silent no-op decisions.
    """

    handled: bool
    route_kind: str
    context: DiscordRequestContext | None = None
    route_decision: RouteDecision | None = None
    response_plan: DiscordResponsePlan | None = None


class MessageHandler:
    """
    Purpose
    -------
    Orchestrate the full message-based request lifecycle for Discord messages
    that may mention the bot.

    Key behaviors
    -------------
    - Build normalized request context from a raw discord.py message.
    - Route the request using the shared Discord router.
    - Delegate planner routing and tool execution to injected async callables.
    - Send message replies based on normalized response plans.
    - Keep message-handling policy centralized and testable.

    Parameters
    ----------
    config : DiscordConfig
        Loaded Discord runtime configuration.
    planner_callable : PlannerCallable
        Async callable that turns a routed planner request into `PlannerOutput`.
    direct_execution_callable : DirectExecutionCallable
        Async callable that executes direct-command routes.
    planner_execution_callable : PlannerExecutionCallable
        Async callable that executes planner-selected tool calls.

    Attributes
    ----------
    config : DiscordConfig
        Loaded Discord runtime configuration.
    planner_callable : PlannerCallable
        Planner execution entrypoint.
    direct_execution_callable : DirectExecutionCallable
        Direct-route execution entrypoint.
    planner_execution_callable : PlannerExecutionCallable
        Planner-output execution entrypoint.

    Notes
    -----
    - This class does not know how the planner works internally.
    - This class does not know how tools are registered or executed
      internally.
    """

    def __init__(
        self,
        config: DiscordConfig,
        planner_callable: PlannerCallable,
        direct_execution_callable: DirectExecutionCallable,
        planner_execution_callable: PlannerExecutionCallable,
    ) -> None:
        self.config = config
        self.planner_callable = planner_callable
        self.direct_execution_callable = direct_execution_callable
        self.planner_execution_callable = planner_execution_callable

    async def handle_message(
        self,
        message: discord.Message,
        bot_user_id: int | None,
    ) -> MessageHandlingResult:
        """
        Handle one raw Discord message event.

        Parameters
        ----------
        message : discord.Message
            Raw discord.py message object.
        bot_user_id : int | None
            Current bot user ID used for explicit mention detection.

        Returns
        -------
        MessageHandlingResult
            High-level handling result for the message.

        Raises
        ------
        discord.DiscordException
            Raised if discord.py fails during reply sending.
        RuntimeError
            Raised if context building or downstream orchestration fails in an
            unexpected way.

        Notes
        -----
        - Bot-authored messages are ignored immediately.
        - Message handling is intentionally structured as
          build-context -> route -> execute -> respond.
        """
        if message.author.bot:
            return MessageHandlingResult(
                handled=False,
                route_kind="ignored_bot_message",
            )

        context: DiscordRequestContext = build_context_from_message(
            message=message,
            config=self.config,
            bot_user_id=bot_user_id,
        )

        route_decision: RouteDecision = route_request_with_attachment_hint(
            context=context,
            config=self.config,
        )

        if route_decision.route_kind == RouteKind.NO_OP:
            response_plan = build_noop_response_plan()
            await send_response_plan_for_message(
                message=message,
                response_plan=response_plan,
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=False,
                route_kind=route_decision.route_kind.value,
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        if route_decision.route_kind == RouteKind.REJECTED:
            response_plan = build_unauthorized_response_plan(
                reason=route_decision.reason,
                visibility=ResponseVisibility.PUBLIC,
            )
            await send_response_plan_for_message(
                message=message,
                response_plan=response_plan,
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind=route_decision.route_kind.value,
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        if route_decision.route_kind == RouteKind.DIRECT_COMMAND:
            return await self._handle_direct_route(
                message=message,
                context=context,
                route_decision=route_decision,
            )

        if route_decision.route_kind == RouteKind.LLM_PLANNER:
            return await self._handle_planner_route(
                message=message,
                context=context,
                route_decision=route_decision,
            )

        response_plan: DiscordResponsePlan = build_simple_response_plan(
            text="Unsupported routing outcome.",
            visibility=ResponseVisibility.PUBLIC,
            should_reply=True,
        )
        await send_response_plan_for_message(
            message=message,
            response_plan=response_plan,
            mention_author=False,
        )
        return MessageHandlingResult(
            handled=True,
            route_kind="unsupported_route_outcome",
            context=context,
            route_decision=route_decision,
            response_plan=response_plan,
        )

    async def _handle_direct_route(
        self,
        message: discord.Message,
        context: DiscordRequestContext,
        route_decision: RouteDecision,
    ) -> MessageHandlingResult:
        """
        Handle a message request that has already been resolved to direct tool
        execution.

        Parameters
        ----------
        message : discord.Message
            Source discord.py message.
        context : DiscordRequestContext
            Normalized request context.
        route_decision : RouteDecision
            Route decision produced by the shared router.

        Returns
        -------
        MessageHandlingResult
            Handling result for the direct route.

        Raises
        ------
        discord.DiscordException
            Raised if discord.py fails to send the response.
        RuntimeError
            Raised if the direct execution layer fails unexpectedly.

        Notes
        -----
        - Direct routes bypass the planner and go straight to tool execution.
        """
        try:
            execution_result = await self.direct_execution_callable(
                context,
                route_decision,
            )
        except Exception: # pylint: disable=broad-exception-caught
            LOGGER.exception("Direct execution failed for message route.")
            await send_error_response_for_message(
                message=message,
                error_text="Direct execution failed unexpectedly.",
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind="direct_command_error",
                context=context,
                route_decision=route_decision,
            )

        response_plan: DiscordResponsePlan = build_simple_response_plan(
            text=execution_result.summary_message or "Command completed.",
            visibility=ResponseVisibility.PUBLIC,
            should_reply=True,
        )
        await send_response_plan_for_message(
            message=message,
            response_plan=response_plan,
            mention_author=False,
        )
        return MessageHandlingResult(
            handled=True,
            route_kind=route_decision.route_kind.value,
            context=context,
            route_decision=route_decision,
            response_plan=response_plan,
        )

    async def _handle_planner_route(
        self,
        message: discord.Message,
        context: DiscordRequestContext,
        route_decision: RouteDecision,
    ) -> MessageHandlingResult:
        """
        Handle a message request that should be routed through the planner.

        Parameters
        ----------
        message : discord.Message
            Source discord.py message.
        context : DiscordRequestContext
            Normalized request context.
        route_decision : RouteDecision
            Planner route decision produced by the shared router.

        Returns
        -------
        MessageHandlingResult
            Handling result for the planner route.

        Raises
        ------
        discord.DiscordException
            Raised if discord.py fails to send the response.
        RuntimeError
            Raised if planner or planner-execution layers fail unexpectedly.

        Notes
        -----
        - Planner routing is intended for free-text natural-language requests.
        - Clarification requests are surfaced directly back to the user without
          executing tools.
        """
        try:
            planner_output = await self.planner_callable(
                context,
                route_decision,
            )
        except Exception: # pylint: disable=broad-exception-caught
            LOGGER.exception("Planner failed for message route.")
            await send_error_response_for_message(
                message=message,
                error_text="Planner routing failed unexpectedly.",
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind="planner_error",
                context=context,
                route_decision=route_decision,
            )

        if planner_output.needs_clarification:
            response_plan = build_clarification_response_plan(
                question=planner_output.clarification_question
                or "I need more information before I can continue.",
                visibility=ResponseVisibility.PUBLIC,
            )
            await send_response_plan_for_message(
                message=message,
                response_plan=response_plan,
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind="planner_clarification",
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        if not planner_output.tool_calls and planner_output.assistant_message:
            response_plan = build_simple_response_plan(
                text=planner_output.assistant_message,
                visibility=ResponseVisibility.PUBLIC,
                should_reply=True,
            )
            await send_response_plan_for_message(
                message=message,
                response_plan=response_plan,
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind="planner_message_only",
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        try:
            execution_result = await self.planner_execution_callable(
                context,
                planner_output,
            )
        except Exception: # pylint: disable=broad-exception-caught
            LOGGER.exception("Planner execution failed for message route.")
            await send_error_response_for_message(
                message=message,
                error_text="Planner-selected tool execution failed.",
                mention_author=False,
            )
            return MessageHandlingResult(
                handled=True,
                route_kind="planner_execution_error",
                context=context,
                route_decision=route_decision,
            )

        response_text = execution_result.summary_message
        if response_text is None or response_text.strip() == "":
            response_text = "Request completed."

        response_plan = build_simple_response_plan(
            text=response_text,
            visibility=ResponseVisibility.PUBLIC,
            should_reply=True,
        )
        await send_response_plan_for_message(
            message=message,
            response_plan=response_plan,
            mention_author=False,
        )
        return MessageHandlingResult(
            handled=True,
            route_kind=route_decision.route_kind.value,
            context=context,
            route_decision=route_decision,
            response_plan=response_plan,
        )
