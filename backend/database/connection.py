"""
Database connection management and schema initialization.
"""

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


class DatabaseConnection:
    """Manages database connection and schema."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    @contextmanager
    def conn(self) -> Iterator[sqlite3.Connection]:
        """Get database connection with row factory."""
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            yield connection
            connection.commit()
        finally:
            connection.close()

    def _init_schema(self):
        """Initialize database schema."""
        with self.conn() as connection:
            connection.executescript("""
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
            result = connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='articles_fts'"
            ).fetchone()

            if not result:
                connection.executescript("""
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

            # Migrations
            self._migrate_add_column(connection, "articles", "source_url", "TEXT")
            self._migrate_add_column(connection, "articles", "content_type", "TEXT")
            self._migrate_add_column(connection, "articles", "file_name", "TEXT")
            self._migrate_add_column(connection, "articles", "file_path", "TEXT")
            self._migrate_add_column(connection, "articles", "reading_time_minutes", "INTEGER")
            self._migrate_add_column(connection, "articles", "word_count", "INTEGER")
            self._migrate_add_column(connection, "articles", "featured_image", "TEXT")
            self._migrate_add_column(connection, "articles", "has_code_blocks", "BOOLEAN DEFAULT FALSE")
            self._migrate_add_column(connection, "articles", "site_name", "TEXT")

            # Create notification_rules table for smart notifications
            connection.executescript("""
                CREATE TABLE IF NOT EXISTS notification_rules (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    feed_id INTEGER REFERENCES feeds(id) ON DELETE CASCADE,
                    keyword TEXT,
                    author TEXT,
                    priority TEXT CHECK(priority IN ('high', 'normal', 'low')) DEFAULT 'normal',
                    enabled INTEGER DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS notification_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    article_id INTEGER REFERENCES articles(id) ON DELETE CASCADE,
                    rule_id INTEGER REFERENCES notification_rules(id) ON DELETE SET NULL,
                    notified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    dismissed INTEGER DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_notification_rules_enabled ON notification_rules(enabled);
                CREATE INDEX IF NOT EXISTS idx_notification_rules_feed ON notification_rules(feed_id);
                CREATE INDEX IF NOT EXISTS idx_notification_history_article ON notification_history(article_id);
                CREATE INDEX IF NOT EXISTS idx_notification_history_notified ON notification_history(notified_at DESC);

                -- Topic history for reading statistics and trend analysis
                CREATE TABLE IF NOT EXISTS topic_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    topic_label TEXT NOT NULL,
                    topic_hash TEXT NOT NULL,
                    article_count INTEGER NOT NULL,
                    article_ids TEXT NOT NULL,
                    clustered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    period_start TIMESTAMP NOT NULL,
                    period_end TIMESTAMP NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_topic_history_clustered ON topic_history(clustered_at DESC);
                CREATE INDEX IF NOT EXISTS idx_topic_history_hash ON topic_history(topic_hash);
                CREATE INDEX IF NOT EXISTS idx_topic_history_period ON topic_history(period_start, period_end);
            """)

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
