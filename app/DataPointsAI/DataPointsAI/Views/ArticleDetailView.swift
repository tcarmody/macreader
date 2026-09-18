import SwiftUI

struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scrollState: ArticleScrollState

    var body: some View {
        Group {
            if let article = appState.selectedArticleDetail {
                ReaderDetailView(
                    item: ReaderItem(article: article, source: appState.feeds.first { $0.id == article.feedId }?.name ?? article.originalUrl.host ?? "Article"),
                    scrollState: scrollState
                )
                .id("feed-\(article.id)")
            } else if appState.selectedArticle != nil {
                ProgressView("Loading article…")
            } else {
                ContentUnavailableView(
                    appState.selectedArticleIds.count > 1 ? "\(appState.selectedArticleIds.count) Articles Selected" : "Select an Article",
                    systemImage: "doc.text",
                    description: Text("Choose an article to read, summarize, or discuss.")
                )
            }
        }
    }
}
