"""
Source URL Extractor - Extract original article URLs from news aggregators.

Supported aggregators:
- Techmeme: Parses source link from description HTML
- Google News: Decodes encoded redirect URLs via API + base64
- Reddit: Fetches thread page to find external link
- Hacker News: Already provides source URLs in RSS (passthrough)
"""

import aiohttp
import asyncio
import base64
import json
import re
import logging
from dataclasses import dataclass
from urllib.parse import urlparse, parse_qs, unquote
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)


@dataclass
class ExtractionResult:
    """Result of source URL extraction."""
    source_url: str | None
    aggregator: str | None  # "techmeme", "google_news", "reddit", "hackernews"
    confidence: float  # 0.0-1.0
    error: str | None = None


class SourceExtractor:
    """Extracts original source URLs from news aggregator links."""

    # Aggregator domain patterns
    AGGREGATOR_PATTERNS = {
        "techmeme": ["techmeme.com"],
        "google_news": ["news.google.com"],
        "reddit": ["reddit.com", "redd.it"],
        "hackernews": ["news.ycombinator.com"],
    }

    def __init__(self, timeout: int = 15):
        self.timeout = timeout
        self.headers = {
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        }

    def identify_aggregator(self, url: str) -> str | None:
        """Identify which aggregator a URL belongs to."""
        url_lower = url.lower()
        for aggregator, domains in self.AGGREGATOR_PATTERNS.items():
            if any(domain in url_lower for domain in domains):
                return aggregator
        return None

    def is_aggregator(self, url: str) -> bool:
        """Check if URL is from a known aggregator."""
        return self.identify_aggregator(url) is not None

    async def extract(self, url: str, content: str = "") -> ExtractionResult:
        """
        Extract source URL from an aggregator link.

        Args:
            url: The aggregator URL
            content: Optional RSS item content/description (for Techmeme)

        Returns:
            ExtractionResult with source URL if found
        """
        aggregator = self.identify_aggregator(url)

        if not aggregator:
            return ExtractionResult(
                source_url=None,
                aggregator=None,
                confidence=0.0,
                error="Not a known aggregator"
            )

        try:
            if aggregator == "techmeme":
                return await self._extract_techmeme(url, content)
            elif aggregator == "google_news":
                return await self._extract_google_news(url)
            elif aggregator == "reddit":
                return await self._extract_reddit(url)
            elif aggregator == "hackernews":
                return self._extract_hackernews(url, content)
            else:
                return ExtractionResult(
                    source_url=None,
                    aggregator=aggregator,
                    confidence=0.0,
                    error=f"No handler for {aggregator}"
                )
        except Exception as e:
            logger.error(f"Extraction failed for {url}: {e}")
            return ExtractionResult(
                source_url=None,
                aggregator=aggregator,
                confidence=0.0,
                error=str(e)
            )

    async def extract_batch(
        self,
        items: list[tuple[str, str]]
    ) -> list[ExtractionResult]:
        """
        Extract source URLs for multiple items.

        Args:
            items: List of (url, content) tuples

        Returns:
            List of ExtractionResult in same order as input
        """
        # Group Google News URLs for batch processing
        google_news_indices = []
        google_news_urls = []
        other_tasks = []
        results: list[ExtractionResult | None] = [None] * len(items)

        for i, (url, content) in enumerate(items):
            aggregator = self.identify_aggregator(url)
            if aggregator == "google_news":
                google_news_indices.append(i)
                google_news_urls.append(url)
            else:
                other_tasks.append((i, self.extract(url, content)))

        # Process non-Google News items concurrently
        if other_tasks:
            other_results = await asyncio.gather(
                *[task for _, task in other_tasks],
                return_exceptions=True
            )
            for (idx, _), result in zip(other_tasks, other_results):
                if isinstance(result, Exception):
                    results[idx] = ExtractionResult(
                        source_url=None,
                        aggregator=self.identify_aggregator(items[idx][0]),
                        confidence=0.0,
                        error=str(result)
                    )
                else:
                    results[idx] = result

        # Batch process Google News URLs
        if google_news_urls:
            gn_results = await self._extract_google_news_batch(google_news_urls)
            for idx, result in zip(google_news_indices, gn_results):
                results[idx] = result

        return results  # type: ignore

    # --- Techmeme ---

    async def _extract_techmeme(self, url: str, content: str) -> ExtractionResult:
        """
        Extract source URL from Techmeme.

        Techmeme RSS includes the source link in the description HTML.
        Techmeme URLs often have a fragment like #a251224p15 that identifies
        the specific article on the page.
        """
        if content:
            soup = BeautifulSoup(content, "html.parser")
            # Find first external link in description
            for link in soup.find_all("a", href=True):
                href = link["href"]
                if href.startswith("http") and "techmeme.com" not in href.lower():
                    return ExtractionResult(
                        source_url=href,
                        aggregator="techmeme",
                        confidence=0.9
                    )

        # Fallback: fetch the Techmeme page and find the source link
        try:
            # Extract fragment from URL (e.g., #a251224p15 -> a251224p15)
            parsed = urlparse(url)
            fragment = parsed.fragment  # e.g., "a251224p15"

            async with aiohttp.ClientSession(headers=self.headers) as session:
                async with session.get(
                    url,
                    timeout=aiohttp.ClientTimeout(total=self.timeout)
                ) as resp:
                    if resp.status == 200:
                        html = await resp.text()
                        soup = BeautifulSoup(html, "html.parser")

                        # If we have a fragment, find the specific article section
                        if fragment:
                            # Find the anchor element for this article
                            anchor = soup.find("a", {"name": fragment})
                            if anchor:
                                # The anchor is inside the cluster div
                                # First try to find the parent cluster
                                cluster = anchor.find_parent("div", class_="clus")
                                if not cluster:
                                    # Fallback: maybe the cluster follows the anchor
                                    cluster = anchor.find_next("div", class_="clus")
                                if cluster:
                                    # Find the main article link (in .ii div or with .ourh class)
                                    link = cluster.select_one(".ii a[href^='http']")
                                    if not link:
                                        link = cluster.select_one("a.ourh[href^='http']")
                                    if link:
                                        href = link.get("href", "")
                                        if href and "techmeme.com" not in href.lower():
                                            return ExtractionResult(
                                                source_url=href,
                                                aggregator="techmeme",
                                                confidence=0.95
                                            )

                        # Fallback: Try .ourh class for main story links (homepage)
                        link = soup.select_one("a.ourh[href^='http']")
                        if link and "techmeme.com" not in link["href"].lower():
                            return ExtractionResult(
                                source_url=link["href"],
                                aggregator="techmeme",
                                confidence=0.7
                            )

                        # Last fallback: first external link in any .ii div
                        for link in soup.select(".ii a[href^='http']"):
                            href = link.get("href", "")
                            if href and "techmeme.com" not in href.lower():
                                return ExtractionResult(
                                    source_url=href,
                                    aggregator="techmeme",
                                    confidence=0.5
                                )
        except Exception as e:
            logger.warning(f"Techmeme fetch failed: {e}")

        return ExtractionResult(
            source_url=None,
            aggregator="techmeme",
            confidence=0.0,
            error="Could not find source link"
        )

    # --- Google News ---

    async def _extract_google_news(self, url: str) -> ExtractionResult:
        """
        Extract source URL from Google News encoded link.

        Uses the batchexecute API with signature/timestamp, with base64 fallback.
        """
        # Extract the article ID from URL
        parsed = urlparse(url)
        path_parts = parsed.path.strip("/").split("/")

        article_id = None
        if "articles" in path_parts:
            idx = path_parts.index("articles")
            if idx + 1 < len(path_parts):
                article_id = path_parts[idx + 1].split("?")[0]

        if not article_id:
            # Try query parameter
            params = parse_qs(parsed.query)
            article_id = params.get("article", [None])[0]

        if not article_id:
            return ExtractionResult(
                source_url=None,
                aggregator="google_news",
                confidence=0.0,
                error="Could not extract article ID"
            )

        # Try API decode first
        result = await self._decode_google_news_api(article_id)
        if result.source_url:
            return result

        # Fallback to base64 decode
        return self._decode_google_news_base64(article_id)

    async def _extract_google_news_batch(
        self,
        urls: list[str]
    ) -> list[ExtractionResult]:
        """Batch decode Google News URLs."""
        results = []
        for url in urls:
            result = await self._extract_google_news(url)
            results.append(result)
            # Small delay to avoid rate limiting
            await asyncio.sleep(0.1)
        return results

    async def _decode_google_news_api(self, article_id: str) -> ExtractionResult:
        """Decode Google News URL using batchexecute API."""
        try:
            # First, get signature and timestamp from the article page
            article_url = f"https://news.google.com/rss/articles/{article_id}"

            async with aiohttp.ClientSession(headers=self.headers) as session:
                async with session.get(
                    article_url,
                    timeout=aiohttp.ClientTimeout(total=self.timeout),
                    allow_redirects=True
                ) as resp:
                    if resp.status != 200:
                        return ExtractionResult(
                            source_url=None,
                            aggregator="google_news",
                            confidence=0.0,
                            error=f"HTTP {resp.status}"
                        )

                    html = await resp.text()

                # Check if we got redirected to the actual article
                final_url = str(resp.url)
                if "news.google.com" not in final_url:
                    return ExtractionResult(
                        source_url=final_url,
                        aggregator="google_news",
                        confidence=0.95
                    )

                # Parse for signature and timestamp
                soup = BeautifulSoup(html, "html.parser")
                div = soup.select_one("c-wiz > div")

                if not div:
                    return ExtractionResult(
                        source_url=None,
                        aggregator="google_news",
                        confidence=0.0,
                        error="Could not find data element"
                    )

                signature = div.get("data-n-a-sg")
                timestamp = div.get("data-n-a-ts")

                if not signature or not timestamp:
                    return ExtractionResult(
                        source_url=None,
                        aggregator="google_news",
                        confidence=0.0,
                        error="Missing signature/timestamp"
                    )

                # Call batchexecute API
                payload = json.dumps([
                    [
                        ["Fbv4je", f'["garturlreq",[["X","Y","Z","{article_id}",{timestamp},"{signature}"],1],"generic"]']
                    ]
                ])

                async with session.post(
                    "https://news.google.com/_/DotsSplashUi/data/batchexecute",
                    headers={
                        **self.headers,
                        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"
                    },
                    data=f"f.req={payload}",
                    timeout=aiohttp.ClientTimeout(total=self.timeout)
                ) as api_resp:
                    if api_resp.status != 200:
                        return ExtractionResult(
                            source_url=None,
                            aggregator="google_news",
                            confidence=0.0,
                            error=f"API HTTP {api_resp.status}"
                        )

                    text = await api_resp.text()

                    # Parse response - format is complex nested JSON
                    # Skip the initial ")]}'\\n" prefix
                    if text.startswith(")]}'"):
                        text = text[5:]

                    try:
                        # Find the URL in the response
                        url_match = re.search(r'https?://[^\s"<>]+', text)
                        if url_match:
                            decoded_url = url_match.group(0)
                            # Clean up any JSON escaping
                            decoded_url = decoded_url.replace("\\u003d", "=")
                            decoded_url = decoded_url.replace("\\u0026", "&")
                            decoded_url = unquote(decoded_url)

                            if "news.google.com" not in decoded_url:
                                return ExtractionResult(
                                    source_url=decoded_url,
                                    aggregator="google_news",
                                    confidence=0.9
                                )
                    except Exception as e:
                        logger.warning(f"Failed to parse API response: {e}")

        except asyncio.TimeoutError:
            return ExtractionResult(
                source_url=None,
                aggregator="google_news",
                confidence=0.0,
                error="Timeout"
            )
        except Exception as e:
            logger.warning(f"Google News API decode failed: {e}")

        return ExtractionResult(
            source_url=None,
            aggregator="google_news",
            confidence=0.0,
            error="API decode failed"
        )

    def _decode_google_news_base64(self, article_id: str) -> ExtractionResult:
        """
        Fallback: Try to decode Google News URL from base64.

        This works for older-style URLs but may not work for all.
        """
        try:
            # Add padding if needed
            padded = article_id + "=" * (4 - len(article_id) % 4)

            # Try standard base64
            try:
                decoded = base64.b64decode(padded)
            except Exception:
                # Try URL-safe base64
                decoded = base64.urlsafe_b64decode(padded)

            # Look for URL in decoded bytes
            decoded_str = decoded.decode("utf-8", errors="ignore")

            # Find URL pattern
            url_match = re.search(r'https?://[^\s\x00-\x1f"<>]+', decoded_str)
            if url_match:
                found_url = url_match.group(0).rstrip("\\")
                if "news.google.com" not in found_url:
                    return ExtractionResult(
                        source_url=found_url,
                        aggregator="google_news",
                        confidence=0.7
                    )

        except Exception as e:
            logger.debug(f"Base64 decode failed: {e}")

        return ExtractionResult(
            source_url=None,
            aggregator="google_news",
            confidence=0.0,
            error="Base64 decode failed"
        )

    # --- Reddit ---

    async def _extract_reddit(self, url: str) -> ExtractionResult:
        """
        Extract source URL from Reddit thread.

        Reddit RSS links point to threads; we need to fetch and find external link.
        """
        # Convert to old.reddit.com for easier parsing
        parsed = urlparse(url)
        reddit_url = url.replace("www.reddit.com", "old.reddit.com")

        try:
            async with aiohttp.ClientSession(headers=self.headers) as session:
                async with session.get(
                    reddit_url,
                    timeout=aiohttp.ClientTimeout(total=self.timeout),
                    allow_redirects=True
                ) as resp:
                    if resp.status != 200:
                        return ExtractionResult(
                            source_url=None,
                            aggregator="reddit",
                            confidence=0.0,
                            error=f"HTTP {resp.status}"
                        )

                    html = await resp.text()

            soup = BeautifulSoup(html, "html.parser")

            # Look for the external link in old Reddit format
            # The title link for link posts points to the external URL
            title_link = soup.select_one("a.title[href^='http']")
            if title_link:
                href = title_link.get("href", "")
                if href and "reddit.com" not in href and "redd.it" not in href:
                    return ExtractionResult(
                        source_url=href,
                        aggregator="reddit",
                        confidence=0.9
                    )

            # Try new Reddit selectors if old format didn't work
            for selector in [
                "a[data-click-id='body'][href^='http']",
                ".Post a[href^='http']:not([href*='reddit.com'])",
            ]:
                link = soup.select_one(selector)
                if link:
                    href = link.get("href", "")
                    if href and "reddit.com" not in href and "redd.it" not in href:
                        return ExtractionResult(
                            source_url=href,
                            aggregator="reddit",
                            confidence=0.8
                        )

            # This might be a self-post (text post) with no external link
            return ExtractionResult(
                source_url=None,
                aggregator="reddit",
                confidence=0.0,
                error="No external link found (may be self-post)"
            )

        except asyncio.TimeoutError:
            return ExtractionResult(
                source_url=None,
                aggregator="reddit",
                confidence=0.0,
                error="Timeout"
            )
        except Exception as e:
            logger.warning(f"Reddit extraction failed: {e}")
            return ExtractionResult(
                source_url=None,
                aggregator="reddit",
                confidence=0.0,
                error=str(e)
            )

    # --- Hacker News ---

    def _extract_hackernews(self, url: str, content: str) -> ExtractionResult:
        """
        Handle Hacker News links.

        HN RSS already provides the source URL in <link>, so this is a passthrough.
        The URL passed here should already be the source URL.
        """
        # HN RSS <link> points to source, <comments> points to HN thread
        # If we get a news.ycombinator.com URL, it's a comments link
        if "news.ycombinator.com" in url:
            # This is a Show HN or Ask HN (self-post) - no external source
            return ExtractionResult(
                source_url=None,
                aggregator="hackernews",
                confidence=1.0,
                error="HN self-post (no external source)"
            )

        # The URL is already the source URL
        return ExtractionResult(
            source_url=url,
            aggregator="hackernews",
            confidence=1.0
        )


# Convenience function
async def extract_source_url(url: str, content: str = "") -> ExtractionResult:
    """Extract source URL from an aggregator link."""
    extractor = SourceExtractor()
    return await extractor.extract(url, content)
