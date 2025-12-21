import SwiftUI

/// Preferences window
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshInterval: Int = 30
    @State private var autoSummarize: Bool = false
    @State private var markReadOnOpen: Bool = true
    @State private var defaultModel: String = "haiku"
    @State private var notificationsEnabled: Bool = true

    // Appearance settings
    @State private var articleFontSize: ArticleFontSize = .medium
    @State private var articleLineSpacing: ArticleLineSpacing = .normal
    @State private var listDensity: ListDensity = .comfortable
    @State private var appTypeface: AppTypeface = .system
    @State private var contentTypeface: ContentTypeface = .system

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

            AppearanceSettingsView(
                articleFontSize: $articleFontSize,
                articleLineSpacing: $articleLineSpacing,
                listDensity: $listDensity,
                appTypeface: $appTypeface,
                contentTypeface: $contentTypeface
            )
            .tabItem {
                Label("Appearance", systemImage: "textformat.size")
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
        .frame(width: 480, height: 420)
        .onAppear {
            loadSettings()
        }
        .onChange(of: refreshInterval) { _, _ in saveSettings() }
        .onChange(of: autoSummarize) { _, _ in saveSettings() }
        .onChange(of: markReadOnOpen) { _, _ in saveSettings() }
        .onChange(of: defaultModel) { _, _ in saveSettings() }
        .onChange(of: notificationsEnabled) { _, _ in saveSettings() }
        .onChange(of: articleFontSize) { _, _ in saveSettings() }
        .onChange(of: articleLineSpacing) { _, _ in saveSettings() }
        .onChange(of: listDensity) { _, _ in saveSettings() }
        .onChange(of: appTypeface) { _, _ in saveSettings() }
        .onChange(of: contentTypeface) { _, _ in saveSettings() }
    }

    private func loadSettings() {
        refreshInterval = appState.settings.refreshIntervalMinutes
        autoSummarize = appState.settings.autoSummarize
        markReadOnOpen = appState.settings.markReadOnOpen
        defaultModel = appState.settings.defaultModel
        notificationsEnabled = appState.settings.notificationsEnabled
        articleFontSize = appState.settings.articleFontSize
        articleLineSpacing = appState.settings.articleLineSpacing
        listDensity = appState.settings.listDensity
        appTypeface = appState.settings.appTypeface
        contentTypeface = appState.settings.contentTypeface
    }

    private func saveSettings() {
        var newSettings = AppSettings(
            refreshIntervalMinutes: refreshInterval,
            autoSummarize: autoSummarize,
            markReadOnOpen: markReadOnOpen,
            defaultModel: defaultModel
        )
        newSettings.notificationsEnabled = notificationsEnabled
        newSettings.articleFontSize = articleFontSize
        newSettings.articleLineSpacing = articleLineSpacing
        newSettings.listDensity = listDensity
        newSettings.appTypeface = appTypeface
        newSettings.contentTypeface = contentTypeface

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

/// Appearance settings tab
struct AppearanceSettingsView: View {
    @Binding var articleFontSize: ArticleFontSize
    @Binding var articleLineSpacing: ArticleLineSpacing
    @Binding var listDensity: ListDensity
    @Binding var appTypeface: AppTypeface
    @Binding var contentTypeface: ContentTypeface

    var body: some View {
        Form {
            Section {
                Picker("App typeface", selection: $appTypeface) {
                    ForEach(AppTypeface.allCases, id: \.self) { typeface in
                        Text(typeface.label)
                            .font(typeface.font(size: 13))
                            .tag(typeface)
                    }
                }

                Picker("Content typeface", selection: $contentTypeface) {
                    ForEach(ContentTypeface.allCases, id: \.self) { typeface in
                        Text(typeface.label).tag(typeface)
                    }
                }

                Text("App typeface is used for titles, summaries, and key points. Content typeface is used for the original HTML article content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Typeface")
            }

            Section {
                Picker("Font size", selection: $articleFontSize) {
                    ForEach(ArticleFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }

                Picker("Line spacing", selection: $articleLineSpacing) {
                    ForEach(ArticleLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.label).tag(spacing)
                    }
                }
            } header: {
                Text("Size & Spacing")
            }

            Section {
                Picker("List density", selection: $listDensity) {
                    ForEach(ListDensity.allCases, id: \.self) { density in
                        Text(density.label).tag(density)
                    }
                }

                Text(listDensityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Article List")
            }

            Section {
                // Preview of current settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Article Title")
                        .font(appTypeface.font(size: articleFontSize.titleFontSize, weight: .bold))

                    Text("This is a preview of how article content will appear with your current font and spacing settings.")
                        .font(appTypeface.font(size: articleFontSize.bodyFontSize))
                        .lineSpacing(articleFontSize.bodyFontSize * (articleLineSpacing.multiplier - 1))
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
    }

    private var listDensityDescription: String {
        switch listDensity {
        case .compact:
            return "More articles visible, no preview text"
        case .comfortable:
            return "Balanced view with summary previews"
        case .spacious:
            return "Easy reading with extra spacing"
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
