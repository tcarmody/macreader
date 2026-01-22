import Foundation

// MARK: - Library Operations
extension AppState {

    func loadLibraryItems() async {
        do {
            let response = try await apiClient.getLibraryItems()
            libraryItems = response.items
            libraryItemCount = response.total
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadLibraryItemDetail(for item: LibraryItem) async {
        do {
            selectedLibraryItemDetail = try await apiClient.getLibraryItem(id: item.id)

            if settings.markReadOnOpen && !item.isRead {
                try await markLibraryItemRead(itemId: item.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addURLToLibrary(url: String, title: String? = nil, autoSummarize: Bool = false) async throws {
        let item = try await apiClient.addURLToLibrary(url: url, title: title, autoSummarize: autoSummarize)
        await loadLibraryItems()

        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
    }

    func uploadFileToLibrary(data: Data, filename: String, title: String? = nil, autoSummarize: Bool = false) async throws {
        let item = try await apiClient.uploadFileToLibrary(data: data, filename: filename, title: title, autoSummarize: autoSummarize)
        await loadLibraryItems()

        selectedLibraryItem = LibraryItem(
            id: item.id,
            url: item.url,
            title: item.title,
            summaryShort: item.summaryShort,
            isRead: item.isRead,
            isBookmarked: item.isBookmarked,
            contentType: item.contentType,
            fileName: item.fileName,
            createdAt: item.createdAt
        )
        selectedLibraryItemDetail = item
    }

    func deleteLibraryItem(itemId: Int) async throws {
        try await apiClient.deleteLibraryItem(id: itemId)

        libraryItems.removeAll { $0.id == itemId }
        libraryItemCount = max(0, libraryItemCount - 1)

        if selectedLibraryItem?.id == itemId {
            selectedLibraryItem = nil
            selectedLibraryItemDetail = nil
        }
    }

    func markLibraryItemRead(itemId: Int, isRead: Bool = true) async throws {
        try await apiClient.markLibraryItemRead(id: itemId, isRead: isRead)

        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isRead = isRead
        }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isRead = isRead
        }
    }

    func toggleLibraryItemBookmark(itemId: Int) async throws {
        let result = try await apiClient.toggleLibraryItemBookmark(id: itemId)

        if let index = libraryItems.firstIndex(where: { $0.id == itemId }) {
            libraryItems[index].isBookmarked = result.isBookmarked
        }
        if selectedLibraryItemDetail?.id == itemId {
            selectedLibraryItemDetail?.isBookmarked = result.isBookmarked
        }
    }

    func summarizeLibraryItem(itemId: Int) async throws {
        try await apiClient.summarizeLibraryItem(id: itemId)

        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let detail = try await apiClient.getLibraryItem(id: itemId)
            if detail.summaryFull != nil {
                if selectedLibraryItemDetail?.id == itemId {
                    self.selectedLibraryItemDetail = detail
                }
                return
            }
        }

        let detail = try await apiClient.getLibraryItem(id: itemId)
        if selectedLibraryItemDetail?.id == itemId {
            self.selectedLibraryItemDetail = detail
        }
    }

    func selectLibrary() {
        showLibrary = true
        showNewsletters = false
        // Don't change selectedFilter - it triggers onChange handler which interferes
        // with library mode. The filter is separate from library view.
        selectedArticle = nil
        selectedArticleDetail = nil
        Task {
            await loadLibraryItems()
        }
    }

    func deselectLibrary() {
        showLibrary = false
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
    }

    // MARK: - Newsletter Operations

    func loadNewsletterItems() async {
        do {
            let response = try await apiClient.getLibraryItems(contentType: "newsletter")
            newsletterItems = response.items
            newsletterCount = response.total
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectNewsletters() {
        showNewsletters = true
        showLibrary = false
        // Don't change selectedFilter - it triggers onChange handler which interferes
        // with newsletters mode. The filter is separate from newsletters view.
        selectedArticle = nil
        selectedArticleDetail = nil
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
        selectedNewsletterFeed = nil
        newsletterArticles = []
    }

    func deselectNewsletters() {
        showNewsletters = false
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil
        selectedNewsletterFeed = nil
        newsletterArticles = []
    }

    /// Select a specific newsletter feed and load its articles
    func selectNewsletterFeed(_ feed: Feed) async {
        showNewsletters = true
        showLibrary = false
        selectedNewsletterFeed = feed
        selectedArticle = nil
        selectedArticleDetail = nil
        selectedLibraryItem = nil
        selectedLibraryItemDetail = nil

        // Load articles for this newsletter feed
        do {
            newsletterArticles = try await apiClient.getArticles(feedId: feed.id)
        } catch {
            self.error = error.localizedDescription
            newsletterArticles = []
        }
    }

    /// Deselect newsletter feed and go back to all newsletters view
    func deselectNewsletterFeed() {
        selectedNewsletterFeed = nil
        newsletterArticles = []
        selectedArticle = nil
        selectedArticleDetail = nil
    }

    /// Toggle collapsed state for a newsletter feed in the sidebar
    func toggleNewsletterFeedCollapsed(_ feedId: Int) {
        if collapsedNewsletterFeeds.contains(feedId) {
            collapsedNewsletterFeeds.remove(feedId)
        } else {
            collapsedNewsletterFeeds.insert(feedId)
        }
    }

    /// Load detail for a newsletter article (from a newsletter feed)
    func loadNewsletterArticleDetail(for article: Article) async {
        do {
            let detail = try await apiClient.getArticle(id: article.id)
            selectedArticleDetail = detail
            selectedArticle = article

            if settings.markReadOnOpen && !article.isRead {
                try await markRead(articleId: article.id)
                // Update local state
                if let index = newsletterArticles.firstIndex(where: { $0.id == article.id }) {
                    newsletterArticles[index].isRead = true
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
