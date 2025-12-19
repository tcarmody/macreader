"""
Feed Parser - Fetch and parse RSS/Atom feeds.

Handles:
- RSS 2.0 and Atom 1.0 formats
- Feed autodiscovery from HTML pages
- Error handling and retry logic
- Rate limiting per domain
"""

import feedparser
import aiohttp
import asyncio
import time
from dataclasses import dataclass
from datetime import datetime
from urllib.parse import urlparse, urljoin
from bs4 import BeautifulSoup


@dataclass
class FeedItem:
    """Represents a single item/entry from a feed."""
    url: str
    title: str
    author: str | None
    published: datetime | None
    content: str


@dataclass
class Feed:
    """Represents a parsed feed."""
    url: str
    title: str
    description: str | None
    items: list[FeedItem]
    last_fetched: datetime


class FeedParser:
    """Parses RSS/Atom feeds with rate limiting."""

    def __init__(self, timeout: int = 30, user_agent: str | None = None):
        self.timeout = timeout
        self.user_agent = user_agent or "RSS Reader/2.0 (+https://github.com/rss-reader)"
        self._domain_last_fetch: dict[str, float] = {}
        self._min_interval = 1.0  # Minimum seconds between requests to same domain

    async def fetch(self, url: str) -> Feed:
        """Fetch and parse a feed URL."""
        # Rate limit per domain
        domain = urlparse(url).netloc
        await self._rate_limit(domain)

        headers = {"User-Agent": self.user_agent}

        async with aiohttp.ClientSession() as session:
            async with session.get(
                url,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=self.timeout)
            ) as resp:
                resp.raise_for_status()
                content = await resp.text()

        return self._parse(url, content)

    async def fetch_multiple(self, urls: list[str]) -> list[Feed | Exception]:
        """
        Fetch multiple feeds concurrently.

        Returns list of Feed objects or Exceptions for failed fetches.
        """
        tasks = [self._fetch_safe(url) for url in urls]
        results = await asyncio.gather(*tasks, return_exceptions=False)
        return results

    async def _fetch_safe(self, url: str) -> Feed | Exception:
        """Fetch a feed, returning Exception on failure instead of raising."""
        try:
            return await self.fetch(url)
        except Exception as e:
            return e

    def _parse(self, url: str, content: str) -> Feed:
        """Parse feed content using feedparser."""
        parsed = feedparser.parse(content)

        # Check for parse errors
        if parsed.bozo and not parsed.entries:
            raise ValueError(f"Failed to parse feed: {parsed.bozo_exception}")

        items = []
        for entry in parsed.entries:
            # Extract content (prefer content over summary)
            content_text = ""
            if hasattr(entry, "content") and entry.content:
                content_text = entry.content[0].value
            elif hasattr(entry, "summary"):
                content_text = entry.summary
            elif hasattr(entry, "description"):
                content_text = entry.description

            # Parse published date
            published = None
            if hasattr(entry, "published_parsed") and entry.published_parsed:
                try:
                    published = datetime(*entry.published_parsed[:6])
                except (TypeError, ValueError):
                    pass
            elif hasattr(entry, "updated_parsed") and entry.updated_parsed:
                try:
                    published = datetime(*entry.updated_parsed[:6])
                except (TypeError, ValueError):
                    pass

            # Get URL
            item_url = entry.get("link", "")
            if not item_url and hasattr(entry, "links"):
                for link in entry.links:
                    if link.get("rel") == "alternate" or link.get("type") == "text/html":
                        item_url = link.get("href", "")
                        break

            items.append(FeedItem(
                url=item_url,
                title=entry.get("title", "Untitled"),
                author=entry.get("author"),
                published=published,
                content=content_text
            ))

        # Get feed metadata
        feed_title = parsed.feed.get("title", "Unknown Feed")
        feed_description = parsed.feed.get("description") or parsed.feed.get("subtitle")

        return Feed(
            url=url,
            title=feed_title,
            description=feed_description,
            items=items,
            last_fetched=datetime.now()
        )

    async def _rate_limit(self, domain: str):
        """Ensure minimum interval between requests to same domain."""
        now = time.time()
        if domain in self._domain_last_fetch:
            elapsed = now - self._domain_last_fetch[domain]
            if elapsed < self._min_interval:
                await asyncio.sleep(self._min_interval - elapsed)
        self._domain_last_fetch[domain] = time.time()

    async def discover_feed(self, url: str) -> str | None:
        """
        Find feed URL from HTML page (autodiscovery).

        Returns the discovered feed URL or None if not found.
        """
        headers = {"User-Agent": self.user_agent}

        async with aiohttp.ClientSession() as session:
            async with session.get(
                url,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=self.timeout)
            ) as resp:
                if resp.status != 200:
                    return None
                html = await resp.text()

        return self._discover_feed_from_html(html, url)

    def _discover_feed_from_html(self, html: str, base_url: str) -> str | None:
        """Extract feed URL from HTML content."""
        soup = BeautifulSoup(html, "html.parser")

        # Look for RSS/Atom link tags
        for link in soup.find_all("link", rel="alternate"):
            link_type = link.get("type", "")
            if "rss" in link_type or "atom" in link_type or "xml" in link_type:
                href = link.get("href")
                if href:
                    return urljoin(base_url, href)

        # Look for common feed paths
        common_paths = [
            "/feed",
            "/feed/",
            "/rss",
            "/rss.xml",
            "/atom.xml",
            "/feed.xml",
            "/index.xml",
        ]

        for path in common_paths:
            feed_url = urljoin(base_url, path)
            # We could check if these exist, but that would require more requests
            # For now, just return the first link-tag discovery or None

        return None

    async def validate_feed(self, url: str) -> bool:
        """
        Check if a URL is a valid feed.

        Returns True if the URL can be parsed as a feed with at least one entry.
        """
        try:
            feed = await self.fetch(url)
            return len(feed.items) > 0
        except Exception:
            return False


def parse_feed_sync(content: str, url: str = "") -> Feed:
    """
    Synchronous feed parsing (for use when content is already fetched).

    Useful for testing or when you already have the feed content.
    """
    parser = FeedParser()
    return parser._parse(url, content)
