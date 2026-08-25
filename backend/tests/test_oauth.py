"""
Tests for OAuth authentication.
"""

from urllib.parse import parse_qs, urlparse

import pytest
from fastapi.testclient import TestClient
from itsdangerous import URLSafeTimedSerializer

from backend import oauth as oauth_module
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


class TestOAuthStateWithoutCookie:
    """
    The OAuth `state` round-trip must not depend on the session cookie.

    The cookie has to survive frontend domain → API → Google → API, which mobile
    browsers routinely drop, producing "CSRF Warning! State not equal in request
    and response" and a login that fails on every retry.
    """

    @pytest.fixture
    def oauth_client(self, temp_db_path, temp_cache_dir, monkeypatch):
        """Test client with Google OAuth enabled and no network calls."""
        monkeypatch.setattr(config, "SESSION_SECRET", "test-secret-for-signing-sessions")
        monkeypatch.setattr(config, "GOOGLE_CLIENT_ID", "test-google-client-id")
        monkeypatch.setattr(config, "GOOGLE_CLIENT_SECRET", "test-google-client-secret")
        monkeypatch.setattr(config, "OAUTH_ALLOWED_EMAILS", "")
        monkeypatch.setattr(config, "OAUTH_FRONTEND_URL", "https://app.example.com")

        # Serializers are memoized globals; drop them so they pick up the test secret.
        monkeypatch.setattr(oauth_module, "_serializer", None)
        monkeypatch.setattr(oauth_module, "_state_serializer", None)

        monkeypatch.setattr(state, "db", Database(temp_db_path))
        monkeypatch.setattr(state, "cache", create_cache(temp_cache_dir))
        monkeypatch.setattr(state, "feed_parser", FeedParser())
        monkeypatch.setattr(state, "fetcher", Fetcher())
        monkeypatch.setattr(state, "summarizer", None)
        monkeypatch.setattr(state, "clusterer", None)

        # lifespan() skips startup entirely when state.db is already set, so the
        # providers have to be registered by hand here.
        monkeypatch.setattr(oauth_module.oauth, "_registry", {})
        monkeypatch.setattr(oauth_module.oauth, "_clients", {})
        oauth_module.setup_oauth()

        # https base URL so the Secure `dp_oauth_state` cookie is actually stored
        # by the client — over http it is silently dropped and every test here
        # would exercise the no-cookie path.
        with TestClient(
            app, base_url="https://api.example.com", raise_server_exceptions=False
        ) as test_client:
            google = oauth_module.oauth.create_client("google")

            async def fake_metadata(*args, **kwargs):
                return {
                    "authorization_endpoint": "https://accounts.google.com/o/oauth2/v2/auth",
                    "token_endpoint": "https://oauth2.googleapis.com/token",
                    "issuer": "https://accounts.google.com",
                }

            async def fake_fetch_access_token(**params):
                # No id_token, so authlib skips nonce verification against Google.
                return {
                    "access_token": "test-access-token",
                    "userinfo": {"email": "reader@example.com", "name": "Reader"},
                }

            monkeypatch.setattr(google, "load_server_metadata", fake_metadata)
            monkeypatch.setattr(google, "fetch_access_token", fake_fetch_access_token)
            yield test_client

    @staticmethod
    def _start_login(test_client) -> str:
        """Begin a login and return the `state` handed to Google."""
        response = test_client.get("/auth/login/google", follow_redirects=False)
        assert response.status_code == 302
        query = parse_qs(urlparse(response.headers["location"]).query)
        return query["state"][0]

    def test_callback_succeeds_when_state_cookie_is_dropped(self, oauth_client):
        """A callback with no session cookie must still complete the login."""
        state_token = self._start_login(oauth_client)

        # The phone never sends `dp_oauth_state` back.
        oauth_client.cookies.clear()

        response = oauth_client.get(
            f"/auth/callback/google?code=test-code&state={state_token}",
            follow_redirects=False,
        )

        assert response.status_code == 302, response.text
        location = response.headers["location"]
        assert location.startswith("https://app.example.com?auth_token=")
        assert "auth_token=" in location

    def test_callback_succeeds_when_state_cookie_survives(self, oauth_client):
        """The normal cookie-backed path keeps working."""
        state_token = self._start_login(oauth_client)
        assert "dp_oauth_state" in oauth_client.cookies

        response = oauth_client.get(
            f"/auth/callback/google?code=test-code&state={state_token}",
            follow_redirects=False,
        )

        assert response.status_code == 302, response.text
        assert "auth_token=" in response.headers["location"]

    def test_callback_rejects_forged_state(self, oauth_client):
        """An unsigned state is still refused — this is the CSRF guard."""
        self._start_login(oauth_client)
        oauth_client.cookies.clear()

        response = oauth_client.get(
            "/auth/callback/google?code=test-code&state=not-a-signed-state",
            follow_redirects=False,
        )

        assert response.status_code == 400
        assert "Invalid login state" in response.json()["detail"]

    def test_callback_rejects_state_signed_with_another_secret(self, oauth_client):
        """State signed with a different key must not be accepted."""
        forged = URLSafeTimedSerializer(
            "some-other-secret", salt="datapoints-oauth-state"
        ).dumps({"provider": "google", "redirect_uri": "https://evil.example.com"})

        oauth_client.cookies.clear()
        response = oauth_client.get(
            f"/auth/callback/google?code=test-code&state={forged}",
            follow_redirects=False,
        )

        assert response.status_code == 400
        assert "Invalid login state" in response.json()["detail"]

    def test_callback_rejects_expired_state(self, oauth_client, monkeypatch):
        """A state older than STATE_MAX_AGE is refused with a retry hint."""
        state_token = self._start_login(oauth_client)
        oauth_client.cookies.clear()
        monkeypatch.setattr(oauth_module, "STATE_MAX_AGE", -1)

        response = oauth_client.get(
            f"/auth/callback/google?code=test-code&state={state_token}",
            follow_redirects=False,
        )

        assert response.status_code == 400
        assert "took too long" in response.json()["detail"]

    def test_session_token_is_not_accepted_as_state(self, oauth_client):
        """The two signed-token namespaces are separated by salt."""
        session_token = oauth_module.get_serializer().dumps(
            {"provider": "google", "redirect_uri": "https://app.example.com"}
        )

        oauth_client.cookies.clear()
        response = oauth_client.get(
            f"/auth/callback/google?code=test-code&state={session_token}",
            follow_redirects=False,
        )

        assert response.status_code == 400


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
