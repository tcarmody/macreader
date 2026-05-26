import SwiftUI
import UniformTypeIdentifiers

/// Preferences window
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshInterval: Int = 30
    @State private var autoSummarize: Bool = false
    @State private var markReadOnOpen: Bool = true
    @State private var hideDuplicates: Bool = false
    @State private var defaultModel: String = "haiku"
    @State private var llmProvider: LLMProvider = .anthropic
    @State private var notificationsEnabled: Bool = true

    // Appearance settings
    @State private var articleFontSize: ArticleFontSize = .medium
    @State private var articleLineSpacing: ArticleLineSpacing = .normal
    @State private var listDensity: ListDensity = .comfortable
    @State private var appTypeface: AppTypeface = .system
    @State private var contentTypeface: ContentTypeface = .system
    @State private var articleTheme: ArticleTheme = .auto

    // Reader mode settings
    @State private var readerModeFontSize: ArticleFontSize = .large
    @State private var readerModeLineSpacing: ArticleLineSpacing = .relaxed

    // Auto-archive settings
    @State private var autoArchiveEnabled: Bool = false
    @State private var autoArchiveDays: Int = 30
    @State private var archiveKeepBookmarked: Bool = true
    @State private var archiveKeepUnread: Bool = false

    // Background refresh
    @State private var backgroundRefreshInterval: RefreshInterval = .every30Minutes

    var body: some View {
        settingsTabView
            .padding(20)
            .frame(width: 540, height: 500)
            .onAppear { loadSettings() }
            .onChange(of: refreshInterval) { _, _ in saveSettings() }
            .onChange(of: autoSummarize) { _, _ in saveSettings() }
            .onChange(of: markReadOnOpen) { _, _ in saveSettings() }
            .onChange(of: hideDuplicates) { _, _ in saveSettings() }
            .onChange(of: defaultModel) { _, _ in saveSettings() }
            .onChange(of: llmProvider) { _, newProvider in
                defaultModel = newProvider.modelOptions.first?.value ?? "haiku"
                saveSettings()
            }
            .applySettingsChangeHandlers(
                notificationsEnabled: notificationsEnabled,
                articleFontSize: articleFontSize,
                articleLineSpacing: articleLineSpacing,
                listDensity: listDensity,
                appTypeface: appTypeface,
                contentTypeface: contentTypeface,
                articleTheme: articleTheme,
                readerModeFontSize: readerModeFontSize,
                readerModeLineSpacing: readerModeLineSpacing,
                autoArchiveEnabled: autoArchiveEnabled,
                autoArchiveDays: autoArchiveDays,
                archiveKeepBookmarked: archiveKeepBookmarked,
                archiveKeepUnread: archiveKeepUnread,
                saveSettings: saveSettings
            )
    }

    @ViewBuilder
    private var settingsTabView: some View {
        TabView {
            GeneralSettingsView(
                refreshInterval: $refreshInterval,
                autoSummarize: $autoSummarize,
                markReadOnOpen: $markReadOnOpen,
                hideDuplicates: $hideDuplicates,
                notificationsEnabled: $notificationsEnabled,
                autoArchiveEnabled: $autoArchiveEnabled,
                autoArchiveDays: $autoArchiveDays,
                archiveKeepBookmarked: $archiveKeepBookmarked,
                archiveKeepUnread: $archiveKeepUnread,
                backgroundRefreshInterval: $backgroundRefreshInterval
            )
            .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsView(
                articleFontSize: $articleFontSize,
                articleLineSpacing: $articleLineSpacing,
                listDensity: $listDensity,
                appTypeface: $appTypeface,
                contentTypeface: $contentTypeface,
                articleTheme: $articleTheme,
                readerModeFontSize: $readerModeFontSize,
                readerModeLineSpacing: $readerModeLineSpacing
            )
            .tabItem { Label("Appearance", systemImage: "textformat.size") }

            AISettingsView(
                llmProvider: $llmProvider,
                defaultModel: $defaultModel
            )
            .tabItem { Label("AI", systemImage: "sparkles") }

            NewsletterSettingsView()
                .tabItem { Label("Newsletters", systemImage: "envelope") }

            NotificationRulesSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }

            StatisticsSettingsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar") }

            AboutView(llmProvider: llmProvider)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }

    private func loadSettings() {
        refreshInterval = appState.settings.refreshIntervalMinutes
        autoSummarize = appState.settings.autoSummarize
        markReadOnOpen = appState.settings.markReadOnOpen
        hideDuplicates = appState.settings.hideDuplicates
        defaultModel = appState.settings.defaultModel
        llmProvider = appState.settings.llmProvider
        notificationsEnabled = appState.settings.notificationsEnabled
        articleFontSize = appState.settings.articleFontSize
        articleLineSpacing = appState.settings.articleLineSpacing
        listDensity = appState.settings.listDensity
        appTypeface = appState.settings.appTypeface
        contentTypeface = appState.settings.contentTypeface
        articleTheme = appState.settings.articleTheme
        readerModeFontSize = appState.settings.readerModeFontSize
        readerModeLineSpacing = appState.settings.readerModeLineSpacing
        autoArchiveEnabled = appState.settings.autoArchiveEnabled
        autoArchiveDays = appState.settings.autoArchiveDays
        archiveKeepBookmarked = appState.settings.archiveKeepBookmarked
        archiveKeepUnread = appState.settings.archiveKeepUnread
        backgroundRefreshInterval = BackgroundRefreshService.shared.getRefreshInterval()
    }

    private func saveSettings() {
        var newSettings = AppSettings(
            refreshIntervalMinutes: refreshInterval,
            autoSummarize: autoSummarize,
            markReadOnOpen: markReadOnOpen,
            defaultModel: defaultModel,
            llmProvider: llmProvider
        )
        newSettings.notificationsEnabled = notificationsEnabled
        newSettings.hideDuplicates = hideDuplicates
        newSettings.articleFontSize = articleFontSize
        newSettings.articleLineSpacing = articleLineSpacing
        newSettings.listDensity = listDensity
        newSettings.appTypeface = appTypeface
        newSettings.contentTypeface = contentTypeface
        newSettings.articleTheme = articleTheme
        newSettings.readerModeFontSize = readerModeFontSize
        newSettings.readerModeLineSpacing = readerModeLineSpacing
        newSettings.autoArchiveEnabled = autoArchiveEnabled
        newSettings.autoArchiveDays = autoArchiveDays
        newSettings.archiveKeepBookmarked = archiveKeepBookmarked
        newSettings.archiveKeepUnread = archiveKeepUnread

        Task {
            try? await appState.updateSettings(newSettings)
        }
    }
}

// MARK: - View Extension for Settings Change Handlers

extension View {
    /// Applies onChange handlers for settings that would otherwise cause compiler complexity issues
    func applySettingsChangeHandlers(
        notificationsEnabled: Bool,
        articleFontSize: ArticleFontSize,
        articleLineSpacing: ArticleLineSpacing,
        listDensity: ListDensity,
        appTypeface: AppTypeface,
        contentTypeface: ContentTypeface,
        articleTheme: ArticleTheme,
        readerModeFontSize: ArticleFontSize,
        readerModeLineSpacing: ArticleLineSpacing,
        autoArchiveEnabled: Bool,
        autoArchiveDays: Int,
        archiveKeepBookmarked: Bool,
        archiveKeepUnread: Bool,
        saveSettings: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: notificationsEnabled) { _, _ in saveSettings() }
            .onChange(of: articleFontSize) { _, _ in saveSettings() }
            .onChange(of: articleLineSpacing) { _, _ in saveSettings() }
            .onChange(of: listDensity) { _, _ in saveSettings() }
            .onChange(of: appTypeface) { _, _ in saveSettings() }
            .onChange(of: contentTypeface) { _, _ in saveSettings() }
            .onChange(of: articleTheme) { _, _ in saveSettings() }
            .onChange(of: readerModeFontSize) { _, _ in saveSettings() }
            .onChange(of: readerModeLineSpacing) { _, _ in saveSettings() }
            .onChange(of: autoArchiveEnabled) { _, _ in saveSettings() }
            .onChange(of: autoArchiveDays) { _, _ in saveSettings() }
            .onChange(of: archiveKeepBookmarked) { _, _ in saveSettings() }
            .onChange(of: archiveKeepUnread) { _, _ in saveSettings() }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
