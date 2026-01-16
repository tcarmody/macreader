"""
Library repository - operations for standalone/library items.

Library items are per-user: each user has their own private library.
Items are stored in the articles table with user_id set to the owner.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_article
from .models import DBArticle


class LibraryRepository:
    """Repository for per-user library items."""

    # Keep the standalone feed for backward compatibility during migration
    STANDALONE_FEED_URL = "local://standalone"
    STANDALONE_FEED_NAME = "Library"

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_or_create_feed(self) -> int:
        """Get or create the system feed for library items. Returns feed ID."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT id FROM feeds WHERE url = ?",
                (self.STANDALONE_FEED_URL,)
            ).fetchone()
            if row:
                return row["id"]

            cursor = conn.execute(
                "INSERT INTO feeds (url, name, category) VALUES (?, ?, ?)",
                (self.STANDALONE_FEED_URL, self.STANDALONE_FEED_NAME, "Library")
            )
            return cursor.lastrowid

    def add(
        self,
        user_id: int,
        url: str,
        title: str,
        content: str | None = None,
        content_type: str = "url",
        file_name: str | None = None,
        file_path: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
    ) -> int | None:
        """
        Add a library item for a user.

        Args:
            user_id: The owning user's ID
            url: URL of the item (or generated identifier for uploads)
            title: Title of the item
            content: Content text (optional)
            content_type: Type of content (url, pdf, docx, etc.)
            file_name: Original filename for uploads
            file_path: Local storage path for uploads
            author: Author name (optional)
            published_at: Publication date (optional, defaults to now)

        Returns:
            Item ID or None if duplicate URL for this user
        """
        feed_id = self.get_or_create_feed()
        pub_date = published_at or datetime.now()

        with self._db.conn() as conn:
            # Check if user already has this URL
            existing = conn.execute(
                "SELECT id FROM articles WHERE user_id = ? AND url = ?",
                (user_id, url)
            ).fetchone()
            if existing:
                return None  # Duplicate for this user

            try:
                cursor = conn.execute(
                    """INSERT INTO articles
                       (feed_id, user_id, url, title, content, content_type,
                        file_name, file_path, author, published_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (feed_id, user_id, url, title, content, content_type,
                     file_name, file_path, author, pub_date.isoformat())
                )
                return cursor.lastrowid
            except Exception:
                return None

    def get_all(
        self,
        user_id: int,
        content_type: str | None = None,
        bookmarked_only: bool = False,
        limit: int = 100,
        offset: int = 0
    ) -> list[DBArticle]:
        """
        Get all library items for a user.

        Args:
            user_id: The user's ID
            content_type: Filter by content type (url, pdf, etc.)
            bookmarked_only: Only return bookmarked items
            limit: Maximum items to return
            offset: Number of items to skip
        """
        feed_id = self.get_or_create_feed()

        # Library items have user_id set (unlike shared RSS articles)
        query = "SELECT * FROM articles WHERE feed_id = ? AND user_id = ?"
        params: list = [feed_id, user_id]

        if content_type:
            query += " AND content_type = ?"
            params.append(content_type)
        if bookmarked_only:
            query += " AND is_bookmarked = 1"

        query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        with self._db.conn() as conn:
            rows = conn.execute(query, params).fetchall()
            return [row_to_article(row) for row in rows]

    def get_count(self, user_id: int) -> int:
        """Get count of library items for a user."""
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT COUNT(*) as count FROM articles WHERE feed_id = ? AND user_id = ?",
                (feed_id, user_id)
            ).fetchone()
            return row["count"] if row else 0

    def get_item(self, user_id: int, article_id: int) -> DBArticle | None:
        """Get a specific library item, verifying ownership."""
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE id = ? AND feed_id = ? AND user_id = ?",
                (article_id, feed_id, user_id)
            ).fetchone()
            return row_to_article(row) if row else None

    def delete(self, user_id: int, article_id: int) -> bool:
        """
        Delete a library item. Only the owner can delete.

        Returns True if deleted, False if not found or not owned.
        """
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            cursor = conn.execute(
                "DELETE FROM articles WHERE id = ? AND feed_id = ? AND user_id = ?",
                (article_id, feed_id, user_id)
            )
            return cursor.rowcount > 0

    def is_standalone_feed(self, feed_id: int) -> bool:
        """Check if a feed ID is the library feed."""
        standalone_id = self.get_or_create_feed()
        return feed_id == standalone_id

    def verify_ownership(self, user_id: int, article_id: int) -> bool:
        """Check if a user owns a library item."""
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT 1 FROM articles WHERE id = ? AND feed_id = ? AND user_id = ?",
                (article_id, feed_id, user_id)
            ).fetchone()
            return row is not None
