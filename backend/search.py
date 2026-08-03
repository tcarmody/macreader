"""
Tantivy-based full-text search index for articles.

Replaces SQLite FTS5 with an in-process Rust search engine that handles
special characters (C++, GPT-4, U.S.), supports fuzzy matching, and
provides better relevance ranking with per-field boosting.

Matching is deliberately forgiving, in three layers:
  1. English stemming, so "summarize" finds "summarizing" and "agent" finds
     "agentic".
  2. Prefix matching on the final word, so "anthro" matches while you're still
     typing.
  3. Edit-distance matching against a raw (unstemmed) copy of the title and
     short summary, so typos still return something.

Layers 2 and 3 are boosted below exact matches, so they only ever add results
underneath the ones you'd have got anyway.

Index lives alongside the SQLite database at data/tantivy_index/.
The Database facade owns sync — every article write calls into here.
"""

import logging
import shutil
from pathlib import Path

import tantivy

logger = logging.getLogger(__name__)

# Fields searched by default, in priority order (title matches rank highest via boost)
_SEARCH_FIELDS = ["title", "summary_short", "summary_full", "content"]

# Bumped whenever the schema changes in a way that makes an existing index
# unreadable or stale. On mismatch the index directory is wiped so it can be
# rebuilt; search falls back to FTS5 until that happens.
#   1 — original: default tokenizer on all text fields
#   2 — en_stem tokenizer + raw keywords field for fuzzy matching
_SCHEMA_VERSION = 2
_VERSION_FILE = ".schema_version"

# Terms shorter than this are not worth fuzzy-matching: at edit distance 1,
# "ai" and "cat" match nearly everything (verified against a sample index).
_MIN_FUZZY_TERM_LENGTH = 5
# Longer words tolerate a second edit without the same false-positive blowup.
_FUZZY_DISTANCE_2_LENGTH = 8


class SearchIndex:
    """Full-text search index backed by Tantivy."""

    def __init__(self, index_path: Path):
        self._path = index_path
        self._discard_if_stale()
        self._path.mkdir(parents=True, exist_ok=True)

        sb = tantivy.SchemaBuilder()
        # Stored + indexed integers used for retrieval and targeted deletes
        sb.add_integer_field("id", stored=True, indexed=True)
        sb.add_integer_field("feed_id", stored=True, indexed=True)
        # Text fields indexed but not stored — we fetch content from SQLite.
        # en_stem folds morphological variants together at index and query time.
        sb.add_text_field("title", stored=False, tokenizer_name="en_stem")
        sb.add_text_field("summary_short", stored=False, tokenizer_name="en_stem")
        sb.add_text_field("summary_full", stored=False, tokenizer_name="en_stem")
        sb.add_text_field("content", stored=False, tokenizer_name="en_stem")
        # Unstemmed copy of title + short summary, used only for typo matching.
        # Fuzzy queries compare against raw index terms, so they need whole words
        # to measure edit distance against — "summarizng" is one edit from
        # "summarizing" but four from the stem "summar".
        sb.add_text_field("keywords_raw", stored=False)
        self._schema = sb.build()

        self._index = tantivy.Index(self._schema, path=str(index_path), reuse=True)
        # Automatically expose new commits to searchers
        self._index.config_reader("OnCommit", 4)
        self._write_schema_version()

    def _discard_if_stale(self):
        """
        Drop an index built against an older schema.

        Tantivy stores the schema alongside the segments, so reopening a v1
        directory with the v2 schema would fail or return nothing. Wiping leaves
        an empty index, which callers already treat as "behind" — search falls
        back to FTS5 until POST /admin/search/rebuild repopulates it.
        """
        if not self._path.exists():
            return

        marker = self._path / _VERSION_FILE
        try:
            found = int(marker.read_text().strip())
        except (OSError, ValueError):
            found = 1  # No marker means the original, pre-versioning schema

        if found == _SCHEMA_VERSION:
            return

        logger.warning(
            "Search index schema v%d found, need v%d — discarding index. "
            "Search uses the FTS5 fallback until POST /admin/search/rebuild runs.",
            found, _SCHEMA_VERSION,
        )
        try:
            shutil.rmtree(self._path)
        except OSError:
            logger.exception("Search index: could not remove stale index at %s", self._path)

    def _write_schema_version(self):
        try:
            (self._path / _VERSION_FILE).write_text(f"{_SCHEMA_VERSION}\n")
        except OSError:
            # Non-fatal: worst case we re-wipe and rebuild once on next startup.
            logger.warning("Search index: could not write schema version marker")

    # ─────────────────────────────────────────────────────────────
    # Writes
    # ─────────────────────────────────────────────────────────────

    def add(
        self,
        article_id: int,
        feed_id: int,
        title: str | None,
        content: str | None,
        summary_full: str | None,
        summary_short: str | None,
    ):
        """Add a new document. Call after INSERT into articles."""
        try:
            with self._index.writer() as writer:
                writer.add_document(self._make_doc(
                    article_id, feed_id, title, content, summary_full, summary_short
                ))
        except Exception:
            logger.exception("Search index: failed to add article %d", article_id)

    def update(
        self,
        article_id: int,
        feed_id: int,
        title: str | None,
        content: str | None,
        summary_full: str | None,
        summary_short: str | None,
    ):
        """Replace an existing document. Call after UPDATE on articles."""
        try:
            with self._index.writer() as writer:
                writer.delete_documents("id", article_id)
                writer.add_document(self._make_doc(
                    article_id, feed_id, title, content, summary_full, summary_short
                ))
        except Exception:
            logger.exception("Search index: failed to update article %d", article_id)

    def delete(self, article_id: int):
        """Remove a single document. Call after DELETE on articles."""
        try:
            with self._index.writer() as writer:
                writer.delete_documents("id", article_id)
        except Exception:
            logger.exception("Search index: failed to delete article %d", article_id)

    def delete_many(self, article_ids: list[int]):
        """Remove multiple documents in one commit. Used by archive cleanup."""
        if not article_ids:
            return
        try:
            with self._index.writer() as writer:
                for article_id in article_ids:
                    writer.delete_documents("id", article_id)
        except Exception:
            logger.exception("Search index: failed to delete %d articles", len(article_ids))

    def delete_by_feed(self, feed_id: int):
        """Remove all documents for a feed. Used when a feed is hard-deleted."""
        try:
            with self._index.writer() as writer:
                writer.delete_documents("feed_id", feed_id)
        except Exception:
            logger.exception("Search index: failed to delete feed %d", feed_id)

    # ─────────────────────────────────────────────────────────────
    # Search
    # ─────────────────────────────────────────────────────────────

    def search(self, query: str, limit: int = 20) -> list[int]:
        """
        Search and return article IDs ordered by relevance.

        Layers stemmed exact matching (boosted by field), prefix matching on the
        final word, and edit-distance matching for typos. If the parser rejects
        the raw input, falls back to progressively simpler queries.
        """
        searcher = self._index.searcher()
        if searcher.num_docs == 0:
            return []

        # Boosted boolean query: exact/stemmed matches on title and summaries
        # outrank body content, with prefix and fuzzy clauses underneath.
        try:
            clauses = [
                (tantivy.Occur.Should, tantivy.Query.boost_query(
                    self._index.parse_query(query, ["title"]), 4.0
                )),
                (tantivy.Occur.Should, tantivy.Query.boost_query(
                    self._index.parse_query(query, ["summary_short"]), 2.0
                )),
                (tantivy.Occur.Should, self._index.parse_query(
                    query, ["summary_full", "content"]
                )),
            ]
            clauses.extend(self._prefix_clauses(query))
            clauses.extend(self._fuzzy_clauses(query))

            combined = tantivy.Query.boolean_query(clauses)
            hits = searcher.search(combined, limit).hits
            if hits:
                return [searcher.doc(addr)["id"][0] for _, addr in hits]
        except Exception:
            pass

        # Fallback: simple multi-field parse (handles most edge cases)
        try:
            q = self._index.parse_query(query, _SEARCH_FIELDS)
            hits = searcher.search(q, limit).hits
            if hits:
                return [searcher.doc(addr)["id"][0] for _, addr in hits]
        except Exception:
            pass

        # Last resort: strip to plain words and retry
        words = "".join(c if c.isalnum() or c.isspace() else " " for c in query).split()
        if not words:
            return []
        try:
            q = self._index.parse_query(" ".join(words), _SEARCH_FIELDS)
            hits = searcher.search(q, limit).hits
            return [searcher.doc(addr)["id"][0] for _, addr in hits]
        except Exception:
            logger.warning("Search index: all query strategies failed for %r", query)
            return []

    @staticmethod
    def _terms(query: str) -> list[str]:
        """Lowercased alphanumeric words. Fuzzy/prefix queries match against raw
        index terms, so they get no tokenizer applied for them — including the
        lowercasing the analyzer would normally do."""
        cleaned = "".join(c if c.isalnum() or c.isspace() else " " for c in query)
        return cleaned.lower().split()

    def _prefix_clauses(self, query: str) -> list[tuple]:
        """
        Match the final word as a prefix, so results appear mid-word while
        typing ("anthro" → "anthropic"). Only the last term: earlier words are
        complete, and prefix-matching them adds noise for no benefit.
        """
        terms = self._terms(query)
        if not terms:
            return []

        last = terms[-1]
        clauses = []
        for field, boost in (("title", 3.0), ("summary_short", 1.5)):
            try:
                clauses.append((
                    tantivy.Occur.Should,
                    tantivy.Query.boost_query(
                        tantivy.Query.phrase_prefix_query(self._schema, field, [last]),
                        boost,
                    ),
                ))
            except Exception:
                continue  # Term the field can't build a prefix query for; skip it
        return clauses

    def _fuzzy_clauses(self, query: str) -> list[tuple]:
        """
        Edit-distance match each long-enough term against the unstemmed
        keywords field, so a typo still finds the article. Heavily de-boosted:
        these should only surface when exact matching found little or nothing.
        """
        clauses = []
        for term in self._terms(query):
            if len(term) < _MIN_FUZZY_TERM_LENGTH:
                continue
            distance = 2 if len(term) >= _FUZZY_DISTANCE_2_LENGTH else 1
            try:
                clauses.append((
                    tantivy.Occur.Should,
                    tantivy.Query.boost_query(
                        tantivy.Query.fuzzy_term_query(
                            self._schema, "keywords_raw", term, distance
                        ),
                        0.5,
                    ),
                ))
            except Exception:
                continue
        return clauses

    # ─────────────────────────────────────────────────────────────
    # Maintenance
    # ─────────────────────────────────────────────────────────────

    def count(self) -> int:
        """Number of documents currently in the index."""
        return self._index.searcher().num_docs

    def rebuild(self, rows) -> int:
        """
        Wipe and rebuild from an iterable of sqlite3.Row or similar objects.

        Each row must support dict-style access for:
          id, feed_id, title, content, summary_full, summary_short
        """
        try:
            count = 0
            with self._index.writer() as writer:
                writer.delete_all_documents()
                for row in rows:
                    writer.add_document(self._make_doc(
                        row["id"],
                        row["feed_id"] or 0,
                        row["title"],
                        row["content"],
                        row["summary_full"],
                        row["summary_short"],
                    ))
                    count += 1
            logger.info("Search index: rebuilt with %d documents", count)
            return count
        except Exception:
            logger.exception("Search index: rebuild failed")
            return 0

    # ─────────────────────────────────────────────────────────────
    # Internal
    # ─────────────────────────────────────────────────────────────

    def _make_doc(
        self,
        article_id: int,
        feed_id: int,
        title: str | None,
        content: str | None,
        summary_full: str | None,
        summary_short: str | None,
    ) -> tantivy.Document:
        kwargs: dict = {"id": article_id, "feed_id": feed_id or 0}
        if title:
            kwargs["title"] = [title]
        if summary_short:
            kwargs["summary_short"] = [summary_short]
        if summary_full:
            kwargs["summary_full"] = [summary_full]
        if content:
            kwargs["content"] = [content]

        # Unstemmed copy of the two highest-signal fields, for fuzzy matching.
        raw = " ".join(part for part in (title, summary_short) if part)
        if raw:
            kwargs["keywords_raw"] = [raw]

        return tantivy.Document(**kwargs)
