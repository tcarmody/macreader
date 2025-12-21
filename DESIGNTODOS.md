# Design Improvement TODOs

Future UI/UX improvements to consider for the macOS RSS reader app.

## Reading Experience

### Reading Progress Indicator
For long articles, show:
- A thin progress bar at the top of the article view
- "X min read" estimate based on word count
- Resume position when returning to partially-read articles

### Reader Mode Toggle
Add a distraction-free reading mode that:
- Hides the sidebar and article list
- Centers content with optimal reading width
- Uses clean, book-like typography

## Interaction Improvements

### Quick Preview on Hover
Add a popover preview when hovering over articles in the list (like Mail.app's quick look), showing more of the summary without full selection.

### Drag & Drop
- Drag feeds between categories
- Drag articles to save or mark read

## Visual Polish

### Empty State Illustrations
Add friendly illustrations to empty states (no articles, no feeds) rather than just text and icons.

### Transition Animations
- Animate article selection transitions
- Add subtle fade when switching between grouping modes
- Smooth scroll-to-selection

### Status Bar Enhancements
Expand the server status indicator to show:
- Last refresh time
- Number of new articles since last check
- Sync status with subtle animation

## Sharing & Integration

### Improved Share Sheet
- Add "Copy Summary" option
- Share with AI-generated summary included

### Touch Bar Support
- Quick actions: next/previous, bookmark, mark read
- Feed switching

## NetNewsWire-Inspired Features

Features observed in NetNewsWire that would enhance this app.

### High Value / Easy to Add

#### Smart Feeds
Add virtual "smart feeds" in the sidebar:
- **Today** - Articles published in the last 24 hours
- Integrate with existing Unread, Bookmarked, Summarized filters

#### Read Filter Toggle
- Add toolbar button to hide/show read articles per feed
- Visual indicator when filter is active
- Per-feed persistence of this setting

#### Mark Older/Below as Read
- Context menu: "Mark Articles Above as Read"
- Context menu: "Mark Articles Below as Read"
- Useful for catching up on feeds

#### Copy Article URL
- Dedicated keyboard shortcut (e.g., `Cmd+Shift+C`)
- Copy both article URL and source URL options

#### Go to Next Unread (`n` key)
- Skip already-read articles when navigating
- Works across feeds (jump to next feed with unread)

### Medium Effort

#### Article Extraction Toggle
- Button to switch between feed content and extracted full article
- Cache extracted content for offline reading
- Show extraction state (loading, complete, error)

#### Per-Feed Notification Settings
- Toggle notifications on/off per individual feed
- Accessible from feed context menu
- Store preference in database

#### Expand/Collapse All Folders
- Keyboard shortcuts: `;` (collapse all), `'` (expand all)
- Useful for users with many feed categories

#### Drag & Drop Feed Organization
- Drag feeds between folders
- Drag to reorder feeds within a folder
- Visual drop indicators

#### Window State Persistence
- Remember panel widths on quit
- Restore selected feed/folder
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

#### Spotlight Integration
- Index articles for macOS Spotlight search
- Support Handoff to iOS companion app
