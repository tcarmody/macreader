"""
Gmail repository - operations for Gmail IMAP configuration.
"""

import sqlite3
from datetime import datetime

from .connection import DatabaseConnection


class GmailRepository:
    """Repository for Gmail configuration."""

    def __init__(self, db: DatabaseConnection):
        self._db = db
        self._ensure_schema()

    def _ensure_schema(self):
        """Ensure Gmail configuration table exists."""
        with self._db.conn() as conn:
            self._init_schema(conn)

    def _init_schema(self, conn: sqlite3.Connection):
        """Initialize Gmail configuration table."""
        conn.execute("""
            CREATE TABLE IF NOT EXISTS gmail_config (
                id INTEGER PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                access_token TEXT NOT NULL,
                refresh_token TEXT NOT NULL,
                token_expires_at TIMESTAMP NOT NULL,
                monitored_label TEXT DEFAULT 'Newsletters',
                last_fetched_uid INTEGER DEFAULT 0,
                poll_interval_minutes INTEGER DEFAULT 30,
                is_enabled BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

    def save_config(
        self,
        email: str,
        access_token: str,
        refresh_token: str,
        token_expires_at: datetime,
        monitored_label: str = "Newsletters",
        poll_interval_minutes: int = 30,
    ) -> int:
        """Save Gmail configuration. Returns config ID."""
        with self._db.conn() as conn:
            self._init_schema(conn)

            # Delete any existing config (single account support)
            conn.execute("DELETE FROM gmail_config")

            cursor = conn.execute(
                """INSERT INTO gmail_config
                   (email, access_token, refresh_token, token_expires_at,
                    monitored_label, poll_interval_minutes)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (email, access_token, refresh_token, token_expires_at.isoformat(),
                 monitored_label, poll_interval_minutes)
            )
            return cursor.lastrowid

    def get_config(self) -> dict | None:
        """Get Gmail configuration if exists."""
        with self._db.conn() as conn:
            self._init_schema(conn)
            row = conn.execute("SELECT * FROM gmail_config LIMIT 1").fetchone()
            if not row:
                return None

            return {
                "id": row["id"],
                "email": row["email"],
                "access_token": row["access_token"],
                "refresh_token": row["refresh_token"],
                "token_expires_at": row["token_expires_at"],
                "monitored_label": row["monitored_label"],
                "last_fetched_uid": row["last_fetched_uid"],
                "poll_interval_minutes": row["poll_interval_minutes"],
                "is_enabled": bool(row["is_enabled"]),
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            }

    def update_tokens(
        self,
        access_token: str,
        refresh_token: str,
        expires_at: datetime,
    ):
        """Update Gmail OAuth tokens."""
        with self._db.conn() as conn:
            conn.execute(
                """UPDATE gmail_config SET
                   access_token = ?, refresh_token = ?, token_expires_at = ?,
                   updated_at = ?""",
                (access_token, refresh_token, expires_at.isoformat(),
                 datetime.now().isoformat())
            )

    def update_config(
        self,
        monitored_label: str | None = None,
        poll_interval_minutes: int | None = None,
        is_enabled: bool | None = None,
    ):
        """Update Gmail configuration settings."""
        updates = []
        params = []

        if monitored_label is not None:
            updates.append("monitored_label = ?")
            params.append(monitored_label)
        if poll_interval_minutes is not None:
            updates.append("poll_interval_minutes = ?")
            params.append(poll_interval_minutes)
        if is_enabled is not None:
            updates.append("is_enabled = ?")
            params.append(is_enabled)

        if not updates:
            return

        updates.append("updated_at = ?")
        params.append(datetime.now().isoformat())

        with self._db.conn() as conn:
            conn.execute(
                f"UPDATE gmail_config SET {', '.join(updates)}",
                params
            )

    def update_last_fetched_uid(self, uid: int):
        """Update the last fetched UID for Gmail polling."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE gmail_config SET last_fetched_uid = ?, updated_at = ?",
                (uid, datetime.now().isoformat())
            )

    def delete_config(self):
        """Delete Gmail configuration (disconnect)."""
        with self._db.conn() as conn:
            conn.execute("DELETE FROM gmail_config")
