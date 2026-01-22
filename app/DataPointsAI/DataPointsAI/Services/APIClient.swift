import Foundation

/// Client for communicating with Python backend
/// MainActor isolated since it's only used from MainActor contexts (AppState)
@MainActor
final class APIClient {
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
        summarizedOnly: Bool? = nil,
        hideDuplicates: Bool = false,
        limit: Int = 100,
        offset: Int = 0
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
        if let summarizedOnly = summarizedOnly {
            queryItems.append(URLQueryItem(name: "summarized_only", value: String(summarizedOnly)))
        }
        if hideDuplicates {
            queryItems.append(URLQueryItem(name: "hide_duplicates", value: "true"))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        return try await get(path: "/articles", queryItems: queryItems)
    }

    func getArticle(id: Int) async throws -> ArticleDetail {
        return try await get(path: "/articles/\(id)")
    }

    func getGroupedArticles(
        groupBy: String,
        unreadOnly: Bool = false,
        limit: Int = 100
    ) async throws -> GroupedArticlesResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "group_by", value: groupBy),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if unreadOnly {
            queryItems.append(URLQueryItem(name: "unread_only", value: "true"))
        }
        return try await get(path: "/articles/grouped", queryItems: queryItems)
    }

    func fetchArticleContent(articleId: Int) async throws -> ArticleDetail {
        return try await post(path: "/articles/\(articleId)/fetch-content")
    }

    func extractFromHTML(articleId: Int, html: String, url: String) async throws -> ArticleDetail {
        return try await post(
            path: "/articles/\(articleId)/extract-from-html",
            body: ExtractFromHTMLRequest(html: html, url: url),
            timeout: 60  // Content extraction can take time for large pages
        )
    }

    func markRead(articleId: Int, isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))

        let _: EmptyResponse = try await post(
            path: "/articles/\(articleId)/read",
            queryItems: queryItems
        )
    }

    func toggleBookmark(articleId: Int) async throws -> BookmarkResponse {
        return try await post(path: "/articles/\(articleId)/bookmark")
    }

    func summarizeArticle(articleId: Int) async throws {
        let _: EmptyResponse = try await post(path: "/articles/\(articleId)/summarize")
    }

    // MARK: - Bulk Article Operations

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

    func bulkDeleteFeeds(ids: [Int]) async throws {
        let _: BulkOperationResponse = try await post(
            path: "/feeds/bulk/delete",
            body: BulkDeleteFeedsRequest(feedIds: ids)
        )
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

    // MARK: - Article Stats & Archive

    func getArticleStats() async throws -> ArticleStats {
        return try await get(path: "/articles/stats")
    }

    func archiveOldArticles(
        days: Int = 30,
        keepBookmarked: Bool = true,
        keepUnread: Bool = false
    ) async throws -> ArchiveResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "keep_bookmarked", value: String(keepBookmarked)),
            URLQueryItem(name: "keep_unread", value: String(keepUnread))
        ]
        return try await post(path: "/articles/archive", queryItems: queryItems)
    }

    // MARK: - Summarization

    func summarizeURL(_ url: String) async throws -> SummarizeURLResponse {
        return try await post(
            path: "/summarize",
            body: SummarizeURLRequest(url: url)
        )
    }

    // MARK: - Batch Summarization

    func batchSummarize(urls: [String]) async throws -> BatchSummarizeResponse {
        return try await post(
            path: "/summarize/batch",
            body: BatchSummarizeRequest(urls: urls),
            timeout: 300  // 5 minutes for batch processing
        )
    }

    // MARK: - Grouped Articles

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

    // MARK: - Library (Standalone Items)

    func getLibraryItems(
        contentType: String? = nil,
        bookmarkedOnly: Bool = false,
        limit: Int = 100
    ) async throws -> LibraryListResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let contentType = contentType {
            queryItems.append(URLQueryItem(name: "content_type", value: contentType))
        }
        if bookmarkedOnly {
            queryItems.append(URLQueryItem(name: "bookmarked_only", value: "true"))
        }

        return try await get(path: "/standalone", queryItems: queryItems)
    }

    func getLibraryItem(id: Int) async throws -> LibraryItemDetail {
        return try await get(path: "/standalone/\(id)")
    }

    func getLibraryStats() async throws -> LibraryStats {
        return try await get(path: "/standalone/stats")
    }

    func addURLToLibrary(url: String, title: String? = nil, autoSummarize: Bool = false) async throws -> LibraryItemDetail {
        var queryItems: [URLQueryItem] = []
        if autoSummarize {
            queryItems.append(URLQueryItem(name: "auto_summarize", value: "true"))
        }
        return try await post(
            path: "/standalone/url",
            body: AddLibraryURLRequest(url: url, title: title),
            queryItems: queryItems,
            timeout: 60  // URL fetching can take time
        )
    }

    func uploadFileToLibrary(data: Data, filename: String, title: String? = nil, autoSummarize: Bool = false) async throws -> LibraryItemDetail {
        // Build multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Build URL with query params
        var queryItems: [URLQueryItem] = []
        if let title = title {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if autoSummarize {
            queryItems.append(URLQueryItem(name: "auto_summarize", value: "true"))
        }

        let url = buildURL(path: "/standalone/upload", queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120  // File upload can take time

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData)
        return try JSONHelper.decode(LibraryItemDetail.self, from: responseData)
    }

    func deleteLibraryItem(id: Int) async throws {
        let _: EmptyResponse = try await delete(path: "/standalone/\(id)")
    }

    func markLibraryItemRead(id: Int, isRead: Bool = true) async throws {
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "is_read", value: String(isRead)))
        let _: EmptyResponse = try await post(
            path: "/standalone/\(id)/read",
            queryItems: queryItems
        )
    }

    func toggleLibraryItemBookmark(id: Int) async throws -> BookmarkResponse {
        return try await post(path: "/standalone/\(id)/bookmark")
    }

    func summarizeLibraryItem(id: Int) async throws {
        let _: EmptyResponse = try await post(path: "/standalone/\(id)/summarize")
    }

    // MARK: - Newsletter Import / Gmail IMAP

    /// Get Gmail OAuth authorization URL
    func getGmailAuthURL() async throws -> GmailAuthURLResponse {
        return try await get(path: "/gmail/auth/url")
    }

    /// Get Gmail connection status
    func getGmailStatus() async throws -> GmailStatusResponse {
        return try await get(path: "/gmail/status")
    }

    /// Get available Gmail labels
    func getGmailLabels() async throws -> GmailLabelResponse {
        return try await get(path: "/gmail/labels")
    }

    /// Update Gmail configuration
    func updateGmailConfig(label: String? = nil, interval: Int? = nil, enabled: Bool? = nil) async throws -> GmailStatusResponse {
        let request = GmailConfigUpdateRequest(
            monitoredLabel: label,
            pollIntervalMinutes: interval,
            isEnabled: enabled
        )
        return try await put(path: "/gmail/config", body: request)
    }

    /// Trigger Gmail newsletter fetch
    func triggerGmailFetch(fetchAll: Bool = false) async throws -> GmailFetchResponse {
        var queryItems: [URLQueryItem] = []
        if fetchAll {
            queryItems.append(URLQueryItem(name: "fetch_all", value: "true"))
        }
        return try await post(path: "/gmail/fetch", queryItems: queryItems)
    }

    /// Disconnect Gmail account
    func disconnectGmail() async throws {
        let _: EmptyResponse = try await delete(path: "/gmail/disconnect")
    }

    /// Import newsletter emails from .eml file data
    func importNewsletters(files: [(filename: String, data: Data)], autoSummarize: Bool = false) async throws -> NewsletterImportResponse {
        // Build multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(file.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: message/rfc822\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Build URL with query params
        var queryItems: [URLQueryItem] = []
        if autoSummarize {
            queryItems.append(URLQueryItem(name: "auto_summarize", value: "true"))
        }

        let url = buildURL(path: "/standalone/newsletter/import", queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData)
        return try JSONHelper.decode(NewsletterImportResponse.self, from: responseData)
    }

    // MARK: - Notification Rules

    /// Get all notification rules
    func getNotificationRules(enabledOnly: Bool = false) async throws -> [NotificationRule] {
        var queryItems: [URLQueryItem] = []
        if enabledOnly {
            queryItems.append(URLQueryItem(name: "enabled_only", value: "true"))
        }
        return try await get(path: "/notifications/rules", queryItems: queryItems)
    }

    /// Create a notification rule
    func createNotificationRule(
        name: String,
        feedId: Int? = nil,
        keyword: String? = nil,
        author: String? = nil,
        priority: String = "normal"
    ) async throws -> NotificationRule {
        return try await post(
            path: "/notifications/rules",
            body: CreateNotificationRuleRequest(
                name: name,
                feedId: feedId,
                keyword: keyword,
                author: author,
                priority: priority
            )
        )
    }

    /// Update a notification rule
    func updateNotificationRule(
        id: Int,
        name: String? = nil,
        feedId: Int? = nil,
        clearFeed: Bool = false,
        keyword: String? = nil,
        clearKeyword: Bool = false,
        author: String? = nil,
        clearAuthor: Bool = false,
        priority: String? = nil,
        enabled: Bool? = nil
    ) async throws -> NotificationRule {
        return try await put(
            path: "/notifications/rules/\(id)",
            body: UpdateNotificationRuleRequest(
                name: name,
                feedId: feedId,
                clearFeed: clearFeed,
                keyword: keyword,
                clearKeyword: clearKeyword,
                author: author,
                clearAuthor: clearAuthor,
                priority: priority,
                enabled: enabled
            )
        )
    }

    /// Delete a notification rule
    func deleteNotificationRule(id: Int) async throws {
        let _: EmptyResponse = try await delete(path: "/notifications/rules/\(id)")
    }

    // MARK: - Notification History

    /// Get notification history
    func getNotificationHistory(limit: Int = 50, includeDismissed: Bool = false) async throws -> [NotificationHistoryEntry] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if includeDismissed {
            queryItems.append(URLQueryItem(name: "include_dismissed", value: "true"))
        }
        return try await get(path: "/notifications/history", queryItems: queryItems)
    }

    /// Dismiss a notification
    func dismissNotification(historyId: Int) async throws {
        let _: EmptyResponse = try await post(path: "/notifications/history/\(historyId)/dismiss")
    }

    /// Dismiss all notifications
    func dismissAllNotifications() async throws {
        let _: EmptyResponse = try await post(path: "/notifications/history/dismiss-all")
    }

    /// Get pending notifications from last refresh
    func getPendingNotifications() async throws -> PendingNotificationsResponse {
        return try await get(path: "/notifications/pending")
    }

    // MARK: - Reading Statistics

    /// Get comprehensive reading statistics
    func getReadingStats(
        periodType: String = "rolling",
        periodValue: String = "30d"
    ) async throws -> ReadingStatsResponse {
        let queryItems = [
            URLQueryItem(name: "period_type", value: periodType),
            URLQueryItem(name: "period_value", value: periodValue)
        ]
        return try await get(path: "/statistics/reading-stats", queryItems: queryItems)
    }

    /// Trigger topic clustering for recent articles
    func triggerTopicClustering(days: Int = 7, persist: Bool = true) async throws -> TopicClusteringResponse {
        let queryItems = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "persist", value: String(persist))
        ]
        return try await post(path: "/statistics/topics/cluster", queryItems: queryItems)
    }

    /// Get topic frequency trends over time
    func getTopicTrends(days: Int = 30, topN: Int = 10) async throws -> TopicTrendsResponse {
        let queryItems = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "top_n", value: String(topN))
        ]
        return try await get(path: "/statistics/topics/trends", queryItems: queryItems)
    }

    // MARK: - Article Chat

    /// Get chat history for an article
    func getChatHistory(articleId: Int) async throws -> ChatHistoryResponse {
        return try await get(path: "/articles/\(articleId)/chat")
    }

    /// Send a chat message about an article
    func sendChatMessage(articleId: Int, message: String) async throws -> ChatMessage {
        struct ChatRequest: Encodable {
            let message: String
        }
        return try await post(
            path: "/articles/\(articleId)/chat",
            body: ChatRequest(message: message),
            timeout: 120  // Chat responses can take time for complex questions
        )
    }

    /// Clear chat history for an article
    func clearChatHistory(articleId: Int) async throws -> ClearChatResponse {
        return try await delete(path: "/articles/\(articleId)/chat")
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
