import SwiftUI
import UniformTypeIdentifiers

/// View for adding URLs or files to the library
struct AddToLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AddTab = .url
    @State private var urlString: String = ""
    @State private var titleOverride: String = ""
    @State private var autoSummarize: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var showFilePicker: Bool = false

    enum AddTab: String, CaseIterable {
        case url = "URL"
        case file = "File"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Add to Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Save a webpage or document for later reading and summarization.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            // Tab picker
            Picker("Add Type", selection: $selectedTab) {
                ForEach(AddTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Content based on selected tab
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                switch selectedTab {
                case .url:
                    urlInputView
                case .file:
                    fileInputView
                }
            }

            Spacer()

            // Bottom buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isLoading ? "Adding..." : "Add to Library") {
                    addToLibrary()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd || isLoading)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 30)
        .frame(width: 450, height: 400)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Computed Properties

    private var canAdd: Bool {
        switch selectedTab {
        case .url:
            return !urlString.isEmpty && isValidURL(urlString)
        case .file:
            return selectedFileURL != nil
        }
    }

    private var supportedFileTypes: [UTType] {
        [
            .pdf,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "doc") ?? .data,
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            .html
        ]
    }

    // MARK: - Subviews

    private var urlInputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.headline)

                TextField("https://example.com/article", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if canAdd {
                            addToLibrary()
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title (optional)")
                    .font(.headline)

                TextField("Leave empty to use page title", text: $titleOverride)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Summarize automatically", isOn: $autoSummarize)
                .font(.callout)

            // Paste from clipboard hint
            if let clipboardURL = getClipboardURL() {
                Button {
                    urlString = clipboardURL
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from clipboard: \(clipboardURL.prefix(40))...")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var fileInputView: some View {
        VStack(spacing: 16) {
            if let fileName = selectedFileName {
                // Show selected file
                VStack(spacing: 12) {
                    Image(systemName: iconForFile(fileName))
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text(fileName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Button("Choose Different File") {
                        showFilePicker = true
                    }
                    .buttonStyle(.link)
                }
            } else {
                // Show file picker button
                Button {
                    showFilePicker = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 32))

                        Text("Select File...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text("Supported: PDF, Word, Text, Markdown, HTML")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title (optional)")
                        .font(.headline)

                    TextField("Leave empty to use filename", text: $titleOverride)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Summarize automatically", isOn: $autoSummarize)
                    .font(.callout)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)

            Text(selectedTab == .url ? "Fetching URL..." : "Uploading file...")
                .font(.headline)

            Text("This may take a moment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Error")
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                errorMessage = nil
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    private func getClipboardURL() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string) else { return nil }
        return isValidURL(string) ? string : nil
    }

    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "txt": return "doc.plaintext"
        case "md", "markdown": return "text.quote"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            selectedFileName = url.lastPathComponent

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func addToLibrary() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let title = titleOverride.isEmpty ? nil : titleOverride

                switch selectedTab {
                case .url:
                    try await appState.addURLToLibrary(
                        url: urlString,
                        title: title,
                        autoSummarize: autoSummarize
                    )

                case .file:
                    guard let fileURL = selectedFileURL else { return }

                    // Access security-scoped resource
                    guard fileURL.startAccessingSecurityScopedResource() else {
                        throw NSError(domain: "ImportError", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Unable to access the selected file."
                        ])
                    }
                    defer { fileURL.stopAccessingSecurityScopedResource() }

                    let data = try Data(contentsOf: fileURL)
                    try await appState.uploadFileToLibrary(
                        data: data,
                        filename: fileURL.lastPathComponent,
                        title: title,
                        autoSummarize: autoSummarize
                    )
                }

                // Success - dismiss the sheet
                dismiss()

            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }
}

#Preview {
    AddToLibraryView()
        .environmentObject(AppState())
}
