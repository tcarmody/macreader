"""
Library service: business logic for library/standalone item operations.

Handles URL saving, file uploads, newsletter imports, and item management.
"""

import uuid
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from fastapi import BackgroundTasks, HTTPException, UploadFile

from ..config import config
from ..database import Database
from ..database.models import DBArticle
from ..exceptions import require_item
from ..extractors import extract_text, detect_content_type, ExtractionError
from ..email_parser import (
    parse_eml_bytes,
    parse_eml_string,
    extract_article_content,
    EmailParseError,
)
from ..schemas import NewsletterImportResult
from ..tasks import summarize_article
from ..validators import require_sufficient_content

if TYPE_CHECKING:
    from ..fetcher import Fetcher
    from ..summarizer import Summarizer


# Directory for uploaded files
UPLOADS_DIR = config.DB_PATH.parent / "uploads"


def ensure_uploads_dir() -> Path:
    """Ensure uploads directory exists."""
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    return UPLOADS_DIR


class LibraryService:
    """Service for library/standalone item business logic."""

    def __init__(
        self,
        db: Database,
        fetcher: "Fetcher | None" = None,
        enhanced_fetcher: object | None = None,
        summarizer: "Summarizer | None" = None,
    ):
        self.db = db
        self.fetcher = fetcher
        self.enhanced_fetcher = enhanced_fetcher
        self.summarizer = summarizer

    # ─────────────────────────────────────────────────────────────
    # List & Stats
    # ─────────────────────────────────────────────────────────────

    def list_items(
        self,
        user_id: int,
        content_type: str | None = None,
        bookmarked_only: bool = False,
        limit: int = 100,
        offset: int = 0,
    ) -> tuple[list[DBArticle], int]:
        """
        List library items with filtering.

        Args:
            user_id: User ID
            content_type: Filter by content type
            bookmarked_only: Only bookmarked items
            limit: Maximum items to return
            offset: Pagination offset

        Returns:
            Tuple of (items, total_count)
        """
        items = self.db.get_standalone_items(
            user_id=user_id,
            content_type=content_type,
            bookmarked_only=bookmarked_only,
            limit=limit,
            offset=offset
        )
        total = self.db.get_standalone_count(user_id)
        return items, total

    def get_stats(self, user_id: int) -> dict:
        """
        Get library statistics.

        Args:
            user_id: User ID

        Returns:
            Dict with total_items and by_type breakdown
        """
        items = self.db.get_standalone_items(user_id=user_id, limit=10000)
        total = len(items)

        by_type: dict[str, int] = {}
        for item in items:
            ct = item.content_type or "unknown"
            by_type[ct] = by_type.get(ct, 0) + 1

        return {
            "total_items": total,
            "by_type": by_type
        }

    def get_item(self, user_id: int, item_id: int) -> DBArticle:
        """
        Get a single library item.

        Args:
            user_id: User ID
            item_id: Item ID

        Returns:
            The library item

        Raises:
            HTTPException: If item not found
        """
        return require_item(self.db.get_library_item(user_id, item_id))

    # ─────────────────────────────────────────────────────────────
    # Add URL
    # ─────────────────────────────────────────────────────────────

    async def add_url(
        self,
        url: str,
        user_id: int,
        background_tasks: BackgroundTasks,
        title: str | None = None,
        auto_summarize: bool = False,
    ) -> DBArticle:
        """
        Add a URL to the library.

        Args:
            url: URL to fetch and save
            user_id: User ID
            background_tasks: FastAPI background tasks
            title: Optional custom title
            auto_summarize: Whether to auto-summarize after fetching

        Returns:
            The created library item

        Raises:
            HTTPException: If fetching fails or URL already exists
        """
        if not self.fetcher:
            raise HTTPException(status_code=503, detail="Fetcher not configured")

        # Fetch content from URL
        try:
            if self.enhanced_fetcher:
                result = await self.enhanced_fetcher.fetch(url)
            else:
                result = await self.fetcher.fetch(url)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to fetch URL: {e}")

        # Use provided title or extracted title
        item_title = title or result.title or "Untitled"

        # Add to database
        item_id = self.db.add_standalone_item(
            user_id=user_id,
            url=url,
            title=item_title,
            content=result.content,
            content_type="url"
        )

        if not item_id:
            raise HTTPException(status_code=409, detail="URL already exists in library")

        item = self.db.get_article(item_id)
        if not item:
            raise HTTPException(status_code=500, detail="Failed to retrieve item")

        # Auto-summarize if requested
        self._schedule_auto_summarize(
            background_tasks, auto_summarize, item_id,
            result.content, url, item_title
        )

        return item

    # ─────────────────────────────────────────────────────────────
    # File Upload
    # ─────────────────────────────────────────────────────────────

    async def upload_file(
        self,
        file: UploadFile,
        user_id: int,
        background_tasks: BackgroundTasks,
        title: str | None = None,
        auto_summarize: bool = False,
    ) -> DBArticle:
        """
        Upload a file to the library.

        Args:
            file: Uploaded file (PDF, DOCX, TXT, MD, HTML)
            user_id: User ID
            background_tasks: FastAPI background tasks
            title: Optional custom title
            auto_summarize: Whether to auto-summarize after extraction

        Returns:
            The created library item

        Raises:
            HTTPException: If file invalid, too large, or already exists
        """
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
        item_id = self.db.add_standalone_item(
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

        item = self.db.get_article(item_id)
        if not item:
            raise HTTPException(status_code=500, detail="Failed to retrieve item")

        # Auto-summarize if requested
        self._schedule_auto_summarize(
            background_tasks, auto_summarize, item_id,
            extracted_text, file_url, item_title
        )

        return item

    # ─────────────────────────────────────────────────────────────
    # Item Operations
    # ─────────────────────────────────────────────────────────────

    def delete_item(self, user_id: int, item_id: int) -> None:
        """
        Delete a library item.

        Args:
            user_id: User ID
            item_id: Item ID to delete

        Raises:
            HTTPException: If item not found
        """
        # Get item first to clean up file if needed
        item = self.db.get_library_item(user_id, item_id)
        if item and item.file_path:
            file_path = Path(item.file_path)
            file_path.unlink(missing_ok=True)

        deleted = self.db.delete_standalone_item(user_id, item_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Item not found in library")

    def mark_read(self, user_id: int, item_id: int, is_read: bool = True) -> None:
        """
        Mark a library item as read/unread.

        Args:
            user_id: User ID
            item_id: Item ID
            is_read: Mark as read (True) or unread (False)

        Raises:
            HTTPException: If item not found
        """
        require_item(self.db.get_library_item(user_id, item_id))
        self.db.mark_read(user_id, item_id, is_read)

    def toggle_bookmark(self, user_id: int, item_id: int) -> bool:
        """
        Toggle bookmark status for a library item.

        Args:
            user_id: User ID
            item_id: Item ID

        Returns:
            New bookmark status

        Raises:
            HTTPException: If item not found
        """
        require_item(self.db.get_library_item(user_id, item_id))
        return self.db.toggle_bookmark(user_id, item_id)

    def schedule_summarization(
        self,
        user_id: int,
        item_id: int,
        background_tasks: BackgroundTasks,
    ) -> None:
        """
        Schedule summarization for a library item.

        Args:
            user_id: User ID
            item_id: Item ID
            background_tasks: FastAPI background tasks

        Raises:
            HTTPException: If summarizer not configured or content insufficient
        """
        if not self.summarizer:
            raise HTTPException(status_code=503, detail="Summarization not configured")

        item = require_item(self.db.get_library_item(user_id, item_id))
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

    # ─────────────────────────────────────────────────────────────
    # Newsletter Import
    # ─────────────────────────────────────────────────────────────

    async def import_newsletter(
        self,
        file: UploadFile,
        user_id: int,
        background_tasks: BackgroundTasks,
        auto_summarize: bool = False,
    ) -> NewsletterImportResult:
        """
        Import a single newsletter from an .eml file.

        Args:
            file: Uploaded .eml file
            user_id: User ID
            background_tasks: FastAPI background tasks
            auto_summarize: Whether to auto-summarize

        Returns:
            Import result with success/error details
        """
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

            item_id = self.db.add_standalone_item(
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

            self._schedule_auto_summarize(
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

    async def import_newsletters(
        self,
        files: list[UploadFile],
        user_id: int,
        background_tasks: BackgroundTasks,
        auto_summarize: bool = False,
    ) -> dict:
        """
        Import multiple newsletters from .eml files.

        Args:
            files: List of uploaded .eml files
            user_id: User ID
            background_tasks: FastAPI background tasks
            auto_summarize: Whether to auto-summarize

        Returns:
            Dict with total, imported, failed counts and results list
        """
        results = [
            await self.import_newsletter(file, user_id, background_tasks, auto_summarize)
            for file in files
        ]

        imported = sum(1 for r in results if r.success)
        failed = len(results) - imported

        return {
            "total": len(files),
            "imported": imported,
            "failed": failed,
            "results": results,
        }

    async def import_newsletter_raw(
        self,
        eml_content: str,
        user_id: int,
        background_tasks: BackgroundTasks,
        auto_summarize: bool = False,
    ) -> DBArticle:
        """
        Import a newsletter from raw .eml content.

        Args:
            eml_content: Raw email content as string
            user_id: User ID
            background_tasks: FastAPI background tasks
            auto_summarize: Whether to auto-summarize

        Returns:
            The created library item

        Raises:
            HTTPException: If parsing fails or content insufficient
        """
        try:
            parsed = parse_eml_string(eml_content)
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
        item_id = self.db.add_standalone_item(
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

        item = self.db.get_library_item(user_id, item_id)
        if not item:
            raise HTTPException(status_code=500, detail="Failed to retrieve item")

        # Auto-summarize if requested
        self._schedule_auto_summarize(
            background_tasks, auto_summarize, item_id,
            article_html, newsletter_url, parsed.title
        )

        return item

    # ─────────────────────────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────────────────────────

    def _schedule_auto_summarize(
        self,
        background_tasks: BackgroundTasks,
        auto_summarize: bool,
        item_id: int,
        content: str | None,
        url: str,
        title: str
    ) -> None:
        """Schedule auto-summarization if enabled and content is available."""
        if auto_summarize and self.summarizer and content:
            background_tasks.add_task(
                summarize_article,
                item_id,
                content,
                url,
                title
            )
