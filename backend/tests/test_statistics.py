"""
Tests for the statistics repository.

Regression coverage for reading stats: read/bookmark state moved from the
articles table to per-user user_article_state, so get_reading_stats must query
that table (scoped to a user) rather than the dropped articles.is_read columns.
"""

from datetime import datetime, timedelta


def _seed(db):
    user_id = db.users.get_or_create_api_user()
    feed_id = db.add_feed("https://example.com/feed.xml", "Stats Feed", "News")
    a1 = db.add_article(feed_id, "https://example.com/1", "One", "Body one with enough words here.")
    a2 = db.add_article(feed_id, "https://example.com/2", "Two", "Body two with enough words here.")
    a3 = db.add_article(feed_id, "https://example.com/3", "Three", "Body three with enough words here.")
    return user_id, feed_id, [a1, a2, a3]


def test_get_reading_stats_runs_and_counts_per_user(test_db):
    """Reproduces the 500: get_reading_stats queried the dropped articles.is_read column."""
    db = test_db
    user_id, feed_id, (a1, a2, a3) = _seed(db)

    # User reads two articles and bookmarks one.
    db.mark_read(user_id, a1, True)
    db.mark_read(user_id, a2, True)
    db.toggle_bookmark(user_id, a3)

    now = datetime.now()
    stats = db.statistics.get_reading_stats(
        user_id=user_id,
        start_date=now - timedelta(days=30),
        end_date=now + timedelta(minutes=1),
    )

    assert stats["articles_read"] == 2
    assert stats["bookmarks_added"] == 1
    assert isinstance(stats["read_by_feed"], dict)
    assert stats["read_by_feed"].get("Stats Feed") == 2


def test_get_reading_stats_is_per_user(test_db):
    """One user's reads must not count toward another user's stats."""
    db = test_db
    reader = db.users.get_or_create(email="reader@example.com", provider="google")
    other = db.users.get_or_create(email="other@example.com", provider="google")
    feed_id = db.add_feed("https://example.com/feed.xml", "Feed", "News")
    art = db.add_article(feed_id, "https://example.com/1", "One", "Body with enough words here.")

    db.mark_read(reader, art, True)

    now = datetime.now()
    window = dict(start_date=now - timedelta(days=30), end_date=now + timedelta(minutes=1))
    assert db.statistics.get_reading_stats(user_id=reader, **window)["articles_read"] == 1
    assert db.statistics.get_reading_stats(user_id=other, **window)["articles_read"] == 0


def test_reading_stats_endpoint_returns_200(client_with_data):
    """End-to-end: the endpoint used to 500 querying the dropped articles.is_read column."""
    test_client, _ = client_with_data
    resp = test_client.get("/statistics/reading-stats")
    assert resp.status_code == 200
    assert "reading" in resp.json()
