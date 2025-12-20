import Foundation

/// Article for list view (matches ArticleResponse from API)
struct Article: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let feedId: Int
    let url: URL
    let sourceUrl: URL?  // Original URL for aggregator articles
    let title: String
    let summaryShort: String?
    var isRead: Bool
    var isBookmarked: Bool
    let publishedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case feedId = "feed_id"
        case url
        case sourceUrl = "source_url"
        case title
        case summaryShort = "summary_short"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case publishedAt = "published_at"
        case createdAt = "created_at"
    }

    /// The best URL to open - prefers source URL over aggregator URL
    var originalUrl: URL { sourceUrl ?? url }

    /// Preview text for article list
    var summaryPreview: String? { summaryShort }

    /// Human-readable time since published
    var timeAgo: String {
        guard let published = publishedAt else {
            return formatDate(createdAt)
        }
        return formatTimeAgo(published)
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            return formatDate(date)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// Article with full summary for detail view (matches ArticleDetailResponse from API)
struct ArticleDetail: Identifiable, Codable, Sendable {
    let id: Int
    let feedId: Int
    let url: URL
    let sourceUrl: URL?  // Original URL for aggregator articles
    let title: String
    let content: String?
    let summaryShort: String?
    let summaryFull: String?
    let keyPoints: [String]?
    var isRead: Bool
    var isBookmarked: Bool
    let publishedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case feedId = "feed_id"
        case url
        case sourceUrl = "source_url"
        case title
        case content
        case summaryShort = "summary_short"
        case summaryFull = "summary_full"
        case keyPoints = "key_points"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case publishedAt = "published_at"
        case createdAt = "created_at"
    }

    /// The best URL to open - prefers source URL over aggregator URL
    var originalUrl: URL { sourceUrl ?? url }

    /// Human-readable time since published
    var timeAgo: String {
        guard let published = publishedAt else {
            return formatDate(createdAt)
        }
        return formatTimeAgo(published)
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            return formatDate(date)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// Group of articles for display
struct ArticleGroup: Identifiable, Sendable {
    let id: String
    let title: String  // "Today", "Yesterday", "AI & Technology", etc.
    let articles: [Article]
}

/// How to group articles in the list view
enum GroupByMode: String, CaseIterable, Sendable {
    case date = "date"
    case feed = "feed"
    case topic = "topic"

    var label: String {
        switch self {
        case .date: return "Date"
        case .feed: return "Feed"
        case .topic: return "Topic"
        }
    }

    var menuLabel: String {
        switch self {
        case .date: return "Group by Date"
        case .feed: return "Group by Feed"
        case .topic: return "Group by Topic"
        }
    }

    var iconName: String {
        switch self {
        case .date: return "calendar"
        case .feed: return "newspaper"
        case .topic: return "sparkles"
        }
    }
}

/// Response from grouped articles API
struct GroupedArticlesResponse: Codable, Sendable {
    let groupBy: String
    let groups: [ArticleGroupResponse]

    enum CodingKeys: String, CodingKey {
        case groupBy = "group_by"
        case groups
    }
}

/// Single group in grouped response
struct ArticleGroupResponse: Codable, Sendable {
    let key: String
    let label: String
    let articles: [Article]
}
