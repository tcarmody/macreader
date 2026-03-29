"""
Digest repository — stores and retrieves assembled auto-digest results.
"""

import json
from datetime import datetime, timedelta

from .connection import DatabaseConnection
from .models import DBDigest


class DigestRepository:
    """Persistence for assembled digests."""

    def __init__(self, connection: DatabaseConnection):
        self._conn = connection

    def save(
        self,
        period: str,
        period_start: datetime,
        period_end: datetime,
        article_ids: list[int],
        title: str,
        intro: str | None,
        content: str,
        format: str,
        tone: str,
        brief_length: str,
        story_count: int,
        word_count: int,
    ) -> int:
        """Persist a digest and return its new ID."""
        with self._conn.conn() as conn:
            cursor = conn.execute(
                """
                INSERT INTO digests
                    (period, period_start, period_end, article_ids,
                     title, intro, content, format, tone, brief_length,
                     story_count, word_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    period,
                    period_start.isoformat(),
                    period_end.isoformat(),
                    json.dumps(article_ids),
                    title,
                    intro,
                    content,
                    format,
                    tone,
                    brief_length,
                    story_count,
                    word_count,
                ),
            )
            return cursor.lastrowid

    def get_latest(self, period: str, max_age_hours: int = 2) -> DBDigest | None:
        """Return the most recent digest for a period if within max_age_hours."""
        # Use the same format as SQLite's CURRENT_TIMESTAMP ('YYYY-MM-DD HH:MM:SS')
        cutoff = (datetime.now() - timedelta(hours=max_age_hours)).strftime("%Y-%m-%d %H:%M:%S")
        with self._conn.conn() as conn:
            row = conn.execute(
                """
                SELECT id, period, period_start, period_end, article_ids,
                       title, intro, content, format, tone, brief_length,
                       story_count, word_count, created_at
                FROM digests
                WHERE period = ? AND created_at >= ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (period, cutoff),
            ).fetchone()
        return self._row_to_digest(row) if row else None

    def get_by_id(self, digest_id: int) -> DBDigest | None:
        """Return a digest by primary key."""
        with self._conn.conn() as conn:
            row = conn.execute(
                """
                SELECT id, period, period_start, period_end, article_ids,
                       title, intro, content, format, tone, brief_length,
                       story_count, word_count, created_at
                FROM digests WHERE id = ?
                """,
                (digest_id,),
            ).fetchone()
        return self._row_to_digest(row) if row else None

    @staticmethod
    def _row_to_digest(row) -> DBDigest:
        return DBDigest(
            id=row["id"],
            period=row["period"],
            period_start=datetime.fromisoformat(row["period_start"]),
            period_end=datetime.fromisoformat(row["period_end"]),
            article_ids=json.loads(row["article_ids"]),
            title=row["title"],
            intro=row["intro"],
            content=row["content"],
            format=row["format"],
            tone=row["tone"],
            brief_length=row["brief_length"],
            story_count=row["story_count"],
            word_count=row["word_count"],
            created_at=datetime.fromisoformat(row["created_at"]),
        )
