"""
Library repository - operations for standalone/library items.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_article
from .models import DBArticle


class LibraryRepository:
    """Repository for standalone library items."""

    STANDALONE_FEED_URL = "local://standalone"
    STANDALONE_FEED_NAME = "Library"

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_or_create_feed(self) -> int:
        """Get or create the system feed for standalone items. Returns feed ID."""
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
        url: str,
        title: str,
        content: str | None = None,
        content_type: str = "url",
        file_name: str | None = None,
        file_path: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
    ) -> int | None:
        """Add a standalone item to the library. Returns item ID or None if duplicate."""
        feed_id = self.get_or_create_feed()
        pub_date = published_at or datetime.now()
        with self._db.conn() as conn:
            try:
                cursor = conn.execute(
                    """INSERT INTO articles
                       (feed_id, url, title, content, content_type, file_name, file_path, author, published_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (feed_id, url, title, content, content_type, file_name, file_path,
                     author, pub_date.isoformat())
                )
                return cursor.lastrowid
            except Exception:
                # Duplicate URL
                return None

    def get_all(
        self,
        content_type: str | None = None,
        bookmarked_only: bool = False,
        limit: int = 100,
        offset: int = 0
    ) -> list[DBArticle]:
        """Get all standalone library items."""
        feed_id = self.get_or_create_feed()
        query = "SELECT * FROM articles WHERE feed_id = ?"
        params: list = [feed_id]

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

    def get_count(self) -> int:
        """Get count of standalone items."""
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT COUNT(*) as count FROM articles WHERE feed_id = ?",
                (feed_id,)
            ).fetchone()
            return row["count"] if row else 0

    def delete(self, article_id: int) -> bool:
        """Delete a standalone item. Returns True if deleted."""
        feed_id = self.get_or_create_feed()
        with self._db.conn() as conn:
            cursor = conn.execute(
                "DELETE FROM articles WHERE id = ? AND feed_id = ?",
                (article_id, feed_id)
            )
            return cursor.rowcount > 0

    def is_standalone_feed(self, feed_id: int) -> bool:
        """Check if a feed ID is the standalone feed."""
        standalone_id = self.get_or_create_feed()
        return feed_id == standalone_id
