"""
Purpose
-------
Provide attachment selection and validation utilities for the Discord
orchestration layer.

Key behaviors
-------------
- Select the subset of normalized attachments that should be considered for a
  request.
- Validate attachment type and size against application policy.
- Expose helpers for common attachment-routing questions, such as whether a
  request contains a PDF or image.
- Keep attachment policy separate from Discord context extraction and tool
  execution.

Conventions
-----------
- This module operates on normalized `AttachmentRef` and
  `DiscordRequestContext` values from `discord_types.py`.
- This module does not download files and does not inspect raw discord.py
  attachment models.
- File-type policy is based on normalized `source_kind`, MIME type, and
  filename metadata already extracted upstream.
- Validation returns explicit policy results so higher layers can decide
  whether to reject, degrade, or continue.

Downstream usage
----------------
Use `select_candidate_attachments()` to choose which attachments should be
considered for a request. Use `validate_attachment()` or
`validate_request_attachments()` before dispatching downstream ingestion or
vision/model tasks.
"""

from __future__ import annotations

from typing import Tuple
from dataclasses import dataclass

from discord_adapter.discord_config import DiscordConfig
from discord_adapter.discord_types import AttachmentRef, DiscordRequestContext


SUPPORTED_SOURCE_KINDS: frozenset = frozenset({"pdf", "image"})


@dataclass(frozen=True)
class AttachmentValidationResult:
    """
    Purpose
    -------
    Represent the validation outcome for a single normalized attachment.

    Key behaviors
    -------------
    - Store whether the attachment passed application policy.
    - Carry a human-readable reason suitable for higher-level error handling.
    - Preserve the original attachment when validation succeeds or fails.

    Parameters
    ----------
    attachment : AttachmentRef
        Normalized attachment being validated.
    is_valid : bool
        Whether the attachment passed validation.
    reason : str
        Human-readable explanation of the validation outcome.

    Attributes
    ----------
    attachment : AttachmentRef
        Attachment being validated.
    is_valid : bool
        Validation outcome flag.
    reason : str
        Human-readable explanation of the outcome.

    Notes
    -----
    - This object is intentionally simple so callers can aggregate many
      validation results without exceptions controlling normal flow.
    """

    attachment: AttachmentRef
    is_valid: bool
    reason: str


@dataclass(frozen=True)
class RequestAttachmentValidationResult:
    """
    Purpose
    -------
    Represent the aggregate validation outcome for all attachments associated
    with a request.

    Key behaviors
    -------------
    - Store per-attachment validation results.
    - Summarize whether the request contains at least one valid attachment.
    - Provide a stable object for routers and handlers to inspect.

    Parameters
    ----------
    results : tuple[AttachmentValidationResult, ...]
        Per-attachment validation results.
    has_valid_attachment : bool
        Whether at least one attachment passed validation.
    selected_attachments : tuple[AttachmentRef, ...]
        Attachments that passed validation and remain candidates for use.

    Attributes
    ----------
    results : tuple[AttachmentValidationResult, ...]
        Per-attachment validation results.
    has_valid_attachment : bool
        Whether at least one attachment passed validation.
    selected_attachments : tuple[AttachmentRef, ...]
        Attachments that passed validation.

    Notes
    -----
    - This object does not choose which valid attachment to use for a specific
      tool. It only reports validation and candidate selection.
    """

    results: Tuple[AttachmentValidationResult, ...]
    has_valid_attachment: bool
    selected_attachments: Tuple[AttachmentRef, ...]


def is_supported_attachment_kind(attachment: AttachmentRef) -> bool:
    """
    Return whether an attachment's normalized source kind is supported.

    Parameters
    ----------
    attachment : AttachmentRef
        Normalized attachment to inspect.

    Returns
    -------
    bool
        True if the attachment source kind is supported, else False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - The current application supports PDFs and common image uploads.
    """
    return attachment.source_kind in SUPPORTED_SOURCE_KINDS


def is_pdf_attachment(attachment: AttachmentRef) -> bool:
    """
    Return whether an attachment is classified as a PDF.

    Parameters
    ----------
    attachment : AttachmentRef
        Normalized attachment to inspect.

    Returns
    -------
    bool
        True if the attachment is a PDF, else False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Classification is based on upstream normalization logic.
    """
    return attachment.source_kind == "pdf"


def is_image_attachment(attachment: AttachmentRef) -> bool:
    """
    Return whether an attachment is classified as an image.

    Parameters
    ----------
    attachment : AttachmentRef
        Normalized attachment to inspect.

    Returns
    -------
    bool
        True if the attachment is an image, else False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Classification is based on upstream normalization logic.
    """
    return attachment.source_kind == "image"


def request_has_supported_attachments(context: DiscordRequestContext) -> bool:
    """
    Return whether a request contains at least one supported attachment.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.

    Returns
    -------
    bool
        True if the request contains at least one supported attachment, else
        False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Unsupported attachments are ignored for this predicate.
    """
    return any(
        is_supported_attachment_kind(attachment)
        for attachment in context.attachments
    )


def select_candidate_attachments(
    context: DiscordRequestContext,
    prefer_images: bool = False,
    prefer_pdfs: bool = False,
) -> Tuple[AttachmentRef, ...]:
    """
    Select candidate attachments from a request according to simple policy.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.
    prefer_images : bool
        Whether image attachments should be prioritized in the returned order.
    prefer_pdfs : bool
        Whether PDF attachments should be prioritized in the returned order.

    Returns
    -------
    tuple[AttachmentRef, ...]
        Supported candidate attachments ordered according to the requested
        preference policy.

    Raises
    ------
    ValueError
        Raised if both image and PDF preference flags are set simultaneously.

    Notes
    -----
    - Unsupported attachments are discarded.
    - Selection here is purely policy-oriented; it does not validate file size.
    """
    if prefer_images and prefer_pdfs:
        raise ValueError(
            "Attachment preference cannot prioritize both images and PDFs."
        )

    supported: Tuple[AttachmentRef, ...] = tuple(
        attachment
        for attachment in context.attachments
        if is_supported_attachment_kind(attachment)
    )

    if prefer_images:
        return tuple(
            sorted(
                supported,
                key=lambda attachment: (
                    0 if is_image_attachment(attachment) else 1
                ),
            )
        )

    if prefer_pdfs:
        return tuple(
            sorted(
                supported,
                key=lambda attachment: (
                    0 if is_pdf_attachment(attachment) else 1
                ),
            )
        )

    return supported


def validate_attachment(
    attachment: AttachmentRef,
    config: DiscordConfig,
) -> AttachmentValidationResult:
    """
    Validate a single attachment against application attachment policy.

    Parameters
    ----------
    attachment : AttachmentRef
        Normalized attachment to validate.
    config : DiscordConfig
        Loaded Discord runtime configuration.

    Returns
    -------
    AttachmentValidationResult
        Validation result for the attachment.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - Unsupported source kinds fail validation immediately.
    - File size is checked against the configured application limit.
    """
    if not is_supported_attachment_kind(attachment):
        return AttachmentValidationResult(
            attachment=attachment,
            is_valid=False,
            reason=(
                "Unsupported attachment type. Only PDF, PNG, JPG, JPEG, and "
                "WEBP uploads are supported."
            ),
        )

    if attachment.size_bytes > config.limits.max_attachment_size_bytes:
        max_mb: float = config.limits.max_attachment_size_bytes / (1024 * 1024)
        return AttachmentValidationResult(
            attachment=attachment,
            is_valid=False,
            reason=(
                f"Attachment exceeds the configured size limit of "
                f"{max_mb:.1f} MB."
            ),
        )

    if attachment.size_bytes <= 0:
        return AttachmentValidationResult(
            attachment=attachment,
            is_valid=False,
            reason="Attachment size must be positive.",
        )

    return AttachmentValidationResult(
        attachment=attachment,
        is_valid=True,
        reason="Attachment passed validation.",
    )


def validate_request_attachments(
    context: DiscordRequestContext,
    config: DiscordConfig,
    prefer_images: bool = False,
    prefer_pdfs: bool = False,
) -> RequestAttachmentValidationResult:
    """
    Validate the candidate attachments associated with a request.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.
    config : DiscordConfig
        Loaded Discord runtime configuration.
    prefer_images : bool
        Whether image attachments should be prioritized in candidate ordering.
    prefer_pdfs : bool
        Whether PDF attachments should be prioritized in candidate ordering.

    Returns
    -------
    RequestAttachmentValidationResult
        Aggregate validation result for the request's candidate attachments.

    Raises
    ------
    ValueError
        Raised if candidate selection receives contradictory preference flags.

    Notes
    -----
    - This function validates only the selected candidate attachments.
    - Requests with no attachments simply return an empty result set and a
      negative aggregate flag.
    """
    candidates: Tuple[AttachmentRef, ...] = select_candidate_attachments(
        context=context,
        prefer_images=prefer_images,
        prefer_pdfs=prefer_pdfs,
    )

    results: Tuple[AttachmentValidationResult, ...] = tuple(
        validate_attachment(attachment=attachment, config=config)
        for attachment in candidates
    )

    selected_attachments: Tuple[AttachmentRef, ...] = tuple(
        result.attachment
        for result in results
        if result.is_valid
    )

    return RequestAttachmentValidationResult(
        results=results,
        has_valid_attachment=len(selected_attachments) > 0,
        selected_attachments=selected_attachments,
    )


def select_first_valid_attachment(
    context: DiscordRequestContext,
    config: DiscordConfig,
    prefer_images: bool = False,
    prefer_pdfs: bool = False,
) -> AttachmentRef | None:
    """
    Select the first valid attachment from a request after policy filtering.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.
    config : DiscordConfig
        Loaded Discord runtime configuration.
    prefer_images : bool
        Whether image attachments should be prioritized.
    prefer_pdfs : bool
        Whether PDF attachments should be prioritized.

    Returns
    -------
    AttachmentRef | None
        First valid candidate attachment, or None if none passed validation.

    Raises
    ------
    ValueError
        Raised if contradictory attachment preference flags are supplied.

    Notes
    -----
    - This helper is intended for single-attachment workflows.
    - Multi-attachment tools should use `validate_request_attachments()`
      directly instead of collapsing to the first match.
    """
    validation_result: RequestAttachmentValidationResult = validate_request_attachments(
        context=context,
        config=config,
        prefer_images=prefer_images,
        prefer_pdfs=prefer_pdfs,
    )

    if not validation_result.selected_attachments:
        return None

    return validation_result.selected_attachments[0]


def summarize_attachment_validation_errors(
    validation_result: RequestAttachmentValidationResult,
) -> Tuple[str, ...]:
    """
    Collect human-readable validation errors from an aggregate result object.

    Parameters
    ----------
    validation_result : RequestAttachmentValidationResult
        Aggregate validation result for request attachments.

    Returns
    -------
    tuple[str, ...]
        Validation error strings for attachments that failed policy checks.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This helper is useful when the response layer needs to explain why no
      valid attachment could be selected.
    """
    return tuple(
        result.reason
        for result in validation_result.results
        if not result.is_valid
    )


def request_contains_pdf(context: DiscordRequestContext) -> bool:
    """
    Return whether a request contains at least one PDF attachment.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.

    Returns
    -------
    bool
        True if the request contains a PDF attachment, else False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This helper does not validate file size or other policy constraints.
    """
    return any(is_pdf_attachment(attachment) for attachment in context.attachments)


def request_contains_image(context: DiscordRequestContext) -> bool:
    """
    Return whether a request contains at least one image attachment.

    Parameters
    ----------
    context : DiscordRequestContext
        Normalized Discord request context.

    Returns
    -------
    bool
        True if the request contains an image attachment, else False.

    Raises
    ------
    RuntimeError
        This function does not raise RuntimeError directly.

    Notes
    -----
    - This helper does not validate file size or other policy constraints.
    """
    return any(
        is_image_attachment(attachment)
        for attachment in context.attachments
    )
