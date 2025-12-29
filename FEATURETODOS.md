# Feature TODO List

This document contains detailed implementation plans for future features in the DataPointsAI RSS reader.

---

## Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Reading Time Estimates | ✅ Done | Auto-calculated, displayed in article list/detail |
| Full-Text Extraction | ✅ Done | Site-specific extractors for Medium, Substack, GitHub, YouTube, Twitter, Wikipedia, Bloomberg |
| Newsletter Email Import | ✅ Done | Gmail IMAP with OAuth2, scheduled polling |
| OPML Export | ✅ Done | Export endpoint with categorization |
| Lazy Loading | ✅ Done | Backend pagination + infinite scroll in Swift UI |
| Smart Notifications | ✅ Done | Backend rules engine, notification history, Swift settings UI |
| Article Sharing | ❌ Not Started | |
| Smart Folders | ❌ Not Started | |
| Saved Searches | ❌ Not Started | |
| Article Tagging | ❌ Not Started | |
| Reading Lists | ❌ Not Started | |
| Background App Refresh | ✅ Done | Timer-based refresh like NetNewsWire |
| Reading Statistics | ✅ Done | Statistics tab in Settings with summarization/reading/topic metrics |
| Feed Analytics | ❌ Not Started | |
| Feed Discovery | ❌ Not Started | |
| iCloud Sync | ❌ Not Started | |
| Third-Party Sync | ❌ Not Started | |
| Podcast/Video Support | ❌ Not Started | |

---

## Advanced Features

### 1. Smart Notifications ✅ DONE

**Goal:** Alert users to important or trending articles based on configurable criteria.

**Implementation Complete:**
- ✅ Backend notification rules engine (`backend/notification_service.py`)
- ✅ Database tables: `notification_rules` and `notification_history`
- ✅ API endpoints for rules CRUD: `/notifications/rules`, `/notifications/history`, `/notifications/pending`
- ✅ Integration with feed refresh to evaluate new articles against rules
- ✅ Keyword matching (title, content, summary)
- ✅ Author-based notifications
- ✅ Feed-specific notification rules
- ✅ Priority levels: high, normal, low
- ✅ Swift `NotificationRulesSettingsView` for managing rules
- ✅ Notification history display in settings
- ✅ Smart notifications sent after feed refresh for matching articles
- ✅ Uses existing `NotificationService.swift` for delivery

**Database Schema:**
```sql
CREATE TABLE notification_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    feed_id INTEGER REFERENCES feeds(id),
    keyword TEXT,
    author TEXT,
    priority TEXT CHECK(priority IN ('high', 'normal', 'low')),
    enabled INTEGER DEFAULT 1,
    created_at TIMESTAMP
);

CREATE TABLE notification_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER REFERENCES articles(id),
    rule_id INTEGER REFERENCES notification_rules(id),
    notified_at TIMESTAMP,
    dismissed INTEGER DEFAULT 0
);
```

**API Endpoints:**
- `GET /notifications/rules` - List all rules
- `POST /notifications/rules` - Create a rule
- `PUT /notifications/rules/{id}` - Update a rule
- `DELETE /notifications/rules/{id}` - Delete a rule
- `GET /notifications/history` - Get notification history
- `POST /notifications/history/{id}/dismiss` - Dismiss notification
- `GET /notifications/pending` - Get pending notifications from last refresh

---

### 2. Reading Time Estimates ✅ DONE

**Goal:** Show estimated reading time for each article.

**Implementation Complete:**
- ✅ `reading_time_minutes` column in `articles` table
- ✅ Auto-calculated during feed parsing (word count / 225 WPM)
- ✅ Exposed in ArticleResponse and ArticleDetailResponse schemas
- ✅ Swift `Article` model has `readingTimeMinutes` with display helper
- ✅ Site extractors calculate reading time for all supported sites

---

### 3. Article Sharing ❌ NOT STARTED

**Goal:** Enable sharing articles via system share sheet and custom integrations.

**Swift App Changes:**
- Implement `NSSharingServicePicker` integration
- Add share button to article toolbar
- Add keyboard shortcut: Cmd+Shift+S
- Create `ShareService.swift` with methods:
  - `shareURL(_ url: URL)` - Share article link
  - `shareContent(_ article: Article)` - Share with title and excerpt
  - `copyToClipboard(_ article: Article)` - Copy link/markdown
- Add context menu option "Share..." to article list

**Share Formats:**
- Plain URL
- Markdown: `[Title](url)`
- Rich text with excerpt
- Reader-formatted content (for apps that accept HTML)

**Integrations to Consider:**
- Native macOS share sheet (Messages, Mail, Notes, etc.)
- Copy as Markdown for note-taking apps
- "Read Later" services (Pocket, Instapaper) via URL schemes

---

### 4. Feed Discovery ❌ NOT STARTED

**Goal:** Help users find new feeds related to their interests.

**Backend Changes:**
- Create `backend/services/feed_discovery.py`:
  ```python
  class FeedDiscoveryService:
      def find_feeds_on_page(url: str) -> list[dict]
      def suggest_related_feeds(feed_urls: list[str]) -> list[dict]
      def get_popular_feeds(category: str) -> list[dict]
  ```
- Add feed detection from any URL:
  - Parse HTML for `<link rel="alternate" type="application/rss+xml">`
  - Check common paths: `/feed`, `/rss`, `/atom.xml`, `/feed.xml`
- Create curated feed directory (JSON file or database table)
- Add endpoints: `GET /feeds/discover?url=`, `GET /feeds/popular`

**Swift App Changes:**
- Create `FeedDiscoveryView.swift`:
  - URL input to discover feeds on any website
  - Categorized popular feeds browser
  - "Similar feeds" suggestions based on subscriptions
- Integrate into Add Feed flow:
  - If user enters non-feed URL, auto-discover feeds
  - Show multiple options if page has several feeds
- Add "Discover" tab or section in sidebar

**Categories for Popular Feeds:**
- Technology, News, Science, Business, Entertainment, Sports, etc.
- Allow community submissions (future feature)

---

## Content Enhancements

### 5. Full-Text Extraction Improvements ✅ DONE

**Goal:** Better extract article content from various website formats.

**Implementation Complete:**
- ✅ Site-specific extractors in `backend/site_extractors.py`:
  - Medium (handles paywalls, reading time, series info)
  - Substack (newsletter metadata, featured images)
  - GitHub (releases, discussions, code blocks)
  - YouTube (video metadata, descriptions)
  - Twitter/X (tweets via meta tags)
  - Wikipedia (categories, content extraction)
  - Bloomberg (article body extraction, paywall detection)
- ✅ Enhanced metadata: reading time, word count, categories, featured images
- ✅ Extractor registry with automatic site detection
- ✅ Fallback chain: site-specific → generic extraction

---

### 6. Podcast/Video Feed Support ❌ NOT STARTED

**Goal:** Support audio and video enclosures in RSS feeds.

**Backend Changes:**
- Add `enclosures` table:
  ```sql
  CREATE TABLE enclosures (
    id INTEGER PRIMARY KEY,
    article_id INTEGER REFERENCES articles(id),
    url TEXT NOT NULL,
    type TEXT,  -- audio/mpeg, video/mp4, etc.
    length INTEGER,  -- bytes
    duration INTEGER  -- seconds, if available
  );
  ```
- Parse `<enclosure>` tags during feed sync
- Extract duration from iTunes namespace if available
- Add `feed_type` column to feeds: 'article', 'podcast', 'video', 'mixed'

**Swift App Changes:**
- Create `MediaPlayerView.swift`:
  - Audio player with playback controls
  - Speed adjustment (0.5x - 2x)
  - Skip forward/back 15/30 seconds
  - Background audio support
- Create `VideoPlayerView.swift` using AVKit
- Add media controls to article view when enclosure present
- Track playback position for resume
- Add "Podcasts" smart folder

**UI Considerations:**
- Show play button in article list for media items
- Mini player at bottom of window during playback
- Keyboard shortcuts: Space (play/pause), Arrow keys (seek)

---

### 7. Newsletter Email Import ✅ DONE

**Goal:** Import newsletters from email into the RSS reader.

**Implementation Complete:**
- ✅ Gmail IMAP integration with OAuth2 authentication
- ✅ `GmailIMAPClient` for IMAP connections
- ✅ Email parsing with `parse_eml_bytes()`
- ✅ Database table `gmail_config` for credentials and settings
- ✅ Endpoints: auth URL, callback, status, labels, config, fetch, disconnect
- ✅ Scheduled polling via `gmail_scheduler.py`
- ✅ Swift `NewsletterWatcherService` for monitoring
- ✅ Swift `GmailSetupWizardView` for OAuth flow
- ✅ Newsletters tab with Gmail integration UI

---

## Organization Features

### 8. Smart Folders ❌ NOT STARTED

**Goal:** Create dynamic folders based on rules/filters.

**Backend Changes:**
- Add `smart_folders` table:
  ```sql
  CREATE TABLE smart_folders (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    icon TEXT,
    rules TEXT NOT NULL,  -- JSON array of rule objects
    sort_order INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  );
  ```
- Rule structure:
  ```json
  {
    "match": "all",  // or "any"
    "conditions": [
      {"field": "feed_id", "op": "in", "value": [1, 2, 3]},
      {"field": "title", "op": "contains", "value": "Swift"},
      {"field": "is_read", "op": "eq", "value": false},
      {"field": "published", "op": "newer_than", "value": "7d"}
    ]
  }
  ```
- Add endpoint: `GET /articles?smart_folder_id=X` that applies rules

**Swift App Changes:**
- Create `SmartFolderEditorView.swift`:
  - Name and icon picker
  - Rule builder UI with add/remove conditions
  - Preview of matching articles
- Display smart folders in sidebar with distinct icon
- Real-time article count updates

**Preset Smart Folders:**
- "Today" - Published in last 24 hours
- "This Week" - Published in last 7 days
- "Long Reads" - Reading time > 10 minutes
- "Unread" - All unread articles

---

### 9. Saved Searches ❌ NOT STARTED

**Goal:** Save and quickly access frequent search queries.

**Backend Changes:**
- Add `saved_searches` table:
  ```sql
  CREATE TABLE saved_searches (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    query TEXT NOT NULL,
    feed_ids TEXT,  -- JSON array, null = all feeds
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_used TEXT
  );
  ```
- Add endpoints: `POST /searches/saved`, `GET /searches/saved`, `DELETE /searches/saved/{id}`

**Swift App Changes:**
- Add "Save Search" button in search results
- Show saved searches in:
  - Quick Open (Cmd+K) results
  - Sidebar section or dropdown
  - Search field suggestions
- Add edit/delete options for saved searches
- Track and display result count per saved search

**Integration with Quick Open:**
- Prefix saved searches in Quick Open results
- Show icon to differentiate from feeds/articles

---

### 10. Article Tagging ❌ NOT STARTED

**Goal:** Allow users to add custom tags to articles for organization.

**Backend Changes:**
- Add tables:
  ```sql
  CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    color TEXT,  -- Hex color for UI
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE article_tags (
    article_id INTEGER REFERENCES articles(id),
    tag_id INTEGER REFERENCES tags(id),
    PRIMARY KEY (article_id, tag_id)
  );
  ```
- Add endpoints:
  - `POST /tags` - Create tag
  - `GET /tags` - List all tags with article counts
  - `POST /articles/{id}/tags` - Add tags to article
  - `DELETE /articles/{id}/tags/{tag_id}` - Remove tag
  - `GET /articles?tag=X` - Filter by tag

**Swift App Changes:**
- Create `TagEditorView.swift`:
  - Tag input with autocomplete
  - Color picker for new tags
  - Quick-add common tags
- Display tags in article list and detail view
- Add tag filter to sidebar
- Keyboard shortcut: Cmd+T to add tag to selected article
- Bulk tagging in multi-select mode

**UI Design:**
- Tags as colored pills/chips
- Tag cloud view option
- Drag-and-drop articles onto tags in sidebar

---

### 11. Reading Lists ❌ NOT STARTED

**Goal:** Create curated collections of articles for later reading.

**Backend Changes:**
- Add tables:
  ```sql
  CREATE TABLE reading_lists (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    is_default INTEGER DEFAULT 0,  -- For "Read Later" list
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE reading_list_items (
    reading_list_id INTEGER REFERENCES reading_lists(id),
    article_id INTEGER REFERENCES articles(id),
    position INTEGER,  -- For manual ordering
    added_at TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (reading_list_id, article_id)
  );
  ```
- Add endpoints for CRUD operations
- Support reordering items within list

**Swift App Changes:**
- Create `ReadingListView.swift`:
  - List management (create, rename, delete)
  - Drag-and-drop reordering
  - Progress indicator (X of Y read)
- Add "Add to Reading List" in article context menu
- Show reading lists in sidebar
- Keyboard shortcut: Cmd+L to add to default list

**Default Lists:**
- "Read Later" - Quick save for later
- Allow users to create custom lists: "Research", "Share with team", etc.

---

## Sync & Export

### 12. iCloud Sync ❌ NOT STARTED

**Goal:** Sync reading state, bookmarks, and settings across devices.

**Implementation Strategy:**
- Use CloudKit for sync infrastructure
- Sync entities: read state, bookmarks, feed list, settings, tags

**Swift App Changes:**
- Create `CloudKitSyncService.swift`:
  - Define CloudKit record types
  - Handle conflict resolution (last-write-wins or merge)
  - Background sync on changes
- Add CloudKit container to app entitlements
- Store sync metadata:
  ```swift
  struct SyncState: Codable {
      var lastSyncDate: Date?
      var pendingChanges: [SyncChange]
      var deviceId: String
  }
  ```
- Add sync status indicator in UI
- Handle offline changes queue

**Sync Frequency:**
- Immediate push for user actions (mark read, bookmark)
- Periodic pull every 5-15 minutes
- Manual sync option in settings

**Considerations:**
- Handle first-time sync (merge vs. replace)
- Privacy: All data stays in user's iCloud
- Conflict UI for edge cases

---

### 13. Third-Party Sync Services ❌ NOT STARTED

**Goal:** Integrate with popular RSS sync services.

**Supported Services:**
1. **Feedbin** - Full API, popular among Mac users
2. **Feedly** - Large user base, good API
3. **Inoreader** - Feature-rich, good API
4. **FreshRSS** - Self-hosted option

**Backend Changes:**
- Create `backend/services/sync/` directory:
  - `base_sync.py` - Abstract sync interface
  - `feedbin_sync.py` - Feedbin implementation
  - `feedly_sync.py` - Feedly implementation
- Store credentials securely (Keychain on client, or encrypted in DB)

**Swift App Changes:**
- Create `SyncServiceView.swift` in Settings:
  - Service selector
  - OAuth flow for services that support it
  - API key input for others
  - Test connection button
- Create `SyncManager.swift`:
  - Abstract protocol for sync operations
  - Service-specific implementations
  - Bidirectional sync with conflict resolution

**API Operations Needed:**
- Fetch subscriptions list
- Sync read/unread state
- Sync starred/bookmarked items
- Add/remove subscriptions

---

### 14. Export Options ⚠️ PARTIAL

**Goal:** Allow users to export their data in various formats.

**Current Status:**
- ✅ OPML export endpoint at `/feeds/export-opml`
- ✅ Full OPML generation with categorization
- ❌ JSON/CSV/HTML article exports not implemented

**Remaining Backend Changes:**
- Add export endpoints:
  - `GET /export/articles?format=json|csv|html`
  - `GET /export/bookmarks?format=json|html`
- Generate files on-demand or queue for large exports

**Export Formats:**

**JSON (Articles):**
```json
{
  "exported_at": "2024-01-15T10:30:00Z",
  "articles": [
    {"title": "...", "url": "...", "content": "...", "published": "..."}
  ]
}
```

**HTML (Reading List):**
- Formatted HTML document with articles
- Suitable for printing or offline reading

**Swift App Changes:**
- Add Export section in Settings
- File save dialogs for each export type
- Option to export selected articles only
- Schedule automatic backups (weekly OPML export)

---

## Analytics

### 15. Reading Statistics ✅ DONE

See [Section 19](#19-reading-statistics--done) for full implementation details.

---

### 16. Feed Analytics ❌ NOT STARTED

**Goal:** Provide insights about feed quality and engagement.

**Backend Changes:**
- Track per-feed metrics:
  - Articles published per day/week
  - User read rate (% of articles read)
  - Average article length
  - Fetch success/failure rate
- Add endpoint: `GET /feeds/{id}/analytics`

**Swift App Changes:**
- Create `FeedAnalyticsView.swift` accessible from feed context menu:
  - Publishing frequency graph
  - Your engagement rate
  - Content length distribution
  - Last successful fetch time
- Add "health" indicator to feed list:
  - Green: Active, high engagement
  - Yellow: Active, low engagement
  - Red: Inactive or fetch errors
- Suggest feed cleanup based on analytics

**Actionable Insights:**
- "You haven't read anything from X in 30 days. Unsubscribe?"
- "Y publishes 50+ articles/day. Consider a filter?"
- "Z hasn't published in 60 days. Check if it's still active?"

---

## Performance

### 17. Background App Refresh ✅ DONE

**Goal:** Keep feeds updated even when app is in background.

**Implementation Complete:**
- ✅ `BackgroundRefreshService.swift` - Timer-based refresh service inspired by NetNewsWire
- ✅ `RefreshInterval` enum with options: Manually, 10min, 30min, 1hr, 2hr, 4hr, 8hr
- ✅ Integrated into General Settings tab with interval picker
- ✅ Persists interval and last refresh time in UserDefaults
- ✅ Handles system wake from sleep (fires old timers)
- ✅ Handles app becoming active (fires old timers)
- ✅ Dock badge updates automatically after background refresh
- ✅ Smart notifications evaluated for new articles during background refresh

**Key Components:**
- `BackgroundRefreshService.shared` - Singleton service
- `configure(with: AppState)` - Called during server startup
- `setRefreshInterval(_:)` - Update refresh frequency
- `timedRefresh()` - Trigger immediate refresh
- `fireOldTimer()` - Handle missed refresh windows

**Settings UI:**
- Background Refresh section in General tab
- Interval picker with all options
- Shows "Last refresh: X ago" when enabled
- Descriptive footer text explaining the feature

---

### 18. Lazy Loading for Large Feeds ✅ DONE

**Goal:** Improve performance when viewing feeds with many articles.

**Implementation Complete:**
- ✅ Pagination with limit/offset in backend (`articlesPageSize = 50`)
- ✅ Database indexes on commonly queried columns
- ✅ FTS5 full-text search with proper indexing
- ✅ Infinite scroll in Swift UI (`ArticleListView.swift`)
- ✅ `loadMoreArticles()` in AppState+Articles.swift
- ✅ `hasMoreArticles` state tracking
- ✅ Loading indicator at list bottom
- ✅ Automatic loading when scrolling near bottom

**Key Components:**
- `AppState.articlesPageSize` - Page size constant (50)
- `AppState.hasMoreArticles` - Tracks if more pages exist
- `AppState.isLoadingMore` - Loading state for UI
- `loadMoreArticles()` - Fetches next page and appends

**Future Enhancements (Optional):**
- "Jump to date" for quick navigation in large feeds
- Search result caching

---

### 19. Reading Statistics ✅ DONE

**Goal:** Track and display reading statistics including summarization metrics and topic trends.

**Implementation Complete:**
- ✅ New `topic_history` database table for persisting topic clustering results
- ✅ `StatisticsRepository` for reading stats, summarization stats, and topic history
- ✅ API endpoints: `GET /statistics/reading-stats`, `POST /statistics/topics/cluster`, `GET /statistics/topics/trends`
- ✅ Support for both rolling windows (7d/30d/90d) and calendar periods (week/month/year)
- ✅ Swift `StatisticsSettingsView` - new Statistics tab in Settings
- ✅ Summarization stats: total articles, summarized count, rate, model usage breakdown
- ✅ Reading stats: articles read, reading time, bookmarks, top feeds
- ✅ Topic stats: current topics, most common topics (historical trends)
- ✅ On-demand topic clustering with AI-powered semantic grouping

**Key Components:**
- `backend/database/statistics_repository.py` - Database queries for statistics
- `backend/routes/statistics.py` - API endpoints
- `backend/database/models.py` - `DBTopicHistory` model
- `app/.../Views/SettingsView.swift` - `StatisticsSettingsView` UI

**Statistics Tracked:**
- **Summarization**: Articles summarized vs total, summarization rate, model usage, avg per day/week
- **Reading**: Articles read, total/average reading time, bookmarks added, reading by feed
- **Topics**: Current topic distribution, historical topic trends, topic clustering persistence

---

## Implementation Priority Recommendation

### Phase 1 - Core Improvements (High Value, Medium Effort)
1. ~~Reading Time Estimates~~ ✅
2. Article Sharing
3. Smart Folders
4. Saved Searches

### Phase 2 - Organization (Medium Value, Medium Effort)
5. Article Tagging
6. Reading Lists
7. ~~Full-Text Extraction Improvements~~ ✅

### Phase 3 - Performance & Analytics (High Value, Higher Effort)
8. ~~Lazy Loading for Large Feeds~~ ✅
9. ~~Background App Refresh~~ ✅
10. ~~Reading Statistics~~ ✅
11. Feed Analytics

### Phase 4 - Advanced Features (Variable Value, Higher Effort)
12. ~~Smart Notifications~~ ✅
13. Export Options (partial)
14. Feed Discovery

### Phase 5 - Sync & Media (High Effort)
15. iCloud Sync
16. Third-Party Sync Services
17. Podcast/Video Feed Support
18. ~~Newsletter Email Import~~ ✅

---

*Document created: December 2024*
*Last updated: December 29, 2024*
