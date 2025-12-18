import Foundation

/// Feed model (matches FeedResponse from API)
struct Feed: Identifiable, Codable, Hashable {
    let id: Int
    let url: URL
    var name: String
    var category: String?
    var unreadCount: Int
    let lastFetched: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case category
        case unreadCount = "unread_count"
        case lastFetched = "last_fetched"
    }
}

/// Filter options for article list
enum ArticleFilter: Hashable {
    case all
    case unread
    case bookmarked
    case feed(Int)

    var displayName: String {
        switch self {
        case .all: return "All Articles"
        case .unread: return "Unread"
        case .bookmarked: return "Saved"
        case .feed: return "Feed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "circle.fill"
        case .bookmarked: return "star.fill"
        case .feed: return "dot.radiowaves.up.forward"
        }
    }
}

/// Application settings (matches SettingsResponse from API)
struct AppSettings: Codable {
    var refreshIntervalMinutes: Int
    var autoSummarize: Bool
    var markReadOnOpen: Bool
    var defaultModel: String

    enum CodingKeys: String, CodingKey {
        case refreshIntervalMinutes = "refresh_interval_minutes"
        case autoSummarize = "auto_summarize"
        case markReadOnOpen = "mark_read_on_open"
        case defaultModel = "default_model"
    }

    static let `default` = AppSettings(
        refreshIntervalMinutes: 30,
        autoSummarize: true,
        markReadOnOpen: true,
        defaultModel: "haiku"
    )
}

/// API health status
struct APIStatus: Codable {
    let status: String
    let version: String
    let summarizationEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case summarizationEnabled = "summarization_enabled"
    }

    var isHealthy: Bool { status == "ok" }
}

/// Statistics from the API
struct Stats: Codable {
    let totalFeeds: Int
    let totalUnread: Int
    let refreshInProgress: Bool

    enum CodingKeys: String, CodingKey {
        case totalFeeds = "total_feeds"
        case totalUnread = "total_unread"
        case refreshInProgress = "refresh_in_progress"
    }
}
