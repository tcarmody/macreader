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

**Status:** pending

**Why this matters:** MACUX.md §Settings prescribes ~520-540pt fixed
width. [SettingsView.swift](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift)
is 480pt and 2184 lines — explicitly flagged in MACUX.md as ripe to
split when next touched.

**Where:** [SettingsView.swift:40](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift#L40)
`.frame(width: 480, height: 500)`.

**Fix recipe:**
1. Change width to 540, keep height 500 (or remove fixed height
   entirely if pane content varies smoothly).
2. Each `TabView` pane already lives in its own struct
   (`GeneralSettingsView`, `AppearanceSettingsView`, etc.) — move
   each to its own file under
   `app/DataPointsAI/DataPointsAI/Views/Settings/`.
3. Leave `SettingsView` itself as the thin `TabView` shell + the
   `loadSettings/saveSettings` bridge.

## 6. `accessibilityElement(children: .combine)` on composite rows

**Status:** pending

**Why this matters:** Each [ArticleRow](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift),
`FeedRow`, and `LibraryItemRow` is title + favicon + feed name + time +
3 state dots + bookmark + featured star. VoiceOver currently walks
every leaf separately. MACUX.md §Accessibility wants one combined
element per row.

**Fix recipe:** wrap the row's outermost `VStack`/`HStack` with
`.accessibilityElement(children: .combine)` and provide an
`.accessibilityLabel` that includes title + source + read state +
flags.

## 7. Replace `Image(systemName:)` toolbar buttons with `Label(_:systemImage:)`

**Status:** pending

**Why this matters:** MACUX.md §Toolbars: in `.primaryAction` /
`.automatic` placement, SwiftUI renders icon + label when given a
`Label`. Today buttons use bare `Image(systemName:)`, so the label
text never appears — even when the user has enabled "Icon and Text"
in Customize Toolbar.

**Where:**
- [FeedListView.swift:231, :238, :272, :283](app/DataPointsAI/DataPointsAI/Views/FeedListView.swift#L231) — trash, clear, plus, refresh
- [LibraryView.swift:53, :61](app/DataPointsAI/DataPointsAI/Views/LibraryView.swift#L53) — filter, add
- [ArticleListView.swift:56, :67, :89](app/DataPointsAI/DataPointsAI/Views/ArticleListView.swift#L56) — search modifiers, sort, more menu

`ArticleDetailView` already uses `Label(…)` correctly — use that as
the reference pattern.

## 8. Drop opaque background + manual divider under the article detail tab strip

**Status:** pending

**Why this matters:** MACUX.md §Liquid Glass blockers. We don't ship
on macOS 26 yet, but the doc says "applies even before we move to
macOS 26 — it costs nothing now and avoids cleanup later."

**Where:**
- [ArticleDetailView.swift:209](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift#L209) — `Color(NSColor.windowBackgroundColor)` paint under the tab strip
- [ArticleDetailView.swift:211](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift#L211) — manual `Divider()` under the tab strip

**Fix recipe:** delete both, let the natural window backing and
SwiftUI's built-in scroll edge effect handle it.

---

## Smaller items, batch when convenient

- **Centralize menu-bar shortcuts** in
  [KeyboardShortcutManager.swift](app/DataPointsAI/DataPointsAI/Services/KeyboardShortcutManager.swift).
  Today ~25 `.keyboardShortcut(…)` calls are scattered inline in
  [RSSReaderApp.swift](app/DataPointsAI/DataPointsAI/App/RSSReaderApp.swift).
  MACUX.md §Menus wants them in one place so the menu bar, toolbar,
  and in-content hotkey handlers can't disagree.
- **Use `.navigationSubtitle(…)`** for "Refreshing feeds…",
  "Summarizing…", "Server starting…" status. Today they surface via
  overlays/banners; MACUX.md §Windows says the subtitle slot is the
  right home.
- **`isDocumentEdited` dot** on sheets that have unsaved edits
  (EditFeedView, AddFeedView). Today close-with-unsaved doesn't
  trigger a Save/Discard alert.
- **Enforce minimum window size** via `.frame(minWidth:, minHeight:)`
  on the `WindowGroup`. MACUX.md §Windows prescribes 900×600 for the
  main reading window.
- **Delete or use the orphan [SearchBar.swift](app/DataPointsAI/DataPointsAI/Views/Components/SearchBar.swift)** —
  only referenced by its own `#Preview`.
- **AddFeedView is a hand-rolled `VStack`** ([MainView.swift:417-491](app/DataPointsAI/DataPointsAI/Views/MainView.swift#L417-L491)) —
  convert to `Form { … }` for consistency with other sheets.
- **Reader Mode toggle in toolbar should sit at `.navigation`
  placement** ([ArticleDetailView.swift:962-972](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift#L962-L972)) —
  it's a pane-state toggle, which MACUX.md §Toolbars puts on the
  leading edge.
- **Reader Mode shortcut conflict** — menu uses ⇧⌘F, but ⌘F is
  reserved for Find. Toolbar tooltip says `(f)` (single-key, handled
  via `KeyboardShortcutManager`). Pick one binding and standardize.
- **Sidebar toolbar holds transient state** (trash + clear-selection
  when a feed selection exists) — MACUX.md §Sidebars says "carry
  navigation, not transient state." Move to a contextual menu instead.
