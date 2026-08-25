# Plans / Follow-ups

Queued remediation work, captured 2026-06-04 after migrating the macOS app's
local database onto the shared Railway backend (Railway is now the single source
of truth — see `scripts/merge_local_into_railway.py`).

Suggested order: **Plan B first** (search is actively broken for everyone), then
**Plan A Phase 1**.

**Status (2026-06-04): Plan B DONE.** Shipped FTS5-fallback-when-empty, an
on-demand `POST /admin/search/rebuild`, and gated startup auto-rebuild behind
`SEARCH_REBUILD_ON_START` (default off). Note: the first attempt's automatic
startup rebuild filled the 500 MB Railway volume with transient Tantivy segments
and wedged SQLite (`disk I/O error`); recovery required growing the volume to
**5 GB**. Index is now complete (30160/30160) and search works. **Plan A is still
open.** Lesson for Plan A: rebuild/refresh work on this single-instance,
volume-backed deployment must respect disk headroom and not run unbounded.

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

---

## Plan C — Fix Digest, then restore it to the reader

**Status (2026-06-04):** Digest was **removed from the casual web reader** because
it fails. Removal commit only touched the frontend reader surface
(`web/src/components/casual/*`, `CasualView` type) — the backend `/digest/*`
endpoints and the admin web `DigestView` are untouched, so nothing else regressed.
The plan is to diagnose, fix, and re-add the **Digest** tab + the Home "Today's
digest" CTA (both easy to restore — see the removal commit).

**What we know:** `GET /digest/auto` (`backend/routes/digest.py:257`) calls
`state.auto_digest_service.generate(...)`. It returns **503** if
`state.auto_digest_service` is unconfigured, but the reported symptom is a hard
failure, so the likely culprits are one of:

- **LLM not configured / failing** on Railway — the digest needs the brief
  generator (`state.brief_generator`) and story grouping; if keys/budget/timeouts
  fail, `generate()` may raise a 500 instead of degrading.
- **A dropped-column / schema-drift query**, like the known latent bug where
  reading-stats queries the dropped `articles.is_read` column
  (noted in `backend/tests/test_feed_visibility.py:180`). Auto-digest / story
  groups may hit the same drift.
- **Cost/latency:** a cold digest scores + briefs many stories via LLM; on the
  single worker it can exceed the client's 5–30s window and read as "fails."

**Approach:**

1. **Reproduce & capture the real error.** Hit `GET /digest/auto?period=today`
   against Railway (and locally) and read the actual traceback/status — don't
   guess. Add a focused test in `backend/tests/` that calls the endpoint with a
   `MockProvider` (mirror `test_auto_digest.py`) to pin the failure.
2. **Fix the root cause** — most likely (a) make `generate()` degrade gracefully
   (clear 503/empty-state instead of 500 when no LLM) and/or (b) repair any
   schema-drift query (audit for `articles.is_read` and other dropped columns).
3. **Make it cheap enough for the reader:** ensure the 2-hour cache is populated
   by a background job (not the user's request), so the reader's first hit is
   instant; show a friendly empty/loading state when the cache is cold.
4. **Re-add to the reader:** restore the `digest` `CasualView`, the nav item in
   `CasualNav.tsx`, the `DigestView` branch in `CasualApp.tsx`, and the Home CTA.

**Effort:** ~half a day once the real error is captured. Step 1 is the gate —
everything else depends on what the traceback says.

---

## Plan D — Make the admin web view responsive

**Added 2026-08-25**, after fixing two bugs that each independently hid Settings
on a phone (collapsed sidebar rail had no footer; `h-screen`/`100vh` pushed the
expanded footer under the mobile browser chrome). Those are shipped, but they
only restored one button — the admin shell itself still doesn't fit a phone.

**Problem:** the admin shell is a fixed-minimum desktop layout rendered inside
`h-dvh flex overflow-hidden` (`web/src/App.tsx:295`). The `react-resizable-panels`
minimums add up well past a phone viewport:

| Panel | File | `minSize` |
| --- | --- | --- |
| sidebar | `App.tsx:311` | 240 |
| main | `App.tsx:315` | 420 |
| article list (inside main) | `App.tsx:268` | 340 |
| article detail (inside main) | `App.tsx:272` | 360 |

So the real floor is **~940px** (sidebar 240 + list 340 + detail 360); the
Library view has the same shape (`App.tsx:284`, `App.tsx:288`). On a ~390px
screen the panes overflow and `overflow-hidden` clips them, and there is no
breakpoint anywhere in the shell — no `md:` variants, no media query, no
mobile branch. Collapsing the sidebar (`Sidebar.tsx:195`) frees 240px but still
leaves a 700px two-pane group in a 390px viewport.

`CasualApp` (`web/src/components/casual/CasualApp.tsx:42`) is the only shell that
adapts: `flex-col` with a mobile top bar and bottom tabs, flipping to
`md:flex-row` with a left rail. Admins are routed away from it (`App.tsx:239-242`)
unless they opt into reader preview.

**Goal:** an admin on a phone gets a usable version of the power UI — feeds,
article list, article detail, search, settings — without needing reader preview.

**Approach (phased):**
1. **Phase 1 — a mobile branch for the shell.** Add a `useIsMobile()` hook
   (`matchMedia('(max-width: 767px)')`, matching the `md:` breakpoint the casual
   shell already uses) and, when it matches, render the panes as a **stack with
   one visible at a time** instead of a `Group`: sidebar → list → detail, with
   back navigation, driven by existing store state (`selectedArticleId` already
   encodes "am I reading something"). This avoids touching the desktop layout at
   all — the `Group`/`Panel` tree stays exactly as it is behind the branch.
2. **Phase 2 — navigation chrome.** The sidebar can't be permanently on screen at
   that width. Either a slide-over drawer triggered from a header button, or
   reuse the casual `BottomNav` pattern for the top-level filters. Prefer the
   drawer: the admin sidebar has far more in it (categories, topics, saved
   searches) than a tab bar can hold.
3. **Phase 3 — audit the other full-width views.** `DigestView`, `StatsView`,
   `ArticleDetail`, and the dialogs (`SettingsDialog`, `FeedManagerDialog`) have
   not been checked at phone width; they may have their own fixed minimums or
   wide tables.

**Risks / notes:** the panel layouts are **persisted to localStorage** via
`useDefaultLayout` (`dp-shell-layout`, `dp-feeds-layout`, `dp-library-layout` —
`App.tsx:107-109`), so a phone session must not write layout state that then
follows the user back to desktop — scope persistence to the desktop branch. Also decide deliberately whether an admin on a phone should just
get `CasualApp`: it already works, and "power UI is desktop-only" is a legitimate
answer that costs zero engineering. Plan D is only worth doing if the answer is
no.

**Effort:** Phase 1 ≈ half a day. Phases 2–3 ≈ a day, mostly design decisions
rather than code. Verify at 390px (iPhone) and 768px (iPad portrait) — the
breakpoint boundary is where stacked/side-by-side flips and is the easiest thing
to get wrong.
