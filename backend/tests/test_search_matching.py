"""
Tests for forgiving match behavior in the Tantivy index.

These exercise the real SearchIndex against a temp directory (unlike
test_search_index.py, which stubs it) because the behavior under test —
stemming, prefix, and edit-distance matching — lives in Tantivy itself.
"""

import pytest

from backend.search import (
    SearchIndex,
    _SCHEMA_VERSION,
    _VERSION_FILE,
)

DOCS = [
    # id, title, summary_short, content
    (1, "Anthropic releases Claude with agentic coding improvements",
     "A new model aimed at long-horizon work.", "Full body about the release."),
    (2, "How we are summarizing newsletters at scale",
     "Batch summarization pipeline notes.", "Body text about digests."),
    (3, "Regulators weigh copyright rules for generative models",
     "Lawmakers debate training data.", "Body about policy and courts."),
]


@pytest.fixture
def index(tmp_path):
    idx = SearchIndex(tmp_path / "tantivy_index")
    for article_id, title, short, content in DOCS:
        idx.add(article_id, feed_id=1, title=title, content=content,
                summary_full=None, summary_short=short)
    idx._index.reload()
    return idx


class TestStemming:
    """Morphological variants should collapse to the same stem."""

    def test_verb_form_matches(self, index):
        assert 2 in index.search("summarize")

    def test_plural_matches_singular(self, index):
        assert 3 in index.search("regulator")

    def test_adjective_matches_noun(self, index):
        assert 1 in index.search("agent")


class TestPrefixMatching:
    """Partial final word should match while the user is still typing."""

    def test_partial_last_word(self, index):
        assert 1 in index.search("anthro")

    def test_partial_after_complete_word(self, index):
        assert 3 in index.search("copyright gener")

    def test_full_word_still_matches(self, index):
        assert 1 in index.search("anthropic")


class TestTypoTolerance:
    """Edit-distance matching against the unstemmed keywords field."""

    def test_typo_in_title_word(self, index):
        assert 1 in index.search("anthropc")

    def test_typo_needing_two_edits(self, index):
        # "summarizng" is one edit from "summarizing" but far from the stem
        # "summar" — this only works because of the raw keywords field.
        assert 2 in index.search("summarizng")

    def test_exact_match_outranks_fuzzy(self, index):
        # Both docs are reachable; the exact title match must come first.
        results = index.search("copyright")
        assert results and results[0] == 3


class TestFuzzyGuards:
    """Short terms must not be fuzzy-matched — at distance 1 they hit everything."""

    def test_short_terms_produce_no_fuzzy_clauses(self, index):
        assert index._fuzzy_clauses("ai cat the") == []

    def test_long_terms_produce_fuzzy_clauses(self, index):
        assert len(index._fuzzy_clauses("anthropic")) == 1

    def test_terms_are_lowercased(self, index):
        # fuzzy_term_query compares against raw index terms and applies no
        # analyzer, so an uppercase query term would silently never match.
        assert index._terms("Anthropic AI") == ["anthropic", "ai"]

    def test_punctuation_is_stripped(self, index):
        assert index._terms("C++ (GPT-4)") == ["c", "gpt", "4"]


class TestNoMatch:
    def test_unrelated_query_returns_nothing(self, index):
        assert index.search("submarine tectonics") == []


class TestSchemaMigration:
    def test_writes_version_marker(self, tmp_path):
        path = tmp_path / "idx"
        SearchIndex(path)
        assert (path / _VERSION_FILE).read_text().strip() == str(_SCHEMA_VERSION)

    def test_discards_index_with_no_marker(self, tmp_path):
        """A pre-versioning (v1) index must be wiped, not reopened."""
        path = tmp_path / "idx"
        idx = SearchIndex(path)
        idx.add(1, 1, "Anthropic ships", None, None, None)
        idx._index.reload()
        assert idx.count() == 1

        (path / _VERSION_FILE).unlink()  # simulate a v1 directory
        reopened = SearchIndex(path)
        assert reopened.count() == 0, "stale index should have been discarded"

    def test_keeps_index_with_current_marker(self, tmp_path):
        path = tmp_path / "idx"
        idx = SearchIndex(path)
        idx.add(1, 1, "Anthropic ships", None, None, None)
        idx._index.reload()

        reopened = SearchIndex(path)
        reopened._index.reload()
        assert reopened.count() == 1, "current-schema index should be reused"
