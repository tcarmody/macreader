"""
Base classes for site-specific extractors.
"""

import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from bs4 import BeautifulSoup


@dataclass
class ExtractedContent:
    """Enhanced content extraction result with rich metadata."""
    title: str
    content: str  # HTML content
    author: str | None = None
    published: str | None = None  # ISO format date

    # Enhanced metadata
    reading_time_minutes: int | None = None
    word_count: int | None = None
    categories: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)

    # Series/collection info
    series_name: str | None = None
    series_part: int | None = None
    series_total: int | None = None

    # Media
    featured_image: str | None = None
    images: list[str] = field(default_factory=list)
    has_video: bool = False
    video_embed_url: str | None = None

    # Content indicators
    is_paywalled: bool = False
    is_truncated: bool = False
    has_code_blocks: bool = False
    code_languages: list[str] = field(default_factory=list)

    # Source info
    site_name: str | None = None
    canonical_url: str | None = None
    extractor_used: str = "generic"


class SiteExtractor(ABC):
    """Base class for site-specific extractors."""

    # Domains this extractor handles
    DOMAINS: list[str] = []

    @classmethod
    def can_handle(cls, url: str) -> bool:
        """Check if this extractor can handle the given URL."""
        url_lower = url.lower()
        return any(domain in url_lower for domain in cls.DOMAINS)

    @abstractmethod
    def extract(self, url: str, html: str) -> ExtractedContent:
        """Extract content from the HTML."""
        pass

    def _estimate_reading_time(self, text: str) -> int:
        """Estimate reading time in minutes based on word count."""
        words = len(text.split())
        # Average reading speed: 200-250 words per minute
        return max(1, round(words / 225))

    def _extract_code_languages(self, soup: BeautifulSoup) -> list[str]:
        """Extract programming languages from code blocks."""
        languages = set()

        # Check class names on pre/code blocks
        for code in soup.find_all(['pre', 'code']):
            classes = code.get('class', [])
            for cls in classes:
                # Common patterns: language-python, lang-js, highlight-ruby
                match = re.match(r'(?:language-|lang-|highlight-)(\w+)', cls)
                if match:
                    languages.add(match.group(1).lower())

        # Also check data-language attributes
        for elem in soup.find_all(attrs={'data-language': True}):
            languages.add(elem['data-language'].lower())

        return list(languages)

    def _clean_html_content(self, soup: BeautifulSoup) -> str:
        """Remove unwanted elements and return cleaned HTML."""
        # Remove common noise elements
        for selector in [
            'script', 'style', 'nav', 'header', 'footer', 'aside',
            'noscript', 'iframe', 'form', 'button', 'input',
            '[class*="ad-"]', '[class*="advertisement"]',
            '[class*="social"]', '[class*="share"]',
            '[class*="related"]', '[class*="recommended"]',
            '[class*="newsletter"]', '[class*="subscribe"]',
            '[id*="comment"]', '[class*="comment"]',
        ]:
            for elem in soup.select(selector):
                elem.decompose()

        return str(soup)
