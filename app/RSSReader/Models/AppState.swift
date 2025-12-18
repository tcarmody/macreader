import Foundation
import SwiftUI

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
    @Published var settings: Settings = .default

    // Server state
    @Published var serverRunning: Bool = false
    @Published var serverError: String?

    // UI state
    @Published var showAddFeed: Bool = false
    @Published var showSettings: Bool = false

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let pythonServer: PythonServer

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
        groupArticlesByDate(filteredArticles)
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

    // MARK: - Initialization

    init(apiClient: APIClient = APIClient(), pythonServer: PythonServer = PythonServer()) {
        self.apiClient = apiClient
        self.pythonServer = pythonServer
    }

    // MARK: - Server Management

    func startServer() async {
        serverError = nil
        do {
            try await pythonServer.start()
            serverRunning = true
            // Load initial data after server starts
            await refresh()
        } catch {
            serverError = error.localizedDescription
            serverRunning = false
        }
    }

    func stopServer() {
        pythonServer.stop()
        serverRunning = false
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
        // Reload the article detail to get the new summary
        if let article = selectedArticle {
            await loadArticleDetail(for: article)
        }
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

    func refreshFeeds() async throws {
        try await apiClient.refreshFeeds()
        // Wait a moment for background refresh to start
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()
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

    func updateSettings(_ newSettings: Settings) async throws {
        settings = try await apiClient.updateSettings(newSettings)
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
}
