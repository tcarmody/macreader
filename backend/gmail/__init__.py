"""
Gmail Integration Module.

Provides Gmail IMAP access for newsletter fetching:
- OAuth 2.0 authentication flow
- IMAP client with XOAUTH2 support
- Background polling scheduler
"""

from .oauth import (
    GmailOAuthError,
    GmailTokens,
    generate_state,
    get_auth_url,
    exchange_code_for_tokens,
    refresh_access_token,
    get_valid_access_token,
    generate_xoauth2_string,
    GMAIL_REDIRECT_URI,
)

from .imap import (
    GmailIMAPError,
    FetchedEmail,
    GmailIMAPClient,
    GmailFetchResult,
    fetch_newsletters_from_gmail,
)

from .scheduler import (
    GmailPollingScheduler,
    gmail_scheduler,
    start_gmail_scheduler,
    stop_gmail_scheduler,
)

__all__ = [
    # OAuth
    "GmailOAuthError",
    "GmailTokens",
    "generate_state",
    "get_auth_url",
    "exchange_code_for_tokens",
    "refresh_access_token",
    "get_valid_access_token",
    "generate_xoauth2_string",
    "GMAIL_REDIRECT_URI",
    # IMAP
    "GmailIMAPError",
    "FetchedEmail",
    "GmailIMAPClient",
    "GmailFetchResult",
    "fetch_newsletters_from_gmail",
    # Scheduler
    "GmailPollingScheduler",
    "gmail_scheduler",
    "start_gmail_scheduler",
    "stop_gmail_scheduler",
]
