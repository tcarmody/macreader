"""
Feed service: business logic for feed management operations.

Handles feed subscription, refresh, OPML import/export, and feed discovery.
"""

import re
from typing import TYPE_CHECKING
from urllib.parse import urljoin, urlparse

import httpx
from fastapi import BackgroundTasks, HTTPException

from ..database import Database
from ..database.models import DBFeed
from ..exceptions import require_feed
from ..opml import parse_opml, generate_opml, OPMLFeed
from ..schemas import OPMLImportResult, DiscoveredFeed
from ..tasks import refresh_all_feeds, refresh_single_feed, fetch_feed_articles

if TYPE_CHECKING:
    from ..feed_parser import FeedParser


class FeedService:
    """Service for feed-related business logic."""

    def __init__(
        self,
        db: Database,
        feed_parser: "FeedParser | None" = None,
    ):
        self.db = db
        self.feed_parser = feed_parser
        # Import state here to avoid circular imports - used for refresh flag
        from ..config import state
        self._state = state

    # ─────────────────────────────────────────────────────────────
    # Feed Management
    # ─────────────────────────────────────────────────────────────

    def list_feeds(self, user_id: int | None = None) -> list[DBFeed]:
        """
        List all subscribed feeds.

        Args:
            user_id: Optional user ID for per-user unread counts

        Returns:
            List of feeds
        """
        return self.db.get_feeds(user_id)

    async def subscribe(
        self,
        url: str,
        background_tasks: BackgroundTasks,
        name: str | None = None,
        category: str | None = None,
    ) -> DBFeed:
        """
        Subscribe to a new feed.

        Args:
            url: Feed URL to subscribe to
            background_tasks: FastAPI background tasks for article fetching
            name: Optional custom name (uses feed title if not provided)
            category: Optional category for organization

        Returns:
            The created feed

        Raises:
            HTTPException: If feed parser not configured or URL invalid
        """
        if not self.feed_parser:
            raise HTTPException(status_code=500, detail="Feed parser not initialized")

        # Validate feed URL by fetching it
        try:
            feed = await self.feed_parser.fetch(url)
            feed_name = name or feed.title
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid feed URL: {e}")

        # Add to database
        try:
            feed_id = self.db.add_feed(url, feed_name, category=category)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Feed already exists or error: {e}")

        # Fetch articles in background
        background_tasks.add_task(fetch_feed_articles, feed_id, feed)

        db_feed = self.db.get_feed(feed_id)
        if not db_feed:
            raise HTTPException(status_code=500, detail="Failed to retrieve feed")

        return db_feed

    async def discover(self, url: str) -> list[DiscoveredFeed]:
        """
        Discover RSS/Atom feeds at a given URL.

        Two-tier approach:
        1. Parse <link rel="alternate"> tags from the page HTML
        2. Probe common feed paths if no link tags found
        """
        # Normalise: ensure scheme present
        if not url.startswith(("http://", "https://")):
            url = "https://" + url

        candidates: list[DiscoveredFeed] = []

        headers = {"User-Agent": "DataPointsAI/1.0 (feed discovery)"}
        try:
            async with httpx.AsyncClient(follow_redirects=True, timeout=10) as client:
                resp = await client.get(url, headers=headers)
                resp.raise_for_status()
                html = resp.text
                final_url = str(resp.url)
        except httpx.HTTPError as e:
            raise HTTPException(status_code=400, detail=f"Could not fetch URL: {e}")

        # Tier 1: <link rel="alternate" type="application/rss+xml|atom+xml">
        pattern = re.compile(
            r'<link[^>]+rel=["\']alternate["\'][^>]*>',
            re.IGNORECASE,
        )
        type_pattern = re.compile(r'type=["\']application/(rss|atom)\+xml["\']', re.IGNORECASE)
        href_pattern = re.compile(r'href=["\']([^"\']+)["\']', re.IGNORECASE)
        title_pattern = re.compile(r'title=["\']([^"\']*)["\']', re.IGNORECASE)

        for tag in pattern.finditer(html):
            tag_str = tag.group(0)
            if not type_pattern.search(tag_str):
                continue
            href_match = href_pattern.search(tag_str)
            if not href_match:
                continue
            feed_url = urljoin(final_url, href_match.group(1))
            title_match = title_pattern.search(tag_str)
            candidates.append(DiscoveredFeed(
                url=feed_url,
                title=title_match.group(1) if title_match else None,
            ))

        if candidates:
            return candidates

        # Tier 2: probe common paths
        base = f"{urlparse(final_url).scheme}://{urlparse(final_url).netloc}"
        common_paths = ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/feed/atom"]
        async with httpx.AsyncClient(follow_redirects=True, timeout=8) as client:
            for path in common_paths:
                probe_url = base + path
                try:
                    r = await client.get(probe_url, headers=headers)
                    content_type = r.headers.get("content-type", "")
                    if r.status_code == 200 and any(
                        ct in content_type for ct in ("rss", "atom", "xml")
                    ):
                        candidates.append(DiscoveredFeed(url=probe_url))
                        break
                except httpx.HTTPError:
                    continue

        return candidates

    def unsubscribe(self, feed_id: int) -> None:
        """
        Unsubscribe from a feed.

        Args:
            feed_id: ID of feed to remove

        Raises:
            HTTPException: If feed not found
        """
        require_feed(self.db.get_feed(feed_id))
        self.db.delete_feed(feed_id)

    def bulk_unsubscribe(self, feed_ids: list[int]) -> int:
        """
        Unsubscribe from multiple feeds.

        Args:
            feed_ids: List of feed IDs to remove

        Returns:
            Number of feeds removed

        Raises:
            HTTPException: If validation fails
        """
        if not feed_ids:
            raise HTTPException(status_code=400, detail="No feed IDs provided")

        if len(feed_ids) > 100:
            raise HTTPException(status_code=400, detail="Maximum 100 feeds per request")

        self.db.bulk_delete_feeds(feed_ids)
        return len(feed_ids)

    def update_feed(
        self,
        feed_id: int,
        name: str | None = None,
        category: str | None = None,
    ) -> DBFeed:
        """
        Update a feed's name or category.

        Args:
            feed_id: ID of feed to update
            name: New name (optional)
            category: New category (empty string to clear, None to keep)

        Returns:
            Updated feed

        Raises:
            HTTPException: If feed not found
        """
        require_feed(self.db.get_feed(feed_id))

        # Empty string means clear category
        clear_category = category == ""
        actual_category = None if clear_category else category

        self.db.update_feed(
            feed_id,
            name=name,
            category=actual_category,
            clear_category=clear_category
        )

        updated_feed = self.db.get_feed(feed_id)
        if not updated_feed:
            raise HTTPException(status_code=500, detail="Failed to retrieve updated feed")

        return updated_feed

    # ─────────────────────────────────────────────────────────────
    # Refresh
    # ─────────────────────────────────────────────────────────────

    def schedule_refresh_all(self, background_tasks: BackgroundTasks) -> bool:
        """
        Schedule a refresh of all feeds.

        Args:
            background_tasks: FastAPI background tasks

        Returns:
            True if refresh was scheduled, False if already in progress
        """
        if self._state.refresh_in_progress:
            return False

        background_tasks.add_task(refresh_all_feeds)
        return True

    def schedule_refresh_feed(
        self,
        feed_id: int,
        background_tasks: BackgroundTasks,
    ) -> None:
        """
        Schedule a refresh of a specific feed.

        Args:
            feed_id: ID of feed to refresh
            background_tasks: FastAPI background tasks

        Raises:
            HTTPException: If feed not found
        """
        feed = require_feed(self.db.get_feed(feed_id))
        background_tasks.add_task(refresh_single_feed, feed_id, feed.url)

    # ─────────────────────────────────────────────────────────────
    # OPML Import/Export
    # ─────────────────────────────────────────────────────────────

    async def _import_single_feed(
        self,
        opml_feed: OPMLFeed,
        existing_urls: set[str],
        background_tasks: BackgroundTasks,
    ) -> OPMLImportResult:
        """
        Import a single feed from OPML.

        Args:
            opml_feed: OPML feed entry to import
            existing_urls: Set of already-subscribed URLs (lowercase)
            background_tasks: FastAPI background tasks

        Returns:
            Import result with success/error details
        """
        # Skip if already subscribed
        if opml_feed.url.lower() in existing_urls:
            return OPMLImportResult(
                url=opml_feed.url,
                name=opml_feed.title,
                success=False,
                error="Already subscribed"
            )

        try:
            parsed_feed = await self.feed_parser.fetch(opml_feed.url)
            feed_name = opml_feed.title or parsed_feed.title

            feed_id = self.db.add_feed(
                url=opml_feed.url,
                name=feed_name,
                category=opml_feed.category
            )

            background_tasks.add_task(fetch_feed_articles, feed_id, parsed_feed)

            return OPMLImportResult(
                url=opml_feed.url,
                name=feed_name,
                success=True,
                feed_id=feed_id
            )

        except Exception as e:
            return OPMLImportResult(
                url=opml_feed.url,
                name=opml_feed.title,
                success=False,
                error=str(e)
            )

    async def import_opml(
        self,
        opml_content: str,
        background_tasks: BackgroundTasks,
    ) -> dict:
        """
        Import feeds from OPML content.

        Args:
            opml_content: Raw OPML XML content
            background_tasks: FastAPI background tasks

        Returns:
            Dict with total, imported, skipped, failed counts and results list

        Raises:
            HTTPException: If feed parser not configured or OPML invalid
        """
        if not self.feed_parser:
            raise HTTPException(status_code=500, detail="Feed parser not initialized")

        # Parse OPML
        try:
            opml_doc = parse_opml(opml_content)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid OPML: {e}")

        if not opml_doc.feeds:
            raise HTTPException(status_code=400, detail="No feeds found in OPML")

        # Get existing feed URLs to skip duplicates
        existing_feeds = self.db.get_feeds()
        existing_urls = {f.url.lower() for f in existing_feeds}

        # Import each feed
        results: list[OPMLImportResult] = []
        for opml_feed in opml_doc.feeds:
            result = await self._import_single_feed(
                opml_feed, existing_urls, background_tasks
            )
            results.append(result)
            if result.success:
                existing_urls.add(opml_feed.url.lower())

        # Count results
        imported = sum(1 for r in results if r.success)
        skipped = sum(1 for r in results if not r.success and r.error == "Already subscribed")
        failed = sum(1 for r in results if not r.success and r.error != "Already subscribed")

        return {
            "total": len(opml_doc.feeds),
            "imported": imported,
            "skipped": skipped,
            "failed": failed,
            "results": results,
        }

    def export_opml(self, title: str = "Data Points AI Feeds") -> dict:
        """
        Export all feeds as OPML.

        Args:
            title: Title for the OPML document

        Returns:
            Dict with opml content and feed_count
        """
        feeds = self.db.get_feeds()

        opml_feeds = [
            OPMLFeed(
                url=f.url,
                title=f.name,
                category=f.category
            )
            for f in feeds
        ]

        opml_content = generate_opml(opml_feeds, title=title)

        return {
            "opml": opml_content,
            "feed_count": len(feeds)
        }
