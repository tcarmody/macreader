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
  - `routes/`: API endpoints (articles, feeds, summarization, standalone, gmail, notifications)
  - `providers/`: LLM implementations (anthropic, openai, google) with abstract base class
  - `database/`: Repository pattern for SQLite operations
  - `tests/`: Pytest test suite
- **web/**: React PWA frontend (Vite + Tailwind + TanStack Query + Zustand)
- **app/**: macOS SwiftUI application (Xcode project in `app/DataPointsAI/`)
- **data/**: SQLite database storage (articles.db with FTS5 search)

## Building & Running

- Backend: `source rss_venv/bin/activate && python -m uvicorn backend.server:app --reload --port 5005`
- Backend tests: `source rss_venv/bin/activate && pytest backend/tests/ -v`
- Web dev server: `cd web && npm run dev` (runs on localhost:3000)
- Swift app: `cd app/DataPointsAI && xcodebuild -scheme DataPointsAI build`

## Architecture Patterns

### Backend
- **Repository pattern**: Database ops in `backend/database/*_repository.py`
- **Service layer**: Business logic in `backend/services/` (article, feed, library)
- **Dependency injection**: FastAPI `Depends()` for db, auth
- **Pydantic schemas**: Request/response validation in `backend/schemas.py`
- **Async throughout**: All I/O operations use async/await
- **Tiered caching**: Memory LRU + disk cache in `backend/cache.py`
- **Site extractors**: Custom content extraction in `backend/site_extractors/` (Bloomberg, GitHub, Medium, Substack, Twitter, Wikipedia, YouTube)
- **Advanced features**: JS rendering and archive fallbacks in `backend/advanced/`

### Web Frontend
- **State separation**: Zustand (UI state) vs TanStack Query (server state)
- **API client**: `web/src/api/client.ts` handles auth headers
- **UI components**: shadcn/ui patterns in `web/src/components/ui/`

### macOS App
- **Observable state**: `AppState` split into extensions (`AppState+*.swift`)
- **MVVM pattern**: Models in `Models/`, views in `Views/`
- **Swift concurrency**: async/await for API calls

## Database

SQLite with FTS5 full-text search. Key tables:
- `feeds`: RSS subscriptions
- `articles`: Content with summaries (also stores library items via `user_id`)
- `user_article_state`: Per-user read/bookmark state
- `users`: Multi-user support with OAuth
- `articles_fts`: Full-text search index (FTS5 virtual table)
- `notification_rules`: Alert rules for keywords/authors
- `notification_history`: Log of sent notifications
- `topic_history`: AI topic clustering results
- `settings`: Application settings
- `gmail_config`: Gmail integration configuration

## LLM Providers

Supports Anthropic (Claude), OpenAI (GPT), and Google (Gemini). Provider implementations follow abstract base in `backend/providers/base.py`. Anthropic is preferred for prompt caching support.

## Key APIs

- `GET/POST /articles`: List, mark read, bookmark
- `GET/POST /feeds`: Subscribe, refresh, OPML import/export
- `POST /summarize/article/{id}`: AI summarization
- `GET/POST /standalone`: Library items (URLs, PDFs, DOCX)
- `GET/POST /notifications/rules`: Alert rule management

## Testing

Tests use pytest with pytest-asyncio. Test files mirror route structure:
- `test_article_routes.py`, `test_feed_routes.py`, `test_auth.py`, etc.
- Fixtures in `conftest.py` provide test database and client

## Environment Variables

Key variables (see `.env.example`):
- `AUTH_API_KEY`: API authentication
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`: LLM providers
- `CORS_ORIGINS`: Allowed origins for web frontend
- `PORT`: Server port (default 5005)
- `ENABLE_JS_RENDER`: Enable JavaScript rendering for dynamic content
- `ENABLE_ARCHIVE`: Enable archive.org fallback for paywalled content
