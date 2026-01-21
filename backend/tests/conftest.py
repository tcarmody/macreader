"""
Pytest fixtures for backend tests.
"""

import os
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Generator

import pytest
from fastapi.testclient import TestClient

from backend.config import state
from backend.database import Database
from backend.cache import create_cache
from backend.feed_parser import FeedParser
from backend.fetcher import Fetcher
from backend.server import app


@dataclass
class StateSnapshot:
    """Snapshot of application state for restoration."""
    db: Database | None
    cache: Any
    feed_parser: FeedParser | None
    fetcher: Fetcher | None
    summarizer: Any
    clusterer: Any
    chat_service: Any


@contextmanager
def isolated_test_state(
    temp_db_path: Path,
    temp_cache_dir: Path
) -> Generator[Database, None, None]:
    """
    Context manager for isolated test state.

    Sets up a fresh database and cache, then restores original state on exit.

    Args:
        temp_db_path: Path for temporary test database
        temp_cache_dir: Path for temporary cache directory

    Yields:
        The test Database instance
    """
    # Capture original state
    snapshot = StateSnapshot(
        db=state.db,
        cache=state.cache,
        feed_parser=state.feed_parser,
        fetcher=state.fetcher,
        summarizer=state.summarizer,
        clusterer=state.clusterer,
        chat_service=state.chat_service,
    )

    try:
        # Set up test state with fresh instances
        test_db = Database(temp_db_path)
        state.db = test_db
        state.cache = create_cache(temp_cache_dir)
        state.feed_parser = FeedParser()
        state.fetcher = Fetcher()
        state.summarizer = None  # Disable for tests (requires API key)
        state.clusterer = None
        state.chat_service = None  # Disable for tests (requires API key)

        yield test_db
    finally:
        # Restore original state
        state.db = snapshot.db
        state.cache = snapshot.cache
        state.feed_parser = snapshot.feed_parser
        state.fetcher = snapshot.fetcher
        state.summarizer = snapshot.summarizer
        state.clusterer = snapshot.clusterer
        state.chat_service = snapshot.chat_service


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
    with isolated_test_state(temp_db_path, temp_cache_dir) as test_db:
        # Create a test user (API key user for dev mode)
        test_db.users.get_or_create_api_user()

        with TestClient(app, raise_server_exceptions=False) as test_client:
            yield test_client


@pytest.fixture
def client_with_data(temp_db_path, temp_cache_dir):
    """Test client with some sample data pre-populated."""
    with isolated_test_state(temp_db_path, temp_cache_dir) as test_db:
        # Create a test user (API key user for dev mode)
        test_user_id = test_db.users.get_or_create_api_user()

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

        # Mark one as read (now requires user_id)
        if article1_id:
            test_db.mark_read(test_user_id, article1_id, True)

        with TestClient(app, raise_server_exceptions=False) as test_client:
            yield test_client, {
                "feed_id": feed_id,
                "article_ids": [article1_id, article2_id],
                "user_id": test_user_id,
            }
