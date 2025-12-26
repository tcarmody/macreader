"""
Database module - SQLite operations for articles and feeds.

Uses repository pattern for better separation of concerns.
"""

from .connection import DatabaseConnection
from .models import DBArticle, DBFeed
from .article_repository import ArticleRepository
from .feed_repository import FeedRepository
from .library_repository import LibraryRepository
from .settings_repository import SettingsRepository
from .gmail_repository import GmailRepository
from .database import Database

__all__ = [
    "Database",
    "DatabaseConnection",
    "DBArticle",
    "DBFeed",
    "ArticleRepository",
    "FeedRepository",
    "LibraryRepository",
    "SettingsRepository",
    "GmailRepository",
]
