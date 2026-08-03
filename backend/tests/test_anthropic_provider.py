"""
Tests for the Anthropic provider's request shaping.

Claude Sonnet 5 / Opus 5 reject temperature with a 400 and run adaptive
thinking by default (which shares the max_tokens budget with the response), so
the provider has to send a different request shape depending on the model.
"""

from types import SimpleNamespace

import pytest

from backend.providers.anthropic import AnthropicProvider
from backend.providers.base import ModelTier


class FakeMessages:
    """Captures the kwargs the provider sends to the Messages API."""

    def __init__(self):
        self.kwargs = None

    def create(self, **kwargs):
        self.kwargs = kwargs
        return SimpleNamespace(
            content=[SimpleNamespace(text="ok")],
            stop_reason="end_turn",
            usage=SimpleNamespace(
                input_tokens=10,
                output_tokens=5,
                cache_read_input_tokens=0,
            ),
        )


@pytest.fixture
def provider():
    p = AnthropicProvider(api_key="test-key")
    p.client = SimpleNamespace(messages=FakeMessages())
    return p


def _sent(provider):
    return provider.client.messages.kwargs


class TestTierModels:
    def test_standard_tier_is_sonnet_5(self, provider):
        assert provider.get_model_for_tier(ModelTier.STANDARD) == "claude-sonnet-5"

    def test_default_model_is_sonnet_5(self, provider):
        provider.complete(user_prompt="hi")
        assert _sent(provider)["model"] == "claude-sonnet-5"

    def test_sonnet_alias_resolves(self):
        p = AnthropicProvider(api_key="test-key", default_model="sonnet")
        assert p._default_model == "claude-sonnet-5"


class TestAdaptiveThinkingModels:
    """Sonnet 5 and later: no temperature, thinking explicitly disabled."""

    def test_complete_omits_temperature(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-sonnet-5")
        assert "temperature" not in _sent(provider)

    def test_complete_disables_thinking(self, provider):
        provider.complete(user_prompt="hi", model="claude-sonnet-5")
        assert _sent(provider)["thinking"] == {"type": "disabled"}

    def test_complete_chat_omits_temperature(self, provider):
        # chat_service calls this with temperature=0.7 and no explicit model
        provider.complete_chat(
            messages=[{"role": "user", "content": "hi"}],
            temperature=0.7,
        )
        assert "temperature" not in _sent(provider)
        assert _sent(provider)["thinking"] == {"type": "disabled"}

    def test_cacheable_prefix_omits_temperature(self, provider):
        provider.complete_with_cacheable_prefix(
            system_prompt="sys",
            instruction_prompt="inst",
            dynamic_content="content",
            model="claude-sonnet-5",
            temperature=0.3,
        )
        sent = _sent(provider)
        assert "temperature" not in sent
        assert sent["thinking"] == {"type": "disabled"}
        # Caching breakpoints must survive the rewrite
        assert sent["system"][0]["cache_control"] == {"type": "ephemeral"}
        assert sent["messages"][0]["content"][0]["cache_control"] == {"type": "ephemeral"}


class TestLegacyModels:
    """Haiku 4.5 still accepts temperature and has no thinking config."""

    def test_temperature_passed_through(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-haiku-4-5")
        assert _sent(provider)["temperature"] == 0.7
        assert "thinking" not in _sent(provider)

    def test_zero_temperature_omitted(self, provider):
        provider.complete(user_prompt="hi", temperature=0.0, model="claude-haiku-4-5")
        assert "temperature" not in _sent(provider)
        assert "thinking" not in _sent(provider)
