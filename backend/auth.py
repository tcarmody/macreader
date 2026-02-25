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
from typing import TYPE_CHECKING

from fastapi import Depends, HTTPException, Request, Security, status
from fastapi.security import APIKeyHeader

from .config import config, get_db

if TYPE_CHECKING:
    from .database import Database

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


def get_current_user(
    request: Request,
    db: "Database" = Depends(get_db),
    api_key: str | None = Security(API_KEY_HEADER)
) -> int:
    """
    Get the current user's ID from authentication.

    This dependency returns a user_id (integer) that can be used
    for database operations requiring user context.

    Authentication modes:
    1. OAuth session: Look up or create user by email from session
    2. Valid API key: Return the shared "API User"
    3. Dev mode (no auth): Return the shared "API User"

    Args:
        request: The FastAPI request object
        db: Database instance
        api_key: The API key from the X-API-Key header

    Returns:
        User ID (integer) for database operations

    Raises:
        HTTPException: If authentication fails
    """
    api_key_configured = bool(config.AUTH_API_KEY)
    oauth_configured = config.OAUTH_ENABLED

    # Check OAuth session first (most specific user identity)
    if oauth_configured:
        from .oauth import get_session_from_cookie
        session = get_session_from_cookie(request)
        if session:
            # Get or create user from OAuth session
            user_id = db.users.get_or_create(
                email=session.email,
                name=session.name,
                provider=session.provider
            )
            db.users.update_last_login(user_id)
            return user_id

    # Check API key
    if api_key and api_key_configured:
        if secrets.compare_digest(api_key, config.AUTH_API_KEY):
            return db.users.get_or_create_api_user()

    # Dev mode (no auth configured) - use shared API user
    if not api_key_configured and not oauth_configured:
        return db.users.get_or_create_api_user()

    # Authentication required but not provided
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


def require_admin(
    request: Request,
    db: "Database" = Depends(get_db),
    user_id: int = Depends(get_current_user)
) -> int:
    """
    Require the current user to have admin privileges.

    Admin access is granted to:
    1. API key users (backwards compatibility - trusted clients like macOS app)
    2. OAuth users whose email is in ADMIN_EMAILS
    3. All users when ADMIN_EMAILS is empty (no restriction configured)

    Returns:
        User ID if admin, raises 403 otherwise
    """
    if not config.ADMIN_EMAILS:
        return user_id

    user = db.users.get_by_id(user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )

    # API key users always have admin access
    if user.provider == "api_key":
        return user_id

    if user.email.lower() in config.ADMIN_EMAILS:
        return user_id

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Admin access required. Contact an administrator for access.",
    )


def is_admin_user(db: "Database", user_id: int) -> bool:
    """Check if a user has admin privileges (non-dependency helper)."""
    if not config.ADMIN_EMAILS:
        return True
    user = db.users.get_by_id(user_id)
    if not user:
        return False
    if user.provider == "api_key":
        return True
    return user.email.lower() in config.ADMIN_EMAILS
