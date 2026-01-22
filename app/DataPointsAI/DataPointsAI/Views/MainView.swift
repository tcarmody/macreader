import SwiftUI

/// Main three-pane layout
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyboardManager = KeyboardShortcutManager.shared
    @StateObject private var articleScrollState = ArticleScrollState()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FeedListView()
        } content: {
            if appState.showLibrary {
                LibraryView()
            } else {
                // ArticleListView handles both RSS feeds and newsletter feeds
                ArticleListView()
            }
        } detail: {
            if appState.showLibrary {
                // Library items use their own detail view
                LibraryItemDetailView()
            } else {
                // Both RSS feeds and newsletters use ArticleDetailView
                // (newsletters are now stored as regular articles in feeds)
                ArticleDetailView(scrollState: articleScrollState)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $appState.searchQuery, prompt: "Search articles (press / to focus)")
        .focused($isSearchFocused)
        .onChange(of: appState.searchQuery) { _, newValue in
            Task {
                await appState.search(query: newValue)
            }
        }
        .sheet(isPresented: $appState.showAddFeed) {
            AddFeedView()
        }
        .sheet(isPresented: $appState.showImportOPML) {
            ImportOPMLView()
        }
        .sheet(isPresented: $appState.showAddToLibrary) {
            AddToLibraryView()
        }
        .sheet(isPresented: $appState.showQuickOpen) {
            QuickOpenView()
        }
        .alert("Error", isPresented: Binding(
            get: { appState.error != nil },
            set: { if !$0 { appState.error = nil } }
        )) {
            Button("OK") {
                DispatchQueue.main.async {
                    appState.error = nil
                }
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
        .overlay(alignment: .top) {
            // Offline mode banner
            if appState.isOffline {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isOffline)
        .overlay(alignment: .bottom) {
            // Show pending key indicator for multi-key sequences
            if keyboardManager.pendingKey != nil {
                PendingKeyIndicator(pendingKey: keyboardManager.pendingKey)
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onChange(of: appState.selectedFilter) { _, _ in
            appState.saveWindowState()
        }
        .onChange(of: appState.readerModeEnabled) { _, isEnabled in
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = isEnabled ? .detailOnly : .all
            }
        }
    }

    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept if a text field is focused
            if let window = NSApp.keyWindow,
               let firstResponder = window.firstResponder,
               firstResponder is NSTextView {
                // Check if this is the search field
                if event.charactersIgnoringModifiers == "\u{1B}" {
                    // Escape pressed - blur search
                    Task { @MainActor in
                        isSearchFocused = false
                        appState.searchQuery = ""
                    }
                    return nil
                }
                return event
            }

            if let action = keyboardManager.processKeyEvent(event) {
                // Special handling for scroll actions
                if action == .scrollDown {
                    let canScroll = articleScrollState.canScrollDown
                    print("Space pressed - canScrollDown: \(canScroll), hasScrollView: \(articleScrollState.scrollView != nil)")
                    if appState.selectedArticleDetail == nil {
                        // No article selected, navigate to first
                        print("  -> No article selected, going to next")
                        Task { @MainActor in
                            await handleKeyboardAction(.nextArticle)
                        }
                    } else if canScroll {
                        // Scroll down within the article
                        print("  -> Scrolling down (pageDown)")
                        articleScrollState.scrollDown()
                    } else {
                        // At bottom of article, navigate to next
                        print("  -> At bottom, going to next article")
                        Task { @MainActor in
                            await handleKeyboardAction(.nextArticle)
                        }
                    }
                    return nil // Always consume space bar
                }

                if action == .scrollUp {
                    let canScroll = articleScrollState.canScrollUp
                    print("Shift+Space pressed - canScrollUp: \(canScroll)")
                    if appState.selectedArticleDetail != nil && canScroll {
                        // Scroll up within the article
                        print("  -> Scrolling up (pageUp)")
                        articleScrollState.scrollUp()
                    } else {
                        print("  -> At top or no article, not scrolling")
                    }
                    return nil // Consume shift+space
                }

                Task { @MainActor in
                    await handleKeyboardAction(action)
                }
                return nil // Consume the event
            }
            return event
        }
    }

    @MainActor
    private func handleKeyboardAction(_ action: KeyboardAction) async {
        switch action {
        case .nextArticle:
            navigateToArticle(direction: .next)

        case .previousArticle:
            navigateToArticle(direction: .previous)

        case .nextUnread:
            navigateToNextUnread()

        case .openArticle:
            if let article = appState.selectedArticle {
                await appState.loadArticleDetail(for: article)
            }

        case .openInBrowser:
            if let article = appState.selectedArticle {
                NSWorkspace.shared.open(article.originalUrl)
            }

        case .toggleRead:
            if let article = appState.selectedArticle {
                let newStatus = !article.isRead
                try? await appState.markRead(articleId: article.id, isRead: newStatus)
            }

        case .markAsUnread:
            if let article = appState.selectedArticle {
                try? await appState.markRead(articleId: article.id, isRead: false)
            }

        case .toggleBookmark:
            if let article = appState.selectedArticle {
                try? await appState.toggleBookmark(articleId: article.id)
            }

        case .goToTop:
            navigateToFirst()

        case .goToBottom:
            navigateToLast()

        case .focusSearch:
            isSearchFocused = true

        case .markAllRead:
            try? await appState.markAllRead()

        case .refresh:
            try? await appState.refreshFeeds()

        case .escape:
            isSearchFocused = false
            appState.searchQuery = ""
            appState.selectedArticleIds.removeAll()

        case .scrollDown, .scrollUp:
            // Handled in setupKeyboardMonitor for proper event consumption
            break

        case .collapseAllFolders:
            appState.collapseAllCategories()

        case .expandAllFolders:
            appState.expandAllCategories()

        case .toggleReaderMode:
            appState.readerModeEnabled.toggle()
        }
    }

    private enum NavigationDirection {
        case next, previous
    }

    private func navigateToArticle(direction: NavigationDirection) {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard !allArticles.isEmpty else { return }

        let currentId = appState.selectedArticle?.id

        let newIndex: Int
        if let currentId = currentId,
           let currentIndex = allArticles.firstIndex(where: { $0.id == currentId }) {
            switch direction {
            case .next:
                newIndex = min(currentIndex + 1, allArticles.count - 1)
            case .previous:
                newIndex = max(currentIndex - 1, 0)
            }
        } else {
            // No current selection, start at first or last
            newIndex = direction == .next ? 0 : allArticles.count - 1
        }

        let article = allArticles[newIndex]
        appState.selectedArticle = article
        appState.selectedArticleIds = [article.id]

        // Also load the article detail
        Task {
            await appState.loadArticleDetail(for: article)
        }
    }

    private func navigateToFirst() {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard let first = allArticles.first else { return }
        appState.selectedArticle = first
        appState.selectedArticleIds = [first.id]
        Task {
            await appState.loadArticleDetail(for: first)
        }
    }

    private func navigateToLast() {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard let last = allArticles.last else { return }
        appState.selectedArticle = last
        appState.selectedArticleIds = [last.id]
        Task {
            await appState.loadArticleDetail(for: last)
        }
    }

    private func navigateToNextUnread() {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard !allArticles.isEmpty else { return }

        let currentId = appState.selectedArticle?.id
        let currentIndex = currentId.flatMap { id in
            allArticles.firstIndex(where: { $0.id == id })
        }

        // Search for next unread starting after current position
        let startIndex = (currentIndex ?? -1) + 1

        // First, search from current position to end
        if let nextUnread = allArticles[startIndex...].first(where: { !$0.isRead }) {
            selectArticle(nextUnread)
            return
        }

        // If not found, wrap around and search from beginning
        if startIndex > 0, let nextUnread = allArticles[..<startIndex].first(where: { !$0.isRead }) {
            selectArticle(nextUnread)
            return
        }

        // No unread articles found - could show feedback here if desired
    }

    private func selectArticle(_ article: Article) {
        appState.selectedArticle = article
        appState.selectedArticleIds = [article.id]
        Task {
            await appState.loadArticleDetail(for: article)
        }
    }
}

/// Visual indicator for pending multi-key sequences
struct PendingKeyIndicator: View {
    let pendingKey: Character?

    var body: some View {
        if let key = pendingKey {
            HStack(spacing: 4) {
                Text("Waiting for next key:")
                    .foregroundStyle(.secondary)
                Text(String(key))
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: key)
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

/// Offline mode banner shown at top of window
struct OfflineBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)

            Text("You're offline. Reading cached articles.")
                .font(.caption)

            Spacer()

            if let connectionType = appState.networkMonitor.connectionType.rawValue as String?,
               connectionType != "Unknown" {
                Text("Last: \(connectionType)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.9))
        .foregroundStyle(.white)
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
