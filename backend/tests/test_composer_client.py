"""Tests for the Composer client + /articles/{id}/promote route."""

import httpx
import pytest

from backend import composer_client
from backend.config import Config, state
from backend.database.models import DBArticle
from datetime import datetime


def _fake_article(**overrides) -> DBArticle:
    base = dict(
        id=42,
        feed_id=1,
        url="https://example.com/a",
        title="Fed holds rates",
        content="body",
        summary_short="short",
        summary_full="long summary",
        key_points=["kp1", "kp2"],
        is_read=False,
        is_bookmarked=False,
        published_at=datetime(2026, 4, 10, 12, 0, 0),
        created_at=datetime(2026, 4, 10, 12, 0, 0),
        author="Jane",
        site_name="Example",
        extracted_keywords='["rates","fed"]',
        related_links='{"links":[{"url":"https://x.com","title":"x","score":0.9}]}',
    )
    base.update(overrides)
    return DBArticle(**base)


def test_build_payload_maps_fields():
    payload = composer_client._build_payload(_fake_article())
    assert payload["source"] == "datapoints"
    assert payload["source_ref"] == "42"
    assert payload["title"] == "Fed holds rates"
    assert payload["summary"] == "long summary"
    assert payload["key_points"] == ["kp1", "kp2"]
    assert payload["keywords"] == ["rates", "fed"]
    assert payload["related_links"] == [
        {"url": "https://x.com", "title": "x", "score": 0.9}
    ]
    assert payload["metadata"]["site_name"] == "Example"
    assert payload["published_at"] == "2026-04-10T12:00:00"


def test_build_payload_prefers_source_url_when_present():
    article = _fake_article(
        url="https://aggregator.com/x",
        source_url="https://real.com/x",
    )
    payload = composer_client._build_payload(article)
    assert payload["url"] == "https://real.com/x"


def test_build_payload_tolerates_missing_extracted_fields():
    article = _fake_article(
        extracted_keywords=None,
        related_links=None,
        key_points=None,
    )
    payload = composer_client._build_payload(article)
    assert payload["keywords"] == []
    assert payload["related_links"] == []
    assert payload["key_points"] == []


@pytest.mark.asyncio
async def test_promote_article_sends_and_parses_response(monkeypatch):
    monkeypatch.setattr(Config, "COMPOSER_URL", "https://composer.test")
    monkeypatch.setattr(Config, "COMPOSER_INGEST_KEY", "secret")

    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = dict(request.headers)
        captured["body"] = request.content.decode()
        return httpx.Response(
            201,
            json={
                "id": "cmp-item-abc",
                "url": "composer://item/cmp-item-abc",
                "already_existed": False,
            },
        )

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        result = await composer_client.promote_article(
            _fake_article(), client=client
        )

    assert captured["url"] == "https://composer.test/v1/ingest/items"
    assert captured["headers"]["x-ingest-key"] == "secret"
    assert result.composer_id == "cmp-item-abc"
    assert result.already_existed is False


@pytest.mark.asyncio
async def test_promote_article_raises_on_http_error(monkeypatch):
    monkeypatch.setattr(Config, "COMPOSER_URL", "https://composer.test")
    transport = httpx.MockTransport(
        lambda req: httpx.Response(500, text="boom")
    )
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(composer_client.ComposerError):
            await composer_client.promote_article(
                _fake_article(), client=client
            )


def test_promote_route_503_when_not_configured(
    client_with_data, monkeypatch
):
    client, data = client_with_data
    monkeypatch.setattr(Config, "COMPOSER_URL", "")
    article_id = data["article_ids"][0]
    resp = client.post(f"/articles/{article_id}/promote")
    assert resp.status_code == 503


def test_promote_route_success_marks_db_and_returns_ids(
    client_with_data, monkeypatch
):
    test_client, data = client_with_data
    monkeypatch.setattr(Config, "COMPOSER_URL", "https://composer.test")

    async def fake_promote(article, *, client=None):
        return composer_client.PromotionResult(
            composer_id="cmp-item-xyz",
            composer_url="composer://item/cmp-item-xyz",
            already_existed=False,
        )

    monkeypatch.setattr(composer_client, "promote_article", fake_promote)

    article_id = data["article_ids"][0]
    resp = test_client.post(f"/articles/{article_id}/promote")
    assert resp.status_code == 200
    body = resp.json()
    assert body["composer_id"] == "cmp-item-xyz"
    assert body["already_existed"] is False

    detail = test_client.get(f"/articles/{article_id}").json()
    assert detail["promoted_to_composer"] is not None
