"""
Enhanced Fetcher - Combines basic fetching with advanced features.

This module wraps the core Fetcher with:
- JavaScript rendering fallback for dynamic content
- Archive service fallback for paywalled content
- Intelligent fallback strategies

Usage:
    from backend.advanced import EnhancedFetcher

    fetcher = EnhancedFetcher(
        enable_js_render=True,
        enable_archive=True
    )
    result = await fetcher.fetch(url)
"""

import logging
from dataclasses import dataclass
from typing import Optional

from ..fetcher import Fetcher, FetchResult
from .js_renderer import JSRenderer, PLAYWRIGHT_AVAILABLE
from .archive import ArchiveService

logger = logging.getLogger(__name__)


@dataclass
class EnhancedFetchResult(FetchResult):
    """Extended result with information about fallback methods used."""
    fallback_used: str | None = None  # "js_render", "archive", None
    archive_source: str | None = None  # "archive.today", "wayback", "google_cache"
    original_error: str | None = None  # Error from primary fetch if fallback was used


class EnhancedFetcher:
    """
    Enhanced content fetcher with JavaScript rendering and archive fallbacks.

    Fetching strategy:
    1. Try simple HTTP fetch
    2. If content is insufficient or paywalled:
       a. If JS rendering enabled and content looks dynamic -> try JS render
       b. If archive enabled and content looks paywalled -> try archives
    3. Return best result available
    """

    def __init__(
        self,
        enable_js_render: bool = True,
        enable_archive: bool = True,
        timeout: int = 30,
        min_content_length: int = 500,
        js_render_timeout: int = 30000,
        archive_max_age_days: int = 30,
    ):
        """
        Initialize the enhanced fetcher.

        Args:
            enable_js_render: Enable JavaScript rendering fallback
            enable_archive: Enable archive service fallback
            timeout: HTTP request timeout in seconds
            min_content_length: Minimum content length to consider valid
            js_render_timeout: Playwright timeout in milliseconds
            archive_max_age_days: Maximum age for archived content
        """
        self.enable_js_render = enable_js_render and PLAYWRIGHT_AVAILABLE
        self.enable_archive = enable_archive
        self.min_content_length = min_content_length

        # Core fetcher
        self._fetcher = Fetcher(
            timeout=timeout,
            min_content_length=min_content_length
        )

        # Advanced services (lazy initialized)
        self._js_renderer: Optional[JSRenderer] = None
        self._archive_service: Optional[ArchiveService] = None

        if self.enable_js_render:
            self._js_renderer = JSRenderer(timeout=js_render_timeout)

        if self.enable_archive:
            self._archive_service = ArchiveService(
                timeout=timeout,
                max_age_days=archive_max_age_days
            )

    async def start(self) -> None:
        """Start any required services (like browser)."""
        if self._js_renderer:
            await self._js_renderer.start()

    async def stop(self) -> None:
        """Stop any running services."""
        if self._js_renderer:
            await self._js_renderer.stop()

    async def fetch(
        self,
        url: str,
        force_js: bool = False,
        force_archive: bool = False,
    ) -> EnhancedFetchResult:
        """
        Fetch content with intelligent fallback.

        Args:
            url: URL to fetch
            force_js: Skip simple fetch and use JS rendering directly
            force_archive: Skip other methods and try archives directly

        Returns:
            EnhancedFetchResult with content and metadata
        """
        original_error = None

        # Strategy 1: Force archive if requested
        if force_archive and self.enable_archive:
            return await self._fetch_from_archive(url)

        # Strategy 2: Force JS render if requested
        if force_js and self.enable_js_render:
            return await self._fetch_with_js(url)

        # Strategy 3: Try simple fetch first
        try:
            result = await self._fetcher.fetch(url)

            # Check if we got good content
            if self._is_good_content(result):
                return EnhancedFetchResult(
                    url=result.url,
                    title=result.title,
                    content=result.content,
                    author=result.author,
                    published=result.published,
                    source=result.source,
                    content_hash=result.content_hash,
                    fallback_used=None,
                )

            # Content is insufficient or paywalled
            original_error = f"Insufficient content ({len(result.content)} chars)"
            if result.source == "paywalled":
                original_error = "Content appears paywalled"

        except Exception as e:
            original_error = str(e)
            result = None
            logger.warning(f"Primary fetch failed for {url}: {e}")

        # Strategy 4: Try JS rendering if content looks like it needs it
        if self.enable_js_render and self._should_try_js_render(result, url):
            js_result = await self._fetch_with_js(url)
            if js_result.fallback_used:  # Means it succeeded
                # Check if JS render result is still a bot detection page
                if not self._is_bot_detection_page(js_result.content):
                    js_result.original_error = original_error
                    return js_result
                else:
                    logger.info(f"JS render returned bot detection page for {url}, trying archive")
                    original_error = "JS render blocked by bot detection"

        # Strategy 5: Try archive if content is paywalled or blocked
        if self.enable_archive and (self._should_try_archive(result, url) or self._is_bot_detection_page(result.content if result else "")):
            archive_result = await self._fetch_from_archive(url)
            if archive_result.fallback_used:  # Means it succeeded
                archive_result.original_error = original_error
                return archive_result

        # Return whatever we have, even if it's not great
        if result:
            return EnhancedFetchResult(
                url=result.url,
                title=result.title,
                content=result.content,
                author=result.author,
                published=result.published,
                source=result.source,
                content_hash=result.content_hash,
                fallback_used=None,
                original_error=original_error,
            )

        # Complete failure
        return EnhancedFetchResult(
            url=url,
            title="Failed to fetch",
            content="",
            source="error",
            fallback_used=None,
            original_error=original_error,
        )

    async def _fetch_with_js(self, url: str) -> EnhancedFetchResult:
        """Fetch using JavaScript rendering."""
        if not self._js_renderer:
            return EnhancedFetchResult(
                url=url,
                title="",
                content="",
                source="error",
                original_error="JS renderer not available"
            )

        try:
            render_result = await self._js_renderer.render(url)

            if not render_result.success:
                return EnhancedFetchResult(
                    url=url,
                    title="",
                    content="",
                    source="error",
                    original_error=render_result.error
                )

            # Extract content from rendered HTML
            fetch_result = self._fetcher._extract_content(
                render_result.final_url,
                render_result.html
            )

            return EnhancedFetchResult(
                url=fetch_result.url,
                title=fetch_result.title,
                content=fetch_result.content,
                author=fetch_result.author,
                published=fetch_result.published,
                source="js_render",
                content_hash=fetch_result.content_hash,
                fallback_used="js_render",
            )

        except Exception as e:
            logger.error(f"JS render failed for {url}: {e}")
            return EnhancedFetchResult(
                url=url,
                title="",
                content="",
                source="error",
                original_error=str(e)
            )

    async def _fetch_from_archive(self, url: str) -> EnhancedFetchResult:
        """Fetch from archive services."""
        if not self._archive_service:
            return EnhancedFetchResult(
                url=url,
                title="",
                content="",
                source="error",
                original_error="Archive service not available"
            )

        try:
            archive_result = await self._archive_service.fetch(url)

            if not archive_result.success:
                return EnhancedFetchResult(
                    url=url,
                    title="",
                    content="",
                    source="error",
                    original_error=archive_result.error
                )

            # Extract content from archived HTML
            fetch_result = self._fetcher._extract_content(
                archive_result.url,
                archive_result.html
            )

            return EnhancedFetchResult(
                url=fetch_result.url,
                title=fetch_result.title,
                content=fetch_result.content,
                author=fetch_result.author,
                published=fetch_result.published,
                source="archive",
                content_hash=fetch_result.content_hash,
                fallback_used="archive",
                archive_source=archive_result.source,
            )

        except Exception as e:
            logger.error(f"Archive fetch failed for {url}: {e}")
            return EnhancedFetchResult(
                url=url,
                title="",
                content="",
                source="error",
                original_error=str(e)
            )

    def _is_good_content(self, result: FetchResult) -> bool:
        """Check if the fetch result has sufficient content."""
        if result.source == "paywalled":
            return False
        return len(result.content) >= self.min_content_length

    def _should_try_js_render(self, result: Optional[FetchResult], url: str) -> bool:
        """Determine if we should try JS rendering."""
        # Known JS-heavy sites
        js_heavy_domains = [
            "medium.com",
            "substack.com",
            "bloomberg.com",
            "reuters.com",
            "twitter.com",
            "x.com",
        ]

        for domain in js_heavy_domains:
            if domain in url.lower():
                return True

        # If we got very little content, might be a JS-rendered site
        if result and len(result.content) < 200:
            return True

        return False

    def _should_try_archive(self, result: Optional[FetchResult], url: str) -> bool:
        """Determine if we should try archive services."""
        # If content is flagged as paywalled
        if result and result.source == "paywalled":
            return True

        # Check known paywalled domains
        for domain in self._fetcher.PAYWALLED_DOMAINS:
            if domain in url.lower():
                return True

        return False

    def _is_bot_detection_page(self, content: str) -> bool:
        """Check if content is a bot detection/CAPTCHA page."""
        if not content:
            return False
        return self._fetcher._looks_blocked(content)
