"""
Feed repository - CRUD operations for feeds.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_feed
from .models import DBFeed


class FeedRepository:
    """Repository for feed operations."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def add(self, url: str, name: str, category: str | None = None) -> int:
        """Add a new feed. Returns feed ID."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                "INSERT INTO feeds (url, name, category) VALUES (?, ?, ?)",
                (url, name, category)
            )
            return cursor.lastrowid

    def get(self, feed_id: int, user_id: int | None = None) -> DBFeed | None:
        """Get single feed by ID with optional user-specific unread count."""
        with self._db.conn() as conn:
            if user_id is not None:
                row = conn.execute(
                    """SELECT f.*,
                       COUNT(CASE WHEN COALESCE(uas.is_read, FALSE) = FALSE THEN 1 END) as unread_count
                       FROM feeds f
                       LEFT JOIN articles a ON f.id = a.feed_id
                       LEFT JOIN user_article_state uas ON a.id = uas.article_id AND uas.user_id = ?
                       WHERE f.id = ?
                       GROUP BY f.id""",
                    (user_id, feed_id)
                ).fetchone()
            else:
                # Without user_id, count all articles as unread (no state)
                row = conn.execute(
                    """SELECT f.*, COUNT(a.id) as unread_count
                       FROM feeds f
                       LEFT JOIN articles a ON f.id = a.feed_id
                       WHERE f.id = ?
                       GROUP BY f.id""",
                    (feed_id,)
                ).fetchone()
            return row_to_feed(row) if row else None

    def get_all(self, user_id: int | None = None) -> list[DBFeed]:
        """Get all feeds with user-specific unread counts."""
        with self._db.conn() as conn:
            if user_id is not None:
                rows = conn.execute("""
                    SELECT f.*,
                           COUNT(CASE WHEN COALESCE(uas.is_read, FALSE) = FALSE THEN 1 END) as unread_count
                    FROM feeds f
                    LEFT JOIN articles a ON f.id = a.feed_id
                    LEFT JOIN user_article_state uas ON a.id = uas.article_id AND uas.user_id = ?
                    GROUP BY f.id
                    ORDER BY f.name
                """, (user_id,)).fetchall()
            else:
                # Without user_id, count all articles as unread
                rows = conn.execute("""
                    SELECT f.*, COUNT(a.id) as unread_count
                    FROM feeds f
                    LEFT JOIN articles a ON f.id = a.feed_id
                    GROUP BY f.id
                    ORDER BY f.name
                """).fetchall()
            return [row_to_feed(row) for row in rows]

    def update(
        self,
        feed_id: int,
        name: str | None = None,
        category: str | None = None,
        clear_category: bool = False
    ):
        """Update feed details. Use clear_category=True to remove category."""
        with self._db.conn() as conn:
            if name is not None:
                conn.execute("UPDATE feeds SET name = ? WHERE id = ?", (name, feed_id))
            if clear_category:
                conn.execute("UPDATE feeds SET category = NULL WHERE id = ?", (feed_id,))
            elif category is not None:
                conn.execute("UPDATE feeds SET category = ? WHERE id = ?", (category, feed_id))

    def update_fetched(self, feed_id: int, error: str | None = None):
        """Update feed's last fetched timestamp."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE feeds SET last_fetched = ?, fetch_error = ? WHERE id = ?",
                (datetime.now().isoformat(), error, feed_id)
            )

    def delete(self, feed_id: int):
        """Delete feed and its articles."""
        with self._db.conn() as conn:
            conn.execute("DELETE FROM feeds WHERE id = ?", (feed_id,))

    def bulk_delete(self, feed_ids: list[int], exclude_newsletters: bool = True):
        """
        Delete multiple feeds and their articles.

        Args:
            feed_ids: List of feed IDs to delete
            exclude_newsletters: If True, newsletter feeds (newsletter://) are preserved
        """
        if not feed_ids:
            return
        with self._db.conn() as conn:
            placeholders = ",".join("?" * len(feed_ids))
            if exclude_newsletters:
                conn.execute(
                    f"DELETE FROM feeds WHERE id IN ({placeholders}) AND url NOT LIKE 'newsletter://%'",
                    feed_ids
                )
            else:
                conn.execute(f"DELETE FROM feeds WHERE id IN ({placeholders})", feed_ids)

    def get_or_create_newsletter_feed(
        self,
        sender_email: str,
        sender_name: str,
        newsletter_name: str | None = None
    ) -> int:
        """
        Get or create a feed for a newsletter sender.

        Each unique sender_email gets its own feed, allowing newsletters
        to be browsed like regular RSS feeds.

        Args:
            sender_email: The sender's email address (used as unique identifier)
            sender_name: Display name of the sender
            newsletter_name: Optional newsletter name (e.g., "The Batch")

        Returns:
            Feed ID for this newsletter
        """
        # Use a special URL scheme to identify newsletter feeds
        feed_url = f"newsletter://{sender_email}"

        with self._db.conn() as conn:
            # Check if feed already exists
            row = conn.execute(
                "SELECT id FROM feeds WHERE url = ?",
                (feed_url,)
            ).fetchone()

            if row:
                return row["id"]

            # Create new feed for this newsletter
            # Use newsletter_name if available, otherwise sender_name
            display_name = newsletter_name or sender_name or sender_email
            cursor = conn.execute(
                "INSERT INTO feeds (url, name, category) VALUES (?, ?, ?)",
                (feed_url, display_name, "Newsletters")
            )
            return cursor.lastrowid

    def is_newsletter_feed(self, feed_id: int) -> bool:
        """Check if a feed is a newsletter feed (vs RSS feed)."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT url FROM feeds WHERE id = ?",
                (feed_id,)
            ).fetchone()
            return row is not None and row["url"].startswith("newsletter://")
