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


@dataclass
class DBFeed:
    id: int
    url: str
    name: str
    category: str | None
    last_fetched: datetime | None
    fetch_error: str | None = None
    unread_count: int = 0
