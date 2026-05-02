import SwiftUI

/// Server status indicator shown at the bottom of the sidebar
struct ServerStatusIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isRestarting = false
    @State private var showHealthDashboard = false
    @State private var syncRotation: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            // Sync status with animation
            syncStatusRow

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

    // MARK: - Sync Status Row

    @ViewBuilder
    private var syncStatusRow: some View {
        HStack(spacing: 4) {
            if appState.isSyncing {
                // Animated sync icon
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(syncRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            syncRotation = 360
                        }
                    }
                    .onDisappear {
                        syncRotation = 0
                    }

                Text("Syncing feeds...")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            } else if let lastRefresh = appState.lastRefreshTime {
                // Last refresh time
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(lastRefreshText(for: lastRefresh))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // New articles badge
                if appState.newArticlesSinceLastCheck > 0 {
                    Text("+\(appState.newArticlesSinceLastCheck) new")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isSyncing)
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

