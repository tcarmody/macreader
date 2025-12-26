"""
Gmail IMAP integration routes.

Handles OAuth authentication and newsletter fetching from Gmail.
"""

import logging
import secrets
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import HTMLResponse

from ..auth import verify_api_key
from ..config import config, state, get_db
from ..database import Database
from ..gmail import (
    get_auth_url,
    exchange_code_for_tokens,
    get_valid_access_token,
    GmailOAuthError,
    generate_state,
    GmailIMAPClient,
    GmailIMAPError,
    fetch_newsletters_from_gmail,
)
from ..schemas import (
    GmailAuthURLResponse,
    GmailStatusResponse,
    GmailConfigUpdateRequest,
    GmailLabelResponse,
    GmailFetchResponse,
)


logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/gmail",
    tags=["gmail"],
    dependencies=[Depends(verify_api_key)]
)

# Store OAuth states temporarily (in production, use Redis or similar)
_oauth_states: dict[str, bool] = {}


@router.get("/auth/url")
async def get_gmail_auth_url() -> GmailAuthURLResponse:
    """
    Get the Gmail OAuth authorization URL.

    The client should redirect the user to this URL to initiate OAuth.
    After authentication, Google will redirect to /gmail/auth/callback.
    """
    if not config.GMAIL_CLIENT_ID or not config.GMAIL_CLIENT_SECRET:
        raise HTTPException(
            status_code=400,
            detail="Gmail OAuth not configured. Set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET."
        )

    state = generate_state()
    _oauth_states[state] = True

    auth_url = get_auth_url(state)

    return GmailAuthURLResponse(
        auth_url=auth_url,
        state=state
    )


@router.get("/auth/callback")
async def gmail_auth_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: Database = Depends(get_db)
) -> HTMLResponse:
    """
    OAuth callback endpoint.

    Google redirects here after user authentication.
    Exchanges the code for tokens and saves the configuration.
    """
    # Verify state
    if state not in _oauth_states:
        return HTMLResponse(
            content=_error_page("Invalid OAuth state. Please try again."),
            status_code=400
        )

    del _oauth_states[state]

    try:
        # Exchange code for tokens
        tokens = await exchange_code_for_tokens(code)

        # Save to database
        db.save_gmail_config(
            email=tokens.email,
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            token_expires_at=tokens.expires_at,
        )

        logger.info(f"Gmail connected for {tokens.email}")

        return HTMLResponse(
            content=_success_page(tokens.email),
            status_code=200
        )

    except GmailOAuthError as e:
        logger.error(f"Gmail OAuth error: {e}")
        return HTMLResponse(
            content=_error_page(str(e)),
            status_code=400
        )
    except Exception as e:
        logger.exception("Gmail OAuth callback error")
        return HTMLResponse(
            content=_error_page("An unexpected error occurred."),
            status_code=500
        )


@router.get("/status")
async def get_gmail_status(
    db: Database = Depends(get_db)
) -> GmailStatusResponse:
    """Get Gmail connection status and configuration."""
    gmail_config = db.get_gmail_config()

    if not gmail_config:
        return GmailStatusResponse(connected=False)

    return GmailStatusResponse(
        connected=True,
        email=gmail_config.get("email"),
        monitored_label=gmail_config.get("monitored_label"),
        poll_interval_minutes=gmail_config.get("poll_interval_minutes", 30),
        last_fetched_uid=gmail_config.get("last_fetched_uid", 0),
        is_polling_enabled=gmail_config.get("is_enabled", True),
        last_fetch=gmail_config.get("updated_at"),
    )


@router.get("/labels")
async def get_gmail_labels(
    db: Database = Depends(get_db)
) -> GmailLabelResponse:
    """
    Get available Gmail labels/folders.

    Requires an active Gmail connection.
    """
    try:
        access_token, email = await get_valid_access_token(db)

        client = GmailIMAPClient(email)
        client.connect(access_token)

        try:
            labels = client.list_labels()
            return GmailLabelResponse(labels=labels)
        finally:
            client.disconnect()

    except GmailOAuthError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except GmailIMAPError as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/config")
async def update_gmail_config(
    request: GmailConfigUpdateRequest,
    db: Database = Depends(get_db)
) -> GmailStatusResponse:
    """Update Gmail configuration settings."""
    gmail_config = db.get_gmail_config()

    if not gmail_config:
        raise HTTPException(status_code=404, detail="Gmail not connected")

    db.update_gmail_config(
        monitored_label=request.monitored_label,
        poll_interval_minutes=request.poll_interval_minutes,
        is_enabled=request.is_enabled,
    )

    # Restart scheduler if interval changed
    if request.poll_interval_minutes is not None or request.is_enabled is not None:
        from ..gmail import gmail_scheduler
        if gmail_scheduler:
            await gmail_scheduler.restart()

    return await get_gmail_status(db)


@router.post("/fetch")
async def trigger_gmail_fetch(
    db: Database = Depends(get_db)
) -> GmailFetchResponse:
    """
    Trigger an immediate fetch of newsletters from Gmail.

    Returns the number of newsletters imported.
    """
    result = await fetch_newsletters_from_gmail(db)

    return GmailFetchResponse(
        success=result.success,
        imported=result.imported,
        failed=result.failed,
        skipped=result.skipped,
        errors=result.errors,
        message=result.message,
    )


@router.delete("/disconnect")
async def disconnect_gmail(
    db: Database = Depends(get_db)
) -> dict:
    """
    Disconnect Gmail account.

    Removes all stored tokens and configuration.
    """
    db.delete_gmail_config()

    # Stop scheduler
    from ..gmail import gmail_scheduler
    if gmail_scheduler:
        await gmail_scheduler.stop()

    logger.info("Gmail disconnected")

    return {"success": True, "message": "Gmail disconnected"}


# ─────────────────────────────────────────────────────────────
# HTML Templates for OAuth Callback
# ─────────────────────────────────────────────────────────────

def _success_page(email: str) -> str:
    """Generate success HTML page for OAuth callback."""
    return f"""
<!DOCTYPE html>
<html>
<head>
    <title>Gmail Connected</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }}
        .card {{
            background: white;
            padding: 40px;
            border-radius: 16px;
            text-align: center;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            max-width: 400px;
        }}
        .icon {{
            font-size: 48px;
            margin-bottom: 20px;
        }}
        h1 {{
            color: #22c55e;
            margin: 0 0 10px 0;
        }}
        p {{
            color: #666;
            margin: 0 0 20px 0;
        }}
        .email {{
            background: #f3f4f6;
            padding: 8px 16px;
            border-radius: 8px;
            font-family: monospace;
            display: inline-block;
            margin-bottom: 20px;
        }}
        .note {{
            font-size: 14px;
            color: #999;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">✓</div>
        <h1>Gmail Connected!</h1>
        <p>Successfully connected to:</p>
        <div class="email">{email}</div>
        <p class="note">You can close this window and return to the app.</p>
    </div>
    <script>
        // Auto-close after 3 seconds
        setTimeout(() => window.close(), 3000);
    </script>
</body>
</html>
"""


def _error_page(error: str) -> str:
    """Generate error HTML page for OAuth callback."""
    return f"""
<!DOCTYPE html>
<html>
<head>
    <title>Connection Failed</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #f87171 0%, #dc2626 100%);
        }}
        .card {{
            background: white;
            padding: 40px;
            border-radius: 16px;
            text-align: center;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            max-width: 400px;
        }}
        .icon {{
            font-size: 48px;
            margin-bottom: 20px;
        }}
        h1 {{
            color: #dc2626;
            margin: 0 0 10px 0;
        }}
        p {{
            color: #666;
            margin: 0 0 20px 0;
        }}
        .error {{
            background: #fef2f2;
            border: 1px solid #fecaca;
            padding: 12px 16px;
            border-radius: 8px;
            color: #dc2626;
            font-size: 14px;
            margin-bottom: 20px;
            text-align: left;
        }}
        .note {{
            font-size: 14px;
            color: #999;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">✗</div>
        <h1>Connection Failed</h1>
        <p>Unable to connect to Gmail:</p>
        <div class="error">{error}</div>
        <p class="note">Please close this window and try again.</p>
    </div>
</body>
</html>
"""
