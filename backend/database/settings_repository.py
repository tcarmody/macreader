"""
Settings repository - operations for app settings.
"""

from datetime import datetime

from .connection import DatabaseConnection


class SettingsRepository:
    """Repository for application settings."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get(self, key: str, default: str | None = None) -> str | None:
        """Get a setting value."""
        with self._db.conn() as conn:
            row = conn.execute(
                "SELECT value FROM settings WHERE key = ?", (key,)
            ).fetchone()
            return row["value"] if row else default

    def set(self, key: str, value: str):
        """Set a setting value."""
        with self._db.conn() as conn:
            conn.execute(
                """INSERT INTO settings (key, value, updated_at)
                   VALUES (?, ?, ?)
                   ON CONFLICT(key) DO UPDATE SET
                   value = excluded.value, updated_at = excluded.updated_at""",
                (key, value, datetime.now().isoformat())
            )

    def get_all(self) -> dict[str, str]:
        """Get all settings as a dictionary."""
        with self._db.conn() as conn:
            rows = conn.execute("SELECT key, value FROM settings").fetchall()
            return {row["key"]: row["value"] for row in rows}
