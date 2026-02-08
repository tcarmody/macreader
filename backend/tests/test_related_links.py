"""
Tests for related links feature using Exa neural search.
"""

import json
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import pytest

from backend.database.models import DBArticle
from backend.services.related_links import (
    construct_search_query,
    extract_keywords_llm,
    normalize_cache_key,
    ExaSearchService,
)


class TestQueryConstruction:
    """Tests for construct_search_query function."""

    def test_query_with_key_points_two_or_more(self):
        """Should use title + first two key points when available."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Understanding Neural Networks",
            content="Long content here...",
            key_points=json.dumps(["Deep learning basics", "Backpropagation", "Gradient descent"]),
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        query = construct_search_query(article, mock_provider)

        assert query == "Understanding Neural Networks Deep learning basics Backpropagation"
        # Should not call LLM when key points exist
        mock_provider.complete.assert_not_called()

    def test_query_with_single_key_point(self):
        """Should use title + single key point when only one available."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="AI Safety Research",
            content="Content...",
            key_points=json.dumps(["Alignment problem"]),
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        query = construct_search_query(article, mock_provider)

        assert query == "AI Safety Research Alignment problem"

    def test_query_with_invalid_key_points_json(self):
        """Should fall back to LLM extraction when key_points JSON is invalid."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Quantum Computing",
            content="Long content about quantum computing and qubits. Quantum computers use quantum bits or qubits to perform calculations that would be impossible for classical computers. This article explores the fundamentals of quantum computing including superposition, entanglement, and quantum gates.",
            key_points="invalid json",
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        mock_provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        mock_provider.complete.return_value = Mock(text="quantum mechanics\nsuperposition\nquantum entanglement")

        query = construct_search_query(article, mock_provider)

        assert "quantum mechanics" in query
        assert "superposition" in query
        assert "quantum entanglement" in query

    def test_query_without_key_points_with_content(self):
        """Should extract keywords via LLM when no key points but has content."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Machine Learning Tutorial",
            content="This article explains supervised learning, classification algorithms, and model training. It covers the fundamentals of machine learning including data preprocessing, feature engineering, model evaluation, and hyperparameter tuning for production deployments.",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        mock_provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        mock_provider.complete.return_value = Mock(text="supervised learning\nclassification\nmodel training")

        query = construct_search_query(article, mock_provider)

        assert "Machine Learning Tutorial" in query
        assert "supervised learning" in query

    def test_query_without_content(self):
        """Should use title only when no key points and no content."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Breaking News: AI Breakthrough",
            content="",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        query = construct_search_query(article, mock_provider)

        assert query == "Breaking News: AI Breakthrough"
        # Should not call LLM when no content
        mock_provider.complete.assert_not_called()


class TestKeywordExtraction:
    """Tests for extract_keywords_llm function."""

    def test_extract_keywords_from_content(self):
        """Should extract 3-5 keywords from article content."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Deep Reinforcement Learning",
            content="This article discusses deep reinforcement learning, policy gradients, Q-learning, and actor-critic methods in detail.",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        mock_provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        mock_provider.complete.return_value = Mock(text="""reinforcement learning
policy gradients
Q-learning
actor-critic methods
neural networks""")

        keywords = extract_keywords_llm(article, mock_provider)

        assert len(keywords) == 5
        assert "reinforcement learning" in keywords
        assert "policy gradients" in keywords
        assert "Q-learning" in keywords

    def test_extract_keywords_uses_cache(self):
        """Should use cached keywords if available."""
        cached_keywords = ["cached", "keywords", "here"]
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Test Article",
            content="Content...",
            extracted_keywords=json.dumps(cached_keywords),
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        keywords = extract_keywords_llm(article, mock_provider)

        assert keywords == cached_keywords
        # Should not call LLM when cache exists
        mock_provider.complete.assert_not_called()

    def test_extract_keywords_truncates_content(self):
        """Should truncate content to 2000 chars for speed."""
        long_content = "word " * 1000  # Much longer than 2000 chars
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Long Article",
            content=long_content,
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        mock_provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        mock_provider.complete.return_value = Mock(text="keyword1\nkeyword2")

        extract_keywords_llm(article, mock_provider)

        # Check that the prompt includes truncated content
        call_args = mock_provider.complete.call_args
        prompt = call_args[1]["user_prompt"]
        content_in_prompt = prompt.split("Content preview:")[1].split("\n\nKey concepts:")[0].strip()
        assert len(content_in_prompt) <= 2000

    def test_extract_keywords_filters_short_lines(self):
        """Should filter out lines with 2 or fewer characters."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Test",
            content="Content...",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_provider = Mock()
        mock_provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        mock_provider.complete.return_value = Mock(text="""valid keyword
AI
a
another valid keyword
ok""")

        keywords = extract_keywords_llm(article, mock_provider)

        # Should exclude "a" (1 char) and "ok" (2 chars)
        assert "a" not in keywords
        assert "ok" not in keywords
        assert "valid keyword" in keywords
        assert "another valid keyword" in keywords
        # "AI" should be included as it's exactly 2 chars, but filter is > 2
        assert "AI" not in keywords


class TestCacheKeyNormalization:
    """Tests for normalize_cache_key function."""

    def test_normalize_lowercase(self):
        """Should normalize to lowercase."""
        key1 = normalize_cache_key("Machine Learning")
        key2 = normalize_cache_key("machine learning")
        assert key1 == key2

    def test_normalize_whitespace(self):
        """Should normalize whitespace."""
        key1 = normalize_cache_key("AI  and   ML")
        key2 = normalize_cache_key("AI and ML")
        assert key1 == key2

    def test_normalize_leading_trailing_spaces(self):
        """Should strip leading/trailing spaces."""
        key1 = normalize_cache_key("  neural networks  ")
        key2 = normalize_cache_key("neural networks")
        assert key1 == key2

    def test_normalize_returns_prefixed_hash(self):
        """Should return prefixed hash."""
        key = normalize_cache_key("test query")
        assert key.startswith("related_links:")
        assert len(key) > len("related_links:")  # Has hash appended

    def test_normalize_consistent_hashing(self):
        """Should produce consistent hashes for same input."""
        query = "Deep Learning Tutorial"
        key1 = normalize_cache_key(query)
        key2 = normalize_cache_key(query)
        assert key1 == key2


class TestExaSearchService:
    """Tests for ExaSearchService class."""

    @pytest.fixture
    def mock_exa_client(self):
        """Mock Exa client."""
        with patch('backend.services.related_links.Exa') as mock_exa:
            client = MagicMock()
            mock_exa.return_value = client
            yield client

    @pytest.fixture
    def mock_cache(self):
        """Mock cache."""
        cache = Mock()
        cache.get.return_value = None  # Default: no cache
        return cache

    @pytest.fixture
    def mock_provider(self):
        """Mock LLM provider."""
        provider = Mock()
        provider.get_model_for_tier.return_value = "claude-haiku-4-5"
        provider.complete.return_value = Mock(text="keyword1\nkeyword2\nkeyword3")
        return provider

    def test_fetch_related_links_calls_exa_api(self, mock_exa_client, mock_cache, mock_provider):
        """Should call Exa API with constructed query."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Machine Learning Basics",
            content="Content about ML...",
            key_points=json.dumps(["supervised learning", "neural networks"]),
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        # Mock Exa response
        mock_result = Mock()
        mock_result.url = "https://related.com/article"
        mock_result.title = "Related Article"
        mock_result.text = "This is a related article about ML"
        mock_result.published_date = "2026-01-15"
        mock_result.score = 0.95

        mock_response = Mock()
        mock_response.results = [mock_result]
        mock_exa_client.search.return_value = mock_response

        service = ExaSearchService(
            api_key="test-key",
            cache=mock_cache,
            provider=mock_provider
        )

        links = service.fetch_related_links(article, num_results=5)

        # Verify Exa was called with correct parameters
        mock_exa_client.search.assert_called_once()
        call_kwargs = mock_exa_client.search.call_args[1]
        # Requests extra results for deduplication (num_results + 10)
        assert call_kwargs["num_results"] == 15
        assert "Machine Learning Basics" in call_kwargs["query"]

        # Verify response format
        assert len(links) == 1
        assert links[0]["url"] == "https://related.com/article"
        assert links[0]["title"] == "Related Article"
        assert links[0]["domain"] == "related.com"

    def test_fetch_related_links_uses_cache(self, mock_exa_client, mock_cache, mock_provider):
        """Should return cached results if available."""
        cached_links = [
            {
                "url": "https://cached.com/article",
                "title": "Cached Article",
                "snippet": "Cached snippet",
                "domain": "cached.com",
                "published_date": None,
                "score": None,
            }
        ]
        mock_cache.get.return_value = cached_links

        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Test",
            content="Content...",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        service = ExaSearchService(
            api_key="test-key",
            cache=mock_cache,
            provider=mock_provider
        )

        links = service.fetch_related_links(article)

        # Should return cached results without calling Exa
        assert links == cached_links
        mock_exa_client.search.assert_not_called()

    def test_fetch_related_links_caches_results(self, mock_exa_client, mock_cache, mock_provider):
        """Should cache results after fetching."""
        mock_cache.get.return_value = None  # No cache

        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Test Article",
            content="Content...",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_result = Mock()
        mock_result.url = "https://result.com/article"
        mock_result.title = "Result"
        mock_result.text = "Snippet text"

        mock_response = Mock()
        mock_response.results = [mock_result]
        mock_exa_client.search.return_value = mock_response

        service = ExaSearchService(
            api_key="test-key",
            cache=mock_cache,
            provider=mock_provider
        )

        service.fetch_related_links(article)

        # Verify cache.set was called with 24-hour TTL
        mock_cache.set.assert_called_once()
        call_args = mock_cache.set.call_args
        assert call_args[1]["ttl"] == 86400  # 24 hours

    def test_fetch_related_links_truncates_snippet(self, mock_exa_client, mock_cache, mock_provider):
        """Should truncate snippet to 200 characters."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Original Article Title",
            content="Content...",
            key_points=None,
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        mock_result = Mock()
        mock_result.url = "https://result.com"
        mock_result.title = "Related Result With Long Snippet"
        mock_result.text = "x" * 500  # Long snippet
        mock_result.published_date = None
        mock_result.score = 0.85

        mock_response = Mock()
        mock_response.results = [mock_result]
        mock_exa_client.search.return_value = mock_response

        service = ExaSearchService(
            api_key="test-key",
            cache=mock_cache,
            provider=mock_provider
        )

        links = service.fetch_related_links(article)

        assert len(links[0]["snippet"]) == 200

    def test_extract_domain(self):
        """Should extract domain from URL."""
        from backend.services.related_links import ExaSearchService

        assert ExaSearchService._extract_domain("https://www.example.com/article") == "example.com"
        assert ExaSearchService._extract_domain("https://example.com/article") == "example.com"
        assert ExaSearchService._extract_domain("http://blog.example.com/post") == "blog.example.com"


class TestAPIEndpoint:
    """Tests for POST /articles/{id}/related endpoint."""

    def test_find_related_endpoint_not_found(self, client):
        """Should return 404 for non-existent article."""
        from backend.config import state
        original_exa = state.exa_service
        state.exa_service = Mock()
        try:
            response = client.post("/articles/99999/related")
            assert response.status_code == 404
        finally:
            state.exa_service = original_exa

    def test_find_related_endpoint_no_exa_service(self, client_with_data):
        """Should return 503 if Exa service not configured."""
        from backend.config import state
        original_exa = state.exa_service
        state.exa_service = None

        try:
            client, data = client_with_data
            article_id = data["article_ids"][0]
            response = client.post(f"/articles/{article_id}/related")
            assert response.status_code == 503
            assert "not configured" in response.json()["detail"].lower()
        finally:
            state.exa_service = original_exa

    def test_find_related_endpoint_returns_immediately(self, client_with_data):
        """Should return immediately with background task message."""
        from backend.config import state

        # Mock Exa service
        mock_exa = Mock()
        original_exa = state.exa_service
        state.exa_service = mock_exa

        try:
            client, data = client_with_data
            article_id = data["article_ids"][0]
            response = client.post(f"/articles/{article_id}/related")

            assert response.status_code == 200
            data = response.json()
            assert data["success"] is True
            assert "finding" in data["message"].lower()
        finally:
            state.exa_service = original_exa


@pytest.mark.integration
class TestExaIntegration:
    """
    Integration tests that require actual Exa API key.

    These tests are marked with @pytest.mark.integration and should be run with:
    pytest -v -m integration

    Requires EXA_API_KEY environment variable to be set.
    """

    @pytest.fixture
    def exa_service(self):
        """Real Exa service for integration testing."""
        import os
        from backend.cache import create_cache
        from backend.providers.anthropic import AnthropicProvider

        api_key = os.getenv("EXA_API_KEY")
        if not api_key:
            pytest.skip("EXA_API_KEY not set")

        cache = create_cache(Path("./data/cache"))
        provider = AnthropicProvider(api_key=os.getenv("ANTHROPIC_API_KEY", ""))

        from backend.services.related_links import ExaSearchService
        return ExaSearchService(api_key=api_key, cache=cache, provider=provider)

    def test_real_exa_search(self, exa_service):
        """Test with real Exa API."""
        article = DBArticle(
            id=1,
            feed_id=1,
            url="https://example.com/article",
            title="Machine Learning for Beginners",
            content="Introduction to supervised learning and neural networks...",
            key_points=json.dumps(["supervised learning", "neural networks", "classification"]),
            summary_short=None,
            summary_full=None,
            is_read=False,
            is_bookmarked=False,
            published_at=None,
            created_at=None,
        )

        links = exa_service.fetch_related_links(article, num_results=3)

        # Basic validation
        assert len(links) <= 3
        assert all("url" in link for link in links)
        assert all("title" in link for link in links)
        assert all("domain" in link for link in links)
