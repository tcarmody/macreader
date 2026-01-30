"""
Related links service: business logic for finding related articles using Exa neural search.

Handles query construction, keyword extraction, API calls, and caching
for semantic article discovery.
"""

import re
import json
import hashlib
import logging
from typing import TYPE_CHECKING
from urllib.parse import urlparse

from tenacity import retry, stop_after_attempt, wait_exponential
from exa_py import Exa

from ..extractors import extract_html_text

if TYPE_CHECKING:
    from ..cache import TieredCache
    from ..database.models import DBArticle
    from ..providers.base import LLMProvider

logger = logging.getLogger(__name__)


def construct_search_query(article: "DBArticle", provider: "LLMProvider") -> str:
    """
    Build optimal search query with fallback strategies.

    Priority order:
    1. Title + Key Points (best - from existing summary)
    2. Title + LLM-Extracted Keywords (good - fast Haiku extraction)
    3. Title only (fallback)
    """

    # Strategy 1: Use existing key points (best quality)
    if article.key_points:
        try:
            key_points = json.loads(article.key_points)
            if isinstance(key_points, list) and len(key_points) >= 2:
                return f"{article.title} {key_points[0]} {key_points[1]}"
            elif isinstance(key_points, list) and len(key_points) == 1:
                return f"{article.title} {key_points[0]}"
        except (json.JSONDecodeError, TypeError):
            pass  # Fall through to next strategy

    # Strategy 2: Extract keywords using LLM (fast and accurate)
    if article.content and len(article.content) > 200:
        keywords = extract_keywords_llm(article, provider)
        if keywords:
            return f"{article.title} {' '.join(keywords[:3])}"

    # Strategy 3: Title only (last resort)
    return article.title


def extract_keywords_llm(article: "DBArticle", provider: "LLMProvider") -> list[str]:
    """
    Use Claude Haiku to extract 3-5 key concepts from article.
    Fast (<1s) and cheap (~$0.001 per extraction).
    """
    from ..providers.base import ModelTier

    # Check cache first
    if article.extracted_keywords:
        try:
            return json.loads(article.extracted_keywords)
        except json.JSONDecodeError:
            pass  # Re-extract if cache is corrupted

    # Truncate content to first 2000 chars for speed
    content_preview = extract_html_text(article.content or "")[:2000]

    prompt = f"""Extract 3-5 key concepts or topics from this article. Return ONLY the concepts, one per line, no explanations.

Title: {article.title}

Content preview:
{content_preview}

Key concepts:"""

    # Get fast model (Haiku)
    model = provider.get_model_for_tier(ModelTier.FAST)

    # Call LLM synchronously (we're in a sync context in tasks.py)
    response = provider.complete(
        user_prompt=prompt,
        model=model,
        max_tokens=100
    )

    # Parse response (one keyword per line)
    keywords = [
        line.strip()
        for line in response.text.strip().split('\n')
        if line.strip() and len(line.strip()) > 2
    ][:5]

    # Return keywords (caching happens in caller)
    return keywords


def normalize_cache_key(query: str) -> str:
    """
    Normalize query for consistent caching.
    Handles capitalization and whitespace variations.
    """
    normalized = re.sub(r'\s+', ' ', query.lower().strip())
    hash_digest = hashlib.sha256(normalized.encode()).hexdigest()[:16]
    return f"related_links:{hash_digest}"


class ExaSearchService:
    """Service for finding related articles using Exa neural search API."""

    def __init__(self, api_key: str, cache: "TieredCache", provider: "LLMProvider"):
        """
        Initialize Exa search service.

        Args:
            api_key: Exa API key
            cache: Tiered cache instance
            provider: LLM provider for keyword extraction
        """
        self.client = Exa(api_key)
        self.cache = cache
        self.provider = provider

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10)
    )
    def fetch_related_links(
        self,
        article: "DBArticle",
        num_results: int = 5
    ) -> list[dict]:
        """
        Fetch related links for an article.

        Args:
            article: Article to find related content for
            num_results: Number of results to return (default: 5)

        Returns:
            List of dicts with link data (url, title, snippet, domain, etc.)
        """

        # Construct query
        query = construct_search_query(article, self.provider)
        logger.info(f"Searching for related links with query: {query}")

        # Check cache
        cache_key = normalize_cache_key(query)
        cached = self.cache.get(cache_key)
        if cached:
            logger.info("Cache hit for related links query")
            return cached

        # Call Exa API with more results to allow for deduplication
        try:
            response = self.client.search(
                query=query,
                num_results=num_results + 10  # Request extra for deduplication
            )
        except Exception as e:
            logger.error(f"Exa API error: {e}")
            raise

        # Parse results and deduplicate
        links = []
        seen_titles = set()
        article_domain = self._extract_domain(article.url)
        article_title_lower = article.title.lower().strip()

        for result in response.results:
            result_domain = self._extract_domain(result.url)
            result_title_lower = result.title.lower().strip()

            # Skip if same URL as source article
            if result.url == article.url:
                continue

            # Skip if same domain as source article (likely duplicates)
            if result_domain == article_domain:
                continue

            # Skip if exact title match with source article
            if result_title_lower == article_title_lower:
                continue

            # Skip if we've seen this exact title before
            if result_title_lower in seen_titles:
                continue

            # Limit to 2 results per domain (avoid too many from arxiv.org, etc.)
            domain_count = sum(1 for link in links if link["domain"] == result_domain)
            if domain_count >= 2:
                continue

            links.append({
                "url": result.url,
                "title": result.title,
                "snippet": getattr(result, "text", "")[:200],  # First 200 chars
                "domain": result_domain,
                "published_date": getattr(result, "published_date", None),
                "score": getattr(result, "score", None)
            })

            seen_titles.add(result_title_lower)

            # Stop once we have enough unique results
            if len(links) >= num_results:
                break

        logger.info(f"Found {len(links)} unique related links (from {len(response.results)} total)")

        # Cache for 24 hours
        self.cache.set(cache_key, links, ttl=86400)

        return links

    @staticmethod
    def _extract_domain(url: str) -> str:
        """Extract clean domain from URL."""
        try:
            return urlparse(url).netloc.replace("www.", "")
        except Exception:
            return ""
