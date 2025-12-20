"""
Database - SQLite operations for articles and feeds.

Uses raw SQLite for simplicity (no ORM).
Includes FTS5 for full-text search.
"""

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterator
import json


@dataclass
class DBArticle:
    id: int
    feed_id: int
    url: str
    title: str
    content: str | None
    summary_short: str | None
    summary_full: str | None
    key_points: list[str] | None
    is_read: bool
    is_bookmarked: bool
    published_at: datetime | None
    created_at: datetime
    source_url: str | None = None  # Original URL for aggregator articles


@dataclass
class DBFeed:
    id: int
    url: str
    name: str
    category: str | None
    last_fetched: datetime | None
    unread_count: int = 0


class Database:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    @contextmanager
    def _conn(self) -> Iterator[sqlite3.Connection]:
        """Get database connection with row factory."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def _init_schema(self):
        """Initialize database schema."""
        with self._conn() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS feeds (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    category TEXT,
                    last_fetched TIMESTAMP,
                    fetch_error TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS articles (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
                    url TEXT UNIQUE NOT NULL,
                    source_url TEXT,
                    title TEXT NOT NULL,
                    author TEXT,
                    content TEXT,
                    content_hash TEXT,
                    summary_short TEXT,
                    summary_full TEXT,
                    key_points TEXT,
                    model_used TEXT,
                    summarized_at TIMESTAMP,
                    is_read BOOLEAN DEFAULT FALSE,
                    read_at TIMESTAMP,
                    is_bookmarked BOOLEAN DEFAULT FALSE,
                    bookmarked_at TIMESTAMP,
                    published_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_articles_feed ON articles(feed_id);
                CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published_at DESC);
                CREATE INDEX IF NOT EXISTS idx_articles_unread ON articles(is_read, published_at DESC);
                CREATE INDEX IF NOT EXISTS idx_articles_bookmarked ON articles(is_bookmarked, bookmarked_at DESC);
            """)

            # Create FTS5 virtual table if it doesn't exist
            # Check if FTS table exists first
            result = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='articles_fts'"
            ).fetchone()

            if not result:
                conn.executescript("""
                    CREATE VIRTUAL TABLE articles_fts USING fts5(
                        title,
                        content,
                        summary_full,
                        content='articles',
                        content_rowid='id'
                    );

                    CREATE TRIGGER articles_ai AFTER INSERT ON articles BEGIN
                        INSERT INTO articles_fts(rowid, title, content, summary_full)
                        VALUES (new.id, new.title, new.content, new.summary_full);
                    END;

                    CREATE TRIGGER articles_au AFTER UPDATE ON articles BEGIN
                        INSERT INTO articles_fts(articles_fts, rowid, title, content, summary_full)
                        VALUES ('delete', old.id, old.title, old.content, old.summary_full);
                        INSERT INTO articles_fts(rowid, title, content, summary_full)
                        VALUES (new.id, new.title, new.content, new.summary_full);
                    END;

                    CREATE TRIGGER articles_ad AFTER DELETE ON articles BEGIN
                        INSERT INTO articles_fts(articles_fts, rowid, title, content, summary_full)
                        VALUES ('delete', old.id, old.title, old.content, old.summary_full);
                    END;
                """)

            # Migration: Add source_url column if it doesn't exist
            self._migrate_add_column(conn, "articles", "source_url", "TEXT")

    # ─────────────────────────────────────────────────────────────
    # Feed operations
    # ─────────────────────────────────────────────────────────────

    def add_feed(self, url: str, name: str, category: str | None = None) -> int:
        """Add a new feed. Returns feed ID."""
        with self._conn() as conn:
            cursor = conn.execute(
                "INSERT INTO feeds (url, name, category) VALUES (?, ?, ?)",
                (url, name, category)
            )
            return cursor.lastrowid

    def get_feed(self, feed_id: int) -> DBFeed | None:
        """Get single feed by ID."""
        with self._conn() as conn:
            row = conn.execute(
                """SELECT f.*, COUNT(CASE WHEN a.is_read = 0 THEN 1 END) as unread_count
                   FROM feeds f
                   LEFT JOIN articles a ON f.id = a.feed_id
                   WHERE f.id = ?
                   GROUP BY f.id""",
                (feed_id,)
            ).fetchone()
            return self._row_to_feed(row) if row else None

    def get_feeds(self) -> list[DBFeed]:
        """Get all feeds with unread counts."""
        with self._conn() as conn:
            rows = conn.execute("""
                SELECT f.*, COUNT(CASE WHEN a.is_read = 0 THEN 1 END) as unread_count
                FROM feeds f
                LEFT JOIN articles a ON f.id = a.feed_id
                GROUP BY f.id
                ORDER BY f.name
            """).fetchall()
            return [self._row_to_feed(row) for row in rows]

    def update_feed(
        self,
        feed_id: int,
        name: str | None = None,
        category: str | None = None,
        clear_category: bool = False
    ):
        """Update feed details. Use clear_category=True to remove category."""
        with self._conn() as conn:
            if name is not None:
                conn.execute("UPDATE feeds SET name = ? WHERE id = ?", (name, feed_id))
            if clear_category:
                conn.execute("UPDATE feeds SET category = NULL WHERE id = ?", (feed_id,))
            elif category is not None:
                conn.execute("UPDATE feeds SET category = ? WHERE id = ?", (category, feed_id))

    def update_feed_fetched(self, feed_id: int, error: str | None = None):
        """Update feed's last fetched timestamp."""
        with self._conn() as conn:
            conn.execute(
                "UPDATE feeds SET last_fetched = ?, fetch_error = ? WHERE id = ?",
                (datetime.now().isoformat(), error, feed_id)
            )

    def delete_feed(self, feed_id: int):
        """Delete feed and its articles."""
        with self._conn() as conn:
            conn.execute("DELETE FROM feeds WHERE id = ?", (feed_id,))

    # ─────────────────────────────────────────────────────────────
    # Article operations
    # ─────────────────────────────────────────────────────────────

    def add_article(
        self,
        feed_id: int,
        url: str,
        title: str,
        content: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
        content_hash: str | None = None,
        source_url: str | None = None
    ) -> int | None:
        """Add a new article. Returns article ID or None if duplicate."""
        with self._conn() as conn:
            try:
                cursor = conn.execute(
                    """INSERT INTO articles
                       (feed_id, url, title, content, author, published_at, content_hash, source_url)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (feed_id, url, title, content, author,
                     published_at.isoformat() if published_at else None,
                     content_hash, source_url)
                )
                return cursor.lastrowid
            except sqlite3.IntegrityError:
                # Duplicate URL
                return None

    def get_articles(
        self,
        feed_id: int | None = None,
        unread_only: bool = False,
        bookmarked_only: bool = False,
        limit: int = 50,
        offset: int = 0
    ) -> list[DBArticle]:
        """Get articles with optional filters."""
        query = "SELECT * FROM articles WHERE 1=1"
        params: list = []

        if feed_id is not None:
            query += " AND feed_id = ?"
            params.append(feed_id)
        if unread_only:
            query += " AND is_read = 0"
        if bookmarked_only:
            query += " AND is_bookmarked = 1"

        query += " ORDER BY published_at DESC NULLS LAST, created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        with self._conn() as conn:
            rows = conn.execute(query, params).fetchall()
            return [self._row_to_article(row) for row in rows]

    def get_article(self, article_id: int) -> DBArticle | None:
        """Get single article by ID."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE id = ?", (article_id,)
            ).fetchone()
            return self._row_to_article(row) if row else None

    def get_article_by_url(self, url: str) -> DBArticle | None:
        """Get article by URL."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE url = ?", (url,)
            ).fetchone()
            return self._row_to_article(row) if row else None

    def update_article_content(self, article_id: int, content: str):
        """Update article content."""
        with self._conn() as conn:
            conn.execute(
                "UPDATE articles SET content = ? WHERE id = ?",
                (content, article_id)
            )

    def update_article_source_url(self, article_id: int, source_url: str):
        """Update article source URL (for aggregator articles)."""
        with self._conn() as conn:
            conn.execute(
                "UPDATE articles SET source_url = ? WHERE id = ?",
                (source_url, article_id)
            )

    def update_summary(
        self,
        article_id: int,
        summary_short: str,
        summary_full: str,
        key_points: list[str],
        model_used: str
    ):
        """Update article summary."""
        with self._conn() as conn:
            conn.execute(
                """UPDATE articles SET
                   summary_short = ?, summary_full = ?, key_points = ?,
                   model_used = ?, summarized_at = ?
                   WHERE id = ?""",
                (summary_short, summary_full, json.dumps(key_points),
                 model_used, datetime.now().isoformat(), article_id)
            )

    def mark_read(self, article_id: int, is_read: bool = True):
        """Mark article as read/unread."""
        with self._conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ? WHERE id = ?",
                (is_read, read_at, article_id)
            )

    def toggle_bookmark(self, article_id: int) -> bool:
        """Toggle bookmark status. Returns new status."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT is_bookmarked FROM articles WHERE id = ?", (article_id,)
            ).fetchone()
            if not row:
                return False
            new_status = not row["is_bookmarked"]
            bookmarked_at = datetime.now().isoformat() if new_status else None
            conn.execute(
                "UPDATE articles SET is_bookmarked = ?, bookmarked_at = ? WHERE id = ?",
                (new_status, bookmarked_at, article_id)
            )
            return new_status

    def bulk_mark_read(self, article_ids: list[int], is_read: bool = True):
        """Mark multiple articles as read/unread."""
        if not article_ids:
            return
        with self._conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            placeholders = ",".join("?" * len(article_ids))
            conn.execute(
                f"UPDATE articles SET is_read = ?, read_at = ? WHERE id IN ({placeholders})",
                [is_read, read_at] + article_ids
            )

    def mark_feed_read(self, feed_id: int, is_read: bool = True) -> int:
        """Mark all articles in a feed as read/unread. Returns count updated."""
        with self._conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            cursor = conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ? WHERE feed_id = ?",
                (is_read, read_at, feed_id)
            )
            return cursor.rowcount

    def mark_all_read(self, is_read: bool = True) -> int:
        """Mark all articles as read/unread. Returns count updated."""
        with self._conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            cursor = conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ?",
                (is_read, read_at)
            )
            return cursor.rowcount

    def bulk_delete_feeds(self, feed_ids: list[int]):
        """Delete multiple feeds and their articles."""
        if not feed_ids:
            return
        with self._conn() as conn:
            placeholders = ",".join("?" * len(feed_ids))
            conn.execute(f"DELETE FROM feeds WHERE id IN ({placeholders})", feed_ids)

    def search(self, query: str, limit: int = 20) -> list[DBArticle]:
        """Full-text search across articles."""
        with self._conn() as conn:
            rows = conn.execute("""
                SELECT a.* FROM articles a
                JOIN articles_fts fts ON a.id = fts.rowid
                WHERE articles_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, (query, limit)).fetchall()
            return [self._row_to_article(row) for row in rows]

    def get_unread_count(self, feed_id: int | None = None) -> int:
        """Get count of unread articles."""
        with self._conn() as conn:
            if feed_id is not None:
                row = conn.execute(
                    "SELECT COUNT(*) as count FROM articles WHERE feed_id = ? AND is_read = 0",
                    (feed_id,)
                ).fetchone()
            else:
                row = conn.execute(
                    "SELECT COUNT(*) as count FROM articles WHERE is_read = 0"
                ).fetchone()
            return row["count"] if row else 0

    def get_articles_grouped_by_date(
        self,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[str, list[DBArticle]]:
        """Get articles grouped by date (YYYY-MM-DD)."""
        articles = self.get_articles(unread_only=unread_only, limit=limit)
        grouped: dict[str, list[DBArticle]] = {}
        for article in articles:
            date_key = (article.published_at or article.created_at).strftime("%Y-%m-%d")
            if date_key not in grouped:
                grouped[date_key] = []
            grouped[date_key].append(article)
        return grouped

    def get_articles_grouped_by_feed(
        self,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[int, list[DBArticle]]:
        """Get articles grouped by feed ID."""
        articles = self.get_articles(unread_only=unread_only, limit=limit)
        grouped: dict[int, list[DBArticle]] = {}
        for article in articles:
            if article.feed_id not in grouped:
                grouped[article.feed_id] = []
            grouped[article.feed_id].append(article)
        return grouped

    # ─────────────────────────────────────────────────────────────
    # Settings operations
    # ─────────────────────────────────────────────────────────────

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        """Get a setting value."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT value FROM settings WHERE key = ?", (key,)
            ).fetchone()
            return row["value"] if row else default

    def set_setting(self, key: str, value: str):
        """Set a setting value."""
        with self._conn() as conn:
            conn.execute(
                """INSERT INTO settings (key, value, updated_at)
                   VALUES (?, ?, ?)
                   ON CONFLICT(key) DO UPDATE SET
                   value = excluded.value, updated_at = excluded.updated_at""",
                (key, value, datetime.now().isoformat())
            )

    def get_all_settings(self) -> dict[str, str]:
        """Get all settings as a dictionary."""
        with self._conn() as conn:
            rows = conn.execute("SELECT key, value FROM settings").fetchall()
            return {row["key"]: row["value"] for row in rows}

    # ─────────────────────────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────────────────────────

    def _migrate_add_column(
        self,
        conn: sqlite3.Connection,
        table: str,
        column: str,
        column_type: str
    ):
        """Add a column to a table if it doesn't exist."""
        cursor = conn.execute(f"PRAGMA table_info({table})")
        columns = [row[1] for row in cursor.fetchall()]
        if column not in columns:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {column_type}")

    def _row_to_article(self, row: sqlite3.Row) -> DBArticle:
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

        # Handle source_url - may not exist in older databases during migration
        try:
            source_url = row["source_url"]
        except (IndexError, KeyError):
            source_url = None

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
            source_url=source_url
        )

    def _row_to_feed(self, row: sqlite3.Row) -> DBFeed:
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

        return DBFeed(
            id=row["id"],
            url=row["url"],
            name=row["name"],
            category=row["category"],
            last_fetched=last_fetched,
            unread_count=unread_count
        )
