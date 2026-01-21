"""
Database facade - provides unified access to all repositories.

This class maintains backwards compatibility with the original monolithic Database class
while delegating to specialized repositories internally.
"""

from datetime import datetime
from pathlib import Path

from .connection import DatabaseConnection
from .article_repository import ArticleRepository
from .chat_repository import ChatRepository
from .feed_repository import FeedRepository
from .library_repository import LibraryRepository
from .settings_repository import SettingsRepository
from .gmail_repository import GmailRepository
from .notification_repository import NotificationRepository
from .statistics_repository import StatisticsRepository
from .user_repository import UserRepository
from .user_article_state_repository import UserArticleStateRepository
from .models import DBArticle, DBFeed, DBNotificationRule, DBNotificationHistory


class Database:
    """
    Unified database access facade.

    Provides backwards-compatible API while using repository pattern internally.

    Multi-user support:
    - User accounts are managed via `users` repository
    - Per-user article state (read/bookmark) via `user_state` repository
    - Library items are per-user (filtered by user_id)
    - Feeds and articles are shared across all users
    """

    # Constants for standalone feed
    STANDALONE_FEED_URL = LibraryRepository.STANDALONE_FEED_URL
    STANDALONE_FEED_NAME = LibraryRepository.STANDALONE_FEED_NAME

    def __init__(self, db_path: Path):
        self._connection = DatabaseConnection(db_path)

        # Initialize repositories
        self.articles = ArticleRepository(self._connection)
        self.feeds = FeedRepository(self._connection)
        self.library = LibraryRepository(self._connection)
        self.settings = SettingsRepository(self._connection)
        self.gmail = GmailRepository(self._connection)
        self.notifications = NotificationRepository(self._connection)
        self.statistics = StatisticsRepository(self._connection)

        # Multi-user support repositories
        self.users = UserRepository(self._connection)
        self.user_state = UserArticleStateRepository(self._connection)

        # Chat repository for article discussions
        self.chat = ChatRepository(self._connection)

    # ─────────────────────────────────────────────────────────────
    # Feed operations (delegated to FeedRepository)
    # ─────────────────────────────────────────────────────────────

    def add_feed(self, url: str, name: str, category: str | None = None) -> int:
        return self.feeds.add(url, name, category)

    def get_feed(self, feed_id: int, user_id: int | None = None) -> DBFeed | None:
        return self.feeds.get(feed_id, user_id)

    def get_feeds(self, user_id: int | None = None) -> list[DBFeed]:
        return self.feeds.get_all(user_id)

    def update_feed(
        self,
        feed_id: int,
        name: str | None = None,
        category: str | None = None,
        clear_category: bool = False
    ):
        return self.feeds.update(feed_id, name, category, clear_category)

    def update_feed_fetched(self, feed_id: int, error: str | None = None):
        return self.feeds.update_fetched(feed_id, error)

    def delete_feed(self, feed_id: int):
        return self.feeds.delete(feed_id)

    def bulk_delete_feeds(self, feed_ids: list[int]):
        return self.feeds.bulk_delete(feed_ids)

    # ─────────────────────────────────────────────────────────────
    # Standalone (Library) operations (delegated to LibraryRepository)
    # Library items are per-user - all methods require user_id
    # ─────────────────────────────────────────────────────────────

    def get_or_create_standalone_feed(self) -> int:
        return self.library.get_or_create_feed()

    def add_standalone_item(
        self,
        user_id: int,
        url: str,
        title: str,
        content: str | None = None,
        content_type: str = "url",
        file_name: str | None = None,
        file_path: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
    ) -> int | None:
        return self.library.add(
            user_id, url, title, content, content_type,
            file_name, file_path, author, published_at
        )

    def get_standalone_items(
        self,
        user_id: int,
        content_type: str | None = None,
        bookmarked_only: bool = False,
        limit: int = 100,
        offset: int = 0
    ) -> list[DBArticle]:
        return self.library.get_all(user_id, content_type, bookmarked_only, limit, offset)

    def get_standalone_count(self, user_id: int) -> int:
        return self.library.get_count(user_id)

    def get_standalone_item(self, user_id: int, article_id: int) -> DBArticle | None:
        return self.library.get_item(user_id, article_id)

    def delete_standalone_item(self, user_id: int, article_id: int) -> bool:
        return self.library.delete(user_id, article_id)

    def is_standalone_feed(self, feed_id: int) -> bool:
        return self.library.is_standalone_feed(feed_id)

    def verify_library_ownership(self, user_id: int, article_id: int) -> bool:
        return self.library.verify_ownership(user_id, article_id)

    # ─────────────────────────────────────────────────────────────
    # Article operations (delegated to ArticleRepository)
    # Read/bookmark state is per-user via user_state repository
    # ─────────────────────────────────────────────────────────────

    def add_article(
        self,
        feed_id: int,
        url: str,
        title: str,
        content: str | None = None,
        author: str | None = None,
        published_at: datetime | None = None,
        content_hash: str | None = None,
        source_url: str | None = None,
        reading_time_minutes: int | None = None,
        word_count: int | None = None,
        featured_image: str | None = None,
        has_code_blocks: bool = False,
        site_name: str | None = None,
    ) -> int | None:
        return self.articles.add(
            feed_id, url, title, content, author, published_at,
            content_hash, source_url, reading_time_minutes, word_count,
            featured_image, has_code_blocks, site_name
        )

    def get_articles(
        self,
        user_id: int,
        feed_id: int | None = None,
        unread_only: bool = False,
        bookmarked_only: bool = False,
        summarized_only: bool | None = None,
        sort_by: str = "newest",
        limit: int = 50,
        offset: int = 0
    ) -> list[DBArticle]:
        return self.articles.get_many(
            user_id, feed_id, unread_only, bookmarked_only,
            summarized_only, sort_by, limit, offset
        )

    def get_article(self, article_id: int) -> DBArticle | None:
        return self.articles.get(article_id)

    def get_article_with_state(self, article_id: int, user_id: int) -> DBArticle | None:
        """Get article with user-specific read/bookmark state."""
        return self.articles.get_with_user_state(article_id, user_id)

    # Alias for service layer compatibility
    def get_article_with_user_state(self, article_id: int, user_id: int) -> DBArticle | None:
        """Get article with user-specific read/bookmark state."""
        return self.articles.get_with_user_state(article_id, user_id)

    def get_article_by_url(self, url: str) -> DBArticle | None:
        return self.articles.get_by_url(url)

    def update_article_content(self, article_id: int, content: str):
        return self.articles.update_content(article_id, content)

    def update_article_source_url(self, article_id: int, source_url: str):
        return self.articles.update_source_url(article_id, source_url)

    def update_summary(
        self,
        article_id: int,
        summary_short: str,
        summary_full: str,
        key_points: list[str],
        model_used: str
    ):
        return self.articles.update_summary(article_id, summary_short, summary_full, key_points, model_used)

    # Per-user article state operations (delegated to UserArticleStateRepository)
    def mark_read(self, user_id: int, article_id: int, is_read: bool = True):
        return self.user_state.mark_read(user_id, article_id, is_read)

    def toggle_bookmark(self, user_id: int, article_id: int) -> bool:
        return self.user_state.toggle_bookmark(user_id, article_id)

    def bulk_mark_read(self, user_id: int, article_ids: list[int], is_read: bool = True):
        return self.user_state.bulk_mark_read(user_id, article_ids, is_read)

    def mark_feed_read(self, user_id: int, feed_id: int, is_read: bool = True) -> int:
        return self.user_state.mark_feed_read(user_id, feed_id, is_read)

    def mark_all_read(self, user_id: int, is_read: bool = True) -> int:
        return self.user_state.mark_all_read(user_id, is_read)

    def search(self, query: str, limit: int = 20) -> list[DBArticle]:
        return self.articles.search(query, limit)

    def get_duplicate_articles(self) -> list[tuple[str, list[DBArticle]]]:
        return self.articles.get_duplicates()

    def get_duplicate_article_ids(self) -> set[int]:
        return self.articles.get_duplicate_ids()

    def archive_old_articles(self, days: int = 30) -> int:
        return self.articles.archive_old(days)

    def get_article_stats(self, user_id: int) -> dict:
        return self.articles.get_stats(user_id)

    def get_unread_count(self, user_id: int, feed_id: int | None = None) -> int:
        return self.user_state.get_unread_count(user_id, feed_id)

    def get_articles_grouped_by_date(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[str, list[DBArticle]]:
        return self.articles.get_grouped_by_date(user_id, unread_only, limit)

    def get_articles_grouped_by_feed(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100
    ) -> dict[int, list[DBArticle]]:
        return self.articles.get_grouped_by_feed(user_id, unread_only, limit)

    # ─────────────────────────────────────────────────────────────
    # Settings operations (delegated to SettingsRepository)
    # ─────────────────────────────────────────────────────────────

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        return self.settings.get(key, default)

    def set_setting(self, key: str, value: str):
        return self.settings.set(key, value)

    def get_all_settings(self) -> dict[str, str]:
        return self.settings.get_all()

    # ─────────────────────────────────────────────────────────────
    # Gmail operations (delegated to GmailRepository)
    # ─────────────────────────────────────────────────────────────

    def save_gmail_config(
        self,
        email: str,
        access_token: str,
        refresh_token: str,
        token_expires_at: datetime,
        monitored_label: str = "Newsletters",
        poll_interval_minutes: int = 30,
    ) -> int:
        return self.gmail.save_config(
            email, access_token, refresh_token, token_expires_at,
            monitored_label, poll_interval_minutes
        )

    def get_gmail_config(self) -> dict | None:
        return self.gmail.get_config()

    def update_gmail_tokens(
        self,
        access_token: str,
        refresh_token: str,
        expires_at: datetime,
    ):
        return self.gmail.update_tokens(access_token, refresh_token, expires_at)

    def update_gmail_config(
        self,
        monitored_label: str | None = None,
        poll_interval_minutes: int | None = None,
        is_enabled: bool | None = None,
    ):
        return self.gmail.update_config(monitored_label, poll_interval_minutes, is_enabled)

    def update_gmail_last_fetched_uid(self, uid: int):
        return self.gmail.update_last_fetched_uid(uid)

    def delete_gmail_config(self):
        return self.gmail.delete_config()

    # ─────────────────────────────────────────────────────────────
    # Notification operations (delegated to NotificationRepository)
    # ─────────────────────────────────────────────────────────────

    def add_notification_rule(
        self,
        name: str,
        feed_id: int | None = None,
        keyword: str | None = None,
        author: str | None = None,
        priority: str = "normal",
    ) -> int:
        return self.notifications.add_rule(name, feed_id, keyword, author, priority)

    def get_notification_rule(self, rule_id: int) -> DBNotificationRule | None:
        return self.notifications.get_rule(rule_id)

    def get_notification_rules(
        self, enabled_only: bool = False
    ) -> list[DBNotificationRule]:
        return self.notifications.get_all_rules(enabled_only)

    def get_notification_rules_for_feed(
        self, feed_id: int
    ) -> list[DBNotificationRule]:
        return self.notifications.get_rules_for_feed(feed_id)

    def update_notification_rule(
        self,
        rule_id: int,
        name: str | None = None,
        feed_id: int | None = None,
        clear_feed: bool = False,
        keyword: str | None = None,
        clear_keyword: bool = False,
        author: str | None = None,
        clear_author: bool = False,
        priority: str | None = None,
        enabled: bool | None = None,
    ):
        return self.notifications.update_rule(
            rule_id, name, feed_id, clear_feed, keyword,
            clear_keyword, author, clear_author, priority, enabled
        )

    def delete_notification_rule(self, rule_id: int):
        return self.notifications.delete_rule(rule_id)

    def add_notification_history(
        self, article_id: int, rule_id: int | None = None
    ) -> int:
        return self.notifications.add_history(article_id, rule_id)

    def get_notification_history(
        self,
        limit: int = 50,
        offset: int = 0,
        include_dismissed: bool = False
    ) -> list[DBNotificationHistory]:
        return self.notifications.get_history(limit, offset, include_dismissed)

    def was_article_notified(self, article_id: int) -> bool:
        return self.notifications.was_notified(article_id)

    def dismiss_notification(self, history_id: int):
        return self.notifications.dismiss_notification(history_id)

    def dismiss_all_notifications(self):
        return self.notifications.dismiss_all()

    def clear_old_notification_history(self, days: int = 30):
        return self.notifications.clear_old_history(days)
