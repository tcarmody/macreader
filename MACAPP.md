# DataPoints — Mac app decisions and findings

Companion to [MACUX.md](MACUX.md). That file holds the portable
guidelines; this one holds what's true of *this* app — where things
live, which conventions have already been chosen, and which
experiments were run so they aren't run again.

Read MACUX.md for the rule; read this for how DataPoints applies it.

The Mac app lives at
[app/DataPointsAI/DataPointsAI/](app/DataPointsAI/DataPointsAI/).
Deployment target: **macOS 15.7** (Sequoia). The Liquid Glass section
of MACUX.md is forward-looking — adopt it when the target moves to
macOS 26.

---

## Where things live

| Surface | Location |
|---|---|
| App entry, all menu bar `commands` | [App/RSSReaderApp.swift](app/DataPointsAI/DataPointsAI/App/RSSReaderApp.swift) |
| Three-pane shell, `.searchable` | [Views/MainView.swift](app/DataPointsAI/DataPointsAI/Views/MainView.swift) |
| Sidebar sub-views | [Views/Sidebar/](app/DataPointsAI/DataPointsAI/Views/Sidebar/) |
| Shared reader (feed + Library) | [Views/Components/ReaderDetailView.swift](app/DataPointsAI/DataPointsAI/Views/Components/ReaderDetailView.swift) |
| Settings panes | [Views/Settings/](app/DataPointsAI/DataPointsAI/Views/Settings/) |
| Keyboard chords | [Services/KeyboardShortcutManager.swift](app/DataPointsAI/DataPointsAI/Services/KeyboardShortcutManager.swift) |
| Reader theme palettes | [Models/ArticleTheme.swift](app/DataPointsAI/DataPointsAI/Models/ArticleTheme.swift) |

New sidebar surfaces go under `Views/Sidebar/`; new settings panes
under `Views/Settings/`.

## Menu layout

Custom `CommandMenu`s sit between View and Window: **Go, Article,
Feed, Library, Reader**. New feature areas should follow that
pattern rather than overloading the standard menus.

The Article and Feed menus are **already brushing the 10-element
`@CommandsBuilder` cap** and use `Group` wrappers to stay under it.
New items go into a sub-view, not appended at the end — items past
the tenth are silently dropped.

## Keyboard chords

All chords are registered in
[KeyboardShortcutManager.swift](app/DataPointsAI/DataPointsAI/Services/KeyboardShortcutManager.swift),
including a `KeyboardShortcut` extension for the reader actions.
Taken chords worth knowing before adding one:

```
⇧⌘E Export OPML     ⇧⌘R Refresh      ⇧⌘S Summarize    ⌘R Mark as Read
⌥⌘E Extract         ⌥⇧⌘E Extract with session
⌥⌘R Find Related    ⇧⌘P Send to Composer
```

That file also documents the vim-style single-key navigation set
(`j`/`k`/`n`/`o`/`r`/`u`/`s`/`b`/`g g`/`G`/`/`/`A`/`;`/`'`/`f`).

Summarize and Delete deliberately carry **no** chord in the Reader
menu — ⇧⌘S and ⌘⌫ are already owned by the Article and Library
menus, and one chord gets one owner.

## Reader actions

The seven reader actions (extract, extract with session, log in,
summarize, find related, send to composer, delete) are described
once in
[Models/ReaderAction.swift](app/DataPointsAI/DataPointsAI/Models/ReaderAction.swift)
— title, icon, section, chord, availability, enablement — and every
surface renders from that list:

- the reader's ellipsis overflow menu
- the Reader menu in the menu bar
- the end-of-article "Actions" panel
- the empty-content state (extraction paths only)

Adding a case to `ReaderAction.all` reaches all of them. Don't
hand-write an action into one surface.

Availability vs enablement differs by surface on purpose:
unavailable actions are **hidden** in the reader's own menus
(extraction is meaningless for a local PDF) but shown **disabled**
in the menu bar, because a menu bar that reshapes itself is
unlearnable.

## Article themes

The reader theme palettes (Manuscript, Noir, Ember, Forest, Ocean,
Midnight, plus Auto) are the sanctioned exception to MACUX.md's
"system colors only" rule. They must resolve dynamically via
`NSColor(name:dynamicProvider:)` so they still honor appearance
changes, and they need contrast-mode variants. See
[ArticleTheme.swift](app/DataPointsAI/DataPointsAI/Models/ArticleTheme.swift).

## Sheets in use

Edit Feed, Add to Library, Import OPML, Feature Article, Setup
Wizard, Gmail setup, Newsletter setup, Quick Open, Feed Manager.
Free-floating panels are not used — default to a sheet.

## Search

`.searchable` in
[MainView.swift](app/DataPointsAI/DataPointsAI/Views/MainView.swift)
owns article and Library search, with `.searchScopes` for the
corpus switch. The standalone
[SearchBar.swift](app/DataPointsAI/DataPointsAI/Views/Components/SearchBar.swift)
component is retained only for embedded contexts where
`.searchable` can't attach; it must not replace the toolbar search.

Search is always global. Clients must not re-apply a sidebar or
feed filter on top of results — see CLAUDE.md.

## Known state

- **`SettingsView.swift` is >2000 lines** and is a strong candidate
  for splitting into per-tab files when next touched.
- **Accessibility** has roughly 25 `accessibilityLabel` /
  `accessibilityHint` / `accessibilityElement` call sites, mostly
  in the reader and its rows. Coverage is partial; new surfaces
  should ship with them and older ones should gain them when
  touched. `HelpLabel.swift` provides the `.helpLabel(_:)` helper
  that sets `.help` and `.accessibilityLabel` together.

---

# Experiments already run — don't repeat these

## Customize Toolbar: tried and reverted (Sept 2026)

Toolbar customization does **not** persist in this app. It was
implemented, measured, and reverted.

Getting SwiftUI to enable it at all required all three of:

1. every column declaring items under one shared `.toolbar(id:)`;
2. every item a `ToolbarItem(id:)` with a globally unique id — one
   plain `.toolbar { }` anywhere in the window disables
   customization for all of it;
3. no conditionally rendered items — always declared, disabled when
   they don't apply.

With all three in place the toolbar reported
`identifier='datapoints-main-toolbar' cust=true autosave=true`, the
palette opened, and drags worked. But `defaults find` came back
**empty across every domain**, while Finder's own
`NSToolbar Configuration Browser` sat there in the classic format —
so the mechanism works on macOS, SwiftUI simply never writes a
configuration. Customizations vanish on relaunch.

Two costs made keeping it worse than dropping it:

- Rule 3 meant seven state-dependent buttons (delete-selection,
  pin-search, mark-selected, …) could no longer appear when they
  became relevant.
- Four permanently-visible items overflowed the sidebar's 240pt
  toolbar section, which clips silently — Refresh simply vanished
  until the sidebar was widened.

Reverted in `67b3851`. The columns are byte-identical to their
pre-refactor state.

## View menu flicker: mitigated, not fixed

Opening the View menu shows `Show Tab Bar`, `Show All Tabs` and
`Enter Full Screen`, then loses them a moment later. AppKit injects
those (three items plus a separator) when the menu opens; SwiftUI
re-syncs the main menu and they go.

**This is not driven by our state.** Two spikes ruled it out,
measured with a 200ms poller on the View submenu logging only on
change:

1. Every observable read stripped from the `commands` tree — 26
   `.disabled`, 10 conditional shortcuts, 3 dynamic titles, 2
   picker getters. Six opens, six collapses.
2. Plus `@StateObject appState` demoted to a plain `let`, removing
   the App body's blanket `objectWillChange` subscription — which
   is exactly what `@Observable` would give us. Four opens, four
   collapses.

So neither a narrow menu-state object nor migrating `AppState` to
`@Observable` would fix it. The `@Observable` migration may still be
worth doing for app-wide re-render cost — 56 `@Published`
properties currently mean any change re-renders every observing
view — but that's a performance argument, not a fix for this.

**Mitigation shipped:** `NSWindow.allowsAutomaticWindowTabbing =
false` in `applicationDidFinishLaunching`. DataPoints has a single
`WindowGroup` and no document model, so window tabs cost nothing to
give up, and the two tab items plus their separator are then never
injected. AppKit's injection drops from four items to one, measured.

`Enter Full Screen` still flickers. Declaring our own via
`toggleFullScreen(nil)` would survive the re-sync, but AppKit still
injects its copy, so that trades a disappearing item for a
duplicated one. Judged not worth it.

If menus ever become a real product surface — dynamic items built
from data, complex validation, scriptability — the durable answer is
owning the main menu in AppKit (`NSMenu` + `validateMenuItem`)
instead of `.commands`. That's a supported, if non-idiomatic,
approach for a SwiftUI app and would remove this whole class of
problem. It wasn't justified by cosmetic flicker alone.
