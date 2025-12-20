import SwiftUI

/// Preferences window
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshInterval: Int = 30
    @State private var autoSummarize: Bool = false
    @State private var markReadOnOpen: Bool = true
    @State private var defaultModel: String = "haiku"
    @State private var notificationsEnabled: Bool = true

    var body: some View {
        TabView {
            GeneralSettingsView(
                refreshInterval: $refreshInterval,
                autoSummarize: $autoSummarize,
                markReadOnOpen: $markReadOnOpen,
                notificationsEnabled: $notificationsEnabled
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            AISettingsView(defaultModel: $defaultModel)
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 450, height: 300)
        .onAppear {
            loadSettings()
        }
        .onChange(of: refreshInterval) { _, _ in saveSettings() }
        .onChange(of: autoSummarize) { _, _ in saveSettings() }
        .onChange(of: markReadOnOpen) { _, _ in saveSettings() }
        .onChange(of: defaultModel) { _, _ in saveSettings() }
        .onChange(of: notificationsEnabled) { _, _ in saveSettings() }
    }

    private func loadSettings() {
        refreshInterval = appState.settings.refreshIntervalMinutes
        autoSummarize = appState.settings.autoSummarize
        markReadOnOpen = appState.settings.markReadOnOpen
        defaultModel = appState.settings.defaultModel
        notificationsEnabled = appState.settings.notificationsEnabled
    }

    private func saveSettings() {
        var newSettings = AppSettings(
            refreshIntervalMinutes: refreshInterval,
            autoSummarize: autoSummarize,
            markReadOnOpen: markReadOnOpen,
            defaultModel: defaultModel
        )
        newSettings.notificationsEnabled = notificationsEnabled

        Task {
            try? await appState.updateSettings(newSettings)
        }
    }
}

/// General settings tab
struct GeneralSettingsView: View {
    @Binding var refreshInterval: Int
    @Binding var autoSummarize: Bool
    @Binding var markReadOnOpen: Bool
    @Binding var notificationsEnabled: Bool

    @StateObject private var notificationService = NotificationService.shared

    let refreshOptions = [15, 30, 60, 120, 240]

    var body: some View {
        Form {
            Section {
                Picker("Auto-refresh interval", selection: $refreshInterval) {
                    ForEach(refreshOptions, id: \.self) { minutes in
                        Text(formatInterval(minutes)).tag(minutes)
                    }
                }
            } header: {
                Text("Refresh")
            }

            Section {
                Toggle("Mark articles as read when opened", isOn: $markReadOnOpen)
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
        }
        .formStyle(.grouped)
        .task {
            await notificationService.checkAuthorizationStatus()
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
}

/// AI settings tab
struct AISettingsView: View {
    @Binding var defaultModel: String

    var body: some View {
        Form {
            Section {
                Picker("Default model", selection: $defaultModel) {
                    Text("Haiku (Faster)").tag("haiku")
                    Text("Sonnet (Smarter)").tag("sonnet")
                }
                .pickerStyle(.radioGroup)

                Text("Haiku is faster and cheaper. Sonnet produces higher quality summaries for complex articles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Claude Model")
            }
        }
        .formStyle(.grouped)
    }
}

/// About tab
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("DataPointsAI")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 2.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical)

            Text("An AI-powered RSS reader for macOS.")
                .multilineTextAlignment(.center)

            Text("Summaries powered by Claude")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
