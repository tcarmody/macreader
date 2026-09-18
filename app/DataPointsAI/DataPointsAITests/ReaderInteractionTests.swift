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
