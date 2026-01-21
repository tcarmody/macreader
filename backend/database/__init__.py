"""
Database module - SQLite operations for articles and feeds.

Uses repository pattern for better separation of concerns.
Supports multi-user with per-user read/bookmark state and per-user library.
"""

from .connection import DatabaseConnection
from .models import DBArticle, DBArticleChat, DBChatMessage, DBFeed, DBUser, DBUserArticleState
from .article_repository import ArticleRepository
from .chat_repository import ChatRepository
from .feed_repository import FeedRepository
from .library_repository import LibraryRepository
from .settings_repository import SettingsRepository
from .gmail_repository import GmailRepository
from .user_repository import UserRepository
from .user_article_state_repository import UserArticleStateRepository
from .database import Database

__all__ = [
    "Database",
    "DatabaseConnection",
    "DBArticle",
    "DBArticleChat",
    "DBChatMessage",
    "DBFeed",
    "DBUser",
    "DBUserArticleState",
    "ArticleRepository",
    "ChatRepository",
    "FeedRepository",
    "LibraryRepository",
    "SettingsRepository",
    "GmailRepository",
    "UserRepository",
    "UserArticleStateRepository",
]
