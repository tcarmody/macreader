import SwiftUI

/// General settings tab
struct GeneralSettingsView: View {
    @Binding var refreshInterval: Int
    @Binding var autoSummarize: Bool
    @Binding var markReadOnOpen: Bool
    @Binding var hideDuplicates: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var autoArchiveEnabled: Bool
    @Binding var autoArchiveDays: Int
    @Binding var archiveKeepBookmarked: Bool
    @Binding var archiveKeepUnread: Bool
    @Binding var backgroundRefreshInterval: RefreshInterval

    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var backgroundRefreshService = BackgroundRefreshService.shared

    let refreshOptions = [15, 30, 60, 120, 240]
    let archiveDaysOptions = [7, 14, 30, 60, 90, 180, 365]

    var body: some View {
        Form {
            Section {
                Picker("Background refresh", selection: $backgroundRefreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .onChange(of: backgroundRefreshInterval) { _, newInterval in
                    backgroundRefreshService.setRefreshInterval(newInterval)
                }

                if backgroundRefreshInterval != .manually {
                    if let lastRefresh = backgroundRefreshService.lastRefreshDate {
                        HStack {
                            Text("Last refresh:")
                            Spacer()
                            Text(formatLastRefresh(lastRefresh))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Feeds will only refresh when you manually trigger a refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Background Refresh")
            } footer: {
                Text("Automatically fetch new articles while the app is running.")
            }

            Section {
                Toggle("Mark articles as read when opened", isOn: $markReadOnOpen)

                Toggle("Hide duplicate articles", isOn: $hideDuplicates)

                if hideDuplicates {
                    Text("Articles with identical content from different feeds will be hidden, keeping only the first occurrence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reading")
            }

            Section {
                Toggle("Auto-summarize new articles", isOn: $autoSummarize)

                if autoSummarize {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Summaries will be generated for every new article during feed refresh. This increases API costs and slows down refreshes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Summaries are generated on demand when you view an article.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Summarization")
            }

            Section {
                Toggle("Show notifications for new articles", isOn: $notificationsEnabled)
                    .disabled(!notificationService.isAuthorized)

                if !notificationService.isAuthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Notifications are disabled in System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle("Auto-archive old articles", isOn: $autoArchiveEnabled)

                if autoArchiveEnabled {
                    Picker("Archive articles older than", selection: $autoArchiveDays) {
                        ForEach(archiveDaysOptions, id: \.self) { days in
                            Text(formatDays(days)).tag(days)
                        }
                    }

                    Toggle("Keep bookmarked articles", isOn: $archiveKeepBookmarked)
                    Toggle("Keep unread articles", isOn: $archiveKeepUnread)

                    Text("Articles will be automatically archived when the app launches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .task {
            await notificationService.checkAuthorizationStatus()
        }
    }

    private func formatDays(_ days: Int) -> String {
        if days < 30 {
            return days == 1 ? "1 day" : "\(days) days"
        } else if days < 365 {
            let months = days / 30
            return months == 1 ? "1 month" : "\(months) months"
        } else {
            let years = days / 365
            return years == 1 ? "1 year" : "\(years) years"
        }
    }

    private func formatInterval(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
    }

    private func formatLastRefresh(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
