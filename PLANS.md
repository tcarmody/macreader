# Plans / Follow-ups

Queued remediation work, captured 2026-06-04 after migrating the macOS app's
local database onto the shared Railway backend (Railway is now the single source
of truth — see `scripts/merge_local_into_railway.py`).

Suggested order: **Plan B first** (search is actively broken for everyone), then
**Plan A Phase 1**.

---

## Plan A — "Refresh all" shouldn't block the backend

**Problem (confirmed in `backend/tasks.py:282`):** `refresh_all_feeds` processes
feeds **sequentially** (`for feed in feeds: await refresh_single_feed(...)`), and
within each feed processes articles sequentially, calling `fetcher.fetch` per
short article. HTTP is async (aiohttp), but `feedparser.parse` and content
extraction (`trafilatura`/BeautifulSoup) are **CPU-bound and run on the event
loop**, and SQLite writes are sync. Scheduled as a FastAPI `BackgroundTask`
(`backend/routes/feeds.py:160`) on a **single uvicorn worker**, a 110-feed
refresh monopolizes the loop, so concurrent requests (mark-read, list, status)
time out → Railway 502.

Mitigations already shipped:
- macOS app no longer forces a full refresh on connect (commit `f3709a3`).
- `ENABLE_JS_RENDER=false` on Railway (Playwright/Chromium isn't installed there;
  each render attempt was failing slowly).

**Goal:** a full refresh never makes interactive requests time out.

**Approach (phased):**
1. **Phase 1 — keep the loop responsive (low risk, high impact):**
   - Offload CPU-bound work (`feedparser.parse`, content extraction) to a thread
     via `asyncio.to_thread`, so the event loop yields during parsing.
   - Bound per-feed/article fetch concurrency with an `asyncio.Semaphore`
     (e.g. 6–8) instead of strictly sequential, to cut wall-clock without a
     thundering herd.
   - Keep the existing `state.refresh_in_progress` guard
     (`backend/tasks.py:287,295`).
2. **Phase 2 — get refresh off the request worker (optional, bigger):**
   - Add a **server-side scheduled refresh** (every N minutes) so clients rarely
     trigger full refreshes, and/or move refresh to a separate process/queue.

**Risks / notes:** SQLite writes and the **Tantivy index are single-writer** —
offloading must keep DB/index writes serialized (parse in threads, write back on
one path). Do **not** use uvicorn `--workers >1` as the fix — multiple Tantivy
writers risk corruption and each worker re-rebuilds the index.

**Effort:** Phase 1 ≈ half a day + testing. Verify by hammering mark-read while a
full refresh runs.

---

## Plan B — Rebuild & harden the search index

**Problem (confirmed live):** The Tantivy index is effectively empty —
`/search?q=anthropic` returns 2 results out of ~27k articles. The migration left
`tantivy_index/` empty and it never repopulated.

Root causes in code:
- Startup rebuild (`backend/server.py:61`) only runs `if search.count() == 0`,
  opens the on-disk index with `reuse=True`, and `rebuild()`
  (`backend/search.py:177`) **swallows exceptions and returns 0** (silent
  failure).
- `Database.search` (`backend/database/database.py:349`) returns `[]` when the
  Tantivy index is empty **instead of falling back to FTS5** — so an empty index
  breaks search entirely rather than degrading.
- No admin endpoint exists to force a reindex without a redeploy.

**Goal:** search reflects all articles, survives migrations, and degrades to FTS5
if Tantivy is empty/broken.

**Approach:**
1. **Immediate data fix:** force a one-time full reindex of the ~27k articles
   (via the new endpoint below, or a guarded startup rebuild), then verify
   `/search?q=anthropic` returns hundreds.
2. **Code hardening:**
   - Add admin endpoint **`POST /admin/search/rebuild`** (`require_admin`) to
     trigger a full reindex on demand — no redeploy needed.
   - Startup: rebuild when `count() == 0` **or `count()` is far below the DB
     article count** (detect drift), and **log + don't swallow** rebuild failures.
   - **FTS5 fallback when Tantivy is empty:** in `Database.search`, if Tantivy
     returns zero hits and the index is empty/unhealthy, fall back to FTS5
     (kept in sync during the migration). This alone would have prevented the
     current broken-search state.
   - Document: delete `tantivy_index/` as part of any DB swap (or have rebuild
     handle it).

**Risks / notes:** A 27k-doc rebuild is CPU/IO heavy on the single worker — run
it as a background task, serialize against the single Tantivy writer, and trigger
at a quiet moment.

**Effort:** ~half a day. The admin-rebuild endpoint alone restores search
immediately.
