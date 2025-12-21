import Foundation

/// Feed model (matches FeedResponse from API)
struct Feed: Identifiable, Codable, Hashable, Sendable {
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
struct AppSettings: Codable, Sendable {
    var refreshIntervalMinutes: Int
    var autoSummarize: Bool
    var markReadOnOpen: Bool
    var defaultModel: String

    // Client-side only settings (not synced with backend)
    var notificationsEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case refreshIntervalMinutes = "refresh_interval_minutes"
        case autoSummarize = "auto_summarize"
        case markReadOnOpen = "mark_read_on_open"
        case defaultModel = "default_model"
        // notificationsEnabled is not sent to/from API
    }

    static let `default` = AppSettings(
        refreshIntervalMinutes: 30,
        autoSummarize: false,
        markReadOnOpen: true,
        defaultModel: "haiku",
        notificationsEnabled: true
    )
}

/// API health status
struct APIStatus: Codable, Sendable {
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

/// Server health status for UI display
enum ServerHealthStatus: Equatable {
    case unknown
    case healthy(summarizationEnabled: Bool)
    case unhealthy(error: String)
    case checking

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .unknown: return "Unknown"
        case .healthy(let summarizationEnabled):
            return summarizationEnabled ? "Connected" : "Connected (no API key)"
        case .unhealthy(let error): return "Error: \(error)"
        case .checking: return "Checking..."
        }
    }

    var statusColor: String {
        switch self {
        case .healthy(let summarizationEnabled):
            return summarizationEnabled ? "green" : "yellow"
        case .unhealthy: return "red"
        case .unknown, .checking: return "gray"
        }
    }
}

/// Statistics from the API
struct Stats: Codable, Sendable {
    let totalFeeds: Int
    let totalUnread: Int
    let refreshInProgress: Bool

    enum CodingKeys: String, CodingKey {
        case totalFeeds = "total_feeds"
        case totalUnread = "total_unread"
        case refreshInProgress = "refresh_in_progress"
    }
}
