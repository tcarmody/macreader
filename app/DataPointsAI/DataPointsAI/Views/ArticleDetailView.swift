import SwiftUI

/// Right pane: full article detail with summary
struct ArticleDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSummarizing: Bool = false

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
                        } else if article.summaryShort != nil {
                            // Has short summary but not full - offer to generate
                            VStack(alignment: .leading, spacing: 8) {
                                Text(article.summaryShort!)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // No summary yet
                            VStack(spacing: 12) {
                                if isSummarizing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating summary...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No summary available")
                                        .foregroundStyle(.secondary)

                                    Button("Generate Summary") {
                                        Task {
                                            isSummarizing = true
                                            try? await appState.summarizeArticle(articleId: article.id)
                                            isSummarizing = false
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
                                NSWorkspace.shared.open(article.url)
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
                            ShareLink(item: article.url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }

                        // Original content preview (collapsed by default)
                        if let content = article.content, !content.isEmpty {
                            DisclosureGroup("Original Content") {
                                Text(content)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.top, 8)
                            }
                            .padding(.top, 8)
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
}

#Preview {
    ArticleDetailView()
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}
