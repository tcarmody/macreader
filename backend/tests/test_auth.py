"""
Tests for API authentication.
"""

import pytest
from fastapi.testclient import TestClient

from backend.config import config, state
from backend.database import Database
from backend.cache import create_cache
from backend.feed_parser import FeedParser
from backend.fetcher import Fetcher
from backend.server import app


class TestAuthenticationDisabled:
    """Tests when AUTH_API_KEY is not configured."""

    def test_public_endpoint_accessible(self, client):
        """Health check should be accessible without auth."""
        response = client.get("/status")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["auth_enabled"] is False

    def test_protected_endpoint_accessible_without_auth(self, client):
        """Protected endpoints should work when auth is disabled."""
        response = client.get("/feeds")
        assert response.status_code == 200

    def test_protected_endpoint_accessible_with_random_key(self, client):
        """Protected endpoints should work with any key when auth is disabled."""
        response = client.get("/feeds", headers={"X-API-Key": "random-key"})
        assert response.status_code == 200


class TestAuthenticationEnabled:
    """Tests when AUTH_API_KEY is configured."""

    @pytest.fixture
    def client_with_auth(self, temp_db_path, temp_cache_dir):
        """Create a test client with auth enabled."""
        # Store original state
        original_db = state.db
        original_cache = state.cache
        original_feed_parser = state.feed_parser
        original_fetcher = state.fetcher
        original_summarizer = state.summarizer
        original_clusterer = state.clusterer
        original_auth_key = config.AUTH_API_KEY

        # Enable auth
        config.AUTH_API_KEY = "test-secret-key-12345"

        # Set up test state
        test_db = Database(temp_db_path)
        state.db = test_db
        state.cache = create_cache(temp_cache_dir)
        state.feed_parser = FeedParser()
        state.fetcher = Fetcher()
        state.summarizer = None
        state.clusterer = None

        with TestClient(app, raise_server_exceptions=False) as test_client:
            yield test_client

        # Restore original state
        state.db = original_db
        state.cache = original_cache
        state.feed_parser = original_feed_parser
        state.fetcher = original_fetcher
        state.summarizer = original_summarizer
        state.clusterer = original_clusterer
        config.AUTH_API_KEY = original_auth_key

    def test_public_endpoint_accessible_without_auth(self, client_with_auth):
        """Health check should be accessible without auth even when enabled."""
        response = client_with_auth.get("/status")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["auth_enabled"] is True

    def test_protected_endpoint_requires_auth(self, client_with_auth):
        """Protected endpoints should require auth when enabled."""
        response = client_with_auth.get("/feeds")
        assert response.status_code == 401
        assert "Missing API key" in response.json()["detail"]

    def test_protected_endpoint_rejects_invalid_key(self, client_with_auth):
        """Protected endpoints should reject invalid keys."""
        response = client_with_auth.get("/feeds", headers={"X-API-Key": "wrong-key"})
        assert response.status_code == 401
        assert "Invalid API key" in response.json()["detail"]

    def test_protected_endpoint_accepts_valid_key(self, client_with_auth):
        """Protected endpoints should accept valid keys."""
        response = client_with_auth.get(
            "/feeds", headers={"X-API-Key": "test-secret-key-12345"}
        )
        assert response.status_code == 200

    def test_search_requires_auth(self, client_with_auth):
        """Search endpoint should require auth."""
        response = client_with_auth.get("/search?q=test")
        assert response.status_code == 401

    def test_search_with_auth(self, client_with_auth):
        """Search endpoint should work with valid auth."""
        response = client_with_auth.get(
            "/search?q=test", headers={"X-API-Key": "test-secret-key-12345"}
        )
        assert response.status_code == 200

    def test_articles_requires_auth(self, client_with_auth):
        """Articles endpoint should require auth."""
        response = client_with_auth.get("/articles")
        assert response.status_code == 401

    def test_articles_with_auth(self, client_with_auth):
        """Articles endpoint should work with valid auth."""
        response = client_with_auth.get(
            "/articles", headers={"X-API-Key": "test-secret-key-12345"}
        )
        assert response.status_code == 200

    def test_post_endpoint_requires_auth(self, client_with_auth):
        """POST endpoints should require auth."""
        response = client_with_auth.post(
            "/feeds", json={"url": "https://example.com/feed.xml"}
        )
        assert response.status_code == 401

    def test_delete_endpoint_requires_auth(self, client_with_auth):
        """DELETE endpoints should require auth."""
        response = client_with_auth.delete("/feeds/1")
        assert response.status_code == 401
