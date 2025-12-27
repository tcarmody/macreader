"""
Notification repository - CRUD operations for notification rules and history.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_notification_rule, row_to_notification_history
from .models import DBNotificationRule, DBNotificationHistory


class NotificationRepository:
    """Repository for notification operations."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    # --- Rules CRUD ---

    def add_rule(
        self,
        name: str,
        feed_id: int | None = None,
        keyword: str | None = None,
        author: str | None = None,
        priority: str = "normal",
    ) -> int:
        """Add a new notification rule. Returns rule ID."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                """INSERT INTO notification_rules
                   (name, feed_id, keyword, author, priority, enabled)
                   VALUES (?, ?, ?, ?, ?, 1)""",
                (name, feed_id, keyword, author, priority)
            )
            return cursor.lastrowid

    def get_rule(self, rule_id: int) -> DBNotificationRule | None:
        """Get a single rule by ID."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM notification_rules WHERE id = ?",
                (rule_id,)
            ).fetchone()
            return row_to_notification_rule(row) if row else None

    def get_all_rules(self, enabled_only: bool = False) -> list[DBNotificationRule]:
        """Get all notification rules."""
        with self._db.conn() as conn:
            query = "SELECT * FROM notification_rules"
            if enabled_only:
                query += " WHERE enabled = 1"
            query += " ORDER BY created_at DESC"
            rows = conn.execute(query).fetchall()
            return [row_to_notification_rule(row) for row in rows]

    def get_rules_for_feed(self, feed_id: int) -> list[DBNotificationRule]:
        """Get notification rules for a specific feed or global rules."""
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT * FROM notification_rules
                   WHERE enabled = 1 AND (feed_id IS NULL OR feed_id = ?)
                   ORDER BY priority DESC, created_at DESC""",
                (feed_id,)
            ).fetchall()
            return [row_to_notification_rule(row) for row in rows]

    def update_rule(
        self,
        rule_id: int,
        name: str | None = None,
        feed_id: int | None = None,
        clear_feed: bool = False,
        keyword: str | None = None,
        clear_keyword: bool = False,
        author: str | None = None,
        clear_author: bool = False,
        priority: str | None = None,
        enabled: bool | None = None,
    ):
        """Update a notification rule."""
        with self._db.conn() as conn:
            if name is not None:
                conn.execute(
                    "UPDATE notification_rules SET name = ? WHERE id = ?",
                    (name, rule_id)
                )
            if clear_feed:
                conn.execute(
                    "UPDATE notification_rules SET feed_id = NULL WHERE id = ?",
                    (rule_id,)
                )
            elif feed_id is not None:
                conn.execute(
                    "UPDATE notification_rules SET feed_id = ? WHERE id = ?",
                    (feed_id, rule_id)
                )
            if clear_keyword:
                conn.execute(
                    "UPDATE notification_rules SET keyword = NULL WHERE id = ?",
                    (rule_id,)
                )
            elif keyword is not None:
                conn.execute(
                    "UPDATE notification_rules SET keyword = ? WHERE id = ?",
                    (keyword, rule_id)
                )
            if clear_author:
                conn.execute(
                    "UPDATE notification_rules SET author = NULL WHERE id = ?",
                    (rule_id,)
                )
            elif author is not None:
                conn.execute(
                    "UPDATE notification_rules SET author = ? WHERE id = ?",
                    (author, rule_id)
                )
            if priority is not None:
                conn.execute(
                    "UPDATE notification_rules SET priority = ? WHERE id = ?",
                    (priority, rule_id)
                )
            if enabled is not None:
                conn.execute(
                    "UPDATE notification_rules SET enabled = ? WHERE id = ?",
                    (1 if enabled else 0, rule_id)
                )

    def delete_rule(self, rule_id: int):
        """Delete a notification rule."""
        with self._db.conn() as conn:
            conn.execute("DELETE FROM notification_rules WHERE id = ?", (rule_id,))

    # --- History operations ---

    def add_history(self, article_id: int, rule_id: int | None = None) -> int:
        """Record that a notification was sent for an article."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                """INSERT INTO notification_history (article_id, rule_id)
                   VALUES (?, ?)""",
                (article_id, rule_id)
            )
            return cursor.lastrowid

    def get_history(
        self,
        limit: int = 50,
        offset: int = 0,
        include_dismissed: bool = False
    ) -> list[DBNotificationHistory]:
        """Get notification history."""
        with self._db.conn() as conn:
            query = "SELECT * FROM notification_history"
            if not include_dismissed:
                query += " WHERE dismissed = 0"
            query += " ORDER BY notified_at DESC LIMIT ? OFFSET ?"
            rows = conn.execute(query, (limit, offset)).fetchall()
            return [row_to_notification_history(row) for row in rows]

    def was_notified(self, article_id: int) -> bool:
        """Check if an article has already been notified."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT 1 FROM notification_history WHERE article_id = ?",
                (article_id,)
            ).fetchone()
            return row is not None

    def dismiss_notification(self, history_id: int):
        """Mark a notification as dismissed."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE notification_history SET dismissed = 1 WHERE id = ?",
                (history_id,)
            )

    def dismiss_all(self):
        """Dismiss all notifications."""
        with self._db.conn() as conn:
            conn.execute("UPDATE notification_history SET dismissed = 1")

    def clear_old_history(self, days: int = 30):
        """Delete notification history older than specified days."""
        with self._db.conn() as conn:
            conn.execute(
                """DELETE FROM notification_history
                   WHERE notified_at < datetime('now', ?)""",
                (f"-{days} days",)
            )
