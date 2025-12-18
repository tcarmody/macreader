"""
RSS Reader API Server

FastAPI application providing endpoints for:
- Article management (list, read, bookmark)
- Feed management (add, remove, refresh)
- Summarization
- Search
- Settings
"""

import os
import asyncio
from pathlib import Path
from datetime import datetime
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import FastAPI, BackgroundTasks, HTTPException, Query, Depends
from pydantic import BaseModel, HttpUrl
from dotenv import load_dotenv

from .database import Database, DBArticle, DBFeed
from .cache import TieredCache, create_cache
from .feeds import FeedParser
from .fetcher import Fetcher
from .summarizer import Summarizer, Summary, Model
from .opml import parse_opml, generate_opml, OPMLFeed

# Load environment variables
load_dotenv()


# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

class Config:
    """Application configuration from environment."""
    API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/articles.db"))
    CACHE_DIR: Path = Path(os.getenv("CACHE_DIR", "./data/cache"))
    PORT: int = int(os.getenv("PORT", "5005"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")


config = Config()


# ─────────────────────────────────────────────────────────────
# Application State
# ─────────────────────────────────────────────────────────────

class AppState:
    """Shared application state."""
    db: Database | None = None
    cache: TieredCache | None = None
    summarizer: Summarizer | None = None
    feed_parser: FeedParser | None = None
    fetcher: Fetcher | None = None
    refresh_in_progress: bool = False


state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application resources."""
    # Startup
    state.db = Database(config.DB_PATH)
    state.cache = create_cache(config.CACHE_DIR)
    state.feed_parser = FeedParser()
    state.fetcher = Fetcher()

    if config.API_KEY:
        state.summarizer = Summarizer(api_key=config.API_KEY, cache=state.cache)
    else:
        print("Warning: ANTHROPIC_API_KEY not set. Summarization disabled.")

    yield

    # Shutdown
    # Nothing to cleanup for now


# ─────────────────────────────────────────────────────────────
# FastAPI App
# ─────────────────────────────────────────────────────────────

app = FastAPI(
    title="RSS Reader API",
    version="2.0.0",
    lifespan=lifespan
)


# ─────────────────────────────────────────────────────────────
# Pydantic Models
# ─────────────────────────────────────────────────────────────

class ArticleResponse(BaseModel):
    """Article for list view."""
    id: int
    feed_id: int
    url: str
    title: str
    summary_short: str | None
    is_read: bool
    is_bookmarked: bool
    published_at: str | None
    created_at: str

    @classmethod
    def from_db(cls, article: DBArticle) -> "ArticleResponse":
        return cls(
            id=article.id,
            feed_id=article.feed_id,
            url=article.url,
            title=article.title,
            summary_short=article.summary_short,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            published_at=article.published_at.isoformat() if article.published_at else None,
            created_at=article.created_at.isoformat()
        )


class ArticleDetailResponse(BaseModel):
    """Article with full summary for detail view."""
    id: int
    feed_id: int
    url: str
    title: str
    content: str | None
    summary_short: str | None
    summary_full: str | None
    key_points: list[str] | None
    is_read: bool
    is_bookmarked: bool
    published_at: str | None
    created_at: str

    @classmethod
    def from_db(cls, article: DBArticle) -> "ArticleDetailResponse":
        return cls(
            id=article.id,
            feed_id=article.feed_id,
            url=article.url,
            title=article.title,
            content=article.content,
            summary_short=article.summary_short,
            summary_full=article.summary_full,
            key_points=article.key_points,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            published_at=article.published_at.isoformat() if article.published_at else None,
            created_at=article.created_at.isoformat()
        )


class FeedResponse(BaseModel):
    """Feed for list view."""
    id: int
    url: str
    name: str
    category: str | None
    unread_count: int
    last_fetched: str | None

    @classmethod
    def from_db(cls, feed: DBFeed) -> "FeedResponse":
        return cls(
            id=feed.id,
            url=feed.url,
            name=feed.name,
            category=feed.category,
            unread_count=feed.unread_count,
            last_fetched=feed.last_fetched.isoformat() if feed.last_fetched else None
        )


class AddFeedRequest(BaseModel):
    """Request to add a new feed."""
    url: str
    name: str | None = None


class SummarizeRequest(BaseModel):
    """Request to summarize a URL."""
    url: str


class BatchSummarizeRequest(BaseModel):
    """Request to summarize multiple URLs."""
    urls: list[str]


class BatchSummarizeResult(BaseModel):
    """Result of a single URL summarization in a batch."""
    url: str
    success: bool
    title: str | None = None
    one_liner: str | None = None
    full_summary: str | None = None
    key_points: list[str] | None = None
    model_used: str | None = None
    cached: bool = False
    error: str | None = None


class BatchSummarizeResponse(BaseModel):
    """Response from batch summarization."""
    total: int
    successful: int
    failed: int
    results: list[BatchSummarizeResult]


class ArticleGroupResponse(BaseModel):
    """A group of articles."""
    key: str
    label: str
    articles: list[ArticleResponse]


class GroupedArticlesResponse(BaseModel):
    """Response for grouped articles."""
    group_by: str
    groups: list[ArticleGroupResponse]


class SettingsResponse(BaseModel):
    """Application settings."""
    refresh_interval_minutes: int = 30
    auto_summarize: bool = True
    mark_read_on_open: bool = True
    default_model: str = "haiku"


class SettingsUpdateRequest(BaseModel):
    """Request to update settings."""
    refresh_interval_minutes: int | None = None
    auto_summarize: bool | None = None
    mark_read_on_open: bool | None = None
    default_model: str | None = None


# ─────────────────────────────────────────────────────────────
# Dependencies
# ─────────────────────────────────────────────────────────────

def get_db() -> Database:
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db


# ─────────────────────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────────────────────

@app.get("/status")
async def health_check() -> dict:
    """API health check."""
    return {
        "status": "ok",
        "version": "2.0.0",
        "summarization_enabled": state.summarizer is not None
    }


# ─────────────────────────────────────────────────────────────
# Articles
# ─────────────────────────────────────────────────────────────

@app.get("/articles")
async def list_articles(
    db: Annotated[Database, Depends(get_db)],
    feed_id: int | None = None,
    unread_only: bool = False,
    bookmarked_only: bool = False,
    limit: int = Query(default=50, le=200),
    offset: int = 0
) -> list[ArticleResponse]:
    """Get articles, optionally filtered by feed or status."""
    articles = db.get_articles(
        feed_id=feed_id,
        unread_only=unread_only,
        bookmarked_only=bookmarked_only,
        limit=limit,
        offset=offset
    )
    return [ArticleResponse.from_db(a) for a in articles]


@app.get("/articles/grouped")
async def get_articles_grouped(
    db: Annotated[Database, Depends(get_db)],
    group_by: str = Query(default="date", regex="^(date|feed)$"),
    unread_only: bool = False,
    limit: int = Query(default=100, le=500)
) -> GroupedArticlesResponse:
    """
    Get articles grouped by date or feed.

    Args:
        group_by: 'date' for daily groups, 'feed' for source groups
        unread_only: Only include unread articles
        limit: Maximum total articles to return
    """
    feeds_map = {f.id: f for f in db.get_feeds()}

    if group_by == "date":
        grouped = db.get_articles_grouped_by_date(unread_only=unread_only, limit=limit)
        groups = []
        for date_str in sorted(grouped.keys(), reverse=True):
            articles = grouped[date_str]
            # Format date label
            date_obj = datetime.strptime(date_str, "%Y-%m-%d")
            today = datetime.now().date()
            if date_obj.date() == today:
                label = "Today"
            elif (today - date_obj.date()).days == 1:
                label = "Yesterday"
            else:
                label = date_obj.strftime("%B %d, %Y")

            groups.append(ArticleGroupResponse(
                key=date_str,
                label=label,
                articles=[ArticleResponse.from_db(a) for a in articles]
            ))
    else:  # group_by == "feed"
        grouped = db.get_articles_grouped_by_feed(unread_only=unread_only, limit=limit)
        groups = []
        for feed_id in sorted(grouped.keys()):
            articles = grouped[feed_id]
            feed = feeds_map.get(feed_id)
            label = feed.name if feed else f"Feed {feed_id}"

            groups.append(ArticleGroupResponse(
                key=str(feed_id),
                label=label,
                articles=[ArticleResponse.from_db(a) for a in articles]
            ))

    return GroupedArticlesResponse(group_by=group_by, groups=groups)


@app.get("/articles/{article_id}")
async def get_article(
    article_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> ArticleDetailResponse:
    """Get single article with full summary."""
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    return ArticleDetailResponse.from_db(article)


@app.post("/articles/{article_id}/read")
async def mark_read(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    is_read: bool = True
) -> dict:
    """Mark article as read/unread."""
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    db.mark_read(article_id, is_read)
    return {"success": True, "is_read": is_read}


@app.post("/articles/{article_id}/bookmark")
async def toggle_bookmark(
    article_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Toggle bookmark status."""
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    new_status = db.toggle_bookmark(article_id)
    return {"success": True, "is_bookmarked": new_status}


class BulkMarkReadRequest(BaseModel):
    """Request to mark multiple articles as read/unread."""
    article_ids: list[int]
    is_read: bool = True


class BulkDeleteFeedsRequest(BaseModel):
    """Request to delete multiple feeds."""
    feed_ids: list[int]


class UpdateFeedRequest(BaseModel):
    """Request to update a feed."""
    name: str | None = None
    category: str | None = None


@app.post("/articles/bulk/read")
async def bulk_mark_read(
    request: BulkMarkReadRequest,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Mark multiple articles as read/unread."""
    if not request.article_ids:
        raise HTTPException(status_code=400, detail="No article IDs provided")

    if len(request.article_ids) > 1000:
        raise HTTPException(status_code=400, detail="Maximum 1000 articles per request")

    db.bulk_mark_read(request.article_ids, request.is_read)
    return {"success": True, "count": len(request.article_ids), "is_read": request.is_read}


@app.post("/articles/feed/{feed_id}/read")
async def mark_feed_read(
    feed_id: int,
    db: Annotated[Database, Depends(get_db)],
    is_read: bool = True
) -> dict:
    """Mark all articles in a feed as read/unread."""
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")

    count = db.mark_feed_read(feed_id, is_read)
    return {"success": True, "count": count, "is_read": is_read}


@app.post("/articles/all/read")
async def mark_all_read(
    db: Annotated[Database, Depends(get_db)],
    is_read: bool = True
) -> dict:
    """Mark all articles as read/unread."""
    count = db.mark_all_read(is_read)
    return {"success": True, "count": count, "is_read": is_read}


@app.post("/feeds/bulk/delete")
async def bulk_delete_feeds(
    request: BulkDeleteFeedsRequest,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Delete multiple feeds at once."""
    if not request.feed_ids:
        raise HTTPException(status_code=400, detail="No feed IDs provided")

    if len(request.feed_ids) > 100:
        raise HTTPException(status_code=400, detail="Maximum 100 feeds per request")

    db.bulk_delete_feeds(request.feed_ids)
    return {"success": True, "count": len(request.feed_ids)}


@app.put("/feeds/{feed_id}")
async def update_feed(
    feed_id: int,
    request: UpdateFeedRequest,
    db: Annotated[Database, Depends(get_db)]
) -> FeedResponse:
    """Update a feed's name or category."""
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")

    db.update_feed(feed_id, name=request.name, category=request.category)

    updated_feed = db.get_feed(feed_id)
    if not updated_feed:
        raise HTTPException(status_code=500, detail="Failed to retrieve updated feed")

    return FeedResponse.from_db(updated_feed)


@app.post("/articles/{article_id}/summarize")
async def summarize_article(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> dict:
    """Generate or regenerate summary for an article."""
    if not state.summarizer:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    # Run summarization in background
    background_tasks.add_task(
        _summarize_article,
        article_id,
        article.content or "",
        article.url,
        article.title
    )

    return {"success": True, "message": "Summarization started"}


def _summarize_article(article_id: int, content: str, url: str, title: str):
    """Background task to summarize an article (sync version for BackgroundTasks)."""
    if not state.summarizer or not state.db:
        print(f"Summarizer not configured for article {article_id}")
        return

    if not content or len(content.strip()) < 50:
        print(f"Article {article_id} has insufficient content for summarization")
        return

    try:
        print(f"Starting summarization for article {article_id}")
        summary = state.summarizer.summarize(content, url, title)
        state.db.update_summary(
            article_id=article_id,
            summary_short=summary.one_liner,
            summary_full=summary.full_summary,
            key_points=summary.key_points,
            model_used=summary.model_used.value
        )
        print(f"Successfully summarized article {article_id}")
    except Exception as e:
        print(f"Error summarizing article {article_id}: {e}")
        import traceback
        traceback.print_exc()


# ─────────────────────────────────────────────────────────────
# Summarization
# ─────────────────────────────────────────────────────────────

@app.post("/summarize")
async def summarize_url(request: SummarizeRequest) -> dict:
    """Summarize a single URL (any webpage, not just feeds)."""
    if not state.summarizer or not state.fetcher:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    try:
        # Fetch content
        result = await state.fetcher.fetch(request.url)

        # Generate summary
        summary = await state.summarizer.summarize_async(
            result.content,
            result.url,
            result.title
        )

        return {
            "url": result.url,
            "title": result.title,
            "one_liner": summary.one_liner,
            "full_summary": summary.full_summary,
            "key_points": summary.key_points,
            "model_used": summary.model_used.value,
            "cached": summary.cached
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/summarize/batch")
async def batch_summarize_urls(request: BatchSummarizeRequest) -> BatchSummarizeResponse:
    """
    Summarize multiple URLs at once.

    Processes URLs concurrently and returns results for each.
    Useful for summarizing multiple articles or webpages in one request.
    """
    if not state.summarizer or not state.fetcher:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    if not request.urls:
        raise HTTPException(status_code=400, detail="No URLs provided")

    if len(request.urls) > 20:
        raise HTTPException(status_code=400, detail="Maximum 20 URLs per batch")

    async def summarize_single(url: str) -> BatchSummarizeResult:
        """Summarize a single URL, catching errors."""
        try:
            result = await state.fetcher.fetch(url)
            summary = await state.summarizer.summarize_async(
                result.content,
                result.url,
                result.title
            )
            return BatchSummarizeResult(
                url=url,
                success=True,
                title=result.title,
                one_liner=summary.one_liner,
                full_summary=summary.full_summary,
                key_points=summary.key_points,
                model_used=summary.model_used.value,
                cached=summary.cached
            )
        except Exception as e:
            return BatchSummarizeResult(
                url=url,
                success=False,
                error=str(e)
            )

    # Process all URLs concurrently
    tasks = [summarize_single(url) for url in request.urls]
    results = await asyncio.gather(*tasks)

    successful = sum(1 for r in results if r.success)
    failed = len(results) - successful

    return BatchSummarizeResponse(
        total=len(results),
        successful=successful,
        failed=failed,
        results=results
    )


# ─────────────────────────────────────────────────────────────
# Feeds
# ─────────────────────────────────────────────────────────────

@app.get("/feeds")
async def list_feeds(
    db: Annotated[Database, Depends(get_db)]
) -> list[FeedResponse]:
    """List all subscribed feeds."""
    feeds = db.get_feeds()
    return [FeedResponse.from_db(f) for f in feeds]


@app.post("/feeds")
async def add_feed(
    request: AddFeedRequest,
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> FeedResponse:
    """Subscribe to a new feed."""
    if not state.feed_parser:
        raise HTTPException(status_code=500, detail="Feed parser not initialized")

    # Validate feed URL by fetching it
    try:
        feed = await state.feed_parser.fetch(request.url)
        feed_name = request.name or feed.title
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid feed URL: {e}")

    # Add to database
    try:
        feed_id = db.add_feed(request.url, feed_name)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Feed already exists or error: {e}")

    # Fetch articles in background
    background_tasks.add_task(_fetch_feed_articles, feed_id, feed)

    db_feed = db.get_feed(feed_id)
    if not db_feed:
        raise HTTPException(status_code=500, detail="Failed to retrieve feed")

    return FeedResponse.from_db(db_feed)


@app.delete("/feeds/{feed_id}")
async def remove_feed(
    feed_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Unsubscribe from a feed."""
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")
    db.delete_feed(feed_id)
    return {"success": True}


@app.post("/feeds/refresh")
async def refresh_feeds(
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> dict:
    """Trigger feed refresh (runs in background)."""
    if state.refresh_in_progress:
        return {"success": True, "message": "Refresh already in progress"}

    background_tasks.add_task(_refresh_all_feeds)
    return {"success": True, "message": "Refresh started"}


@app.post("/feeds/{feed_id}/refresh")
async def refresh_feed(
    feed_id: int,
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> dict:
    """Refresh a specific feed."""
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")

    background_tasks.add_task(_refresh_single_feed, feed_id, feed.url)
    return {"success": True, "message": "Refresh started"}


async def _refresh_all_feeds():
    """Background task to refresh all feeds."""
    if not state.db or not state.feed_parser:
        return

    state.refresh_in_progress = True
    try:
        feeds = state.db.get_feeds()
        for feed in feeds:
            await _refresh_single_feed(feed.id, feed.url)
    finally:
        state.refresh_in_progress = False


async def _refresh_single_feed(feed_id: int, feed_url: str):
    """Refresh a single feed."""
    if not state.db or not state.feed_parser:
        return

    try:
        feed = await state.feed_parser.fetch(feed_url)
        await _fetch_feed_articles(feed_id, feed)
        state.db.update_feed_fetched(feed_id)
    except Exception as e:
        state.db.update_feed_fetched(feed_id, error=str(e))
        print(f"Error refreshing feed {feed_id}: {e}")


async def _fetch_feed_articles(feed_id: int, feed):
    """Add articles from a parsed feed to the database."""
    if not state.db or not state.fetcher:
        return

    for item in feed.items:
        if not item.url:
            continue

        # Check if article already exists
        existing = state.db.get_article_by_url(item.url)
        if existing:
            continue

        # Fetch full content if feed only has summary
        content = item.content
        if len(content) < 500 and state.fetcher:
            try:
                result = await state.fetcher.fetch(item.url)
                content = result.content
            except Exception:
                pass  # Use feed content as fallback

        # Add article
        article_id = state.db.add_article(
            feed_id=feed_id,
            url=item.url,
            title=item.title,
            content=content,
            author=item.author,
            published_at=item.published
        )

        # Auto-summarize if enabled and API key configured
        if article_id and state.summarizer and content:
            try:
                summary = await state.summarizer.summarize_async(
                    content, item.url, item.title
                )
                state.db.update_summary(
                    article_id=article_id,
                    summary_short=summary.one_liner,
                    summary_full=summary.full_summary,
                    key_points=summary.key_points,
                    model_used=summary.model_used.value
                )
            except Exception as e:
                print(f"Error summarizing article {item.url}: {e}")


# ─────────────────────────────────────────────────────────────
# Search
# ─────────────────────────────────────────────────────────────

@app.get("/search")
async def search(
    q: str,
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(default=20, le=100)
) -> list[ArticleResponse]:
    """Full-text search across articles and summaries."""
    if len(q) < 2:
        raise HTTPException(status_code=400, detail="Query too short")

    articles = db.search(q, limit=limit)
    return [ArticleResponse.from_db(a) for a in articles]


# ─────────────────────────────────────────────────────────────
# Settings
# ─────────────────────────────────────────────────────────────

@app.get("/settings")
async def get_settings(
    db: Annotated[Database, Depends(get_db)]
) -> SettingsResponse:
    """Get application settings."""
    settings = db.get_all_settings()
    return SettingsResponse(
        refresh_interval_minutes=int(settings.get("refresh_interval_minutes", "30")),
        auto_summarize=settings.get("auto_summarize", "true").lower() == "true",
        mark_read_on_open=settings.get("mark_read_on_open", "true").lower() == "true",
        default_model=settings.get("default_model", "haiku")
    )


@app.put("/settings")
async def update_settings(
    request: SettingsUpdateRequest,
    db: Annotated[Database, Depends(get_db)]
) -> SettingsResponse:
    """Update application settings."""
    if request.refresh_interval_minutes is not None:
        db.set_setting("refresh_interval_minutes", str(request.refresh_interval_minutes))
    if request.auto_summarize is not None:
        db.set_setting("auto_summarize", str(request.auto_summarize).lower())
    if request.mark_read_on_open is not None:
        db.set_setting("mark_read_on_open", str(request.mark_read_on_open).lower())
    if request.default_model is not None:
        db.set_setting("default_model", request.default_model)

    return await get_settings(db)


# ─────────────────────────────────────────────────────────────
# Stats
# ─────────────────────────────────────────────────────────────

@app.get("/stats")
async def get_stats(
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Get overall statistics."""
    feeds = db.get_feeds()
    total_unread = sum(f.unread_count for f in feeds)

    return {
        "total_feeds": len(feeds),
        "total_unread": total_unread,
        "refresh_in_progress": state.refresh_in_progress
    }


# ─────────────────────────────────────────────────────────────
# OPML Import/Export
# ─────────────────────────────────────────────────────────────

class OPMLImportRequest(BaseModel):
    """Request to import feeds from OPML."""
    opml_content: str


class OPMLImportResult(BaseModel):
    """Result of importing a single feed from OPML."""
    url: str
    name: str | None
    success: bool
    error: str | None = None
    feed_id: int | None = None


class OPMLImportResponse(BaseModel):
    """Response from OPML import."""
    total: int
    imported: int
    skipped: int
    failed: int
    results: list[OPMLImportResult]


@app.post("/feeds/import-opml")
async def import_opml(
    request: OPMLImportRequest,
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> OPMLImportResponse:
    """
    Import feeds from OPML content.

    Parses the OPML, validates each feed, and adds them to the database.
    Returns detailed results for each feed.
    """
    if not state.feed_parser:
        raise HTTPException(status_code=500, detail="Feed parser not initialized")

    # Parse OPML
    try:
        opml_doc = parse_opml(request.opml_content)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid OPML: {e}")

    if not opml_doc.feeds:
        raise HTTPException(status_code=400, detail="No feeds found in OPML")

    results: list[OPMLImportResult] = []
    imported = 0
    skipped = 0
    failed = 0

    # Get existing feed URLs to skip duplicates
    existing_feeds = db.get_feeds()
    existing_urls = {f.url.lower() for f in existing_feeds}

    for opml_feed in opml_doc.feeds:
        # Skip if already subscribed
        if opml_feed.url.lower() in existing_urls:
            results.append(OPMLImportResult(
                url=opml_feed.url,
                name=opml_feed.title,
                success=False,
                error="Already subscribed"
            ))
            skipped += 1
            continue

        # Try to validate and add the feed
        try:
            parsed_feed = await state.feed_parser.fetch(opml_feed.url)
            feed_name = opml_feed.title or parsed_feed.title

            feed_id = db.add_feed(
                url=opml_feed.url,
                name=feed_name,
                category=opml_feed.category
            )

            # Fetch articles in background
            background_tasks.add_task(_fetch_feed_articles, feed_id, parsed_feed)

            results.append(OPMLImportResult(
                url=opml_feed.url,
                name=feed_name,
                success=True,
                feed_id=feed_id
            ))
            imported += 1
            existing_urls.add(opml_feed.url.lower())

        except Exception as e:
            results.append(OPMLImportResult(
                url=opml_feed.url,
                name=opml_feed.title,
                success=False,
                error=str(e)
            ))
            failed += 1

    return OPMLImportResponse(
        total=len(opml_doc.feeds),
        imported=imported,
        skipped=skipped,
        failed=failed,
        results=results
    )


@app.get("/feeds/export-opml")
async def export_opml(
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """
    Export all feeds as OPML.

    Returns OPML XML content that can be imported into other feed readers.
    """
    feeds = db.get_feeds()

    opml_feeds = [
        OPMLFeed(
            url=f.url,
            title=f.name,
            category=f.category
        )
        for f in feeds
    ]

    opml_content = generate_opml(opml_feeds, title="DataPointsAI Feeds")

    return {
        "opml": opml_content,
        "feed_count": len(feeds)
    }
