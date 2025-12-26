import Foundation

// MARK: - Article Operations
extension AppState {

    func loadArticlesForCurrentFilter() async throws -> [Article] {
        let hideDupes = settings.hideDuplicates

        switch selectedFilter {
        case .all:
            return try await apiClient.getArticles(hideDuplicates: hideDupes)
        case .unread:
            return try await apiClient.getArticles(unreadOnly: true, hideDuplicates: hideDupes)
        case .today:
            let allArticles = try await apiClient.getArticles(hideDuplicates: hideDupes)
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            return allArticles.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }
        case .bookmarked:
            return try await apiClient.getArticles(bookmarkedOnly: true, hideDuplicates: hideDupes)
        case .summarized:
            return try await apiClient.getArticles(summarizedOnly: true, hideDuplicates: hideDupes)
        case .unsummarized:
            return try await apiClient.getArticles(summarizedOnly: false, hideDuplicates: hideDupes)
        case .feed(let id):
            return try await apiClient.getArticles(feedId: id, hideDuplicates: hideDupes)
        }
    }

    func reloadArticles() async {
        do {
            articles = try await loadArticlesForCurrentFilter()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadArticleDetail(for article: Article) async {
        do {
            let detail = try await apiClient.getArticle(id: article.id)

            if let content = detail.content, !content.isEmpty {
                Task.detached {
                    let _ = await ImageCacheService.shared.cacheImagesInContent(content)
                }
            }

            selectedArticleDetail = detail

            if settings.markReadOnOpen && !article.isRead {
                try await markRead(articleId: article.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markRead(articleId: Int, isRead: Bool = true) async throws {
        try await apiClient.markRead(articleId: articleId, isRead: isRead)

        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].isRead = isRead
        }
        if selectedArticleDetail?.id == articleId {
            selectedArticleDetail?.isRead = isRead
        }

        feeds = try await apiClient.getFeeds()
        updateDockBadge()
    }

    func toggleBookmark(articleId: Int) async throws {
        let result = try await apiClient.toggleBookmark(articleId: articleId)

        if let index = articles.firstIndex(where: { $0.id == articleId }) {
            articles[index].isBookmarked = result.isBookmarked
        }
        if selectedArticleDetail?.id == articleId {
            selectedArticleDetail?.isBookmarked = result.isBookmarked
        }
    }

    func summarizeArticle(articleId: Int) async throws {
        try await apiClient.summarizeArticle(articleId: articleId)

        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let detail = try await apiClient.getArticle(id: articleId)
            if detail.summaryFull != nil {
                if selectedArticleDetail?.id == articleId {
                    self.selectedArticleDetail = detail
                }
                return
            }
        }

        let detail = try await apiClient.getArticle(id: articleId)
        if selectedArticleDetail?.id == articleId {
            self.selectedArticleDetail = detail
        }
    }

    func fetchArticleContent(articleId: Int) async throws {
        let detail = try await apiClient.fetchArticleContent(articleId: articleId)
        selectedArticleDetail = detail
    }

    func fetchArticleContentAuthenticated(articleId: Int, url: URL) async throws {
        let fetcher = AuthenticatedFetcher()
        let result = await fetcher.fetch(url: url)

        if result.success {
            let detail = try await apiClient.extractFromHTML(
                articleId: articleId,
                html: result.html,
                url: result.finalURL.absoluteString
            )
            selectedArticleDetail = detail
        } else {
            throw APIError.networkError(result.error ?? "Failed to fetch page with authentication")
        }
    }

    // MARK: - Bulk Article Actions

    func bulkMarkRead(articleIds: [Int], isRead: Bool = true) async throws {
        guard !articleIds.isEmpty else { return }

        try await apiClient.bulkMarkRead(articleIds: articleIds, isRead: isRead)

        for articleId in articleIds {
            if let index = articles.firstIndex(where: { $0.id == articleId }) {
                articles[index].isRead = isRead
            }
        }
        if let detail = selectedArticleDetail, articleIds.contains(detail.id) {
            selectedArticleDetail?.isRead = isRead
        }

        feeds = try await apiClient.getFeeds()
        updateDockBadge()
    }

    func markFeedRead(feedId: Int, isRead: Bool = true) async throws {
        try await apiClient.markFeedRead(feedId: feedId, isRead: isRead)

        for i in articles.indices where articles[i].feedId == feedId {
            articles[i].isRead = isRead
        }
        if let detail = selectedArticleDetail, detail.feedId == feedId {
            selectedArticleDetail?.isRead = isRead
        }

        feeds = try await apiClient.getFeeds()
        updateDockBadge()
    }

    func markAllRead(isRead: Bool = true) async throws {
        try await apiClient.markAllRead(isRead: isRead)

        for i in articles.indices {
            articles[i].isRead = isRead
        }
        selectedArticleDetail?.isRead = isRead

        feeds = try await apiClient.getFeeds()
        updateDockBadge()
    }

    // MARK: - Search

    func search(query: String) async {
        guard query.count >= 2 else {
            await reloadArticles()
            return
        }

        do {
            articles = try await apiClient.search(query: query)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
