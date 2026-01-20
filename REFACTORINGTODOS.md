# Refactoring TODOs

## Pending

(None currently)

## Completed

- [x] Refactor database.py - Extract into repository pattern (`backend/database/`)
- [x] Refactor AppState.swift - Split into focused extensions (`State/`)
- [x] Refactor site_extractors.py - Split into separate files (`backend/site_extractors/`)
- [x] Consolidate Gmail module files (`backend/gmail/`)
- [x] Refactor FeedListView.swift - Extract section components (`Views/Sidebar/`)
- [x] Refactor ArticleDetailView.swift - Extract components (`Views/ArticleDetail/`)
- [x] Refactor APIClient.swift - Extract types to APIModels.swift
- [x] Extract helper functions in backend routes:
  - `resolve_fetch_url()` in articles.py for URL resolution logic
  - `import_single_feed()` in feeds.py for OPML import processing
  - `import_single_newsletter()` in standalone.py for newsletter imports
- [x] Extract frontend polling logic:
  - `useSummarizationPolling` hook in use-polling.ts for reusable polling
  - Refactored `useSummarizeArticle` and `useSummarizeLibraryItem` to use polling hook
  - Added `invalidateArticleRelated()` helper for consistent cache invalidation
- [x] Replace custom keyboard shortcuts with react-hotkeys-hook library (web)
- [x] Add service layer for Python routes (`backend/services/`):
  - `ArticleService` - Article listing, grouping, fetching, state management, summarization
  - `FeedService` - Feed subscription, refresh, OPML import/export
  - `LibraryService` - Library items, file uploads, newsletter imports
  - Dependency injection factories for FastAPI routes
  - Routes can gradually migrate to use services while maintaining backward compatibility
