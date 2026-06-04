"""
Tests for search-index resilience (Plan B):
- Database.search falls back to FTS5 when the Tantivy index is empty/not rebuilt
- Tantivy is used once it has documents
- rebuild_search_index / count_articles plumbing

Uses a stub search index so the tests are fast and don't depend on Tantivy's
on-disk index.
"""

import pytest


class StubSearch:
    """Minimal stand-in for SearchIndex with controllable doc count + results."""

    def __init__(self, doc_count: int = 0, results: list[int] | None = None):
        self._count = doc_count
        self._results = results or []
        self.search_called = False
        self.rebuilt_rows: list | None = None

    def count(self) -> int:
        return self._count

    def search(self, query: str, limit: int = 20) -> list[int]:
        self.search_called = True
        return self._results[:limit]

    def rebuild(self, rows) -> int:
        self.rebuilt_rows = list(rows)
        self._count = len(self.rebuilt_rows)
        return self._count


@pytest.fixture
def db_with_articles(test_db):
    feed = test_db.add_feed("https://ex.com/feed.xml", "Example", "Tech")
    a1 = test_db.add_article(
        feed, "https://ex.com/1", "Python testing guide",
        "An article all about python testing and pytest fixtures.",
    )
    a2 = test_db.add_article(
        feed, "https://ex.com/2", "Rust ownership",
        "An article about the rust borrow checker and ownership.",
    )
    return test_db, {"feed": feed, "python": a1, "rust": a2}


def test_falls_back_to_fts5_when_index_empty(db_with_articles):
    db, ids = db_with_articles
    stub = StubSearch(doc_count=0)  # empty / not-yet-rebuilt index
    db.set_search(stub)

    results = db.search("python", limit=10)

    assert not stub.search_called, "empty Tantivy index should be skipped"
    assert ids["python"] in {a.id for a in results}, "FTS5 fallback should find the match"


def test_uses_tantivy_when_populated(db_with_articles):
    db, ids = db_with_articles
    stub = StubSearch(doc_count=5, results=[ids["rust"]])
    db.set_search(stub)

    results = db.search("anything", limit=10)

    assert stub.search_called, "populated Tantivy index should be used"
    assert [a.id for a in results] == [ids["rust"]]


def test_count_articles_and_rebuild(db_with_articles):
    db, ids = db_with_articles
    assert db.count_articles() == 2

    stub = StubSearch(doc_count=0)
    db.set_search(stub)
    assert db.search_index_doc_count() == 0

    n = db.rebuild_search_index()
    assert n == 2
    assert stub.rebuilt_rows is not None and len(stub.rebuilt_rows) == 2
    assert db.search_index_doc_count() == 2


def test_rebuild_noop_without_search(test_db):
    # No Tantivy attached → rebuild reports unavailable (-1), search uses FTS5.
    assert test_db.search_index_doc_count() is None
    assert test_db.rebuild_search_index() == -1
