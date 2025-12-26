"""
Site-Specific Content Extractors - Custom extraction logic for common publishers.

Provides specialized extractors for sites that don't work well with generic extraction:
- Medium: Handles paywalled content markers, series info
- Substack: Extracts newsletter-specific metadata
- GitHub: Parses release notes, READMEs, discussions
- YouTube: Extracts video metadata and descriptions
- Twitter/X: Handles thread content
- Wikipedia: Structured article content
- Bloomberg: News article content

Each extractor returns enhanced metadata beyond what trafilatura provides.
"""

from .base import ExtractedContent, SiteExtractor
from .medium import MediumExtractor
from .substack import SubstackExtractor
from .github import GitHubExtractor
from .youtube import YouTubeExtractor
from .twitter import TwitterExtractor
from .wikipedia import WikipediaExtractor
from .bloomberg import BloombergExtractor

# Registry of all extractors
SITE_EXTRACTORS: list[type[SiteExtractor]] = [
    MediumExtractor,
    SubstackExtractor,
    GitHubExtractor,
    YouTubeExtractor,
    TwitterExtractor,
    WikipediaExtractor,
    BloombergExtractor,
]


def get_extractor_for_url(url: str) -> SiteExtractor | None:
    """Get the appropriate site-specific extractor for a URL, if available."""
    for extractor_class in SITE_EXTRACTORS:
        if extractor_class.can_handle(url):
            return extractor_class()
    return None


def extract_with_site_extractor(url: str, html: str) -> ExtractedContent | None:
    """
    Try to extract content using a site-specific extractor.

    Returns None if no site-specific extractor is available.
    """
    import logging
    logger = logging.getLogger(__name__)

    extractor = get_extractor_for_url(url)
    if extractor:
        try:
            return extractor.extract(url, html)
        except Exception as e:
            logger.warning(f"Site extractor failed for {url}: {e}")
            return None
    return None


__all__ = [
    "ExtractedContent",
    "SiteExtractor",
    "SITE_EXTRACTORS",
    "get_extractor_for_url",
    "extract_with_site_extractor",
    "MediumExtractor",
    "SubstackExtractor",
    "GitHubExtractor",
    "YouTubeExtractor",
    "TwitterExtractor",
    "WikipediaExtractor",
    "BloombergExtractor",
]
