"""
Tests for the Google provider's request shaping.

Gemini 4 models ignore temperature / top_p / top_k (and 400 on out-of-range
values) and think by default out of the max_output_tokens budget, so the
provider has to send a different request shape than for Gemini 3 and earlier.
"""

from types import SimpleNamespace

import pytest

from backend.providers.base import ModelTier
from backend.providers.google import GoogleProvider


class FakeModels:
    """Captures the kwargs the provider sends to generate_content."""

    def __init__(self):
        self.kwargs = None

    def generate_content(self, **kwargs):
        self.kwargs = kwargs
        return SimpleNamespace(
            text="ok",
            usage_metadata=SimpleNamespace(
                prompt_token_count=10,
                candidates_token_count=5,
            ),
        )


@pytest.fixture
def provider():
    p = GoogleProvider(api_key="test-key")
    p.client = SimpleNamespace(models=FakeModels())
    return p


def _sent(provider):
    return provider.client.models.kwargs


def _config(provider):
    return _sent(provider)["config"]


class TestTierModels:
    def test_tiers_map_to_gemini_4_models(self, provider):
        assert provider.get_model_for_tier(ModelTier.FAST) == "gemini-4-hydrogen"
        assert provider.get_model_for_tier(ModelTier.STANDARD) == "gemini-4-carbon"
        assert provider.get_model_for_tier(ModelTier.ADVANCED) == "gemini-4-carbon"

    def test_default_model_is_hydrogen(self, provider):
        provider.complete(user_prompt="hi")
        assert _sent(provider)["model"] == "gemini-4-hydrogen"

    def test_aliases_resolve(self):
        p = GoogleProvider(api_key="test-key")
        assert p._resolve_model("hydrogen") == "gemini-4-hydrogen"
        assert p._resolve_model("carbon") == "gemini-4-carbon"
        assert p._resolve_model("flash") == "gemini-4-hydrogen"
        assert p._resolve_model("pro") == "gemini-4-carbon"


class TestGemini4:
    @pytest.mark.parametrize("model", ["gemini-4-hydrogen", "gemini-4-carbon"])
    def test_omits_temperature(self, provider, model):
        provider.complete(user_prompt="hi", model=model, temperature=0.7)
        assert _config(provider).temperature is None

    @pytest.mark.parametrize("model", ["gemini-4-hydrogen", "gemini-4-carbon"])
    def test_low_thinking_with_headroom(self, provider, model):
        provider.complete(user_prompt="hi", model=model, max_tokens=1024)
        config = _config(provider)
        assert config.thinking_config.thinking_level.value == "LOW"
        assert config.max_output_tokens == 1024 + GoogleProvider.THINKING_HEADROOM_TOKENS

    def test_cacheable_prefix_omits_temperature(self, provider):
        provider.complete_with_cacheable_prefix(
            system_prompt="sys",
            instruction_prompt="do it",
            dynamic_content="text",
            model="gemini-4-carbon",
            temperature=0.5,
        )
        assert _config(provider).temperature is None


class TestOlderModels:
    def test_gemini_2_5_temperature_passed_through(self, provider):
        provider.complete(user_prompt="hi", model="gemini-2.5-flash", temperature=0.7)
        config = _config(provider)
        assert config.temperature == 0.7
        assert config.thinking_config is None
        assert config.max_output_tokens == 1024
