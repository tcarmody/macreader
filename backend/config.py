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

# Load environment variables
load_dotenv()


def _parse_bool(value: str | None, default: bool = False) -> bool:
    """Parse boolean from environment variable."""
    if value is None:
        return default
    return value.lower() in ("true", "1", "yes", "on")


class Config:
    """Application configuration from environment."""
    API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/articles.db"))
    CACHE_DIR: Path = Path(os.getenv("CACHE_DIR", "./data/cache"))
    PORT: int = int(os.getenv("PORT", "5005"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

    # Advanced fetching features
    ENABLE_JS_RENDER: bool = _parse_bool(os.getenv("ENABLE_JS_RENDER"), default=True)
    ENABLE_ARCHIVE: bool = _parse_bool(os.getenv("ENABLE_ARCHIVE"), default=True)
    JS_RENDER_TIMEOUT: int = int(os.getenv("JS_RENDER_TIMEOUT", "30000"))  # ms
    ARCHIVE_MAX_AGE_DAYS: int = int(os.getenv("ARCHIVE_MAX_AGE_DAYS", "30"))


config = Config()


class AppState:
    """Shared application state."""
    db: "Database | None" = None
    cache: "TieredCache | None" = None
    summarizer: "Summarizer | None" = None
    clusterer: "Clusterer | None" = None
    feed_parser: "FeedParser | None" = None
    fetcher: "Fetcher | None" = None
    enhanced_fetcher: "object | None" = None  # EnhancedFetcher from advanced module
    refresh_in_progress: bool = False


state = AppState()


def get_db() -> "Database":
    """Dependency to get database instance."""
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db
