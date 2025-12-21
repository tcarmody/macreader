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

    private var healthCheckTask: Task<Void, Never>?

    // UI state
    @Published var showAddFeed: Bool = false
    @Published var showSettings: Bool = false
    @Published var showImportOPML: Bool = false
    @Published var groupByMode: GroupByMode = .date
    @Published var sortOption: ArticleSortOption = .newestFirst
    @Published var isClusteringLoading: Bool = false

    // Server-side grouped articles (for topic/feed modes)
    @Published private var serverGroupedArticles: [ArticleGroup] = []

    // Multi-selection state
    @Published var selectedFeedIds: Set<Int> = []
    @Published var selectedArticleIds: Set<Int> = []

    // Edit state
    @Published var feedBeingEdited: Feed?

    // Category state
    @Published var collapsedCategories: Set<String> = []

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let pythonServer: PythonServer

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
        case .bookmarked:
            return "Saved"
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
            result = result.filter { !$0.isRead }
        case .bookmarked:
            result = result.filter { $0.isBookmarked }
        case .feed(let id):
            result = result.filter { $0.feedId == id }
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
        self.pythonServer = PythonServer()

        // Load client-side settings from UserDefaults
        loadLocalSettings()
    }

    // MARK: - Server Management

    func startServer() async {
        serverError = nil
        do {
            try await pythonServer.start()
            serverRunning = true
            // Start periodic health checks
            startHealthChecks()
            // Load initial data after server starts
            await refresh()
        } catch {
            serverError = error.localizedDescription
            serverRunning = false
            serverStatus = .unhealthy(error: error.localizedDescription)
        }
    }

    func stopServer() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        pythonServer.stop()
        serverRunning = false
        serverStatus = .unknown
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
        case .bookmarked:
            return try await apiClient.getArticles(bookmarkedOnly: true)
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
                self.selectedArticleDetail = detail
                return
            }
        }

        // If we get here, summary wasn't ready in time - reload anyway
        if let article = selectedArticle {
            let detail = try await apiClient.getArticle(id: article.id)
            self.selectedArticleDetail = detail
        }
    }

    func fetchArticleContent(articleId: Int) async throws {
        let detail = try await apiClient.fetchArticleContent(articleId: articleId)
        selectedArticleDetail = detail
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
        // Wait a moment for background refresh to start
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()

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
