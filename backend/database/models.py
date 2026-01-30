"""
Database models - dataclasses for database entities.
"""

from dataclasses import dataclass
from datetime import datetime


@dataclass
class DBArticle:
    id: int
    feed_id: int
    url: str
    title: str
    content: str | None
    summary_short: str | None
    summary_full: str | None
    key_points: list[str] | None
    is_read: bool
    is_bookmarked: bool
    published_at: datetime | None
    created_at: datetime
    source_url: str | None = None  # Original URL for aggregator articles
    content_type: str | None = None  # url, pdf, docx, txt, md, html
    file_name: str | None = None  # Original filename for uploads
    file_path: str | None = None  # Local storage path for files

    # Enhanced extraction metadata
    author: str | None = None
    reading_time_minutes: int | None = None
    word_count: int | None = None
    featured_image: str | None = None
    has_code_blocks: bool = False
    site_name: str | None = None

    # Multi-user support: owner for library items (NULL for shared RSS articles)
    user_id: int | None = None

    # Original feed name for archived articles (when feed was deleted but article preserved)
    feed_name: str | None = None

    # Related links (Exa neural search) - JSON string
    related_links: str | None = None

    # Extracted keywords cache for LLM - JSON string
    extracted_keywords: str | None = None

    # Related links error message if fetch failed
    related_links_error: str | None = None


@dataclass
class DBUser:
    """User account for multi-user support."""
    id: int
    email: str
    name: str | None
    provider: str | None  # 'google', 'github', 'api_key'
    created_at: datetime
    last_login_at: datetime | None = None


@dataclass
class DBUserArticleState:
    """Per-user article state (read/bookmark status)."""
    id: int
    user_id: int
    article_id: int
    is_read: bool
    read_at: datetime | None
    is_bookmarked: bool
    bookmarked_at: datetime | None


@dataclass
class DBFeed:
    id: int
    url: str
    name: str
    category: str | None
    last_fetched: datetime | None
    fetch_error: str | None = None
    unread_count: int = 0


@dataclass
class DBNotificationRule:
    id: int
    name: str
    feed_id: int | None
    keyword: str | None
    author: str | None
    priority: str  # 'high', 'normal', 'low'
    enabled: bool
    created_at: datetime


@dataclass
class DBNotificationHistory:
    id: int
    article_id: int
    rule_id: int | None
    notified_at: datetime
    dismissed: bool


@dataclass
class DBTopicHistory:
    """Persisted topic clustering result for trend analysis."""
    id: int
    topic_label: str
    topic_hash: str
    article_count: int
    article_ids: list[int]
    clustered_at: datetime
    period_start: datetime
    period_end: datetime


@dataclass
class DBArticleChat:
    """Chat session for an article (one per user per article)."""
    id: int
    article_id: int
    user_id: int
    created_at: datetime
    updated_at: datetime


@dataclass
class DBChatMessage:
    """Individual message in an article chat."""
    id: int
    chat_id: int
    role: str  # 'user' or 'assistant'
    content: str
    model_used: str | None
    created_at: datetime
