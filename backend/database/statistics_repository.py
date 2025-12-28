"""
Statistics repository - reading stats and topic history operations.
"""

import hashlib
import json
from datetime import datetime, timedelta

from .connection import DatabaseConnection
from .models import DBTopicHistory


class StatisticsRepository:
    """Repository for reading statistics and topic history."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    # --- Topic History ---

    def save_topic_clustering(
        self,
        topics: list[dict],  # [{label, article_ids}]
        period_start: datetime,
        period_end: datetime
    ) -> list[int]:
        """Save topic clustering results. Returns list of new IDs."""
        ids = []
        with self._db.conn() as conn:
            for topic in topics:
                label = topic["label"]
                article_ids = topic["article_ids"]
                topic_hash = self._hash_topic(label)

                cursor = conn.execute(
                    """INSERT INTO topic_history
                       (topic_label, topic_hash, article_count, article_ids,
                        period_start, period_end)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (label, topic_hash, len(article_ids),
                     json.dumps(article_ids),
                     period_start.isoformat(), period_end.isoformat())
                )
                ids.append(cursor.lastrowid)
        return ids

    def get_topic_history(
        self,
        days: int | None = None,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
        limit: int = 100
    ) -> list[DBTopicHistory]:
        """Get topic history with flexible date filtering."""
        query = "SELECT * FROM topic_history WHERE 1=1"
        params: list = []

        if days is not None:
            cutoff = (datetime.now() - timedelta(days=days)).isoformat()
            query += " AND clustered_at >= ?"
            params.append(cutoff)
        elif start_date is not None:
            query += " AND clustered_at >= ?"
            params.append(start_date.isoformat())

        if end_date is not None:
            query += " AND clustered_at <= ?"
            params.append(end_date.isoformat())

        query += " ORDER BY clustered_at DESC LIMIT ?"
        params.append(limit)

        with self._db.conn() as conn:
            rows = conn.execute(query, params).fetchall()
            return [self._row_to_topic_history(row) for row in rows]

    def get_topic_trends(
        self,
        days: int = 30,
        top_n: int = 10
    ) -> list[dict]:
        """Get topic frequency trends over time."""
        cutoff = (datetime.now() - timedelta(days=days)).isoformat()

        with self._db.conn() as conn:
            # Get aggregated counts by topic hash
            rows = conn.execute("""
                SELECT topic_hash, topic_label, SUM(article_count) as total_count,
                       COUNT(*) as cluster_count
                FROM topic_history
                WHERE clustered_at >= ?
                GROUP BY topic_hash
                ORDER BY total_count DESC
                LIMIT ?
            """, (cutoff, top_n)).fetchall()

            return [
                {
                    "topic_hash": row["topic_hash"],
                    "label": row["topic_label"],
                    "total_count": row["total_count"],
                    "cluster_count": row["cluster_count"]
                }
                for row in rows
            ]

    def get_most_common_topics(self, limit: int = 10) -> list[dict]:
        """Get most common topics across all time."""
        with self._db.conn() as conn:
            rows = conn.execute("""
                SELECT topic_hash, topic_label, SUM(article_count) as total_count
                FROM topic_history
                GROUP BY topic_hash
                ORDER BY total_count DESC
                LIMIT ?
            """, (limit,)).fetchall()

            return [
                {
                    "label": row["topic_label"],
                    "count": row["total_count"]
                }
                for row in rows
            ]

    # --- Summarization Stats ---

    def get_summarization_stats(
        self,
        start_date: datetime | None = None,
        end_date: datetime | None = None
    ) -> dict:
        """Get summarization statistics for a period."""
        with self._db.conn() as conn:
            # Build date filter
            date_filter = ""
            params: list = []

            if start_date:
                date_filter += " AND (published_at >= ? OR (published_at IS NULL AND created_at >= ?))"
                params.extend([start_date.isoformat(), start_date.isoformat()])
            if end_date:
                date_filter += " AND (published_at <= ? OR (published_at IS NULL AND created_at <= ?))"
                params.extend([end_date.isoformat(), end_date.isoformat()])

            # Total articles in period
            total = conn.execute(
                f"SELECT COUNT(*) as cnt FROM articles WHERE 1=1 {date_filter}",
                params
            ).fetchone()["cnt"]

            # Summarized articles in period
            summarized = conn.execute(
                f"SELECT COUNT(*) as cnt FROM articles WHERE summary_full IS NOT NULL {date_filter}",
                params
            ).fetchone()["cnt"]

            # Model breakdown
            model_rows = conn.execute(
                f"""SELECT model_used, COUNT(*) as cnt
                    FROM articles
                    WHERE model_used IS NOT NULL {date_filter}
                    GROUP BY model_used
                    ORDER BY cnt DESC""",
                params
            ).fetchall()
            model_breakdown = {row["model_used"]: row["cnt"] for row in model_rows}

            # Calculate averages
            days_in_period = 1
            if start_date and end_date:
                days_in_period = max(1, (end_date - start_date).days)
            elif start_date:
                days_in_period = max(1, (datetime.now() - start_date).days)

            avg_per_day = summarized / days_in_period if days_in_period > 0 else 0
            avg_per_week = avg_per_day * 7

            return {
                "total_articles": total,
                "summarized_articles": summarized,
                "summarization_rate": summarized / total if total > 0 else 0,
                "model_breakdown": model_breakdown,
                "avg_per_day": round(avg_per_day, 2),
                "avg_per_week": round(avg_per_week, 2),
                "period_start": start_date.isoformat() if start_date else None,
                "period_end": end_date.isoformat() if end_date else datetime.now().isoformat()
            }

    # --- Reading Stats ---

    def get_reading_stats(
        self,
        start_date: datetime | None = None,
        end_date: datetime | None = None
    ) -> dict:
        """Get reading statistics for a period."""
        with self._db.conn() as conn:
            # Build date filter for read_at
            date_filter = ""
            params: list = []

            if start_date:
                date_filter += " AND read_at >= ?"
                params.append(start_date.isoformat())
            if end_date:
                date_filter += " AND read_at <= ?"
                params.append(end_date.isoformat())

            # Articles read in period
            articles_read = conn.execute(
                f"SELECT COUNT(*) as cnt FROM articles WHERE is_read = 1 {date_filter}",
                params
            ).fetchone()["cnt"]

            # Total reading time
            reading_time = conn.execute(
                f"""SELECT COALESCE(SUM(reading_time_minutes), 0) as total
                    FROM articles WHERE is_read = 1 {date_filter}""",
                params
            ).fetchone()["total"]

            # Average reading time
            avg_reading = reading_time / articles_read if articles_read > 0 else 0

            # Bookmarks added in period (reusing date range on bookmarked_at)
            bookmark_params: list = []
            bookmark_filter = ""
            if start_date:
                bookmark_filter += " AND bookmarked_at >= ?"
                bookmark_params.append(start_date.isoformat())
            if end_date:
                bookmark_filter += " AND bookmarked_at <= ?"
                bookmark_params.append(end_date.isoformat())

            bookmarks_added = conn.execute(
                f"SELECT COUNT(*) as cnt FROM articles WHERE is_bookmarked = 1 {bookmark_filter}",
                bookmark_params
            ).fetchone()["cnt"]

            # Read by day (last 14 days max for chart)
            read_by_day = {}
            day_rows = conn.execute(
                f"""SELECT DATE(read_at) as day, COUNT(*) as cnt
                    FROM articles
                    WHERE is_read = 1 AND read_at IS NOT NULL {date_filter}
                    GROUP BY DATE(read_at)
                    ORDER BY day DESC
                    LIMIT 14""",
                params
            ).fetchall()
            for row in day_rows:
                if row["day"]:
                    read_by_day[row["day"]] = row["cnt"]

            # Read by feed
            read_by_feed = {}
            feed_rows = conn.execute(
                f"""SELECT f.name, COUNT(*) as cnt
                    FROM articles a
                    JOIN feeds f ON a.feed_id = f.id
                    WHERE a.is_read = 1 {date_filter}
                    GROUP BY f.id
                    ORDER BY cnt DESC
                    LIMIT 10""",
                params
            ).fetchall()
            for row in feed_rows:
                read_by_feed[row["name"]] = row["cnt"]

            return {
                "articles_read": articles_read,
                "total_reading_time_minutes": reading_time,
                "avg_reading_time_minutes": round(avg_reading, 1),
                "bookmarks_added": bookmarks_added,
                "read_by_day": read_by_day,
                "read_by_feed": read_by_feed
            }

    # --- Helpers ---

    def _hash_topic(self, label: str) -> str:
        """Create a normalized hash for a topic label."""
        normalized = label.lower().strip()
        return hashlib.md5(normalized.encode()).hexdigest()[:12]

    def _row_to_topic_history(self, row) -> DBTopicHistory:
        """Convert database row to DBTopicHistory."""
        return DBTopicHistory(
            id=row["id"],
            topic_label=row["topic_label"],
            topic_hash=row["topic_hash"],
            article_count=row["article_count"],
            article_ids=json.loads(row["article_ids"]) if row["article_ids"] else [],
            clustered_at=datetime.fromisoformat(row["clustered_at"]) if row["clustered_at"] else datetime.now(),
            period_start=datetime.fromisoformat(row["period_start"]) if row["period_start"] else datetime.now(),
            period_end=datetime.fromisoformat(row["period_end"]) if row["period_end"] else datetime.now()
        )
