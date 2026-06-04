"""
Tests for the non-admin feed-visibility allowlist.

Non-admin (web) users see only feeds marked public (is_public), PLUS any article
that has been individually Featured — so curated items from private feeds still
surface on the web. Admins (API-key clients like the macOS app, and OAuth users in
ADMIN_EMAILS) see everything. Reading stats and topic clustering are admin-only.

Admin identity in these tests = the shared API-key user (provider "api_key", always
admin). Non-admin = an OAuth ("google") user whose email is not in ADMIN_EMAILS.
"""

import pytest
from fastapi.testclient import TestClient

from backend.auth import get_current_user
from backend.server import app
from backend.tests.conftest import isolated_test_state


@pytest.fixture
def vis(temp_db_path, temp_cache_dir):
    """Isolated DB with a public feed, a private feed, and a featured private article."""
    with isolated_test_state(temp_db_path, temp_cache_dir) as db:
        admin_id = db.users.get_or_create_api_user()  # provider "api_key" -> admin
        reader_id = db.users.get_or_create(
            email="reader@example.com", name="Reader", provider="google"
        )  # not in ADMIN_EMAILS -> non-admin

        public_feed = db.add_feed("https://pub.example.com/feed.xml", "Public Feed", "News")
        private_feed = db.add_feed("https://priv.example.com/feed.xml", "Private Feed", "News")
        db.update_feed(public_feed, is_public=True)

        pub_article = db.add_article(
            public_feed, "https://pub.example.com/a1", "Public Pythons",
            "Public content all about pythons and snakes, plenty of words here.",
        )
        priv_article = db.add_article(
            private_feed, "https://priv.example.com/a1", "Private Pythons",
            "Secret content all about pythons, definitely enough words to index.",
        )
        priv_featured = db.add_article(
            private_feed, "https://priv.example.com/a2", "Featured Private Pythons",
            "Curated content about pythons that an admin chose to feature publicly.",
        )
        db.feature_article(priv_featured, admin_id)

        ids = {
            "admin_id": admin_id,
            "reader_id": reader_id,
            "public_feed": public_feed,
            "private_feed": private_feed,
            "pub_article": pub_article,
            "priv_article": priv_article,
            "priv_featured": priv_featured,
        }
        with TestClient(app, raise_server_exceptions=False) as client:
            yield client, db, ids
    app.dependency_overrides.pop(get_current_user, None)


def act_as(user_id: int):
    """Override the authenticated user for subsequent requests."""
    app.dependency_overrides[get_current_user] = lambda: user_id


# ─────────────────────────────────────────────────────────────
# Repository-level filtering (pure, no HTTP)
# ─────────────────────────────────────────────────────────────

def test_migration_defaults_feeds_private(vis):
    _, db, ids = vis
    private = db.get_feed(ids["private_feed"])
    assert private.is_public is False  # allowlist: private until published


def test_get_feeds_admin_sees_all_nonadmin_sees_public(vis):
    _, db, ids = vis
    admin_feeds = {f.id for f in db.get_feeds(ids["admin_id"], admin=True)}
    reader_feeds = {f.id for f in db.get_feeds(ids["reader_id"], admin=False)}
    assert {ids["public_feed"], ids["private_feed"]} <= admin_feeds
    assert reader_feeds == {ids["public_feed"]}


def test_get_visible_feed_ids(vis):
    _, db, ids = vis
    assert db.get_visible_feed_ids(admin=True) is None  # unrestricted
    assert db.get_visible_feed_ids(admin=False) == {ids["public_feed"]}


def test_get_articles_nonadmin_excludes_private_includes_featured(vis):
    _, db, ids = vis
    reader_ids = {a.id for a in db.get_articles(ids["reader_id"], admin=False, limit=100)}
    assert ids["pub_article"] in reader_ids
    assert ids["priv_featured"] in reader_ids   # featured bypasses the allowlist
    assert ids["priv_article"] not in reader_ids


def test_get_articles_admin_sees_everything(vis):
    _, db, ids = vis
    admin_ids = {a.id for a in db.get_articles(ids["admin_id"], admin=True, limit=100)}
    assert {ids["pub_article"], ids["priv_article"], ids["priv_featured"]} <= admin_ids


def test_get_shared_since_respects_visibility(vis):
    from datetime import datetime, timedelta
    _, db, ids = vis
    since = datetime.now() - timedelta(days=1)
    reader = {a.id for a in db.get_articles_since(since, admin=False)}
    assert ids["pub_article"] in reader
    assert ids["priv_featured"] in reader
    assert ids["priv_article"] not in reader


# ─────────────────────────────────────────────────────────────
# Route-level enforcement
# ─────────────────────────────────────────────────────────────

def test_feeds_endpoint_filtered_for_nonadmin(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    resp = client.get("/feeds")
    assert resp.status_code == 200
    returned = {f["id"] for f in resp.json()}
    assert returned == {ids["public_feed"]}
    assert all("is_public" in f for f in resp.json())


def test_articles_endpoint_filtered_for_nonadmin(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    resp = client.get("/articles?limit=100")
    assert resp.status_code == 200
    returned = {a["id"] for a in resp.json()}
    assert ids["pub_article"] in returned
    assert ids["priv_featured"] in returned
    assert ids["priv_article"] not in returned


def test_article_detail_private_is_404_for_nonadmin(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    assert client.get(f"/articles/{ids['priv_article']}").status_code == 404
    assert client.get(f"/articles/{ids['priv_featured']}").status_code == 200
    assert client.get(f"/articles/{ids['pub_article']}").status_code == 200


def test_article_detail_private_ok_for_admin(vis):
    client, _, ids = vis
    act_as(ids["admin_id"])
    assert client.get(f"/articles/{ids['priv_article']}").status_code == 200


def test_search_excludes_private_for_nonadmin(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    resp = client.get("/search?q=pythons&limit=50")
    assert resp.status_code == 200
    returned = {a["id"] for a in resp.json()}
    assert ids["priv_article"] not in returned
    assert ids["pub_article"] in returned


def test_search_admin_sees_private(vis):
    client, _, ids = vis
    act_as(ids["admin_id"])
    resp = client.get("/search?q=pythons&limit=50")
    assert resp.status_code == 200
    returned = {a["id"] for a in resp.json()}
    assert ids["priv_article"] in returned


def test_statistics_admin_only(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    # Non-admins are blocked at the router (require_admin) -> 403.
    assert client.get("/statistics/reading-stats").status_code == 403
    assert client.get("/statistics/topics/current").status_code == 403
    assert client.get("/statistics/topics/trends").status_code == 403
    # Admins pass the gate. (reading-stats has an unrelated latent bug querying the
    # dropped articles.is_read column, so assert against a working stats endpoint.)
    act_as(ids["admin_id"])
    assert client.get("/statistics/topics/current").status_code == 200


def test_grouped_topic_blocked_for_nonadmin(vis):
    client, _, ids = vis
    act_as(ids["reader_id"])
    assert client.get("/articles/grouped?group_by=topic").status_code == 403
    # date/feed grouping still works, and is feed-filtered
    resp = client.get("/articles/grouped?group_by=feed")
    assert resp.status_code == 200


def test_feature_endpoint_makes_article_visible_to_all_users(vis):
    """Admin features a private-feed article via POST /feature; a non-admin reader
    then sees it everywhere (featured filter, full list, detail) flagged is_featured.

    This exercises the full HTTP path (not just the db helper) to confirm featuring
    is global, not scoped to the admin who performed it.
    """
    client, _, ids = vis
    target = ids["priv_article"]  # private-feed article, not featured in the fixture

    # Non-admin can't see it yet (private feed, not featured).
    act_as(ids["reader_id"])
    assert client.get(f"/articles/{target}").status_code == 404

    # Admin features it through the endpoint.
    act_as(ids["admin_id"])
    resp = client.post(f"/articles/{target}/feature", json={"note": "Editor's pick"})
    assert resp.status_code == 200
    assert resp.json()["is_featured"] is True

    # A different (non-admin) user now sees it as featured, everywhere.
    act_as(ids["reader_id"])
    featured = client.get("/articles?featured_only=true&limit=100")
    assert featured.status_code == 200
    featured_by_id = {a["id"]: a for a in featured.json()}
    assert target in featured_by_id
    assert featured_by_id[target]["is_featured"] is True
    assert featured_by_id[target]["featured_note"] == "Editor's pick"

    full_list = {a["id"] for a in client.get("/articles?limit=100").json()}
    assert target in full_list  # featured bypasses the private-feed allowlist
    assert client.get(f"/articles/{target}").status_code == 200


def test_feature_endpoint_blocked_for_nonadmin(vis):
    """Non-admins cannot feature (require_admin -> 403) and the article stays unfeatured."""
    client, db, ids = vis
    target = ids["priv_article"]
    act_as(ids["reader_id"])
    assert client.post(f"/articles/{target}/feature", json={"note": "nope"}).status_code == 403
    assert db.get_article(target).is_featured is False


def test_update_feed_visibility_toggle(vis):
    client, db, ids = vis
    act_as(ids["admin_id"])
    # Publish the private feed
    resp = client.put(f"/feeds/{ids['private_feed']}", json={"is_public": True})
    assert resp.status_code == 200
    assert resp.json()["is_public"] is True
    assert db.get_visible_feed_ids(admin=False) == {ids["public_feed"], ids["private_feed"]}
    # Unpublish the public feed
    resp = client.put(f"/feeds/{ids['public_feed']}", json={"is_public": False})
    assert resp.status_code == 200
    assert resp.json()["is_public"] is False
    assert db.get_visible_feed_ids(admin=False) == {ids["private_feed"]}
