"""
Purpose
-------
Handle slash-command interactions for the general Discord orchestration
workflow.

Key behaviors
-------------
- Accept raw discord.py interaction objects for slash-command execution.
- Translate interactions into normalized internal request contexts.
- Route slash commands through the shared Discord router.
- Delegate direct-command execution to an injected execution callable.
- Send consistent success, failure, and authorization responses through the
  interaction response and follow-up APIs.

Conventions
-----------
- This module handles only slash-command workflows.
- Slash commands are routed as direct commands and do not pass through the
  free-text planner path.
- This module assumes long-running command execution should defer the
  interaction before execution.
- Ephemeral responses are preferred for slash-command failures and
  authorization errors.

Downstream usage
----------------
Instantiate `SlashCommandHandler` with the loaded Discord config and a direct
execution callable. Register the app commands returned by
`build_ingest_command()` and `build_ping_command()` on the bot's command tree,
or add the whole group to a cog/main bot module as desired.
"""

from __future__ import annotations

from dataclasses import dataclass
import logging
from typing import Any, Awaitable, Callable, TypeAlias

import discord
from discord import app_commands

from discord_adapter.discord_config import DiscordConfig
from discord_adapter.discord_context import build_context_from_interaction
from discord_adapter.discord_router import route_request
from discord_adapter.response_utils import (
    build_simple_response_plan,
    build_unauthorized_response_plan,
    defer_interaction_if_needed,
    send_error_response_for_interaction,
    send_response_plan_for_interaction,
)
from discord_adapter.discord_types import (
    DiscordRequestContext,
    DiscordResponsePlan,
    ExecutionResult,
    ResponseVisibility,
    RouteDecision,
    RouteKind,
)


LOGGER = logging.getLogger(__name__)


DirectExecutionCallable: TypeAlias = Callable[
    [DiscordRequestContext, RouteDecision],
    Awaitable[ExecutionResult],
]


@dataclass(frozen=True)
class SlashHandlingResult:
    """
    Purpose
    -------
    Represent the high-level outcome of handling one slash-command interaction.

    Key behaviors
    -------------
    - Capture whether the interaction was handled successfully.
    - Preserve the normalized request context and route decision for logging or
      metrics.
    - Carry the final response plan chosen for the interaction.

    Parameters
    ----------
    handled : bool
        Whether the interaction was processed by the orchestration layer.
    route_kind : str
        High-level route kind string for logging and metrics.
    context : DiscordRequestContext | None
        Normalized request context if interaction processing reached that stage.
    route_decision : RouteDecision | None
        Route decision produced by the shared router, if any.
    response_plan : DiscordResponsePlan | None
        Final response plan sent or chosen for the interaction, if any.

    Attributes
    ----------
    handled : bool
        Whether the interaction was processed.
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
    - `handled=False` is uncommon for slash commands because invoking a slash
      command is already an explicit request to the bot.
    """

    handled: bool
    route_kind: str
    context: DiscordRequestContext | None = None
    route_decision: RouteDecision | None = None
    response_plan: DiscordResponsePlan | None = None


class SlashCommandHandler:
    """
    Purpose
    -------
    Orchestrate the slash-command request lifecycle for the Discord
    application.

    Key behaviors
    -------------
    - Build normalized internal request contexts from slash-command
      interactions.
    - Route slash commands through the shared Discord router.
    - Delegate direct execution to an injected async callable.
    - Send interaction responses using the shared response utilities.
    - Keep slash-command policy centralized and testable.

    Parameters
    ----------
    config : DiscordConfig
        Loaded Discord runtime configuration.
    direct_execution_callable : DirectExecutionCallable
        Async callable that executes direct-command routes.

    Attributes
    ----------
    config : DiscordConfig
        Loaded Discord runtime configuration.
    direct_execution_callable : DirectExecutionCallable
        Direct-route execution entrypoint.

    Notes
    -----
    - Slash commands are routed directly and do not go through the free-text
      planner path.
    - This class does not know how tools are registered internally.
    """

    def __init__(
        self,
        config: DiscordConfig,
        direct_execution_callable: DirectExecutionCallable,
    ) -> None:
        self.config = config
        self.direct_execution_callable = direct_execution_callable

    async def handle_interaction(
        self,
        interaction: discord.Interaction[Any],
    ) -> SlashHandlingResult:
        """
        Handle one raw slash-command interaction.

        Parameters
        ----------
        interaction : discord.Interaction[Any]
            Raw discord.py interaction object.

        Returns
        -------
        SlashHandlingResult
            High-level handling result for the interaction.

        Raises
        ------
        discord.DiscordException
            Raised if discord.py fails during response or follow-up delivery.
        RuntimeError
            Raised if context building or downstream orchestration fails in an
            unexpected way.

        Notes
        -----
        - This method follows the structure
          build-context -> route -> execute -> respond.
        - Long-running direct execution is deferred before execution starts.
        """
        context: DiscordRequestContext = build_context_from_interaction(
            interaction=interaction,
            config=self.config,
        )

        route_decision: RouteDecision = route_request(
            context=context,
            config=self.config,
        )

        if route_decision.route_kind == RouteKind.NO_OP:
            response_plan = build_simple_response_plan(
                text="Nothing to do for this command.",
                visibility=ResponseVisibility.EPHEMERAL,
                should_reply=True,
            )
            await send_response_plan_for_interaction(
                interaction=interaction,
                response_plan=response_plan,
            )
            return SlashHandlingResult(
                handled=False,
                route_kind=route_decision.route_kind.value,
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        if route_decision.route_kind == RouteKind.REJECTED:
            response_plan = build_unauthorized_response_plan(
                reason=route_decision.reason,
                visibility=ResponseVisibility.EPHEMERAL,
            )
            await send_response_plan_for_interaction(
                interaction=interaction,
                response_plan=response_plan,
            )
            return SlashHandlingResult(
                handled=True,
                route_kind=route_decision.route_kind.value,
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        if route_decision.route_kind != RouteKind.DIRECT_COMMAND:
            response_plan = build_simple_response_plan(
                text="Slash commands must resolve to direct execution.",
                visibility=ResponseVisibility.EPHEMERAL,
                should_reply=True,
            )
            await send_response_plan_for_interaction(
                interaction=interaction,
                response_plan=response_plan,
            )
            return SlashHandlingResult(
                handled=True,
                route_kind="invalid_slash_route",
                context=context,
                route_decision=route_decision,
                response_plan=response_plan,
            )

        return await self._handle_direct_route(
            interaction=interaction,
            context=context,
            route_decision=route_decision,
        )

    async def _handle_direct_route(
        self,
        interaction: discord.Interaction[Any],
        context: DiscordRequestContext,
        route_decision: RouteDecision,
    ) -> SlashHandlingResult:
        """
        Handle a slash-command route that has already been resolved to direct
        tool execution.

        Parameters
        ----------
        interaction : discord.Interaction[Any]
            Source discord.py interaction.
        context : DiscordRequestContext
            Normalized request context.
        route_decision : RouteDecision
            Route decision produced by the shared router.

        Returns
        -------
        SlashHandlingResult
            Handling result for the direct route.

        Raises
        ------
        discord.DiscordException
            Raised if discord.py fails to send the response.
        RuntimeError
            Raised if the direct execution layer fails unexpectedly.

        Notes
        -----
        - The interaction is deferred before direct execution because command
          handlers may perform I/O or other longer-running work.
        """
        try:
            await defer_interaction_if_needed(
                interaction=interaction,
                ephemeral=False,
                thinking=True,
            )
            execution_result = await self.direct_execution_callable(
                context,
                route_decision,
            )
        except Exception: # pylint: disable=broad-exception-caught
            LOGGER.exception("Direct slash-command execution failed.")
            await send_error_response_for_interaction(
                interaction=interaction,
                error_text="Slash-command execution failed unexpectedly.",
                visibility=ResponseVisibility.EPHEMERAL,
            )
            return SlashHandlingResult(
                handled=True,
                route_kind="direct_command_error",
                context=context,
                route_decision=route_decision,
            )

        response_text: str = execution_result.summary_message
        if response_text is None or response_text.strip() == "":
            response_text = "Command completed."

        response_plan: DiscordResponsePlan = build_simple_response_plan(
            text=response_text,
            visibility=ResponseVisibility.PUBLIC,
            should_reply=True,
        )
        await send_response_plan_for_interaction(
            interaction=interaction,
            response_plan=response_plan,
        )
        return SlashHandlingResult(
            handled=True,
            route_kind=route_decision.route_kind.value,
            context=context,
            route_decision=route_decision,
            response_plan=response_plan,
        )


def build_ping_command() -> app_commands.Command[Any, ..., Any]:
    """
    Build a minimal ping slash command used for connectivity testing.

    Parameters
    ----------
    slash_handler : SlashCommandHandler
        Configured slash-command handler instance.

    Returns
    -------
    app_commands.Command[Any, ..., Any]
        Registered app command object.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This command is intentionally simple and useful for validating command
      registration and interaction response plumbing.
    """

    @app_commands.command(
        name="ping",
        description="Check whether the bot is responsive.",
    )
    async def ping(
        interaction: discord.Interaction[Any],
    ) -> None:
        """
        Respond to a basic ping command.

        Parameters
        ----------
        interaction : discord.Interaction[Any]
            Raw discord.py interaction.

        Returns
        -------
        None
            This function returns no value.

        Raises
        ------
        discord.DiscordException
            Raised if the interaction response fails.

        Notes
        -----
        - This bypasses the shared routing layer because it is intended as a
          transport-level sanity check.
        """
        response_plan = build_simple_response_plan(
            text="Pong.",
            visibility=ResponseVisibility.EPHEMERAL,
            should_reply=True,
        )
        await send_response_plan_for_interaction(
            interaction=interaction,
            response_plan=response_plan,
        )

    return ping


def build_ingest_command(
    slash_handler: SlashCommandHandler,
) -> app_commands.Command[Any, ..., Any]:
    """
    Build a generic ingest slash command for file-driven workflows.

    Parameters
    ----------
    slash_handler : SlashCommandHandler
        Configured slash-command handler instance.

    Returns
    -------
    app_commands.Command[Any, ..., Any]
        Registered app command object.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This command is intentionally generic and delegates into the normalized
      slash-command handler path.
    - The raw attachment option remains attached to the interaction and is
      normalized by the shared context builder.
    """

    @app_commands.command(
        name="ingest",
        description="Upload a PDF or image for ingestion.",
    )
    @app_commands.describe(
        file="PDF or image to ingest",
        note="Optional note to help downstream routing and parsing",
    )
    async def ingest(
        interaction: discord.Interaction[Any],
        file: discord.Attachment,
        note: str | None = None,
    ) -> None:
        """
        Handle the generic ingest slash command.

        Parameters
        ----------
        interaction : discord.Interaction[Any]
            Raw discord.py interaction.
        file : discord.Attachment
            Uploaded Discord attachment.
        note : str | None
            Optional free-text note from the caller.

        Returns
        -------
        None
            This function returns no value.

        Raises
        ------
        discord.DiscordException
            Raised if interaction response delivery fails.
        RuntimeError
            Raised if normalized slash-command orchestration fails
            unexpectedly.

        Notes
        -----
        - The command parameters are present so Discord registers the correct
          option schema.
        - The actual normalized command handling happens through the shared
          slash-command handler and context builder.
        """
        _ = file
        _ = note
        await slash_handler.handle_interaction(interaction)

    return ingest


def build_roll_command(
    slash_handler: SlashCommandHandler,
) -> app_commands.Command[Any, ..., Any]:
    """
    Build a generic roll slash command for dice-related direct execution.

    Parameters
    ----------
    slash_handler : SlashCommandHandler
        Configured slash-command handler instance.

    Returns
    -------
    app_commands.Command[Any, ..., Any]
        Registered app command object.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This command exists to demonstrate how the general slash-command layer
      can support non-ingestion features such as rolling.
    """

    @app_commands.command(
        name="roll",
        description="Execute a structured dice-roll command.",
    )
    @app_commands.describe(
        request="Natural-language or structured roll request",
    )
    async def roll(
        interaction: discord.Interaction[Any],
        request: str,
    ) -> None:
        """
        Handle the generic roll slash command.

        Parameters
        ----------
        interaction : discord.Interaction[Any]
            Raw discord.py interaction.
        request : str
            Roll request text.

        Returns
        -------
        None
            This function returns no value.

        Raises
        ------
        discord.DiscordException
            Raised if interaction response delivery fails.
        RuntimeError
            Raised if normalized slash-command orchestration fails
            unexpectedly.

        Notes
        -----
        - The argument is registered with Discord as a command option.
        - Actual execution remains delegated through the normalized
          slash-command path.
        """
        _ = request
        await slash_handler.handle_interaction(interaction)

    return roll


def register_default_slash_commands(
    tree: app_commands.CommandTree[Any],
    slash_handler: SlashCommandHandler,
) -> None:
    """
    Register a default baseline set of slash commands on a command tree.

    Parameters
    ----------
    tree : app_commands.CommandTree[Any]
        discord.py application command tree.
    slash_handler : SlashCommandHandler
        Configured slash-command handler instance.

    Returns
    -------
    None
        This function returns no value.

    Raises
    ------
    discord.app_commands.CommandAlreadyRegistered
        Raised if a command with the same name is already registered.

    Notes
    -----
    - This helper keeps startup code small by centralizing baseline command
      registration.
    - You can add additional command builders here as the application grows.
    """
    tree.add_command(build_ping_command())
    tree.add_command(build_ingest_command(slash_handler))
    tree.add_command(build_roll_command(slash_handler))
