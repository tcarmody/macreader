import SwiftUI

/// Middle pane: article list
struct ArticleListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoading && appState.articles.isEmpty {
                ProgressView("Loading articles...")
            } else if appState.groupedArticles.isEmpty {
                EmptyArticlesView()
            } else {
                List(selection: $appState.selectedArticle) {
                    ForEach(appState.groupedArticles) { group in
                        Section(group.title) {
                            ForEach(group.articles) { article in
                                ArticleRow(article: article)
                                    .tag(article)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(appState.currentFilterName)
        .onChange(of: appState.selectedArticle) { _, newArticle in
            if let article = newArticle {
                Task {
                    await appState.loadArticleDetail(for: article)
                }
            }
        }
        .refreshable {
            try? await appState.refreshFeeds()
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
                    appState.showAddFeed = true
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
