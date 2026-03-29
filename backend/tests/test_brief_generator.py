"""
Tests for BriefGenerator service.

Uses a mock LLM provider — no API keys needed.
"""

import pytest

from backend.providers.base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier
from backend.services.brief_generator import (
    BriefGenerator,
    BriefLength,
    BriefTone,
    Brief,
)


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
        text = self._responses[self._call_index] if self._call_index < len(self._responses) else "Mock brief."
        self._call_index += 1
        return LLMResponse(text=text, model=model or "mock-fast")


SAMPLE_TITLE = "OpenAI releases GPT-5 with 2M token context"
SAMPLE_CONTENT = "OpenAI today announced GPT-5, its newest frontier model. The model supports a 2 million token context window and scores 92% on MMLU. Pricing starts at $15 per million input tokens."
LONG_TECHNICAL_CONTENT = " ".join([
    "The algorithm uses distributed consensus via cryptographic proofs and neural network "
    "architectures for machine learning inference across microservices infrastructure. " * 200
])


# ─── Service-level tests (no cache) ──────────────────────────────────────────

@pytest.mark.asyncio
async def test_generate_returns_brief():
    provider = MockProvider()
    provider.queue_response("OpenAI launched GPT-5 with a 2M token window, undercutting competitors on price.")
    gen = BriefGenerator(provider=provider, cache=None)

    brief = await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SENTENCE, BriefTone.NEUTRAL)

    assert isinstance(brief, Brief)
    assert brief.article_id == 1
    assert brief.length == BriefLength.SENTENCE
    assert brief.tone == BriefTone.NEUTRAL
    assert "GPT-5" in brief.content
    assert brief.cached is False
    assert len(provider.calls) == 1


@pytest.mark.asyncio
async def test_generate_all_lengths():
    for length in BriefLength:
        provider = MockProvider()
        provider.queue_response(f"Brief for {length.value}.")
        gen = BriefGenerator(provider=provider, cache=None)
        brief = await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, length, BriefTone.NEUTRAL)
        assert brief.length == length
        assert len(provider.calls) == 1


@pytest.mark.asyncio
async def test_generate_all_tones():
    for tone in BriefTone:
        provider = MockProvider()
        provider.queue_response(f"Brief with {tone.value} tone.")
        gen = BriefGenerator(provider=provider, cache=None)
        brief = await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, tone)
        assert brief.tone == tone


@pytest.mark.asyncio
async def test_generate_uses_correct_model_for_sentence():
    provider = MockProvider()
    provider.queue_response("One sentence brief.")
    gen = BriefGenerator(provider=provider, cache=None)

    await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SENTENCE, BriefTone.NEUTRAL)

    assert provider.calls[0]["model"] == "mock-fast"


@pytest.mark.asyncio
async def test_generate_uses_correct_model_for_short():
    provider = MockProvider()
    provider.queue_response("Three sentence brief.")
    gen = BriefGenerator(provider=provider, cache=None)

    await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, BriefTone.NEUTRAL)

    assert provider.calls[0]["model"] == "mock-fast"


@pytest.mark.asyncio
async def test_generate_paragraph_uses_standard_for_technical_content():
    provider = MockProvider()
    provider.queue_response("Technical paragraph brief.")
    gen = BriefGenerator(provider=provider, cache=None)

    await gen.generate(1, SAMPLE_TITLE, LONG_TECHNICAL_CONTENT, BriefLength.PARAGRAPH, BriefTone.NEUTRAL)

    assert provider.calls[0]["model"] == "mock-standard"


@pytest.mark.asyncio
async def test_generate_paragraph_uses_fast_for_simple_content():
    provider = MockProvider()
    provider.queue_response("Simple paragraph brief.")
    gen = BriefGenerator(provider=provider, cache=None)

    await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.PARAGRAPH, BriefTone.NEUTRAL)

    assert provider.calls[0]["model"] == "mock-fast"


# ─── Cache tests ──────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_cache_hit_skips_provider(temp_cache_dir):
    from backend.cache import create_cache
    cache = create_cache(temp_cache_dir)

    provider = MockProvider()
    provider.queue_response("Original brief.")
    gen = BriefGenerator(provider=provider, cache=cache)

    # First call — cache miss, provider called
    brief1 = await gen.generate(42, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, BriefTone.NEUTRAL)
    assert brief1.cached is False
    assert len(provider.calls) == 1

    # Second call — cache hit, provider NOT called again
    brief2 = await gen.generate(42, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, BriefTone.NEUTRAL)
    assert brief2.cached is True
    assert brief2.content == brief1.content
    assert len(provider.calls) == 1  # still 1


@pytest.mark.asyncio
async def test_different_tones_cached_separately(temp_cache_dir):
    from backend.cache import create_cache
    cache = create_cache(temp_cache_dir)

    provider = MockProvider()
    provider.queue_response("Neutral brief.")
    provider.queue_response("Opinionated brief.")
    gen = BriefGenerator(provider=provider, cache=cache)

    b1 = await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, BriefTone.NEUTRAL)
    b2 = await gen.generate(1, SAMPLE_TITLE, SAMPLE_CONTENT, BriefLength.SHORT, BriefTone.OPINIONATED)

    assert b1.content == "Neutral brief."
    assert b2.content == "Opinionated brief."
    assert len(provider.calls) == 2


# ─── Batch tests ──────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_generate_batch_returns_all_results():
    provider = MockProvider()
    for i in range(3):
        provider.queue_response(f"Brief for article {i + 1}.")
    gen = BriefGenerator(provider=provider, cache=None)

    items = [
        {"article_id": i + 1, "title": f"Article {i + 1}", "content": SAMPLE_CONTENT}
        for i in range(3)
    ]
    results = await gen.generate_batch(items, BriefLength.SHORT, BriefTone.NEUTRAL)

    assert len(results) == 3
    assert all(isinstance(r, Brief) for r in results)
    assert {r.article_id for r in results} == {1, 2, 3}


@pytest.mark.asyncio
async def test_generate_batch_caps_at_20():
    provider = MockProvider()
    for i in range(25):
        provider.queue_response(f"Brief {i}.")
    gen = BriefGenerator(provider=provider, cache=None)

    items = [
        {"article_id": i, "title": f"Article {i}", "content": SAMPLE_CONTENT}
        for i in range(25)
    ]
    results = await gen.generate_batch(items, BriefLength.SHORT, BriefTone.NEUTRAL)

    assert len(results) == 20


# ─── Model selection unit tests ───────────────────────────────────────────────

def test_select_model_sentence_always_fast():
    provider = MockProvider()
    gen = BriefGenerator(provider=provider, cache=None)
    assert gen._select_model(LONG_TECHNICAL_CONTENT, BriefLength.SENTENCE) == ModelTier.FAST


def test_select_model_short_always_fast():
    provider = MockProvider()
    gen = BriefGenerator(provider=provider, cache=None)
    assert gen._select_model(LONG_TECHNICAL_CONTENT, BriefLength.SHORT) == ModelTier.FAST


def test_select_model_paragraph_fast_for_simple():
    provider = MockProvider()
    gen = BriefGenerator(provider=provider, cache=None)
    assert gen._select_model(SAMPLE_CONTENT, BriefLength.PARAGRAPH) == ModelTier.FAST


def test_select_model_paragraph_standard_for_long():
    provider = MockProvider()
    gen = BriefGenerator(provider=provider, cache=None)
    long_content = "word " * 2500
    assert gen._select_model(long_content, BriefLength.PARAGRAPH) == ModelTier.STANDARD


def test_select_model_paragraph_standard_for_technical():
    provider = MockProvider()
    gen = BriefGenerator(provider=provider, cache=None)
    tech = "The algorithm uses neural networks and cryptographic consensus protocols in the distributed infrastructure."
    assert gen._select_model(tech, BriefLength.PARAGRAPH) == ModelTier.STANDARD


# ─── Cache key tests ─────────────────────────────────────────────────────────

def test_cache_key_format():
    key = BriefGenerator._cache_key(7, BriefLength.SHORT, BriefTone.OPINIONATED)
    assert key == "brief:7:short:opinionated"


def test_cache_keys_differ_by_tone():
    k1 = BriefGenerator._cache_key(1, BriefLength.SHORT, BriefTone.NEUTRAL)
    k2 = BriefGenerator._cache_key(1, BriefLength.SHORT, BriefTone.OPINIONATED)
    assert k1 != k2


def test_cache_keys_differ_by_length():
    k1 = BriefGenerator._cache_key(1, BriefLength.SENTENCE, BriefTone.NEUTRAL)
    k2 = BriefGenerator._cache_key(1, BriefLength.PARAGRAPH, BriefTone.NEUTRAL)
    assert k1 != k2
