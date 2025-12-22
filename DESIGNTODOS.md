# Design Improvement TODOs

Future UI/UX improvements to consider for the macOS RSS reader app.

## Implemented Features

### Reading Experience
- [x] **Article Font & Line Spacing Settings** - Customizable font sizes and line spacing
- [x] **Typeface Selection** - System and custom font options for UI and content

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

## Still To-Do

### Reading Experience

#### Reading Progress Indicator
For long articles, show:
- A thin progress bar at the top of the article view
- "X min read" estimate based on word count
- Resume position when returning to partially-read articles

#### Reader Mode Toggle
Add a distraction-free reading mode that:
- Hides the sidebar and article list
- Centers content with optimal reading width
- Uses clean, book-like typography

### Interaction Improvements

#### Quick Preview on Hover
Add a popover preview when hovering over articles in the list (like Mail.app's quick look), showing more of the summary without full selection.

### Visual Polish

#### Transition Animations
- Animate article selection transitions
- Add subtle fade when switching between grouping modes
- Smooth scroll-to-selection

#### Status Bar Enhancements
Expand the server status indicator to show:
- Number of new articles since last check
- Sync status with subtle animation

### Hardware Integration

#### Touch Bar Support
- Quick actions: next/previous, bookmark, mark read
- Feed switching

### Medium Effort Features

#### Per-Feed Notification Settings
- Toggle notifications on/off per individual feed
- Accessible from feed context menu
- Store preference in database

#### Feed Reordering
- Drag to reorder feeds within a folder
- Persist custom sort order

#### Window Layout Persistence
- Remember panel widths on quit
- Restore scroll position in article list
- Restore last selected article

### Larger Features (Future)

#### Multiple Accounts / Sync Services
- Support Feedbin, Feedly, Inoreader
- iCloud sync for local accounts
- Account-specific settings

#### Safari Extension
- "Subscribe to Feed" from Safari toolbar
- Auto-detect RSS feeds on web pages
- Add directly to selected folder

#### Article Themes
- Multiple built-in reading themes
- Support custom CSS themes
- Dark mode specific themes

#### Widgets
- macOS widget showing unread count
- Today widget with recent articles
- Starred articles widget

#### Handoff Support
- Support Handoff to iOS companion app (requires iOS app)
