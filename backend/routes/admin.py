"""
Admin routes: operational endpoints gated to admins.
"""

from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends

from ..auth import verify_api_key, require_admin
from ..config import get_db
from ..database import Database

router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    dependencies=[Depends(verify_api_key)],
)


@router.get("/search/status")
async def search_status(
    db: Annotated[Database, Depends(get_db)],
    _admin: Annotated[int, Depends(require_admin)] = 0,
) -> dict:
    """Report search-index health: Tantivy doc count vs total articles."""
    idx = db.search_index_doc_count()
    articles = db.count_articles()
    return {
        "tantivy_enabled": idx is not None,
        "index_documents": idx,
        "article_count": articles,
        # Healthy when Tantivy is present and not behind the DB.
        "healthy": idx is not None and idx >= articles,
    }


@router.post("/search/rebuild")
async def search_rebuild(
    db: Annotated[Database, Depends(get_db)],
    background_tasks: BackgroundTasks,
    _admin: Annotated[int, Depends(require_admin)] = 0,
) -> dict:
    """Trigger a full Tantivy reindex of all articles. Runs in a background
    thread (Starlette runs sync background tasks off the event loop), so it
    doesn't block the worker. Poll GET /admin/search/status for progress."""
    if db.search_index_doc_count() is None:
        return {
            "started": False,
            "message": "Tantivy unavailable; using FTS5 fallback. Nothing to rebuild.",
        }
    # Sync callable → Starlette runs it in a threadpool, off the event loop.
    background_tasks.add_task(db.rebuild_search_index)
    return {
        "started": True,
        "article_count": db.count_articles(),
        "message": "Reindex started. Poll /admin/search/status for progress.",
    }
