# Mac UI / UX / Accessibility Reference

The rules below distill Apple's Human Interface Guidelines (HIG),
the macOS 26 Liquid Glass design system, and the most-cited
community references into conventions a Mac app should follow.

**Consult this document before adding any new UX surface** (window,
sheet, panel, menu, toolbar, control). It is faster than re-deriving
the rules from Apple docs each time.

This file is deliberately app-agnostic — it should be portable to any
Mac app. Decisions, file locations, and findings specific to this
codebase live in [MACAPP.md](MACAPP.md).

The most useful external sources, in authority order:

1. [Apple HIG (root)](https://developer.apple.com/design/human-interface-guidelines/) and component pages (`toolbars`, `sidebars`, `menus-and-actions`, `windows`, `settings`, `foundations/accessibility`).
2. [Build an AppKit app with the new design — WWDC25 #310](https://developer.apple.com/videos/play/wwdc2025/310/) and [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
3. [Macintosh Checklist (Mario Guzman)](https://marioaguzman.github.io/design/macintoshchecklist/) — concrete numerics.
4. [macOS Settings Window Guidelines (usagimaru)](https://zenn.dev/usagimaru/articles/b2a328775124ef?locale=en) — preferences-pane specifics.

The HIG pages are JS-rendered and don't reverse-proxy cleanly to
agent tooling; open them in a browser when in doubt.

---

## Core postures

These are non-negotiable for a Mac app — every new surface should
inherit them by default:

- **Menu bar is primary.** Every action a user might reach for
  must be in the menu bar, even when it's also on a toolbar,
  context menu, or keyboard shortcut. Users who can't find a
  feature look in the menu bar before anywhere else. Give each
  feature area its own `CommandMenu` when the standard menus don't
  accommodate it.
- **Settings is modeless.** No Save / Cancel / Apply buttons.
  Changes commit immediately via `@AppStorage` / bindings. ⌘,
  opens it; Esc or ⌘W closes it.
- **Single main window** unless the app is genuinely document-based.
  If you add a per-document surface, key the `WindowGroup` on a
  value so reopening the same item surfaces the existing window
  rather than duplicating.
- **Toolbars carry primary actions**, in the titlebar, as real
  `.toolbar { … }` content — not as in-content `HStack`s of
  buttons. On macOS 26 the toolbar is the Liquid Glass plane.
- **Sidebars carry navigation**, not filters or transient state.
  Filters belong in a toolbar picker or `.searchable` scope.
- **Drag-drop is a first-class input** alongside menu / picker
  flows. The drop target should give clear visual feedback while
  hovered.
- **System colors only** (`.controlAccentColor`, `.labelColor`,
  `.windowBackgroundColor`, etc.). Hand-picked hex values defeat
  Dark Mode, Increase Contrast, and accent-color personalization.
  Reading-surface theme palettes are a legitimate exception, but
  must resolve dynamically via `NSColor(name:dynamicProvider:)` so
  they still honor appearance changes.

## Menus

- **Required structure:** App, File, Edit, View, Window, Help.
  App-specific menus go between Edit and View (e.g. Format,
  Insert) or between View and Window.
- **Ellipsis (`…`)** on any item that opens further UI: dialogs,
  sheets, secondary windows, file pickers. No ellipsis on items
  that perform their action immediately.
- **Title case** for menu titles and items. Never ALL CAPS except
  for acronyms.
- **Standard shortcuts** for standard actions: ⌘N New, ⌘O Open,
  ⌘S Save, ⇧⌘S Save As, ⌘W Close, ⌘P Print, ⌘F Find, ⌘G Find Next,
  ⌘Z / ⇧⌘Z Undo / Redo, ⌘Q Quit, ⌘, Settings, ⌘? Help.
- **Avoid system-reserved chords**: `⌃⌘[`, `⌃⌘]`, and similar are
  silently dropped by SwiftUI's `CommandMenu`. Default to
  `⌥⌘<arrow>` or `⇧⌘<letter>` when standard shortcuts don't apply.
- **`@CommandsBuilder` has a 10-element cap** per group. Wrap
  longer groups in sub-Views — items past the 10th are silently
  dropped. (`ViewBuilder` no longer has this limit; the cap is
  specific to the commands builder.)
- **Disabled items**: gray them out rather than hiding. Hiding
  makes users think the feature was removed.
- **Contextual menus** should mirror the items that would
  otherwise be in the menu bar's most-relevant menu, not invent
  new actions. A row's context menu mirrors the menu that owns
  that object type.
- **Centralize shortcut definitions** in one place so the menu bar,
  toolbar, and any in-content hotkey handlers agree rather than
  drifting.
- **One canonical owner per chord.** When the same action appears
  in several menus, bind the key in exactly one of them and leave
  the others bare — duplicate bindings on a single chord are
  resolved unpredictably.

## Toolbars

- Use `.toolbar { ToolbarItemGroup(placement: …) { … } }` —
  always a real toolbar, never an in-content `HStack`.
- **Placement determines label visibility** — and that's
  intentional, not a bug to work around:
  - `.primaryAction` / `.automatic` (trailing-edge actions like
    Save, Share, Export) — render icon + label by default. Use
    `Label(_:systemImage:)` and let SwiftUI do both. This is what
    HIG means by "icon + label is the macOS default."
  - `.navigation` (leading-edge view toggles like sidebar /
    inspector / pane visibility) — render icon-only by default.
    This is the macOS convention; Mail, Notes, Pages, Xcode, and
    Finder all do it. Don't move pane toggles to `.primaryAction`
    to "fix" the icon-only rendering — the icons there are
    conventional and tooltips + accessibility labels carry the
    meaning.
- **Icons** must come from SF Symbols. Pane / sidebar / inspector
  toggles in `.navigation` should use the standard symbols
  (`sidebar.left`, `sidebar.right`, `text.alignleft`, `eye`, etc.)
  so users recognize them from other apps.
- **Order:** primary actions on the leading edge, search and
  utility on the trailing edge, separators between logical groups.
- **`.help()` tooltip** on every toolbar item — covers users who
  hide labels, and provides VoiceOver text.
- **No more than ~5–7 default items** before requiring Customize
  Toolbar. Beyond that, the user can't scan the row.
- **Symbols** must come from SF Symbols, sized via `.imageScale`
  not hard-coded fonts, so they scale with the user's control-size
  preference.
- **A `NavigationSplitView` column clips its toolbar section
  silently** when it runs out of width — no overflow chevron, the
  button is simply gone. A sidebar at its default width fits about
  two items. Budget accordingly.

## Known SwiftUI / AppKit limitations

Framework behaviour that no amount of app-side design fixes. Check
here before spending time on a workaround.

- **Toolbar customization doesn't persist.** `NavigationSplitView`
  merges every column's `.toolbar` into one `NSToolbar`. Getting
  `allowsUserCustomization` and `autosavesConfiguration` to turn on
  at all requires one shared `.toolbar(id:)` across every column,
  globally unique `ToolbarItem(id:)`s, and no conditionally
  rendered items. Even then SwiftUI never writes a configuration,
  so customizations are lost on relaunch. Treat Customize Toolbar
  as unavailable in a SwiftUI `NavigationSplitView` app.
- **`ForEach` is not `CustomizableToolbarContent`** — SwiftUI
  resolves it as a `ViewBuilder` and the build fails with a wall of
  unrelated conformance notes. List `ToolbarItem(id:)`s explicitly.
- **SwiftUI discards AppKit's injected menu items.** AppKit adds
  `Show Tab Bar`, `Show All Tabs` and `Enter Full Screen` to the
  View menu when it opens; SwiftUI re-syncs the main menu on its
  own schedule and they disappear. This is *not* driven by your
  observable state — removing every state dependency, including the
  `@StateObject` subscription on the `App` struct, does not stop
  it, so migrating to `@Observable` won't help either.
  `NSWindow.allowsAutomaticWindowTabbing = false` removes three of
  the four items for any app that doesn't use window tabs; the
  full-screen item keeps flickering.

## Sidebars

- Use `NavigationSplitView { sidebar } detail: { … }` for the main
  editor-style window with a tree, or an `HSplitView` with a
  list-style pane for browse surfaces.
- **Width:** min 220pt, ideal 260–280pt, max 320–360pt. The
  Macintosh Checklist suggests min 225–275, max 350–400 — stay in
  that range.
- **Collapsible** via a toolbar `Toggle` and the default ⌃⌘S
  sidebar chord. Persist the state via `@AppStorage`.
- **Source-list style** (`.listStyle(.sidebar)`) for hierarchical
  navigation; **inset grouped** for flat-list inspectors.
- **Counts as trailing badges**, never as parenthetical text in
  the row label.
- **Sections** use disclosure groups with persisted expand state.
  Read once at view init and write via explicit `.onChange` —
  never let `@AppStorage` participate in a `List(selection:)`
  render loop, as it causes selection thrash and infinite
  re-renders.

## Windows

- **Title** identifies the document or surface. **Subtitle** (via
  `.navigationSubtitle`) carries transient status (Refreshing…,
  Summarizing…, Save failed: …) — never the title repeated.
- **Minimum size:** ~480×320pt for utility windows, 620×380pt for
  browse surfaces, 900×600pt for a main content window.
- **Document-edited dot** in the red close button via
  `window.isDocumentEdited = isDirty` when a sheet has unsaved
  edits. Close-with-unsaved triggers a standard Save / Discard
  Changes / Cancel alert.
- **Multi-instance** `WindowGroup(for: URL.self)` for detached
  per-item windows — opening the same item should surface the
  existing window rather than duplicating.
- **State restoration** for window position and size is automatic
  from `WindowGroup`; explicit `@SceneStorage` for per-window
  panel-visibility flags (e.g. sidebar / inspector show-hide).
- **Full-screen** is supported by default for content windows.
  Inspector or accessory panels shouldn't follow into full-screen.

## Settings

- `Settings { … }` scene, accessible via ⌘,. TabView with
  `.tabItem { Label("Tab", systemImage: "…") }` per pane.
- **Both icon AND label** per tab — required for VoiceOver and
  for the truncation behavior when the window narrows.
- **Conventional tab order:** general behavior first, advanced /
  AI / debug last. Restore the last-viewed tab on reopen via
  `@AppStorage`.
- **Centered Form layout** (`.formStyle(.grouped)`) with
  `Section("…")` headings, right-aligned label column, controls on
  the trailing side. Descriptions go below in a `.callout` /
  `.secondary` foreground.
- **Fixed width** (~520–540pt). Height can vary by pane but
  shouldn't change wildly between tabs in the same window —
  flicker on tab switch is jarring.
- **No Save / Cancel / Apply buttons.** Bindings commit
  immediately.
- **Keep parity across panes.** A pane that's an order of
  magnitude longer than its siblings should probably split into
  two panes.

## Sheets, panels, alerts

- **Sheets** for window-modal flows that complete a single task.
  Sheets must have a clear primary action button and a Cancel
  button; Esc cancels.
- **Alerts** (`.alert(…)`) for confirmations and error reporting.
  Destructive actions get the `role: .destructive` button modifier
  for the red text + right-side placement.
- **Confirmation dialogs** (`.confirmationDialog`) for multi-choice
  destructive decisions (Unsubscribe / Move to Archive / Cancel).
- **Free-floating panels** (`Window` scene with `.windowStyle`
  configured) for accessory tools that should stay visible across
  app switches. Default to sheets unless the tool genuinely needs
  to persist.
- **Progress sheets** show determinate progress when total is
  known; cancellable when the work can be interrupted; surface
  per-item failure lists rather than a generic "some items failed."

## Search

- **`.searchable(text: $query)`** is the right answer for any
  filter-this-collection interaction. Lands in the titlebar on
  macOS 26, gets glass treatment, has a native clear button, and
  binds ⌘F.
- **Avoid custom search capsules.** They look native at first but
  miss the system styling that ships with `.searchable` on macOS
  26 — and they don't participate in keyboard navigation out of
  the box. A standalone search component is acceptable only for
  embedded contexts where `.searchable` can't attach (e.g. inside
  a sheet); it should not replace the toolbar search.
- **Scope chips** (`.searchScopes`) for multi-corpus filters.

## Liquid Glass and macOS 26 (forward-looking)

If the deployment target is below macOS 26, the Liquid Glass
treatment doesn't apply yet. When the target moves to macOS 26
Tahoe, adoption is mostly automatic when built with Xcode 26 — but
several things have to **not** be in the way:

- **Don't paint opaque backgrounds** on the window's root view.
  `Color(nsColor: .windowBackgroundColor)` over the full body
  blocks the floating-glass treatment macOS 26 applies to toolbars
  and sidebars. Let the system render the chrome over the content.
- **Don't insert manual `Divider()`s under the toolbar.** macOS 26
  uses the **scroll edge effect** — a fade or hard backing that
  appears automatically as content scrolls under the floating
  toolbar. A manual divider competes with this.
- **Extend content edge-to-edge.** Toolbar and sidebar sample
  through; padding the content away from the window edges defeats
  the effect.
- **Remove legacy `NSVisualEffectView`** from sidebars when you
  encounter them. They block glass.
- **Glass goes only on the navigation layer** (toolbar, sidebar,
  floating controls) — never on content (lists, tables,
  scrollable areas). Avoid stacking glass over glass.
- **Tinting:** use accent only for primary actions. Secondary /
  tertiary controls stay un-tinted. Destructive uses the system
  red role, not a hand-picked color.

Until the target moves, write SwiftUI that's HIG-compliant on
both targets and gate any glass-specific code paths with
`@available(macOS 26.0, *)`.

## Accessibility

Every new surface should ship with these from day one, and existing
surfaces should get them whenever they're touched.

- **VoiceOver labels** on every icon-only control. The convention
  is: `.accessibilityLabel("…")` mirrors the `.help("…")` copy.
  `.help` is for sighted-user tooltips; `accessibilityLabel` is
  for VoiceOver. Both are needed — a single helper that sets both
  at once keeps them from drifting.
- **`.accessibilityHint("…")`** for non-obvious actions ("Opens
  the chat panel for this article").
- **Composite rows** (list rows with several labels, images,
  badges) use `accessibilityElement(children: .combine)` so
  VoiceOver reads the row as one element rather than walking every
  subview separately.
- **Keyboard focus** reaches every interactive surface. Add
  `.focusable()` on custom hit areas (drop zones, theme rows,
  custom pickers). Tab key should walk the whole UI; focus ring
  uses the system color, never custom.
- **Color contrast:** rely on system colors. They satisfy WCAG AA
  against the matching background by design.
- **Don't rely on color alone** to convey state. Status indicators
  should pair color with a distinct symbol and text.
- **Reduce Motion** is respected automatically by SwiftUI
  transitions; custom `withAnimation` blocks should check
  `@Environment(\.accessibilityReduceMotion)` for any
  non-decorative motion.
- **Reduce Transparency** falls out of Liquid Glass automatically
  on macOS 26 — glass becomes frostier, no extra code.
- **Increase Contrast** likewise — system colors switch to
  high-contrast variants. Any custom palette needs explicit dark /
  light variants and, ideally, contrast-mode variants too.
- **Dynamic Type:** use `Font.system(.body)` / `.title`, never
  hard-coded point sizes.

## Anti-patterns

- Hamburger menu. The menu bar exists for this.
- iOS-style tab bars (`TabView` rendered as bottom tabs). Use
  sidebars or document tabs.
- Buttons styled to look like links.
- Modal-blocking on routine state changes — settings, sort order,
  filter changes should never gate the UI.
- Hidden disabled controls. Show them disabled instead.
- Hand-rolled "preferences sheets" that aren't the `Settings`
  scene. ⌘, must open Apple's standard window.
- Per-app accent overrides that ignore the user's System Settings
  accent. Reading themes are fine as long as they remix the
  accent rather than replacing it.
- In-content search fields that duplicate the toolbar
  `.searchable`. Pick one per surface.

## Pre-flight checklist for new UX

Before merging a new window, sheet, panel, toolbar, or menu:

1. **Menu bar:** is there an item to reach this action from the
   menu bar? If no, add one to the most relevant menu or create a
   new `CommandMenu`.
2. **Keyboard shortcut:** is the action one users will repeat? If
   yes, give it a shortcut — but only from the standard set or
   `⌥⌘<key>` / `⇧⌘<letter>` range, registered wherever the app
   centralizes its chords.
3. **VoiceOver:** every icon-only button has
   `.accessibilityLabel`. Every composite row uses
   `accessibilityElement(children: .combine)`.
4. **Tab key:** focusable hits reach the surface; Tab walks
   through them in reading order.
5. **Tooltips:** `.help("…")` on toolbar items, icon buttons, and
   non-obvious controls. Same copy as the VoiceOver label.
6. **System colors:** no hard-coded hex.
7. **Liquid Glass readiness:** no opaque background paints over
   the window root; no manual dividers under the toolbar. Applies
   even before moving to macOS 26 — it costs nothing now and
   avoids cleanup later.
8. **Ellipsis discipline:** every action that opens further UI
   ends in `…`; immediate-effect actions don't.
9. **Standard shortcuts:** ⌘, opens Settings, ⌘F opens search,
   ⌘W closes the window, Esc cancels modal flows.
10. **Build target:** SwiftUI APIs used are available on the
    deployment target, or gated with `@available(macOS 26.0, *)`
    for glass-only paths.

When in doubt: open the same surface in Mail, Notes, or Pages and
copy what Apple did. Those three are the most-current reference
implementations of the HIG.
