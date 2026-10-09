"""
Tests for the Anthropic provider's request shaping.

Claude models from Sonnet 5 / Opus 4.7 onwards reject temperature with a 400
and run adaptive thinking by default (which shares the max_tokens budget with
the response), and the 5.5 models each turn thinking off differently, so the
provider has to send a different request shape depending on the model.
"""

from types import SimpleNamespace

import pytest

from backend.providers.anthropic import AnthropicProvider
from backend.providers.base import ModelTier


class FakeMessages:
    """Captures the kwargs the provider sends to the Messages API."""

    def __init__(self):
        self.kwargs = None
        self.content = [SimpleNamespace(type="text", text="ok")]
        self.stop_reason = "end_turn"
        self.stop_details = None

    def create(self, **kwargs):
        self.kwargs = kwargs
        return SimpleNamespace(
            content=self.content,
            stop_reason=self.stop_reason,
            stop_details=self.stop_details,
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
    def test_tiers_map_to_5_5_models(self, provider):
        assert provider.get_model_for_tier(ModelTier.FAST) == "claude-haiku-5-5"
        assert provider.get_model_for_tier(ModelTier.STANDARD) == "claude-sonnet-5-5"
        assert provider.get_model_for_tier(ModelTier.ADVANCED) == "claude-opus-5-5"

    def test_default_model_is_sonnet_5_5(self, provider):
        provider.complete(user_prompt="hi")
        assert _sent(provider)["model"] == "claude-sonnet-5-5"

    def test_aliases_resolve(self):
        for alias, model in [
            ("haiku", "claude-haiku-5-5"),
            ("sonnet", "claude-sonnet-5-5"),
            ("opus", "claude-opus-5-5"),
        ]:
            p = AnthropicProvider(api_key="test-key", default_model=alias)
            assert p._default_model == model


class TestSonnet55:
    """No temperature; "disabled" thinking is a 400, so send between_tools."""

    def test_complete_omits_temperature(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-sonnet-5-5")
        assert "temperature" not in _sent(provider)

    def test_complete_turns_thinking_off(self, provider):
        provider.complete(user_prompt="hi", max_tokens=300, model="claude-sonnet-5-5")
        sent = _sent(provider)
        assert sent["thinking"] == {"type": "between_tools"}
        assert sent["max_tokens"] == 300

    def test_complete_chat_omits_temperature(self, provider):
        # chat_service calls this with temperature=0.7 and no explicit model
        provider.complete_chat(
            messages=[{"role": "user", "content": "hi"}],
            temperature=0.7,
        )
        assert "temperature" not in _sent(provider)
        assert _sent(provider)["thinking"] == {"type": "between_tools"}

    def test_cacheable_prefix_omits_temperature(self, provider):
        provider.complete_with_cacheable_prefix(
            system_prompt="sys",
            instruction_prompt="inst",
            dynamic_content="content",
            model="claude-sonnet-5-5",
            temperature=0.3,
        )
        sent = _sent(provider)
        assert "temperature" not in sent
        assert sent["thinking"] == {"type": "between_tools"}
        # Caching breakpoints must survive the rewrite
        assert sent["system"][0]["cache_control"] == {"type": "ephemeral"}
        assert sent["messages"][0]["content"][0]["cache_control"] == {"type": "ephemeral"}

    def test_requests_server_side_fallback(self, provider):
        provider.complete(user_prompt="hi", model="claude-sonnet-5-5")
        sent = _sent(provider)
        assert sent["extra_body"] == {"fallbacks": "default"}
        assert sent["extra_headers"] == {
            "anthropic-beta": "server-side-fallback-2026-07-01"
        }


class TestOpus55:
    """Thinking can't be turned off: low effort plus max_tokens headroom."""

    def test_sends_no_thinking_config_or_temperature(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-opus-5-5")
        assert "thinking" not in _sent(provider)
        assert "temperature" not in _sent(provider)

    def test_low_effort_with_headroom_and_fallback(self, provider):
        provider.complete(user_prompt="hi", max_tokens=300, model="claude-opus-5-5")
        sent = _sent(provider)
        assert sent["max_tokens"] == 300 + AnthropicProvider.THINKING_HEADROOM_TOKENS
        assert sent["extra_body"] == {
            "output_config": {"effort": "low"},
            "fallbacks": "default",
        }
        assert sent["extra_headers"] == {
            "anthropic-beta": "server-side-fallback-2026-07-01"
        }


class TestHaiku55:
    """No temperature; thinking can still be disabled; no server-side fallback."""

    def test_disables_thinking_and_omits_temperature(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-haiku-5-5")
        sent = _sent(provider)
        assert sent["thinking"] == {"type": "disabled"}
        assert "temperature" not in sent
        assert "extra_body" not in sent
        assert "extra_headers" not in sent


class TestPreviousGenerationModels:
    """Models reachable via LLM_MODEL keep the request shape they accept."""

    def test_sonnet_5_keeps_disabled_thinking(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-sonnet-5")
        sent = _sent(provider)
        assert sent["thinking"] == {"type": "disabled"}
        assert "temperature" not in sent
        assert "extra_body" not in sent

    def test_opus_5_keeps_disabled_thinking(self, provider):
        provider.complete(user_prompt="hi", max_tokens=300, model="claude-opus-5")
        sent = _sent(provider)
        assert sent["thinking"] == {"type": "disabled"}
        assert sent["max_tokens"] == 300
        assert "extra_body" not in sent

    def test_haiku_4_5_temperature_passed_through(self, provider):
        provider.complete(user_prompt="hi", temperature=0.7, model="claude-haiku-4-5")
        assert _sent(provider)["temperature"] == 0.7
        assert "thinking" not in _sent(provider)

    def test_haiku_4_5_zero_temperature_omitted(self, provider):
        provider.complete(user_prompt="hi", temperature=0.0, model="claude-haiku-4-5")
        assert "temperature" not in _sent(provider)
        assert "thinking" not in _sent(provider)


class TestResponseParsing:
    def test_reads_text_blocks_by_type(self, provider):
        # A fallback-served or thinking response doesn't start with a text block
        provider.client.messages.content = [
            SimpleNamespace(type="fallback"),
            SimpleNamespace(type="thinking", thinking=""),
            SimpleNamespace(type="text", text="ok"),
        ]
        assert provider.complete(user_prompt="hi").text == "ok"

    def test_refusal_raises_with_category(self, provider):
        provider.client.messages.content = []
        provider.client.messages.stop_reason = "refusal"
        provider.client.messages.stop_details = SimpleNamespace(category="cyber")
        with pytest.raises(RuntimeError, match="declined.*cyber"):
            provider.complete(user_prompt="hi")

    def test_refusal_without_details_raises(self, provider):
        provider.client.messages.content = []
        provider.client.messages.stop_reason = "refusal"
        with pytest.raises(RuntimeError, match="declined"):
            provider.complete_chat(messages=[{"role": "user", "content": "hi"}])
