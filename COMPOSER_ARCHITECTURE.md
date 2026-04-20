# Composer — Architectural Plan

A companion application to DataPoints. DataPoints is where news comes in and gets triaged; Composer is where selected material gets thought about, arranged, and turned into writing.

---

## 1. Vision

**DataPoints** is a *river*. New articles flow in, get summarized, get read or dismissed, and eventually flow out. It is time-ordered, ephemeral, optimized for "what is new."

**Composer** is a *workbench*. Things you want to keep thinking about get lifted out of the river and placed here. It is topic-ordered, persistent, optimized for "what am I working on."

The two apps are deliberately separate. DataPoints stays a focused reader; Composer stays a focused writing/research tool. They share a seam, not a codebase.

### What Composer is

- A personal research library of material you've consciously chosen to keep
- A workspace for arranging that material into threads, outlines, and drafts
- A writing environment for producing newsletters, essays, memos, or notes
- A grounded AI assistant that can answer questions against your own corpus

### What Composer is not

- A reader (DataPoints does that)
- A general-purpose note-taking app (Obsidian, Notion, Apple Notes do that)
- A knowledge graph / personal wiki (at least not initially — see §11)
- A publishing platform (it exports; it does not host)

---

## 2. The Two-App Split

### Division of responsibility

| Concern | DataPoints | Composer |
|---|---|---|
| RSS subscription, fetching | ✓ | — |
| Article triage (read / dismiss / bookmark) | ✓ | — |
| AI summarization, key points, briefs | ✓ | — (consumes) |
| Chat-with-article (ephemeral Q&A) | ✓ | — |
| Auto-digest, story grouping | ✓ | — |
| Library (URLs, PDFs, DOCX as one-off captures) | ✓ | — |
| Promoted research items (persistent, curated) | — | ✓ |
| User-authored notes and annotations | — | ✓ |
| Arranging items into threads / outlines | — | ✓ |
| Drafting long-form writing | — | ✓ |
| Newsletter / essay composition and export | — | ✓ |
| Grounded Q&A over your saved corpus | — | ✓ |

### The promotion moment

The critical UX is the transition from river to workbench. In DataPoints, any article (or library item, or newsletter blurb, or chat excerpt) can be **promoted** to Composer via a "Send to Composer" action. Promotion:

1. Snapshots the item's content and derived artifacts (summary, key points, related links, extracted keywords)
2. Sends that snapshot to Composer's ingest API
3. Records in DataPoints that the item was promoted (so the UI can show it, and re-promotion is idempotent)
4. Returns a Composer item ID that DataPoints can deep-link to

After promotion, the two copies diverge: DataPoints may later re-summarize, re-group, or auto-archive the source article; Composer's copy is immutable and belongs to the user's research library.

### Ephemerality vs. persistence

Because promotion is now a first-class action, DataPoints can be more aggressive about ephemerality: auto-archive read articles after 30 days, cap library size, skip long-term indexing of things that were never promoted. Anything that mattered has already been lifted out.

---

## 3. System Architecture

Two independent applications, two independent databases, communicating over HTTP.

```
┌─────────────────────────┐           ┌─────────────────────────┐
│       DataPoints        │           │        Composer         │
│                         │           │                         │
│  ┌──────────────────┐   │           │   ┌──────────────────┐  │
│  │  FastAPI server  │   │           │   │  FastAPI server  │  │
│  │   (port 5005)    │◄──┼───────────┼──►│   (port 5006)    │  │
│  └────────┬─────────┘   │ promotion │   └────────┬─────────┘  │
│           │             │   API     │            │            │
│  ┌────────▼─────────┐   │           │   ┌────────▼─────────┐  │
│  │  SQLite +        │   │           │   │  SQLite +        │  │
│  │  Tantivy index   │   │           │   │  vector index    │  │
│  └──────────────────┘   │           │   └──────────────────┘  │
│                         │           │                         │
│  macOS app / web PWA    │           │  web PWA (desktop-first)│
└─────────────────────────┘           └─────────────────────────┘
```

### Key principles

- **No shared database.** Composer reads/writes only its own DB. This lets each app evolve its schema without coordinated migrations and reinforces the ephemeral/persistent boundary.
- **DataPoints is the sender.** Promotion is a push from DataPoints to Composer, not a pull. Composer does not reach into DataPoints's DB or crawl its API for changes. This keeps the dependency arrow clean: DataPoints knows Composer exists; Composer does not know DataPoints exists.
- **Immutable snapshots.** When DataPoints promotes an item, it sends a full snapshot. Composer stores that snapshot and never re-fetches. If the source URL dies, the content stays. If DataPoints re-summarizes, Composer is unaffected.
- **Composer is self-contained.** You can delete DataPoints tomorrow and Composer still works — you just lose the ability to promote new items.

---

## 4. Data Model

SQLite, same pattern as DataPoints (repository layer, migrations in `connection.py`). Key tables below. All IDs are UUIDs unless noted.

### `items`

A promoted research artifact. Immutable snapshot of something brought in from DataPoints (or, eventually, from other sources).

```
id              TEXT PRIMARY KEY
source          TEXT        -- 'datapoints' | 'manual' | 'web-clip' | ...
source_ref      TEXT        -- opaque ID in the source system (e.g. DataPoints article ID)
url             TEXT
title           TEXT
author          TEXT
published_at    TIMESTAMP
promoted_at     TIMESTAMP
content         TEXT        -- full extracted text at time of promotion
summary         TEXT
key_points      JSON        -- array of strings
keywords        JSON        -- array of strings
related_links   JSON        -- array of {url, title, score} from Exa
metadata        JSON        -- site-extractor specific fields, paywall state, etc.
```

### `notes`

User-authored text. First-class object, not a property of items. A note may reference zero or more items.

```
id              TEXT PRIMARY KEY
title           TEXT
body            TEXT        -- markdown
created_at      TIMESTAMP
updated_at      TIMESTAMP
```

### `item_notes`

Join table: notes can be attached to items (a highlight-like annotation) or stand alone.

```
item_id         TEXT
note_id         TEXT
anchor          JSON        -- optional: character offset, quoted passage, etc.
```

### `collections`

Lightweight folders. A collection groups items and notes around a topic or project. Flat, not nested, at least initially.

```
id              TEXT PRIMARY KEY
name            TEXT
description     TEXT
created_at      TIMESTAMP
```

### `collection_members`

```
collection_id   TEXT
member_type     TEXT        -- 'item' | 'note' | 'draft'
member_id       TEXT
position        INTEGER     -- ordering within the collection
```

### `drafts`

A piece of writing in progress. Newsletters, essays, memos.

```
id              TEXT PRIMARY KEY
kind            TEXT        -- 'newsletter' | 'essay' | 'memo' | 'freeform'
title           TEXT
body            TEXT        -- markdown or structured JSON (see §7)
status          TEXT        -- 'draft' | 'ready' | 'published' | 'archived'
created_at      TIMESTAMP
updated_at      TIMESTAMP
published_at    TIMESTAMP   -- nullable
metadata        JSON        -- target platform, tone, length target, etc.
```

### `draft_sources`

Tracks which items/notes are cited or referenced by a draft. Populated manually (when the user drags an item into a draft) or heuristically (when the AI cites an item).

```
draft_id        TEXT
source_type     TEXT        -- 'item' | 'note'
source_id       TEXT
role            TEXT        -- 'cited' | 'referenced' | 'background'
```

### `embeddings`

Vector embeddings for Ask mode (§7.1). One row per embedded chunk.

```
id              TEXT PRIMARY KEY
source_type     TEXT        -- 'item' | 'note' | 'draft'
source_id       TEXT
chunk_index     INTEGER
chunk_text      TEXT
embedding       BLOB        -- raw float32 vector
model           TEXT        -- e.g. 'voyage-3' — so we can migrate models safely
```

Use `sqlite-vec` or a similar extension for similarity search. Falls back to in-memory cosine if the extension isn't available.

### `chat_sessions` / `chat_messages`

Conversations in Ask mode. Mirrors DataPoints's pattern.

```
chat_sessions:
  id, title, created_at, updated_at, scope  -- 'all' | 'collection:<id>' | 'item:<id>'

chat_messages:
  id, session_id, role, content, citations (JSON), created_at
```

---

## 5. Integration Layer

### 5.1 Promotion API (Composer side)

Composer exposes a small public API that DataPoints calls.

**`POST /ingest/items`**

```json
{
  "source": "datapoints",
  "source_ref": "dp-article-9812",
  "url": "https://example.com/article",
  "title": "…",
  "author": "…",
  "published_at": "2026-04-17T10:00:00Z",
  "content": "…full text…",
  "summary": "…",
  "key_points": ["…", "…"],
  "keywords": ["…"],
  "related_links": [{"url": "…", "title": "…", "score": 0.82}],
  "metadata": {}
}
```

Response:

```json
{
  "id": "cmp-item-abc123",
  "url": "composer://item/cmp-item-abc123",
  "already_existed": false
}
```

Idempotent on `(source, source_ref)` — re-posting returns the existing item without overwriting.

**`POST /ingest/items/batch`** — same, but takes an array. For bulk promotion from a DataPoints digest or saved search.

**Authentication:** shared API key (`COMPOSER_INGEST_KEY`), rotatable. Over HTTPS only.

### 5.2 Promotion UX (DataPoints side)

Minimum viable DataPoints changes:

1. New config: `COMPOSER_URL`, `COMPOSER_INGEST_KEY`, `ENABLE_COMPOSER_INTEGRATION`
2. New service `backend/services/composer_client.py` — thin HTTP client for the ingest API
3. New column `articles.promoted_to_composer` (nullable TEXT, stores Composer item ID)
4. New endpoint `POST /articles/{id}/promote` — calls Composer, stores returned ID
5. UI affordance: "Send to Composer" button on article view, article row, bulk action; badge on already-promoted articles

This is explicitly a **one-way push**. DataPoints never queries Composer for state.

### 5.3 Deep linking

Composer items have a stable URL: `https://composer.local/items/{id}` (or custom scheme `composer://item/{id}` in desktop contexts). DataPoints can link to them from the promoted badge, so "I already sent this somewhere" becomes a one-click jump.

### 5.4 Versioning

The ingest API is versioned in its path (`/v1/ingest/items`). Composer may add new fields over time; DataPoints may not send all of them. Composer treats all extra data as optional.

---

## 6. Three Modes

Composer has three primary surfaces. They share a single data model; the mode is a view, not a silo.

### 6.1 Ask — grounded research assistant

A chat interface with RAG over your items, notes, and drafts.

**Mechanics:**
- When a session opens, the user picks a scope: everything, a collection, or a single item
- Each user message triggers retrieval (vector + keyword hybrid) over scoped embeddings
- Top-K chunks become context; LLM generates an answer with inline citations back to specific items/notes
- Citations are clickable: open the source item in a side panel

**Key design calls:**
- Favor **grounded** answers with citations over free-form synthesis. If retrieval returns nothing relevant, the assistant should say so, not hallucinate.
- The existing DataPoints summaries and key points are *already* compressed representations — cheap retrieval fodder. Embed both the summary and the full content; retrieve against the summary first for speed, fall back to full-content chunks for precision.
- Anthropic (Claude) as the default provider — consistent with DataPoints, and prompt caching gives big wins when the same collection is queried repeatedly.

### 6.2 Arrange — the notebook

A workspace for organizing items and notes into threads, outlines, and connections.

**Primary surface:** a two-pane layout — library on the left, current arrangement on the right. Drag items from the library into the arrangement; drop between items to create a note.

**Arrangement formats (pick one to start):**
- **Outline** (recommended to start): nested bullets, each node is either an item reference, a note, or inline text. Like Workflowy or Roam but smaller.
- **Canvas**: free 2D placement with arrows. More expressive, more UI complexity.
- **Document**: linear prose with item embeds. Essentially a draft with richer references.

Start with outline. It's the most keyboard-driven, the easiest to implement, and degrades gracefully into a draft (§6.3) when an outline is ready to become prose.

**Collections as the container:** an arrangement lives inside a collection. A collection has a library view (all members), an outline view (arranged members), and — when you're ready — a draft view.

### 6.3 Publish — the composer

A writing environment that produces exportable artifacts.

**Editor:** rich text (TipTap or Lexical) with first-class support for:
- Citations — inline references to items; surfaced as footnotes or links on export
- Quote blocks — pull a passage from an item with attribution
- AI assist — "summarize this section," "expand this bullet," "rewrite in a tighter voice" — all grounded in the cited items so generations stay faithful
- Templates — newsletter (intro, N blurbs, signoff), essay, memo

**Export targets (MVP):**
- Markdown file
- HTML (styled, email-ready)
- Copy to clipboard (rich text)

**Export targets (later):**
- Substack API
- Beehiiv / Buttondown
- Direct email via SMTP
- RSS feed of published pieces

**Crucial constraint:** Composer is not a publishing platform. It produces artifacts and hands them off. It does not host, schedule, or track opens.

---

## 7. Data Flow Examples

### 7.1 Promoting an article and querying it

1. User reads an article in DataPoints, clicks "Send to Composer"
2. DataPoints `POST /articles/{id}/promote` → calls Composer `POST /v1/ingest/items` with snapshot
3. Composer inserts into `items`, enqueues embedding job
4. Background worker chunks the content, computes embeddings, inserts into `embeddings`
5. User opens Composer, Ask mode, asks "what have I saved about the Fed's rate decision?"
6. Composer embeds the query, retrieves top-K chunks from `embeddings`, constructs LLM prompt with citations, streams answer
7. User clicks a citation → item detail opens in side panel

### 7.2 Composing a newsletter from a collection

1. User has a collection "Weekly AI roundup" with 12 promoted items from the past week
2. Opens the collection, switches to outline view, drags items into a reading order, writes connecting text between them
3. Clicks "Turn into newsletter" → a draft is created with the outline structure as scaffolding
4. Each item becomes a block: title, link, short blurb (seeded from the item's existing summary), space for user commentary
5. User edits, invokes AI assist to tighten prose
6. Exports to Markdown, pastes into Substack

Note how much of this is free because DataPoints already produced summaries and briefs. Composer is *assembling*, not *generating*.

---

## 8. Tech Stack Recommendation

Prioritize consistency with DataPoints where possible so the mental overhead of maintaining two apps is low.

### Backend

- **Python 3.11+, FastAPI** — same as DataPoints; same patterns (repository layer, service layer, Pydantic schemas, async throughout)
- **SQLite** with `sqlite-vec` for vector search; migrate to Postgres later only if needed
- **Uvicorn** on port 5006
- **Shared venv or separate?** Separate. Two requirements files, two venvs. Shared Python version.
- **LLM providers**: reuse the abstract base pattern from DataPoints (`providers/base.py`). You could literally copy the provider code into Composer, or extract it into a small shared package (`datapoints-llm`) installed by both. Extract if the code starts diverging; copy if it doesn't.
- **Embeddings**: Voyage (`voyage-3`) or OpenAI (`text-embedding-3-small`). Both are fine. Voyage is cheaper; OpenAI is more familiar.

### Frontend

- **React + Vite** — same stack as DataPoints web
- **TanStack Query + Zustand** — same state pattern
- **TipTap** for the editor (well-supported, extensible, good React integration)
- **shadcn/ui** — same component library
- **Tailwind** — same styling

### Desktop?

DataPoints has a native macOS SwiftUI app for reading. Composer is **web-first**:
- Writing apps benefit from cross-platform access (you start a draft on laptop, finish on another machine)
- Rich text editing is much more mature on web
- Cost of maintaining a native companion is not worth it for an app you use at a desk

If desktop parity becomes important, wrap the web app in Tauri later. Don't start native.

### Deployment

- Run both apps locally during development, each on its own port
- For remote access: same machine, reverse proxy (Caddy/Nginx) routing `/datapoints` and `/composer` to respective FastAPI processes
- Each app ships its own web frontend; the user bookmarks two URLs

---

## 9. Key API Surface (Composer)

### Public (consumed by DataPoints)
```
POST   /v1/ingest/items
POST   /v1/ingest/items/batch
GET    /v1/health
```

### Internal (consumed by Composer's own frontend)
```
# Items
GET    /items                    list, filter, search
GET    /items/{id}
DELETE /items/{id}
PATCH  /items/{id}               user edits (notes, tags, archive)

# Notes
GET    /notes
POST   /notes
GET    /notes/{id}
PATCH  /notes/{id}
DELETE /notes/{id}

# Collections
GET    /collections
POST   /collections
GET    /collections/{id}
PATCH  /collections/{id}
POST   /collections/{id}/members
DELETE /collections/{id}/members/{member_id}

# Drafts
GET    /drafts
POST   /drafts
GET    /drafts/{id}
PATCH  /drafts/{id}
POST   /drafts/{id}/export       body: { format: 'markdown' | 'html' }
POST   /drafts/from-collection   create a draft scaffolded from a collection

# Ask
GET    /chat/sessions
POST   /chat/sessions
POST   /chat/sessions/{id}/messages     streaming response

# Search
GET    /search                   hybrid vector+keyword across items and notes
```

---

## 10. Development Phases

Each phase is independently shippable. You should be able to stop at the end of any phase and have a usable app.

### Phase 0 — Skeleton (week 1)
- Repo, FastAPI scaffold, SQLite with initial schema, repository layer
- React + Vite frontend scaffold, shared layout
- Auth (single-user API key, like DataPoints)
- `GET /health` and nothing else
- **Exit criterion:** frontend loads, backend responds

### Phase 1 — Ingest and Library (weeks 2–3)
- Ingest API, items table, idempotency
- DataPoints side: "Send to Composer" button, `promoted_to_composer` column
- Composer frontend: library view, item detail view, basic filtering and full-text search
- **Exit criterion:** promote 20 articles from DataPoints, browse them in Composer

### Phase 2 — Notes and Collections (weeks 4–5)
- Notes CRUD, item-note annotations
- Collections, collection membership
- Outline view inside a collection (drag-to-reorder, inline notes)
- **Exit criterion:** organize a week's worth of items into a coherent outline

### Phase 3 — Ask (weeks 6–7)
- Embedding pipeline (background worker, chunking, storage)
- Hybrid retrieval (vector + FTS5)
- Chat endpoint with streaming, citations
- Chat UI with scope selector and citation panel
- **Exit criterion:** ask a question across your saved corpus and get a useful cited answer

### Phase 4 — Publish (weeks 8–10)
- Drafts table, rich text editor, citation primitive
- "Turn collection into draft" flow
- AI assist (grounded rewrites, expansions, summaries)
- Markdown / HTML export
- **Exit criterion:** write and export one newsletter end-to-end using promoted material

### Phase 5 — Polish and Iteration (ongoing)
- Import from other sources (web clipper browser extension, RSS, Readwise)
- Publication integrations (Substack API first)
- Desktop wrapper if warranted
- Cross-collection insights, duplicate detection, "items you haven't touched in 30 days"

---

## 11. Open Questions

These are decisions worth deferring until you've built enough to have intuition.

1. **Nested collections?** Start flat. Add hierarchy only if users (you) are clearly limited by the flatness.
2. **Graph view?** Defer. The document-first framing says no. If you find yourself wanting backlinks, revisit.
3. **Collaboration?** Not in scope. Single-user, local-first. If someone else wants their own Composer, they run their own instance.
4. **Mobile?** Not in scope. Composer is a desk tool.
5. **Sync across machines?** For now, run it on one machine you reach over the network. If local-first multi-device sync becomes a real need, look at something like Automerge — but don't pre-build it.
6. **Full-text search engine?** Start with SQLite FTS5. Add Tantivy (matching DataPoints) only if it becomes slow.
7. **Scheduled / recurring drafts?** (e.g. weekly newsletter template that auto-populates from the past week's collection) Interesting but not MVP.
8. **Version history for drafts?** Probably yes, eventually — writers want this. Can be done cheaply with append-only `draft_revisions` table. Defer past Phase 4.

---

## 12. Design Principles (to hold the line)

1. **Composer is for things you've chosen.** Never auto-ingest. Every item in Composer was consciously promoted.
2. **Document-first, not knowledge-first.** The artifact you produce is the point. Avoid growing into Obsidian/Roam territory unless there's clear pull.
3. **Grounded over generative.** AI features must cite. A Composer that hallucinates is worse than no Composer.
4. **The corpus is the moat.** The value of Composer scales with the quality of what's in it. Ruthlessly prefer signal over volume.
5. **Two apps, one brain.** The user shouldn't have to think about where a feature lives — the split should feel obvious. When in doubt, consumption-shaped things belong in DataPoints; production-shaped things belong in Composer.
6. **Local, private, yours.** Your notes, drafts, and saved items do not leave your machine except when you explicitly publish or export.

---

## Appendix A — Minimal DataPoints changes

To unblock Phase 1 of Composer, DataPoints needs:

```
# backend/config.py
COMPOSER_URL: str | None
COMPOSER_INGEST_KEY: str | None
ENABLE_COMPOSER_INTEGRATION: bool = False

# Migration: add column
ALTER TABLE articles ADD COLUMN promoted_to_composer TEXT;

# backend/services/composer_client.py
class ComposerClient:
    async def promote_item(self, article) -> str: ...

# backend/routes/articles.py
@router.post("/{article_id}/promote")
async def promote_article(article_id: int, ...) -> PromoteResponse: ...
```

Frontend: "Send to Composer" action on article detail + article row, plus a "Promoted" badge. The macOS app gets the same action via a new `APIClient.promoteArticle(_:)` method.

That's the entire DataPoints footprint. Everything else happens in Composer.
