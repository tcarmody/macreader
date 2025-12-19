"""
Miscellaneous routes: health check, search, settings, stats.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from ..config import state, get_db
from ..database import Database
from ..schemas import ArticleResponse, SettingsResponse, SettingsUpdateRequest

router = APIRouter(tags=["misc"])


# ─────────────────────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────────────────────

@router.get("/status")
async def health_check() -> dict:
    """API health check."""
    return {
        "status": "ok",
        "version": "2.0.0",
        "summarization_enabled": state.summarizer is not None
    }


# ─────────────────────────────────────────────────────────────
# Search
# ─────────────────────────────────────────────────────────────

@router.get("/search")
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

@router.get("/settings")
async def get_settings(
    db: Annotated[Database, Depends(get_db)]
) -> SettingsResponse:
    """Get application settings."""
    settings = db.get_all_settings()
    return SettingsResponse(
        refresh_interval_minutes=int(settings.get("refresh_interval_minutes", "30")),
        auto_summarize=settings.get("auto_summarize", "false").lower() == "true",
        mark_read_on_open=settings.get("mark_read_on_open", "true").lower() == "true",
        default_model=settings.get("default_model", "haiku")
    )


@router.put("/settings")
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

@router.get("/stats")
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
