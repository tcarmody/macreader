# DataPoints — Mac UX Backlog

Tracked plan derived from the [MACUX.md](MACUX.md) audit run on 2026-05-26.
Items are ordered by impact: silent bug risk → accessibility → visual
correctness → forward-looking polish. Tick each item as it lands.

Re-run the audit against [MACUX.md](MACUX.md) when a new UX surface
ships, then append new findings here.

---

## 1. Split Article + Library menus to stay under the 10-element `@CommandsBuilder` cap

**Status:** ✅ done (2026-05-26)

**Why this matters:** SwiftUI's `CommandMenu` silently drops items past
the 10th — no compile error, no runtime warning. Article menu had
**17 elements** (13 buttons + 4 dividers); Library menu had **14**.
MACUX.md §Menus explicitly flagged this as already at the limit.

**What changed:**
- Removed duplicate buttons from the Article menu: "Open Original"
  (identical to "Open in Browser") and "Copy Article URL" (identical
  to "Copy Link"). Both pairs invoked exactly the same code.
- Wrapped the remaining items in three `Group { … }` containers in
  both `CommandMenu("Article")` and `CommandMenu("Library")`. Each
  top-level `@CommandsBuilder` body now has 3 elements; the menu UI
  is unchanged because dividers stay in place inside the Groups.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 2. Remove Window-menu duplicates of canonical bindings

**Status:** ✅ done (2026-05-26)

**Why this matters:** The Window menu re-registered shortcuts that the
canonical scenes already own. Best case dead weight; worst case
SwiftUI binds the duplicate and the Settings scene's ⌘, breaks.

**What changed:**
- Deleted the entire `CommandGroup(after: .windowArrangement)` block
  in [RSSReaderApp.swift](app/DataPointsAI/DataPointsAI/App/RSSReaderApp.swift) —
  all three buttons (`Settings... ⌘,`, `Quick Open... ⌘K`,
  `Feed Manager... ⌥⌘F`) duplicated bindings already owned by the
  Settings scene, Go menu, and Feed menu respectively.
- Removed orphan `@Published var showSettings: Bool` from
  [AppState.swift](app/DataPointsAI/DataPointsAI/Models/AppState.swift) —
  the state was only written by the dead Window-menu button and
  never read.
- Dropped the duplicate `.keyboardShortcut("l", ⇧⌘)` from Library
  menu's "Open Library" — the View menu's "Show Library" toggle owns
  ⇧⌘L (it works in both enter and exit states).
- Dropped the duplicate `.keyboardShortcut("a", ⇧⌘)` from Library
  menu's "Add to Library..." — File menu's identical button owns
  ⇧⌘A.
- Gated the 5 Article↔Library context-sensitive pairs (⇧⌘S, ⇧⌘.,
  ⌥⌘T, ⌥⌘C, ⌘B) on `appState.showLibrary` via
  `.keyboardShortcut(condition ? KeyboardShortcut(...) : nil)`.
  Only the menu whose context is active claims the shortcut.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 3. Add `accessibilityLabel` everywhere `.help` exists

**Status:** ✅ done (2026-05-26)

**Why this matters:** MACUX.md §Accessibility says `.help` (sighted
tooltip) and `accessibilityLabel` (VoiceOver) must both exist. The
codebase had **53 `.help` calls and 0 `accessibilityLabel` calls** —
VoiceOver users heard nothing useful on icon-only toolbar buttons.

**What changed:**
- Added [HelpLabel.swift](app/DataPointsAI/DataPointsAI/Views/HelpLabel.swift),
  a tiny `View` extension exposing `.helpLabel(_:)` that sets both
  `.help` and `.accessibilityLabel` to the same text. Two overloads
  (LocalizedStringKey + StringProtocol) cover every existing call
  site, including the dynamic ones (e.g. `.helpLabel(feed.url.absoluteString)`,
  `.helpLabel(item.isRead ? "Mark as Unread" : "Mark as Read")`).
- Globally swept all 53 `.help(` call sites to `.helpLabel(`. No
  visual or interaction behavior changes — VoiceOver gains the
  paired label everywhere.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

**Future:** new icon-only controls should use `.helpLabel(...)` instead
of `.help(...)`. Worth noting in MACUX.md §Accessibility's first bullet.

## 4. Replace hand-picked colors with system colors + symbol pairing

**Status:** ✅ done (2026-05-26)

**Why this matters:** MACUX.md §Core postures says "system colors only."
Hand-picked `Color.blue` for "this is selected/unread" ignores the user's
accent personalization. Three identical-opacity colored dots in
[ArticleRow](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift)
distinguished summary / related / chat **by color alone**, defeating
color-blind and VoiceOver users.

**What changed:**
- **State-color → accent:** every `Color.blue` used for "unread,"
  "selected," or "active" became `Color.accentColor` so it follows the
  user's System Settings accent. Sites: [ArticleRow](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift)
  unread/multi-select dots, [ArticleDetailStatusBar](app/DataPointsAI/DataPointsAI/Views/ArticleDetail/ArticleDetailStatusBar.swift)
  read/unread indicator, [LibraryView](app/DataPointsAI/DataPointsAI/Views/LibraryView.swift)
  type-icon and type badge, [LibraryItemDetailView](app/DataPointsAI/DataPointsAI/Views/LibraryItemDetailView.swift)
  type badge, [QuickOpenView](app/DataPointsAI/DataPointsAI/Views/QuickOpenView.swift)
  unread badge, [FilterRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/FilterRow.swift) /
  [FeedRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/FeedRow.swift) /
  [NewsletterFeedRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/NewsletterFeedRow.swift) /
  [NewsletterHeader](app/DataPointsAI/DataPointsAI/Views/Sidebar/NewsletterHeader.swift) /
  [CategoryHeader](app/DataPointsAI/DataPointsAI/Views/Sidebar/CategoryHeader.swift)
  unread-count badges, [SetupWizardView](app/DataPointsAI/DataPointsAI/Views/SetupWizardView.swift)
  recommended/selected indicators, [ArticleListView](app/DataPointsAI/DataPointsAI/Views/ArticleListView.swift)
  group unread dot, [ArticleSummarySection](app/DataPointsAI/DataPointsAI/Views/ArticleDetail/ArticleSummarySection.swift)
  key-point bullets.
- **Color-only state → SF Symbol glyphs:** [ArticleRow](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift)
  activity dots became `sparkles` / `link` / `bubble.left.fill`
  glyphs in `.foregroundStyle(.secondary)`. [ArticleDetailView](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift)
  tab strip status dots became `checkmark` glyphs.
- **Blue micro-tint backgrounds → system materials:** `Color.blue.opacity(0.05)`
  backgrounds on the AI Summary section, chat container, and related
  links section became `.thinMaterial` with appropriate corner radii.
- **AI brand unified on purple:** the AI Summary label in both
  article and library detail views was `.blue` in places and `.purple`
  in others; all now `.purple` to match the chip + assistant chat
  avatar.
- **Empty-state document fills:** `Color.white` (absolute white in
  Dark Mode) → `Color(.controlBackgroundColor)` which adapts.

**Skipped intentionally:**
- Featured-callout purple in [ArticleDetailView](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift) —
  deliberate brand color, semantically distinct from accent so the
  callout doesn't blend into the article header gradient. SwiftUI's
  `Color.purple` adapts to Dark Mode.
- AI Summary chip / chat assistant avatar purple — same reason.
- Empty-state illustrations (`Color.brown` bookshelf, `Color.indigo`
  empty-library circle, `Color.gray` paper stack, `Color.green`
  caught-up celebration, `Color.orange` offline state, `Color.yellow`
  no-results hint) — decorative artwork, SwiftUI named colors that
  adapt. Not state indicators.
- `Color.black.opacity(0.3)` modal scrim in
  [MainView ServerStatusView](app/DataPointsAI/DataPointsAI/Views/MainView.swift#L412) — standard
  macOS / iOS modal-overlay pattern.
- OfflineBanner `.orange.opacity(0.9)` — `Color.orange` is the
  conventional warning color across Apple apps; it adapts.
- Star (`.yellow`) and bookmark (`.orange`) glyphs — Apple's
  conventional semantic colors for these specific roles (Finder, Mail,
  Safari Reader).

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 5. Bump SettingsView width to 540pt and split per-tab files

**Status:** ✅ done (2026-05-26)

**Why this matters:** MACUX.md §Settings prescribes ~520-540pt fixed
width. [SettingsView.swift](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift)
was 480pt and 2184 lines — explicitly flagged as ripe for splitting.

**What changed:**
- Width 480 → 540pt at [SettingsView.swift:40](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift#L40).
- Created [Views/Settings/](app/DataPointsAI/DataPointsAI/Views/Settings/) and moved each tab into its own file:
  - [GeneralSettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/GeneralSettingsView.swift) (165 lines)
  - [AppearanceSettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/AppearanceSettingsView.swift) (193 lines, includes `ThemePreviewButton`)
  - [AISettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/AISettingsView.swift) (168 lines)
  - [NewsletterSettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/NewsletterSettingsView.swift) (495 lines, includes Gmail helpers)
  - [NotificationRulesSettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/NotificationRulesSettingsView.swift) (557 lines, includes `NotificationHistoryRow`, `NotificationRuleRow`, `EditNotificationRuleSheet`)
  - [StatisticsSettingsView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/StatisticsSettingsView.swift) (373 lines, includes `StatRow`)
  - [AboutView.swift](app/DataPointsAI/DataPointsAI/Views/Settings/AboutView.swift) (35 lines)
- [SettingsView.swift](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift) shrank from 2184 → 210 lines — now just the `TabView` shell + load/save bridge + the `applySettingsChangeHandlers` View extension.
- Also fixed a leftover from item #4: `AboutView` newspaper icon was
  `.foregroundStyle(.blue)`; now `Color.accentColor`.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 6. `accessibilityElement(children: .combine)` on composite rows

**Status:** ✅ done (2026-05-26)

**Why this matters:** Composite rows (title + favicon + feed name +
time + state glyphs + bookmark + featured star) had VoiceOver walk
every leaf separately. One combined element per row + a single
descriptive label is the MACUX.md §Accessibility ask.

**What changed:** added `.accessibilityElement(children: .combine)` +
a dynamically-computed `.accessibilityLabel` to the six composite
row types:

- [ArticleRow](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift) —
  "{title}, from {feed}, {timeAgo}, Read/Unread, [Selected,]
  [Featured,] [Bookmarked,] [has summary,] [N related,] [has chat]"
- [LibraryItemRow](app/DataPointsAI/DataPointsAI/Views/LibraryView.swift) —
  "{name}, {type}, {timeAgo}, Read/Unread, [Bookmarked,]
  [has summary]"
- [FeedRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/FeedRow.swift) —
  "{name}, [N unread,] [health status,] [Selected]"
- [NewsletterFeedRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/NewsletterFeedRow.swift) —
  "Newsletter: {name}, [N unread,] [Selected]"
- [FilterRow](app/DataPointsAI/DataPointsAI/Views/Sidebar/FilterRow.swift) —
  "{filter name}, [N (unread)]"
- [QuickOpenFeedRow + QuickOpenArticleRow](app/DataPointsAI/DataPointsAI/Views/QuickOpenView.swift) —
  feed/article with source, read state, bookmark flag

Also picked up a stray `.foregroundStyle(.blue)` on the QuickOpen
feed icon → `Color.accentColor`.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 7. Replace `Image(systemName:)` toolbar buttons with `Label(_:systemImage:)`

**Status:** ✅ done (2026-05-26)

**Why this matters:** MACUX.md §Toolbars: in `.primaryAction` /
`.automatic` placement, SwiftUI renders icon + label when given a
`Label`. Buttons used bare `Image(systemName:)`, so the label text
never appeared — even when the user had Customize Toolbar set to
"Icon and Text."

**What changed:** every icon-only toolbar `Button { Image(...) }`
became `Button { Label(text, systemImage: ...) }`. Sites covered:

- [FeedListView.swift](app/DataPointsAI/DataPointsAI/Views/FeedListView.swift) —
  trash, clear-selection, add, refresh
- [LibraryView.swift](app/DataPointsAI/DataPointsAI/Views/LibraryView.swift) —
  filter, add-to-library
- [ArticleListView.swift](app/DataPointsAI/DataPointsAI/Views/ArticleListView.swift) —
  search-in-summaries, pin-search, sort, more-actions

Labels are concise (1-2 words) since the same text already appears
in `.helpLabel(...)` for the longer tooltip / VoiceOver line.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

## 8. Drop opaque background + manual divider under the article detail tab strip

**Status:** ✅ done (2026-05-26)

**Why this matters:** MACUX.md §Liquid Glass blockers. The opaque
`windowBackgroundColor` paint + manual `Divider()` under the tab
strip in [ArticleDetailView](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift)
would block macOS 26's automatic scroll-edge effect from rendering
under the floating toolbar plane. Fixing now costs nothing and
avoids cleanup at the macOS 26 bump.

**What changed:** removed both the
`.background(Color(NSColor.windowBackgroundColor))` and the manual
`Divider()` from `detailTabStrip(article:)`. The `VStack` wrapper
was no longer doing anything so collapsed it to just the `HStack`.

**Verified:** `xcodebuild -scheme DataPointsAI` reports `BUILD SUCCEEDED`.

---

## Smaller items, batch when convenient

### Done (2026-05-26 batch)

- ✅ **Delete orphan SearchBar.swift** — only referenced by its own
  `#Preview`; removed.
- ✅ **Enforce minimum window size** — `.frame(minWidth: 900,
  minHeight: 600)` on the `WindowGroup`'s `MainView()` (matches
  MACUX.md §Windows main-reading-window minimum).
- ✅ **Reader Mode toolbar placement** — moved to
  `ToolbarItem(placement: .navigation)` so the icon-only book toggle
  sits on the leading edge alongside other pane-state toggles.
- ✅ **Reader Mode shortcut conflict resolved** — dropped the View
  menu's ⇧⌘F binding (conflicted with the conventional ⌘F Find
  meaning). The bare `f` via [KeyboardShortcutManager](app/DataPointsAI/DataPointsAI/Services/KeyboardShortcutManager.swift)
  is now the single owner.
- ✅ **`.navigationSubtitle(...)` for transient status** — added
  `AppState.statusSubtitle: String?` (a computed property reading
  `serverRunning`, `isOffline`, `isSyncing`, `isClusteringLoading`)
  and wired `.navigationSubtitle(appState.statusSubtitle ?? "")` to
  [ArticleListView](app/DataPointsAI/DataPointsAI/Views/ArticleListView.swift)
  (which owns the window's `navigationTitle`). Surfaces
  "Connecting…", "Offline — reading cached articles", "Refreshing
  feeds…", "Clustering topics…" in the window subtitle.
- ✅ **AddFeedView → `Form`** — replaced the hand-rolled `VStack` +
  `.textFieldStyle(.roundedBorder)` block with a `Form { Section { … } }
  .formStyle(.grouped)` + a single bottom action bar. Now consistent
  with EditFeedView, FeatureArticleSheet, Settings sub-views, etc.

### Deferred

- **Centralize menu-bar shortcuts** in
  [KeyboardShortcutManager.swift](app/DataPointsAI/DataPointsAI/Services/KeyboardShortcutManager.swift).
  ~25 `.keyboardShortcut(…)` calls scattered inline in
  [RSSReaderApp.swift](app/DataPointsAI/DataPointsAI/App/RSSReaderApp.swift)
  remain. The refactor is purely organizational — single source of
  truth for shortcut chords, but no user-visible change. Worth doing
  before the next round of shortcut churn.
- **`isDocumentEdited` dot on unsaved sheets** (EditFeedView,
  newsletter editing). Requires tracking dirty state per sheet +
  hooking `NSApp.keyWindow?.isDocumentEdited = isDirty` + a
  Save/Discard confirmation on close. Non-trivial wiring; defer
  until the next sheet UX pass.
- **Sidebar transient state** — trash + clear-selection toolbar
  buttons in the sidebar when feeds are multi-selected. MACUX.md
  flags this but the alternative (multi-select-aware row context
  menus + ⌫ key handler + Edit menu actions) is bigger than a
  smaller-batch fix. Current UX is reasonable.

---

## Follow-up backlog after the shared-reader pass (2026-09-18)

The items below remain intentionally open after the feed/Library
unification. They are ordered by user impact and testability.

### 9. Add native search scopes for Articles and Library

**Status:** ☐ open

The search field now searches the active collection, but the title-bar
search does not yet expose a native scope control. Add `.searchScopes` for
`Articles`, `Library`, and (where useful) `All`, preserving the active scope
when switching panes. The scope must change the query source rather than
filtering already-returned results locally.

**Acceptance:** the scope is visible in the macOS search UI, ⌘F focuses the
same field, and changing scope never shows results from the wrong corpus.

### 10. Add a first-class Library drop target

**Status:** ☐ open

MACUX.md calls for drag-and-drop alongside the file picker. Accept dropped
URLs and supported documents in the Library list, show a visible drop state,
and reuse the existing upload/add URL flows. Reject unsupported types with a
recoverable message instead of silently ignoring them.

**Acceptance:** a URL dragged from Safari and a PDF dragged from Finder both
reach the same add flow as the corresponding menu commands; VoiceOver exposes
the drop target and its accepted content types.

### 11. Make appearance themes accessibility-aware

**Status:** ☑ implementation complete; manual settings verification remains

The reader themes retain their palettes while adding explicit Increase
Contrast and Reduce Transparency overrides at the shared HTML reader boundary.
Manual verification across every theme and system appearance combination
remains. Keep the system accent for controls and reserve theme colors for the
reading canvas.

**Acceptance:** text and links remain readable in all themes with Increase
Contrast enabled; no reading surface depends on translucency for contrast.

### 12. Complete VoiceOver and keyboard-focus QA for the new reader

**Status:** ☑ implementation complete; manual VoiceOver pass remains

The unified rows and toolbars now expose labels and hints, and the native
segmented reader tabs announce section changes. A manual VoiceOver and
keyboard-focus pass remains for empty states, asynchronous progress, visible
focus rings, and complete Tab order. Add further hints where an action has a
side effect (for example, “opens the Summary section and starts generation”).

**Acceptance:** VoiceOver announces the selected reader tab, loading/error
state, source, read state, and available actions without relying on color;
keyboard focus can reach every toolbar and tab control.

### 13. Verify macOS 27 toolbar and menu behavior on a signed app

**Status:** ☑ signed SDK 27 build verified; visual QA remains

Build and run the signed bundle on macOS 27 with the 27 SDK. Check toolbar
overflow, menu symbol visibility, title-bar search placement, sidebar widths,
scroll-edge behavior, dark mode, and window restoration. SwiftUI 27 changes
menu symbol rendering, so each action must remain understandable when its
symbol is hidden.

**Acceptance:** no primary action disappears into overflow at the minimum
window size; all menu items retain clear text labels; the app works with both
standard and customized toolbar configurations.

### 14. Persist reader state per item and restore it safely

**Status:** ☑ implemented; manual navigation verification remains

The reader now persists the selected section and per-section reading offset per
article/library item in a bounded cache, invalidates entries when content
length changes, and clamps offsets through the existing scroll-state restore.

**Acceptance:** returning to an item restores its section and approximate
position; switching users or deleting an item removes its saved state.

### 15. Add a hover quick preview for dense lists

**Status:** ☐ open

The shared row makes scanning consistent, but users still need to select an
item to inspect more summary text. Add an optional hover popover for pointer
users, while keeping selection and keyboard navigation unchanged. Do not make
the preview the only way to access content.

**Acceptance:** the preview is delayed, dismisses predictably, does not steal
keyboard focus, and is disabled or simplified for Reduce Motion / VoiceOver.

### 16. Improve transient sync feedback

**Status:** ☐ open

The window subtitle communicates broad status, but refresh completion and new
article counts are easy to miss. Add a subtle, non-blocking status treatment
for “N new articles,” failed sync, and retry, with an accessible announcement
and no permanent banner.

**Acceptance:** users can tell whether refresh succeeded, failed, or added
nothing without opening Settings or reading logs.

### 17. Add interaction tests around the shared reader

**Status:** ☑ command-line interaction coverage added

The backend Library search tests cover pagination, literal matching, and user
isolation. The macOS test host can now initialize the notification service
without touching UserNotifications. The first interaction tests cover stable
reader section order and shared plain-document rendering; extend them with
Library/feed keyboard routing, stale selection responses, and accessibility
tree assertions as the UI test host grows.
