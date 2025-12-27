import SwiftUI
import CoreSpotlight
import UserNotifications
import UniformTypeIdentifiers

@main
struct RSSReaderApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isExporting = false
    @State private var showSetupWizard = false
    @State private var hasCheckedForAPIKey = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .onAppear {
                    Task {
                        await appState.startServer()
                        // Setup notification categories
                        NotificationService.shared.setupNotificationCategories()

                        // Start newsletter watcher if auto-import is enabled
                        await NewsletterWatcherService.shared.startWatchingIfEnabled()

                        // Check if we need to show the setup wizard (no API keys configured)
                        if !hasCheckedForAPIKey {
                            hasCheckedForAPIKey = true
                            await checkForSetupWizard()
                        }
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlightActivity)
                .sheet(isPresented: $showSetupWizard) {
                    SetupWizardView {
                        // Wizard completed - server will already have been restarted
                        showSetupWizard = false
                    }
                    .environmentObject(appState)
                }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Add Feed...") {
                    DispatchQueue.main.async {
                        appState.showAddFeed = true
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Import OPML...") {
                    DispatchQueue.main.async {
                        appState.showImportOPML = true
                    }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Export OPML...") {
                    exportOPML()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.feeds.isEmpty)

                Divider()

                Button("Refresh Feeds") {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // Go menu
            CommandMenu("Go") {
                Button("Quick Open...") {
                    DispatchQueue.main.async {
                        appState.showQuickOpen = true
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Next Article") {
                    appState.navigateToNextArticle()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.groupedArticles.flatMap { $0.articles }.isEmpty)

                Button("Previous Article") {
                    appState.navigateToPreviousArticle()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.groupedArticles.flatMap { $0.articles }.isEmpty)
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Show All") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .all
                    }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Unread") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .unread
                    }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Saved") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .bookmarked
                    }
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Show Today") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .today
                    }
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                // Grouping options
                Picker("Group By", selection: Binding(
                    get: { appState.groupByMode },
                    set: { newMode in
                        Task {
                            await appState.setGroupByMode(newMode)
                        }
                    }
                )) {
                    ForEach(GroupByMode.allCases, id: \.self) { mode in
                        Text(mode.menuLabel).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button(appState.readerModeEnabled ? "Exit Reader Mode" : "Enter Reader Mode") {
                    appState.readerModeEnabled.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Increase Font Size") {
                    appState.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!appState.settings.articleFontSize.canIncrease)

                Button("Decrease Font Size") {
                    appState.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!appState.settings.articleFontSize.canDecrease)

                Button("Reset Font Size") {
                    appState.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // Edit menu - Selection commands
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Select All Articles") {
                    selectAllArticles()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Clear Selection") {
                    DispatchQueue.main.async {
                        appState.selectedArticleIds.removeAll()
                        appState.selectedFeedIds.removeAll()
                    }
                }
                .keyboardShortcut(.escape)
                .disabled(appState.selectedArticleIds.isEmpty && appState.selectedFeedIds.isEmpty)
            }

            // Article menu
            CommandMenu("Article") {
                Button("Open in Browser") {
                    if let article = appState.selectedArticle {
                        NSWorkspace.shared.open(article.url)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Button("Open Original") {
                    if let article = appState.selectedArticle {
                        NSWorkspace.shared.open(article.url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Divider()

                Button("Summarize Article") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.summarizeArticle(articleId: article.id)
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.selectedArticle == nil || appState.selectedArticleDetail?.summaryFull != nil)

                Button("Toggle Bookmark") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.toggleBookmark(articleId: article.id)
                        }
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Divider()

                Button("Copy Link") {
                    if let article = appState.selectedArticle {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(article.url.absoluteString, forType: .string)
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Button("Copy Article URL") {
                    if let article = appState.selectedArticle {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(article.url.absoluteString, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.selectedArticle == nil)

                Divider()

                Button("Mark as Read") {
                    markSelectedAsRead(true)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedArticle == nil && appState.selectedArticleIds.isEmpty)

                Button("Mark as Unread") {
                    markSelectedAsRead(false)
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(appState.selectedArticle == nil && appState.selectedArticleIds.isEmpty)

                Divider()

                Button("Mark All as Read") {
                    Task {
                        try? await markCurrentFilterAsRead()
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // Feed menu
            CommandMenu("Feed") {
                Button("Rename Feed...") {
                    if case .feed(let feedId) = appState.selectedFilter,
                       let feed = appState.feeds.first(where: { $0.id == feedId }) {
                        appState.feedBeingEdited = feed
                    }
                }
                .disabled(!isCurrentlyViewingFeed)

                Button("Mark Feed as Read") {
                    if case .feed(let feedId) = appState.selectedFilter {
                        Task {
                            try? await appState.markFeedRead(feedId: feedId)
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!isCurrentlyViewingFeed)

                Divider()

                Button("Delete Feed") {
                    // This will be handled by the confirmation dialog in FeedListView
                    if case .feed(let feedId) = appState.selectedFilter {
                        Task {
                            try? await appState.deleteFeed(feedId: feedId)
                        }
                    }
                }
                .disabled(!isCurrentlyViewingFeed)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("AI Setup Wizard...") {
                    showSetupWizard = true
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }

    private var isCurrentlyViewingFeed: Bool {
        if case .feed = appState.selectedFilter {
            return true
        }
        return false
    }

    private func selectAllArticles() {
        let allIds = appState.groupedArticles.flatMap { $0.articles }.map { $0.id }
        DispatchQueue.main.async {
            appState.selectedArticleIds = Set(allIds)
        }
    }

    private func markSelectedAsRead(_ isRead: Bool) {
        Task {
            if !appState.selectedArticleIds.isEmpty {
                try? await appState.bulkMarkRead(
                    articleIds: Array(appState.selectedArticleIds),
                    isRead: isRead
                )
                await MainActor.run {
                    appState.selectedArticleIds.removeAll()
                }
            } else if let article = appState.selectedArticle {
                try? await appState.markRead(articleId: article.id, isRead: isRead)
            }
        }
    }

    private func markCurrentFilterAsRead() async throws {
        switch appState.selectedFilter {
        case .all, .unread:
            try await appState.markAllRead()
        case .today, .bookmarked, .summarized, .unsummarized:
            let ids = appState.filteredArticles.map { $0.id }
            try await appState.bulkMarkRead(articleIds: ids)
        case .feed(let feedId):
            try await appState.markFeedRead(feedId: feedId)
        }
    }

    // MARK: - Setup Wizard

    private func checkForSetupWizard() async {
        // Check if any API key is configured in Keychain
        let hasAPIKey = KeychainService.shared.hasAnyAPIKey()

        if !hasAPIKey {
            // Show setup wizard on first launch
            await MainActor.run {
                showSetupWizard = true
            }
        }
    }

    // MARK: - Spotlight Integration

    private func handleSpotlightActivity(_ userActivity: NSUserActivity) {
        if let articleId = SpotlightService.articleId(from: userActivity) {
            Task {
                await appState.openArticleFromSpotlight(articleId: articleId)
            }
        }
    }

    // MARK: - OPML Export

    private func exportOPML() {
        Task {
            do {
                let opmlContent = try await appState.exportOPML()

                // Show save panel
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.title = "Export OPML"
                    savePanel.nameFieldLabel = "Export As:"
                    savePanel.nameFieldStringValue = "feeds.opml"
                    savePanel.allowedContentTypes = [
                        UTType(filenameExtension: "opml") ?? .xml
                    ]
                    savePanel.canCreateDirectories = true

                    savePanel.begin { response in
                        if response == .OK, let url = savePanel.url {
                            do {
                                try opmlContent.write(to: url, atomically: true, encoding: .utf8)
                            } catch {
                                DispatchQueue.main.async {
                                    self.appState.error = "Failed to save OPML: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    appState.error = "Failed to export OPML: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set ourselves as the notification delegate
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clear dock badge on quit
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and play sound even when app is active
        return [.banner, .sound]
    }

    /// Handle notification tap/action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification - open the article if there's an ID
            if let articleId = userInfo["articleId"] as? Int {
                await MainActor.run {
                    // Post notification to open article
                    NotificationCenter.default.post(
                        name: .openArticleFromNotification,
                        object: nil,
                        userInfo: ["articleId": articleId]
                    )
                }
            }

        case "MARK_READ":
            // Mark articles as read (would need to pass article IDs through userInfo)
            break

        case "BOOKMARK":
            // Bookmark the article
            if let articleId = userInfo["articleId"] as? Int {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .bookmarkArticleFromNotification,
                        object: nil,
                        userInfo: ["articleId": articleId]
                    )
                }
            }

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openArticleFromNotification = Notification.Name("openArticleFromNotification")
    static let bookmarkArticleFromNotification = Notification.Name("bookmarkArticleFromNotification")
}
