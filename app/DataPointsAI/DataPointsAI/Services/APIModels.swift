import Foundation

// MARK: - API Error

/// Errors from API calls
enum APIError: Error, LocalizedError, Sendable {
    case networkError(String)
    case invalidResponse
    case serverError(Int, String)
    case decodingError(String)
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .serverNotRunning:
            return "Server is not running"
        }
    }
}

// MARK: - JSON Helper

/// Helper for JSON decoding with custom date formatting
enum JSONHelper {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Use custom date decoding to handle multiple formats:
        // - "yyyy-MM-dd'T'HH:mm:ss" (articles)
        // - "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" (feeds with microseconds)
        // - "yyyy-MM-dd'T'HH:mm:ss+HH:mm" (ISO 8601 with timezone offset)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO 8601 formatter first (handles timezone offsets like +00:00)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try format with microseconds (no timezone)
            let formatterWithMicroseconds = DateFormatter()
            formatterWithMicroseconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            formatterWithMicroseconds.timeZone = TimeZone(identifier: "UTC")
            if let date = formatterWithMicroseconds.date(from: dateString) {
                return date
            }

            // Try format without microseconds (no timezone)
            let formatterWithoutMicroseconds = DateFormatter()
            formatterWithoutMicroseconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            formatterWithoutMicroseconds.timeZone = TimeZone(identifier: "UTC")
            if let date = formatterWithoutMicroseconds.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to parse date: \(dateString)"
                )
            )
        }
        return decoder
    }()

    private static let encoder = JSONEncoder()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}

// MARK: - Article Requests/Responses

extension APIClient {
    /// Extract article content from pre-fetched HTML
    struct ExtractFromHTMLRequest: Encodable {
        let html: String
        let url: String
    }

    struct BookmarkResponse: Codable, Sendable {
        let success: Bool
        let isBookmarked: Bool

        enum CodingKeys: String, CodingKey {
            case success
            case isBookmarked = "is_bookmarked"
        }
    }

    struct BulkMarkReadRequest: Encodable {
        let articleIds: [Int]
        let isRead: Bool

        enum CodingKeys: String, CodingKey {
            case articleIds = "article_ids"
            case isRead = "is_read"
        }
    }

    struct BulkOperationResponse: Codable, Sendable {
        let success: Bool
        let count: Int
    }
}

// MARK: - Feed Requests/Responses

extension APIClient {
    struct BulkDeleteFeedsRequest: Encodable {
        let feedIds: [Int]

        enum CodingKeys: String, CodingKey {
            case feedIds = "feed_ids"
        }
    }

    struct UpdateFeedRequest: Encodable {
        let name: String?
        let category: String?
    }
}

// MARK: - OPML Requests/Responses

extension APIClient {
    struct OPMLImportRequest: Encodable {
        let opmlContent: String

        enum CodingKeys: String, CodingKey {
            case opmlContent = "opml_content"
        }
    }

    struct OPMLImportResult: Codable, Sendable {
        let url: String
        let name: String?
        let success: Bool
        let error: String?
        let feedId: Int?

        enum CodingKeys: String, CodingKey {
            case url
            case name
            case success
            case error
            case feedId = "feed_id"
        }
    }

    struct OPMLImportResponse: Codable, Sendable {
        let total: Int
        let imported: Int
        let skipped: Int
        let failed: Int
        let results: [OPMLImportResult]
    }

    struct OPMLExportResponse: Codable, Sendable {
        let opml: String
        let feedCount: Int

        enum CodingKeys: String, CodingKey {
            case opml
            case feedCount = "feed_count"
        }
    }
}

// MARK: - Article Stats & Archive Responses

extension APIClient {
    struct ArticleStats: Codable, Sendable {
        let total: Int
        let unread: Int
        let bookmarked: Int
        let lastWeek: Int
        let lastMonth: Int
        let olderThanMonth: Int
        let oldestArticle: String?

        enum CodingKeys: String, CodingKey {
            case total
            case unread
            case bookmarked
            case lastWeek = "last_week"
            case lastMonth = "last_month"
            case olderThanMonth = "older_than_month"
            case oldestArticle = "oldest_article"
        }
    }

    struct ArchiveResponse: Codable, Sendable {
        let success: Bool
        let archivedCount: Int
        let days: Int
        let keptBookmarked: Bool
        let keptUnread: Bool

        enum CodingKeys: String, CodingKey {
            case success
            case archivedCount = "archived_count"
            case days
            case keptBookmarked = "kept_bookmarked"
            case keptUnread = "kept_unread"
        }
    }
}

// MARK: - Summarization Requests/Responses

extension APIClient {
    struct SummarizeURLRequest: Encodable {
        let url: String
    }

    struct SummarizeURLResponse: Codable, Sendable {
        let url: String
        let title: String
        let oneLiner: String
        let fullSummary: String
        let keyPoints: [String]
        let modelUsed: String
        let cached: Bool

        enum CodingKeys: String, CodingKey {
            case url
            case title
            case oneLiner = "one_liner"
            case fullSummary = "full_summary"
            case keyPoints = "key_points"
            case modelUsed = "model_used"
            case cached
        }
    }

    struct BatchSummarizeRequest: Encodable {
        let urls: [String]
    }

    struct BatchSummarizeResult: Codable, Sendable {
        let url: String
        let success: Bool
        let title: String?
        let oneLiner: String?
        let fullSummary: String?
        let keyPoints: [String]?
        let modelUsed: String?
        let cached: Bool
        let error: String?

        enum CodingKeys: String, CodingKey {
            case url
            case success
            case title
            case oneLiner = "one_liner"
            case fullSummary = "full_summary"
            case keyPoints = "key_points"
            case modelUsed = "model_used"
            case cached
            case error
        }
    }

    struct BatchSummarizeResponse: Codable, Sendable {
        let total: Int
        let successful: Int
        let failed: Int
        let results: [BatchSummarizeResult]
    }
}

// MARK: - Grouped Articles

extension APIClient {
    struct ArticleGroup: Codable, Sendable {
        let key: String
        let label: String
        let articles: [Article]
    }

    struct GroupedArticlesResponse: Codable, Sendable {
        let groupBy: String
        let groups: [ArticleGroup]

        enum CodingKeys: String, CodingKey {
            case groupBy = "group_by"
            case groups
        }
    }

    enum ArticleGrouping: String {
        case date
        case feed
    }
}

// MARK: - Library Requests/Responses

extension APIClient {
    struct AddLibraryURLRequest: Encodable {
        let url: String
        let title: String?
    }
}

// MARK: - Newsletter Import

extension APIClient {
    struct NewsletterImportResult: Codable, Sendable {
        let success: Bool
        let title: String?
        let author: String?
        let itemId: Int?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case success
            case title
            case author
            case itemId = "item_id"
            case error
        }
    }

    struct NewsletterImportResponse: Codable, Sendable {
        let total: Int
        let imported: Int
        let failed: Int
        let results: [NewsletterImportResult]
    }
}

// MARK: - Gmail IMAP Integration

extension APIClient {
    struct GmailAuthURLResponse: Codable, Sendable {
        let authUrl: String
        let state: String

        enum CodingKeys: String, CodingKey {
            case authUrl = "auth_url"
            case state
        }
    }

    struct GmailStatusResponse: Codable, Sendable {
        let connected: Bool
        let email: String?
        let monitoredLabel: String?
        let pollIntervalMinutes: Int
        let lastFetchedUid: Int
        let isPollingEnabled: Bool
        let lastFetch: String?

        enum CodingKeys: String, CodingKey {
            case connected
            case email
            case monitoredLabel = "monitored_label"
            case pollIntervalMinutes = "poll_interval_minutes"
            case lastFetchedUid = "last_fetched_uid"
            case isPollingEnabled = "is_polling_enabled"
            case lastFetch = "last_fetch"
        }
    }

    struct GmailLabelResponse: Codable, Sendable {
        let labels: [String]
    }

    struct GmailConfigUpdateRequest: Codable, Sendable {
        let monitoredLabel: String?
        let pollIntervalMinutes: Int?
        let isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case monitoredLabel = "monitored_label"
            case pollIntervalMinutes = "poll_interval_minutes"
            case isEnabled = "is_enabled"
        }
    }

    struct GmailFetchResponse: Codable, Sendable {
        let success: Bool
        let imported: Int
        let failed: Int
        let skipped: Int
        let errors: [String]?
        let message: String?
    }
}

// MARK: - Empty Response

/// Empty response for endpoints that don't return data
struct EmptyResponse: Codable, Sendable {
    let success: Bool?
    let message: String?
}

// MARK: - Notification Rules & History

extension APIClient {
    /// Notification rule from the server
    struct NotificationRule: Codable, Sendable, Identifiable {
        let id: Int
        let name: String
        let feedId: Int?
        let feedName: String?
        let keyword: String?
        let author: String?
        let priority: String
        let enabled: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case feedId = "feed_id"
            case feedName = "feed_name"
            case keyword
            case author
            case priority
            case enabled
            case createdAt = "created_at"
        }
    }

    /// Request to create a notification rule
    struct CreateNotificationRuleRequest: Encodable {
        let name: String
        let feedId: Int?
        let keyword: String?
        let author: String?
        let priority: String

        enum CodingKeys: String, CodingKey {
            case name
            case feedId = "feed_id"
            case keyword
            case author
            case priority
        }
    }

    /// Request to update a notification rule
    struct UpdateNotificationRuleRequest: Encodable {
        let name: String?
        let feedId: Int?
        let clearFeed: Bool
        let keyword: String?
        let clearKeyword: Bool
        let author: String?
        let clearAuthor: Bool
        let priority: String?
        let enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case feedId = "feed_id"
            case clearFeed = "clear_feed"
            case keyword
            case clearKeyword = "clear_keyword"
            case author
            case clearAuthor = "clear_author"
            case priority
            case enabled
        }
    }

    /// Notification history entry
    struct NotificationHistoryEntry: Codable, Sendable, Identifiable {
        let id: Int
        let articleId: Int
        let articleTitle: String?
        let ruleId: Int?
        let ruleName: String?
        let notifiedAt: Date
        let dismissed: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case articleId = "article_id"
            case articleTitle = "article_title"
            case ruleId = "rule_id"
            case ruleName = "rule_name"
            case notifiedAt = "notified_at"
            case dismissed
        }
    }

    /// Article that matched a notification rule during refresh
    struct NotificationMatch: Codable, Sendable {
        let articleId: Int
        let articleTitle: String
        let feedId: Int
        let ruleId: Int
        let ruleName: String
        let priority: String
        let matchReason: String

        enum CodingKeys: String, CodingKey {
            case articleId = "article_id"
            case articleTitle = "article_title"
            case feedId = "feed_id"
            case ruleId = "rule_id"
            case ruleName = "rule_name"
            case priority
            case matchReason = "match_reason"
        }
    }

    /// Response containing pending notifications from last refresh
    struct PendingNotificationsResponse: Codable, Sendable {
        let count: Int
        let notifications: [NotificationMatch]
    }
}
