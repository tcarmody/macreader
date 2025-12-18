import Foundation

/// Article for list view (matches ArticleResponse from API)
struct Article: Identifiable, Codable, Hashable {
    let id: Int
    let feedId: Int
    let url: URL
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
        case title
        case summaryShort = "summary_short"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case publishedAt = "published_at"
        case createdAt = "created_at"
    }

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
struct ArticleDetail: Identifiable, Codable {
    let id: Int
    let feedId: Int
    let url: URL
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

/// Group of articles for time-based display
struct ArticleGroup: Identifiable {
    let id: String
    let title: String  // "Today", "Yesterday", "Last Week", etc.
    let articles: [Article]
}
