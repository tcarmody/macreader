import Foundation
import AppKit

// MARK: - Article Operations
extension AppState {

    func loadArticlesForCurrentFilter(offset: Int = 0) async throws -> [Article] {
        let hideDupes = settings.hideDuplicates
        let limit = Self.articlesPageSize

        switch selectedFilter {
        case .all:
            return try await apiClient.getArticles(hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .unread:
            return try await apiClient.getArticles(unreadOnly: true, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .today:
            let allArticles = try await apiClient.getArticles(hideDuplicates: hideDupes, limit: limit, offset: offset)
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            return allArticles.filter { ($0.publishedAt ?? $0.createdAt) >= startOfToday }
        case .bookmarked:
            return try await apiClient.getArticles(bookmarkedOnly: true, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .featured:
            return try await apiClient.getArticles(featuredOnly: true, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .summarized:
            return try await apiClient.getArticles(summarizedOnly: true, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .unsummarized:
            return try await apiClient.getArticles(summarizedOnly: false, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .feed(let id):
            return try await apiClient.getArticles(feedId: id, hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .topic:
            return try await apiClient.getArticles(hideDuplicates: hideDupes, limit: limit, offset: offset)
        case .savedSearch(_, let query):
            return try await apiClient.search(query: query, limit: limit, includeSummaries: searchIncludeSummaries)
        }
    }

    func reloadArticles() async {
        do {
            // Reset pagination state
            currentArticleOffset = 0
            hasMoreArticles = true

            let newArticles = try await loadArticlesForCurrentFilter()
            articles = newArticles

            // If we got fewer than page size, no more to load
            hasMoreArticles = newArticles.count >= Self.articlesPageSize
            currentArticleOffset = newArticles.count
        } catch {
            self.error = error.localizedDescription
        }

        // Refresh sidebar data in background (non-critical)
        await loadCurrentTopics()
        await loadSavedSearches()
    }

    /// Load more articles for infinite scroll pagination
    func loadMoreArticles() async {
        guard !isLoadingMore && hasMoreArticles else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let moreArticles = try await loadArticlesForCurrentFilter(offset: currentArticleOffset)

            if moreArticles.isEmpty {
                hasMoreArticles = false
            } else {
                // Append new articles, avoiding duplicates
                let existingIds = Set(articles.map { $0.id })
                let uniqueNewArticles = moreArticles.filter { !existingIds.contains($0.id) }
                articles.append(contentsOf: uniqueNewArticles)
                currentArticleOffset += moreArticles.count
                hasMoreArticles = moreArticles.count >= Self.articlesPageSize
            }
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

    /// Open the Feature dialog for the given article (or use the currently-loaded list version).
    func beginFeatureFlow(for article: Article) {
        featureFlowArticle = articles.first(where: { $0.id == article.id }) ?? article
    }

    func featureArticle(articleId: Int, note: String?) async throws {
        let detail = try await apiClient.featureArticle(articleId: articleId, note: note)
        applyFeaturedState(from: detail)
    }

    func unfeatureArticle(articleId: Int) async throws {
        let detail = try await apiClient.unfeatureArticle(articleId: articleId)
        applyFeaturedState(from: detail)
    }

    private func applyFeaturedState(from detail: ArticleDetail) {
        if let index = articles.firstIndex(where: { $0.id == detail.id }) {
            articles[index].isFeatured = detail.isFeatured
            articles[index].featuredAt = detail.featuredAt
            articles[index].featuredNote = detail.featuredNote
        }
        if selectedArticleDetail?.id == detail.id {
            selectedArticleDetail?.isFeatured = detail.isFeatured
            selectedArticleDetail?.featuredAt = detail.featuredAt
            selectedArticleDetail?.featuredNote = detail.featuredNote
        }
        // The cap may have evicted other articles. Refetch list cheaply when on Featured.
        if case .featured = selectedFilter {
            Task { await reloadArticles() }
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
        let fetcher = await MainActor.run { AuthenticatedFetcher() }
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

    func loadRelatedLinks(for articleId: Int) async {
        isLoadingRelated = true

        do {
            // Trigger related links fetch
            try await apiClient.findRelatedLinks(articleId: articleId)

            // Poll for completion (wait for background task to finish - success or error)
            for _ in 0..<30 {  // Poll for up to 30 seconds
                try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                let detail = try await apiClient.getArticle(id: articleId)
                // Stop polling when we get either results OR an error
                if detail.relatedLinks != nil || detail.relatedLinksError != nil {
                    if selectedArticleDetail?.id == articleId {
                        selectedArticleDetail = detail
                    }
                    isLoadingRelated = false
                    return
                }
            }

            // Timeout - reload anyway to show what we have
            let detail = try await apiClient.getArticle(id: articleId)
            if selectedArticleDetail?.id == articleId {
                selectedArticleDetail = detail
            }
        } catch {
            // Network error during API call - reload article to show any server-side error
            if let detail = try? await apiClient.getArticle(id: articleId),
               selectedArticleDetail?.id == articleId {
                selectedArticleDetail = detail
            }
        }

        isLoadingRelated = false
    }

    /// Select an article, load its detail, and switch the detail view to a
    /// specific tab. Used by the article-row context menu to jump straight to
    /// Chat / Related / AI tabs. Tab-specific side effects (kicking off a
    /// summary, fetching related links) are handled by ArticleDetailView when
    /// it observes `pendingDetailTab`.
    func openArticle(_ article: Article, tab: DetailTab) async {
        selectedArticle = article
        selectedArticleIds = [article.id]
        await loadArticleDetail(for: article)
        pendingDetailTab = tab
    }

    /// Fire-and-forget summarization request. For regenerate flow, the row
    /// badge / detail view will update on next poll — we don't block or show a
    /// progress indicator in the list.
    func triggerSummarization(articleId: Int) {
        Task {
            try? await apiClient.summarizeArticle(articleId: articleId)
        }
    }

    /// Send an article to the Composer research workbench. Updates the local
    /// article cache so the "In Composer" state is reflected immediately.
    func promoteArticleToComposer(articleId: Int) async throws {
        _ = try await apiClient.promoteToComposer(articleId: articleId)
        let now = ISO8601DateFormatter().string(from: Date())
        if selectedArticleDetail?.id == articleId {
            selectedArticleDetail?.promotedToComposer = now
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

    // MARK: - Saved Searches

    func loadSavedSearches() async {
        do {
            savedSearches = try await apiClient.getSavedSearches()
        } catch {
            // Non-critical — sidebar just won't show saved searches section
        }
    }

    func saveCurrentSearch(name: String) async {
        guard searchQuery.count >= 2 else { return }
        do {
            let saved = try await apiClient.createSavedSearch(
                name: name,
                query: searchQuery,
                includeSummaries: searchIncludeSummaries
            )
            savedSearches.insert(saved, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteSavedSearch(id: Int) async {
        do {
            try await apiClient.deleteSavedSearch(id: id)
            savedSearches.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func activateSavedSearch(_ saved: SavedSearch) async {
        searchQuery = saved.query
        searchIncludeSummaries = saved.includeSummaries
        selectedFilter = .savedSearch(saved.id, saved.query)
        await search(query: saved.query)
        // Update recency in background
        Task {
            try? await apiClient.touchSavedSearch(id: saved.id)
            if let idx = savedSearches.firstIndex(where: { $0.id == saved.id }) {
                let item = savedSearches.remove(at: idx)
                savedSearches.insert(item, at: 0)
            }
        }
    }

    // MARK: - Topics

    func loadCurrentTopics() async {
        do {
            currentTopics = try await apiClient.getCurrentTopics()
        } catch {
            // Non-critical — sidebar just won't show topics section
        }
    }

    // MARK: - Search

    func search(query: String) async {
        guard query.count >= 2 else {
            await reloadArticles()
            return
        }

        do {
            articles = try await apiClient.search(query: query, includeSummaries: searchIncludeSummaries)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Navigation

    /// Navigate to the next article in the list
    func navigateToNextArticle() {
        let allArticles = groupedArticles.flatMap { $0.articles }
        guard !allArticles.isEmpty else { return }

        if let currentId = selectedArticle?.id,
           let currentIndex = allArticles.firstIndex(where: { $0.id == currentId }) {
            let newIndex = min(currentIndex + 1, allArticles.count - 1)
            let article = allArticles[newIndex]
            selectedArticle = article
            selectedArticleIds = [article.id]
            Task {
                await loadArticleDetail(for: article)
            }
        } else {
            // No current selection, start at first
            let article = allArticles[0]
            selectedArticle = article
            selectedArticleIds = [article.id]
            Task {
                await loadArticleDetail(for: article)
            }
        }
    }

    /// Navigate to the previous article in the list
    func navigateToPreviousArticle() {
        let allArticles = groupedArticles.flatMap { $0.articles }
        guard !allArticles.isEmpty else { return }

        if let currentId = selectedArticle?.id,
           let currentIndex = allArticles.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(currentIndex - 1, 0)
            let article = allArticles[newIndex]
            selectedArticle = article
            selectedArticleIds = [article.id]
            Task {
                await loadArticleDetail(for: article)
            }
        } else {
            // No current selection, start at last
            let article = allArticles[allArticles.count - 1]
            selectedArticle = article
            selectedArticleIds = [article.id]
            Task {
                await loadArticleDetail(for: article)
            }
        }
    }

    // MARK: - Copy & Share Operations

    /// Copy article title to clipboard
    func copyArticleTitle() {
        guard let article = selectedArticle else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(article.title, forType: .string)
    }

    /// Copy article summary to clipboard
    func copyArticleSummary() {
        guard let detail = selectedArticleDetail,
              let summary = detail.summaryFull ?? detail.summaryShort else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    /// Share article using native macOS sharing
    func shareArticle() {
        guard let article = selectedArticle else { return }

        // Prepare share items
        var items: [Any] = [article.originalUrl]

        // Add summary text if available
        if let detail = selectedArticleDetail,
           let summary = detail.summaryFull ?? detail.summaryShort, !summary.isEmpty {
            let shareText = "\(article.title)\n\n\(summary)\n\n\(article.originalUrl.absoluteString)"
            items.append(shareText)
        }

        // Show share picker
        let picker = NSSharingServicePicker(items: items)

        // Find the key window and position the picker
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}
