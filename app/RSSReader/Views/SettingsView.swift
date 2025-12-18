import SwiftUI

/// Preferences window
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshInterval: Int = 30
    @State private var autoSummarize: Bool = true
    @State private var markReadOnOpen: Bool = true
    @State private var defaultModel: String = "haiku"

    var body: some View {
        TabView {
            GeneralSettingsView(
                refreshInterval: $refreshInterval,
                autoSummarize: $autoSummarize,
                markReadOnOpen: $markReadOnOpen
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
    }

    private func loadSettings() {
        refreshInterval = appState.settings.refreshIntervalMinutes
        autoSummarize = appState.settings.autoSummarize
        markReadOnOpen = appState.settings.markReadOnOpen
        defaultModel = appState.settings.defaultModel
    }

    private func saveSettings() {
        let newSettings = Settings(
            refreshIntervalMinutes: refreshInterval,
            autoSummarize: autoSummarize,
            markReadOnOpen: markReadOnOpen,
            defaultModel: defaultModel
        )

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
            } header: {
                Text("Summarization")
            }
        }
        .formStyle(.grouped)
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

            Text("RSS Reader")
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
