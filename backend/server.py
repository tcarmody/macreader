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
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware

from .config import config, state
from .database import Database
from .cache import create_cache
from .feed_parser import FeedParser
from .fetcher import Fetcher
from .summarizer import Summarizer
from .clustering import Clusterer
from .providers import get_provider_from_env
from .routes import (
    articles_router,
    feeds_router,
    summarization_router,
    misc_router,
    misc_public_router,
    standalone_router,
    notifications_router,
    statistics_router,
)
from .routes.gmail import router as gmail_router
from .routes.chat import router as chat_router
from .services.chat_service import ChatService
from .rate_limit import setup_rate_limiting
from .oauth import router as oauth_router, setup_oauth
from .gmail import start_gmail_scheduler, stop_gmail_scheduler

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

        # Initialize LLM provider (supports Anthropic, OpenAI, Google)
        state.provider = get_provider_from_env(
            anthropic_key=config.ANTHROPIC_API_KEY or None,
            openai_key=config.OPENAI_API_KEY or None,
            google_key=config.GOOGLE_API_KEY or None,
            preferred_provider=config.LLM_PROVIDER or None,
            default_model=config.LLM_MODEL or None,
        )

        if state.provider:
            state.summarizer = Summarizer(provider=state.provider, cache=state.cache)
            state.clusterer = Clusterer(provider=state.provider, cache=state.cache)
            state.chat_service = ChatService(db=state.db, provider=state.provider)

            # Initialize Exa search service for related links
            if config.EXA_API_KEY and config.ENABLE_RELATED_LINKS:
                from .services.related_links import ExaSearchService
                state.exa_service = ExaSearchService(
                    api_key=config.EXA_API_KEY,
                    cache=state.cache,
                    provider=state.provider
                )
                logger.info("Exa search service initialized for related links")
            elif config.ENABLE_RELATED_LINKS and not config.EXA_API_KEY:
                logger.warning(
                    "Related links feature enabled but EXA_API_KEY not configured. "
                    "Sign up at https://exa.ai for free $10 credits (~2,000 searches)."
                )

            logger.info(f"LLM provider initialized: {state.provider.name}")
        else:
            logger.warning(
                "No LLM API key configured. Set ANTHROPIC_API_KEY, OPENAI_API_KEY, "
                "or GOOGLE_API_KEY. Summarization, clustering, and chat disabled."
            )

        # Setup OAuth providers
        setup_oauth()
        if config.OAUTH_ENABLED:
            logger.info("OAuth authentication enabled")

        # Start Gmail polling scheduler
        await start_gmail_scheduler(state.db)

    yield

    # Shutdown Gmail scheduler
    await stop_gmail_scheduler()

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

# CORS configuration for web frontend
# Allow origins from environment variable or default to common development URLs
cors_origins = os.getenv("CORS_ORIGINS", "").split(",") if os.getenv("CORS_ORIGINS") else []
cors_origins = [origin.strip() for origin in cors_origins if origin.strip()]

# Always allow localhost for development
default_origins = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173",
]

# Combine configured and default origins
all_origins = list(set(cors_origins + default_origins))

# Allowed HTTP methods (restrict to what the API actually uses)
allowed_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]

# Allowed headers (only what the frontend needs)
allowed_headers = [
    "Content-Type",
    "Authorization",
    "X-API-Key",           # Auth API key
    "X-Anthropic-Key",     # LLM provider keys
    "X-OpenAI-Key",
    "X-Google-Key",
    "X-Preferred-Provider",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=all_origins,
    allow_credentials=True,
    allow_methods=allowed_methods,
    allow_headers=allowed_headers,
    expose_headers=["Retry-After"],  # For rate limiting
)

# Session middleware for OAuth state storage (required by authlib)
# Uses SESSION_SECRET for signing - falls back to a default for non-OAuth use
session_secret = config.SESSION_SECRET or "dev-session-secret-not-for-production"
app.add_middleware(SessionMiddleware, secret_key=session_secret)

# Setup rate limiting
setup_rate_limiting(app)
logger.info(f"Rate limiting: {config.RATE_LIMIT_PER_MINUTE} requests/minute per IP")


@app.middleware("http")
async def inject_api_keys_from_headers(request: Request, call_next):
    """
    Middleware to extract API keys from request headers and make them available.
    This allows the web frontend to pass user-provided API keys.

    Headers:
    - X-Anthropic-Key: Anthropic API key
    - X-OpenAI-Key: OpenAI API key
    - X-Google-Key: Google API key
    - X-Preferred-Provider: Preferred LLM provider
    """
    # Store original values
    original_anthropic = config.ANTHROPIC_API_KEY
    original_openai = config.OPENAI_API_KEY
    original_google = config.GOOGLE_API_KEY
    original_provider = config.LLM_PROVIDER

    # Check for header-provided keys
    header_anthropic = request.headers.get("X-Anthropic-Key")
    header_openai = request.headers.get("X-OpenAI-Key")
    header_google = request.headers.get("X-Google-Key")
    header_provider = request.headers.get("X-Preferred-Provider")

    # Temporarily override config if headers are provided
    # Only override if header is non-empty and config is empty
    if header_anthropic and not config.ANTHROPIC_API_KEY:
        config.ANTHROPIC_API_KEY = header_anthropic
    if header_openai and not config.OPENAI_API_KEY:
        config.OPENAI_API_KEY = header_openai
    if header_google and not config.GOOGLE_API_KEY:
        config.GOOGLE_API_KEY = header_google
    if header_provider:
        config.LLM_PROVIDER = header_provider

    # Reinitialize provider if we got new keys and don't have one yet
    if not state.provider and (header_anthropic or header_openai or header_google):
        state.provider = get_provider_from_env(
            anthropic_key=config.ANTHROPIC_API_KEY or None,
            openai_key=config.OPENAI_API_KEY or None,
            google_key=config.GOOGLE_API_KEY or None,
            preferred_provider=config.LLM_PROVIDER or None,
            default_model=config.LLM_MODEL or None,
        )
        if state.provider:
            state.summarizer = Summarizer(provider=state.provider, cache=state.cache)
            state.clusterer = Clusterer(provider=state.provider, cache=state.cache)
            state.chat_service = ChatService(db=state.db, provider=state.provider)
            logger.info(f"LLM provider initialized from headers: {state.provider.name}")

    try:
        response = await call_next(request)
        return response
    finally:
        # Restore original values
        config.ANTHROPIC_API_KEY = original_anthropic
        config.OPENAI_API_KEY = original_openai
        config.GOOGLE_API_KEY = original_google
        config.LLM_PROVIDER = original_provider


# Include routers
# Public routes (no auth required)
app.include_router(misc_public_router)
app.include_router(oauth_router)  # OAuth routes are public (login/callback/status)
# Protected routes (require auth when AUTH_API_KEY or OAuth is configured)
app.include_router(misc_router)
app.include_router(articles_router)
app.include_router(feeds_router)
app.include_router(summarization_router)
app.include_router(standalone_router)
app.include_router(gmail_router)
app.include_router(notifications_router)
app.include_router(statistics_router)
app.include_router(chat_router)
