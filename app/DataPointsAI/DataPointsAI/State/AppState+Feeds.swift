import Foundation

// MARK: - Feed Operations
extension AppState {

    func addFeed(url: String, name: String? = nil) async throws {
        let feed = try await apiClient.addFeed(url: url, name: name)
        feeds.append(feed)
        await reloadArticles()
    }

    func deleteFeed(feedId: Int) async throws {
        try await apiClient.deleteFeed(id: feedId)
        feeds.removeAll { $0.id == feedId }

        if case .feed(let id) = selectedFilter, id == feedId {
            selectedFilter = .all
        }

        await reloadArticles()
    }

    func bulkDeleteFeeds(feedIds: [Int]) async throws {
        guard !feedIds.isEmpty else { return }

        try await apiClient.bulkDeleteFeeds(ids: feedIds)

        if case .feed(let id) = selectedFilter, feedIds.contains(id) {
            selectedFilter = .all
        }

        feeds = try await apiClient.getFeeds()
        await reloadArticles()
    }

    func updateFeed(feedId: Int, name: String? = nil, category: String? = nil) async throws {
        let updatedFeed = try await apiClient.updateFeed(id: feedId, name: name, category: category)

        if let index = feeds.firstIndex(where: { $0.id == feedId }) {
            feeds[index] = updatedFeed
        }
    }

    func moveFeedToCategory(feedId: Int, category: String?) async throws {
        try await updateFeed(feedId: feedId, category: category)
    }

    func refreshFeeds() async throws {
        let previousUnreadCount = totalUnreadCount
        isSyncing = true

        defer { isSyncing = false }

        try await apiClient.refreshFeeds()

        let maxAttempts = 60
        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let stats = try? await apiClient.getStats()
            if stats?.refreshInProgress == false {
                break
            }

            if attempt % 5 == 4 {
                await refresh()
            }
        }

        await refresh()
        lastRefreshTime = Date()

        // Track new articles since last check
        let newArticleCount = totalUnreadCount - previousUnreadCount
        if newArticleCount > 0 {
            newArticlesSinceLastCheck = newArticleCount
        }

        // Check for smart notifications (articles matching rules)
        if settings.notificationsEnabled {
            await sendSmartNotifications()
        }

        // Fallback to generic count notification if no smart notifications were sent
        if newArticleCount > 0 && settings.notificationsEnabled {
            // Only send generic notification if we didn't send any smart notifications
            let pending = try? await apiClient.getPendingNotifications()
            if pending?.count == 0 || pending == nil {
                await notificationService.notifyNewArticles(count: newArticleCount)
            }
        }
    }

    /// Fetch and send notifications for articles that matched notification rules
    private func sendSmartNotifications() async {
        do {
            let pending = try await apiClient.getPendingNotifications()

            for match in pending.notifications {
                // Send individual notification for each matched article
                await notificationService.notifyArticle(
                    title: match.articleTitle,
                    summary: match.matchReason,
                    articleId: match.articleId
                )
            }
        } catch {
            print("Failed to fetch pending notifications: \(error)")
        }
    }

    // MARK: - Category Operations

    func toggleCategoryCollapsed(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
        saveWindowState()
    }

    func collapseAllCategories() {
        collapsedCategories = Set(categories)
        saveWindowState()
    }

    func expandAllCategories() {
        collapsedCategories.removeAll()
        saveWindowState()
    }

    func renameCategory(from oldName: String, to newName: String) async throws {
        let feedsInCategory = feeds.filter { $0.category == oldName }
        for feed in feedsInCategory {
            try await updateFeed(feedId: feed.id, category: newName)
        }
    }

    func deleteCategory(_ category: String) async throws {
        let feedsInCategory = feeds.filter { $0.category == category }
        for feed in feedsInCategory {
            let updatedFeed = try await apiClient.updateFeed(id: feed.id, name: nil, category: "")
            if let index = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[index] = updatedFeed
            }
        }
    }

    // MARK: - OPML Import/Export

    func importOPML(content: String) async throws -> APIClient.OPMLImportResponse {
        let result = try await apiClient.importOPML(content: content)
        feeds = try await apiClient.getFeeds()
        await reloadArticles()
        return result
    }

    func importOPML(from fileURL: URL) async throws -> APIClient.OPMLImportResponse {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try await importOPML(content: content)
    }

    func exportOPML() async throws -> String {
        let result = try await apiClient.exportOPML()
        return result.opml
    }
}
