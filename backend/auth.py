"""
Authentication module for API access control.

Provides API key-based and OAuth authentication for the RSS Reader API.
Supports three authentication modes:
1. No auth (local development) - when neither AUTH_API_KEY nor OAuth is configured
2. API key auth - when AUTH_API_KEY is set
3. OAuth auth - when OAuth providers are configured with SESSION_SECRET
4. Both - when both are configured, either method works
"""

import secrets
from fastapi import HTTPException, Request, Security, status
from fastapi.security import APIKeyHeader

from .config import config

# Header name for the API key
API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)


def verify_api_key_only(api_key: str | None = Security(API_KEY_HEADER)) -> str:
    """
    Verify the API key from request headers (API key auth only).

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


def verify_api_key(
    request: Request,
    api_key: str | None = Security(API_KEY_HEADER)
) -> str:
    """
    Verify authentication via API key OR OAuth session.

    Authentication modes:
    1. If neither AUTH_API_KEY nor OAuth is configured: allow all (dev mode)
    2. If only AUTH_API_KEY is configured: require valid API key
    3. If only OAuth is configured: require valid session cookie
    4. If both are configured: either valid API key OR valid session works

    Args:
        request: The FastAPI request object
        api_key: The API key from the X-API-Key header

    Returns:
        The validated API key or empty string if OAuth session is valid

    Raises:
        HTTPException: If authentication fails
    """
    api_key_configured = bool(config.AUTH_API_KEY)
    oauth_configured = config.OAUTH_ENABLED

    # No auth configured - allow all (dev mode)
    if not api_key_configured and not oauth_configured:
        return ""

    # Check API key first if provided
    if api_key and api_key_configured:
        if secrets.compare_digest(api_key, config.AUTH_API_KEY):
            return api_key

    # Check OAuth session
    if oauth_configured:
        from .oauth import get_session_from_cookie
        session = get_session_from_cookie(request)
        if session:
            return ""  # Authenticated via OAuth

    # If only API key auth is configured
    if api_key_configured and not oauth_configured:
        if not api_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing API key. Provide X-API-Key header.",
                headers={"WWW-Authenticate": "ApiKey"},
            )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    # If only OAuth is configured
    if oauth_configured and not api_key_configured:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated. Please login.",
        )

    # Both configured but neither worked
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required. Provide valid API key or login.",
    )


def generate_api_key() -> str:
    """Generate a secure random API key."""
    return secrets.token_urlsafe(32)
