import SwiftUI

/// Article row with inline summary preview and multi-select support
struct ArticleRow: View {
    let article: Article
    var isMultiSelected: Bool = false
    @EnvironmentObject var appState: AppState

    /// Whether this article is the current keyboard navigation target
    private var isKeyboardFocused: Bool {
        appState.selectedArticle?.id == article.id
    }

    /// Current list density setting
    private var listDensity: ListDensity {
        appState.settings.listDensity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: listDensity == .compact ? 2 : 4) {
            // Title row with unread indicator
            HStack(alignment: .top, spacing: 8) {
                // Selection/Unread indicator
                ZStack {
                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 14))
                    } else if !article.isRead {
                        // Unread indicator - simple blue dot
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    } else {
                        // Read - empty space (no indicator)
                        Color.clear
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, listDensity == .compact ? 2 : 4)

                VStack(alignment: .leading, spacing: listDensity == .compact ? 2 : 4) {
                    // Title - bold for unread, semibold for read
                    Text(article.displayTitle)
                        .font(.headline)
                        .fontWeight(article.isRead ? .semibold : .bold)
                        .lineLimit(listDensity == .compact ? 1 : 2)
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

                    // Summary preview (hidden in compact mode)
                    if listDensity.showSummaryPreview, let preview = article.summaryPreview {
                        Text(preview.smartQuotes)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(listDensity == .spacious ? 3 : 2)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, listDensity.verticalPadding)
        .padding(.horizontal, isMultiSelected || isKeyboardFocused ? 4 : 0)
        .background(
            isMultiSelected ? Color.accentColor.opacity(0.1) :
            isKeyboardFocused ? Color.accentColor.opacity(0.05) : Color.clear
        )
        .overlay(
            // Keyboard focus indicator
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(isKeyboardFocused && !isMultiSelected ? 0.5 : 0), lineWidth: 1)
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .contextMenu {
            articleContextMenu
        }
    }

    @ViewBuilder
    private var articleContextMenu: some View {
        let hasSelection = !appState.selectedArticleIds.isEmpty
        let isInSelection = appState.selectedArticleIds.contains(article.id)
        let effectiveIds = hasSelection && isInSelection ? Array(appState.selectedArticleIds) : [article.id]
        let count = effectiveIds.count

        // Open in browser - only for single article
        if count == 1 {
            Button {
                NSWorkspace.shared.open(article.url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }

            Divider()
        }

        // Mark as read/unread
        Button {
            Task {
                if count == 1 {
                    try? await appState.markRead(articleId: article.id, isRead: !article.isRead)
                } else {
                    // For bulk, mark all as read
                    try? await appState.bulkMarkRead(articleIds: effectiveIds, isRead: true)
                    appState.selectedArticleIds.removeAll()
                }
            }
        } label: {
            if count == 1 {
                Label(
                    article.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                )
            } else {
                Label("Mark \(count) as Read", systemImage: "envelope.open")
            }
        }

        if count > 1 {
            Button {
                Task {
                    try? await appState.bulkMarkRead(articleIds: effectiveIds, isRead: false)
                    appState.selectedArticleIds.removeAll()
                }
            } label: {
                Label("Mark \(count) as Unread", systemImage: "envelope.badge")
            }
        }

        // Bookmark - only for single article
        if count == 1 {
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
        }

        Divider()

        // Copy/Share - only for single article
        if count == 1 {
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

        // Mark Above/Below as Read
        Divider()

        Button {
            markArticlesAboveAsRead()
        } label: {
            Label("Mark Above as Read", systemImage: "arrow.up.to.line")
        }

        Button {
            markArticlesBelowAsRead()
        } label: {
            Label("Mark Below as Read", systemImage: "arrow.down.to.line")
        }

        // Selection management
        if hasSelection {
            Divider()

            Button {
                appState.selectedArticleIds.removeAll()
            } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
        }

        if !isInSelection {
            Button {
                appState.selectedArticleIds.insert(article.id)
            } label: {
                Label("Add to Selection", systemImage: "plus.circle")
            }
        }
    }

    private func markArticlesAboveAsRead() {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard let currentIndex = allArticles.firstIndex(where: { $0.id == article.id }) else { return }

        let articlesToMark = allArticles[..<currentIndex].filter { !$0.isRead }
        guard !articlesToMark.isEmpty else { return }

        Task {
            try? await appState.bulkMarkRead(articleIds: articlesToMark.map { $0.id }, isRead: true)
        }
    }

    private func markArticlesBelowAsRead() {
        let allArticles = appState.groupedArticles.flatMap { $0.articles }
        guard let currentIndex = allArticles.firstIndex(where: { $0.id == article.id }) else { return }

        let startIndex = allArticles.index(after: currentIndex)
        guard startIndex < allArticles.endIndex else { return }

        let articlesToMark = allArticles[startIndex...].filter { !$0.isRead }
        guard !articlesToMark.isEmpty else { return }

        Task {
            try? await appState.bulkMarkRead(articleIds: articlesToMark.map { $0.id }, isRead: true)
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
        sourceUrl: nil,
        title: "OpenAI Announces GPT-5 with Revolutionary Capabilities",
        summaryShort: "OpenAI has unveiled GPT-5, the latest iteration of its large language model with significant improvements in reasoning and multimodal capabilities.",
        isRead: false,
        isBookmarked: true,
        publishedAt: Date().addingTimeInterval(-7200),
        createdAt: Date(),
        readingTimeMinutes: 5,
        author: "John Doe"
    )

    ArticleRow(article: article)
        .environmentObject(AppState())
        .padding()
        .frame(width: 350)
}
