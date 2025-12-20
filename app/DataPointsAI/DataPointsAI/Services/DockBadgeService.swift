import Foundation
import AppKit
import Combine

/// Service for managing the dock icon badge showing unread count
@MainActor
class DockBadgeService: ObservableObject {
    static let shared = DockBadgeService()

    @Published private(set) var currentBadgeCount: Int = 0

    private init() {}

    // MARK: - Badge Management

    /// Update the dock badge with unread count
    /// - Parameter count: Number of unread articles (0 to hide badge)
    func updateBadge(unreadCount count: Int) {
        currentBadgeCount = count

        if count > 0 {
            NSApplication.shared.dockTile.badgeLabel = formatBadgeNumber(count)
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    /// Clear the dock badge
    func clearBadge() {
        currentBadgeCount = 0
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    /// Increment badge count by a given amount
    /// - Parameter amount: Amount to increment (default 1)
    func incrementBadge(by amount: Int = 1) {
        let newCount = currentBadgeCount + amount
        updateBadge(unreadCount: newCount)
    }

    /// Decrement badge count by a given amount
    /// - Parameter amount: Amount to decrement (default 1)
    func decrementBadge(by amount: Int = 1) {
        let newCount = max(0, currentBadgeCount - amount)
        updateBadge(unreadCount: newCount)
    }

    // MARK: - Helpers

    private func formatBadgeNumber(_ count: Int) -> String {
        if count > 999 {
            return "999+"
        }
        return String(count)
    }
}

// MARK: - Dock Tile Customization

extension DockBadgeService {
    /// Request attention in the dock (bounce icon)
    /// - Parameter critical: If true, bounce until user focuses app
    func requestAttention(critical: Bool = false) {
        let requestType: NSApplication.RequestUserAttentionType = critical ? .criticalRequest : .informationalRequest
        NSApplication.shared.requestUserAttention(requestType)
    }

    /// Cancel attention request
    func cancelAttentionRequest() {
        NSApplication.shared.cancelUserAttentionRequest(0)
    }
}
