# Refactoring TODOs

## Pending

### Add Service Layer for Python Routes
The route files in `backend/routes/` currently contain business logic mixed with HTTP handling. Extract business logic into a service layer.

**Current structure:**
- `backend/routes/articles.py` - Article endpoints with inline logic
- `backend/routes/feeds.py` - Feed endpoints with inline logic
- `backend/routes/gmail.py` - Gmail endpoints with inline logic
- `backend/routes/library.py` - Library endpoints with inline logic
- `backend/routes/settings.py` - Settings endpoints with inline logic

**Proposed structure:**
```
backend/
  services/
    __init__.py
    article_service.py    # Article business logic
    feed_service.py       # Feed management logic
    gmail_service.py      # Gmail integration logic
    library_service.py    # Library/standalone items logic
    summarization_service.py  # AI summarization logic
  routes/
    # Routes become thin HTTP handlers that delegate to services
```

**Benefits:**
- Routes become thin HTTP adapters
- Business logic becomes testable in isolation
- Easier to reuse logic across different endpoints
- Clearer separation of concerns

## Completed

- [x] Refactor database.py - Extract into repository pattern (`backend/database/`)
- [x] Refactor AppState.swift - Split into focused extensions (`State/`)
- [x] Refactor site_extractors.py - Split into separate files (`backend/site_extractors/`)
- [x] Consolidate Gmail module files (`backend/gmail/`)
- [x] Refactor FeedListView.swift - Extract section components (`Views/Sidebar/`)
- [x] Refactor ArticleDetailView.swift - Extract components (`Views/ArticleDetail/`)
- [x] Refactor APIClient.swift - Extract types to APIModels.swift
