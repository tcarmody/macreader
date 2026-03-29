"""
Story Group repository - storage for event-level article deduplication groups.
"""

import json
from datetime import datetime

from .connection import DatabaseConnection
from .models import DBStoryGroup


class StoryGroupRepository:
    """Repository for story groups (same-event deduplication)."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def save_groups(
        self,
        groups: list[dict],  # [{label, representative_id, member_ids}]
        period_start: datetime,
        period_end: datetime,
    ) -> list[int]:
        """Persist story groups for a period, replacing same-day groups.

        Deletes any existing story_groups whose period_start falls on the same
        calendar date, then inserts the new groups. Returns the new IDs.
        """
        ids: list[int] = []
        with self._db.conn() as conn:
            # Delete previous groups for the same date to avoid duplicates
            conn.execute(
                "DELETE FROM story_groups WHERE date(period_start) = date(?)",
                (period_start.isoformat(),),
            )

            for group in groups:
                cursor = conn.execute(
                    """INSERT INTO story_groups
                       (label, representative_id, period_start, period_end)
                       VALUES (?, ?, ?, ?)""",
                    (
                        group["label"],
                        group.get("representative_id"),
                        period_start.isoformat(),
                        period_end.isoformat(),
                    ),
                )
                group_id = cursor.lastrowid
                ids.append(group_id)

                # Insert members
                for article_id in group.get("member_ids", []):
                    conn.execute(
                        "INSERT OR IGNORE INTO story_group_members (story_group_id, article_id) VALUES (?, ?)",
                        (group_id, article_id),
                    )

        return ids

    def get_groups_for_period(
        self,
        period_start: datetime,
        period_end: datetime,
        min_size: int = 2,
    ) -> list[DBStoryGroup]:
        """Return story groups that overlap with the given period, with member_ids populated."""
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT sg.id, sg.label, sg.representative_id,
                          sg.period_start, sg.period_end, sg.created_at,
                          COUNT(sgm.article_id) AS member_count
                   FROM story_groups sg
                   JOIN story_group_members sgm ON sgm.story_group_id = sg.id
                   WHERE sg.period_start >= ? AND sg.period_end <= ?
                   GROUP BY sg.id
                   HAVING member_count >= ?
                   ORDER BY sg.created_at DESC""",
                (period_start.isoformat(), period_end.isoformat(), min_size),
            ).fetchall()

            result: list[DBStoryGroup] = []
            for row in rows:
                member_ids = self.get_members(row["id"], conn=conn)
                result.append(self._row_to_model(row, member_ids))

        return result

    def get_group_for_article(self, article_id: int) -> DBStoryGroup | None:
        """Return the most recent story group containing this article, or None."""
        with self._db.conn() as conn:
            row = conn.execute(
                """SELECT sg.id, sg.label, sg.representative_id,
                          sg.period_start, sg.period_end, sg.created_at
                   FROM story_groups sg
                   JOIN story_group_members sgm ON sgm.story_group_id = sg.id
                   WHERE sgm.article_id = ?
                   ORDER BY sg.created_at DESC
                   LIMIT 1""",
                (article_id,),
            ).fetchone()

            if row is None:
                return None

            member_ids = self.get_members(row["id"], conn=conn)
            return self._row_to_model(row, member_ids)

    def get_members(self, story_group_id: int, conn=None) -> list[int]:
        """Return article_ids for a story group."""
        def _fetch(c):
            rows = c.execute(
                "SELECT article_id FROM story_group_members WHERE story_group_id = ? ORDER BY article_id",
                (story_group_id,),
            ).fetchall()
            return [r["article_id"] for r in rows]

        if conn is not None:
            return _fetch(conn)
        with self._db.conn() as c:
            return _fetch(c)

    @staticmethod
    def _row_to_model(row, member_ids: list[int]) -> DBStoryGroup:
        return DBStoryGroup(
            id=row["id"],
            label=row["label"],
            representative_id=row["representative_id"],
            period_start=datetime.fromisoformat(row["period_start"]),
            period_end=datetime.fromisoformat(row["period_end"]),
            created_at=datetime.fromisoformat(row["created_at"]),
            member_ids=member_ids,
        )
