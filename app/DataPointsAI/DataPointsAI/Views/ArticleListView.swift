import SwiftUI

/// Middle pane: article list with multi-select support
struct ArticleListView: View {
    @EnvironmentObject var appState: AppState
    @State private var listSelection: Set<Article.ID> = []

    var body: some View {
        Group {
            if appState.isLoading && appState.articles.isEmpty {
                ProgressView("Loading articles...")
            } else if appState.isClusteringLoading {
                ProgressView("Clustering by topic...")
            } else if appState.groupedArticles.isEmpty {
                EmptyArticlesView()
            } else {
                articleList
            }
        }
        .navigationTitle(appState.currentFilterName)
        .onChange(of: listSelection) { oldSelection, newSelection in
            handleSelectionChange(from: oldSelection, to: newSelection)
        }
        .refreshable {
            try? await appState.refreshFeeds()
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("Group By", selection: Binding(
                    get: { appState.groupByMode },
                    set: { newMode in
                        Task {
                            await appState.setGroupByMode(newMode)
                        }
                    }
                )) {
                    ForEach(GroupByMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Group articles by \(appState.groupByMode.label)")
            }

            ToolbarItemGroup {
                if !appState.selectedArticleIds.isEmpty {
                    selectionToolbar
                }

                Menu {
                    Button {
                        Task {
                            try? await markCurrentFilterRead()
                        }
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }

                    Divider()

                    if !appState.selectedArticleIds.isEmpty {
                        Button {
                            appState.selectedArticleIds.removeAll()
                            listSelection.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                    }

                    Button {
                        selectAllVisible()
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle.fill")
                    }
                    .keyboardShortcut("a", modifiers: [.command])
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More Actions")
            }
        }
    }

    private var articleList: some View {
        List(selection: $listSelection) {
            ForEach(appState.groupedArticles) { group in
                Section(group.title) {
                    ForEach(group.articles) { article in
                        ArticleRow(
                            article: article,
                            isMultiSelected: appState.selectedArticleIds.contains(article.id)
                        )
                        .tag(article.id)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func handleSelectionChange(from oldSelection: Set<Article.ID>, to newSelection: Set<Article.ID>) {
        // Sync list selection to app state
        appState.selectedArticleIds = newSelection

        // If exactly one item is selected, load its detail
        if newSelection.count == 1, let selectedId = newSelection.first {
            let allArticles = appState.groupedArticles.flatMap { $0.articles }
            if let article = allArticles.first(where: { $0.id == selectedId }) {
                appState.selectedArticle = article
                Task {
                    await appState.loadArticleDetail(for: article)
                }
            }
        } else if newSelection.isEmpty {
            appState.selectedArticle = nil
        }
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        let count = appState.selectedArticleIds.count

        Button {
            Task {
                try? await appState.bulkMarkRead(articleIds: Array(appState.selectedArticleIds), isRead: true)
                appState.selectedArticleIds.removeAll()
            }
        } label: {
            Image(systemName: "envelope.open")
        }
        .help("Mark \(count) as Read")

        Button {
            Task {
                try? await appState.bulkMarkRead(articleIds: Array(appState.selectedArticleIds), isRead: false)
                appState.selectedArticleIds.removeAll()
            }
        } label: {
            Image(systemName: "envelope.badge")
        }
        .help("Mark \(count) as Unread")

        Button {
            appState.selectedArticleIds.removeAll()
        } label: {
            Image(systemName: "xmark.circle")
        }
        .help("Clear Selection (\(count))")
    }

    private func selectAllVisible() {
        let allIds = appState.groupedArticles.flatMap { $0.articles }.map { $0.id }
        listSelection = Set(allIds)
        appState.selectedArticleIds = Set(allIds)
    }

    private func markCurrentFilterRead() async throws {
        switch appState.selectedFilter {
        case .all:
            try await appState.markAllRead()
        case .unread:
            try await appState.markAllRead()
        case .bookmarked:
            // Don't mark bookmarked as read automatically
            let ids = appState.filteredArticles.map { $0.id }
            try await appState.bulkMarkRead(articleIds: ids)
        case .feed(let feedId):
            try await appState.markFeedRead(feedId: feedId)
        }
    }
}

/// Empty state when no articles
struct EmptyArticlesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptyIcon)
        } description: {
            Text(emptyDescription)
        } actions: {
            if appState.feeds.isEmpty {
                Button("Add Feed") {
                    DispatchQueue.main.async {
                        appState.showAddFeed = true
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Refresh") {
                    Task {
                        try? await appState.refreshFeeds()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var emptyTitle: String {
        switch appState.selectedFilter {
        case .all:
            return appState.feeds.isEmpty ? "No Feeds" : "No Articles"
        case .unread:
            return "All Caught Up"
        case .bookmarked:
            return "No Saved Articles"
        case .feed:
            return "No Articles"
        }
    }

    private var emptyIcon: String {
        switch appState.selectedFilter {
        case .all:
            return appState.feeds.isEmpty ? "newspaper" : "doc.text"
        case .unread:
            return "checkmark.circle"
        case .bookmarked:
            return "star"
        case .feed:
            return "doc.text"
        }
    }

    private var emptyDescription: String {
        switch appState.selectedFilter {
        case .all:
            return appState.feeds.isEmpty
                ? "Add some feeds to get started."
                : "No articles found."
        case .unread:
            return "You've read all your articles."
        case .bookmarked:
            return "Bookmark articles to save them for later."
        case .feed:
            return "This feed has no articles yet."
        }
    }
}

#Preview {
    ArticleListView()
        .environmentObject(AppState())
        .frame(width: 350)
}
