"""
Saved search repository - per-user persistent search queries.
"""

from datetime import datetime, timezone

from .connection import DatabaseConnection
from .models import DBSavedSearch


def _row_to_saved_search(row) -> DBSavedSearch:
    return DBSavedSearch(
        id=row["id"],
        user_id=row["user_id"],
        name=row["name"],
        query=row["query"],
        include_summaries=bool(row["include_summaries"]),
        last_used_at=datetime.fromisoformat(row["last_used_at"]) if row["last_used_at"] else None,
        created_at=datetime.fromisoformat(row["created_at"]),
    )


class SavedSearchRepository:
    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_all(self, user_id: int) -> list[DBSavedSearch]:
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT * FROM saved_searches
                   WHERE user_id = ?
                   ORDER BY last_used_at DESC NULLS LAST, created_at DESC""",
                (user_id,)
            ).fetchall()
        return [_row_to_saved_search(r) for r in rows]

    def create(self, user_id: int, name: str, query: str, include_summaries: bool) -> DBSavedSearch:
        with self._db.conn() as conn:
            cursor = conn.execute(
                """INSERT INTO saved_searches (user_id, name, query, include_summaries)
                   VALUES (?, ?, ?, ?)""",
                (user_id, name, query, int(include_summaries))
            )
            row = conn.execute(
                "SELECT * FROM saved_searches WHERE id = ?", (cursor.lastrowid,)
            ).fetchone()
        return _row_to_saved_search(row)

    def delete(self, id: int, user_id: int) -> bool:
        with self._db.conn() as conn:
            cursor = conn.execute(
                "DELETE FROM saved_searches WHERE id = ? AND user_id = ?",
                (id, user_id)
            )
        return cursor.rowcount > 0

    def touch(self, id: int, user_id: int) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE saved_searches SET last_used_at = ? WHERE id = ? AND user_id = ?",
                (now, id, user_id)
            )
