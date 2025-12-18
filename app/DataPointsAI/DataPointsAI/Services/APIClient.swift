import Foundation

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

/// Helper for JSON decoding outside of actor context
private enum JSONHelper {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Use custom date decoding to handle both formats:
        // - "yyyy-MM-dd'T'HH:mm:ss" (articles)
        // - "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" (feeds with microseconds)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try format with microseconds first (more specific)
            let formatterWithMicroseconds = DateFormatter()
            formatterWithMicroseconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            formatterWithMicroseconds.timeZone = TimeZone(identifier: "UTC")
            if let date = formatterWithMicroseconds.date(from: dateString) {
                return date
            }

            // Try format without microseconds
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

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
}

/// Client for communicating with Python backend
actor APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:5005")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Health

    func healthCheck() async throws -> APIStatus {
        return try await get(path: "/status")
    }

    // MARK: - Articles

    func getArticles(
        feedId: Int? = nil,
        unreadOnly: Bool = false,
        bookmarkedOnly: Bool = false,
        limit: Int = 50
    ) async throws -> [Article] {
        var queryItems: [URLQueryItem] = []

        if let feedId = feedId {
            queryItems.append(URLQueryItem(name: "feed_id", value: String(feedId)))
        }
        if unreadOnly {
            queryItems.append(URLQueryItem(name: "unread_only", value: "true"))
        }
        if bookmarkedOnly {
            queryItems.append(URLQueryItem(name: "bookmarked_only", value: "true"))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))

        return try await get(path: "/articles", queryItems: queryItems)
    }

    func getArticle(id: Int) async throws -> ArticleDetail {
        return try await get(path: "/articles/\(id)")
    }

    func fetchArticleContent(articleId: Int) async throws -> ArticleDetail {
        return try await post(path: "/articles/\(articleId)/fetch-content")
    }

    func markRead(articleId: Int, isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))

        let _: EmptyResponse = try await post(
            path: "/articles/\(articleId)/read",
            queryItems: queryItems
        )
    }

    struct BookmarkResponse: Codable, Sendable {
        let success: Bool
        let isBookmarked: Bool

        enum CodingKeys: String, CodingKey {
            case success
            case isBookmarked = "is_bookmarked"
        }
    }

    func toggleBookmark(articleId: Int) async throws -> BookmarkResponse {
        return try await post(path: "/articles/\(articleId)/bookmark")
    }

    func summarizeArticle(articleId: Int) async throws {
        let _: EmptyResponse = try await post(path: "/articles/\(articleId)/summarize")
    }

    // MARK: - Bulk Article Operations

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

    func bulkMarkRead(articleIds: [Int], isRead: Bool = true) async throws {
        let _: BulkOperationResponse = try await post(
            path: "/articles/bulk/read",
            body: BulkMarkReadRequest(articleIds: articleIds, isRead: isRead)
        )
    }

    func markFeedRead(feedId: Int, isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))
        let _: BulkOperationResponse = try await post(
            path: "/articles/feed/\(feedId)/read",
            queryItems: queryItems
        )
    }

    func markAllRead(isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))
        let _: BulkOperationResponse = try await post(
            path: "/articles/all/read",
            queryItems: queryItems
        )
    }

    // MARK: - Feeds

    func getFeeds() async throws -> [Feed] {
        return try await get(path: "/feeds")
    }

    func addFeed(url: String, name: String? = nil) async throws -> Feed {
        struct AddFeedRequest: Encodable {
            let url: String
            let name: String?
        }
        return try await post(
            path: "/feeds",
            body: AddFeedRequest(url: url, name: name)
        )
    }

    func deleteFeed(id: Int) async throws {
        let _: EmptyResponse = try await delete(path: "/feeds/\(id)")
    }

    struct BulkDeleteFeedsRequest: Encodable {
        let feedIds: [Int]

        enum CodingKeys: String, CodingKey {
            case feedIds = "feed_ids"
        }
    }

    func bulkDeleteFeeds(ids: [Int]) async throws {
        let _: BulkOperationResponse = try await post(
            path: "/feeds/bulk/delete",
            body: BulkDeleteFeedsRequest(feedIds: ids)
        )
    }

    struct UpdateFeedRequest: Encodable {
        let name: String?
        let category: String?
    }

    func updateFeed(id: Int, name: String?, category: String? = nil) async throws -> Feed {
        return try await put(
            path: "/feeds/\(id)",
            body: UpdateFeedRequest(name: name, category: category)
        )
    }

    func refreshFeeds() async throws {
        let _: EmptyResponse = try await post(path: "/feeds/refresh")
    }

    func refreshFeed(id: Int) async throws {
        let _: EmptyResponse = try await post(path: "/feeds/\(id)/refresh")
    }

    // MARK: - OPML Import/Export

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

    func importOPML(content: String) async throws -> OPMLImportResponse {
        return try await post(
            path: "/feeds/import-opml",
            body: OPMLImportRequest(opmlContent: content),
            timeout: 300  // 5 minutes for large OPML files
        )
    }

    func exportOPML() async throws -> OPMLExportResponse {
        return try await get(path: "/feeds/export-opml")
    }

    // MARK: - Search

    func search(query: String, limit: Int = 20) async throws -> [Article] {
        let queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await get(path: "/search", queryItems: queryItems)
    }

    // MARK: - Settings

    func getSettings() async throws -> AppSettings {
        return try await get(path: "/settings")
    }

    func updateSettings(_ settings: AppSettings) async throws -> AppSettings {
        return try await put(path: "/settings", body: settings)
    }

    // MARK: - Stats

    func getStats() async throws -> Stats {
        return try await get(path: "/stats")
    }

    // MARK: - Summarization

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

    func summarizeURL(_ url: String) async throws -> SummarizeURLResponse {
        return try await post(
            path: "/summarize",
            body: SummarizeURLRequest(url: url)
        )
    }

    // MARK: - Batch Summarization

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

    func batchSummarize(urls: [String]) async throws -> BatchSummarizeResponse {
        return try await post(
            path: "/summarize/batch",
            body: BatchSummarizeRequest(urls: urls),
            timeout: 300  // 5 minutes for batch processing
        )
    }

    // MARK: - Grouped Articles

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

    func getArticlesGrouped(
        by grouping: ArticleGrouping = .date,
        unreadOnly: Bool = false,
        limit: Int = 100
    ) async throws -> GroupedArticlesResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "group_by", value: grouping.rawValue),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if unreadOnly {
            queryItems.append(URLQueryItem(name: "unread_only", value: "true"))
        }

        return try await get(path: "/articles/grouped", queryItems: queryItems)
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response, data: data)
        do {
            return try JSONHelper.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            let errorMessage = Self.formatDecodingError(decodingError)
            print("❌ Decoding error for \(path): \(errorMessage)")
            if let jsonString = String(data: data.prefix(500), encoding: .utf8) {
                print("📄 JSON preview: \(jsonString)...")
            }
            throw APIError.decodingError(errorMessage)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func post<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        do {
            return try JSONHelper.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONHelper.encode(body)

        if let timeout = timeout {
            request.timeoutInterval = timeout
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        do {
            return try JSONHelper.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func put<T: Decodable, B: Encodable>(
        path: String,
        body: B
    ) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONHelper.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        do {
            return try JSONHelper.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func delete<T: Decodable>(path: String) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        do {
            return try JSONHelper.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func buildURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }
    }

    private static func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Value not found: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .keyNotFound(let key, let context):
            return "Key not found: '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// Empty response for endpoints that don't return data
private struct EmptyResponse: Codable, Sendable {
    let success: Bool?
    let message: String?
}
