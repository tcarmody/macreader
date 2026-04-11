"""
Miscellaneous routes: health check, search, settings, stats.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key, get_current_user, require_admin
from ..config import state, get_db, config
from ..database import Database
from ..schemas import (
    ArticleResponse, SettingsResponse, SettingsUpdateRequest,
    SavedSearchResponse, SavedSearchCreate,
)

# Protected routes require authentication
router = APIRouter(tags=["misc"], dependencies=[Depends(verify_api_key)])

# Public router for endpoints that don't require auth
public_router = APIRouter(tags=["misc"])


# ─────────────────────────────────────────────────────────────
# Health Check (public - no auth required)
# ─────────────────────────────────────────────────────────────

@public_router.get("/status")
async def health_check() -> dict:
    """API health check."""
    return {
        "status": "ok",
        "version": "2.0.0",
        "summarization_enabled": state.summarizer is not None,
        "provider": state.provider.name if state.provider else None,
        "auth_enabled": bool(config.AUTH_API_KEY),
    }


# ─────────────────────────────────────────────────────────────
# Search
# ─────────────────────────────────────────────────────────────

@router.get("/search")
async def search(
    q: str,
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(default=20, le=100),
    include_summaries: bool = Query(default=True)
) -> list[ArticleResponse]:
    """Full-text search across articles and summaries."""
    if len(q) < 2:
        raise HTTPException(status_code=400, detail="Query too short")

    articles = db.search(q, limit=limit, include_summaries=include_summaries)
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
        default_model=settings.get("default_model", "haiku"),
        llm_provider=settings.get("llm_provider", "anthropic")
    )


@router.put("/settings")
async def update_settings(
    request: SettingsUpdateRequest,
    db: Annotated[Database, Depends(get_db)],
    _admin: Annotated[int, Depends(require_admin)] = 0
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
    if request.llm_provider is not None:
        db.set_setting("llm_provider", request.llm_provider)

    return await get_settings(db)


# ─────────────────────────────────────────────────────────────
# Stats
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# Saved Searches
# ─────────────────────────────────────────────────────────────

@router.get("/searches/saved")
async def list_saved_searches(
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> list[SavedSearchResponse]:
    """List all saved searches for the current user."""
    return [SavedSearchResponse.from_db(s) for s in db.saved_searches.get_all(user_id)]


@router.post("/searches/saved", status_code=201)
async def create_saved_search(
    body: SavedSearchCreate,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> SavedSearchResponse:
    """Save a search query for quick re-use."""
    if len(body.query.strip()) < 2:
        raise HTTPException(status_code=400, detail="Query too short")
    saved = db.saved_searches.create(user_id, body.name.strip(), body.query.strip(), body.include_summaries)
    return SavedSearchResponse.from_db(saved)


@router.delete("/searches/saved/{search_id}", status_code=204)
async def delete_saved_search(
    search_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> None:
    """Delete a saved search."""
    if not db.saved_searches.delete(search_id, user_id):
        raise HTTPException(status_code=404, detail="Saved search not found")


@router.post("/searches/saved/{search_id}/use", status_code=204)
async def touch_saved_search(
    search_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
) -> None:
    """Update last_used_at so the list stays sorted by recency."""
    db.saved_searches.touch(search_id, user_id)


# ─────────────────────────────────────────────────────────────
# Stats
# ─────────────────────────────────────────────────────────────

@router.get("/stats")
async def get_stats(
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> dict:
    """Get overall statistics."""
    feeds = db.get_feeds(user_id)
    total_unread = sum(f.unread_count for f in feeds)

    return {
        "total_feeds": len(feeds),
        "total_unread": total_unread,
        "refresh_in_progress": state.refresh_in_progress
    }
