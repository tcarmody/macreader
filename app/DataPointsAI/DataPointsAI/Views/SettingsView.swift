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
            .frame(width: 480, height: 500)
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

/// Appearance settings tab
struct AppearanceSettingsView: View {
    @Binding var articleFontSize: ArticleFontSize
    @Binding var articleLineSpacing: ArticleLineSpacing
    @Binding var listDensity: ListDensity
    @Binding var appTypeface: AppTypeface
    @Binding var contentTypeface: ContentTypeface
    @Binding var articleTheme: ArticleTheme
    @Binding var readerModeFontSize: ArticleFontSize
    @Binding var readerModeLineSpacing: ArticleLineSpacing

    var body: some View {
        Form {
            Section {
                // Theme picker with visual previews
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(ArticleTheme.allCases, id: \.self) { theme in
                            ThemePreviewButton(
                                theme: theme,
                                isSelected: articleTheme == theme,
                                action: { articleTheme = theme }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                Text(articleTheme.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Article Theme")
            }

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
                Picker("Font size", selection: $readerModeFontSize) {
                    ForEach(ArticleFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }

                Picker("Line spacing", selection: $readerModeLineSpacing) {
                    ForEach(ArticleLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.label).tag(spacing)
                    }
                }

                Text("Reader mode (f) hides the sidebar and article list for distraction-free reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reader Mode")
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
    @EnvironmentObject var appState: AppState
    @Binding var llmProvider: LLMProvider
    @Binding var defaultModel: String

    @State private var showAPIKeySheet = false
    @State private var showSetupWizard = false
    @State private var apiKeyInput = ""
    @State private var selectedKeyProvider: LLMProvider = .anthropic
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $llmProvider) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.label).tag(provider)
                    }
                }

                Text(llmProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Provider")
            }

            Section {
                Picker("Default model", selection: $defaultModel) {
                    ForEach(llmProvider.modelOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.radioGroup)

                if let selectedOption = llmProvider.modelOptions.first(where: { $0.value == defaultModel }) {
                    Text(selectedOption.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Model")
            }

            Section {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    HStack {
                        Text(provider.label)
                        Spacer()
                        if KeychainService.shared.hasKey(for: provider) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Remove") {
                                removeAPIKey(for: provider)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.red)
                        } else {
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                            Button("Add") {
                                selectedKeyProvider = provider
                                apiKeyInput = ""
                                saveError = nil
                                showAPIKeySheet = true
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                Text("API keys are stored securely in your macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Setup Wizard...") {
                    showSetupWizard = true
                }
                .buttonStyle(.link)
            } header: {
                Text("API Keys")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAPIKeySheet) {
            apiKeySheet
        }
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardView {
                showSetupWizard = false
            }
            .environmentObject(appState)
        }
    }

    private var apiKeySheet: some View {
        VStack(spacing: 20) {
            Text("Add \(selectedKeyProvider.label) API Key")
                .font(.headline)

            SecureField("API Key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            if let error = saveError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    showAPIKeySheet = false
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    saveAPIKey()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty || isSaving)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    private func saveAPIKey() {
        isSaving = true
        saveError = nil

        Task {
            do {
                try KeychainService.shared.save(key: apiKeyInput, for: selectedKeyProvider)
                // Restart the server to pick up the new key
                await appState.restartServer()

                await MainActor.run {
                    isSaving = false
                    showAPIKeySheet = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private func removeAPIKey(for provider: LLMProvider) {
        Task {
            do {
                try KeychainService.shared.delete(provider: provider)
            } catch {
                print("Failed to remove API key: \(error)")
            }
            // Restart the server to pick up the change
            await appState.restartServer()
        }
    }
}

/// Newsletter settings tab
struct NewsletterSettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var watchFolderPath: String = ""
    @State private var autoImportEnabled: Bool = false
    @State private var autoSummarizeNewsletter: Bool = false
    @State private var deleteAfterImport: Bool = false
    @State private var isSelectingFolder: Bool = false
    @State private var importResults: [NewsletterWatcherService.ImportResult] = []
    @State private var showSetupWizard: Bool = false

    // Gmail integration state
    @State private var showGmailSetupWizard: Bool = false
    @State private var gmailConnected: Bool = false
    @State private var gmailEmail: String = ""
    @State private var gmailLabel: String = "Newsletters"
    @State private var gmailPollInterval: Int = 30
    @State private var gmailEnabled: Bool = true
    @State private var isLoadingGmailStatus: Bool = false
    @State private var isFetchingGmail: Bool = false
    @State private var gmailFetchResult: String?

    var body: some View {
        Form {
            // Setup Wizard Section - shown prominently if not configured
            if watchFolderPath.isEmpty || !autoImportEnabled {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mail.app Integration")
                                .fontWeight(.semibold)
                            Text("Set up automatic newsletter import from Mail.app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Setup Wizard") {
                            showSetupWizard = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Quick Setup")
                }
            }

            // Gmail Integration Section
            Section {
                if isLoadingGmailStatus {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading Gmail status...")
                            .foregroundStyle(.secondary)
                    }
                } else if gmailConnected {
                    // Connected state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .fontWeight(.medium)
                            Text(gmailEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") {
                            disconnectGmail()
                        }
                        .foregroundStyle(.red)
                    }

                    HStack {
                        Text("Monitored label:")
                        Spacer()
                        Text(gmailLabel)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Check every", selection: $gmailPollInterval) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                    .onChange(of: gmailPollInterval) { _, newValue in
                        updateGmailConfig()
                    }

                    Toggle("Enable automatic fetching", isOn: $gmailEnabled)
                        .onChange(of: gmailEnabled) { _, _ in
                            updateGmailConfig()
                        }

                    HStack {
                        Button {
                            fetchGmailNow()
                        } label: {
                            if isFetchingGmail {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Fetch Now", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isFetchingGmail)

                        if let result = gmailFetchResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // Not connected state
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gmail IMAP")
                                .fontWeight(.semibold)
                            Text("Automatically fetch newsletters from Gmail")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Connect Gmail") {
                            showGmailSetupWizard = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Label("Gmail Integration", systemImage: "envelope.badge.fill")
            } footer: {
                if !gmailConnected {
                    Text("Connect your Gmail account to automatically import newsletters from a specific label.")
                }
            }

            Section {
                HStack {
                    TextField("Watch folder", text: $watchFolderPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button("Choose...") {
                        selectFolder()
                    }

                    if !watchFolderPath.isEmpty {
                        Button("Reveal") {
                            if let url = URL(string: "file://\(watchFolderPath)") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                            }
                        }
                    }
                }

                if watchFolderPath.isEmpty {
                    Button("Use Default Folder") {
                        let defaultFolder = NewsletterWatcherService.suggestedWatchFolder()
                        watchFolderPath = defaultFolder.path
                        Task {
                            await NewsletterWatcherService.shared.setWatchFolder(defaultFolder)
                        }
                    }

                    Text("Default: ~/Documents/DataPointsAI Newsletters/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Watch Folder")
            } footer: {
                Text("Place .eml files in this folder to import them. You can set up a Mail.app rule to automatically export emails here.")
            }

            Section {
                Toggle("Auto-import new .eml files", isOn: $autoImportEnabled)
                    .disabled(watchFolderPath.isEmpty)
                    .onChange(of: autoImportEnabled) { _, newValue in
                        Task {
                            await NewsletterWatcherService.shared.setAutoImportEnabled(newValue)
                        }
                    }

                if autoImportEnabled {
                    Toggle("Auto-summarize imported newsletters", isOn: $autoSummarizeNewsletter)
                        .onChange(of: autoSummarizeNewsletter) { _, newValue in
                            Task {
                                await NewsletterWatcherService.shared.setAutoSummarizeEnabled(newValue)
                            }
                        }

                    Toggle("Delete .eml files after import", isOn: $deleteAfterImport)
                        .onChange(of: deleteAfterImport) { _, newValue in
                            Task {
                                await NewsletterWatcherService.shared.setDeleteAfterImportEnabled(newValue)
                            }
                        }
                }
            } header: {
                Text("Auto Import")
            }

            Section {
                Button("Import .eml Files...") {
                    importEmlFiles()
                }

                if !importResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(importResults.prefix(5), id: \.filename) { result in
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                Text(result.title ?? result.filename)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                        if importResults.count > 5 {
                            Text("...and \(importResults.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Manual Import")
            }

            Section {
                Button("Run Setup Wizard...") {
                    showSetupWizard = true
                }

                Button("Show Setup Instructions") {
                    showMailAppInstructions()
                }
            } header: {
                Text("Mail.app Integration")
            } footer: {
                Text("Set up a Mail.app rule to automatically export newsletter emails to your watch folder.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
            loadGmailStatus()
        }
        .sheet(isPresented: $showSetupWizard) {
            NewsletterSetupWizardView {
                // Reload settings after wizard completes
                loadSettings()
            }
        }
        .sheet(isPresented: $showGmailSetupWizard) {
            GmailSetupWizardView {
                // Reload Gmail status after wizard completes
                loadGmailStatus()
            }
            .environmentObject(appState)
        }
    }

    private func loadSettings() {
        Task {
            if let folder = await NewsletterWatcherService.shared.watchFolder {
                await MainActor.run {
                    watchFolderPath = folder.path
                }
            }
            let autoImport = await NewsletterWatcherService.shared.isAutoImportEnabled
            let autoSum = await NewsletterWatcherService.shared.isAutoSummarizeEnabled
            let deleteAfter = await NewsletterWatcherService.shared.isDeleteAfterImportEnabled

            await MainActor.run {
                autoImportEnabled = autoImport
                autoSummarizeNewsletter = autoSum
                deleteAfterImport = deleteAfter
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        panel.message = "Select a folder to watch for newsletter .eml files"

        if panel.runModal() == .OK, let url = panel.url {
            watchFolderPath = url.path
            Task {
                await NewsletterWatcherService.shared.setWatchFolder(url)
            }
        }
    }

    private func importEmlFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "eml")!]
        panel.prompt = "Import"
        panel.message = "Select .eml files to import as newsletters"

        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                do {
                    let results = try await NewsletterWatcherService.shared.importFiles(
                        urls: urls,
                        autoSummarize: autoSummarizeNewsletter
                    )
                    await MainActor.run {
                        importResults = results.map {
                            NewsletterWatcherService.ImportResult(
                                filename: $0.filename,
                                success: $0.success,
                                title: $0.title,
                                error: $0.error
                            )
                        }
                    }
                } catch {
                    print("Import failed: \(error)")
                }
            }
        }
    }

    private func showMailAppInstructions() {
        let alert = NSAlert()
        alert.messageText = "Mail.app Newsletter Import Setup"
        alert.informativeText = """
        To automatically import newsletters from Mail.app:

        1. Open Mail.app → Preferences → Rules
        2. Create a new rule with conditions to match your newsletters
           (e.g., "From contains newsletter" or specific sender addresses)
        3. Set the action to "Run AppleScript"
        4. Create an AppleScript that exports the email to:
           \(watchFolderPath.isEmpty ? "~/Documents/DataPointsAI Newsletters/" : watchFolderPath)

        Sample AppleScript:
        ---
        on perform mail action with messages theMessages
            repeat with theMessage in theMessages
                set theSubject to subject of theMessage
                set thePath to "\(watchFolderPath.isEmpty ? "~/Documents/DataPointsAI Newsletters/" : watchFolderPath)" & theSubject & ".eml"
                set theSource to source of theMessage
                do shell script "echo " & quoted form of theSource & " > " & quoted form of thePath
            end repeat
        end perform mail action with messages
        ---

        Would you like to copy the AppleScript to clipboard?
        """
        alert.addButton(withTitle: "Copy AppleScript")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            let script = """
            on perform mail action with messages theMessages
                repeat with theMessage in theMessages
                    set theSubject to subject of theMessage
                    -- Sanitize filename
                    set cleanSubject to do shell script "echo " & quoted form of theSubject & " | tr -d '/:*?\"<>|' | head -c 100"
                    set thePath to "\(watchFolderPath.isEmpty ? "~/Documents/DataPointsAI Newsletters/" : watchFolderPath)" & cleanSubject & ".eml"
                    set theSource to source of theMessage
                    do shell script "echo " & quoted form of theSource & " > " & quoted form of thePath
                end repeat
            end perform mail action with messages
            """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(script, forType: .string)
        }
    }

    // MARK: - Gmail Functions

    private func loadGmailStatus() {
        isLoadingGmailStatus = true

        Task {
            do {
                let status = try await appState.apiClient.getGmailStatus()

                await MainActor.run {
                    gmailConnected = status.connected
                    gmailEmail = status.email ?? ""
                    gmailLabel = status.monitoredLabel ?? "Newsletters"
                    gmailPollInterval = status.pollIntervalMinutes
                    gmailEnabled = status.isPollingEnabled
                    isLoadingGmailStatus = false
                }
            } catch {
                await MainActor.run {
                    gmailConnected = false
                    isLoadingGmailStatus = false
                }
            }
        }
    }

    private func updateGmailConfig() {
        Task {
            do {
                _ = try await appState.apiClient.updateGmailConfig(
                    label: nil,
                    interval: gmailPollInterval,
                    enabled: gmailEnabled
                )
            } catch {
                print("Failed to update Gmail config: \(error)")
            }
        }
    }

    private func fetchGmailNow() {
        isFetchingGmail = true
        gmailFetchResult = nil

        Task {
            do {
                let response = try await appState.apiClient.triggerGmailFetch()

                await MainActor.run {
                    isFetchingGmail = false
                    if response.imported > 0 {
                        gmailFetchResult = "Imported \(response.imported) newsletter(s)"
                        // Reload feeds to show new newsletter feeds
                        Task {
                            try? await appState.refreshFeeds()
                        }
                    } else if response.success {
                        gmailFetchResult = "No new newsletters"
                    } else {
                        gmailFetchResult = response.message ?? "Fetch failed"
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingGmail = false
                    gmailFetchResult = error.localizedDescription
                }
            }
        }
    }

    private func disconnectGmail() {
        Task {
            do {
                try await appState.apiClient.disconnectGmail()

                await MainActor.run {
                    gmailConnected = false
                    gmailEmail = ""
                    gmailLabel = "Newsletters"
                    gmailPollInterval = 30
                    gmailEnabled = true
                }
            } catch {
                print("Failed to disconnect Gmail: \(error)")
            }
        }
    }
}

/// Notification Rules settings tab
struct NotificationRulesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var notificationService = NotificationService.shared

    @State private var rules: [APIClient.NotificationRule] = []
    @State private var history: [APIClient.NotificationHistoryEntry] = []
    @State private var isLoading = true
    @State private var isLoadingHistory = false
    @State private var showAddRuleSheet = false
    @State private var editingRule: APIClient.NotificationRule?
    @State private var showHistory = false

    // New rule form state
    @State private var newRuleName = ""
    @State private var newRuleKeyword = ""
    @State private var newRuleAuthor = ""
    @State private var newRuleFeedId: Int?
    @State private var newRulePriority = "normal"

    var body: some View {
        Form {
            Section {
                if !notificationService.isAuthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Notifications are disabled")
                                .fontWeight(.medium)
                            Text("Enable notifications in System Settings to use smart notification rules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading rules...")
                            .foregroundStyle(.secondary)
                    }
                } else if rules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No notification rules yet")
                            .foregroundStyle(.secondary)
                        Text("Create rules to get notified about specific keywords, authors, or feeds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(rules) { rule in
                        NotificationRuleRow(
                            rule: rule,
                            onToggle: { toggleRule(rule) },
                            onEdit: { editingRule = rule },
                            onDelete: { deleteRule(rule) }
                        )
                    }
                }

                Button {
                    resetNewRuleForm()
                    showAddRuleSheet = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Notification Rules")
            } footer: {
                Text("Rules are evaluated when new articles arrive. Matching articles trigger notifications based on priority.")
            }

            Section {
                DisclosureGroup("Recent Notifications", isExpanded: $showHistory) {
                    if isLoadingHistory {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    } else if history.isEmpty {
                        Text("No recent notifications")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history.prefix(10)) { entry in
                            NotificationHistoryRow(entry: entry, onOpen: {
                                openArticle(entry.articleId)
                            })
                        }

                        if !history.isEmpty {
                            Button("Dismiss All") {
                                dismissAllNotifications()
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: showHistory) { _, isExpanded in
                    if isExpanded {
                        Task {
                            await loadHistory()
                        }
                    }
                }
            } header: {
                Text("History")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("High Priority", systemImage: "bell.badge.fill")
                        .foregroundStyle(.red)
                    Text("Urgent notifications that break through Focus modes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Normal Priority", systemImage: "bell.fill")
                        .foregroundStyle(.blue)
                    Text("Standard notifications grouped by app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Low Priority", systemImage: "bell")
                        .foregroundStyle(.gray)
                    Text("Silent notifications in Notification Center only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Priority Levels")
            }
        }
        .formStyle(.grouped)
        .task {
            await loadRules()
            await notificationService.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showAddRuleSheet) {
            addRuleSheet
        }
        .sheet(item: $editingRule) { rule in
            editRuleSheet(rule: rule)
        }
    }

    private var addRuleSheet: some View {
        VStack(spacing: 20) {
            Text("New Notification Rule")
                .font(.headline)

            Form {
                TextField("Rule name", text: $newRuleName)

                Section {
                    TextField("Keyword (optional)", text: $newRuleKeyword)
                    TextField("Author (optional)", text: $newRuleAuthor)

                    Picker("Feed (optional)", selection: $newRuleFeedId) {
                        Text("All feeds").tag(nil as Int?)
                        ForEach(appState.feeds, id: \.id) { feed in
                            Text(feed.name).tag(feed.id as Int?)
                        }
                    }
                } header: {
                    Text("Filters (at least one required)")
                }

                Picker("Priority", selection: $newRulePriority) {
                    Text("High").tag("high")
                    Text("Normal").tag("normal")
                    Text("Low").tag("low")
                }
            }
            .frame(height: 250)

            HStack {
                Button("Cancel") {
                    showAddRuleSheet = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    createRule()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(newRuleName.isEmpty || (newRuleKeyword.isEmpty && newRuleAuthor.isEmpty && newRuleFeedId == nil))
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    @ViewBuilder
    private func editRuleSheet(rule: APIClient.NotificationRule) -> some View {
        EditNotificationRuleSheet(
            rule: rule,
            feeds: appState.feeds,
            onSave: { updatedRule in
                Task {
                    await updateRule(updatedRule)
                }
            },
            onCancel: { editingRule = nil }
        )
    }

    private func loadRules() async {
        do {
            let fetchedRules = try await appState.apiClient.getNotificationRules()
            await MainActor.run {
                rules = fetchedRules
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("Failed to load notification rules: \(error)")
        }
    }

    private func resetNewRuleForm() {
        newRuleName = ""
        newRuleKeyword = ""
        newRuleAuthor = ""
        newRuleFeedId = nil
        newRulePriority = "normal"
    }

    private func createRule() {
        Task {
            do {
                let rule = try await appState.apiClient.createNotificationRule(
                    name: newRuleName,
                    feedId: newRuleFeedId,
                    keyword: newRuleKeyword.isEmpty ? nil : newRuleKeyword,
                    author: newRuleAuthor.isEmpty ? nil : newRuleAuthor,
                    priority: newRulePriority
                )
                await MainActor.run {
                    rules.insert(rule, at: 0)
                    showAddRuleSheet = false
                }
            } catch {
                print("Failed to create rule: \(error)")
            }
        }
    }

    private func toggleRule(_ rule: APIClient.NotificationRule) {
        Task {
            do {
                let updated = try await appState.apiClient.updateNotificationRule(
                    id: rule.id,
                    enabled: !rule.enabled
                )
                await MainActor.run {
                    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                        rules[index] = updated
                    }
                }
            } catch {
                print("Failed to toggle rule: \(error)")
            }
        }
    }

    private func updateRule(_ update: (id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) async {
        do {
            let updated = try await appState.apiClient.updateNotificationRule(
                id: update.id,
                name: update.name,
                feedId: update.feedId,
                clearFeed: update.clearFeed,
                keyword: update.keyword,
                clearKeyword: update.keyword == nil,
                author: update.author,
                clearAuthor: update.author == nil,
                priority: update.priority
            )
            await MainActor.run {
                if let index = rules.firstIndex(where: { $0.id == update.id }) {
                    rules[index] = updated
                }
                editingRule = nil
            }
        } catch {
            print("Failed to update rule: \(error)")
        }
    }

    private func deleteRule(_ rule: APIClient.NotificationRule) {
        Task {
            do {
                try await appState.apiClient.deleteNotificationRule(id: rule.id)
                await MainActor.run {
                    rules.removeAll { $0.id == rule.id }
                }
            } catch {
                print("Failed to delete rule: \(error)")
            }
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        do {
            let fetchedHistory = try await appState.apiClient.getNotificationHistory()
            await MainActor.run {
                history = fetchedHistory
                isLoadingHistory = false
            }
        } catch {
            await MainActor.run {
                isLoadingHistory = false
            }
            print("Failed to load notification history: \(error)")
        }
    }

    private func dismissAllNotifications() {
        Task {
            do {
                try await appState.apiClient.dismissAllNotifications()
                await MainActor.run {
                    history.removeAll()
                }
            } catch {
                print("Failed to dismiss notifications: \(error)")
            }
        }
    }

    private func openArticle(_ articleId: Int) {
        // Select the article to navigate to it
        appState.selectedArticleIds = [articleId]
    }
}

/// Row for notification history entry
struct NotificationHistoryRow: View {
    let entry: APIClient.NotificationHistoryEntry
    let onOpen: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.articleTitle ?? "Unknown Article")
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let ruleName = entry.ruleName {
                        Label(ruleName, systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(formatDate(entry.notifiedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onOpen) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Row for a notification rule
struct NotificationRuleRow: View {
    let rule: APIClient.NotificationRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .fontWeight(.medium)
                    priorityBadge
                }

                HStack(spacing: 8) {
                    if let keyword = rule.keyword {
                        Label(keyword, systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let author = rule.author {
                        Label(author, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let feedName = rule.feedName {
                        Label(feedName, systemImage: "newspaper")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: .init(
                get: { rule.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        switch rule.priority {
        case "high":
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case "low":
            Image(systemName: "bell")
                .foregroundStyle(.gray)
                .font(.caption)
        default:
            Image(systemName: "bell.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        }
    }
}

/// Sheet for editing a notification rule
struct EditNotificationRuleSheet: View {
    let rule: APIClient.NotificationRule
    let feeds: [Feed]
    let onSave: ((id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var keyword: String
    @State private var author: String
    @State private var feedId: Int?
    @State private var priority: String

    init(rule: APIClient.NotificationRule, feeds: [Feed], onSave: @escaping ((id: Int, name: String?, keyword: String?, author: String?, feedId: Int?, clearFeed: Bool, priority: String?)) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.feeds = feeds
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: rule.name)
        _keyword = State(initialValue: rule.keyword ?? "")
        _author = State(initialValue: rule.author ?? "")
        _feedId = State(initialValue: rule.feedId)
        _priority = State(initialValue: rule.priority)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Notification Rule")
                .font(.headline)

            Form {
                TextField("Rule name", text: $name)

                Section {
                    TextField("Keyword", text: $keyword)
                    TextField("Author", text: $author)

                    Picker("Feed", selection: $feedId) {
                        Text("All feeds").tag(nil as Int?)
                        ForEach(feeds, id: \.id) { feed in
                            Text(feed.name).tag(feed.id as Int?)
                        }
                    }
                } header: {
                    Text("Filters")
                }

                Picker("Priority", selection: $priority) {
                    Text("High").tag("high")
                    Text("Normal").tag("normal")
                    Text("Low").tag("low")
                }
            }
            .frame(height: 250)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    onSave((
                        id: rule.id,
                        name: name != rule.name ? name : nil,
                        keyword: keyword.isEmpty ? nil : keyword,
                        author: author.isEmpty ? nil : author,
                        feedId: feedId,
                        clearFeed: feedId == nil && rule.feedId != nil,
                        priority: priority != rule.priority ? priority : nil
                    ))
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}

/// Statistics settings tab
struct StatisticsSettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var stats: APIClient.ReadingStatsResponse?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedPeriodType: PeriodType = .rolling
    @State private var selectedPeriodValue: String = "30d"
    @State private var isClusteringTopics = false
    @State private var clusteringError: String?
    @State private var clusteringSuccess: String?

    enum PeriodType: String, CaseIterable {
        case rolling = "rolling"
        case calendar = "calendar"

        var label: String {
            switch self {
            case .rolling: return "Rolling Window"
            case .calendar: return "Calendar Period"
            }
        }
    }

    var periodOptions: [String] {
        switch selectedPeriodType {
        case .rolling:
            return ["7d", "30d", "90d"]
        case .calendar:
            return ["week", "month", "year"]
        }
    }

    var body: some View {
        Form {
            // Period Selector
            Section {
                Picker("Period Type", selection: $selectedPeriodType) {
                    ForEach(PeriodType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .onChange(of: selectedPeriodType) { _, _ in
                    selectedPeriodValue = periodOptions.first ?? "30d"
                    Task { await loadStats() }
                }

                Picker("Time Period", selection: $selectedPeriodValue) {
                    ForEach(periodOptions, id: \.self) { option in
                        Text(formatPeriodLabel(option)).tag(option)
                    }
                }
                .onChange(of: selectedPeriodValue) { _, _ in
                    Task { await loadStats() }
                }
            } header: {
                Text("Time Period")
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading statistics...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = loadError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let stats = stats {
                // Summarization Stats
                summarizationSection(stats.summarization)

                // Reading Stats
                readingSection(stats.reading)

                // Topic Stats
                topicSection(stats.topics)
            }

            // Topic Clustering Action
            Section {
                Button {
                    Task { await clusterTopics() }
                } label: {
                    if isClusteringTopics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing topics...")
                        }
                    } else {
                        Label("Analyze Current Topics", systemImage: "sparkles")
                    }
                }
                .disabled(isClusteringTopics)

                if let error = clusteringError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let success = clusteringSuccess {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Topic Analysis")
            } footer: {
                Text("Uses AI to group articles by topic and saves results for trend analysis.")
            }
        }
        .formStyle(.grouped)
        .task {
            await loadStats()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func summarizationSection(_ stats: APIClient.SummarizationStats) -> some View {
        Section {
            StatRow(
                label: "Articles Summarized",
                value: "\(stats.summarizedArticles) of \(stats.totalArticles)",
                detail: String(format: "%.1f%%", stats.summarizationRate * 100)
            )

            StatRow(
                label: "Average per Day",
                value: String(format: "%.1f", stats.avgPerDay)
            )

            StatRow(
                label: "Average per Week",
                value: String(format: "%.1f", stats.avgPerWeek)
            )

            // Model breakdown
            if !stats.modelBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(stats.modelBreakdown.keys.sorted()), id: \.self) { model in
                        HStack {
                            Text(formatModelName(model))
                            Spacer()
                            Text("\(stats.modelBreakdown[model] ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Label("Summarization", systemImage: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private func readingSection(_ stats: APIClient.ReadingActivityStats) -> some View {
        Section {
            StatRow(
                label: "Articles Read",
                value: "\(stats.articlesRead)"
            )

            StatRow(
                label: "Total Reading Time",
                value: formatReadingTime(stats.totalReadingTimeMinutes)
            )

            StatRow(
                label: "Avg. per Article",
                value: String(format: "%.1f min", stats.avgReadingTimeMinutes)
            )

            StatRow(
                label: "Bookmarks Added",
                value: "\(stats.bookmarksAdded)"
            )

            // Top feeds by reading
            if !stats.readByFeed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most Read Feeds")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(stats.readByFeed.sorted { $0.value > $1.value }.prefix(5)), id: \.key) { feed, count in
                        HStack {
                            Text(feed)
                                .lineLimit(1)
                            Spacer()
                            Text("\(count) articles")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Label("Reading", systemImage: "book")
        }
    }

    @ViewBuilder
    private func topicSection(_ stats: APIClient.TopicStats) -> some View {
        Section {
            if stats.currentTopics.isEmpty && stats.mostCommon.isEmpty {
                Text("No topic data available. Run topic analysis to see trends.")
                    .foregroundStyle(.secondary)
            } else {
                // Current topics
                if !stats.currentTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Topics")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(stats.currentTopics.prefix(5), id: \.label) { topic in
                            HStack {
                                Text(topic.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(topic.count) articles")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                // Most common topics (historical)
                if !stats.mostCommon.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most Common Topics")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(stats.mostCommon.prefix(5), id: \.label) { topic in
                            HStack {
                                Text(topic.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(topic.count) total")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        } header: {
            Label("Topics", systemImage: "tag")
        }
    }

    // MARK: - Helper Functions

    private func loadStats() async {
        isLoading = true
        loadError = nil

        do {
            let fetchedStats = try await appState.apiClient.getReadingStats(
                periodType: selectedPeriodType.rawValue,
                periodValue: selectedPeriodValue
            )
            await MainActor.run {
                stats = fetchedStats
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func clusterTopics() async {
        isClusteringTopics = true
        clusteringError = nil
        clusteringSuccess = nil

        do {
            let result = try await appState.apiClient.triggerTopicClustering()
            await MainActor.run {
                clusteringSuccess = "Found \(result.topics.count) topics across \(result.totalArticles) articles"
                isClusteringTopics = false
            }
            // Refresh stats to show new topics
            await loadStats()
        } catch {
            await MainActor.run {
                clusteringError = error.localizedDescription
                isClusteringTopics = false
            }
        }
    }

    private func formatPeriodLabel(_ value: String) -> String {
        switch value {
        case "7d": return "Last 7 days"
        case "30d": return "Last 30 days"
        case "90d": return "Last 90 days"
        case "week": return "This week"
        case "month": return "This month"
        case "year": return "This year"
        default: return value
        }
    }

    private func formatModelName(_ model: String) -> String {
        // Clean up model names for display
        model.replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gpt-", with: "GPT-")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func formatReadingTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}

/// Row displaying a statistic
struct StatRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let detail = detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Text(value)
                .fontWeight(.medium)
        }
    }
}

/// About tab
struct AboutView: View {
    var llmProvider: LLMProvider

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Data Points AI")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 2.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical)

            Text("An AI-powered RSS reader for macOS.")
                .multilineTextAlignment(.center)

            Text("Summaries powered by \(llmProvider.label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Theme Preview Button

/// Visual button for selecting an article theme
struct ThemePreviewButton: View {
    let theme: ArticleTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Theme preview swatch
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.backgroundColor)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    // Sample text lines
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.textColor)
                            .frame(width: 40, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.secondaryTextColor)
                            .frame(width: 30, height: 3)
                    }
                }

                // Theme label
                Text(theme.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
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
