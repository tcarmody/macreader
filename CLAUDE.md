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
- `POST /articles/{id}/related`: Find related articles using Exa neural search
- `GET/POST /standalone`: Library items (URLs, PDFs, DOCX)
- `GET/POST /notifications/rules`: Alert rule management

## Related Links (Exa Neural Search)

The Related Links feature uses [Exa](https://exa.ai) neural search to discover semantically related articles. Unlike keyword search, Exa's neural embeddings understand conceptual relationships between content.

### Setup

1. **Sign up for Exa API** (https://exa.ai)
   - Free tier: $10 credits (~2,000 searches)
   - Production: $5 per 1,000 searches

2. **Add API key to `.env`:**
   ```bash
   EXA_API_KEY=your-exa-api-key-here
   ENABLE_RELATED_LINKS=true  # Optional, defaults to true
   ```

3. **Install dependencies:**
   ```bash
   source rss_venv/bin/activate && pip install exa-py tenacity
   ```

4. **Restart the backend:**
   ```bash
   source rss_venv/bin/activate && python -m uvicorn backend.server:app --reload --port 5005
   ```

### How It Works

**Query Construction (3-tier strategy):**
1. **Best:** Title + Key Points (from existing summary)
2. **Good:** Title + LLM-extracted keywords (Claude Haiku, <$0.001/article)
3. **Fallback:** Title only

**Execution Flow:**
1. User clicks "Find Related" button in macOS app
2. Backend triggers background task via `POST /articles/{id}/related`
3. ExaSearchService constructs optimal query based on article content
4. Exa API returns top 5 semantically related articles
5. Results stored in `articles.related_links` (JSON column)
6. Frontend polls for completion (up to 30 seconds)
7. Related links displayed in article detail view

**Performance:**
- Latency: 0.35-1.2 seconds (Exa API call)
- Cache: 24 hours (normalized query keys)
- Cost: ~$0.005 per article for Exa + ~$0.001 for keyword extraction

### API Endpoint

**POST /articles/{article_id}/related**

Triggers background task to find related links.

**Request:**
```bash
curl -X POST http://localhost:5005/articles/123/related
```

**Response:**
```json
{
  "success": true,
  "message": "Finding related links..."
}
```

**Article Response (after completion):**
```json
{
  "id": 123,
  "title": "...",
  "related_links": [
    {
      "url": "https://example.com/article",
      "title": "Related Article",
      "snippet": "Brief description...",
      "domain": "example.com",
      "published_date": "2026-01-15",
      "score": 0.92
    }
  ]
}
```

### Configuration

Environment variables in `.env`:

```bash
# Exa API key (required)
EXA_API_KEY=your-api-key-here

# Enable/disable feature (default: true)
ENABLE_RELATED_LINKS=true
```

### Architecture

**Backend Components:**
- `backend/services/related_links.py` - ExaSearchService with query construction
- `backend/routes/articles.py` - POST /articles/{id}/related endpoint
- `backend/tasks.py` - fetch_related_links_task() background task
- `backend/config.py` - EXA_API_KEY and ENABLE_RELATED_LINKS config

**Database:**
- `articles.related_links` - JSON column storing results
- `articles.extracted_keywords` - Cache for LLM keyword extraction

**macOS App:**
- `Article.swift` - RelatedLink model
- `APIClient.swift` - findRelatedLinks() method
- `AppState+Articles.swift` - loadRelatedLinks() with polling
- `ArticleRelatedLinksSection.swift` - UI component
- `ArticleDetailView.swift` - "Find Related" button integration

### Troubleshooting

**"Related links feature not configured" error**

Check:
1. Is `EXA_API_KEY` set in `.env`?
2. Did you restart the backend after adding the key?
3. Check backend logs for initialization message:
   ```
   INFO: Exa search service initialized for related links
   ```

**No related links appearing**

1. Check article has been fetched/summarized
2. Wait 1-2 seconds after clicking "Find Related"
3. Check backend logs for errors:
   ```bash
   tail -f backend/logs/app.log | grep -i exa
   ```

4. Test endpoint directly:
   ```bash
   curl -X POST http://localhost:5005/articles/123/related
   ```

5. Check database for results:
   ```bash
   sqlite3 data/articles.db "SELECT id, title, related_links FROM articles WHERE id = 123;"
   ```

**Invalid API key error**

```
ERROR: Exa API error: Invalid API key
```

Solutions:
- Verify key at https://exa.ai/dashboard
- Check for extra spaces in `.env` file
- Ensure key starts with correct prefix

**Rate limiting (429 error)**

Exa free tier limits:
- 1,000 requests per day
- Consider upgrading or implementing request throttling

**Slow response times**

1. Check cache hit rate (should be >30% after 100 uses)
2. Verify network latency to Exa API
3. Consider reducing `num_results` from 5 to 3

**Related links not relevant**

Quality issues usually indicate:
1. Article has poor/missing content → fetch full article first
2. Article has no summary → generate summary for better query
3. Title is too generic → LLM keyword extraction will help

**Memory/database issues**

If `related_links` JSON is too large:
- Each link ~200 bytes
- 5 links × 1000 articles = ~1MB (negligible)
- If database grows too large, consider adding cleanup task

### Best Practices

1. **Generate summary first** - Key points produce the best queries
2. **Fetch full article** - Better content = better related links
3. **Monitor costs** - Track usage in Exa dashboard
4. **Cache aggressively** - 24-hour TTL for related links
5. **Technical content** - Exa excels at research/technical articles

### Cost Optimization

**Monthly estimates:**
- 100 articles: $0.50 (free tier)
- 500 articles: $2.50 (free tier)
- 1,000 articles: $5.00
- 10,000 articles: $50.00

**Reduce costs:**
- Use cache effectively (24-hour TTL)
- Only fetch for important articles
- Consider title-only queries for simple content
- Disable for low-value feeds

## Testing

Tests use pytest with pytest-asyncio. Test files mirror route structure:
- `test_article_routes.py`, `test_feed_routes.py`, `test_auth.py`, etc.
- Fixtures in `conftest.py` provide test database and client

### Bug Fix Workflow

When a bug is reported:
1. **Write a reproducing test first** - Create a test that fails due to the bug
2. **Fix the bug** - Implement the fix
3. **Prove via passing test** - Run the test to verify the fix works

## Environment Variables

Key variables (see `.env.example`):
- `AUTH_API_KEY`: API authentication
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`: LLM providers
- `CORS_ORIGINS`: Allowed origins for web frontend
- `PORT`: Server port (default 5005)
- `ENABLE_JS_RENDER`: Enable JavaScript rendering for dynamic content
- `ENABLE_ARCHIVE`: Enable archive.org fallback for paywalled content
