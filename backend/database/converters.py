"""
Database row converters - convert SQLite rows to dataclasses.
"""

import json
import sqlite3
from datetime import datetime

from .models import DBArticle, DBFeed, DBNotificationRule, DBNotificationHistory


def row_to_article(row: sqlite3.Row) -> DBArticle:
    """Convert a database row to a DBArticle."""
    key_points = None
    if row["key_points"]:
        try:
            key_points = json.loads(row["key_points"])
        except json.JSONDecodeError:
            pass

    published_at = None
    if row["published_at"]:
        try:
            published_at = datetime.fromisoformat(row["published_at"])
        except ValueError:
            pass

    created_at = datetime.now()
    if row["created_at"]:
        try:
            created_at = datetime.fromisoformat(row["created_at"])
        except ValueError:
            pass

    # Handle optional columns - may not exist in older databases during migration
    def safe_get(col: str) -> str | None:
        try:
            return row[col]
        except (IndexError, KeyError):
            return None

    def safe_get_int(col: str) -> int | None:
        try:
            val = row[col]
            return int(val) if val is not None else None
        except (IndexError, KeyError, ValueError, TypeError):
            return None

    def safe_get_bool(col: str) -> bool:
        try:
            return bool(row[col])
        except (IndexError, KeyError):
            return False

    return DBArticle(
        id=row["id"],
        feed_id=row["feed_id"],
        url=row["url"],
        title=row["title"],
        content=row["content"],
        summary_short=row["summary_short"],
        summary_full=row["summary_full"],
        key_points=key_points,
        is_read=bool(row["is_read"]),
        is_bookmarked=bool(row["is_bookmarked"]),
        published_at=published_at,
        created_at=created_at,
        source_url=safe_get("source_url"),
        content_type=safe_get("content_type"),
        file_name=safe_get("file_name"),
        file_path=safe_get("file_path"),
        author=safe_get("author"),
        reading_time_minutes=safe_get_int("reading_time_minutes"),
        word_count=safe_get_int("word_count"),
        featured_image=safe_get("featured_image"),
        has_code_blocks=safe_get_bool("has_code_blocks"),
        site_name=safe_get("site_name"),
    )


def row_to_feed(row: sqlite3.Row) -> DBFeed:
    """Convert a database row to a DBFeed."""
    last_fetched = None
    if row["last_fetched"]:
        try:
            last_fetched = datetime.fromisoformat(row["last_fetched"])
        except ValueError:
            pass

    # Handle unread_count - may not be present in all queries
    try:
        unread_count = row["unread_count"] or 0
    except (IndexError, KeyError):
        unread_count = 0

    # Handle fetch_error - may not be present in all queries
    try:
        fetch_error = row["fetch_error"]
    except (IndexError, KeyError):
        fetch_error = None

    return DBFeed(
        id=row["id"],
        url=row["url"],
        name=row["name"],
        category=row["category"],
        last_fetched=last_fetched,
        fetch_error=fetch_error,
        unread_count=unread_count
    )


def row_to_notification_rule(row: sqlite3.Row) -> DBNotificationRule:
    """Convert a database row to a DBNotificationRule."""
    created_at = datetime.now()
    if row["created_at"]:
        try:
            created_at = datetime.fromisoformat(row["created_at"])
        except ValueError:
            pass

    return DBNotificationRule(
        id=row["id"],
        name=row["name"],
        feed_id=row["feed_id"],
        keyword=row["keyword"],
        author=row["author"],
        priority=row["priority"] or "normal",
        enabled=bool(row["enabled"]),
        created_at=created_at,
    )


def row_to_notification_history(row: sqlite3.Row) -> DBNotificationHistory:
    """Convert a database row to a DBNotificationHistory."""
    notified_at = datetime.now()
    if row["notified_at"]:
        try:
            notified_at = datetime.fromisoformat(row["notified_at"])
        except ValueError:
            pass

    return DBNotificationHistory(
        id=row["id"],
        article_id=row["article_id"],
        rule_id=row["rule_id"],
        notified_at=notified_at,
        dismissed=bool(row["dismissed"]),
    )
