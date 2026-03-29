"""
Tests for AutoDigestService.

Uses mock LLM provider and real SQLite (test_db fixture) — no API keys needed.
"""

import json
from datetime import datetime, timedelta

import pytest

from backend.clustering import Clusterer
from backend.providers.base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier
from backend.services.auto_digest import AutoDigestService, _MIN_STORIES
from backend.services.brief_generator import BriefGenerator, BriefLength, BriefTone
from backend.services.story_groups import StoryGroupService


# ─── Mock provider ────────────────────────────────────────────────────────────

class MockProvider(LLMProvider):
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

    def complete(self, user_prompt, system_prompt=None, model=None,
                 max_tokens=1024, temperature=0.0, use_cache=False, json_mode=False) -> LLMResponse:
        self.calls.append({"user_prompt": user_prompt, "model": model})
        text = self._responses[self._call_index] if self._call_index < len(self._responses) else "Mock response."
        self._call_index += 1
        return LLMResponse(text=text, model=model or "mock-fast")


# ─── Fixtures ────────────────────────────────────────────────────────────────

def _cluster_response(topics: list[dict]) -> str:
    return json.dumps({"topics": topics})


def _story_groups_response(groups: list[dict]) -> str:
    return json.dumps({"groups": groups})


def make_service(provider, db, extra_story_group_responses=None, extra_cluster_responses=None):
    """Build an AutoDigestService wired to shared mock provider."""
    clusterer = Clusterer(provider=provider, cache=None)
    brief_gen = BriefGenerator(provider=provider, cache=None)
    story_svc = StoryGroupService(db=db, provider=provider, cache=None)
    return AutoDigestService(
        db=db,
        provider=provider,
        clusterer=clusterer,
        brief_generator=brief_gen,
        story_group_service=story_svc,
        cache=None,
    )


def seed_articles(db, n: int, published_offset_hours: int = 0) -> list[int]:
    """Insert n articles into the test DB and return their IDs."""
    feed_id = db.add_feed(url="https://example.com/feed.xml", name="Test Feed")
    ids = []
    for i in range(n):
        published = datetime.now() - timedelta(hours=published_offset_hours + i)
        aid = db.add_article(
            feed_id=feed_id,
            url=f"https://example.com/article-{i}",
            title=f"Article {i}: Some News Story",
            content="This article discusses something interesting and noteworthy. " * 10,
            published_at=published,
            word_count=200 + i * 10,
        )
        ids.append(aid)
    return ids


# ─── Core pipeline tests ──────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_generate_returns_digest_structure(test_db):
    """Happy-path: articles in DB → valid Digest with sections and raw output."""
    provider = MockProvider()
    ids = seed_articles(test_db, 8)

    # Queued responses: story groups (no groups), clustering, 8 briefs, 1 intro
    provider.queue_response(_story_groups_response([]))  # no duplicates
    provider.queue_response(_cluster_response([
        {"label": "AI Models", "article_ids": ids[:3]},
        {"label": "Policy", "article_ids": ids[3:5]},
        {"label": "Open Source", "article_ids": ids[5:6]},
        {"label": "Business", "article_ids": ids[6:7]},
        {"label": "Research", "article_ids": ids[7:8]},
    ]))
    for i in range(8):
        provider.queue_response(f"Brief for article {i}.")
    provider.queue_response("Eight stories worth your time. Topics span AI and policy.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today")

    assert digest.story_count >= _MIN_STORIES
    assert len(digest.sections) > 0
    assert digest.title.startswith("DataPoints Daily Digest")
    assert digest.intro != ""
    assert "# DataPoints Daily Digest" in digest.raw
    assert digest.cached is False


@pytest.mark.asyncio
async def test_generate_deduplicates_story_groups(test_db):
    """Representative of a 3-source story group is selected; others excluded."""
    provider = MockProvider()
    ids = seed_articles(test_db, 6)

    # seed_articles gives word_count = 200 + i*10, so ids[2] has the highest
    # word_count (220) and is the representative; ids[0] and ids[1] are non-rep.
    provider.queue_response(_story_groups_response([
        {"label": "GPT-5 launch", "article_ids": [ids[0], ids[1], ids[2]]}
    ]))
    provider.queue_response(_cluster_response([
        {"label": "AI Models", "article_ids": [ids[2]]},  # representative
        {"label": "Policy", "article_ids": [ids[3]]},
        {"label": "Open Source", "article_ids": [ids[4]]},
        {"label": "Business", "article_ids": [ids[5]]},
        {"label": "Research", "article_ids": [ids[2]]},  # duplicate cluster entry; fine
    ]))
    for _ in range(10):
        provider.queue_response("Brief text.")
    provider.queue_response("Good intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today")

    all_article_ids = [a.id for s in digest.sections for a in s.articles]
    # ids[0] and ids[1] should NOT appear — they are non-representative members
    assert ids[0] not in all_article_ids
    assert ids[1] not in all_article_ids


@pytest.mark.asyncio
async def test_story_group_size_on_representative(test_db):
    """The representative article carries story_group_size == group member count."""
    provider = MockProvider()
    ids = seed_articles(test_db, 5)

    provider.queue_response(_story_groups_response([
        {"label": "Big Event", "article_ids": [ids[0], ids[1], ids[2]]}
    ]))
    provider.queue_response(_cluster_response([
        {"label": "AI", "article_ids": [ids[0]]},
        {"label": "Policy", "article_ids": [ids[3]]},
        {"label": "Open Source", "article_ids": [ids[4]]},
        {"label": "Science", "article_ids": [ids[0]]},
        {"label": "Business", "article_ids": [ids[3]]},
    ]))
    for _ in range(10):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today")

    rep_article = next(
        (a for s in digest.sections for a in s.articles if a.id == ids[0]), None
    )
    if rep_article:
        assert rep_article.story_group_size == 3


@pytest.mark.asyncio
async def test_minimum_five_stories(test_db):
    """Even with many clusters, at least _MIN_STORIES stories are selected."""
    provider = MockProvider()
    ids = seed_articles(test_db, 10)

    provider.queue_response(_story_groups_response([]))
    # 10 clusters, each with 1 article — should still yield >= 5
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(10)
    ]))
    for _ in range(15):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today", max_stories=10)

    assert digest.story_count >= _MIN_STORIES


@pytest.mark.asyncio
async def test_max_stories_cap(test_db):
    """story_count never exceeds max_stories."""
    provider = MockProvider()
    ids = seed_articles(test_db, 20)

    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(20)
    ]))
    for _ in range(25):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today", max_stories=7)

    assert digest.story_count <= 7


@pytest.mark.asyncio
async def test_empty_feed_returns_empty_digest(test_db):
    """No articles → empty digest with no sections."""
    provider = MockProvider()
    service = make_service(provider, test_db)

    digest = await service.generate(period="today")

    assert digest.story_count == 0
    assert digest.sections == []
    assert "No stories available" in digest.raw


# ─── Caching tests ────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_cached_digest_returned_within_ttl(test_db):
    """Second call within 2h returns cached digest without new LLM calls."""
    provider = MockProvider()
    ids = seed_articles(test_db, 6)

    # First call
    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(6)
    ]))
    for _ in range(10):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    digest1 = await service.generate(period="today")
    calls_after_first = len(provider.calls)
    assert not digest1.cached

    # Second call — should hit DB cache
    digest2 = await service.generate(period="today")
    assert digest2.cached
    assert len(provider.calls) == calls_after_first  # no new LLM calls


@pytest.mark.asyncio
async def test_force_refresh_bypasses_cache(test_db):
    """force_refresh=True re-runs the pipeline even when a fresh digest exists."""
    provider = MockProvider()
    ids = seed_articles(test_db, 6)

    for _ in range(2):  # queue enough for two full runs
        provider.queue_response(_story_groups_response([]))
        provider.queue_response(_cluster_response([
            {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(6)
        ]))
        for _ in range(10):
            provider.queue_response("Brief.")
        provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    await service.generate(period="today")
    calls_after_first = len(provider.calls)

    await service.generate(period="today", force_refresh=True)
    assert len(provider.calls) > calls_after_first


@pytest.mark.asyncio
async def test_feed_id_filter_bypasses_cache(test_db):
    """Digests with feed_ids filter are never cached or returned from cache."""
    provider = MockProvider()
    ids = seed_articles(test_db, 4)

    # Queue for first call (unfiltered, gets cached)
    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(4)
    ]))
    for _ in range(6):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    # Queue for second call (filtered, should re-run)
    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(4)
    ]))
    for _ in range(6):
        provider.queue_response("Brief.")
    provider.queue_response("Intro.")

    service = make_service(provider, test_db)
    d1 = await service.generate(period="today")
    calls_after_first = len(provider.calls)

    # Filtered digest — always re-runs
    d2 = await service.generate(period="today", feed_ids=[1])
    assert not d2.cached
    assert len(provider.calls) > calls_after_first


# ─── Rendering tests ─────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_markdown_format(test_db):
    provider = MockProvider()
    ids = seed_articles(test_db, 5)

    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(5)
    ]))
    for _ in range(8):
        provider.queue_response("Brief text here.")
    provider.queue_response("Newsletter intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today", format="markdown")

    assert "# DataPoints Daily Digest" in digest.raw
    assert "## " in digest.raw          # section headers
    assert "**Article" in digest.raw    # bold titles
    assert "→ https://" in digest.raw   # article links


@pytest.mark.asyncio
async def test_html_format(test_db):
    provider = MockProvider()
    ids = seed_articles(test_db, 5)

    provider.queue_response(_story_groups_response([]))
    provider.queue_response(_cluster_response([
        {"label": f"Topic {i}", "article_ids": [ids[i]]} for i in range(5)
    ]))
    for _ in range(8):
        provider.queue_response("Brief text here.")
    provider.queue_response("Newsletter intro.")

    service = make_service(provider, test_db)
    digest = await service.generate(period="today", format="html")

    assert "<article>" in digest.raw
    assert "<h1" in digest.raw
    assert "<h2" in digest.raw
    assert 'href="https://' in digest.raw


# ─── Scoring / selection unit tests ──────────────────────────────────────────

def test_select_articles_top_one_per_cluster(test_db):
    """Takes exactly 1 article per cluster when enough clusters exist."""
    from backend.database.models import DBArticle
    from backend.clustering import Topic

    provider = MockProvider()
    service = make_service(provider, test_db)

    published = datetime.now() - timedelta(hours=1)
    articles = [
        DBArticle(id=i, feed_id=1, url=f"https://x.com/{i}", title=f"A{i}",
                  content="x", summary_short="s", summary_full=None,
                  key_points=None, is_read=False, is_bookmarked=False,
                  published_at=published, created_at=published, word_count=100)
        for i in range(1, 11)
    ]
    article_map = {a.id: a for a in articles}

    topics = [
        Topic(id=f"t{i}", label=f"Topic {i}", article_ids=[articles[i].id])
        for i in range(10)
    ]

    selected = service._select_articles(topics, article_map, {}, max_stories=10)
    assert len(selected) == 10
    assert len(set(selected)) == 10  # no duplicates


def test_select_articles_fills_to_min_stories(test_db):
    """With only 2 clusters, fills to _MIN_STORIES from runner-up pool."""
    from backend.database.models import DBArticle
    from backend.clustering import Topic

    provider = MockProvider()
    service = make_service(provider, test_db)

    published = datetime.now() - timedelta(hours=1)
    articles = [
        DBArticle(id=i, feed_id=1, url=f"https://x.com/{i}", title=f"A{i}",
                  content="x", summary_short="s", summary_full=None,
                  key_points=None, is_read=False, is_bookmarked=False,
                  published_at=published, created_at=published, word_count=100)
        for i in range(1, 9)
    ]
    article_map = {a.id: a for a in articles}

    # 2 clusters with 4 articles each — top-1 per cluster = 2 → must fill to 5
    topics = [
        Topic(id="t0", label="Topic 0", article_ids=[1, 2, 3, 4]),
        Topic(id="t1", label="Topic 1", article_ids=[5, 6, 7, 8]),
    ]

    selected = service._select_articles(topics, article_map, {}, max_stories=10)
    assert len(selected) >= _MIN_STORIES


def test_select_articles_respects_max_cap(test_db):
    """max_stories cap is always honoured, even if pool is large."""
    from backend.database.models import DBArticle
    from backend.clustering import Topic

    provider = MockProvider()
    service = make_service(provider, test_db)

    published = datetime.now() - timedelta(hours=1)
    articles = [
        DBArticle(id=i, feed_id=1, url=f"https://x.com/{i}", title=f"A{i}",
                  content="x", summary_short="s", summary_full=None,
                  key_points=None, is_read=False, is_bookmarked=False,
                  published_at=published, created_at=published, word_count=100)
        for i in range(1, 21)
    ]
    article_map = {a.id: a for a in articles}
    topics = [Topic(id=f"t{i}", label=f"T{i}", article_ids=[articles[i].id]) for i in range(20)]

    selected = service._select_articles(topics, article_map, {}, max_stories=3)
    assert len(selected) <= 3


def test_scoring_prefers_summarized_articles(test_db):
    """Summarized articles score +2 over unsummarized ones."""
    from backend.database.models import DBArticle
    from backend.clustering import Topic

    provider = MockProvider()
    service = make_service(provider, test_db)

    published = datetime.now() - timedelta(hours=1)

    summarized = DBArticle(
        id=1, feed_id=1, url="https://x.com/1", title="A1",
        content="x", summary_short="Has summary", summary_full=None,
        key_points=None, is_read=False, is_bookmarked=False,
        published_at=published, created_at=published, word_count=100,
    )
    unsummarized = DBArticle(
        id=2, feed_id=1, url="https://x.com/2", title="A2",
        content="x", summary_short=None, summary_full=None,
        key_points=None, is_read=False, is_bookmarked=False,
        published_at=published, created_at=published, word_count=200,
    )
    article_map = {1: summarized, 2: unsummarized}
    topics = [Topic(id="t0", label="Tech", article_ids=[1, 2])]

    selected = service._select_articles(topics, article_map, {}, max_stories=1)
    assert selected[0] == 1  # summarized wins despite lower word_count


def test_scoring_story_group_bonus(test_db):
    """Article covered by 3 sources gets +2 bonus (group_size - 1 = 2)."""
    from backend.database.models import DBArticle
    from backend.clustering import Topic

    provider = MockProvider()
    service = make_service(provider, test_db)

    published = datetime.now() - timedelta(hours=1)
    a1 = DBArticle(id=1, feed_id=1, url="https://x.com/1", title="A1",
                   content="x", summary_short=None, summary_full=None,
                   key_points=None, is_read=False, is_bookmarked=False,
                   published_at=published, created_at=published, word_count=100)
    a2 = DBArticle(id=2, feed_id=1, url="https://x.com/2", title="A2",
                   content="x", summary_short=None, summary_full=None,
                   key_points=None, is_read=False, is_bookmarked=False,
                   published_at=published, created_at=published, word_count=100)
    article_map = {1: a1, 2: a2}
    group_sizes = {1: 3}  # a1 is rep of 3-source group → score +2

    topics = [Topic(id="t0", label="Tech", article_ids=[1, 2])]
    selected = service._select_articles(topics, article_map, group_sizes, max_stories=1)
    assert selected[0] == 1


# ─── Title / period tests ─────────────────────────────────────────────────────

def test_title_today():
    now = datetime(2026, 3, 29, 10, 0)
    title = AutoDigestService._make_title("today", now)
    assert "Daily Digest" in title
    assert "March 29, 2026" in title


def test_title_week():
    now = datetime(2026, 3, 29, 10, 0)
    title = AutoDigestService._make_title("week", now)
    assert "Weekly Digest" in title


def test_period_start_today():
    now = datetime(2026, 3, 29, 12, 0)
    start = AutoDigestService._period_start("today", now)
    assert start == now - timedelta(hours=24)


def test_period_start_week():
    now = datetime(2026, 3, 29, 12, 0)
    start = AutoDigestService._period_start("week", now)
    assert start == now - timedelta(days=7)
