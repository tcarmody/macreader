import SwiftUI

/// Article row with inline summary preview
struct ArticleRow: View {
    let article: Article
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with unread indicator
            HStack(alignment: .top, spacing: 8) {
                // Unread indicator
                Circle()
                    .fill(article.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(article.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(article.isRead ? .secondary : .primary)

                    // Source and time
                    HStack(spacing: 4) {
                        if let feedName = feedName(for: article.feedId) {
                            Text(feedName)
                                .lineLimit(1)
                        }
                        Text("·")
                        Text(article.timeAgo)

                        if article.isBookmarked {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Summary preview
                    if let preview = article.summaryPreview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                NSWorkspace.shared.open(article.url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }

            Divider()

            Button {
                Task {
                    try? await appState.markRead(articleId: article.id, isRead: !article.isRead)
                }
            } label: {
                Label(
                    article.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                )
            }

            Button {
                Task {
                    try? await appState.toggleBookmark(articleId: article.id)
                }
            } label: {
                Label(
                    article.isBookmarked ? "Remove Bookmark" : "Bookmark",
                    systemImage: article.isBookmarked ? "star.slash" : "star"
                )
            }

            Divider()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(article.url.absoluteString, forType: .string)
            } label: {
                Label("Copy Link", systemImage: "link")
            }

            ShareLink(item: article.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func feedName(for feedId: Int) -> String? {
        appState.feeds.first { $0.id == feedId }?.name
    }
}

#Preview {
    let article = Article(
        id: 1,
        feedId: 1,
        url: URL(string: "https://example.com")!,
        title: "OpenAI Announces GPT-5 with Revolutionary Capabilities",
        summaryShort: "OpenAI has unveiled GPT-5, the latest iteration of its large language model with significant improvements in reasoning and multimodal capabilities.",
        isRead: false,
        isBookmarked: true,
        publishedAt: Date().addingTimeInterval(-7200),
        createdAt: Date()
    )

    return ArticleRow(article: article)
        .environmentObject(AppState())
        .padding()
        .frame(width: 350)
}
