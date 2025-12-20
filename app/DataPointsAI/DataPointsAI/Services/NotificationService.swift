import Foundation
import UserNotifications
import Combine

/// Service for managing user notifications about new articles
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("Failed to request notification authorization: \(error)")
            return false
        }
    }

    // MARK: - Notifications

    /// Notify user about new articles
    /// - Parameters:
    ///   - count: Number of new articles
    ///   - feedName: Optional feed name if articles are from a single feed
    func notifyNewArticles(count: Int, feedName: String? = nil) async {
        guard isAuthorized, count > 0 else { return }

        let content = UNMutableNotificationContent()

        if let feedName = feedName {
            content.title = feedName
            content.body = count == 1
                ? "1 new article"
                : "\(count) new articles"
        } else {
            content.title = "New Articles"
            content.body = count == 1
                ? "1 new article available"
                : "\(count) new articles available"
        }

        content.sound = .default
        content.categoryIdentifier = "NEW_ARTICLES"
        content.userInfo = ["count": count]

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "new-articles-\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to deliver notification: \(error)")
        }
    }

    /// Notify about a specific article
    /// - Parameters:
    ///   - title: Article title
    ///   - summary: Optional article summary preview
    ///   - articleId: Article ID for deep linking
    func notifyArticle(title: String, summary: String?, articleId: Int) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        if let summary = summary {
            content.body = summary
        }
        content.sound = .default
        content.categoryIdentifier = "ARTICLE"
        content.userInfo = ["articleId": articleId]

        let request = UNNotificationRequest(
            identifier: "article-\(articleId)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to deliver article notification: \(error)")
        }
    }

    /// Notify about feed refresh failure
    /// - Parameters:
    ///   - feedName: Name of the feed that failed
    ///   - error: Error message
    func notifyRefreshError(feedName: String, error: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Refresh Failed"
        content.body = "\(feedName): \(error)"
        content.sound = .default
        content.categoryIdentifier = "ERROR"

        let request = UNNotificationRequest(
            identifier: "error-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to deliver error notification: \(error)")
        }
    }

    // MARK: - Badge Management

    /// Clear all pending notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Clear notifications for a specific article
    func clearNotification(forArticleId articleId: Int) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["article-\(articleId)"]
        )
    }
}

// MARK: - Notification Categories

extension NotificationService {
    /// Setup notification categories with actions
    func setupNotificationCategories() {
        // New articles category
        let openAction = UNNotificationAction(
            identifier: "OPEN_APP",
            title: "Open",
            options: [.foreground]
        )

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ",
            title: "Mark as Read",
            options: []
        )

        let newArticlesCategory = UNNotificationCategory(
            identifier: "NEW_ARTICLES",
            actions: [openAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )

        // Article category
        let bookmarkAction = UNNotificationAction(
            identifier: "BOOKMARK",
            title: "Bookmark",
            options: []
        )

        let articleCategory = UNNotificationCategory(
            identifier: "ARTICLE",
            actions: [openAction, bookmarkAction],
            intentIdentifiers: [],
            options: []
        )

        // Error category
        let errorCategory = UNNotificationCategory(
            identifier: "ERROR",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            newArticlesCategory,
            articleCategory,
            errorCategory
        ])
    }
}
