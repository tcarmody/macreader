import SwiftUI
import UniformTypeIdentifiers

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
                            fetchGmailNow(fetchAll: false)
                        } label: {
                            if isFetchingGmail {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Fetch New", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isFetchingGmail)

                        Button {
                            fetchGmailNow(fetchAll: true)
                        } label: {
                            Label("Fetch All", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(isFetchingGmail)
                        .helpLabel("Re-import all newsletters from Gmail (ignores previously fetched)")

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

                    Text("Default: ~/Documents/Data Points AI Newsletters/")
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
           \(watchFolderPath.isEmpty ? "~/Documents/Data Points AI Newsletters/" : watchFolderPath)

        Sample AppleScript:
        ---
        on perform mail action with messages theMessages
            repeat with theMessage in theMessages
                set theSubject to subject of theMessage
                set thePath to "\(watchFolderPath.isEmpty ? "~/Documents/Data Points AI Newsletters/" : watchFolderPath)" & theSubject & ".eml"
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
                    set thePath to "\(watchFolderPath.isEmpty ? "~/Documents/Data Points AI Newsletters/" : watchFolderPath)" & cleanSubject & ".eml"
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

    private func fetchGmailNow(fetchAll: Bool = false) {
        isFetchingGmail = true
        gmailFetchResult = nil

        Task {
            do {
                let response = try await appState.apiClient.triggerGmailFetch(fetchAll: fetchAll)

                await MainActor.run {
                    isFetchingGmail = false
                    if response.imported > 0 {
                        gmailFetchResult = "Imported \(response.imported) newsletter(s)"
                        // Reload feeds to show new newsletter feeds
                        Task {
                            try? await appState.refreshFeeds()
                        }
                    } else if response.success {
                        gmailFetchResult = response.message ?? "No new newsletters"
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

