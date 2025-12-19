"""
Tests for feed routes.
"""

import pytest


class TestListFeeds:
    """Tests for GET /feeds endpoint."""

    def test_list_feeds_empty(self, client):
        """Should return empty list when no feeds."""
        response = client.get("/feeds")
        assert response.status_code == 200
        assert response.json() == []

    def test_list_feeds_returns_feeds(self, client_with_data):
        """Should return list of feeds."""
        client, data = client_with_data
        response = client.get("/feeds")
        assert response.status_code == 200
        feeds = response.json()
        assert len(feeds) == 1

    def test_list_feeds_has_required_fields(self, client_with_data):
        """Each feed should have required fields."""
        client, data = client_with_data
        response = client.get("/feeds")
        feeds = response.json()
        feed = feeds[0]
        assert "id" in feed
        assert "url" in feed
        assert "name" in feed
        assert "category" in feed
        assert "unread_count" in feed
        assert "last_fetched" in feed

    def test_list_feeds_includes_unread_count(self, client_with_data):
        """Feed should include correct unread count."""
        client, data = client_with_data
        response = client.get("/feeds")
        feeds = response.json()
        # One article read, one unread
        assert feeds[0]["unread_count"] == 1


class TestAddFeed:
    """Tests for POST /feeds endpoint."""

    @pytest.mark.skip(reason="Requires network access to validate feed URL")
    def test_add_feed_valid_url(self, client):
        """Should add a valid feed."""
        response = client.post("/feeds", json={
            "url": "https://example.com/feed.xml",
            "name": "My Feed"
        })
        assert response.status_code == 200
        feed = response.json()
        assert feed["name"] == "My Feed"

    def test_add_feed_invalid_url(self, client):
        """Should reject invalid feed URL."""
        response = client.post("/feeds", json={
            "url": "not-a-valid-url"
        })
        assert response.status_code == 400

    def test_add_feed_missing_url(self, client):
        """Should require URL."""
        response = client.post("/feeds", json={})
        assert response.status_code == 422


class TestDeleteFeed:
    """Tests for DELETE /feeds/{feed_id} endpoint."""

    def test_delete_feed(self, client_with_data):
        """Should delete a feed."""
        client, data = client_with_data
        response = client.delete(f"/feeds/{data['feed_id']}")
        assert response.status_code == 200
        assert response.json()["success"] is True

        # Verify it's gone
        feeds = client.get("/feeds").json()
        assert len(feeds) == 0

    def test_delete_feed_not_found(self, client):
        """Should return 404 for non-existent feed."""
        response = client.delete("/feeds/99999")
        assert response.status_code == 404

    def test_delete_feed_cascades_articles(self, client_with_data):
        """Deleting feed should delete its articles."""
        client, data = client_with_data
        client.delete(f"/feeds/{data['feed_id']}")

        # Verify articles are gone
        articles = client.get("/articles").json()
        assert len(articles) == 0


class TestUpdateFeed:
    """Tests for PUT /feeds/{feed_id} endpoint."""

    def test_update_feed_name(self, client_with_data):
        """Should update feed name."""
        client, data = client_with_data
        response = client.put(f"/feeds/{data['feed_id']}", json={
            "name": "Updated Name"
        })
        assert response.status_code == 200
        assert response.json()["name"] == "Updated Name"

    def test_update_feed_category(self, client_with_data):
        """Should update feed category."""
        client, data = client_with_data
        response = client.put(f"/feeds/{data['feed_id']}", json={
            "category": "New Category"
        })
        assert response.status_code == 200
        assert response.json()["category"] == "New Category"

    def test_update_feed_not_found(self, client):
        """Should return 404 for non-existent feed."""
        response = client.put("/feeds/99999", json={"name": "Test"})
        assert response.status_code == 404


class TestBulkDeleteFeeds:
    """Tests for POST /feeds/bulk/delete endpoint."""

    def test_bulk_delete_feeds(self, client_with_data):
        """Should delete multiple feeds."""
        client, data = client_with_data
        response = client.post("/feeds/bulk/delete", json={
            "feed_ids": [data["feed_id"]]
        })
        assert response.status_code == 200
        assert response.json()["count"] == 1

    def test_bulk_delete_empty_list(self, client):
        """Should reject empty feed list."""
        response = client.post("/feeds/bulk/delete", json={
            "feed_ids": []
        })
        assert response.status_code == 400


class TestRefreshFeeds:
    """Tests for feed refresh endpoints."""

    def test_refresh_all_feeds(self, client_with_data):
        """Should trigger refresh of all feeds."""
        client, data = client_with_data
        response = client.post("/feeds/refresh")
        assert response.status_code == 200
        assert "message" in response.json()

    def test_refresh_single_feed(self, client_with_data):
        """Should trigger refresh of single feed."""
        client, data = client_with_data
        response = client.post(f"/feeds/{data['feed_id']}/refresh")
        assert response.status_code == 200
        assert "message" in response.json()

    def test_refresh_feed_not_found(self, client):
        """Should return 404 for non-existent feed."""
        response = client.post("/feeds/99999/refresh")
        assert response.status_code == 404


class TestOPMLExport:
    """Tests for GET /feeds/export-opml endpoint."""

    def test_export_opml_empty(self, client):
        """Should export empty OPML."""
        response = client.get("/feeds/export-opml")
        assert response.status_code == 200
        data = response.json()
        assert "opml" in data
        assert data["feed_count"] == 0

    def test_export_opml_with_feeds(self, client_with_data):
        """Should export OPML with feeds."""
        client, data = client_with_data
        response = client.get("/feeds/export-opml")
        assert response.status_code == 200
        result = response.json()
        assert result["feed_count"] == 1
        assert "<?xml" in result["opml"]
        assert "example.com" in result["opml"]


class TestOPMLImport:
    """Tests for POST /feeds/import-opml endpoint."""

    def test_import_opml_invalid_xml(self, client):
        """Should reject invalid OPML."""
        response = client.post("/feeds/import-opml", json={
            "opml_content": "not valid xml"
        })
        assert response.status_code == 400

    def test_import_opml_empty_feeds(self, client):
        """Should reject OPML with no feeds."""
        opml = """<?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
            <head><title>Test</title></head>
            <body></body>
        </opml>"""
        response = client.post("/feeds/import-opml", json={
            "opml_content": opml
        })
        assert response.status_code == 400
        assert "No feeds found" in response.json()["detail"]

    def test_import_opml_missing_content(self, client):
        """Should require opml_content field."""
        response = client.post("/feeds/import-opml", json={})
        assert response.status_code == 422
