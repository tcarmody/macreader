"""
Tests for StoryGroupService.

Uses a mock LLM provider — no API keys needed.
"""

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone

import pytest

from backend.providers.base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier
from backend.services.story_groups import StoryGroupService, StoryGroup


# ─── Mock provider ────────────────────────────────────────────────────────────

class MockProvider(LLMProvider):
    """Mock LLM provider that returns pre-configured responses."""

    TIER_MODELS = {
        ModelTier.FAST: "mock-fast",
        ModelTier.STANDARD: "mock-standard",
        ModelTier.ADVANCED: "mock-advanced",
    }

    def __init__(self):
        self.calls: list[dict] = []
        self._responses: list[str] = []
        self._call_index = 0

    @property
    def name(self) -> str:
        return "mock"

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities()

    def queue_response(self, text: str):
        self._responses.append(text)

    def complete(
        self,
        user_prompt: str,
        system_prompt: str | None = None,
        model: str | None = None,
        max_tokens: int = 1024,
        temperature: float = 0.0,
        use_cache: bool = False,
        json_mode: bool = False,
    ) -> LLMResponse:
        self.calls.append({"user_prompt": user_prompt, "model": model})
        text = self._responses[self._call_index] if self._call_index < len(self._responses) else '{"groups": []}'
        self._call_index += 1
        return LLMResponse(text=text, model=model or "mock-fast")


# ─── Minimal mock article ────────────────────────────────────────────────────

def make_article(
    article_id: int,
    title: str = "Article Title",
    word_count: int | None = None,
    published_at: datetime | None = None,
    feed_id: int = 1,
    summary_short: str | None = None,
    content: str | None = "Some article content.",
    site_name: str | None = None,
    feed_name: str | None = "Test Feed",
):
    """Create a minimal DBArticle-like object for testing."""
    from backend.database.models import DBArticle
    return DBArticle(
        id=article_id,
        feed_id=feed_id,
        url=f"https://example.com/{article_id}",
        title=title,
        content=content,
        summary_short=summary_short,
        summary_full=None,
        key_points=None,
        is_read=False,
        is_bookmarked=False,
        published_at=published_at,
        created_at=datetime(2026, 3, 28),
        word_count=word_count,
        site_name=site_name,
        feed_name=feed_name,
    )


# ─── detect_groups tests ──────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_detect_groups_finds_matching_pair():
    """LLM returns 1 group of 2 articles — service returns correct StoryGroup."""
    provider = MockProvider()
    provider.queue_response(json.dumps({
        "groups": [
            {"label": "GPT-5 launched by OpenAI", "article_ids": [1, 2]}
        ]
    }))

    articles = [
        make_article(1, title="OpenAI releases GPT-5", word_count=800),
        make_article(2, title="GPT-5 arrives with 2M token context", word_count=500),
        make_article(3, title="EU AI Act implementation timeline", word_count=400),
    ]

    service = StoryGroupService(db=None, provider=provider, cache=None)
    groups = await service.detect_groups(articles)

    assert len(groups) == 1
    g = groups[0]
    assert g.id is None
    assert g.label == "GPT-5 launched by OpenAI"
    assert set(g.member_ids) == {1, 2}
    assert g.representative_id == 1  # highest word_count


@pytest.mark.asyncio
async def test_detect_groups_no_overlap_returns_empty():
    """LLM returns no groups — service returns empty list."""
    provider = MockProvider()
    provider.queue_response('{"groups": []}')

    articles = [
        make_article(1, title="Apple earnings beat estimates"),
        make_article(2, title="UK AI regulation bill passes"),
        make_article(3, title="OpenAI publishes reasoning research"),
    ]

    service = StoryGroupService(db=None, provider=provider, cache=None)
    groups = await service.detect_groups(articles)

    assert groups == []


@pytest.mark.asyncio
async def test_detect_groups_malformed_json_returns_empty():
    """LLM returns malformed JSON — service falls back to empty list."""
    provider = MockProvider()
    provider.queue_response("This is not JSON at all, sorry!")

    articles = [
        make_article(1, title="Article A"),
        make_article(2, title="Article B"),
    ]

    service = StoryGroupService(db=None, provider=provider, cache=None)
    groups = await service.detect_groups(articles)

    assert groups == []


@pytest.mark.asyncio
async def test_detect_groups_fewer_than_two_articles():
    """Single article — skip LLM call and return empty."""
    provider = MockProvider()
    service = StoryGroupService(db=None, provider=provider, cache=None)

    groups = await service.detect_groups([make_article(1)])
    assert groups == []
    assert len(provider.calls) == 0


@pytest.mark.asyncio
async def test_detect_groups_ignores_unknown_article_ids():
    """LLM returns an article_id not in our list — it is silently dropped."""
    provider = MockProvider()
    provider.queue_response(json.dumps({
        "groups": [
            {"label": "Some event", "article_ids": [1, 99]}  # 99 doesn't exist
        ]
    }))

    articles = [make_article(1), make_article(2)]
    service = StoryGroupService(db=None, provider=provider, cache=None)
    groups = await service.detect_groups(articles)

    # Group has only 1 valid member (1), 99 is unknown → filtered out (< 2 members)
    assert groups == []


@pytest.mark.asyncio
async def test_detect_groups_strips_markdown_fences():
    """LLM wraps JSON in markdown code fences — service strips and parses."""
    provider = MockProvider()
    provider.queue_response('```json\n{"groups": [{"label": "FTX verdict", "article_ids": [1, 2]}]}\n```')

    articles = [make_article(1), make_article(2)]
    service = StoryGroupService(db=None, provider=provider, cache=None)
    groups = await service.detect_groups(articles)

    assert len(groups) == 1
    assert groups[0].label == "FTX verdict"


# ─── _pick_representative tests ───────────────────────────────────────────────

def test_pick_representative_highest_word_count():
    articles = [
        make_article(1, word_count=200),
        make_article(2, word_count=800),
        make_article(3, word_count=400),
    ]
    assert StoryGroupService._pick_representative(articles) == 2


def test_pick_representative_tie_breaks_on_oldest():
    """When word_count is equal, older published_at wins."""
    articles = [
        make_article(1, word_count=500, published_at=datetime(2026, 3, 28, 12, 0)),
        make_article(2, word_count=500, published_at=datetime(2026, 3, 28, 8, 0)),  # older
        make_article(3, word_count=500, published_at=datetime(2026, 3, 28, 18, 0)),
    ]
    assert StoryGroupService._pick_representative(articles) == 2


def test_pick_representative_no_word_count_uses_zero():
    """Articles with no word_count (None) are treated as 0."""
    articles = [
        make_article(1, word_count=None),
        make_article(2, word_count=300),
    ]
    assert StoryGroupService._pick_representative(articles) == 2


# ─── Cache tests ──────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_cache_hit_skips_provider_call(temp_cache_dir, test_db):
    """After first detection, a second identical call uses cache and skips LLM."""
    from backend.cache import create_cache
    cache = create_cache(temp_cache_dir)

    provider = MockProvider()
    provider.queue_response(json.dumps({
        "groups": [{"label": "GPT-5 launch", "article_ids": [1, 2]}]
    }))

    # Insert articles into DB (get_articles_since will query these)
    feed_id = test_db.add_feed(url="https://example.com/feed.xml", name="Test Feed")
    from datetime import timedelta
    since = datetime(2026, 3, 27)
    published = datetime(2026, 3, 28)
    test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/1",
        title="OpenAI releases GPT-5",
        content="OpenAI announced GPT-5 today.",
        published_at=published,
        word_count=800,
    )
    test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/2",
        title="GPT-5 arrives with new features",
        content="The new GPT-5 model is here.",
        published_at=published,
        word_count=500,
    )

    service = StoryGroupService(db=test_db, provider=provider, cache=cache)

    # First call — cache miss, LLM called
    groups1 = await service.get_or_detect_for_window(since=since)
    assert len(provider.calls) == 1

    # Second call — cache hit, LLM NOT called again
    groups2 = await service.get_or_detect_for_window(since=since)
    assert len(provider.calls) == 1  # still 1
    assert len(groups2) == len(groups1)


@pytest.mark.asyncio
async def test_force_refresh_bypasses_cache(temp_cache_dir, test_db):
    """force_refresh=True re-runs detection even when cache is warm."""
    from backend.cache import create_cache
    cache = create_cache(temp_cache_dir)

    provider = MockProvider()
    # Queue two responses — second should be used on force refresh
    provider.queue_response(json.dumps({
        "groups": [{"label": "GPT-5 launch", "article_ids": [1, 2]}]
    }))
    provider.queue_response(json.dumps({
        "groups": [{"label": "GPT-5 launch updated", "article_ids": [1, 2]}]
    }))

    feed_id = test_db.add_feed(url="https://example.com/feed.xml", name="Test Feed")
    since = datetime(2026, 3, 27)
    published = datetime(2026, 3, 28)
    test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/1",
        title="OpenAI releases GPT-5",
        content="OpenAI announced GPT-5 today.",
        published_at=published,
        word_count=800,
    )
    test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/2",
        title="GPT-5 arrives with new features",
        content="The new GPT-5 model is here.",
        published_at=published,
        word_count=500,
    )

    service = StoryGroupService(db=test_db, provider=provider, cache=cache)

    await service.get_or_detect_for_window(since=since)
    assert len(provider.calls) == 1

    await service.get_or_detect_for_window(since=since, force_refresh=True)
    assert len(provider.calls) == 2


# ─── get_group_for_article tests ─────────────────────────────────────────────

def test_get_group_for_article_not_found(test_db):
    """Article not in any group returns None."""
    import asyncio
    service = StoryGroupService(db=test_db, provider=MockProvider(), cache=None)
    result = asyncio.get_event_loop().run_until_complete(
        service.get_group_for_article(article_id=999)
    )
    assert result is None


@pytest.mark.asyncio
async def test_get_group_for_article_returns_group(test_db):
    """Article that belongs to a saved group is found correctly."""
    provider = MockProvider()
    feed_id = test_db.add_feed(url="https://example.com/feed.xml", name="Test Feed")
    published = datetime(2026, 3, 28)
    aid1 = test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/1",
        title="Article 1",
        content="Content 1",
        published_at=published,
        word_count=800,
    )
    aid2 = test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/2",
        title="Article 2",
        content="Content 2",
        published_at=published,
        word_count=500,
    )

    period_start = datetime(2026, 3, 27)
    period_end = datetime(2026, 3, 29)
    test_db.story_groups.save_groups(
        groups=[{"label": "Some Event", "representative_id": aid1, "member_ids": [aid1, aid2]}],
        period_start=period_start,
        period_end=period_end,
    )

    service = StoryGroupService(db=test_db, provider=provider, cache=None)
    group = await service.get_group_for_article(article_id=aid1)

    assert group is not None
    assert group.label == "Some Event"
    assert aid1 in group.member_ids
    assert aid2 in group.member_ids


# ─── _parse_response unit tests ──────────────────────────────────────────────

def test_parse_response_valid_json():
    raw = '{"groups": [{"label": "Event X", "article_ids": [1, 2, 3]}]}'
    result = StoryGroupService._parse_response(raw)
    assert len(result) == 1
    assert result[0]["label"] == "Event X"


def test_parse_response_empty_groups():
    result = StoryGroupService._parse_response('{"groups": []}')
    assert result == []


def test_parse_response_malformed_returns_empty():
    result = StoryGroupService._parse_response("not json")
    assert result == []


def test_parse_response_strips_code_fences():
    raw = '```json\n{"groups": [{"label": "Y", "article_ids": [1]}]}\n```'
    result = StoryGroupService._parse_response(raw)
    assert len(result) == 1


def test_parse_response_missing_groups_key():
    result = StoryGroupService._parse_response('{"result": []}')
    assert result == []


# ─── _cache_key tests ─────────────────────────────────────────────────────────

def test_cache_key_format():
    articles = [make_article(1), make_article(3), make_article(2)]
    key = StoryGroupService._cache_key(articles, window_hours=48)
    assert key.startswith("story_groups:")
    assert len(key) > len("story_groups:")


def test_cache_key_order_independent():
    """Cache key must be identical regardless of article list order."""
    articles_abc = [make_article(1), make_article(2), make_article(3)]
    articles_cba = [make_article(3), make_article(2), make_article(1)]
    assert StoryGroupService._cache_key(articles_abc, 48) == StoryGroupService._cache_key(articles_cba, 48)


def test_cache_keys_differ_by_window():
    articles = [make_article(1), make_article(2)]
    k1 = StoryGroupService._cache_key(articles, window_hours=24)
    k2 = StoryGroupService._cache_key(articles, window_hours=48)
    assert k1 != k2


def test_cache_keys_differ_by_article_set():
    articles_a = [make_article(1), make_article(2)]
    articles_b = [make_article(1), make_article(3)]
    assert StoryGroupService._cache_key(articles_a, 48) != StoryGroupService._cache_key(articles_b, 48)
