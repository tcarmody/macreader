"""
Composer client — promotes DataPoints articles to the Composer workbench.

Composer runs a separate ingest API (see COMPOSER_ARCHITECTURE.md). We POST
`/v1/ingest/items` with an `X-Ingest-Key` header. Ingest is idempotent on
(source, source_ref), so re-posting the same article is safe.

The payload and response shapes are the shared contract in `dpcommon.ingest`,
which Composer's routes use as their request and response models.
"""

import json
import logging
from dataclasses import dataclass

import httpx
from dpcommon.ingest import (
    INGEST_ITEMS_PATH,
    INGEST_KEY_HEADER,
    IngestItem,
    IngestItemResponse,
)
from pydantic import ValidationError

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

    fields = {
        "source": "datapoints",
        # article.url (UNIQUE) rather than the AUTOINCREMENT id: ids diverge
        # between DataPoints instances (local vs Railway), so two instances
        # promoting different articles could collide on the same numeric ref.
        # The URL is stable across instances, so either copy can promote the
        # same article and Composer dedupes to one item.
        "source_ref": article.url,
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
    # Built through the shared contract model, so a payload Composer would
    # reject fails here first
    return IngestItem.model_validate(fields).model_dump(mode="json")


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
        headers[INGEST_KEY_HEADER] = Config.COMPOSER_INGEST_KEY

    url = Config.COMPOSER_URL.rstrip("/") + INGEST_ITEMS_PATH

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
        body = IngestItemResponse.model_validate(resp.json())
    except (ValueError, ValidationError) as exc:
        raise ComposerError(f"Invalid Composer response: {exc}") from exc

    return PromotionResult(
        composer_id=body.id,
        composer_url=body.url,
        already_existed=body.already_existed,
    )
