import SwiftUI

/// In-flight reader operations. An action that would collide with a running
/// operation disables itself rather than queueing a second request.
///
/// Only surfaces inside the reader know these — the menu bar sees the
/// selected item but not the view's local task state, so it gates on
/// availability alone (`ReaderActivity.idle`), exactly as it did before.
struct ReaderActivity: Equatable {
    var isFetching = false
    var isSummarizing = false
    var isFindingRelated = false
    var isPromoting = false

    static let idle = ReaderActivity()
}

/// One reader action, described once and rendered by every surface that
/// offers it: the reader toolbar, its overflow menu, the Reader menu in the
/// menu bar, and the empty-content state. Title, icon, section, chord,
/// availability, and enablement live here so those surfaces cannot drift.
///
/// Adding a case to `all` reaches all of them at once.
struct ReaderAction: Identifiable {
    /// Divider-separated runs, rendered in declaration order.
    enum Section: CaseIterable {
        case source        // getting the text in the first place
        case intelligence  // what we do with the text once we have it
        case destructive
    }

    let id: String
    let command: ReaderCommand
    let section: Section
    let systemImage: String
    /// Chords come from `KeyboardShortcut` extensions in
    /// KeyboardShortcutManager.swift — see MACUX.md §Keyboard Shortcuts.
    /// `nil` means another menu already owns the canonical binding
    /// (Summarize is ⇧⌘S on Article/Library; Delete is ⌘⌫ on Library).
    let shortcut: KeyboardShortcut?
    let role: ButtonRole?
    /// Whether the user can drag this into the reader toolbar via
    /// View ▸ Customize Toolbar. Rare and destructive actions stay
    /// menu-only so a stray click can't fire them.
    let isPinnable: Bool

    private let titleFor: (ReaderItem?) -> String
    private let availableFor: (ReaderItem) -> Bool
    private let enabledFor: (ReaderItem, ReaderActivity) -> Bool

    /// Stable key persisted in the user's toolbar customization. Derived from
    /// `id` so the descriptor is the single source for it — renaming `id`
    /// resets that one item's placement, which is why these ids are frozen.
    var toolbarID: String { "reader-action-\(id)" }

    func title(for item: ReaderItem?) -> String { titleFor(item) }

    /// Whether the action makes sense for this item at all. Unavailable
    /// actions are hidden in the reader's own menus (extraction is
    /// meaningless for a local PDF) but shown disabled in the menu bar,
    /// per MACUX.md — a menu bar that reshapes itself is unlearnable.
    func isAvailable(for item: ReaderItem?) -> Bool {
        guard let item else { return false }
        return availableFor(item)
    }

    func isEnabled(for item: ReaderItem?, activity: ReaderActivity) -> Bool {
        guard let item, availableFor(item) else { return false }
        return enabledFor(item, activity)
    }
}

extension ReaderAction {
    static let extractArticle = ReaderAction(
        id: "extract", command: .extract, section: .source,
        systemImage: "arrow.down.doc", shortcut: .extractArticle,
        role: nil, isPinnable: true,
        titleFor: { _ in "Extract Article" },
        availableFor: { $0.origin == .feed },
        enabledFor: { _, activity in !activity.isFetching }
    )

    static let extractWithSession = ReaderAction(
        id: "extract-session", command: .extractAuthenticated, section: .source,
        systemImage: "key", shortcut: .extractWithSession,
        role: nil, isPinnable: true,
        titleFor: { _ in "Extract with App Session" },
        availableFor: { $0.origin == .feed },
        enabledFor: { _, activity in !activity.isFetching }
    )

    static let logInToSite = ReaderAction(
        id: "login", command: .login, section: .source,
        systemImage: "person.badge.key", shortcut: nil,
        role: nil, isPinnable: false,
        titleFor: { _ in "Log in to Site…" },
        availableFor: { $0.origin == .feed },
        enabledFor: { _, _ in true }
    )

    static let summarize = ReaderAction(
        id: "summarize", command: .summarize, section: .intelligence,
        systemImage: "sparkles", shortcut: nil,
        role: nil, isPinnable: true,
        titleFor: { $0?.summaryFull == nil ? "Generate Summary" : "Regenerate Summary" },
        availableFor: { _ in true },
        enabledFor: { _, activity in !activity.isSummarizing }
    )

    static let findRelated = ReaderAction(
        id: "find-related", command: .findRelated, section: .intelligence,
        systemImage: "link", shortcut: .findRelatedArticles,
        role: nil, isPinnable: true,
        titleFor: { _ in "Find Related Articles" },
        availableFor: { _ in true },
        enabledFor: { _, activity in !activity.isFindingRelated }
    )

    static let sendToComposer = ReaderAction(
        id: "promote", command: .promote, section: .intelligence,
        systemImage: "paperplane", shortcut: .sendToComposer,
        role: nil, isPinnable: true,
        titleFor: { $0?.isPromoted == true ? "In Composer" : "Send to Composer" },
        availableFor: { _ in true },
        enabledFor: { item, activity in !item.isPromoted && !activity.isPromoting }
    )

    static let deleteFromLibrary = ReaderAction(
        id: "delete", command: .delete, section: .destructive,
        systemImage: "trash", shortcut: nil,
        role: .destructive, isPinnable: false,
        titleFor: { _ in "Delete from Library…" },
        availableFor: { $0.origin == .library },
        enabledFor: { _, _ in true }
    )

    static let all: [ReaderAction] = [
        extractArticle, extractWithSession, logInToSite,
        summarize, findRelated, sendToComposer,
        deleteFromLibrary,
    ]

    static let pinnable: [ReaderAction] = all.filter(\.isPinnable)

    /// Available actions grouped into their divider-separated runs, with
    /// empty runs dropped so no surface renders a stray leading divider.
    static func sections(for item: ReaderItem?) -> [[ReaderAction]] {
        Section.allCases.compactMap { section in
            let actions = all.filter { $0.section == section && $0.isAvailable(for: item) }
            return actions.isEmpty ? nil : actions
        }
    }
}
