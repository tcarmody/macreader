import SwiftUI
import UniformTypeIdentifiers

/// Setup wizard for configuring Mail.app newsletter import integration
struct NewsletterSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: SetupStep = .welcome
    @State private var watchFolderPath: String = ""
    @State private var autoImportEnabled: Bool = true
    @State private var autoSummarize: Bool = false
    @State private var deleteAfterImport: Bool = true
    @State private var scriptInstalled: Bool = false
    @State private var ruleCreated: Bool = false
    @State private var isTestingImport: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false

    var onComplete: () -> Void

    enum SetupStep: CaseIterable {
        case welcome
        case watchFolder
        case importSettings
        case installScript
        case createRule
        case testSetup
        case complete

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .watchFolder: return "Watch Folder"
            case .importSettings: return "Settings"
            case .installScript: return "Install Script"
            case .createRule: return "Mail Rule"
            case .testSetup: return "Test"
            case .complete: return "Done"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 20)
                .padding(.bottom, 10)

            Divider()

            // Content area
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .watchFolder:
                    watchFolderStep
                case .importSettings:
                    importSettingsStep
                case .installScript:
                    installScriptStep
                case .createRule:
                    createRuleStep
                case .testSetup:
                    testSetupStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationButtons
                .padding(20)
        }
        .frame(width: 550, height: 500)
        .onAppear {
            // Set default watch folder
            let suggestedFolder = NewsletterWatcherService.suggestedWatchFolder()
            watchFolderPath = suggestedFolder.path
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.offset) { index, step in
                Circle()
                    .fill(stepIndex(step) <= stepIndex(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)

                if index < SetupStep.allCases.count - 1 {
                    Rectangle()
                        .fill(stepIndex(step) < stepIndex(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 24, height: 2)
                }
            }
        }
    }

    private func stepIndex(_ step: SetupStep) -> Int {
        SetupStep.allCases.firstIndex(of: step) ?? 0
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Newsletter Import Setup")
                .font(.title)
                .fontWeight(.bold)

            Text("This wizard will help you set up automatic newsletter import from Mail.app. Your newsletters will be exported to a watch folder and automatically imported into your library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("Configure a watch folder", systemImage: "folder")
                Label("Install the export script", systemImage: "applescript")
                Label("Create a Mail.app rule", systemImage: "envelope")
                Label("Test the integration", systemImage: "checkmark.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Watch Folder Step

    private var watchFolderStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Choose Watch Folder")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select a folder where newsletter emails will be exported. Data Points AI will monitor this folder and automatically import new .eml files.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Folder path", text: $watchFolderPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button("Choose...") {
                        selectWatchFolder()
                    }
                }
                .frame(width: 400)

                Text("Default: ~/Documents/Data Points AI Newsletters/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !watchFolderPath.isEmpty {
                Label("Folder will be created if it doesn't exist", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Import Settings Step

    private var importSettingsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gearshape.2")
                .font(.system(size: 50))
                .foregroundStyle(.purple)

            Text("Import Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Configure how newsletters should be processed when imported.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $autoImportEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-import new emails")
                            .fontWeight(.medium)
                        Text("Automatically import .eml files added to the watch folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $autoSummarize) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-summarize newsletters")
                            .fontWeight(.medium)
                        Text("Generate AI summaries for imported newsletters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $deleteAfterImport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete .eml files after import")
                            .fontWeight(.medium)
                        Text("Remove the exported file after successful import")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 400)
            .toggleStyle(.switch)

            Spacer()
        }
    }

    // MARK: - Install Script Step

    private var installScriptStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "applescript")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Install AppleScript")
                .font(.title2)
                .fontWeight(.semibold)

            Text("An AppleScript is needed to export emails from Mail.app to the watch folder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(spacing: 16) {
                // Step 1: Open in Script Editor
                instructionRow(
                    number: 1,
                    title: "Open Script Editor",
                    description: "Click the button below to open the script in Script Editor",
                    buttonTitle: "Open in Script Editor",
                    buttonAction: openScriptInEditor
                )

                // Step 2: Update the folder path
                instructionRow(
                    number: 2,
                    title: "Update Folder Path",
                    description: "Change destinationFolder to match your watch folder",
                    code: "property destinationFolder : \"\(watchFolderPath)/\""
                )

                // Step 3: Save the script
                instructionRow(
                    number: 3,
                    title: "Save to Mail Scripts Folder",
                    description: "File > Save, then save to:",
                    code: "~/Library/Application Scripts/com.apple.mail/"
                )

                Toggle(isOn: $scriptInstalled) {
                    Text("I have saved the script")
                        .fontWeight(.medium)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 8)
            }
            .frame(width: 450)

            Spacer()
        }
    }

    // MARK: - Create Rule Step

    private var createRuleStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Create Mail.app Rule")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a rule in Mail.app to run the script for matching emails.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(spacing: 16) {
                instructionRow(
                    number: 1,
                    title: "Open Mail Rules",
                    description: "Open Mail.app Settings and go to the Rules tab",
                    buttonTitle: "Open Mail Settings",
                    buttonAction: openMailSettings
                )

                instructionRow(
                    number: 2,
                    title: "Add New Rule",
                    description: "Click 'Add Rule' and configure conditions for your newsletters",
                    code: "From contains: substack.com, newsletter, etc."
                )

                instructionRow(
                    number: 3,
                    title: "Set Action",
                    description: "Set the action to 'Run AppleScript' and select your saved script",
                    code: "Run AppleScript: ExportNewsletterToDataPointsAI"
                )

                Toggle(isOn: $ruleCreated) {
                    Text("I have created the Mail rule")
                        .fontWeight(.medium)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 8)
            }
            .frame(width: 450)

            Spacer()
        }
    }

    // MARK: - Test Setup Step

    private var testSetupStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Test Your Setup")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Test the integration by exporting a newsletter from Mail.app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To test:")
                        .fontWeight(.medium)

                    Text("1. Open Mail.app and select a newsletter email")
                        .font(.callout)
                    Text("2. Open Script Editor and run the script manually")
                        .font(.callout)
                    Text("3. Check if the .eml file appears in the watch folder")
                        .font(.callout)
                    Text("4. Data Points AI should import it automatically")
                        .font(.callout)
                }

                Divider()

                HStack {
                    Button("Open Watch Folder") {
                        openWatchFolder()
                    }

                    Spacer()

                    if isTestingImport {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result = testResult {
                    HStack {
                        Image(systemName: testSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(testSuccess ? .green : .blue)
                        Text(result)
                            .font(.callout)
                    }
                }
            }
            .frame(width: 400)

            Text("You can skip this step and test later")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            startWatchingForTest()
        }
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Setup Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("Newsletter import is now configured. Emails matching your Mail.app rule will be automatically exported and imported into your library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Label("Watch folder: \(watchFolderPath)", systemImage: "folder")
                if autoImportEnabled {
                    Label("Auto-import enabled", systemImage: "checkmark.circle")
                }
                if autoSummarize {
                    Label("Auto-summarize enabled", systemImage: "sparkles")
                }
                if deleteAfterImport {
                    Label("Delete after import enabled", systemImage: "trash")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome && currentStep != .complete {
                Button("Back") {
                    withAnimation {
                        goBack()
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            if currentStep == .welcome {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()

            if currentStep == .complete {
                Button("Done") {
                    completeSetup()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .installScript {
                Button("Continue") {
                    withAnimation {
                        goNext()
                    }
                }
                .disabled(!scriptInstalled)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .createRule {
                Button("Continue") {
                    withAnimation {
                        goNext()
                    }
                }
                .disabled(!ruleCreated)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .testSetup {
                Button("Finish Setup") {
                    withAnimation {
                        goNext()
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") {
                    withAnimation {
                        goNext()
                    }
                }
                .disabled(currentStep == .watchFolder && watchFolderPath.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helper Views

    private func instructionRow(
        number: Int,
        title: String,
        description: String,
        code: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let code = code {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }

                if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                    Button(buttonTitle, action: buttonAction)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }

            Spacer()
        }
    }

    // MARK: - Navigation Logic

    private func goNext() {
        guard let currentIndex = SetupStep.allCases.firstIndex(of: currentStep),
              currentIndex < SetupStep.allCases.count - 1 else { return }
        currentStep = SetupStep.allCases[currentIndex + 1]
    }

    private func goBack() {
        guard let currentIndex = SetupStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0 else { return }
        currentStep = SetupStep.allCases[currentIndex - 1]
    }

    private func completeSetup() {
        // Save settings
        Task {
            let folderURL = URL(fileURLWithPath: watchFolderPath)

            // Ensure folder exists
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // Save settings to NewsletterWatcherService
            await NewsletterWatcherService.shared.setWatchFolder(folderURL)
            await NewsletterWatcherService.shared.setAutoImportEnabled(autoImportEnabled)
            await NewsletterWatcherService.shared.setAutoSummarizeEnabled(autoSummarize)
            await NewsletterWatcherService.shared.setDeleteAfterImportEnabled(deleteAfterImport)

            // Start watching if enabled
            if autoImportEnabled {
                await NewsletterWatcherService.shared.startWatching()
            }
        }

        onComplete()
        dismiss()
    }

    // MARK: - Actions

    private func selectWatchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Watch Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            watchFolderPath = url.path
        }
    }

    private func openScriptInEditor() {
        // First, copy the script to a temp location
        let scriptContent = generateAppleScript()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ExportNewsletterToDataPointsAI.applescript")

        do {
            try scriptContent.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
        } catch {
            // Fallback: open Script Editor
            if let scriptEditorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScriptEditor2") {
                NSWorkspace.shared.open(scriptEditorURL)
            }
        }
    }

    private func generateAppleScript() -> String {
        """
        (*
            Export Newsletter to Data Points AI

            This AppleScript exports newsletter emails to the Data Points AI watch folder.
            Save this script to: ~/Library/Application Scripts/com.apple.mail/
        *)

        -- Configuration: Set this to your Data Points AI newsletter folder
        property destinationFolder : "\(watchFolderPath)/"

        -- Main handler for Mail.app rules
        using terms from application "Mail"
            on perform mail action with messages theMessages for rule theRule
                -- Ensure destination folder exists
                set expandedPath to do shell script "echo " & quoted form of destinationFolder
                do shell script "mkdir -p " & quoted form of expandedPath

                repeat with theMessage in theMessages
                    try
                        set theSubject to subject of theMessage
                        set cleanSubject to my sanitizeFilename(theSubject)
                        set theTimestamp to do shell script "date +%Y%m%d%H%M%S"
                        set fileName to cleanSubject & "_" & theTimestamp & ".eml"
                        set fullPath to expandedPath & "/" & fileName

                        set theSource to source of theMessage
                        set encodedSource to do shell script "echo " & quoted form of theSource & " | base64"
                        do shell script "echo " & quoted form of encodedSource & " | base64 -d > " & quoted form of fullPath

                        log "Exported: " & fileName
                    on error errMsg
                        log "Error: " & errMsg
                    end try
                end repeat
            end perform mail action with messages
        end using terms from

        on sanitizeFilename(inputText)
            set invalidChars to {"/", ":", "*", "?", "\\"", "<", ">", "|", "\\\\"}
            set outputText to inputText
            repeat with invalidChar in invalidChars
                set AppleScript's text item delimiters to invalidChar
                set textItems to text items of outputText
                set AppleScript's text item delimiters to "-"
                set outputText to textItems as text
            end repeat
            set AppleScript's text item delimiters to ""
            if length of outputText > 100 then
                set outputText to text 1 thru 100 of outputText
            end if
            try
                set outputText to do shell script "echo " & quoted form of outputText & " | xargs"
            end try
            if outputText is "" then
                set outputText to "newsletter"
            end if
            return outputText
        end sanitizeFilename

        on run
            tell application "Mail"
                set selectedMessages to selection
                if (count of selectedMessages) > 0 then
                    set expandedPath to do shell script "echo " & quoted form of destinationFolder
                    do shell script "mkdir -p " & quoted form of expandedPath
                    set exportCount to 0
                    repeat with theMessage in selectedMessages
                        try
                            set theSubject to subject of theMessage
                            set cleanSubject to my sanitizeFilename(theSubject)
                            set theTimestamp to do shell script "date +%Y%m%d%H%M%S"
                            set fileName to cleanSubject & "_" & theTimestamp & ".eml"
                            set fullPath to expandedPath & "/" & fileName
                            set theSource to source of theMessage
                            set encodedSource to do shell script "echo " & quoted form of theSource & " | base64"
                            do shell script "echo " & quoted form of encodedSource & " | base64 -d > " & quoted form of fullPath
                            set exportCount to exportCount + 1
                        end try
                    end repeat
                    display dialog "Exported " & exportCount & " message(s) to " & destinationFolder buttons {"OK"} default button "OK"
                else
                    display dialog "No messages selected." buttons {"OK"} default button "OK"
                end if
            end tell
        end run
        """
    }

    private func openMailSettings() {
        // Open Mail.app and then open settings
        let script = """
        tell application "Mail"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Mail"
                keystroke "," using command down
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func openWatchFolder() {
        let url = URL(fileURLWithPath: watchFolderPath)
        // Create folder if it doesn't exist
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func startWatchingForTest() {
        // Start watching the folder to detect test imports
        Task {
            let folderURL = URL(fileURLWithPath: watchFolderPath)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // Check for existing .eml files
            if let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                let emlFiles = contents.filter { $0.pathExtension.lowercased() == "eml" }
                if !emlFiles.isEmpty {
                    testResult = "Found \(emlFiles.count) .eml file(s) in watch folder"
                    testSuccess = true
                }
            }
        }
    }
}

#Preview {
    NewsletterSetupWizardView {
        print("Setup complete!")
    }
}
