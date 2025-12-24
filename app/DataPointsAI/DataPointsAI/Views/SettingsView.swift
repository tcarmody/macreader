import SwiftUI

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
            .tabItem {
                Label("General", systemImage: "gear")
            }

            AppearanceSettingsView(
                articleFontSize: $articleFontSize,
                articleLineSpacing: $articleLineSpacing,
                listDensity: $listDensity,
                appTypeface: $appTypeface,
                contentTypeface: $contentTypeface,
                readerModeFontSize: $readerModeFontSize,
                readerModeLineSpacing: $readerModeLineSpacing
            )
            .tabItem {
                Label("Appearance", systemImage: "textformat.size")
            }

            AISettingsView(
                llmProvider: $llmProvider,
                defaultModel: $defaultModel
            )
            .tabItem {
                Label("AI", systemImage: "sparkles")
            }

            AboutView(llmProvider: llmProvider)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 480, height: 500)
        .onAppear {
            loadSettings()
        }
        .onChange(of: refreshInterval) { _, _ in saveSettings() }
        .onChange(of: autoSummarize) { _, _ in saveSettings() }
        .onChange(of: markReadOnOpen) { _, _ in saveSettings() }
        .onChange(of: hideDuplicates) { _, _ in saveSettings() }
        .onChange(of: defaultModel) { _, _ in saveSettings() }
        .onChange(of: llmProvider) { _, newProvider in
            // Reset model to first option when provider changes
            defaultModel = newProvider.modelOptions.first?.value ?? "haiku"
            saveSettings()
        }
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
