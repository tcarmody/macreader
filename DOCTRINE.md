# DataPoints Doctrine

This document records key architectural and design decisions made during the development of DataPoints, explaining the reasoning behind each choice.

---

## Table of Contents

1. [Core Philosophy](#core-philosophy)
2. [UI/UX Design Principles](#uiux-design-principles)
3. [Architecture Decisions](#architecture-decisions)
4. [Technology Choices](#technology-choices)
5. [Feature Decisions](#feature-decisions)
6. [Lessons Learned](#lessons-learned)

---

## Core Philosophy

### Summaries Are the Product

The primary value proposition of DataPoints is AI-generated summaries. Unlike traditional RSS readers where you must click into each article, summaries should be visible by default in the article list. The summary preview in the list view lets users triage content quickly without opening every article.

### Native-First, Web-Second

The macOS app uses native SwiftUI, not a web wrapper. Native apps provide better keyboard shortcuts, system integration (Spotlight, notifications, dock badges), and feel more at home on the Mac. The web PWA was added later for cross-platform access, not as the primary experience.

### Progressive Disclosure

Simple surface, power features on demand. New users see a clean three-pane layout. Power features (topic clustering, JavaScript rendering, archive fallbacks) are available but not required.

### Minimal Viable Complexity

Every feature must justify its existence. The redesign reduced backend code from ~15,000 lines to ~2,500 lines while preserving all functionality. Simpler code is easier to maintain, debug, and extend.

---

## UI/UX Design Principles

### State-First UI: Show Results, Not Actions

**Principle**: The UI should reflect what exists, not what the user can do. Buttons and actions should recede; content and state should lead.

**Application**: In the article list, compact colored dots (purple for AI summary, blue for related links, faded blue for chat) replaced named icons and badge counts. The dots are data — they tell you what has been done to an article. The actions that produced them live in the detail view where they belong. An article row's job is triage, not feature advertising.

**Why it matters**: Showing action buttons in every row creates visual noise proportional to the number of features, not proportional to their relevance to the user at that moment. An article with no summary shouldn't advertise "Summarize" — the user is trying to decide whether to open the article at all.

### One Canonical Path for Each Job

**Principle**: When two UI elements do the same thing, remove one. Don't keep the redundant one "for discoverability."

**Application**:
- "Hide Read" toggle was removed because the "Unread" smart feed already filters to unread articles. Two ways to do the same thing produce inconsistent state and confuse users about which one is authoritative.
- The AI dropdown was removed after smart tabs absorbed both its jobs (trigger + navigate). The dropdown's existence alongside the tab strip implied they were different things, when they weren't.
- The macOS selection toolbar had two envelope buttons (mark read, mark unread). These were collapsed into a single smart toggle that reads the current state and flips it, labeled accordingly.

### Visual Hierarchy as an Alternative to Overflow Menus

**Principle**: Before collapsing secondary actions into a dropdown, try demoting them in-place: smaller size, muted color, secondary position. Reserve dropdowns for genuinely variable/contextual sets of actions.

**Application**: Fetch, Share, and External Link in the article detail toolbar were demoted to `h-7 w-7` icon-only buttons with muted foreground color, rather than hidden behind a `...` menu. They're still one click away for power users; they just no longer compete visually with primary actions.

**Why it matters**: Overflow menus trade discoverability for visual cleanliness, but they also hide actions permanently behind an interaction step. Visual demotion achieves cleanliness without hiding. A muted icon is scannable; a `...` menu requires opening to know what's inside.

### Progressive Disclosure in the Sidebar

**Principle**: Power-user sections (Topics, Pinned Searches) should be collapsed by default. Their presence is signaled by a badge showing the count of items, so users know there's something there without it taking up space until they ask for it.

**Application**: Topics and Pinned Searches sections in the sidebar default to collapsed with count badges. New users see a clean sidebar; returning users who use these features will expand the sections once and the preference persists.

### Terminology Disambiguation: Save vs. Pin

**Principle**: When two distinct features share the same verb or icon, one of them must be renamed. "Save" is too generic — it means bookmark, save-to-read-later, save-search, and more.

**Application**: The bookmark action on articles stays as "Save" (bookmark icon). The action of keeping a search query for reuse was renamed "Pin" with a pin icon throughout both platforms — the button, the section header, the empty states, the tooltip text, and all menu items.

**Why it matters**: "Saved Searches" and "Saved Articles" created genuine user confusion — were pinned searches like bookmarks? Could you "save" a search the way you save an article? "Pinned Searches" signals a different kind of persistence (I want to keep this query available) without conflating it with reading-list bookmarks.

### macOS Toolbar Separation: Inline vs. Window Toolbar

**Principle**: On macOS, the window toolbar and an inline detail-view toolbar are both visible when an article is open. Avoid duplicating actions between them.

**Application**:
- **Inline article toolbar** (inside the detail pane, above the tab strip): owns all article-level actions — Read toggle, Bookmark, the smart tab strip, and secondary utility buttons (Fetch, Share, External Link). This toolbar is only visible when an article is selected.
- **Window toolbar** (macOS title bar area): owns global utility actions that make sense regardless of what's selected — Reader Mode and Fetch Content. Read toggle and Bookmark were removed from the window toolbar because they already live in the inline toolbar.

**Why it matters**: macOS merges toolbar items from all views into one bar. Before this separation, opening an article while articles were selected produced three envelope icons simultaneously: mark-read and mark-unread from the selection toolbar, plus the read-toggle from the window toolbar. Users couldn't know which icon did what. Assigning each toolbar a clear scope of responsibility prevents this collision.

---

## Architecture Decisions

### Client-Server Split

**Decision**: Native Swift app + Python FastAPI backend, communicating via JSON API.

**Alternatives Considered**:
- Pure Swift (no Python): Would lose access to Python's rich ecosystem for feed parsing, content extraction, and LLM integrations
- Electron app: Would sacrifice native feel and system integration
- Python with embedded web UI: Would sacrifice native feel

**Rationale**: This split plays to each language's strengths. Swift/SwiftUI excels at native Mac UI. Python has the best libraries for RSS parsing (feedparser), content extraction (BeautifulSoup, trafilatura), and LLM APIs (anthropic, openai, google-generativeai).

### SQLite for Persistence

**Decision**: SQLite stored locally, with Tantivy for full-text search.

**Alternatives Considered**:
- PostgreSQL: Overkill for single-user app
- Core Data: Would complicate the client-server split
- Cloud database: Adds latency, cost, and complexity for personal tool

**Rationale**: SQLite is fast, requires no setup, and the article corpus is inherently local data. Full-text search is handled by Tantivy rather than SQLite's built-in FTS5 (see Search decision below).

### Search: Tantivy over SQLite FTS5

**Decision**: Replace SQLite FTS5 full-text search with Tantivy, a Rust-based search engine running in-process via `tantivy-py`.

**Alternatives Considered**:
- **Keep FTS5 with sanitization**: A 15-line query sanitization patch fixes the immediate crash bugs. Chosen as the quick fix if search were less central, but leaves fundamental limitations in place.
- **FTS5 trigram tokenizer**: SQLite 3.38+ supports substring matching. Would fix special-character queries without a new dependency, but produces a 3–5x larger index and still lacks relevance ranking control or fuzzy matching.
- **Meilisearch**: High search quality, but requires a separate running process to manage and a sync mechanism between SQLite and the Meilisearch index.
- **Whoosh / Tantivy (in-process)**: Both are in-process Python search libraries. Tantivy uses Rust (via PyO3) and is significantly faster and more capable than Whoosh.

**Why FTS5 was unreliable**: FTS5 interprets characters like `+`, `-`, `.` as query operators. Queries such as `GPT-4`, `C++`, and `U.S.` crash with syntax errors; `AND`, `OR`, and `NOT` are reserved words. There was no error handling in the search path, so any such query returned silently empty results or a 500 error. Special characters are extremely common in tech news content.

**Why Tantivy**: Tantivy's query parser handles `GPT-4`, `C++`, and `U.S.` natively because it uses the same unicode tokenizer at query time as at index time—punctuation is treated as a separator, not a control character. Additional capabilities over FTS5 include per-field relevance boosting (title matches outrank body text), fuzzy term matching, phrase slop, and regex queries—none of which are available in FTS5 without custom extensions.

**Sync Strategy**: The `Database` facade owns sync. Every article write path (`add_article`, `update_article_content`, `update_summary`, `delete_feed`, `archive_old_articles`, `add_standalone_item`, `delete_standalone_item`) calls into the `SearchIndex` directly. This is explicit rather than trigger-based, which makes sync failures visible and debuggable. Tantivy failures are caught and logged without crashing the app; FTS5 remains as a fallback if the search index is unavailable.

**Feed Deletion Edge Case**: When a feed is deleted, SQLite's `ON DELETE CASCADE` removes articles, but some articles may be moved to the Archive feed first (protected because they're bookmarked or summarized). To avoid removing those from Tantivy, the facade records article IDs before deletion, then diffs against what still exists in SQLite afterward, and only removes the truly-deleted ones. Moved articles stay in the index under their new feed.

**Index Storage**: The Tantivy index lives at `data/tantivy_index/` alongside the SQLite database. On first startup the index is rebuilt from all articles in SQLite; thereafter it is kept current by the write-path hooks. There is no background sync process.

**Schema**: Integer fields `id` and `feed_id` are stored and indexed (for targeted deletes). Text fields `title`, `summary_short`, `summary_full`, and `content` are indexed but not stored—content is fetched from SQLite by article ID after search, so there is no duplication of article text.

**Rationale**: The in-process design means no extra service to run or monitor. The explicit sync pattern matches how every other write operation in the codebase works. The search quality improvement (correct special-character handling, better relevance ranking) directly addresses the reliability failures that prompted the change.

**Decision**: Two-tier cache with in-memory LRU and persistent disk cache.

**Rationale**: Memory cache provides sub-millisecond access for frequently accessed items. Disk cache survives restarts and stores the full summary corpus. Summaries are expensive to generate (~$0.001/article), so aggressive caching is worthwhile.

### Background Processing

**Decision**: Feed refresh and summarization run as background tasks, not blocking the UI.

**Rationale**: Fetching 20+ feeds takes 10-30 seconds. Summarizing an article takes 2-5 seconds. Users shouldn't wait. The UI shows stale data immediately and updates progressively as new data arrives.

### Multi-User Data Model

**Decision**: Per-user read/bookmark state via a separate `user_article_state` table, with feeds shared across all users.

**Alternatives Considered**:
- Per-user article copies: Would duplicate content and increase storage
- Single-user only: Limits sharing the deployment with family/team
- Full per-user isolation: Overkill for RSS reader, feeds are public content

**Rationale**: Articles are public content that doesn't need per-user copies. Only the user's interaction state (read, bookmarked) is personal. The `user_article_state` table uses lazy creation—rows are only created when a user interacts with an article. This keeps storage minimal while enabling true multi-user support.

**User Resolution**: Users are identified via OAuth session or API key. API key authentication maps to a shared "API User" for backward compatibility. OAuth users get individual records with their email as the unique identifier.

**Library Items**: Library items (saved URLs, uploaded documents) are per-user via a `user_id` column, as these represent personal collections rather than shared content.

### Role-Based Access Control

**Decision**: Two-tier user system (admin/regular) with config-based email allowlist and a `require_admin` FastAPI dependency.

**Alternatives Considered**:
- Database-stored roles: Adds migration complexity, requires admin UI to manage roles
- Per-route permission checks: Scatters authorization logic across route handlers
- Full RBAC framework (e.g., Casbin): Over-engineered for two tiers

**Rationale**: DataPoints has a small, known set of administrators. A config-based email allowlist (`ADMIN_EMAILS` environment variable) is simpler than database-stored roles and can be changed without code deploys. The `require_admin` dependency chains on `get_current_user`, so it reuses existing authentication logic and adds authorization as a single `Depends()` annotation on protected routes.

**Admin Privileges**:
- Add, edit, delete feeds
- Import OPML
- Bulk delete feeds
- Modify application settings
- Create, edit, delete notification rules

**Regular User Access**:
- Read articles, mark read/unread, bookmark
- Refresh feeds
- Export OPML
- View notification rules and history
- Use library features

**API Key Backwards Compatibility**: API key users (e.g., the macOS app) always receive admin access. This preserves existing behavior for trusted clients that authenticate with the shared API key rather than OAuth.

**Frontend Enforcement**: The `is_admin` flag is exposed via the `/auth/status` endpoint. The web frontend uses this to hide admin-only UI elements (add/delete feed buttons, import, settings mutations) rather than showing them disabled. This reduces confusion for regular users who don't need to see controls they can't use.

### Database Performance Optimizations

**Decision**: Enable SQLite WAL mode with aggressive PRAGMA optimizations for better concurrency.

**Settings Applied**:
- `journal_mode=WAL`: Allows concurrent reads during writes
- `synchronous=NORMAL`: Faster writes while maintaining safety with WAL
- `cache_size=-64000`: 64MB in-memory cache
- `temp_store=MEMORY`: Temp tables in RAM
- `mmap_size=268435456`: 256MB memory-mapped I/O

**Rationale**: These settings optimize for read-heavy workloads typical of RSS readers. WAL mode is the key change—it removes the reader/writer blocking that occurs in rollback journal mode. The other settings reduce I/O and improve query performance.

### Batch Query Patterns

**Decision**: Use `executemany()` and `INSERT...SELECT` for bulk operations instead of loops.

**Alternatives Considered**:
- Loop with individual INSERTs: Simpler code but O(n) database round-trips
- Raw SQL with parameter interpolation: Security risk (SQL injection)

**Rationale**: Bulk operations like "mark all read" or "mark feed read" can affect hundreds or thousands of articles. A loop with individual INSERTs creates N+1 query patterns that scale poorly. Using `executemany()` batches all operations into a single round-trip. Using `INSERT...SELECT` eliminates the need to fetch IDs first.

**Performance Impact**: Mark-all-read on 1000 articles went from ~1000 queries to 1 query.

### Scaling Strategy

**Decision**: Design for incremental scaling with clear migration paths documented in SCALE.md.

**Scaling Tiers**:
1. **SQLite optimized** (<500 users): WAL mode, batch queries, composite indexes
2. **PostgreSQL** (500-5,000 users): Connection pooling, read replicas, materialized views
3. **Hybrid** (5,000-50,000 users): PostgreSQL + Redis caching + background workers
4. **Microservices** (50,000+ users): Service decomposition, event-driven architecture

**Rationale**: Over-engineering for scale you don't have wastes time. Under-preparing for scale you'll need creates emergencies. The documented scaling path lets you optimize incrementally as usage grows, with clear signals for when to move to the next tier.

**Current Implementation**: Tier 1 (SQLite optimized) with WAL mode, batch queries, and composite indexes.

---

## Technology Choices

### LLM Provider: Multi-Provider Support

**Decision**: Support Anthropic Claude, OpenAI GPT, and Google Gemini.

**Rationale**: Different users have different API keys and preferences. Claude offers prompt caching (90% cost reduction for repeated prefixes). GPT-4o-mini is cheapest. Gemini Flash offers the best price/performance for simple summaries. Supporting all three maximizes user choice.

### Primary Model: Claude Haiku

**Decision**: Default to Claude Haiku for most summarization.

**Alternatives Considered**:
- Claude Sonnet: Higher quality but 10x cost
- GPT-4o: Comparable quality but no prompt caching
- Local models: Would require significant compute and lose quality

**Rationale**: Haiku provides excellent summary quality for news articles at the lowest cost. Complex technical articles automatically upgrade to Sonnet based on content analysis (word count, technical terms).

### Content Extraction: Trafilatura

**Decision**: Use trafilatura for reader-mode article extraction.

**Alternatives Considered**:
- BeautifulSoup only: Requires manual selector logic per site
- Readability.js: Requires Node.js integration
- newspaper3k: Less maintained, lower quality

**Rationale**: Trafilatura is specifically designed for article extraction and handles the wide variety of HTML structures found on news sites. It produces clean markdown suitable for LLM consumption.

### Web Framework: React + Vite + Tailwind

**Decision**: For the web PWA, use React 19 with Vite 7 build tool, Tailwind CSS 3.4 with shadcn/ui patterns.

**Alternatives Considered**:
- Next.js: SSR unnecessary for PWA, adds complexity
- Vue: Smaller ecosystem for component libraries
- Svelte: Less mature ecosystem

**Rationale**: React has the largest ecosystem. Vite provides fast development builds with HMR. Tailwind + shadcn/ui provides a clean design system without heavy dependencies. The PWA approach means the frontend is static files that can be hosted anywhere (Vercel).

### State Management: Zustand + TanStack Query

**Decision**: Zustand 5 for client state, TanStack Query 5 for server state.

**Alternatives Considered**:
- Redux: More boilerplate than necessary
- Context only: Gets messy for complex state
- SWR: TanStack Query has better TypeScript support

**Rationale**: This combination cleanly separates UI state (Zustand: selected article, sidebar collapsed, theme, API config) from server state (TanStack Query: articles, feeds, with caching, optimistic updates, and mutations). Zustand state is persisted to localStorage for session continuity.

### Web PWA Architecture

**Decision**: Full PWA with Workbox service workers, offline caching, and standalone display mode.

**Key Features**:
- Service worker caching via vite-plugin-pwa with auto-update strategy
- Network-first caching for API responses (1-hour expiration)
- Manifest with theme colors and multiple icon sizes (192x192, 512x512)
- Standalone display mode for app-like experience
- OAuth token storage in localStorage (workaround for third-party cookie blocking)

**Rationale**: PWA enables installation on any platform without app store distribution. Service workers provide offline resilience and faster subsequent loads. The standalone display mode removes browser chrome for a native-like experience.

---

## Feature Decisions

### Summaries: Headline + Body + Key Points

**Decision**: Generate three-part summaries: headline (title), short summary (1-2 sentences for list view), and full summary (3-5 paragraphs with key points).

**Rationale**: Different contexts need different summary lengths. The article list needs a quick preview. The detail view can show the full summary. The structured format allows flexible UI rendering.

### Summarization Style: Technical Journalism

**Decision**: Prompts are tuned for AI/tech news, targeting technical professionals.

**Rationale**: The original use case is reading AI and technology news. The prompts emphasize technical details (benchmarks, pricing, availability), avoid marketing language, and assume reader expertise. See SUMMARIZATION_PROMPTS.md for the full prompt engineering rationale.

### Keyboard Navigation: Vim-Style + Standard Shortcuts

**Decision**: Support vim-style navigation (j/k, g g, G, n) alongside standard macOS shortcuts (⌘], ⌘[) and arrow keys.

**Rationale**: RSS readers are keyboard-heavy applications. Technical users often prefer vim bindings. Standard macOS users expect familiar shortcuts. Supporting both vim-style and standard navigation accommodates all users. The macOS app provides 25+ keyboard shortcuts covering navigation, filters, article actions, and view controls.

### Smart Feeds: Today, Unread, Bookmarked, Summarized

**Decision**: Provide smart feeds that filter across all subscriptions.

**Rationale**: Modeled after NetNewsWire. "Today" shows what's new. "Unread" is the default working queue. "Bookmarked" is your reading list. "Summarized" shows which articles have AI summaries.

### OPML Import/Export

**Decision**: Support standard OPML format for feed portability.

**Rationale**: OPML is the universal RSS feed exchange format. Users switching from other readers expect to import their subscriptions. Users may want to backup or migrate to other readers.

### Article Themes

**Decision**: Provide 7 stylized reading themes (Auto, Manuscript, Noir, Ember, Forest, Ocean, Midnight) instead of just light/dark mode.

**Alternatives Considered**:
- Light/dark only: Too limited for reading-focused app
- Full custom theme builder: Over-engineered for the use case
- CSS file uploads: Too technical for most users

**Rationale**: Reading is a personal experience. Some users prefer warm sepia tones (Manuscript) for long reading sessions. Others want high contrast (Noir) or calming colors (Forest, Ocean). Each theme is carefully designed with coordinated background, text, link, and accent colors. CSS variables enable the themes to work in the native WebView.

**Platform Notes**: The macOS app offers all 7 article themes. The web PWA currently supports light/dark/system theme modes for the overall UI, with article themes planned for future parity.

### Web PWA Design Styles

**Decision**: Provide 9 design style variants for the web PWA UI, each with a distinct color identity: Default (cool slate blue), Warm (amber & copper), Soft (lavender with soft shadows), Sharp (crimson & steel with square edges), Compact (forest green with tight spacing), Teal AI (ocean depths), High Contrast (pure black/white), Sepia (golden parchment), and Mono (pure grayscale).

**Alternatives Considered**:
- Single fixed design: Too limiting for diverse user preferences
- Full CSS customization: Too complex for most users
- Separate accessibility mode: Better to integrate accessibility as design choices
- Structural-only variants: Early versions shared the same blue-gray palette, making themes hard to distinguish

**Rationale**: Different users have different visual preferences and needs. Each theme has a unique color family (distinct HSL hue range) so themes are immediately distinguishable from each other. Structural differences (border radius, spacing, shadows) complement but don't replace color identity. Design styles are implemented as CSS custom property overrides with full light and dark mode palettes, making them lightweight and composable with the existing theme system.

**Color Identities**:
- **Default**: Cool slate blue (hsl 220-222) — the baseline palette
- **Warm**: Amber & copper (hsl 25-35) — high-saturation warm tones
- **Soft**: Lavender (hsl 262-270) — purple-tinted shadows and rounded corners
- **Sharp**: Crimson & steel (hsl 350 primary, hsl 220 neutral) — square corners, bold accents
- **Compact**: Forest green (hsl 150-155) — nature-inspired, tight spacing
- **Teal AI**: Ocean teal (hsl 178-190) — full teal palette, not just an accent swap

**Accessibility Focus**: Three styles specifically address accessibility needs:
- **High Contrast**: Pure black/white, 2px borders, bold focus rings (WCAG AAA compliant)
- **Sepia**: Rich golden parchment tones (hsl 35-42) with serif typography to reduce eye strain
- **Mono**: Grayscale only, removes all color accents for reduced visual noise

Global `prefers-reduced-motion` support disables animations for users who prefer minimal motion.

### Keyboard Shortcuts Implementation (Web)

**Decision**: Use the `react-hotkeys-hook` library for web PWA keyboard shortcuts instead of custom event handlers.

**Alternatives Considered**:
- Custom `useEffect` with `keydown` listeners: Brittle, requires manual focus management
- Native browser accesskey: Poor cross-browser support, conflicts with browser shortcuts
- Mousetrap library: Less React-idiomatic, not maintained as actively

**Rationale**: The initial custom implementation had silent failures due to focus restrictions and view guards. `react-hotkeys-hook` is a battle-tested library that handles edge cases (input focus, modal states, cross-browser compatibility) robustly. It provides a clean hook-based API that integrates naturally with React's component model.

### Typography Options

**Decision**: Offer 28 fonts across four categories (sans-serif, serif, slab-serif, monospace).

**Alternatives Considered**:
- System fonts only: Too limiting
- User-installed fonts: Complex to enumerate and may break
- Web fonts: Adds latency and external dependencies

**Rationale**: Typography significantly affects reading comfort and speed. The font selection includes macOS system fonts that are guaranteed to be available (SF Pro, New York, SF Mono) plus classic fonts (Georgia, Palatino, Helvetica Neue). Categories help users find appropriate fonts: serif for long-form reading, sans-serif for scanning, monospace for code-heavy content.

**Platform Notes**: The macOS app offers the full 28-font selection for both app UI and article content. The web PWA uses system fonts with Tailwind Typography for article prose styling.

### JavaScript Rendering (Optional)

**Decision**: Support JavaScript rendering via Playwright for JS-heavy sites.

**Alternatives Considered**:
- Puppeteer: Playwright has better async API
- Selenium: Heavier, slower
- No JS support: Would miss content from SPAs

**Rationale**: Some news sites (especially aggregators and paywalled sites) require JavaScript to render content. This is optional because it adds 2-5 seconds latency and significant memory usage. Most feeds work fine without it.

### Archive Fallback (Optional)

**Decision**: Support fetching from archive.is and Wayback Machine for paywalled content.

**Rationale**: For personal reading, archives often have the content. This is an optional fallback, not a circumvention tool. The heuristic checks for known paywalled domains before attempting.

### Gmail Newsletter Integration

**Decision**: Import newsletters from Gmail via IMAP OAuth2, creating virtual "feeds" with `newsletter://` URLs.

**Alternatives Considered**:
- Gmail API with push notifications: More complex OAuth scopes, webhook infrastructure required
- Forwarding to a catch-all email: Requires email server setup, less reliable
- Manual paste/upload: Poor UX for regular newsletters

**Rationale**: Many valuable newsletters arrive via email, not RSS. Gmail IMAP provides read-only access to the inbox with standard OAuth2 authentication. The `newsletter://sender@email.com` URL scheme creates a feed-like experience while making it clear these aren't traditional RSS feeds.

**Email Parsing**: Newsletter HTML is cleaned aggressively:
- Remove tracking pixels (1x1 images, known tracker domains)
- Strip invisible elements (`display:none`, `visibility:hidden`)
- Remove base64-encoded images (bloat, often tracking)
- Extract sender-specific content using known newsletter patterns

**Fetch Modes**: Two fetch options handle different use cases:
- **Fetch New**: Only imports emails since last fetch (default, fast)
- **Fetch All**: Re-scans entire inbox for the configured label (initial import, recovery)

**Result Tracking**: Import results distinguish between:
- **Imported**: New articles successfully created
- **Skipped**: Duplicates (already imported based on message ID)
- **Empty**: Emails with insufficient content after cleaning
- **Failed**: Parse errors (logged with full traceback for debugging)

### Content Source Types

**Decision**: Use URL schemes to distinguish content sources: `http(s)://` for RSS feeds, `newsletter://` for Gmail newsletters, `local://` for Library items.

**Alternatives Considered**:
- Separate tables per source type: Would complicate queries and UI code
- Flags on feed table: Less extensible, harder to reason about
- Single URL scheme with metadata: Loses semantic clarity

**Rationale**: Different content sources have fundamentally different fetch mechanisms:
- **RSS feeds** (`http://`, `https://`): Fetched via HTTP using feedparser, subject to SSRF validation
- **Newsletter feeds** (`newsletter://sender@email.com`): Fetched via Gmail IMAP OAuth, no HTTP involved
- **Library items** (`local://library`): User-uploaded content (PDFs, URLs), stored directly in database

The URL scheme makes the fetch mechanism immediately apparent in code. A simple scheme check determines whether a feed needs HTTP refresh, Gmail fetch, or no refresh at all.

**Feed Health Dashboard**: The Feed Health view only shows RSS feeds since it monitors HTTP fetch status (last fetched, fetch errors, stale feeds). Newsletter and Library feeds are excluded via the `isLocalFeed` property which returns `true` for non-HTTP schemes. This prevents confusing "Never fetched" status for feeds that don't use HTTP fetching.

**SSRF Protection**: The URL validation in `safe_fetch.py` only allows `http` and `https` schemes. Newsletter feeds bypass this entirely since they're fetched via Gmail IMAP, not HTTP. This prevents "URL scheme newsletter is not allowed" errors during feed refresh.

### Topic Clustering (Optional)

**Decision**: Simple keyword-based clustering, not ML-based.

**Alternatives Considered**:
- HDBSCAN: Requires heavy ML dependencies
- LLM-based clustering: Too expensive per article
- Embedding-based: Adds complexity for marginal benefit

**Rationale**: For typical RSS volumes (<100 articles/day), simple keyword extraction + Jaccard similarity is "good enough" and has zero dependencies. The goal is grouping related stories ("5 articles about GPT-5"), not sophisticated topic modeling.

### Reading Statistics

**Decision**: Track reading behavior and summarization usage with support for both rolling windows (7/30/90 days) and calendar periods (week/month/year).

**Alternatives Considered**:
- No analytics: Misses opportunity for user insights
- Third-party analytics: Privacy concerns, external dependency
- Real-time only: Loses historical trends

**Rationale**: Users benefit from understanding their reading patterns—which feeds they actually read, how much time they spend, what topics trend over time. The statistics are computed from existing data (read timestamps, summarization records) without additional tracking. Topic history is persisted separately to enable trend analysis across clustering runs.

**Statistics Tracked**:
- **Summarization**: Articles summarized, summarization rate, model usage breakdown
- **Reading**: Articles read, total/average reading time, bookmarks, top feeds by engagement
- **Topics**: Current topic distribution, historical topic trends with persistence

### Article Organization (Web)

**Decision**: Provide grouping (date/feed/topic) and sorting (newest/oldest/title) in the web PWA article list. A separate "Unread" smart feed handles read-state filtering.

**Rationale**: Power users need ways to manage large article lists. Grouping by topic (AI-powered) surfaces related stories. Grouping by feed helps when catching up on specific sources. Sorting by title helps find specific articles.

**Hide-Read Removed**: An explicit "hide read" toggle was removed. The "Unread" smart feed already does this job — selecting it filters to unread articles across all subscriptions. A redundant toggle that duplicates an existing filter violates the principle of having one canonical way to do things. The toggle also required its own UI state separate from the filter state, which created subtle inconsistencies (e.g., marking an article read while "hide read" was on would cause it to vanish immediately, but the same article would still appear if you navigated to the Unread feed). Removing it simplifies both the UI and the state model.

### Related Links via Neural Search

**Decision**: Integrate Exa's neural search API for semantic article discovery.

**Alternatives Considered**:
- **Traditional search APIs** (Brave, SERP proxies): Keyword-based, misses conceptual relationships
- **Internal embeddings** (OpenAI): Only searches your own database, no external discovery
- **LLM-based search** (Claude with web tool): Higher cost, slower
- **Tavily**: Similar capability but 2x cost and slower than Exa

**Rationale**: Research papers and technical articles often have related content that keyword search misses. Exa's neural embeddings understand semantic similarity—if you're reading about "transformers in NLP," it finds related work on attention mechanisms even if they don't share exact keywords. At $5 per 1,000 searches with sub-second latency, Exa offers the best price/performance for semantic discovery.

**Query Construction Strategy**: Three-tier fallback system maximizes quality while minimizing cost:
1. **Title + Key Points** (from existing summary): Best quality, no additional cost
2. **Title + LLM Keywords** (Claude Haiku extraction): Good quality, ~$0.001/article
3. **Title Only**: Acceptable fallback when no content available

This strategy ensures good results even for articles without summaries while opportunistically using existing summary data when available.

**Deduplication**: Research papers appear on multiple platforms (arXiv, university sites, ResearchGate). The implementation filters:
- Exact URL matches with source article
- Same domain as source article
- Duplicate titles (case-insensitive)
- More than 2 results from any single domain

This prevents "5 copies of the same arXiv paper" results common with naive semantic search.

**Performance**: Results are cached for 24 hours with normalized query keys (lowercase, whitespace-stripped, SHA256 hashed). Cache hit rates >30% after initial use significantly reduce API costs. Background task execution ensures the UI never blocks during the 0.5-1.5 second search.

**Platform Support**: Currently macOS-only with independent "Find Related" button. The feature enhances article discovery without requiring it—users can opt in when they want deeper exploration of a topic.

### Article Detail: Tab Strip Layout

**Decision**: Organize AI features (summary, related articles, chat) into a tab strip alongside article content, rather than as collapsible accordion sections stacked below it.

**Alternatives Considered**:
- Stacked accordion sections: The original design — summary, related links, and chat collapse/expand below the article body. Requires scrolling past content to discover; AI features feel bolted on.
- Persistent AI sidebar: A split pane showing AI content beside the article. Reduces reading width; feels like a permanent second panel rather than an optional feature.
- Floating overlay/HUD: Shows AI status over the article. Gets in the way of reading and is hard to dismiss predictably.

**Rationale**: Tabs make AI features peers of the content rather than appendages. The tab strip sits at a fixed position in the UI, so discoverability doesn't depend on scrolling. Each tab has exactly one job — no visual competition from other sections. The three-pane structure is fully preserved; the change is within the detail pane only.

**Tab Design Decisions**:
- **Dot indicators** (purple for AI summary, blue for related articles and chat) signal that content is available without requiring the user to open each tab.
- **Chat is gated**: the Chat tab is disabled until a summary exists. Chat without context is unhelpful, and the visual disabled state communicates the prerequisite before the user clicks.
- **Auto-advance on action completion**: clicking Summarize switches to the AI tab when the summary arrives; clicking Find Related switches to the Related tab when links load — but only if the user is still on the Article tab (hasn't navigated elsewhere). This makes the action → result flow tangible without hijacking navigation.
- **Reset on article change**: switching articles resets to the Article tab, so reading always starts with content, not a potentially empty AI tab.
- **Scroll reset on tab switch**: switching tabs scrolls back to the top of the content area to avoid disorienting mid-page positions.

**Platform Implementation**: Web uses a CSS bottom-border underline strip. macOS uses a custom SwiftUI `HStack` of `Button` views with an `accentColor` rectangle overlay as the active indicator. Both sit outside the scroll view so the tab strip is sticky.

### Unified AI Entry Point: Smart Tabs

**Decision**: The tab strip is the single entry point for all AI features (Summary, Related, Chat). Clicking a tab that has no content yet triggers generation inline — no separate toolbar button or dropdown needed.

**History**: Three separate toolbar buttons (Summarize, Context/Find Related, Chat) were first consolidated into a single "AI" dropdown. The dropdown was then removed entirely once smart tabs made it redundant. The dropdown had two jobs: trigger actions and navigate to results. Smart tabs do both, so the dropdown was pure overhead — an extra click and an extra mental model to maintain.

**Smart Tab Behavior**:
- **AI tab (no summary yet)**: clicking triggers summarization and switches to the AI tab.
- **Related tab (no links yet)**: clicking triggers Find Related and switches to the Related tab.
- **Chat tab**: only enabled once a summary exists; clicking opens the chat directly.
- Tabs with triggerable but empty content show a small `+` indicator (web: `<Plus />` icon at 40% opacity; macOS: SF Symbol `plus` at secondary color) so users know the click will do something.

**Alternatives Considered**:
- AI dropdown: Intermediate design. Better than three separate buttons, but still duplicated the tab strip's navigation role.
- Three separate buttons: Original design. Clear but noisy; added width and cognitive load.
- Tabs as navigation only (action stays in toolbar): Keeps action and navigation separate but forces users to learn two surfaces.

**Rationale**: The tab strip is already visible and labeled. Making it dual-purpose (navigate + trigger) eliminates the toolbar AI button entirely and reduces the total number of interactive elements in the toolbar. The `+` indicator communicates affordance without requiring a tooltip or separate button. The action → result flow is tangible: clicking a tab triggers the work, and the same tab shows the result when it arrives.

### Article List: Key Points in List Response

**Decision**: Include `key_points` (the first few AI-generated bullet points) in the article list API response alongside `summary_short`, and use `key_points[0]` as the row preview text when available.

**Alternatives Considered**:
- **Summary short only in list**: Simpler API, but `summary_short` is a prose sentence while `key_points[0]` is a tighter, more scannable bullet.
- **Separate endpoint for key points**: Clean separation but adds a per-row request or a batch fetch call.
- **Client-side combination**: Fetching article detail for every visible row is prohibitively expensive.

**Rationale**: Key points are already generated as part of summarization and stored in the same `articles` row. Including them in the list response adds negligible query cost (no join needed) while replacing the raw snippet with a curated first insight. The fallback chain is `key_points[0]` → `summary_short` → nothing, so rows degrade gracefully for unsummarized articles.

### Article List: `has_chat` via EXISTS Subquery

**Decision**: Source the chat-badge boolean directly in the article list query using an EXISTS subquery, rather than a separate API call or join that would require fetching full chat records.

**Alternatives Considered**:
- **Separate `/articles/{id}/has-chat` call per row**: N+1 requests for N rows — unacceptable.
- **LEFT JOIN on `article_chats`**: Returns a row per message; requires `COUNT(DISTINCT)` and changes the cardinality of the result set.
- **Cached flag on article row**: Denormalization; the flag would go stale unless we update it on every chat mutation.

**Rationale**: `EXISTS(SELECT 1 FROM article_chats WHERE article_id = ? AND user_id = ?)` is a constant-time predicate that the query planner evaluates with an index seek. It adds no extra rows and no extra round-trips. The boolean is accurate at query time without any cache invalidation work. The only cost is one extra `user_id` parameter in the SQL params list.

### Search: Scope Toggle for Summary Inclusion

**Decision**: Add an `include_summaries` parameter to the search endpoint. When `false`, restrict FTS5 search to `title` and `content` columns only; when `true` (default), include `summary_short` and `summary_full` in the search.

**Alternatives Considered**:
- **Always search summaries**: Reasonable default but produces false positives — searching for "transformer" in summaries matches articles about electrical transformers that the article body doesn't focus on.
- **Always exclude summaries**: Simpler, but loses the ability to find an article you remember reading about a topic only mentioned in the AI summary.
- **Separate search endpoints**: Over-engineered for a boolean toggle.

**Rationale**: FTS5 column-restriction syntax (`title: "q" OR content: "q"`) makes this a one-line change to the query string. The toggle is persisted in client state (localStorage / AppState) so users set it once. The default `true` maximizes recall for new users; power users can narrow to body-only when they want precision.

### Topics Sidebar: Dedicated Lightweight Endpoint

**Decision**: Add `GET /statistics/topics/current` that returns only the most recent clustering run's topics with article counts — a purpose-built subset of the heavy `/reading-stats` endpoint.

**Alternatives Considered**:
- **Reuse `/statistics/reading-stats`**: Already returns `current_topics`, but also fetches summarization stats, reading activity, and topic trends — ~10x the work needed for a sidebar widget.
- **Client-side filtering from full stats**: Same problem as above; forces the client to request and parse a large response just to render a list of topic names.
- **Store topics in a separate sidebar-specific table**: Overkill; the data already exists in `topic_history`.

**Rationale**: The sidebar loads on every navigation. A lightweight endpoint that reads only the latest `topic_history` rows is fast and cheap. The backend does a single `SELECT ... WHERE clustered_at = (SELECT MAX(...))` and returns a short list. Sidebar responsiveness justifies the single extra endpoint.

**Client-side filtering**: Topics filter the already-fetched article list by intersecting `article_ids` from the topic response with the current list. This avoids a new filtered-articles API call and keeps the filter instant even on large lists.

### Floating "Jump to AI Summary" Chip

**Decision**: Show a floating capsule button in the bottom-right of the Article tab after the user scrolls past ~30% of the content, offering a one-click path to the AI tab.

**Alternatives Considered**:
- **Persistent banner at top of article**: Always visible, but occupies reading width and is distracting for users who don't want AI features.
- **Chip after 50% or 70% scroll**: More selective, but users who skim (fast scrollers) may never trigger it.
- **Chip only for long articles**: Adds complexity; the chip is useful at any length since the AI tab is still off-screen.
- **No chip — rely on tab strip**: The tab strip is visible, but for users in reading flow, a contextual nudge is more effective than a passive tab label.

**Rationale**: 30% is a deliberate choice — it fires after the user has read enough to decide they want context, but before they've finished and lost interest. The chip is non-intrusive (positioned over empty space, semi-transparent until hovered), auto-dismisses on tab switch, and never appears if there's no summary. It converts reading engagement directly into AI feature discovery without interrupting flow.

**Scroll detection implementation**: shadcn's `ScrollArea` wraps a Radix primitive. The scrollable element is a `div[data-radix-scroll-area-viewport]` inside the scroll container — not the container itself. A `useEffect` queries this element by attribute selector and attaches a passive native `scroll` listener. On macOS, an `NSScrollView` delegate tracks `documentVisibleRect` against `documentView.frame.size.height` to compute the same ratio.

### Summarization: Two-Pass Critic Pipeline

**Decision**: Add an optional second LLM pass that evaluates and revises summaries for complex content.

**Alternatives Considered**:
- **Agentic loop** (iterate until convergence): Unbounded cost, convergence is hard to guarantee
- **Always two-pass**: Doubles cost for simple articles where single-pass quality is sufficient
- **Higher-tier model for everything**: 10x cost increase, diminishing returns on short content

**Rationale**: Single-pass summarization asks the LLM to simultaneously comprehend content, extract facts, write prose, format JSON, and follow ~20 style rules. This works well for short, single-story articles but degrades for newsletters (stories get merged) and long articles (headline quality drops). A targeted second pass addresses these specific weaknesses without the cost or complexity of a full agentic loop.

**Design**: Generate → Critic (2-step, not a loop). Step 1 always produces a complete, usable summary. Step 2 conditionally evaluates structure, readability, style adherence, and writes an improved headline.

**Trigger Conditions** (checked after step 1):
- Word count > 2,000 (complex content benefits from review)
- `content_type == "newsletter"` (multi-story content needs structural review)

**Model Selection**: Critic uses FAST tier (Haiku) since it's pattern-matching against style rules, not deep comprehension. This keeps the marginal cost at ~$0.001 per critic call.

**Fallback Safety**: If the critic call fails or returns unparseable JSON, step 1 output is used as-is. The pipeline never degrades below single-pass quality.

**Kill Switch**: `critic_enabled` flag (default `True`) on the `Summarizer` class allows disabling the critic for cost control or testing without code changes.

**Future Direction**: Plan documented in LOOP.md to extend critic to all articles once revision rate data validates the cost/quality tradeoff.

---

## Lessons Learned

### Keep It Simple

The original codebase had six different clustering implementations, multiple caching strategies, and complex inheritance hierarchies. The redesign consolidated to one clustering approach, one cache system with pluggable backends, and flat module structure. The simpler code is easier to understand, debug, and extend.

### Summaries First, Content Second

Early versions hid summaries behind a "Summarize" button. Users often didn't click it. Making summaries visible by default in the article list dramatically increased engagement with the AI features.

### Native Feels Better

The initial prototype was a web app. Moving to native SwiftUI provided better keyboard handling, system integration (Spotlight search for articles, notifications for new content), and overall feel. The web PWA was later added for cross-platform access, but the native app remains the primary experience.

### User-Provided API Keys

Early versions required server-side API keys. Switching to user-provided keys (stored in browser localStorage for web, Keychain for native) eliminated the need for user accounts, reduced hosting costs, and gave users control over their AI spending.

### Security Hardening

The security improvements were implemented incrementally:

1. **API Key Authentication** - Simple shared key for single-user deployments
2. **SSRF Protection** - Block requests to private networks and cloud metadata endpoints
3. **Rate Limiting** - Prevent abuse and excessive LLM costs
4. **OAuth Authentication** - User login via Google/GitHub for multi-user deployments

Each layer addresses different threat models. API key auth is sufficient for personal use. OAuth enables sharing with trusted users while maintaining individual accountability.

### Deployment Should Be Simple

The deployment setup evolved from complex Docker configurations to simple Platform-as-a-Service deployment:
- Backend: Railway with Railpack auto-detection
- Frontend: Vercel with static file hosting
- Database: SQLite on Railway's persistent volume

This setup requires no DevOps expertise and costs ~$0-5/month for personal use.

---

## Appendix: Architecture Evolution

### Phase 1: Web Prototype
- Python backend with Jinja templates
- Simple CRUD operations
- Manual summarization trigger

### Phase 2: Native Mac App
- SwiftUI three-pane layout
- Background server management
- Automatic summarization

### Phase 3: Feature Expansion
- Multiple LLM providers
- JavaScript rendering
- Archive fallbacks
- Topic clustering
- Spotlight integration

### Phase 4: Web PWA
- React 19 frontend for cross-platform access
- Three-pane layout matching native app (Sidebar, Article List, Article Detail)
- Shared backend with native app
- User-provided API keys via request headers
- OAuth authentication (Google/GitHub)
- Vim-style keyboard shortcuts (j/k/m/s/o/r)
- Light/dark/system theme support
- PWA with offline caching and standalone mode
- Library view for standalone content (PDFs, URLs, documents)

### Phase 5: Reading Experience Polish
- Article themes (7 stylized themes with CSS variables)
- Expanded typography (28 fonts across 4 categories)
- Comprehensive keyboard shortcuts (25+ shortcuts)
- Font size controls (⌘+/⌘-/⌘0)
- Reader mode toggle

### Phase 6: Multi-User & Analytics
- Multi-user support with per-user read/bookmark state
- User resolution via OAuth session or API key
- Reading statistics (articles read, reading time, top feeds)
- Summarization metrics (rate, model usage breakdown)
- Topic trend tracking with historical persistence
- Web PWA article organization (grouping, sorting, hide read, pagination)

### Phase 7: Web PWA Design System
- Design style variants (9 styles: Default, Warm, Soft, Sharp, Compact, Teal AI, High Contrast, Sepia, Mono)
- Accessibility-focused styles (High Contrast WCAG AAA, Sepia reading mode, Mono grayscale)
- Reduced motion support via `prefers-reduced-motion`
- Robust keyboard shortcuts via react-hotkeys-hook library
- Extracted helper functions for cleaner codebase

### Phase 8: Performance & Scaling Foundation
- SQLite WAL mode for concurrent reads during writes
- PRAGMA optimizations (cache_size, temp_store, mmap_size)
- Batch query patterns (executemany, INSERT...SELECT)
- Composite indexes for common query patterns
- Documented scaling path (SQLite → PostgreSQL → Hybrid → Microservices)
- SCALE.md with detailed migration guides for each tier

### Phase 9: Gmail Newsletter Integration
- Gmail IMAP OAuth2 for newsletter import
- URL scheme pattern (`newsletter://sender@email.com`) for distinct content sources
- Feed Health dashboard excludes non-HTTP feeds
- Separate tracking for empty/insufficient vs duplicate emails
- Email content cleaning (tracking pixels, invisible elements, base64 images)

### Phase 10: Neural Search for Article Discovery
- Exa API integration for semantic article similarity
- 3-tier query construction (key points → LLM keywords → title fallback)
- Intelligent deduplication (filters duplicates by URL, domain, title)
- 24-hour caching with normalized query keys
- Background task execution with polling (30s timeout)
- Database columns for related_links (JSON) and extracted_keywords cache
- macOS-only "Find Related" button in article detail view
- Comprehensive test coverage (25+ tests)

### Phase 11: Two-Pass Summarization
- Critic step evaluates structure, readability, and style adherence
- Rewrites headline with full context of generated summary
- Triggers for long articles (>2,000 words) and newsletters
- FAST tier (Haiku) for critic — pattern matching, not comprehension
- Graceful fallback to step 1 output on any failure
- `critic_enabled` kill switch for cost control
- 20 unit tests with MockProvider (no API keys required)
- Rollout plan documented in LOOP.md

### Phase 12: Access Control & Visual Identity
- Two-tier user system (admin/regular) with `ADMIN_EMAILS` config
- `require_admin` FastAPI dependency for protected mutations (feeds, settings, notification rules)
- API key users retain admin access for macOS app backwards compatibility
- Frontend admin gating via `is_admin` flag from `/auth/status`
- Distinct color identities for all 9 design styles (each theme has a unique HSL hue family)
- Themes distinguishable by color, not just structural differences

### Phase 13: AI-Integrated Article List UI
- Key points exposed in article list API (`key_points` in `ArticleResponse`) for richer row previews
- `has_chat` sourced via EXISTS subquery in list query (no extra per-article request)
- `related_link_count` derived from JSON column at serialization time
- Search scope toggle (`include_summaries`) using FTS5 column-restriction syntax
- Dedicated lightweight `/statistics/topics/current` endpoint for sidebar topics
- Topics sidebar section with collapsible UI and client-side topic filtering by article ID set
- Floating "Jump to AI Summary" chip triggered at 30% scroll progress in Article tab
- Chip scroll detection via Radix `[data-radix-scroll-area-viewport]` native event listener
- Optional Codable fields (Int?, Bool?) for backward-compatible Swift model evolution

### Phase 13: Tantivy Search
- Replaced SQLite FTS5 with Tantivy (Rust-based, in-process via tantivy-py)
- Fixes silent failures on special-character queries (`GPT-4`, `C++`, `U.S.`, `AND`)
- Per-field relevance boosting (title ×4, summary_short ×2, full/content ×1)
- Three-tier query strategy: boosted boolean → plain multi-field → stripped-word fallback
- Explicit sync via Database facade write paths (no triggers)
- Feed-deletion edge case: diff IDs before/after to preserve Archive-moved articles
- FTS5 retained as fallback if Tantivy is unavailable
- One-time index rebuild on first startup from all articles in SQLite

### Phase 14: Article Detail UI Redesign

- Three-pane structure preserved; article detail pane restructured with a four-tab strip (Article · AI Summary · Related · Chat)
- AI features promoted from scroll-to-discover accordion sections to first-class tab destinations
- Dot indicators on tabs signal content availability without requiring the user to click
- Auto-advance ties action to result: summarize → AI tab, find related → Related tab (only if still on Article tab)
- Chat tab gated behind summary existence on both web and macOS; visually disabled with tooltip explaining prerequisite
- Unified AI toolbar button replaces three separate buttons (Summarize, Context, Chat)
- AI dropdown shows inline status: first key point preview, related article count, chat active indicator
- Count badge on AI button reflects total number of activated AI features per article
- Scroll position resets on tab switch to avoid mid-page disorientation
- UITODOS.md created to track remaining UI improvement backlog

### Current: Stable Platform
- Native macOS app + Web PWA
- Railway backend + Vercel frontend
- Multi-provider LLM support (Claude, GPT, Gemini)
- Multi-user support with OAuth (Google, GitHub) and role-based access control
- Gmail newsletter integration via IMAP
- Neural search for related articles (Exa)
- Two-pass summarization for complex content
- Reading statistics and topic trends
- Polished reading experience with themes and typography
- Accessibility-first design system with 9 color-distinct visual variants
- Performance-optimized SQLite with scaling documentation
- ~2,800 lines of Python backend
