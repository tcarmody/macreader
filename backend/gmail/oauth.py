"""
Gmail OAuth 2.0 Authentication for IMAP Access.

Handles the OAuth flow to get tokens for Gmail IMAP access.
"""

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import secrets
from typing import TYPE_CHECKING
from urllib.parse import urlencode

import httpx

from ..config import config

if TYPE_CHECKING:
    from ..database import Database


# Gmail IMAP requires full mail access scope
GMAIL_SCOPES = [
    "https://mail.google.com/",  # Full IMAP/SMTP access
    "openid",
    "email",
    "profile",
]

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

# Local callback for desktop OAuth flow
GMAIL_REDIRECT_URI = "http://127.0.0.1:5005/gmail/auth/callback"


class GmailOAuthError(Exception):
    """Gmail OAuth authentication error."""
    pass


@dataclass
class GmailTokens:
    """OAuth tokens for Gmail access."""
    access_token: str
    refresh_token: str
    expires_at: datetime
    email: str
    name: str | None = None


def generate_state() -> str:
    """Generate a secure random state parameter for CSRF protection."""
    return secrets.token_urlsafe(32)


def get_auth_url(state: str) -> str:
    """
    Generate the Google OAuth authorization URL for Gmail IMAP access.

    Args:
        state: Random state parameter for CSRF protection

    Returns:
        Authorization URL to redirect user to
    """
    if not config.GMAIL_CLIENT_ID:
        raise GmailOAuthError("GMAIL_CLIENT_ID not configured")

    params = {
        "client_id": config.GMAIL_CLIENT_ID,
        "redirect_uri": GMAIL_REDIRECT_URI,
        "response_type": "code",
        "scope": " ".join(GMAIL_SCOPES),
        "state": state,
        "access_type": "offline",  # Request refresh token
        "prompt": "consent",  # Always show consent to get refresh token
    }

    return f"{GOOGLE_AUTH_URL}?{urlencode(params)}"


async def exchange_code_for_tokens(code: str) -> GmailTokens:
    """
    Exchange authorization code for access and refresh tokens.

    Args:
        code: Authorization code from OAuth callback

    Returns:
        GmailTokens with access token, refresh token, and user info
    """
    if not config.GMAIL_CLIENT_ID or not config.GMAIL_CLIENT_SECRET:
        raise GmailOAuthError("GMAIL_CLIENT_ID or GMAIL_CLIENT_SECRET not configured")

    async with httpx.AsyncClient() as client:
        # Exchange code for tokens
        token_response = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "client_id": config.GMAIL_CLIENT_ID,
                "client_secret": config.GMAIL_CLIENT_SECRET,
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": GMAIL_REDIRECT_URI,
            },
        )

        if token_response.status_code != 200:
            error_data = token_response.json()
            raise GmailOAuthError(
                f"Token exchange failed: {error_data.get('error_description', error_data.get('error', 'Unknown error'))}"
            )

        token_data = token_response.json()

        access_token = token_data["access_token"]
        refresh_token = token_data.get("refresh_token")
        expires_in = token_data.get("expires_in", 3600)

        if not refresh_token:
            raise GmailOAuthError(
                "No refresh token received. Please revoke app access and try again."
            )

        # Get user info
        userinfo_response = await client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )

        if userinfo_response.status_code != 200:
            raise GmailOAuthError("Failed to fetch user info")

        userinfo = userinfo_response.json()

        return GmailTokens(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=expires_in),
            email=userinfo["email"],
            name=userinfo.get("name"),
        )


async def refresh_access_token(refresh_token: str) -> GmailTokens:
    """
    Refresh an expired access token.

    Args:
        refresh_token: The refresh token

    Returns:
        New GmailTokens with fresh access token
    """
    if not config.GMAIL_CLIENT_ID or not config.GMAIL_CLIENT_SECRET:
        raise GmailOAuthError("GMAIL_CLIENT_ID or GMAIL_CLIENT_SECRET not configured")

    async with httpx.AsyncClient() as client:
        response = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "client_id": config.GMAIL_CLIENT_ID,
                "client_secret": config.GMAIL_CLIENT_SECRET,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            },
        )

        if response.status_code != 200:
            error_data = response.json()
            raise GmailOAuthError(
                f"Token refresh failed: {error_data.get('error_description', error_data.get('error', 'Unknown error'))}"
            )

        token_data = response.json()
        expires_in = token_data.get("expires_in", 3600)

        # Get user email from new token
        userinfo_response = await client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {token_data['access_token']}"},
        )

        email = ""
        name = None
        if userinfo_response.status_code == 200:
            userinfo = userinfo_response.json()
            email = userinfo.get("email", "")
            name = userinfo.get("name")

        return GmailTokens(
            access_token=token_data["access_token"],
            # Google may or may not return a new refresh token
            refresh_token=token_data.get("refresh_token", refresh_token),
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=expires_in),
            email=email,
            name=name,
        )


async def get_valid_access_token(db: "Database") -> tuple[str, str]:
    """
    Get a valid access token, refreshing if necessary.

    Args:
        db: Database instance to read/write tokens

    Returns:
        Tuple of (access_token, email)

    Raises:
        GmailOAuthError: If not configured or token refresh fails
    """
    gmail_config = db.get_gmail_config()

    if not gmail_config:
        raise GmailOAuthError("Gmail not configured")

    # Check if token is expired or expiring soon (within 5 minutes)
    expires_at = gmail_config.get("token_expires_at")
    if expires_at:
        if isinstance(expires_at, str):
            expires_at = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))

        buffer_time = datetime.now(timezone.utc) + timedelta(minutes=5)

        if expires_at > buffer_time:
            # Token is still valid
            return gmail_config["access_token"], gmail_config["email"]

    # Token expired or expiring, refresh it
    try:
        new_tokens = await refresh_access_token(gmail_config["refresh_token"])

        # Update tokens in database
        db.update_gmail_tokens(
            access_token=new_tokens.access_token,
            refresh_token=new_tokens.refresh_token,
            expires_at=new_tokens.expires_at,
        )

        return new_tokens.access_token, gmail_config["email"]

    except GmailOAuthError:
        raise
    except Exception as e:
        raise GmailOAuthError(f"Token refresh failed: {e}")


def generate_xoauth2_string(email: str, access_token: str) -> str:
    """
    Generate XOAUTH2 authentication string for IMAP.

    Args:
        email: Gmail email address
        access_token: OAuth access token

    Returns:
        Base64-encoded XOAUTH2 string
    """
    auth_string = f"user={email}\x01auth=Bearer {access_token}\x01\x01"
    return base64.b64encode(auth_string.encode()).decode()
