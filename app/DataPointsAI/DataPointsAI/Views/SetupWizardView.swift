import SwiftUI

/// Setup wizard for configuring AI provider and API keys on first launch
struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var currentStep: SetupStep = .welcome
    @State private var selectedProvider: LLMProvider = .anthropic
    @State private var apiKey: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String?
    @State private var validationSuccess: Bool = false

    var onComplete: () -> Void

    enum SetupStep {
        case welcome
        case selectProvider
        case enterKey
        case complete
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
                case .selectProvider:
                    selectProviderStep
                case .enterKey:
                    enterKeyStep
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
        .frame(width: 500, height: 420)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(zip([SetupStep.welcome, .selectProvider, .enterKey, .complete].indices,
                              [SetupStep.welcome, .selectProvider, .enterKey, .complete])), id: \.0) { index, step in
                Circle()
                    .fill(stepIndex(step) <= stepIndex(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)

                if index < 3 {
                    Rectangle()
                        .fill(stepIndex(step) < stepIndex(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 2)
                }
            }
        }
    }

    private func stepIndex(_ step: SetupStep) -> Int {
        switch step {
        case .welcome: return 0
        case .selectProvider: return 1
        case .enterKey: return 2
        case .complete: return 3
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Welcome to Data Points AI")
                .font(.title)
                .fontWeight(.bold)

            Text("Data Points AI uses AI to summarize articles and extract key points. To get started, you'll need an API key from an AI provider.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("Anthropic Claude (Recommended)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("OpenAI GPT", systemImage: "circle")
                    .foregroundStyle(.secondary)
                Label("Google Gemini", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            Spacer()
        }
    }

    // MARK: - Select Provider Step

    private var selectProviderStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Choose Your AI Provider")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select which AI service you'd like to use for article summarization.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    ProviderOptionButton(
                        provider: provider,
                        isSelected: selectedProvider == provider
                    ) {
                        selectedProvider = provider
                        // Clear any previous API key when switching providers
                        apiKey = ""
                        validationError = nil
                        validationSuccess = false
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Enter Key Step

    private var enterKeyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Enter Your \(selectedProvider.label) API Key")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your API key is stored securely in the macOS Keychain and never leaves your device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 350)
                    .disabled(isValidating)

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if validationSuccess {
                    Label("API key validated successfully!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Button(action: getAPIKeyURL) {
                Text("Get an API key from \(selectedProvider.label)")
                    .font(.callout)
            }
            .buttonStyle(.link)

            Spacer()
        }
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Data Points AI is now configured to use \(selectedProvider.label) for AI-powered summaries.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Label("Add RSS feeds to get started", systemImage: "plus.circle")
                Label("Click on an article to see its summary", systemImage: "doc.text")
                Label("Change providers anytime in Settings", systemImage: "gear")
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
                Button("Get Started") {
                    completeSetup()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            } else if currentStep == .enterKey {
                Button(action: validateAndContinue) {
                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Validate & Continue")
                    }
                }
                .disabled(apiKey.isEmpty || isValidating)
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
        switch currentStep {
        case .welcome:
            currentStep = .selectProvider
        case .selectProvider:
            currentStep = .enterKey
        case .enterKey:
            currentStep = .complete
        case .complete:
            break
        }
    }

    private func goBack() {
        switch currentStep {
        case .welcome:
            break
        case .selectProvider:
            currentStep = .welcome
        case .enterKey:
            currentStep = .selectProvider
        case .complete:
            currentStep = .enterKey
        }
    }

    private func validateAndContinue() {
        isValidating = true
        validationError = nil
        validationSuccess = false

        Task {
            do {
                // Save to Keychain first
                try KeychainService.shared.save(key: apiKey, for: selectedProvider)

                // Restart the server to pick up the new key
                await appState.restartServer()

                // Give the server time to fully initialize
                try await Task.sleep(nanoseconds: 1_000_000_000)

                // Check if the server reports summarization as enabled
                let status = try await appState.apiClient.healthCheck()

                await MainActor.run {
                    if status.summarizationEnabled {
                        validationSuccess = true
                        // Update settings to use the selected provider
                        var newSettings = appState.settings
                        newSettings.llmProvider = selectedProvider
                        newSettings.defaultModel = selectedProvider.modelOptions.first?.value ?? "haiku"
                        Task {
                            try? await appState.updateSettings(newSettings)
                        }
                        // Move to next step after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation {
                                currentStep = .complete
                            }
                        }
                    } else {
                        validationError = "API key was saved but the server couldn't initialize the provider. Please check your key."
                    }
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    validationError = "Failed to validate: \(error.localizedDescription)"
                    isValidating = false
                }
            }
        }
    }

    private func completeSetup() {
        onComplete()
        dismiss()
    }

    private func getAPIKeyURL() {
        let url: URL
        switch selectedProvider {
        case .anthropic:
            url = URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:
            url = URL(string: "https://platform.openai.com/api-keys")!
        case .google:
            url = URL(string: "https://aistudio.google.com/apikey")!
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Provider Option Button

struct ProviderOptionButton: View {
    let provider: LLMProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.label)
                            .fontWeight(.medium)
                        if provider == .anthropic {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title2)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SetupWizardView {
        print("Setup complete!")
    }
    .environmentObject(AppState())
}
