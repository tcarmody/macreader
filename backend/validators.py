"""
Content validation utilities for common validation patterns.
"""

from fastapi import HTTPException

MIN_CONTENT_LENGTH = 50


def require_sufficient_content(
    content: str | None,
    detail: str = "Content is insufficient for processing"
) -> str:
    """
    Validate that content meets minimum length requirements.

    Args:
        content: The content to validate
        detail: Error message if validation fails

    Returns:
        The stripped content if valid

    Raises:
        HTTPException: 400 if content is None, empty, or too short
    """
    if not content or len(content.strip()) < MIN_CONTENT_LENGTH:
        raise HTTPException(status_code=400, detail=detail)
    return content.strip()
