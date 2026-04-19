"""
Database models - dataclasses for database entities.
"""

from dataclasses import dataclass, field
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

    # Timestamp when article was promoted to Composer (NULL = not promoted)
    promoted_to_composer: datetime | None = None

    # Sentence-length brief from article_briefs (populated by list queries with JOIN)
    brief: str | None = None

    # Chat existence flag (populated by list queries with EXISTS subquery)
    has_chat: bool = False


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
class DBStoryGroup:
    """A group of articles covering the exact same news event."""
    id: int
    label: str
    representative_id: int | None
    period_start: datetime
    period_end: datetime
    created_at: datetime
    member_ids: list[int] = field(default_factory=list)


@dataclass
class DBBrief:
    """Newsletter-ready brief for an article at a specific length and tone."""
    id: int
    article_id: int
    length: str   # 'sentence' | 'short' | 'paragraph'
    tone: str     # 'neutral' | 'opinionated' | 'analytical'
    content: str
    model_used: str | None
    created_at: datetime


@dataclass
class DBDigest:
    """An assembled daily or weekly digest."""
    id: int
    period: str           # 'today' | 'week' | 'custom'
    period_start: datetime
    period_end: datetime
    article_ids: list[int]  # selected article IDs (parsed from JSON)
    title: str
    intro: str | None
    content: str          # rendered output
    format: str
    tone: str
    brief_length: str
    story_count: int
    word_count: int
    created_at: datetime


@dataclass
class DBSavedSearch:
    """A user's saved search query for quick re-use."""
    id: int
    user_id: int
    name: str
    query: str
    include_summaries: bool
    last_used_at: datetime | None
    created_at: datetime


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
