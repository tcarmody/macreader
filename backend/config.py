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


class Config:
    """Application configuration from environment."""
    API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/articles.db"))
    CACHE_DIR: Path = Path(os.getenv("CACHE_DIR", "./data/cache"))
    PORT: int = int(os.getenv("PORT", "5005"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")


config = Config()


class AppState:
    """Shared application state."""
    db: "Database | None" = None
    cache: "TieredCache | None" = None
    summarizer: "Summarizer | None" = None
    clusterer: "Clusterer | None" = None
    feed_parser: "FeedParser | None" = None
    fetcher: "Fetcher | None" = None
    refresh_in_progress: bool = False


state = AppState()


def get_db() -> "Database":
    """Dependency to get database instance."""
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db
