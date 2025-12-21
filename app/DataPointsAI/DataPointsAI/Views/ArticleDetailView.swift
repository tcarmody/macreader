import SwiftUI
import WebKit

/// Right pane: full article detail with summary
struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSummarizing: Bool = false
    @State private var isFetchingContent: Bool = false
    @State private var contentHeight: CGFloat = 200
    @State private var summarizationError: String?
    @State private var summarizationElapsed: Int = 0
    @State private var summarizationTimer: Timer?

    var body: some View {
        Group {
            if let article = appState.selectedArticleDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(article.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .textSelection(.enabled)

                            HStack(spacing: 8) {
                                if let feedName = feedName(for: article.feedId) {
                                    Text(feedName)
                                        .foregroundStyle(.secondary)
                                }
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(article.timeAgo)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                // Bookmark indicator
                                if article.isBookmarked {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .font(.subheadline)
                        }

                        Divider()

                        // AI Summary
                        if let summary = article.summaryFull {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("AI Summary", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.blue)

                                Text(summary)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            // No full summary - show generate button
                            VStack(spacing: 12) {
                                if isSummarizing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating summary... \(summarizationElapsed)s")
                                        .foregroundStyle(.secondary)
                                    if summarizationElapsed > 10 {
                                        Text("Complex articles may take up to 60 seconds")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                } else if let error = summarizationError {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button("Retry") {
                                        startSummarization(articleId: article.id)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    if let shortSummary = article.summaryShort {
                                        Text(shortSummary)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No summary available")
                                            .foregroundStyle(.secondary)
                                    }

                                    Button("Generate Summary") {
                                        startSummarization(articleId: article.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Key Points
                        if let keyPoints = article.keyPoints, !keyPoints.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Key Points")
                                    .font(.headline)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(keyPoints, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundStyle(.blue)
                                            Text(point)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        // Actions
                        HStack(spacing: 16) {
                            Button {
                                NSWorkspace.shared.open(article.originalUrl)
                            } label: {
                                Label("Read Original", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task {
                                    try? await appState.toggleBookmark(articleId: article.id)
                                }
                            } label: {
                                Label(
                                    article.isBookmarked ? "Saved" : "Save",
                                    systemImage: article.isBookmarked ? "star.fill" : "star"
                                )
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            // Share button
                            ShareLink(item: article.originalUrl) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }

                        // Original content (rendered HTML)
                        if let content = article.content, !content.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Original Content")
                                        .font(.headline)

                                    Spacer()

                                    // For aggregator articles, offer to fetch full source content
                                    if article.sourceUrl != nil {
                                        if isFetchingContent {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Button("Fetch Source Article") {
                                                Task {
                                                    isFetchingContent = true
                                                    try? await appState.fetchArticleContent(articleId: article.id)
                                                    isFetchingContent = false
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                HTMLContentView(html: content, dynamicHeight: $contentHeight)
                                    .frame(height: contentHeight)
                            }
                            .padding(.top, 8)
                        } else {
                            // No content - offer to fetch it
                            VStack(spacing: 12) {
                                if isFetchingContent {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Fetching content...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Content not available in feed")
                                        .foregroundStyle(.secondary)

                                    Button("Fetch from Website") {
                                        Task {
                                            isFetchingContent = true
                                            try? await appState.fetchArticleContent(articleId: article.id)
                                            isFetchingContent = false
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select an Article",
                    systemImage: "doc.text",
                    description: Text("Choose an article from the list to read its summary.")
                )
            }
        }
        .toolbar {
            if appState.selectedArticleDetail != nil {
                ToolbarItemGroup {
                    Button {
                        if let article = appState.selectedArticle {
                            Task {
                                let newStatus = !(appState.selectedArticleDetail?.isRead ?? false)
                                try? await appState.markRead(articleId: article.id, isRead: newStatus)
                            }
                        }
                    } label: {
                        Image(systemName: appState.selectedArticleDetail?.isRead == true
                              ? "envelope.open" : "envelope.badge")
                    }
                    .help(appState.selectedArticleDetail?.isRead == true
                          ? "Mark as Unread" : "Mark as Read")

                    Button {
                        if let article = appState.selectedArticle {
                            Task {
                                try? await appState.toggleBookmark(articleId: article.id)
                            }
                        }
                    } label: {
                        Image(systemName: appState.selectedArticleDetail?.isBookmarked == true
                              ? "star.fill" : "star")
                    }
                    .help(appState.selectedArticleDetail?.isBookmarked == true
                          ? "Remove Bookmark" : "Bookmark")
                }
            }
        }
    }

    private func feedName(for feedId: Int) -> String? {
        appState.feeds.first { $0.id == feedId }?.name
    }

    private func startSummarization(articleId: Int) {
        summarizationError = nil
        summarizationElapsed = 0
        isSummarizing = true

        // Start elapsed time counter
        summarizationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            summarizationElapsed += 1
        }

        Task {
            do {
                try await appState.summarizeArticle(articleId: articleId)
                // Check if summary was actually generated
                if appState.selectedArticleDetail?.summaryFull == nil {
                    summarizationError = "Summary generation timed out. The server may be busy."
                }
            } catch {
                summarizationError = error.localizedDescription
            }

            summarizationTimer?.invalidate()
            summarizationTimer = nil
            isSummarizing = false
        }
    }
}

#Preview {
    ArticleDetailView()
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}
