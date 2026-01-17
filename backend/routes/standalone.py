"""
Standalone (Library) routes: add URLs, upload files, list/manage items.

Includes newsletter email import support.
"""

import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile

from ..auth import verify_api_key, get_current_user
from ..config import state, get_db, config
from ..database import Database
from ..exceptions import require_item
from ..validators import require_sufficient_content
from ..email_parser import (
    parse_eml_bytes,
    extract_article_content,
    EmailParseError,
)
from ..extractors import extract_text, detect_content_type, ExtractionError
from ..schemas import (
    AddStandaloneURLRequest,
    StandaloneItemResponse,
    StandaloneItemDetailResponse,
    StandaloneListResponse,
    LibraryStatsResponse,
    NewsletterImportResult,
    NewsletterImportResponse,
)
from ..tasks import summarize_article

router = APIRouter(
    prefix="/standalone",
    tags=["library"],
    dependencies=[Depends(verify_api_key)]
)

# Directory for uploaded files
UPLOADS_DIR = config.DB_PATH.parent / "uploads"


def ensure_uploads_dir() -> Path:
    """Ensure uploads directory exists."""
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    return UPLOADS_DIR


def schedule_auto_summarize(
    background_tasks: BackgroundTasks,
    auto_summarize: bool,
    item_id: int,
    content: str | None,
    url: str,
    title: str
) -> None:
    """
    Schedule auto-summarization if enabled and content is available.

    Args:
        background_tasks: FastAPI background tasks
        auto_summarize: Whether auto-summarize was requested
        item_id: ID of the item to summarize
        content: Content to summarize
        url: URL for context
        title: Title for context
    """
    if auto_summarize and state.summarizer and content:
        background_tasks.add_task(
            summarize_article,
            item_id,
            content,
            url,
            title
        )


# ─────────────────────────────────────────────────────────────
# List & Stats
# ─────────────────────────────────────────────────────────────

@router.get("")
async def list_standalone_items(
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
    content_type: str | None = None,
    bookmarked_only: bool = False,
    limit: int = Query(default=100, le=500),
    offset: int = 0
) -> StandaloneListResponse:
    """List all standalone items in the library."""
    items = db.get_standalone_items(
        user_id=user_id,
        content_type=content_type,
        bookmarked_only=bookmarked_only,
        limit=limit,
        offset=offset
    )
    total = db.get_standalone_count(user_id)
    return StandaloneListResponse(
        items=[StandaloneItemResponse.from_db(item) for item in items],
        total=total
    )


@router.get("/stats")
async def get_library_stats(
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> LibraryStatsResponse:
    """Get library statistics."""
    items = db.get_standalone_items(user_id=user_id, limit=10000)  # Get all for stats
    total = len(items)

    by_type: dict[str, int] = {}
    for item in items:
        ct = item.content_type or "unknown"
        by_type[ct] = by_type.get(ct, 0) + 1

    return LibraryStatsResponse(
        total_items=total,
        by_type=by_type
    )


# ─────────────────────────────────────────────────────────────
# Add URL
# ─────────────────────────────────────────────────────────────

@router.post("/url")
async def add_url_to_library(
    request: AddStandaloneURLRequest,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
    background_tasks: BackgroundTasks,
    auto_summarize: bool = Query(default=False, description="Automatically summarize after fetching")
) -> StandaloneItemDetailResponse:
    """Add a URL to the library."""
    if not state.fetcher:
        raise HTTPException(status_code=503, detail="Fetcher not configured")

    # Fetch content from URL
    try:
        if state.enhanced_fetcher:
            result = await state.enhanced_fetcher.fetch(request.url)
        else:
            result = await state.fetcher.fetch(request.url)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch URL: {e}")

    # Use provided title or extracted title
    title = request.title or result.title or "Untitled"

    # Add to database
    item_id = db.add_standalone_item(
        user_id=user_id,
        url=request.url,
        title=title,
        content=result.content,
        content_type="url"
    )

    if not item_id:
        raise HTTPException(status_code=409, detail="URL already exists in library")

    item = db.get_article(item_id)
    if not item:
        raise HTTPException(status_code=500, detail="Failed to retrieve item")

    # Auto-summarize if requested
    schedule_auto_summarize(background_tasks, auto_summarize, item_id, result.content, request.url, title)

    return StandaloneItemDetailResponse.from_db(item)


# ─────────────────────────────────────────────────────────────
# Upload File
# ─────────────────────────────────────────────────────────────

@router.post("/upload")
async def upload_file_to_library(
    file: UploadFile = File(...),
    title: str | None = Query(default=None, description="Optional title for the item"),
    db: Database = Depends(get_db),
    user_id: int = Depends(get_current_user),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    auto_summarize: bool = Query(default=False, description="Automatically summarize after extraction")
) -> StandaloneItemDetailResponse:
    """Upload a file to the library (PDF, DOCX, TXT, MD, HTML)."""
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    # Detect content type from filename
    try:
        content_type = detect_content_type(file.filename)
    except ExtractionError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Read file content and check size
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read file: {e}")

    # Enforce file size limit
    max_size_bytes = config.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    if len(content) > max_size_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Maximum size is {config.MAX_UPLOAD_SIZE_MB}MB"
        )

    # Save file with UUID name
    uploads_dir = ensure_uploads_dir()
    file_ext = Path(file.filename).suffix
    unique_filename = f"{uuid.uuid4()}{file_ext}"
    file_path = uploads_dir / unique_filename

    try:
        file_path.write_bytes(content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save file: {e}")

    # Extract text content
    try:
        extracted_text = extract_text(file_path, content_type)
    except ExtractionError as e:
        # Clean up file on extraction failure
        file_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"Failed to extract text: {e}")

    # Use provided title or filename
    item_title = title or Path(file.filename).stem

    # Create a file:// URL for identification
    file_url = f"file://{unique_filename}"

    # Add to database
    item_id = db.add_standalone_item(
        user_id=user_id,
        url=file_url,
        title=item_title,
        content=extracted_text,
        content_type=content_type,
        file_name=file.filename,
        file_path=str(file_path)
    )

    if not item_id:
        # Clean up file on duplicate
        file_path.unlink(missing_ok=True)
        raise HTTPException(status_code=409, detail="File already exists in library")

    item = db.get_article(item_id)
    if not item:
        raise HTTPException(status_code=500, detail="Failed to retrieve item")

    # Auto-summarize if requested
    schedule_auto_summarize(background_tasks, auto_summarize, item_id, extracted_text, file_url, item_title)

    return StandaloneItemDetailResponse.from_db(item)


# ─────────────────────────────────────────────────────────────
# Single Item Operations
# ─────────────────────────────────────────────────────────────

@router.get("/{item_id}")
async def get_standalone_item(
    item_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> StandaloneItemDetailResponse:
    """Get a single standalone item with full content."""
    item = require_item(db.get_library_item(user_id, item_id))
    return StandaloneItemDetailResponse.from_db(item)


@router.delete("/{item_id}")
async def delete_standalone_item(
    item_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> dict:
    """Delete a standalone item from the library."""
    # Get item first to clean up file if needed
    item = db.get_library_item(user_id, item_id)
    if item and item.file_path:
        file_path = Path(item.file_path)
        file_path.unlink(missing_ok=True)

    deleted = db.delete_standalone_item(user_id, item_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Item not found in library")

    return {"success": True, "deleted_id": item_id}


@router.post("/{item_id}/read")
async def mark_item_read(
    item_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
    is_read: bool = True
) -> dict:
    """Mark a standalone item as read/unread."""
    require_item(db.get_library_item(user_id, item_id))
    db.mark_read(user_id, item_id, is_read)
    return {"success": True, "is_read": is_read}


@router.post("/{item_id}/bookmark")
async def toggle_item_bookmark(
    item_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)]
) -> dict:
    """Toggle bookmark status for a standalone item."""
    require_item(db.get_library_item(user_id, item_id))
    new_status = db.toggle_bookmark(user_id, item_id)
    return {"success": True, "is_bookmarked": new_status}


@router.post("/{item_id}/summarize")
async def summarize_standalone_item(
    item_id: int,
    db: Annotated[Database, Depends(get_db)],
    user_id: Annotated[int, Depends(get_current_user)],
    background_tasks: BackgroundTasks
) -> dict:
    """Generate or regenerate summary for a standalone item."""
    if not state.summarizer:
        raise HTTPException(status_code=503, detail="Summarization not configured")

    item = require_item(db.get_library_item(user_id, item_id))
    content = require_sufficient_content(
        item.content,
        "Item has insufficient content for summarization"
    )

    background_tasks.add_task(
        summarize_article,
        item_id,
        content,
        item.url,
        item.title
    )

    return {"success": True, "message": "Summarization started"}


# ─────────────────────────────────────────────────────────────
# Newsletter Import
# ─────────────────────────────────────────────────────────────

async def import_single_newsletter(
    file: UploadFile,
    db: Database,
    user_id: int,
    background_tasks: BackgroundTasks,
    auto_summarize: bool
) -> NewsletterImportResult:
    """Import a single newsletter from an .eml file."""
    if not file.filename:
        return NewsletterImportResult(success=False, error="No filename provided")

    if not file.filename.lower().endswith(".eml"):
        return NewsletterImportResult(
            success=False,
            error=f"Not an .eml file: {file.filename}"
        )

    try:
        content = await file.read()
        parsed = parse_eml_bytes(content)

        article_html = extract_article_content(parsed)
        if not article_html or len(article_html.strip()) < 50:
            return NewsletterImportResult(
                success=False,
                title=parsed.title,
                author=parsed.author,
                error="Newsletter has insufficient content"
            )

        # Generate unique URL for deduplication
        date_str = parsed.date.strftime("%Y%m%d%H%M%S") if parsed.date else "unknown"
        newsletter_id = f"{parsed.sender_email}_{date_str}"
        newsletter_url = f"newsletter://{newsletter_id}"

        item_id = db.add_standalone_item(
            user_id=user_id,
            url=newsletter_url,
            title=parsed.title,
            content=article_html,
            content_type="newsletter",
            file_name=file.filename,
            author=parsed.author,
            published_at=parsed.date,
        )

        if not item_id:
            return NewsletterImportResult(
                success=False,
                title=parsed.title,
                author=parsed.author,
                error="Newsletter already exists in library"
            )

        schedule_auto_summarize(
            background_tasks, auto_summarize, item_id,
            article_html, newsletter_url, parsed.title
        )

        return NewsletterImportResult(
            success=True,
            title=parsed.title,
            author=parsed.author,
            item_id=item_id,
        )

    except EmailParseError as e:
        return NewsletterImportResult(success=False, error=f"Failed to parse email: {e}")
    except Exception as e:
        return NewsletterImportResult(success=False, error=f"Import error: {e}")


@router.post("/newsletter/import")
async def import_newsletters(
    files: list[UploadFile] = File(...),
    db: Database = Depends(get_db),
    user_id: int = Depends(get_current_user),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    auto_summarize: bool = Query(default=False, description="Automatically summarize after import")
) -> NewsletterImportResponse:
    """
    Import newsletter emails from .eml files.

    Accepts multiple .eml files and imports them as library items.
    Extracts newsletter content, subject, sender, and date.
    """
    results = [
        await import_single_newsletter(file, db, user_id, background_tasks, auto_summarize)
        for file in files
    ]

    imported = sum(1 for r in results if r.success)
    failed = len(results) - imported

    return NewsletterImportResponse(
        total=len(files),
        imported=imported,
        failed=failed,
        results=results
    )


@router.post("/newsletter/import-raw")
async def import_newsletter_raw(
    content: str,
    db: Database = Depends(get_db),
    user_id: int = Depends(get_current_user),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    auto_summarize: bool = Query(default=False, description="Automatically summarize after import")
) -> StandaloneItemDetailResponse:
    """
    Import a newsletter from raw .eml content (e.g., from clipboard).

    Accepts the raw email content as a string and imports it as a library item.
    """
    from ..email_parser import parse_eml_string

    try:
        parsed = parse_eml_string(content)
    except EmailParseError as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse email: {e}")

    # Extract article content
    article_html = extract_article_content(parsed)
    if not article_html or len(article_html.strip()) < 50:
        raise HTTPException(status_code=400, detail="Newsletter has insufficient content")

    # Generate unique URL
    date_str = parsed.date.strftime("%Y%m%d%H%M%S") if parsed.date else "unknown"
    newsletter_id = f"{parsed.sender_email}_{date_str}"
    newsletter_url = f"newsletter://{newsletter_id}"

    # Add to database
    item_id = db.add_standalone_item(
        user_id=user_id,
        url=newsletter_url,
        title=parsed.title,
        content=article_html,
        content_type="newsletter",
        author=parsed.author,
        published_at=parsed.date,
    )

    if not item_id:
        raise HTTPException(status_code=409, detail="Newsletter already exists in library")

    item = db.get_library_item(user_id, item_id)
    if not item:
        raise HTTPException(status_code=500, detail="Failed to retrieve item")

    # Auto-summarize if requested
    schedule_auto_summarize(background_tasks, auto_summarize, item_id, article_html, newsletter_url, parsed.title)

    return StandaloneItemDetailResponse.from_db(item)
