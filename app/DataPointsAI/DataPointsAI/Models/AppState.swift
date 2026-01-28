import Foundation
import SwiftUI
import Combine
import CoreSpotlight

/// Main application state manager
///
/// This class is organized into extensions for better maintainability:
/// - AppState+Server.swift - Server management
/// - AppState+Articles.swift - Article operations
/// - AppState+Feeds.swift - Feed operations
/// - AppState+Library.swift - Library and newsletter operations
/// - AppState+Settings.swift - Settings and persistence
/// - AppState+Grouping.swift - Article grouping
/// - AppState+Spotlight.swift - macOS integration (Spotlight, notifications, dock badge)
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
    @Published var newArticlesSinceLastCheck: Int = 0
    @Published var isSyncing: Bool = false

    // Network state
    let networkMonitor = NetworkMonitor.shared
    @Published var isOffline: Bool = false

    internal var healthCheckTask: Task<Void, Never>?
    private var networkCancellable: AnyCancellable?

    // UI state
    @Published var showAddFeed: Bool = false
    @Published var showSettings: Bool = false
    @Published var showImportOPML: Bool = false
    @Published var showQuickOpen: Bool = false
    @Published var showFeedManager: Bool = false
    @Published var groupByMode: GroupByMode = .date
    @Published var sortOption: ArticleSortOption = .newestFirst
    @Published var hideReadArticles: Bool = false
    @Published var isClusteringLoading: Bool = false
    @Published var readerModeEnabled: Bool = false

    // Pagination state
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreArticles: Bool = true
    @Published var currentArticleOffset: Int = 0
    static let articlesPageSize: Int = 100

    // Server-side grouped articles (for topic/feed modes)
    @Published internal var serverGroupedArticles: [ArticleGroup] = []

    // Multi-selection state
    @Published var selectedFeedIds: Set<Int> = []
    @Published var selectedArticleIds: Set<Int> = []

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
    @Published var showLibrary: Bool = false
    @Published var showNewsletterSetup: Bool = false
    @Published var sidebarVisible: Bool = true

    // MARK: - Dependencies

    let apiClient: APIClient
    let server: PythonServer

    // Native macOS services
    internal let notificationService = NotificationService.shared
    internal let spotlightService = SpotlightService.shared
    internal let dockBadgeService = DockBadgeService.shared
    internal let backgroundRefreshService = BackgroundRefreshService.shared

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
        if groupByMode != .date && !serverGroupedArticles.isEmpty {
            return serverGroupedArticles.map { group in
                ArticleGroup(id: group.id, title: group.title, articles: sortArticles(group.articles))
            }
        }
        return groupArticlesByDate(filteredArticles).map { group in
            ArticleGroup(id: group.id, title: group.title, articles: sortArticles(group.articles))
        }
    }

    private func sortArticles(_ articles: [Article]) -> [Article] {
        switch sortOption {
        case .newestFirst:
            return articles.sorted { ($0.publishedAt ?? $0.createdAt) > ($1.publishedAt ?? $1.createdAt) }
        case .oldestFirst:
            return articles.sorted { ($0.publishedAt ?? $0.createdAt) < ($1.publishedAt ?? $1.createdAt) }
        case .unreadFirst:
            return articles.sorted { a, b in
                if a.isRead != b.isRead {
                    return !a.isRead
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

        switch selectedFilter {
        case .all:
            break
        case .unread:
            break
        case .today:
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            result = result.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }
        case .bookmarked:
            result = result.filter { $0.isBookmarked }
        case .summarized:
            result = result.filter { $0.summaryShort != nil }
        case .unsummarized:
            result = result.filter { $0.summaryShort == nil }
        case .feed(let id):
            result = result.filter { $0.feedId == id }
        }

        if hideReadArticles && selectedFilter != .unread {
            result = result.filter { !$0.isRead }
        }

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

    /// RSS feeds grouped by category (excludes newsletter feeds)
    var feedsByCategory: [(category: String?, feeds: [Feed])] {
        // Exclude newsletter feeds from the RSS section
        let rssFeeds = feeds.filter { !$0.url.absoluteString.hasPrefix("newsletter://") }
        let grouped = Dictionary(grouping: rssFeeds) { $0.category }

        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == nil { return true }
            if key2 == nil { return false }
            return key1! < key2!
        }

        return sortedKeys.map { key in
            (category: key, feeds: grouped[key]!.sorted { $0.name < $1.name })
        }
    }

    /// Newsletter feeds (feeds with newsletter:// URL scheme)
    var newsletterFeeds: [Feed] {
        feeds.filter { $0.url.absoluteString.hasPrefix("newsletter://") }
            .sorted { $0.name < $1.name }
    }

    /// Total unread count across all newsletter feeds
    var newsletterUnreadCount: Int {
        newsletterFeeds.reduce(0) { $0 + $1.unreadCount }
    }

    var categories: [String] {
        // Exclude "Newsletters" category from RSS categories
        Set(feeds.compactMap { $0.category })
            .filter { $0 != "Newsletters" }
            .sorted()
    }

    // MARK: - Initialization

    init() {
        self.apiClient = APIClient()
        self.server = PythonServer()

        loadLocalSettings()

        networkCancellable = networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOffline = !isConnected
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

            let feedURLs = feeds.map { $0.url }
            Task.detached {
                await FaviconService.shared.prefetch(feedURLs: feedURLs)
            }

            updateDockBadge()
            indexArticlesForSpotlight()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
