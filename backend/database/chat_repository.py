"""
Chat repository - CRUD operations for article chats and messages.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_article_chat, row_to_chat_message
from .models import DBArticleChat, DBChatMessage


class ChatRepository:
    """Repository for article chat operations."""

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_or_create_chat(self, article_id: int, user_id: int) -> DBArticleChat:
        """Get existing chat or create a new one for this article/user pair."""
        with self._db.conn() as conn:
            # Try to get existing chat
            row = conn.execute(
                """SELECT * FROM article_chats
                   WHERE article_id = ? AND user_id = ?""",
                (article_id, user_id)
            ).fetchone()

            if row:
                return row_to_article_chat(row)

            # Create new chat
            now = datetime.now().isoformat()
            cursor = conn.execute(
                """INSERT INTO article_chats (article_id, user_id, created_at, updated_at)
                   VALUES (?, ?, ?, ?)""",
                (article_id, user_id, now, now)
            )
            chat_id = cursor.lastrowid

            row = conn.execute(
                "SELECT * FROM article_chats WHERE id = ?",
                (chat_id,)
            ).fetchone()
            return row_to_article_chat(row)

    def get_chat(self, article_id: int, user_id: int) -> DBArticleChat | None:
        """Get chat for article/user pair if it exists."""
        with self._db.conn() as conn:
            row = conn.execute(
                """SELECT * FROM article_chats
                   WHERE article_id = ? AND user_id = ?""",
                (article_id, user_id)
            ).fetchone()
            return row_to_article_chat(row) if row else None

    def add_message(
        self,
        chat_id: int,
        role: str,
        content: str,
        model_used: str | None = None
    ) -> DBChatMessage:
        """Add a message to a chat."""
        with self._db.conn() as conn:
            now = datetime.now().isoformat()

            # Insert message
            cursor = conn.execute(
                """INSERT INTO chat_messages (chat_id, role, content, model_used, created_at)
                   VALUES (?, ?, ?, ?, ?)""",
                (chat_id, role, content, model_used, now)
            )
            message_id = cursor.lastrowid

            # Update chat's updated_at
            conn.execute(
                "UPDATE article_chats SET updated_at = ? WHERE id = ?",
                (now, chat_id)
            )

            row = conn.execute(
                "SELECT * FROM chat_messages WHERE id = ?",
                (message_id,)
            ).fetchone()
            return row_to_chat_message(row)

    def get_messages(
        self,
        chat_id: int,
        limit: int = 50,
        offset: int = 0
    ) -> list[DBChatMessage]:
        """Get messages for a chat, ordered by creation time."""
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT * FROM chat_messages
                   WHERE chat_id = ?
                   ORDER BY created_at ASC
                   LIMIT ? OFFSET ?""",
                (chat_id, limit, offset)
            ).fetchall()
            return [row_to_chat_message(row) for row in rows]

    def get_message_count(self, chat_id: int) -> int:
        """Get total number of messages in a chat."""
        with self._db.conn() as conn:
            result = conn.execute(
                "SELECT COUNT(*) as cnt FROM chat_messages WHERE chat_id = ?",
                (chat_id,)
            ).fetchone()
            return result["cnt"]

    def delete_chat(self, article_id: int, user_id: int) -> bool:
        """Delete a chat and all its messages. Returns True if chat existed."""
        with self._db.conn() as conn:
            # Messages are deleted via CASCADE
            cursor = conn.execute(
                """DELETE FROM article_chats
                   WHERE article_id = ? AND user_id = ?""",
                (article_id, user_id)
            )
            return cursor.rowcount > 0

    def get_recent_chats(
        self,
        user_id: int,
        limit: int = 10
    ) -> list[DBArticleChat]:
        """Get user's most recently updated chats."""
        with self._db.conn() as conn:
            rows = conn.execute(
                """SELECT * FROM article_chats
                   WHERE user_id = ?
                   ORDER BY updated_at DESC
                   LIMIT ?""",
                (user_id, limit)
            ).fetchall()
            return [row_to_article_chat(row) for row in rows]
