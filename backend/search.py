"""
Tantivy-based full-text search index for articles.

Replaces SQLite FTS5 with an in-process Rust search engine that handles
special characters (C++, GPT-4, U.S.), supports fuzzy matching, and
provides better relevance ranking with per-field boosting.

Index lives alongside the SQLite database at data/tantivy_index/.
The Database facade owns sync — every article write calls into here.
"""

import logging
from pathlib import Path

import tantivy

logger = logging.getLogger(__name__)

# Fields searched by default, in priority order (title matches rank highest via boost)
_SEARCH_FIELDS = ["title", "summary_short", "summary_full", "content"]


class SearchIndex:
    """Full-text search index backed by Tantivy."""

    def __init__(self, index_path: Path):
        self._path = index_path
        self._path.mkdir(parents=True, exist_ok=True)

        sb = tantivy.SchemaBuilder()
        # Stored + indexed integers used for retrieval and targeted deletes
        sb.add_integer_field("id", stored=True, indexed=True)
        sb.add_integer_field("feed_id", stored=True, indexed=True)
        # Text fields indexed but not stored — we fetch content from SQLite
        sb.add_text_field("title", stored=False)
        sb.add_text_field("summary_short", stored=False)
        sb.add_text_field("summary_full", stored=False)
        sb.add_text_field("content", stored=False)
        self._schema = sb.build()

        self._index = tantivy.Index(self._schema, path=str(index_path), reuse=True)
        # Automatically expose new commits to searchers
        self._index.config_reader("OnCommit", 4)

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

        Uses boosted title/summary queries for better ranking, then falls back
        to a phrase query if the parser rejects the raw input.
        """
        searcher = self._index.searcher()
        if searcher.num_docs == 0:
            return []

        # Boosted boolean query: title and summaries outrank body content
        try:
            title_q = tantivy.Query.boost_query(
                self._index.parse_query(query, ["title"]), 4.0
            )
            short_q = tantivy.Query.boost_query(
                self._index.parse_query(query, ["summary_short"]), 2.0
            )
            full_q = self._index.parse_query(query, ["summary_full", "content"])
            combined = tantivy.Query.boolean_query([
                (tantivy.Occur.Should, title_q),
                (tantivy.Occur.Should, short_q),
                (tantivy.Occur.Should, full_q),
            ])
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
        return tantivy.Document(**kwargs)
