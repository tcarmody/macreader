"""
Tests for the Summarizer critic pipeline.

Uses a mock LLM provider to test the 2-step summarization flow
(generate → critic) without requiring API keys.
"""

import json
import pytest

from backend.providers.base import LLMProvider, LLMResponse, ProviderCapabilities, ModelTier
from backend.summarizer import Summarizer, Summary, Model


class MockProvider(LLMProvider):
    """Mock LLM provider that returns pre-configured responses."""

    TIER_MODELS = {
        ModelTier.FAST: "mock-fast",
        ModelTier.STANDARD: "mock-standard",
        ModelTier.ADVANCED: "mock-advanced",
    }

    def __init__(self):
        self.calls: list[dict] = []
        self.responses: list[str] = []
        self._call_index = 0

    @property
    def name(self) -> str:
        return "mock"

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities()

    def queue_response(self, text: str):
        """Queue a response to be returned on the next complete() call."""
        self.responses.append(text)

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
        self.calls.append({
            "user_prompt": user_prompt,
            "system_prompt": system_prompt,
            "model": model,
        })
        text = self.responses[self._call_index] if self._call_index < len(self.responses) else "{}"
        self._call_index += 1
        return LLMResponse(text=text, model=model or "mock-fast")


def _make_step1_response(content_type="news", headline="Test headline here"):
    """Build a valid step 1 JSON response."""
    return json.dumps({
        "headline": headline,
        "summary": "This is the summary from step 1.",
        "key_points": ["Point one", "Point two", "Point three"],
        "content_type": content_type,
    })


def _make_critic_response(headline="Critic improved headline for article", revisions=None):
    """Build a valid critic JSON response."""
    return json.dumps({
        "headline": headline,
        "summary": "This is the revised summary from the critic.",
        "key_points": ["Revised point one", "Revised point two"],
        "revisions_made": revisions or [],
    })


class TestCriticTrigger:
    """Tests for when the critic step should and shouldn't run."""

    def test_short_article_skips_critic(self):
        """Articles under 2000 words with non-newsletter type skip critic."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response(content_type="news"))

        summarizer = Summarizer(provider=provider)
        # ~100 words
        content = "Short article content. " * 50
        summary = summarizer.summarize(content, "https://example.com/short")

        assert len(provider.calls) == 1
        assert summary.one_liner == "Test headline here"

    def test_long_article_triggers_critic(self):
        """Articles over 2000 words trigger critic step."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response(content_type="news"))
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        # ~2500 words
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        assert len(provider.calls) == 2
        assert summary.one_liner == "Critic improved headline for article"

    def test_newsletter_triggers_critic(self):
        """Newsletter content type triggers critic even for short content."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response(content_type="newsletter"))
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        content = "Newsletter content. " * 50
        summary = summarizer.summarize(content, "https://example.com/newsletter")

        assert len(provider.calls) == 2
        assert summary.one_liner == "Critic improved headline for article"

    def test_critic_disabled_flag(self):
        """critic_enabled=False prevents critic from running."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response(content_type="newsletter"))

        summarizer = Summarizer(provider=provider, critic_enabled=False)
        content = "Newsletter content. " * 50
        summary = summarizer.summarize(content, "https://example.com/newsletter")

        assert len(provider.calls) == 1
        assert summary.one_liner == "Test headline here"

    def test_short_non_newsletter_types_skip_critic(self):
        """Other content types (analysis, tutorial, etc.) don't trigger critic for short content."""
        for content_type in ["analysis", "tutorial", "review", "research"]:
            provider = MockProvider()
            provider.queue_response(_make_step1_response(content_type=content_type))

            summarizer = Summarizer(provider=provider)
            content = "Short article. " * 50
            summarizer.summarize(content, f"https://example.com/{content_type}")

            assert len(provider.calls) == 1, f"{content_type} should not trigger critic"


class TestCriticOutput:
    """Tests for critic step output handling."""

    def test_critic_revises_headline(self):
        """Critic's headline replaces step 1's headline."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response(headline="Original headline"))
        provider.queue_response(_make_critic_response(headline="Better headline from critic"))

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        assert summary.one_liner == "Better headline from critic"

    def test_critic_revises_summary(self):
        """Critic's revised summary replaces step 1's summary."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        assert summary.full_summary == "This is the revised summary from the critic."

    def test_critic_revises_key_points(self):
        """Critic's revised key points replace step 1's key points."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        assert summary.key_points == ["Revised point one", "Revised point two"]


class TestCriticFailure:
    """Tests for critic step failure handling."""

    def test_critic_exception_falls_back(self):
        """If critic call raises, step 1 output is used."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        # Second call will return "{}" which is valid JSON but missing fields —
        # but we need an actual failure. Let's make it return invalid JSON.
        provider.queue_response("not valid json at all")

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        # Should fall back to step 1 output
        assert summary.one_liner == "Test headline here"
        assert summary.full_summary == "This is the summary from step 1."

    def test_critic_malformed_json_falls_back(self):
        """If critic returns unparseable response, step 1 output is used."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        provider.queue_response("```json\n{broken json\n```")

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        assert summary.one_liner == "Test headline here"

    def test_step1_unparseable_skips_critic(self):
        """If step 1 returns non-JSON, content_type is None and critic is skipped."""
        provider = MockProvider()
        provider.queue_response("Headline: Some headline\nSummary: Some summary text.")

        summarizer = Summarizer(provider=provider)
        # Even with long content, if content_type can't be extracted, only
        # word count > 2000 triggers critic. This is short content.
        content = "Short content. " * 50
        summary = summarizer.summarize(content, "https://example.com/legacy")

        assert len(provider.calls) == 1


class TestCriticModelSelection:
    """Tests for model tier selection in critic step."""

    def test_critic_uses_fast_tier(self):
        """Critic always uses FAST tier regardless of step 1 model."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        # Long content triggers STANDARD for step 1
        content = "word " * 2500
        summarizer.summarize(content, "https://example.com/long")

        # Step 1 uses STANDARD, step 2 (critic) uses FAST
        assert provider.calls[0]["model"] == "mock-standard"
        assert provider.calls[1]["model"] == "mock-fast"

    def test_step1_model_preserved_in_summary(self):
        """Summary.model_used reflects step 1 model, not critic model."""
        provider = MockProvider()
        provider.queue_response(_make_step1_response())
        provider.queue_response(_make_critic_response())

        summarizer = Summarizer(provider=provider)
        content = "word " * 2500
        summary = summarizer.summarize(content, "https://example.com/long")

        # Model used should reflect the generation step, not the critic
        assert summary.model_used == Model.SONNET


class TestShouldUseCritic:
    """Direct tests for _should_use_critic logic."""

    def test_word_count_threshold(self):
        summarizer = Summarizer(provider=MockProvider())

        assert not summarizer._should_use_critic("word " * 2000, "news")
        assert summarizer._should_use_critic("word " * 2001, "news")

    def test_newsletter_type(self):
        summarizer = Summarizer(provider=MockProvider())

        assert summarizer._should_use_critic("short", "newsletter")
        assert not summarizer._should_use_critic("short", "news")
        assert not summarizer._should_use_critic("short", "analysis")
        assert not summarizer._should_use_critic("short", None)

    def test_both_conditions(self):
        """Long newsletter triggers critic (both conditions true)."""
        summarizer = Summarizer(provider=MockProvider())

        assert summarizer._should_use_critic("word " * 2500, "newsletter")


class TestExtractContentType:
    """Tests for _extract_content_type helper."""

    def test_extracts_from_valid_json(self):
        summarizer = Summarizer(provider=MockProvider())

        result = summarizer._extract_content_type('{"content_type": "newsletter", "headline": "test"}')
        assert result == "newsletter"

    def test_extracts_from_code_block(self):
        summarizer = Summarizer(provider=MockProvider())

        result = summarizer._extract_content_type('```json\n{"content_type": "research"}\n```')
        assert result == "research"

    def test_returns_none_for_invalid_json(self):
        summarizer = Summarizer(provider=MockProvider())

        assert summarizer._extract_content_type("not json") is None
        assert summarizer._extract_content_type("") is None

    def test_returns_none_for_missing_field(self):
        summarizer = Summarizer(provider=MockProvider())

        assert summarizer._extract_content_type('{"headline": "test"}') is None
