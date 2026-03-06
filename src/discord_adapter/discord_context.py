"""
Purpose
-------
Translate raw discord.py message and interaction objects into the internal
Discord request context used by the orchestration system.

Key behaviors
-------------
- Convert guild messages, DM messages, and slash-command interactions into a
  shared `DiscordRequestContext`.
- Normalize Discord attachments into existing `AttachmentRef` values from the
  shared types module.
- Derive conversation scope, mention status, slash-command metadata, and
  authorization flags in one place.
- Keep discord.py-specific attribute access out of routers, planners, and tool
  executors.

Conventions
-----------
- `guild_id is None` is treated as direct-message scope.
- Dungeon Master authorization is determined from config allowlists, not from
  Discord DM scope alone.
- Attachment metadata is normalized here, but attachment validation policy
  belongs in attachment-specific utilities.

Downstream usage
----------------
Use `build_context_from_message()` for mention-based free-text messages and
`build_context_from_interaction()` for slash-command interactions. Pass the
returned `DiscordRequestContext` into authorization, routing, and planner
layers.
"""

from __future__ import annotations

from typing import Any, Tuple, List, Dict

import discord

from discord_adapter.discord_config import DiscordConfig
from discord_adapter.discord_types import (
    AttachmentRef,
    ConversationScope,
    DiscordRequestContext,
    EventSource,
    PrivilegeLevel,
    SlashCommandInvocation,
)


def _infer_conversation_scope(guild_id: int | None) -> ConversationScope:
    """
    Infer the Discord conversation scope from a guild identifier.

    Parameters
    ----------
    guild_id : int | None
        Guild identifier if the event originated in a guild, else None.

    Returns
    -------
    ConversationScope
        `GUILD` when a guild ID is present, else `DIRECT_MESSAGE`.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This helper exists so scope derivation is centralized and consistent.
    """
    if guild_id is None:
        return ConversationScope.DIRECT_MESSAGE

    return ConversationScope.GUILD


def _infer_source_kind(filename: str, content_type: str | None) -> str:
    """
    Infer a normalized source kind from Discord attachment metadata.

    Parameters
    ----------
    filename : str
        Original Discord attachment filename.
    content_type : str | None
        MIME type reported by Discord, if present.

    Returns
    -------
    str
        Normalized source kind. Currently `pdf`, `image`, or `unknown`.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - MIME type is preferred when available.
    - Filename suffix is used as a fallback because Discord metadata may omit
      content type on some uploads.
    """
    if content_type == "application/pdf":
        return "pdf"

    if content_type in {"image/png", "image/jpeg", "image/webp"}:
        return "image"

    normalized_name: str = filename.lower()
    if normalized_name.endswith(".pdf"):
        return "pdf"

    if normalized_name.endswith((".png", ".jpg", ".jpeg", ".webp")):
        return "image"

    return "unknown"


def _normalize_attachment(attachment: discord.Attachment) -> AttachmentRef:
    """
    Convert a discord.py attachment into the shared internal attachment type.

    Parameters
    ----------
    attachment : discord.Attachment
        Raw discord.py attachment model.

    Returns
    -------
    AttachmentRef
        Normalized attachment metadata.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This function performs normalization only. It does not validate file size
      or file-type policy.
    """
    return AttachmentRef(
        attachment_id=str(attachment.id),
        filename=attachment.filename,
        url=attachment.url,
        content_type=attachment.content_type,
        size_bytes=attachment.size,
        source_kind=_infer_source_kind(
            filename=attachment.filename,
            content_type=attachment.content_type,
        ),
    )


def _normalize_attachments(
    attachments: List[discord.Attachment],
    max_attachments_per_request: int,
) -> Tuple[AttachmentRef, ...]:
    """
    Normalize a bounded list of Discord attachments.

    Parameters
    ----------
    attachments : list[discord.Attachment]
        Raw attachments associated with a Discord message or interaction.
    max_attachments_per_request : int
        Maximum number of attachments to retain.

    Returns
    -------
    tuple[AttachmentRef, ...]
        Tuple of normalized attachments capped to the configured limit.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Attachment truncation is intentional and configuration-driven.
    - Validation should happen later in the attachment utility layer.
    """
    selected: List[discord.Attachment] = attachments[:max_attachments_per_request]
    return tuple(_normalize_attachment(attachment) for attachment in selected)


def _compute_privilege_level(
    user_id: int,
    authorized_dm_user_ids: Tuple[int, ...],
    admin_user_ids: Tuple[int, ...],
) -> PrivilegeLevel:
    """
    Compute the effective privilege level for a Discord user.

    Parameters
    ----------
    user_id : int
        Discord user ID.
    authorized_dm_user_ids : tuple[int, ...]
        Allowlist for Dungeon Master-level access.
    admin_user_ids : tuple[int, ...]
        Allowlist for higher-trust administrative access.

    Returns
    -------
    PrivilegeLevel
        Effective privilege level for the user.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Admin privilege dominates DM privilege.
    - User privilege is the default when no allowlist matches.
    """
    if user_id in admin_user_ids:
        return PrivilegeLevel.ADMIN

    if user_id in authorized_dm_user_ids:
        return PrivilegeLevel.DM

    return PrivilegeLevel.USER


def _extract_username_from_message(message: discord.Message) -> str | None:
    """
    Extract a human-readable username from a Discord message author.

    Parameters
    ----------
    message : discord.Message
        Raw Discord message object.

    Returns
    -------
    str | None
        Display name or username if available.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Guild members expose `display_name`; generic users may not.
    - This helper avoids duplicating fragile attribute checks.
    """
    author = message.author

    if hasattr(author, "display_name"):
        return str(author.display_name)

    if hasattr(author, "name"):
        return str(author.name)

    return None


def _extract_username_from_interaction(
    interaction: discord.Interaction[Any],
) -> str | None:
    """
    Extract a human-readable username from a Discord interaction user.

    Parameters
    ----------
    interaction : discord.Interaction[Any]
        Raw Discord interaction object.

    Returns
    -------
    str | None
        Display name or username if available.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Interaction users are usually `discord.User` or `discord.Member`.
    """
    user = interaction.user

    if hasattr(user, "display_name"):
        return str(user.display_name)

    if hasattr(user, "name"):
        return str(user.name)

    return None


def _extract_slash_command(
    interaction: discord.Interaction[Any],
) -> SlashCommandInvocation | None:
    """
    Extract normalized slash-command metadata from an interaction.

    Parameters
    ----------
    interaction : discord.Interaction[Any]
        Raw Discord interaction object.

    Returns
    -------
    SlashCommandInvocation | None
        Normalized slash-command payload, or None when not available.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This function intentionally keeps option parsing shallow and JSON-like.
    - Attachment options should be normalized upstream or stored in raw option
      form for later interpretation.
    """
    command = interaction.command
    if command is None:
        return None

    command_name = getattr(command, "name", None)
    if not isinstance(command_name, str) or command_name == "":
        return None

    namespace = getattr(interaction, "namespace", None)
    options: Dict[str, Any] = {}

    if namespace is not None:
        for key, value in namespace.__dict__.items():
            options[key] = value

    return SlashCommandInvocation(
        command_name=command_name,
        subcommand_path=(),
        options=options,
    )


def build_context_from_message(
    message: discord.Message,
    config: DiscordConfig,
    bot_user_id: int | None,
) -> DiscordRequestContext:
    """
    Build a normalized internal request context from a Discord message.

    Parameters
    ----------
    message : discord.Message
        Raw discord.py message object.
    config : DiscordConfig
        Loaded Discord runtime configuration.
    bot_user_id : int | None
        Current bot user ID used to detect explicit mentions.

    Returns
    -------
    DiscordRequestContext
        Normalized request context derived from the message.

    Raises
    ------
    RuntimeError
        Raised if required message identifiers are missing unexpectedly.

    Notes
    -----
    - `mention_triggered` is computed by checking whether the bot user appears
      in the message mentions list.
    - DM scope is derived from `message.guild is None`.
    """
    if message.channel.id is None:
        raise RuntimeError("Message channel ID is required.")

    guild_id = message.guild.id if message.guild is not None else None
    conversation_scope = _infer_conversation_scope(guild_id)
    normalized_attachments = _normalize_attachments(
        attachments=message.attachments,
        max_attachments_per_request=config.limits.max_attachments_per_request,
    )

    mention_triggered = False
    if bot_user_id is not None:
        mention_triggered = any(
            mentioned_user.id == bot_user_id
            for mentioned_user in message.mentions
        )

    privilege_level = _compute_privilege_level(
        user_id=message.author.id,
        authorized_dm_user_ids=config.auth.authorized_dm_user_ids,
        admin_user_ids=config.auth.admin_user_ids,
    )

    return DiscordRequestContext(
        event_source=EventSource.MESSAGE,
        conversation_scope=conversation_scope,
        user_id=message.author.id,
        username=_extract_username_from_message(message),
        channel_id=message.channel.id,
        guild_id=guild_id,
        message_id=message.id,
        interaction_id=None,
        raw_text=message.content,
        mention_triggered=mention_triggered,
        attachments=normalized_attachments,
        slash_command=None,
        is_dm_authorized=privilege_level in {
            PrivilegeLevel.DM,
            PrivilegeLevel.ADMIN,
        },
        privilege_level=privilege_level,
        metadata={
            "jump_url": message.jump_url,
            "author_is_bot": message.author.bot,
        },
    )


def build_context_from_interaction(
    interaction: discord.Interaction[Any],
    config: DiscordConfig,
) -> DiscordRequestContext:
    """
    Build a normalized internal request context from a Discord interaction.

    Parameters
    ----------
    interaction : discord.Interaction[Any]
        Raw discord.py interaction object.
    config : DiscordConfig
        Loaded Discord runtime configuration.

    Returns
    -------
    DiscordRequestContext
        Normalized request context derived from the interaction.

    Raises
    ------
    RuntimeError
        Raised if required interaction identifiers are missing unexpectedly.

    Notes
    -----
    - Slash-command metadata is extracted into `SlashCommandInvocation` when
      available.
    - Interactions do not use mention-trigger semantics, so that field is
      always false here.
    """
    if interaction.channel_id is None:
        raise RuntimeError("Interaction channel ID is required.")

    guild_id = interaction.guild_id
    conversation_scope = _infer_conversation_scope(guild_id)
    privilege_level = _compute_privilege_level(
        user_id=interaction.user.id,
        authorized_dm_user_ids=config.auth.authorized_dm_user_ids,
        admin_user_ids=config.auth.admin_user_ids,
    )

    return DiscordRequestContext(
        event_source=EventSource.SLASH_COMMAND,
        conversation_scope=conversation_scope,
        user_id=interaction.user.id,
        username=_extract_username_from_interaction(interaction),
        channel_id=interaction.channel_id,
        guild_id=guild_id,
        message_id=None,
        interaction_id=interaction.id,
        raw_text="",
        mention_triggered=False,
        attachments=(),
        slash_command=_extract_slash_command(interaction),
        is_dm_authorized=privilege_level in {
            PrivilegeLevel.DM,
            PrivilegeLevel.ADMIN,
        },
        privilege_level=privilege_level,
        metadata={
            "interaction_type": str(interaction.type),
        },
    )
