"""
Article routes: list, detail, read/bookmark operations.
"""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query

from ..config import state, get_db
from ..database import Database
from ..schemas import (
    ArticleResponse,
    ArticleDetailResponse,
    ArticleGroupResponse,
    GroupedArticlesResponse,
    BulkMarkReadRequest,
    ExtractSourceResponse,
)
from ..tasks import summarize_article
from ..source_extractor import SourceExtractor

router = APIRouter(prefix="/articles", tags=["articles"])


# ─────────────────────────────────────────────────────────────
# List & Grouped (static paths first)
# ─────────────────────────────────────────────────────────────

@router.get("")
async def list_articles(
    db: Annotated[Database, Depends(get_db)],
    feed_id: int | None = None,
    unread_only: bool = False,
    bookmarked_only: bool = False,
    summarized_only: bool | None = None,
    limit: int = Query(default=50, le=200),
    offset: int = 0
) -> list[ArticleResponse]:
    """Get articles, optionally filtered by feed or status.

    Args:
        summarized_only: If True, only return summarized articles.
                        If False, only return unsummarized articles.
                        If None, return all articles regardless of summary status.
    """
    articles = db.get_articles(
        feed_id=feed_id,
        unread_only=unread_only,
        bookmarked_only=bookmarked_only,
        summarized_only=summarized_only,
        limit=limit,
        offset=offset
    )
    return [ArticleResponse.from_db(a) for a in articles]


@router.get("/grouped")
async def get_articles_grouped(
    db: Annotated[Database, Depends(get_db)],
    group_by: str = Query(default="date", pattern="^(date|feed|topic)$"),
    unread_only: bool = False,
    limit: int = Query(default=100, le=500)
) -> GroupedArticlesResponse:
    """
    Get articles grouped by date, feed, or topic.

    Args:
        group_by: 'date' for daily groups, 'feed' for source groups, 'topic' for AI clustering
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
    elif group_by == "topic":
        # Use Claude-powered clustering
        if not state.clusterer:
            raise HTTPException(
                status_code=503,
                detail="Topic clustering unavailable: API key not configured"
            )

        # Get all articles first
        articles = db.get_articles(unread_only=unread_only, limit=limit)

        if not articles:
            return GroupedArticlesResponse(group_by=group_by, groups=[])

        # Cluster the articles
        result = await state.clusterer.cluster_async(articles)

        # Build article lookup for response
        article_map = {a.id: a for a in articles}

        groups = []
        for topic in result.topics:
            topic_articles = [
                article_map[aid]
                for aid in topic.article_ids
                if aid in article_map
            ]
            if topic_articles:
                groups.append(ArticleGroupResponse(
                    key=topic.id,
                    label=topic.label,
                    articles=[ArticleResponse.from_db(a) for a in topic_articles]
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


# ─────────────────────────────────────────────────────────────
# Bulk Operations (static paths - must come before {article_id})
# ─────────────────────────────────────────────────────────────

@router.post("/bulk/read")
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


@router.post("/feed/{feed_id}/read")
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


@router.post("/all/read")
async def mark_all_read(
    db: Annotated[Database, Depends(get_db)],
    is_read: bool = True
) -> dict:
    """Mark all articles as read/unread."""
    count = db.mark_all_read(is_read)
    return {"success": True, "count": count, "is_read": is_read}


# ─────────────────────────────────────────────────────────────
# Single Article Operations (parameterized paths last)
# ─────────────────────────────────────────────────────────────

@router.get("/{article_id}")
async def get_article(
    article_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> ArticleDetailResponse:
    """Get single article with full summary."""
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    return ArticleDetailResponse.from_db(article)


@router.post("/{article_id}/read")
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


@router.post("/{article_id}/bookmark")
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


@router.post("/{article_id}/fetch-content")
async def fetch_article_content(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    force_archive: bool = Query(default=False, description="Force archive lookup for paywalled content"),
    force_js: bool = Query(default=False, description="Force JavaScript rendering"),
    use_aggregator_url: bool = Query(default=False, description="Use aggregator URL instead of source URL"),
) -> ArticleDetailResponse:
    """
    Fetch full content for an article from its URL.

    For aggregator articles (Techmeme, Google News, etc.), this fetches from
    the original source URL by default, not the aggregator page.

    Uses intelligent fallback:
    1. Try simple HTTP fetch
    2. If content is paywalled and archive enabled, try archive services
    3. If content is dynamic and JS render enabled, use Playwright

    Query params:
        force_archive: Skip simple fetch and go straight to archives
        force_js: Skip simple fetch and use JavaScript rendering
        use_aggregator_url: Fetch from aggregator URL instead of source (default: False)
    """
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    # Prefer source_url for aggregator articles (fetch the actual source content)
    fetch_url = article.url
    if article.source_url and not use_aggregator_url:
        fetch_url = article.source_url

    try:
        # Use enhanced fetcher if available, otherwise fall back to simple fetcher
        if state.enhanced_fetcher:
            result = await state.enhanced_fetcher.fetch(
                fetch_url,
                force_archive=force_archive,
                force_js=force_js
            )
            source = result.source
            if hasattr(result, 'fallback_used') and result.fallback_used:
                source = result.fallback_used
        elif state.fetcher:
            result = await state.fetcher.fetch(fetch_url)
            source = result.source
        else:
            raise HTTPException(status_code=503, detail="Fetcher not configured")

        if result.content:
            db.update_article_content(article_id, result.content)
            article = db.get_article(article_id)
            if not article:
                raise HTTPException(status_code=500, detail="Failed to retrieve article")

            return ArticleDetailResponse.from_db(article)
        else:
            # No content fetched
            error_msg = "No content extracted"
            if hasattr(result, 'original_error') and result.original_error:
                error_msg = result.original_error
            raise HTTPException(status_code=400, detail=f"Failed to fetch content: {error_msg}")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch content: {e}")


@router.post("/{article_id}/summarize")
async def summarize_article_endpoint(
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

    # Use source_url for aggregator articles (more accurate context for summarization)
    url_for_summary = article.source_url or article.url

    # Run summarization in background
    background_tasks.add_task(
        summarize_article,
        article_id,
        article.content or "",
        url_for_summary,
        article.title
    )

    return {"success": True, "message": "Summarization started"}


@router.post("/{article_id}/extract-source")
async def extract_source_url(
    article_id: int,
    db: Annotated[Database, Depends(get_db)],
    force: bool = Query(default=False, description="Re-extract even if source_url exists")
) -> ExtractSourceResponse:
    """
    Extract original source URL for an aggregator article.

    This is useful for articles from aggregators like Google News or Reddit
    where the RSS link points to the aggregator rather than the source article.

    For Hacker News and Techmeme, source URLs are extracted during feed refresh.
    This endpoint handles cases that require HTTP requests (Google News, Reddit)
    or re-extraction if the initial extraction failed.
    """
    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    # Return existing source_url if available and not forcing re-extraction
    if article.source_url and not force:
        extractor = SourceExtractor()
        aggregator = extractor.identify_aggregator(article.url)
        return ExtractSourceResponse(
            success=True,
            source_url=article.source_url,
            aggregator=aggregator,
            confidence=1.0
        )

    # Try to extract source URL
    extractor = SourceExtractor()

    # Check if this is even an aggregator URL
    if not extractor.is_aggregator(article.url):
        return ExtractSourceResponse(
            success=False,
            error="Not an aggregator URL"
        )

    result = await extractor.extract(article.url, article.content or "")

    # Update database if extraction succeeded
    if result.source_url:
        db.update_article_source_url(article_id, result.source_url)

    return ExtractSourceResponse(
        success=result.source_url is not None,
        source_url=result.source_url,
        aggregator=result.aggregator,
        confidence=result.confidence,
        error=result.error
    )
