"""
Repository for per-user article state (read/bookmark status).
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_user_article_state
from .models import DBUserArticleState


class UserArticleStateRepository:
    """Repository for per-user article read/bookmark state."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_state(self, user_id: int, article_id: int) -> DBUserArticleState | None:
        """Get state for a specific user+article pair."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM user_article_state
                WHERE user_id = ? AND article_id = ?
                """,
                (user_id, article_id)
            )
            row = cursor.fetchone()
            return row_to_user_article_state(row) if row else None

    def _get_or_create_state(self, conn, user_id: int, article_id: int) -> int:
        """
        Get or create state record (internal helper).

        Returns the state record ID.
        """
        cursor = conn.execute(
            "SELECT id FROM user_article_state WHERE user_id = ? AND article_id = ?",
            (user_id, article_id)
        )
        row = cursor.fetchone()

        if row:
            return row["id"]

        # Create new state record with defaults
        cursor = conn.execute(
            """
            INSERT INTO user_article_state (user_id, article_id, is_read, is_bookmarked)
            VALUES (?, ?, FALSE, FALSE)
            """,
            (user_id, article_id)
        )
        return cursor.lastrowid

    def mark_read(self, user_id: int, article_id: int, is_read: bool = True):
        """Mark article as read/unread for a user."""
        with self._db.conn() as conn:
            self._get_or_create_state(conn, user_id, article_id)

            read_at = datetime.now().isoformat() if is_read else None
            conn.execute(
                """
                UPDATE user_article_state
                SET is_read = ?, read_at = ?
                WHERE user_id = ? AND article_id = ?
                """,
                (is_read, read_at, user_id, article_id)
            )

    def toggle_bookmark(self, user_id: int, article_id: int) -> bool:
        """Toggle bookmark status for a user. Returns new status."""
        with self._db.conn() as conn:
            self._get_or_create_state(conn, user_id, article_id)

            # Get current status
            cursor = conn.execute(
                """
                SELECT is_bookmarked FROM user_article_state
                WHERE user_id = ? AND article_id = ?
                """,
                (user_id, article_id)
            )
            row = cursor.fetchone()
            current = bool(row["is_bookmarked"]) if row else False

            # Toggle
            new_status = not current
            bookmarked_at = datetime.now().isoformat() if new_status else None

            conn.execute(
                """
                UPDATE user_article_state
                SET is_bookmarked = ?, bookmarked_at = ?
                WHERE user_id = ? AND article_id = ?
                """,
                (new_status, bookmarked_at, user_id, article_id)
            )

            return new_status

    def bulk_mark_read(
        self,
        user_id: int,
        article_ids: list[int],
        is_read: bool = True
    ):
        """Mark multiple articles as read/unread for a user."""
        if not article_ids:
            return

        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None

            # Batch insert/update using executemany for better performance
            conn.executemany(
                """
                INSERT INTO user_article_state (user_id, article_id, is_read, read_at, is_bookmarked)
                VALUES (?, ?, ?, ?, FALSE)
                ON CONFLICT(user_id, article_id) DO UPDATE SET
                    is_read = excluded.is_read,
                    read_at = excluded.read_at
                """,
                [(user_id, article_id, is_read, read_at) for article_id in article_ids]
            )

    def mark_feed_read(
        self,
        user_id: int,
        feed_id: int,
        is_read: bool = True
    ) -> int:
        """
        Mark all articles in a feed as read/unread for a user.

        Returns count of articles updated.
        """
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None

            # Use INSERT...SELECT to update all articles in one statement
            # This is much faster than fetching IDs and looping
            cursor = conn.execute(
                """
                INSERT INTO user_article_state (user_id, article_id, is_read, read_at, is_bookmarked)
                SELECT ?, id, ?, ?, FALSE
                FROM articles
                WHERE feed_id = ?
                ON CONFLICT(user_id, article_id) DO UPDATE SET
                    is_read = excluded.is_read,
                    read_at = excluded.read_at
                """,
                (user_id, is_read, read_at, feed_id)
            )

            return cursor.rowcount

    def mark_all_read(self, user_id: int, is_read: bool = True) -> int:
        """
        Mark all articles as read/unread for a user.

        Only affects shared articles (user_id IS NULL), not library items.

        Returns count of articles updated.
        """
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None

            # Use INSERT...SELECT to update all shared articles in one statement
            # This is much faster than fetching IDs and looping
            cursor = conn.execute(
                """
                INSERT INTO user_article_state (user_id, article_id, is_read, read_at, is_bookmarked)
                SELECT ?, id, ?, ?, FALSE
                FROM articles
                WHERE user_id IS NULL
                ON CONFLICT(user_id, article_id) DO UPDATE SET
                    is_read = excluded.is_read,
                    read_at = excluded.read_at
                """,
                (user_id, is_read, read_at)
            )

            return cursor.rowcount

    def get_user_stats(self, user_id: int) -> dict:
        """Get read/bookmark stats for a user."""
        with self._db.conn() as conn:
            # Count read articles
            cursor = conn.execute(
                """
                SELECT COUNT(*) as count FROM user_article_state
                WHERE user_id = ? AND is_read = TRUE
                """,
                (user_id,)
            )
            read_count = cursor.fetchone()["count"]

            # Count bookmarked articles
            cursor = conn.execute(
                """
                SELECT COUNT(*) as count FROM user_article_state
                WHERE user_id = ? AND is_bookmarked = TRUE
                """,
                (user_id,)
            )
            bookmarked_count = cursor.fetchone()["count"]

            return {
                "read_count": read_count,
                "bookmarked_count": bookmarked_count,
            }

    def get_unread_count(self, user_id: int, feed_id: int | None = None) -> int:
        """
        Get count of unread articles for a user.

        If feed_id is provided, counts only articles in that feed.
        Only counts shared articles (not library items).
        """
        with self._db.conn() as conn:
            if feed_id:
                # Count articles in feed that are NOT marked read by user
                cursor = conn.execute(
                    """
                    SELECT COUNT(*) as count FROM articles a
                    LEFT JOIN user_article_state uas
                        ON uas.article_id = a.id AND uas.user_id = ?
                    WHERE a.feed_id = ?
                      AND a.user_id IS NULL
                      AND COALESCE(uas.is_read, FALSE) = FALSE
                    """,
                    (user_id, feed_id)
                )
            else:
                # Count all shared articles not marked read by user
                cursor = conn.execute(
                    """
                    SELECT COUNT(*) as count FROM articles a
                    LEFT JOIN user_article_state uas
                        ON uas.article_id = a.id AND uas.user_id = ?
                    WHERE a.user_id IS NULL
                      AND COALESCE(uas.is_read, FALSE) = FALSE
                    """,
                    (user_id,)
                )

            return cursor.fetchone()["count"]
