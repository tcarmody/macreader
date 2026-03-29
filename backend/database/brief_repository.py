"""
Brief repository - storage for newsletter-ready article briefs.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .models import DBBrief


class BriefRepository:
    """Repository for article briefs (newsletter-ready blurbs)."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get(self, article_id: int, length: str, tone: str) -> DBBrief | None:
        """Return a cached brief for a given article/length/tone, or None."""
        with self._db.conn() as conn:
            row = conn.execute(
                """SELECT id, article_id, length, tone, content, model_used, created_at
                   FROM article_briefs
                   WHERE article_id = ? AND length = ? AND tone = ?""",
                (article_id, length, tone),
            ).fetchone()
        if row is None:
            return None
        return self._row_to_model(row)

    def upsert(
        self,
        article_id: int,
        length: str,
        tone: str,
        content: str,
        model_used: str | None,
    ) -> None:
        """Insert or replace a brief (INSERT OR REPLACE on the unique constraint)."""
        with self._db.conn() as conn:
            conn.execute(
                """INSERT INTO article_briefs (article_id, length, tone, content, model_used, created_at)
                   VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(article_id, length, tone)
                   DO UPDATE SET content = excluded.content,
                                 model_used = excluded.model_used,
                                 created_at = excluded.created_at""",
                (article_id, length, tone, content, model_used, datetime.now().isoformat()),
            )

    def get_all_for_article(self, article_id: int) -> list[DBBrief]:
        """Return all briefs stored for an article."""
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT id, article_id, length, tone, content, model_used, created_at
                   FROM article_briefs
                   WHERE article_id = ?
                   ORDER BY length, tone""",
                (article_id,),
            ).fetchall()
        return [self._row_to_model(r) for r in rows]

    @staticmethod
    def _row_to_model(row) -> DBBrief:
        return DBBrief(
            id=row["id"],
            article_id=row["article_id"],
            length=row["length"],
            tone=row["tone"],
            content=row["content"],
            model_used=row["model_used"],
            created_at=datetime.fromisoformat(row["created_at"]) if row["created_at"] else datetime.now(),
        )
