import Foundation
import AppKit

// MARK: - HTML Entity Decoding

extension String {
    /// Decodes HTML entities (numeric and named) to their character equivalents
    var htmlDecoded: String {
        guard contains("&") else { return self }

        // Use NSAttributedString for comprehensive HTML entity decoding
        guard let data = self.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }

        return attributedString.string
    }
}

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

    // Enhanced metadata
    let readingTimeMinutes: Int?
    let author: String?

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
        case readingTimeMinutes = "reading_time_minutes"
        case author
    }

    /// The best URL to open - prefers source URL over aggregator URL
    var originalUrl: URL { sourceUrl ?? url }

    /// Title with HTML entities decoded (smart quotes, etc.)
    var displayTitle: String { title.htmlDecoded }

    /// Preview text for article list
    var summaryPreview: String? { summaryShort }

    /// Formatted reading time string (e.g., "5 min")
    var readingTimeDisplay: String? {
        guard let minutes = readingTimeMinutes, minutes > 0 else { return nil }
        return "\(minutes) min"
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

    // Enhanced extraction metadata
    let author: String?
    let readingTimeMinutes: Int?
    let wordCountValue: Int?
    let featuredImage: String?
    let hasCodeBlocks: Bool?
    let siteName: String?

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
        case author
        case readingTimeMinutes = "reading_time_minutes"
        case wordCountValue = "word_count"
        case featuredImage = "featured_image"
        case hasCodeBlocks = "has_code_blocks"
        case siteName = "site_name"
    }

    /// The best URL to open - prefers source URL over aggregator URL
    var originalUrl: URL { sourceUrl ?? url }

    /// Title with HTML entities decoded (smart quotes, etc.)
    var displayTitle: String { title.htmlDecoded }

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

    /// Estimated reading time - uses API-provided value or calculates from content
    var estimatedReadTime: String? {
        // Prefer API-provided reading time
        if let minutes = readingTimeMinutes, minutes > 0 {
            return "\(minutes) min read"
        }

        // Fall back to calculating from content
        guard let content = content, !content.isEmpty else { return nil }

        // Strip HTML tags to get plain text
        let plainText = content.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Count words (split by whitespace)
        let words = plainText.split { $0.isWhitespace }
        let wc = words.count

        // Calculate minutes at 225 wpm (matching backend)
        let minutes = max(1, Int(ceil(Double(wc) / 225.0)))

        return "\(minutes) min read"
    }

    /// Word count of the article content - uses API-provided value or calculates
    var wordCount: Int? {
        // Prefer API-provided word count
        if let wc = wordCountValue, wc > 0 {
            return wc
        }

        // Fall back to calculating from content
        guard let content = content, !content.isEmpty else { return nil }

        let plainText = content.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        return plainText.split { $0.isWhitespace }.count
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

/// How to sort articles within groups
enum ArticleSortOption: String, CaseIterable, Sendable {
    case newestFirst = "newest"
    case oldestFirst = "oldest"
    case unreadFirst = "unread"
    case titleAZ = "title_az"
    case titleZA = "title_za"

    var label: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        case .unreadFirst: return "Unread First"
        case .titleAZ: return "Title A-Z"
        case .titleZA: return "Title Z-A"
        }
    }

    var iconName: String {
        switch self {
        case .newestFirst: return "arrow.down.circle"
        case .oldestFirst: return "arrow.up.circle"
        case .unreadFirst: return "envelope.badge"
        case .titleAZ: return "textformat.abc"
        case .titleZA: return "textformat.abc"
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


// MARK: - Library (Standalone Items)

/// Content type for library items
enum LibraryContentType: String, Codable, CaseIterable, Sendable {
    case url = "url"
    case pdf = "pdf"
    case docx = "docx"
    case txt = "txt"
    case md = "md"
    case html = "html"

    var label: String {
        switch self {
        case .url: return "URL"
        case .pdf: return "PDF"
        case .docx: return "Document"
        case .txt: return "Text"
        case .md: return "Markdown"
        case .html: return "HTML"
        }
    }

    var iconName: String {
        switch self {
        case .url: return "link"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .txt: return "doc.plaintext"
        case .md: return "text.quote"
        case .html: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Library item for list view (matches StandaloneItemResponse from API)
struct LibraryItem: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let url: URL
    let title: String
    let summaryShort: String?
    var isRead: Bool
    var isBookmarked: Bool
    let contentType: String?
    let fileName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case summaryShort = "summary_short"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case contentType = "content_type"
        case fileName = "file_name"
        case createdAt = "created_at"
    }

    /// Parsed content type enum
    var type: LibraryContentType {
        guard let contentType = contentType else { return .url }
        return LibraryContentType(rawValue: contentType) ?? .url
    }

    /// Display name - use filename for uploads, title for URLs
    var displayName: String {
        fileName ?? title
    }

    /// Human-readable time since created
    var timeAgo: String {
        formatTimeAgo(createdAt)
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
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

/// Library item with full content for detail view (matches StandaloneItemDetailResponse from API)
struct LibraryItemDetail: Identifiable, Codable, Sendable {
    let id: Int
    let url: URL
    let title: String
    let content: String?
    let summaryShort: String?
    let summaryFull: String?
    let keyPoints: [String]?
    var isRead: Bool
    var isBookmarked: Bool
    let contentType: String?
    let fileName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case content
        case summaryShort = "summary_short"
        case summaryFull = "summary_full"
        case keyPoints = "key_points"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case contentType = "content_type"
        case fileName = "file_name"
        case createdAt = "created_at"
    }

    /// Parsed content type enum
    var type: LibraryContentType {
        guard let contentType = contentType else { return .url }
        return LibraryContentType(rawValue: contentType) ?? .url
    }

    /// Display name - use filename for uploads, title for URLs
    var displayName: String {
        fileName ?? title
    }
}

/// Response from library list API
struct LibraryListResponse: Codable, Sendable {
    let items: [LibraryItem]
    let total: Int
}

/// Library statistics
struct LibraryStats: Codable, Sendable {
    let totalItems: Int
    let byType: [String: Int]

    enum CodingKeys: String, CodingKey {
        case totalItems = "total_items"
        case byType = "by_type"
    }
}
