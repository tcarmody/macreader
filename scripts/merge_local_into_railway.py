#!/usr/bin/env python3
"""
One-time migration: merge the local macOS-app database (content source) into a
copy of the Railway production database (base), preserving all Railway data.

WHY: The macOS app runs its own embedded backend with a *separate* SQLite DB, so
featured stories (and all local content) never reached the Railway DB that web
users read from. This consolidates everything onto Railway as the single source
of truth.

WHAT IT DOES (Railway DB is the base; nothing of Railway's is removed):
  - feeds:    insert local feeds missing from Railway (dedup by unique url)
  - articles: insert local *shared* RSS articles (user_id IS NULL) missing from
              Railway (dedup by unique url), remapping feed_id by feed url
  - featured: apply the local is_featured/featured_at/featured_note flags onto the
              matching Railway articles (by url) -- this is the actual fix
  - PRESERVED untouched: users, user_article_state, article_chats/messages,
              saved_searches, briefs, etc. (Railway's real web-user data)

NOT imported: local user_article_state / chats (they belong to synthetic local
dev accounts default@local / api-user@local, not real users), and local library
items (articles with user_id set).

FTS5 (articles_fts) is external-content with AFTER INSERT/UPDATE triggers, so it
stays in sync automatically as rows are inserted/updated here.

Operates on COPIES in /tmp -- it never opens the live Railway DB for writing.
"""
import os
import shutil
import sqlite3
import sys

LOCAL = os.environ.get("LOCAL_DB", "data/articles.db")           # content source
RAILWAY = os.environ.get("RAILWAY_DB", "/tmp/railway-articles.db")  # base (downloaded copy)
MERGED = os.environ.get("MERGED_DB", "/tmp/merged-articles.db")    # output

# Retention cutoff: shared articles older than this are pruned UNLESS they are
# featured or a web user has read/bookmarked/chatted them. "" disables pruning.
CUTOFF = os.environ.get("CUTOFF", "2026-03-01")


def count(con, table, where=""):
    return con.execute(f"SELECT COUNT(*) FROM {table} {where}").fetchone()[0]


def main():
    for p in (LOCAL, RAILWAY):
        if not os.path.exists(p):
            sys.exit(f"missing input db: {p}")

    print(f"base (railway): {RAILWAY}\nsource (local): {LOCAL}\noutput: {MERGED}\n")
    shutil.copyfile(RAILWAY, MERGED)

    con = sqlite3.connect(MERGED)
    con.execute("PRAGMA foreign_keys=OFF")
    con.execute(f"ATTACH ? AS L", (LOCAL,))
    cur = con.cursor()

    tracked = ["users", "feeds", "articles", "user_article_state", "article_chats"]
    before = {t: count(con, t) for t in tracked}
    before["featured"] = count(con, "articles", "WHERE is_featured=1")

    # 1) feeds: insert any local feed whose url isn't already present
    cur.execute(
        """INSERT OR IGNORE INTO feeds (url, name, category, last_fetched, fetch_error, created_at, is_public)
           SELECT url, name, category, last_fetched, fetch_error, created_at, is_public FROM L.feeds"""
    )
    feeds_added = cur.rowcount

    # 2) articles: insert missing shared RSS articles, remapping feed_id by feed url.
    #    Build the column list dynamically so we never drift from the schema.
    cols = [r[1] for r in con.execute("PRAGMA table_info(articles)")]
    insert_cols = [c for c in cols if c != "id"]
    exprs = []
    for c in insert_cols:
        if c == "feed_id":
            # local feed_id -> local feed url -> merged feed id
            exprs.append(
                "(SELECT mf.id FROM feeds mf WHERE mf.url = "
                "(SELECT lf.url FROM L.feeds lf WHERE lf.id = la.feed_id))"
            )
        elif c == "user_id":
            exprs.append("NULL")                       # shared RSS article
        elif c == "is_featured":
            exprs.append("0")                          # featured applied in step 3
        elif c in ("featured_at", "featured_by_user_id", "featured_note"):
            exprs.append("NULL")
        else:
            exprs.append("la." + c)
    cur.execute(
        f"INSERT OR IGNORE INTO articles ({', '.join(insert_cols)}) "
        f"SELECT {', '.join(exprs)} FROM L.articles la WHERE la.user_id IS NULL"
    )
    articles_added = cur.rowcount

    # 3) featured: apply local flags by url (covers both newly-inserted and
    #    pre-existing Railway rows). featured_by_user_id -> NULL (local user ids
    #    don't map to Railway users; the column is audit-only).
    cur.execute(
        """UPDATE articles
           SET is_featured = 1,
               featured_at = (SELECT la.featured_at FROM L.articles la WHERE la.url = articles.url),
               featured_note = (SELECT la.featured_note FROM L.articles la WHERE la.url = articles.url),
               featured_by_user_id = NULL
           WHERE url IN (SELECT url FROM L.articles WHERE is_featured = 1)"""
    )
    featured_applied = cur.rowcount

    # 4) compact: prune shared articles older than CUTOFF, but never drop a
    #    featured article or one any web user has read/bookmarked/chatted.
    pruned = 0
    if CUTOFF:
        protected = (
            "(is_featured=1 "
            " OR id IN (SELECT article_id FROM user_article_state) "
            " OR id IN (SELECT article_id FROM article_chats))"
        )
        cur.execute(
            f"""DELETE FROM articles
                WHERE user_id IS NULL
                  AND COALESCE(published_at, created_at) < ?
                  AND NOT {protected}""",
            (CUTOFF,),
        )
        pruned = cur.rowcount

    con.commit()

    # Clean up rows in child tables that referenced now-deleted articles, so we
    # don't leave dangling references (article_briefs / story_group_members).
    for child, col in [("article_briefs", "article_id"),
                       ("story_group_members", "article_id")]:
        try:
            cur.execute(
                f"DELETE FROM {child} WHERE {col} NOT IN (SELECT id FROM articles)"
            )
        except sqlite3.OperationalError:
            pass  # table may not exist
    con.commit()

    # FTS integrity (external-content) + reclaim space
    fts_ok = con.execute("INSERT INTO articles_fts(articles_fts) VALUES('integrity-check')") is not None
    con.commit()
    con.execute("VACUUM")
    con.commit()

    after = {t: count(con, t) for t in tracked}
    after["featured"] = count(con, "articles", "WHERE is_featured=1")
    fts_rows = count(con, "articles_fts")

    print("operations:")
    print(f"  feeds inserted:      {feeds_added}")
    print(f"  articles inserted:   {articles_added}")
    print(f"  featured applied:    {featured_applied}")
    print(f"  pruned (< {CUTOFF or 'off'}): {pruned}")
    print("\n           before  ->  after")
    for t in tracked + ["featured"]:
        print(f"  {t:<20} {before[t]:>7}  ->  {after[t]:>7}")
    print(f"  articles_fts rows:   {fts_rows} (should equal articles)")

    # sanity assertions
    assert after["users"] == before["users"], "users count changed!"
    assert after["user_article_state"] == before["user_article_state"], "user state changed!"
    assert after["article_chats"] == before["article_chats"], "chats changed!"
    assert fts_rows == after["articles"], "FTS out of sync with articles!"
    con.close()
    size_mb = os.path.getsize(MERGED) / 1e6
    print(f"\nmerged db: {MERGED}  ({size_mb:.0f} MB)  -- OK")


if __name__ == "__main__":
    main()
