"""
Tests for OAuth authentication.
"""

import pytest
from fastapi.testclient import TestClient

from backend.config import config, state
from backend.database import Database
from backend.cache import create_cache
from backend.feed_parser import FeedParser
from backend.fetcher import Fetcher
from backend.server import app


class TestOAuthDisabled:
    """Tests when OAuth is not configured."""

    def test_auth_status_shows_oauth_disabled(self, client):
        """Auth status should show OAuth as disabled when not configured."""
        response = client.get("/auth/status")
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is False
        assert data["google_enabled"] is False
        assert data["github_enabled"] is False
        assert data["user"] is None

    def test_login_fails_without_provider(self, client):
        """Login should fail when provider is not configured."""
        response = client.get("/auth/login/google", follow_redirects=False)
        assert response.status_code == 400
        assert "not configured" in response.json()["detail"]

    def test_login_rejects_unknown_provider(self, client):
        """Login should reject unknown providers."""
        response = client.get("/auth/login/facebook", follow_redirects=False)
        assert response.status_code == 400
        assert "Unknown provider" in response.json()["detail"]


class TestOAuthEnabled:
    """Tests when OAuth is configured."""

    @pytest.fixture
    def client_with_oauth(self, temp_db_path, temp_cache_dir):
        """Create a test client with OAuth enabled."""
        # Store original state
        original_db = state.db
        original_cache = state.cache
        original_feed_parser = state.feed_parser
        original_fetcher = state.fetcher
        original_summarizer = state.summarizer
        original_clusterer = state.clusterer
        original_session_secret = config.SESSION_SECRET
        original_google_id = config.GOOGLE_CLIENT_ID
        original_google_secret = config.GOOGLE_CLIENT_SECRET
        original_github_id = config.GITHUB_CLIENT_ID
        original_github_secret = config.GITHUB_CLIENT_SECRET

        # Enable OAuth with Google
        config.SESSION_SECRET = "test-secret-for-signing-sessions"
        config.GOOGLE_CLIENT_ID = "test-google-client-id"
        config.GOOGLE_CLIENT_SECRET = "test-google-client-secret"

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
        config.SESSION_SECRET = original_session_secret
        config.GOOGLE_CLIENT_ID = original_google_id
        config.GOOGLE_CLIENT_SECRET = original_google_secret
        config.GITHUB_CLIENT_ID = original_github_id
        config.GITHUB_CLIENT_SECRET = original_github_secret

    def test_auth_status_shows_oauth_enabled(self, client_with_oauth):
        """Auth status should show OAuth as enabled when configured."""
        response = client_with_oauth.get("/auth/status")
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is True
        assert data["google_enabled"] is True
        assert data["github_enabled"] is False  # Only Google configured
        assert data["user"] is None  # Not logged in

    def test_protected_endpoint_requires_auth(self, client_with_oauth):
        """Protected endpoints should require auth when OAuth is enabled."""
        response = client_with_oauth.get("/feeds")
        assert response.status_code == 401

    def test_logout_without_session(self, client_with_oauth):
        """Logout should work even without a session."""
        response = client_with_oauth.post("/auth/logout")
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "Logged out successfully"

    def test_get_me_without_session(self, client_with_oauth):
        """Getting current user without session should return null."""
        response = client_with_oauth.get("/auth/me")
        assert response.status_code == 200
        assert response.json() is None


class TestOAuthWithAPIKey:
    """Tests when both OAuth and API key auth are configured."""

    @pytest.fixture
    def client_with_both(self, temp_db_path, temp_cache_dir):
        """Create a test client with both OAuth and API key auth enabled."""
        # Store original state
        original_db = state.db
        original_cache = state.cache
        original_feed_parser = state.feed_parser
        original_fetcher = state.fetcher
        original_summarizer = state.summarizer
        original_clusterer = state.clusterer
        original_auth_key = config.AUTH_API_KEY
        original_session_secret = config.SESSION_SECRET
        original_google_id = config.GOOGLE_CLIENT_ID
        original_google_secret = config.GOOGLE_CLIENT_SECRET

        # Enable both
        config.AUTH_API_KEY = "test-api-key-12345"
        config.SESSION_SECRET = "test-secret-for-signing-sessions"
        config.GOOGLE_CLIENT_ID = "test-google-client-id"
        config.GOOGLE_CLIENT_SECRET = "test-google-client-secret"

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
        config.SESSION_SECRET = original_session_secret
        config.GOOGLE_CLIENT_ID = original_google_id
        config.GOOGLE_CLIENT_SECRET = original_google_secret

    def test_api_key_works_with_oauth_enabled(self, client_with_both):
        """API key should still work when OAuth is also enabled."""
        response = client_with_both.get(
            "/feeds", headers={"X-API-Key": "test-api-key-12345"}
        )
        assert response.status_code == 200

    def test_invalid_api_key_rejected(self, client_with_both):
        """Invalid API key should be rejected even with OAuth enabled."""
        response = client_with_both.get(
            "/feeds", headers={"X-API-Key": "wrong-key"}
        )
        assert response.status_code == 401

    def test_no_auth_rejected(self, client_with_both):
        """Requests without any auth should be rejected."""
        response = client_with_both.get("/feeds")
        assert response.status_code == 401
