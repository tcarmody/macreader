"""
Content Fetcher - Extract article content from URLs.

Handles:
- HTTP fetching with proper headers
- HTML content extraction using trafilatura (reader-mode)
- Fallback to BeautifulSoup for edge cases
- SSRF protection via URL validation
- Integration points for JS renderer and archive services (future)
"""

import aiohttp
import re
import hashlib
from dataclasses import dataclass
from bs4 import BeautifulSoup

from .url_validator import validate_url, SSRFError
from .site_extractors import extract_with_site_extractor, ExtractedContent

try:
    import trafilatura
    from trafilatura.settings import use_config
    TRAFILATURA_AVAILABLE = True
except ImportError:
    TRAFILATURA_AVAILABLE = False


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

    # Enhanced metadata (populated by site-specific extractors)
    reading_time_minutes: int | None = None
    word_count: int | None = None
    categories: list[str] | None = None
    tags: list[str] | None = None
    featured_image: str | None = None
    has_code_blocks: bool = False
    code_languages: list[str] | None = None
    is_paywalled: bool = False
    site_name: str | None = None
    extractor_used: str = "generic"


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

        Raises:
            SSRFError: If URL targets internal network or blocked resources

        Note: JS rendering and archive fallback are deferred to advanced/ module.
        This core implementation does simple HTTP fetch only.
        """
        # Validate URL to prevent SSRF attacks
        validate_url(url)

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
        """Extract article content from HTML using site-specific, trafilatura, or BeautifulSoup extraction."""
        # Try site-specific extractor first (for Medium, Substack, GitHub, etc.)
        site_result = extract_with_site_extractor(url, html)
        if site_result and self.has_sufficient_content(site_result.content):
            return self._convert_site_extraction(url, site_result)

        # Try trafilatura (reader-mode extraction)
        if TRAFILATURA_AVAILABLE:
            result = self._extract_with_trafilatura(url, html)
            if result and self.has_sufficient_content(result.content):
                return result

        # Fallback to BeautifulSoup heuristics
        return self._extract_with_beautifulsoup(url, html)

    def _convert_site_extraction(self, url: str, extracted: ExtractedContent) -> FetchResult:
        """Convert site-specific extraction result to FetchResult."""
        content_hash = hashlib.sha256(extracted.content.encode()).hexdigest()[:16]

        return FetchResult(
            url=extracted.canonical_url or url,
            title=extracted.title or "Untitled",
            content=extracted.content,
            author=extracted.author,
            published=extracted.published,
            source="direct",
            content_hash=content_hash,
            reading_time_minutes=extracted.reading_time_minutes,
            word_count=extracted.word_count,
            categories=extracted.categories if extracted.categories else None,
            tags=extracted.tags if extracted.tags else None,
            featured_image=extracted.featured_image,
            has_code_blocks=extracted.has_code_blocks,
            code_languages=extracted.code_languages if extracted.code_languages else None,
            is_paywalled=extracted.is_paywalled,
            site_name=extracted.site_name,
            extractor_used=extracted.extractor_used,
        )

    def _extract_with_trafilatura(self, url: str, html: str) -> FetchResult | None:
        """Extract content using trafilatura (Mozilla Readability-style extraction)."""
        try:
            # Configure trafilatura for better extraction
            config = use_config()
            config.set("DEFAULT", "EXTRACTION_TIMEOUT", "30")

            # Extract main content as HTML (preserves formatting)
            content = trafilatura.extract(
                html,
                url=url,
                output_format="html",
                include_links=True,
                include_images=False,
                include_tables=True,
                favor_recall=True,  # Prefer more content over precision
                config=config,
            )

            if not content:
                return None

            # Extract metadata separately
            metadata = trafilatura.extract_metadata(html, default_url=url)

            title = metadata.title if metadata else None
            author = metadata.author if metadata else None
            published = None
            if metadata and metadata.date:
                published = metadata.date

            # Generate content hash
            content_hash = hashlib.sha256(content.encode()).hexdigest()[:16]

            # Fall back to BeautifulSoup for title if not found
            soup = BeautifulSoup(html, "html.parser")
            if not title:
                if title_tag := soup.find("title"):
                    title = title_tag.get_text(strip=True)
                    title = re.sub(r"\s*[|\-–—]\s*[^|\-–—]+$", "", title)

            # Calculate word count and reading time
            text_content = BeautifulSoup(content, "html.parser").get_text()
            word_count = len(text_content.split())
            reading_time = max(1, round(word_count / 225))

            # Check for code blocks
            has_code = bool(soup.find("pre") or soup.find("code"))
            code_languages = self._extract_code_languages(soup) if has_code else None

            # Extract featured image
            featured_image = None
            if og_image := soup.find("meta", property="og:image"):
                featured_image = og_image.get("content")

            # Extract site name
            site_name = None
            if og_site := soup.find("meta", property="og:site_name"):
                site_name = og_site.get("content")

            # Extract categories from meta tags
            categories = None
            if article_section := soup.find("meta", property="article:section"):
                categories = [article_section.get("content")]
            elif keywords := soup.find("meta", {"name": "keywords"}):
                kw_content = keywords.get("content", "")
                if kw_content:
                    categories = [k.strip() for k in kw_content.split(",")[:5]]

            return FetchResult(
                url=url,
                title=title or "Untitled",
                content=content,
                author=author,
                published=published,
                source="direct",
                content_hash=content_hash,
                reading_time_minutes=reading_time,
                word_count=word_count,
                categories=categories,
                featured_image=featured_image,
                has_code_blocks=has_code,
                code_languages=code_languages,
                site_name=site_name,
                extractor_used="trafilatura",
            )
        except Exception:
            # If trafilatura fails, return None to trigger fallback
            return None

    def _extract_with_beautifulsoup(self, url: str, html: str) -> FetchResult:
        """Fallback extraction using BeautifulSoup heuristics."""
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
            "please enable javascript",
            "javascript is required",
            "enablejs",
            "retry/enablejs",
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

    def _extract_code_languages(self, soup: BeautifulSoup) -> list[str]:
        """Extract programming languages from code blocks in the HTML."""
        languages = set()

        # Check class names on pre/code blocks
        for code in soup.find_all(['pre', 'code']):
            classes = code.get('class', [])
            if isinstance(classes, str):
                classes = [classes]
            for cls in classes:
                # Common patterns: language-python, lang-js, highlight-ruby, hljs-javascript
                match = re.match(r'(?:language-|lang-|highlight-|hljs-)(\w+)', cls)
                if match:
                    lang = match.group(1).lower()
                    # Normalize common variants
                    lang_map = {
                        'js': 'javascript',
                        'ts': 'typescript',
                        'py': 'python',
                        'rb': 'ruby',
                        'yml': 'yaml',
                        'sh': 'bash',
                        'shell': 'bash',
                    }
                    languages.add(lang_map.get(lang, lang))

        # Also check data-language attributes
        for elem in soup.find_all(attrs={'data-language': True}):
            languages.add(elem['data-language'].lower())

        return list(languages) if languages else None


async def fetch_url(url: str, timeout: int = 30) -> FetchResult:
    """Convenience function to fetch a single URL."""
    fetcher = Fetcher(timeout=timeout)
    return await fetcher.fetch(url)
