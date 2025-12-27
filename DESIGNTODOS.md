# Design Improvement TODOs

Future UI/UX improvements to consider for the macOS RSS reader app.

## Implemented Features

### Reading Experience
- [x] **Article Font & Line Spacing Settings** - Customizable font sizes and line spacing
- [x] **Typeface Selection** - System and custom font options for UI and content
- [x] **Reader Mode Toggle** - Distraction-free reading with `f` key, hides sidebar/list, centers content

### Interaction Improvements
- [x] **Drag & Drop Feeds** - Drag feeds between categories with visual drop indicators
- [x] **Keyboard Shortcuts** - Vim-style navigation (j/k, n, g g, G, etc.)
- [x] **Expand/Collapse All Folders** - `;` to collapse all, `'` to expand all

### Visual Polish
- [x] **Empty State Illustrations** - Custom SwiftUI illustrations for empty states
- [x] **Last Refresh Time** - Shows "Updated Xm ago" in status bar

### Sharing & Integration
- [x] **Improved Share Sheet** - Share link, share with summary, copy summary, copy link options
- [x] **Spotlight Integration** - Articles indexed for system-wide search with deep linking

### NetNewsWire-Inspired Features
- [x] **Smart Feeds** - Today, Unread, Bookmarked, Summarized, Unsummarized filters
- [x] **Read Filter Toggle** - Hide/show read articles
- [x] **Mark Above/Below as Read** - Context menu options for catching up
- [x] **Copy Article URL** - Available in share menu
- [x] **Go to Next Unread** - `n` key to jump to next unread article
- [x] **Article Extraction Toggle** - Fetch full article with loading/error states
- [x] **Window State Persistence** - Remembers collapsed categories and selected filter

---

### Feed & Article Management
- [x] **OPML Import/Export** - Import and export feed subscriptions
- [x] **Bulk Operations** - Delete multiple feeds, bulk mark articles as read
- [x] **Category Management** - Rename, delete categories; move uncategorized feeds
- [x] **Multi-Select** - Select multiple articles/feeds for bulk actions
- [x] **Context Menus** - Quick actions via right-click on feeds and articles

### Article Display
- [x] **Grouping Options** - Group by Date, Feed, or Topic (AI-powered clustering)
- [x] **Sort Options** - Newest/Oldest First, Unread First, Title A-Z/Z-A
- [x] **List Density Settings** - Compact, Comfortable, Spacious options

### AI Features
- [x] **Multiple LLM Providers** - Anthropic Claude, OpenAI GPT, Google Gemini
- [x] **Model Selection** - Choose speed vs quality models per provider
- [x] **Auto-Summarization** - Option to summarize on fetch
- [x] **Summary Types** - One-liner, full summary, and key points extraction

### Library Feature
- [x] **URL Library** - Save URLs for later reading
- [x] **File Uploads** - Add PDFs, DOCX, TXT, Markdown, HTML files
- [x] **Library Summarization** - AI summaries for library items

### Native macOS Integration
- [x] **Dock Badge** - Unread count on dock icon
- [x] **Desktop Notifications** - Alerts for new articles
- [x] **Full-Text Search** - SQLite FTS5-powered search with `/` shortcut

### Settings & Configuration
- [x] **Refresh Interval** - Configurable auto-refresh timing
- [x] **Mark Read on Open** - Optional auto-mark behavior
- [x] **Notifications Toggle** - Enable/disable desktop notifications

### Reading Progress
- [x] **Reading Progress Indicator** - Progress bar at top of article view, "X min read" estimate, scroll position tracking

### Notification Rules
- [x] **Per-Feed Notification Settings** - Smart notification rules with feed, keyword, and author filters; three priority levels (High, Normal, Low)

### Visual Polish
- [x] **Transition Animations** - Article selection slide-in transition, fade when switching grouping modes, smooth scroll-to-selection
- [x] **Article Themes** - Six built-in themes (Auto, Light, Dark, Sepia, Paper, Night) with visual picker in Appearance settings

---

## Still To-Do

### Interaction Improvements

#### Quick Preview on Hover
Add a popover preview when hovering over articles in the list (like Mail.app's quick look), showing more of the summary without full selection.

#### Status Bar Enhancements
Expand the server status indicator to show:
- Number of new articles since last check
- Sync status with subtle animation

### Hardware Integration

#### Touch Bar Support
- Quick actions: next/previous, bookmark, mark read
- Feed switching

### Larger Features (Future)

#### Multiple Accounts / Sync Services
- Support Feedbin, Feedly, Inoreader
- iCloud sync for local accounts
- Account-specific settings

#### Safari Extension
- "Subscribe to Feed" from Safari toolbar
- Auto-detect RSS feeds on web pages
- Add directly to selected folder

#### Widgets
- macOS widget showing unread count
- Today widget with recent articles
- Starred articles widget

#### Handoff Support
- Support Handoff to iOS companion app (requires iOS app)
