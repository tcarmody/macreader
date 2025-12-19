"""
Feed routes: management, refresh, OPML import/export.
"""

from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from ..config import state, get_db
from ..database import Database
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

router = APIRouter(prefix="/feeds", tags=["feeds"])


# ─────────────────────────────────────────────────────────────
# Feed Management
# ─────────────────────────────────────────────────────────────

@router.get("")
async def list_feeds(
    db: Annotated[Database, Depends(get_db)]
) -> list[FeedResponse]:
    """List all subscribed feeds."""
    feeds = db.get_feeds()
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
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")
    db.delete_feed(feed_id)
    return {"success": True}


@router.put("/{feed_id}")
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
    feed = db.get_feed(feed_id)
    if not feed:
        raise HTTPException(status_code=404, detail="Feed not found")

    background_tasks.add_task(refresh_single_feed, feed_id, feed.url)
    return {"success": True, "message": "Refresh started"}


# ─────────────────────────────────────────────────────────────
# OPML Import/Export
# ─────────────────────────────────────────────────────────────

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
            background_tasks.add_task(fetch_feed_articles, feed_id, parsed_feed)

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

    opml_content = generate_opml(opml_feeds, title="DataPointsAI Feeds")

    return {
        "opml": opml_content,
        "feed_count": len(feeds)
    }
