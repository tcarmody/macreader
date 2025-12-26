import SwiftUI

/// Setup wizard for Gmail IMAP newsletter integration
struct GmailSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var currentStep: SetupStep = .welcome
    @State private var isAuthenticating: Bool = false
    @State private var authError: String?
    @State private var gmailConnected: Bool = false
    @State private var gmailEmail: String = ""
    @State private var availableLabels: [String] = []
    @State private var selectedLabel: String = "Newsletters"
    @State private var pollInterval: Int = 30
    @State private var isLoadingLabels: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    @State private var pollingTimer: Timer?

    var onComplete: () -> Void

    enum SetupStep: CaseIterable {
        case welcome
        case authenticate
        case selectLabel
        case configure
        case test
        case complete

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .authenticate: return "Connect"
            case .selectLabel: return "Label"
            case .configure: return "Settings"
            case .test: return "Test"
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
                case .authenticate:
                    authenticateStep
                case .selectLabel:
                    selectLabelStep
                case .configure:
                    configureStep
                case .test:
                    testStep
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
        .frame(width: 550, height: 480)
        .onDisappear {
            pollingTimer?.invalidate()
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
                .foregroundStyle(.red)

            Text("Gmail Integration")
                .font(.title)
                .fontWeight(.bold)

            Text("Connect your Gmail account to automatically fetch newsletters from a specific label. Your newsletters will be imported and can be summarized with AI.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("Sign in with Google", systemImage: "person.badge.key")
                Label("Select a label to monitor", systemImage: "tag")
                Label("Configure polling interval", systemImage: "clock")
                Label("Automatic background fetching", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Authenticate Step

    private var authenticateStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if gmailConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("Connected!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Signed in as \(gmailEmail)")
                    .foregroundStyle(.secondary)
            } else if isAuthenticating {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 10)

                Text("Waiting for authentication...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Complete the sign-in in your browser, then return here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button("Cancel") {
                    pollingTimer?.invalidate()
                    isAuthenticating = false
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "envelope.badge.person.crop")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Connect Your Gmail")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Click the button below to sign in with your Google account. You'll be redirected to Google's login page.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let error = authError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Button(action: startAuthentication) {
                    Label("Sign in with Google", systemImage: "g.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    private func startAuthentication() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                let authResponse = try await appState.apiClient.getGmailAuthURL()

                // Open auth URL in browser
                if let url = URL(string: authResponse.authUrl) {
                    NSWorkspace.shared.open(url)
                }

                // Start polling for completion
                startPollingForAuth()

            } catch {
                await MainActor.run {
                    authError = error.localizedDescription
                    isAuthenticating = false
                }
            }
        }
    }

    private func startPollingForAuth() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await checkAuthStatus()
            }
        }
    }

    private func checkAuthStatus() async {
        do {
            let status = try await appState.apiClient.getGmailStatus()

            await MainActor.run {
                if status.connected {
                    gmailConnected = true
                    gmailEmail = status.email ?? ""
                    selectedLabel = status.monitoredLabel ?? "Newsletters"
                    pollInterval = status.pollIntervalMinutes
                    isAuthenticating = false
                    pollingTimer?.invalidate()
                }
            }
        } catch {
            // Keep polling
        }
    }

    // MARK: - Select Label Step

    private var selectLabelStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tag.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Select Gmail Label")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose which Gmail label to monitor for newsletters. Create a label in Gmail and filter your newsletters to it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if isLoadingLabels {
                ProgressView("Loading labels...")
            } else if !availableLabels.isEmpty {
                Picker("Label", selection: $selectedLabel) {
                    ForEach(availableLabels, id: \.self) { label in
                        Text(label).tag(label)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
            } else {
                TextField("Label name", text: $selectedLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)

                Button("Load Labels") {
                    loadLabels()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tip: Create a label like \"Newsletters\" in Gmail,")
                Text("then use filters to automatically label incoming newsletters.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            if availableLabels.isEmpty {
                loadLabels()
            }
        }
    }

    private func loadLabels() {
        isLoadingLabels = true

        Task {
            do {
                let response = try await appState.apiClient.getGmailLabels()

                await MainActor.run {
                    availableLabels = response.labels
                    // Pre-select "Newsletters" if available
                    if availableLabels.contains("Newsletters") {
                        selectedLabel = "Newsletters"
                    } else if !availableLabels.isEmpty && !availableLabels.contains(selectedLabel) {
                        selectedLabel = availableLabels.first ?? ""
                    }
                    isLoadingLabels = false
                }
            } catch {
                await MainActor.run {
                    isLoadingLabels = false
                }
            }
        }
    }

    // MARK: - Configure Step

    private var configureStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gearshape.fill")
                .font(.system(size: 50))
                .foregroundStyle(.gray)

            Text("Polling Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Configure how often to check for new newsletters.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Check every:")
                    Picker("", selection: $pollInterval) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                Text("More frequent polling uses more resources but catches newsletters faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
    }

    // MARK: - Test Step

    private var testStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if isTesting {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 10)

                Text("Fetching newsletters...")
                    .font(.title2)
                    .fontWeight(.semibold)
            } else if testSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("Success!")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let result = testResult {
                    Text(result)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Test Connection")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Click the button below to fetch newsletters from your Gmail account and verify everything is working.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let result = testResult {
                    Label(result, systemImage: "info.circle")
                        .foregroundStyle(testSuccess ? .green : .orange)
                        .font(.callout)
                }

                Button(action: runTest) {
                    Label("Fetch Newsletters Now", systemImage: "arrow.down.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil

        Task {
            do {
                // Save config first
                _ = try await appState.apiClient.updateGmailConfig(
                    label: selectedLabel,
                    interval: pollInterval,
                    enabled: true
                )

                // Fetch newsletters
                let response = try await appState.apiClient.triggerGmailFetch()

                await MainActor.run {
                    isTesting = false
                    testSuccess = response.success

                    if response.imported > 0 {
                        testResult = "Imported \(response.imported) newsletter(s)!"
                    } else if response.success {
                        testResult = response.message ?? "Connection successful. No new newsletters found."
                    } else {
                        testResult = response.message ?? "Fetch failed."
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testSuccess = false
                    testResult = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Gmail integration is configured. Newsletters from \"\(selectedLabel)\" will be automatically imported every \(pollInterval) minutes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Label("Newsletters appear in the Newsletters section", systemImage: "envelope.open")
                Label("Use the Fetch button for immediate updates", systemImage: "arrow.clockwise")
                Label("Adjust settings anytime in Preferences", systemImage: "gear")
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

            Spacer()

            if currentStep == .complete {
                Button("Done") {
                    completeSetup()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .authenticate {
                Button("Continue") {
                    withAnimation {
                        goNext()
                    }
                }
                .disabled(!gmailConnected)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .test {
                Button("Continue") {
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
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Navigation Logic

    private func goNext() {
        let steps = SetupStep.allCases
        if let currentIndex = steps.firstIndex(of: currentStep),
           currentIndex < steps.count - 1 {
            currentStep = steps[currentIndex + 1]
        }
    }

    private func goBack() {
        let steps = SetupStep.allCases
        if let currentIndex = steps.firstIndex(of: currentStep),
           currentIndex > 0 {
            currentStep = steps[currentIndex - 1]
        }
    }

    private func completeSetup() {
        // Save final config
        Task {
            _ = try? await appState.apiClient.updateGmailConfig(
                label: selectedLabel,
                interval: pollInterval,
                enabled: true
            )
        }

        onComplete()
        dismiss()
    }
}

#Preview {
    GmailSetupWizardView {
        print("Setup complete!")
    }
    .environmentObject(AppState())
}
