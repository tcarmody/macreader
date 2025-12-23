"""
Authentication module for API access control.

Provides API key-based authentication for the RSS Reader API.
"""

import secrets
from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from .config import config

# Header name for the API key
API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)


def verify_api_key(api_key: str | None = Security(API_KEY_HEADER)) -> str:
    """
    Verify the API key from request headers.

    If AUTH_API_KEY is not configured in the environment, authentication
    is disabled and all requests are allowed (for local development).

    Args:
        api_key: The API key from the X-API-Key header

    Returns:
        The validated API key

    Raises:
        HTTPException: If authentication is enabled and the key is missing or invalid
    """
    configured_key = config.AUTH_API_KEY

    # If no auth key is configured, skip authentication (local dev mode)
    if not configured_key:
        return ""

    # Auth is enabled - require valid key
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Provide X-API-Key header.",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    # Use constant-time comparison to prevent timing attacks
    if not secrets.compare_digest(api_key, configured_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    return api_key


def generate_api_key() -> str:
    """Generate a secure random API key."""
    return secrets.token_urlsafe(32)
