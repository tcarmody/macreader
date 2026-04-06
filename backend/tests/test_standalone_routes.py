"""
Tests for standalone (library) routes.

Focuses on the duplicate URL behavior: when a URL already exists in the
database (either in the user's library or as an RSS article), adding it
again should bookmark it and return the existing article rather than error.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock

from backend.config import state
from backend.fetcher import FetchResult


def make_fetch_result(url: str, title: str = "Test Article", content: str = "Some content") -> FetchResult:
    """Helper to create a mock FetchResult."""
    result = FetchResult.__new__(FetchResult)
    result.url = url
    result.title = title
    result.content = content
    result.author = None
    result.published = None
    result.source = "direct"
    result.content_hash = None
    result.reading_time_minutes = None
    result.word_count = None
    result.categories = None
    result.tags = None
    result.featured_image = None
    result.has_code_blocks = False
    result.code_languages = None
    result.is_paywalled = False
    result.site_name = None
    result.extractor_used = "generic"
    return result


class TestAddUrlDuplicate:
    """Tests for duplicate URL handling in POST /standalone/url."""

    def test_duplicate_library_url_bookmarks_and_returns_existing(self, client_with_data):
        """When a URL already exists in the user's library, bookmark it and return it."""
        client, data = client_with_data

        url = "https://example.com/my-saved-article"

        # Set up a mock fetcher that returns a valid result
        mock_fetcher = MagicMock()
        mock_fetcher.fetch = AsyncMock(return_value=make_fetch_result(url))
        original_fetcher = state.fetcher
        state.fetcher = mock_fetcher

        try:
            # First add — should succeed
            response1 = client.post("/standalone/url", json={"url": url})
            assert response1.status_code == 200
            item1 = response1.json()
            assert item1["already_existed"] is False
            assert item1["is_bookmarked"] is False

            # Second add of same URL — should bookmark and return existing
            response2 = client.post("/standalone/url", json={"url": url})
            assert response2.status_code == 200
            item2 = response2.json()
            assert item2["already_existed"] is True
            assert item2["is_bookmarked"] is True
            assert item2["id"] == item1["id"]
        finally:
            state.fetcher = original_fetcher

    def test_duplicate_rss_url_bookmarks_rss_article(self, client_with_data):
        """When a URL exists as an RSS article, bookmark it and return it."""
        client, data = client_with_data

        # Use a URL that exists as an RSS article (added in client_with_data fixture)
        rss_url = "https://example.com/article1"

        mock_fetcher = MagicMock()
        mock_fetcher.fetch = AsyncMock(return_value=make_fetch_result(rss_url))
        original_fetcher = state.fetcher
        state.fetcher = mock_fetcher

        try:
            response = client.post("/standalone/url", json={"url": rss_url})
            assert response.status_code == 200
            item = response.json()
            assert item["already_existed"] is True
            assert item["is_bookmarked"] is True
        finally:
            state.fetcher = original_fetcher

    def test_duplicate_already_bookmarked_stays_bookmarked(self, client_with_data):
        """If the existing article is already bookmarked, it stays bookmarked."""
        client, data = client_with_data

        url = "https://example.com/pre-bookmarked"

        mock_fetcher = MagicMock()
        mock_fetcher.fetch = AsyncMock(return_value=make_fetch_result(url))
        original_fetcher = state.fetcher
        state.fetcher = mock_fetcher

        try:
            # Add once
            response1 = client.post("/standalone/url", json={"url": url})
            assert response1.status_code == 200
            item_id = response1.json()["id"]

            # Bookmark it directly
            client.post(f"/standalone/{item_id}/bookmark")

            # Add again — already bookmarked, should stay bookmarked
            response2 = client.post("/standalone/url", json={"url": url})
            assert response2.status_code == 200
            item2 = response2.json()
            assert item2["already_existed"] is True
            assert item2["is_bookmarked"] is True
        finally:
            state.fetcher = original_fetcher

    def test_new_url_has_already_existed_false(self, client_with_data):
        """A freshly added URL should have already_existed=False."""
        client, data = client_with_data

        url = "https://example.com/brand-new-article"

        mock_fetcher = MagicMock()
        mock_fetcher.fetch = AsyncMock(return_value=make_fetch_result(url))
        original_fetcher = state.fetcher
        state.fetcher = mock_fetcher

        try:
            response = client.post("/standalone/url", json={"url": url})
            assert response.status_code == 200
            item = response.json()
            assert item["already_existed"] is False
            assert item["is_bookmarked"] is False
        finally:
            state.fetcher = original_fetcher
