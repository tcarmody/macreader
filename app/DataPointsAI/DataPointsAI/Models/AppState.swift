import Foundation
import SwiftUI
import Combine
import CoreSpotlight

/// Main application state manager
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties

    @Published var feeds: [Feed] = []
    @Published var articles: [Article] = []
    @Published var selectedFilter: ArticleFilter = .all
    @Published var selectedArticle: Article?
    @Published var selectedArticleDetail: ArticleDetail?
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var settings: AppSettings = .default

    // Server state
    @Published var serverRunning: Bool = false
    @Published var serverError: String?
    @Published var serverStatus: ServerHealthStatus = .unknown
    @Published var lastRefreshTime: Date?

    private var healthCheckTask: Task<Void, Never>?

    // UI state
    @Published var showAddFeed: Bool = false
    @Published var showSettings: Bool = false
    @Published var showImportOPML: Bool = false
    @Published var groupByMode: GroupByMode = .date
    @Published var sortOption: ArticleSortOption = .newestFirst
    @Published var hideReadArticles: Bool = false
    @Published var isClusteringLoading: Bool = false

    // Server-side grouped articles (for topic/feed modes)
    @Published private var serverGroupedArticles: [ArticleGroup] = []

    // Multi-selection state
    @Published var selectedFeedIds: Set<Int> = []
    @Published var selectedArticleIds: Set<Int> = []

    // Snapshot of article IDs to keep visible in current filter view
    // Used to prevent articles from disappearing when marked as read in Unread view
    private var unreadViewArticleIds: Set<Int>?

    // Edit state
    @Published var feedBeingEdited: Feed?

    // Category state
    @Published var collapsedCategories: Set<String> = []

    // Library state
    @Published var libraryItems: [LibraryItem] = []
    @Published var libraryItemCount: Int = 0
    @Published var selectedLibraryItem: LibraryItem?
    @Published var selectedLibraryItemDetail: LibraryItemDetail?
    @Published var showAddToLibrary: Bool = false
    @Published var showLibrary: Bool = false  // Whether Library is selected in sidebar

    // MARK: - Dependencies

    let apiClient: APIClient
    let server: PythonServer

    // Native macOS services
    private let notificationService = NotificationService.shared
    private let spotlightService = SpotlightService.shared
    private let dockBadgeService = DockBadgeService.shared

    // MARK: - Computed Properties

    var currentFilterName: String {
        switch selectedFilter {
        case .all:
            return "All Articles"
        case .unread:
            return "Unread"
        case .today:
            return "Today"
        case .bookmarked:
            return "Saved"
        case .summarized:
            return "Summarized"
        case .unsummarized:
            return "Unsummarized"
        case .feed(let id):
            return feeds.first { $0.id == id }?.name ?? "Feed"
        }
    }

    var groupedArticles: [ArticleGroup] {
        // For topic/feed modes, use server-side grouped data
        if groupByMode != .date && !serverGroupedArticles.isEmpty {
            return serverGroupedArticles.map { group in
                ArticleGroup(id: group.id, title: group.title, articles: sortArticles(group.articles))
            }
        }
        // For date mode, group locally
        return groupArticlesByDate(filteredArticles).map { group in
            ArticleGroup(id: group.id, title: group.title, articles: sortArticles(group.articles))
        }
    }

    /// Sort articles according to current sort option
    private func sortArticles(_ articles: [Article]) -> [Article] {
        switch sortOption {
        case .newestFirst:
            return articles.sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
        case .oldestFirst:
            return articles.sorted { ($0.publishedAt ?? $0.createdAt) < ($1.publishedAt ?? $1.createdAt) }
        case .unreadFirst:
            return articles.sorted { a, b in
                if a.isRead != b.isRead {
                    return !a.isRead // Unread (false) comes first
                }
                return (a.publishedAt ?? a.createdAt) > (b.publishedAt ?? b.createdAt)
            }
        case .titleAZ:
            return articles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return articles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    var filteredArticles: [Article] {
        var result = articles

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .unread:
            // Use snapshot if available to keep articles visible until navigating away
            if let snapshotIds = unreadViewArticleIds {
                result = result.filter { snapshotIds.contains($0.id) }
            } else {
                result = result.filter { !$0.isRead }
            }
        case .today:
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            result = result.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }
        case .bookmarked:
            result = result.filter { $0.isBookmarked }
        case .summarized:
            // Already filtered server-side, but apply locally for consistency
            result = result.filter { $0.summaryShort != nil }
        case .unsummarized:
            // Already filtered server-side, but apply locally for consistency
            result = result.filter { $0.summaryShort == nil }
        case .feed(let id):
            result = result.filter { $0.feedId == id }
        }

        // Apply "hide read" toggle (unless we're already in unread filter)
        if hideReadArticles && selectedFilter != .unread {
            result = result.filter { !$0.isRead }
        }

        // Apply search
        if !searchQuery.isEmpty {
            result = result.filter { article in
                article.title.localizedCaseInsensitiveContains(searchQuery) ||
                (article.summaryShort?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }

        return result
    }

    var totalUnreadCount: Int {
        feeds.reduce(0) { $0 + $1.unreadCount }
    }

    var todayArticleCount: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return articles.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }.count
    }

    /// Feeds grouped by category, with uncategorized feeds under nil key
    var feedsByCategory: [(category: String?, feeds: [Feed])] {
        let grouped = Dictionary(grouping: feeds) { $0.category }

        // Sort: uncategorized first, then alphabetically by category name
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == nil { return true }
            if key2 == nil { return false }
            return key1! < key2!
        }

        return sortedKeys.map { key in
            (category: key, feeds: grouped[key]!.sorted { $0.name < $1.name })
        }
    }

    /// All unique category names
    var categories: [String] {
        Set(feeds.compactMap { $0.category }).sorted()
    }

    // MARK: - Initialization

    init() {
        self.apiClient = APIClient()
        self.server = PythonServer()

        // Load client-side settings from UserDefaults
        loadLocalSettings()
    }

    // MARK: - Server Management

    func startServer() async {
        serverError = nil
        do {
            try await server.start()
            serverRunning = true
            // Start periodic health checks
            startHealthChecks()
            // Load initial data after server starts
            await refresh()
            // Refresh feeds to fetch new articles on launch
            try? await refreshFeeds()
        } catch {
            serverError = error.localizedDescription
            serverRunning = false
            serverStatus = .unhealthy(error: error.localizedDescription)
        }
    }

    func stopServer() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        server.stop()
        serverRunning = false
        serverStatus = .unknown
    }

    /// Restart the server with fresh code
    func restartServer() async {
        serverStatus = .checking
        do {
            try await server.restart()
            serverRunning = true
            await checkServerHealth()
        } catch {
            serverStatus = .unhealthy(error: error.localizedDescription)
            serverError = error.localizedDescription
        }
    }

    /// Check server health once
    func checkServerHealth() async {
        serverStatus = .checking
        do {
            let status = try await apiClient.healthCheck()
            if status.isHealthy {
                serverStatus = .healthy(summarizationEnabled: status.summarizationEnabled)
                serverRunning = true
                serverError = nil
            } else {
                serverStatus = .unhealthy(error: "Server reported unhealthy status")
            }
        } catch {
            serverStatus = .unhealthy(error: error.localizedDescription)
            // Don't immediately mark server as not running - could be transient
        }
    }

    /// Start periodic health checks (every 30 seconds)
    private func startHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkServerHealth()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }

    // MARK: - Data Loading

    func refresh() async {
        isLoading = true
        error = nil

        do {
            async let feedsTask = apiClient.getFeeds()
            async let articlesTask = loadArticlesForCurrentFilter()
            async let settingsTask = apiClient.getSettings()

            feeds = try await feedsTask
            articles = try await articlesTask
            settings = try await settingsTask

            // Capture unread snapshot if in unread view and no snapshot exists yet
            // This handles the initial app startup case
            if selectedFilter == .unread && unreadViewArticleIds == nil {
                captureUnreadSnapshot()
            }

            // Update dock badge with unread count
            updateDockBadge()

            // Index articles for Spotlight search
            indexArticlesForSpotlight()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadArticlesForCurrentFilter() async throws -> [Article] {
        switch selectedFilter {
        case .all:
            return try await apiClient.getArticles()
        case .unread:
            return try await apiClient.getArticles(unreadOnly: true)
        case .today:
            // Fetch all articles and filter to today client-side
            let allArticles = try await apiClient.getArticles()
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            return allArticles.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }
        case .bookmarked:
            return try await apiClient.getArticles(bookmarkedOnly: true)
        case .summarized:
            return try await apiClient.getArticles(summarizedOnly: true)
        case .unsummarized:
            return try await apiClient.getArticles(summarizedOnly: false)
        case .feed(let id):
            return try await apiClient.getArticles(feedId: id)
        }
    }

    func reloadArticles() async {
        do {
            articles = try await loadArticlesForCurrentFilter()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadArticleDetail(for article: Article) async {
        do {
            selectedArticleDetail = try await apiClient.getArticle(id: article.id)

            // Mark as read if setting enabled
            if settings.markReadOnOpen && !article.isRead {
                try await markRead(articleId: article.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Article Actions

    func markRead(articleId: Int, isRead: Bool = true) async throws {
        try await apiClient.markRead(articleId: articleId, isRead: isRead)

        // Update local state
        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].isRead = isRead
        }
        if selectedArticleDetail?.id == articleId {
            selectedArticleDetail?.isRead = isRead
        }

        // Refresh feeds to update unread counts
        feeds = try await apiClient.getFeeds()

        // Update dock badge
        updateDockBadge()
    }

    func toggleBookmark(articleId: Int) async throws {
        let result = try await apiClient.toggleBookmark(articleId: articleId)

        // Update local state
        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].isBookmarked = result.isBookmarked
        }
        if selectedArticleDetail?.id == articleId {
            selectedArticleDetail?.isBookmarked = result.isBookmarked
        }
    }

    func summarizeArticle(articleId: Int) async throws {
        try await apiClient.summarizeArticle(articleId: articleId)

        // Poll for the summary to be ready (background task on server)
        // Try up to 60 times with 1 second delay (60 seconds total)
        // Complex articles with Sonnet model can take 15-30+ seconds
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            let detail = try await apiClient.getArticle(id: articleId)
            if detail.summaryFull != nil {
                // Only update if still viewing this article
                if selectedArticleDetail?.id == articleId {
                    self.selectedArticleDetail = detail
                }
                return
            }
        }

        // If we get here, summary wasn't ready in time - reload anyway
        // Always use the articleId we were asked to summarize, not selectedArticle
        let detail = try await apiClient.getArticle(id: articleId)
        if selectedArticleDetail?.id == articleId {
            self.selectedArticleDetail = detail
        }
    }

    func fetchArticleContent(articleId: Int) async throws {
        let detail = try await apiClient.fetchArticleContent(articleId: articleId)
        selectedArticleDetail = detail
    }

    // MARK: - Library Actions

    func loadLibraryItems() async {
        do {
            let response = try await apiClient.getLibraryItems()
            libraryItems = response.items
            libraryItemCount = response.total
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadLibraryItemDetail(for item: LibraryItem) async {
        do {
            selectedLibraryItemDetail = try await apiClient.getLibraryItem(id: item.id)

            // Mark as read if setting enabled
            if settings.markReadOnOpen && !item.isRead {
                try await markLibraryItemRead(itemId: item.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addURLToLibrary(url: String, title: String? = nil, autoSummarize: Bool = false) async throws {
        let item = try await apiClient.addURLToLibrary(url: url, title: title, autoSummarize: autoSummarize)
        // Reload library items
        await loadLibraryItems()

        // Select the new item
        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
    }

    func uploadFileToLibrary(data: Data, filename: String, title: String? = nil, autoSummarize: Bool = false) async throws {
        let item = try await apiClient.uploadFileToLibrary(data: data, filename: filename, title: title, autoSummarize: autoSummarize)
        // Reload library items
        await loadLibraryItems()

        // Select the new item
        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
    }

    func deleteLibraryItem(itemId: Int) async throws {
        try await apiClient.deleteLibraryItem(id: itemId)

        // Remove from local state
        libraryItems.removeAll { $0.id == itemId }
        libraryItemCount = max(0, libraryItemCount - 1)

        // Clear selection if deleted item was selected
        if selectedLibraryItem?.id == itemId {
            selectedLibraryItem = nil
            selectedLibraryItemDetail = nil
        }
    }

    func markLibraryItemRead(itemId: Int, isRead: Bool = true) async throws {
        try await apiClient.markLibraryItemRead(id: itemId, isRead: isRead)

        // Update local state
        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isRead = isRead
        }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isRead = isRead
        }
    }

    func toggleLibraryItemBookmark(itemId: Int) async throws {
        let result = try await apiClient.toggleLibraryItemBookmark(id: itemId)

        // Update local state
        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isBookmarked = result.isBookmarked
        }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isBookmarked = result.isBookmarked
        }
    }

    func summarizeLibraryItem(itemId: Int) async throws {
        try await apiClient.summarizeLibraryItem(id: itemId)

        // Poll for the summary to be ready
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let detail = try await apiClient.getLibraryItem(id: itemId)
            if detail.summaryFull != nil {
                if selectedLibraryItemDetail?.id == itemId {
                    self.selectedLibraryItemDetail = detail
                }
                return
            }
        }

        // Reload anyway after timeout
        let detail = try await apiClient.getLibraryItem(id: itemId)
        if selectedLibraryItemDetail?.id == itemId {
            self.selectedLibraryItemDetail = detail
        }
    }

    func selectLibrary() {
        showLibrary = true
        clearUnreadSnapshot()  // Clear snapshot when leaving feeds view
        selectedFilter = .all  // Reset filter when switching to library
        selectedArticle = nil
        selectedArticleDetail = nil
        Task {
            await loadLibraryItems()
        }
    }

    func deselectLibrary() {
        showLibrary = false
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
    }

    // MARK: - Bulk Article Actions

    func bulkMarkRead(articleIds: [Int], isRead: Bool = true) async throws {
        guard !articleIds.isEmpty else { return }

        try await apiClient.bulkMarkRead(articleIds: articleIds, isRead: isRead)

        // Update local state
        for articleId in articleIds {
            if let index = articles.firstIndex(where: { $0.id == articleId }) {
                articles[index].isRead = isRead
            }
        }
        if let detail = selectedArticleDetail, articleIds.contains(detail.id) {
            selectedArticleDetail?.isRead = isRead
        }

        // Refresh feeds to update unread counts
        feeds = try await apiClient.getFeeds()

        // Update dock badge
        updateDockBadge()
    }

    func markFeedRead(feedId: Int, isRead: Bool = true) async throws {
        try await apiClient.markFeedRead(feedId: feedId, isRead: isRead)

        // Update local state for articles from this feed
        for i in articles.indices where articles[i].feedId == feedId {
            articles[i].isRead = isRead
        }
        if let detail = selectedArticleDetail, detail.feedId == feedId {
            selectedArticleDetail?.isRead = isRead
        }

        // Refresh feeds to update unread counts
        feeds = try await apiClient.getFeeds()

        // Update dock badge
        updateDockBadge()
    }

    func markAllRead(isRead: Bool = true) async throws {
        try await apiClient.markAllRead(isRead: isRead)

        // Update all local articles
        for i in articles.indices {
            articles[i].isRead = isRead
        }
        selectedArticleDetail?.isRead = isRead

        // Refresh feeds to update unread counts
        feeds = try await apiClient.getFeeds()

        // Update dock badge
        updateDockBadge()
    }

    // MARK: - Feed Actions

    func addFeed(url: String, name: String? = nil) async throws {
        let feed = try await apiClient.addFeed(url: url, name: name)
        feeds.append(feed)
        await reloadArticles()
    }

    func deleteFeed(feedId: Int) async throws {
        try await apiClient.deleteFeed(id: feedId)
        feeds.removeAll { $0.id == feedId }

        // Reset filter if we deleted the currently selected feed
        if case .feed(let id) = selectedFilter, id == feedId {
            selectedFilter = .all
        }

        await reloadArticles()
    }

    func bulkDeleteFeeds(feedIds: [Int]) async throws {
        guard !feedIds.isEmpty else { return }

        try await apiClient.bulkDeleteFeeds(ids: feedIds)

        // Reset filter if we deleted the currently selected feed
        if case .feed(let id) = selectedFilter, feedIds.contains(id) {
            selectedFilter = .all
        }

        // Refresh feeds from server to ensure sync
        feeds = try await apiClient.getFeeds()
        await reloadArticles()
    }

    func updateFeed(feedId: Int, name: String? = nil, category: String? = nil) async throws {
        let updatedFeed = try await apiClient.updateFeed(id: feedId, name: name, category: category)

        // Update local state
        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index] = updatedFeed
        }
    }

    func moveFeedToCategory(feedId: Int, category: String?) async throws {
        try await updateFeed(feedId: feedId, category: category)
    }

    func toggleCategoryCollapsed(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
        saveWindowState()
    }

    /// Collapse all category folders in the sidebar
    func collapseAllCategories() {
        collapsedCategories = Set(categories)
        saveWindowState()
    }

    /// Expand all category folders in the sidebar
    func expandAllCategories() {
        collapsedCategories.removeAll()
        saveWindowState()
    }

    func renameCategory(from oldName: String, to newName: String) async throws {
        // Update all feeds in this category
        let feedsInCategory = feeds.filter { $0.category == oldName }
        for feed in feedsInCategory {
            try await updateFeed(feedId: feed.id, category: newName)
        }
    }

    func deleteCategory(_ category: String) async throws {
        // Move all feeds in this category to uncategorized
        let feedsInCategory = feeds.filter { $0.category == category }
        for feed in feedsInCategory {
            // Pass empty string to clear category, API will convert to null
            let updatedFeed = try await apiClient.updateFeed(id: feed.id, name: nil, category: "")
            if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[index] = updatedFeed
            }
        }
    }

    func refreshFeeds() async throws {
        // Track current unread count to detect new articles
        let previousUnreadCount = totalUnreadCount

        try await apiClient.refreshFeeds()

        // Poll until refresh completes (or timeout after 60 seconds)
        let maxAttempts = 60
        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

            let stats = try? await apiClient.getStats()
            if stats?.refreshInProgress == false {
                break
            }

            // Reload articles periodically while refresh is in progress
            // so user sees new articles as they come in
            if attempt % 5 == 4 {
                await refresh()
            }
        }

        // Final refresh to get all new articles
        await refresh()

        // Update last refresh time
        lastRefreshTime = Date()

        // Notify about new articles if count increased
        let newArticleCount = totalUnreadCount - previousUnreadCount
        if newArticleCount > 0 && settings.notificationsEnabled {
            await notificationService.notifyNewArticles(count: newArticleCount)
        }
    }

    // MARK: - OPML Import/Export

    func importOPML(content: String) async throws -> APIClient.OPMLImportResponse {
        let result = try await apiClient.importOPML(content: content)

        // Reload feeds to include newly imported ones
        feeds = try await apiClient.getFeeds()
        await reloadArticles()

        return result
    }

    func importOPML(from fileURL: URL) async throws -> APIClient.OPMLImportResponse {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try await importOPML(content: content)
    }

    func exportOPML() async throws -> String {
        let result = try await apiClient.exportOPML()
        return result.opml
    }

    // MARK: - Search

    func search(query: String) async {
        guard query.count >= 2 else {
            await reloadArticles()
            return
        }

        do {
            articles = try await apiClient.search(query: query)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Settings

    func updateSettings(_ newSettings: AppSettings) async throws {
        // Preserve client-side appearance settings that aren't synced to the API
        let savedAppearance = (
            fontSize: newSettings.articleFontSize,
            lineSpacing: newSettings.articleLineSpacing,
            listDensity: newSettings.listDensity,
            notifications: newSettings.notificationsEnabled,
            appTypeface: newSettings.appTypeface,
            contentTypeface: newSettings.contentTypeface
        )

        // Send to API (only synced settings will be sent due to CodingKeys)
        var updatedSettings = try await apiClient.updateSettings(newSettings)

        // Restore client-side settings
        updatedSettings.articleFontSize = savedAppearance.fontSize
        updatedSettings.articleLineSpacing = savedAppearance.lineSpacing
        updatedSettings.listDensity = savedAppearance.listDensity
        updatedSettings.notificationsEnabled = savedAppearance.notifications
        updatedSettings.appTypeface = savedAppearance.appTypeface
        updatedSettings.contentTypeface = savedAppearance.contentTypeface

        settings = updatedSettings

        // Persist client-side settings locally
        saveLocalSettings()
    }

    /// Save client-side settings to UserDefaults
    private func saveLocalSettings() {
        UserDefaults.standard.set(settings.articleFontSize.rawValue, forKey: "articleFontSize")
        UserDefaults.standard.set(settings.articleLineSpacing.rawValue, forKey: "articleLineSpacing")
        UserDefaults.standard.set(settings.listDensity.rawValue, forKey: "listDensity")
        UserDefaults.standard.set(settings.notificationsEnabled, forKey: "notificationsEnabled")
        UserDefaults.standard.set(settings.appTypeface.rawValue, forKey: "appTypeface")
        UserDefaults.standard.set(settings.contentTypeface.rawValue, forKey: "contentTypeface")

        // Save window state
        saveWindowState()
    }

    /// Save window state (collapsed categories, selected filter)
    func saveWindowState() {
        // Save collapsed categories
        UserDefaults.standard.set(Array(collapsedCategories), forKey: "collapsedCategories")

        // Save selected filter
        if let filterData = try? JSONEncoder().encode(selectedFilter) {
            UserDefaults.standard.set(filterData, forKey: "selectedFilter")
        }
    }

    /// Load client-side settings from UserDefaults
    private func loadLocalSettings() {
        if let fontSizeRaw = UserDefaults.standard.string(forKey: "articleFontSize"),
           let fontSize = ArticleFontSize(rawValue: fontSizeRaw) {
            settings.articleFontSize = fontSize
        }
        if let lineSpacingRaw = UserDefaults.standard.string(forKey: "articleLineSpacing"),
           let lineSpacing = ArticleLineSpacing(rawValue: lineSpacingRaw) {
            settings.articleLineSpacing = lineSpacing
        }
        if let densityRaw = UserDefaults.standard.string(forKey: "listDensity"),
           let density = ListDensity(rawValue: densityRaw) {
            settings.listDensity = density
        }
        // Only load if key exists (to preserve default of true)
        if UserDefaults.standard.object(forKey: "notificationsEnabled") != nil {
            settings.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        if let appTypefaceRaw = UserDefaults.standard.string(forKey: "appTypeface"),
           let appTypeface = AppTypeface(rawValue: appTypefaceRaw) {
            settings.appTypeface = appTypeface
        }
        if let contentTypefaceRaw = UserDefaults.standard.string(forKey: "contentTypeface"),
           let contentTypeface = ContentTypeface(rawValue: contentTypefaceRaw) {
            settings.contentTypeface = contentTypeface
        }

        // Load window state
        loadWindowState()
    }

    /// Load window state (collapsed categories, selected filter)
    private func loadWindowState() {
        // Load collapsed categories
        if let categories = UserDefaults.standard.stringArray(forKey: "collapsedCategories") {
            collapsedCategories = Set(categories)
        }

        // Load selected filter
        if let filterData = UserDefaults.standard.data(forKey: "selectedFilter"),
           let filter = try? JSONDecoder().decode(ArticleFilter.self, from: filterData) {
            selectedFilter = filter
        }
    }

    // MARK: - Grouping

    func setGroupByMode(_ mode: GroupByMode) async {
        groupByMode = mode

        if mode == .date {
            // Clear server groups, use local grouping
            serverGroupedArticles = []
        } else {
            // Fetch grouped articles from server
            await loadGroupedArticles()
        }
    }

    func loadGroupedArticles() async {
        guard groupByMode != .date else { return }

        isClusteringLoading = groupByMode == .topic
        error = nil

        do {
            let unreadOnly = selectedFilter == .unread
            let response = try await apiClient.getGroupedArticles(
                groupBy: groupByMode.rawValue,
                unreadOnly: unreadOnly
            )

            serverGroupedArticles = response.groups.map { group in
                ArticleGroup(
                    id: group.key,
                    title: group.label,
                    articles: group.articles
                )
            }

            // Also update the flat articles list for consistency
            articles = response.groups.flatMap { $0.articles }
        } catch {
            self.error = error.localizedDescription
            // Fall back to date grouping on error
            serverGroupedArticles = []
        }

        isClusteringLoading = false
    }

    // MARK: - Unread View Snapshot

    /// Capture a snapshot of currently unread article IDs when entering the Unread view
    /// This prevents articles from disappearing when marked as read
    func captureUnreadSnapshot() {
        let unreadIds = Set(articles.filter { !$0.isRead }.map { $0.id })
        unreadViewArticleIds = unreadIds
    }

    /// Clear the unread snapshot when navigating away from the Unread view
    func clearUnreadSnapshot() {
        unreadViewArticleIds = nil
    }

    /// Select a filter and manage unread snapshot appropriately
    func selectFilter(_ filter: ArticleFilter) {
        // Clear snapshot when leaving unread view
        if selectedFilter == .unread && filter != .unread {
            clearUnreadSnapshot()
        }

        selectedFilter = filter

        // Capture snapshot when entering unread view
        if filter == .unread {
            captureUnreadSnapshot()
        }
    }

    // MARK: - Helpers

    private func groupArticlesByDate(_ articles: [Article]) -> [ArticleGroup] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!

        var todayArticles: [Article] = []
        var yesterdayArticles: [Article] = []
        var lastWeekArticles: [Article] = []
        var olderArticles: [Article] = []

        for article in articles {
            let articleDate = article.publishedAt ?? article.createdAt

            if articleDate >= today {
                todayArticles.append(article)
            } else if articleDate >= yesterday {
                yesterdayArticles.append(article)
            } else if articleDate >= lastWeek {
                lastWeekArticles.append(article)
            } else {
                olderArticles.append(article)
            }
        }

        var groups: [ArticleGroup] = []

        if !todayArticles.isEmpty {
            groups.append(ArticleGroup(id: "today", title: "Today", articles: todayArticles))
        }
        if !yesterdayArticles.isEmpty {
            groups.append(ArticleGroup(id: "yesterday", title: "Yesterday", articles: yesterdayArticles))
        }
        if !lastWeekArticles.isEmpty {
            groups.append(ArticleGroup(id: "lastweek", title: "Last 7 Days", articles: lastWeekArticles))
        }
        if !olderArticles.isEmpty {
            groups.append(ArticleGroup(id: "older", title: "Older", articles: olderArticles))
        }

        return groups
    }

    // MARK: - Native macOS Integration

    /// Update dock badge with current unread count
    private func updateDockBadge() {
        dockBadgeService.updateBadge(unreadCount: totalUnreadCount)
    }

    /// Index articles for Spotlight search
    private func indexArticlesForSpotlight() {
        // Build feed name lookup
        let feedNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0.name) })
        spotlightService.indexArticles(articles, feedNames: feedNames)
    }

    /// Handle opening an article from Spotlight
    /// - Parameter articleId: The article ID from Spotlight
    func openArticleFromSpotlight(articleId: Int) async {
        // Find the article
        if let article = articles.first(where: { $0.id == articleId }) {
            selectedArticle = article
            await loadArticleDetail(for: article)
        } else {
            // Article not in current list, fetch it directly
            do {
                let detail = try await apiClient.getArticle(id: articleId)
                // Create a minimal Article from the detail for selection
                let article = Article(
                    id: detail.id,
                    feedId: detail.feedId,
                    url: detail.url,
                    sourceUrl: detail.sourceUrl,
                    title: detail.title,
                    summaryShort: detail.summaryShort,
                    isRead: detail.isRead,
                    isBookmarked: detail.isBookmarked,
                    publishedAt: detail.publishedAt,
                    createdAt: detail.createdAt
                )
                selectedArticle = article
                selectedArticleDetail = detail
            } catch {
                self.error = "Could not open article: \(error.localizedDescription)"
            }
        }
    }

    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        return await notificationService.requestAuthorization()
    }
}
