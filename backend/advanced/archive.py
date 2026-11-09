"""
Archive Services - Fetch content from web archives to bypass paywalls.

Supports:
- Archive.today (archive.is, archive.ph)
- Ghostarchive (ghostarchive.org)
- Wayback Machine (web.archive.org)

Google Cache is deliberately absent: Google shut it down in 2024 and the
endpoint now answers 200 with a stub page for every URL.

These services often have cached versions of articles that were
captured before the paywall or have full content available.
"""

import asyncio
import logging
import re
from collections.abc import AsyncIterator
from contextlib import aclosing
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional
from urllib.parse import quote, urlparse

import aiohttp

logger = logging.getLogger(__name__)


@dataclass
class ArchiveResult:
    """Result of fetching from an archive service."""
    url: str
    original_url: str
    html: str
    source: str  # "archive.today", "archive.ph", "ghostarchive", "wayback"
    cached_date: datetime | None
    success: bool
    error: str | None = None


class ArchiveService:
    """
    Fetches content from various web archive services.

    Queries several archives concurrently:
    - Archive.today / Archive.ph - Often has full article content
    - Ghostarchive - Sometimes has content others don't
    - Wayback Machine - Historical snapshots
    """

    def __init__(
        self,
        timeout: float = 10,
        max_age_days: int = 30,  # Maximum age of cached content
        user_agent: str | None = None,
    ):
        self.timeout = timeout
        self.max_age_days = max_age_days
        self.user_agent = user_agent or (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        )
        self.headers = {
            "User-Agent": self.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        }

    async def fetch(self, url: str) -> ArchiveResult:
        """
        Try to fetch content from archive services.

        Returns the first service to answer with content.

        Args:
            url: Original URL to find in archives

        Returns:
            ArchiveResult with archived content if found
        """
        async with aclosing(self.iter_results(url)) as results:
            async for result in results:
                return result

        # No archive found
        return ArchiveResult(
            url=url,
            original_url=url,
            html="",
            source="none",
            cached_date=None,
            success=False,
            error="No archived version found"
        )

    async def iter_results(self, url: str) -> AsyncIterator[ArchiveResult]:
        """
        Query every archive service at once, yielding hits as they arrive.

        Services run concurrently, each capped at self.timeout, so a service
        that never answers (archive.today stalls non-browser clients) costs
        one timeout in total rather than one per service. Callers that stop
        early should wrap this in contextlib.aclosing so the stragglers are
        cancelled.
        """
        services = [
            ("archive.today", self._fetch_archive_today),
            ("archive.ph", self._fetch_archive_ph),
            ("ghostarchive", self._fetch_ghostarchive),
            ("wayback", self._fetch_wayback),
        ]

        async def run(service_name, fetch_func):
            try:
                return await asyncio.wait_for(fetch_func(url), self.timeout)
            except Exception as e:
                logger.debug(f"Failed to fetch from {service_name}: {e!r}")
                return None

        tasks = [asyncio.create_task(run(name, func)) for name, func in services]
        try:
            for next_done in asyncio.as_completed(tasks):
                result = await next_done
                if result and result.success and result.html:
                    logger.info(f"Found {url} in {result.source}")
                    yield result
        finally:
            for task in tasks:
                task.cancel()

    async def _fetch_archive_today(self, url: str) -> ArchiveResult:
        """
        Fetch from Archive.today (archive.is, archive.ph).

        Archive.today often captures full article content including
        content that's normally behind paywalls.
        """
        # Archive.today search API
        search_url = f"https://archive.today/newest/{url}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(
                search_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                # If we get a 200, we have an archived version
                if resp.status == 200:
                    html = await resp.text()
                    final_url = str(resp.url)

                    # Extract the archive date from the URL if possible
                    cached_date = self._parse_archive_today_date(final_url)

                    # Check if content is too old
                    if cached_date and self._is_too_old(cached_date):
                        return ArchiveResult(
                            url=final_url,
                            original_url=url,
                            html="",
                            source="archive.today",
                            cached_date=cached_date,
                            success=False,
                            error="Cached version too old"
                        )

                    return ArchiveResult(
                        url=final_url,
                        original_url=url,
                        html=html,
                        source="archive.today",
                        cached_date=cached_date,
                        success=True
                    )

                # 404 means no archive exists
                return ArchiveResult(
                    url=url,
                    original_url=url,
                    html="",
                    source="archive.today",
                    cached_date=None,
                    success=False,
                    error=f"Not found (status {resp.status})"
                )

    async def _fetch_archive_ph(self, url: str) -> ArchiveResult:
        """
        Fetch from Archive.ph (alternative endpoint).

        Sometimes archive.ph has different cached versions than archive.today.
        """
        search_url = f"https://archive.ph/newest/{url}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(
                search_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                if resp.status == 200:
                    html = await resp.text()
                    final_url = str(resp.url)

                    cached_date = self._parse_archive_today_date(final_url)

                    if cached_date and self._is_too_old(cached_date):
                        return ArchiveResult(
                            url=final_url,
                            original_url=url,
                            html="",
                            source="archive.ph",
                            cached_date=cached_date,
                            success=False,
                            error="Cached version too old"
                        )

                    return ArchiveResult(
                        url=final_url,
                        original_url=url,
                        html=html,
                        source="archive.ph",
                        cached_date=cached_date,
                        success=True
                    )

                return ArchiveResult(
                    url=url,
                    original_url=url,
                    html="",
                    source="archive.ph",
                    cached_date=None,
                    success=False,
                    error=f"Not found (status {resp.status})"
                )

    async def _fetch_ghostarchive(self, url: str) -> ArchiveResult:
        """
        Fetch from Ghostarchive.org.

        A newer archive service that sometimes has content others don't.
        """
        search_url = f"https://ghostarchive.org/search?term={quote(url, safe='')}"

        async with aiohttp.ClientSession(headers=self.headers) as session:
            # First search for the URL
            async with session.get(
                search_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                if resp.status != 200:
                    return ArchiveResult(
                        url=url,
                        original_url=url,
                        html="",
                        source="ghostarchive",
                        cached_date=None,
                        success=False,
                        error=f"Search failed (status {resp.status})"
                    )

                search_html = await resp.text()

                # Look for archive link in search results
                # Ghostarchive links look like: /archive/xxxxx
                match = re.search(r'href="(/archive/[^"]+)"', search_html)
                if not match:
                    return ArchiveResult(
                        url=url,
                        original_url=url,
                        html="",
                        source="ghostarchive",
                        cached_date=None,
                        success=False,
                        error="No archive found"
                    )

                archive_path = match.group(1)
                archive_url = f"https://ghostarchive.org{archive_path}"

            # Fetch the actual archived page
            async with session.get(
                archive_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                if resp.status != 200:
                    return ArchiveResult(
                        url=archive_url,
                        original_url=url,
                        html="",
                        source="ghostarchive",
                        cached_date=None,
                        success=False,
                        error=f"Failed to fetch archive (status {resp.status})"
                    )

                html = await resp.text()

                return ArchiveResult(
                    url=archive_url,
                    original_url=url,
                    html=html,
                    source="ghostarchive",
                    cached_date=None,  # Ghostarchive doesn't expose dates easily
                    success=True
                )

    async def _fetch_wayback(self, url: str) -> ArchiveResult:
        """
        Fetch from the Wayback Machine (Internet Archive).

        Uses the CDX API to find the most recent snapshot.
        """
        # CDX API to find available snapshots
        cdx_url = (
            f"https://web.archive.org/cdx/search/cdx"
            f"?url={quote(url, safe='')}"
            f"&output=json"
            f"&limit=1"
            f"&sort=reverse"  # Most recent first
        )

        async with aiohttp.ClientSession(headers=self.headers) as session:
            # First, check if there's an archived version
            async with session.get(
                cdx_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout)
            ) as resp:
                if resp.status != 200:
                    return ArchiveResult(
                        url=url,
                        original_url=url,
                        html="",
                        source="wayback",
                        cached_date=None,
                        success=False,
                        error=f"CDX API error (status {resp.status})"
                    )

                data = await resp.json()

                # Response is [header, ...rows], need at least one row
                if len(data) < 2:
                    return ArchiveResult(
                        url=url,
                        original_url=url,
                        html="",
                        source="wayback",
                        cached_date=None,
                        success=False,
                        error="No snapshots found"
                    )

                # Extract timestamp and URL from the most recent snapshot
                # Format: [urlkey, timestamp, original, mimetype, statuscode, digest, length]
                snapshot = data[1]
                timestamp = snapshot[1]
                original_url = snapshot[2]

                # Parse the timestamp (format: YYYYMMDDHHmmss)
                cached_date = self._parse_wayback_date(timestamp)

                # Check if too old
                if cached_date and self._is_too_old(cached_date):
                    return ArchiveResult(
                        url=url,
                        original_url=url,
                        html="",
                        source="wayback",
                        cached_date=cached_date,
                        success=False,
                        error="Cached version too old"
                    )

            # Fetch the actual archived page
            archive_url = f"https://web.archive.org/web/{timestamp}id_/{original_url}"

            async with session.get(
                archive_url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                if resp.status != 200:
                    return ArchiveResult(
                        url=archive_url,
                        original_url=url,
                        html="",
                        source="wayback",
                        cached_date=cached_date,
                        success=False,
                        error=f"Failed to fetch archive (status {resp.status})"
                    )

                html = await resp.text()

                # Remove Wayback Machine toolbar/banner
                html = self._clean_wayback_html(html)

                return ArchiveResult(
                    url=archive_url,
                    original_url=url,
                    html=html,
                    source="wayback",
                    cached_date=cached_date,
                    success=True
                )

    def _is_too_old(self, cached_date: datetime) -> bool:
        """Check if the cached date is older than the maximum allowed age."""
        max_age = timedelta(days=self.max_age_days)
        return datetime.now() - cached_date > max_age

    def _parse_archive_today_date(self, url: str) -> datetime | None:
        """Extract the archive date from an archive.today URL."""
        # URL format: https://archive.today/2024.01.15-123456/...
        match = re.search(r"archive\.\w+/(\d{4})\.(\d{2})\.(\d{2})", url)
        if match:
            try:
                return datetime(
                    int(match.group(1)),
                    int(match.group(2)),
                    int(match.group(3))
                )
            except ValueError:
                pass
        return None

    def _parse_wayback_date(self, timestamp: str) -> datetime | None:
        """Parse Wayback Machine timestamp (YYYYMMDDHHmmss)."""
        try:
            return datetime.strptime(timestamp[:14], "%Y%m%d%H%M%S")
        except (ValueError, IndexError):
            return None

    def _clean_wayback_html(self, html: str) -> str:
        """Remove Wayback Machine toolbar and scripts from HTML."""
        # Remove the Wayback banner/toolbar
        html = re.sub(
            r'<!-- BEGIN WAYBACK TOOLBAR INSERT -->.*?<!-- END WAYBACK TOOLBAR INSERT -->',
            '',
            html,
            flags=re.DOTALL
        )

        # Remove Wayback-specific scripts
        html = re.sub(
            r'<script[^>]*src="[^"]*web\.archive\.org[^"]*"[^>]*>.*?</script>',
            '',
            html,
            flags=re.DOTALL | re.IGNORECASE
        )

        return html


# Global service instance
_service: Optional[ArchiveService] = None


def get_archive_service() -> ArchiveService:
    """Get or create the global archive service instance."""
    global _service
    if _service is None:
        _service = ArchiveService()
    return _service


async def fetch_from_archive(url: str) -> ArchiveResult:
    """
    Convenience function to fetch from archives.

    Args:
        url: Original URL to find in archives

    Returns:
        ArchiveResult with archived content if found
    """
    service = get_archive_service()
    return await service.fetch(url)
