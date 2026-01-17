"""
Feed routes: management, refresh, OPML import/export.
"""

from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from ..auth import verify_api_key, get_current_user
from ..config import state, get_db
from ..database import Database
from ..exceptions import require_feed
from ..schemas import (
    FeedResponse,
    AddFeedRequest,
    UpdateFeedRequest,
    BulkDeleteFeedsRequest,
    OPMLImportRequest,
    OPMLImportResult,
    OPMLImportResponse,
)
from ..opml import parse_opml, generate_opml, OPMLFeed
from ..tasks import refresh_all_feeds, refresh_single_feed, fetch_feed_articles

router = APIRouter(
    prefix="/feeds",
    tags=["feeds"],
    dependencies=[Depends(verify_api_key)]
)


# ─────────────────────────────────────────────────────────────
# Feed Management
# ─────────────────────────────────────────────────────────────

@router.get("")
async def list_feeds(
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> list[FeedResponse]:
    """List all subscribed feeds with user-specific unread counts."""
    feeds = db.get_feeds(user_id)
    return [FeedResponse.from_db(f) for f in feeds]


@router.post("")
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
    background_tasks.add_task(fetch_feed_articles, feed_id, feed)

    db_feed = db.get_feed(feed_id)
    if not db_feed:
        raise HTTPException(status_code=500, detail="Failed to retrieve feed")

    return FeedResponse.from_db(db_feed)


@router.delete("/{feed_id}")
async def remove_feed(
    feed_id: int,
    db: Annotated[Database, Depends(get_db)]
) -> dict:
    """Unsubscribe from a feed."""
    require_feed(db.get_feed(feed_id))
    db.delete_feed(feed_id)
    return {"success": True}


@router.put("/{feed_id}")
async def update_feed(
    feed_id: int,
    request: UpdateFeedRequest,
    db: Annotated[Database, Depends(get_db)]
) -> FeedResponse:
    """Update a feed's name or category. Set category to empty string to remove it."""
    require_feed(db.get_feed(feed_id))

    # Empty string means clear category
    clear_category = request.category == ""
    category = None if clear_category else request.category

    db.update_feed(feed_id, name=request.name, category=category, clear_category=clear_category)

    updated_feed = db.get_feed(feed_id)
    if not updated_feed:
        raise HTTPException(status_code=500, detail="Failed to retrieve updated feed")

    return FeedResponse.from_db(updated_feed)


@router.post("/bulk/delete")
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


# ─────────────────────────────────────────────────────────────
# Refresh
# ─────────────────────────────────────────────────────────────

@router.post("/refresh")
async def refresh_feeds(
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> dict:
    """Trigger feed refresh (runs in background)."""
    if state.refresh_in_progress:
        return {"success": True, "message": "Refresh already in progress"}

    background_tasks.add_task(refresh_all_feeds)
    return {"success": True, "message": "Refresh started"}


@router.post("/{feed_id}/refresh")
async def refresh_feed(
    feed_id: int,
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks
) -> dict:
    """Refresh a specific feed."""
    feed = require_feed(db.get_feed(feed_id))
    background_tasks.add_task(refresh_single_feed, feed_id, feed.url)
    return {"success": True, "message": "Refresh started"}


# ─────────────────────────────────────────────────────────────
# OPML Import/Export
# ─────────────────────────────────────────────────────────────

async def import_single_feed(
    opml_feed: OPMLFeed,
    db: Database,
    existing_urls: set[str],
    background_tasks: BackgroundTasks
) -> OPMLImportResult:
    """Import a single feed from OPML, handling validation and errors."""
    # Skip if already subscribed
    if opml_feed.url.lower() in existing_urls:
        return OPMLImportResult(
            url=opml_feed.url,
            name=opml_feed.title,
            success=False,
            error="Already subscribed"
        )

    try:
        parsed_feed = await state.feed_parser.fetch(opml_feed.url)
        feed_name = opml_feed.title or parsed_feed.title

        feed_id = db.add_feed(
            url=opml_feed.url,
            name=feed_name,
            category=opml_feed.category
        )

        background_tasks.add_task(fetch_feed_articles, feed_id, parsed_feed)

        return OPMLImportResult(
            url=opml_feed.url,
            name=feed_name,
            success=True,
            feed_id=feed_id
        )

    except Exception as e:
        return OPMLImportResult(
            url=opml_feed.url,
            name=opml_feed.title,
            success=False,
            error=str(e)
        )


@router.post("/import-opml")
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

    # Get existing feed URLs to skip duplicates
    existing_feeds = db.get_feeds()
    existing_urls = {f.url.lower() for f in existing_feeds}

    # Import each feed
    results: list[OPMLImportResult] = []
    for opml_feed in opml_doc.feeds:
        result = await import_single_feed(opml_feed, db, existing_urls, background_tasks)
        results.append(result)
        if result.success:
            existing_urls.add(opml_feed.url.lower())

    # Count results
    imported = sum(1 for r in results if r.success)
    skipped = sum(1 for r in results if not r.success and r.error == "Already subscribed")
    failed = sum(1 for r in results if not r.success and r.error != "Already subscribed")

    return OPMLImportResponse(
        total=len(opml_doc.feeds),
        imported=imported,
        skipped=skipped,
        failed=failed,
        results=results
    )


@router.get("/export-opml")
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

    opml_content = generate_opml(opml_feeds, title="Data Points AI Feeds")

    return {
        "opml": opml_content,
        "feed_count": len(feeds)
    }
