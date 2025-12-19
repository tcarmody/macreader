import SwiftUI

@main
struct RSSReaderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .onAppear {
                    Task {
                        await appState.startServer()
                    }
                }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Add Feed...") {
                    DispatchQueue.main.async {
                        appState.showAddFeed = true
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Refresh Feeds") {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Show All") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .all
                    }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Unread") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .unread
                    }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Saved") {
                    DispatchQueue.main.async {
                        appState.selectedFilter = .bookmarked
                    }
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                // Grouping options
                Picker("Group By", selection: Binding(
                    get: { appState.groupByMode },
                    set: { newMode in
                        Task {
                            await appState.setGroupByMode(newMode)
                        }
                    }
                )) {
                    ForEach(GroupByMode.allCases, id: \.self) { mode in
                        Text(mode.menuLabel).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            // Edit menu - Selection commands
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Select All Articles") {
                    selectAllArticles()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Clear Selection") {
                    DispatchQueue.main.async {
                        appState.selectedArticleIds.removeAll()
                        appState.selectedFeedIds.removeAll()
                    }
                }
                .keyboardShortcut(.escape)
                .disabled(appState.selectedArticleIds.isEmpty && appState.selectedFeedIds.isEmpty)
            }

            // Article menu
            CommandMenu("Article") {
                Button("Open Original") {
                    if let article = appState.selectedArticle {
                        NSWorkspace.shared.open(article.url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Button("Toggle Bookmark") {
                    if let article = appState.selectedArticle {
                        Task {
                            try? await appState.toggleBookmark(articleId: article.id)
                        }
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(appState.selectedArticle == nil)

                Divider()

                Button("Mark as Read") {
                    markSelectedAsRead(true)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedArticle == nil && appState.selectedArticleIds.isEmpty)

                Button("Mark as Unread") {
                    markSelectedAsRead(false)
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(appState.selectedArticle == nil && appState.selectedArticleIds.isEmpty)

                Divider()

                Button("Mark All as Read") {
                    Task {
                        try? await markCurrentFilterAsRead()
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // Feed menu
            CommandMenu("Feed") {
                Button("Rename Feed...") {
                    if case .feed(let feedId) = appState.selectedFilter,
                       let feed = appState.feeds.first(where: { $0.id == feedId }) {
                        appState.feedBeingEdited = feed
                    }
                }
                .disabled(!isCurrentlyViewingFeed)

                Button("Mark Feed as Read") {
                    if case .feed(let feedId) = appState.selectedFilter {
                        Task {
                            try? await appState.markFeedRead(feedId: feedId)
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!isCurrentlyViewingFeed)

                Divider()

                Button("Delete Feed") {
                    // This will be handled by the confirmation dialog in FeedListView
                    if case .feed(let feedId) = appState.selectedFilter {
                        Task {
                            try? await appState.deleteFeed(feedId: feedId)
                        }
                    }
                }
                .disabled(!isCurrentlyViewingFeed)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }

    private var isCurrentlyViewingFeed: Bool {
        if case .feed = appState.selectedFilter {
            return true
        }
        return false
    }

    private func selectAllArticles() {
        let allIds = appState.groupedArticles.flatMap { $0.articles }.map { $0.id }
        DispatchQueue.main.async {
            appState.selectedArticleIds = Set(allIds)
        }
    }

    private func markSelectedAsRead(_ isRead: Bool) {
        Task {
            if !appState.selectedArticleIds.isEmpty {
                try? await appState.bulkMarkRead(
                    articleIds: Array(appState.selectedArticleIds),
                    isRead: isRead
                )
                await MainActor.run {
                    appState.selectedArticleIds.removeAll()
                }
            } else if let article = appState.selectedArticle {
                try? await appState.markRead(articleId: article.id, isRead: isRead)
            }
        }
    }

    private func markCurrentFilterAsRead() async throws {
        switch appState.selectedFilter {
        case .all, .unread:
            try await appState.markAllRead()
        case .bookmarked:
            let ids = appState.filteredArticles.map { $0.id }
            try await appState.bulkMarkRead(articleIds: ids)
        case .feed(let feedId):
            try await appState.markFeedRead(feedId: feedId)
        }
    }
}
