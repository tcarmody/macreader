"""
Summarization failures must reach the client, and the provider the user picked
(X-Preferred-Provider header from the web app, the `llm_provider` setting from
the Mac app) must be the one that summarizes.
"""

import json

import pytest

from dpcommon.llm import LLMProvider, ModelTier
from dpcommon.llm.base import LLMResponse, ProviderCapabilities

from backend.config import config, state
from backend.services import summarizer_selection
from backend.summarizer import Summarizer

ARTICLE_TEXT = (
    "The city council voted seven to two on Tuesday to approve a new network "
    "of protected bike lanes across the downtown core. "
) * 20

GOOD_REPLY = json.dumps({
    "headline": "Council approves downtown bike lanes",
    "summary": "The council approved a protected bike lane network.",
    "key_points": ["Vote was 7-2", "Covers downtown"],
})


class FakeProvider(LLMProvider):
    TIER_MODELS = {t: f"fake-{t.value}" for t in ModelTier}

    def __init__(self, name: str, error: Exception | None = None):
        self._name = name
        self.error = error
        self.calls = 0

    @property
    def name(self) -> str:
        return self._name

    @property
    def capabilities(self) -> ProviderCapabilities:
        return ProviderCapabilities()

    def complete(self, user_prompt, system_prompt=None, model=None, max_tokens=1024,
                 temperature=0.0, use_cache=False, json_mode=False) -> LLMResponse:
        self.calls += 1
        if self.error:
            raise self.error
        return LLMResponse(text=GOOD_REPLY, model=model or "fake", input_tokens=1, output_tokens=1)


@pytest.fixture
def article(client_with_data):
    client, data = client_with_data
    article_id = state.db.add_article(
        feed_id=data["feed_id"],
        url="https://example.com/bike-lanes",
        title="Bike lanes",
        content=ARTICLE_TEXT,
    )
    return client, article_id


@pytest.fixture
def default_provider(monkeypatch):
    """Server started with Anthropic; restore provider state afterwards."""
    anthropic = FakeProvider("anthropic")
    monkeypatch.setattr(state, "provider", anthropic)
    monkeypatch.setattr(state, "summarizer", Summarizer(provider=anthropic))
    summarizer_selection.clear_cache()
    yield anthropic
    summarizer_selection.clear_cache()


@pytest.fixture
def google(monkeypatch):
    """A Google key on the server; create_provider hands back a fake."""
    fake = FakeProvider("google")
    monkeypatch.setattr(config, "GOOGLE_API_KEY", "test-google-key")
    monkeypatch.setattr(
        summarizer_selection, "create_provider",
        lambda kind, key, **kw: fake if kind == "google" else pytest.fail(f"unexpected {kind}"),
    )
    return fake


class TestSummaryErrors:
    def test_provider_failure_is_recorded_on_article(self, article, monkeypatch):
        client, article_id = article
        failing = FakeProvider("anthropic", error=RuntimeError("Error code: 401 - invalid x-api-key"))
        monkeypatch.setattr(state, "provider", failing)
        monkeypatch.setattr(state, "summarizer", Summarizer(provider=failing))
        summarizer_selection.clear_cache()

        resp = client.post(f"/articles/{article_id}/summarize")
        assert resp.status_code == 200

        detail = client.get(f"/articles/{article_id}").json()
        assert detail["summary_full"] is None
        assert "401" in detail["summary_error"]

    def test_success_clears_previous_error(self, article, default_provider):
        client, article_id = article
        state.db.set_summary_error(article_id, "old failure")

        client.post(f"/articles/{article_id}/summarize")

        detail = client.get(f"/articles/{article_id}").json()
        assert detail["summary_error"] is None
        assert detail["summary_short"] == "Council approves downtown bike lanes"

    def test_unusable_content_is_recorded(self, article, default_provider, monkeypatch):
        client, article_id = article
        from backend import tasks
        monkeypatch.setattr(tasks, "_is_usable_content", lambda c: False)
        monkeypatch.setattr(tasks, "_extract_source_sync", lambda u, c: None)
        monkeypatch.setattr(tasks, "_fetch_content_sync", lambda u: None)

        client.post(f"/articles/{article_id}/summarize")

        detail = client.get(f"/articles/{article_id}").json()
        assert detail["summary_error"]
        assert default_provider.calls == 0


class TestPreferredProvider:
    def test_llm_provider_setting_is_used(self, article, default_provider, google):
        client, article_id = article
        state.db.set_setting("llm_provider", "google")

        client.post(f"/articles/{article_id}/summarize")

        assert google.calls >= 1
        assert default_provider.calls == 0
        assert client.get(f"/articles/{article_id}").json()["summary_short"]

    def test_header_overrides_setting(self, article, default_provider, google):
        client, article_id = article
        state.db.set_setting("llm_provider", "anthropic")

        client.post(f"/articles/{article_id}/summarize", headers={"X-Preferred-Provider": "google"})

        assert google.calls >= 1
        assert default_provider.calls == 0

    def test_preferred_provider_without_key_falls_back(self, article, default_provider, monkeypatch):
        client, article_id = article
        monkeypatch.setattr(config, "GOOGLE_API_KEY", "")
        state.db.set_setting("llm_provider", "google")

        client.post(f"/articles/{article_id}/summarize")

        assert default_provider.calls >= 1

    def test_status_reports_selected_provider(self, client, default_provider, google):
        state.db.set_setting("llm_provider", "google")
        assert client.get("/status").json()["provider"] == "google"
