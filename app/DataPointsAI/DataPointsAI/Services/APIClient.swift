import Foundation

/// Errors from API calls
enum APIError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingError(Error)
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .serverNotRunning:
            return "Server is not running"
        }
    }
}

/// Client for communicating with Python backend
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = URL(string: "http://127.0.0.1:5005")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared

        self.decoder = JSONDecoder()
        // Don't use automatic snake_case conversion - models have explicit CodingKeys
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        // Don't use automatic snake_case conversion - models have explicit CodingKeys
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

    func markRead(articleId: Int, isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))

        let _: EmptyResponse = try await post(
            path: "/articles/\(articleId)/read",
            queryItems: queryItems
        )
    }

    struct BookmarkResponse: Codable {
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

    func refreshFeeds() async throws {
        let _: EmptyResponse = try await post(path: "/feeds/refresh")
    }

    func refreshFeed(id: Int) async throws {
        let _: EmptyResponse = try await post(path: "/feeds/\(id)/refresh")
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

    struct SummarizeURLResponse: Codable {
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

    // MARK: - HTTP Methods

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response, data: data)
        return try decode(data)
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
        return try decode(data)
    }

    private func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decode(data)
    }

    private func put<T: Decodable, B: Encodable>(
        path: String,
        body: B
    ) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decode(data)
    }

    private func delete<T: Decodable>(path: String) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decode(data)
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

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

/// Empty response for endpoints that don't return data
private struct EmptyResponse: Codable {
    let success: Bool?
    let message: String?
}
