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

**Decision**: For the web PWA, use React 18 with Vite build tool, Tailwind CSS with shadcn/ui patterns.

**Alternatives Considered**:
- Next.js: SSR unnecessary for PWA, adds complexity
- Vue: Smaller ecosystem for component libraries
- Svelte: Less mature ecosystem

**Rationale**: React has the largest ecosystem. Vite provides fast development builds. Tailwind + shadcn/ui provides a clean design system without heavy dependencies. The PWA approach means the frontend is static files that can be hosted anywhere (Vercel).

### State Management: Zustand + TanStack Query

**Decision**: Zustand for client state, TanStack Query for server state.

**Alternatives Considered**:
- Redux: More boilerplate than necessary
- Context only: Gets messy for complex state
- SWR: TanStack Query has better TypeScript support

**Rationale**: This combination cleanly separates UI state (Zustand: selected article, sidebar collapsed, theme) from server state (TanStack Query: articles, feeds, with caching and mutations).

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

**Rationale**: Reading is a personal experience. Some users prefer warm sepia tones (Manuscript) for long reading sessions. Others want high contrast (Noir) or calming colors (Forest, Ocean). Each theme is carefully designed with coordinated background, text, link, and accent colors. CSS variables enable the themes to work in both the native WebView and the web PWA.

### Typography Options

**Decision**: Offer 28 fonts across four categories (sans-serif, serif, slab-serif, monospace).

**Alternatives Considered**:
- System fonts only: Too limiting
- User-installed fonts: Complex to enumerate and may break
- Web fonts: Adds latency and external dependencies

**Rationale**: Typography significantly affects reading comfort and speed. The font selection includes macOS system fonts that are guaranteed to be available (SF Pro, New York, SF Mono) plus classic fonts (Georgia, Palatino, Helvetica Neue). Categories help users find appropriate fonts: serif for long-form reading, sans-serif for scanning, monospace for code-heavy content.

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

### Topic Clustering (Optional)

**Decision**: Simple keyword-based clustering, not ML-based.

**Alternatives Considered**:
- HDBSCAN: Requires heavy ML dependencies
- LLM-based clustering: Too expensive per article
- Embedding-based: Adds complexity for marginal benefit

**Rationale**: For typical RSS volumes (<100 articles/day), simple keyword extraction + Jaccard similarity is "good enough" and has zero dependencies. The goal is grouping related stories ("5 articles about GPT-5"), not sophisticated topic modeling.

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
- React frontend for cross-platform access
- Shared backend with native app
- User-provided API keys via headers

### Phase 5: Reading Experience Polish
- Article themes (7 stylized themes with CSS variables)
- Expanded typography (28 fonts across 4 categories)
- Comprehensive keyboard shortcuts (25+ shortcuts)
- Font size controls (⌘+/⌘-/⌘0)
- Reader mode toggle

### Current: Stable Platform
- Native macOS app + Web PWA
- Railway backend + Vercel frontend
- Multi-provider LLM support
- Polished reading experience with themes and typography
- ~2,500 lines of Python backend
