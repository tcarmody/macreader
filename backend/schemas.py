"""
Pydantic models for API request/response validation.
"""

from pydantic import BaseModel

from .database import DBArticle, DBFeed
from .database.models import DBNotificationRule, DBNotificationHistory


# ─────────────────────────────────────────────────────────────
# Article Schemas
# ─────────────────────────────────────────────────────────────

class ArticleResponse(BaseModel):
    """Article for list view."""
    id: int
    feed_id: int
    url: str
    source_url: str | None = None  # Original URL for aggregator articles
    title: str
    summary_short: str | None
    is_read: bool
    is_bookmarked: bool
    published_at: str | None
    created_at: str

    # Useful metadata for list view
    reading_time_minutes: int | None = None
    author: str | None = None

    @classmethod
    def from_db(cls, article: DBArticle) -> "ArticleResponse":
        return cls(
            id=article.id,
            feed_id=article.feed_id,
            url=article.url,
            source_url=article.source_url,
            title=article.title,
            summary_short=article.summary_short,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            published_at=article.published_at.isoformat() if article.published_at else None,
            created_at=article.created_at.isoformat(),
            reading_time_minutes=article.reading_time_minutes,
            author=article.author,
        )


class ArticleDetailResponse(BaseModel):
    """Article with full summary for detail view."""
    id: int
    feed_id: int
    url: str
    source_url: str | None = None  # Original URL for aggregator articles
    title: str
    content: str | None
    summary_short: str | None
    summary_full: str | None
    key_points: list[str] | None
    is_read: bool
    is_bookmarked: bool
    published_at: str | None
    created_at: str

    # Enhanced extraction metadata
    author: str | None = None
    reading_time_minutes: int | None = None
    word_count: int | None = None
    featured_image: str | None = None
    has_code_blocks: bool = False
    site_name: str | None = None

    @classmethod
    def from_db(cls, article: DBArticle) -> "ArticleDetailResponse":
        return cls(
            id=article.id,
            feed_id=article.feed_id,
            url=article.url,
            source_url=article.source_url,
            title=article.title,
            content=article.content,
            summary_short=article.summary_short,
            summary_full=article.summary_full,
            key_points=article.key_points,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            published_at=article.published_at.isoformat() if article.published_at else None,
            created_at=article.created_at.isoformat(),
            author=article.author,
            reading_time_minutes=article.reading_time_minutes,
            word_count=article.word_count,
            featured_image=article.featured_image,
            has_code_blocks=article.has_code_blocks,
            site_name=article.site_name,
        )


class ArticleGroupResponse(BaseModel):
    """A group of articles."""
    key: str
    label: str
    articles: list[ArticleResponse]


class GroupedArticlesResponse(BaseModel):
    """Response for grouped articles."""
    group_by: str
    groups: list[ArticleGroupResponse]


class BulkMarkReadRequest(BaseModel):
    """Request to mark multiple articles as read/unread."""
    article_ids: list[int]
    is_read: bool = True


class ExtractSourceResponse(BaseModel):
    """Response from source URL extraction."""
    success: bool
    source_url: str | None = None
    aggregator: str | None = None
    confidence: float = 0.0
    error: str | None = None


# ─────────────────────────────────────────────────────────────
# Feed Schemas
# ─────────────────────────────────────────────────────────────

class FeedResponse(BaseModel):
    """Feed for list view."""
    id: int
    url: str
    name: str
    category: str | None
    unread_count: int
    last_fetched: str | None
    fetch_error: str | None = None

    @classmethod
    def from_db(cls, feed: DBFeed) -> "FeedResponse":
        return cls(
            id=feed.id,
            url=feed.url,
            name=feed.name,
            category=feed.category,
            unread_count=feed.unread_count,
            last_fetched=feed.last_fetched.isoformat() if feed.last_fetched else None,
            fetch_error=feed.fetch_error
        )


class AddFeedRequest(BaseModel):
    """Request to add a new feed."""
    url: str
    name: str | None = None


class UpdateFeedRequest(BaseModel):
    """Request to update a feed."""
    name: str | None = None
    category: str | None = None


class BulkDeleteFeedsRequest(BaseModel):
    """Request to delete multiple feeds."""
    feed_ids: list[int]


# ─────────────────────────────────────────────────────────────
# Summarization Schemas
# ─────────────────────────────────────────────────────────────

class SummarizeRequest(BaseModel):
    """Request to summarize a URL."""
    url: str


class BatchSummarizeRequest(BaseModel):
    """Request to summarize multiple URLs."""
    urls: list[str]


class BatchSummarizeResult(BaseModel):
    """Result of a single URL summarization in a batch."""
    url: str
    success: bool
    title: str | None = None
    one_liner: str | None = None
    full_summary: str | None = None
    key_points: list[str] | None = None
    model_used: str | None = None
    cached: bool = False
    error: str | None = None


class BatchSummarizeResponse(BaseModel):
    """Response from batch summarization."""
    total: int
    successful: int
    failed: int
    results: list[BatchSummarizeResult]


# ─────────────────────────────────────────────────────────────
# Settings Schemas
# ─────────────────────────────────────────────────────────────

class SettingsResponse(BaseModel):
    """Application settings."""
    refresh_interval_minutes: int = 30
    auto_summarize: bool = False
    mark_read_on_open: bool = True
    default_model: str = "haiku"
    llm_provider: str = "anthropic"  # anthropic, openai, or google


class SettingsUpdateRequest(BaseModel):
    """Request to update settings."""
    refresh_interval_minutes: int | None = None
    auto_summarize: bool | None = None
    mark_read_on_open: bool | None = None
    default_model: str | None = None
    llm_provider: str | None = None


# ─────────────────────────────────────────────────────────────
# OPML Schemas
# ─────────────────────────────────────────────────────────────

class OPMLImportRequest(BaseModel):
    """Request to import feeds from OPML."""
    opml_content: str


class OPMLImportResult(BaseModel):
    """Result of importing a single feed from OPML."""
    url: str
    name: str | None
    success: bool
    error: str | None = None
    feed_id: int | None = None


class OPMLImportResponse(BaseModel):
    """Response from OPML import."""
    total: int
    imported: int
    skipped: int
    failed: int
    results: list[OPMLImportResult]


# ─────────────────────────────────────────────────────────────
# Standalone (Library) Schemas
# ─────────────────────────────────────────────────────────────

class AddStandaloneURLRequest(BaseModel):
    """Request to add a URL to the library."""
    url: str
    title: str | None = None


class StandaloneItemResponse(BaseModel):
    """Standalone item for list view."""
    id: int
    url: str
    title: str
    summary_short: str | None
    is_read: bool
    is_bookmarked: bool
    content_type: str | None  # url, pdf, docx, txt, md, html
    file_name: str | None
    created_at: str

    @classmethod
    def from_db(cls, article: DBArticle) -> "StandaloneItemResponse":
        return cls(
            id=article.id,
            url=article.url,
            title=article.title,
            summary_short=article.summary_short,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            content_type=article.content_type,
            file_name=article.file_name,
            created_at=article.created_at.isoformat()
        )


class StandaloneItemDetailResponse(BaseModel):
    """Standalone item with full content for detail view."""
    id: int
    url: str
    title: str
    content: str | None
    summary_short: str | None
    summary_full: str | None
    key_points: list[str] | None
    is_read: bool
    is_bookmarked: bool
    content_type: str | None
    file_name: str | None
    created_at: str

    @classmethod
    def from_db(cls, article: DBArticle) -> "StandaloneItemDetailResponse":
        return cls(
            id=article.id,
            url=article.url,
            title=article.title,
            content=article.content,
            summary_short=article.summary_short,
            summary_full=article.summary_full,
            key_points=article.key_points,
            is_read=article.is_read,
            is_bookmarked=article.is_bookmarked,
            content_type=article.content_type,
            file_name=article.file_name,
            created_at=article.created_at.isoformat()
        )


class StandaloneListResponse(BaseModel):
    """Response for list of standalone items."""
    items: list[StandaloneItemResponse]
    total: int


class LibraryStatsResponse(BaseModel):
    """Library statistics."""
    total_items: int
    by_type: dict[str, int]  # count by content_type


# ─────────────────────────────────────────────────────────────
# Newsletter Import Schemas
# ─────────────────────────────────────────────────────────────

class NewsletterImportResult(BaseModel):
    """Result of importing a single newsletter email."""
    success: bool
    title: str | None = None
    author: str | None = None
    item_id: int | None = None
    error: str | None = None


class NewsletterImportResponse(BaseModel):
    """Response from newsletter import."""
    total: int
    imported: int
    failed: int
    results: list[NewsletterImportResult]


# ─────────────────────────────────────────────────────────────
# Gmail IMAP Schemas
# ─────────────────────────────────────────────────────────────

class GmailAuthURLResponse(BaseModel):
    """Response containing Gmail OAuth authorization URL."""
    auth_url: str
    state: str


class GmailAuthCallbackRequest(BaseModel):
    """Request to complete Gmail OAuth flow."""
    code: str
    state: str


class GmailStatusResponse(BaseModel):
    """Gmail connection status."""
    connected: bool
    email: str | None = None
    monitored_label: str | None = None
    poll_interval_minutes: int = 30
    last_fetched_uid: int = 0
    is_polling_enabled: bool = True
    last_fetch: str | None = None


class GmailConfigUpdateRequest(BaseModel):
    """Request to update Gmail configuration."""
    monitored_label: str | None = None
    poll_interval_minutes: int | None = None
    is_enabled: bool | None = None


class GmailLabelResponse(BaseModel):
    """Response containing available Gmail labels."""
    labels: list[str]


class GmailFetchResponse(BaseModel):
    """Response from Gmail fetch operation."""
    success: bool
    imported: int = 0
    failed: int = 0
    skipped: int = 0
    errors: list[str] | None = None
    message: str | None = None


# ─────────────────────────────────────────────────────────────
# Authenticated Fetch Schemas
# ─────────────────────────────────────────────────────────────

class ExtractFromHTMLRequest(BaseModel):
    """Request to extract article content from pre-fetched HTML.

    Used when the client fetches the page (e.g., with browser cookies)
    and sends the HTML to the backend for content extraction.
    """
    html: str
    url: str  # The URL the HTML was fetched from (for context)


# ─────────────────────────────────────────────────────────────
# Notification Schemas
# ─────────────────────────────────────────────────────────────

class NotificationRuleResponse(BaseModel):
    """Notification rule for display."""
    id: int
    name: str
    feed_id: int | None
    feed_name: str | None = None  # Populated by API
    keyword: str | None
    author: str | None
    priority: str
    enabled: bool
    created_at: str

    @classmethod
    def from_db(
        cls, rule: DBNotificationRule, feed_name: str | None = None
    ) -> "NotificationRuleResponse":
        return cls(
            id=rule.id,
            name=rule.name,
            feed_id=rule.feed_id,
            feed_name=feed_name,
            keyword=rule.keyword,
            author=rule.author,
            priority=rule.priority,
            enabled=rule.enabled,
            created_at=rule.created_at.isoformat(),
        )


class CreateNotificationRuleRequest(BaseModel):
    """Request to create a notification rule."""
    name: str
    feed_id: int | None = None
    keyword: str | None = None
    author: str | None = None
    priority: str = "normal"


class UpdateNotificationRuleRequest(BaseModel):
    """Request to update a notification rule."""
    name: str | None = None
    feed_id: int | None = None
    clear_feed: bool = False
    keyword: str | None = None
    clear_keyword: bool = False
    author: str | None = None
    clear_author: bool = False
    priority: str | None = None
    enabled: bool | None = None


class NotificationHistoryResponse(BaseModel):
    """Notification history entry."""
    id: int
    article_id: int
    article_title: str | None = None  # Populated by API
    rule_id: int | None
    rule_name: str | None = None  # Populated by API
    notified_at: str
    dismissed: bool

    @classmethod
    def from_db(
        cls,
        history: DBNotificationHistory,
        article_title: str | None = None,
        rule_name: str | None = None,
    ) -> "NotificationHistoryResponse":
        return cls(
            id=history.id,
            article_id=history.article_id,
            article_title=article_title,
            rule_id=history.rule_id,
            rule_name=rule_name,
            notified_at=history.notified_at.isoformat(),
            dismissed=history.dismissed,
        )


class NotificationMatchResponse(BaseModel):
    """Article that matched notification rules during refresh."""
    article_id: int
    article_title: str
    feed_id: int
    rule_id: int
    rule_name: str
    priority: str
    match_reason: str


class PendingNotificationsResponse(BaseModel):
    """Response containing articles that triggered notifications."""
    count: int
    notifications: list[NotificationMatchResponse]


# ─────────────────────────────────────────────────────────────
# Reading Statistics Schemas
# ─────────────────────────────────────────────────────────────

class TimePeriod(BaseModel):
    """Time period specification."""
    type: str  # 'rolling' or 'calendar'
    value: str  # '7d', '30d', '90d' for rolling; 'week', 'month', 'year' for calendar


class SummarizationStatsResponse(BaseModel):
    """Summarization statistics."""
    total_articles: int
    summarized_articles: int
    summarization_rate: float  # percentage (0.0 to 1.0)
    model_breakdown: dict[str, int]  # model_name -> count
    avg_per_day: float
    avg_per_week: float
    period_start: str | None
    period_end: str


class TopicInfo(BaseModel):
    """Single topic info."""
    label: str
    count: int
    article_ids: list[int] | None = None


class TopicTrend(BaseModel):
    """Topic with frequency data."""
    topic_hash: str
    label: str
    total_count: int
    cluster_count: int


class TopicStatsResponse(BaseModel):
    """Topic statistics."""
    current_topics: list[TopicInfo]
    topic_trends: list[TopicTrend]
    most_common: list[TopicInfo]


class ReadingActivityStats(BaseModel):
    """Reading activity statistics."""
    articles_read: int
    total_reading_time_minutes: int
    avg_reading_time_minutes: float
    bookmarks_added: int
    read_by_day: dict[str, int]  # date -> count
    read_by_feed: dict[str, int]  # feed_name -> count


class ReadingStatsResponse(BaseModel):
    """Complete reading statistics response."""
    period: TimePeriod
    period_start: str
    period_end: str
    summarization: SummarizationStatsResponse
    topics: TopicStatsResponse
    reading: ReadingActivityStats


class TopicClusteringResponse(BaseModel):
    """Response from topic clustering."""
    topics: list[TopicInfo]
    total_articles: int
    persisted: bool


class TopicTrendsResponse(BaseModel):
    """Response with topic trends."""
    trends: list[TopicTrend]
    days: int
