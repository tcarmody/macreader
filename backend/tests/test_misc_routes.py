"""
Tests for misc routes: health check, search, settings, stats.
"""

import pytest


class TestHealthCheck:
    """Tests for /status endpoint."""

    def test_health_check_returns_ok(self, client):
        """Health check should return status ok."""
        response = client.get("/status")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "version" in data
        assert "summarization_enabled" in data

    def test_health_check_shows_summarization_disabled(self, client):
        """Health check should show summarization disabled when no API key."""
        response = client.get("/status")
        data = response.json()
        # Summarization is disabled in test fixture
        assert data["summarization_enabled"] is False


class TestSearch:
    """Tests for /search endpoint."""

    def test_search_requires_query(self, client):
        """Search should require a query parameter."""
        response = client.get("/search")
        assert response.status_code == 422  # Validation error

    def test_search_rejects_short_query(self, client):
        """Search should reject queries shorter than 2 characters."""
        response = client.get("/search?q=a")
        assert response.status_code == 400
        assert "too short" in response.json()["detail"].lower()

    def test_search_returns_empty_for_no_matches(self, client):
        """Search should return empty list when no matches."""
        response = client.get("/search?q=nonexistent")
        assert response.status_code == 200
        assert response.json() == []

    def test_search_finds_matching_articles(self, client_with_data):
        """Search should find articles matching the query."""
        client, data = client_with_data
        response = client.get("/search?q=Test Article")
        assert response.status_code == 200
        results = response.json()
        assert len(results) >= 1
        assert any("Test Article" in r["title"] for r in results)

    def test_search_respects_limit(self, client_with_data):
        """Search should respect the limit parameter."""
        client, data = client_with_data
        response = client.get("/search?q=Test&limit=1")
        assert response.status_code == 200
        results = response.json()
        assert len(results) <= 1


class TestSettings:
    """Tests for /settings endpoints."""

    def test_get_settings_returns_defaults(self, client):
        """Get settings should return default values."""
        response = client.get("/settings")
        assert response.status_code == 200
        data = response.json()
        assert "refresh_interval_minutes" in data
        assert "auto_summarize" in data
        assert "mark_read_on_open" in data
        assert "default_model" in data

    def test_update_settings_refresh_interval(self, client):
        """Should be able to update refresh interval."""
        response = client.put("/settings", json={"refresh_interval_minutes": 60})
        assert response.status_code == 200
        data = response.json()
        assert data["refresh_interval_minutes"] == 60

    def test_update_settings_auto_summarize(self, client):
        """Should be able to update auto_summarize setting."""
        response = client.put("/settings", json={"auto_summarize": True})
        assert response.status_code == 200
        data = response.json()
        assert data["auto_summarize"] is True

    def test_update_settings_persists(self, client):
        """Updated settings should persist."""
        client.put("/settings", json={"default_model": "sonnet"})
        response = client.get("/settings")
        assert response.json()["default_model"] == "sonnet"

    def test_update_multiple_settings(self, client):
        """Should be able to update multiple settings at once."""
        response = client.put("/settings", json={
            "refresh_interval_minutes": 15,
            "auto_summarize": True,
            "mark_read_on_open": False
        })
        assert response.status_code == 200
        data = response.json()
        assert data["refresh_interval_minutes"] == 15
        assert data["auto_summarize"] is True
        assert data["mark_read_on_open"] is False


class TestStats:
    """Tests for /stats endpoint."""

    def test_stats_returns_counts(self, client):
        """Stats should return feed and unread counts."""
        response = client.get("/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total_feeds" in data
        assert "total_unread" in data
        assert "refresh_in_progress" in data

    def test_stats_empty_database(self, client):
        """Stats should return zeros for empty database."""
        response = client.get("/stats")
        data = response.json()
        assert data["total_feeds"] == 0
        assert data["total_unread"] == 0

    def test_stats_with_data(self, client_with_data):
        """Stats should reflect actual data."""
        client, data = client_with_data
        response = client.get("/stats")
        stats = response.json()
        assert stats["total_feeds"] == 1
        # One article is read, one is unread
        assert stats["total_unread"] == 1
