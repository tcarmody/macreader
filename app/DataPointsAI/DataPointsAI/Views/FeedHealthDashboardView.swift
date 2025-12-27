import SwiftUI

/// Dashboard showing health status of all feeds
struct FeedHealthDashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedFeed: Feed?
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with summary
            VStack(spacing: 12) {
                Text("Feed Health")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 24) {
                    HealthSummaryCard(
                        count: healthyCount,
                        label: "Healthy",
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )

                    HealthSummaryCard(
                        count: staleCount,
                        label: "Stale",
                        color: .yellow,
                        icon: "exclamationmark.triangle.fill"
                    )

                    HealthSummaryCard(
                        count: errorCount,
                        label: "Errors",
                        color: .red,
                        icon: "xmark.circle.fill"
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Feed list
            if appState.feeds.isEmpty {
                ContentUnavailableView(
                    "No Feeds",
                    systemImage: "dot.radiowaves.up.forward",
                    description: Text("Add some feeds to see their health status.")
                )
            } else {
                List(sortedFeeds, selection: $selectedFeed) { feed in
                    FeedHealthRow(feed: feed)
                        .tag(feed)
                        .contextMenu {
                            Button {
                                refreshSingleFeed(feed)
                            } label: {
                                Label("Refresh Feed", systemImage: "arrow.clockwise")
                            }

                            Button {
                                NSWorkspace.shared.open(feed.url)
                            } label: {
                                Label("Open Feed URL", systemImage: "safari")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Task {
                                    try? await appState.deleteFeed(feedId: feed.id)
                                }
                            } label: {
                                Label("Delete Feed", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer with actions
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if errorCount > 0 {
                    Button("Retry All Failed") {
                        retryAllFailed()
                    }
                    .disabled(isRefreshing)
                }

                Button {
                    Task {
                        isRefreshing = true
                        try? await appState.refreshFeeds()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Refresh All")
                    }
                }
                .disabled(isRefreshing)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Computed Properties

    /// Regular feeds that need HTTP fetching (excludes Library and Newsletters)
    private var regularFeeds: [Feed] {
        appState.feeds.filter { !$0.isLocalFeed }
    }

    private var healthyCount: Int {
        regularFeeds.filter { $0.healthStatus == .healthy }.count
    }

    private var staleCount: Int {
        regularFeeds.filter { $0.healthStatus == .stale }.count
    }

    private var errorCount: Int {
        regularFeeds.filter {
            if case .error = $0.healthStatus { return true }
            return false
        }.count
    }

    /// Feeds sorted by health status (errors first, then stale, then healthy)
    /// Excludes local feeds (Library, Newsletters) since they don't need HTTP refresh
    private var sortedFeeds: [Feed] {
        regularFeeds.sorted { feed1, feed2 in
            let priority1 = healthPriority(feed1.healthStatus)
            let priority2 = healthPriority(feed2.healthStatus)
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return feed1.name < feed2.name
        }
    }

    private func healthPriority(_ status: FeedHealthStatus) -> Int {
        switch status {
        case .error: return 0
        case .stale: return 1
        case .neverFetched: return 2
        case .healthy: return 3
        }
    }

    // MARK: - Actions

    private func refreshSingleFeed(_ feed: Feed) {
        Task {
            do {
                try await appState.apiClient.refreshFeed(id: feed.id)
                // Reload feeds to get updated status
                appState.feeds = try await appState.apiClient.getFeeds()
            } catch {
                appState.error = error.localizedDescription
            }
        }
    }

    private func retryAllFailed() {
        let failedFeeds = appState.feeds.filter {
            if case .error = $0.healthStatus { return true }
            return false
        }

        Task {
            isRefreshing = true
            for feed in failedFeeds {
                try? await appState.apiClient.refreshFeed(id: feed.id)
            }
            // Reload feeds to get updated status
            appState.feeds = try await appState.apiClient.getFeeds()
            isRefreshing = false
        }
    }
}

/// Summary card showing count of feeds in a health category
struct HealthSummaryCard: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text("\(count)")
                    .fontWeight(.semibold)
            }
            .font(.title3)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Row showing a single feed's health status
struct FeedHealthRow: View {
    let feed: Feed

    var body: some View {
        HStack(spacing: 12) {
            // Health indicator
            Image(systemName: feed.healthStatus.iconName)
                .foregroundStyle(healthColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let lastFetched = feed.lastFetched {
                        Text("Last updated: \(relativeTime(from: lastFetched))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never fetched")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if case .error(let msg) = feed.healthStatus {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(truncatedError(msg))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .help(msg)
                    }
                }
            }

            Spacer()

            Text("\(feed.unreadCount) unread")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var healthColor: Color {
        switch feed.healthStatus {
        case .healthy: return .green
        case .stale: return .yellow
        case .error: return .red
        case .neverFetched: return .gray
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func truncatedError(_ error: String) -> String {
        if error.count > 50 {
            return String(error.prefix(50)) + "..."
        }
        return error
    }
}

#Preview {
    FeedHealthDashboardView()
        .environmentObject(AppState())
}
