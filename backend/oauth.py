"""
OAuth authentication module.

Provides OAuth2 authentication via Google and GitHub providers.
Uses signed cookies for session management.
"""

import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from authlib.integrations.starlette_client import OAuth
from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from pydantic import BaseModel

from .config import config

logger = logging.getLogger(__name__)

# OAuth client setup
oauth = OAuth()

# Session serializer for secure cookies
_serializer: Optional[URLSafeTimedSerializer] = None


def get_serializer() -> URLSafeTimedSerializer:
    """Get the session serializer, creating it if needed."""
    global _serializer
    if _serializer is None:
        if not config.SESSION_SECRET:
            raise HTTPException(
                status_code=500,
                detail="SESSION_SECRET not configured"
            )
        _serializer = URLSafeTimedSerializer(config.SESSION_SECRET)
    return _serializer


def setup_oauth():
    """Configure OAuth providers if credentials are available."""
    if config.GOOGLE_CLIENT_ID and config.GOOGLE_CLIENT_SECRET:
        oauth.register(
            name="google",
            client_id=config.GOOGLE_CLIENT_ID,
            client_secret=config.GOOGLE_CLIENT_SECRET,
            server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
            client_kwargs={"scope": "openid email profile"},
        )
        logger.info("Google OAuth configured")

    if config.GITHUB_CLIENT_ID and config.GITHUB_CLIENT_SECRET:
        oauth.register(
            name="github",
            client_id=config.GITHUB_CLIENT_ID,
            client_secret=config.GITHUB_CLIENT_SECRET,
            authorize_url="https://github.com/login/oauth/authorize",
            access_token_url="https://github.com/login/oauth/access_token",
            api_base_url="https://api.github.com/",
            client_kwargs={"scope": "user:email"},
        )
        logger.info("GitHub OAuth configured")


class UserSession(BaseModel):
    """User session data stored in cookie."""
    email: str
    name: Optional[str] = None
    provider: str  # "google" or "github"
    created_at: str


class OAuthStatus(BaseModel):
    """OAuth configuration status."""
    enabled: bool
    google_enabled: bool
    github_enabled: bool
    user: Optional[UserSession] = None


def create_session_cookie(user: UserSession, response: Response) -> None:
    """Create a signed session cookie."""
    serializer = get_serializer()
    session_data = user.model_dump()
    signed_value = serializer.dumps(session_data)

    logger.warning(f"Setting cookie with value length: {len(signed_value)}")

    # Set cookie with security options
    # Use samesite="none" for cross-origin requests (frontend on different domain than backend)
    # This requires secure=True (HTTPS)
    response.set_cookie(
        key="session",
        value=signed_value,
        max_age=config.SESSION_MAX_AGE,
        httponly=True,
        secure=True,  # Required for samesite="none"
        samesite="none",  # Allow cross-origin cookie sending
        path="/",
    )

    # Log the actual Set-Cookie header that will be sent
    logger.warning(f"Response headers after set_cookie: {dict(response.headers)}")


def get_session_from_cookie(request: Request) -> Optional[UserSession]:
    """Extract and validate session from cookie or Authorization header."""
    # First try Authorization header (for cross-origin requests where cookies don't work)
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header[7:]  # Remove "Bearer " prefix
        try:
            serializer = get_serializer()
            session_data = serializer.loads(token, max_age=config.SESSION_MAX_AGE)
            return UserSession(**session_data)
        except SignatureExpired:
            logger.debug("Auth token expired")
        except BadSignature:
            logger.warning("Invalid auth token signature")
        except Exception as e:
            logger.warning(f"Error parsing auth token: {e}")

    # Fall back to cookie
    session_cookie = request.cookies.get("session")
    if not session_cookie:
        return None

    try:
        serializer = get_serializer()
        session_data = serializer.loads(
            session_cookie,
            max_age=config.SESSION_MAX_AGE
        )
        return UserSession(**session_data)
    except SignatureExpired:
        logger.debug("Session cookie expired")
        return None
    except BadSignature:
        logger.warning("Invalid session cookie signature")
        return None
    except Exception as e:
        logger.warning(f"Error parsing session cookie: {e}")
        return None


def clear_session_cookie(response: Response) -> None:
    """Clear the session cookie."""
    response.delete_cookie(
        key="session",
        path="/",
        httponly=True,
        secure=config.SESSION_SECURE,
        samesite="lax",
    )


def verify_oauth_session(request: Request) -> Optional[UserSession]:
    """
    Verify OAuth session from request.

    Returns the user session if valid, None otherwise.
    Used as a FastAPI dependency for protected routes.
    """
    return get_session_from_cookie(request)


def require_oauth_session(request: Request) -> UserSession:
    """
    Require valid OAuth session.

    Raises 401 if not authenticated.
    Used as a FastAPI dependency for protected routes.
    """
    session = get_session_from_cookie(request)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated. Please login.",
        )
    return session


# Create OAuth router
router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/status")
async def auth_status(request: Request) -> OAuthStatus:
    """Get authentication status and available providers."""
    user = get_session_from_cookie(request)

    return OAuthStatus(
        enabled=config.OAUTH_ENABLED,
        google_enabled=bool(config.GOOGLE_CLIENT_ID and config.GOOGLE_CLIENT_SECRET),
        github_enabled=bool(config.GITHUB_CLIENT_ID and config.GITHUB_CLIENT_SECRET),
        user=user,
    )


@router.get("/login/{provider}")
async def login(provider: str, request: Request):
    """Initiate OAuth login flow."""
    if provider not in ("google", "github"):
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    client = oauth.create_client(provider)
    if not client:
        raise HTTPException(
            status_code=400,
            detail=f"Provider {provider} not configured"
        )

    # Generate callback URL
    redirect_uri = str(request.url_for("oauth_callback", provider=provider))

    # Force HTTPS in production (behind reverse proxy like Railway/Vercel)
    if redirect_uri.startswith("http://") and not redirect_uri.startswith("http://localhost") and not redirect_uri.startswith("http://127.0.0.1"):
        redirect_uri = redirect_uri.replace("http://", "https://", 1)

    # Store state for CSRF protection
    state = secrets.token_urlsafe(32)

    return await client.authorize_redirect(request, redirect_uri, state=state)


@router.get("/callback/{provider}")
async def oauth_callback(provider: str, request: Request):
    """Handle OAuth callback and create session."""
    if provider not in ("google", "github"):
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    client = oauth.create_client(provider)
    if not client:
        raise HTTPException(
            status_code=400,
            detail=f"Provider {provider} not configured"
        )

    try:
        token = await client.authorize_access_token(request)
    except Exception as e:
        logger.error(f"OAuth callback error: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Authentication failed: {str(e)}"
        )

    # Get user info based on provider
    if provider == "google":
        user_info = token.get("userinfo")
        if not user_info:
            user_info = await client.userinfo(token=token)

        email = user_info.get("email")
        name = user_info.get("name")

    elif provider == "github":
        resp = await client.get("user", token=token)
        user_data = resp.json()

        # GitHub may not return email in user data, need separate call
        email = user_data.get("email")
        if not email:
            email_resp = await client.get("user/emails", token=token)
            emails = email_resp.json()
            primary_email = next(
                (e for e in emails if e.get("primary")),
                emails[0] if emails else None
            )
            email = primary_email.get("email") if primary_email else None

        name = user_data.get("name") or user_data.get("login")

    if not email:
        raise HTTPException(
            status_code=400,
            detail="Could not retrieve email from OAuth provider"
        )

    # Check if email is in allowed list (if configured)
    # Supports exact emails (user@example.com) and domain wildcards (*@example.com)
    if config.OAUTH_ALLOWED_EMAILS:
        allowed = [e.strip().lower() for e in config.OAUTH_ALLOWED_EMAILS.split(",")]
        email_lower = email.lower()
        email_domain = email_lower.split("@")[-1]

        is_allowed = False
        for pattern in allowed:
            if pattern.startswith("*@"):
                # Domain wildcard: *@example.com matches any email from that domain
                allowed_domain = pattern[2:]  # Remove "*@" prefix
                if email_domain == allowed_domain:
                    is_allowed = True
                    break
            elif email_lower == pattern:
                # Exact email match
                is_allowed = True
                break

        if not is_allowed:
            logger.warning(f"OAuth login rejected for email: {email}")
            raise HTTPException(
                status_code=403,
                detail="Access denied. Email not in allowed list."
            )

    # Create session
    user = UserSession(
        email=email,
        name=name,
        provider=provider,
        created_at=datetime.now(timezone.utc).isoformat(),
    )

    # Create session token
    serializer = get_serializer()
    session_data = user.model_dump()
    session_token = serializer.dumps(session_data)

    # Redirect to frontend with token in URL
    # Frontend will store this and send it back on API requests
    frontend_url = config.OAUTH_FRONTEND_URL or "/"
    redirect_url = f"{frontend_url}?auth_token={session_token}"
    logger.warning(f"OAuth callback: redirecting to {frontend_url} with token")

    response = RedirectResponse(url=redirect_url, status_code=302)

    # Also try to set the cookie (may work for same-site requests)
    create_session_cookie(user, response)

    logger.warning(f"OAuth login successful: {email} via {provider}")
    return response


@router.post("/logout")
async def logout(response: Response):
    """Clear session and logout."""
    clear_session_cookie(response)
    return {"message": "Logged out successfully"}


@router.get("/me")
async def get_current_user(request: Request) -> Optional[UserSession]:
    """Get current authenticated user."""
    return get_session_from_cookie(request)
