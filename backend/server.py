"""
RSS Reader API Server

FastAPI application providing endpoints for:
- Article management (list, read, bookmark)
- Feed management (add, remove, refresh)
- Summarization
- Search
- Settings
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import config, state
from .database import Database
from .cache import create_cache
from .feed_parser import FeedParser
from .fetcher import Fetcher
from .summarizer import Summarizer
from .clustering import Clusterer
from .routes import (
    articles_router,
    feeds_router,
    summarization_router,
    misc_router,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application resources."""
    # Startup - skip if already initialized (e.g., by tests)
    if state.db is None:
        state.db = Database(config.DB_PATH)
        state.cache = create_cache(config.CACHE_DIR)
        state.feed_parser = FeedParser()
        state.fetcher = Fetcher()

        if config.API_KEY:
            state.summarizer = Summarizer(api_key=config.API_KEY, cache=state.cache)
            state.clusterer = Clusterer(api_key=config.API_KEY, cache=state.cache)
        else:
            print("Warning: ANTHROPIC_API_KEY not set. Summarization and clustering disabled.")

    yield

    # Shutdown
    # Nothing to cleanup for now


app = FastAPI(
    title="RSS Reader API",
    version="2.0.0",
    lifespan=lifespan
)

# Include routers
app.include_router(misc_router)
app.include_router(articles_router)
app.include_router(feeds_router)
app.include_router(summarization_router)
