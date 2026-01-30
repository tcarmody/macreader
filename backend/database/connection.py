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
        """Get database connection with row factory and performance optimizations."""
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        # Enable foreign key constraints
        connection.execute("PRAGMA foreign_keys = ON")
        # Performance optimizations for better concurrency and throughput
        connection.execute("PRAGMA journal_mode = WAL")  # Allow concurrent reads during writes
        connection.execute("PRAGMA synchronous = NORMAL")  # Faster writes, still safe with WAL
        connection.execute("PRAGMA cache_size = -64000")  # 64MB cache (negative = KB)
        connection.execute("PRAGMA temp_store = MEMORY")  # Store temp tables in memory
        connection.execute("PRAGMA mmap_size = 268435456")  # 256MB memory-mapped I/O
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
                    -- Note: is_read/is_bookmarked are now per-user in user_article_state table
                    published_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                -- Users table for multi-user support
                CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT UNIQUE NOT NULL,
                    name TEXT,
                    provider TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    last_login_at TIMESTAMP
                );

                -- Per-user article state (read/bookmark status)
                CREATE TABLE IF NOT EXISTS user_article_state (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
                    is_read BOOLEAN DEFAULT FALSE,
                    read_at TIMESTAMP,
                    is_bookmarked BOOLEAN DEFAULT FALSE,
                    bookmarked_at TIMESTAMP,
                    UNIQUE(user_id, article_id)
                );

                CREATE INDEX IF NOT EXISTS idx_articles_feed ON articles(feed_id);
                CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published_at DESC);
                -- Composite index for efficient feed+date queries
                CREATE INDEX IF NOT EXISTS idx_articles_feed_published ON articles(feed_id, published_at DESC);
                -- Note: is_read/is_bookmarked indexes are now on user_article_state
                CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
                CREATE INDEX IF NOT EXISTS idx_user_article_state_user ON user_article_state(user_id);
                CREATE INDEX IF NOT EXISTS idx_user_article_state_lookup ON user_article_state(user_id, article_id);
                CREATE INDEX IF NOT EXISTS idx_user_article_state_unread ON user_article_state(user_id, is_read);
                CREATE INDEX IF NOT EXISTS idx_user_article_state_bookmarked ON user_article_state(user_id, is_bookmarked);
                -- Composite index for efficient unread count queries
                CREATE INDEX IF NOT EXISTS idx_user_article_state_composite ON user_article_state(user_id, article_id, is_read);
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

            # Multi-user support: add user_id to articles for library item ownership
            # RSS articles have user_id = NULL (shared), library items have user_id set
            self._migrate_add_column(connection, "articles", "user_id", "INTEGER REFERENCES users(id) ON DELETE CASCADE")

            # Store original feed name for archived articles (when feed is deleted but article is preserved)
            self._migrate_add_column(connection, "articles", "feed_name", "TEXT")

            # Related links feature (Exa neural search)
            self._migrate_add_column(connection, "articles", "related_links", "TEXT")
            self._migrate_add_column(connection, "articles", "extracted_keywords", "TEXT")

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

                -- Article chat for refining summaries and Q&A
                CREATE TABLE IF NOT EXISTS article_chats (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(article_id, user_id)
                );

                CREATE TABLE IF NOT EXISTS chat_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    chat_id INTEGER NOT NULL REFERENCES article_chats(id) ON DELETE CASCADE,
                    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                    content TEXT NOT NULL,
                    model_used TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_article_chats_article ON article_chats(article_id);
                CREATE INDEX IF NOT EXISTS idx_article_chats_user ON article_chats(user_id);
                CREATE INDEX IF NOT EXISTS idx_chat_messages_chat ON chat_messages(chat_id, created_at);
            """)

            # Migrate existing read/bookmark state from articles table to user_article_state
            # This handles databases that were created before multi-user support was added
            self._migrate_article_state_to_user_state(connection)

    def _migrate_article_state_to_user_state(self, conn: sqlite3.Connection):
        """
        Migrate is_read/is_bookmarked from articles table to user_article_state.

        For databases created before multi-user support, read/bookmark state was stored
        directly in the articles table. This migration copies that state to user_article_state
        for a default user (id=1), preserving existing read/bookmark status.
        """
        # Check if articles table has the old is_read column
        cursor = conn.execute("PRAGMA table_info(articles)")
        columns = [row[1] for row in cursor.fetchall()]
        if "is_read" not in columns:
            return  # New database, no migration needed

        # Check if migration is needed: user_article_state is empty but articles has state
        state_count = conn.execute("SELECT COUNT(*) FROM user_article_state").fetchone()[0]
        if state_count > 0:
            return  # Already has data, migration not needed

        # Check if there's any state to migrate
        has_state = conn.execute("""
            SELECT COUNT(*) FROM articles
            WHERE (is_read = 1 OR is_bookmarked = 1)
              AND user_id IS NULL
        """).fetchone()[0]
        if has_state == 0:
            return  # No state to migrate

        # Ensure default user exists (id=1)
        existing_user = conn.execute("SELECT id FROM users WHERE id = 1").fetchone()
        if not existing_user:
            conn.execute(
                "INSERT INTO users (id, email, name, provider) VALUES (1, 'default@local', 'Default User', 'local')"
            )

        # Migrate read/bookmark state to user_article_state for user_id=1
        conn.execute("""
            INSERT INTO user_article_state (user_id, article_id, is_read, read_at, is_bookmarked, bookmarked_at)
            SELECT
                1,
                id,
                COALESCE(is_read, 0),
                read_at,
                COALESCE(is_bookmarked, 0),
                bookmarked_at
            FROM articles
            WHERE (is_read = 1 OR is_bookmarked = 1)
              AND user_id IS NULL
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
