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
)
from ..tasks import summarize_article

router = APIRouter(prefix="/articles", tags=["articles"])


# ─────────────────────────────────────────────────────────────
# List & Detail
# ─────────────────────────────────────────────────────────────

@router.get("")
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


@router.get("/grouped")
async def get_articles_grouped(
    db: Annotated[Database, Depends(get_db)],
    group_by: str = Query(default="date", regex="^(date|feed|topic)$"),
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


# ─────────────────────────────────────────────────────────────
# Read/Bookmark Operations
# ─────────────────────────────────────────────────────────────

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
# Content & Summarization
# ─────────────────────────────────────────────────────────────

@router.post("/{article_id}/fetch-content")
async def fetch_article_content(
    article_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> ArticleDetailResponse:
    """Fetch full content for an article from its URL."""
    if not state.fetcher:
        raise HTTPException(status_code=503, detail="Fetcher not configured")

    article = db.get_article(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")

    try:
        result = await state.fetcher.fetch(article.url)
        if result.content:
            db.update_article_content(article_id, result.content)
            article = db.get_article(article_id)
            if not article:
                raise HTTPException(status_code=500, detail="Failed to retrieve article")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch content: {e}")

    return ArticleDetailResponse.from_db(article)


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

    # Run summarization in background
    background_tasks.add_task(
        summarize_article,
        article_id,
        article.content or "",
        article.url,
        article.title
    )

    return {"success": True, "message": "Summarization started"}
