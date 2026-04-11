# Claude Code Project Instructions

DataPoints is an RSS reader with AI-powered summarization. It has a Python FastAPI backend, a macOS SwiftUI app, and a React web PWA.

## Python Environment

Always activate the virtual environment before running Python commands:

```bash
source rss_venv/bin/activate && <command>
```

Examples:
- Run tests: `source rss_venv/bin/activate && pytest backend/tests/ -v`
- Run server: `source rss_venv/bin/activate && python -m uvicorn backend.server:app --reload --port 5005`
- Install deps: `source rss_venv/bin/activate && pip install -r requirements.txt`

## Project Structure

- **backend/**: Python FastAPI server (port 5005)
  - `routes/`: API endpoints (articles, feeds, summarization, standalone, gmail, notifications, statistics, chat, digest, misc)
  - `providers/`: LLM implementations (anthropic, openai, google) with abstract base class in `base.py`
  - `services/`: Business logic (article_service, feed_service, library_service, related_links, brief_generator, story_groups, auto_digest, chat_service)
  - `database/`: Repository pattern for SQLite operations; `connection.py` owns schema + migrations
  - `site_extractors/`: Custom per-site content extraction (bloomberg, github, medium, substack, twitter, wikipedia, youtube)
  - `advanced/`: Optional JS rendering (Playwright) and archive.org fallback
  - `tests/`: Pytest test suite
- **web/**: React PWA frontend (Vite + Tailwind + TanStack Query + Zustand)
- **app/**: macOS SwiftUI application (Xcode project in `app/DataPointsAI/`)
- **data/**: SQLite database (`articles.db`) and Tantivy full-text search index (`tantivy_index/`)

## Building & Running

- Backend: `source rss_venv/bin/activate && python -m uvicorn backend.server:app --reload --port 5005`
- Backend tests: `source rss_venv/bin/activate && pytest backend/tests/ -v`
- Web dev server: `cd web && npm run dev` (runs on localhost:3000)
- Swift app: `cd app/DataPointsAI && xcodebuild -scheme DataPointsAI -destination 'platform=macOS' build`

## Architecture Patterns

### Backend
- **Repository pattern**: All database ops in `backend/database/*_repository.py`; `Database` class in `database.py` is the unified facade
- **Service layer**: Business logic in `backend/services/`; routes stay thin
- **Dependency injection**: FastAPI `Depends()` for db (`get_db`), auth (`verify_api_key`, `get_current_user`, `require_admin`)
- **Pydantic schemas**: Request/response validation in `backend/schemas.py`
- **Async throughout**: All I/O operations use async/await
- **Tiered caching**: Memory LRU + disk cache in `backend/cache.py`
- **Full-text search**: Tantivy (Rust-based, via `tantivy-py`) as primary; SQLite FTS5 as fallback. Index rebuilt on startup, kept in sync on every article write. See DOCTRINE.md for rationale.
- **Site extractors**: Per-site content extraction in `backend/site_extractors/`; auto-detected from URL
- **Summarizer**: Two-pass critic pipeline in `backend/summarizer.py` (generate → critic for articles >2,000 words and newsletters)
- **Background tasks**: FastAPI `BackgroundTasks` for related-link fetching and summarization; `backend/tasks.py` for task functions

### Web Frontend
- **State separation**: Zustand (UI/persistent state) vs TanStack Query (server state with caching)
- **API client**: `web/src/api/client.ts` — all fetch calls, auth headers, base URL
- **Hooks**: `web/src/hooks/use-queries.ts` — TanStack Query hooks and mutations
- **Store**: `web/src/store/app-store.ts` — Zustand store, persisted to localStorage
- **UI components**: shadcn/ui patterns in `web/src/components/ui/`

### macOS App
- **Observable state**: `AppState` class split into focused extensions in `State/AppState+*.swift`
- **MVVM pattern**: Models in `Models/`, views in `Views/`, state in `State/`, API in `Services/`
- **Swift concurrency**: `@MainActor` isolated `APIClient`; async/await throughout
- **API models**: Codable structs in `Services/APIModels.swift`; article models in `Models/Article.swift`
- **Filter system**: `ArticleFilter` enum (in `Models/Feed.swift`) with associated values for feed, topic, and savedSearch cases; fully Codable

## Database

SQLite at `data/articles.db`. Schema and all migrations live in `backend/database/connection.py`.

Key tables:
- `feeds`: RSS feed subscriptions
- `articles`: Article content + summaries; also stores library items (user_id set for those)
- `user_article_state`: Per-user read/bookmark state (lazy-created on first interaction)
- `users`: User accounts (OAuth or API key)
- `articles_fts`: FTS5 virtual table (fallback search when Tantivy unavailable)
- `notification_rules` / `notification_history`: Smart notification rules and delivery log
- `topic_history`: Persisted AI topic clustering results for trend analysis
- `article_chats` / `chat_messages`: Per-user per-article chat sessions
- `article_briefs`: Newsletter-ready blurbs (length × tone variants)
- `story_groups` / `story_group_members`: Same-event article deduplication
- `digests`: Assembled auto-digest cache
- `saved_searches`: Per-user saved search queries
- `settings`: Application settings (key/value)
- `gmail_config`: Gmail OAuth credentials and label configuration (managed by `GmailRepository`)

## LLM Providers

Supports Anthropic (Claude), OpenAI (GPT), and Google (Gemini). Provider implementations follow abstract base in `backend/providers/base.py`. Anthropic is preferred — it supports prompt caching which reduces cost ~90% on repeated prefix calls.

## Key APIs

Routes and their prefixes:
- `GET/POST /articles` — list, grouped, bulk read, bookmark, summarize, find related
- `GET/POST /feeds` — subscribe, refresh, OPML import/export
- `POST /summarize` — AI summarization (also available as `POST /articles/{id}/summarize`)
- `POST /articles/{id}/related` — trigger Exa neural search for related links
- `GET/POST /standalone` — Library items (URLs, PDFs, DOCX, TXT, MD, HTML)
- `GET/POST /notifications/rules` — smart notification rule management
- `GET /statistics/reading-stats` — reading + summarization stats
- `GET /statistics/topics/current` — topics from most recent clustering run (used by sidebar)
- `POST /statistics/topics/cluster` — trigger AI topic clustering
- `GET/POST /articles/{id}/chat` — per-article chat sessions
- `GET /digest/auto` — auto-assembled daily/weekly digest
- `GET /digest/story-groups` — same-event article groupings
- `POST /briefs/batch` — newsletter-ready blurbs (brief_generator)
- `GET/POST /searches/saved` — per-user saved search queries
- `GET /search` — full-text search (Tantivy primary, FTS5 fallback); supports `include_summaries` param
- `GET/PUT /settings` — application settings

## Testing

Tests use pytest with pytest-asyncio. Test files in `backend/tests/`:
- `test_article_routes.py`, `test_feed_routes.py`, `test_summarization_routes.py`, etc.
- `test_summarizer.py` — two-pass critic pipeline tests with `MockProvider` (no API keys needed)
- `test_related_links.py` — Exa search service unit tests
- `test_auto_digest.py`, `test_brief_generator.py`, `test_story_groups.py` — newsletter pipeline tests
- Fixtures in `conftest.py` provide in-memory test database and test client

### Bug Fix Workflow

When a bug is reported:
1. **Write a reproducing test first** — create a test that fails due to the bug
2. **Fix the bug** — implement the fix
3. **Prove via passing test** — run the test to verify the fix works

## Environment Variables

Key variables (see `.env.example`):
- `AUTH_API_KEY`: Shared API key for macOS app and direct API access
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`: LLM providers
- `ADMIN_EMAILS`: Comma-separated emails that get admin privileges (OAuth users)
- `CORS_ORIGINS`: Allowed origins for web frontend
- `PORT`: Server port (default 5005)
- `DB_PATH`: SQLite database path (default `./data/articles.db`)
- `EXA_API_KEY`: Exa neural search API key (required for Related Links feature)
- `ENABLE_RELATED_LINKS`: Enable/disable Exa search (default true)
- `ENABLE_JS_RENDER`: Enable Playwright JavaScript rendering for dynamic content
- `ENABLE_ARCHIVE`: Enable archive.org fallback for paywalled content

## Related Links (Exa Neural Search)

The Related Links feature uses [Exa](https://exa.ai) neural search to discover semantically related articles.

### Setup

1. Get an Exa API key at https://exa.ai (free tier: $10 credits)
2. Add to `.env`: `EXA_API_KEY=your-key-here`
3. Restart the backend

### How It Works

**Query construction (3-tier):**
1. Title + Key Points (best — uses existing summary)
2. Title + LLM-extracted keywords (Claude Haiku, ~$0.001/article)
3. Title only (fallback)

**Flow:** User clicks "Find Related" → `POST /articles/{id}/related` triggers a background task → Exa returns top 5 results → stored in `articles.related_links` (JSON) → frontend polls until complete (up to 30s)

**Performance:** 0.35–1.2s latency; 24-hour cache on normalized query keys; ~$0.005/article

### Architecture

- `backend/services/related_links.py` — `ExaSearchService`, query construction, deduplication
- `backend/routes/articles.py` — `POST /articles/{id}/related` endpoint
- `backend/tasks.py` — `fetch_related_links_task()` background task
- `backend/config.py` — `EXA_API_KEY`, `ENABLE_RELATED_LINKS`
- `articles.related_links` — JSON column storing results
- `articles.extracted_keywords` — cached LLM keyword extraction
- macOS: `ArticleRelatedLinksSection.swift`, `AppState+Articles.swift` (`loadRelatedLinks()`), `APIClient.swift` (`findRelatedLinks()`)
