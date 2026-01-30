"""
Article repository - CRUD operations for articles.
"""

import json
from datetime import datetime, timedelta

from .connection import DatabaseConnection
from .converters import row_to_article
from .models import DBArticle


class ArticleRepository:
    """Repository for article operations."""

    # Explicit column list for articles table, excluding is_read/is_bookmarked/read_at/bookmarked_at
    # which are now stored in user_article_state. This prevents column name conflicts when
    # joining with user_article_state and using COALESCE for per-user state.
    ARTICLE_COLUMNS = """
        a.id, a.feed_id, a.url, a.title, a.author, a.content, a.content_hash,
        a.summary_short, a.summary_full, a.key_points, a.model_used, a.summarized_at,
        a.published_at, a.created_at, a.source_url, a.content_type, a.file_name,
        a.file_path, a.reading_time_minutes, a.word_count, a.featured_image,
        a.has_code_blocks, a.site_name, a.user_id, a.feed_name, a.related_links,
        a.extracted_keywords, a.related_links_error
    """.strip()

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def add(
        self,
        feed_id: int,
        url: str,
        title: str,
        content: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
        content_hash: str | None = None,
        source_url: str | None = None,
        reading_time_minutes: int | None = None,
        word_count: int | None = None,
        featured_image: str | None = None,
        has_code_blocks: bool = False,
        site_name: str | None = None,
    ) -> int | None:
        """Add a new article. Returns article ID or None if duplicate."""
        with self._db.conn() as conn:
            try:
                cursor = conn.execute(
                    """INSERT INTO articles
                       (feed_id, url, title, content, author, published_at, content_hash, source_url,
                        reading_time_minutes, word_count, featured_image, has_code_blocks, site_name)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (feed_id, url, title, content, author,
                     published_at.isoformat() if published_at else None,
                     content_hash, source_url,
                     reading_time_minutes, word_count, featured_image, has_code_blocks, site_name)
                )
                return cursor.lastrowid
            except Exception:
                # Duplicate URL
                return None

    def get(self, article_id: int) -> DBArticle | None:
        """Get single article by ID (without user-specific state)."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE id = ?", (article_id,)
            ).fetchone()
            return row_to_article(row) if row else None

    def get_with_user_state(self, article_id: int, user_id: int) -> DBArticle | None:
        """Get single article by ID with user-specific read/bookmark state."""
        with self._db.conn() as conn:
            row = conn.execute(f"""
                SELECT {self.ARTICLE_COLUMNS},
                       COALESCE(uas.is_read, 0) as is_read,
                       COALESCE(uas.is_bookmarked, 0) as is_bookmarked,
                       uas.read_at,
                       uas.bookmarked_at
                FROM articles a
                LEFT JOIN user_article_state uas
                    ON a.id = uas.article_id AND uas.user_id = ?
                WHERE a.id = ?
            """, (user_id, article_id)).fetchone()
            return row_to_article(row) if row else None

    def get_by_url(self, url: str) -> DBArticle | None:
        """Get article by URL."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE url = ?", (url,)
            ).fetchone()
            return row_to_article(row) if row else None

    # Valid sort options mapped to SQL ORDER BY clauses
    # Note: is_read now comes from user_article_state via COALESCE
    SORT_OPTIONS = {
        "newest": "a.published_at DESC NULLS LAST, a.created_at DESC",
        "oldest": "a.published_at ASC NULLS LAST, a.created_at ASC",
        "unread_first": "COALESCE(uas.is_read, 0) ASC, a.published_at DESC NULLS LAST, a.created_at DESC",
        "title_asc": "a.title ASC",
        "title_desc": "a.title DESC",
    }

    def get_many(
        self,
        user_id: int,
        feed_id: int | None = None,
        unread_only: bool = False,
        bookmarked_only: bool = False,
        summarized_only: bool | None = None,
        sort_by: str = "newest",
        limit: int = 50,
        offset: int = 0
    ) -> list[DBArticle]:
        """
        Get articles with optional filters, including per-user read/bookmark state.

        Args:
            user_id: The user ID for per-user state lookup
            feed_id: Optional feed ID to filter by
            unread_only: Only return unread articles (per user's state)
            bookmarked_only: Only return bookmarked articles (per user's state)
            summarized_only: Filter by summarization status
            sort_by: Sort order
            limit: Maximum number of articles to return
            offset: Number of articles to skip
        """
        # Join with user_article_state for per-user read/bookmark status
        # Use COALESCE to default to 0 (unread) when no state record exists
        # Note: We use explicit column list (ARTICLE_COLUMNS) instead of a.* to avoid
        # column name conflicts with the old is_read/is_bookmarked columns in articles table
        query = f"""
            SELECT {self.ARTICLE_COLUMNS},
                   COALESCE(uas.is_read, 0) as is_read,
                   COALESCE(uas.is_bookmarked, 0) as is_bookmarked,
                   uas.read_at,
                   uas.bookmarked_at
            FROM articles a
            LEFT JOIN user_article_state uas
                ON uas.article_id = a.id AND uas.user_id = ?
            WHERE a.user_id IS NULL
        """
        params: list = [user_id]

        if feed_id is not None:
            query += " AND a.feed_id = ?"
            params.append(feed_id)
        if unread_only:
            query += " AND COALESCE(uas.is_read, 0) = 0"
        if bookmarked_only:
            query += " AND COALESCE(uas.is_bookmarked, 0) = 1"
        if summarized_only is True:
            query += " AND a.summary_full IS NOT NULL"
        elif summarized_only is False:
            query += " AND a.summary_full IS NULL"

        # Use validated sort option or default to newest
        order_clause = self.SORT_OPTIONS.get(sort_by, self.SORT_OPTIONS["newest"])
        query += f" ORDER BY {order_clause} LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        with self._db.conn() as conn:
            rows = conn.execute(query, params).fetchall()
            return [row_to_article(row) for row in rows]

    def update_content(self, article_id: int, content: str):
        """Update article content."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE articles SET content = ? WHERE id = ?",
                (content, article_id)
            )

    def update_source_url(self, article_id: int, source_url: str):
        """Update article source URL (for aggregator articles)."""
        with self._db.conn() as conn:
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
        with self._db.conn() as conn:
            conn.execute(
                """UPDATE articles SET
                   summary_short = ?, summary_full = ?, key_points = ?,
                   model_used = ?, summarized_at = ?
                   WHERE id = ?""",
                (summary_short, summary_full, json.dumps(key_points),
                 model_used, datetime.now().isoformat(), article_id)
            )

    # Note: mark_read, toggle_bookmark, bulk_mark_read, mark_feed_read, mark_all_read
    # have been moved to UserArticleStateRepository for per-user state management

    def search(self, query: str, limit: int = 20) -> list[DBArticle]:
        """Full-text search across articles."""
        with self._db.conn() as conn:
            rows = conn.execute("""
                SELECT a.* FROM articles a
                JOIN articles_fts fts ON a.id = fts.rowid
                WHERE articles_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, (query, limit)).fetchall()
            return [row_to_article(row) for row in rows]

    def get_duplicates(self) -> list[tuple[str, list[DBArticle]]]:
        """Find articles with duplicate content_hash across different feeds."""
        with self._db.conn() as conn:
            hash_rows = conn.execute("""
                SELECT content_hash, COUNT(*) as cnt
                FROM articles
                WHERE content_hash IS NOT NULL AND content_hash != ''
                GROUP BY content_hash
                HAVING cnt > 1
                ORDER BY cnt DESC
            """).fetchall()

            duplicates = []
            for hash_row in hash_rows:
                content_hash = hash_row["content_hash"]
                article_rows = conn.execute(
                    "SELECT * FROM articles WHERE content_hash = ? ORDER BY published_at DESC",
                    (content_hash,)
                ).fetchall()
                articles = [row_to_article(row) for row in article_rows]
                duplicates.append((content_hash, articles))

            return duplicates

    def get_duplicate_ids(self) -> set[int]:
        """Get IDs of duplicate articles (keeping the oldest/first one)."""
        duplicates = self.get_duplicates()
        ids_to_hide = set()

        for _, articles in duplicates:
            if len(articles) <= 1:
                continue
            sorted_articles = sorted(
                articles,
                key=lambda a: a.published_at or a.created_at
            )
            for article in sorted_articles[1:]:
                ids_to_hide.add(article.id)

        return ids_to_hide

    def archive_old(
        self,
        days: int = 30,
    ) -> int:
        """
        Delete shared articles older than specified days.

        Only deletes shared articles (user_id IS NULL), not library items.
        Note: With per-user state, we can no longer filter by read/bookmarked
        status since different users have different states.

        Returns count deleted.
        """
        cutoff_date = (datetime.now() - timedelta(days=days)).isoformat()

        with self._db.conn() as conn:
            # Only delete shared articles, not library items
            query = """
                DELETE FROM articles
                WHERE user_id IS NULL
                  AND (published_at < ? OR (published_at IS NULL AND created_at < ?))
            """
            cursor = conn.execute(query, (cutoff_date, cutoff_date))
            return cursor.rowcount

    def get_stats(self, user_id: int) -> dict:
        """Get statistics about articles in the database for a user."""
        now = datetime.now()
        one_week_ago = (now - timedelta(days=7)).isoformat()
        one_month_ago = (now - timedelta(days=30)).isoformat()

        with self._db.conn() as conn:
            # Total shared articles
            total = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE user_id IS NULL"
            ).fetchone()["cnt"]

            # Unread articles for this user
            unread = conn.execute("""
                SELECT COUNT(*) as cnt FROM articles a
                LEFT JOIN user_article_state uas
                    ON uas.article_id = a.id AND uas.user_id = ?
                WHERE a.user_id IS NULL
                  AND COALESCE(uas.is_read, 0) = 0
            """, (user_id,)).fetchone()["cnt"]

            # Bookmarked articles for this user
            bookmarked = conn.execute("""
                SELECT COUNT(*) as cnt FROM articles a
                LEFT JOIN user_article_state uas
                    ON uas.article_id = a.id AND uas.user_id = ?
                WHERE a.user_id IS NULL
                  AND COALESCE(uas.is_bookmarked, 0) = 1
            """, (user_id,)).fetchone()["cnt"]

            last_week = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE user_id IS NULL AND (published_at >= ? OR (published_at IS NULL AND created_at >= ?))",
                (one_week_ago, one_week_ago)
            ).fetchone()["cnt"]

            last_month = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE user_id IS NULL AND (published_at >= ? OR (published_at IS NULL AND created_at >= ?)) AND (published_at < ? OR (published_at IS NULL AND created_at < ?))",
                (one_month_ago, one_month_ago, one_week_ago, one_week_ago)
            ).fetchone()["cnt"]

            older_than_month = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE user_id IS NULL AND (published_at < ? OR (published_at IS NULL AND created_at < ?))",
                (one_month_ago, one_month_ago)
            ).fetchone()["cnt"]

            oldest = conn.execute(
                "SELECT MIN(COALESCE(published_at, created_at)) as oldest FROM articles WHERE user_id IS NULL"
            ).fetchone()["oldest"]

            return {
                "total": total,
                "unread": unread,
                "bookmarked": bookmarked,
                "last_week": last_week,
                "last_month": last_month,
                "older_than_month": older_than_month,
                "oldest_article": oldest
            }

    # Note: get_unread_count has been moved to UserArticleStateRepository

    def get_grouped_by_date(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[str, list[DBArticle]]:
        """Get articles grouped by date (YYYY-MM-DD)."""
        articles = self.get_many(user_id=user_id, unread_only=unread_only, limit=limit)
        grouped: dict[str, list[DBArticle]] = {}
        for article in articles:
            date_key = (article.published_at or article.created_at).strftime("%Y-%m-%d")
            if date_key not in grouped:
                grouped[date_key] = []
            grouped[date_key].append(article)
        return grouped

    def get_grouped_by_feed(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[int, list[DBArticle]]:
        """Get articles grouped by feed ID."""
        articles = self.get_many(user_id=user_id, unread_only=unread_only, limit=limit)
        grouped: dict[int, list[DBArticle]] = {}
        for article in articles:
            if article.feed_id not in grouped:
                grouped[article.feed_id] = []
            grouped[article.feed_id].append(article)
        return grouped
