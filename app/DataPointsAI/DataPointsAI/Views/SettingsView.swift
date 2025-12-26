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

    // Reader mode settings
    @State private var readerModeFontSize: ArticleFontSize = .large
    @State private var readerModeLineSpacing: ArticleLineSpacing = .relaxed

    // Auto-archive settings
    @State private var autoArchiveEnabled: Bool = false
    @State private var autoArchiveDays: Int = 30
    @State private var archiveKeepBookmarked: Bool = true
    @State private var archiveKeepUnread: Bool = false

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
                archiveKeepUnread: $archiveKeepUnread
            )
            .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsView(
                articleFontSize: $articleFontSize,
                articleLineSpacing: $articleLineSpacing,
                listDensity: $listDensity,
                appTypeface: $appTypeface,
                contentTypeface: $contentTypeface,
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
        readerModeFontSize = appState.settings.readerModeFontSize
        readerModeLineSpacing = appState.settings.readerModeLineSpacing
        autoArchiveEnabled = appState.settings.autoArchiveEnabled
        autoArchiveDays = appState.settings.autoArchiveDays
        archiveKeepBookmarked = appState.settings.archiveKeepBookmarked
        archiveKeepUnread = appState.settings.archiveKeepUnread
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

    @StateObject private var notificationService = NotificationService.shared

    let refreshOptions = [15, 30, 60, 120, 240]
    let archiveDaysOptions = [7, 14, 30, 60, 90, 180, 365]

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
}

/// Appearance settings tab
struct AppearanceSettingsView: View {
    @Binding var articleFontSize: ArticleFontSize
    @Binding var articleLineSpacing: ArticleLineSpacing
    @Binding var listDensity: ListDensity
    @Binding var appTypeface: AppTypeface
    @Binding var contentTypeface: ContentTypeface
    @Binding var readerModeFontSize: ArticleFontSize
    @Binding var readerModeLineSpacing: ArticleLineSpacing

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
                        // Reload newsletters list
                        Task {
                            await appState.loadNewsletterItems()
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
