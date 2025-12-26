import SwiftUI

/// Server status indicator shown at the bottom of the sidebar
struct ServerStatusIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isRestarting = false
    @State private var showHealthDashboard = false

    var body: some View {
        VStack(spacing: 4) {
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
