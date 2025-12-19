"""
Pytest fixtures for backend tests.
"""

import os
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend.config import state
from backend.database import Database
from backend.cache import create_cache
from backend.feed_parser import FeedParser
from backend.fetcher import Fetcher
from backend.server import app


@pytest.fixture
def temp_db_path():
    """Create a temporary database file path."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        yield Path(f.name)
    # Cleanup
    if os.path.exists(f.name):
        os.unlink(f.name)


@pytest.fixture
def temp_cache_dir():
    """Create a temporary cache directory."""
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def test_db(temp_db_path):
    """Create a test database instance."""
    db = Database(temp_db_path)
    yield db


@pytest.fixture
def client(temp_db_path, temp_cache_dir):
    """Create a test client with isolated database and cache."""
    # Store original state
    original_db = state.db
    original_cache = state.cache
    original_feed_parser = state.feed_parser
    original_fetcher = state.fetcher
    original_summarizer = state.summarizer
    original_clusterer = state.clusterer

    # Set up test state with fresh instances
    test_db = Database(temp_db_path)
    state.db = test_db
    state.cache = create_cache(temp_cache_dir)
    state.feed_parser = FeedParser()
    state.fetcher = Fetcher()
    state.summarizer = None  # Disable for tests (requires API key)
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


@pytest.fixture
def client_with_data(temp_db_path, temp_cache_dir):
    """Test client with some sample data pre-populated."""
    # Store original state
    original_db = state.db
    original_cache = state.cache
    original_feed_parser = state.feed_parser
    original_fetcher = state.fetcher
    original_summarizer = state.summarizer
    original_clusterer = state.clusterer

    # Set up test state with fresh instances
    test_db = Database(temp_db_path)
    state.db = test_db
    state.cache = create_cache(temp_cache_dir)
    state.feed_parser = FeedParser()
    state.fetcher = Fetcher()
    state.summarizer = None
    state.clusterer = None

    # Add test data
    feed_id = test_db.add_feed(
        url="https://example.com/feed.xml",
        name="Test Feed",
        category="Test"
    )

    article1_id = test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/article1",
        title="Test Article 1",
        content="This is the content of test article 1. It has enough text to be meaningful."
    )

    article2_id = test_db.add_article(
        feed_id=feed_id,
        url="https://example.com/article2",
        title="Test Article 2",
        content="This is the content of test article 2. It also has enough text."
    )

    # Mark one as read
    if article1_id:
        test_db.mark_read(article1_id, True)

    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client, {
            "feed_id": feed_id,
            "article_ids": [article1_id, article2_id],
        }

    # Restore original state
    state.db = original_db
    state.cache = original_cache
    state.feed_parser = original_feed_parser
    state.fetcher = original_fetcher
    state.summarizer = original_summarizer
    state.clusterer = original_clusterer
