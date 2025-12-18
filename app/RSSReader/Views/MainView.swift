import SwiftUI

/// Main three-pane layout
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FeedListView()
        } content: {
            ArticleListView()
        } detail: {
            ArticleDetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $appState.searchQuery, prompt: "Search articles")
        .onChange(of: appState.searchQuery) { _, newValue in
            Task {
                await appState.search(query: newValue)
            }
        }
        .sheet(isPresented: $appState.showAddFeed) {
            AddFeedView()
        }
        .alert("Error", isPresented: .constant(appState.error != nil)) {
            Button("OK") {
                appState.error = nil
            }
        } message: {
            if let error = appState.error {
                Text(error)
            }
        }
        .overlay {
            if !appState.serverRunning {
                ServerStatusView()
            }
        }
    }
}

/// Server connection status overlay
struct ServerStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            if let error = appState.serverError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("Server Error")
                    .font(.headline)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task {
                        await appState.startServer()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Starting server...")
                    .font(.headline)
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}

/// Sheet for adding a new feed
struct AddFeedView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var feedURL: String = ""
    @State private var feedName: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Feed")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Feed URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/feed.xml", text: $feedURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("My Feed", text: $feedName)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addFeed()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(feedURL.isEmpty || isLoading)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func addFeed() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await appState.addFeed(
                    url: feedURL,
                    name: feedName.isEmpty ? nil : feedName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
