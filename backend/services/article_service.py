"""
Article service: business logic for article operations.

Handles article listing, grouping, fetching, summarization, and state management.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from fastapi import BackgroundTasks, HTTPException

from ..database import Database
from ..database.models import DBArticle
from ..source_extractor import SourceExtractor
from ..tasks import summarize_article
from ..validators import require_sufficient_content

if TYPE_CHECKING:
    from ..fetcher import Fetcher
    from ..summarizer import Summarizer
    from ..clustering import Clusterer


class ArticleService:
    """Service for article-related business logic."""

    def __init__(
        self,
        db: Database,
        fetcher: "Fetcher | None" = None,
        enhanced_fetcher: object | None = None,
        summarizer: "Summarizer | None" = None,
        clusterer: "Clusterer | None" = None,
    ):
        self.db = db
        self.fetcher = fetcher
        self.enhanced_fetcher = enhanced_fetcher
        self.summarizer = summarizer
        self.clusterer = clusterer

    # ─────────────────────────────────────────────────────────────
    # Listing & Filtering
    # ─────────────────────────────────────────────────────────────

    def list_articles(
        self,
        user_id: int,
        feed_id: int | None = None,
        unread_only: bool = False,
        bookmarked_only: bool = False,
        summarized_only: bool | None = None,
        hide_duplicates: bool = False,
        sort_by: str = "newest",
        limit: int = 50,
        offset: int = 0,
    ) -> list[DBArticle]:
        """
        Get articles with filtering options.

        Args:
            user_id: User ID for per-user state
            feed_id: Filter by feed
            unread_only: Only unread articles
            bookmarked_only: Only bookmarked articles
            summarized_only: True for summarized, False for unsummarized, None for all
            hide_duplicates: Hide duplicate articles
            sort_by: Sort order (newest, oldest, unread_first, title_asc, title_desc)
            limit: Maximum articles to return
            offset: Pagination offset

        Returns:
            List of articles matching filters
        """
        articles = self.db.get_articles(
            user_id=user_id,
            feed_id=feed_id,
            unread_only=unread_only,
            bookmarked_only=bookmarked_only,
            summarized_only=summarized_only,
            sort_by=sort_by,
            limit=limit,
            offset=offset,
        )

        if hide_duplicates:
            duplicate_ids = self.db.get_duplicate_article_ids()
            articles = [a for a in articles if a.id not in duplicate_ids]

        return articles

    # ─────────────────────────────────────────────────────────────
    # Grouping
    # ─────────────────────────────────────────────────────────────

    async def group_articles_by_date(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100,
    ) -> list[dict]:
        """
        Group articles by date with formatted labels.

        Returns:
            List of groups with key, label, and articles
        """
        grouped = self.db.get_articles_grouped_by_date(
            user_id=user_id, unread_only=unread_only, limit=limit
        )

        groups = []
        for date_str in sorted(grouped.keys(), reverse=True):
            articles = grouped[date_str]
            label = self._format_date_label(date_str)
            groups.append({
                "key": date_str,
                "label": label,
                "articles": articles,
            })

        return groups

    async def group_articles_by_feed(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100,
    ) -> list[dict]:
        """
        Group articles by feed.

        Returns:
            List of groups with key, label, and articles
        """
        feeds_map = {f.id: f for f in self.db.get_feeds()}
        grouped = self.db.get_articles_grouped_by_feed(
            user_id=user_id, unread_only=unread_only, limit=limit
        )

        groups = []
        for feed_id in sorted(grouped.keys()):
            articles = grouped[feed_id]
            feed = feeds_map.get(feed_id)
            label = feed.name if feed else f"Feed {feed_id}"
            groups.append({
                "key": str(feed_id),
                "label": label,
                "articles": articles,
            })

        return groups

    async def group_articles_by_topic(
        self,
        user_id: int,
        unread_only: bool = False,
        limit: int = 100,
    ) -> list[dict]:
        """
        Group articles by AI-detected topic.

        Returns:
            List of groups with key, label, and articles

        Raises:
            HTTPException: If clusterer is not configured
        """
        if not self.clusterer:
            raise HTTPException(
                status_code=503,
                detail="Topic clustering unavailable: API key not configured"
            )

        articles = self.db.get_articles(
            user_id=user_id, unread_only=unread_only, limit=limit
        )

        if not articles:
            return []

        result = await self.clusterer.cluster_async(articles)
        article_map = {a.id: a for a in articles}

        groups = []
        for topic in result.topics:
            topic_articles = [
                article_map[aid]
                for aid in topic.article_ids
                if aid in article_map
            ]
            if topic_articles:
                groups.append({
                    "key": topic.id,
                    "label": topic.label,
                    "articles": topic_articles,
                })

        return groups

    def _format_date_label(self, date_str: str) -> str:
        """Format a date string into a human-readable label."""
        date_obj = datetime.strptime(date_str, "%Y-%m-%d")
        today = datetime.now().date()

        if date_obj.date() == today:
            return "Today"
        elif (today - date_obj.date()).days == 1:
            return "Yesterday"
        else:
            return date_obj.strftime("%B %d, %Y")

    # ─────────────────────────────────────────────────────────────
    # Content Fetching
    # ─────────────────────────────────────────────────────────────

    async def resolve_fetch_url(
        self,
        article: DBArticle,
        use_aggregator_url: bool = False,
    ) -> str:
        """
        Resolve the URL to fetch for an article.

        For aggregator articles, extracts and returns the original source URL
        unless use_aggregator_url is True.
        """
        if use_aggregator_url:
            return article.url

        if article.source_url:
            return article.source_url

        extractor = SourceExtractor()
        if extractor.is_aggregator(article.url):
            result = await extractor.extract(article.url, article.content or "")
            if result.source_url:
                self.db.update_article_source_url(article.id, result.source_url)
                return result.source_url

        return article.url

    async def fetch_article_content(
        self,
        article: DBArticle,
        force_archive: bool = False,
        force_js: bool = False,
        use_aggregator_url: bool = False,
    ) -> DBArticle:
        """
        Fetch full content for an article.

        Uses intelligent fallback:
        1. Try simple HTTP fetch
        2. If content is paywalled and archive enabled, try archive services
        3. If content is dynamic and JS render enabled, use Playwright

        Args:
            article: Article to fetch content for
            force_archive: Skip simple fetch and go straight to archives
            force_js: Skip simple fetch and use JavaScript rendering
            use_aggregator_url: Fetch from aggregator URL instead of source

        Returns:
            Updated article with fetched content

        Raises:
            HTTPException: If fetching fails
        """
        fetch_url = await self.resolve_fetch_url(article, use_aggregator_url)

        try:
            if self.enhanced_fetcher:
                result = await self.enhanced_fetcher.fetch(
                    fetch_url,
                    force_archive=force_archive,
                    force_js=force_js
                )
            elif self.fetcher:
                result = await self.fetcher.fetch(fetch_url)
            else:
                raise HTTPException(status_code=503, detail="Fetcher not configured")

            if result.content:
                self.db.update_article_content(article.id, result.content)
                updated_article = self.db.get_article(article.id)
                if not updated_article:
                    raise HTTPException(
                        status_code=500, detail="Failed to retrieve article"
                    )
                return updated_article
            else:
                error_msg = "No content extracted"
                if hasattr(result, 'original_error') and result.original_error:
                    error_msg = result.original_error
                raise HTTPException(
                    status_code=400, detail=f"Failed to fetch content: {error_msg}"
                )

        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to fetch content: {e}")

    def extract_from_html(self, article_id: int, html: str, url: str) -> DBArticle:
        """
        Extract article content from pre-fetched HTML.

        Used when the client fetches the page with browser authentication
        and sends the HTML to the backend for extraction only.

        Args:
            article_id: Article to update
            html: HTML content to extract from
            url: URL for context

        Returns:
            Updated article with extracted content

        Raises:
            HTTPException: If extraction fails
        """
        if not html or len(html) < 100:
            raise HTTPException(
                status_code=400, detail="HTML content is too short or empty"
            )

        try:
            if self.fetcher:
                result = self.fetcher._extract_content(url, html)
            else:
                raise HTTPException(status_code=503, detail="Fetcher not configured")

            if result.content:
                self.db.update_article_content(article_id, result.content)
                article = self.db.get_article(article_id)
                if not article:
                    raise HTTPException(
                        status_code=500, detail="Failed to retrieve article"
                    )
                return article
            else:
                raise HTTPException(
                    status_code=400, detail="Failed to extract content from HTML"
                )

        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to extract content: {e}")

    async def extract_source_url(
        self,
        article: DBArticle,
        force: bool = False,
    ) -> dict:
        """
        Extract original source URL for an aggregator article.

        Args:
            article: Article to extract source from
            force: Re-extract even if source_url exists

        Returns:
            Dict with success, source_url, aggregator, confidence, error
        """
        extractor = SourceExtractor()

        if article.source_url and not force:
            aggregator = extractor.identify_aggregator(article.url)
            return {
                "success": True,
                "source_url": article.source_url,
                "aggregator": aggregator,
                "confidence": 1.0,
                "error": None,
            }

        if not extractor.is_aggregator(article.url):
            return {
                "success": False,
                "source_url": None,
                "aggregator": None,
                "confidence": 0.0,
                "error": "Not an aggregator URL",
            }

        result = await extractor.extract(article.url, article.content or "")

        if result.source_url:
            self.db.update_article_source_url(article.id, result.source_url)

        return {
            "success": result.source_url is not None,
            "source_url": result.source_url,
            "aggregator": result.aggregator,
            "confidence": result.confidence,
            "error": result.error,
        }

    # ─────────────────────────────────────────────────────────────
    # State Management
    # ─────────────────────────────────────────────────────────────

    def mark_read(self, user_id: int, article_id: int, is_read: bool = True) -> None:
        """Mark a single article as read/unread."""
        self.db.mark_read(user_id, article_id, is_read)

    def bulk_mark_read(
        self,
        user_id: int,
        article_ids: list[int],
        is_read: bool = True,
    ) -> int:
        """
        Mark multiple articles as read/unread.

        Args:
            user_id: User ID
            article_ids: List of article IDs to mark
            is_read: Mark as read (True) or unread (False)

        Returns:
            Number of articles marked

        Raises:
            HTTPException: If validation fails
        """
        if not article_ids:
            raise HTTPException(status_code=400, detail="No article IDs provided")

        if len(article_ids) > 1000:
            raise HTTPException(
                status_code=400, detail="Maximum 1000 articles per request"
            )

        self.db.bulk_mark_read(user_id, article_ids, is_read)
        return len(article_ids)

    def mark_feed_read(
        self,
        user_id: int,
        feed_id: int,
        is_read: bool = True,
    ) -> int:
        """Mark all articles in a feed as read/unread."""
        return self.db.mark_feed_read(user_id, feed_id, is_read)

    def mark_all_read(self, user_id: int, is_read: bool = True) -> int:
        """Mark all articles as read/unread."""
        return self.db.mark_all_read(user_id, is_read)

    def toggle_bookmark(self, user_id: int, article_id: int) -> bool:
        """Toggle bookmark status for an article."""
        return self.db.toggle_bookmark(user_id, article_id)

    # ─────────────────────────────────────────────────────────────
    # Stats & Maintenance
    # ─────────────────────────────────────────────────────────────

    def get_duplicates(self) -> tuple[list[tuple], set[int]]:
        """
        Get information about duplicate articles.

        Returns:
            Tuple of (duplicate_groups, duplicate_ids_set)
        """
        duplicates = self.db.get_duplicate_articles()
        duplicate_ids = self.db.get_duplicate_article_ids()
        return duplicates, duplicate_ids

    def get_article_stats(self, user_id: int) -> dict:
        """Get statistics about articles in the database."""
        return self.db.get_article_stats(user_id)

    def archive_old_articles(self, days: int = 30) -> int:
        """
        Archive (delete) old shared articles.

        Args:
            days: Archive articles older than this many days

        Returns:
            Number of articles archived
        """
        return self.db.archive_old_articles(days=days)

    # ─────────────────────────────────────────────────────────────
    # Summarization
    # ─────────────────────────────────────────────────────────────

    def schedule_summarization(
        self,
        article: DBArticle,
        background_tasks: BackgroundTasks,
    ) -> None:
        """
        Schedule article summarization as a background task.

        Args:
            article: Article to summarize
            background_tasks: FastAPI background tasks

        Raises:
            HTTPException: If summarizer not configured or content insufficient
        """
        if not self.summarizer:
            raise HTTPException(
                status_code=503, detail="Summarization not configured"
            )

        content = require_sufficient_content(
            article.content,
            "Article has insufficient content. Try using 'Fetch Source Article' first."
        )

        # Use source_url for aggregator articles (more accurate context)
        url_for_summary = article.source_url or article.url

        background_tasks.add_task(
            summarize_article,
            article.id,
            content,
            url_for_summary,
            article.title
        )
