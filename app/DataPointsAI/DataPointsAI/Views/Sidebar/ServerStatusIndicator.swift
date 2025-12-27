import SwiftUI

/// Server status indicator shown at the bottom of the sidebar
struct ServerStatusIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isRestarting = false
    @State private var showHealthDashboard = false

    var body: some View {
        VStack(spacing: 6) {
            // Stats row - unread count and today's articles
            statsRow

            Divider()
                .padding(.horizontal, -12)

            // Feed health summary (if there are issues)
            if feedsWithIssuesCount > 0 {
                Button {
                    showHealthDashboard = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("\(feedsWithIssuesCount) feed\(feedsWithIssuesCount == 1 ? "" : "s") need\(feedsWithIssuesCount == 1 ? "s" : "") attention")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            // Last refresh time (if available)
            if let lastRefresh = appState.lastRefreshTime {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(lastRefreshText(for: lastRefresh))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            // Server status row
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(appState.serverStatus.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isRestarting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else if !appState.serverStatus.isHealthy && appState.serverRunning {
                    Button {
                        Task {
                            await appState.checkServerHealth()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Retry connection")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .contextMenu {
            Button {
                showHealthDashboard = true
            } label: {
                Label("Feed Health Dashboard...", systemImage: "heart.text.square")
            }

            Divider()

            Button {
                Task {
                    isRestarting = true
                    await appState.restartServer()
                    isRestarting = false
                }
            } label: {
                Label("Restart Server", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRestarting)
        }
        .sheet(isPresented: $showHealthDashboard) {
            FeedHealthDashboardView()
        }
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 12) {
            // Unread count
            StatBadge(
                icon: "envelope.badge",
                value: appState.totalUnreadCount,
                label: "unread",
                color: appState.totalUnreadCount > 0 ? .blue : .secondary
            )

            // Today's articles
            StatBadge(
                icon: "sun.max",
                value: appState.todayArticleCount,
                label: "today",
                color: appState.todayArticleCount > 0 ? .orange : .secondary
            )

            // Summarized count
            StatBadge(
                icon: "sparkles",
                value: summarizedCount,
                label: "summarized",
                color: summarizedCount > 0 ? .purple : .secondary
            )

            Spacer()
        }
    }

    private var summarizedCount: Int {
        appState.articles.filter { $0.summaryShort != nil }.count
    }

    private var feedsWithIssuesCount: Int {
        appState.feeds.filter { feed in
            switch feed.healthStatus {
            case .error, .stale:
                return true
            default:
                return false
            }
        }.count
    }

    private func lastRefreshText(for date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Updated just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Updated \(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "Updated \(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Updated \(formatter.string(from: date))"
        }
    }

    private var statusColor: Color {
        switch appState.serverStatus {
        case .healthy(let summarizationEnabled):
            return summarizationEnabled ? .green : .yellow
        case .unhealthy:
            return .red
        case .unknown, .checking:
            return .gray
        }
    }
}

// MARK: - Stat Badge Component

/// Compact stat badge for displaying counts with icons
private struct StatBadge: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text("\(value)")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(color)
        }
        .help("\(value) \(label)")
    }
}
