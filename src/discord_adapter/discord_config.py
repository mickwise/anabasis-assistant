"""
Purpose
-------
Load and validate runtime configuration for the Discord orchestration layer.

Key behaviors
-------------
- Read Discord-related settings from environment variables.
- Parse optional development and authorization settings into normalized Python
  types.
- Centralize configuration used by the Discord router, context builder,
  message handler, slash-command layer, and response utilities.
- Provide one validated config object for the rest of the application.

Conventions
-----------
- This module owns configuration only. It does not construct Discord clients,
  parse messages, or execute tools.
- Environment variables are treated as the source of truth for deployment-time
  settings.
- Missing optional variables are replaced with safe defaults.
- Missing required variables raise a runtime error immediately at startup.

Downstream usage
----------------
Call `load_discord_config()` once during application startup. Pass the returned
`DiscordConfig` object into the Discord orchestration and routing layers.
"""

from __future__ import annotations

from typing import Tuple
from dataclasses import dataclass, field
import os


def _parse_bool_env(value: str | None, default: bool) -> bool:
    """
    Parse a boolean environment variable.

    Parameters
    ----------
    value : str | None
        Raw environment-variable string value.
    default : bool
        Fallback value used when the environment variable is unset.

    Returns
    -------
    bool
        Parsed boolean value.

    Raises
    ------
    ValueError
        Raised if the provided value is not a recognized boolean string.

    Notes
    -----
    - Accepted true values are: 1, true, yes, on.
    - Accepted false values are: 0, false, no, off.
    - Parsing is case-insensitive and ignores surrounding whitespace.
    """
    if value is None:
        return default

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True

    if normalized in {"0", "false", "no", "off"}:
        return False

    raise ValueError(f"Invalid boolean environment value: {value!r}")


def _parse_int_env(value: str | None, default: int) -> int:
    """
    Parse an integer environment variable.

    Parameters
    ----------
    value : str | None
        Raw environment-variable string value.
    default : int
        Fallback value used when the environment variable is unset.

    Returns
    -------
    int
        Parsed integer value.

    Raises
    ------
    ValueError
        Raised if the provided value cannot be parsed as an integer.

    Notes
    -----
    - This function does not impose range constraints. Range validation should
      happen in the higher-level config loader when needed.
    """
    if value is None or value.strip() == "":
        return default

    return int(value.strip())


def _parse_optional_int_env(value: str | None) -> int | None:
    """
    Parse an optional integer environment variable.

    Parameters
    ----------
    value : str | None
        Raw environment-variable string value.

    Returns
    -------
    int | None
        Parsed integer value, or None if the input is missing or empty.

    Raises
    ------
    ValueError
        Raised if the provided value cannot be parsed as an integer.

    Notes
    -----
    - Empty strings are treated the same as unset values.
    """
    if value is None or value.strip() == "":
        return None

    return int(value.strip())


def _parse_csv_ints_env(value: str | None) -> Tuple[int, ...]:
    """
    Parse a comma-separated list of integers from an environment variable.

    Parameters
    ----------
    value : str | None
        Raw environment-variable string value.

    Returns
    -------
    tuple[int, ...]
        Parsed integer tuple. Returns an empty tuple when the input is unset or
        empty.

    Raises
    ------
    ValueError
        Raised if any non-empty list entry cannot be parsed as an integer.

    Notes
    -----
    - Whitespace around comma-separated values is ignored.
    - Empty items are skipped.
    """
    if value is None or value.strip() == "":
        return ()

    parts = [part.strip() for part in value.split(",")]
    filtered = [part for part in parts if part != ""]
    return tuple(int(part) for part in filtered)


@dataclass(frozen=True)
class DiscordSecrets:
    """
    Purpose
    -------
    Hold Discord credentials required by the application runtime.

    Key behaviors
    -------------
    - Store the bot token required to connect through the Discord Gateway.
    - Preserve optional metadata fields that may be useful for logging or
      future transport changes.

    Parameters
    ----------
    bot_token : str
        Discord bot token used for authenticating the Gateway client.
    application_id : str | None
        Optional Discord application ID.
    public_key : str | None
        Optional Discord public key.

    Attributes
    ----------
    bot_token : str
        Discord bot token.
    application_id : str | None
        Discord application ID if provided.
    public_key : str | None
        Discord public key if provided.

    Notes
    -----
    - For a Gateway-based discord.py bot, the bot token is the only field that
      is strictly required at runtime.
    - The application ID and public key are retained because they are often
      present in the deployment environment and may be useful later.
    """

    bot_token: str
    application_id: str | None = None
    public_key: str | None = None


@dataclass(frozen=True)
class DiscordLimits:
    """
    Purpose
    -------
    Hold operational limits for Discord request handling.

    Key behaviors
    -------------
    - Centralize file-size limits and other bounded values used by upstream
      validation logic.
    - Keep operational thresholds out of routing and handler code.

    Parameters
    ----------
    max_attachment_size_bytes : int
        Maximum accepted attachment size in bytes.
    max_attachments_per_request : int
        Maximum number of attachments the application will consider from a
        single request.
    max_message_length_for_planner : int
        Maximum number of characters forwarded directly to the planner layer.

    Attributes
    ----------
    max_attachment_size_bytes : int
        Maximum accepted upload size in bytes.
    max_attachments_per_request : int
        Maximum number of attachments considered from one request.
    max_message_length_for_planner : int
        Maximum text length forwarded into the planner.

    Notes
    -----
    - These are application-level limits, not Discord protocol limits.
    - Keep these values conservative until the downstream pipeline is stable.
    """

    max_attachment_size_bytes: int = 15 * 1024 * 1024
    max_attachments_per_request: int = 4
    max_message_length_for_planner: int = 4000


@dataclass(frozen=True)
class DiscordFeatures:
    """
    Purpose
    -------
    Hold feature flags that control high-level Discord behavior.

    Key behaviors
    -------------
    - Enable or disable mention-based natural-language handling.
    - Enable or disable slash-command registration and execution.
    - Control whether DM-context workflows are allowed at all.

    Parameters
    ----------
    enable_message_mentions : bool
        Whether free-text mention-based bot invocation is enabled.
    enable_slash_commands : bool
        Whether slash commands are enabled.
    enable_dm_workflows : bool
        Whether direct-message workflows are enabled.
    enable_llm_router : bool
        Whether free-text messages should be routed through the planner layer.

    Attributes
    ----------
    enable_message_mentions : bool
        Mention-based invocation flag.
    enable_slash_commands : bool
        Slash-command enablement flag.
    enable_dm_workflows : bool
        Direct-message workflow enablement flag.
    enable_llm_router : bool
        Planner-routing enablement flag.

    Notes
    -----
    - `enable_llm_router` only affects the free-text route. Direct slash
      commands should still function when it is false.
    """

    enable_message_mentions: bool = True
    enable_slash_commands: bool = True
    enable_dm_workflows: bool = True
    enable_llm_router: bool = True


@dataclass(frozen=True)
class DiscordAuthConfig:
    """
    Purpose
    -------
    Hold authorization-related configuration for Discord workflows.

    Key behaviors
    -------------
    - Store allowlists for Dungeon Master-only private workflows.
    - Allow future campaign-level authorization to be layered on top of stable
      base config.

    Parameters
    ----------
    authorized_dm_user_ids : tuple[int, ...]
        User IDs allowed to access Dungeon Master-only workflows.
    admin_user_ids : tuple[int, ...]
        User IDs treated as higher-trust application administrators.

    Attributes
    ----------
    authorized_dm_user_ids : tuple[int, ...]
        Dungeon Master allowlist.
    admin_user_ids : tuple[int, ...]
        Admin allowlist.

    Notes
    -----
    - Being in a Discord DM is not enough for Dungeon Master authorization.
    - These allowlists are a simple first step and can later be replaced or
      supplemented by database-backed authorization.
    """

    authorized_dm_user_ids: Tuple[int, ...] = ()
    admin_user_ids: Tuple[int, ...] = ()


@dataclass(frozen=True)
class DiscordRuntimeConfig:
    """
    Purpose
    -------
    Hold general runtime settings for Discord startup and command sync.

    Key behaviors
    -------------
    - Configure development-guild sync behavior for faster slash-command
      iteration.
    - Store logging and environment labels used across startup code.

    Parameters
    ----------
    dev_guild_id : int | None
        Optional guild ID used for development-only command sync.
    environment_name : str
        Human-readable environment label such as dev, staging, or prod.
    log_level : str
        Logging level string used by startup code.

    Attributes
    ----------
    dev_guild_id : int | None
        Optional development guild ID.
    environment_name : str
        Human-readable environment label.
    log_level : str
        Logging level string.

    Notes
    -----
    - `dev_guild_id` should usually be set during development and omitted in
      broader deployments.
    """

    dev_guild_id: int | None = None
    environment_name: str = "dev"
    log_level: str = "INFO"


@dataclass(frozen=True)
class DiscordConfig:
    """
    Purpose
    -------
    Aggregate all Discord-related runtime configuration into one object.

    Key behaviors
    -------------
    - Expose a single validated configuration object to the rest of the
      application.
    - Group secrets, limits, features, authorization rules, and runtime
      settings into explicit sub-configs.

    Parameters
    ----------
    secrets : DiscordSecrets
        Credential configuration.
    limits : DiscordLimits
        Operational limits.
    features : DiscordFeatures
        High-level feature flags.
    auth : DiscordAuthConfig
        Authorization configuration.
    runtime : DiscordRuntimeConfig
        General runtime settings.

    Attributes
    ----------
    secrets : DiscordSecrets
        Credential configuration.
    limits : DiscordLimits
        Operational limits.
    features : DiscordFeatures
        Feature flags.
    auth : DiscordAuthConfig
        Authorization configuration.
    runtime : DiscordRuntimeConfig
        Runtime settings.

    Notes
    -----
    - This object should be treated as immutable application state.
    - Load it once at startup and pass it downward explicitly.
    """

    secrets: DiscordSecrets
    limits: DiscordLimits = field(default_factory=DiscordLimits)
    features: DiscordFeatures = field(default_factory=DiscordFeatures)
    auth: DiscordAuthConfig = field(default_factory=DiscordAuthConfig)
    runtime: DiscordRuntimeConfig = field(default_factory=DiscordRuntimeConfig)


def load_discord_config() -> DiscordConfig:
    """
    Load and validate Discord runtime configuration from environment variables.

    Parameters
    ----------
    None
        This function accepts no parameters.

    Returns
    -------
    DiscordConfig
        Fully parsed Discord configuration object.

    Raises
    ------
    RuntimeError
        Raised if required environment variables are missing or if parsed
        values violate basic constraints.
    ValueError
        Raised if one or more environment variables cannot be parsed into the
        expected types.

    Notes
    -----
    - Required environment variables:
        * DISCORD_BOT_TOKEN
    - Optional environment variables:
        * DISCORD_APPLICATION_ID
        * DISCORD_PUBLIC_KEY
        * DEV_GUILD_ID
        * DISCORD_MAX_ATTACHMENT_SIZE_BYTES
        * DISCORD_MAX_ATTACHMENTS_PER_REQUEST
        * DISCORD_MAX_MESSAGE_LENGTH_FOR_PLANNER
        * DISCORD_ENABLE_MESSAGE_MENTIONS
        * DISCORD_ENABLE_SLASH_COMMANDS
        * DISCORD_ENABLE_DM_WORKFLOWS
        * DISCORD_ENABLE_LLM_ROUTER
        * DISCORD_AUTHORIZED_DM_USER_IDS
        * DISCORD_ADMIN_USER_IDS
        * DISCORD_ENVIRONMENT
        * DISCORD_LOG_LEVEL
    """
    bot_token = os.getenv("DISCORD_BOT_TOKEN", "").strip()
    application_id = os.getenv("DISCORD_APPLICATION_ID", "").strip() or None
    public_key = os.getenv("DISCORD_PUBLIC_KEY", "").strip() or None

    if bot_token == "":
        raise RuntimeError("DISCORD_BOT_TOKEN is required.")

    max_attachment_size_bytes = _parse_int_env(
        os.getenv("DISCORD_MAX_ATTACHMENT_SIZE_BYTES"),
        15 * 1024 * 1024,
    )
    max_attachments_per_request = _parse_int_env(
        os.getenv("DISCORD_MAX_ATTACHMENTS_PER_REQUEST"),
        4,
    )
    max_message_length_for_planner = _parse_int_env(
        os.getenv("DISCORD_MAX_MESSAGE_LENGTH_FOR_PLANNER"),
        4000,
    )

    if max_attachment_size_bytes <= 0:
        raise RuntimeError(
            "DISCORD_MAX_ATTACHMENT_SIZE_BYTES must be positive."
        )

    if max_attachments_per_request <= 0:
        raise RuntimeError(
            "DISCORD_MAX_ATTACHMENTS_PER_REQUEST must be positive."
        )

    if max_message_length_for_planner <= 0:
        raise RuntimeError(
            "DISCORD_MAX_MESSAGE_LENGTH_FOR_PLANNER must be positive."
        )

    features = DiscordFeatures(
        enable_message_mentions=_parse_bool_env(
            os.getenv("DISCORD_ENABLE_MESSAGE_MENTIONS"),
            True,
        ),
        enable_slash_commands=_parse_bool_env(
            os.getenv("DISCORD_ENABLE_SLASH_COMMANDS"),
            True,
        ),
        enable_dm_workflows=_parse_bool_env(
            os.getenv("DISCORD_ENABLE_DM_WORKFLOWS"),
            True,
        ),
        enable_llm_router=_parse_bool_env(
            os.getenv("DISCORD_ENABLE_LLM_ROUTER"),
            True,
        ),
    )

    runtime = DiscordRuntimeConfig(
        dev_guild_id=_parse_optional_int_env(os.getenv("DEV_GUILD_ID")),
        environment_name=os.getenv("DISCORD_ENVIRONMENT", "dev").strip()
        or "dev",
        log_level=os.getenv("DISCORD_LOG_LEVEL", "INFO").strip() or "INFO",
    )

    auth = DiscordAuthConfig(
        authorized_dm_user_ids=_parse_csv_ints_env(
            os.getenv("DISCORD_AUTHORIZED_DM_USER_IDS")
        ),
        admin_user_ids=_parse_csv_ints_env(
            os.getenv("DISCORD_ADMIN_USER_IDS")
        ),
    )

    secrets = DiscordSecrets(
        bot_token=bot_token,
        application_id=application_id,
        public_key=public_key,
    )

    limits = DiscordLimits(
        max_attachment_size_bytes=max_attachment_size_bytes,
        max_attachments_per_request=max_attachments_per_request,
        max_message_length_for_planner=max_message_length_for_planner,
    )

    return DiscordConfig(
        secrets=secrets,
        limits=limits,
        features=features,
        auth=auth,
        runtime=runtime,
    )
