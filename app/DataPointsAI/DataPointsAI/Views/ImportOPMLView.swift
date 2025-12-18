import SwiftUI
import UniformTypeIdentifiers

/// View for importing feeds from OPML files
struct ImportOPMLView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var importResult: APIClient.OPMLImportResponse?
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Import OPML")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Import feeds from an OPML file exported from another RSS reader.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            Spacer()

            // Content area - shows different states
            if isImporting {
                importingView
            } else if let result = importResult {
                resultView(result)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                selectFileView
            }

            Spacer()

            // Bottom buttons
            HStack {
                if importResult != nil {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    if errorMessage != nil {
                        Button("Try Again") {
                            errorMessage = nil
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 30)
        .frame(width: 400, height: 350)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Subviews

    private var selectFileView: some View {
        VStack(spacing: 16) {
            Button {
                showFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Select OPML File...")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Supported formats: .opml, .xml")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var importingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Importing feeds...")
                .font(.headline)

            Text("This may take a moment as each feed is validated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultView(_ result: APIClient.OPMLImportResponse) -> some View {
        VStack(spacing: 16) {
            // Summary
            HStack(spacing: 20) {
                resultStat(value: result.imported, label: "Imported", color: .green)
                resultStat(value: result.skipped, label: "Skipped", color: .orange)
                resultStat(value: result.failed, label: "Failed", color: .red)
            }

            Divider()

            // Details list (scrollable if many results)
            if !result.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.results, id: \.url) { item in
                            HStack {
                                Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(item.success ? .green : (item.error == "Already subscribed" ? .orange : .red))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? item.url)
                                        .font(.callout)
                                        .lineLimit(1)

                                    if let error = item.error {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private func resultStat(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(value > 0 ? color : .secondary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Import Failed")
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFromFile(url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFromFile(_ url: URL) {
        isImporting = true
        errorMessage = nil

        Task {
            do {
                // Need to start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "ImportError", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Unable to access the selected file."
                    ])
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let result = try await appState.importOPML(from: url)
                importResult = result

            } catch {
                errorMessage = error.localizedDescription
            }

            isImporting = false
        }
    }
}

#Preview {
    ImportOPMLView()
        .environmentObject(AppState())
}
