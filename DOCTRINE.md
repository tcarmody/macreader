# DataPoints Doctrine

This document records key architectural and design decisions made during the development of DataPoints, explaining the reasoning behind each choice.

---

## Table of Contents

1. [Core Philosophy](#core-philosophy)
2. [Architecture Decisions](#architecture-decisions)
3. [Technology Choices](#technology-choices)
4. [Feature Decisions](#feature-decisions)
5. [Lessons Learned](#lessons-learned)

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

## Architecture Decisions

### Client-Server Split

**Decision**: Native Swift app + Python FastAPI backend, communicating via JSON API.

**Alternatives Considered**:
- Pure Swift (no Python): Would lose access to Python's rich ecosystem for feed parsing, content extraction, and LLM integrations
- Electron app: Would sacrifice native feel and system integration
- Python with embedded web UI: Would sacrifice native feel

**Rationale**: This split plays to each language's strengths. Swift/SwiftUI excels at native Mac UI. Python has the best libraries for RSS parsing (feedparser), content extraction (BeautifulSoup, trafilatura), and LLM APIs (anthropic, openai, google-generativeai).

### SQLite for Persistence

**Decision**: SQLite with FTS5 for full-text search, stored locally.

**Alternatives Considered**:
- PostgreSQL: Overkill for single-user app
- Core Data: Would complicate the client-server split
- Cloud database: Adds latency, cost, and complexity for personal tool

**Rationale**: SQLite is fast, requires no setup, and FTS5 provides excellent full-text search. Articles are inherently local data—you don't need cloud sync for an RSS reader.

### Tiered Caching (Memory + Disk)

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

**Decision**: Provide grouping (date/feed/topic), sorting (newest/oldest/title), and hide-read toggle in the web PWA article list.

**Rationale**: Power users need ways to manage large article lists. Grouping by topic (AI-powered) surfaces related stories. Grouping by feed helps when catching up on specific sources. Sorting by title helps find specific articles. Hide-read toggle reduces visual clutter. These controls match the macOS app's capabilities for feature parity.

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
