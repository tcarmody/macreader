"""
Repository for user operations.
"""

from datetime import datetime

from .connection import DatabaseConnection
from .converters import row_to_user
from .models import DBUser


class UserRepository:
    """Repository for user CRUD operations."""

    # Special user for API key authentication
    API_KEY_USER_EMAIL = "api-user@local"

    def __init__(self, db: DatabaseConnection):
        self._db = db

    def get_or_create(
        self,
        email: str,
        name: str | None = None,
        provider: str | None = None
    ) -> int:
        """
        Get existing user by email or create new one.

        Args:
            email: User's email address (unique identifier)
            name: User's display name (optional)
            provider: Auth provider ('google', 'github', 'api_key')

        Returns:
            User ID (integer)
        """
        with self._db.conn() as conn:
            # Check if user exists
            cursor = conn.execute(
                "SELECT id FROM users WHERE email = ?",
                (email,)
            )
            row = cursor.fetchone()

            if row:
                return row["id"]

            # Create new user
            cursor = conn.execute(
                """
                INSERT INTO users (email, name, provider, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (email, name, provider, datetime.now().isoformat())
            )
            return cursor.lastrowid

    def get_by_id(self, user_id: int) -> DBUser | None:
        """Get user by ID."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                "SELECT * FROM users WHERE id = ?",
                (user_id,)
            )
            row = cursor.fetchone()
            return row_to_user(row) if row else None

    def get_by_email(self, email: str) -> DBUser | None:
        """Get user by email."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                "SELECT * FROM users WHERE email = ?",
                (email,)
            )
            row = cursor.fetchone()
            return row_to_user(row) if row else None

    def update_last_login(self, user_id: int):
        """Update user's last login timestamp."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE users SET last_login_at = ? WHERE id = ?",
                (datetime.now().isoformat(), user_id)
            )

    def update_name(self, user_id: int, name: str):
        """Update user's display name."""
        with self._db.conn() as conn:
            conn.execute(
                "UPDATE users SET name = ? WHERE id = ?",
                (name, user_id)
            )

    def get_or_create_api_user(self) -> int:
        """
        Get or create the shared API key user.

        This user is used for all API key authenticated requests,
        providing backward compatibility with clients that don't
        support OAuth.

        Returns:
            User ID for the shared API user
        """
        return self.get_or_create(
            email=self.API_KEY_USER_EMAIL,
            name="API User",
            provider="api_key"
        )

    def get_all(self) -> list[DBUser]:
        """Get all users (for admin purposes)."""
        with self._db.conn() as conn:
            cursor = conn.execute(
                "SELECT * FROM users ORDER BY created_at DESC"
            )
            return [row_to_user(row) for row in cursor.fetchall()]
