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
        """Get single article by ID."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE id = ?", (article_id,)
            ).fetchone()
            return row_to_article(row) if row else None

    def get_by_url(self, url: str) -> DBArticle | None:
        """Get article by URL."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM articles WHERE url = ?", (url,)
            ).fetchone()
            return row_to_article(row) if row else None

    def get_many(
        self,
        feed_id: int | None = None,
        unread_only: bool = False,
        bookmarked_only: bool = False,
        summarized_only: bool | None = None,
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
        if summarized_only is True:
            query += " AND summary_full IS NOT NULL"
        elif summarized_only is False:
            query += " AND summary_full IS NULL"

        query += " ORDER BY published_at DESC NULLS LAST, created_at DESC LIMIT ? OFFSET ?"
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

    def mark_read(self, article_id: int, is_read: bool = True):
        """Mark article as read/unread."""
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ? WHERE id = ?",
                (is_read, read_at, article_id)
            )

    def toggle_bookmark(self, article_id: int) -> bool:
        """Toggle bookmark status. Returns new status."""
        with self._db.conn() as conn:
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
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            placeholders = ",".join("?" * len(article_ids))
            conn.execute(
                f"UPDATE articles SET is_read = ?, read_at = ? WHERE id IN ({placeholders})",
                [is_read, read_at] + article_ids
            )

    def mark_feed_read(self, feed_id: int, is_read: bool = True) -> int:
        """Mark all articles in a feed as read/unread. Returns count updated."""
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            cursor = conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ? WHERE feed_id = ?",
                (is_read, read_at, feed_id)
            )
            return cursor.rowcount

    def mark_all_read(self, is_read: bool = True) -> int:
        """Mark all articles as read/unread. Returns count updated."""
        with self._db.conn() as conn:
            read_at = datetime.now().isoformat() if is_read else None
            cursor = conn.execute(
                "UPDATE articles SET is_read = ?, read_at = ?",
                (is_read, read_at)
            )
            return cursor.rowcount

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
        keep_bookmarked: bool = True,
        keep_unread: bool = False
    ) -> int:
        """Delete articles older than specified days. Returns count deleted."""
        cutoff_date = (datetime.now() - timedelta(days=days)).isoformat()

        with self._db.conn() as conn:
            query = "DELETE FROM articles WHERE published_at < ? OR (published_at IS NULL AND created_at < ?)"
            conditions = []
            if keep_bookmarked:
                conditions.append("is_bookmarked = 0")
            if keep_unread:
                conditions.append("is_read = 1")

            if conditions:
                query = f"DELETE FROM articles WHERE (published_at < ? OR (published_at IS NULL AND created_at < ?)) AND {' AND '.join(conditions)}"

            cursor = conn.execute(query, (cutoff_date, cutoff_date))
            return cursor.rowcount

    def get_stats(self) -> dict:
        """Get statistics about articles in the database."""
        now = datetime.now()
        one_week_ago = (now - timedelta(days=7)).isoformat()
        one_month_ago = (now - timedelta(days=30)).isoformat()

        with self._db.conn() as conn:
            total = conn.execute("SELECT COUNT(*) as cnt FROM articles").fetchone()["cnt"]
            unread = conn.execute("SELECT COUNT(*) as cnt FROM articles WHERE is_read = 0").fetchone()["cnt"]
            bookmarked = conn.execute("SELECT COUNT(*) as cnt FROM articles WHERE is_bookmarked = 1").fetchone()["cnt"]

            last_week = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE published_at >= ? OR (published_at IS NULL AND created_at >= ?)",
                (one_week_ago, one_week_ago)
            ).fetchone()["cnt"]

            last_month = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE (published_at >= ? OR (published_at IS NULL AND created_at >= ?)) AND (published_at < ? OR (published_at IS NULL AND created_at < ?))",
                (one_month_ago, one_month_ago, one_week_ago, one_week_ago)
            ).fetchone()["cnt"]

            older_than_month = conn.execute(
                "SELECT COUNT(*) as cnt FROM articles WHERE published_at < ? OR (published_at IS NULL AND created_at < ?)",
                (one_month_ago, one_month_ago)
            ).fetchone()["cnt"]

            oldest = conn.execute(
                "SELECT MIN(COALESCE(published_at, created_at)) as oldest FROM articles"
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

    def get_unread_count(self, feed_id: int | None = None) -> int:
        """Get count of unread articles."""
        with self._db.conn() as conn:
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

    def get_grouped_by_date(
        self,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[str, list[DBArticle]]:
        """Get articles grouped by date (YYYY-MM-DD)."""
        articles = self.get_many(unread_only=unread_only, limit=limit)
        grouped: dict[str, list[DBArticle]] = {}
        for article in articles:
            date_key = (article.published_at or article.created_at).strftime("%Y-%m-%d")
            if date_key not in grouped:
                grouped[date_key] = []
            grouped[date_key].append(article)
        return grouped

    def get_grouped_by_feed(
        self,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[int, list[DBArticle]]:
        """Get articles grouped by feed ID."""
        articles = self.get_many(unread_only=unread_only, limit=limit)
        grouped: dict[int, list[DBArticle]] = {}
        for article in articles:
            if article.feed_id not in grouped:
                grouped[article.feed_id] = []
            grouped[article.feed_id].append(article)
        return grouped
