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


class TestFeatureArticle:
    """Tests for POST/DELETE /articles/{article_id}/feature endpoints and featured_only filter."""

    def test_feature_article(self, client_with_data):
        """Featuring an article sets is_featured=true and stores the editorial note."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/feature",
            json={"note": "Editor's pick of the week."},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["id"] == article_id
        assert body["is_featured"] is True
        assert body["featured_note"] == "Editor's pick of the week."
        assert body["featured_at"] is not None

    def test_feature_article_not_found(self, client):
        """Featuring a missing article returns 404."""
        response = client.post("/articles/99999/feature", json={"note": None})
        assert response.status_code == 404

    def test_refeaturing_updates_note_only(self, client_with_data):
        """Re-featuring an already-featured article updates the note without duplicating."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        client.post(f"/articles/{article_id}/feature", json={"note": "first"})
        response = client.post(
            f"/articles/{article_id}/feature", json={"note": "second"}
        )
        assert response.status_code == 200
        assert response.json()["featured_note"] == "second"

        # Total featured count should still be 1
        stats = client.get("/stats").json()
        assert stats["featured_articles"] == 1

    def test_unfeature_article(self, client_with_data):
        """Unfeaturing clears is_featured and the editorial note."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        client.post(f"/articles/{article_id}/feature", json={"note": "pinned"})
        response = client.delete(f"/articles/{article_id}/feature")
        assert response.status_code == 200
        body = response.json()
        assert body["is_featured"] is False
        assert body["featured_note"] is None
        assert body["featured_at"] is None

    def test_featured_only_filter(self, client_with_data):
        """featured_only=true returns only featured articles."""
        client, data = client_with_data
        first, second = data["article_ids"]
        client.post(f"/articles/{first}/feature", json={"note": "yes"})

        response = client.get("/articles?featured_only=true")
        assert response.status_code == 200
        ids = [a["id"] for a in response.json()]
        assert ids == [first]
        assert second not in ids

    def test_feature_cap_evicts_oldest(self, client, test_db):
        """Adding a 33rd featured article evicts the oldest by featured_at."""
        import time

        # Build a feed and 33 articles
        feed_id = test_db.add_feed("https://cap.example/feed.xml", "Cap Feed")
        article_ids = []
        for i in range(33):
            aid = test_db.add_article(
                feed_id=feed_id,
                url=f"https://cap.example/a{i}",
                title=f"Article {i}",
                content="filler content " * 10,
            )
            article_ids.append(aid)

        # Feature the first 32, sleeping briefly so featured_at is strictly ordered
        for aid in article_ids[:32]:
            response = client.post(f"/articles/{aid}/feature", json={"note": None})
            assert response.status_code == 200
            time.sleep(0.002)

        assert client.get("/stats").json()["featured_articles"] == 32

        # Featuring the 33rd should evict the oldest (article_ids[0])
        response = client.post(
            f"/articles/{article_ids[32]}/feature", json={"note": None}
        )
        assert response.status_code == 200

        # Total stays at 32
        assert client.get("/stats").json()["featured_articles"] == 32

        # The newest is in, the oldest is out
        featured = client.get("/articles?featured_only=true&limit=200").json()
        featured_ids = {a["id"] for a in featured}
        assert article_ids[32] in featured_ids
        assert article_ids[0] not in featured_ids

    def test_feature_note_validation_too_long(self, client_with_data):
        """Notes longer than 500 chars are rejected."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/feature", json={"note": "x" * 501}
        )
        assert response.status_code == 422

    def test_feature_note_blank_stored_as_null(self, client_with_data):
        """A blank/whitespace note is stored as null."""
        client, data = client_with_data
        article_id = data["article_ids"][0]
        response = client.post(
            f"/articles/{article_id}/feature", json={"note": "   "}
        )
        assert response.status_code == 200
        assert response.json()["featured_note"] is None
