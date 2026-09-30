import SwiftUI
import XCTest
@testable import DataPointsAI

@MainActor
final class ReaderInteractionTests: XCTestCase {
    func testReaderSectionsExposeStableNativeOrder() {
        XCTAssertEqual(DetailTab.allCases.map(\.rawValue), ["Content", "Summary", "Related", "Chat"])
    }

    func testPlainLibraryContentIsEscapedForTheSharedHTMLReader() {
        let item = ReaderItem(libraryItem: makeLibraryItem(content: "<script>alert('x')</script>\nsecond line"))
        XCTAssertTrue(item.renderedContent.contains("&lt;script&gt;"))
        XCTAssertFalse(item.renderedContent.contains("<script>"))
        XCTAssertTrue(item.renderedContent.contains("white-space: pre-wrap"))
    }

    func testNotificationServiceCanBeConstructedWithoutSystemNotificationHost() {
        let service = NotificationService(startMonitoring: false)
        XCTAssertFalse(service.isAuthorized)
        XCTAssertEqual(service.authorizationStatus, .notDetermined)
    }

    func testReaderThemeAddsHighContrastAndOpaqueSurfaceOverrides() {
        let styles = ArticleTheme.ember.cssStyles(accessibilityContrast: true, reduceTransparency: true)
        XCTAssertTrue(styles.contains("text-decoration-thickness: 2px"))
        XCTAssertTrue(styles.contains("--code-bg: var(--bg-color)"))
    }

    func testReaderPositionStoreRejectsChangedContent() {
        let id = "test-reader-position"
        ReaderPositionStore.shared.save(itemID: id, contentLength: 10, tab: .ai, offsets: [.ai: 140])
        XCTAssertEqual(ReaderPositionStore.shared.restore(itemID: id, contentLength: 10)?.0, .ai)
        XCTAssertNil(ReaderPositionStore.shared.restore(itemID: id, contentLength: 11))
    }

    func testSyncFeedbackUsesAccessibleTransientMessages() {
        XCTAssertEqual(AppState.SyncFeedback.newArticles(2).subtitle, "2 new articles")
        XCTAssertEqual(AppState.SyncFeedback.noChanges.subtitle, "Refresh complete — no new articles")
        XCTAssertTrue(AppState.SyncFeedback.failed("Network unavailable").subtitle.contains("Retry"))
    }

    // MARK: - Reader actions

    func testExtractionActionsAreUnavailableForLibraryItems() {
        let library = ReaderItem(libraryItem: makeLibraryItem(content: "text"))
        XCTAssertFalse(ReaderAction.extractArticle.isAvailable(for: library))
        XCTAssertFalse(ReaderAction.extractWithSession.isAvailable(for: library))
        XCTAssertFalse(ReaderAction.logInToSite.isAvailable(for: library))
        XCTAssertTrue(ReaderAction.deleteFromLibrary.isAvailable(for: library))
        XCTAssertTrue(ReaderAction.summarize.isAvailable(for: library))
    }

    func testDeleteIsUnavailableForFeedArticles() {
        let feed = ReaderItem(article: makeArticle(), source: "Example")
        XCTAssertFalse(ReaderAction.deleteFromLibrary.isAvailable(for: feed))
        XCTAssertTrue(ReaderAction.extractArticle.isAvailable(for: feed))
    }

    func testNoActionIsAvailableWithoutAnItem() {
        for action in ReaderAction.all {
            XCTAssertFalse(action.isAvailable(for: nil), "\(action.id) should need an item")
            XCTAssertFalse(action.isEnabled(for: nil, activity: .idle), "\(action.id) should need an item")
        }
    }

    func testInFlightOperationDisablesOnlyItsOwnAction() {
        let feed = ReaderItem(article: makeArticle(), source: "Example")
        let fetching = ReaderActivity(isFetching: true)
        XCTAssertFalse(ReaderAction.extractArticle.isEnabled(for: feed, activity: fetching))
        XCTAssertFalse(ReaderAction.extractWithSession.isEnabled(for: feed, activity: fetching))
        XCTAssertTrue(ReaderAction.summarize.isEnabled(for: feed, activity: fetching))
        XCTAssertTrue(ReaderAction.findRelated.isEnabled(for: feed, activity: fetching))
    }

    func testAlreadyPromotedItemCannotBeSentToComposerAgain() {
        let promoted = ReaderItem(article: makeArticle(promotedToComposer: "2026-01-01T00:00:00Z"),
                                  source: "Example")
        XCTAssertEqual(ReaderAction.sendToComposer.title(for: promoted), "In Composer")
        XCTAssertTrue(ReaderAction.sendToComposer.isAvailable(for: promoted))
        XCTAssertFalse(ReaderAction.sendToComposer.isEnabled(for: promoted, activity: .idle))
    }

    func testSummarizeTitleReflectsWhetherASummaryExists() {
        let bare = ReaderItem(article: makeArticle(), source: "Example")
        let summarized = ReaderItem(article: makeArticle(summaryFull: "A summary"), source: "Example")
        XCTAssertEqual(ReaderAction.summarize.title(for: bare), "Generate Summary")
        XCTAssertEqual(ReaderAction.summarize.title(for: summarized), "Regenerate Summary")
    }

    /// Menus render these runs in order with a divider between each, so an
    /// empty leading run would show up as a stray divider.
    func testSectionsDropEmptyRunsPerOrigin() {
        let feed = ReaderItem(article: makeArticle(), source: "Example")
        let library = ReaderItem(libraryItem: makeLibraryItem(content: "text"))
        XCTAssertEqual(ReaderAction.sections(for: feed).map { $0.map(\.id) },
                       [["extract", "extract-session", "login"],
                        ["summarize", "find-related", "promote"]])
        XCTAssertEqual(ReaderAction.sections(for: library).map { $0.map(\.id) },
                       [["summarize", "find-related", "promote"], ["delete"]])
        XCTAssertTrue(ReaderAction.sections(for: nil).isEmpty)
    }

    /// MACUX.md §Keyboard Shortcuts: chords come only from the ⌥⌘ / ⇧⌘
    /// ranges, and must not collide with bindings other menus already own.
    func testReaderChordsAreDistinctAndAvoidTakenBindings() {
        let chords = ReaderAction.all.compactMap(\.shortcut)
        XCTAssertEqual(chords.count, 4, "Summarize and Delete defer to their owning menus")
        XCTAssertEqual(Set(chords).count, chords.count, "Reader chords collide with each other")

        let taken: Set<KeyboardShortcut> = [
            KeyboardShortcut("e", modifiers: [.command, .shift]),  // Export OPML
            KeyboardShortcut("r", modifiers: [.command, .shift]),  // Refresh
            KeyboardShortcut("s", modifiers: [.command, .shift]),  // Summarize
            KeyboardShortcut("r", modifiers: .command),            // Mark as Read
        ]
        for chord in chords {
            XCTAssertFalse(taken.contains(chord), "Reader chord collides with an existing binding")
            XCTAssertTrue(chord.modifiers.contains(.command), "Chords must be Command-based")
        }
    }

    private func makeArticle(summaryFull: String? = nil,
                             promotedToComposer: String? = nil) -> ArticleDetail {
        ArticleDetail(
            id: 1, feedId: 1, url: URL(string: "https://example.com/a")!, sourceUrl: nil,
            title: "Test", content: nil, summaryShort: nil, summaryFull: summaryFull,
            keyPoints: nil, isRead: false, isBookmarked: false, publishedAt: nil,
            createdAt: Date(), author: nil, readingTimeMinutes: nil, wordCountValue: nil,
            featuredImage: nil, hasCodeBlocks: nil, siteName: nil, relatedLinks: nil,
            relatedLinksError: nil, promotedToComposer: promotedToComposer,
            isFeatured: false, featuredAt: nil, featuredNote: nil
        )
    }

    private func makeLibraryItem(content: String) -> LibraryItemDetail {
        LibraryItemDetail(
            id: 1, url: URL(string: "https://example.com")!, title: "Test",
            content: content, summaryShort: nil, summaryFull: nil, keyPoints: nil,
            isRead: false, isBookmarked: false, contentType: "txt", fileName: nil,
            createdAt: Date(), relatedLinks: nil, relatedLinksError: nil,
            promotedToComposer: nil, alreadyExisted: false
        )
    }
}
