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

**Status:** pending

**Why this matters:** MACUX.md §Accessibility says `.help` (sighted
tooltip) and `accessibilityLabel` (VoiceOver) must both exist. Today
there are **53 `.help` calls and 0 `accessibilityLabel` calls** in the
entire Mac app. VoiceOver users currently hear nothing useful on
icon-only toolbar buttons.

**Where:** every icon-only `Button { Image(systemName: …) }`. Search:

```bash
grep -rn "\.help(" app/DataPointsAI/DataPointsAI/ --include="*.swift"
```

**Fix recipe:** for each `.help("X")` add a matching
`.accessibilityLabel("X")`. Same copy. One PR can do all 53.

## 4. Replace hand-picked colors with system colors + symbol pairing

**Status:** pending

**Why this matters:** MACUX.md §Core postures says "system colors only."
Hand-picked `Color.purple/blue/orange/yellow` defeat Dark Mode auto-
resolution, Increase Contrast, accent personalization, and (eventually)
Liquid Glass tinting.

**Worst offenders:**
- [ArticleDetailView.swift:178](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift#L178), [:239, :241, :243, :384, :387, :399, :402](app/DataPointsAI/DataPointsAI/Views/ArticleDetailView.swift#L239) — AI Summary chip + chat bubbles use `Color.purple` and `.foregroundStyle(.white)`. Replace with `.accentColor` or the `sparkles` symbol semantic color.
- [ArticleRow.swift:41, :47](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift#L41-L47) — unread/selected dot uses `Color.blue`. Should use `.tint` / `.accentColor`.
- [ArticleRow.swift:80](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift#L80) `.yellow` featured star, [:86](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift#L86) `.orange` bookmark — system role colors (`.yellow` is fine if a system role, `.orange` is not).
- [ArticleRow.swift:92-98](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift#L92-L98) — activity dots (`Color.purple/blue.opacity`) distinguish summary/related/chat **by color alone**. Add a glyph or text pairing per MACUX.md §Accessibility.
- [ArticleRow.swift:27](app/DataPointsAI/DataPointsAI/Views/Components/ArticleRow.swift#L27) — `NSColor.yellow.withAlphaComponent(0.5)` search highlight. Use `.findHighlightColor` or `.selectedTextBackgroundColor`.
- [MainView.swift:412](app/DataPointsAI/DataPointsAI/Views/MainView.swift#L412) — `Color.black.opacity(0.3)` overlay backing. Replace with `.regularMaterial` / `.thinMaterial`.
- [MainView.swift:516-517](app/DataPointsAI/DataPointsAI/Views/MainView.swift#L516-L517) — `OfflineBanner` uses `.orange.opacity(0.9)` + `.white`. Use a system warning role.
- [LibraryView.swift](app/DataPointsAI/DataPointsAI/Views/LibraryView.swift), [LibraryItemDetailView.swift](app/DataPointsAI/DataPointsAI/Views/LibraryItemDetailView.swift), [ArticleListView.swift](app/DataPointsAI/DataPointsAI/Views/ArticleListView.swift), [QuickOpenView.swift](app/DataPointsAI/DataPointsAI/Views/QuickOpenView.swift), [SetupWizardView.swift](app/DataPointsAI/DataPointsAI/Views/SetupWizardView.swift), [SettingsView.swift:2118](app/DataPointsAI/DataPointsAI/Views/SettingsView.swift#L2118) — assorted `Color.blue/gray/indigo/brown/green.opacity(…)` background tints.

[ArticleTheme.swift](app/DataPointsAI/DataPointsAI/Models/ArticleTheme.swift) `Color(red: …, green: …, blue: …)` palettes stay
as-is — MACUX.md §Core postures lists article themes as the documented
exception, provided they resolve dynamically via `NSColor(name:
dynamicProvider:)`.

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
