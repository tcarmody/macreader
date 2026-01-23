"""
Database row converters - convert SQLite rows to dataclasses.
"""

import json
import sqlite3
from datetime import datetime

from .models import (
    DBArticle,
    DBArticleChat,
    DBChatMessage,
    DBFeed,
    DBNotificationRule,
    DBNotificationHistory,
    DBUser,
    DBUserArticleState,
)


def parse_datetime(value: str | None, default: datetime | None = None) -> datetime | None:
    """
    Safely parse an ISO datetime string.

    Args:
        value: ISO format datetime string, or None
        default: Value to return if parsing fails (default: None)

    Returns:
        Parsed datetime or default value
    """
    if not value:
        return default
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return default


def row_to_article(row: sqlite3.Row) -> DBArticle:
    """Convert a database row to a DBArticle."""
    key_points = None
    if row["key_points"]:
        try:
            key_points = json.loads(row["key_points"])
        except json.JSONDecodeError:
            pass

    published_at = parse_datetime(row["published_at"])
    created_at = parse_datetime(row["created_at"], default=datetime.now())

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
        # is_read/is_bookmarked come from user_article_state via JOIN, may not be present
        is_read=safe_get_bool("is_read"),
        is_bookmarked=safe_get_bool("is_bookmarked"),
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
        user_id=safe_get_int("user_id"),
        feed_name=safe_get("feed_name"),
    )


def row_to_feed(row: sqlite3.Row) -> DBFeed:
    """Convert a database row to a DBFeed."""
    last_fetched = parse_datetime(row["last_fetched"])

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
    created_at = parse_datetime(row["created_at"], default=datetime.now())

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
    notified_at = parse_datetime(row["notified_at"], default=datetime.now())

    return DBNotificationHistory(
        id=row["id"],
        article_id=row["article_id"],
        rule_id=row["rule_id"],
        notified_at=notified_at,
        dismissed=bool(row["dismissed"]),
    )


def row_to_user(row: sqlite3.Row) -> DBUser:
    """Convert a database row to a DBUser."""
    created_at = parse_datetime(row["created_at"], default=datetime.now())
    last_login_at = parse_datetime(row["last_login_at"])

    return DBUser(
        id=row["id"],
        email=row["email"],
        name=row["name"],
        provider=row["provider"],
        created_at=created_at,
        last_login_at=last_login_at,
    )


def row_to_user_article_state(row: sqlite3.Row) -> DBUserArticleState:
    """Convert a database row to a DBUserArticleState."""
    read_at = parse_datetime(row["read_at"])
    bookmarked_at = parse_datetime(row["bookmarked_at"])

    return DBUserArticleState(
        id=row["id"],
        user_id=row["user_id"],
        article_id=row["article_id"],
        is_read=bool(row["is_read"]),
        read_at=read_at,
        is_bookmarked=bool(row["is_bookmarked"]),
        bookmarked_at=bookmarked_at,
    )


def row_to_article_chat(row: sqlite3.Row) -> DBArticleChat:
    """Convert a database row to a DBArticleChat."""
    created_at = parse_datetime(row["created_at"], default=datetime.now())
    updated_at = parse_datetime(row["updated_at"], default=datetime.now())

    return DBArticleChat(
        id=row["id"],
        article_id=row["article_id"],
        user_id=row["user_id"],
        created_at=created_at,
        updated_at=updated_at,
    )


def row_to_chat_message(row: sqlite3.Row) -> DBChatMessage:
    """Convert a database row to a DBChatMessage."""
    created_at = parse_datetime(row["created_at"], default=datetime.now())

    return DBChatMessage(
        id=row["id"],
        chat_id=row["chat_id"],
        role=row["role"],
        content=row["content"],
        model_used=row["model_used"],
        created_at=created_at,
    )
