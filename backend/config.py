"""
Configuration and application state management.
"""

import os
from pathlib import Path
from typing import TYPE_CHECKING

from dotenv import load_dotenv
from fastapi import HTTPException

if TYPE_CHECKING:
    from .database import Database
    from .cache import TieredCache
    from .feed_parser import FeedParser
    from .fetcher import Fetcher
    from .summarizer import Summarizer
    from .clustering import Clusterer
    from .providers import LLMProvider
    from .services.chat_service import ChatService

# Load environment variables from project root
# Use the backend directory's parent to find .env
_backend_dir = Path(__file__).parent
_project_root = _backend_dir.parent
load_dotenv(_project_root / ".env")


def _parse_bool(value: str | None, default: bool = False) -> bool:
    """Parse boolean from environment variable."""
    if value is None:
        return default
    return value.lower() in ("true", "1", "yes", "on")


class Config:
    """Application configuration from environment."""
    # Authentication
    # Set this to require API key authentication for all endpoints
    # If not set, the API is open (suitable for local development only)
    AUTH_API_KEY: str = os.getenv("AUTH_API_KEY", "")

    # LLM Provider configuration
    # Set one of these API keys based on your preferred provider
    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")

    # Preferred provider: "anthropic", "openai", or "google"
    # If not set, uses the first available key in order: Anthropic > OpenAI > Google
    LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "")

    # Optional: override the default model for the selected provider
    LLM_MODEL: str = os.getenv("LLM_MODEL", "")

    # Related Links (Exa Neural Search)
    EXA_API_KEY: str = os.getenv("EXA_API_KEY", "")
    ENABLE_RELATED_LINKS: bool = _parse_bool(os.getenv("ENABLE_RELATED_LINKS"), default=True)

    # Legacy alias for backwards compatibility
    API_KEY: str = ANTHROPIC_API_KEY

    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/articles.db"))
    CACHE_DIR: Path = Path(os.getenv("CACHE_DIR", "./data/cache"))
    PORT: int = int(os.getenv("PORT", "5005"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

    # Rate limiting
    # Requests per minute per IP (0 = disabled)
    RATE_LIMIT_PER_MINUTE: int = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

    # File upload limits
    # Maximum file size in MB (default 50MB)
    MAX_UPLOAD_SIZE_MB: int = int(os.getenv("MAX_UPLOAD_SIZE_MB", "50"))

    # Advanced fetching features
    ENABLE_JS_RENDER: bool = _parse_bool(os.getenv("ENABLE_JS_RENDER"), default=True)
    ENABLE_ARCHIVE: bool = _parse_bool(os.getenv("ENABLE_ARCHIVE"), default=True)
    JS_RENDER_TIMEOUT: int = int(os.getenv("JS_RENDER_TIMEOUT", "30000"))  # ms
    ARCHIVE_MAX_AGE_DAYS: int = int(os.getenv("ARCHIVE_MAX_AGE_DAYS", "30"))

    # OAuth Configuration
    # Google OAuth (for general login)
    GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET: str = os.getenv("GOOGLE_CLIENT_SECRET", "")

    # Gmail IMAP OAuth (separate credentials for IMAP access)
    # Falls back to GOOGLE_CLIENT_ID/SECRET if not set
    GMAIL_CLIENT_ID: str = os.getenv("GMAIL_CLIENT_ID", "") or os.getenv("GOOGLE_CLIENT_ID", "")
    GMAIL_CLIENT_SECRET: str = os.getenv("GMAIL_CLIENT_SECRET", "") or os.getenv("GOOGLE_CLIENT_SECRET", "")

    # GitHub OAuth
    GITHUB_CLIENT_ID: str = os.getenv("GITHUB_CLIENT_ID", "")
    GITHUB_CLIENT_SECRET: str = os.getenv("GITHUB_CLIENT_SECRET", "")

    # Session settings
    # Secret key for signing session cookies (required for OAuth)
    # Generate with: python -c "import secrets; print(secrets.token_urlsafe(32))"
    SESSION_SECRET: str = os.getenv("SESSION_SECRET", "")

    # Session lifetime in seconds (default: 7 days)
    SESSION_MAX_AGE: int = int(os.getenv("SESSION_MAX_AGE", str(7 * 24 * 60 * 60)))

    # Set to False for local development over HTTP
    SESSION_SECURE: bool = _parse_bool(os.getenv("SESSION_SECURE"), default=True)

    # Comma-separated list of allowed email addresses (empty = allow all)
    OAUTH_ALLOWED_EMAILS: str = os.getenv("OAUTH_ALLOWED_EMAILS", "")

    # Frontend URL to redirect to after OAuth callback
    OAUTH_FRONTEND_URL: str = os.getenv("OAUTH_FRONTEND_URL", "/")

    @property
    def OAUTH_ENABLED(self) -> bool:
        """Check if OAuth is configured and enabled."""
        has_provider = bool(
            (self.GOOGLE_CLIENT_ID and self.GOOGLE_CLIENT_SECRET) or
            (self.GITHUB_CLIENT_ID and self.GITHUB_CLIENT_SECRET)
        )
        has_secret = bool(self.SESSION_SECRET)
        return has_provider and has_secret

    @classmethod
    def has_llm_key(cls) -> bool:
        """Check if any LLM API key is configured."""
        return bool(cls.ANTHROPIC_API_KEY or cls.OPENAI_API_KEY or cls.GOOGLE_API_KEY)


config = Config()


class AppState:
    """Shared application state."""
    db: "Database | None" = None
    cache: "TieredCache | None" = None
    provider: "LLMProvider | None" = None  # LLM provider instance
    summarizer: "Summarizer | None" = None
    clusterer: "Clusterer | None" = None
    chat_service: "ChatService | None" = None  # Chat service for article Q&A
    exa_service: "object | None" = None  # ExaSearchService for related links
    feed_parser: "FeedParser | None" = None
    fetcher: "Fetcher | None" = None
    enhanced_fetcher: "object | None" = None  # EnhancedFetcher from advanced module
    refresh_in_progress: bool = False
    last_refresh_notifications: list = []  # NotificationMatch objects from last refresh


state = AppState()


def get_db() -> "Database":
    """Dependency to get database instance."""
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db


def get_chat_service() -> "ChatService | None":
    """Dependency to get chat service instance (may be None if LLM not configured)."""
    return state.chat_service
