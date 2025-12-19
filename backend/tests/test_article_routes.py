"""
Tests for article routes.
"""

import pytest


class TestListArticles:
    """Tests for GET /articles endpoint."""

    def test_list_articles_empty(self, client):
        """Should return empty list when no articles."""
        response = client.get("/articles")
        assert response.status_code == 200
        assert response.json() == []

    def test_list_articles_returns_articles(self, client_with_data):
        """Should return list of articles."""
        client, data = client_with_data
        response = client.get("/articles")
        assert response.status_code == 200
        articles = response.json()
        assert len(articles) == 2

    def test_list_articles_has_required_fields(self, client_with_data):
        """Each article should have required fields."""
        client, data = client_with_data
        response = client.get("/articles")
        articles = response.json()
        article = articles[0]
        assert "id" in article
        assert "feed_id" in article
        assert "url" in article
        assert "title" in article
        assert "is_read" in article
        assert "is_bookmarked" in article
        assert "created_at" in article

    def test_list_articles_filter_by_feed(self, client_with_data):
        """Should filter articles by feed_id."""
        client, data = client_with_data
        response = client.get(f"/articles?feed_id={data['feed_id']}")
        assert response.status_code == 200
        articles = response.json()
        assert all(a["feed_id"] == data["feed_id"] for a in articles)

    def test_list_articles_unread_only(self, client_with_data):
        """Should filter to unread articles only."""
        client, data = client_with_data
        response = client.get("/articles?unread_only=true")
        assert response.status_code == 200
        articles = response.json()
        # One article was marked as read in fixture
        assert len(articles) == 1
        assert all(a["is_read"] is False for a in articles)

    def test_list_articles_respects_limit(self, client_with_data):
        """Should respect limit parameter."""
        client, data = client_with_data
        response = client.get("/articles?limit=1")
        assert response.status_code == 200
        articles = response.json()
        assert len(articles) == 1

    def test_list_articles_respects_offset(self, client_with_data):
        """Should respect offset parameter."""
        client, data = client_with_data
        response1 = client.get("/articles?limit=1&offset=0")
        response2 = client.get("/articles?limit=1&offset=1")
        articles1 = response1.json()
        articles2 = response2.json()
        assert len(articles1) == 1
        assert len(articles2) == 1
        assert articles1[0]["id"] != articles2[0]["id"]


class TestGetArticle:
    """Tests for GET /articles/{article_id} endpoint."""

    def test_get_article_not_found(self, client):
        """Should return 404 for non-existent article."""
        response = client.get("/articles/99999")
        assert response.status_code == 404

    def test_get_article_returns_detail(self, client_with_data):
        """Should return article with full details."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.get(f"/articles/{article_id}")
        assert response.status_code == 200
        article = response.json()
        assert article["id"] == article_id
        assert "content" in article  # Detail view includes content
        assert "summary_full" in article


class TestMarkRead:
    """Tests for POST /articles/{article_id}/read endpoint."""

    def test_mark_read(self, client_with_data):
        """Should mark article as read."""
        client, data = client_with_data
        article_id = data["article_ids"][1]  # Unread article
        response = client.post(f"/articles/{article_id}/read")
        assert response.status_code == 200
        assert response.json()["is_read"] is True

        # Verify it persisted
        article = client.get(f"/articles/{article_id}").json()
        assert article["is_read"] is True

    def test_mark_unread(self, client_with_data):
        """Should mark article as unread."""
        client, data = client_with_data
        article_id = data["article_ids"][0]  # Read article
        response = client.post(f"/articles/{article_id}/read?is_read=false")
        assert response.status_code == 200
        assert response.json()["is_read"] is False

    def test_mark_read_not_found(self, client):
        """Should return 404 for non-existent article."""
        response = client.post("/articles/99999/read")
        assert response.status_code == 404


class TestToggleBookmark:
    """Tests for POST /articles/{article_id}/bookmark endpoint."""

    def test_toggle_bookmark_on(self, client_with_data):
        """Should bookmark an article."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(f"/articles/{article_id}/bookmark")
        assert response.status_code == 200
        assert response.json()["is_bookmarked"] is True

    def test_toggle_bookmark_off(self, client_with_data):
        """Should unbookmark an already bookmarked article."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        # Bookmark it
        client.post(f"/articles/{article_id}/bookmark")
        # Toggle off
        response = client.post(f"/articles/{article_id}/bookmark")
        assert response.status_code == 200
        assert response.json()["is_bookmarked"] is False

    def test_toggle_bookmark_not_found(self, client):
        """Should return 404 for non-existent article."""
        response = client.post("/articles/99999/bookmark")
        assert response.status_code == 404


class TestBulkMarkRead:
    """Tests for POST /articles/bulk/read endpoint."""

    def test_bulk_mark_read(self, client_with_data):
        """Should mark multiple articles as read."""
        client, data = client_with_data
        response = client.post("/articles/bulk/read", json={
            "article_ids": data["article_ids"],
            "is_read": True
        })
        assert response.status_code == 200
        assert response.json()["count"] == 2

    def test_bulk_mark_read_empty_list(self, client):
        """Should reject empty article list."""
        response = client.post("/articles/bulk/read", json={
            "article_ids": [],
            "is_read": True
        })
        assert response.status_code == 400

    def test_bulk_mark_unread(self, client_with_data):
        """Should mark multiple articles as unread."""
        client, data = client_with_data
        response = client.post("/articles/bulk/read", json={
            "article_ids": data["article_ids"],
            "is_read": False
        })
        assert response.status_code == 200
        assert response.json()["is_read"] is False


class TestMarkFeedRead:
    """Tests for POST /articles/feed/{feed_id}/read endpoint."""

    def test_mark_feed_read(self, client_with_data):
        """Should mark all articles in feed as read."""
        client, data = client_with_data
        response = client.post(f"/articles/feed/{data['feed_id']}/read")
        assert response.status_code == 200
        assert response.json()["count"] == 2

        # Verify all are read
        articles = client.get("/articles?unread_only=true").json()
        assert len(articles) == 0

    def test_mark_feed_read_not_found(self, client):
        """Should return 404 for non-existent feed."""
        response = client.post("/articles/feed/99999/read")
        assert response.status_code == 404


class TestMarkAllRead:
    """Tests for POST /articles/all/read endpoint."""

    def test_mark_all_read(self, client_with_data):
        """Should mark all articles as read."""
        client, data = client_with_data
        response = client.post("/articles/all/read")
        assert response.status_code == 200
        assert response.json()["count"] == 2

    def test_mark_all_unread(self, client_with_data):
        """Should mark all articles as unread."""
        client, data = client_with_data
        response = client.post("/articles/all/read?is_read=false")
        assert response.status_code == 200

        # Verify all are unread
        articles = client.get("/articles?unread_only=true").json()
        assert len(articles) == 2


class TestGroupedArticles:
    """Tests for GET /articles/grouped endpoint."""

    def test_grouped_by_date(self, client_with_data):
        """Should group articles by date."""
        client, data = client_with_data
        response = client.get("/articles/grouped?group_by=date")
        assert response.status_code == 200
        result = response.json()
        assert result["group_by"] == "date"
        assert "groups" in result

    def test_grouped_by_feed(self, client_with_data):
        """Should group articles by feed."""
        client, data = client_with_data
        response = client.get("/articles/grouped?group_by=feed")
        assert response.status_code == 200
        result = response.json()
        assert result["group_by"] == "feed"
        assert len(result["groups"]) == 1  # One feed

    def test_grouped_by_topic_requires_api_key(self, client_with_data):
        """Topic grouping should fail without API key."""
        client, data = client_with_data
        response = client.get("/articles/grouped?group_by=topic")
        assert response.status_code == 503  # Service unavailable

    def test_grouped_invalid_group_by(self, client):
        """Should reject invalid group_by value."""
        response = client.get("/articles/grouped?group_by=invalid")
        assert response.status_code == 422
