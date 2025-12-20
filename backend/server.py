"""
RSS Reader API Server

FastAPI application providing endpoints for:
- Article management (list, read, bookmark)
- Feed management (add, remove, refresh)
- Summarization
- Search
- Settings
"""

import logging
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

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application resources."""
    # Startup - skip if already initialized (e.g., by tests)
    if state.db is None:
        state.db = Database(config.DB_PATH)
        state.cache = create_cache(config.CACHE_DIR)
        state.feed_parser = FeedParser()
        state.fetcher = Fetcher()

        # Initialize enhanced fetcher if advanced features are enabled
        if config.ENABLE_JS_RENDER or config.ENABLE_ARCHIVE:
            try:
                from .advanced import EnhancedFetcher
                state.enhanced_fetcher = EnhancedFetcher(
                    enable_js_render=config.ENABLE_JS_RENDER,
                    enable_archive=config.ENABLE_ARCHIVE,
                    js_render_timeout=config.JS_RENDER_TIMEOUT,
                    archive_max_age_days=config.ARCHIVE_MAX_AGE_DAYS,
                )
                await state.enhanced_fetcher.start()
                logger.info(
                    f"Enhanced fetcher initialized (JS render: {config.ENABLE_JS_RENDER}, "
                    f"Archive: {config.ENABLE_ARCHIVE})"
                )
            except ImportError as e:
                logger.warning(f"Could not initialize enhanced fetcher: {e}")
            except Exception as e:
                logger.warning(f"Enhanced fetcher initialization failed: {e}")

        if config.API_KEY:
            state.summarizer = Summarizer(api_key=config.API_KEY, cache=state.cache)
            state.clusterer = Clusterer(api_key=config.API_KEY, cache=state.cache)
        else:
            print("Warning: ANTHROPIC_API_KEY not set. Summarization and clustering disabled.")

    yield

    # Shutdown
    if state.enhanced_fetcher:
        try:
            await state.enhanced_fetcher.stop()
        except Exception as e:
            logger.warning(f"Error stopping enhanced fetcher: {e}")


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
