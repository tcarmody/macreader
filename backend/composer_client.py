"""
Composer client — promotes DataPoints articles to the Composer workbench.

Composer runs a separate ingest API (see COMPOSER_ARCHITECTURE.md). We POST
`/v1/ingest/items` with an `X-Ingest-Key` header. Ingest is idempotent on
(source, source_ref), so re-posting the same article is safe.
"""

import json
import logging
from dataclasses import dataclass

import httpx

from .config import Config
from .database.models import DBArticle

logger = logging.getLogger(__name__)


class ComposerError(Exception):
    """Raised when Composer rejects an ingest or is unreachable."""


@dataclass
class PromotionResult:
    composer_id: str
    composer_url: str
    already_existed: bool


def is_configured() -> bool:
    return bool(Config.COMPOSER_URL)


def _build_payload(article: DBArticle) -> dict:
    keywords: list[str] = []
    if article.extracted_keywords:
        try:
            parsed = json.loads(article.extracted_keywords)
            if isinstance(parsed, list):
                keywords = [str(k) for k in parsed if k]
        except json.JSONDecodeError:
            pass

    related_links: list[dict] = []
    if article.related_links:
        try:
            parsed = json.loads(article.related_links)
            links = parsed.get("links") if isinstance(parsed, dict) else parsed
            if isinstance(links, list):
                for link in links:
                    if not isinstance(link, dict):
                        continue
                    url = link.get("url")
                    if not url:
                        continue
                    related_links.append(
                        {
                            "url": url,
                            "title": link.get("title"),
                            "score": link.get("score"),
                        }
                    )
        except json.JSONDecodeError:
            pass

    metadata: dict = {}
    if article.site_name:
        metadata["site_name"] = article.site_name
    if article.word_count is not None:
        metadata["word_count"] = article.word_count
    if article.reading_time_minutes is not None:
        metadata["reading_time_minutes"] = article.reading_time_minutes
    if article.featured_image:
        metadata["featured_image"] = article.featured_image
    if article.feed_name:
        metadata["feed_name"] = article.feed_name

    published_at = (
        article.published_at.isoformat() if article.published_at else None
    )

    return {
        "source": "datapoints",
        "source_ref": str(article.id),
        "url": article.source_url or article.url,
        "title": article.title,
        "author": article.author,
        "published_at": published_at,
        "content": article.content,
        "summary": article.summary_full or article.summary_short,
        "key_points": article.key_points or [],
        "keywords": keywords,
        "related_links": related_links,
        "metadata": metadata,
    }


async def promote_article(
    article: DBArticle,
    *,
    client: httpx.AsyncClient | None = None,
) -> PromotionResult:
    """POST the article to Composer's ingest endpoint."""
    if not is_configured():
        raise ComposerError("Composer integration is not configured")

    payload = _build_payload(article)
    headers = {"Content-Type": "application/json"}
    if Config.COMPOSER_INGEST_KEY:
        headers["X-Ingest-Key"] = Config.COMPOSER_INGEST_KEY

    url = Config.COMPOSER_URL.rstrip("/") + "/v1/ingest/items"

    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=10.0)
    try:
        resp = await client.post(url, json=payload, headers=headers)
    except httpx.HTTPError as exc:
        logger.warning("Composer promote failed: %s", exc)
        raise ComposerError(f"Composer unreachable: {exc}") from exc
    finally:
        if owns_client:
            await client.aclose()

    if resp.status_code >= 400:
        logger.warning(
            "Composer returned %s: %s", resp.status_code, resp.text[:200]
        )
        raise ComposerError(f"Composer returned {resp.status_code}")

    try:
        body = resp.json()
    except ValueError as exc:
        raise ComposerError(f"Invalid Composer response: {exc}") from exc

    return PromotionResult(
        composer_id=body["id"],
        composer_url=body["url"],
        already_existed=bool(body.get("already_existed")),
    )
