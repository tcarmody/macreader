"""
Content Fetcher - Extract article content from URLs.

Handles:
- HTTP fetching with proper headers
- HTML content extraction (removes boilerplate)
- Integration points for JS renderer and archive services (future)
"""

import aiohttp
import re
import hashlib
from dataclasses import dataclass
from bs4 import BeautifulSoup


@dataclass
class FetchResult:
    """Result of fetching and extracting article content."""
    url: str
    title: str
    content: str
    author: str | None = None
    published: str | None = None
    source: str = "direct"  # "direct", "archive", "js_render"
    content_hash: str | None = None


class Fetcher:
    """Fetches and extracts content from web pages."""

    # Known paywalled domains
    PAYWALLED_DOMAINS = [
        "wsj.com",
        "nytimes.com",
        "ft.com",
        "economist.com",
        "bloomberg.com",
        "washingtonpost.com",
        "theathletic.com",
        "businessinsider.com",
        "barrons.com",
        "telegraph.co.uk",
        "thetimes.co.uk",
    ]

    def __init__(
        self,
        timeout: int = 30,
        user_agent: str | None = None,
        min_content_length: int = 500
    ):
        self.timeout = timeout
        self.user_agent = user_agent or (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        )
        self.min_content_length = min_content_length
        self.headers = {
            "User-Agent": self.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br",
            "DNT": "1",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
            "Cache-Control": "max-age=0",
        }

    async def fetch(self, url: str, force_js: bool = False) -> FetchResult:
        """
        Fetch and extract content from URL.

        Args:
            url: The URL to fetch
            force_js: If True, would use JS rendering (not implemented in core)

        Returns:
            FetchResult with extracted content

        Note: JS rendering and archive fallback are deferred to advanced/ module.
        This core implementation does simple HTTP fetch only.
        """
        result = await self._simple_fetch(url)

        # Check if content looks paywalled
        if self._looks_paywalled(result.content, url):
            result.source = "paywalled"

        return result

    async def _simple_fetch(self, url: str) -> FetchResult:
        """Basic HTTP fetch and content extraction."""
        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.get(
                url,
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                allow_redirects=True
            ) as resp:
                resp.raise_for_status()
                html = await resp.text()
                final_url = str(resp.url)

        result = self._extract_content(final_url, html)
        return result

    def _extract_content(self, url: str, html: str) -> FetchResult:
        """Extract article content from HTML."""
        soup = BeautifulSoup(html, "html.parser")

        # Remove unwanted elements
        for tag in soup.find_all([
            "script", "style", "nav", "header", "footer", "aside",
            "noscript", "iframe", "form", "button", "input"
        ]):
            tag.decompose()

        # Remove common ad/social elements
        for selector in [
            "[class*='ad-']", "[class*='advertisement']",
            "[class*='social']", "[class*='share']",
            "[class*='related']", "[class*='recommended']",
            "[class*='newsletter']", "[class*='subscribe']",
            "[id*='comment']", "[class*='comment']",
        ]:
            for element in soup.select(selector):
                element.decompose()

        # Try to find article content
        article = (
            soup.find("article") or
            soup.find(class_=re.compile(r"^(article|post|post-content|entry-content|story)$", re.I)) or
            soup.find(attrs={"role": "main"}) or
            soup.find("main") or
            soup.find(class_=re.compile(r"content|body", re.I)) or
            soup.body
        )

        # Extract content as HTML (preserving formatting)
        content = ""
        if article:
            # Get content elements and keep HTML structure
            content_parts = []
            for elem in article.find_all(["p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "pre"]):
                # Get outer HTML to preserve formatting
                html = str(elem)
                if elem.get_text(strip=True):  # Skip empty elements
                    content_parts.append(html)
            content = "\n".join(content_parts)

        # If HTML extraction yielded little, fall back to inner HTML of article
        if len(content) < 100 and article:
            content = str(article)

        # Clean up excessive whitespace in content
        content = re.sub(r"\n{3,}", "\n\n", content)

        # Extract title
        title = ""
        if title_tag := soup.find("title"):
            title = title_tag.get_text(strip=True)
        if not title:
            if h1 := soup.find("h1"):
                title = h1.get_text(strip=True)
        if not title:
            if og_title := soup.find("meta", property="og:title"):
                title = og_title.get("content", "")

        # Clean title (remove site name suffix)
        title = re.sub(r"\s*[|\-–—]\s*[^|\-–—]+$", "", title)

        # Extract author
        author = None
        if author_meta := soup.find("meta", {"name": "author"}):
            author = author_meta.get("content")
        if not author:
            if author_meta := soup.find("meta", property="article:author"):
                author = author_meta.get("content")
        if not author:
            author_elem = soup.find(class_=re.compile(r"author|byline", re.I))
            if author_elem:
                author = author_elem.get_text(strip=True)

        # Extract published date
        published = None
        if date_meta := soup.find("meta", property="article:published_time"):
            published = date_meta.get("content")
        if not published:
            if time_elem := soup.find("time", datetime=True):
                published = time_elem.get("datetime")

        # Generate content hash for deduplication
        content_hash = hashlib.sha256(content.encode()).hexdigest()[:16]

        return FetchResult(
            url=url,
            title=title or "Untitled",
            content=content,
            author=author,
            published=published,
            source="direct",
            content_hash=content_hash
        )

    def _looks_paywalled(self, content: str, url: str) -> bool:
        """
        Heuristic check if content appears to be behind a paywall.

        Returns True if:
        - Domain is known to be paywalled, or
        - Content contains paywall indicators and is short
        """
        # First check for bot detection / CAPTCHA pages
        if self._looks_blocked(content):
            return True

        # Check known paywalled domains
        for domain in self.PAYWALLED_DOMAINS:
            if domain in url.lower():
                # Even paywalled sites sometimes have full content
                # Only flag if content is suspiciously short
                if len(content) < 1000:
                    return True

        # Check for paywall indicators in content
        paywall_phrases = [
            "subscribe to continue",
            "subscription required",
            "sign in to read",
            "become a member",
            "subscribers only",
            "paywall",
            "this article is for subscribers",
            "to read the full article",
            "already a subscriber",
            "free articles remaining",
        ]

        content_lower = content.lower()
        for phrase in paywall_phrases:
            if phrase in content_lower:
                # Short content + paywall phrase = likely paywalled
                if len(content) < 2000:
                    return True

        return False

    def _looks_blocked(self, content: str) -> bool:
        """
        Check if content looks like a bot detection / CAPTCHA page.

        Returns True if the content appears to be a block page rather than article content.
        """
        content_lower = content.lower()

        # Bot detection / CAPTCHA indicators
        block_phrases = [
            "unusual activity",
            "detected unusual",
            "you're not a robot",
            "not a robot",
            "captcha",
            "verify you are human",
            "human verification",
            "security check",
            "please verify",
            "access denied",
            "blocked",
            "cloudflare",
            "just a moment",
            "checking your browser",
            "enable javascript and cookies",
            "browser supports javascript",
            "ray id",
            "reference id",
            "why did this happen",
            "click the box below",
            "complete the security check",
            "pardon our interruption",
            "we need to verify",
        ]

        matches = sum(1 for phrase in block_phrases if phrase in content_lower)

        # If multiple block indicators and short content, it's likely a block page
        if matches >= 2 and len(content) < 3000:
            return True

        # Single strong indicator with very short content
        strong_indicators = ["captcha", "not a robot", "unusual activity", "access denied"]
        if any(ind in content_lower for ind in strong_indicators) and len(content) < 2000:
            return True

        return False

    def has_sufficient_content(self, content: str) -> bool:
        """Check if extracted content meets minimum threshold."""
        return len(content) >= self.min_content_length


async def fetch_url(url: str, timeout: int = 30) -> FetchResult:
    """Convenience function to fetch a single URL."""
    fetcher = Fetcher(timeout=timeout)
    return await fetcher.fetch(url)
