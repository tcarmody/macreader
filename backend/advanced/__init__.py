"""
Advanced content fetching features.

This module provides enhanced content extraction capabilities:
- JavaScript rendering for dynamic content (Playwright)
- Archive service integration for paywall bypass
- Enhanced fetcher combining all strategies
"""

from .js_renderer import JSRenderer, render_url, PLAYWRIGHT_AVAILABLE
from .archive import ArchiveService, fetch_from_archive
from .enhanced_fetcher import EnhancedFetcher, EnhancedFetchResult

__all__ = [
    "JSRenderer",
    "render_url",
    "PLAYWRIGHT_AVAILABLE",
    "ArchiveService",
    "fetch_from_archive",
    "EnhancedFetcher",
    "EnhancedFetchResult",
]
