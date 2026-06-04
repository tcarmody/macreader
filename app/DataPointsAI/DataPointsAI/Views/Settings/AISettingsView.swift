import SwiftUI

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
    @State private var showBackendKeySheet = false
    @State private var backendKeyInput = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Server")
                    Spacer()
                    Text(APIClient.defaultBaseURL.host ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("API Key")
                    Spacer()
                    if KeychainService.shared.hasBackendAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Change") {
                            backendKeyInput = ""
                            saveError = nil
                            showBackendKeySheet = true
                        }
                        .buttonStyle(.link)
                        Button("Remove") {
                            removeBackendKey()
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(.red)
                    } else {
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                        Button("Add") {
                            backendKeyInput = ""
                            saveError = nil
                            showBackendKeySheet = true
                        }
                        .buttonStyle(.link)
                    }
                }
                Text("This app connects to the shared hosted backend. Featuring a story here makes it visible to everyone with an account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backend Connection")
            }

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
        .sheet(isPresented: $showBackendKeySheet) {
            backendKeySheet
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

    private var backendKeySheet: some View {
        VStack(spacing: 20) {
            Text("Backend API Key")
                .font(.headline)

            Text("Paste the AUTH_API_KEY configured on the server.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("API Key", text: $backendKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            if let error = saveError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    showBackendKeySheet = false
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    saveBackendKey()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(backendKeyInput.isEmpty || isSaving)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    private func saveBackendKey() {
        saveError = nil
        do {
            // Save + recreate the client synchronously, then close immediately.
            try appState.updateBackendAPIKey(backendKeyInput)
        } catch {
            saveError = error.localizedDescription
            return
        }
        showBackendKeySheet = false
        // Reconnect + refresh in the background so the sheet never blocks on a
        // potentially long feed refresh.
        Task { await appState.startServer() }
    }

    private func removeBackendKey() {
        Task {
            try? KeychainService.shared.deleteBackendAPIKey()
            await appState.restartServer()
        }
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

