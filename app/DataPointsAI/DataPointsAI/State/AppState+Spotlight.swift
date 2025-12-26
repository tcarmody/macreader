import Foundation
import CoreSpotlight

// MARK: - Native macOS Integration
extension AppState {

    internal func updateDockBadge() {
        dockBadgeService.updateBadge(unreadCount: totalUnreadCount)
    }

    internal func indexArticlesForSpotlight() {
        let feedNames = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0.name) })
        spotlightService.indexArticles(articles, feedNames: feedNames)
    }

    func openArticleFromSpotlight(articleId: Int) async {
        if let article = articles.first(where: { $0.id == articleId }) {
            selectedArticle = article
            await loadArticleDetail(for: article)
        } else {
            do {
                let detail = try await apiClient.getArticle(id: articleId)
                let article = Article(
                    id: detail.id,
                    feedId: detail.feedId,
                    url: detail.url,
                    sourceUrl: detail.sourceUrl,
                    title: detail.title,
                    summaryShort: detail.summaryShort,
                    isRead: detail.isRead,
                    isBookmarked: detail.isBookmarked,
                    publishedAt: detail.publishedAt,
                    createdAt: detail.createdAt,
                    readingTimeMinutes: detail.readingTimeMinutes,
                    author: detail.author
                )
                selectedArticle = article
                selectedArticleDetail = detail
            } catch {
                self.error = "Could not open article: \(error.localizedDescription)"
            }
        }
    }

    func requestNotificationPermission() async -> Bool {
        return await notificationService.requestAuthorization()
    }
}
